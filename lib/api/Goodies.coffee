require("./helpers").install(global)
Api = require("./Api")
tp = require "../transactions" #transaction processor

exports = module.exports = class Goodies extends Api
  @model = Goody

  ### _add_ ###
  # Add goodies for a specific organization
  #
  # **data**
  #
  # - **org** _Object_ the organization to create the goody for
  # - **name** _String_ name of the goody
  # - **description** _[optional] String_ description of the goody
  # - **active** _Boolean_ is this goody redeemable
  # - **karmaPointsRequired** _Number_ how many points are needed to redeem this goody
  #
  # **callback** _Function_ (error, ObjectId)
  @add: (data, callback)->
    try
      if Object.isString data.org.id
        data.org.id = ObjectId(data.org.id)
    catch error
      callback(error)
      return

    #some validation, eventually move all validation out to it's own pre-processing proxy
    if data.karmaPointsRequired % 10 != 0 or data.karmaPointsRequired < 10
      callback(new errors.ValidationError "karmaPointsRequired is invalid", {karmaPointsRequired:"must be divisible by 10"})
      return

    if utils.isBlank(data.name)
      callback new errors.ValidationError("name is required")
      return

    doc = {
      _id                 : new ObjectId()
      org                 : data.org
      name                : data.name
      description         : if data.description? then data.description else undefined
      active              : if data.active? then data.active else true
      karmaPointsRequired : parseInt(data.karmaPointsRequired)
    }

    @model.collection.insert doc, {safe: true}, (err, num)->
      if err?
        logger.error(err)
        callback err
        return
      else if num<1
        error = new Error "Goody was not saved!"
        logger.error(error)
        callback(error)
        return
      callback null, doc._id
    return

  ### _update_ ###
  #
  # Update the goody
  #
  # **data**
  #
  # - **org** _Object_ the organization to create the goody for
  # - **name** _String_ name of the goody
  # - **description** _String (optional)_ description of the goody
  # - **active** _Boolean_ is this goody redeemable
  # - **karmaPointsRequired** _Number_ how many points are required to redeem this goody
  #
  # **callback** _Function_ (error, success)
  @update: (goodyId, data, callback)->
    try
      if Object.isString goodyId
        goodyId = new ObjectId(goodyId)
      if Object.isString data.org.id
        data.org.id = new ObjectId(data.org.id)
    catch error
      callback(error)
      return

    #some validation, eventually move all validation out to it's own pre-processing proxy
    if data.karmaPointsRequired % 10 != 0 or data.karmaPointsRequired<10
      callback(new errors.ValidationError "karmaPointsRequired is invalid", {karmaPointsRequired: "must be a factor of 10"})
      return

    if utils.isBlank(data.name)
      callback new errors.ValidationError("name is required")
      return

    doc = {
      org                 : data.org
      name                : data.name
      description         : if data.description? then data.description else undefined
      active              : if data.active? then data.active else true
      karmaPointsRequired : parseInt(data.karmaPointsRequired)
    }

    $where = {
      _id: goodyId
    }

    @model.collection.update $where, doc, {safe: true}, (err, num)->
      if err?
        logger.error(err)
        callback err
        return
      else if num<1
        error = new Error "Goody was not saved!"
        logger.error(error)
        callback(error)
        return
      callback null, true
    return

  ### _get_ ###
  #
  # Only active goodies can be retrieved
  # if you'd like to confirm that the goody belongs to a specific business pass in the businessId
  #
  # Various argument possibilities
  #
  # - goodyId, callback
  # - goodyId, businessId, callback
  #
  # **goodyId** _String/ObjectId_ id of the goody we want<br />
  # **businessId** _String/ObjectId (optional)_ id of the business which the goody should belong to<br />
  # **callback** _Function_ (error, goody)
  @get: (goodyId, businessId, callback)->
    try
      if Object.isString goodyId
        goodyId = new ObjectId(goodyId)
    catch error
      callback(error)
      return

    if Object.isFunction(businessId)
      callback = businessId
      delete businessId
    else
      try
        if Object.isString businessId
          businessId = new ObjectId(businessId)
      catch error
        callback(error)
        return

    $query = {}

    $query["_id"]        = goodyId
    $query["active"]     = true

    if businessId?
      $query["org.type"] = choices.organizations.BUSINESS
      $query["org.id"] = businessId

    @model.collection.findOne $query, (error, goody)->
      if error?
        logger.error(error)
        callback error
        return
      callback error, goody
      return

  ### _getByBusiness_ ###
  #
  # Get the goodies for a specific business (active goodies)
  #
  # **businessId** _String/ObjectId_ id of the business we want goodies for
  #
  # **options**
  #
  # - **active** _Boolean, default: true_ active goodies vs deactivated goodies
  # - **sort** _Number, default: 1_  sort ascending(1) or descending(-1)
  #
  # **callback** _Function_ (error, goodies)
  @getByBusiness: (businessId, options, callback)->
    defaultOpts = {
      active: true
      sort  : 1 #least points first
    }

    try
      if Object.isString businessId
        businessId = new ObjectId(businessId)
    catch error
      callback(error)
      return

    if Object.isFunction(options)
      callback = options
      options = defaultOpts
    else
      options = {
        active  : if options.active? then options.active else defaultOpts.active
        sort    : options.sort || defaultOpts.sort
      }

    $query = {
      "org.id"  : businessId
      "active"  : options.active
    }

    @model.collection.find $query, {sort: {karmaPointsRequired: 1}}, (error, cursor)->
      if error?
        logger.error(error)
        callback(error)
        return
      cursor.toArray (error, goodies)->
        callback(error, goodies)
    return

  ### _remove_ ###
  #
  # This is really just disabling the goody, we never want to delete information
  #
  # **goodyId** _String/ObjectId_ id of the goody we want to remove <br />
  # **callback** _Function_ (error)
  @remove: (goodyId, callback)->
    try
      if Object.isString goodyId
        goodyId = new ObjectId(goodyId)
    catch error
      callback(error)
      return
    @model.collection.update {_id: goodyId}, {$set: {active: false}}, {safe: true}, (err)->
      if err?
        logger.error(err)
        callback err
        return
      else
        callback(err)
        return

  ### _count_ ###
  #
  # Count the number of goodies given some criteria
  #
  # Various argument possibilities
  #
  # - callback
  # - options, callback
  #
  # **options**
  #
  # - **businessId** String/ObjectId_ id of a business
  # - **active** _Boolean, default: true_ active goodies vs deactivated goodies
  #
  # **callback** _Function_ (error, count)
  @count: (options, callback)->
    $query = {}

    if Object.isFunction(options)
      callback = options
      delete options
    else
      if options.businessId?
        try
          if Object.isString options.businessId
            options.businessId = new ObjectId(options.businessId)
        catch error
          logger.error error
          callback(error)
          return

        $query["org.type"] = choices.organizations.BUSINESS
        $query["org.id"]   = options.businessId

      if options.active?
        $query["active"] = options.active

    @model.collection.count $query, (error, count)->
      if error?
        logger.error error
        callback(error)
        return
      else
        callback(error, count)
        return

  ### _redeem_ ###
  #
  # Redeem a goody at a specific business/location/register
  #
  # **goodyId** _String/ObjectId_ id of the goody we want to remove <br />
  # **consumerId** _String/ObjectId_ id of the consumer<br />
  # **businessId** _String/ObjectId_ id of the business<br />
  # **locationId** _String/ObjectId_ id of the location<br />
  # **registerId** _String/ObjectId_ id of the register<br />
  # **timestamp** _String/ObjectId_ timestamp of when the goody was redeemed<br />
  # **callback** _Function_ (error, success)
  @redeem: (goodyId, consumerId, businessId, locationId, registerId, timestamp, callback)->
    try
      if Object.isString goodyId
        goodyId = new ObjectId(goodyId)
      if Object.isString consumerId
        consumerId = new ObjectId(consumerId)
      if Object.isString businessId
        businessId = new ObjectId(businessId)
      if Object.isString locationId
        locationId = new ObjectId(locationId)
      if Object.isString registerId
        registerId = new ObjectId(registerId)
      timestamp = Date.create(timestamp)
    catch error
      callback(error)
      return

    @get goodyId, businessId, (error, goody)->
      if error?
        logger.error error
        callback(error)
        return

      #Check that the goody exists and is active (get will only return active by default - but incase it changes I check this in here)
      #if they are not then error out
      if !goody? or !goody.active
        error = {message: "sorry that goody doesn't exists or is no longer active"}
        logger.error(error)
        callback error, false
        return

      #get the consumer
      Consumers.one consumerId, {firstName: 1, lastName: 1, screenName: 1}, (error, consumer)->
        if error?
          logger.error
          callback(error)
          return
        if !consumer?
          error = {message: "consumer does not exist"}
          logger.error(error)
          callback(error)
          return

        entity = {
          type       : choices.entities.CONSUMER
          id         : consumerId
          name       : "#{consumer.firstName} #{consumer.lastName}"
          screenName : consumer.screenName
        }

        transactionEntity = entity

        transactionData = {
          goody    : goody
          consumer : entity

          org : {
            type : choices.organizations.BUSINESS
            id   : businessId
          }

          locationId   : locationId
          registerId   : registerId
          dateRedeemed : timestamp
        }

        redemptionLogTransaction = Consumers.createTransaction(
          choices.transactions.states.PENDING
        , choices.transactions.actions.REDEMPTION_LOG_GOODY_REDEEMED
        , transactionData
        , choices.transactions.directions.OUTBOUND
        , transactionEntity)

        $query = {}
        $query["consumerId"]                 = consumerId
        $query["org.type"]                   = choices.organizations.BUSINESS
        $query["org.id"]                     = businessId
        $query["data.karmaPoints.remaining"] = {$gte: goody.karmaPointsRequired}

        $inc     = {}
        $pushAll = {}

        $inc["data.karmaPoints.remaining"] = -1 * goody.karmaPointsRequired
        $inc["data.karmaPoints.used"]      = goody.karmaPointsRequired

        $pushAll = {
          "transactions.ids": [redemptionLogTransaction.id]
          "transactions.log": [redemptionLogTransaction]
        }

        $update = {$inc: $inc, $pushAll: $pushAll}

        fields = {_id: 1}

        Statistics.model.collection.findAndModify $query, [], $update, {safe: true, new: true, fields: fields}, (error, statistic)->
          if error?
            logger.error error
            callback(error, false)
            return
          if !statistic?
            callback(error, false)
            return
          callback(error, true)
          tp.process(statistic, redemptionLogTransaction)
          return