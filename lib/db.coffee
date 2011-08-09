mongoose = require 'mongoose'
mongooseTypes = require 'mongoose-types'

utils = require('globals').utils
countries = require('globals').countries

exports = module.exports

mongooseTypes.loadTypes(mongoose)
Schema = mongoose.Schema
ObjectId = mongoose.SchemaTypes.ObjectId
Email = mongoose.SchemaTypes.Email
Url = mongoose.SchemaTypes.Url

# connect to database
db = mongoose.connect '127.0.0.1', 'goodybag', 1337, (err, conn)->
	if err?
		console.log 'error connecting to db'
	else
		console.log 'successfully connected to db'

# This is my fix for a bug that exists in mongoose that doesn't
# expose these methods if using a named scope

#add some missing cursor methods to model object
['limit', 'skip', 'maxscan', 'snapshot'].forEach (method) ->
  mongoose.Model[method] = (v)->
    cQuery
    if (cQuery = this._cumulativeQuery)
      cQuery.options[method] = v
    this

####################
# Goody ############
####################
Goody = new Schema {
	email             : {type: String, index:true, required:true}
	id                : {type: String, index:true, required:true}
	title             : {type: String, required: true}
	desc              : {type: String}
	image             : {type: String}
	url               : {type: Url}
	share: {
		facebook: {
			allowed       : {type: Boolean, default:false}
			url           : {type: Url}
		}
		twitter: {
			allowed       : {type: Boolean, default:false}
			url           : {type: Url}
		}
	}
	
	company           : {type: String, index:true}
	category          : {type: Array, index: true}
	type              : {type: String, enum: ['freebie', 'discount', 'printable'], index: true}
	state             : {type: String, enum: ['received', 'activated', 'credited'], default: 'received', index: true}
	dates: {
		received        : {type: Date, index: true}
		activated       : {type: Date, index: true}
		credited        : {type: Date, index: true}
		expiration      : {type: Date, index: true}
	}
}

#compound indexes
Goody.index {email:1, id:1}
Goody.index {email:1, company:1}
Goody.index {email:1, category:1}
Goody.index {email:1, type:1}
#Goody.index {email:1, state:1} #already accounted for below
Goody.index {email:1, 'dates.received':1}
Goody.index {email:1, 'dates.activated':1}
Goody.index {email:1, 'dates.credited':1}
Goody.index {email:1, 'dates.expiration':1}
Goody.index {email:1, state:1, 'dates.expiration': 1}

#named scopes
Goody.namedScope('inbox').where('state', 'received').where('dates.expiration').lt(new Date())
Goody.namedScope('activated').where('state', 'activated').where('dates.expiration').lte(new Date())
Goody.namedScope('credited').where('state', 'credited')
Goody.namedScope('expired').where('state').ne('credited').where('dates.expiration').lte(new Date())

#dynamic named scopes
Goody.namedScope 'email', (email)->
	return this.where('email', email)
# 
# Goody.namedScope 'limit', (size)->
# 	this.limit size


####################
# Deal #############
####################
Deal = new Schema {
  did             : {type: String, required: true, unique: true}
  provider        : {type: String, required: true}
  title           : {type: String, required: true}
  description     : {type: String, required: true}
  business: {
    name          : {type: String, required: true}
    street1       : {type: String}
    street2       : {type: String}
    city          : {type: String}
    state         : {type: String}
    zip           : {type: String}
    country       : {type: String, enum: countries.codes}
    lat           : {type: Number}
    lng           : {type: Number}
  }
  city            : {type: String, required: true}
  state           : {type: String, required: true}
  country         : {type: String, required: true, enum: countries.codes}
  costs: { #lowest if there are multiple (as is the case with groupon)
    actual        : {type: Number, required: true}
    discounted    : {type: Number, required: true}
  }
  dates: {
    start         : {type: Date, required: true}
    end           : {type: Date, required: true}
    expires       : {type: Date}
  }
  timezone        : {type: String, required: true}
  image           : {type: Url, required: true}
  tipped          : {type: Boolean, required: true, default: true}
  
  like            : [] #userids that like this deal
  dislike         : [] #userids that disliked this deal
  #available      : {type: Boolean, required: true, default: false}
  
  created         : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
  url             : {type: Url, require: true}
  data            : {}
}

#indexes
#all together, so we can do real-time queries ocross all these values (instead of map/reducing on ones which are not indexed)
#more expensive, but this index isn't really modified that often, so no real worry at the moment
Deal.index {provider:1, city:1, state: 1, 'dates.start': 1, 'dates.end': 1, 'cost.actual': 1, 'cost.discounted': 1, created: 1}
Deal.index {like: 1}
Deal.index {dislike: 1}
#Deal.index {provider:1, city:1, state: 1}
#Deal.index {created: 1}

#named scopes
Deal.namedScope('available').where('dates.end').gt(new Date( (new Date()).toUTCString() ))

#dynamic named scopes
Deal.namedScope 'city', (city)->
  return this.where('city', city)

Deal.namedScope 'tip', ()->
  return this.tip=true

Deal.namedScope 'range', (start, end)->
  return this.where('dates.start').gte(start).where('dates.end').lte(end)

#static functions
Deal.static {
  like: (id, user, callback)->
    this.collection.update  {_id:id}, {$addToSet:{like: user}}, callback
      
  dislike: (id, user, callback)->
    this.collection.update  {_id:id}, {$addToSet:{dislike: user}}, callback
        
  unLike: (id, user, callback)->
    this.collection.update  {_id:id}, {$pull:{like: user}}, callback
        
  unDislike: (id, user, callback)->
    this.collection.update  {_id:id}, {$pull:{dislike: user}}, callback
}


####################
# User #############
####################
User = new Schema {
	email               : {type: String, index: true, unique: true, set: utils.toLower, validate: /^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/}
	password            : {type: String, validate:/.{5,}/}
	fb: {
		access_token      : String
		base_domain       : String
		expires           : Number
		secret            : String
		session_key       : String
		sig               : String
		uid               : {type: String, index: true, unique: true}
		perms             : []
	}
	created             : {type: Date, default: Date.now, index: true}
	logins              : []
	charities           : {}
}

#compound indexes
User.index {email:1, password:1}

#static functions
User.static {
	authenticate: (email, password, callback)->
		this.findOne {email: email, password: password}, (err, user)->
			if(err)
				return callback err, user
			if user?
				return callback err, user
			else
				return callback "invalid username password"
		return
		
	getByFBID: (uid, callback)->
		this.findOne {'fb.uid': uid}, (err, user)->
			return callback err, user
		
	register: (fbid, email, password, callback)->
		if fbid == null or fbid == undefined
			callback 'No facebook id specified'
			return
		this.findOne {"fb.uid": fbid}, (err, user)->
			if(err)
				return callback err, user
			if user == null
				return callback "User not authenticated with facebook"
			if user.email != undefined
				return callback "User already registered"
			
			#everything is ok, update user object and save
			user.email = email
			user.password = password
			user.date = new Date()
			user.save (err)->
				callback err, user
		return
}

# mongoose.model 'User', User
# mongoose.model 'Goody', Goody
# mongoose.model 'Deal', Deal

exports.User  = mongoose.model 'User', User
exports.Goody = mongoose.model 'Goody', Goody
exports.Deal  = mongoose.model 'Deal', Deal

exports.models = {
  User: User
	Goody: Goody
	Deal: Deal
}