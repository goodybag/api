exports = module.exports

bcrypt = require "bcrypt"
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

ObjectId = globals.mongoose.Types.ObjectId

DBTransaction = db.DBTransaction
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
BusinessTransaction = db.BusinessTransaction
BusinessRequest = db.BusinessRequest
PasswordResetRequest = db.PasswordResetRequest
Statistic = db.Statistic

#TODO:
#Make sure that all necessary fields exist for each function before sending the query to the db


 ## API ##
class API
  @model = null
  constructor: ()->
    #nothing to say

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

  @remove = (id, callback)->
    return @_remove(id, callback)

  @_remove = (id, callback)->
    @model.remove {'_id': id}, callback
    return

  @del = @remove

  @one: (id, callback)->
    return @_one(id, callback)

  @_one: (id, callback)->
    @model.findOne {_id: id}, callback
    return

  @get: (options, callback)->
    query = @optionParser(options)
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
    if Object.isString(entity.id)
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
      entity: entity
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


## DBTransactions ##
class DBTransactions extends API
  @model = DBTransaction


## Consumers ##
class Consumers extends API
  @model = Consumer

  # List all consumers (limit to 25 at a time for now - not taking in a limit arg on purpose)
  @getIdsAndScreenNames: (skip, callback)->
    query = @query()
    query.only("_id", "screenName")
    query.skip(skip || 0)
    query.limit(25)
    query.exec callback

  @getScreenNamesByIds: (ids, callback)->
    query = @query()
    query.only("_id", "screenName")
    query.in("_id", ids)
    query.exec callback

  @getByBarcodeId: (barcodeId, callback)->
    query = @queryOne()
    query.where("barcodeId", barcodeId)
    query.exec callback

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
                #self.model.update {'facebook.id': fbid}, {$set: consumer, $inc: {loginCount:1}}, {}, (error, success)->
                consumerModel = new self.model(consumer)
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

  @register: (data, callback)->
    self = this
    bcrypt.gen_salt 10, (error, salt)=>
      if error?
        callback error
        return
      bcrypt.encrypt data.password+defaults.passwordSalt, salt, (error, hash)=>
        if error?
          callback error
          return
        data.password = hash
        self.add data, (error, consumer)->
          if error?
            if error.code is 11000
              callback new errors.ValidationError "Email Already Exists", {"email":"Email Already Exists"} #email exists error
              return
            else
              callback error
              return
          else
            callback error, consumer
            return

  @login: (email, password, callback)->
    query = @_query()
    query.where('email', email)#.where('password', password)
    query.findOne (error, consumer)->
      if error?
        callback error, consumer
        return
      else if consumer?
        if !consumer.password? #if there is no pasword set then they are a facebook user
          callback new errors.ValidationError "Please authenticate via Facebook", {"login":"invalid authentication mechanism - use facebook"}
          return
        bcrypt.compare password+defaults.passwordSalt, consumer.password, (error, success)->
          if error? or !success
            callback new errors.ValidationError "Invalid Password", {"login":"invalid password"}
            return
          else
            callback error, consumer
            return
      else
        callback new errors.ValidationError "Invalid Email Address", {"login":"invalid email address"}
        return

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

  @setTransactonPending: @__setTransactionPending
  @setTransactionProcessing: @__setTransactionProcessing
  @setTransactionProcessed: @__setTransactionProcessed
  @setTransactionError: @__setTransactionError


## Clients ##
class Clients extends API
  @model = Client

  @validatePassword: (id, password, callback)->
    if(Object.isString(id))
      id = new ObjectId(id)

    query = @_query()
    query.where('_id', id)
    query.fields(['password'])
    query.findOne (error, client)->
      if error?
        callback error, client
        return
      else if client?
        bcrypt.compare password+defaults.passwordSalt, client.password, (error, valid)->
          if error?
            callback (error)
            return
          else
            if valid
              callback(null, true)
              return
            else
              callback(null, false)
              return
      else
        callback new error.ValidationError "Invalid id", {"id", "invalid"}
        return

  @encryptPassword:(password, callback)->
    bcrypt.gen_salt 10, (error, salt)=>
      if error?
        callback error
        return
      bcrypt.encrypt password+defaults.passwordSalt, salt, (error, hash)=>
        if error?
          callback error
          return
        callback null, hash
        return

  @register: (data, callback)->
    self = this
    @encryptPassword data.password, (error, hash)->
      if error?
        callback new errors.ValidationError "Invalid Password", {"password":"Invalid Password"} #error encrypting password, so fail
        return
      else
        data.password = hash
        self.add data, (error, client)->
          if error?
            if error.code is 11000
              callback new errors.ValidationError "Email Already Exists", {"email":"Email Already Exists"} #email exists error
              return
            else
              callback error
              return
          else
            callback error, client
            return

  @login: (email, password, callback)->
    query = @_query()
    query.where('email', email)#.where('password', password)
    query.findOne (error, client)->
      if error?
        callback error, client
        return
      else if client?
        bcrypt.compare password+defaults.passwordSalt, client.password, (error, success)->
          if error? or !success
            callback new errors.ValidationError "Incorrect Password.", {"login":"passwordincorrect"} #do not update this error without updating the frontend javascript
            return
          else
            callback error, client
            return
      else
        callback new errors.ValidationError "Email address not found.", {"login":"emailnotfound"} #do not update this erro without updating the frontend javascript
        return

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

  @updateMedia: (id, guid, data, callback)->
    if(Object.isString(id))
      id = new ObjectId(id)
    if(Object.isString(data.mediaId))
      data.mediaId = new ObjectId(data.mediaId)

    query = @_query()
    query.where("_id", id)
    query.where("media.guid", guid)

    set = {}
    set["media.thumb"] = data.thumb
    set["media.url"] = data.url
    set["media.mediaId"] = data.mediaId
    set["media.guid"] = data.guid #reset

    query.update {$set:set}, (error, success)->
      if error?
        callback error #dberror
      else
        callback null, success
      return
    return

  @updateEmail: (id, password, newEmail, callback)->
    if(Object.isString(id))
      id = new ObjectId(id)

    async.parallel {
      validatePassword: (cb)->
        Clients.validatePassword id, password, (error, success)->
          if error?
            e = new errors.ValidationError("Unable to validate password",{"password":"Unable to validate password"})
            callback(e)
            cb(e)
            return
          else
            if !success?
              e = new errors.ValidationError("Incorrect Password.",{"password":"Incorrect Password"})
              callback(e)
              cb(e)
              return
            else
              cb(null)
              return

      checkExists: (cb)->
        Clients.getByEmail newEmail, (error, client)->
          if error? #db error
            callback(error)
            cb(error)
            return
          else if client? #email address already in use by a user
            if client._id == id
              e = new errors.ValidationError("That is your current email",{"email": "That is your current email"})
              callback(e)
              cb(e)
              return
            else
              e = new errors.ValidationError("Another user is already using this email",{"email": "Another user is already using this email"}) #email exists error
              callback(e)
              cb(e)
              return
          else #doesn't exist, so proceed
            cb(null)
            return

    },
    (error, results)->
      if error?
        return

      #the new email address requires verification
      query = Clients._query()
      query.where("_id", id)
      key = hashlib.md5(globals.secretWord + newEmail+(new Date().toString()))+'-'+generatePassword(12, false, /\d/)
      set = {
        changeEmail: {
          newEmail: newEmail
          key: key
          expirationDate: Date.create("next week")
        }
      }
      query.update {$set:set}, (error, success)->
        if error?
          if error.code is 11000
            callback new errors.ValidationError "Email Already Exists", {"email": "Email Already Exists"} #email exists error
            return
          else
            callback error
            return
        else if !success
          callback new errors.ValidationError "User Not Found", {"user": "User Not Found"} #email exists error
          return
        else
          callback(null, key)
          return

  @updateEmailComplete: (key, email, callback)->
    query = @_query()
    query.where('changeEmail.key', key)
    query.where('changeEmail.newEmail', email)
    query.update {$set:{email:email}, $unset: {changeEmail: 1}}, (error, success)->
      if error?
        if error.code is 11000
          callback new errors.ValidationError "Email Already Exists", {"email": "Email Already Exists"} #email exists error
        else
          callback error
        return
      if success==0
        callback "Invalid key, expired or already used.", new errors.ValidationError({"key":"Invalid key, expired or already used."})
        return
      #success
      callback null, success
      return

  @updateWithPassword: (id, password, data, callback)->
    if Object.isString(id)?
      id = new ObjectId(id)

    @validatePassword id, password, (error, success)->
      if error?
        logger.error error
        e = new errors.ValidationError({"password":"Unable to validate password"})
        callback(e)
        return
      else if !success?
        e = new errors.ValidationError({"password":"Invalid Password"})
        callback(e)
        return

      async.series {
        encryptPassword: (cb)->#only if the user is trying to update their password field
          if data.password?
            Clients.encryptPassword data.password, (error, hash)->
              if error?
                callback new errors.ValidationError "Invalid Password", {"password":"Invalid Password"} #error encrypting password, so fail
                cb(error)
                return
              else
                data.password = hash
                cb(null)
                return
          else
            cb(null)
            return

        updateDb: (cb)->
          #password was valid so do what we need to now
          query = Clients._query()
          query.where('_id', id)
          query.findOne (error, client)->
            if error?
              callback error
              cb(error)
              return
            else if client?
              for own k,v of data
                client[k] = v
              client.save callback
              cb(null)
              return
            else
              e = new errors.ValidationError {'password':"Wrong Password"} #invalid login error
              callback(e)
              cb(e)
              return
          return
      },
      (error, results)->
        return
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

  @setTransactonPending: @__setTransactionPending
  @setTransactionProcessing: @__setTransactionProcessing
  @setTransactionProcessed: @__setTransactionProcessed
  @setTransactionError: @__setTransactionError


## Businesses ##
class Businesses extends API
  @model = Business

  #clientid, limit, skip
  @optionParser = (options, q)->
    query = @_optionParser(options, q)
    query.in('clients', [options.clientId]) if options.clientId?
    query.where 'locations.tapins', true if options.tapins?
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
      return
    return

  @updateIdentity: (id, data, callback)->
    if Object.isString(id)
      id = new ObjectId(id)
    set = {}
    for own k,v of data
      if !utils.isBlank(v)
        set[k] = v
    @model.collection.update {_id: id}, {$set: set}, {safe: true}, callback

  @updateMedia: (id, guid, data, callback)->
    if(Object.isString(id))
      id = new ObjectId(id)
    if(Object.isString(data.mediaId))
      data.mediaId = new ObjectId(data.mediaId)

    query = @_query()
    query.where("_id", id)
    query.where("media.guid", data.guid)

    set = {}
    set["media.thumb"] = data.thumb
    set["media.url"] = data.url
    set["media.mediaId"] = data.mediaId
    set["media.guid"] = data.guid #reset

    query.update {$set:set}, (error, success)->
      if error?
        callback error #dberror
      else
        callback null, success
      return
    return

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

  @setTransactonPending: @__setTransactionPending
  @setTransactionProcessing: @__setTransactionProcessing
  @setTransactionProcessed: @__setTransactionProcessed
  @setTransactionError: @__setTransactionError


## Campaigns ##
class Campaigns extends API
  @updateMedia: (entityType, entityId, guid, data, mediaKey, callback)->
    if(Object.isString(entityId))
      entityId = new ObjectId(entityId)
    if(Object.isString(data.mediaId))
      data.mediaId = new ObjectId(data.mediaId)
    if(Object.isFunction(mediaKey))
      callback = mediaKey
      mediaKey = "media"

    query = @_query()
    query.where("entity.type", entityType)
    query.where("entity.id", entityId)
    query.where("#{mediaKey}.guid", guid)

    set = {}
    set["#{mediaKey}.thumb"] = data.thumb
    set["#{mediaKey}.url"] = data.url
    set["#{mediaKey}.mediaId"] = data.mediaId
    set["#{mediaKey}.guid"] = data.guid #reset

    query.update {$set:set}, (error, success)->
      if error?
        callback error #dberror
      else
        callback null, success
      return
    return


## Polls ##
class Polls extends Campaigns
  @model = Poll

  #inherits from campaigns
  #@updateMedia

  #options: name, businessid, type, businessname,showstats, answered, start, end, outoffunds
  @optionParser = (options, q)->
    query = @_optionParser options, q
    query.where('entity.type', options.entityType) if options.entityType?
    query.where('entity.id', options.entityId) if options.entityId?
    query.where('dates.start').gte(options.start) if options.start?
    # query.where('dates.end').gte(options.start) if options.end?
    query.where('transaction.state', state) if options.state?
    return query

  # @add = (data, amount, event, callback)-> #come back to this one, first transactions need to work
  @add: (data, amount, callback)->
    if Object.isString(data.entity.id)
      data.entity.id = new ObjectId data.entity.id
    if data.mediaQuestion and Object.isString(data.mediaQuestion.mediaId) and data.mediaQuestion.mediaId.length>0
      data.mediaQuestion.mediaId = new ObjectId data.mediaQuestion.mediaId
    if data.mediaResults? and Object.isString(data.mediaResults.mediaId) and data.mediaResults.mediaId.length>0
      data.mediaResults.mediaId = new ObjectId data.mediaResults.mediaId

    instance = new @model(data)

    transactionData = {
      amount: amount
    }

    transaction = @createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.POLL_CREATED, transactionData, choices.transactions.directions.INBOUND, instance._doc.entity)

    instance.transactions.state = choices.transactions.states.PENDING #soley for reading purposes
    instance.transactions.locked = true
    instance.transactions.ids = [transaction.id]
    instance.transactions.log = [transaction]

    #instance.events = @_createEventsObj event
    instance.save (error, poll)->
      logger.debug error
      logger.debug poll
      callback error, poll
      if error?
        logger.debug "error"
      else
        tp.process(poll._doc, transaction)
      return
    return

  @update: (entityType, entityId, pollId, data, newAllocated, perResponse, callback)->
    self = this

    instance = new @model(data)

    if Object.isString(pollId)
      pollId = new ObjectId(pollId)
    if Object.isString(entityId)
      entityId = new ObjectId(entityId)

    #Set the fields you want updated now, not afte the update
    #for the ones that you want set after the update put those
    #in the transactionData and make thsoe changes in the
    #setTransactionProcessed function

    $set = {
      entity: {
        type          : entityType
        id            : entityId
        name          : data.entity.name
      }

      lastModifiedBy: {
        type          : data.lastModifiedBy.type
        id            : data.lastModifiedBy.id
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
      displayMediaQuestion    : data.displayMediaQuestion
      displayMediaResults    : data.displayMediaResults

      mediaQuestion : data.mediaQuestion
      mediaResults  : data.mediaResults
    }
    #flat properties so that they dont overwrite their entire subdoc
    $set["dates.start"]= new Date(data.dates.start) #this is so that we don't lose the create date
    $set["transactions.locked"]= true #THIS IS A LOCKING TRANSACTION, SO IF ANYONE ELSE TRIES TO DO A LOKCING TRANSACTION IT WILL NOT HAPPEN (AS LONG AS YOU CHECK FOR THAT)
    $set["transactions.state"]= choices.transactions.states.PENDING

    #TRANSACTION updates
    transactionEntity = {
        type          : entityType
        id            : entityId
    }
    transactionData = {
      newAllocated: newAllocated
      perResponse: perResponse
    }
    transaction = self.createTransaction choices.transactions.states.PENDING, choices.transactions.actions.POLL_UPDATED, transactionData, choices.transactions.directions.INBOUND, transactionEntity

    $push = {
      "transactions.ids": transaction.id
      "transactions.log": transaction
    }

    $update = {
      $set: $set
      $push: $push
    }

    where = {
      _id: pollId,
      "entity.type":entityType,
      "entity.id":entityId,
      "transactions.locked": false,
      "deleted": false
      $or : [
        {"dates.start": {$gt:new Date()}, "transactions.state": choices.transactions.states.PROCESSED},
        {"transactions.state": choices.transactions.states.ERROR}
      ]
    }
    @model.collection.findAndModify where, [], $update, {safe: true, new: true}, (error, poll)->
      if error?
        callback error, null
      else if !poll?
        callback new errors.ValidationError({"poll":"Poll does not exist or not editable."})
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
        query.where('transactions.state', choices.transactions.states.ERROR)
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
      query.skip(options.skip || 0)
      query.limit(options.limit || 25)
      query.exec callback
    else
      query.count callback
    return

  @del: (entityType, entityId, pollId, lastModifiedBy, callback)->
    self = this
    if Object.isString(entityId)
      entityId = new ObjectId(entityId)
    if Object.isString(pollId)
      pollId = new ObjectId(pollId)
    if Object.isString(lastModifiedBy.id)
      lastModifiedBy.id = new ObjectId(lastModifiedBy.id)

    entity = {}
    transactionData = {}
    transaction = self.createTransaction choices.transactions.states.PENDING, choices.transactions.actions.POLL_DELETED, transactionData, choices.transactions.directions.OUTBOUND, entity

    $set = {
      "lastModifiedBy.type": lastModifiedBy.type
      "lastModifiedBy.id": lastModifiedBy.id

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

    where = {
      _id: pollId,
      "entity.type":entityType,
      "entity.id":entityId,
      "transactions.locked": false,
      "deleted": false
      $or : [
        {"dates.start": {$gt:new Date()}, "transactions.state": choices.transactions.states.PROCESSED},
        {"transactions.state": choices.transactions.states.ERROR}
      ]
    }
    @model.collection.findAndModify where, [], $update, {safe: true, new: true}, (error, poll)->
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

  @answered = (consumerId, options, callback)->
    if Object.isString(consumerId)
      consumerId = new ObjectId(consumerId)
    query = @optionParser(options)
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
          timestamp: new Date()
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

        self.model.collection.findAndModify query, [], update, {new:true, safe:true, fields:fieldsToReturn}, (error, poll)->
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


## Discussions ##
class Discussions extends Campaigns
  @model = Discussion

  #inherits from campaigns
  #@updateMedia

  @optionParser = (options, q)->
    query = @_optionParser(options, q)

    query.where('entity.type', options.entityType) if options.entityType?
    query.where('entity.id', options.entityId) if options.entityId?
    query.where('dates.start').gte(options.start) if options.start?
    # query.where('dates.end').gte(options.start) if options.end?
    query.where('transaction.state', state) if options.state?

    return query

  @add = (data, amount, callback)->
    instance = new @model(data)
    if data.tags?
      Tags.addAll data.tags
    transactionData = {
      amount: amount
    }

    transaction = @createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.DISCUSSION_CREATED, transactionData, choices.transactions.directions.INBOUND, instance._doc.entity)

    instance.transactions.locked = true
    instance.transactions.ids = [transaction.id]
    instance.transactions.log = [transaction]

    instance.save (error, discussion)->
      callback error, discussion
      if error?
        return
      else
        tp.process(discussion._doc, transaction)
    return

  @update: (entityType, entityId, discussionId, newAllocated, data, callback)->
    self = this

    instance = new @model(data)

    if Object.isString(entityId)
      entityId = new ObjectId(entityId)
    if Object.isString(discussionId)
      discussionId = new ObjectId(discussionId)
    if data.media? and Object.isString(data.media.mediaId) and data.media.mediaId.length>0
      data.media.mediaId = new ObjectId(data.media.mediaId)

    #Set the fields you want updated now, not afte the update
    #for the ones that you want set after the update put those
    #in the transactionData and make thsoe changes in the
    #setTransactionProcessed function

    $set = {
      entity: {
        type          : entityType
        id            : entityId
        name          : data.entity.name
      }

      lastModifiedBy: {
        type: data.lastModifiedBy.type
        id: data.lastModifiedBy.id
      }

      name            : data.name
      question        : data.question
      details         : data.details
      tags            : data.tags
      displayMedia    : data.displayMedia
      media           : data.media
    }
     #this is flattened so that it does not overwrite the entire dates subdocument
    $set["dates.start"] = new Date(data.dates.start)


    # We don't do a transaction for discussion creation right now because they are a fixed amount at the moment
    # this will change when we implement the consumer side
    entity = {
      type: entityType
      id: entityId
    }
    transactionData = {
      newAllocated: newAllocated
    }
    transaction = self.createTransaction choices.transactions.states.PENDING, choices.transactions.actions.DISCUSSION_UPDATED, transactionData, choices.transactions.directions.INBOUND, entity

    $set["transactions.locked"] = true #THIS IS A LOCKING TRANSACTION, SO IF ANYONE ELSE TRIES TO DO A LOKCING TRANSACTION IT WILL NOT HAPPEN (AS LONG AS YOU CHECK FOR THAT)
    $set["transactions.state"] = choices.transactions.states.PENDING

    $push = {
      "transactions.ids": transaction.id
      "transactions.log": transaction
    }

    logger.info data

    $update = {
      $set: $set
      $push: $push
    }
    where = {
      _id: discussionId,
      "entity.type":entityType,
      "entity.id":entityId,
      "transactions.locked": false,
      "deleted": false
      $or : [
        {"dates.start": {$gt:new Date()}, "transactions.state": choices.transactions.states.PROCESSED},
        {"transactions.state": choices.transactions.states.ERROR}
      ]
    }
    @model.collection.findAndModify where, [], $update, {safe: true, new: true}, (error, discussion)->
      if error?
        callback error, null
      else if !discussion?
        callback new errors.ValidationError({"discussion":"Discussion does not exist or Access Denied."})
      else
        callback null, discussion
        tp.process(discussion, transaction)
    return

  @del: (entityType, entityId, discussionId, lastModifiedBy, callback)->
    self = this
    if Object.isString(entityId)
      entityId = new ObjectId(entityId)
    if Object.isString(discussionId)
      discussionId = new ObjectId(discussionId)
    if Object.isString(lastModifiedBy.id)
      lastModifiedBy.id = new ObjectId(lastModifiedBy.id)

    entity = {}
    transactionData = {}
    transaction = self.createTransaction choices.transactions.states.PENDING, choices.transactions.actions.DISCUSSION_DELETED, transactionData, choices.transactions.directions.OUTBOUND, entity

    $set = {
      "deleted": true
      "transactions.locked": true #THIS IS A LOCKING TRANSACTION, SO IF ANYONE ELSE TRIES TO DO A LOKCING TRANSACTION IT WILL NOT HAPPEN (AS LONG AS YOU CHECK FOR THAT)
      "transactions.state": choices.transactions.states.PENDING

      "lastModifiedBy.type": lastModifiedBy.type
      "lastModifiedBy.id": lastModifiedBy.id
    }
    $push = {
      "transactions.ids": transaction.id
      "transactions.log": transaction
    }

    $update = {
      $set: $set
      $push: $push
    }

    where = {
      _id: discussionId,
      "entity.type":entityType,
      "entity.id":entityId,
      "transactions.locked": false,
      "deleted": false
      $or : [
        {"dates.start": {$gt:new Date()}, "transactions.state": choices.transactions.states.PROCESSED},
        {"transactions.state": choices.transactions.states.ERROR}
      ]
    }
    @model.collection.findAndModify where, [], $update, {safe: true, new: true}, (error, discussion)->
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

  @listCampaign: (entityType, entityId, stage, options, callback)->
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

  ### _list_ ###
  # **options**
  #
  # - **limit** _Number, default: 25_ limit number of discussions returned
  # - **skip** _Number, default: 0_ an offset for number of discussions returned
  #
  # **callback** error, discussions
  @list: (options, callback)->
    if Object.isFunction(options)
      callback = options
    else
      limit = options.limit || 25
      skip = options.skip || 0

    $query = {
      "dates.start"           : {$lte: new Date()}
      , deleted               : {$ne: true}
      , "transactions.state"  : choices.transactions.states.PROCESSED
      , "transactions.locked" : {$ne: true}
    }

    $fields = {
      question          : 1
      , tags            : 1
      , media           : 1
      , thanker         : 1
      , donors          : 1
      , donationAmounts : 1
      , dates           : 1
      , funds           : 1
      , donationCount   : 1
      , thankCount      : 1
    }

    @model.collection.find $query, $fields, (error, cursor)->
      if error?
        callback(error)
        return
      cursor.toArray (error, discussions)->
        callback(error, discussions)

  ### _get_ ###
  #
  # **discussionId** _String/ObjectId_ id of discussion
  #
  # **responseOptions**
  #
  # - **start** _Number, default: 0_ starting index of slice for responses
  # - **stop** _Number, default: 10_ stopping index of slice for responses
  #
  # **callback** error, discussion
  @get: (discussionId, responseOptions, callback)->
    if Object.isString(discussionId)
      discussionId = new ObjectId(discussionId)

    if Object.isFunction(responseOptions)
      callback = responseOptions
      responseOptions = {}

    responseOptions.start = responseOptions.start || 0
    responseOptions.stop = responseOptions.stop || 10

    $query = {
      "dates.start"           : {$lte: new Date()}
      , deleted               : {$ne: true}
      , "transactions.state"  : choices.transactions.states.PROCESSED
      , "transactions.locked" : {$ne: true}
    }

    $fields = {
      question          : 1
      , tags            : 1
      , media           : 1
      , thanker         : 1
      , donors          : 1
      , donationAmounts : 1
      , dates           : 1
      , funds           : 1
      , donationCount   : 1
      , thankCount      : 1
      , responses       : {$slice:[responseOptions.start, responseOptions.stop]}
    }

    @model.collection.findOne $query, $fields, (error, discussion)->
      callback(error, discussion)

  ### _getResponsesOnly_ ###
  # **discussionId** _String/ObjectId_ Id of discussion
  #
  # **responseOptions**
  #
  # - **start** _Number, default: 0_ starting index of slice for responses
  # - **stop** _Number, default: 10_ stopping index of slice for responses
  #
  # **callback** error, discussion
  @getResponsesOnly: (discussionId, responseOptions, callback)->
    if Object.isString(discussionId)
      discussionId = new ObjectId(discussionId)

    if Object.isFunction(responseOptions)
      callback = responseOptions
      responseOptions = {}

    responseOptions.start = responseOptions.start || 0
    responseOptions.stop = responseOptions.stop || 10

    $query = {
      "dates.start"           : {$lte: new Date()}
      , deleted               : {$ne: true}
      , "transactions.state"  : choices.transactions.states.PROCESSED
      , "transactions.locked" : {$ne: true}
    }

    $fields = {
      _id: 1
      , responses   : {$slice:[responseOptions.start, responseOptions.stop]}
    }

    @model.collection.findOne $query, $fields, (error, discussion)->
      callback(error, discussion.responses)

  @getByEntity: (entityType, entityId, discussionId, callback)->
    @model.findOne {_id: discussionId, 'entity.type': entityType ,'entity.id': entityId}, callback
    return

  ### _thank_ ###
  # **discussionId** _String/ObjectId_ Id of discussion <br />
  # **responseId** _String/ObjectId_ Id of response in discussion <br />
  # **thankerEntity** _Object_ an entity object containing at least `type` and `id` <br />
  # **amount** _Float_ the amount that the user wishes to thank the respondant <br />
  # **callback** error, numDocsModified
  @thank: (discussionId, responseId, thankerEntity, amount, callback)-> #take money out of my own funds and give to another user, update discussion
    if Object.isString(discussionId)
      discussionId = new ObjectId(discussionId)
    if Object.isString(responseId)
      responseId = new ObjectId(responseId)
    if Object.isString(thankerEntity.id)
      thankerEntity.id = new ObjectId(thankerEntity.id)

    amount = parseFloat(amount)
    if amount<0
      callback(new errors.ValidationError("discussion": "can not thank a negative amount"))

    thankerApiClass = null
    if thankerEntity.type is choices.entities.CONSUMER
      thankerApiClass = Consumers
    else if thankerEntity.type is choices.entities.BUSINESS
      thankerApiClass = Businesses
    else
      callback new errors.ValidationError({"discussion":"Entity type: #{thankerEntity.type} is invalid or unsupported"})
      return

    fieldsToReturn = {}
    fieldsToReturn["responseEntities.#{responseId.toString()}"] = 1

    entityThanked = null
    async.series {
      getResponseEntity: (cb)=>
        @model.collection.findOne {_id: discussionId}, fieldsToReturn, (error, discussion)->
          if error?
            cb error
            return
          else if !discussion?
            cb new errors.ValidationError("discussion": "response doesn't exist")
            return
          else
            entityThanked = discussion.responseEntities["#{responseId.toString()}"]
            cb()
            return
      save: (cb)=>
        transactionData = {
          amount: amount
          thankerEntity: thankerEntity
          discussionId: discussionId
          responseId: responseId
          timestamp: new Date()
        }

        transaction = @createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.DISCUSSION_THANKED, transactionData, choices.transactions.directions.OUTBOUND, entityThanked)

        $set = {}
        $push = {
          "transactions.ids": transaction.id
          "transactions.log": transaction
        }

        $inc = {
          "funds.remaining": -1*amount
        }

        $update = {$push: $push, $set: $set, $inc: $inc}

        fieldsToReturn = {_id: 1}

        thankerApiClass.model.collection.findAndModify {_id: thankerEntity.id, "funds.remaining": {$gte: amount}}, [], $update, {safe: true, fields: fieldsToReturn}, (error, doc)->
          if error?
            cb error
          else if !doc?
            cb new errors.ValidationError({"funds.remaining":"insufficient funds remaining"})
          else
            callback(null, 1) #1 for number of documents updated (no need to return document)
            tp.process(doc, transaction)
            cb()
    },
    (error, results)=>
      if error?
        callback(error)

  ### _donate_ ###
  # **discussionId** _String/ObjectId_ Id of discussion <br />
  # **entity** _Object_ an entity object containing at least `type` and `id` <br />
  # **amount** _Float_ the amount that the user wishes to thank the respondant <br />
  # **callback** error, numDocsModified
  @donate: (discussionId, entity, amount, callback)->
    if Object.isString(discussionId)
      discussionId = new ObjectId(discussionId)
    if Object.isString(entity.id)
      entity.id = new ObjectId(entity.id)

    amount = parseFloat(amount)
    if amount<0
      callback(new errors.ValidationError("discussion": "can not donate negative funds"))

    transactionData = {
      amount: amount
      timestamp: new Date()
    }
    transaction = @createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.DISCUSSION_DONATED, transactionData, choices.transactions.directions.INBOUND, entity)

    $set = {}
    $push = {
      "transactions.ids": transaction.id
      "transactions.log": transaction
    }
    $update = {$push: $push, $set: $set}

    fieldsToReturn = {_id: 1 }
    @model.collection.findAndModify {_id: discussionId}, [], $update, {safe: true, fields: fieldsToReturn}, (error, discussion)->
      if error?
        callback(error)
      else if !discussion?
        callback new errors.ValidationError({"discussion":"Discussion does not exist or is not editable."})
      else
        callback(null, 1) #1 for number of documents updated (no need to return document)
        tp.process(discussion, transaction)

  ### distributeDonation ###
  # **discussionId** _String/ObjectId_ Id of discussion <br />
  # **responseId** _String/ObjectId_ Id of response in discussion <br />
  # **donorEntity** _Object_ an entity object containing at least `type` and `id` <br />
  # **amount** _Float_ the amount that the user wishes to donate into the discussions <br />
  # **callback** error, numDocsModified
  @distributeDonation: (discussionId, responseId, donorEntity, amount, callback)-> #distribute the amount that the donorEntity has donated to a particular response
    if Object.isString(discussionId)
      discussionId = new ObjectId(discussionId)
    if Object.isString(responseId)
      responseId = new ObjectId(responseId)
    if Object.isString(donorEntity.id)
      donorEntity.id = new ObjectId(donorEntity.id)

    amount = parseFloat(amount)
    if amount<0
      callback(new errors.ValidationError("discussion": "can not distribute negative funds"))

    fieldsToReturn = {}
    fieldsToReturn["responseEntities.#{responseId.toString()}"] = 1

    doneeEntity = null
    async.series {
      getResponseEntity: (cb)=>
        @model.collection.findOne {_id: discussionId}, fieldsToReturn, (error, discussion)->
          if error?
            cb error
            return
          else if !discussion?
            cb new errors.ValidationError("discussion": "response doesn't exist")
            return
          else
            doneeEntity = discussion.responseEntities["#{responseId.toString()}"]
            cb()
            return
      save: (cb)=>
        transactionData = {
          amount: amount
          donorEntity: donorEntity
          discussionId: discussionId
          responseId: responseId
          timestamp: new Date()
        }

        transaction = @createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.DISCUSSION_DONATION_DISTRIBUTED, transactionData, choices.transactions.directions.OUTBOUND, doneeEntity)

        $set = {}
        $push = {
          "transactions.ids": transaction.id
          "transactions.log": transaction
        }

        $inc = {
          "funds.remaining": -1*amount
        }

        $update = {$push: $push, $set: $set, $inc: $inc}

        fieldsToReturn = {_id: 1}

        $query = {_id: discussionId}
        $query["donationAmounts.#{donorEntity.type}_#{donorEntity.id}.remaining"] = {$gte: amount}

        logger.debug $query
        logger.debug $update
        @model.collection.findAndModify $query, [], $update, {safe: true, fields: fieldsToReturn}, (error, doc)->
          if error?
            cb error
          else if !doc?
            cb new errors.ValidationError({"funds.remaining":"insufficient funds remaining"})
          else
            callback(null, 1) #1 for number of documents updated (no need to return document)
            tp.process(doc, transaction)
            cb()
    },
    (error, results)=>
      if error?
        callback(error)

  ### _respond_ ###
  # **discussionId** _String/ObjectId_ Id of discussion <br />
  # **entity** _Object_ an entity object containing at least `type` and `id` <br />
  # **content** _String_ the content of the response <br />
  # **callback** error, numDocsModified
  @respond: (discussionId, entity, content, callback)->
    if Object.isString(discussionId)
      discussionId = new ObjectId(discussionId)
    if Object.isString(entity.id)
      entity.id = new ObjectId(entity.id)

    response = {
      _id               : new ObjectId()
      entity            : entity
      content           : content

      commentCount      : 0

      dates: {
        created         : new Date()
        lastModified    : new Date()
      }
    }

    $push = {
      responses: response
    }

    $set = {}
    $set["responseEntities.#{response._id.toString()}"] = entity

    $inc = {
      responseCount: 1
    }

    $update = {$push: $push, $inc: $inc, $set: $set}

    @model.collection.update {_id: discussionId}, $update, {safe: true}, callback

  ### _comment_ ###
  # **discussionId** _String/ObjectId_ Id of discussion <br />
  # **responseId** _String/ObjectId_ Id of response in discussion <br />
  # **entity** _Object_ an entity object containing at least `type` and `id` <br />
  # **content** _String_ the content of the comment <br />
  # **callback** error, numDocsModified
  @comment: (discussionId, responseId, entity, content, callback)->
    if Object.isString(discussionId)
      discussionId = new ObjectId(discussionId)
    if Object.isString(responseId)
      responseId = new ObjectId(responseId)
    if Object.isString(entity.id)
      entity.id = new ObjectId(entity.id)

      comment = {
        _id               : new ObjectId()
        entity            : entity
        content           : content

        dates: {
          created         : new Date()
          lastModified    : new Date()
        }
      }

      $push = {"responses.$.comments": comment}
      $inc = {"responses.$.commentCount": 1}

      $update = {$push: $push, $inc: $inc}
      @model.collection.update {_id: discussionId, "responses._id": responseId}, $update, {safe: true}, callback

  ### _voteUp_ ###
  # **discussionId** _String/ObjectId_ Id of discussion <br />
  # **responseId** _String/ObjectId_ Id of response in discussion <br />
  # **entity** _Object_ an entity object containing at least `type` and `id` <br />
  # **callback** error
  @voteUp: (discussionId, responseId, entity, callback)->
    @_vote(discussionId, responseId, entity, choices.votes.UP, callback)

  ### _voteDown_ ###
  # **discussionId** _String/ObjectId_ Id of discussion <br />
  # **responseId** _String/ObjectId_ Id of response in discussion <br />
  # **entity** _Object_ an entity object containing at least `type` and `id` <br />
  # **callback** error
  @voteDown: (discussionId, responseId, entity, callback)->
    @_vote(discussionId, responseId, entity, choices.votes.DOWN, callback)

  ### _\_vote_ ###
  # **discussionId** _String/ObjectId_ Id of discussion <br />
  # **responseId** _String/ObjectId_ Id of response in discussion <br />
  # **entity** _Object_ an entity object containing at least `type` and `id` <br />
  # **direction** _String, enum: choices.votes_ <br />
  # **callback** error
  @_vote: (discussionId, responseId, entity, direction, callback)->
    if Object.isString(discussionId)
      discussionId = new ObjectId(discussionId)
    if Object.isString(responseId)
      responseId = new ObjectId(responseId)
    if Object.isString(entity.id)
      entity.id = new ObjectId(entity.id)

    d = "up"
    opposite = choices.votes.DOWN
    if direction is choices.votes.DOWN
      d = "down"
      opposite = choices.votes.UP

    #if the user has voted the opposite, undo that
    @_undoVote discussionId, responseId, entity, opposite, (error, data)->
      return

    entity._id = new ObjectId() #we do this because mongoose does it to every document array

    $query = {_id: discussionId, "responses._id": responseId}

    $inc = {"responses.$.votes.count": 1}
    $set = {}
    $push = {}

    $query["responses.votes.#{d}.by.id"] = {$ne: entity.id} #not already set
    $inc["responses.$.votes.#{d}.count"] = 1
    $push["responses.$.votes.#{d}.by"] = entity
    $set["responses.$.votes.#{d}.ids.#{entity.type}_#{entity.id.toString()}"] = 1

    $update = {$inc: $inc, $push: $push, $set: $set}

    @model.collection.update $query, $update, {safe: false}, callback


  ### _undoVoteUp_ ###
  # **discussionId** _String/ObjectId_ Id of discussion <br />
  # **responseId** _String/ObjectId_ Id of response in discussion <br />
  # **entity** _Object_ an entity object containing at least `type` and `id` <br />
  # **callback** error
  @undoVoteUp: (discussionId, responseId, entity, callback)->
    @_undoVote(discussionId, responseId, entity, choices.votes.UP, callback)

  ### _undoVoteDown_ ###
  # **discussionId** _String/ObjectId_ Id of discussion <br />
  # **responseId** _String/ObjectId_ Id of response in discussion <br />
  # **entity** _Object_ an entity object containing at least `type` and `id` <br />
  # **callback** error
  @undoVoteDown: (discussionId, responseId, entity, callback)->
    @_undoVote(discussionId, responseId, entity, choices.votes.DOWN, callback)

  ### _\_undoVote_ ###
  # **discussionId** _String/ObjectId_ Id of discussion <br />
  # **responseId** _String/ObjectId_ Id of response in discussion <br />
  # **entity** _Object_ an entity object containing at least `type` and `id` <br />
  # **direction** _String, enum: choices.votes_ <br />
  # **callback** error
  @_undoVote: (discussionId, responseId, entity, direction, callback)->
    if Object.isString(discussionId)
      discussionId = new ObjectId(discussionId)
    if Object.isString(responseId)
      responseId = new ObjectId(responseId)
    if Object.isString(entity.id)
      entity.id = new ObjectId(entity.id)

    d = "up"
    if direction is choices.votes.DOWN
      d = "down"

    $query = {_id: discussionId, "responses._id": responseId}
    $pull = {}
    $inc = {"responses.$.votes.count": -1}
    $unset = {}

    $query["responses.votes.#{d}.by.id"] = entity.id
    $pull["responses.$.votes.#{d}.by"] = {type: entity.type, id: entity.id}
    $inc["responses.$.votes.#{d}.count"] = -1
    $unset["responses.$.votes.#{d}.ids.#{entity.type}_#{entity.id.toString()}"] = 1

    $update = {$inc: $inc, $pull: $pull, $unset: $unset}

    @model.collection.update $query, $update, {safe: false}, callback

  @setTransactonPending: @__setTransactionPending
  @setTransactionProcessing: @__setTransactionProcessing
  @setTransactionProcessed: @__setTransactionProcessed
  @setTransactionError: @__setTransactionError


## Medias ##
class Medias extends API
  @model = Media

  @addOrUpdate: (media, callback)->
    if Object.isString(media.entity.id)
      media.entity.id = new ObjectId media.entity.id
    @model.collection.findAndModify {guid:media.guid},[], {$set:media}, {new: true, safe: true, upsert:true}, (error, mediaCreated)->
      if error?
        callback error #dberror
        return
      logger.debug mediaCreated
      callback null, mediaCreated
      return
    return

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
  @getByEntity: (entityType, entityId, type, callback)->
    if Object.isFunction(type)
      callback = type
      @get {entityType: entityType, entityId: entityId}, callback
      #@get {'entity.type': choices.entities.BUSINESS, 'entity.id': entityId}, callback
    else
      @get {entityType: entityType, entityId: entityId, type: type}, callback
      #@get {'entity.type': choices.entities.BUSINESS, 'entity.id': entityId, type: type}, callback
    return

  @getByGuid: (entityType, entityId, guid, callback)->
    @get {entityType: entityType, entityId: entityId, guid: guid}, callback
    #@get {'entity.type': entityType, 'entity.id': entityId, 'media.guid': guid}, callback


## ClientInvitations ##
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


## Tags ##
class Tags extends API
  @model = Tag

  @add = (name, callback)->
    @_add {name: name}, callback

  @addAll = (nameArr, callback)->
    #callback is not required..
    countUpdates = 0
    for val,i in nameArr
      @model.update {name:val}, {$inc:{count:1}}, {upsert:true,safe:true}, (error, success)->
        if error?
          callback error
          return
        if ++countUpdates == nameArr.length && Object.isFunction callback #check if done
          callback null, countUpdates
        return

  @search = (name, callback)->
    re = new RegExp("^"+name+".*", 'i')
    query = @_query()
    query.where('name', re)
    query.limit(10)
    query.exec callback


## EventRequests ##
class EventRequests extends API
  @model = EventRequest

  @requestsPending: (businessId, callback)->
    query = @_query()
    query.where 'organizationEntity.id', businessId
    query.where('date.responded').exists false
    query.exec callback

  @respond: (requestId, callback)->
    $query = {_id: requestId}
    $update =
      $set:
        'date.responded': new Date()
    $options = {remove: false, new: true, upsert: false}
    @model.collection.findAndModify $query, [], $update, $options, callback


## Events ##
class Events extends API
  @model = Event

  @optionParser: (options, q)->
    query = @_optionParser options, q
    if options.not?
      query.where('_id').$ne options.not
    if options.upcoming?
      query.where('dates.actual').$gt Date.now()
    return query

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

    $push = {
      rsvp: userId
    }

    $query = {_id: eventId}
    $update = {$push: $push}
    $options = {remove: false, new: true, upsert: false}
    @model.collection.findAndModify $query, [], $update, $options, (error, event)->
      callback error, event
      if !error?
        who = {type: choices.entities.CONSUMER, id: userId}
        Streams.eventRsvped who, event


  @setTransactonPending: @__setTransactionPending
  @setTransactionProcessing: @__setTransactionProcessing
  @setTransactionProcessed: @__setTransactionProcessed
  @setTransactionError: @__setTransactionError


## BusinessTransactions ##
class BusinessTransactions extends API
  @model = db.BusinessTransaction

  @add: (data, callback)->
    if Object.isString(data.organizationEntity.id)
      data.organizationEntity.id = new ObjectId(data.organizationEntity.id)
    if Object.isString(data.locationId)
      data.locationId = new ObjectId(data.locationId)

    timestamp = Date.create(data.timestamp)

    doc = {
      organizationEntity: {
        type          : data.organizationEntity.type
        id            : data.organizationEntity.id
        name          : data.organizationEntity.name
      }

      locationId      : data.locationId
      registerId      : data.registerId
      barcodeId       : data.barcodeId
      transactionId   : data.transactionId
      date            : Date.create(timestamp)
      time            : new Date(0,0,0, timestamp.getHours(), timestamp.getMinutes(), timestamp.getSeconds(), timestamp.getMilliseconds()) #this is for slicing by time
      amount          : parseFloat(data.amount).round(2)
      #donationAmount  : data.donationAmount #business don't have a donation $ or % field in db
    }

    self = this
    async.series {
      findConsumer: (cb)-> #find only if there was a barcode that needed to be analyzed
        if doc.barcodeId?
          Consumers.getByBarcodeId doc.barcodeId, (error, consumer)->
            if error?
              cb(error, null)
              return
            else if consumer?
              doc.userEntity = {
                type        : choices.entities.CONSUMER
                id          : consumer._id
                name        : "#{consumer.firstName} #{consumer.lastName}"
                screenName  : consumer.screenName
              }
              cb(null)
            else
              cb(null) #insert the transaction anyway, it is an invalid bar code though
              #cb(new errors.ValidationError {"DNE": "Consumer Does Not Exist"})
        else
          cb(null)

      findOrg: (cb)-> #do 3 things, make sure org exists, get the name, get donation amount
        if doc.organizationEntity.type is choices.entities.BUSINESS
          Businesses.one doc.organizationEntity.id, (error, business)->
            if error?
              cb(error, null)
              return
            else if business?
              doc.organizationEntity.name = business.publicName
              # if doc.userEntity? #donate only if this was a goodybag user
              #   doc.donationAmount = (business.donationPercentage * doc.amount).round(2)
              cb(null)
            else
              cb(new errors.ValidationError {"DNE": "Business Does Not Exist"})

      save: (cb)=> #save it and write to the statistics table
        instance = new @model(doc)

        transactionData = {
          amount: doc.amount
        }

        statTransaction = @createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.STAT_BT_TAPPED, transactionData, choices.transactions.directions.INBOUND, instance._doc.organizationEntity)

        instance.transactions.locked = false
        instance.transactions.ids = [statTransaction.id]
        instance.transactions.log = [statTransaction]

        instance.save (error, bt)->
          cb error, bt
          if error?
            return
          if doc.userEntity?
            who = doc.userEntity
            tp.process(bt._doc, statTransaction) #write stat to collection
            Streams.btTapped bt._doc #NOTICE THE _doc HERE, BECAUSE !!!! #we don't care about the callback
        return
    }, (error, results)->
      if error?
        callback(error)
      else if results.save?
        callback(null, results.save)

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

  @byBusinessGbCostumers = (businessId, options, callback)->
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

  @test = (callback)->
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


## BusinessRequests ##
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


## Streams ##
class Streams extends API
  @model: Stream

  @add: (stream, callback)->
    model = {
      who                : stream.who
      by                 : stream.by
      entitiesInvolved   : stream.entitiesInvolved
      what               : stream.what
      when               : stream.when || new Date()
      where              : stream.where
      events             : stream.events
      private            : stream.private || false #default to public
      data               : stream.data || {}
      feeds              : stream.feeds
      feedSpecificData   : stream.feedSpecificData
      entitySpecificData : stream.entitySpecificData
      dates: {
        created           : new Date()
        lastModified      : new Date()
      }
    }

    instance = new @model(model)
    instance.save callback

  @pollCreated: (pollDoc, callback)->
    if Object.isString(pollDoc._id)
      pollDoc._id = new ObjectId(pollDoc._id)

    if Object.isString(pollDoc.entity.id)
      pollDoc.entity.id = new ObjectId(pollDoc.entity.id)

    if Object.isString(pollDoc.createdBy.id)
      pollDoc.createdBy.id = new ObjectId(pollDoc.createdBy.id)

    who = pollDoc.entity
    poll = {type: choices.objects.POLL, id: pollDoc._id }
    user = undefined #will be set only if document.entity is an organization and not a consumer

    if who.type is choices.entities.BUSINESS
      user = {type: pollDoc.createdBy.type, id: pollDoc.createdBy.id}

    stream = {
      who               : who
      entitiesInvolved  : [who]
      what              : poll
      when              : pollDoc.dates.created
      #where:
      events            : [choices.eventTypes.POLL_CREATED]
      data              : {}
      feeds: {
        global          : false
      }
      private: false #THIS NEEDS TO BE UPDATED BASED ON PRIVACY SETTINGS OF WHO (if consumer)
    }

    if user?
      stream.by = user
      stream.entitiesInvolved.push(user)

    stream.data = {
      poll:{
        name: pollDoc.name
      }
    }

    logger.debug stream

    @add stream, callback

  @pollUpdated: (pollDoc, callback)->
    if Object.isString(pollDoc._id)
      pollDoc._id = new ObjectId(pollDoc._id)

    if Object.isString(pollDoc.entity.id)
      pollDoc.entity.id = new ObjectId(pollDoc.entity.id)

    if Object.isString(pollDoc.lastModifiedBy.id)
      pollDoc.lastModifiedBy.id = new ObjectId(pollDoc.lastModifiedBy.id)

    who = pollDoc.entity
    poll = {type: choices.objects.POLL, id: pollDoc._id }
    user = undefined #will be set only if document.entity is an organization and not a consumer

    if who.type is choices.entities.BUSINESS
      user = {type: pollDoc.lastModifiedBy.type, id: pollDoc.lastModifiedBy.id}

    stream = {
      who               : who
      entitiesInvolved  : [who]
      what              : poll
      when              : pollDoc.dates.lastModified
      #where:
      events            : [choices.eventTypes.POLL_UPDATED]
      data              : {}
      feeds: {
        global          : false
      }
      private: false #THIS NEEDS TO BE UPDATED BASED ON PRIVACY SETTINGS OF WHO (if consumer)
    }

    if user?
      stream.by = user
      stream.entitiesInvolved.push(user)

    stream.data = {
      poll:{
        name: pollDoc.name
      }
    }

    @add stream, callback

  @pollDeleted: (pollDoc, callback)->
    if Object.isString(pollDoc._id)
      pollDoc._id = new ObjectId(pollDoc._id)

    if Object.isString(pollDoc.entity.id)
      pollDoc.entity.id = new ObjectId(pollDoc.entity.id)

    if Object.isString(pollDoc.lastModifiedBy.id)
      pollDoc.lastModifiedBy.id = new ObjectId(pollDoc.lastModifiedBy.id)

    who = pollDoc.entity.type #who ever created it
    poll = {type: choices.objects.POLL, id: pollDoc._id }
    user = undefined #will be set only if document.entity is an organization and not a consumer

    if who.type is choices.entities.BUSINESS
      user = pollDoc.lastModifiedBy

    stream = {
      who               : who
      entitiesInvolved  : [who]
      what              : poll
      when              : pollDoc.dates.lastModified
      #where:
      events            : [choices.eventTypes.POLL_DELETED]
      data              : {}
      feeds: {
        global          : false
      }
      private: false #THIS NEEDS TO BE UPDATED BASED ON PRIVACY SETTINGS OF WHO (if consumer)
    }

    if user?
      stream.by = user
      stream.entitiesInvolved.push(user)

    stream.data = {
      poll:{
        name: pollDoc.name
      }
    }

    @add stream, callback

  @pollAnswered: (who, timestamp, pollDoc, callback)->
    if Object.isString(who.id)
      who.id = new ObjectId(who.id)

    if Object.isString(pollDoc._id)
      pollDoc._id = new ObjectId(pollDoc._id)

    if Object.isString(pollDoc.entity.id)
      pollDoc.entity.id = new ObjectId(pollDoc.entity.id)

    poll = {type: choices.objects.POLL, id: pollDoc._id }

    stream = {
      who               : who
      entitiesInvolved  : [who, pollDoc.entity]
      what              : poll
      when              : timestamp
      #where:
      events            : [choices.eventTypes.POLL_ANSWERED]
      data              : {}
      feeds: {
        global          : false
      }
      private: false #THIS NEEDS TO BE UPDATED BASED ON PRIVACY SETTINGS OF WHO (if consumer)
    }

    stream.data = {
      poll:{
        name: pollDoc.name
      }
    }

    @add stream, callback

  @discussionCreated: (discussionDoc, callback)->
    logger.debug discussionDoc
    if Object.isString(discussionDoc._id)
      discussionDoc._id = new ObjectId(discussionDoc._id)

    if Object.isString(discussionDoc.entity.id)
      discussionDoc.entity.id = new ObjectId(discussionDoc.entity.id)

    if Object.isString(discussionDoc.createdBy.id)
      discussionDoc.createdBy.id = new ObjectId(discussionDoc.createdBy.id)

    who = discussionDoc.entity
    discussion = {type: choices.objects.DISCUSSION, id: discussionDoc._id }
    user = undefined #will be set only if document.entity is an organization and not a consumer

    if who.type is choices.entities.BUSINESS
      user = {type: discussionDoc.createdBy.type, id: discussionDoc.createdBy.id}

    stream = {
      who               : who
      entitiesInvolved  : [who]
      what              : discussion
      when              : discussionDoc.dates.created
      #where:
      events            : [choices.eventTypes.DISCUSSION_CREATED]
      data              : {}
      feeds: {
        global          : false
      }
    }

    if user?
      stream.by = user
      stream.entitiesInvolved.push(user)

    stream.data = {
      discussion:{
        name: discussionDoc.name
      }
    }

    logger.debug stream

    @add stream, callback

  @discussionUpdated: (discussionDoc, callback)->
    if Object.isString(discussionDoc._id)
      discussionDoc._id = new ObjectId(discussionDoc._id)

    if Object.isString(discussionDoc.entity.id)
      discussionDoc.entity.id = new ObjectId(discussionDoc.entity.id)

    if Object.isString(discussionDoc.lastModifiedBy.id)
      discussionDoc.lastModifiedBy.id = new ObjectId(discussionDoc.lastModifiedBy.id)

    who = discussionDoc.entity #who ever created it
    discussion = {type: choices.objects.DISCUSSION, id: discussionDoc._id }
    user = undefined #will be set only if document.entity is an organization and not a consumer

    if who.type is choices.entities.BUSINESS
      user = {type: discussionDoc.lastModifiedBy.type, id: discussionDoc.lastModifiedBy.id}

    stream = {
      who               : who
      entitiesInvolved  : [who]
      what              : discussion
      when              : discussionDoc.dates.lastModified
      #where:
      events            : [choices.eventTypes.DISCUSSION_UPDATED]
      data              : {}
      feeds: {
        global          : false
      }
    }

    if user?
      stream.by = user
      stream.entitiesInvolved.push(user)

    stream.data = {
      discussion:{
        name: discussionDoc.name
      }
    }

    @add stream, callback

  @discussionDeleted: (discussionDoc, callback)->
    if Object.isString(discussionDoc._id)
      discussionDoc._id = new ObjectId(discussionDoc._id)

    if Object.isString(discussionDoc.entity.id)
      discussionDoc.entity.id = new ObjectId(discussionDoc.entity.id)

    if Object.isString(discussionDoc.lastModifiedBy.id)
      discussionDoc.lastModifiedBy.id = new ObjectId(discussionDoc.lastModifiedBy.id)

    who = discussionDoc.entity #who ever created it
    discussion = {type: choices.objects.DISCUSSION, id: discussionDoc._id }
    user = undefined #will be set only if document.entity is an organization and not a consumer

    if who.type is choices.entities.BUSINESS
      user = {type: discussionDoc.lastModifiedBy.type, id: discussionDoc.lastModifiedBy.id}

    stream = {
      who               : who
      entitiesInvolved  : [who]
      what              : discussion
      when              : discussionDoc.dates.lastModified
      #where:
      events            : [choices.eventTypes.DISCUSSION_DELETED]
      data              : {}
      feeds: {
        global          : false
      }
    }

    if user?
      stream.by = user
      stream.entitiesInvolved.push(user)

    stream.data = {
      discussion:{
        name: discussionDoc.name
      }
    }

    @add stream, callback

  @discussionAnswered: (who, timestamp, discussionDoc, callback)->
    if Object.isString(who.id)
      who.id = new ObjectId(who.id)

    if Object.isString(discussionDoc._id)
      discussionDoc._id = new ObjectId(discussionDoc._id)

    if Object.isString(discussionDoc.entity.id)
      discussionDoc.entity.id = new ObjectId(discussionDoc.entity.id)

    discussion = {type: choices.objects.DISCUSSION, id: discussionDoc._id }

    stream = {
      who               : who
      entitiesInvolved  : [who, discussionDoc.entity]
      what              : discussion
      when              : timestamp
      #where:
      events            : [choices.eventTypes.DISCUSSION_ANSWERED]
      data              : {}
      feeds: {
        global          : false
      }
    }

    stream.data = {
      discussion:{
        name: discussionDoc.name
      }
    }

    @add stream, callback

  @eventRsvped: (who, eventDoc, callback)->
    if Object.isString(who.id)
      who.id = new ObjectId(who.id)

    event = {type: choices.objects.EVENT, id: eventDoc._id}
    stream = {
      who               : who
      entitiesInvolved  : [who, eventDoc.entity]
      what              : event
      when              : new Date()
      events            : [choices.eventTypes.EVENT_RSVPED]
      data              : {}
      feeds: {
        global          : true
      }
    }

    stream.data = {
      event: {
        entity:{
          name: eventDoc.entity.name
        }
        locationId: eventDoc.locationId
        location: eventDoc.location
        dates:{
          actual: eventDoc.dates.actual
        }
      }
    }

    @add stream, callback

  @btTapped: (btDoc, callback)->
    if Object.isString(btDoc._id)
      btDoc._id = new ObjectId(btDoc._id)
    if Object.isString(btDoc.userEntity.id)
      btDoc.userEntity.id = new ObjectId(btDoc.userEntity.id)
    if Object.isString(btDoc.organizationEntity.id)
      btDoc.organizationEntity.id = new ObjectId(btDoc.organizationEntity.id)

    tapIn = {type: choices.objects.TAPIN, id: btDoc._id}
    who = btDoc.userEntity

    stream = {
      who               : who
      entitiesInvolved  : [who, btDoc.organizationEntity]
      what              : tapIn
      when              : btDoc.date

      where: {
        org             : btDoc.organizationEntity
        locationId      : btDoc.locationId
      }

      events            : [choices.eventTypes.BT_TAPPED]
      data              : {}

      feeds: {
        global          : true #unless a user's preferences are do that
      }
    }

    stream.feedSpecificData = {}
    stream.feedSpecificData.involved = { #available only to entities involved
      amount: btDoc.amount
      donationAmount: btDoc.donationAmount
    }

    logger.debug(stream)

    @add stream, callback
  ###
  example1: client created a poll:
    who = client
    what = [client, business, poll]
    when = timestamp that poll was created
    where = undefined
    events = [pollCreated]
    entitiesInvolved = [client, business]
    data:
      pollCreated:
        pollId: ObjectId
        pollName: String
        businessId: ObjectId
  ###

  ###
  example2: consumer created a poll:
    who = consumer
    what = [consumer, poll]
    when = timestamp that poll was created
    where = undefined
    events = [pollCreated]
    entitiesInvolved = [client]
    data:
      pollCreated:
        pollId: ObjectId
        pollName: String
  ###

  ###
  example3: consumer attend an event and tapped in:
    who = consumer
    what = [consumer, business, businessTransaction]
    when = timestamp the user tappedIn
    where: undefined
      org:
        type: business
        id: ObjectId
      orgName: String
      locationId: ObjectId
      locationName: String
    events = [attended, eventTapIn]
    entitiesInvolved = [client, business]
    data:
      eventTapIn:
        eventId: ObjectId
        businessTransactionId: ObjectId
        spent: XX.xx
  ###

  @global: (options, callback)->
    query = @optionParser(options)
    query.where "feeds.global", true
    query.sort "dates.lastModified", -1
    query.fields [
      "who.type"
      , "who.name"
      , "who.id"
      , "by"
      , "what"
      , "when"
      , "where"
      , "events"
      , "dates"
      , "data"
    ]
    query.exec callback

  @business: (businessId, options, callback)->
    query = @optionParser(options)
    query.sort "dates.lastModified", -1
    query.where "entitiesInvolved.type", choices.entities.BUSINESS
    query.where "entitiesInvolved.id", businessId
    query.only {
      "who.type": 1
      , "who.screenName": 1
      , "by": 1
      , "what": 1
      , "when": 1
      , "where": 1
      , "events": 1
      , "dates": 1
      , "data": 1
      , "feedSpecificData.involved": 1
      , "_id": 0
      , "id": 0
    }
    query.exec callback

  @businessWithConsumerByScreenName: (businessId, screenName, options, callback)->
    query = @optionParser(options)
    query.sort "dates.lastModified", -1
    query.where "entitiesInvolved.type", choices.entities.BUSINESS
    query.where "entitiesInvolved.id", businessId
    query.where "who.type", choices.entities.CONSUMER
    query.where "who.screenName", screenName
    query.fields [
      "who.type"
      , "who.screenName"
      , "what"
      , "when"
      , "where"
      , "events"
      , "dates"
      , "data"
      , "feedSpecificData.involved"
    ]
    query.exec callback

  @consumerPersonal: (consumerId, options, callback)->
    query = @optionParser(options)
    query.sort "dates.lastModified", -1
    query.where "who.type", choices.entities.CONSUMER
    query.where "who.id", consumerId
    query.fields [
      "who.type"
      , "who.name"
      , "who.id"
      , "by"
      , "what"
      , "when"
      , "where"
      , "events"
      , "dates"
      , "data"
      , "feedSpecificData.involved"
    ]
    query.exec callback

  @getLatest: (entity, limit, offset, callback)->
    query = @_query()
    query.limit limit
    query.skip offset
    query.sort "dates.lastModified", -1
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


## Statistics ##
class Statistics extends API
  @model: Statistic

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
  @withTapIns: (org, skip, callback)->
    query = Statistics.query()
    query.where("org.type", org.type)
    query.where("org.id", org.id)
    query.where("data.tapIns.totalTapIns").gt(0)
    query.limit(25) #we don't accept limit as an argument because it holds up the event loop
    query.skip(skip)
    query.exec (error, statistics)->
      if error?
        callback(error)
      else
        callback(error, statistics)
        # customerIds
        # for customer in statistics
        #   customerIds.push(customer.consumerId)
        #   delete customer.consumerId

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

  @btTapped: (org, consumerId, transactionId, spent, timestamp, callback)->
    if Object.isString(org.id)
      org.id = new ObjectId(org.id)

    if Object.isString(consumerId)
      consumerId = new ObjectId(consumerId)

    if Object.isString(transactionId)
      transactionId = new ObjectId(transactionId)

    $inc = {}
    $inc["data.tapIns.totalTapIns"] = 1
    $inc["data.tapIns.totalAmountPurchased"] = parseFloat(spent) #parse just incase it's a string

    $set = {}
    $set["data.tapIns.lastVisited"] = new Date(timestamp) #if it is a string it will become a date hopefully

    $push = {}
    $push["transactions.ids"] = transactionId

    $update = {
      $set: $set
      $inc: $inc
      $push: $push
    }

    @model.collection.update {org: org, consumerId: consumerId}, $update, {safe: true, upsert: true }, callback
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


## PasswordResetRequests ##
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


exports.DBTransactions = DBTransactions
exports.Consumers = Consumers
exports.Clients = Clients
exports.Businesses = Businesses
exports.Polls = Polls
exports.Discussions = Discussions
exports.Medias = Medias
exports.ClientInvitations = ClientInvitations
exports.Tags = Tags
exports.EventRequests = EventRequests
exports.Events = Events
exports.BusinessTransactions = BusinessTransactions
exports.BusinessRequests = BusinessRequests
exports.Streams = Streams
exports.Statistics = Statistics
exports.PasswordResetRequests = PasswordResetRequests