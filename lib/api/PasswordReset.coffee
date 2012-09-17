require("./helpers").install(global)
Api = require("./Api")
tp = require "../transactions" #transaction processor

exports = module.exports = class PasswordResetRequests extends Api
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