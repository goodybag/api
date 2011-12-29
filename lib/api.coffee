exports = module.exports

generatePassword = require "password-generator"
hashlib = require "hashlib"
util = require "util"
async = require "async"
wwwdude = require "wwwdude"

globals = require "globals"
loggers = require "./loggers"

db = require "./db"
tp = require "./transactions" #transaction processor 

logger = loggers.api

utils = globals.utils
choices = globals.choices
defaults = globals.defaults
errors = globals.errors

ObjectId = globals.mongoose.Types.ObjectId;

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
PasswordResetRequest = db.PasswordResetRequest

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

  @del = @remove

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
  
  @getByEntity: (entityType, entityId, id, fields, callback)->
    if Object.isFunction(fields)
      callback=fields
      @model.findOne {_id: id, 'entity.type': entityType ,'entity.id': entityId}, callback
    else
      @model.findOne {_id: id, 'entity.type': entityType ,'entity.id': entityId}, fields, callback
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

    console.log $update

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
      $set["transactions.state"] = choices.transactions.states.ERROR

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

  @one: (consumerId, callback)->
    self = this
    super.one consumerId (error, consumer)->
      if error?
        callback error #eventually we will be changing these db errors..so leave the if error .. else
      else
        callback null, consumer

  @facebookLogin: (accessToken, callback)->
    self = this
    accessToken = accessToken.split("&")
    wwwClient = wwwdude.createClient({
        contentParser: wwwdude.parsers.json
    })
    wwwClient.get("https://graph.facebook.com/me?access_token="+accessToken)
    .on('success', (facebookData, res)->
      if(facebookData.error?)
        callback new errors.ValidationError {"facebook":facebookData.error.type+": "+facebookData.error.message}
      else
        fbid = facebookData.id
        consumer = {
          firstName: facebookData.first_name,
          lastName:  facebookData.last_name,
          email:     facebookData.email,
          facebook: {
              me           : facebookData,
              access_token : accessToken,
              id           : fbid
          }
        }
        #self.model.update {"facebook.id": fbid}, {$set: consumer, $inc: {loginCount:1}}, {}, (error, success)->
        self.model.collection.findAndModify {"facebook.id": fbid}, [], {$set: consumer, $inc: {loginCount:1}}, {new:true, safe:true}, (error, consumerUpdated)->
          if error?
            callback error
          else if consumerUpdated? #if success>0
            callback null, consumerUpdated #streamlined process for returning logins..
          else
            query = self._query()
            query.where("email", facebookData.email) #email account with
            query.where("facebook").exists(false)    #no facebook
            query.findOne (error, consumerWithEmail)->
              if error?
                callback error
              else if consumerWithEmail?
                callback new errors.ValidationError {"email":"Account with email already exists, please enter password."}
              else
                #self.model.update {"facebook.id": fbid}, {$set: consumer, $inc: {loginCount:1}}, {}, (error, success)->
                consumerModel = new self.model consumer
                consumerModel.save consumer, (error, success)->
                  if error?
                    callback error
                  else #success is true
                    callback null, consumer #slow process...for new fb regs..
                  return
          return
      return
    ).on('error', (error, res)->
      callback error
      return
    ).on('http-error', (data, res)->
      if(data.error?)
        callback new errors.ValidationError {"facebook":data.error.type+": "+data.error.message}
      else
        callback new errors.ValidationError {"http":"HTTP Error"}
      return
    )
    return

  @register: (email, password, callback)->
    self = this
    query = @_query()
    query.where('email', email)
    query.update {$push:{"responses.skipConsumers":consumerId},$inc:{"responses.skipCount":1}}, (error, success)->

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

  @updatePassword: (id, password, callback)->
    if Object.isString(id)
      id = new ObjectId(id)
    
    query = {_id: id}
    update = {$set: {password: password}}
    options = {remove: false, new: true, upsert: false}
    @model.collection.findAndModify query, [], update, options, (error, user)->
      if error?
        callback error
        return
      if !user?
        callback new errors.ValidationError {"_id": "_id does not exist"}
        return
      if user?
        callback error, user
      return


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
      return
    return

  @updateEmail: (clientId, password, newEmail, callback)->
    if(Object.isString(clientId))
      clientId = new ObjectId( clientId)
    Clients.getByEmail newEmail, (error, client)->
      if error?
        callback error
        return
      if client?
        if client._id == clientId
          callback new errors.ValidationError({"email":"That is your current email"})
        else
          callback new errors.ValidationError({"email":"Another user is already using this email"}) #email exists error
        return
      query = Clients._query()
      query.where("_id",clientId)
      query.where("password",password)
      changeEmailKey = hashlib.md5(globals.secretWord + newEmail+(new Date().toString()))+'-'+generatePassword(12, false, /\d/)
      set = {
        changeEmail: {
          newEmail: newEmail
          key: changeEmailKey
          expirationDate: Date.create("next week")
        }
      }
      query.update {$set:set}, (error, success)->
        if error?
          callback error
          return
        if !success
          callback new errors.ValidationError({"password":"Incorrect Password."})
          return
        url = "https://goodybag.com/#!/change-email/" + changeEmailKey
        message = '<p>We got your request! Now let\'s get that email updated. Click or go here:</p>'
        message += "<p><a href=\"#{ url }\">#{ url }</a></p>"
        utils.sendMail {
            sender: 'info@goodybag.com',
            to: newEmail,
            reply_to: 'info@goodybag.com',
            subject: "Change Email Request",
            html: message,
          }, (error, emailSent)->
            if error?
              callback new errors.EmailError("Confirmation email failed to send.","ChangeEmail")
              return
            callback null, success
            return
      return  
    return

  @updateEmailComplete: (key, callback)->
    query = @_query()
    query.where('changeEmail.key', key)
    query.fields("changeEmail")
    query.findOne (error, client)->
      if error?
        callback error #dberror
        return
      if !client? || !client.changeEmail?
        callback new errors.ValidationError({"key":"Invalid key or already used."})
        return
      #client found
      if(new Date()>client.changeEmail.expirationDate)
        callback new errors.ValidationError({"key":"Key expired."})
        return
      query.update {$set:{email:client.changeEmail.newEmail, changeEmail:null}}, (error, success)->
        if error?
          callback error #dberror
        else
          callback null, success


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

  @updatePassword: (id, password, callback)->
    if Object.isString(id)
      id = new ObjectId(id)
    
    query = {_id: id}
    update = {$set: {password: password}}
    options = {remove: false, new: true, upsert: false}
    @model.collection.findAndModify query, [], update, options, (error, user)->
      if error?
        callback error
        return
      if !user?
        callback new errors.ValidationError {"_id": "_id does not exist"}
        return
      if user?
        callback error, user
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

  @getGroupPending: (id, groupName, callback)->
    ClientInvitations.list id, groupName, callback
    
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

    transaction = @createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.POLL_CREATED, transactionData, choices.transactions.directions.INBOUND, instance.entity)
    
    instance.transactions.state = choices.transactions.states.PENDING #soley for reading purposes
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

  @update: (pollId, data, newAllocated, perResponse, callback)->
    self = this

    instance = new @model(data)

    if Object.isString(pollId)
      pollId = new ObjectId(pollId)
    if Object.isString(data.entity.id)
      data.entity.id = new ObjectId(data.entity.id)
    entityType = data.entity.type
    entityId = data.entity.id
    
    #Set the fields you want updated now, not afte the update
    #for the ones that you want set after the update put those
    #in the transactionData and make thsoe changes in the
    #setTransactionProcessed function

    updateDoc = {
      entity: {
        type          : data.entity.type
        id            : data.entity.id
        name          : data.entity.name
      }
      name            : data.name
      type            : data.type
      question        : data.question
      choices         : data.choices
      numChoices      : parseInt(data.numChoices)
      responses: {
        remaining     : parseInt(data.responses.max)
        max           : parseInt(data.responses.max)
        log           : data.responses.log
        dates         : data.responses.dates
        choiceCounts  : data.responses.choiceCounts
      } 
      showStats       : data.showStats
      displayName     : data.displayName
      displayMedia    : data.displayMedia

      media: {
        when          : data.media.when
        url           : data.media.url
        thumb         : data.media.thumb
        guid          : data.media.guid
      }
    }
    

    entity = {
      type: data.entity.type
      id: data.entity.id
    }

    transactionData = {
      newAllocated: newAllocated
      perResponse: perResponse
    }
    transaction = self.createTransaction choices.transactions.states.PENDING, choices.transactions.actions.POLL_UPDATED, transactionData, choices.transactions.directions.INBOUND, entity
    
    $set = {
      "dates.start": new Date(data.dates.start) #this is so that we don't lose the create date
      "transactions.locked": true #THIS IS A LOCKING TRANSACTION, SO IF ANYONE ELSE TRIES TO DO A LOKCING TRANSACTION IT WILL NOT HAPPEN (AS LONG AS YOU CHECK FOR THAT)
      "transactions.state": choices.transactions.states.PENDING
    }
    $push = {
      "transactions.ids": transaction.id
      "transactions.log": transaction
    }

    logger.info data

    for own k,v of updateDoc
      console.log k
      $set[k] = v

    $update = {
      $set: $set
      $push: $push
    }

    console.log $update

    @model.collection.findAndModify {_id: pollId, "entity.type":entityType, "entity.id":entityId, "transactions.locked": false}, [], $update, {safe: true, new: true}, (error, poll)->
      if error?
        callback error, null
      else if !poll?
        callback new errors.ValidationError({"poll":"Poll does not exist or Access Denied."})
      else
        callback null, poll
        tp.process(poll, transaction)
    return

  @list: (entityType, entityId, stage, options, callback)->
    #options: count(boolean)-to return just the count, skip(int), limit(int)
    query = @_query()
    query.where("entity.type", entityType)
    query.where("entity.id", entityId)
    switch stage 
      when "active"
        query.where('responses.remaining').gt(0)   #has responses remaining..
        query.where('dates.start').lte(new Date())
        query.where('transactions.state').ne(choices.transactions.states.ERROR)
        query.where("deleted").ne(true)
        fieldsToReturn = {
            _id                   : 1,
            name                  : 1,
            question              : 1,
            "responses.remaining" : 1,
            "responses.max"       : 1,
            dates                 : 1,
            "transactions.state"  : 1
        }
      when "future"
        query.where('dates.start').gt(new Date())
        query.where('responses.remaining').gt(0)
        query.where('transactions.state').ne(choices.transactions.states.ERROR)
        query.where("deleted").ne(true)
        fieldsToReturn = {
            _id                   : 1,
            name                  : 1,
            question              : 1,
            dates                 : 1,
            "transactions.state"  : 1
        }
      when "completed"
        query.where('responses.remaining').lte(0)
        query.where('transactions.state').ne(choices.transactions.states.ERROR)
        query.where("deleted").ne(true)
        fieldsToReturn = {
            _id                   : 1,
            name                  : 1,
            question              : 1,
            "responses.remaining" : 1,
            "responses.max"       : 1,
            dates                 : 1,
            "transactions.state"  : 1,
            "funds.allocated"     : 1
        }
      when "errored"
        query.where('transactions.state', choices.transactions.ERROR)
        fieldsToReturn = {
            _id                   : 1,
            name                  : 1,
            question              : 1,
            "responses.remaining" : 1,
            "responses.max"       : 1,
            dates                 : 1,
            "transactions.state"  : 1,
            "funds.allocated"     : 1
        }
      else # "all"
        fieldsToReturn = {
            _id                   : 1,
            name                  : 1,
            question              : 1,
            "responses.remaining" : 1,
            "responses.max"       : 1,
            dates                 : 1,
            "transactions.state"  : 1,
            "funds.allocated"     : 1
        }
    if !options.count
      query.sort("dates.start", -1)
      query.fields(fieldsToReturn); 
      query.skip(options.skip)
      query.limit(options.limit)
      query.exec callback
    else
      query.count callback
    return
  
  @del: (entityType, entityId, pollId, callback)->
    self = this
    if Object.isString(entityId)
      entityId = new ObjectId(entityId)
    if Object.isString(pollId)
      pollId = new ObjectId(pollId)

    entity = {}
    transactionData = {}
    transaction = self.createTransaction choices.transactions.states.PENDING, choices.transactions.actions.POLL_DELETED, transactionData, choices.transactions.directions.OUTBOUND, entity
    
    $set = {
      "deleted": true
      "transactions.locked": true #THIS IS A LOCKING TRANSACTION, SO IF ANYONE ELSE TRIES TO DO A LOKCING TRANSACTION IT WILL NOT HAPPEN (AS LONG AS YOU CHECK FOR THAT)
      "transactions.state": choices.transactions.states.PENDING
    }
    $push = {
      "transactions.ids": transaction.id
      "transactions.log": transaction
    }

    $update = {
      $set: $set
      $push: $push
    }

    @model.collection.findAndModify {"entity.type":entityType, "entity.id":entityId, _id: pollId, "transactions.locked": false, "deleted": false}, [], $update, {safe: true, new: true}, (error, poll)->
      if error?
        logger.error "POLLS - DELETE: unable to findAndModify"
        logger.error error
        callback error, null
      else if !poll?
        logger.warn "POLLS - DELETE: no document found to modify"
        callback new errors.ValidationError({"poll":"Poll does not exist or Access Denied."})
      else
        logger.info "POLLS - DELETE: findAndModify succeeded, transaction starting"
        callback null, poll
        tp.process(poll, transaction)
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
        transaction = self.createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.POLL_ANSWERED, transactionData, choices.transactions.directions.OUTBOUND, entity)
    
        push["transactions.ids"] = transaction.id
        push["transactions.log"] = transaction
        inc["funds.remaining"] = -1*perResponse

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
            "transactions.state"      : choices.transactions.states.PROCESSED #poll is processed and ready to launch
            "deleted"                 : false
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
      callback null, results.save
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
    query.where('transactions.state',choices.transactions.states.PROCESSED)    #poll is processed (paid for) and ready to launch

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
    query.where('transactions.state',choices.transactions.states.PROCESSED)    #poll is processed (paid for) and ready to launch

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
    query.where('transactions.state',choices.transactions.states.PROCESSED)    #poll is processed (paid for) and ready to launch
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
      #Polls.removePollPrivateFields(poll)
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

    transactionData = {
      amount: amount
    }

    transaction = @createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.DISCUSSION_CREATED, transactionData, choices.transactions.directions.INBOUND, instance.entity)
    
    instance.transactions.locked = true
    instance.transactions.ids = [transaction.id]
    instance.transactions.log = [transaction]

    console.log instance.transactions.log
    instance.save (error, discussion)->
      callback error, discussion
      if error?
        return
      else
        tp.process(discussion, transaction)
    return
    
  @list: (entityType, entityId, stage, options, callback)->
    #options: count(boolean)-to return just the count, skip(int), limit(int)
    query = @_query()
    query.where("entity.type", entityType)
    query.where("entity.id", entityId)
    switch stage 
      when "active"
        query.where("funds.remaining").gte(0)
        query.where("dates.start").lte(new Date())
        query.where('transactions.state').ne(choices.transactions.states.ERROR)
        query.where("deleted").ne(true)
        fieldsToReturn = {
            _id                  : 1,
            name                 : 1,
            question             : 1,
            "responses.count"    : 1,
            dates                : 1,
            funds                : 1,
            "transactions.state" : 1
        }
      when "future"
        query.where("funds.remaining").gte(0)
        query.where('dates.start').gt(new Date())
        query.where('transactions.state').ne(choices.transactions.states.ERROR)
        query.where("deleted").ne(true)
        fieldsToReturn = {
            _id                  : 1,
            name                 : 1,
            question             : 1,
            dates                : 1,
            funds                : 1,
            "transactions.state" : 1
        }
      when "completed"
        query.where("funds.remaining").lte(0)
        query.where('transactions.state').ne(choices.transactions.states.ERROR)
        query.where("deleted").ne(true)
        fieldsToReturn = {
            _id                  : 1,
            name                 : 1,
            question             : 1,
            "responses.count"    : 1,
            dates                : 1,
            funds                : 1,
            "transactions.state" : 1
        }
      when "errored"
        query.where('transactions.state', choices.transactions.states.ERROR)
        fieldsToReturn = {
            _id                   : 1,
            name                  : 1,
            question              : 1,
            dates                 : 1,
            "transactions.state"  : 1,
            "funds.allocated"     : 1
        }
      else # "all"
        fieldsToReturn = {
            _id                   : 1,
            name                  : 1,
            question              : 1,
            "responses.count"     : 1,
            dates                 : 1,
            "transactions.state"  : 1,
            "funds.allocated"     : 1
        }
    if !options.count
      query.sort("dates.start", -1)
      query.fields(fieldsToReturn)
      query.skip(options.skip)
      query.limit(options.limit)
      query.exec callback
    else
      query.count callback
    return
  
  @del: (entityType, entityId, discussionId, callback)->
    self = this
    if Object.isString(entityId)
      entityId = new ObjectId(entityId)
    if Object.isString(discussionId)
      discussionId = new ObjectId(discussionId)

    entity = {}
    transactionData = {}
    transaction = self.createTransaction choices.transactions.states.PENDING, choices.transactions.actions.POLL_DELETED, transactionData, choices.transactions.directions.OUTBOUND, entity
    
    $set = {
      "deleted": true
      "transactions.locked": true #THIS IS A LOCKING TRANSACTION, SO IF ANYONE ELSE TRIES TO DO A LOKCING TRANSACTION IT WILL NOT HAPPEN (AS LONG AS YOU CHECK FOR THAT)
      "transactions.state": choices.transactions.states.PENDING
    }
    $push = {
      "transactions.ids": transaction.id
      "transactions.log": transaction
    }

    $update = {
      $set: $set
      $push: $push
    }

    @model.collection.findAndModify {"entity.type":entityType, "entity.id":entityId, _id: discussionId, "transactions.locked": false, "deleted": false}, [], $update, {safe: true, new: true}, (error, discussion)->
      if error?
        logger.error "DISCUSSIONS - DELETE: unable to findAndModify"
        logger.error error
        callback error, null
      else if !discussion?
        logger.warn "DISCUSSIONS - DELETE: no document found to modify"
        callback new errors.ValidationError({"discussion":"Discussion does not exist or Access Denied."})
      else
        logger.info "DISCUSSIONS - DELETE: findAndModify succeeded, transaction starting"
        callback null, discussion
        tp.process(discussion, transaction)
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
  
  @list = (businessId, groupName, callback)->
    query = @_query()
    query.where("businessId", businessId)
    query.where("groupName", groupName)
    query.fields({
      email: 1
    })
    query.exec callback
  
  @validate = (key, callback)->
    @model.collection.findAndModify {key: key, status: choices.invitations.state.PENDING},[],{$set: {status: choices.invitations.state.PROCESSED}}, {new: true, safe: true}, (error, invite)->
      if error?
        callback error #db error
      else if !invite?
        callback new errors.ValidationError {"key":"Invalid Invite Key"} #invalid key error
      else
        callback null, invite #success
      return
  
  @del = (businessId, groupName, pendingId, callback)->
    query = @_query()
    query.where("businessId", businessId)
    query.where("groupName", groupName)
    query.where("_id", pendingId)
    query.remove(callback)

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

class BusinessTransaction extends API
  @model = db.BusinessTransaction
  
  @byUser = (userId, options, callback)->
    if Object.isFunction options
      callback = options
      options = {}
    query = @optionParser options
    query.where 'userEntity.id', userId
    query.exec callback

  @byBusiness = (businessId, options, callback)->
    if Object.isFunction options
      callback = options
      options = {}
    query = @optionParser options
    query.where 'organizationEntity.id', businessId
    query.exec callback

class BusinessRequests extends API
  @model = BusinessRequest

  @add = (userId, business, callback)->
    data =
      userEntity:
        type: choices.entities.CONSUMER
        id: userId
      businessName: business
    instance = new @model data
    instance.save callback

    
class Streams extends API
  @model = Stream

  @add = (entity, eventType, eventId, documentId, timestamp, message, data, callback)->
    if Object.isString(message)
      message = message
      
    if Object.isFunction(data)
      callback = data
      data = {}
    
    stream = {
      eventType : eventType
      eventId   : eventId
      entity    : entity
      documentId: documentId
      message   : message
      data      : data

      dates: {
        event   : timestamp
      }
    }

    instance = new @model(stream)

    instance.save callback

  @getLatest = (entity, limit, offset, callback)->
    query = @_query()
    query.limit limit
    query.skip offset
    query.sort "dates.event", -1
    if entity?
      query.where "entity.type", entity.type
      query.where "entity.id", entity.id

    query.exec (error, activities)->
      if error?
        callback error
        return
      else if activities.length <=0
        callback error, {activities: [], consumers: []}
        return

      ids = []
      for activity in activities
        ids.push {_id: activity.entity.id}

      # get the consumer's name, and other info if we need it
      # currently only getting consumers, I will need to modify this to support
      # both consumers and businesses, because businesses will also answer do
      # things on the consumer side
      cQuery = Consumers._query()
      cQuery.or ids
      cQuery.only "email"
      cQuery.exec (error, consumers)->
        if error?
          callback error
          return
        callback error, {activities: activities, consumers: consumers}
      
class PasswordResetRequests extends API
  @model: PasswordResetRequest

  @consume: (id, callback)->
    if Object.isString(id)
      id = new ObjectId(id)
    
    query = {_id: id}
    update = {$set: {consumed: true}}
    options = {remove: false, new: true, upsert: false}
    @model.collection.findAndModify query, [], update, options, (error, request)->
      if error?
        callback error
        return
      if !request?
        callback new errors.ValidationError {"_id": "_id does not exist"}
        return
      if request?
        callback error, request
      return

  @pending: (key, callback)->
    minutes = new Date().getMinutes()
    minutes -= globals.defaults.passwordResets.keyLife
    date = new Date()
    date.setMinutes minutes
    options =
      key: key
      date: {$gt: date}
      consumed: false
    @model.findOne options, callback

  @add: (type, email, callback)->
    # determine user type
    if type == choices.entities.CONSUMER
      userModel = Consumers.model
    else if type == choices.entities.CLIENT
      userModel = Clients.model
    else
      callback new errors.ValidationError {
        "type": "Not a valid entity type."
      }
      return
      # find the user
    userModel.findOne {email: email}, (error, user)=>
      if error?
        callback error
        return
      #found the user now submit the request
      request =
        entity:
          type: type
          id: user._id
        key: hashlib.md5(globals.secretWord+email+(new Date().toString()))
      instance = new @model request
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
exports.BusinessRequests = BusinessRequests
exports.PasswordResetRequests = PasswordResetRequests
