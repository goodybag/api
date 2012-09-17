require("./helpers").install(global)
Api = require("./Api")
tp = require "../transactions" #transaction processor

exports = module.exports = class Medias extends Api
  @model = Media

  @mediaFieldsForType: (mediasDoc, mediaFor)->
    switch mediaFor
      when 'event','poll','discussion'
        imageType = 'landscape'
      when 'business','consumer','client'
        imageType = 'square'
      when 'consumer-secure'
        imageType = 'secureSquare'

    if imageType == "square"
      media = {
        url     : mediasDoc.sizes.s128
        thumb   : mediasDoc.sizes.s85
        mediaId : mediasDoc._id
      }
    else if imageType == "secureSquare"
      media = {
        url     : mediasDoc.sizes['s128-secure']
        thumb   : mediasDoc.sizes['s85-secure']
        mediaId : mediasDoc._id
      }
    else if imageType == "landscape"
      media = {
        url     : mediasDoc.sizes.s320x240
        thumb   : mediasDoc.sizes.s100x75
        mediaId : mediasDoc._id
      }
    return media

  #validate Media Objects for other collections
  @validateMedia: (media, imageType, callback)->
    validatedMedia = {}
    if !media?
      callback new errors.ValidationError {"media":"Media is null."}
      return

    if !utils.isBlank(media.mediaId)
      #mediaId and no urls -> look up urls
      delete media.tempURL
      if (!utils.isBlank(media.url) or !utils.isBlank(media.thumb))
        logger.debug "validateMedia - mediaId supplied, missing urls, fetch urls from db."
        #mediaId typecheck is done in one
        Medias.one media.mediaId, (error, data)->
          if error?
            callback error #callback
            return
          else if !data? || data.length==0
            callback new errors.ValidationError({"mediaId":"Invalid MediaId"})
            return

          if imageType=="square"
            validatedMedia.mediaId = data._id #type objectId
            validatedMedia.thumb = data.sizes.s85
            validatedMedia.url   = data.sizes.s128
            validatedMedia.rotateDegrees = media.rotateDegrees if !utils.isBlank(media.rotateDegrees) && media.rotateDegrees!=0
            callback null, validatedMedia #media found and urls set
            return
          else if imageType=="landscape"
            logger.debug "imageType-landscape"
            logger.debug data
            validatedMedia.mediaId = data._id #type objectId
            validatedMedia.thumb = data.sizes.s100x75
            validatedMedia.url   = data.sizes.s320x240
            validatedMedia.rotateDegrees = media.rotateDegrees if !utils.isBlank(media.rotateDegrees) && media.rotateDegrees!=0
            callback null, validatedMedia #media found and urls set
            return
          else
            callback new errors.ValidationError({"imageType":"Unknown value."})
            return
      else  #media Id and has urls
        logger.debug "validateMedia - mediaId supplied with both URLs, no updates required."
        callback null, media
        return
    else if !utils.isBlank(media.guid) #media guid supplied.
      validatedMedia.guid = media.guid
      validatedMedia.rotateDegrees = media.rotateDegrees if !utils.isBlank(media.rotateDegrees) && media.rotateDegrees!=0
      if !utils.isBlank(media.tempURL)
        validatedMedia.url = media.tempURL
        validatedMedia.thumb = media.tempURL
        callback null, validatedMedia
        return
      else
        if utils.isBlank(media.url) || utils.isBlank(media.thumb)
          callback new errors.ValidationError({"media":"'tempURL' or ('url' and 'thumb') is required when supplying guid."})
          return
        else
          validatedMedia.url   = media.url
          validatedMedia.thumb = media.thumb
          callback null, validatedMedia
          return
    else if media.url? || media.thumb? #and !data.media.guid and !data.media.mediaId
      callback new errors.ValidationError({"media":"'guid' or 'mediaId' is required when supplying a media.url"})
      return
    else
      #invalid (missing ) or empty mediaObject
      callback null, {} #guid and urls supplied
      return



  #validate Media Objects for other collections
  @validateAndGetMediaURLs: (entityType, entityId, mediaFor, media, callback)->
    validatedMedia = {}
    if (!utils.isBlank(media.rotateDegrees) && !isNaN(parseInt(media.rotateDegrees)))
      validatedMedia.rotateDegrees = media.rotateDegrees
    if !media?
      callback null, null
      return

    if !utils.isBlank(media.mediaId)
      #mediaId and no urls -> look up urls
      if (utils.isBlank(media.url) or utils.isBlank(media.thumb))
        logger.debug "validateMedia - mediaId supplied, missing urls, fetch urls from db."
        #mediaId typecheck is done in one
        if Object.isString(media.mediaId)
          media.mediaId = new ObjectId(media.mediaId)
        Medias.one media.mediaId, (error, mediasDoc)->
          if error?
            callback error #callback
            return
          else if !mediasDoc? || mediasDoc.length==0
            callback new errors.ValidationError({"mediaId":"Invalid MediaId"})
            return
          validatedMedia = Medias.mediaFieldsForType mediasDoc._doc, mediaFor
          callback null, validatedMedia # found - media by mediaId
          return
      else  #media Id and has urls
        logger.debug "validateMedia - mediaId supplied with both URLs, no updates required."
        callback null, media
        return
    else if !utils.isBlank(media.guid) #media guid supplied.
      validatedMedia.guid = media.guid
      Medias.getByGuid entityType, entityId, validatedMedia.guid, (error, mediasDoc)->
        if error?
          callback error
          return
        else if mediasDoc?
          logger.debug "validateMedia - guid supplied, found guid in Medias."
          validatedMedia = Medias.mediaFieldsForType mediasDoc._doc, mediaFor
          callback null, validatedMedia # found - media uploaded by transloadit already
          return
        else #!media? - media has yet to be uploaded by transloadit.. mark it with the guid and use tempurls for now
          logger.debug "validateMedia - guid supplied, guid not found (use temp. URLs for now)."
          if !utils.isBlank(media.tempURL)
            validatedMedia.url = media.tempURL
            validatedMedia.thumb = media.tempURL
            callback null, validatedMedia
            return
          else
            if utils.isBlank(media.url) || utils.isBlank(media.thumb)
              callback new errors.ValidationError({"media":"'tempURL' or ('url' and 'thumb') is required when supplying guid."})
              return
            else
              validatedMedia.url   = media.url
              validatedMedia.thumb = media.thumb
              callback null, validatedMedia
              return
    else if !utils.isBlank(media.url) || !utils.isBlank(media.thumb) #and !data.media.guid and !data.media.mediaId
      callback new errors.ValidationError({"media":"'guid' or 'mediaId' is required when supplying a media.url"})
      return
    else
      #invalid (missing mediaId and guid..) or empty mediaObject
      callback null, null #guid and urls supplied
      return

  @addOrUpdate: (media, callback)->
    if Object.isString(media.entity.id)
      media.entity.id = new ObjectId media.entity.id
    @model.collection.findAndModify {guid:media.guid},[], {$set:media}, {new: true, safe: true, upsert:true}, (error, mediaCreated)->
      if error?
        callback error #dberror
        return
      logger.debug mediaCreated
      callback null, mediaCreated
      return
    return

  @optionParser = (options, q)->
    query = @_optionParser(options, q)
    query.where('entity.type', options.entityType) if options.entityType?
    query.where('entity.id', options.entityId) if options.entityId?
    query.where('type', options.type) if options.type?
    query.where('guid', options.guid) if options.guid?
    query.in('tags', options.tags) if options.tags?
    query.where('uploaddate').gte(options.start) if options.start?
    query.where('uploaddate').lte(options.end) if options.end?

    return query

  #type is either image or video
  @getByEntity: (entityType, entityId, type, callback)->
    if Object.isFunction(type)
      callback = type
      @get {entityType: entityType, entityId: entityId}, callback
      #@get {'entity.type': choices.entities.BUSINESS, 'entity.id': entityId}, callback
    else
      @get {entityType: entityType, entityId: entityId, type: type}, callback
      #@get {'entity.type': choices.entities.BUSINESS, 'entity.id': entityId, type: type}, callback
    return

  #getByGuid(entityId,guid,callback)
  @getByGuid: (entityType, entityId, guid, callback)->
    if Object.isString entityId
      entityId = entityId
    @get {entityType: entityType, entityId: entityId, guid: guid}, (error,mediasDoc)->
      if mediasDoc? && mediasDoc.length
        callback null, mediasDoc[0]
      else
        callback error, null