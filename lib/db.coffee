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
defaults = globals.defaults
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
# DailyDeal ########
####################
DailyDeal = new Schema {
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
    country       : {type: String, enum: countries.codes, default: "us"}
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
DailyDeal.index {did:1}
DailyDeal.index {city:1}
DailyDeal.index {provider:1, city:1, state: 1, 'dates.start': 1, 'dates.end': 1, 'cost.actual': 1, 'cost.discounted': 1, created: 1}
DailyDeal.index {like: 1}
DailyDeal.index {dislike: 1}
#DailyDeal.index {provider:1, city:1, state: 1}
#DailyDeal.index {created: 1}

#named scopes
DailyDeal.namedScope('available').where('dates.end').gt(new Date( (new Date()).toUTCString() ))

#dynamic named scopes
DailyDeal.namedScope 'city', (city)->
  return this.where('city', city)

DailyDeal.namedScope 'deal', (id)->
  return this.where('_id', id)

DailyDeal.namedScope 'range', (start, end)->
  if start?
    this.where('dates.start').gte(start)
  if end?
    this.where('dates.end').lte(end)
  return query


####################
# CONSUMER #########
####################
Consumer = new Schema {
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
Consumer.index {email:1, password:1}

#static functions
Consumer.static {
  authenticate: (email, password, callback)->
    this.findOne {email: email, password: password}, (err, consumer)->
      if(err)
        return callback err, consumer
      if consumer?
        return callback err, consumer
      else
        return callback "invalid consumername password"
    return
    
  getByFBID: (uid, callback)->
    this.findOne {'fb.uid': uid}, (err, consumer)->
      return callback err, consumer
    
  register: (fbid, email, password, callback)->
    if fbid == null or fbid == undefined
      callback 'No facebook id specified'
      return
    this.findOne {"fb.uid": fbid}, (err, consumer)->
      if(err)
        return callback err, consumer
      if consumer == null
        return callback "User not authenticated with facebook"
      if consumer.email != undefined
        return callback "User already registered"
      
      #everything is ok, update consumer object and save
      consumer.email = email
      consumer.password = password
      consumer.date = new Date()
      consumer.save (err)->
        callback err, consumer
    return
}

####################
# Client ###########
####################
Client = new Schema {
  firstName     : {type: String, required: true}
  lastName      : {type: String, required: true}
  email         : {type: String, index: true, unique: true, set: utils.toLower, validate: /^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/}
  password      : {type: String, validate:/.{5,}/, required: true}
  media: {
    url         : {type: Url, required: true} #video or image
    thumb       : {type: Url}
    guid        : {type: String}
  }
  dates: {
    created     : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
  }
}

#indexes
Client.index {email: 1, password: 1}


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
    country       : {type: String, enum: countries.codes, required: true, default: "us"}
    phone         : {type: String}
    fax           : {type: String}
    lat           : {type: Number}
    lng           : {type: Number}
}


####################
# Business #########
####################
Business = new Schema {
  name          : {type: String, required: true}
  publicName    : {type: String, required: true}
  url           : {type: Url}
  email         : {type: Email}

  legal: { #legal
    street1     : {type: String, required: true}
    street2     : {type: String}
    city        : {type: String, required: true}
    state       : {type: String, required: true}
    zip         : {type: Number, required: true}
    country     : {type: String, enum: countries.codes, required: true, default: "us"}
    phone       : {type: String, required: true}
    fax         : {type: String}
  }

  locations     : [Location]

  media: {
    url         : {type: Url, required: true, default: "http://www.campusdish.com/NR/rdonlyres/1E7DF990-91DC-4101-99CD-96A23A2E5E7E/0/Subwaycontour.gif"} #image
    thumb       : {type: Url}
    guid        : {type: String}
    duration    : {type: Number} #useful for videos, in number of seconds (e.g. 48.42)
  }
  
  clients       : [ObjectId] #clientIds
  clientGroups  : {} #{clientId: group}
  groups: {
    #default groups for a business, others can be created
    owners      : [ObjectId] #clientIds
    managers    : [ObjectId] #clientIds
  }

  dates: {
    created     : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
  }

  funds: {
    allocated     : {type: Number, required: true}
    remaining     : {type: Number, required: true}
  }

  permissions: { #permissions for groups
  #nothing needs to be done for now, but in the future permissions for groups will be taken care of here.
  #we take care of logic and permissions for owners and manager
  #owners and managers can't change, the permissions can't change either, therefore no need to specify anything for them now
    #default groups for a business
    #owners      : [String]
    #managers    : [String]
  }

  transactions: {
    ids           : [ObjectId]
    history       : {}

    # Example of transaction history object
    # history: {
    #   transactionId: { #transactionId is a string representation of the ObjectId
    #     document: {
    #       type          : {type: String, required: true, enum: choices.transactions.types._enum}
    #       id            : {type: ObjectId, required: true}
    #     }
    #     amount: {type: Number}
    #     timestamp: {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
    #   }
    # }

  }
}

#indexes
Business.index {name: 1}
Business.index {publicName: 1}
Business.index {users: 1}


####################
# Poll #############
####################
Poll = new Schema {
  entity: { #We support various types of users creating discussions (currently businesses and consumers can create discussions)
    type          : {type: String, required: true, enum: choices.entities._enum}
    id            : {type: ObjectId, required: true}
    name          : {type: String}
  }
  name            : {type: String, required: true}
  type            : {type: String, required: true, enum: choices.polls.type._enum}
  question        : {type: String, required: true}
  choices         : [type: String, required: true]
  numChoices      : {type: Number, required: true}
  responses: {
    remaining     : {type: Number, required: true} #decrement each response
    max           : {type: Number, required: true}
    consumers     : [type: ObjectId] #append ObjectId(consumerId) each response
    log           : {}               #append consumerId:{answers:[1,2],timestamp:Date}
    dates         : []               #append {consumerId:ObjId,timestamp:Date} -- for sorting by date
    choiceCounts  : [type: Number, required: true] #increment each choice chosen
  }
  showStats       : {type: Boolean, required: true} #whether to display the stats to the user or not
  displayName     : {type: Boolean, required: true}
  displayMedia    : {type: String, required: true, default: choices.polls.displayMedia.NO, enum: choices.polls.displayMedia._enum}
  media: {
    url           : {type: Url, required: true} #video or image
    thumb         : {type: Url}
    guid          : {type: String}
  }
  dates: {
    created       : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
    start         : {type: Date, required: true}
    end           : {type: Date}
  }
  funds: {
    perResponse   : {type: Number, required: true}
    allocated     : {type: Number, required: true, default: 0.0}
    remaining     : {type: Number, required: true, default: 0.0}
  }

  transactions: {
    ids           : [ObjectId]
    history       : {}
    
    # Example of a transaction history object
    # history = {
    #   transactionId: {
    #     state: {type: String, required: true, enum: choices.transactions.state._enum, default: choices.transactions.state.PENDING}
    #     created: {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
    #     lastModified: {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
    #     amount: {type: Number, required: true, default: 0.0}
    #   }
    # }
    
    currentState  : {type: String, required: true, enum: choices.transactions.state._enum, default: choices.transactions.state.PENDING}
    currentId     : {type: ObjectId}
    
    currentBalance: {type: Number, required: true, default: 0.0}
    newBalance    : {type: Number, required: true, default: 0.0}
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
  question        : {type: String, required: true}
  details         : {type: String}
  tags            : [String]
  media: {
    url           : {type: Url, required: true} #video or image
    thumb         : {type: Url}
    guid          : {type: String}
  }
  dates: {
    created       : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
    start         : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
    end           : {type: Date}
    
    #end           : {type: Date, required: true, default: new Date( (new Date().addWeeks(3)).toUTCString() )} #three week later
  }
  funds: {
    allocated     : {type: Number, required: true, default: 0.0}
    remaining     : {type: Number, required: true, default: 0.0}
  }
  
  transactions: {
    ids           : [ObjectId]
    history       : {}
    
    # Example of a transaction history object
    # history = {
    #   transactionId: {
    #     state: {type: String, required: true, enum: choices.transactions.state._enum, default: choices.transactions.state.PENDING}
    #     created: {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
    #     lastModified: {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
    #     amount: {type: Number, required: true, default: 0.0}
    #   }
    # }
    
    currentState  : {type: String, required: true, enum: choices.transactions.state._enum, default: choices.transactions.state.PENDING}
    currentId     : {type: ObjectId}
    
    currentBalance: {type: Number, required: true, default: 0.0}
    newBalance    : {type: Number, required: true, default: 0.0}
  }
}

#index
Discussion.index {'entity.type': 1, 'entity.id': 1, 'dates.start': 1, 'dates.end': 1} #for listing in the client interface, to show most recently created
Discussion.index {'transaction.state': 1}


####################
# Response #########
####################
#Responses happen on the consumer end, so no need to worry about specing this out right now
#Responses are in their own collection for two reasons: 
#   They need to be pulled in a limit/skip fashion
#   We want to section them off in groups of either 25/50/100. This way will result in less requests to the database

###THIS IS AN OPTIMIZATION WE CAN DO LATER - LETS REACH THIS MUCH ACTIVITY THAT OUR SITE SLOWS DOWN :)
Response = new Schema {
  discussionId    : {type: ObjectId, required: true}
  responses: [{
    entity: { #We support various types of users creating discussions (currently businesses and consumers can create discussions)
      type   : {type: String, required: true, enum: choices.entities._enum}
      id     : {type: ObjectId, required: true}
      name   : {type: String}
    }
    response : {type: String, required: true}
  }]
}

###

Response = new Schema {
  entity: { #We support various types of users creating discussions (currently businesses and consumers can create discussions)
    type          : {type: String, required: true, enum: choices.entities._enum}
    id            : {type: ObjectId, required: true}
    name          : {type: String}
  }
  
  discussionId    : {type: ObjectId, required: true}
  response        : {type: String, required: true}
  parent          : {type: ObjectId} #was this in response to a previous response? which one?
  dates: {
    created       : {type: Date, default: new Date( (new Date()).toUTCString() )}
  }
}

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
  media: {
    url           : {type: Url, required: true} #video or image
    thumb         : {type: Url}
    guid          : {type: String}
    duration      : {type: Number} #useful for videos, in number of seconds (e.g. 48.42)
  }
  dates: {
    created       : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
    start         : {type: Date, required: true}
    end           : {type: Date}
  }
  views: {
    unique        : {type: Number, required: true, default: 0} #this gets incremented only if it was the first time
    overall       : {type: Number, required: true, default: 0} #this gets incremented on every view
  }
  viewers         : [ObjectId] #the users who have viewed this video
  funds: {
    allocated     : {type: Number, required: true, default: 0}
    remaining     : {type: Number, required: true, default: 0}
  }
  transaction: {
    state         : {type: String, required: true, enum: choices.transactions.state._enum, default: choices.transactions.state.PENDING}
    error         : {type: String} #only populated if there is an error in the transaction i.e. insufficient funds
    created       : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
    lastModified  : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
  }
}

#indexes
FlipAd.index {'entity.type': 1, 'entity.id': 1, 'dates.start': 1, 'dates.end': 1} #for listing in the client interface, to show most recently created
FlipAd.index {'funds.remainging': 1, 'dates.start': 1, 'dates.end': 1} #for showing the flips ads that are still viewable
FlipAd.index {'entity.type': 1, 'entity.id': 1, 'media.url': 1} #to look up by url
FlipAd.index {'entity.type': 1, 'entity.id': 1, 'media.guid': 1} #to look up by guid


####################
# Deal #############
####################
Deal = new Schema {
  entity: { #We support different types of users creating and uploading content 
    type          : {type: String, required: true, enum: choices.entities._enum}
    id            : {type: ObjectId, required: true}
    name          : {type: String}
  }
  
  type            : {type: String, required: true, enum: choices.deals.type._enum}
  campaignName    : {type: String, required: true}

  item            : {type: String} #product or service
  item2           : {type: String} #the second product or service
  discount        : {type: Number} #dollar or percentage depending on deal type
  value           : {type: Number, required: true} #estimated value / estimated retail value / minimum purchase amount
  price           : {type: Number, required: true} #sale price

  title           : {type: String, required: true}
  subtitle        : {type: String}
  locations       : [String]
  terms           : {type: String}
  restrictions    : {type: String}
  purchaseLimit   : {type: Number, required: true, default: -1} #max per consumer, -1 is infinite
  availabile      : {type: Number, required: true, default: -1} #if infinite -1?
  code            : {type: String}
  media: {
    url           : {type: Url, required: true} #video or image
    thumb         : {type: Url}
    guid          : {type: String}
  }
  dates: {
    created     : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
    start       : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
    end         : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
    expiration  : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
  }
  
}


####################
# Media ############
####################
Media = new Schema {
  entity: { #We support different types of users creating and uploading content 
    type      : {type: String, required: true, enum: choices.entities._enum}
    id        : {type: ObjectId, required: true}
    name      : {type: String}
  }
  type        : {type: String, required: true, enum: choices.media.type._enum}
  name        : {type: String, required: true}
  url         : {type: Url, required: true}
  duration    : {type: Number}
  fileSize    : {type: Number}
  thumb       : {type: Url, required: true}
  thumbs      : [] #only populated if video
  sizes: { #only for images, not yet implemented in transloaded's template, or api
    small     : {type: Url}
    medium    : {type: Url}
    large     : {type: Url}
  }
  tags        : []
  dates: {
    created   : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
  }
}

#indexes
Media.index {'entity.type': 1, 'entity.id': 1, type: 1} #for listing in the client interface, to show most recently created
Media.index {'entity.type': 1, 'entity.id': 1, tags: 1} #for searching by tags
Media.index {'entity.type': 1, 'entity.id': 1, name: 1} #for searching by name
Media.index {'entity.type': 1, 'entity.id': 1, 'dates.created': 1} #for searching by name
Media.index {url:1} #for when we want to find out which entity a url belongs to


####################
# ClientInvitation #
####################
ClientInvitation = new Schema {
  businessId      : {type: ObjectId, required: true}
  groupName       : {type: String, required: true}
  email           : {type: Email, required: true}
  key             : {type: String, required: true}
  status          : {type: String, required: true, enum: choices.invitations.state._enum, default: choices.invitations.state.PENDING}
  dates: {
    created       : {type: Date, default: new Date( (new Date()).toUTCString() )}
    expires       : {type: Date}
  }
}

#unique index on businessId + email address is required


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
  dateTime     : {type: Date, default: Date.now}
  data         : {}
}

#indexes
Stream.index('entity': 1, 'id': 1, 'datetime': 1, 'type':1)
Stream.index('datetime': 1)


####################
# TAG ##############
####################
Tag = new Schema {
  name: {type: String, required: true}
}

Tag.index('name': 1)

############
# Events ###
############
EventDateRange = new Schema {
  start: {type: Date, required: true}
  end: {type: Date, required: true}
}
Event = new Schema {
  entity      : { 
    type      : {type: String, required: true, enum: choices.entities._enum}
    id        : {type: ObjectId, required: true}
    name      : {type: String}
  }
  locationId  : {type: ObjectId}
  location    : {
    name      : {type: String}
    street1   : {type: String, required: true}
    street2   : {type: String}
    city      : {type: String, required: true}
    state     : {type: String, required: true}
    zip       : {type: Number, required: true}
    country   : {type: String, enum: countries.codes, required: true, default: "us"}
    phone     : {type: String}
    fax       : {type: String}
    lat       : {type: Number}
    lng       : {type: Number}
  }
  dates       : {
    requested : {type: Date, required: true}
    responded : {type: Date, required: true}
    actual    : {type: Date, required: true}
  }
  hours       : [EventDateRange]
  pledge      : {type: Number, min: 0, max: 100, required: true}
  externalUrl : {type: Url}
  rsvp        : [ObjectId]
  rsvpUsers   : {}
}

#####################
# Events Requests ###
#####################
EventRequest = new Schema {
  userEntity          : {
    type              : {type: String, required: true, enum: choices.entities._enum}
    id                : {type: ObjectId, required: true}
    name              : {type: String}
  }
  organizationEntity  : {
    type              : {type: String, required: true, enum: choices.entities._enum}
    id                : {type: ObjectId, required: true}
    name              : {type: String}
  }
  date                : {
    requested         : {type: Date, default: Date.now}
    responded         : {type: Date}
  }
}

exports.DailyDeal           = mongoose.model 'DailyDeal', DailyDeal
exports.Consumer            = mongoose.model 'Consumer', Consumer
exports.Client              = mongoose.model 'Client', Client
exports.Business            = mongoose.model 'Business', Business
exports.Poll                = mongoose.model 'Poll', Poll
exports.Discussion          = mongoose.model 'Discussion', Discussion
exports.Response            = mongoose.model 'Response', Response
exports.FlipAd              = mongoose.model 'FlipAd', FlipAd
exports.Deal                = mongoose.model 'Deal', Deal
exports.Media               = mongoose.model 'Media', Media
exports.ClientInvitation    = mongoose.model 'ClientInvitation', ClientInvitation
exports.Tag                 = mongoose.model 'Tag', Tag
exports.EventRequest        = mongoose.model 'EventRequest', EventRequest
exports.Event               = mongoose.model 'Event', Event

exports.schemas = {
  DailyDeal: DailyDeal
  Consumer: Consumer
  Client: Client
  Business: Business
  Poll: Poll
  Discussion: Discussion
  Response: Response
  FlipAd: FlipAd
  Deal: Deal
  Media: Media
  ClientInvitation: ClientInvitation
  Tag: Tag
  EventRequest: EventRequest
  Event: Event
}
