exports = module.exports

bcrypt = require "bcrypt"
uuid = require "node-uuid"
generatePassword = require "password-generator"
util = require "util"
async = require "async"

globals = require "globals"
loggers = require "./loggers"

db = require "./db"
tp = require "./transactions" #transaction processor

logger = loggers.api

config = globals.config
utils = globals.utils
choices = globals.choices
defaults = globals.defaults
errors = globals.errors
transloadit = globals.transloadit
guidGen = globals.guid
fb = globals.facebook
urlShortner = globals.urlShortner
hashlib = globals.hashlib

ObjectId = globals.mongoose.Types.ObjectId
Binary = globals.mongoose.mongo.BSONPure.Binary

DBTransaction = db.DBTransaction
Sequence = db.Sequence
Client = db.Client
RedemptionLog = db.RedemptionLog
Consumer = db.Consumer
Goody = db.Goody
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
UnclaimedBarcodeStatistic = db.UnclaimedBarcodeStatistic
Organization = db.Organization
Referral = db.Referral
Barcode = db.Barcode
CardRequest = db.CardRequest
EmailSubmission = db.EmailSubmission

#TODO:
#Make sure that all necessary fields exist for each function before sending the query to the db

 ## API ##

## API ##
class API
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


## Database Transactions ##
class DBTransactions extends API
  @model: DBTransaction


## Sequences ##
class Sequences extends API
  @model: Sequence

  @current: (key, callback)->
    $fields = {}
    $fields[key] = 1
    @model.collection.findOne {_id: new ObjectId(0)}, {fields: $fields}, (error, doc)->
      if error?
        callback(error)
      else if !doc?
        callback({"sequence": "could not find sequence document"})
      else
        callback(null, doc[key])

  @next: (key, count, callback)->
    if Object.isFunction(count)
      callback = count
      count = 1

    $inc = {}
    $inc[key] = count

    $update = {$inc: $inc}

    $fields = {}
    $fields[key]= 1

    @model.collection.findAndModify {_id: new ObjectId(0)}, [], $update, {new: true, safe: true, fields: $fields, upsert: true}, (error, doc)->
      if error?
        callback(error)
      else if !doc?
        callback({"sequence": "could not find sequence document"})
      else
        callback(null, doc[key])


## Redemption Logs ##
class RedemptionLogs extends API
  @model = RedemptionLog

  @add = (consumer, org, locationId, registerId, goody, dateRedeemed, transactionId, callback)->
    try
      if Object.isString consumer.id
        consumer.id = new ObjectId consumer.id
      if Object.isString org.id
        org.id = new ObjectId org.id
      if Object.isString locationId
        locationId = new ObjectId locationId
      if Object.isString registerId
        registerId = new ObjectId registerId
    catch error
      logger.error error
      callback(error)
      return

    doc = {
      _id: transactionId
      consumer: consumer
      org: org
      locationId: locationId
      registerId: registerId
      goody: {
        id: goody._id
        name: goody.name
        karmaPointsRequired: goody.karmaPointsRequired
      }

      dates: {
        created: new Date()
        redeemed: dateRedeemed
      }

      transactions : {
        ids : [transactionId]
      }
    }

    @model.collection.insert doc, {safe: true}, (error, logEntry)->
      if error?
        logger.error(error)
        cb(error)
        return
      callback(error, logEntry)
      return


## Users ##
class Users extends API
  #start potential new API functions
  #model.findById id, fields, options callback
  #model.findOne
  @_sendFacebookPicToTransloadit = (entityId, screenName, guid, picURL, callback)->
    logger.debug ("TRANSLOADIT - send fbpic - "+"notifyURL:"+config.transloadit.notifyURL+",guid:"+guid+",picURL:"+picURL+",entityId:"+entityId)
    client = new transloadit(config.transloadit.authKey, config.transloadit.authSecret)
    params = {
      auth: {
        key: config.transloadit.authKey
      }
      notify_url: config.transloadit.notifyURL
      template_id: config.transloadit.consumerFromURLTemplateId
      steps: {
        ':original':
          robot: '/http/import'
          url  : picURL
        export85:
          path: "consumers/"+entityId+"-85.png"
        export128:
          path: "consumers/"+entityId+"-128.png"
        export85Secure:
          path: "consumers-secure/"+screenName+"-85.png"
        export128Secure:
          path: "consumers-secure/"+screenName+"-128.png"
      }
    }
    fields = {
      mediaFor: "consumer"
      entityId: entityId.toString()
      guid: guid
    }
    client.send params, fields
      ,(success)->
        logger.debug "Transloadit Response - "+success
        if callback?
          callback null, true
        return
      ,(error)->
        #callback new errors.TransloaditError('Uh oh, looks like there was a problem updating your profile picture.', error)
        logger.error new errors.TransloaditError('Transloadit error on facebook login, updating profile picture', error)
        if callback?
          callback error
        return
    return

  @_updatePasswordHelper = (id, password, callback)->
    #this function is a helper to update a users password
    #ussually a user has to enter their previous password or
    #have a secure reset-password link to update their password.
    #do not call this function directly.. w/out security.
    self = this
    @encryptPassword password, (error, hash)->
      if error?
        callback new errors.ValidationError "Invalid Password", {"password":"Invalid Password"} #error encrypting password, so fail
        return
      #password encrypted successfully
      password = hash
      self.update id, {password: hash}, callback
      return

  @one: (id, fieldsToReturn, dbOptions, callback)->
    if Object.isString id
      id = new ObjectId id
    if id instanceof ObjectId
      id = { _id: id }
    if Object.isFunction fieldsToReturn && !fieldsToReturn?
      #Fields to return must always be specified for consumers...
      callback new errors.ValidationError {"fieldsToReturn","Database error, fields must always be specified."}
      dbOptions = {safe:true}
      return
      # callback = fieldsToReturn
      # fields = {}
    if Object.isFunction dbOptions
      callback = dbOptions
      dbOptions = {}
    @model.findOne id, fieldsToReturn, dbOptions, callback
    return

  @update: (id, doc, dbOptions, callback)->
    if Object.isString id
      id = new ObjectId id
    if Object.isFunction dbOptions
      callback = dbOptions
      dbOptions = {safe:true}
    #id typecheck is done in .update
    where = {_id:id}
    @model.update where, doc, dbOptions, callback
    return

  #end potential new API functions

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
      return
    return

  @validatePassword: (id, password, callback)->
    if(Object.isString(id))
      id = new ObjectId(id)

    query = @_query()
    query.where('_id', id)
    query.fields(['password'])
    query.findOne (error, user)->
      if error?
        callback error, user
        return
      else if user?
        bcrypt.compare password+defaults.passwordSalt, user.password, (error, valid)->
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
        callback new errors.ValidationError "Invalid id", {"id": "invalid"}
        return

  @login: (email, password, fieldsToReturn, callback)->
    if Object.isFunction fieldsToReturn
      callback = fieldsToReturn
      fieldsToReturn = {}
    if !Object.isEmpty fieldsToReturn || fieldsToReturn.password!=1
      #if the fieldsToReturn is not 'empty' - which would return all fields
      #add the password field, bc is it is necessary to verify the password.
      fieldsToReturn.password = 1
      addedPasswordToFields = true #to determine whether to remove before executing the callback
    if !fieldsToReturn.facebook? || fieldsToReturn["facebook.id"]!=1
      fieldsToReturn["facebook.id"] = 1
    query = @_query()
    query.where('email', email)#.where('password', password)
    query.fields(fieldsToReturn)
    query.findOne (error, consumer)->
      if error?
        callback error, consumer
        return
      else if consumer?
        # It's really not necessary
        # if consumer.facebook? && consumer.facebook.id? #if facebook user
        #   callback new errors.ValidationError "Please authenticate via Facebook", {"login":"invalid authentication mechanism - use facebook"}
        #   return
        bcrypt.compare password+defaults.passwordSalt, consumer.password, (error, success)->
          if error? or !success
            callback new errors.ValidationError "Invalid Password", {"login":"invalid password"}
          else
            delete consumer._doc.password
            callback null, consumer
          return
      else
        callback new errors.ValidationError "Invalid Email Address", {"login":"invalid email address"}
        return

  @getByEmail: (email, fieldsToReturn, callback)->
    if Object.isFunction fieldsToReturn
      callback = fieldsToReturn
      fieldsToReturn = {} #all fields
    query = @_query()
    query.where('email', email)
    query.fields(fieldsToReturn)
    query.findOne (error, user)->
      if error?
        callback error #db error
      else
        callback null, user #if no consumer with that email will return null
      return
    return

  @updateWithPassword: (id, password, data, callback)->
    self = this
    if Object.isString(id)?
      id = new ObjectId(id)
    @validatePassword id, password, (error, success)->
      if error?
        logger.error error
        e = new errors.ValidationError({"Invalid password, unable to save.","password":"Unable to validate password"})
        callback(e)
        return
      else if !success #true/false
        e = new errors.ValidationError("Incorrect password.", {"password":"Incorrect Password"})
        callback(e)
        return

      async.series {
        encryptPassword: (cb)->#only if the user is trying to update their password field
          if data.password?
            self.encryptPassword data.password, (error, hash)->
              if error?
                callback new errors.ValidationError "Invalid password, unable to save.", {"password":"Unable to encrypt password"} #error encrypting password, so fail
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
          query = self._query()
          query.where('_id', id)
          query.findOne (error, client)->
            if error?
              callback error
              cb(error)
              return
            else if client?
              set = data
              self.update id, {$set:set}, callback
              return
            else #!client?
              e = new errors.ValidationError "Incorrect password.",{'password':"Incorrect Password"} #invalid login error
              callback(e)
              cb(e)
              return
          return
      },
      (error, results)->
        return
    return

  @updateWithFacebookAuthNonce: (id, facebookAccessToken, facebookAuthNonce, data, callback)->
    self = this
    url = '/oauth/access_token_info'
    options = {
      client_id:config.facebook.appId
    }
    fb.get url, facebookAccessToken, options, (error, accessTokenInfo)->
      #we don't care if the nonce has been used or not..
      #verify that the nonce from FB matches the nonce from the user..
      if(accessTokenInfo.auth_nonce != facebookAuthNonce)
        callback new errors.ValidationError('Facebook authentication errors.', {'Auth Nonce':'Incorrect.'})
      else
        set = data
        self.update id, {$set:set}, callback
      return
    return

  @updateMedia: (id, media, callback)->
    self = this
    #id typecheck is done in @update
    #media.mediaId typecheck is done in validateMedia
    Medias.validateAndGetMediaURLs "consumer", id, "consumer", media, (error, validatedMedia)->
      if error?
        callback error
        return
      logger.silly validatedMedia
      update = {}
      if !validatedMedia?
        mediaToReturn = null
        update.$unset = {media:1}
      else
        mediaToReturn = validatedMedia
        update.$set = {media:validatedMedia}

      self.update id, update, (error, count)-> #error,count
        if error?
          callback error
          return
        if count==0
          callback new errors.ValidationError {"id":"Consumer Id not found."}
        else
          callback null, mediaToReturn #send back the media object
        return
      return
    return

  @updateMediaWithFacebook: (id, screenName, fbid, callback)->
    self = this
    if Object.isString id
      id = new ObjectId id

    accessToken = ""
    async.series
      accessToken: (callback)->
        self.model.findById id, {"facebook.access_token":1}, (error,user)->
          if error?
            callback error
            return
          #success
          accessToken = user.facebook.access_token #sets access token to be used in the next step
          callback null, accessToken
          return
      fbPicURL: (callback)->
        fb.get ["me/picture"], accessToken, (error,fbData)-> #right now the batch call
          if error?
            callback error
            return
          picResponse = fbData[0]

          if picResponse.headers[5].name == "Location" #hard-coded to get the Location header from the response headers
            fbPicURL = picResponse.headers[5].value;
          else
            #since the above index is hard-coded, just in case the header index of Location changes
            #search for the Location header
            for i,v in picResponse.headers
              if v.name == "Location"
                fbPicURL = v.value
          #facebook pic retrieved
          if !fbPicURL? || fb.isDefaultProfilePic(fbPicURL,fbid)
            callback new errors.ValidationError {"pic":"Since you have no facebook picture, we left your picture as the default goodybag picture."}
            return
          #user has fb pic
          callback null, fbPicURL
          return
    ,(error, data)->
      if error?
        callback error
        return
      #success got accessToken and got fbPicURL
      guid = guidGen.v1()
      media ={
        guid:  guid
        thumb: data.fbPicURL
        url: data.fbPicURL
        mediaId: null
      }
      set = {
        media          : media
        "facebook.pic" : data.fbPicURL
      }
      self.update {_id:id}, {$set:set}, (error,success)->
        if error?
          callback error
          return
        #media update success
        self._sendFacebookPicToTransloadit id, screenName, guid, data.fbPicURL, (error, success)->
          if error?
            callback error
          else
            callback null, media
          return
        return
    return
  @updateMediaByGuid: (id, guid, mediasDoc, callback)->
    if(Object.isString(id))
      id = new ObjectId(id)

    query = @_query()
    query.where("_id", id)
    query.where("media.guid", guid)
    set = {
      media       : Medias.mediaFieldsForType mediasDoc, "consumer"
      secureMedia : Medias.mediaFieldsForType mediasDoc, "consumer-secure"
    }

    query.update {$set:set}, (error, success)->
      if error?
        callback error #dberror
      else
        callback null, success
      return
    return

  @delMedia: (id,callback)->
    if Object.isString id
      id = new ObjectId id
    @model.update {_id:id}, {$set:{"permissions.media":false},$unset:{media:1,secureMedia:1,"facebook.pic":1}}, callback
    return

  #@updateEmail
  @updateEmailRequest: (id, password, newEmail, callback)->
    logger.debug "###### ID ######"
    logger.debug id
    #id typecheck is done in @update
    @getByEmail newEmail, (error, user)->
      if error?
        callback error
        return
      if user?
        if id == user._id
          callback new errors.ValidationError("That is your current email",{"email":"That is your current email"})
        else
          callback new errors.ValidationError("Another user is already using this email",{"email":"Another user is already using this email"}) #email exists error
        return
    data = {}
    data.changeEmail =
      newEmail: newEmail
      key: hashlib.md5(config.secretWord + newEmail+(new Date().toString()))+'-'+generatePassword(12, false, /\d/)
      expirationDate: Date.create("next week")
    @updateWithPassword id, password, data, (error, count)-> #error,count
      if count==0
        callback new errors.ValidationError({"password":"Incorrect password."}) #assuming id is correct..
        return
      #success or errors..
      callback error, data.changeEmail
      return
    return

  @updateFBEmailRequest: (id, facebookAccessToken, facebookAuthNonce, newEmail, callback)->
    #id typecheck is done in @update
    @getByEmail newEmail, (error, user)->
      if error?
        callback error
        return
      if user?
        if id == user._id
          callback new errors.ValidationError("That is your current email",{"email":"That is your current email"})
        else
          callback new errors.ValidationError("Another user is already using this email",{"email":"Another user is already using this email"}) #email exists error
        return
    data = {}
    data.changeEmail =
      newEmail: newEmail
      key: hashlib.md5(config.secretWord + newEmail+(new Date().toString()))+'-'+generatePassword(12, false, /\d/)
      expirationDate: Date.create("next week")
    @updateWithFacebookAuthNonce id, facebookAccessToken, facebookAuthNonce, data, (error, count)-> #error,count
      if error
        callback error
      #success..
      callback error, data.changeEmail
      return
    return

  @updateEmailComplete: (key, callback)->
    query = @_query()
    query.where('changeEmail.key', key)
    query.fields("changeEmail")
    query.findOne (error, user)->
      if error?
        callback error #dberror
        return
      if !user?
        callback new errors.ValidationError({"key":"Invalid key, expired or already used."})
        return
      #user found
      user = user._doc
      if(new Date()>user.changeEmail.expirationDate)
        callback new errors.ValidationError({"key":"Key expired."})
        query.update {$set:{changeEmail:null}}, (error, success)->
          return #clear expired email request.
        return
      query.update {$set:{email:user.changeEmail.newEmail, changeEmail:null}}, (error, count)->
        if error?
          if errors.code is 11000 or errors.code is 11001
            callback new errors.ValidationError "Email Already Exists", {"email": "Email Already Exists"} #email exists error
          else
            callback error #dberror
          return
        callback null, user.changeEmail.newEmail
        return
      return
    return


## Consumers ##
class Consumers extends Users
  @model = Consumer

  @initialUpdate: (entity, data, callback)->
    if Object.isString(entity.id)
      entity.id = new ObjectId(entity.id)

    set = {}

    if !utils.isBlank(data.barcodeId)
      logger.silly "addBarcodeId"
      set.barcodeId = data.barcodeId
    if !utils.isBlank(data.affiliationId)
      #you can only set one for now...via the more info modal
      logger.silly "addAffil"
      affiliationId = new ObjectId affiliationId
      set["profile.affiliations"] = [data.affiliationId]

    #if session screenName not set and screeName not passed in..
    if utils.isBlank(data.screenName)
      callback new errors.ValidationError "Alias is required.", {"screenName":"required"}
      return
    else
      logger.silly "addScreenName"
      set.screenName = data.screenName
      set.setScreenName = true

    if Object.isEmpty set
      callback new errors.ValidationError "Nothing to update..", {"update":"required"}
      return

    entity.screenName = data.screenName

    $pushAll = {}
    if set.barcodeId?
      transactionData = {}

      btTransaction = @createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.BT_BARCODE_CLAIMED, transactionData, choices.transactions.directions.OUTBOUND, entity)
      statTransaction = @createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.STAT_BARCODE_CLAIMED, transactionData, choices.transactions.directions.OUTBOUND, entity)

      $pushAll = {
        "transactions.ids": [btTransaction.id, statTransaction.id]
        "transactions.log": [btTransaction, statTransaction]
      }

    $update = {$pushAll: $pushAll, $set: set}

    $query = {_id: entity.id, setScreenName: false}

    if set.barcodeId?
       $query.barcodeId = {$ne: set.barcodeId}

    fieldsToReturn = {_id: 1, barcodeId: 1}
    @model.collection.findAndModify $query, [], $update, {safe: true, fields: fieldsToReturn, new: true}, (error, consumer)->
      if error?
        if error.code is 11000 or error.code is 11001
          if(error.message.indexOf("barcodeId"))
            callback new errors.ValidationError "Sorry, that TapIn Id is already taken.", {"TapIn Id":"not unique"}
          else
            callback new errors.ValidationError "Sorry, that Alias is already taken.", {"screenName":"not unique"}
          return
        callback error
        return
      else if !consumer? #if there is no consumer object that means that you are already using this barcodeId, so error, because we don't want to run the transactions twice!!
        callback new errors.ValidationError "This is already your TapIn code, or you've already set your alias", {"barcodeId": "this is already your tapIn code", "screenname": "already set"}
        return
      #success
      if set.barcodeId?
        tp.process(consumer, btTransaction)
        tp.process(consumer, statTransaction)
      success = if consumer? then true else false
      callback null, success
    return

  # List all consumers (limit to 25 at a time for now - not taking in a limit arg on purpose)
  @getIdsAndScreenNames: (options, callback)->
    if Object.isFunction(options)
      callback = options
      options = {}
    query = @query()
    query.only("_id", "screenName", "setScreenName")
    query.skip(options.skip || 0)
    query.limit(options.limit || 25)
    query.exec callback

  @getScreenNamesByIds: (ids, callback)->
    query = @query()
    query.only(["_id", "screenName", "setScreenName"])
    query.in("_id", ids)

    query.exec callback
    return

  ### _getByBarcodeId_ ###
  #
  # get a consumer by the barcodeId
  #
  # Various argument possibilities
  #
  # - barcodeId, callback
  # - barcodeId, fields, callback
  #
  # **barcodeId** _String_ the barcode<br />
  # **fields** _Dict_ list of fields to return< br />
  # **callback** _Function_ (error, consumer)
  @getByBarcodeId: (barcodeId, fields, callback)->
    if Object.isFunction(fields)
      callback = fields
      fields = null

    $query = {$or: [{barcodeId: barcodeId}, {"updateVerification.data.barcodeId": barcodeId, "updateVerification.expiration": {$gt: new Date()} }]}
    @model.collection.findOne $query, fields, (error, consumer)->
      if error?
        callback error
        return
      callback null, consumer
      return

  ### _findByBarcodeIds_ ###
  #
  # Find conusmers who have the given barcodeIds. Ignore pending
  #
  # Various argument possibilities
  #
  # - barcodeIds, callback
  # - barcodeIds, fields, callback
  #
  # **barcodeId** _Array_ the barcodes<br />
  # **fields** _Dict_ list of fields to return< br />
  # **callback** _Function_ (error, consumer)
  @findByBarcodeIds:(barcodeIds, fields, callback)->
    if Object.isFunction(fields)
      callback = fields
      fields = null

    $query = { barcodeId: {$in: barcodeIds} }
    @model.collection.find $query, fields, (error, cursor)->
      if error?
        callback(error)
        return

      cursor.toArray (error, consumers)->
        callback null, consumers
        return

  @getByEmail: (email, fields, callback)->
    if Object.isFunction(fields)
      callback = fields
      fields = null

    $query = {email: email}
    @model.collection.findOne $query, {fields: fields}, (error, consumer)->
      if error?
        callback error
        return
      callback null, consumer
      return

  @updateBarcodeId: (entity, barcodeId, callback)->
    if Object.isString(entity.id)
      entity.id = new ObjectId(entity.id)

    if !barcodeId?
      callback(null, false)
      return

    $query = {_id: entity.id, barcodeId: {$ne: barcodeId}}

    transactionData = {}

    btTransaction = @createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.BT_BARCODE_CLAIMED, transactionData, choices.transactions.directions.OUTBOUND, entity)
    statTransaction = @createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.STAT_BARCODE_CLAIMED, transactionData, choices.transactions.directions.OUTBOUND, entity)

    $set = {
      barcodeId: barcodeId
    }

    $pushAll = {
      "transactions.ids": [btTransaction.id, statTransaction.id]
      "transactions.log": [btTransaction, statTransaction]
    }

    $update = {$pushAll: $pushAll, $set: $set}

    fieldsToReturn = {_id: 1, barcodeId: 1}
    @model.collection.findAndModify $query, [], $update, {safe: true, fields: fieldsToReturn, new: true}, (error, consumer)->
      if error?
        if error.code is 11000 or error.code is 11001
          callback new errors.ValidationError "TapIn code is already in use", {"barcodeId": "tapIn code is already in use"}
          return
        callback error
        return
      else if !consumer? #if there is no consumer object that means that you are already using this barcodeId, so error, because we don't want to run the transactions twice!!
        callback new errors.ValidationError "This is already your TapIn code", {"barcodeId": "this is already your tapIn code"}
        return
      #success
      tp.process(consumer, btTransaction)
      tp.process(consumer, statTransaction)
      success = if consumer? then true else false
      callback null, success
    return

  # different that update, because update checks if you've already claimed it, this doesn't
  @claimBarcodeId: (entity, barcodeId, callback)->
    if Object.isString(entity.id)
      entity.id = new ObjectId(entity.id)

    if !barcodeId?
      callback(null, false)
      return

    $query = {_id: entity.id}
    transactionData = {}

    btTransaction = @createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.BT_BARCODE_CLAIMED, transactionData, choices.transactions.directions.OUTBOUND, entity)
    statTransaction = @createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.STAT_BARCODE_CLAIMED, transactionData, choices.transactions.directions.OUTBOUND, entity)

    $set = {
      barcodeId: barcodeId
    }

    $pushAll = {
      "transactions.ids": [btTransaction.id, statTransaction.id]
      "transactions.log": [btTransaction, statTransaction]
    }

    $update = {$pushAll: $pushAll, $set: $set}

    fieldsToReturn = {_id: 1, barcodeId: 1}
    @model.collection.findAndModify $query, [], $update, {safe: true, fields: fieldsToReturn, new: true}, (error, consumer)->
      if error?
        callback error
        return
      else if !consumer?
        callback new errors.ValidationError "Consumer with that identifer doesn't exist"
        return
      #success
      tp.process(consumer, btTransaction)
      tp.process(consumer, statTransaction)
      success = if consumer? then true else false
      callback null, success
    return

  ###
  # acceptable parameters
  # uid, value, callback
  # uid, accessToken, value, callback
  ###
  @updateTapinsToFacebook: (uid, accessToken, value, callback)->
    if Object.isBoolean(accessToken)
      callback = value
      value = accessToken

    if !value?
      callback(null, false)
      return
    if value is true
      if !accessToken?
        callback {message: "There was not enough information from facebook to complete this request"}
        return
      logger.silly "attempting to save tapIns To Facebook"
      fb.get 'me/permissions', accessToken, (error, response)=>
        permissions = response.data[0]
        logger.debug permissions
        if error?
          callback {message: "Sorry, it seems facebook isn't responding right now, please try again in a short while."}
          return
        else if permissions? and permissions.publish_stream is 1 and permissions.offline_access is 1
          logger.silly "Permissions are good. Saving tapIns to Facebook value"
          @update uid, {tapinsToFacebook: true, "facebook.access_token": accessToken}, (error, count)->
            if error?
              callback error
              return
            callback null, count #should be 1 or 0, since update by Id
            return
        else
          callback {message: "Not Enough Permissions"}
          return
    else #value is false
      logger.silly "attempting to no longer saving tapIns To Facebook"
      @update uid, {tapinsToFacebook: false}, (error, count)->
        if error?
          callback error
          return
        callback null, count #should be 1 or 0, since update by Id
        return

  @register: (data, fieldsToReturn, callback)->
    self = this
    data.aliasId = new ObjectId()
    @encryptPassword data.password, (error, hash)->
      if error?
        callback new errors.ValidationError "Invalid Password", {"password":"Invalid Password"} #error encrypting password, so fail
        return
      else
        data.password = hash
        data.referralCodes = {}
        Sequences.next 'urlShortner', 2, (error, sequence)->
          if error?
            callback error #dberror
            return
          tapInCode = urlShortner.encode(sequence-1)
          userCode = urlShortner.encode(sequence)
          data.referralCodes.tapIn = tapInCode
          data.referralCodes.user = userCode

          self.add data, (error, consumer)->
            if error?
              if error.code is 11000 or error.code is 11001
                callback new errors.ValidationError "Email Already Exists", {"email":"Email Already Exists"} #email exists error
              else
                callback error
            else
              entity = {
                type: choices.entities.CONSUMER
                id: consumer._doc._id
              }

              Referrals.addUserLink(entity, "/", userCode)
              Referrals.addTapInLink(entity, "/", tapInCode)

              consumer = self._copyFields(consumer, fieldsToReturn)
              callback error, consumer
            return
        return
      return
    return

  ### _registerPendingAndClaim_ ###
  #
  # register the consumer and claim past tap-ins<br />
  # add a signupVerification key and expiration.<br />
  # This will enable the user to claim this account.
  @registerAsPendingAndClaim: (data, fields, callback)->
    if Object.isFunction(fields)
      callback = fields
      fields = null

    data.signUpVerification = {}
    data.signUpVerification.key = hashlib.md5(data.email) + "|" + uuid.v4()
    data.signUpVerification.expiration = Date.create().addYears(1)
    @register data, fields, (error, consumer)->
      if error?
        callback error
        return
      callback null, consumer

      entity = {
        id: consumer._id
        name: "#{consumer.firstName} #{consumer.lastName}"
        screenName: consumer.screenName
      }

      Consumers.claimBarcodeId entity, consumer.barcodeId, (error)->
        if error?
          logger.error error

  ### _tapInUpdateData_ ###
  #
  # Store the values to modify if the update is verified
  #
  # this is usually the barcodeId and charity
  #
  # **id** _String/ObjectId_ the consumerId<br />
  # **data** _Object_ the fields to set<br />
  # **fields** _Object_ list of fields to return< br />
  # **callback** _Function_ (error, consumer)
  @tapInUpdateData: (id, data, fields, callback)->
    if Object.isFunction(fields)
      callback = fields
      fields = null

    if Object.isString(id)
      id = new ObjectId(id)

    $set = {}
    $set.updateVerification = {
      key: id.toString() + "|" + uuid.v4()
      expiration: Date.create().addWeeks(2)
      data: {}
    }

    if data.charity?
      $set.updateVerification.data.charity = data.charity
    if data.barcodeId?
      $set.updateVerification.data.barcodeId = data.barcodeId

    @model.collection.findAndModify {_id: id}, [], {$set: $set}, {fields: fields, new: true, safe: true}, (error, consumer)->
      if error?
        logger.error
        callback {name: "DatabaseError", message: "Unable to update the consumer"}
        return
      callback null, consumer

  @getFacebookData: (accessToken, callback)->
    #verify accessToken and get User Profile
    urls = ["app","me","me/picture"]
    fb.get urls, accessToken, (error,data)->
      if error?
        callback error
        return
      appResponse = data[0] #same order as url array..
      meResponse = data[1]
      picResponse = data[2]
      if appResponse.code!=200
        callback new errors.HttpError 'Error connecting with Facebook, try again later.', 'facebookBatch:'+urls[0], appResponse.code
        return
      logger.silly "#####################################"
      logger.silly JSON.parse(appResponse.body).id
      logger.silly config.facebook.appId
      logger.silly "%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%"
      if JSON.parse(appResponse.body).id != config.facebook.appId
        return callback new errors.ValidationError {'accessToken':"Incorrect access token. Not for Goodybag's app."}
      if meResponse.code!=200
        callback new errors.HttpError 'Error connecting with Facebook, try again later.', 'facebookBatch:'+urls[1], appResponse.code
        return
      if picResponse.code!=302&&picResponse.code!=200&&picResponse.code!=301 #this should be a 302..
        callback new errors.HttpError 'Error connecting with Facebook, try again later.', 'facebookBatch:'+urls[1], appResponse.code
        return

      meResponse.body = JSON.parse(meResponse.body)
      fbid = meResponse.body.id
      if picResponse.headers[5].name == "Location" #hard-coded to get the Location header from the response headers
        fbPicURL = picResponse.headers[5].value;
      else
        #since the above index is hard-coded, just in case the header index of Location changes
        #search for the Location header
        for i,v in picResponse.headers
          if v.name == "Location"
            fbPicURL = v.value

      facebookData =
        me  : meResponse.body
        pic : if !fbPicURL? || fb.isDefaultProfilePic(fbPicURL, fbid) then null else fbPicURL #check if pic is default fb pic, if it is ignore it. picResponse.body should just be a string of the url..
      callback null, facebookData

  @facebookLogin: (accessToken, fieldsToReturn, referralCode, callback)->
    #** fieldsToReturn needs to include screenName **
    if Object.isFunction fieldsToReturn
      callback = fieldsToReturn
      fieldsToReturn = {}
    self = this
    accessToken = accessToken.split("&")[0]
    #verify accessToken and get User Profile
    urls = ["app","me","me/picture"]
    fb.get urls, accessToken, (error,data)->
      if error?
        callback error
        return
      appResponse = data[0] #same order as url array..
      meResponse = data[1]
      picResponse = data[2]
      if appResponse.code!=200
        callback new errors.HttpError 'Error connecting with Facebook, try again later.', 'facebookBatch:'+urls[0], appResponse.code
        return
      if JSON.parse(appResponse.body).id != config.facebook.appId
        callback new errors.ValidationError {'accessToken':"Incorrect access token. Not for Goodybag's app."}
      if meResponse.code!=200
        callback new errors.HttpError 'Error connecting with Facebook, try again later.', 'facebookBatch:'+urls[1], appResponse.code
        return
      if picResponse.code!=302&&picResponse.code!=200&&picResponse.code!=301 #this should be a 302..
        callback new errors.HttpError 'Error connecting with Facebook, try again later.', 'facebookBatch:'+urls[1], appResponse.code
        return

      meResponse.body = JSON.parse(meResponse.body)
      fbid = meResponse.body.id
      if picResponse.headers[5].name == "Location" #hard-coded to get the Location header from the response headers
        fbPicURL = picResponse.headers[5].value;
      else
        #since the above index is hard-coded, just in case the header index of Location changes
        #search for the Location header
        for i,v in picResponse.headers
          if v.name == "Location"
            fbPicURL = v.value

      facebookData =
        me  : meResponse.body
        pic : if !fbPicURL? || fb.isDefaultProfilePic(fbPicURL, fbid) then null else fbPicURL #check if pic is default fb pic, if it is ignore it. picResponse.body should just be a string of the url..
      createOrUpdateUser(facebookData)
      return

    #create user if new, or update user where fbid
    createOrUpdateUser = (facebookData)->
      fbid = facebookData.me.id
      consumer = {
        firstName: facebookData.me.first_name,
        lastName:  facebookData.me.last_name,
        #email:     facebookData.me.email #this is set only for new users, bc users can edit their email
      }
      consumer['facebook.access_token'] = accessToken
      consumer['facebook.id'] = facebookData.me.id
      consumer['facebook.me'] = facebookData.me
      consumer['facebook.pic']= facebookData.pic if facebookData.pic?

      consumer['profile.birthday'] = if facebookData.me.birthday? then utils.setDateToUTC(facebookData.me.birthday)
      consumer['profile.gender']   = facebookData.me.gender
      consumer['profile.location'] = if facebookData.me.location? then facebookData.me.location.name
      consumer['profile.hometown'] = if facebookData.me.hometown? then facebookData.me.hometown.name
      #consumer['profile.work']      = facebookData.me.work
      #consumer['profile.education'] = facebookData.me.education

      #find user with fbid or same email
      self.model.findOne {$or:[{"facebook.id":facebookData.me.id}, {email:facebookData.me.email}]}, {_id:1,"permissions.media":1,"facebook.fbid":1,"facebook.pic":1}, null, (error,consumerAlreadyRegistered)->
        if error?
          callback error
          return
        else
          callTransloadit = false
          if consumerAlreadyRegistered?
            consumerAlreadyRegistered = consumerAlreadyRegistered._doc #cause mongoose
            # Previously Register User Found
            mediaPermission  = consumerAlreadyRegistered.permissions.media
            facebookPicFound = facebookData.pic?
            facebookPicIsNew = consumerAlreadyRegistered.facebook.pic != facebookData.pic
            if mediaPermission && facebookPicFound && facebookPicIsNew
              # User has
              # * Media permissions set to true - (or no permissions set, this should never be the case..)
              # * Facebook Profile picture found (on Facebook, not default picture)
              # * Facebook picture found is not the same as last Facebook picture found.
              # THEN set their GB pic as the FB pic, and send it to transloadit for processing.
              mediaGuid = guidGen.v1()
              consumer.media = {
                guid    : mediaGuid
                url     : facebookData.pic #tempURL
                thumb   : facebookData.pic #tempURL
                mediaId : null
              }
              callTransloadit = true

            self.model.collection.findAndModify {$or:[{"facebook.id":facebookData.me.id}, {email:facebookData.me.email}]}, [], {$set: consumer, $inc: {loginCount:1}}, {fields:fieldsToReturn,new:true,safe:true}, (error, consumerToReturn)->
              callback error, consumerToReturn
              if callTransloadit && !error?
                self._sendFacebookPicToTransloadit consumerToReturn._id, consumerToReturn.screenName, mediaGuid, facebookData.pic
              return
          else
            # Brand New User!
            # generate a random password and screenName...
            consumer.password = hashlib.md5(config.secretWord + facebookData.me.email+(new Date().toString()))+'-'+generatePassword(12, false, /\d/)
            consumer.screenName = new ObjectId()
            self.encryptPassword consumer.password, (error, hash)->
              if error?
                callback new errors.ValidationError "Invalid Password", {"password":"Invalid Password"} #error encrypting password, so fail
                return
              #successful password encryption
              consumer.password = hash
              consumer.email = facebookData.me.email
              consumer.facebook = {}
              consumer.facebook.access_token = accessToken
              consumer.facebook.id = facebookData.me.id
              if facebookData.pic?
                mediaGuid = guidGen.v1()
                consumer.media = {
                  guid    : mediaGuid
                  url     : facebookData.pic
                  thumb   : facebookData.pic
                  mediaId : null
                }
                callTransloadit = true

              consumer.referralCodes = {}
              Sequences.next 'urlShortner', 2, (error, sequence)->
                if error?
                  callback error #dberror
                  return
                tapInCode = urlShortner.encode(sequence-1)
                userCode = urlShortner.encode(sequence)
                consumer.referralCodes.tapIn = tapInCode
                consumer.referralCodes.user = userCode
                #save new user
                newUserModel = new self.model(consumer)
                newUserModel.save (error, newUser)->
                  if error?
                    callback error #dberror
                  else
                    newUserFields = self._copyFields(newUser, fieldsToReturn)
                    callback null, newUserFields

                    #create referral codes in the referral's collection
                    entity = {
                      type: choices.entities.CONSUMER
                      id: newUser._id
                    }

                    Referrals.addUserLink(entity, "/", userCode)
                    Referrals.addTapInLink(entity, "/", tapInCode)

                    if !utils.isBlank(referralCode)
                      Referrals.signUp(referralCode, entity)

                    if callTransloadit
                      self._sendFacebookPicToTransloadit newUser._id, newUser.screenName, mediaGuid, facebookData.pic
                  return
                return
              return
          return

    return #end @facebookLogin

  @getProfile: (id, callback)->
    fieldsToReturn = {
      _id           : 1
      firstName     : 1
      lastName      : 1
      email         : 1
      profile       : 1
      permissions   : 1
    }
    fieldsToReturn["facebook.id"] = 1 #if user has this then the user is a fbUser
    facebookMeFields = {
      work      : 1
      education : 1
    }
    Object.merge fieldsToReturn, @_flattenDoc(facebookMeFields,"facebook.me")
    @one id, fieldsToReturn, (error, consumer)->
      if error?
        callback error
        return
      callback null, consumer
      return
    return

  @getPublicProfile: (id, callback)->
    self = this
    fieldsToReturn = {
      _id           : 1
      firstName     : 1
      lastName      : 1
      email         : 1
      profile       : 1
      permissions   : 1
      media         : 1
    }
    fieldsToReturn["facebook.id"] = 1 #if user has this then the user is a fbUser
    facebookMeFields = {
      work      : 1
      education : 1
    }
    Object.merge fieldsToReturn, @_flattenDoc(facebookMeFields,"facebook.me")
    @one id, fieldsToReturn, (error, consumer)->
      if error?
        callback error
        return

      #user permissions to determine which fields to delete
      if !consumer.permissions.email
        delete consumer.email
      consumer.profile  = self._copyFields(consumer.profile, consumer.permissions)
      consumer.facebook = self._copyFields(consumer.facebook, consumer.permissions)
      for field,idsToRemove of consumer.permissions.hiddenFacebookItems #object of remove id arrays
        #if there are ids to remove, idsToRemove - array of ids to remove from facebook field
        if(idsToRemove? && idsToRemove.length > 0)
          facebookFieldItems = consumer.facebook[field] #array of all items for a facebook field
          #check field items ids to see if they match any that need to be removed
          for i,item in facebookFieldItems
            if(item.id in idsToRemove)        #if id found in the array of ids to remove
              facebookFieldItems.splice(i,1); #remove item from entry array
              break;

      callback null, consumer
      return
    return

  @updateHonorScore: (id, eventId, amount, callback)->
    if Object.isString(id)
      id = new ObjectId(id)

    if Object.isString(eventId)
      eventId = new ObjectId(eventId)

    @model.findAndModify {_id:  id}, [], {$push:{"events.ids": eventId}, $inc: {honorScore: amount}}, {new: true, safe: true}, callback

  @deductFunds: (id, transactionId, amount, callback)->
    if isNaN(amount)
      callback ({message: "amount is not a number"})
      return

    amount = parseInt(amount)

    if amount <0
      callback({message: "amount cannot be negative"})
      return

    if Object.isString(id)
      id = new ObjectId(id)

    if Object.isString(transactionId)
      transactionId = new ObjectId(transactionId)

    @model.collection.findAndModify {_id: id, 'funds.remaining': {$gte: amount}, 'transactions.ids': {$ne: transactionId}}, [], {$addToSet: {"transactions.ids": transactionId}, $inc: {'funds.remaining': -1*amount }}, {new: true, safe: true}, callback

  @incrementDonated: (id, transactionId, amount, callback)->
    logger.debug "incrementing donated"
    if isNaN(amount)
      callback ({message: "amount is not a number"})
      return

    amount = parseInt(amount)

    if amount <=0
      callback({message: "amount cannot be zero or negative"})
      return

    if Object.isString(id)
      id = new ObjectId(id)

    if Object.isString(transactionId)
      transactionId = new ObjectId(transactionId)

    logger.debug "attempting to increment donated for #{id} by: #{amount}"

    @model.collection.findAndModify {_id: id, 'transactions.ids': {$ne: transactionId}}, [], {$addToSet: {"transactions.ids": transactionId}, $inc: {'funds.donated': amount}}, {new: true, safe: true}, callback

  @depositFunds: (id, transactionId, amount, callback)->
    if isNaN(amount)
      callback ({message: "amount is not a number"})
      return

    amount = parseInt(amount)

    if amount <0
      callback({message: "amount cannot be negative"})
      return

    if Object.isString(id)
      id = new ObjectId(id)

    if Object.isString(transactionId)
      transactionId = new ObjectId(transactionId)

    @model.collection.findAndModify {_id: id, 'transactions.ids': {$ne: transactionId}}, [], {$addToSet: {"transactions.ids": transactionId}, $inc: {'funds.remaining': amount, 'funds.allocated': amount }}, {new: true, safe: true}, callback

  @updatePermissions: (id, data, callback)->
    if Object.isString id
      id = new ObjectId(id)
    if !data? && Object.keys(data).length > 1
      callback new errors.ValidationError {"permissions":"You can only update one permission at a time"}
      return

    where = {
      _id: id
    }
    set = {}
    push = {}
    pull = {}
    #pushAll = {}
    consumerModel = new @model
    permissionsKeys = Object.keys(consumerModel._doc.permissions)
    permissionsKeys.remove("hiddenFacebookItems")
    for k,v of data
      permission = "permissions."+k
      if !(k in permissionsKeys)
        callback new errors.ValidationError {"permissionKey":"Unknown value."}
        return
    set[permission] = v=="true" or v==true

    doc = {}
    if !Object.isEmpty(set)
      doc["$set"] = set
    else
      callback new errors.ValidationError {"data":"No new updates."}
      return

    @model.update where, doc, {safe:true}, callback
    return

  @updateHiddenFacebookItems: (id,data,callback)->
    if Object.isString id
      id = new ObjectId(id)
    if !data?
      callback new errors.ValidationError {"data":"No update data."}
      return
    if Object.keys(data).length > 1
      callback new errors.ValidationError {"entry":"You can only update one entry at a time"}
      return

    where = {
      _id: id
    }
    push = {}
    pull = {}

    facebookItemKeys = ["work","education"]
    for entry,fbid of data
      if !(entry in facebookItemKeys)
        callback new errors.ValidationError {"facebookItemKey":"Unknown value ("+entry+")."}
        return
      if Object.isString fbid
        if fbid.substr(0,1) == "-"
          fbid = fbid.slice(1)
          where["permissions.hiddenFacebookItems."+entry] = fbid
          pull["permissions.hiddenFacebookItems."+entry] = fbid #id to unhide
        else
          if entry == "work"
            where["facebook.me.work.employer.id"] = fbid
          else if entry == "education"
            where["facebook.me.education.school.id"] = fbid
          push["permissions.hiddenFacebookItems."+entry] = fbid #id to hide
      else
        callback new errors.ValidationError {"fbid":"Invalid value (must be a string)."}
        return

    doc = {}
    if !Object.isEmpty(push)
      doc["$push"] = push
    else if !Object.isEmpty(pull)
      doc["$pull"] = pull
    else
      callback new errors.ValidationError {"data":"No new updates."}
      return
    @model.update where, doc, {safe:true}, callback
    return

  #Consumer profile functions
  @addRemoveWork: (op,id,data,callback)->
    if Object.isString id
      id = new ObjectId id
    if op == "add"
      where = {
        _id : id
        "profile.work.name":{$ne:data.name}
      }
      doc = {
        $push: {
          "profile.work": data
        }
      }
    else if op == "remove"
      where = {
        _id : id
      }
      doc = {
        $pull: {
          "profile.work": data
        }
      }
    else
      callback new errors.ValidationError {"op":"Invalid value."}
      return
    this.model.update where, doc, (error, success)->
      if success==0
        callback new errors.ValidationError "Whoops, looks like you already added that company.", {"name":"Company with that name already added."}
      else
        callback error, success
      return
    return

  @addRemoveEducation: (op,id,data,callback)->
    if Object.isString id
      id = new ObjectId id
    if op == "add"
      where = {
        _id : id
        "profile.education.name":{$ne:data.name}
      }
      doc = {
        $push: {
          "profile.education": data
        }
      }
    else if op == "remove"
      where = {
        _id : id
      }
      doc = {
        $pull: {
          "profile.education": data
        }
      }
    else
      callback new errors.ValidationError {"op":"Invalid value."}
      return
    @model.update where, doc, (error, success)->
      if success==0
        callback new errors.ValidationError "Whoops, looks like you already added that school.", {"name":"School with that name already added."}
      else
        callback error, success
      return
    return

  @addRemoveInterest: (op,id,data,callback)->
    if Object.isString id
      id = new ObjectId id
    if op == "add"
      where = {
        _id : id
        "profile.interests.name":{$ne:data.name}
      }
      doc = {
        $push: {
          "profile.interests": data
        }
      }
    else if op == "remove"
      where = {
        _id : id
      }
      doc = {
        $pull: {
          "profile.interests": data
        }
      }
    else
      callback new errors.ValidationError {"op":"Invalid value."}
      return
    @model.update where, doc, (error, success)->
      if success==0
        callback new errors.ValidationError "Whoops, looks like you already added that interest.", {"name":"Interest already added."}
      else
        callback error, success
      return
    return

  @updateProfile: (id,data,callback)->
    if Object.isString id
      id = new ObjectId id
    where = {
      _id : id
    }

    consumerModel = new @model
    nonFacebookProfileKeys = Object.keys(consumerModel._doc.permissions)
    nonFacebookProfileKeys.remove("aboutme") #allowed to be edit for both fb and nonfb users
    for key of data
      if key in nonFacebookProfileKeys
        where["facebook.id"] = {$exists:false}

    data = @_flattenDoc data, "profile"
    @model.update where, {$set:data}, (error, count)->
      if count==0
        callback new errors.ValidationError {"user":"Facebook User: to update your information edit your profile on facebook."}
        return
      callback error, count
      return
    return

  @addRemoveAffiliation: (op, id, affiliationId, callback)->
    if Object.isString id
      id = new ObjectId id
    if Object.isString affiliationId
      affiliationId = new ObjectId affiliationId

    if op == "add"
      where = {
        _id : id
        "profile.affiliations": {$ne:affiliationId}
      }
      doc = {
        $set: { #this is temporary ... this will eventually be $push..
          "profile.affiliations": [affiliationId]
        }
        # $push: {
        #   "profile.affiliations": affiliationId
        # }
      }
    else if op == "remove"
      where = {
        _id : id
      }
      doc = {
        $set: {
          "profile.affiliations": []
        }
        # $pull: {
        #   "profile.affiliations": affiliationId
        # }
      }
    else
      callback new errors.ValidationError {"op":"Invalid value."}
      return
    @model.update where, doc, (error, success)->
      callback error, success
      # if success==0
      #   callback new errors.ValidationError "Whoops, looks like you already added that affiliation.", {"name":"Affiliation already added."}
      # else
      #   callback error, success
      # return
    return

  @addFunds: (id, amount, callback)->
    amount = parseFloat(amount)
    if isNaN(amount)
      callback ({message: "amount is not a number"})
      return
    else if amount <0
      callback({message: "amount cannot be negative"})
      return

    amount = parseFloat(Math.abs(amount.toFixed(2)))

    $update = {$inc: {"funds.remaining": amount, "funds.allocated": amount} }

    @model.collection.update {_id: id}, $update, {safe: true}, callback

  @setTransactonPending: @__setTransactionPending
  @setTransactionProcessing: @__setTransactionProcessing
  @setTransactionProcessed: @__setTransactionProcessed
  @setTransactionError: @__setTransactionError


## Clients ##
class Clients extends API
  @model = Client

  @_updatePasswordHelper = (id, password, callback)->
    #this function is a helper to update a users password
    #ussually a user has to enter their previous password or
    #have a secure reset-password link to update their password.
    #do not call this function directly.. w/out security.
    self = this
    @encryptPassword password, (error, hash)->
      if error?
        callback new errors.ValidationError "Invalid Password", {"password":"Invalid Password"} #error encrypting password, so fail
        return
      #password encrypted successfully
      password = hash
      self.update id, {password: hash}, callback
      return

  @updateIdentity: (id, data, callback)->
    self = this
    logger.silly id
    if Object.isString(id)
      id = new ObjectId(id)

    entityType = "client"
    Medias.validateAndGetMediaURLs entityType, id, "client", data.media, (error, validatedMedia)->
      if error?
        callback error
        return

      updateDoc = {}
      if !validatedMedia?
        delete data.media
        #updateDoc.$unset = {media:1} #DONT UNSET - media is submitted with business info updates..
      else
        data.media = validatedMedia

      updateDoc.$set = data
      logger.silly data
      self.model.collection.findAndModify {_id: id}, [], updateDoc, {safe: true}, callback
      return
    return

  @register: (data, fieldsToReturn, callback)->
    self = this
    data.screenName = new ObjectId()
    @encryptPassword data.password, (error, hash)->
      if error?
        callback new errors.ValidationError "Invalid Password", {"password":"Invalid Password"} #error encrypting password, so fail
        return
      else
        data.password = hash
        data.referralCodes = {}
        Sequences.next 'urlShortner', 2, (error, sequence)->
          if error?
            callback error #dberror
            return
          tapInCode = urlShortner.encode(sequence-1)
          userCode = urlShortner.encode(sequence)
          data.referralCodes.tapIn = tapInCode
          data.referralCodes.user = userCode

          self.add data, (error, client)->
            if error?
              if error.code is 11000 or error.code is 11001
                callback new errors.ValidationError "Email Already Exists", {"email":"Email Already Exists"} #email exists error
              else
                callback error
            else
              client = self._copyFields(client, fieldsToReturn)
              callback error, client
            return
        return
      return
    return

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
            if error.code is 11000 or error.code is 11001
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

  @getByEmail: (email, fieldsToReturn, callback)->
    if Object.isFunction fieldsToReturn
      callback = fieldsToReturn
      fieldsToReturn = {} #all fields
    query = @_query()
    query.where('email', email)
    query.fields(fieldsToReturn)
    query.findOne (error, user)->
      if error?
        callback error #db error
      else
        callback null, user #if no consumer with that email will return null
      return
    return

  @updateMediaByGuid: (id, guid, mediasDoc, callback)->
    if(Object.isString(id))
      id = new ObjectId(id)

    query = @_query()
    query.where("_id", id)
    query.where("media.guid", guid)

    set = {
      media : Medias.mediaFieldsForType mediasDoc, "client"
    }
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
            if !success #true/false
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
      key = hashlib.md5(config.secretWord + newEmail+(new Date().toString()))+'-'+generatePassword(12, false, /\d/)
      set = {
        changeEmail: {
          newEmail: newEmail
          key: key
          expirationDate: Date.create("next week")
        }
      }
      query.update {$set:set}, (error, success)->
        if error?
          if error.code is 11000 or error.code is 11001
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
        if error.code is 11000 or error.code is 11001
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
    if options.deleted?
      options.deleted = options.deleted
    else
      options.deleted = false

    query.in('clients', [options.clientId]) if options.clientId?
    query.where 'deleted', options.deleted
    query.where 'locations.tapins', true if options.tapins?
    query.where 'isCharity', options.charity if options.charity?
    query.where 'gbEquipped', true if options.equipped?
    query.where 'type', options.type if options.type?
    query.sort('publicName', 1) if options.alphabetical? and options.alphabetical == true
    return query

  @updateSettings = (id, pin, data, callback)->
    if Object.isString(id)
      id = new ObjectId(id)

    $query = {_id: id}
    $options = {remove: false, new: true, upsert: false}

    Businesses.validatePin id, pin, (error)=>
      if error?
        callback error
        return

      if data.pin?
        Businesses.encryptPin data.pin, (error, encrypted)=>
          if error?
            callback error
            return
          data.pin = encrypted
          $update = {$set: @_flattenDoc(data)}
          @model.collection.findAndModify $query, [], $update, $options, callback
      else
        $update = {$set: @_flattenDoc(data)}
        @model.collection.findAndModify $query, [], $update, $options, callback
      return
    return

  @getMultiple = (idArray, fieldsToReturn, callback)->
    query = @query()
    query.in("_id",idArray)
    query.fields(fieldsToReturn)
    query.find callback
    return

  @getOneEquipped = (id, fieldsToReturn, callback)->
    query = @_queryOne()
    @model.findOne {_id: id, 'gbEquipped': true}, fieldsToReturn, callback

  @encryptPin: (password, callback)->
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
      return
    return

  @updatePin: (id, pin, callback) ->
    self = this
    Businesses.encryptPin pin, (error, hash) ->
      if error?
        callback error
        return
      Businesses.update id, { pin: hash }, (error, business)->
        if error?
          callback error
          return
        callback null, business.pin
        return
      return
    return

  @validatePin: (id, pin, callback)->
    if !id? or !pin?
      callback { message: "No arguments given" }
      return
    Businesses.one id, (error, business)->
      if error?
        callback error
        return
      if !business?
        callback error
        return
      if !business.pin?
        Businesses.updatePin business._id, 'asdf', (error, hash) ->
          if error?
            callback error
            return
          bcrypt.compare pin+defaults.passwordSalt, hash, (error, success)->
            if error? or !success
              callback error
              return
            callback error, business
            return
      else
        bcrypt.compare pin+defaults.passwordSalt, business.pin, (error, success)->
          if error? or !success
            callback new errors.ValidationError "Validation Error", {"pin":"Invalid Pin"}
            return
          callback error, business
          return

  @add = (clientId, data, callback)->
    instance = new @model()
    for own k,v of data
      instance[k] = v
    if data['locations']? and data['locations'] != []
        instance.markModified('locations')
    if !data.pin?
      instance.pin = "asdf"

    #add user to the list of users for this business and add them to the group of owners
    instance['clients'] = [clientId] #only one user now
    instance['clientGroups'] = {}
    instance['clientGroups'][clientId] = choices.businesses.groups.OWNERS
    instance['groups'][choices.businesses.groups.OWNERS] = [clientId]

    Businesses.encryptPin instance.pin, (error, hash)->
      if error?
        callback error
        return
      instance.pin = hash
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

  @updateIsCharity: (businessId, isCharity, callback)->
    if !businessId? or businessId.length!=24
      callback new errors.ValidationError "Please select a business.", {"business":"invalid businessId"}
      return
    else
      if Object.isString businessId
        businessId = new ObjectId businessId
    set = {
      isCharity: isCharity
    }
    @model.collection.update {_id: businessId}, {$set:set}, {safe: true}, (error, count)->
      if error?
        callback error
        return
      callback error, count>0 #success
    return

  @updateIdentity: (id, data, callback)->
    self = this
    if Object.isString(id)
      id = new ObjectId(id)

    entityType = "business"
    Medias.validateAndGetMediaURLs entityType, id, "business", data.media, (error, validatedMedia)->
      if error?
        callback error
        return

      updateDoc = {}
      if !validatedMedia?
        delete data.media
        #updateDoc.$unset = {media:1} #DONT UNSET - media is submitted with business info updates..
      else
        data.media = validatedMedia

      updateDoc.$set = data
      self.model.collection.update {_id: id}, updateDoc, {safe: true}, callback
      return
    return

  @updateMediaByGuid: (id, guid, mediasDoc, callback)->
    if(Object.isString(id))
      id = new ObjectId(id)

    query = @_query()
    query.where("_id", id)
    query.where("media.guid", guid)

    set = {
      media : Medias.mediaFieldsForType mediasDoc, "business"
    }

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
    self = this
    if Object.isArray(locationIds)
      for locationId in locationIds
        objIds.push new ObjectId(locationId)
    else
      objIds = [locationIds]

    if Object.isString(id)
      id = new ObjectId(id)

    @model.collection.findOne { _id: id }, { registers: 1, locRegister: 1 }, (err, results) ->
      if err?
        callback err, null
      else
        $unset = {}
        for location in objIds
          if results.locRegister[location]?
            $unset[ "locRegister." + location ] = 1;
          for register in results.locRegister[location]
            if results.registers[register]?
              $unset[ "registers." + register ] = 1;
        self.model.collection.findAndModify { _id: id }, [], { $unset: $unset }, {safe: true}, (err, response) ->
          if err?
            callback err, null

    $pull = {}
    $pull["locations"] = {_id: { $in: objIds }}
    $pull["registerData"] =  {locationId: {$in: objIds}}
    @model.collection.update {_id: id}, {$pull: $pull}, {safe: true}, callback

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

  @addFunds: (id, amount, callback)->
    amount = parseFloat(amount)
    if amount <0
      callback({message: "amount cannot be negative"})
      return

    $update = {$inc: {"funds.remaining": amount, "funds.allocated": amount} }

    @model.collection.update {_id: id}, $update, {safe: true}, callback

  @validateTransactionEntity: (businessId, locationId, registerId, callback)->
    if Object.isString(businessId)
      businessId = new ObjectId(businessId)
    if Object.isString(locationId)
      locationId = new ObjectId(locationId)
    if Object.isString(registerId)
      registerId = new ObjectId(registerId)

    query = {}
    query["_id"] = businessId
    query["locRegister.#{locationId}"] = registerId
    query["registers.#{registerId}.locationId"] = locationId
    #query["registers.#{registerId}.locationId"] = locationId #SHOULD BE THIS, BUT TEMPORARILY USE ABOVE CAUSE CODE NEEDS A FIXIN'

    @model.collection.findOne query, {_id: 1, publicName: 1}, callback

  @addRegister = (businessId, locationId, callback)->
    if Object.isString businessId
      businessId = new ObjectId businessId
    if Object.isString locationId
      locationId = new ObjectId locationId
    registerId = new ObjectId()

    # Get an id that can be utilized to setup the tablets
    Sequences.next "register-setup-id", (error, value)=>
      if error?
        callback error #dberror
        return

      $query = {_id: businessId}
      $set = {registers: {}}
      $push = {}
      $set.registers[registerId] = {}
      $set.registers[registerId].locationId = locationId
      $set.registers[registerId].setupId = value

      $push["registerData"] = {locationId: locationId, registerId: registerId, setupId: value}
      $push["locRegister.#{locationId}"] = registerId

      $set = API._flattenDoc $set
      #$push = @_flattenDoc $push
      $update = {$set: $set, $push: $push}

      @model.collection.findAndModify $query, [], $update, {safe: true}, (error)->
        callback error, registerId

  @delRegister = (businessId, locationId, registerId, callback)->
    if Object.isString businessId
      businessId = new ObjectId businessId

    $query = {_id: businessId}
    $unset = {}
    $pull = {}
    $unset["registers.#{registerId}"] = 1
    $pull["locRegister.#{locationId}"] = new ObjectId(registerId)
    $pull["registerData"] = {registerId: new ObjectId(registerId)}
    $update = {$unset: $unset, $pull: $pull}

    @model.collection.findAndModify $query, [], $update, {safe: true}, callback

  @isCharity = (id, fields, callback)->
    if Object.isString id
      id = new ObjectId id
    @model.collection.findOne {_id: id, isCharity: true}, {fields: fields}, (error, charity)->
      if error?
        callback(error)
        return
      callback null, charity

  @getRandomCharity = (fields, callback)->
    @model.collection.count {isCharity: true}, (error, count)=>
      if error?
        callback(error)
        return
      if count <= 0
        callback null
        return

      $opts = {fields: fields, limit: -1}

      if count == 1
        $opts.skip = 0
      else
        $opts.skip = Number.random(0,count-1)

      @model.collection.find {isCharity: true}, $opts, (error, cursor)->
        if error?
          callback(error)
          return
        cursor.toArray (error, charities)->
          if charities.length > 0
            callback error, charities[0]
          else
            callback error
          return

  @validateRegister = (businessId, locationId, registerId, fields, callback)->
    if Object.isString businessId
      businessId = new ObjectId businessId
    if Object.isString locationId
      locationId = new ObjectId locationId
    if Object.isString registerId
      registerId = new ObjectId registerId

    $query = {_id: businessId}
    $query["locRegister."+locationId.toString()] = registerId
    @model.collection.findOne $query, fields, (error, business)->
      if error?
        callback error
        return
      callback null, business

  @getBySetupId = (setupId, fields, callback)->
    $query = {"registerData.setupId": setupId}
    @model.collection.findOne $query, fields, (error, business)->
      if error?
        callback error
        return
      callback null, business

## Organizations ##
class Organizations extends API
  @model = Organization

  @search = (name, type, callback)->
    re = new RegExp("^"+name+".*", 'i')
    query = @_query()
    if name? and !name.isBlank()
      query.where('name', re)
    if type in choices.organizations._enum
      query.where('type', type)
    query.limit(100)
    query.exec callback

  @setTransactonPending: @__setTransactionPending
  @setTransactionProcessing: @__setTransactionProcessing
  @setTransactionProcessed: @__setTransactionProcessed
  @setTransactionError: @__setTransactionError


## Campaigns ##
# class Campaigns extends API


## Polls ##
class Polls extends API # Campaigns
  @model = Poll

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
  @add: (pollData, amount, callback)->
    self = this
    if Object.isString(pollData.entity.id)
      pollData.entity.id = new ObjectId pollData.entity.id

    #find Entity, and check if they have enough funds
    logger.debug "pollData.entity"
    logger.debug pollData.entity
    switch pollData.entity.type
      when choices.entities.BUSINESS
        entityClass = Businesses
      when choices.entities.CONSUMER
        entityClass = Consumers

    async.parallel {
        checkFunds: (cb)->
          if Object.isString pollData.entity.id
            pollData.entity.id = new ObjectId pollData.entity.id
          entityClass.one pollData.entity.id, {funds:1}, (error, entity)->
            if error?
              cb error
              return
            if !entity?
              #Entity not found
              cb new errors.ValidationError "Entity id not found.", {"entity":"Entity not found."}
              return
            if (entity.funds.remaining < (pollData.funds.perResponse*pollData.responses.max))
              #Entity does not have enough funds
              cb new errors.ValidationError "Insufficient funds.", {"entity":"Insufficient funds"}
              return
            # Success - entity found and has enough funds to create poll..
            cb null, entity

        validatedMediaQuestion: (cb)->
          if !pollDate.mediaQuestion?
            Medias.validateAndGetMediaURLs pollData.entity.type, pollData.entity.id, "poll", pollData.mediaQuestion, (error, validatedMedia)->
              if error?
                cb error
                return
              #mediaCheck - if validated media is null.. delete media from the poll pollData.
              if !validatedMedia?
                delete pollData.mediaQuestion
                cb null, null
              else
                pollData.mediaQuestion = validatedMedia
                cb null, validatedMedia
              return
          else
            delete pollData.mediaQuestion
            cb null, null #consumers will have a null media object

        validatedMediaResults: (cb)->
          if !pollDate.mediaResults?
            Medias.validateAndGetMediaURLs pollData.entity.type, pollData.entity.id, "poll", pollData.mediaResults, (error, validatedMedia)->
              if error?
                cb error
                return
              #mediaCheck - if validated media is null.. delete media from the poll data.
              if !validatedMedia?
                delete pollData.mediaResults
                cb null, null
              else
                pollData.mediaResults = validatedMedia
                cb null, validatedMedia
              return
          else
            delete pollData.mediaResults
            cb null, null #consumers will have a null media object
      },
      (error, asyncResults)-> #asyn.parallel callback
        if error?
          callback error
          return

        #note: pollData was modified above in the validateMedia checks above..
        #note: pollData was modified above in the validateMedia checks above..
        #note: pollData was modified above in the validateMedia checks above..
        logger.debug "POLL pollData"
        logger.debug pollData
        instance = new self.model(pollData)

        transactionData = {
          amount: amount
        }

        transaction = self.createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.POLL_CREATED, transactionData, choices.transactions.directions.INBOUND, instance._doc.entity)

        instance.transactions.state = choices.transactions.states.PENDING #soley for reading purposes
        instance.transactions.locked = true
        instance.transactions.ids = [transaction.id]
        instance.transactions.log = [transaction]

        #instance.events = @_createEventsObj event
        instance.save (error, poll)->
          logger.debug error
          logger.debug poll
          if error?
            logger.debug "error"
            callback error
          else
            callback error, poll._doc
            tp.process(poll._doc, transaction)
          return
        return
    return

  @update: (entityType, entityId, pollId, pollData, newAllocated, perResponse, callback)->
    self = this
    instance = new @model(pollData)

    if Object.isString(pollId)
      pollId = new ObjectId(pollId)
    if Object.isString(entityId)
      entityId = new ObjectId(entityId)


    async.parallel {
        # checkFunds: (cb)->
        #   find Entity, and check if they have enough funds
        #    switch entityType
        #      when choices.entities.BUSINESS
        #        entityClass = Businesses
        #      when choices.entities.CONSUMER
        #        entityClass = Consumers
        #   if Object.isString pollData.entity.id
        #     pollData.entity.id = new ObjectId pollData.entity.id
        #   entityClass.one pollData.entity.id, {funds:1}, (error, entity)->
        #     if error?
        #       cb error
        #       return
        #     if !entity?
        #       #Entity not found
        #       cb new errors.ValidationError "Entity id not found.", {"entity":"Entity not found."}
        #       return
        #     if (entity.funds.remaining < (pollData.funds.perResponse*pollData.responses.max))
        #       #Entity does not have enough funds
        #       cb new errors.ValidationError "Insufficient funds.", {"entity":"Insufficient funds"}
        #       return
        #     # Success - entity found and has enough funds to create poll..
        #     cb null, entity

        validatedMediaQuestion: (cb)->
          Medias.validateAndGetMediaURLs entityType, entityId, "poll", pollData.mediaQuestion, (error, validatedMedia)->
            if error?
              cb error
              return
            #mediaCheck - if validated media is null.. delete media from the poll pollData.
            if !validatedMedia?
              delete pollData.mediaQuestion
              cb null, null
            else
              pollData.mediaQuestion = validatedMedia
              cb null, validatedMedia
            return

        validatedMediaResults: (cb)->
          Medias.validateAndGetMediaURLs entityType, entityId, "poll", pollData.mediaResults, (error, validatedMedia)->
            if error?
              cb error
              return
            #mediaCheck - if validated media is null.. delete media from the poll data.
            if !validatedMedia?
              delete pollData.mediaResults
              cb null, null
            else
              pollData.mediaResults = validatedMedia
              cb null, validatedMedia
            return
      },
      (error, asyncData)-> #asyn.parallel callback
        if error?
          callback error
          return

        #Set the fields you want updated now, not afte the update
        #for the ones that you want set after the update put those
        #in the transactionData and make thsoe changes in the
        #setTransactionProcessed function
        updateDoc = {}

        updateDoc.$unset = {}
        if !asyncData.validatedMediaQuestion?
          updateDoc.$unset.mediaQuestion = 1
        if !asyncData.validatedMediaResults?
          updateDoc.$unset.mediaResults = 1
        delete updateDoc.$unset if Object.isEmpty(updateDoc.$unset) #delete it if nothing to unset

        updateDoc.$set = {
          entity: {
            type          : entityType
            id            : entityId
            name          : pollData.entity.name
          }

          lastModifiedBy: {
            type          : pollData.lastModifiedBy.type
            id            : pollData.lastModifiedBy.id
          }

          name            : pollData.name
          type            : pollData.type
          question        : pollData.question
          choices         : pollData.choices
          numChoices      : parseInt(pollData.numChoices)
          responses: {
            remaining     : parseInt(pollData.responses.max)
            max           : parseInt(pollData.responses.max)
            log           : pollData.responses.log
            dates         : pollData.responses.dates
            choiceCounts  : pollData.responses.choiceCounts
          }
          showStats       : pollData.showStats
          displayName     : pollData.displayName

        }
        #flat properties so that they dont overwrite their entire subdoc
        updateDoc.$set["dates.start"]= new Date(pollData.dates.start) #this is so that we don't lose the create date
        updateDoc.$set["transactions.locked"]= true #THIS IS A LOCKING TRANSACTION, SO IF ANYONE ELSE TRIES TO DO A LOKCING TRANSACTION IT WILL NOT HAPPEN (AS LONG AS YOU CHECK FOR THAT)
        updateDoc.$set["transactions.state"]= choices.transactions.states.PENDING

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

        updateDoc.$push = {
          "transactions.ids": transaction.id
          "transactions.log": transaction
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
        self.model.collection.findAndModify where, [], updateDoc, {safe: true, new: true}, (error, poll)->
          if error?
            callback error, null
          else if !poll?
            callback new errors.ValidationError({"poll":"Poll does not exist or not editable."})
          else
            callback null, poll
            tp.process(poll, transaction)
          return
        return
      return

  @updateMediaByGuid: (entityType, entityId, guid, mediasDoc, mediaKey, callback)->
    if(Object.isString(entityId))
      entityId = new ObjectId(entityId)
    if(Object.isFunction(mediaKey))
      callback = mediaKey
      mediaKey = "media"

    query = @_query()
    query.where("entity.type", entityType)
    query.where("entity.id", entityId)
    query.where("#{mediaKey}.guid", guid)

    set = {}
    set["#{mediaKey}"] = Medias.mediaFieldsForType mediasDoc, "poll"

    query.update {$set:set}, (error, success)->
      if error?
        callback error #dberror
      else
        callback null, success
      return
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

  @answer = (entity, pollId, answers, callback)->
    if Object.isString(pollId)
      pollId = new ObjectId(pollId)

    if Object.isString(entity.id)
      entity.id = new ObjectId(entity.id)

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

        set["responses.log."+entity.id] = {
            answers   : answers,
            timestamp : timestamp
        }

        push["responses.dates"] = {
          consumerId: entity.id
          timestamp: timestamp
        }
        push["responses.consumers"] = entity.id

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
        fieldsToReturn["responses.log.#{entity.id}"] = 1

        query = {
            _id                       : pollId,
            "entity.id"               : {$ne : entity.id} #can't answer a question you authored
            numChoices                : {$gt : maxAnswer}   #makes sure all answers selected exist
            "responses.consumers"     : {$ne : entity.id}  #makes sure consumer has not already answered
            "responses.skipConsumers" : {$ne : entity.id}  #makes sure consumer has not already skipped..
            "responses.flagConsumers" : {$ne : entity.id}  #makes sure consumer has not already flagged..
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
    query.where('deleted').ne(true)
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
class Discussions extends API #Campaigns
  @model = Discussion

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

    if data.tags?
      Tags.addAll data.tags, choices.tags.types.DISCUSSIONS
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

  @updateMediaByGuid: (entityType, entityId, guid, mediasDoc, callback)->
    if(Object.isString(entityId))
      entityId = new ObjectId(entityId)

    query = @_query()
    query.where("entity.type", entityType)
    query.where("entity.id", entityId)
    query.where("media.guid", guid)

    set = {
      media : Medias.mediaFieldsForType mediasDoc, "discussion"
    }

    query.update {$set:set}, (error, success)->
      if error?
        callback error #dberror
      else
        callback null, success
      return
    return

  @listCampaigns: (entityType, entityId, stage, options, callback)->
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
  #
  # - **sort** _String, enum: choices.discussions.sort, default: choices.discussions.sort.dateDescending
  # - **limit** _Number, default: 25_ limit number of discussions returned
  # - **skip** _Number, default: 0_ an offset for number of discussions returned
  #
  # **callback** error, discussions
  @list: (options, callback)->
    if Object.isFunction(options)
      callback = options
      options = {}

    options.limit = options.limit || 25
    options.skip = options.skip || 0

    if options.sort? and options.sort in choices.discussions.sorts._enum
      sort = options.sort
    else
      options.sort = choices.discussions.sorts.DATE_DESCENDING

    $query = {
      "dates.start"           : {$lte: new Date()}
      , $or                   : [{deleted: false}, {deleted: {$exists: false}}]
      , "transactions.state"  : choices.transactions.states.PROCESSED
      , "transactions.locked" : {$ne: true}
    }

    $sort = {}
    switch sort
      when choices.discussions.sorts.DATE_ASCENDING
        $sort = {'dates.start': 1}
      when choices.discussions.sorts.DATE_DESCENDING
        $sort = {'dates.start': -1}
      when choices.discussions.sorts.RECENTLY_POPULAR_7
        $query["dates.start"].$gte = Date.create().addWeeks(-1)
        $sort = {'dates.start': -1}
        $sort = {'responseCount': 1}
      when choices.discussions.sorts.RECENTLY_POPULAR_14
        $query["dates.start"].$gte = Date.create().addWeeks(-2)
        $sort = {'dates.start': -1, 'responseCount': 1}
      when choices.discussions.sorts.RECENTLY_POPULAR_1
        $query["dates.start"].$gte = Date.create().addDays(-1)
        $sort = {'dates.start': -1, 'responseCount': 1}

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

    cursor = @model.collection.find $query, $fields, (err, cursor)->
      if error?
        callback(error)
        return
      cursor.limit(options.limit)
      cursor.skip(options.skip)
      cursor.sort($sort)
      cursor.toArray (error, discussions)->
        callback(error, discussions)

  ### _get_ ###
  #
  # **discussionId** _String/ObjectId_ id of discussion
  #
  # **responseOptions**
  #
  # - **limit** _Number, default: 10_ limit of responses
  # - **skip** _Number, default: 0_  responses to skip
  #
  # **callback** error, discussion
  @get: (discussionId, responseOptions, callback)->
    if Object.isString(discussionId)
      discussionId = new ObjectId(discussionId)

    if Object.isFunction(responseOptions)
      callback = responseOptions
      responseOptions = {}

    responseOptions.limit = responseOptions.limit || 10
    responseOptions.skip = responseOptions.skip || 0

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
      , responses       : {$slice:[responseOptions.skip, responseOptions.skip + responseOptions.limit]}
    }

    @model.collection.findOne $query, $fields, (error, discussion)->
      callback(error, discussion)

  ### _getResponses_ ###
  # **discussionId** _String/ObjectId_ Id of discussion
  #
  # **responseOptions**
  #
  # - **limit** _Number, default: 10_ limit of responses
  # - **skip** _Number, default: 0_  responses to skip
  #
  # **callback** error, discussion
  @getResponses: (discussionId, responseOptions, callback)->
    if Object.isString(discussionId)
      discussionId = new ObjectId(discussionId)

    if Object.isFunction(responseOptions)
      callback = responseOptions
      responseOptions = {}

    responseOptions.limit = responseOptions.limit || 10
    responseOptions.skip = responseOptions.skip || 0

    $query = {
      "dates.start"           : {$lte: new Date()}
      , deleted               : {$ne: true}
      , "transactions.state"  : choices.transactions.states.PROCESSED
      , "transactions.locked" : {$ne: true}
    }

    $fields = {
      _id: 1
      , responses       : {$slice:[responseOptions.skip, responseOptions.skip + responseOptions.limit]}
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
    score = 1
    opposite = choices.votes.DOWN
    if direction is choices.votes.DOWN
      d = "down"
      score = -1
      opposite = choices.votes.UP

    #if the user has voted the opposite, undo that
    @_undoVote discussionId, responseId, entity, opposite, (error, data)->
      return

    entity._id = new ObjectId() #we do this because mongoose does it to every document array

    $query = {_id: discussionId, "responses._id": responseId}

    $inc = {"votes.count":1, "votes.score": score, "responses.$.votes.count": 1}
    $set = {}
    $push = {}

    $query["responses.votes.#{d}.by.id"] = {$ne: entity.id} #not already set
    $inc["responses.$.votes.#{d}.count"] = 1
    $inc["votes.#{d}"] = 1
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
    score = -1
    if direction is choices.votes.DOWN
      d = "down"
      score = 1

    $query = {_id: discussionId, "responses._id": responseId}
    $pull = {}
    $inc = {"votes.count": -1, "votes.score": score, "responses.$.votes.count": -1}
    $unset = {}

    $query["responses.votes.#{d}.by.id"] = entity.id
    $pull["responses.$.votes.#{d}.by"] = {type: entity.type, id: entity.id}
    $inc["responses.$.votes.#{d}.count"] = -1
    $inc["votes.#{d}"] = -1
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

  @mediaFieldsForType: (mediasDoc, mediaFor)->
    switch mediaFor
      when 'event','poll','discussion'
        imageType = 'landscape'
      when 'business','consumer','client'
        imageType = 'square'
      when 'consumer-secure'
        imageType = 'secureSquare'

    if imageType == "square"
      media = {
        url     : mediasDoc.sizes.s128
        thumb   : mediasDoc.sizes.s85
        mediaId : mediasDoc._id
      }
    else if imageType == "secureSquare"
      media = {
        url     : mediasDoc.sizes['s128-secure']
        thumb   : mediasDoc.sizes['s85-secure']
        mediaId : mediasDoc._id
      }
    else if imageType == "landscape"
      media = {
        url     : mediasDoc.sizes.s320x240
        thumb   : mediasDoc.sizes.s100x75
        mediaId : mediasDoc._id
      }
    return media

  #validate Media Objects for other collections
  @validateMedia: (media, imageType, callback)->
    validatedMedia = {}
    if !media?
      callback new errors.ValidationError {"media":"Media is null."}
      return

    if !utils.isBlank(media.mediaId)
      #mediaId and no urls -> look up urls
      delete media.tempURL
      if (!utils.isBlank(media.url) or !utils.isBlank(media.thumb))
        logger.debug "validateMedia - mediaId supplied, missing urls, fetch urls from db."
        #mediaId typecheck is done in one
        Medias.one media.mediaId, (error, data)->
          if error?
            callback error #callback
            return
          else if !data? || data.length==0
            callback new errors.ValidationError({"mediaId":"Invalid MediaId"})
            return

          if imageType=="square"
            validatedMedia.mediaId = data._id #type objectId
            validatedMedia.thumb = data.sizes.s85
            validatedMedia.url   = data.sizes.s128
            validatedMedia.rotateDegrees = media.rotateDegrees if !utils.isBlank(media.rotateDegrees) && media.rotateDegrees!=0
            callback null, validatedMedia #media found and urls set
            return
          else if imageType=="landscape"
            logger.debug "imageType-landscape"
            logger.debug data
            validatedMedia.mediaId = data._id #type objectId
            validatedMedia.thumb = data.sizes.s100x75
            validatedMedia.url   = data.sizes.s320x240
            validatedMedia.rotateDegrees = media.rotateDegrees if !utils.isBlank(media.rotateDegrees) && media.rotateDegrees!=0
            callback null, validatedMedia #media found and urls set
            return
          else
            callback new errors.ValidationError({"imageType":"Unknown value."})
            return
      else  #media Id and has urls
        logger.debug "validateMedia - mediaId supplied with both URLs, no updates required."
        callback null, media
        return
    else if !utils.isBlank(media.guid) #media guid supplied.
      validatedMedia.guid = media.guid
      validatedMedia.rotateDegrees = media.rotateDegrees if !utils.isBlank(media.rotateDegrees) && media.rotateDegrees!=0
      if !utils.isBlank(media.tempURL)
        validatedMedia.url = media.tempURL
        validatedMedia.thumb = media.tempURL
        callback null, validatedMedia
        return
      else
        if utils.isBlank(media.url) || utils.isBlank(media.thumb)
          callback new errors.ValidationError({"media":"'tempURL' or ('url' and 'thumb') is required when supplying guid."})
          return
        else
          validatedMedia.url   = media.url
          validatedMedia.thumb = media.thumb
          callback null, validatedMedia
          return
    else if media.url? || media.thumb? #and !data.media.guid and !data.media.mediaId
      callback new errors.ValidationError({"media":"'guid' or 'mediaId' is required when supplying a media.url"})
      return
    else
      #invalid (missing ) or empty mediaObject
      callback null, {} #guid and urls supplied
      return



  #validate Media Objects for other collections
  @validateAndGetMediaURLs: (entityType, entityId, mediaFor, media, callback)->
    validatedMedia = {}
    if (!utils.isBlank(media.rotateDegrees) && !isNaN(parseInt(media.rotateDegrees)))
      validatedMedia.rotateDegrees = media.rotateDegrees
    if !media?
      callback null, null
      return

    if !utils.isBlank(media.mediaId)
      #mediaId and no urls -> look up urls
      if (utils.isBlank(media.url) or utils.isBlank(media.thumb))
        logger.debug "validateMedia - mediaId supplied, missing urls, fetch urls from db."
        #mediaId typecheck is done in one
        if Object.isString(media.mediaId)
          media.mediaId = new ObjectId(media.mediaId)
        Medias.one media.mediaId, (error, mediasDoc)->
          if error?
            callback error #callback
            return
          else if !mediasDoc? || mediasDoc.length==0
            callback new errors.ValidationError({"mediaId":"Invalid MediaId"})
            return
          validatedMedia = Medias.mediaFieldsForType mediasDoc._doc, mediaFor
          callback null, validatedMedia # found - media by mediaId
          return
      else  #media Id and has urls
        logger.debug "validateMedia - mediaId supplied with both URLs, no updates required."
        callback null, media
        return
    else if !utils.isBlank(media.guid) #media guid supplied.
      validatedMedia.guid = media.guid
      Medias.getByGuid entityType, entityId, validatedMedia.guid, (error, mediasDoc)->
        if error?
          callback error
          return
        else if mediasDoc?
          logger.debug "validateMedia - guid supplied, found guid in Medias."
          validatedMedia = Medias.mediaFieldsForType mediasDoc._doc, mediaFor
          callback null, validatedMedia # found - media uploaded by transloadit already
          return
        else #!media? - media has yet to be uploaded by transloadit.. mark it with the guid and use tempurls for now
          logger.debug "validateMedia - guid supplied, guid not found (use temp. URLs for now)."
          if !utils.isBlank(media.tempURL)
            validatedMedia.url = media.tempURL
            validatedMedia.thumb = media.tempURL
            callback null, validatedMedia
            return
          else
            if utils.isBlank(media.url) || utils.isBlank(media.thumb)
              callback new errors.ValidationError({"media":"'tempURL' or ('url' and 'thumb') is required when supplying guid."})
              return
            else
              validatedMedia.url   = media.url
              validatedMedia.thumb = media.thumb
              callback null, validatedMedia
              return
    else if !utils.isBlank(media.url) || !utils.isBlank(media.thumb) #and !data.media.guid and !data.media.mediaId
      callback new errors.ValidationError({"media":"'guid' or 'mediaId' is required when supplying a media.url"})
      return
    else
      #invalid (missing mediaId and guid..) or empty mediaObject
      callback null, null #guid and urls supplied
      return

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

  #getByGuid(entityId,guid,callback)
  @getByGuid: (entityType, entityId, guid, callback)->
    if Object.isString entityId
      entityId = entityId
    @get {entityType: entityType, entityId: entityId, guid: guid}, (error,mediasDoc)->
      if mediasDoc? && mediasDoc.length
        callback null, mediasDoc[0]
      else
        callback error, null

    #@get {'entity.type': entityType, 'entity.id': entityId, 'media.guid': guid}, callback


## Client Invitations ##
class ClientInvitations extends API
  @model = ClientInvitation

  @add = (businessId, groupName, email, callback)->
    key = hashlib.md5(config.secretWord + email+(new Date().toString()))+'-'+generatePassword(12, false, /\d/)
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

  @add = (name, type, callback)->
    @_add {name: name, type: type}, callback

  @addAll = (nameArr, type, callback)->
    #callback is not required..
    countUpdates = 0
    for val,i in nameArr
      @model.update {name:val, type: type}, {$inc:{count:1}}, {upsert:true,safe:true}, (error, success)->
        if error?
          callback error
          return
        if ++countUpdates == nameArr.length && Object.isFunction callback #check if done
          callback null, countUpdates
        return

  @search = (name, type, callback)->
    re = new RegExp("^"+name+".*", 'i')
    query = @_query()
    if name? or name.isBlank()
      query.where('name', re)
    if type in choices.tags.types._enum
      query.where('type', type)
    query.limit(10)
    query.exec callback


## Event Requests ##
class EventRequests extends API
  @model = EventRequest

  @requestsPending: (businessId, callback)->
    if Object.isString businessId
      businessId = new ObjectId businessId
    query = @_query()
    query.where 'organizationEntity.id', businessId
    query.where('date.responded').exists false
    query.exec callback

  @respond: (requestId, callback)->
    if Object.isString requestId
      requestId = new ObjectId requestId
    $query = {_id: requestId}
    $update =
      $set:
        'date.responded': new Date()
    $options = {remove: false, new: true, upsert: false}
    @model.collection.findAndModify $query, [], $update, $options, callback


## Events ##
class Events extends API
  @model = Event

  @add: (event, callback)->
    self = Events

    #validate and get media urls (if avail) - returns null media if media is incomplete
    Medias.validateAndGetMediaURLs event.entity.type, event.entity.id, "event", event.media, (error, validatedMedia)->
      if error?
        callback error
        return
      if !validatedMedia?
        #no media, or incomplete media subdoc..
        delete event.media
      else
        #media good..
        event.media = validatedMedia

      self._add event, callback
    return

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

  @updateMediaByGuid: (entityType, entityId, guid, mediasDoc, callback)->
    if(Object.isString(entityId))
      entityId = new ObjectId(entityId)

    query = @_query()
    query.where("entity.type", entityType)
    query.where("entity.id", entityId)
    query.where("media.guid", guid)

    set = {
      media : Medias.mediaFieldsForType mediasDoc, "event"
    }

    query.update {$set:set}, (error, success)->
      if error?
        callback error #dberror
      else
        callback null, success
      return
    return


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


## Business Transactions ##
class BusinessTransactions extends API
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


## Business Requests ##
class BusinessRequests extends API
  @model = BusinessRequest

  @add = (userId, business, callback)->
    data = {
      businessName: business
    }

    if userId?
      data.userEntity = {
        type: choices.entities.CONSUMER
        id: userId
      }
      data.loggedin = true
    else
      data.loggedin = false

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

  @fundsDonated: (who, charity, donationLogDoc, callback)->
    if Object.isString who.id
      who.id = new ObjectId who.id
    if Object.isString charity.id
      charity.id = new ObjectId charity.id

    donation = {id: donationLogDoc._id, type:choices.objects.DONATION_LOG}

    stream = {
      who               : who
      entitiesInvolved  : [who, charity]
      what              : donation
      when              : donationLogDoc.dates.donated
      #where:
      events            : [choices.eventTypes.FUNDS_DONATED]
      data              : {}
      feeds: {
        global          : true
      }
      private: false #THIS NEEDS TO BE UPDATED BASED ON PRIVACY SETTINGS OF WHO (if consumer)
    }

    stream.data = {
      amount : donationLogDoc.amount
    }
    stream.feedSpecificData = {}
    stream.feedSpecificData.involved = { #available only to entities involved
      charity : charity
    }

    logger.silly stream.data

    @add stream, (error,data)->
      if error?
        logger.error error
      logger.debug data
      if callback?
        callback error,data
      return
    return

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
        question: pollDoc.question
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
        question: pollDoc.question
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
        question: pollDoc.question
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
        question: pollDoc.question
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
    if Object.isString(btDoc.organizationEntity.id)
      btDoc.organizationEntity.id = new ObjectId(btDoc.organizationEntity.id)

    #A user entity doesn't have to exist for a tapIn
    if btDoc.userEntity? and btDoc.userEntity.id?
      if Object.isString(btDoc.userEntity.id)
        btDoc.userEntity.id = new ObjectId(btDoc.userEntity.id)
    else
      btDoc.userEntity = {}
      btDoc.userEntity.type = choices.entities.CONSUMER
      btDoc.userEntity.id = new ObjectId("000000000000000000000000")
      btDoc.userEntity.name = "Someone"

    tapIn = {type: choices.objects.TAPIN, id: btDoc._id}
    who = btDoc.userEntity

    stream = {
      who               : who
      entitiesInvolved  : [who, btDoc.organizationEntity, btDoc.charity]
      what              : tapIn
      when              : btDoc.date

      where: {
        org             : btDoc.organizationEntity
        locationId      : btDoc.locationId
      }

      events            : [choices.eventTypes.BT_TAPPED]
      data              : {
        donationAmount  : btDoc.donationAmount
        charity         : btDoc.charity
      }

      feeds: {
        global          : true #unless a user's preferences are do that
      }
    }

    stream.feedSpecificData = {}
    stream.feedSpecificData.involved = #available only to entities involved
      amount: btDoc.amount
      donationAmount: btDoc.donationAmount #we shouldn't need this here

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
      , "who.screenName"
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
      , "who.screenName"
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


## Password Reset Requests ##
class PasswordResetRequests extends API
  @model: PasswordResetRequest

  @update: (id, doc, dbOptions, callback)->
    if Object.isString id
      id = new ObjectId id
    if Object.isFunction dbOptions
      callback = dbOptions
      dbOptions = {safe:true}
    #id typecheck is done in .update
    where = {_id:id}
    @model.update where, doc, dbOptions, callback
    return

  @add: (type, email, callback)->
    # determine user type
    if type == choices.entities.CONSUMER
      UserClass = Consumers
    else if type == choices.entities.CLIENT
      UserClass = Clients
    else
      callback new errors.ValidationError {"type": "Not a valid entity type."}
      return
      # find the user
    UserClass.getByEmail email, {_id:1,"facebook.id":1}, (error, user)=>
      if error?
        callback error
        return
      #found the user now submit the request
      if !user?
        callback new errors.ValidationError "That email is not registered with Goodybag.", {"email":"not found"}
        return
      if user.facebook? && user.facebook.id?
        callback new errors.ValidationError "Your account is authenticated through Facebook.", {"user":"facebookuser"} #do not update this error without updating the frontend javascript
        return
      request =
        entity:
          type: type
          id: user._id
        key: hashlib.md5(config.secretWord+email+(new Date().toString()))
      instance = new @model request
      instance.save callback
      return
    return

  @pending: (key, callback)->
    date = (new Date()).addMinutes(0 - globals.defaults.passwordResets.keyLife);
    where =
      key: key
      date: {$gt: date}
      consumed: false
    @model.findOne where, callback
    return

  @consume: (key, newPassword, callback)->
    self = this
    if Object.isString(id)
      id = new ObjectId(id)
    self.pending key, (error, resetRequest)->
      if error?
        callback error
        return
      if !resetRequest?
        callback new errors.ValidationError "The password-reset key is invalid, expired or already used.", {"key":"invalid, expired,or used"}
        return
      #key found and active.
      switch resetRequest.entity.type
        when choices.entities.CONSUMER
          userClass = Consumers
        when choices.entities.CLIENT
          userClass = Clients
        else
          callback new errors.ValidationError {"type": "Not a valid entity type."}

      userClass._updatePasswordHelper resetRequest.entity.id, newPassword, (error, count)->
        if error?
          callback error
          return
        #password update success
        success = count>0 #true
        callback null, success #respond to the user, well clear the request after.
        # Change the status of the request
        self.update resetRequest._id, {$set:{consumed:true}}, (error)->
          if error?
            logger.error error
            return
          #consumer request success
          return
        return
      return
    return


## Goodies ##
class Goodies extends API
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


## Unclaimed Barcode Statistics ##
class UnclaimedBarcodeStatistics extends API
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


## Statistics ##
class Statistics extends API
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


## Referrals ##
class Referrals extends API
  @model = Referral

  @addUserLink: (entity, link, code, callback )->
    doc = {
      _id: new ObjectId()
      type: choices.referrals.types.LINK
      entity: {
        type: entity.type
        id: entity.id
      }
      incentives: {referrer: defaults.referrals.incentives.referrers.USER, referred: defaults.referrals.incentives.referreds.USER}
      link: {
        code: code
        url:  link
        type: choices.referrals.links.types.USER
        visits: 0
      }
      signups: 0
      referredUsers: []
    }

    @model.collection.insert(doc, {safe: true}, callback)

  @addTapInLink: (entity, link, code, callback)->
    doc = {
      _id: new ObjectId()
      type: choices.referrals.types.LINK
      entity: {
        type: entity.type
        id: entity.id
      }
      incentives: {referrer: defaults.referrals.incentives.referrers.TAP_IN, referred: defaults.referrals.incentives.referreds.TAP_IN}
      link: {
        code: code
        url:  link
        type: choices.referrals.links.types.TAPIN
        visits: 0
      }
      signups: 0
      referredUsers: []
    }

    @model.collection.insert(doc, {safe: true}, callback)

  @signUp: (code, referredEntity, callback)->
    $update = {
      $inc: {signups: 1}
      $push: {referredUsers: referredEntity}
    }

    $fields = {_id: 1, entity: 1, incentives: 1}

    logger.info "code: " + code
    @model.collection.findAndModify {"link.code": code}, [], $update, {safe: true, new: true, fields: $fields}, (error, doc)->
      if error?
        if callback?
          callback(error)
        return
      else
        logger.debug doc
        referralFound = doc?
        if callback?
          callback(null, referralFound)
        #deposit money into the referred's account
        if doc.entity.type is choices.entities.CONSUMER
          Consumers.addFunds(referredEntity.id, doc.incentives.referred)
        else if choices.entities.BUSINESS
          Businesses.addFunds(referredEntity.id, doc.incentives.referred)

        #deposit money into the referrer's account
        if doc.entity.type is choices.entities.CONSUMER
          Consumers.addFunds(doc.entity.id, doc.incentives.referrer)
        else if choices.entities.BUSINESS
          Businesses.addFunds(doc.entity.id, doc.incentives.referrer)


## Barcodes ##
class Barcodes extends API
  @model = Barcode

  @assignNew: (entity, callback)->
    self = this
    Sequences.next "barcodeId", (error, value)=>
      value = defaults.barcode.offset + value
      security = utils.randomBarcodeSecurityString(3)
      barcodeId = "#{value}-#{security}"
      @model.collection.insert {barcodeId: barcodeId}, {safe: true}, (error, barcode)->
        if error?
          callback(error)
          return
        else if barcode?
          barcode = barcode[0]
          logger.silly "UPDATING CONSUMER BARCODE TO #{barcodeId}"
          Consumers.updateBarcodeId entity, barcodeId, (error, success)->
            if error?
              callback(error)
              return
            if success is true
              callback(error, barcode)
              return
            else
              callback({"name": "barcodeAssociationError", message: "unable to properly associate barcodeId with user"})
              return
        else
          callback(null, null)
          return


## CardRequests ##
class CardRequests extends API
  @model = CardRequest

  @pending: (id, callback)->
    if Object.isString id
      id = new ObjectId id
    $query = {'entity.id': id, 'dates.responded': {$exists: false}}
    @model.findOne $query, callback


## EmailSubmissions ##
class EmailSubmissions extends API
  @model = EmailSubmission

  @add: (data, callback)->
    if Object.isString data.businessId
      data.businessId = new ObjectId data.businessId
    if Object.isString data.locationId
      data.locationId = new ObjectId data.locationId
    if Object.isString data.registerId
      data.registerId = new ObjectId data.registerId
    @_add data, callback


exports.DBTransactions             = DBTransactions
exports.Consumers                  = Consumers
exports.Clients                    = Clients
exports.Businesses                 = Businesses
exports.Polls                      = Polls
exports.Discussions                = Discussions
exports.Goodies                    = Goodies
exports.Statistics                 = Statistics
exports.Medias                     = Medias
exports.ClientInvitations          = ClientInvitations
exports.Tags                       = Tags
exports.EventRequests              = EventRequests
exports.Events                     = Events
exports.BusinessTransactions       = BusinessTransactions
exports.BusinessRequests           = BusinessRequests
exports.Streams                    = Streams
exports.Statistics                 = Statistics
exports.UnclaimedBarcodeStatistics = UnclaimedBarcodeStatistics
exports.Organizations              = Organizations
exports.PasswordResetRequests      = PasswordResetRequests
exports.Referrals                  = Referrals
exports.Barcodes                   = Barcodes
exports.CardRequests               = CardRequests
exports.EmailSubmissions           = EmailSubmissions
exports.RedemptionLogs             = RedemptionLogs