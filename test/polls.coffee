vows = require 'vows'
assert = require 'assert'
api = require '../lib/api'
db = require '../lib/db'
util = require 'util'

globals = require 'globals'
utils = globals.utils

Polls = api.Polls

suite = vows.describe 'Testing Polls'

poll = null

#add
suite.addBatch {
  'New Poll': {
    'was added when all required fields have values': {
      topic: ()->
        obj = {
          name        : 'single selection poll'
          businessid  : '4e4af2c8a022988a14000006'
          type        : 'single'
          question    : 'Are you in a relationship'
          choices     : ['yes', 'no', "it's complicated"]
          funds       :
            allocated   : 500
            remaining   : 500
        }
        Polls.add obj, this.callback
        return
      'successfully': (error, data)->
        assert.isNull(error)
        assert.isObject(data)
        poll = data
    }
  }
}

#remove
suite.addBatch {
  'New Poll': {
    'was deleted': {
      topic: ()->
        Polls.remove poll._id, this.callback
        return
      'successfully': (error, data)->
        assert.isNull(error)
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
      'successfully': (error, data)->
        assert.isNull(error)
    }
  }
}

suite.export module
