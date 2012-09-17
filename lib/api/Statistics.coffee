require("./helpers").install(global)
Api = require("./Api")
tp = require "../transactions" #transaction processor

exports = module.exports = class Statistics extends Api
  @model: Statistic

  ### _getKarmaPoints_ ###
  #
  # Get either of the following:
  #
  # - A list of the karmaPoints for a specific consumer and all the businesses they've interacted with
  # - The karmaPoints for a specific customer-business relation
  #
  # Various argument possibilities
  #
  # - consumerId, callback
  # - consumerId, businessId, callback
  #
  # **consumerId** _String/ObjectId_ id of the consumer<br />
  # **businessId** _String/ObjectId_ id of the business
  #
  # Various callback possibilities (in order of argument possibilities above)
  #
  # - **callback** _Function_ (error, statistics)
  # - **callback** _Function_ (error, statistic)
  @getKarmaPoints: (consumerId, businessId, callback)->
    getAll = true #the KarmaPoints for each business
    try
      if Object.isString consumerId
        consumerId = new ObjectId(consumerId)
    catch error
      callback(error)
      return

    if Object.isFunction(businessId)
      callback = businessId
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

    $query["consumerId"] = consumerId

    if !getAll
      $query["org.type"] = choices.organizations.BUSINESS
      $query["org.id"]   = businessId
      $options["limit"]  = 1

    @model.collection.find $query, {consumerId: 1, org: 1, "data.karmaPoints": 1}, $options, (error, cursor)->
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
  # **consumerId** _String/ObjectId_ id of the consumer<br />
  # **businessId** _String/ObjectId_ id of the business<br />
  # **amount** _String/ObjectId_ amount of KarmaPoints<br />
  # **callback** _Function_ (error, count)<br />
  @awardKarmaPoints: (consumerId, businessId, amount, callback)->
    try
      if Object.isString consumerId
        consumerId = new ObjectId(consumerId)
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
    $query["consumerId"] = consumerId
    $query["org.type"]   = choices.organizations.BUSINESS
    $query["org.id"]     = businessId

    @model.collection.update $query, {$inc: {"data.karmaPoints.earned": amount, "data.karmaPoints.remaining": amount} }, {safe: true, upsert: true}, (error, count)->
      if error?
        logger.error error
      callback(error, count)

  ### _useKarmaPoints_ ###
  #
  # KarmaPoints were used to redeem a goody so decrement the number of KarmaPoints available for a specific user with a specific business
  #
  # **consumerId** _String/ObjectId_ id of the consumer<br />
  # **businessId** _String/ObjectId_ id of the business<br />
  # **amount** _String/ObjectId_ amount of KarmaPoints<br />
  # **callback** _Function_ (error, success)<br />
  @useKarmaPoints: (consumerId, businessId, amount, callback)->
    try
      if Object.isString consumerId
        consumerId = new ObjectId(consumerId)
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
    $query["consumerId"] = consumerId
    $query["org.type"]   = choices.organizations.BUSINESS
    $query["org.id"]     = businessId

    @model.collection.update $query, {$inc: {"data.karmaPoints.remaining": -1 * amount, "data.karmaPoints.used": amount}}, {safe: true}, (error, count)->
      success = false
      if error?
        logger.error error
      if count == 1
        success = true
      callback(error, success)

  @add: (data, callback)->
    obj = {
      org: {
        type                : data.org.type
        id                  : data.org.id
      }
      consumerId            : data.consumerId
      data                  : data.data || {}
    }

    instance = new @model(obj)
    instance.save(callback)

  @list: (org, callback)->
    query = @query()
    query.where("org.type", org.type)
    query.where("org.id", org.id)
    query.exec(callback)
    return

  #Give me a list of people who have tapped in to a business before and therefore are customers
  @withTapIns: (org, options, callback)->
    if Object.isString(org.id)
      org.id = new ObjectId(org.id)
    @model.collection.find {"org.type": org.type, "org.id": org.id, "data.tapIns.totalTapIns": {$gt: 0}}, (error, cursor)->
      if error?
        callback(error)
        return
      cursor.limit(options.limit || 25)
      cursor.skip(options.skip || 0)
      cursor.sort({"data.tapIns.lastVisited": -1})
      cursor.toArray (error, statistics)->
        logger.debug(statistics)
        callback(error, statistics)

  @getByConsumerIds: (org, consumerIds, callback)->
    query = @query()
    query.where("org.type", org.type)
    query.where("org.id", org.id)

    #return multiple documents if multiple consumers specified
    query.in "consumerId", consumerIds

    query.exec(callback)
    return

  @pollAnswered: (org, consumerId, transactionId, timestamp, callback)->
    if Object.isString(org.id)
      org.id = new ObjectId(org.id)

    if Object.isString(consumerId)
      consumerId = new ObjectId(consumerId)

    if Object.isString(transactionId)
      transactionId = new ObjectId(transactionId)

    $update = {
      $set: {"data.polls.lastAnsweredDate": timestamp}
      $inc: {"data.polls.totalAnswered": 1}
      $push: {"transactions.ids": transactionId}
    }

    @model.collection.update {org: org, consumerId: consumerId}, $update, {safe: true, upsert: true }, callback

  @discussionAnswered: (org, consumerId, transactionId, timestamp, callback)->

  @eventRsvped: (org, consumerId, transactionId, timestamp, callback)->

  #we accept the tapIns as a parameter because we use it when you claim a barcode, in that case you may have more than just one tapIn that is getting transfered in.

  @btTapped: (orgEntity, consumerId, transactionId, spent, karmaPointsEarned, donationAmount, timestamp, totalTapIns, callback)->
    if Object.isFunction(totalTapIns)
      callback = totalTapIns
      totalTapIns = 1

    if Object.isString(orgEntity.id)
      orgEntity.id = new ObjectId(orgEntity.id)

    if Object.isString(consumerId)
      consumerId = new ObjectId(consumerId)

    if Object.isString(transactionId)
      transactionId = new ObjectId(transactionId)

    $inc = {}
    $inc["data.tapIns.totalTapIns"] = totalTapIns

    if spent? && !isNaN(spent)
      $inc["data.tapIns.totalAmountPurchased"] = parseInt(spent) #as an integer

    if karmaPointsEarned? && !isNaN(karmaPointsEarned)
      $inc["data.karmaPoints.earned"] = parseInt(karmaPointsEarned)
      $inc["data.karmaPoints.remaining"] = parseInt(karmaPointsEarned)

    if donationAmount? && !isNaN(donationAmount)
      $inc["data.tapIns.totalDonated"] = if !isNaN(donationAmount) then parseInt(donationAmount) else 0

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

    @model.collection.update {org: org, consumerId: consumerId, 'transactions.ids': {$ne: transactionId}}, $update, {safe: true, upsert: true }, callback
    return

  @_inc: (org, consumerId, field, value, callback)->
    #default is to increment by 1
    if Object.isFunction(value)
      callback = value
      value = 1

    query = @queryOne()
    query.where("org.type", org.type)
    query.where("org.id", org.id)
    query.where("consumerId", consumerId)

    $inc = {}
    $inc["data.#{field}"] = value

    query.update {$inc: $inc}, callback #will return the number of documents updated
    return

  @setTransactonPending: @__setTransactionPending
  @setTransactionProcessing: @__setTransactionProcessing
  @setTransactionProcessed: @__setTransactionProcessed
  @setTransactionError: @__setTransactionError