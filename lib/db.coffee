exports = module.exports

mongoose = require 'mongoose'
mongooseTypes = require 'mongoose-types'
mongooseTypes.loadTypes(mongoose)
Schema = mongoose.Schema
ObjectId = mongoose.SchemaTypes.ObjectId
Email = mongoose.SchemaTypes.Email
Url = mongoose.SchemaTypes.Url

globals = require 'globals'
utils = globals.utils
choices = globals.choices
countries = globals.countries

# connect to database
db = mongoose.connect '127.0.0.1', 'goodybag', 1337, (err, conn)->
  if err?
    console.log 'error connecting to db'
  #else
  # console.log 'successfully connected to db'

# This is my fix for a bug that exists in mongoose that doesn't
# expose these methods if using a named scope

#add some missing cursor methods to model object
['limit', 'skip', 'maxscan', 'snapshot'].forEach (method) ->
  mongoose.Model[method] = (v)->
    cQuery
    if (cQuery = this._cumulativeQuery)
      cQuery.options[method] = v
    this


exports.disconnect = (callback)->
  db.disconnect(callback)


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
#   this.limit size


####################
# Media ############
####################
Media = new Schema {
  businessid  : {type: ObjectId, required: true}
  type        : {type: String, required: true, enum: choices.media.type._enum}
  uploaddate  : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
  name        : {type: String, required: true}
  url         : {type: Url, required: true}
  duration    : {type: Number}
  filesize    : {type: Number}
  thumb       : {type: Url, required: true}
  thumbs      : [] #only populated if video
  sizes: { #only for images, not yet implemented in transloaded's template, or api
    small     : {type: Url}
    medium    : {type: Url}
    large     : {type: Url}
  }
  tags        : []
}

#indexes
Media.index {businessid:1, type: 1}
Media.index {businessid:1, tags: 1} #use tags instead of folders
Media.index {businessid:1, name:1} #for searching by name
Media.index {businessid:1, uploaddate: 1} #for ordering by date
Media.index {url:1} #for when we want to find out which client a url belongs to


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
  
  voters          : {}
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
Deal.index {did:1}
Deal.index {city:1}
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

Deal.namedScope 'deal', (id)->
  return this.where('_id', id)

Deal.namedScope 'range', (start, end)->
  if start?
    this.where('dates.start').gte(start)
  if end?
    this.where('dates.end').lte(end)
  return query


####################
# User #############
####################
User = new Schema {
  email           : {type: String, index: true, unique: true, set: utils.toLower, validate: /^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/}
  password        : {type: String, validate:/.{5,}/}
  fb: {           
    access_token  : String
    base_domain   : String
    expires       : Number
    secret        : String
    session_key   : String
    sig           : String
    uid           : {type: String, index: true, unique: true}
    perms         : []
  }               
  created         : {type: Date, default: new Date( (new Date()).toUTCString() ), index: true}
  logins          : []
  charities       : {}
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




####################
# Client ###########
####################
Client = new Schema {
  firstname     : {type: String, required: true}
  lastname      : {type: String, required: true}
  phone         : {type: String}
  email         : {type: String, index: true, unique: true, set: utils.toLower, validate: /^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/}
  password      : {type: String, validate:/.{5,}/, required: true}
  created       : {type: Date, default: new Date( (new Date()).toUTCString() ), index: true}
  #permissions   : {} #consider putting this into it's own collection and then cache this entire thing in memory, otherwise cache each logged in user in memory and have this available
  #We are moving permissions(roles) into each object so that it is faster for querying and inserting purposes (double the speed because we now only have to do something to a single collection instead of two collections, right now the benefits outway separating it out into its own collection or even keeping it in the user collection)
}

#indexes
Client.index({email: 1, password: 1})
Client.index({'permissions.businesses.admin': 1})
Client.index({'permissions.businesses.manage': 1})
Client.index({phone: 1})


####################
# Location #########
####################
Location = new Schema {
    name          : {type: String}
    street1       : {type: String, required: true}
    street2       : {type: String}
    city          : {type: String, required: true}
    state         : {type: String, required: true}
    zip           : {type: Number, required: true}
    country       : {type: String, enum: countries.codes, required: true}
    phone         : {type: String, required: true}
    fax           : {type: String}
    lat           : {type: Number}
    lng           : {type: Number}
}


####################
# Business #########
####################
#STORE THIS ENTIRE DB IN MEMCACHE OR REDIS, SHOULD BE SMALL
Business = new Schema {
  name          : {type: String, required: true}
  publicname    : {type: String, required: true}
  logo          : {type: Url} 
  locations     : [Location]
  users         : [ObjectId] #client ids
  permissions   : {}
}

#indexes
Business.index({name: 1})
Business.index({publicname: 1})
Business.index({users: 1})


####################
# FipAd ############
####################
FlipAd = new Schema {
  entity: { #We support multile users creating content (right now, we don't allow users to create flipAds, but we may)
    type          : {type: String, required: true, enum: choices.entities._enum}
    id            : {type: ObjectId, required: true}
    name          : {type: String}
  }
  campaignName    : {type: String, required: true}
  title           : {type: String, required: true}
  description     : {type: String}
  type            : {type: String, required: true, enum: choices.media.type._enum}
  url             : {type: Url, required: true} #video or image
  thumb           : {type: Url}
  dates: {
    created       : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
    start         : {type: Date, required: true}
    end           : {type: Date}
  }
  metaData: {
    duration      : {type: Number} #useful for videos, in number of seconds (e.g. 48.42)
  }
  views: {
    unique        : {type: Number, required: true, default: 0} #this gets incremented only if it was the first time
    overall       : {type: Number, required: true, default: 0} #this gets incremented on every view
  }
  viewers         : [ObjectId] #the users who have viewed this video
  funds: {
    allocated     : {type: Number, required: true}
    remaining     : {type: Number, required: true}
  }
  transaction: {
    state         : {type: String, required: true, enum: choices.transactions.state._enum, default: choices.transactions.state.PENDING}
    error         : {type: String} #only populated if there is an error in the transaction i.e. insufficient funds
    created       : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
    lastmodified  : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
  }
}

#indexes
FlipAd.index('businessid':1, 'dates.created':1) #for listing in the client interface, to show most recently created
FlipAd.index('funds.remainging':1, 'dates.start':1, 'dates.end':1) #for showing the flips ads that are still viewable


####################
# Poll #############
####################

Poll = new Schema {
  name          : {type:String, required: true}
  businessid    : {type: ObjectId, required: true}
  type          : {type: String, require: true, enum: choices.polls.type._enum}
  question      : {type: String, required: true}
  choices       : []
  image         : {type: Url}
  businessName  : {type: String}
  stats         : {type: Boolean, default: true, required: true} #whether to display the stats to the user or not
  answered      : {type: Number, default: 0}
  dates: {
    created     : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
    start       : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
    end         : {type: Date}
  }
  funds: {
    allocated   : {type: Number, required: true}
    remaining   : {type: Number, required: true}
  }

}


####################
# Discussion #######
####################
Discussion = new Schema {
  entity: { #We support various types of users creating discussions (currently businesses and consumers can create discussions)
    type          : {type: String, required: true, enum: choices.entities._enum}
    id            : {type: ObjectId, required: true}
    name          : {type: String}
  }
  campaignName    : {type: String, required: true}
  entityName      : {type: String}
  question        : {type: String, required: true}
  image           : {type: String}
  responses       : {type: Number, required: true, default: 0} #count of the number of responses (not including sub comments)
  bestresponses   : [] #a copy of the responses that were selected as the best response (without sub comments) #up to two
  dates: {
    created       : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
    start         : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
    end           : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
    
    #end           : {type: Date, required: true, default: new Date( (new Date().addWeeks(3)).toUTCString() )} #three week later
  }
  funds: {
    allocated     : {type: Number, required: true}
    remaining     : {type: Number, required: true}
  }
  transaction: {
    state         : {type: String, required: true, enum: choices.transactions.state._enum, default: choices.transactions.state.PENDING}
    error         : {type: String} #only populated if there is an error in the transaction i.e. insufficient funds
    created       : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
    lastmodified  : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
  }
}

#index
Discussion.index('businessid': 1, 'dates.start': 1, 'dates.end': 1)
Discussion.index('transaction.state': 1)


####################
# Response #########
####################
#Responses happen on the consumer end, so no need to worry about specing this out right now
#Responses are in their own collection for two reasons: 
#   They need to be pulled in a limit/skip fashion
#   We want to section them off in groups of either 25/50/100. This way will result in less requests to the database
Response = new Schema {
  discussionid    : {type: ObjectId, required: true}
  ###responses: [{
    userid: ObjectId, required
    response: String, required
  }]###
}


####################
# Stream ###########
####################
Stream = new Schema {
  entity: {
    type       : {type: String, required: true, enum: ['business', 'consumer']},
    id         : {type: ObjectId, required: true}
  }
  type         : {type: String, required: true, enum: ['']}
  action       : {type: String, required: true, enum: ['']}
  datetime     : {type: Date, default: Date.now}
  data         : {}
}

#indexes
Stream.index('entity': 1, 'id': 1, 'datetime': 1, 'type':1)
Stream.index('datetime': 1)

exports.User        = mongoose.model 'User', User
exports.Client      = mongoose.model 'Client', Client
exports.Business    = mongoose.model 'Business', Business
exports.Goody       = mongoose.model 'Goody', Goody
exports.Deal        = mongoose.model 'Deal', Deal
exports.Media       = mongoose.model 'Media', Media
exports.FlipAd      = mongoose.model 'FlipAd', FlipAd
exports.Poll        = mongoose.model 'Poll', Poll
exports.Discussion  = mongoose.model 'Discussion', Discussion

exports.schemas = {
  User: User
  Client: Client
  Business: Business
  Goody: Goody
  Deal: Deal
  Media: Media
  FlipAd: FlipAd
  Poll: Poll
  Discussion: Discussion
}
