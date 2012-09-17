require("./helpers").install(global)
Api = require("./Api")
tp = require "../transactions" #transaction processor

exports = module.exports = class Organizations extends Api
  @model = Organization

  @search = (name, type, callback)->
    re = new RegExp("^"+name+".*", 'i')
    query = @_query()
    if name? and !name.isBlank()
      query.where('name', re)
    if type in choices.organizations._enum
      query.where('type', type)
    query.limit(100)
    query.exec callback

  @setTransactonPending: @__setTransactionPending
  @setTransactionProcessing: @__setTransactionProcessing
  @setTransactionProcessed: @__setTransactionProcessed
  @setTransactionError: @__setTransactionError