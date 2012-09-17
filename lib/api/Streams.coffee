require("./helpers").install(global)
Api = require("./Api")
tp = require "../transactions" #transaction processor

exports = module.exports = class Streams extends Api
  @model: Stream

  @add: (stream, callback)->
    model = {
      who                : stream.who
      by                 : stream.by
      entitiesInvolved   : stream.entitiesInvolved
      what               : stream.what
      when               : stream.when || new Date()
      where              : stream.where
      events             : stream.events
      private            : stream.private || false #default to public
      data               : stream.data || {}
      feeds              : stream.feeds
      feedSpecificData   : stream.feedSpecificData
      entitySpecificData : stream.entitySpecificData
      dates: {
        created           : new Date()
        lastModified      : new Date()
      }
    }

    instance = new @model(model)
    instance.save callback

  @fundsDonated: (who, charity, donationLogDoc, callback)->
    if Object.isString who.id
      who.id = new ObjectId who.id
    if Object.isString charity.id
      charity.id = new ObjectId charity.id

    donation = {id: donationLogDoc._id, type:choices.objects.DONATION_LOG}

    stream = {
      who               : who
      entitiesInvolved  : [who, charity]
      what              : donation
      when              : donationLogDoc.dates.donated
      #where:
      events            : [choices.eventTypes.FUNDS_DONATED]
      data              : {}
      feeds: {
        global          : true
      }
      private: false #THIS NEEDS TO BE UPDATED BASED ON PRIVACY SETTINGS OF WHO (if consumer)
    }

    stream.data = {
      amount : donationLogDoc.amount
    }
    stream.feedSpecificData = {}
    stream.feedSpecificData.involved = { #available only to entities involved
      charity : charity
    }

    logger.silly stream.data

    @add stream, (error,data)->
      if error?
        logger.error error
      logger.debug data
      if callback?
        callback error,data
      return
    return

  @pollCreated: (pollDoc, callback)->
    if Object.isString(pollDoc._id)
      pollDoc._id = new ObjectId(pollDoc._id)

    if Object.isString(pollDoc.entity.id)
      pollDoc.entity.id = new ObjectId(pollDoc.entity.id)

    if Object.isString(pollDoc.createdBy.id)
      pollDoc.createdBy.id = new ObjectId(pollDoc.createdBy.id)

    who = pollDoc.entity
    poll = {type: choices.objects.POLL, id: pollDoc._id }
    user = undefined #will be set only if document.entity is an organization and not a consumer

    if who.type is choices.entities.BUSINESS
      user = {type: pollDoc.createdBy.type, id: pollDoc.createdBy.id}

    stream = {
      who               : who
      entitiesInvolved  : [who]
      what              : poll
      when              : pollDoc.dates.created
      #where:
      events            : [choices.eventTypes.POLL_CREATED]
      data              : {}
      feeds: {
        global          : false
      }
      private: false #THIS NEEDS TO BE UPDATED BASED ON PRIVACY SETTINGS OF WHO (if consumer)
    }

    if user?
      stream.by = user
      stream.entitiesInvolved.push(user)

    stream.data = {
      poll:{
        question: pollDoc.question
        name: pollDoc.name
      }
    }

    logger.debug stream

    @add stream, callback

  @pollUpdated: (pollDoc, callback)->
    if Object.isString(pollDoc._id)
      pollDoc._id = new ObjectId(pollDoc._id)

    if Object.isString(pollDoc.entity.id)
      pollDoc.entity.id = new ObjectId(pollDoc.entity.id)

    if Object.isString(pollDoc.lastModifiedBy.id)
      pollDoc.lastModifiedBy.id = new ObjectId(pollDoc.lastModifiedBy.id)

    who = pollDoc.entity
    poll = {type: choices.objects.POLL, id: pollDoc._id }
    user = undefined #will be set only if document.entity is an organization and not a consumer

    if who.type is choices.entities.BUSINESS
      user = {type: pollDoc.lastModifiedBy.type, id: pollDoc.lastModifiedBy.id}

    stream = {
      who               : who
      entitiesInvolved  : [who]
      what              : poll
      when              : pollDoc.dates.lastModified
      #where:
      events            : [choices.eventTypes.POLL_UPDATED]
      data              : {}
      feeds: {
        global          : false
      }
      private: false #THIS NEEDS TO BE UPDATED BASED ON PRIVACY SETTINGS OF WHO (if consumer)
    }

    if user?
      stream.by = user
      stream.entitiesInvolved.push(user)

    stream.data = {
      poll:{
        question: pollDoc.question
        name: pollDoc.name
      }
    }

    @add stream, callback

  @pollDeleted: (pollDoc, callback)->
    if Object.isString(pollDoc._id)
      pollDoc._id = new ObjectId(pollDoc._id)

    if Object.isString(pollDoc.entity.id)
      pollDoc.entity.id = new ObjectId(pollDoc.entity.id)

    if Object.isString(pollDoc.lastModifiedBy.id)
      pollDoc.lastModifiedBy.id = new ObjectId(pollDoc.lastModifiedBy.id)

    who = pollDoc.entity.type #who ever created it
    poll = {type: choices.objects.POLL, id: pollDoc._id }
    user = undefined #will be set only if document.entity is an organization and not a consumer

    if who.type is choices.entities.BUSINESS
      user = pollDoc.lastModifiedBy

    stream = {
      who               : who
      entitiesInvolved  : [who]
      what              : poll
      when              : pollDoc.dates.lastModified
      #where:
      events            : [choices.eventTypes.POLL_DELETED]
      data              : {}
      feeds: {
        global          : false
      }
      private: false #THIS NEEDS TO BE UPDATED BASED ON PRIVACY SETTINGS OF WHO (if consumer)
    }

    if user?
      stream.by = user
      stream.entitiesInvolved.push(user)

    stream.data = {
      poll:{
        question: pollDoc.question
        name: pollDoc.name
      }
    }

    @add stream, callback

  @pollAnswered: (who, timestamp, pollDoc, callback)->
    if Object.isString(who.id)
      who.id = new ObjectId(who.id)

    if Object.isString(pollDoc._id)
      pollDoc._id = new ObjectId(pollDoc._id)

    if Object.isString(pollDoc.entity.id)
      pollDoc.entity.id = new ObjectId(pollDoc.entity.id)

    poll = {type: choices.objects.POLL, id: pollDoc._id }

    stream = {
      who               : who
      entitiesInvolved  : [who, pollDoc.entity]
      what              : poll
      when              : timestamp
      #where:
      events            : [choices.eventTypes.POLL_ANSWERED]
      data              : {}
      feeds: {
        global          : false
      }
      private: false #THIS NEEDS TO BE UPDATED BASED ON PRIVACY SETTINGS OF WHO (if consumer)
    }

    stream.data = {
      poll:{
        question: pollDoc.question
        name: pollDoc.name
      }
    }

    @add stream, callback

  @discussionCreated: (discussionDoc, callback)->
    logger.debug discussionDoc
    if Object.isString(discussionDoc._id)
      discussionDoc._id = new ObjectId(discussionDoc._id)

    if Object.isString(discussionDoc.entity.id)
      discussionDoc.entity.id = new ObjectId(discussionDoc.entity.id)

    if Object.isString(discussionDoc.createdBy.id)
      discussionDoc.createdBy.id = new ObjectId(discussionDoc.createdBy.id)

    who = discussionDoc.entity
    discussion = {type: choices.objects.DISCUSSION, id: discussionDoc._id }
    user = undefined #will be set only if document.entity is an organization and not a consumer

    if who.type is choices.entities.BUSINESS
      user = {type: discussionDoc.createdBy.type, id: discussionDoc.createdBy.id}

    stream = {
      who               : who
      entitiesInvolved  : [who]
      what              : discussion
      when              : discussionDoc.dates.created
      #where:
      events            : [choices.eventTypes.DISCUSSION_CREATED]
      data              : {}
      feeds: {
        global          : false
      }
    }

    if user?
      stream.by = user
      stream.entitiesInvolved.push(user)

    stream.data = {
      discussion:{
        name: discussionDoc.name
      }
    }

    logger.debug stream

    @add stream, callback

  @discussionUpdated: (discussionDoc, callback)->
    if Object.isString(discussionDoc._id)
      discussionDoc._id = new ObjectId(discussionDoc._id)

    if Object.isString(discussionDoc.entity.id)
      discussionDoc.entity.id = new ObjectId(discussionDoc.entity.id)

    if Object.isString(discussionDoc.lastModifiedBy.id)
      discussionDoc.lastModifiedBy.id = new ObjectId(discussionDoc.lastModifiedBy.id)

    who = discussionDoc.entity #who ever created it
    discussion = {type: choices.objects.DISCUSSION, id: discussionDoc._id }
    user = undefined #will be set only if document.entity is an organization and not a consumer

    if who.type is choices.entities.BUSINESS
      user = {type: discussionDoc.lastModifiedBy.type, id: discussionDoc.lastModifiedBy.id}

    stream = {
      who               : who
      entitiesInvolved  : [who]
      what              : discussion
      when              : discussionDoc.dates.lastModified
      #where:
      events            : [choices.eventTypes.DISCUSSION_UPDATED]
      data              : {}
      feeds: {
        global          : false
      }
    }

    if user?
      stream.by = user
      stream.entitiesInvolved.push(user)

    stream.data = {
      discussion:{
        name: discussionDoc.name
      }
    }

    @add stream, callback

  @discussionDeleted: (discussionDoc, callback)->
    if Object.isString(discussionDoc._id)
      discussionDoc._id = new ObjectId(discussionDoc._id)

    if Object.isString(discussionDoc.entity.id)
      discussionDoc.entity.id = new ObjectId(discussionDoc.entity.id)

    if Object.isString(discussionDoc.lastModifiedBy.id)
      discussionDoc.lastModifiedBy.id = new ObjectId(discussionDoc.lastModifiedBy.id)

    who = discussionDoc.entity #who ever created it
    discussion = {type: choices.objects.DISCUSSION, id: discussionDoc._id }
    user = undefined #will be set only if document.entity is an organization and not a consumer

    if who.type is choices.entities.BUSINESS
      user = {type: discussionDoc.lastModifiedBy.type, id: discussionDoc.lastModifiedBy.id}

    stream = {
      who               : who
      entitiesInvolved  : [who]
      what              : discussion
      when              : discussionDoc.dates.lastModified
      #where:
      events            : [choices.eventTypes.DISCUSSION_DELETED]
      data              : {}
      feeds: {
        global          : false
      }
    }

    if user?
      stream.by = user
      stream.entitiesInvolved.push(user)

    stream.data = {
      discussion:{
        name: discussionDoc.name
      }
    }

    @add stream, callback

  @discussionAnswered: (who, timestamp, discussionDoc, callback)->
    if Object.isString(who.id)
      who.id = new ObjectId(who.id)

    if Object.isString(discussionDoc._id)
      discussionDoc._id = new ObjectId(discussionDoc._id)

    if Object.isString(discussionDoc.entity.id)
      discussionDoc.entity.id = new ObjectId(discussionDoc.entity.id)

    discussion = {type: choices.objects.DISCUSSION, id: discussionDoc._id }

    stream = {
      who               : who
      entitiesInvolved  : [who, discussionDoc.entity]
      what              : discussion
      when              : timestamp
      #where:
      events            : [choices.eventTypes.DISCUSSION_ANSWERED]
      data              : {}
      feeds: {
        global          : false
      }
    }

    stream.data = {
      discussion:{
        name: discussionDoc.name
      }
    }

    @add stream, callback

  @eventRsvped: (who, eventDoc, callback)->
    if Object.isString(who.id)
      who.id = new ObjectId(who.id)

    event = {type: choices.objects.EVENT, id: eventDoc._id}
    stream = {
      who               : who
      entitiesInvolved  : [who, eventDoc.entity]
      what              : event
      when              : new Date()
      events            : [choices.eventTypes.EVENT_RSVPED]
      data              : {}
      feeds: {
        global          : true
      }
    }

    stream.data = {
      event: {
        entity:{
          name: eventDoc.entity.name
        }
        locationId: eventDoc.locationId
        location: eventDoc.location
        dates:{
          actual: eventDoc.dates.actual
        }
      }
    }

    @add stream, callback

  @btTapped: (btDoc, callback)->
    if Object.isString(btDoc._id)
      btDoc._id = new ObjectId(btDoc._id)
    if Object.isString(btDoc.organizationEntity.id)
      btDoc.organizationEntity.id = new ObjectId(btDoc.organizationEntity.id)

    #A user entity doesn't have to exist for a tapIn
    if btDoc.userEntity? and btDoc.userEntity.id?
      if Object.isString(btDoc.userEntity.id)
        btDoc.userEntity.id = new ObjectId(btDoc.userEntity.id)
    else
      btDoc.userEntity = {}
      btDoc.userEntity.type = choices.entities.CONSUMER
      btDoc.userEntity.id = new ObjectId("000000000000000000000000")
      btDoc.userEntity.name = "Someone"

    tapIn = {type: choices.objects.TAPIN, id: btDoc._id}
    who = btDoc.userEntity

    stream = {
      who               : who
      entitiesInvolved  : [who, btDoc.organizationEntity, btDoc.charity]
      what              : tapIn
      when              : btDoc.date

      where: {
        org             : btDoc.organizationEntity
        locationId      : btDoc.locationId
      }

      events            : [choices.eventTypes.BT_TAPPED]
      data              : {
        donationAmount  : btDoc.donationAmount
        charity         : btDoc.charity
      }

      feeds: {
        global          : true #unless a user's preferences are do that
      }
    }

    stream.feedSpecificData = {}
    stream.feedSpecificData.involved = #available only to entities involved
      amount: btDoc.amount
      donationAmount: btDoc.donationAmount #we shouldn't need this here

    logger.debug(stream)

    @add stream, callback
  ###
  example1: client created a poll:
    who = client
    what = [client, business, poll]
    when = timestamp that poll was created
    where = undefined
    events = [pollCreated]
    entitiesInvolved = [client, business]
    data:
      pollCreated:
        pollId: ObjectId
        pollName: String
        businessId: ObjectId
  ###

  ###
  example2: consumer created a poll:
    who = consumer
    what = [consumer, poll]
    when = timestamp that poll was created
    where = undefined
    events = [pollCreated]
    entitiesInvolved = [client]
    data:
      pollCreated:
        pollId: ObjectId
        pollName: String
  ###

  ###
  example3: consumer attend an event and tapped in:
    who = consumer
    what = [consumer, business, businessTransaction]
    when = timestamp the user tappedIn
    where: undefined
      org:
        type: business
        id: ObjectId
      orgName: String
      locationId: ObjectId
      locationName: String
    events = [attended, eventTapIn]
    entitiesInvolved = [client, business]
    data:
      eventTapIn:
        eventId: ObjectId
        businessTransactionId: ObjectId
        spent: XX.xx
  ###

  @global: (options, callback)->
    query = @optionParser(options)
    query.where "feeds.global", true
    query.sort "dates.lastModified", -1
    query.fields [
      "who.type"
      , "who.screenName"
      , "by"
      , "what"
      , "when"
      , "where"
      , "events"
      , "dates"
      , "data"
    ]
    query.exec callback

  @business: (businessId, options, callback)->
    query = @optionParser(options)
    query.sort "dates.lastModified", -1
    query.where "entitiesInvolved.type", choices.entities.BUSINESS
    query.where "entitiesInvolved.id", businessId
    query.only {
      "who.type": 1
      , "who.screenName": 1
      , "by": 1
      , "what": 1
      , "when": 1
      , "where": 1
      , "events": 1
      , "dates": 1
      , "data": 1
      , "feedSpecificData.involved": 1
      , "_id": 0
      , "id": 0
    }
    query.exec callback

  @businessWithConsumerByScreenName: (businessId, screenName, options, callback)->
    query = @optionParser(options)
    query.sort "dates.lastModified", -1
    query.where "entitiesInvolved.type", choices.entities.BUSINESS
    query.where "entitiesInvolved.id", businessId
    query.where "who.type", choices.entities.CONSUMER
    query.where "who.screenName", screenName
    query.fields [
      "who.type"
      , "who.screenName"
      , "what"
      , "when"
      , "where"
      , "events"
      , "dates"
      , "data"
      , "feedSpecificData.involved"
    ]
    query.exec callback

  @consumerPersonal: (consumerId, options, callback)->
    query = @optionParser(options)
    query.sort "dates.lastModified", -1
    query.where "who.type", choices.entities.CONSUMER
    query.where "who.id", consumerId
    query.fields [
      "who.type"
      , "who.name"
      , "who.screenName"
      , "who.id"
      , "by"
      , "what"
      , "when"
      , "where"
      , "events"
      , "dates"
      , "data"
      , "feedSpecificData.involved"
    ]
    query.exec callback

  @getLatest: (entity, limit, offset, callback)->
    query = @_query()
    query.limit limit
    query.skip offset
    query.sort "dates.lastModified", -1
    if entity?
      query.where "entity.type", entity.type
      query.where "entity.id", entity.id

    query.exec (error, activities)->
      if error?
        callback error
        return
      else if activities.length <=0
        callback error, {activities: [], consumers: []}
        return

      ids = []
      for activity in activities
        ids.push {_id: activity.entity.id}

      # get the consumer's name, and other info if we need it
      # currently only getting consumers, I will need to modify this to support
      # both consumers and businesses, because businesses will also answer do
      # things on the consumer side
      cQuery = Consumers._query()
      cQuery.or ids
      cQuery.only "email"
      cQuery.exec (error, consumers)->
        if error?
          callback error
          return
        callback error, {activities: activities, consumers: consumers}