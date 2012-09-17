require("./helpers").install(global)
Api = require("./Api")
tp = require "../transactions" #transaction processor

exports = module.exports = class BusinessRequests extends Api
  @model = BusinessRequest

  @add = (userId, business, callback)->
    data = {
      businessName: business
    }

    if userId?
      data.userEntity = {
        type: choices.entities.CONSUMER
        id: userId
      }
      data.loggedin = true
    else
      data.loggedin = false

    instance = new @model data
    instance.save callback