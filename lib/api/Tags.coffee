require("./helpers").install(global)
Api = require("./Api")
tp = require "../transactions" #transaction processor

exports = module.exports = class Tags extends Api
  @model = Tag

  @add = (name, type, callback)->
    @_add {name: name, type: type}, callback

  @addAll = (nameArr, type, callback)->
    #callback is not required..
    countUpdates = 0
    for val,i in nameArr
      @model.update {name:val, type: type}, {$inc:{count:1}}, {upsert:true,safe:true}, (error, success)->
        if error?
          callback error
          return
        if ++countUpdates == nameArr.length && Object.isFunction callback #check if done
          callback null, countUpdates
        return

  @search = (name, type, callback)->
    re = new RegExp("^"+name+".*", 'i')
    query = @_query()
    if name? or name.isBlank()
      query.where('name', re)
    if type in choices.tags.types._enum
      query.where('type', type)
    query.limit(10)
    query.exec callback