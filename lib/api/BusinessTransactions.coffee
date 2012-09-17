require("./helpers").install(global)
Api = require("./Api")
tp = require "../transactions" #transaction processor

exports = module.exports = class BusinessTransactions extends Api
  @model = db.BusinessTransaction

  @add: (data, callback)->
    if Object.isString(data.organizationEntity.id)
      data.organizationEntity.id = new ObjectId(data.organizationEntity.id)
    if Object.isString(data.charity.id)
      data.organizationEntity.id = new ObjectId(data.charity.id)
    if Object.isString(data.locationId)
      data.locationId = new ObjectId(data.locationId)
    if Object.isString(data.registerId)
      data.registerId = new ObjectId(data.registerId)

    if !isNaN(data.timestamp) #if it is a number
      timestamp = Date.create(parseFloat(data.timestamp))
    else #if it is not a number then try and create a date
      timestamp = Date.create(data.timestamp)

    amount = undefined
    if data.amount?
      amount = if !isNaN(parseInt(data.amount)) then Math.abs(parseInt(amount)) else undefined

    doc = {
      # userEntity: null #doesn't always exist

      organizationEntity: {
        type          : data.organizationEntity.type
        id            : data.organizationEntity.id
        name          : data.organizationEntity.name
      }

      charity: {
        type          : choices.entities.CHARITY
        id            : data.charity.id
        name          : data.charity.name
      }

      postToFacebook  : data.postToFacebook

      locationId      : data.locationId
      registerId      : data.registerId
      barcodeId       : if !utils.isBlank(data.barcodeId) then data.barcodeId+"" else undefined #make string
      transactionId   : undefined
      date            : timestamp
      time            : new Date(0,0,0, timestamp.getHours(), timestamp.getMinutes(), timestamp.getSeconds(), timestamp.getMilliseconds()) #this is for slicing by time
      amount          : amount
      receipt         : undefined #we don't collect it yet, otherwise this is binary data
      hasReceipt      : false #we don't collect it yet

      karmaPoints     : 0
      donationType    : defaults.bt.donationType #we should pull this out from the organization later
      donationValue   : defaults.bt.donationValue #we should pull this out from the organization (#this is the amount the business has pledged)
      donationAmount  : defaults.bt.donationAmount #this is the amount totalled after any additions (such as more funds for posting to facebook)
    }

    if data.userEntity?
      doc.userEntity =
        type        : choices.entities.CONSUMER
        id          : data.userEntity.id
        name        : data.userEntity.name
        screenName  : data.userEntity.screenName

    self = this

    accessToken = data.accessToken || null
    async.series {
      findRecentTapIns: (cb)->
        if doc.barcodeId?
          BusinessTransactions.findLastTapInByBarcodeIdAtBusinessSince doc.barcodeId, doc.organizationEntity.id, doc.date.clone().addHours(-3), (error, bt)->
            if error?
              cb(error, null)
              return
            else if bt?
              logger.warn "Ignoring tapIn - occcured within 3 hour time frame at this business"
              cb({name: "IgnoreTapIn", message: "User has tapped in multiple times with in a 3 hour time frame"}) #do not change the name without changing it in the callback below
              return
            else
              cb(null)
        else
          cb(null)

      save: (cb)=> #save it and write to the statistics table
        #award karmaPoints only if the business actually has active goodies, if they don't then they are not giving points to consumers
        Goodies.count {active: true, businessId: data.organizationEntity.id}, (error, count)=>
          if error?
            logger.error error
            cb(error, null)
            return
          if count > 0
            logger.info "goodies exist, so we will be awarding karma points"
            doc.karmaPoints = globals.defaults.tapIns.karmaPointsEarned

            if doc.postToFacebook
              doc.karmaPoints = globals.defaults.tapIns.karmaPointsEarnedFB
              doc.donationAmount += defaults.bt.donationFacebook

          transactionData = {}
          transaction = undefined

          if doc.userEntity?
            logger.silly "BT_TAPPED TRANSACTION CREATED"
            transaction = @createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.BT_TAPPED, transactionData, choices.transactions.directions.OUTBOUND, doc.userEntity)
          else
            transaction = @createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.STAT_BT_TAPPED, transactionData, choices.transactions.directions.OUTBOUND, undefined)

          doc.transactions        = {}
          doc.transactions.locked = false
          doc.transactions.ids    = [transaction.id]
          doc.transactions.log    = [transaction]

          @model.collection.insert doc, {safe: true}, (error, bt)->
            if error?
              logger.error(error)
              cb(error)
              return
            bt = Object.clone(bt[0]) #we are cloning this because it is the same as the doc object (insert must just be appending the _id and returning the same object)

            tp.process(bt, transaction) #process transaction - either add funds to consumer object then update stats or just update unclaimed stats if there is no user to add funds too
            Streams.btTapped bt #we don't care about the callback for this stream function
            cb(null, true) #success
            if doc.userEntity?
              logger.debug accessToken
              logger.debug doc.postToFacebook
              if accessToken? and doc.postToFacebook #post to facebook
                logger.verbose "Posting tapIn to facebook"
                fb.post 'me/feed', accessToken, {message: "I just tapped in at #{doc.organizationEntity.name} and raised #{doc.donationAmount}¢ for #{doc.charity.name}, :)", link: "http://www.goodybag.com/", name: "Goodybag", picture: "http://www.goodybag.com/static/images/gb-logo.png"}, (error, response)->
                  if error?
                    logger.error error
                  else
                    logger.debug response
              return
            return
    }, (error, results)->
      if error?
        if error.name? and error.name is "IgnoreTapIn"
          callback(null, {ignored: true}) #don't report an error back to the device, we are going to ignore the tapIn
          return
        callback(error)
        return
      else if results.save?
        callback(null, {ignored: false})
        return

  @findLastTapInByBarcodeIdAtBusinessSince: (barcodeId, businessId, since, callback)->
    if Object.isString(businessId)
      businessId = new ObjectId(businessId)

    @model.collection.findOne {barcodeId: barcodeId, "organizationEntity.id": businessId, date: {$gte: since}}, {sort:{date: -1}, limit: 1}, callback
    return

  @findOneRecentTapIn: (businessId, locationId, registerId, callback)->
    if Object.isString(businessId)
      businessId = new ObjectId(businessId)
    if Object.isString(locationId)
      locationId = new ObjectId(locationId)
    if Object.isString(registerId)
      registerId = new ObjectId(registerId)

    @model.collection.findOne {"organizationEntity.id": businessId, locationId: locationId, registerId: registerId}, {sort: {date: -1}}, callback
    return

  @associateReceipt: (id, receipt, callback)->
    if Object.isString(id)
      id = new ObjectId(id)
    @model.collection.update {_id: id, hasReceipt: false}, {$set: {receipt: new Binary(receipt), hasReceipt: true}}, {safe: true}, callback
    return

  @claimBarcodeId: (entity, barcodeId, callback)->
    if Object.isString(entity.id)
      entity.id = new ObjectId(entity.id)

    barcodeId = barcodeId + ""
    $set = {
      userEntity: {
        type: choices.entities.CONSUMER
        , id: entity.id
        , name: entity.name
        , screenName: entity.screenName
      }
    }
    @model.collection.update {barcodeId: barcodeId}, {$set: $set}, {multi:true, safe:true}, callback
    return

  @replaceBarcodeId: (oldId, barcodeId, callback)->
    if utils.isBlank(oldId)
      callback new errors.ValidationError("oldId is required fields")
      return
    if utils.isBlank(barcodeId)
      callback new errors.ValidationError("barcodeId is required fields")
      return

    $set = {
      barcodeId: barcodeId
    }
    @model.collection.update {barcodeId: oldId}, {$set: $set}, {multi:true, safe:true}, callback
    return

  @byUser: (userId, options, callback)->
    if Object.isFunction options
      callback = options
      options = {}
    query = @optionParser options
    query.where 'userEntity.id', userId
    query.exec callback

  @byBarcode: (barcodeId, options, callback)->
    if Object.isFunction options
      callback = options
      options = {}
    query = @optionParser options
    query.where 'barcodeId', barcodeId
    query.exec callback

  @byBusiness: (businessId, options, callback)->
    if Object.isFunction options
      callback = options
      options = {}
    query = @optionParser options
    query.fields [
      "_id"
      , "amount"
      , "barcodeId"
      , "date"
      , "donationAmount"
      , "locationId"
      , "organizationEntity"
      , "registerId"
      , "time"
      , "transactionId"
      , "userEntity.screenName"
    ]
    query.where 'organizationEntity.id', businessId
    if options.location?
      query.where 'locationId', options.location
    logger.info options
    query.exec callback

  @byBusinessGbCostumers: (businessId, options, callback)->
    if Object.isFunction options
      callback = options
      options = {}
    if !options.limit?
      options.limit = 25
    if !options.skip?
      options.skip = 0
    query = @optionParser options
    query.where 'organizationEntity.id', businessId
    query.where('userEntity.id').exists true
    if options.location?
      query.where 'locationId', options.location
    query.exec callback

  @test: (callback)->
    data =
      "barcodeId" : "aldkfjs12lsdfl12lskdjf"
      "registerId" : "asdlf3jljsdlfoiuwirljf"
      "locationId" : new ObjectId("4efd61571927c5951200002b")
      "date" : new Date(2011, 11, 30, 12, 22, 22)
      "time" : new Date(0,0,0,12,22,22)
      "amount" : 18.54
      "donationAmount" : 0.03
      "organizationEntity" :
        "id" : new ObjectId("4eda8f766412f8805e6e864c")
        "type" : "client"

      "userEntity" :
        "id" : new ObjectId("4eebdcc12e7501d8d7036cb1")
        "type" : "consumer"
    @model.collection.insert data, {safe: true}, callback

  @setTransactonPending: @__setTransactionPending
  @setTransactionProcessing: @__setTransactionProcessing
  @setTransactionProcessed: @__setTransactionProcessed
  @setTransactionError: @__setTransactionError