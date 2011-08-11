exports = module.exports

db = require './db'
util = require 'util'

Goody = db.Goody
Deal = db.Deal

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

class API
  @model = null
  constructor: ()->
    #nothing to say
  @query: ()->
    return @model.find() #instance of query object
  
  @bulkInsert: (docs, options, callback)->
    @model.collection.insert(docs, options, callback)

class Deals extends API
  @model = Deal
  
  @like: (id, user, callback)->
    voters = {}
    voters['voters.'+user] = 1
    @model.collection.update  {_id:id}, {$addToSet:{like: user}, $pull:{dislike: user}, $set:voters}, callback

  @dislike: (id, user, callback)->
    voters = {}
    voters['voters.'+user] = -1
    @model.collection.update  {_id:id}, {$addToSet:{dislike: user}, $pull:{like: user}, $set:voters}, callback

  @neutral: (id, user, callback)->
    voters = {}
    voters['voters.'+user] = 1 #for unsetting
    @model.collection.update  {_id:id}, {$pull:{dislike: user, like: user}, $unset:voters}, callback
  
  #currently only supports groupon, more abstraction needed to support more deals
  @add: (data, callback)->
    deal = new Deal();
    for own k,v of data
      deal[k] = v
    deal.save callback
  
  @remove: (id, callback)->
    @model.remove {'_id': id}, callback
    
  @getDeal: (id, callback)->
    @model.findOne {_id: id}, {data: 0, dislike: 0}, callback
  
  #options: city, start, end, limit, skip
  @getDeals: (options, callback)->
    query = Deal.find()

    if typeof(options) === 'function'
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

exports.Deals = Deals