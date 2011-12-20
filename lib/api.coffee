exports = module.exports

generatePassword = require "password-generator"
hashlib = require "hashlib"
util = require "util"
async = require "async"

globals = require "globals"
db = require "./db"
tp = require "./transactions" #transaction processor 

ObjectId = require("mongoose").Types.ObjectId;

utils = globals.utils
choices = globals.choices
defaults = globals.defaults
errors = globals.errors

Client = db.Client
Consumer = db.Consumer
Business = db.Business
Media = db.Media
Poll = db.Poll
Discussion = db.Discussion
Response = db.Response
ClientInvitation = db.ClientInvitation
Tag = db.Tag
EventRequest = db.EventRequest
Event = db.Event
Stream = db.Stream
TapIn = db.TapIn
BusinessRequest = db.BusinessRequest

#TODO:
#Make sure that all necessary fields exist for each function before sending the query to the db

class API
  @model = null
  constructor: ()->
    #nothing to say

  @_query: ()->
    return @model.find() #instance of query object

  @optionParser = (options, q)->
    return @_optionParser(options, q)

  @_optionParser = (options, q)->
    query = q || @_query()

    if options.limit?
      query.limit(options.limit)
      
    if options.skip?
      query.skip(options.skip)
    
    if options.sort?
      query.sort(options.sort)

    return query

  @add = (data, callback)->
    return @_add(data, callback)

  @_add = (data, callback)->
    instance = new @model(data)
    instance.save callback
    return

  @update: (id, data, callback)->
    @model.findById id, (err, obj)->
      for own k,v of data
        obj[k] = v
      obj.save callback

  @remove = (id, callback)->
    return @_remove(id, callback)

  @_remove = (id, callback)->
    @model.remove {'_id': id}, callback
    return

  @one = (id, callback)->
    return @_one(id, callback)

  @_one = (id, callback)->
    @model.findOne {_id: id}, callback
    return

  @get = (options, callback)->
    query = @optionParser(options)
    query.exec callback
    return
    
  @bulkInsert: (docs, options, callback)->
    @model.collection.insert(docs, options, callback)
    return
  
  @getByEntity: (entityType, entityId, id, callback)->
    @model.findOne {_id: id, 'entity.type': entityType ,'entity.id': entityId}, callback
    return


  #EVENT ENGINE
  @createUserEvent: (eventType, entityType, entityId, eventData)->
    event = {}
    event.eventType = eventType
    event.entity = {
      type: entityType
      id: entityId
    }
    event.data = eventData
    event.state = choices.eventStates.PENDING
    event.timestamp = new Date()
    event.attempts = 0

    return event

  @createOrgEvent: (eventType, orgEntityType, orgEntityId, userEntityType, userEntityId, eventData)->
    event = {}
    event.eventType = eventType
    event.entity = {
      type: orgEntityType
      id: orgEntityId
    }
    event.byEntity = {
      type: userEntityType
      id: userEntityId
    }
    event.data = eventData
    event.state = choices.eventStates.PENDING
    event.timestamp = new Date()
    event.attempts = 0

    return event

  @createEventsObj: (event)->
    eventId = new ObjectId()
    eventIdStr = eventId.toString()
      
    events = {}
    events.history = {}

    events.ids = [eventId]
    events.history[eventIdStr] = event

    return events
    
  # EVENTENGINE STATE
  @__setEventPending: (id, eventId, callback)->
    if Object.isString(id)
      id = new ObjectId(id)

    if Object.isString(eventId)
      eventId = new ObjectId(eventId)

    eventIdStr = eventId.toString()

    $set: {}
    $set["events.history.#{eventIdStr}.state"] = choices.eventStates.PENDING
    @model.collection.findAndModify {_id: id}, [], {$set: $set}, {new: true, safe: true}, callback
    return

  @__setEventProcessing: (id, eventId, callback)->
    if Object.isString(id)
      id = new ObjectId(id)

    if Object.isString(eventId)
      eventId = new ObjectId(eventId)

    eventIdStr = eventId.toString()

    $set: {}
    $set["events.history.#{eventIdStr}.state"] = choices.eventStates.PROCESSING

    $inc: {}
    $inc["events.history.#{eventIdStr}.attempts"] = 1
    @model.collection.findAndModify {_id: id}, [], {$set: $set, $inc: $inc}, {new: true, safe: true}, callback
    return
    
  @__setEventProcessed: (id, eventId, callback)->
    if Object.isString(id)
      id = new ObjectId(id)

    if Object.isString(eventId)
      eventId = new ObjectId(eventId)

    eventIdStr = eventId.toString()

    $set: {}
    $set["events.history.#{eventIdStr}.state"] = choices.eventStates.PROCESSED
    @model.collection.findAndModify {_id: id}, [], {$set: $set}, {new: true, safe: true}, callback
    return
    
  @__setEventError: (id, eventId, errorObj, callback)->
    if !callback?
      callback = errorObj
      
    if Object.isString(id)
      id = new ObjectId(id)

    if Object.isString(eventId)
      eventId = new ObjectId(eventId)

    eventIdStr = eventId.toString()

    $set: {}
    $set["events.history.#{eventIdStr}.state"] = choices.eventStates.ERROR
    $set["events.history.#{eventIdStr}.error"] = errorObj
    @model.collection.findAndModify {_id: id}, [], {$set: $set}, {new: true, safe: true}, callback
    return
  
  #TRANSACTIONS
  @createTransaction: (state, action, data, direction, entity)->
    transaction = {
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
      entity: {
        type: entity.type
        id: entity.id
      }
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
      $set.state = choices.transactions.states.PENDING
    
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
            $nin: [choices.transactions.states.PROCESSED, choices.transactions.states.ERROR]
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
      $set.state = choices.transactions.states.PROCESSING
    
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
      $set.state = choices.transactions.states.PROCESSED
    
    if removeLock is true
      $set["transactions.locked"] = false

    $update = {} 
    $update.$set = {}

    Object.merge($update, modifierDoc)
    Object.merge($update.$set, $set)

    @model.collection.findAndModify $query, [], $update, {new: true, safe: true}, callback

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
      $set.state = choices.transactions.states.ERROR

    if removeLock is true
      $set["transactions.locked"] = false

    $update = {} 
    $update.$set = {}

    Object.merge($update, modifierDoc)
    Object.merge($update.$set, $set)
    
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

class Consumers extends API
  @model = Consumer

  @facebook: (data, callback)->
    #TODO
    return

  @register: (email, password, callback)->
    self = this
    query = @_query()
    query.where('email', email)
    query.findOne (error, consumer)->
      if error?
        callback error #db error
      else if !consumer?
        self.add({email:email,password:password}, callback) #registration success
      else if consumer?
        callback new errors.ValidationError {"email":"Email Already Exists"} #email exists error
      return
  
  @login: (email, password, callback)->
    query = @_query()
    query.where('email', email).where('password', password)
    query.findOne (error, consumer)->
      if(error)
        return callback error, consumer
      else if consumer?
        return callback error, consumer
      else
        return callback new errors.ValidationError {"login":"invalid username/password"}

  @updateHonorScore: (id, eventId, amount, callback)->
    if Object.isString(id)
      id = new ObjectId(id)
      
    if Object.isString(eventId)
      eventId = new ObjectId(eventId)

    @model.findAndModify {_id:  id}, [], {$push:{"events.ids": eventId}, $inc: {honorScore: amount}}, {new: true, safe: true}, callback

  @deductFunds: (id, transactionId, amount, callback)->
    if Object.isString(id)
      id = new ObjectId(id)
    
    if Object.isString(transactionId)
      transactionId = new ObjectId(transactionId)
    
    @model.collection.findAndModify {_id: id, 'funds.remaining': {$gte: amount}, 'transactions.ids': {$ne: transactionId}}, [], {$addToSet: {"transactions.ids": transactionId}, $inc: {'funds.remaining': -1*amount }}, {new: true, safe: true}, callback
    
  @depositFunds: (id, transactionId, amount, callback)->
    if Object.isString(id)
      id = new ObjectId(id)
    
    if Object.isString(transactionId)
      transactionId = new ObjectId(transactionId)
    
    @model.collection.findAndModify {_id: id, 'transactions.ids': {$ne: transactionId}}, [], {$addToSet: {"transactions.ids": transactionId}, $inc: {'funds.remaining': amount, 'funds.allocated': amount }}, {new: true, safe: true}, callback

  @setEventPending: @__setEventPending
  @setEventProcessing: @__setEventProcessing
  @setEventProcessed: @__setEventProcessed
  @setEventError: @__setEventError


class Clients extends API
  @model = Client
  
  @register: (data, callback)->
    #if !utils.mustContain(data, ['email','firstname', 'lastname', 'password'])
    #  return callback(new Error("at least one required field is missing."))
    self = this
    query = @_query()
    query.where('email', data.email)
    query.findOne (error, client)->
      if error?
        callback error #db error
      else if !client?
        self.add(data, callback) #registration success
      else if client?
        callback new errors.ValidationError {"email":"Email Already Exists"} #email exists error
      return
        
  @login: (email, password, callback)->
    query = @_query()
    query.where('email', email).where('password', password)
    query.findOne (error, client)->
      if(error)
        return callback error, client
      else if client?
        return callback error, client
      else
        return callback new Error("invalid username/password")
  
  @getBusinessIds: (id, callback)->
    query = Businesses.model.find()
    query.only('_id')
    query.where('clients', id)

    query.exec (error, businesses)->
      if error?
        callback error, null
      else
        ids = []
        for business in businesses
          ids.push business.id
        callback null, ids

  @getByEmail: (email, callback)->
    query = @_query()
    query.where('email', email)
    query.findOne (error, client)->
      if error?
        callback error #db error
      else
        callback null, client #if no client with that email will return null

  @updateWithPassword: (id, password, options, callback)->
    query = @_query()
    query.where('_id', id).where('password', password)
    query.where('password', password)
    query.findOne (error, client)->
      if error?
        callback error
      else if client?
        for own k,v of options
          client[k] = v
        client.save callback
      else
        callback new errors.ValidationError {'password':"Wrong Password"} #invalid login error
      return

  @setEventPending: @__setEventPending
  @setEventProcessing: @__setEventProcessing
  @setEventProcessed: @__setEventProcessed
  @setEventError: @__setEventError


class Businesses extends API
  @model = Business
  
  #clientid, limit, skip
  @optionParser = (options, q)->
    query = @_optionParser(options, q)
    query.in('clients', [options.clientId]) if options.clientId?
    return query
    
  @add = (clientId, data, callback)->
    instance = new @model()
    for own k,v of data
      instance[k] = v
    if data['locations']? and data['locations'] != []
        instance.markModified('locations')

    #add user to the list of users for this business and add them to the group of owners
    instance['clients'] = [clientId] #only one user now
    instance['clientGroups'] = {}
    instance['clientGroups'][clientId] = choices.businesses.groups.OWNERS
    instance['groups'][choices.businesses.groups.OWNERS] = [clientId]

    instance.save callback
    return

  @addClient: (id, clientId, groupName, callback)->
    if !(groupName in choices.businesses.groups._enum)
      callback new errors.ValidationError {"groupName":"Group does not Exist"}
      return
      
    #incase we pass in a string turn it into an ObjectId
    if Object.isString(clientId)
      clientId = new ObjectId(clientId)

    if Object.isString(id)
      id = new ObjectId(id)
      
    updateDoc = {}
    updateDoc['$addToSet'] = {}
    updateDoc['$addToSet']['clients'] = clientId
    updateDoc['$addToSet']['groups.'+groupName] = clientId
    updateDoc['$set'] = {}
    updateDoc['$set']['clientGroups.'+clientId] = groupName

    @model.collection.update {_id: id}, updateDoc, {safe: true}, callback
    return

  @addManager: (id, clientId, callback)->
    @addClient(id, clientId, choices.businesses.groups.MANAGERS, callback)
    return

  @addOwner: (id, clientId, callback)->
    @addClient(id, clientId, choices.businesses.groups.OWNERS, callback)
    return
  
  @delClient: (id, clientId, callback)->
    self = this
    
    #incase we pass in a string turn it into an ObjectId
    if Object.isString(clientId)
      clientId = new ObjectId(clientId)

    if Object.isString(id)
      id = new ObjectId(id)
    
    @one id, (error, business)->
      if error?
        callback error
        return
      else
        updateDoc = {}
        updateDoc['$pull'] = {}
        updateDoc['$pull']['clients'] = clientId
        updateDoc['$unset'] = {}

        group = business.clientGroups[clientId] #the group the client is in
        updateDoc['$pull']['groups.'+group] = clientId
        updateDoc['$unset']['clientGroups.'+clientId] = 1
        self.model.collection.update {_id: id}, updateDoc, callback
  
  @updateIdentity: (id, data, callback)->
    set = {}
    for own k,v of data
      if !utils.isBlank(v)
        set[k] = v
    @model.collection.update {_id: new ObjectId(id)}, {$set: set}, {safe: true}, callback

  @addLocation: (id, data, callback)->
    if Object.isString(id)
      id = new ObjectId(id)
      
    data._id = new ObjectId()
    @model.collection.update {_id: id}, {$push: {"locations": data}}, {safe: true}, (error, count)->
      callback error, count, data._id

  @updateLocation: (id, locationId, data, callback)->
    if Object.isString(id)
      id = new ObjectId(id)
      
    if Object.isString(locationId)
      locationId = new ObjectId(locationId)
      
    data._id = locationId
    #@model.update {_id: new ObjectId(id), 'locations._id': new ObjectId(locationId)}, data, (error, business)-> #safe=true is the default here I believe
    @model.collection.update {_id: id, 'locations._id': locationId}, {$set: {"locations.$": data}}, {safe: true}, callback
  
  #locationIds can be an array or a string
  @delLocations: (id, locationIds, callback)->
    objIds = []
    if Object.isArray(locationIds)
      for locationId in locationIds
        objIds.push new ObjectId(locationId)
    else
      objIds = [locationIds]
    
    if Object.isString(id)
      id = new ObjectId(id)
      
    @model.collection.update {_id: id}, {$pull: {locations: {_id: {$in: objIds} }}}, {safe: true}, callback

  @getGroup: (id, groupName, callback)->
    data = {}
    data.groupName = groupName
    @one id, (error, business)->
      if error?
        callback error, business
      else
        userIds = []
        for userId in business.groups[groupName]
          userIds.push(userId)
        query = Client.find()
        query.in('_id', userIds)
        query.exclude(['created', 'password'])
        query.exec (error, clients)->
          if error?
            callback error, null
          else
            data.members = clients
            callback null, data

  @deductFunds: (id, transactionId, amount, callback)->
    if Object.isString(id)
      id = new ObjectId(id)
    
    if Object.isString(transactionId)
      transactionId = new ObjectId(transactionId)
    
    @model.collection.findAndModify {_id: id, 'funds.remaining': {$gte: amount}, 'transactions.ids': {$ne: transactionId}}, [], {$addToSet: {"transactions.ids": transactionId}, $inc: {'funds.remaining': -1*amount }}, {new: true, safe: true}, callback

  @listWithTapins: (callback)->
    query = @_query()
    query.where('locations.tapins', true)
    query.exec callback

class Polls extends API
  @model = Poll

  #options: name, businessid, type, businessname,showstats, answered, start, end, outoffunds
  @optionParser = (options, q) ->
    query = q || @_query()
    query.where('entity.type', options.entityType) if options.entityType?
    query.where('entity.id', options.entityId) if options.entityId?
    query.where('dates.start').gte(options.start) if options.start?
    # query.where('dates.end').gte(options.start) if options.end?
    query.where('transaction.state', state) if options.state?
    return query
  
  # @add = (data, amount, event, callback)-> #come back to this one, first transactions need to work
  @add = (data, amount, callback)->
    instance = new @model(data)

    transactionData = {
      amount: amount
    }

    transaction = @createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.POLL_CREATE, transactionData, choices.transactions.directions.INBOUND, instance.entity)
    
    instance.transactions.locked = true
    instance.transactions.ids = [transaction.id]
    instance.transactions.log = [transaction]

    #instance.events = @_createEventsObj event

    instance.save (error, poll)->
      callback error, poll
      if error?
        return
      else
        tp.process(poll, transaction)
    return
  
  @update: (entityType, entityId, pollId, data, amount, callback)->
    self = this
    @getByEntity entityType, entityId, pollId, (error, poll)->
      if error?
        callback error, null
      else if !poll?
        callback new errors.ValidationError({"poll":"Poll does not exist or Access Denied."})
      else
        if (poll.dates.start <= new Date() && poll.state!=choices.transactions.states.ERROR)
          callback new errors.ValidationError({"poll":"Can not edit a poll that is in progress or that has completed."}), null
        else
          for own k,v of data
            poll[k] = v

          transactionData = {
                amount: amount
          }

          transaction = self.createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.POLL_CREATE, transactionData, choices.transactions.directions.INBOUND, poll.entity)
        
          poll.transactions.locked = true
          poll.transactions.ids = [transaction.id]
          poll.transactions.log = [transaction]

          #poll.events = @_createEventsObj event

          poll.save (error, poll)->
            callback error, poll
            if error?
              return
            else
              tp.process(poll, transaction)
            return
      return
    return

  @all = (entityType, entityId, skip, limit, callback)->
    options = {
      entityType: entityType,
      entityId: entityId, 
      skip: skip, 
      limit: limit
    }
    query = @optionParser(options)
    query.fields({
        _id                   : 1,
        entity                : 1,
        type                  : 1,
        name                  : 1,
        question              : 1,        
        choices               : 1,
        "responses.remaining" : 1,
        "responses.max"       : 1,
        flagCount             : 1,
        skipCount             : 1,
        dates                 : 1,
        funds                 : 1,
        state                 : 1,
        media                 : 1,
        "funds.perResponse"   : 1
    });
    query.sort('dates.start', -1)
    query.exec callback
    return

  @pending = (entityType, entityId, skip, limit, callback)->
    options = {
      entityType: entityType,
      entityId: entityId, 
      skip: skip, 
      limit: limit
    }
    query = @optionParser(options)
    query.where('dates.start').gt(new Date())
    query.fields({
        _id                   : 1,
        entity                : 1,
        type                  : 1,
        name                  : 1,
        question              : 1,        
        choices               : 1,
        "responses.remaining" : 1,
        "responses.max"       : 1,
        flagCount             : 1,
        skipCount             : 1,
        dates                 : 1,
        funds                 : 1,
        state                 : 1,
        media                 : 1,
        "funds.perResponse"   : 1
    });
    query.sort('dates.start', -1)
    query.exec callback
    return

  @active = (entityType, entityId, skip, limit, callback)->
   options = {
      entityType: entityType,
      entityId: entityId, 
      skip: skip, 
      limit: limit
    } 
    query = @optionParser(options)
    query.where('dates.start').lte(new Date())
    # query.where('dates.end').gt(new Date())
    query.fields({
        _id                   : 1,
        entity                : 1,
        type                  : 1,
        name                  : 1,
        question              : 1,        
        choices               : 1,
        "responses.remaining" : 1,
        "responses.max"       : 1,
        flagCount             : 1,
        skipCount             : 1,
        dates                 : 1,
        funds                 : 1,
        state                 : 1,
        media                 : 1,
        "funds.perResponse"   : 1
    });
    query.sort('dates.start', -1)
    query.exec callback
    return
    
  @completed = (entityType, entityId, skip, limit, callback)->
    options = {
      entityType: entityType,
      entityId: entityId, 
      skip: skip, 
      limit: limit
    }
    query = @optionParser(options)
    # query.where('dates.end').lte(new Date())
    query.fields({
        _id                   : 1,
        entity                : 1,
        type                  : 1,
        name                  : 1,
        question              : 1,        
        choices               : 1,
        "responses.remaining" : 1,
        "responses.max"       : 1,
        flagCount             : 1,
        skipCount             : 1,
        dates                 : 1,
        funds                 : 1,
        state                 : 1,
        media                 : 1,
        "funds.perResponse"   : 1
    });
    query.sort('dates.start', -1)
    query.exec callback
    return
  
  @answered = (consumerId, skip, limit, callback)->
    if Object.isString(consumerId)
      consumerId = new ObjectId(consumerId)
    query = @_query()
    query.where('responses.consumers',consumerId)
    fieldsToReturn = {
        _id                 : 1,
        question            : 1,
        choices             : 1,
        displayName         : 1,
        displayMedia        : 1,
        "entity.name"       : 1,
        media               : 1,
        "funds.perResponse" : 1
    }
    fieldsToReturn["responses.log.#{consumerId}"] = 1 #consumer answer info., only their info.
    
    query.fields(fieldsToReturn)
    query.sort("responses.log.#{consumerId}.timestamp",-1)
    query.exec (error, polls)->
      if error?
        callback error
        return
      Polls.removePollPrivateFields(polls)
      callback null, polls
      return

  @answer = (consumerId, pollId, answers, callback)->
    if Object.isString(pollId)
      pollId = new ObjectId(pollId)

    if Object.isString(consumerId)
      consumerId = new ObjectId(consumerId)
      
    minAnswer = Math.min.apply(Math,answers)
    maxAnswer = Math.max.apply(Math,answers)
    if(minAnswer < 0 || isNaN(minAnswer) || isNaN(maxAnswer))
      callback new errors.ValidationError({"answers":"Out of Range"})
      return
    timestamp = new Date()

    perResponse = 0.0

    self = this
    async.series {
      findPerResponse: (cb)->
        # We need to find the poll first just to get the perResponse amount for transactions
        self.model.findOne {_id: pollId}, {funds: 1}, (error, poll)->
          if error?
            cb error
            return
          else if !poll?
            cb new errors.ValidationError({"poll":"Invalid poll."});
            return
          else
            perResponse = poll.funds.perResponse
            cb()

      save: (cb)->
        
        inc = new Object()
        set = new Object()
        push = new Object()
        
        transactionData = {
          amount: perResponse
        }

        entity = {
          type: choices.entities.CONSUMER,
          id: consumerId
        }

        # CREATE TRANSACTION
        transaction = self.createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.POLL_ANSWER, transactionData, choices.transactions.directions.OUTBOUND, entity)
    
        push["transactions.ids"] = transaction.id
        push["transactions.log"] = transaction
        inc["funds.remaining"] = -1*perResponse

        # CREATE EVENT
        event = self.createUserEvent choices.eventTypes.POLL_ANSWERED, choices.entities.CONSUMER, consumerId
        eventId = new ObjectId()
        eventIdStr = eventId.toString()
        set["events.history.#{eventIdStr}"] = event
        push["events.ids"] = eventId
    

        inc["responses.remaining"] = -1;
    
        i=0
        while i<answers.length
          inc["responses.choiceCounts."+answers[i]] = 1;
          i++
      
        set["responses.log."+consumerId] = {
            answers   : answers,
            timestamp : timestamp
        }
    
        push["responses.dates"] = {
          consumerId: consumerId
          timestamp: timestamp
        }
        push["responses.consumers"] = consumerId

        update = {
          $inc  : inc
          $push : push
          $set  : set
        }
    
        fieldsToReturn = {
          _id                      : 1,
          question                 : 1,
          choices                  : 1,
          "responses.choiceCounts" : 1,
        # "responses.log.consumerId: 1, # below
          showStats                : 1,
          displayName              : 1,
          displayMedia             : 1,
          "entity.name"            : 1,
          media                    : 1,
          dates                    : 1,
          "funds.perResponse"      : 1
        }
        fieldsToReturn["responses.log.#{consumerId}"] = 1
    
        query = {
            _id                       : pollId,
            "entity.id"               : {$ne : consumerId} #can't answer a question you authored
            numChoices                : {$gt : maxAnswer}   #makes sure all answers selected exist
            "responses.consumers"     : {$ne : consumerId}  #makes sure consumer has not already answered
            "responses.skipConsumers" : {$ne : consumerId}  #makes sure consumer has not already skipped..
            "responses.flagConsumers" : {$ne : consumerId}  #makes sure consumer has not already flagged..
            "dates.start"             : {$lte: new Date()}  #makes sure poll has started
            # "dates.end"               : {$gt : new Date()}  #makes sure poll has not ended
            "state"                   : choices.transactions.states.PROCESSED #poll is processed and ready to launch
        }
        query.type = if answers.length==1 then "single" else "multiple" #prevent injection of multiple answers for a single poll..

        self.model.collection.findAndModify query, [], update, {new:true, safe:true}, fieldsToReturn, (error, poll)->
          if error?
            cb error
            return
          if !poll?
            cb new errors.ValidationError({"poll":"Invalid poll, Invalid answer, You are owner of the poll, or You've already answered."});
            return
          Polls.removePollPrivateFields(poll)
          cb null, poll
          tp.process(poll, transaction)
          return
    },
    (error, results)->
      if error?
        callback(error)
        return
      callback null, results
      return
    #TODO: transaction of funds.. per response gain to consumer..
  
  @skip = (consumerId, pollId, callback)->
    if Object.isString(consumerId)
      consumerId = new ObjectId(consumerId)
    query = @_query()
    query.where('_id',pollId)
    query.where('entity.id').ne(consumerId)               #not author
    query.where('responses.consumers'    ).ne(consumerId) #not already answerd 
    query.where('responses.skipConsumers').ne(consumerId) #not already skipped
    query.where('responses.flagConsumers').ne(consumerId) #not already flagged
    query.where('dates.start').lte(new Date())            #poll has started
    # query.where('dates.end').gt(new Date())               #poll has not ended
    query.where('state',choices.transactions.states.PROCESSED)    #poll is processed (paid for) and ready to launch

    query.update {$push:{"responses.skipConsumers":consumerId},$inc:{"responses.skipCount":1}}, (error, success)->
      callback error, success # 1 or 0
      return

  @flag = (consumerId, pollId, callback)->
    if Object.isString(consumerId)
      consumerId = new ObjectId(consumerId)
    query = @_query()
    query.where('_id',pollId)
    query.where('entity.id').ne(consumerId)               #not author
    query.where('responses.consumers'    ).ne(consumerId) #not already answerd 
    query.where('responses.skipConsumers').ne(consumerId) #not already skipped
    query.where('responses.flagConsumers').ne(consumerId) #not already flagged
    query.where('dates.start').lte(new Date())            #poll has started
    # query.where('dates.end').gt(new Date())               #poll has not ended
    query.where('state',choices.transactions.states.PROCESSED)    #poll is processed (paid for) and ready to launch

    query.update {$push:{"responses.flagConsumers":consumerId},$inc:{"responses.flagCount":1}}, (error, success)->
      callback error, success # 1 or 0
      return

  @next = (consumerId, callback)->
    if Object.isString(consumerId)
      consumerId = new ObjectId(consumerId)
    query = @_query()
    query.where('entity.id').ne(consumerId)               #not author
    query.where('responses.consumers'    ).ne(consumerId) #not already answerd 
    query.where('responses.skipConsumers').ne(consumerId) #not already skipped
    query.where('responses.flagConsumers').ne(consumerId) #not already flagged
    query.where('responses.remaining').gt(0)
    query.where('dates.start').lte(new Date())            #poll has started
    # query.where('dates.end').gt(new Date())               #poll has not ended
    query.where('state',choices.transactions.states.PROCESSED)    #poll is processed (paid for) and ready to launch
    query.limit(1)                                        #you only want the next ONE

    query.fields({
        _id                 : 1,
        type                : 1,
        question            : 1,
        choices             : 1,
        displayName         : 1,
        displayMedia        : 1,
        "entity.name"       : 1,
        media               : 1,
        "funds.perResponse" : 1
    });
    query.exec (error, poll)->
      if error?
        callback error
        return
      Polls.removePollPrivateFields(poll)
      callback null, poll 
      return

  @removePollPrivateFields = (polls)->
    if !Object.isArray(polls) #if polls is a single poll object
      if(!polls.displayName)
        delete polls.entity
      if(!polls.displayMedia)
        delete media
      if(!polls.showStats && polls.responses?)
        delete polls.responses.choiceCounts 
    else                      #else polls is an array of poll objects
      i=0
      while i<polls.length
        if(!polls[i].displayName)
          delete polls[i].entity
        if(!polls[i].displayMedia)
          delete media
        if(!polls[i].showStats)
          delete polls[i].responses.choiceCounts 
        i++
    return

    
  @setEventPending: @__setEventPending
  @setEventProcessing: @__setEventProcessing
  @setEventProcessed: @__setEventProcessed
  @setEventError: @__setEventError
    
  @setTransactonPending: @__setTransactionPending
  @setTransactionProcessing: @__setTransactionProcessing
  @setTransactionProcessed: @__setTransactionProcessed
  @setTransactionError: @__setTransactionError
      
      
class Discussions extends API
  @model = Discussion

  @optionParser = (options, q)->
    query = @_optionParser(options, q)

    query.where('entity.type', options.entityType) if options.entityType?
    query.where('entity.id', options.entityId) if options.entityId?
    query.where('dates.start').gte(options.start) if options.start?
    # query.where('dates.end').gte(options.start) if options.end?
    query.where('transaction.state', state) if options.state?
    
    return query

  @update: (entityType, entityId, discussionId, data, callback)->
    @getByEntity entityType, entityId, discussionId, (error, discussion)->
      if error?
        callback error, discussion
      else
        if (discussion.dates.start <= new Date())
          callback {name: "DateTimeError", message: "Can not edit a discussion that is in progress or has completed."}, null
        else
          for own k,v of data
            discussion[k] = v
          discussion.save callback
      return
    return
    
  @add = (data, amount, callback)->
    instance = new @model(data)
    
   # transactions: {
   #    ids           : [ObjectId]
   #    history       : {}
   #  
   #    # Example of a transaction history object
   #    # history = {
   #    #   transactionId: {
   #    #     state: {type: String, required: true, enum: choices.transactions.state._enum, default: choices.transactions.state.PENDING}
   #    #     created: {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
   #    #     lastModified: {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
   #    #     amount: {type: Number, required: true, default: 0.0}
   #    #   }
   #    # }
   #  
   #    currentState  : {type: String, required: true, enum: choices.transactions.state._enum, default: choices.transactions.state.PENDING}
   #    currentId     : {type: ObjectId}
   #  
   #    currentAllocated: {type: Number, required: true}
   #    newAllocated    : {type: Number}
   # }


    transaction = {}
    transaction.state = choices.transactions.state.PENDING
    transaction.created = new Date()
    transaction.lastModified = new Date()
    
    transactionId = new ObjectId()
    transactionIdStr = transactionId.toString()

    instance.transactions.ids = [transactionId]

    instance.transactions.history = {}
    instance.transactions.history[transactionIdStr] = transaction

    instance.transactions.currentId = transactionId
    instance.transactions.currentState = choices.transactions.state.PENDING

    instance.transactions.currentAllocated = 0.0
    instance.transactions.newAllocated = amount

    instance.save (error, discussion)->
      callback error, discussion
      if error?
        return
      else
        amount = discussion.transactions.newAllocated - discussion.transactions.currentAllocated
        Businesses.deductFunds discussion.entity.id, choices.transactions.types.DISCUSSION, discussion.id, discussion.transactions.currentId, discussion.transactions.newAllocated, (error, business)->
          if error?
            return
          else
            Discussions.setTransactionProcessed instance.transactions.id, amount, (error, discussion)->
              return
    return
    
  @pending: (entityType, entityId, skip, limit, callback)->
    options = {
      entityType: entityType,
      entityId: entityId, 
      skip: skip, 
      limit: limit
    }
    query = @optionParser(options)
    query.where('dates.start').gt(new Date())
    query.sort('dates.start', -1)
    query.exec callback
    return

  @active: (entityType, entityId, skip, limit, callback)->
   options = {
      entityType: entityType,
      entityId: entityId, 
      skip: skip, 
      limit: limit
    } 
    query = @optionParser(options)
    query.where('dates.start').lte(new Date())
    # query.where('dates.end').gt(new Date())
    query.sort('dates.start', -1)
    query.exec callback
    return
    
  @completed: (entityType, entityId, skip, limit, callback)->
    options = {
      entityType: entityType,
      entityId: entityId, 
      skip: skip, 
      limit: limit
    }
    query = @optionParser(options)
    # query.where('dates.end').lte(new Date())
    query.sort('dates.start', -1)
    query.exec callback
    return

  @getByEntity: (entityType, entityId, discussionId, callback)->
    @model.findOne {_id: discussionId, 'entity.type': entityType ,'entity.id': entityId}, callback
    return
    
  @setTransactonPending: @__setTransactionPending
  @setTransactionProcessing: @__setTransactionProcessing
  @setTransactionProcessed: @__setTransactionProcessed
  @setTransactionError: @__setTransactionError
    
    
class Responses extends API
  @model = Response

  @count = (entityType, businessId, discussionId, callback)->
    @model.count {'entity.id':businessId, 'entity.type':entityType, discussionId: discussionId}, (error, count)->
      callback error, count
  
      
class Medias extends API
  @model = Media
  
  @optionParser = (options, q)->
    query = @_optionParser(options, q)
    
    query.where('entity.type', options.entityType) if options.entityType?
    query.where('entity.id', options.entityId) if options.entityId?
    query.where('type', options.type) if options.type?
    query.where('guid', options.guid) if options.guid?
    query.in('tags', options.tags) if options.tags?
    query.where('uploaddate').gte(options.start) if options.start?
    query.where('uploaddate').lte(options.end) if options.end?
    
    return query

  #type is either image or video
  @getByEntity = (entityType, entityId, type, callback)->
    if Object.isFunction(type)
      callback = type
      @get {entityType: entityType, entityId: entityId}, callback
      #@get {'entity.type': choices.entities.BUSINESS, 'entity.id': entityId}, callback
    else
      @get {entityType: entityType, entityId: entityId, type: type}, callback
      #@get {'entity.type': choices.entities.BUSINESS, 'entity.id': entityId, type: type}, callback
    return

  @getByGuid = (entityType, entityId, guid, callback)->
    @get {entityType: entityType, entityId: entityId, guid: guid}, callback
    #@get {'entity.type': entityType, 'entity.id': entityId, 'media.guid': guid}, callback


class ClientInvitations extends API
  @model = ClientInvitation

  @add = (businessId, groupName, email, callback)->
    key = hashlib.md5(globals.secretWord + email+(new Date().toString()))+'-'+generatePassword(12, false, /\d/)
    @_add {businessId: businessId, groupName: groupName, email: email, key: key}, callback
  
  @validate = (key, callback)->
    @model.collection.findAndModify {key: key, status: choices.invitations.state.PENDING},[],{$set: {status: choices.invitations.state.PROCESSED}}, {new: true, safe: true}, (error, invite)->
      if error?
        callback error #db error
      else if !invite?
        callback new errors.ValidationError {"key":"Invalid Invite Key"} #invalid key error
      else
        callback null, invite #success
      return


class Tags extends API
  @model = Tag

  @add = (name, callback)->
    @_add {name: name}, callback
  
  @search = (name, callback)->
    re = new RegExp("^"+name+".*", 'i')
    query = @_query()
    query.where('name', re)
    query.limit(10)
    query.exec callback


class EventRequests extends API
  @model = EventRequest


class Events extends API
  @model = Event

  @upcomingEvents = (limit, skip, callback)->
    query = @_query()
    query.where('dates.actual').$gt Date.now()
    query.limit limit
    query.skip skip
    query.sort 'dates.actual', 1
    query.exec (error, events)->
      if error?
        callback error
      else
        callback error, events

  @soonestEvent = (callback)->
    query = @model.findOne().sort 'dates.actual', 1
    query.exec (error, event)->
      if error?
        callback error
      else
        callback error, event

  # Retrieves the next latest event not in the passed in list of eventIds
  @next = (eventIds, callback)->
    query = @model.findOne {_id: {$nin: eventIds}}
    query.sort 'dates.actual', -1
    query.exec (error, event)->
      if error?
        callback error
      else
        callback error, event

  @isUserRsvpd = (eventId, userId, callback)->
    @model.findOne {_id: eventId, rsvp: userId}, (error, event)->
      if error?
        callback error
      else
        callback error, true

  @unRsvp = (eventId, userId, callback)->
    if Object.isString eventId
      eventId = new ObjectId eventId
    if Object.isString userId
      userId = new ObjectId userId
    query = {_id: eventId}
    update = {$pop: {rsvp: userId}}
    options = {remove: false, new: true, upsert: false}
    @model.collection.findAndModify query, [], update, options, callback

  @rsvp = (eventId, userId, callback)->
    if Object.isString eventId
      eventId = new ObjectId eventId
    if Object.isString userId
      userId = new ObjectId userId

    entity = {
      type: choices.entities.CONSUMER
      id: userId
    }
    transactionData = {}
    transaction = @createTransaction choices.transactions.states.PENDING, choices.transactions.actions.EVENT_EVENT_RSVPED, transactionData, choices.transactions.directions.OUTBOUND, entity
    
    $push = {
      rsvp: userId
      "transactions.ids": transaction.id
      "transactions.log": transaction
    }
    
    $query = {_id: eventId}
    $update = {$push: $push}
    $options = {remove: false, new: true, upsert: false}
    @model.collection.findAndModify $query, [], $update, $options, (error, event)->
      callback error, event
      if !error?
        tp.process(event, transaction)

  # Get dates specified but support pagination
  @getByDateDescLimit = (params, limit, page, callback)->
    query = @model.find(params).sort 'dates.actual', 1
    query.limit limit
    query.skip(limit * page)
    query.exec callback

  @getOrderByDateDesc = (params, callback)->
    query = @model.find(params).sort 'dates.actual', -1
    query.exec callback

  @getEventsRsvpdByUser = (id, order, callback)->
    query = @_query()
    query.where 'rsvp', id
    if order == 1 || order == -1
      query.sort 'dates.actual', order
    query.exec callback

  @setTransactonPending: @__setTransactionPending
  @setTransactionProcessing: @__setTransactionProcessing
  @setTransactionProcessed: @__setTransactionProcessed
  @setTransactionError: @__setTransactionError


class Streams extends API
  @model = db.Stream

  @add = (entity, eventType, eventId, documentId, timestamp, messages, data, callback)->
    if Object.isString(messages)
      messages = [messages]
      
    if Object.isFunction(data)
      callback = data
      data = {}
    
    stream = {
      eventType : eventType
      eventId   : eventId
      entity    : entity
      documentId: documentId
      messages  : messages
      data      : data

      dates: {
        event   : timestamp
      }
    }

    instance = new @model(stream)

    instance.save callback

class TapIns extends API
  @model = db.TapIn
  
  @byUser = (userId, options, callback)->
    if Object.isFunction(options)
      callback = options
      options = {}
    query = @optionParser options
    query.where 'userEntity.id', userId
    query.exec callback

class BusinessRequest extends API
  @model = db.BusinessRequest

  @add = (userId, business, callback)->
    data =
      userEntity:
        type: choices.entities.CONSUMER
        id: userId
      businessName: business
    instance = new @model data
    instance.save callback

    
exports.Clients = Clients
exports.Consumers = Consumers
exports.Businesses = Businesses
exports.Medias = Medias
exports.Polls = Polls
exports.Discussions = Discussions
exports.Responses = Responses
exports.ClientInvitations = ClientInvitations
exports.Tags = Tags
exports.EventRequests = EventRequests
exports.Events = Events
exports.Streams = Streams
exports.TapIns = TapIns
exports.BusinessRequests = BusinessRequest
