require("./helpers").install(global)
Api = require("./Api")
tp = require "../transactions" #transaction processor

exports = module.exports = class Users extends Api
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