vows = require 'vows'
assert = require 'assert'
util = require 'util'

api = require '../lib/api'
db = require '../lib/db'
globals = require 'globals'

utils = globals.utils
Clients = api.Clients

client = null

suite = vows.describe 'Testing Clients'

#register
suite.addBatch {
  'New client': {
    'registered': {
      topic: ()->
        obj = {
          email       : "test@gmail.com"
          password    : "password"
          phone       : "1234567890"
          firstname   : "test"
          lastname    : "ing"
        }
        Clients.register obj, this.callback
        return
      'successfully': (err, data)->
        assert.isNull(err)
        assert.isObject(data)
        client = data
    }
  }
}

#login
suite.addBatch {
  'New client': {
    'unregistered': {
      topic: ()->
        Clients.login "test@gmail.com", "password", this.callback
        return
      'successfully': (err, data)->
        assert.isNull(err)
        assert.equal(data.email, "test@gmail.com")
    }
  }
}

#deregister
suite.addBatch {
  'New client': {
    'unregistered': {
      topic: ()->
        Clients.remove client._id, this.callback
        return
      'successfully': (err, data)->
        assert.isNull(err)
    }
  }
}

#disconnect from database
suite.addBatch {
  'Disconnect': {
    'from database': {
      topic: ()->
        db.disconnect(this.callback)
        return
      'successfully': (err, data)->
        assert.isNull(err)
    }
  }
}

suite.export module