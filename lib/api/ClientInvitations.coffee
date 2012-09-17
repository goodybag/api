require("./helpers").install(global)
Api = require("./Api")
tp = require "../transactions" #transaction processor

exports = module.exports = class ClientInvitations extends Api
  @model = ClientInvitation

  @add = (businessId, groupName, email, callback)->
    key = hashlib.md5(config.secretWord + email+(new Date().toString()))+'-'+generatePassword(12, false, /\d/)
    @_add {businessId: businessId, groupName: groupName, email: email, key: key}, callback

  @list = (businessId, groupName, callback)->
    query = @_query()
    query.where("businessId", businessId)
    query.where("groupName", groupName)
    query.fields({
      email: 1
    })
    query.exec callback

  @validate = (key, callback)->
    @model.collection.findAndModify {key: key, status: choices.invitations.state.PENDING},[],{$set: {status: choices.invitations.state.PROCESSED}}, {new: true, safe: true}, (error, invite)->
      if error?
        callback error #db error
      else if !invite?
        callback new errors.ValidationError {"key":"Invalid Invite Key"} #invalid key error
      else
        callback null, invite #success
      return

  @del = (businessId, groupName, pendingId, callback)->
    query = @_query()
    query.where("businessId", businessId)
    query.where("groupName", groupName)
    query.where("_id", pendingId)
    query.remove(callback)