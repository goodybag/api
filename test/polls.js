(function() {
  var Polls, addPoll, api, assert, db, dbCallback, globals, pollData, removePoll, util, utils, vows,
    __hasProp = Object.prototype.hasOwnProperty;

  vows = require('vows');

  assert = require('assert');

  api = require('../lib/api');

  db = require('../lib/db');

  util = require('util');

  globals = require('globals');

  utils = globals.utils;

  Polls = api.Polls;

  removePoll = function(poll) {
    return Polls.remove(poll._id, function(error, data) {
      if (error != null) return console.log('error remvoing: ' + error);
    });
  };

  dbCallback = function(assertCallback) {
    return function(err, poll) {
      var p, _i, _len;
      try {
        return assertCallback(err, poll);
      } finally {
        if (!(poll != null)) return;
        if (Array.isArray(poll)) {
          for (_i = 0, _len = poll.length; _i < _len; _i++) {
            p = poll[_i];
            removePoll(p);
          }
        } else {
          removePoll(poll);
        }
      }
    };
  };

  addPoll = function(poll, callback) {
    return Polls.add(poll, callback);
  };

  pollData = function(data) {
    var obj, property, value;
    obj = {
      name: 'single selection poll',
      businessid: '4e4af2c8a022988a14000006',
      type: 'single',
      question: 'Are you in a relationship',
      choices: ['yes', 'no', "it's complicated"],
      funds: {
        allocated: 500,
        remaining: 500
      }
    };
    for (property in data) {
      if (!__hasProp.call(data, property)) continue;
      value = data[property];
      obj[property] = value;
    }
    return obj;
  };

  vows.describe('Polls').addBatch({
    '#add': {
      'with all required values': {
        topic: function() {
          return Polls.add(pollData(), this.callback);
        },
        'should be successful': dbCallback(function(error, data) {
          assert.isNull(error);
          return assert.isObject(data);
        })
      },
      'with missing required field name': {
        topic: function() {
          return Polls.add(pollData({
            name: null
          }), this.callback);
        },
        'should fail validation': dbCallback(function(error, data) {
          return assert.equal(error != null ? error.name : void 0, 'ValidationError');
        })
      }
    },
    '#update': {
      'with choices': {
        topic: function() {
          var assertCallback;
          assertCallback = this.callback;
          return addPoll(pollData(), function(error, poll) {
            poll.choices.push('new choice');
            return Polls.update(poll._id, poll, assertCallback);
          });
        },
        'should add choice': dbCallback(function(error, poll) {
          return assert.length(poll != null ? poll.choices : void 0, 4);
        })
      }
    },
    'get': {
      'by name': {
        topic: function() {
          var assertCallback, name;
          assertCallback = this.callback;
          name = 'get by name';
          return addPoll(pollData({
            name: name
          }), function(error, poll) {
            return Polls.get({
              name: name
            }, assertCallback);
          });
        },
        'should find existing Poll': dbCallback(function(error, polls) {
          var _ref;
          return assert.equal((_ref = polls[0]) != null ? _ref.name : void 0, 'get by name');
        })
      }
    }
  }).addBatch({
    'Disconnect': {
      'from database': {
        topic: function() {
          return db.disconnect(this.callback);
        },
        'should be successfull': function(error, data) {
          return assert.isNull(error);
        }
      }
    }
  })["export"](module);

}).call(this);
