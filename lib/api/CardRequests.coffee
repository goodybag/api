require("./helpers").install(global)
Api = require("./Api")
tp = require "../transactions" #transaction processor

exports = module.exports = class CardRequests extends Api
  @model = CardRequest

  @pending: (id, callback)->
    if Object.isString id
      id = new ObjectId id
    $query = {'entity.id': id, 'dates.responded': {$exists: false}}
    @model.findOne $query, callback
