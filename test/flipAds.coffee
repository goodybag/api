vows = require 'vows'
assert = require 'assert'
api = require '../lib/api'
db = require '../lib/db'
util = require 'util'

globals = require 'globals'
utils = globals.utils

FlipAds = api.FlipAds

flipad = null

suite = vows.describe 'Testing FlipAds'

#add
suite.addBatch {
  'New ad': {
    'was added': {
      topic: ()->
        obj = {
          businessid      : "4e4af2c8a022988a14000006"
          title           : "Title"
          description     : "Not needed"
          type            : "image"
          url             : "http://www.google.com/logo.png"
          thumb           : "http://www.google.com/thumb.png"
          dates: {
            start         : new Date( (new Date()).toUTCString() )
            end           : new Date( (new Date()).toUTCString() )
          }
          metadata: {
            duration      : 0
          }
          funds: {
            allocated     : 100.00
            remaining     : 50.00
          }
        }
        FlipAds.add obj, this.callback
        return
      'successfully': (error, data)->
        assert.isNull(error)
        assert.isObject(data)
        flipad = data
    }
  }
}

#get
suite.addBatch {
  'New ad': {
    'was found': {
      topic: ()->
        FlipAds.getByDateReversed {businessid: flipad.businessid}, this.callback
        return
      'successfully': (error, data)->
        assert.isNull(error)
        assert.equal(data.length, 1)
    }
  }
}

#remove
suite.addBatch {
  'New ad': {
    'was deleted': {
      topic: ()->
        FlipAds.remove flipad._id, this.callback
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
