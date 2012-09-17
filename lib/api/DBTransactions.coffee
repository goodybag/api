require("./helpers").install(global)
Api = require("./Api")
tp = require "../transactions" #transaction processor

exports = module.exports = class DBTransactions extends Api
  @model: DBTransaction