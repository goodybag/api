require("./helpers").install(global)
Api = require("./Api")
tp = require "../transactions" #transaction processor

exports = module.exports = class Sequences extends Api
  @model: Sequence

  @current: (key, callback)->
    $fields = {}
    $fields[key] = 1
    @model.collection.findOne {_id: new ObjectId(0)}, {fields: $fields}, (error, doc)->
      if error?
        callback(error)
      else if !doc?
        callback({"sequence": "could not find sequence document"})
      else
        callback(null, doc[key])

  @next: (key, count, callback)->
    if Object.isFunction(count)
      callback = count
      count = 1

    $inc = {}
    $inc[key] = count

    $update = {$inc: $inc}

    $fields = {}
    $fields[key]= 1

    @model.collection.findAndModify {_id: new ObjectId(0)}, [], $update, {new: true, safe: true, fields: $fields, upsert: true}, (error, doc)->
      if error?
        callback(error)
      else if !doc?
        callback({"sequence": "could not find sequence document"})
      else
        callback(null, doc[key])