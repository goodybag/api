require("./helpers").install(global)
tp = require "../transactions" #transaction processor

exports = module.exports = class Api
  @model = null
  constructor: ()->

  @_flattenDoc = (doc, startPath)->
    flat = {}
    #flatten function
    flatten = (obj, path)->
      if Object.isObject obj
        path = if !path? then "" else path+"."
        for key of obj
          flatten obj[key], path+key
      else if Object.isArray obj
        path = if !path? then "" else path+"."
        i = 0
        while i<obj.length
          flatten obj[i], path+i
          i++
      else
        flat[path] = obj
      return flat
    #end flatten
    return flatten doc, startPath

  @_copyFields = utils.copyFields

  @_query: ()->
    return @model.find() #instance of query object

  @query: @_query

  @_queryOne: ()->
    return @model.findOne() #instance of query object which will return only one document

  @queryOne: @_queryOne

  @optionParser: (options, q)->
    return @_optionParser(options, q)

  @_optionParser: (options, q)->
    query = q || @_query()

    if options.limit?
      query.limit options.limit

    if options.skip?
      query.skip options.skip

    if options.sort?
      query.sort options.sort.field, options.sort.direction

    return query

  @add: (data, callback)->
    return @_add(data, callback)

  @_add: (data, callback)->
    instance = new @model(data)
    instance.save callback
    return

  @update: (id, data, callback)->
    if Object.isString(id)
      id = new ObjectId(id)
    @model.findById id, (err, obj)->
      for own k,v of data
        obj[k] = v
      obj.save callback

  #NEW update, everything should be migrated to this..
  @_update: (id, updateDoc, dbOptions, callback)->
    if Object.isString id
      id = new ObjectId id
    if id instanceof ObjectId
      id = { _id: id }
    if Object.isFunction dbOptions
      callback = dbOptions
      dbOptions = {safe:true}

    @model.update id, updateDoc, dbOptions, callback
    return

  @remove = (id, callback)->
    return @_remove(id, callback)

  @_remove = (id, callback)->
    if Object.isString id
      id = new ObjectId id
    if id instanceof ObjectId
      id = { _id: id }
    logger.silly id
    @model.remove id, callback
    return

  @del = @remove

  # @one: (id, callback)->
  @one: (id, fieldsToReturn, dbOptions, callback)->
    return @_one(id, fieldsToReturn, dbOptions, callback)

  @_one: (id, fieldsToReturn, dbOptions, callback)->
    if Object.isString id
      id = new ObjectId id
    if id instanceof ObjectId
      id = { _id: id }
    if Object.isFunction fieldsToReturn
      #Fields to return must always be specified for consumers...
      callback = fieldsToReturn
      fieldsToReturn = {}
      dbOptions = {safe:true}
      # callback new errors.ValidationError {"fieldsToReturn","Database error, fields must always be specified."}
      # return
    if Object.isFunction dbOptions
      callback = dbOptions
      dbOptions = {safe:true}
    @model.findOne id, fieldsToReturn, dbOptions, callback
    return

  @get: (options, fieldsToReturn, callback)->
    if Object.isFunction fieldsToReturn
      callback = fieldsToReturn
      fieldsToReturn = {} #all..
    query = @optionParser(options)
    query.fields fieldsToReturn
    logger.silly fieldsToReturn
    logger.debug query
    query.exec callback
    return

  @bulkInsert: (docs, options, callback)->
    @model.collection.insert(docs, options, callback)
    return

  @getByEntity: (entityType, entityId, id, fields, callback)->
    if Object.isFunction(fields)
      callback=fields
      @model.findOne {_id: id, 'entity.type': entityType ,'entity.id': entityId}, callback
    else
      @model.findOne {_id: id, 'entity.type': entityType ,'entity.id': entityId}, fields, callback
    return

  #TRANSACTIONS
  @createTransaction: (state, action, data, direction, entity)->
    #we are doing a check for entity because we can have transactions that don't refer to an entity. An example of this is the STAT_BT_TAPPED transaction
    if entity? and Object.isString(entity.id)
      entity.id = new ObjectId(entity.id)

    transaction = {
      _id: new ObjectId() #We are putting this in here only because mongoose does for us. #CONSIDER REMOVING THE REGULAR ID FIELD AND ONLY USE THIS
      id: new ObjectId()
      state: state
      action: action
      error: {}
      dates: {
        created: new Date()
        lastModified: new Date()
      }
      data: data
      direction: direction
      entity: if entity? then entity else undefined
    }

    return transaction

  @moveTransactionToLog: (id, transaction, callback)->
    if Object.isString(id)
      id = new ObjectId(id)

    $query = {
      _id: id
      "transactions.ids": transaction.id
    }

    $push = {
      "transactions.log": transaction
    }

    $pull = {
      "transactions.temp": {id: transaction.id}
    }

    $update = {
      $push: $push
      $pull: $pull
    }

    @model.collection.findAndModify $query, [], $update, {safe: true, new: true}, callback

  @removeTransaction: (documentId, transactionId, callback)->
    if Object.isString(documentId)
      documentId = new ObjectId(documentId)
    if Object.isString(transactionId)
      transactionId = new ObjectId(transactionId)

    $update = {
      "$pull": {"transactions.log": {id: transactionId} }
    }

    @model.collection.update {"_id": documentId}, $update, {safe: true, multi: true}, (error, count)->  #will return count of documents matched
      if error?
        logger.error error
      callback(error, count)

  @removeTransactionInvolvement: (transactionId, callback)->
    if Object.isString(transactionId)
      transactionId = new ObjectId(transactionId)

    $update = {
      "$pull": {"transactions.ids": transactionId}
    }

    @model.collection.update {"transactions.ids": transactionId}, $update, {safe: true, multi: true}, (error, count)->  #will return count of documents matched
      if error?
        logger.error error
      callback(error, count)

  #TRANSACTION STATE
  #locking variable is to ask if this is a locking transaction or not (usually creates/updates are locking in our case)
  @__setTransactionPending: (id, transactionId, locking, callback)->
    if Object.isString(id)
      id = new ObjectId(id)

    if Object.isString(transactionId)
      transactionId = new ObjectId(transactionId)

    $query = {
      _id: id
      "transactions.log": {
        $elemMatch: {
          "id": transactionId
          "state":{
            $nin: [choices.transactions.states.PENDING, choices.transactions.states.PROCESSING, choices.transactions.states.PROCESSED, choices.transactions.states.ERROR]
          }
        }
      }
    }

    $set = {
      "transactions.log.$.state": choices.transactions.states.PENDING
      "transactions.log.$.dates.lastModified": new Date()
      "transactions.locked": locked
    }

    if locking is true
      $set["transactions.state"] = choices.transactions.states.PENDING

    @model.collection.findAndModify $query, [], {$set: $set}, {new: true, safe: true}, callback

  @__setTransactionProcessing: (id, transactionId, locking, callback)->
    if Object.isString(id)
      id = new ObjectId(id)

    if Object.isString(transactionId)
      transactionId = new ObjectId(transactionId)

    $query = {
      _id: id
      "transactions.log": {
        $elemMatch: {
          "id": transactionId
          "state":{
            $nin: [choices.transactions.states.PROCESSED, choices.transactions.states.ERROR] #purposefully keeping choices.transactions.state.PROCESSING out of this list
          }
        }
      }
    }

    $set = {
      "transactions.log.$.state": choices.transactions.states.PROCESSING
      "transactions.log.$.dates.lastModified": new Date()
    }

    $inc = {
      "transactions.log.$.attempts": 1
    }

    if locking is true
      $set["transactions.state"] = choices.transactions.states.PROCESSING

    @model.collection.findAndModify $query, [], {$set: $set, $inc: $inc}, {new: true, safe: true}, callback

  @__setTransactionProcessed: (id, transactionId, locking, removeLock, modifierDoc, callback)->
    if Object.isString(id)
      id = new ObjectId(id)

    if Object.isString(transactionId)
      transactionId = new ObjectId(transactionId)

    $query = {
      _id: id
      "transactions.log": {
        $elemMatch: {
          "id": transactionId
          "state":{
            $nin: [choices.transactions.states.PROCESSED, choices.transactions.states.ERROR]
          }
        }
      }
    }

    $set = {
      "transactions.log.$.state": choices.transactions.states.PROCESSED
      "transactions.log.$.dates.lastModified": new Date()
      "transactions.log.$.dates.completed": new Date()
    }

    if locking is true
      $set["transactions.state"] = choices.transactions.states.PROCESSED

    if removeLock is true
      $set["transactions.locked"] = false

    $update = {}
    $update.$set = {}

    Object.merge($update, modifierDoc)
    Object.merge($update.$set, $set)

    @model.collection.findAndModify $query, [], $update, {new: true, safe: true}, (error, doc)->
      callback(error, doc)

  @__setTransactionError: (id, transactionId, locking, removeLock, errorObj, modifierDoc, callback)->
    if Object.isString(id)
      id = new ObjectId(id)

    if Object.isString(transactionId)
      transactionId = new ObjectId(transactionId)

    $query = {
      _id: id
      "transactions.log": {
        $elemMatch: {
          "id": transactionId
          "state":{
            $nin: [choices.transactions.states.PROCESSED, choices.transactions.states.ERROR]
          }
        }
      }
    }

    $set = {
      "transactions.log.$.state": choices.transactions.states.ERROR
      "transactions.log.$.dates.lastModified": new Date()
      "transactions.log.$.dates.completed": new Date()
      "transactions.log.$.error": errorObj
    }

    if locking is true
      $set["transactions.state"] = choices.transactions.states.ERROR

    if removeLock is true
      $set["transactions.locked"] = false

    $update = {}
    $update.$set = {}

    Object.merge($update, modifierDoc)
    Object.merge($update.$set, $set)

    logger.debug($update)
    @model.collection.findAndModify $query, [], $update, {new: true, safe: true}, callback

  @checkIfTransactionExists: (id, transactionId, callback)->
    if Object.isString(id)
      id = new ObjectId(id)

    if Object.isString(transactionId)
      transactionId = new ObjectId(transactionId)

    $query = {
      _id: id
      "transactions.ids": transactionId
    }

    @model.findOne $query, callback