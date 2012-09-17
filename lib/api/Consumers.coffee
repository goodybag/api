require("./helpers").install(global)
Users = require("./Users")
tp = require "../transactions" #transaction processor

exports = module.exports = class Consumers extends Users
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