require("./helpers").install(global)
Api = require("./Api")
tp = require "../transactions" #transaction processor

exports = module.exports = class Clients extends Api
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