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


###################################################################
###################################################################
###################################################################

#####################
# Reference #########
#####################
reference = {
  type            : {type:String, required: true}
  id              : {type: ObjectId, required: true}
}


##################
# Entity #########
##################
entity = {
  type              : {type: String, required: true, enum: choices.entities._enum}
  id                : {type: ObjectId, required: true}
  name              : {type: String} #TODO: consider making this required with a default of  ""
  screenName        : {type: String} #only applies to consumers
  by: { #only if on behalf of another entity (if the entity is a business - this is the client in that business)
    type: {type: String, enum: choices.entities._enum}
    id: {type: ObjectId}
    name: {type: String}
  }
}


##############
# DONOR ######
##############
donor = {
  entity          : entity
  funds: {
    remaining     : {type: Number, required: true, default: 0.0}
    allocated     : {type: Number, required: true, default: 0.0}
  }
}


########################
# Organization #########
########################
organization = {
  type              : {type: String, required: true, enum: choices.organizations._enum}
  id                : {type: ObjectId, required: true}
  name              : {type: String}
}


####################
# Location #########
####################
location = {
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


#######################
# transaction #########
#######################
transaction = {
  id              : {type: ObjectId, required: true}
  state           : {type: String, required: true, enum: choices.transactions.states._enum}
  action          : {type: String, required: true, enum: choices.transactions.actions._enum}

  error: {
    message       : {type: String}
  }

  dates: {
    created       : {type: Date, required: true, default: Date.now}
    completed     : {type: Date}
    lastModified  : {type: Date, required: true, default: Date.now}
  }

  #EXTRA INFO GOES IN HERE
  data: {}

  #INBOUND = DEPOST, OUTBOUND = WIDTHDRAWL
  direction       : {type: String, required: true, enum: choices.transactions.directions._enum}

  #DEPOSIT OR DEDUCT TO/FROM WHOM? (Sometimes we may use the entity object in the document itself)
  entity: {
    type          : {type: String, enum: choices.entities._enum}
    id            : {type: ObjectId}
    name          : {type: String}
    screenName    : {type: String}
  }

  attempts        : {type: Number, default: 0}
  pollerId        : {type: ObjectId} #THIS IS FOR IF WE FAIL AND THE POLLER PICKS IT UP
}


########################
# transactions #########
########################
transactions = {
  ids               : [ObjectId]
  failed            : [ObjectId]
  log               : [Transaction]
  temp              : [Transaction]
  locked            : {type: Boolean}
  state             : {type: String, enum: choices.transactions.states._enum}
}


#################
# Media #########
#################
media = {
  url               : {type: String, validate: Url} #video or image
  thumb             : {type: String, validate: Url}
  guid              : {type: String}
  mediaId           : {type: ObjectId}
  rotateDegrees     : {type: Number} #tempURLs from transloadit have wacky rotations...
}


####################
# registerData #####
####################
registerData = {
  registerId: {type: ObjectId, required: true}
  setupId: {type: Number, required: true}
}


ProfileEntry = new Schema {
  name              : {type: String}
  type              : {type: String}
}

###################################################################
###################################################################
###################################################################

Reference = new Schema reference
Entity = new Schema entity
Location = new Schema location
Donor = new Schema donor
Transaction = new Schema transaction
RegisterData = new Schema registerData


#################################
# DATABASE TRANSACTIONS #########
#################################
DBTransaction = new Schema {
  document: {
    type            : {type: String, required: true}
    id              : {type: ObjectId, required: true}
  }
  timestamp         : {type: Date, default: Date.now}
  transaction       : transaction
}

DBTransaction.index {"document.type": 1, "document.id": 1, "transaction.id": 1}, {unique: true}
DBTransaction.index {"transaction.id": 1, "transaction.state": 1, "transaction.action": 1}
DBTransaction.index {"transaction.state": 1}
DBTransaction.index {"transaction.action": 1}
DBTransaction.index {"entity.type": 1, "entity.id": 1}
DBTransaction.index {"by.type": 1, "by.id": 1}


##################################
# SEQUENCE #######################
##################################
Sequence = new Schema {
  urlShortner: {type: Number, default: 0}
  barcodeId: {type: Number, default: 0}
}


####################
# BARCODE ##########
####################
Barcode = new Schema {
  barcodeId: {type: String, required: true}
}

Barcode.index {"barcodeId": 1}, {unique: true}


##################################
# PASSWORD RESET REQUEST #########
##################################
PasswordResetRequest = new Schema {
  date        : {type: Date, default: Date.now}
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
  password        : {type: String, min:5, required: true}
  firstName       : {type: String}
  lastName        : {type: String}
  privateId       : {type: ObjectId}
  screenName      : {type: String, min:5}
  aliasId         : {type: ObjectId}
  setScreenName   : {type: Boolean, default: false}
  created         : {type: Date, default: Date.now}
  logins          : []
  loginCount      : {type: Number, default: 1}
  honorScore      : {type: Number, default: 0}
  charities       : {}
  media           : media
  secureMedia     : media
  tapinsToFacebook: {type: Boolean, default: false}
  changeEmail     : {}

  # same as organization, but making fields not required because an account can be pre-created without charity
  charity: {
    type          : {type: String, enum: [choices.organizations.CHARITY]}
    id            : {type: ObjectId}
    name          : {type: String}
  }

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
    affiliations  : [ObjectId]
    #interests movies music books?
  }

  permissions: {
    email         : {type: Boolean, default: false}
    media         : {type: Boolean, default: true}
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
    affiliations  : {type: Boolean, default: false}
    hiddenFacebookItems : {
      work: [{type:String}]      #hidden work ids
      education: [{type:String}] #hidden education ids
    }
  }

  funds: {
    allocated     : {type: Number, default: 0.0, required: true}
    remaining     : {type: Number, default: 0.0, required: true}
    donated       : {type: Number, default: 0.0, required: true}
  }

  donations: {
    log : {}
      #{entityId} : {
      #  amount: {type:Number}
      #  count : {type:Number}
      #}
    charities   : [ObjectId]
  }


  referralCodes: {
    tapIn         : {type: String}
    user          : {type: String}
  }

  barcodeId       : {type: String}

  gbAdmin         : {type: Boolean, default: false}

  updateVerification : {
    key        : {type: String}
    expiration : {type: Date}
    data       : {}
  }

  signUpVerification: {
    key: {type: String}
    expiration: {type: Date}
  }

  transactions    : transactions
}

Consumer.index {screenName: 1}, {unique: true, sparse: true} #sparse because we allow for null/non-existant values
Consumer.index {barcodeId: 1}, {unique: true, sparse: true} #sparse because we allow for null/non-existant values
Consumer.index {email: 1}
Consumer.index {"facebook.id": 1, email: 1}
Consumer.index {"signUpVerification.key": 1}
Consumer.index {"updateVerification.key": 1}
Consumer.index {"updateVerification.data.barcodeId": 1, "updateVerification.expiration": 1} # manage barcodeId uniqueness in code not db for this one
Consumer.index {_id: 1, "transactions.ids": 1}
Consumer.index {"transactions.ids": 1}


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
    created     : {type: Date, required: true, default: Date.now}
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
  type          : [{ type: String, required: true }]
  tags          : [{ type: String, required: true }]
  url           : {type: String, validate: Url}
  email         : {type: String, validate: Email}
  isCharity     : {type: Boolean, default: false}
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

  registers     : {} # {registerId: {location: locationId, setupId: Sequence No. ...}} # Sequence No. is from Sequences collection
  locRegister   : {} # {locationId: [registerId]}
  registerData  : [RegisterData]

  locations     : [Location]

  media: media

  clients       : [ObjectId] #clientIds
  clientGroups  : {} # {clientId: group}
  groups: {
    #default groups for a business, others can be created
    owners      : [ObjectId] #clientIds
    managers    : [ObjectId] #clientIds
  }

  dates: {
    created: {type: Date, required: true, default: Date.now}
  }

  funds: {
    allocated         : {type: Number, required: true, default: 0.0}
    remaining         : {type: Number, required: true, default: 0.0}
    donationsRecieved : {type: Number} #for charities only.
  }

  gbEquipped    : {type: Boolean, default: false}
  deleted       : {type: Boolean, default: false}

  pin           : {type: String, validate: /[0-9]/}
  cardCode      : {type: String} #This will replace pin entirely

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

Business.index {name: 1}
Business.index {publicName: 1}
Business.index {isCharity: 1}
Business.index {deleted: 1}


####################
# Organization #####
####################
Organization = new Schema {
  type    : {type: String, required: true}
  subType : {type: String, required: true}
  name    : {type: String, required: true}
}

Organization.index {type: 1, name: 1}, {unique: true}
Organization.index {type: 1, subType: 1, name: 1}


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
  numChoices           : {type: Number, min:2, required: true}
  showStats            : {type: Boolean, required: true} #whether to display the stats to the user or not
  displayName          : {type: Boolean, required: true}

  responses: {
    remaining          : {type: Number,   required: true} #decrement each response
    max                : {type: Number,   min:1, required: true}
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
    created            : {type: Date, required: true, default: Date.now}
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

  media               : media
  thanker             : [Entity] #entities who have thanked a response (not using donated funds)
  donors              : [Entity] #entities who have put money into this discussion (including creator)
  # remove name, screenName, by from the donors list - because we want to use addToSet here
  # donorNames          : {} #{entityTYPE_ObjectIdAsStr: NAME}
  # donorBy             : {} #{entityTYPE_ObjectIdAsStr: [Name]} #if done on behalf of a business
  donationAmounts     : {} #{entityTYPE_ObjectIdAsStr: {allocated: AMOUNT, remaining: AMOUNT}} #amount donated by that entity #we are storing it here instead of in donors, incase the same entity donates multiple times

  dates: {
    created           : {type: Date, required: true, default: Date.now}
    start             : {type: Date, required: true, default: Date.now}
    end               : {type: Date}
  }

  funds: {
    allocated         : {type: Number, required: true, default: 0.0}
    remaining         : {type: Number, required: true, default: 0.0}

    #these are just total sums
    donations         : {type: Number, required: true, default: 0.0}
    thanks            : {type: Number, required: true, default: 0.0}
  }

  donationCount       : {type: Number, required: true, default: 0}
  thankCount          : {type: Number, required: true, default: 0}

  votes: { #these are all totals
    count           : {type: Number, default: 0}
    score           : {type: Number, default: 0}
    up              : {type: Number, default: 0}
    down            : {type: Number, default: 0}
  }

  flagged: {
    by                : [Entity]
    count             : {type: Number, default: 0}
  }

  responseCount       : {type: Number, required: true, default: 0}

  responses           : [Response]
  responseEntities    : {} #{responseId: entity} #this is used for determining who to donate money to later, so we don't iterate responses array

  deleted             : {type: Boolean, default: false}
  transactions        : transactions
}


####################
# Response #########
####################
Response = new Schema {
  entity            : entity
  content           : {type: String}

  dates: {
    created         : {type: Date, required: true, default: Date.now}
    lastModified    : {type: Date, required: true, default: Date.now}
  }

  comments          : [Comment]
  commentCount      : {type: Number, required: true, default: 0}

  votes: {
    count           : {type: Number, default: 0}
    score           : {type: Number, default: 0}

    up: {
      by            : [Entity]
      ids           : {} # {TYPE_ObjectIdAsStr: 1} for each user that votes up
      count         : {type: Number, default: 0}
    }

    down: {
      by            : [Entity]
      ids           : {} # {TYPE_ObjectIdAsStr: 1} for each user that votes down
      count         : {type: Number, default: 0}
    }
  }

  flagged: {
    by              : [Entity]
    count           : {type: Number, default: 0}
  }

  earned            : {type: Number, default: 0.0}

  thanks: {
    count           : {type: Number, default: 0}
    amount          : {type: Number, default: 0.0} #total

    by: [{
      entity        : entity
      amount        : {type: Number}
    }]
  }

  donations: {
    count           : {type: Number, default: 0}
    amount          : {type: Number, default: 0.0} #total

    by: [{
      entity        : entity
      amount        : {type: Number}
    }]
  }
}


####################
# Comment ##########
####################
Comment = new Schema {
  entity            : entity
  content           : {type: String}

  dates: {
    created         : {type: Date, required: true, default: Date.now}
    lastModified    : {type: Date, required: true, default: Date.now}
  }

  flagged: {
    by              : [Entity]
    count           : {type: Number, default: 0}
  }
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
    created     : {type: Date, required: true, default: Date.now}
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
Media.index {"guid": 1}


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
    created       : {type: Date, default: Date.now}
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
    name              : {type: String}
  }
  entitiesInvolved    : [Entity]
  what                : reference #the document this stream object is about
  when                : {type: Date, required: true, default: Date.now}
  where: {
    org: {
      type            : {type: String, enum: choices.entities._enum}
      id              : {type: ObjectId}
      name            : {type: String}
    }
    locationId        : {type: ObjectId}
    locationName      : {type: String} #generally we don't have this information #probably remove this
  }
  events              : [{type:String, required: true, enum: choices.eventTypes._enum}]
  feeds: {
    global            : {type: Boolean, required: true, default: false}
  }
  dates: {
    created           : {type: Date, default: Date.now}
    lastModified      : {type: Date}
  }
  data                : {}#available to all enabled feeds #eventTypes to info mapping:=> eventType: {id: XX, extraFF: GG} #essentially if this was in feedSpecificData it would be the feed: global

  feedSpecificData: { #available only for the specified feeds #feed to eventType to info mapping: {involved: {eventType: {id: XX, extraFF: GG} } }
    #data              : {} #this is the data object above
    involved          : {} #data this is visible to all the entities involved only
  }

  entitySpecificData  : {} #avialable only to the entities specified. {#ENTITY_TYPE}_{}

  deleted             : {type: Boolean, default: false}

  transactions        : transactions
}

#indexes
Stream.index {"feeds.global": 1, "dates.lastModified": -1}
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
  name  : {type: String, required: true}
  type  : {type: String, required: true, enum: choices.tags.types._enum}
  count : {type: Number}
  transactions: transactions
}

Tag.index {type: 1, name:1}, {unique: true}


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
  location      : location

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
  details       : {type: String}

  transactions  : transactions
  media         : media
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
  charity               : organization

  locationId            : {type: ObjectId, required: true}
  registerId            : {type: String, required: true}
  barcodeId             : {type: String}
  transactionId         : {type: String} #if their data has a transaction number we put it here
  date                  : {type: Date, required: true}
  time                  : {type: Date, required: true}
  amount                : {type: Number, required: false}
  receipt               : {type: Buffer, required: false} #binary receipt data
  hasReceipt            : {type: Boolean, required: true, default:false} #because we want to check if there is a receipt without pulling receipt (might be big)

  karmaPoints           : {type: String, required: true}
  donationType          : {type: String, required: true, enum: choices.donationTypes._enum} #percentage or dollar amount
  donationValue         : {type: Number, required: true} #what is the percentage or what is the dollar amount
  donationAmount        : {type: Number, required: true, default: 0} #the amount donated
  postToFacebook        : {type: Boolean, required: true, default: false} #do we post this transaction to facebook

  transactions          : transactions
}

BusinessTransaction.index {barcodeId: 1, "organizationEntity.id": 1, "date": -1}
BusinessTransaction.index {"transactions.ids": 1}


#######################
# Business Requests ###
#######################
BusinessRequest = new Schema {
  userEntity: {
    type                : {type: String, required: false, enum: choices.entities._enum}
    id                  : {type: ObjectId, required: false}
    name                : {type: String}
  }
  loggedin              : {type: Boolean, required: true, default: true}
  businessName          : {type: String, require: true}
  date: {
    requested           : {type: Date, default: Date.now}
    read                : {type: Date}
  }
}


##############
# REFERRAL ###
##############
Referral = new Schema {
  type                  : {type: String, enum: choices.referrals.types._enum, required: true}

  entity: {
    type                : {type: String, required: true, enum: choices.entities._enum}
    id                  : {type: ObjectId, required: true}
  }
  by: {
    type                : {type: String, required: true, enum: choices.entities._enum}
    id                  : {type: ObjectId, required: true}
  }

  incentives: {
    referrer            : {type:Number, required: true, default: 0.0}
    referred            : {type:Number, required: true, default: 0.0}
  }

  #if type is choices.referrals.types.STICKER then we have this sub document
  stickers: {
    range: {
      start             : {type: Number}
      stop              : {type: Number}
    }
    eventId             : {type: ObjectId}
  }

  #if type is choices.referrals.types.LINK then we have this sub document
  link: {
    code                : {type: String}
    url                 : {type: String, validate: Url}
    type                : {type: String, enum: choices.referrals.links.types._enum}
    visits              : {type: Number}
  }
  signups               : {type: Number, required: true, default:0}
  referredUsers         : [Entity]
}

#Indexes
Referral.index {type: 1, 'entity.type': 1, 'entity.id': 1, 'link.url': 1}

Referral.index {type: 1, 'stickers.range.start': 1, 'stickers.range.stop': 1}
Referral.index {type: 1, 'stickers.eventId': 1}

Referral.index {type: 1, 'entity.type': 1, 'entity.id':1, 'stickers.eventId': 1}
Referral.index {type: 1, 'link.code': 1}
Referral.index {type: 1, 'link.url': 1}


##################
# GOODY ##########
##################
Goody = new Schema {
  org                   : organization
  name                  : {type:String, required:true}
  description           : {type:String}
  active                : {type:Boolean, default: false, required:true}
  karmaPointsRequired   : {type:Number, required:true}
}

Goody.index {"org.type": 1, "org.id": 1, "karmaPointsRequired" : 1}


###########################
# REDEMPTION LOG ##########
###########################
RedemptionLog = new Schema {
  consumer              : entity
  org                   : organization

  locationId            : {type: ObjectId, required: true}
  registerId            : {type: ObjectId, required: true}

  goody: {
    id                  : {type: ObjectId, required: true}
    name                : {type: String, required: true}
    karmaPointsRequired : {type: Number, required: true}
  }

  dates: {
    created             : {type: Date, default: Date.now, required: true}
    redeemed            : {type: Date, default: Date.now, required: true}
  }

  transactions          : transactions
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
  #firstVisit
  #lastVisited
  #totalDonated
  #charityCentsRaised [REMOVE]
  #charityCentsRemaining [REMOVE]
  #charityCentsRedeemed [REMOVE]

#karmaPoints
  #earned
  #remaining
  #used

#goodies
  #totalRedeemed: count
  #granular:
    #goodyId: count

#polls:
  #totalAnswered
  #lastAnsweredDate
Statistic = new Schema {
  org                     : organization #note, we don't care about the organization's name here
  consumerId              : {type: ObjectId, required: true}
  data                    : {} #store counts, totals, dates, etc

  transactions            : transactions
}

Statistic.index {'org.type': 1, 'org.id':1, consumerId: 1}, {unique: true}

Statistic.index {consumerId: 1, "org.id": 1}
Statistic.index {consumerId: 1, "org.type": 1, "org.id": 1}

Statistic.index {'org.type': 1, 'org.id':1, consumerId: 1, "transactions.ids": 1}

#THESE ACTUALLY NEEDED DATA INFRONT OF THE LAST COLUM - SO FIX THIS WHEN DOING GOODIES
#we want to stop storing in data eventually - just keep it at the top level

# Statistic.index {'org.type': 1, 'org.id':1, consumerId: 1, "tapIns.totalTapIns": 1} #REMOVE
# Statistic.index {'org.type': 1, 'org.id':1, consumerId: 1, "tapIns.totalAmountPurchased": 1} #REMOVE
# Statistic.index {'org.type': 1, 'org.id':1, consumerId: 1, "tapIns.lastVisited": 1} #REMOVE
# Statistic.index {'org.type': 1, 'org.id':1, consumerId: 1, "tapIns.charityCentsRedeemed": 1} #REMOVE
# Statistic.index {'org.type': 1, 'org.id':1, consumerId: 1, "tapIns.charityCentsRemaining": 1} #REMOVE
# Statistic.index {'org.type': 1, 'org.id':1, consumerId: 1, "tapIns.charityCentsRaised": 1} #REMOVE

# Statistic.index {'org.type': 1, 'org.id':1, consumerId: 1, "polls.totalAnswered": 1} #REMOVE
# Statistic.index {'org.type': 1, 'org.id':1, consumerId: 1, "polls.lastAnsweredDate": 1} #REMOVE

Statistic.index {'org.type': 1, 'org.id': 1, consumerId: 1, "data.tapIns.totalTapIns": 1}
Statistic.index {'org.type': 1, 'org.id': 1, consumerId: 1, "data.tapIns.totalAmountPurchased": 1}
Statistic.index {'org.type': 1, 'org.id': 1, consumerId: 1, "data.tapIns.lastVisited": 1}
Statistic.index {'org.type': 1, 'org.id': 1, consumerId: 1, "data.tapIns.firstVisited": 1}
Statistic.index {'org.type': 1, 'org.id': 1, consumerId: 1, "data.tapIns.totalDonated": 1}

Statistic.index {'org.type': 1, 'org.id': 1, consumerId: 1, "data.polls.totalAnswered": 1}
Statistic.index {'org.type': 1, 'org.id': 1, consumerId: 1, "data.polls.lastAnsweredDate": 1}

Statistic.index {'org.type': 1, 'org.id': 1, consumerId: 1, "data.karmaPoints.earned": 1}
Statistic.index {'org.type': 1, 'org.id': 1, consumerId: 1, "data.karmaPoints.remaining": 1}
Statistic.index {'org.type': 1, 'org.id': 1, consumerId: 1, "data.karmaPoints.used": 1}


#CURRENTLY BEING TRACKED: (ALWAYS UPDATE THIS LIST PLEASE AND THE INDEXES)
#tapIns:
  #totalTapIns
  #totalAmountPurchased
  #firstVisited
  #lastVisited
  #totalDonated

#karmaPoints
  #earned
  #remaining
  #used

UnclaimedBarcodeStatistic = new Schema {
  org                     : organization
  barcodeId               : {type: String, required: true}
  data                    : {}

  claimId                 : {type: ObjectId}
}

UnclaimedBarcodeStatistic.index {'org.type': 1, 'org.id':1, barcodeId: 1}, {unique: true}
UnclaimedBarcodeStatistic.index {claimId: 1, barcodeId: 1} #used when claiming a barcode
UnclaimedBarcodeStatistic.index {'org.type': 1, 'org.id':1, barcodeId: 1, "transactions.ids": 1}
UnclaimedBarcodeStatistic.index {"transactions.ids": 1}

# UnclaimedBarcodeStatistic.index {'org.type': 1, 'org.id':1, barcodeId: 1, "tapIns.totalTapIns": 1} #REMOVE
# UnclaimedBarcodeStatistic.index {'org.type': 1, 'org.id':1, barcodeId: 1, "tapIns.totalAmountPurchased": 1} #REMOVE
# UnclaimedBarcodeStatistic.index {'org.type': 1, 'org.id':1, barcodeId: 1, "tapIns.lastVisited": 1} #REMOVE
# UnclaimedBarcodeStatistic.index {'org.type': 1, 'org.id':1, barcodeId: 1, "tapIns.chariryCents": 1} #REMOVE

UnclaimedBarcodeStatistic.index {'org.type': 1, 'org.id':1, barcodeId: 1, "data.tapIns.totalTapIns": 1}
UnclaimedBarcodeStatistic.index {'org.type': 1, 'org.id':1, barcodeId: 1, "data.tapIns.totalAmountPurchased": 1}
UnclaimedBarcodeStatistic.index {'org.type': 1, 'org.id':1, barcodeId: 1, "data.tapIns.lastVisited": 1}
UnclaimedBarcodeStatistic.index {'org.type': 1, 'org.id':1, barcodeId: 1, "data.tapIns.firstVisited": 1}
UnclaimedBarcodeStatistic.index {'org.type': 1, 'org.id':1, barcodeId: 1, "data.tapIns.totalDonated": 1}

UnclaimedBarcodeStatistic.index {'org.type': 1, 'org.id':1, consumerId: 1, "data.karmaPoints.earned": 1}
UnclaimedBarcodeStatistic.index {'org.type': 1, 'org.id':1, consumerId: 1, "data.karmaPoints.remaining": 1}
UnclaimedBarcodeStatistic.index {'org.type': 1, 'org.id':1, consumerId: 1, "data.karmaPoints.used": 1}


##########################
# Card Requests ##########
##########################
CardRequest = new Schema {
  entity: {
    type                : {type: String, required: true, enum: choices.entities._enum}
    id                  : {type: ObjectId, required: true}
  }
  dates: {
    requested           : {type: Date, required: true}
    responded           : {type: Date}
  }
}


#############################
# Email Submission ##########
#############################
EmailSubmission = new Schema {
  entity: {
    type                : {type: String, required: true, enum: choices.entities._enum}
  }
  barcodeId             : {type: String}
  businessId            : {type: ObjectId, required: true}
  registerId            : {type: ObjectId, required: true}
  locationId            : {type: ObjectId, required: true}
  email                 : {type: String, validate: Email, required: true}
  date                  : {type: Date, required: true }
}


exports.DBTransaction             = mongoose.model 'DBTransaction', DBTransaction
exports.Sequence                  = mongoose.model 'Sequence', Sequence
exports.Consumer                  = mongoose.model 'Consumer', Consumer
exports.Client                    = mongoose.model 'Client', Client
exports.Business                  = mongoose.model 'Business', Business
exports.Poll                      = mongoose.model 'Poll', Poll
exports.Goody                     = mongoose.model 'Goody', Goody
exports.Discussion                = mongoose.model 'Discussion', Discussion
exports.Response                  = mongoose.model 'Response', Response
exports.Media                     = mongoose.model 'Media', Media
exports.ClientInvitation          = mongoose.model 'ClientInvitation', ClientInvitation
exports.Tag                       = mongoose.model 'Tag', Tag
exports.EventRequest              = mongoose.model 'EventRequest', EventRequest
exports.Stream                    = mongoose.model 'Stream', Stream
exports.Event                     = mongoose.model 'Event', Event
exports.BusinessTransaction       = mongoose.model 'BusinessTransaction', BusinessTransaction
exports.BusinessRequest           = mongoose.model 'BusinessRequest', BusinessRequest
exports.PasswordResetRequest      = mongoose.model 'PasswordResetRequest', PasswordResetRequest
exports.Statistic                 = mongoose.model 'Statistic', Statistic
exports.UnclaimedBarcodeStatistic = mongoose.model 'UnclaimedBarcodeStatistic', UnclaimedBarcodeStatistic
exports.Organization              = mongoose.model 'Organization', Organization
exports.Referral                  = mongoose.model 'Referral', Referral
exports.Barcode                   = mongoose.model 'Barcode', Barcode
exports.CardRequest               = mongoose.model 'CardRequest', CardRequest
exports.EmailSubmission           = mongoose.model 'EmailSubmission', EmailSubmission
exports.RedemptionLog             = mongoose.model 'RedemptionLog', RedemptionLog

exports.schemas = {
  Sequence                  : Sequence
  Consumer                  : Consumer
  Client                    : Client
  Business                  : Business
  Poll                      : Poll
  Goody                     : Goody
  Discussion                : Discussion
  Response                  : Response
  Media                     : Media
  ClientInvitation          : ClientInvitation
  Tag                       : Tag
  EventRequest              : EventRequest
  Stream                    : Stream
  Event                     : Event
  BusinessTransaction       : BusinessTransaction
  BusinessRequest           : BusinessRequest
  PasswordResetRequest      : PasswordResetRequest
  Statistic                 : Statistic
  UnclaimedBarcodeStatistic : UnclaimedBarcodeStatistic
  Organization              : Organization
  Referral                  : Referral
  Barcode                   : Barcode
  CardRequest               : CardRequest
  EmailSubmission           : EmailSubmission
  RedemptionLog             : RedemptionLog
}
