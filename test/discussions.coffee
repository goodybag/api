api = require "../lib/api"
globals = require "globals"

mongoose = globals.mongoose

# connect to the goodybag database
db = mongoose.connect "mongodb://127.0.0.1:1337/goodybag", {auto_reconnect: true}, (error, conn)->
  if error?
    console.log "could not connect to database"
  else
    console.log "connected to database"

discussionId = "4f2a4eaa2be51c4e1800000c"
responseId = "4f2a521d667303221a00000c"

entity = {
  type: "consumer"
  id: "4f29c3b92892abdd0d000025"
  name: "lalit"
  screenName: "secret"
}

respond = ()->
  content = "blah blah blah"
  response = {
    entity: entity
    content: content
  }

  api.Discussions.respond discussionId, entity, content, (error, success)->
    console.log error
    console.log success

voteUp = ()->
  api.Discussions.voteUp discussionId, responseId, entity, (error, success)->
    console.log error
    console.log success

voteDown = ()->
  api.Discussions.voteDown discussionId, responseId, entity, (error, success)->
    console.log error
    console.log success

undoVoteUp = ()->
  api.Discussions.undoVoteUp discussionId, responseId, entity, (error, success)->
    console.log error
    console.log success

comment = ()->
  entity = entity

  content = "COMMENTING YAY YAY!!"

  api.Discussions.comment discussionId, responseId, entity, content, (error, success)->
    console.log error
    console.log success

donate = ()->
  amount = 0.01

  api.Discussions.donate discussionId, entity, amount, (error, success)->
    console.log error
    console.log success

thank = ()->
  amount = 0.01

  api.Discussions.thank discussionId, responseId, entity, amount, (error, success)->
    console.log error
    console.log success


distributeDonation = ()->
  amount = 0.01

  api.Discussions.distributeDonation discussionId, responseId, entity, amount, (error, success)->
    console.log error
    console.log success

list = ()->
  api.Discussions.list (error, discussions)->
    console.log error
    console.log discussions

get = ()->
  api.Discussions.get discussionId, (error, discussion)->
    console.log error
    console.log discussion

getResponses = ()->
  api.Discussions.getResponses discussionId, {start:0, stop:2}, (error, responses)->
    console.log error
    console.log responses

#respond()
#voteUp()
#undoVoteUp()
#voteDown()
#comment()
#donate()
#thank()
#distributeDonation()
#list()
#get()
#getResponses()