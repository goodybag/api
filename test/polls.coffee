vows = require 'vows'
assert = require 'assert'
api = require '../lib/api'
db = require '../lib/db'
util = require 'util'

globals = require 'globals'
utils = globals.utils

Polls = api.Polls

suite = vows.describe 'Polls'

dbCallback = (assertCallback) ->
  (err, poll) ->
    assertCallback(err, poll)
    return if !poll?
    Polls.remove poll._id, (error, data) ->

pollData = (data) ->
  obj =
    name        : 'single selection poll'
    businessid  : '4e4af2c8a022988a14000006'
    type        : 'single'
    question    : 'Are you in a relationship'
    choices     : ['yes', 'no', "it's complicated"]
    funds       :
      allocated   : 500
      remaining   : 500

  for own property, value of data
    obj[property] = value

  return obj

#add
suite.addBatch(
  '#add':
    'with all required values':
      topic: -> Polls.add pollData(), this.callback
      'should be successful': dbCallback (error, data)->
        assert.isNull(error)
        assert.isObject(data)

    'with missing required field name':
      topic: -> Polls.add pollData({name: null}), this.callback
      'should fail validation': dbCallback (error, data)->
        assert.equal(error?.name, 'ValidationError')

)

suite.export module
