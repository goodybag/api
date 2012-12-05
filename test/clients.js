(function() {
  var Clients, api, assert, client, db, globals, suite, util, utils, vows;

  vows = require('vows');

  assert = require('assert');

  util = require('util');

  api = require('../lib/api');

  db = require('../lib/db');

  globals = require('globals');

  utils = globals.utils;

  Clients = api.Clients;

  client = null;

  suite = vows.describe('Testing Clients');

  suite.addBatch({
    'New client': {
      'registered': {
        topic: function() {
          var obj;
          obj = {
            email: "test@gmail.com",
            password: "password",
            phone: "1234567890",
            firstname: "test",
            lastname: "ing"
          };
          Clients.register(obj, this.callback);
        },
        'successfully': function(err, data) {
          assert.isNull(err);
          assert.isObject(data);
          return client = data;
        }
      }
    }
  });

  suite.addBatch({
    'New client': {
      'unregistered': {
        topic: function() {
          Clients.login("test@gmail.com", "password", this.callback);
        },
        'successfully': function(err, data) {
          assert.isNull(err);
          return assert.equal(data.email, "test@gmail.com");
        }
      }
    }
  });

  suite.addBatch({
    'New client': {
      'unregistered': {
        topic: function() {
          Clients.remove(client._id, this.callback);
        },
        'successfully': function(err, data) {
          return assert.isNull(err);
        }
      }
    }
  });

  suite["export"](module);

}).call(this);
