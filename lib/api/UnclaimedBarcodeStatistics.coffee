require("./helpers").install(global)
Api = require("./Api")
tp = require "../transactions" #transaction processor

exports = module.exports = class UnclaimedBarcodeStatistics extends Api
  @model: UnclaimedBarcodeStatistic

  @add: (data, callback)->
    obj = {
      org: {
        type                : data.org.type
        id                  : data.org.id
      }
      barcodeId             : data.barcodeId
      data                  : data.data || {}
    }

    instance = new @model(obj)
    instance.save(callback)

  @claimBarcodeId: (barcodeId, claimId, callback)->
    if Object.isString(claimId)
      claimId = new ObjectId(claimId)

    @model.collection.update {barcodeId: barcodeId}, {$set: {claimId: claimId}}, {safe:true}, callback
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
    @model.collection.update {barcodeId: oldId}, {$set: $set}, {safe:true, multi: true}, callback
    return

  @getClaimed: (claimId, callback)->
    if Object.isString(claimId) #this is really just the id of the transaction that is claiming this barcode
      claimId = new ObjectId(claimId)

    @model.collection.find {claimId: claimId}, (err, cursor)->
      if error?
        callback(error)
        return
      cursor.toArray (error, unclaimedBarcodeStatistics)->
        callback(error, unclaimedBarcodeStatistics)
      return

  @removeClaimed: (claimId, callback)->
    @model.collection.remove {claimId: claimId}, {safe: true}, callback

  @btTapped: (orgEntity, barcodeId, transactionId, spent, karmaPointsEarned, donationAmount, timestamp, callback)->
    if Object.isString(orgEntity.id)
      orgEntity.id = new ObjectId(orgEntity.id)

    if Object.isString(transactionId)
      transactionId = new ObjectId(transactionId)

    $inc = {}
    $inc["data.tapIns.totalTapIns"] = 1
    $inc["data.tapIns.totalDonated"] = if !isNaN(donationAmount) then parseInt(donationAmount) else 0

    if spent? && !isNaN(spent)
      $inc["data.tapIns.totalAmountPurchased"] = parseInt(spent) #as an integer
    if karmaPointsEarned? && !isNaN(karmaPointsEarned)
      $inc["data.karmaPoints.earned"] = parseInt(karmaPointsEarned)
      $inc["data.karmaPoints.remaining"] = parseInt(karmaPointsEarned)

    $set = {}
    $set["data.tapIns.lastVisited"] = new Date(timestamp) #if it is a string it will become a date hopefully

    $push = {}
    $push["transactions.ids"] = transactionId

    $update = {
      $set: $set
      $inc: $inc
      $push: $push
    }

    # We do this because we don't care about the name or anything else for this business in the statistics collection
    # Hence we strip away any other properties for the purposes of the query
    org = {
      type  : orgEntity.type
      id    : orgEntity.id
    }

    @model.collection.update {org: org, barcodeId: barcodeId, 'transactions.ids': {$ne: transactionId}}, $update, {safe: true, upsert: true }, callback
    return

  ### _getKarmaPoints_ ###
  #
  # Get either of the following:
  #
  # - A list of the karmaPoints for a specific consumer and all the businesses they've interacted with
  # - The karmaPoints for a specific customer-business relation
  #
  # Various argument possibilities
  #
  # - barcodeId, callback
  # - barcodeId, businessId, callback
  #
  # **barcodeId** _String/ObjectId_ the barcode<br />
  # **businessId** _String/ObjectId_ id of the business
  #
  # Various callback possibilities (in order of argument possibilities above)
  #
  # - **callback** _Function_ (error, statistics)
  # - **callback** _Function_ (error, statistic)
  @getKarmaPoints: (barcodeId, businessId, callback)->
    getAll = true #the KarmaPoints for each business

    if Object.isFunction(businessId)
      callback = businessId
      delete businessId
    else
      try
        if Object.isString businessId
          businessId = new ObjectId(businessId)
        getAll = false #the KarmaPoints for a specific business
      catch error
        callback(error)
        return

    $query   = {}
    $options = {}

    $query["barcodeId"] = barcodeId

    if !getAll
      $query["org.type"] = choices.organizations.BUSINESS
      $query["org.id"]   = businessId
      $options["limit"]  = 1

    @model.collection.find $query, {barcodeId: 1, org: 1, "data.karmaPoints": 1}, $options, (error, cursor)->
      if error?
        logger.error(error)
        callback(error)
        return
      cursor.toArray (error, statistics)->
        if !getAll and statistics.length == 1 #if were only wanted karmaPoints for one specific relationship (not all) then don't give back an array
          callback(error, statistics[0])
          return
        callback(error, statistics)

  ### _awardKarmaPoints_ ###
  #
  # Award a consumer KarmaPoints for their interactions with a specific business
  #
  # **barcodeId** _String/ObjectId_ the barcode<br />
  # **businessId** _String/ObjectId_ id of the business<br />
  # **amount** _String/ObjectId_ amount of KarmaPoints<br />
  # **callback** _Function_ (error, count)<br />
  @awardKarmaPoints: (barcodeId, businessId, amount, callback)->
    try
      if Object.isString businessId
        businessId = new ObjectId(businessId)
    catch error
      callback(error)
      return

    #verify amount is valid
    amount = parseInt(amount)
    if amount < 0
      callback({message: "amount needs to be a positive integer"})
      return

    $query = {}
    $query["barcodeId"]  = barcodeId
    $query["org.type"]   = choices.organizations.BUSINESS
    $query["org.id"]     = businessId

    @model.collection.update $query, {$inc: {"data.karmaPoints.earned": amount, "data.karmaPoints.remaining": amount} }, {safe: true, upsert: true}, (error, count)->
      if error?
        logger.error error
      callback(error, count)
      return