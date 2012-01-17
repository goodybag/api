globals = require "globals"
gb = require "goodybag-api"
gbapi = gb.api
config = require "./config"
mongoose = globals.mongoose

# create mongodb url
servers = []
for server in config.mongo.servers
  servers.push "#{server}/#{config.mongo.dbs.goodybag}"
mongoConnStr = servers.join(",")
console.log mongoConnStr

# connect to the goodybag database
db = mongoose.connect mongoConnStr, {}, (error, conn)->
  if error?
    console.log 'could not connect to database'
  else
    console.log "connected to database"

# connect to the goodybag database
gbapi.Consumers.get "4efc3800b78cea5683859057", (error, data)->
  console.log "what"
  console.log error
  console.log data
  return