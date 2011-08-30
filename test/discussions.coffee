vows = require 'vows'
assert = require 'assert'
api = require '../lib/api'
db = require '../lib/db'
util = require 'util'

globals = require 'globals'
utils = globals.utils

Discussions = api.Discussions

suite = vows.describe 'Testing Discussions'

discussion = null

#add
suite.addBatch {
  'New discussion': {
    'was added': {
      topic: ()->
        obj = {
          businessid    : '4e4af2c8a022988a14000006'
          question      : 'How is it working in a startup'
          funds         :
            allocated   : 500
            remaining   : 500
        }
        Discussions.add obj, this.callback
        return
      'successfully': (error, data)->
        assert.isNull(error)
        assert.isObject(data)
        discussion = data
        return
    }
  }
}

#remove
suite.addBatch {
  'New discussion': {
    'was deleted': {
      topic: ()->
        Discussions.remove discussion._id, this.callback
        return
      'successfully': (error, data)->
        assert.isNull(error)
    }
  }
}

suite.export module
