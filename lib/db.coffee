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
DocumentArray = mongoose.SchemaTypes.DocumentArray

#validation
Url = /(ftp|http|https):\/\/(\w+:{0,1}\w*@)?(\S+)(:[0-9]+)?(\/|\/([\w#!:.?+=&%@!\-\/]))?/
Email = /^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/


###############
# ENTITY ######
###############
Entity = new Schema {
  type            : {type: String, required: true, enum: choices.entities._enum}
  id              : {type: ObjectId, required: true}
  name            : {type: String}
  screenName      : {type: String} #only applies to consumers
}


##################
# REFERENCE ######
##################
Reference = new Schema {
  type            : {type:String, required: true}
  id              : {type: ObjectId, required: true}
}


####################
# TRANSACTION ######
####################
TransactionSchema =  {
  id              : {type: ObjectId, required: true}
  state           : {type: String, required: true, enum: choices.transactions.states._enum}
  action          : {type: String, required: true, enum: choices.transactions.actions._enum}

  error: {
    message       : {type: String}
  }

  dates: {
    created       : {type: Date, required: true, default: new Date()}
    completed     : {type: Date}
    lastModified  : {type: Date, required: true, default: new Date()}
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
Transaction = new Schema TransactionSchema


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

reference = {
  type            : {type:String, required: true}
  id              : {type: ObjectId, required: true}
}

entity = {
  type              : {type: String, required: true, enum: choices.entities._enum}
  id                : {type: ObjectId, required: true}
  name              : {type: String} #TODO: consider making this required with a default of  ""
  screenName        : {type: String} #only applies to consumers
}

organization = {
  type              : {type: String, required: true, enum: choices.organizations._enum}
  id                : {type: ObjectId, required: true}
  name              : {type: String}
}

transactions = {
  ids               : [ObjectId]
  failed            : [ObjectId]
  log               : [Transaction]
  temp              : [Transaction]
  locked            : {type: Boolean}
  state             : {type: String, enum: choices.transactions.states._enum}
}

media = {
  url               : {type: String, validate: Url} #video or image
  thumb             : {type: String, validate: Url}
  guid              : {type: String}
  mediaId           : {type: ObjectId}
}

ProfileEntry = new Schema {
  name              : {type: String}
  type              : {type: String}
}

###################################################################
###################################################################
###################################################################

#################################
# DATABASE TRANSACTIONS #########
#################################
DBTransaction = new Schema {
  document: {
    type            : {type: String, required: true, enum: choices.objects._enum}
    id              : {type: ObjectId, required: true}
  }

  entity            : entity

  by: {
    type            : {type: String, enum: choices.entities._enum}
    id              : {type: ObjectId}
    name            : {type: String} #TODO: consider making this required with a default of  ""
    screenName      : {type: String} #only applies to consumers
  }

  timestamp        : {type: Date, default: new Date()}
  transaction       : TransactionSchema
}

DBTransaction.index {"document.type": 1, "document.id": 1, "transaction.id": 1}, {unique: true}
DBTransaction.index {"transaction.id": 1, "transaction.state": 1, "transaction.action": 1}
DBTransaction.index {"transaction.state": 1}
DBTransaction.index {"transaction.action": 1}
DBTransaction.index {"entity.type": 1, "entity.id": 1}
DBTransaction.index {"by.type": 1, "by.id": 1}


##################################
# PASSWORD RESET REQUEST #########
##################################
PasswordResetRequest = new Schema {
  date        : {type: Date, default: new Date()}
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
  email           : {type: String, set: utils.toLower, validate: Email, unique: true}
  password        : {type: String, min:5, default: mongoose.Types.ObjectId.createPk(), required:true}
  firstName       : {type: String, required: true}
  lastName        : {type: String, required: true}
  screenName      : {type: String, default: mongoose.Types.ObjectId.createPk(), unique: true}
  setScreenName   : {type: Boolean, default: false}
  created         : {type: Date, default: new Date()}
  logins          : []
  honorScore      : {type: Number, default: 0}
  charities       : {}

  facebook: {
    access_token  : {type: String}
    id            : {type: String}
  }

  profile: {
    birthday      : {type: Date}
    gender        : {}
    education     : [ProfileEntry] #fb
    work          : [ProfileEntry] #fb
    location      : {} #fb
    hometown      : {} #fb
    interests     : [ProfileEntry] #not fb
    aboutme       : {} #not fb
    timezone      : {}
    #interests movies music books?
  }
  permissions: {
    email         : {type: Boolean, default: false}
    birthday      : {type: Boolean, default: false}
    gender        : {type: Boolean, default: false}
    education     : {type: Boolean, default: false} #fb
    work          : {type: Boolean, default: false} #fb
    location      : {type: Boolean, default: false} #fb
    hometown      : {type: Boolean, default: false} #fb
    interests     : {type: Boolean, default: false} #not fb
    fbinterests   : {type: Boolean, default: false} #not fb
    aboutme       : {type: Boolean, default: false} #not fb
    timezone      : {type: Boolean, default: false}
    hiddenFacebookItems : {
      work: [{type:String}]      #hidden work ids
      education: [{type:String}] #hidden education ids
    }
  }

  funds: {
    allocated     : {type: Number, default: 0.0, required: true}
    remaining     : {type: Number, default: 0.0, required: true}
  }

  barcodeId       : {type:String}

  gbAdmin         : {type: Boolean, default: false}
  transactions    : transactions
}


####################
# Client ###########
####################
Client = new Schema {
  firstName     : {type: String, required: true}
  lastName      : {type: String, required: true}
  email         : {type: String, index: true, unique: true, set: utils.toLower, validate: Email}
  password      : {type: String, validate:/.{5,}/, required: true}
  changeEmail   : {}

  media:media

  dates: {
    created     : {type: Date, required: true, default: new Date()}
  }

  funds: {
    allocated   : {type: Number, required: true, default: 0.0}
    remaining   : {type: Number, required: true, default: 0.0}
  }

  transactions  : transactions

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

  media: media

  clients       : [ObjectId] #clientIds
  clientGroups  : {} #{clientId: group}
  groups: {
    #default groups for a business, others can be created
    owners      : [ObjectId] #clientIds
    managers    : [ObjectId] #clientIds
  }

  dates: {
    created     : {type: Date, required: true, default: new Date()}
  }

  funds: {
    allocated   : {type: Number, required: true, default: 0.0}
    remaining   : {type: Number, required: true, default: 0.0}
  }
  gbEquipped    : {type: Boolean, default: false}

  transactions  : transactions

  permissions: { #permissions for groups
  #nothing needs to be done for now, but in the future permissions for groups will be taken care of here.
  #we take care of logic and permissions for owners and manager
  #owners and managers can't change, the permissions can't change either, therefore no need to specify anything for them now
    #default groups for a business
    #owners      : [String]
    #managers    : [String]
  }
}


####################
# Poll #############
####################
Poll = new Schema {
  entity: { #We support various types of users creating discussions (currently businesses and consumers can create discussions)
    type               : {type: String, required: true, enum: choices.entities._enum}
    id                 : {type: ObjectId, required: true}
    name               : {type: String}
  }

  createdBy: { #if it was created by a business or any other organization type, we want to know by which user in that organization otherwise just the consumer
    type               : {type: String, required: true, enum: choices.entities._enum}
    id                 : {type: ObjectId, required: true}
  }

  lastModifiedBy: { #if it was created by a business or any other organization type, we want to know by which user in that organization otherwise just the consumer
    type               : {type: String, required: true, enum: choices.entities._enum}
    id                 : {type: ObjectId, required: true}
  }

  name                 : {type: String, required: true}
  type                 : {type: String, required: true, enum: choices.polls.type._enum}
  question             : {type: String, required: true}
  choices              : [type: String, required: true]
  numChoices           : {type: Number, required: true}
  showStats            : {type: Boolean, required: true} #whether to display the stats to the user or not
  displayName          : {type: Boolean, required: true}
  displayMediaQuestion : {type: Boolean, required: true}
  displayMediaResults  : {type: Boolean, required: true}

  responses: {
    remaining          : {type: Number,   required: true} #decrement each response
    max                : {type: Number,   required: true}
    consumers          : [type: ObjectId, required: true, default: new Array()] #append ObjectId(consumerId) each response
    log                : {} #append consumerId:{answers:[1,2],timestamp:Date}
    dates              : [] #append {consumerId:ObjId,timestamp:Date} -- for sorting by date
    choiceCounts       : [type: Number,   required: true, default: new Array()] #increment each choice chosen, default should be a zero array..
    flagConsumers      : [type: ObjectId, required: true, default: new Array()]
    flagCount          : {type: Number,   required: true, default: 0}
    skipConsumers      : [type: ObjectId, required: true, default: new Array()]
    skipCount          : {type: Number,   required: true, default: 0}
  }

  mediaQuestion: media #if changed please update api calls, transloadit hook, frontend code (uploadify/transloadit)
  mediaResults: media #if changed please update api calls, transloadit hook, frontend code (uploadify/transloadit)

  dates: {
    created            : {type: Date, required: true, default: new Date()}
    start              : {type: Date, required: true}
    end                : {type: Date}
  }

  funds: {
    perResponse        : {type: Number, required: true}
    allocated          : {type: Number, required: true, default: 0.0}
    remaining          : {type: Number, required: true, default: 0.0}
  }

  deleted              : {type: Boolean, default: false}

  transactions: transactions

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

  createdBy: { #if it was created by a business or any other organization type, we want to know by which user in that organization otherwise just the consumer
    type              : {type: String, required: true, enum: choices.entities._enum}
    id                : {type: ObjectId, required: true}
  }

  lastModifiedBy: { #if it was created by a business or any other organization type, we want to know by which user in that organization otherwise just the consumer
    type              : {type: String, required: true, enum: choices.entities._enum}
    id                : {type: ObjectId, required: true}
  }

  name                : {type: String, required: true}
  question            : {type: String, required: true}
  details             : {type: String}
  tags                : [String]
  displayName         : {type: Boolean, required: true}
  displayMedia        : {type: Boolean, required: true}
  responses: {
    count             : {type: Number, required: true, default: 0}
    consumers         : [type: ObjectId, required: true, default: new Array()] #append ObjectId(consumerId) each response
    log               : {}                             #append consumerId:{answers:[1,2],timestamp:Date}
    dates             : []                             #append {consumerId:ObjId,timestamp:Date} -- for sorting by date
    flagConsumers     : [type: ObjectId, required: true, default: new Array()]
    flagCount         : {type: Number,   required: true, default: 0}
  }
  media: media
  dates: {
    created           : {type: Date, required: true, default: new Date()}
    start             : {type: Date, required: true, default: new Date()}
    end               : {type: Date}

    #end           : {type: Date, required: true, default: new Date( (new Date().addWeeks(3)).toUTCString() )} #three week later
  }

  funds: {
    allocated         : {type: Number, required: true, default: 0.0}
    remaining         : {type: Number, required: true, default: 0.0}
  }

  deleted             : {type: Boolean, default: false}

  transactions        : transactions

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
    created       : {type: Date, default: new Date()}
  }

  deleted         : {type: Boolean, default: false}

  transactions    : transactions
}


####################
# Media ############
####################
Media = new Schema {
  entity: { #We support different types of users creating and uploading content
    type        : {type: String, required: true, enum: choices.entities._enum}
    id          : {type: ObjectId, required: true}
    name        : {type: String}
  }

  type          : {type: String, required: true, enum: choices.media.type._enum}
  name          : {type: String, required: true}
  duration      : {type: Number}
  thumbs        : [] #only populated if video
  sizes         : {} #this should match transloadits sizes
  tags          : []

  dates: {
    created     : {type: Date, required: true, default: new Date()}
  }

  transactions  : transactions

  deleted       : {type: Boolean, default: false}
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
    created       : {type: Date, default: new Date()}
    expires       : {type: Date}
  }

  transactions    : transactions
}

#unique index on businessId + group + email address is required
ClientInvitation.index {businessId: 1, groupName: 1, email: 1}, {unique: true}


####################
# Stream ###########
####################
Stream = new Schema {
  who                 : entity
  by: { # if who is an organization, then which user in that organization
    type              : {type: String, enum: choices.entities._enum}
    id                : {type: ObjectId}
    name              : {type:String}
  }
  entitiesInvolved    : [Entity]
  what                : reference #the document this stream object is about
  when                : {type: Date, required: true, default: new Date()}
  where: {
    org: {
      type            : {type: String, enum: choices.entities._enum}
      id              : {type: ObjectId}
      name            : {type: String}
    }
    locationId        : {type: ObjectId}
    locationName      : {type: String}
  }
  events              : [{type:String, required: true, enum: choices.eventTypes}]
  feeds: {
    global            : {type: Boolean, required: true, default: false}
  }
  dates: {
    created           : {type: Date, default: new Date()}
    lastModified      : {type: Date}
  }
  data                : {}#eventTypes to info mapping:=> eventType: {id: XX, extraFF: GG}
  deleted             : {type: Boolean, default: false}

  transactions        : transactions
}

#indexes
Stream.index {"feeds.global": 1, "who.type": 1, "who.id": 1, events: 1}
Stream.index {"who.type": 1, "who.id": 1, events: 1}
Stream.index {"who.type": 1, "who.id": 1, "by.type": 1, "by.id": 1, events: 1}
Stream.index {"what.type": 1, "what.id": 1}
Stream.index {when: 1}
Stream.index {events: 1}
Stream.index {"entitiesInvolved.type": 1, "entitiesInvolved.id": 1, "who.type": 1, "who.id": 1}
Stream.index {"entitiesInvolved.type": 1, "entitiesInvolved.id": 1, "who.type": 1, "who.screenName": 1}
Stream.index {"where.org.type": 1, "where.org.id": 1}


####################
# TAG ##############
####################
Tag = new Schema {
  name: {type: String, required: true}
  #category: {type: String, required: true}

  transactions: transactions
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
    type        : {type: String, required: true, enum: choices.entities._enum}
    id          : {type: ObjectId, required: true}
    name        : {type: String}
  }

  locationId    : {type: ObjectId}
  location      : {
    name        : {type: String}
    street1     : {type: String, required: true}
    street2     : {type: String}
    city        : {type: String, required: true}
    state       : {type: String, required: true}
    zip         : {type: Number, required: true}
    country     : {type: String, enum: countries.codes, required: true, default: "us"}
    phone       : {type: String}
    fax         : {type: String}
    lat         : {type: Number}
    lng         : {type: Number}
  }

  dates: {
    requested   : {type: Date, required: true}
    responded   : {type: Date, required: true}
    actual      : {type: Date, required: true}
  }

  hours         : [EventDateRange]
  pledge        : {type: Number, min: 0, max: 100, required: true}
  externalUrl   : {type: String, validate: Url}
  rsvp          : [ObjectId]
  rsvpUsers     : {}

  transactions  : transactions
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

  transactions          : transactions
}


#########################
# BusinessTransaction ###
#########################
BusinessTransaction = new Schema {
  userEntity: { # Not required since they may not be registered
    type                : {type: String, enum: choices.entities._enum}
    id                  : {type: ObjectId}
    name                : {type: String}
    screenName          : {type: String}
  }

  organizationEntity    : organization

  locationId            : {type: ObjectId, required: true}
  registerId            : {type: String, required: true}
  barcodeId             : {type: String}
  transactionId         : {type: String} #if their data has a transaction number we put it here
  date                  : {type: Date, required: true}
  time                  : {type: Date, required: true}
  amount                : {type: Number, required: true}
  donationAmount        : {type: Number}

  transactions          : transactions
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


##########
# Stat ###
##########
# Businesses typically want to keep totals, counts, etc of the following
# tapIns, totalSpent, eventsAttended, pollsAnswered, DiscussionComments, lastVisited, lastInteraction

#CURRENTLY BEING TRACKED: (ALWAYS UPDATE THIS LIST PLEASE AND THE INDEXES)
#tapIns:
  #totalTapIns
  #totalAmountPurchased
  #lastVisited
#polls:
  #totalAnswered
  #lastAnsweredDate
Statistic = new Schema {
  org                     : organization
  consumerId              : {type: ObjectId, required: true}
  data                    : {} #store counts, totals, dates, etc

  transactions            : transactions
}

Statistic.index {'org.type': 1, 'org.id':1, consumerId: 1}, {unique: true}

Statistic.index {'org.type': 1, 'org.id':1, consumerId: 1, "tapIns.totalTapIns": 1}
Statistic.index {'org.type': 1, 'org.id':1, consumerId: 1, "tapIns.totalAmountPurchased": 1}
Statistic.index {'org.type': 1, 'org.id':1, consumerId: 1, "tapIns.lastVisited": 1}

Statistic.index {'org.type': 1, 'org.id':1, consumerId: 1, "polls.totalAnswered": 1}
Statistic.index {'org.type': 1, 'org.id':1, consumerId: 1, "polls.lastAnsweredDate": 1}

exports.DBTransaction         = mongoose.model 'DBTransaction', DBTransaction
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
exports.BusinessTransaction   = mongoose.model 'BusinessTransaction', BusinessTransaction
exports.BusinessRequest       = mongoose.model 'BusinessRequest', BusinessRequest
exports.PasswordResetRequest  = mongoose.model 'PasswordResetRequest', PasswordResetRequest
exports.Statistic             = mongoose.model 'Statistic', Statistic

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
  BusinessTransaction: BusinessTransaction
  BusinessRequest: BusinessRequest
  PasswordResetRequest: PasswordResetRequest
  Statistic: Statistic
}
