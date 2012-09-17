require("./helpers").install(global)
Api = require("./Api")
tp = require "../transactions" #transaction processor

exports = module.exports = class Referrals extends Api
  @model = Referral

  @addUserLink: (entity, link, code, callback )->
    doc = {
      _id: new ObjectId()
      type: choices.referrals.types.LINK
      entity: {
        type: entity.type
        id: entity.id
      }
      incentives: {referrer: defaults.referrals.incentives.referrers.USER, referred: defaults.referrals.incentives.referreds.USER}
      link: {
        code: code
        url:  link
        type: choices.referrals.links.types.USER
        visits: 0
      }
      signups: 0
      referredUsers: []
    }

    @model.collection.insert(doc, {safe: true}, callback)

  @addTapInLink: (entity, link, code, callback)->
    doc = {
      _id: new ObjectId()
      type: choices.referrals.types.LINK
      entity: {
        type: entity.type
        id: entity.id
      }
      incentives: {referrer: defaults.referrals.incentives.referrers.TAP_IN, referred: defaults.referrals.incentives.referreds.TAP_IN}
      link: {
        code: code
        url:  link
        type: choices.referrals.links.types.TAPIN
        visits: 0
      }
      signups: 0
      referredUsers: []
    }

    @model.collection.insert(doc, {safe: true}, callback)

  @signUp: (code, referredEntity, callback)->
    $update = {
      $inc: {signups: 1}
      $push: {referredUsers: referredEntity}
    }

    $fields = {_id: 1, entity: 1, incentives: 1}

    logger.info "code: " + code
    @model.collection.findAndModify {"link.code": code}, [], $update, {safe: true, new: true, fields: $fields}, (error, doc)->
      if error?
        if callback?
          callback(error)
        return
      else
        logger.debug doc
        referralFound = doc?
        if callback?
          callback(null, referralFound)
        #deposit money into the referred's account
        if doc.entity.type is choices.entities.CONSUMER
          Consumers.addFunds(referredEntity.id, doc.incentives.referred)
        else if choices.entities.BUSINESS
          Businesses.addFunds(referredEntity.id, doc.incentives.referred)

        #deposit money into the referrer's account
        if doc.entity.type is choices.entities.CONSUMER
          Consumers.addFunds(doc.entity.id, doc.incentives.referrer)
        else if choices.entities.BUSINESS
          Businesses.addFunds(doc.entity.id, doc.incentives.referrer)