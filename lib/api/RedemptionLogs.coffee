require("./helpers").install(global)
Api = require("./Api")
tp = require "../transactions" #transaction processor

exports = module.exports = class RedemptionLogs extends Api
  @model = RedemptionLog

  @add = (consumer, org, locationId, registerId, goody, dateRedeemed, transactionId, callback)->
    try
      if Object.isString consumer.id
        consumer.id = new ObjectId consumer.id
      if Object.isString org.id
        org.id = new ObjectId org.id
      if Object.isString locationId
        locationId = new ObjectId locationId
      if Object.isString registerId
        registerId = new ObjectId registerId
    catch error
      logger.error error
      callback(error)
      return

    doc = {
      _id: transactionId
      consumer: consumer
      org: org
      locationId: locationId
      registerId: registerId
      goody: {
        id: goody._id
        name: goody.name
        karmaPointsRequired: goody.karmaPointsRequired
      }

      dates: {
        created: new Date()
        redeemed: dateRedeemed
      }

      transactions : {
        ids : [transactionId]
      }
    }

    @model.collection.insert doc, {safe: true}, (error, logEntry)->
      if error?
        logger.error(error)
        cb(error)
        return
      callback(error, logEntry)
      return