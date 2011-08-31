vows = require 'vows'
assert = require 'assert'
api = require '../lib/api'
db = require '../lib/db'
util = require 'util'
globals = require 'globals'
utils = globals.utils
Polls = api.Polls

dbCallback = (assertCallback) ->
  (err, poll) ->
    try
      assertCallback(err, poll)
    finally
      console.log 'starting cleanup for: ' + util.inspect(poll)
      return if !poll?
      console.log 'cleaning up'
      Polls.remove poll._id, (error, data) ->
        console.log('error remvoing: ' + error) if error?

addPoll = (poll, callback) -> Polls.add poll, callback

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

vows.describe('Polls').addBatch(
  '#add':
    'with all required values':
      topic: -> Polls.add pollData(), this.callback
      'should be successful': dbCallback (error, data)->
        assert.isNull error
        assert.isObject data

    'with missing required field name':
      topic: -> Polls.add pollData({name: null}), this.callback
      'should fail validation': dbCallback (error, data)->
        assert.equal error?.name, 'ValidationError'

  '#update':
    'with choices':
      topic: ->
        assertCallback = this.callback
        addPoll pollData(), (error, poll) ->
          poll.choices.push 'new choice'
          Polls.update poll._id, poll, assertCallback
      'should add choice': dbCallback (error, poll) ->
        assert.length poll?.choices, 4

  'get':
    'by name':
      topic: ->
        assertCallback = this.callback
        name = 'get by name'
        addPoll pollData({name: name}), (error, poll) ->
          Polls.get {name: name}, assertCallback
      'should find existing Poll': dbCallback (error, poll) ->
        assert.equal poll?.name, 'get by name'

).addBatch(
  'Disconnect':
    'from database':
      topic: -> db.disconnect(this.callback)
      'should be successfull': (error, data)->
        assert.isNull(error)
).export module
