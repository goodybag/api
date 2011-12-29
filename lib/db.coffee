exports = module.exports

globals = require 'globals'
loggers = require "./loggers"

utils = globals.utils
defaults = globals.defaults
choices = globals.choices
countries = globals.countries

mongoose = globals.mongoose

Schema = mongoose.Schema
ObjectId = mongoose.SchemaTypes.ObjectId

#validation
Url = /(ftp|http|https):\/\/(\w+:{0,1}\w*@)?(\S+)(:[0-9]+)?(\/|\/([\w#!:.?+=&%@!\-\/]))?/
Email = /^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/


####################
# TRANSACTION ######
####################

#Transaction = new Schema {}

Transaction = new Schema {
  id              : {type: ObjectId, required: true}
  state           : {type: String, required: true, enum: choices.transactions.states._enum}
  action          : {type: String, required: true, enum: choices.transactions.actions._enum}
   
  error: {
    message       : {type: String}
  }
  
  dates: {
    created       : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
    completed     : {type: Date}
    lastModified  : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
  }
  
  #EXTRA INFO GOES IN HERE
  data: {}
  
  #INBOUND = DEPOST, OUTBOUND = WIDTHDRAWL
  direction       : {type: String, required: true, enum: choices.transactions.directions._enum}
  
  #DEPOSIT OR DEDUCT TO/FROM WHOM? (Sometimes we may use the entity object in the document itself)
  entity: {
    type          : {type: String, required: true, enum: choices.entities._enum}
    id            : {type: ObjectId, required: true}
    name          : {type: String}
  }

  attempts        : {type: Number, default: 0}
  pollerId        : {type: ObjectId} #THIS IS FOR IF WE FAIL AND THE POLLER PICKS IT UP

}


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
    #Lets us know if this business can supports tapins
    tapins        : {type: Boolean}
}


###################################################################
###################################################################
###################################################################


##################################
# PASSWORD RESET REQUEST #########
##################################
PasswordResetRequest = new Schema {
  date        : {type: Date, default: new Date( (new Date()).toUTCString() )}
  key         : {type: String, required: true, unique: true}
  entity: {
    type      : {type: String, required: true, enum: choices.entities._enum}
    id        : {type: ObjectId, required: true}
    name      : {type: String}
  }
  consumed    : {type: Boolean, default: false}
}

####################
# CONSUMER #########
####################
Consumer = new Schema {
  email           : {type: String, set: utils.toLower, validate: Email}
  password        : {type: String, validate:/.{5,}/}
  facebook: {           
    access_token  : String
    #id            : Number
  }               
  created         : {type: Date, default: new Date( (new Date()).toUTCString() )}
  logins          : []
  honorScore      : {type: Number, required: true, default: 0}
  charities       : {}

  funds: {
    allocated     : {type: Number, required: true, default: 0.0}
    remaining     : {type: Number, required: true, default: 0.0}
  }
 
  transactions: {
    ids           : [ObjectId]
    failed        : [ObjectId]
    log           : [Transaction]
    temp          : [Transaction]
    locked        : {type: Boolean}
    state         : {type: String, enum: choices.transactions.states._enum}
  } 

  events: {
    ids           : [ObjectId]
    history       : {}
  }
}


####################
# Client ###########
####################
Client = new Schema {
  firstName     : {type: String, required: true}
  lastName      : {type: String, required: true}
  email         : {type: String, index: true, unique: true, set: utils.toLower, validate: Email}
  password      : {type: String, validate:/.{5,}/, required: true}
  media: {
    url         : {type: String, validate: Url}
    thumb       : {type: String, validate: Url}
    guid        : {type: String}
  }
  dates: {
    created     : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
  }

  funds: {
    allocated   : {type: Number, required: true, default: 0.0}
    remaining   : {type: Number, required: true, default: 0.0}
  }
  
  transactions: {
    ids         : [ObjectId]
    failed      : [ObjectId]
    log         : [Transaction]
    temp        : [Transaction]
    locked      : {type: Boolean}
    state       : {type: String, enum: choices.transactions.states._enum}
  }

  events: {
    ids         : [ObjectId]
    history     : {}
  }
}


####################
# Business #########
####################
Business = new Schema {
  name          : {type: String, required: true}
  publicName    : {type: String, required: true}
  type          : [{type: String, required: true, enum: choices.businesses.types._enum}]
  url           : {type: String, validate: Url}
  email         : {type: String, validate: Email}

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
    url         : {type: String, validate: Url} #image
    thumb       : {type: String, validate: Url}
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
    allocated   : {type: Number, required: true}
    remaining   : {type: Number, required: true}
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
    ids         : [ObjectId]
    failed      : [ObjectId]
    log         : [Transaction] 
    temp        : [Transaction]
    locked      : {type: Boolean}
    state       : {type: String, enum: choices.transactions.states._enum}
  }

  events: {
    ids         : [ObjectId]
    history     : {}
  }
}


####################
# Poll #############
####################
Poll = new Schema {
  entity: { #We support various types of users creating discussions (currently businesses and consumers can create discussions)
    type              : {type: String, required: true, enum: choices.entities._enum}
    id                : {type: ObjectId, required: true}
    name              : {type: String}
  }
  name                : {type: String, required: true}
  type                : {type: String, required: true, enum: choices.polls.type._enum}
  question            : {type: String, required: true}
  choices             : [type: String, required: true]
  numChoices          : {type: Number, required: true}
  showStats           : {type: Boolean, required: true} #whether to display the stats to the user or not
  displayName         : {type: Boolean, required: true}
  displayMedia        : {type: Boolean, required: true}
  responses: {
    remaining     : {type: Number,   required: true} #decrement each response
    max           : {type: Number,   required: true}
    consumers     : [type: ObjectId, required: true, default: new Array()] #append ObjectId(consumerId) each response
    log           : {}                             #append consumerId:{answers:[1,2],timestamp:Date}
    dates         : []                             #append {consumerId:ObjId,timestamp:Date} -- for sorting by date
    choiceCounts  : [type: Number,   required: true, default: new Array()] #increment each choice chosen, default should be a zero array..
    flagConsumers : [type: ObjectId, required: true, default: new Array()]
    flagCount     : {type: Number,   required: true, default: 0}
    skipConsumers : [type: ObjectId, required: true, default: new Array()]
    skipCount     : {type: Number,   required: true, default: 0}
  }
  
  media: {
    when          : {type: String, required: true, enum: choices.polls.media.when._enum } #when to display
    url           : {type: String, validate: Url} #video or image
    thumb         : {type: String, validate: Url}
    guid          : {type: String}
  }
  dates: {
    created           : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
    start             : {type: Date, required: true}
    end               : {type: Date}
  }
  funds: {
    perResponse       : {type: Number, required: true}
    allocated         : {type: Number, required: true, default: 0.0}
    remaining         : {type: Number, required: true, default: 0.0}
  }

  
  transactions: {
    ids               : [ObjectId]
    failed            : [ObjectId]
    log               : [Transaction]
    temp              : [Transaction]
    locked            : {type: Boolean}
    state             : {type: String, enum: choices.transactions.states._enum}
  }

  events: {
    ids               : [ObjectId]
    history           : {}
  }

  deleted             : {type: Boolean, default: false}
}


####################
# Discussion #######
####################
Discussion = new Schema {
  entity: { #We support various types of users creating discussions (currently businesses and consumers can create discussions)
    type              : {type: String, required: true, enum: choices.entities._enum}
    id                : {type: ObjectId, required: true}
    name              : {type: String}
  }
  name                : {type: String, required: true}
  question            : {type: String, required: true}
  details             : {type: String}
  tags                : [String]
  displayName         : {type: Boolean, required: true}
  displayMedia        : {type: Boolean, required: true}
  responses: {
    count         : {type: Number, required: true, default: 0}
    consumers     : [type: ObjectId, required: true, default: new Array()] #append ObjectId(consumerId) each response
    log           : {}                             #append consumerId:{answers:[1,2],timestamp:Date}
    dates         : []                             #append {consumerId:ObjId,timestamp:Date} -- for sorting by date
    flagConsumers : [type: ObjectId, required: true, default: new Array()]
    flagCount     : {type: Number,   required: true, default: 0}
  }
  media: {
    url               : {type: String, validate: Url}
    thumb             : {type: String, validate: Url}
    guid              : {type: String}
  }
  dates: {
    created           : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
    start             : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
    end               : {type: Date}
    
    #end           : {type: Date, required: true, default: new Date( (new Date().addWeeks(3)).toUTCString() )} #three week later
  }
  funds: {
    allocated         : {type: Number, required: true, default: 0.0}
    remaining         : {type: Number, required: true, default: 0.0}
  }
  
  transactions: {
    ids               : [ObjectId]
    failed            : [ObjectId]
    log               : [Transaction]
    temp              : [Transaction]
    locked            : {type: Boolean}
    state             : {type: String, enum: choices.transactions.states._enum}
  }

  events: {
    ids               : [ObjectId]
    history           : {}
  }

  deleted             : {type: Boolean, default: false}
}


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
  
  transactions: {
    ids           : [ObjectId]
    failed        : [ObjectId]
    log           : [Transaction]
    temp          : [Transaction]
    locked        : {type: Boolean}
    state         : {type: String, enum: choices.transactions.states._enum}
  }

  events: {
    ids           : [ObjectId]
    history       : {}
  }

  deleted             : {type: Boolean, default: false}
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
  url         : {type: String, validate: Url}
  duration    : {type: Number}
  fileSize    : {type: Number}
  thumb       : {type: String, validate: Url}
  thumbs      : [] #only populated if video
  sizes: { #only for images, not yet implemented in transloaded's template, or api
    small     : {type: String, validate: Url}
    medium    : {type: String, validate: Url}
    large     : {type: String, validate: Url}
  }
  tags        : []
  dates: {
    created   : {type: Date, required: true, default: new Date( (new Date()).toUTCString() )}
  }

  events: {
    ids       : [ObjectId]
    history   : {}
  }

  transactions: {
    ids       : [ObjectId]
    failed    : [ObjectId]
    log       : [Transaction]
    temp      : [Transaction]
    locked    : {type: Boolean}
    state     : {type: String, enum: choices.transactions.states._enum}
  }

  deleted             : {type: Boolean, default: false}
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
  email           : {type: String, required: true, validate: Email}
  key             : {type: String, required: true}
  status          : {type: String, required: true, enum: choices.invitations.state._enum, default: choices.invitations.state.PENDING}
  dates: {
    created       : {type: Date, default: new Date( (new Date()).toUTCString() )}
    expires       : {type: Date}
  }

  transactions: {
    ids           : [ObjectId]
    failed        : [ObjectId]
    log           : [Transaction]
    temp          : [Transaction]
    locked        : {type: Boolean}
    state         : {type: String, enum: choices.transactions.states._enum}
  }
  
  events: {
    ids           : [ObjectId]
    history       : {}
  }
}

#unique index on businessId + group + email address is required
ClientInvitation.index {businessId: 1, groupName: 1, email: 1}, {unique: true}


####################
# Stream ###########
####################
Stream = new Schema {
  eventType     : {type: String, required: true, enum: choices.eventTypes._enum}
  eventId       : {type: ObjectId, required: true} #unique
  entity: {
    type        : {type: String, required: true, enum: choices.entities._enum}
    id          : {type: ObjectId, required: true}
    name        : {type: String}
  }
  documentId    : {type: ObjectId, required: true}
  message       : {type: String}
  dates: {
    event       : {type: Date, required: true} #event date/time
    created     : {type: Date, default: new Date( (new Date()).toUTCString() )} #timestamp added to the stream
  }
  data          : {}

  transactions: {
    ids         : [ObjectId]
    failed      : [ObjectId]
    log         : [Transaction]
    temp        : [Transaction]
    locked      : {type: Boolean}
    state       : {type: String, enum: choices.transactions.states._enum}
  }
  
  events: {
    ids         : [ObjectId]
    history     : {}
  }

  deleted             : {type: Boolean, default: false}
}

#indexes


####################
# TAG ##############
####################
Tag = new Schema {
  name: {type: String, required: true}

  transactions: {
    ids           : [ObjectId]
    failed        : [ObjectId]
    log           : [Transaction]
    temp          : [Transaction]
    locked        : {type: Boolean}
  }
}


############
# Events ###
############
EventDateRange = new Schema {
  start: {type: Date, required: true}
  end: {type: Date, required: true}
}

Event = new Schema {
  entity: { 
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
  
  dates: {
    requested : {type: Date, required: true}
    responded : {type: Date, required: true}
    actual    : {type: Date, required: true}
  }
  
  hours       : [EventDateRange]
  pledge      : {type: Number, min: 0, max: 100, required: true}
  externalUrl : {type: String, validate: Url}
  rsvp        : [ObjectId]
  rsvpUsers   : {}

  transactions: {
    ids       : [ObjectId]
    failed    : [ObjectId]
    log       : [Transaction]
    temp      : [Transaction]
    locked    : {type: Boolean}
    state     : {type: String, enum: choices.transactions.states._enum}
  }
}

#####################
# Events Requests ###
#####################
EventRequest = new Schema {
  userEntity: {
    type                : {type: String, required: true, enum: choices.entities._enum}
    id                  : {type: ObjectId, required: true}
    name                : {type: String}
  }
  
  organizationEntity: {
    type                : {type: String, required: true, enum: choices.entities._enum}
    id                  : {type: ObjectId, required: true}
    name                : {type: String}
  }
  
  date: {
    requested           : {type: Date, default: Date.now}
    responded           : {type: Date}
  }

  transactions: {
    ids                 : [ObjectId]
    failed              : [ObjectId]
    log                 : [Transaction]
    temp                : [Transaction]
    locked              : {type: Boolean}
  }
}

############
# TapIns ###
############
TapIn = new Schema {
  userEntity: {
    type                : {type: String, required: true, enum: choices.entities._enum}
    id                  : {type: ObjectId, required: true}
    name                : {type: String}
  }
  
  organizationEntity: {
    type                : {type: String, required: true, enum: choices.entities._enum}
    id                  : {type: ObjectId, required: true}
    name                : {type: String}
  }

  registerId            : {type: String, required: true}
  date                  : {type: Date, required: true}
  transactionAmount     : {type: Number, required: true}
  donationAmount        : {type: Number, required: true}
}

#######################
# Business Requests ###
#######################
BusinessRequest = new Schema {
  userEntity: {
    type                : {type: String, required: true, enum: choices.entities._enum}
    id                  : {type: ObjectId, required: true}
    name                : {type: String}
  }
  businessName          : {type: String, require: true}
  date: {
    requested           : {type: Date, default: Date.now}
    read                : {type: Date}
  }
}

exports.Consumer              = mongoose.model 'Consumer', Consumer
exports.Client                = mongoose.model 'Client', Client
exports.Business              = mongoose.model 'Business', Business
exports.Poll                  = mongoose.model 'Poll', Poll
exports.Discussion            = mongoose.model 'Discussion', Discussion
exports.Response              = mongoose.model 'Response', Response
exports.Media                 = mongoose.model 'Media', Media
exports.ClientInvitation      = mongoose.model 'ClientInvitation', ClientInvitation
exports.Tag                   = mongoose.model 'Tag', Tag
exports.EventRequest          = mongoose.model 'EventRequest', EventRequest
exports.Stream                = mongoose.model 'Stream', Stream
exports.Event                 = mongoose.model 'Event', Event
exports.TapIn                 = mongoose.model 'TapIn', TapIn
exports.BusinessRequest       = mongoose.model 'BusinessRequest', BusinessRequest
exports.PasswordResetRequest  = mongoose.model 'PasswordResetRequest', PasswordResetRequest

exports.schemas = {
  Consumer: Consumer
  Client: Client
  Business: Business
  Poll: Poll
  Discussion: Discussion
  Response: Response
  Media: Media
  ClientInvitation: ClientInvitation
  Tag: Tag
  EventRequest: EventRequest
  Stream: Stream
  Event: Event
  TapIn: TapIn
  BusinessRequest: BusinessRequest
  PasswordResetRequest: PasswordResetRequest
}
