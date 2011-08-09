exports = module.exports

db = require './db'
utils = 'globals'

Goody = db.Goody
Deal = db.Deal

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
	
	#WE COULD DO IT LIKE THIS, BUT WE WANT TO CONTROL IT ANYWAY
	#if Goody.hasOwnProperty(req.params.type)
	#	query = Goody[req.params.type].email(req.session.user.email)
	#
	#	if req.params.limit?
	#		query.limit(req.params.limit)
	#	else
	#		query.limit(10)
	#
	#	if req.params.skip?
	#		query.skip(req.params.skip)
    #
	#	query.find (err, data)->
	#		return utils.sendJSON res, data
	#else
	#	return utils.sendJSON res, {}

class Deals
  constructor: ()->
      ['like', 'dislike', 'unLike', 'unDislike'].forEach (method)->
        Deals.prototype[method] = (dealID, user, callback)->
          Deal[method].call Deal, dealID, user, callback
  
  #currently only supports groupon, more abstraction needed to support more deals
  add: (data, callback)->
    deal = new Deal();
    for own k,v of data
      deal[k] = v
    deal.save callback
  
  remove: (id, callback)->
    deal = Deals.findById id
    deal.remove callback
    
  getDeal: (id, callback)->
    Deals.findById id, callback
    
  getDeals: (city, start, end, callback)->
    query = Deal.city city
    if start? and end?
      query.range start, end
    else
      query.available
    query.find callback

exports.Deals = Deals