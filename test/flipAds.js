(function() {
  var FlipAds, api, assert, db, flipad, globals, suite, util, utils, vows;

  vows = require('vows');

  assert = require('assert');

  api = require('../lib/api');

  db = require('../lib/db');

  util = require('util');

  globals = require('globals');

  utils = globals.utils;

  FlipAds = api.FlipAds;

  flipad = null;

  suite = vows.describe('Testing FlipAds');

  suite.addBatch({
    'New ad': {
      'was added': {
        topic: function() {
          var obj;
          obj = {
            businessid: "4e4af2c8a022988a14000006",
            title: "Title",
            description: "Not needed",
            type: "image",
            url: "http://www.google.com/logo.png",
            thumb: "http://www.google.com/thumb.png",
            dates: {
              start: new Date((new Date()).toUTCString()),
              end: new Date((new Date()).toUTCString())
            },
            metadata: {
              duration: 0
            },
            funds: {
              allocated: 100.00,
              remaining: 50.00
            }
          };
          FlipAds.add(obj, this.callback);
        },
        'successfully': function(error, data) {
          assert.isNull(error);
          assert.isObject(data);
          return flipad = data;
        }
      }
    }
  });

  suite.addBatch({
    'New ad': {
      'was found': {
        topic: function() {
          FlipAds.getByDateReversed({
            businessid: flipad.businessid
          }, this.callback);
        },
        'successfully': function(error, data) {
          assert.isNull(error);
          return assert.equal(data.length, 1);
        }
      }
    }
  });

  suite.addBatch({
    'New ad': {
      'was deleted': {
        topic: function() {
          FlipAds.remove(flipad._id, this.callback);
        },
        'successfully': function(error, data) {
          return assert.isNull(error);
        }
      }
    }
  });

  suite["export"](module);

}).call(this);
