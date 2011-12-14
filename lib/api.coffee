exports = module.exports

generatePassword = require 'password-generator'
hashlib = require 'hashlib'
util = require 'util'

db = require './db'
globals = require 'globals'
ObjectId = require('mongoose').Types.ObjectId;

utils = globals.utils
choices = globals.choices
defaults = globals.defaults
errors = globals.errors

DailyDeal = db.DailyDeal
Client = db.Client
Consumer = db.Consumer
Business = db.Business
Deal = db.Deal
Media = db.Media
FlipAd = db.FlipAd
Poll = db.Poll
Discussion = db.Discussion
Response = db.Response
ClientInvitation = db.ClientInvitation
Tag = db.Tag
EventRequest = db.EventRequest
Event = db.Event

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
        console.log 
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

  @deductFunds: (id, documentType, documentId, transactionId, amount, callback)->
    if Object.isString(id)
      id = new ObjectId(id)
    
    if Object.isString(documentId)
      documentId = new ObjectId(documentId)
      
    if Object.isString(transactionId)
      transactionId = new ObjectId(transactionId)
      
  # transactions: {
  #   ids           : [ObjectId]
  #   history       : {}
  # 
  #   # Example of transaction history object
  #   # history: {
  #   #   transactionId: { #transactionId is a string representation of the ObjectId
  #   #     document: {
  #   #       type          : {type: String, required: true, enum: choices.transactions.types._enum}
  #   #       id            : {type: ObjectId, required: true}
  #   #     }
  #   #     amount: {type: Number}
  #   #     timestamp: {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
  #   #   }
  #   # }
  # 
  # }

    transaction = {}

    transaction.document = {}
    transaction.document.type = documentType
    transaction.document.id = documentId

    transaction.amount = amount
    transaction.timestamp = new Date( (new Date()).toUTCString() )

    transactionIdStr = transactionId.toString()
    $set = {}
    $set['transactions.history.'+transactionIdStr] = transaction

    console.log {_id: id, 'funds.remaining': {$gte: amount}, 'transactions.ids': {$ne: transactionId}}
    console.log util.inspect {$set: $set, $inc: {'funds.remaining': amount }}

    @model.collection.findAndModify {_id: id, 'funds.remaining': {$gte: amount}, 'transactions.ids': {$ne: transactionId}}, [], {$set: $set, $inc: {'funds.remaining': -1*amount }}, {new: true, safe: true}, (error, business)->
      console.log error
      console.log business


class DailyDeals extends API
  @model = DailyDeal
  
  #currently only supports groupon, more abstraction needed to support more deals
  @add: (data, callback)->
    deal = new Deal();
    for own k,v of data
      deal[k] = v
    # @model.collection.update 
    delete deal.doc._id #need to delete otherwise: Mod on _id not allowed
    @model.update {did:deal['did']}, deal.doc, {upsert: true}, callback #upsert
    return
    
  @remove = (did, callback)->
    @model.remove {'did': did}, callback
    return
    
  @getDeal: (did, callback)->
    @model.findOne {did: did}, {data: 0, dislike: 0}, callback
    return
  
  #options: city, start, end, limit, skip
  @getDeals: (options, callback)->
    query = @_query()

    if typeof(options) == 'function'
      callback = options
    else
      if options.city?
        query.where('city', options.city)

      if options.start? and options.end?
        query.range options.start, options.end
      else if options.start?
        query.where('dates.start').gte(options.start)
      else if options.end?
        query.where('dates.end').lte(options.end)
      else
        query.where('dates.end').gt(new Date( (new Date()).toUTCString() ))

      if options.limit?
        query.limit(options.limit)

      if options.skip?
        query.skip(options.skip)
    query.select({data: 0, dislike: 0}).exec callback
    return

  @like: (did, user, callback)->
    voters = {}
    voters['voters.'+user] = 1
    @model.collection.update  {did: did}, {$addToSet:{like: user}, $pull:{dislike: user}, $set:voters}, callback
    return

  @dislike: (did, user, callback)->
    voters = {}
    voters['voters.'+user] = -1
    @model.collection.update  {did: did}, {$addToSet:{dislike: user}, $pull:{like: user}, $set:voters}, callback
    return

  @neutral: (did, user, callback)->
    voters = {}
    voters['voters.'+user] = 1 #for unsetting
    @model.collection.update  {did: did}, {$pull:{dislike: user, like: user}, $unset:voters}, callback
    return

    
class Polls extends API
  @model = Poll

  #options: name, businessid, type, businessname,showstats, answered, start, end, outoffunds
  @optionParser = (options, q) ->
    query = q || @_query()
    query.where('entity.type', options.entityType) if options.entityType?
    query.where('entity.id', options.entityId) if options.entityId?
    query.where('dates.start').gte(options.start) if options.start?
    query.where('dates.end').gte(options.start) if options.end?
    query.where('transaction.state', state) if options.state?
    return query
  
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
   #    currentBalance: {type: Number, required: true}
   #    newBalance    : {type: Number}
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

    instance.transactions.currentBalance = 0.0
    instance.transactions.newBalance = amount

    #console.log instance
    #console.log amount

    instance.save (error, poll)->
      callback error, poll
      if error?
        return
      else
        amount = poll.transactions.newBalance - poll.transactions.currentBalance
        Businesses.deductFunds poll.entity.id, choices.transactions.types.POLL, poll.id, poll.transactions.currentId, poll.transactions.newBalance, (error, business)->
          if error?
            return
          else
            polls.setTransactionProcessed instance.transactions.id, amount, (error, poll)->
              return
            return
    #load default transaction stuff (maybe create a separate function to do transaction setup)
    #instance.transaction.state = choices.transactions.state.PENDING #This is the default setting
    #instance.save callback
    return
  
  @update: (entityType, entityId, pollId, data, callback)->
    @getByEntity entityType, entityId, pollId, (error, poll)->
      if error?
        callback error, null
      else
        if (poll.dates.start <= new Date())
          callback {name: "DateTimeError", message: "Can not edit a poll that is in progress or has completed."}, null
        else
          for own k,v of data
            poll[k] = v
          poll.save callback
      return
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
    query.where('dates.end').gt(new Date())
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
    query.where('dates.end').lte(new Date())
    query.sort('dates.start', -1)
    query.exec callback
    return

  @answer = (pollId, consumerId, answers, callback)->
    if Object.isString(pollId)
      pollId = new ObjectId(pollId)
    if Object.isString(consumerId)
      consumerId = new ObjectId(consumerId)
    minAnswer = Math.min.apply(Math,answers)
    maxAnswer = Math.max.apply(Math,answers)
    if(minAnswer < 0 || isNaN(minAnswer) || isNaN(maxAnswer))
      callback new errors.ValidationError({"answers":"Out of Range"})
      return
    timestamp = new Date
    
    query = {
        _id               : pollId,
        numChoices        : {$gt : maxAnswer},
        "responses.consumers" : {$ne : consumerId}
    }
    inc = new Object()
    inc["responses.remaining"] = -1;
    i=0
    while i<answers.length
      inc["responses.choiceCounts."+answers[i]] = 1;
      i++
    set = new Object()
    set["responses.log."+consumerId] = {
        answers   : answers,
        timestamp : timestamp
    }
    update = {
        $inc  : inc,
        $push : {
            date  : {
                consumerId : consumerId
                timestamp  : timestamp
            }
            "responses.consumers" : consumerId,
        },
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
    fieldsToReturn["responses.log."+consumerId.toString]
    
    @model.collection.findAndModify query, [], update, {new:true, safe:true}, fieldsToReturn, (error, poll)->
      Polls.removePollPrivateFields(error, poll, callback)
    #TODO: transaction of funds.. per response gain to consumer..

  @next = (userId, callback)->
    if Object.isString(userId)
      userId = new ObjectId(userId)
    query = @_query
    query.where('responses.users').ne(userId)
    #endDate..
    #remove fields
    query.fields({
        _id           : 1,
        question      : 1,
        choices       : 1,
        displayName   : 1,
        displayMedia  : 1,
        "entity.name" : 1,
        media         : 1
    });
    query.exec (error, poll)->
      if error? || !poll?
        callback error
        return
      Polls.removePollPrivateFields(error, poll, callback)
      return

  @answered = (userId, skip, limit)->
    if Object.isString(userId)
      userId = new ObjectId(userId)
    query = $_query
    query.where('responses.users',userId)
    query.fields({
        _id           : 1,
        question      : 1,
        choices       : 1,
        displayName   : 1,
        displayMedia  : 1,
        "entity.name" : 1,
        media         : 1
    });
    query.exec (error, poll)->
      if error? || !poll?
        callback error
        return
      Polls.removePollPrivateFields(error, poll, callback)
      return

  @removePollPrivateFields = (error, polls, callback)->
    #arrayCheck
    if !Object.isArray(polls)
      if(!polls.displayName)
        delete polls.entity
      if(!polls.displayMedia)
        delete media
      if(!polls.showStats && polls.responses?)
        delete polls.responses.choiceCounts 
    else
      i=0
      while i<polls.length
        if(!polls[i].displayName)
          delete polls[i].entity
        if(!polls[i].displayMedia)
          delete media
        if(!polls[i].showStats)
          delete polls[i].responses.choiceCounts 
        i++
    callback null, polls #array or one poll
    return
    
  @setTransactionPending: (id, transactionId, callback)->
    if !callback?
      callback = error
    #convert id to objectId
    if Object.isString(id)
      id = new ObjectId(id)

    #convert id to objectId
    if Object.isString(transactionId)
      transactionId = new ObjectId(transactionId)

    transactionIdStr = transactionId.toString()

    $set: {}
    $set["transactions.currentId"] = transactionId
    $set["transactions.currentState"] = state
    $set["transactions.history."+transactionIdStr+".state"] = state
    @model.collection.findAndModify {_id: id}, [], {$set: $set}, {new: true, safe: true}, callback
    return

  @setTransactionProcessing: (id, transactionId, callback)->
    if !callback?
      callback = error
    #convert id to objectId
    if Object.isString(id)
      id = new ObjeπctId(id)

    #convert id to objectid
    if Object.isString(transactionId)
      transactionId = new ObjectId(transactionId)

    transactionIdStr = transactionId.toString()

    $set: {}
    $set["transactions.currentState"] = state
    $set["transactions.history."+transactionIdStr+".state"] = state
    @model.collection.findAndModify {_id: id}, [], {$set: $set}, {new: true, safe: true}, callback
    return

  @setTransactionProcessed: (id, transactionId, amount, callback)->
    if !callback?
      callback = error
    #convert id to objectId
    if Object.isString(id)
      id = new ObjectId(id)

    #convert id to objectId
    if Object.isString(transactionId)
      transactionId = new ObjectId(transactionId)

    transactionIdStr = transactionId.toString()

    $set: {}
    $set["transactions.currentState"] = state
    $set["transactions.history."+transactionIdStr+".state"] = state
    $set["transactions.history."+transactionIdStr+".amount"] = amount
    @model.collection.findAndModify {_id: id}, [], {$set: $set}, $inc: {"transactions.currentBalance": amount, "funds.allocated": amount, "funds.remaining": amount}, {new: true, safe: true}, callback
    return

  @setTransactionError: (id, transactionId, errorObj, callback)->
    if !callback?
      callback = error
    #convert id to objectId
    if Object.isString(id)
      id = new ObjectId(id)

    #convert id to objectId
    if Object.isString(transactionId)
      transactionId = new ObjectId(transactionId)

    transactionIdStr = transactionId.toString()

    $set: {}
    $set["transactions.currentState"] = state
    $set["transactions.history."+transactionIdStr+".error"] = errorObj
    @model.collection.findAndModify {_id: id}, [], {$set: $set}, {new: true, safe: true}, callback
    return
      
      
class Discussions extends API
  @model = Discussion

  @optionParser = (options, q)->
    query = @_optionParser(options, q)

    query.where('entity.type', options.entityType) if options.entityType?
    query.where('entity.id', options.entityId) if options.entityId?
    query.where('dates.start').gte(options.start) if options.start?
    query.where('dates.end').gte(options.start) if options.end?
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
   #    currentBalance: {type: Number, required: true}
   #    newBalance    : {type: Number}
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

    instance.transactions.currentBalance = 0.0
    instance.transactions.newBalance = amount

    instance.save (error, discussion)->
      callback error, discussion
      if error?
        return
      else
        amount = discussion.transactions.newBalance - discussion.transactions.currentBalance
        Businesses.deductFunds discussion.entity.id, choices.transactions.types.DISCUSSION, discussion.id, discussion.transactions.currentId, discussion.transactions.newBalance, (error, business)->
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
    query.where('dates.end').gt(new Date())
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
    query.where('dates.end').lte(new Date())
    query.sort('dates.start', -1)
    query.exec callback
    return

  @getByEntity: (entityType, entityId, discussionId, callback)->
    @model.findOne {_id: discussionId, 'entity.type': entityType ,'entity.id': entityId}, callback
    return

  @setTransactionPending: (id, transactionId, callback)->
    if !callback?
      callback = error
    #convert id to objectId
    if Object.isString(id)
      id = new ObjectId(id)
    
    #convert id to objectId
    if Object.isString(transactionId)
      transactionId = new ObjectId(transactionId)
    
    transactionIdStr = transactionId.toString()

    $set: {}
    $set["transactions.currentId"] = transactionId
    $set["transactions.currentState"] = state
    $set["transactions.history."+transactionIdStr+".state"] = state
    @model.collection.findAndModify {_id: id}, [], {$set: $set}, {new: true, safe: true}, callback
    return

  @setTransactionProcessing: (id, transactionId, callback)->
    if !callback?
      callback = error
    #convert id to objectId
    if Object.isString(id)
      id = new ObjeπctId(id)
    
    #convert id to objectid
    if Object.isString(transactionId)
      transactionId = new ObjectId(transactionId)
    
    transactionIdStr = transactionId.toString()

    $set: {}
    $set["transactions.currentState"] = state
    $set["transactions.history."+transactionIdStr+".state"] = state
    @model.collection.findAndModify {_id: id}, [], {$set: $set}, {new: true, safe: true}, callback
    return
  
  @setTransactionProcessed: (id, transactionId, amount, callback)->
    if !callback?
      callback = error
    #convert id to objectId
    if Object.isString(id)
      id = new ObjectId(id)
    
    #convert id to objectId
    if Object.isString(transactionId)
      transactionId = new ObjectId(transactionId)
    
    transactionIdStr = transactionId.toString()

    $set: {}
    $set["transactions.currentState"] = state
    $set["transactions.history."+transactionIdStr+".state"] = state
    $set["transactions.history."+transactionIdStr+".amount"] = amount
    @model.collection.findAndModify {_id: id}, [], {$set: $set}, $inc: {"transactions.currentBalance": amount, "funds.allocated": amount, "funds.remaining": amount}, {new: true, safe: true}, callback
    return

  @setTransactionError: (id, transactionId, errorObj, callback)->
    if !callback?
      callback = error
    #convert id to objectId
    if Object.isString(id)
      id = new ObjectId(id)
    
    #convert id to objectId
    if Object.isString(transactionId)
      transactionId = new ObjectId(transactionId)
    
    transactionIdStr = transactionId.toString()

    $set: {}
    $set["transactions.currentState"] = state
    $set["transactions.history."+transactionIdStr+".error"] = errorObj
    @model.collection.findAndModify {_id: id}, [], {$set: $set}, {new: true, safe: true}, callback
    return
    

class Responses extends API
  @model = Response

  @count = (entityType, businessId, discussionId, callback)->
    @model.count {'entity.id':businessId, 'entity.type':entityType, discussionId: discussionId}, (error, count)->
      callback error, count


class FlipAds extends API
  @model = FlipAd

  @optionParser = (options, q)->
    query = @_optionParser(options, q)

    query.where('entity.type', options.entityType) if options.entityType?
    query.where('entity.id', options.entityId) if options.entityId?
    query.where('dates.start').gte(options.start) if options.start?
    query.where('dates.end').gte(options.start) if options.end?
    query.where('transaction.state', state) if options.state?
    
    return query

  @add = (data, callback)->
    instance = new @model(data)
    
    #load default transaction stuff (maybe create a separate function to do transaction setup)
    #instance.transaction.state = choices.transactions.state.PENDING #This is the default setting
    instance.save callback
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
    query.where('dates.end').gt(new Date())
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
    query.where('dates.end').lte(new Date())
    query.sort('dates.start', -1)
    query.exec callback
    return
  
  @updateUrlByGuid: (entityType, entityId, guid, url, thumb, callback)->
    @model.collection.update  {'entity.type': entityType, 'entity.id': entityId, 'media.guid': guid}, {$set:{'media.url': url, 'media.thumb': thumb}}, {safe: true}, callback
    return


class Deals extends API
  @model = Deal

  @optionParser = (options, q)->
    query = @_optionParser(options, q)

    query.where('entity.type', options.entityType) if options.entityType?
    query.where('entity.id', options.entityId) if options.entityId?
    query.where('dates.start').gte(options.start) if options.start?
    query.where('dates.end').gte(options.start) if options.end?
    query.where('transaction.state', state) if options.state?
    
    return query

  @add = (data, callback)->
    switch data.type
      when choices.deals.type.VOUCHER
        if utils.isBlank(data.item)
          callback new errors.ValidationError {"item":"required"}
          return
      
      when choices.deals.type.BXGXF
        if utils.isBlank(data.item)
          callback new errors.ValidationError {"item":"required"}
          return
        if utils.isBlank(data.item2)
          callback new errors.ValidationError {"item2":"required"}
          return
          
      when choices.deals.type.PERCENT_ALL
        if utils.isBlank(data.discount) || parseInt(data.discount) > 100
          callback new errors.ValidationError {"discount":["required", "invalid"]}
          return
      
      when choices.deals.type.PERCENT_MIN
        if utils.isBlank(data.discount) || parseInt(data.discount) > 100
          callback new errors.ValidationError {"discount":["required", "invalid"]}
          return
      
      when choices.deals.type.PERCENT_ITEM
        if utils.isBlank(data.item)
          callback new errors.ValidationError {"item":"required"}
          return
        if utils.isBlank(data.discount) || parseInt(data.discount) > 100
          callback new errors.ValidationError {"discount":"required"}
          return
        
      when choices.deals.type.DOLLAR_ALL
        if utils.isBlank(data.discount) || parseFloat(data.discount) > parseFloat(data.value)
          callback new errors.ValidationError {"discount":["required","invalid"]}
          return
      
      when choices.deals.type.DOLLAR_MIN
        if utils.isBlank(data.discount) || parseFloat(data.discount) > parseFloat(data.value)
          callback new errors.ValidationError {"discount":["required","invalid"]}
          return
      
      when choices.deals.type.DOLLAR_ITEM
        if utils.isBlank(data.item)
          callback new errors.ValidationError {"item":"required"}
          return
        if utils.isBlank(data.discount) || parseFloat(data.discount) > parseFloat(data.value)
          callback new errors.ValidationError {"discount":["required","invalid"]}
          return

    instance = new @model(data)
    
    #load default transaction stuff (maybe create a separate function to do transaction setup)
    #instance.transaction.state = choices.transactions.state.PENDING #This is the default setting
    instance.save callback
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
    query.where('dates.end').gt(new Date())
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
    query.where('dates.end').lte(new Date())
    query.sort('dates.start', -1)
    query.exec callback
    return

  @updateMediaUrlByGuid: (entityType, entityId, guid, url, thumb, callback)->
    @model.collection.update  {'entity.type': entityType, 'entity.id': entityId, 'media.guid': guid}, {$set:{'media.url': url, 'media.thumb': thumb}}, {safe: true}, callback
    return


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

  # Retrieves the next latest event not in the passed in list of eventIds
  @next = (eventIds, callback)->
    query = @model.findOne {_id: {$nin: eventIds}}
    query.sort 'dates.actual', -1
    query.exec (error, event)->
      if error?
        callback error
      else
        callback error, event

  @one = (eventId, callback)->
    @model.findOne {_id: eventId}, (error, event)->
      if error?
        callback error
      else
        callback error, event

  @unRsvp = (eventId, userId, callback)->
    @model.findOne {_id: eventId}, (error, event)->
      if error?
        callback error
      else
        index = event.rsvp.indexOf(userId)
        if index == -1
          callback error, event
        else
          event.rsvp.splice index, 1
          if event.rsvpUsers[userId]?
            delete event.rsvpUsers[userId]
          event.save callback

  @rsvp = (eventId, userId, callback)->
    @model.findOne {_id: eventId}, (error, event)->
      if error?
        callback error
      else
        # Just return the event as if we were saving if it's already in the list
        if event.rsvp.indexOf(userId) > -1
          callback error, event
        else
          event.rsvp.push userId
          event.rsvpUsers[userId] = true
          event.save callback

  # Get dates specified but support pagination
  @getByDateDescLimit = (params, limit, page, callback)->
    query = @model.find(params).sort 'dates.actual', -1
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

exports.Clients = Clients
exports.Consumers = Consumers
exports.Businesses = Businesses
exports.Medias = Medias
exports.FlipAds = FlipAds
exports.Polls = Polls
exports.Discussions = Discussions
exports.Responses = Responses
exports.Deals = Deals
exports.DailyDeals = DailyDeals
exports.ClientInvitations = ClientInvitations
exports.Tags = Tags
exports.EventRequests = EventRequests
exports.Events = Events