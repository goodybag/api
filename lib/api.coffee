exports = module.exports

db = require './db'
util = require 'util'
globals = require 'globals'

utils = globals.utils

Goody = db.Goody
Deal = db.Deal
Media = db.Media

#util.log util.inspect Deal, true, 2

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

class API
  @model = null
  constructor: ()->
    #nothing to say
  
  @_query: ()->
    return @model.find() #instance of query object
  
  @_optionParser = (options, q)->
    query = q || @_query()
    return query
  
  @add = (data, callback)->
    instance = new @model()
    for own k,v of data
      instance[k] =v
    instance.save callback
    return

  @remove = (id, callback)->
    @model.remove {'_id': id}, callback
    return

  @get = (id, callback)->
    @model.findOne {_id: id}, callback
    return
    
  @bulkInsert: (docs, options, callback)->
    @model.collection.insert(docs, options, callback)
    return

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

class Medias extends API
  @model = Media
  
  #options: clientid, type, tags, start, end, limit, skip
  @_optionParser = (options, q)->
    query = q || @_query()
    
    if options.clientid?
      query.where('clientid', options.clientid)
    
    if options.type?
      query.where('type', options.type)
    
    if options.tags?
      query.in('tags', options.tags)
    
    if options.start?
      query.where('uploaddate').gte(options.start)
    
    if options.end?
      query.where('uploaddate').lte(options.end)
      
    if options.limit?
      query.limit(options.limit)

    if options.skip?
      query.skip(options.skip)
    
    return query
  
  @getFiles = (options, callback)->
    #THIS SHOULD HAPPEN IN THE WEB ROUTES END, MAKING SURE THE PARAMETERS REQUIRED EXIST
    #if !utils.mustContain(options, 'clientid')
    #  callback(new Error('required field(s) were missing. required fileds are: clientid'), null)
    
    query = @_optionParser(options)
    query.exec callback
    return
    
exports.Deals = Deals
exports.Medias = Medias