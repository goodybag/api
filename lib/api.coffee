exports = module.exports

db = require './db'
globals = require 'globals'

utils = globals.utils
choices = globals.choices
defaults = globals.defaults

Goody = db.Goody
Client = db.Client
Business = db.Business
Deal = db.Deal
Media = db.Media
FlipAd = db.FlipAd
Poll = db.Poll
Discussion = db.Discussion


exports.getGoodies = (email, type, limit, skip, callback)->
  #valid types include: inbox, activated, credited, expired
  query = null
  switch type
    when 'inbox'
      query = Goody.inbox.email(email)
    when 'activated'
      query = Goody.activated.email(email)
    when 'credited'
      query = Goody.credited.email(email)
    when 'expired'
      query = Goody.expired.email(email)
    else
      return callback 'invalidType: '+type

  if limit?
    query.limit(limit)
  else
    query.limit(10)
  
  if skip?
    query.skip(skip)
    
  query.find (err, data)->
    callback err, data
  return


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
    @model.findOne {_id: id}, callback
    return

  @get = (options, callback)->
    query = @optionParser(options)
    query.exec callback
    return

    
  @bulkInsert: (docs, options, callback)->
    @model.collection.insert(docs, options, callback)
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
        return callback err, user
      else if !client?
        return self.add(data, callback)
      else if client?
        return callback(new Error('Client already exists'))
        
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
  

class Businesses extends API
  @model = Business
  
  #clientid, limit, skip
  @optionParser = (options, q)->
    query = @_optionParser(options, q)
    
    if options.clientId?
      query.in('users', options.clientId)

    return query
    
  @add = (clientid, data, callback)->
    instance = new @model()
    for own k,v of data
      instance[k] = v
    if data['locations']? and data['locations'] != []
        instance.markModified('locations')

    #add user to the list of users for this business and add the admin role
    instance['users'] = [clientId] #only one user now
    instance['permissions'] = {}
    instance['permissions'][clientId] = [choices.roles.business.ADMIN]

    instance.save callback 
    return

  @addPermissions: (clientId, id, perms, callback)->
    #clientid is the user wanting to remove this permission
    #make sure user has permissions to add permission (where should this happen)

    #perms: {clientid: [roles]}
    #e.g. perms: {'4ab21ad39ae20001': ['admin']}
    for own user, rls in perms
      obj = {}
      for role in rls
        #make sure all the roles exist otherwise die!
        if !roles.business.hasOwnProperty(role)
          callback(new Error('role: ' + role + ' is not a valid role. clientid: '+ user))
          return
      obj[user] = {$each: roles}
    @model.collection.update  {id: id}, {$addToSet: obj}, callback
    return

  @removePermission: (clientId, id, perms, callback)->
    #clientid is the user wanting to remove this permission
    #make sure user has permissions to remove permissions permission (where should this happen)

    #perms: {clientid: [roles]}
    #e.g. perms: {'4ab21ad39ae20001': ['admin']}
    for own user, rls in perms
      obj = {}
      obj[user] = rls
    @model.collection.update  {id: id}, {$pullAll:obj}, callback 

  ###
  #this should probably be here, for now it's in the media class
  @getMedias(businessid, callback)->
    Medias.get {'businessid': businessid}, callback
  ###


class Deals extends API
  @model = Deal
  
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
    query.where('name', options.name) if options.name?
    # query.where('businessid', options.businessid) if options.businessid?
    # query.where('type', options.type) if options.type?
    # query.where('businessname', options.businessname) if options.businessname?
    return query
  
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
    @model.collection.update  {'entity.type': entityType, 'entity.id': entityId, 'media.guid': guid}, {$set:{'media.url': url, 'media.thumb': thumb}}, callback
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
  @getByBusiness = (entityId, type, callback)->
    if typeof(type)=="function"
      callback = type
      @get {entityType: choices.entities.BUSINESS, entityId: entityId}, callback
      #@get {'entity.type': choices.entities.BUSINESS, 'entity.id': entityId}, callback
    else
      @get {entityType: choices.entities.BUSINESS, entityId: entityId, type: type}, callback
      #@get {'entity.type': choices.entities.BUSINESS, 'entity.id': entityId, type: type}, callback
    return
  
  @getByGuid = (entityType, entityId, guid, callback)->
    @get {entityType: entityType, entityId: entityId, guid: guid}, callback
    #@get {'entity.type': entityType, 'entity.id': entityId, 'media.guid': guid}, callback


exports.Clients = Clients
exports.Businesses = Businesses
exports.Deals = Deals
exports.Medias = Medias
exports.FlipAds = FlipAds
exports.Polls = Polls
exports.Discussions = Discussions
