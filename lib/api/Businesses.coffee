require("./helpers").install(global)
Api = require("./Api")
tp = require "../transactions" #transaction processor

exports = module.exports = class Businesses extends Api
  @model = Business

  #clientid, limit, skip
  @optionParser = (options, q)->
    query = @_optionParser(options, q)
    query.in('clients', [options.clientId]) if options.clientId?
    query.where 'locations.tapins', true if options.tapins?
    query.where 'isCharity', options.charity if options.charity?
    query.where 'deleted', options.deleted if options.deleted?
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

    @model.collection.update {_id: id}, {$pull: { locations: {_id: { $in: objIds } },  } }, {safe: true}, callback

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

    $query = {_id: businessId}
    $set = {registers: {}}
    $push = {locRegister: {}}
    $set.registers[registerId] = {}
    $set.registers[registerId].locationId = locationId
    $push.locRegister[locationId] = registerId

    $set = @_flattenDoc $set
    $push = @_flattenDoc $push
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