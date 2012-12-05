(function() {
  var Medias, api, assert, db, globals, image, suite, util, utils, video, vows;

  vows = require('vows');

  assert = require('assert');

  api = require('../lib/api');

  db = require('../lib/db');

  util = require('util');

  globals = require('globals');

  utils = globals.utils;

  Medias = api.Medias;

  suite = vows.describe('Testing Medias');

  video = null;

  image = null;

  suite.addBatch({
    'New video': {
      'was added': {
        topic: function() {
          var obj;
          obj = {
            businessid: '4e4af2c8a022988a14000006',
            type: 'video',
            name: 'video-1',
            url: 'http://www.test.com',
            thumb: 'http://www.test.com',
            duration: 425.45,
            thumbs: ['http://www.test.com/thumb1.jpg', 'http://www.test.com/thumb2.jpg'],
            tags: ['summer', 'winter']
          };
          Medias.add(obj, this.callback);
        },
        'successfully': function(error, data) {
          assert.isNull(error);
          assert.isObject(data);
          return video = data;
        }
      }
    },
    'New image': {
      'was added': {
        topic: function() {
          var obj;
          obj = {
            businessid: '4e4af2c8a022988a14000006',
            type: 'image',
            name: 'image-1',
            url: 'http://www.test.com',
            thumb: 'http://www.test.com',
            duration: 425.45,
            tags: ['summer']
          };
          Medias.add(obj, this.callback);
        },
        'successfully': function(error, data) {
          assert.isNull(error);
          assert.isObject(data);
          return image = data;
        }
      }
    }
  });

  suite.addBatch({
    'New video': {
      'was found': {
        topic: function() {
          Medias.one(video._id, this.callback);
        },
        'successfully': function(error, data) {
          assert.isNull(error);
          return assert.isObject(data);
        }
      }
    },
    'New image': {
      'was found': {
        topic: function() {
          Medias.one(image._id, this.callback);
        },
        'successfully': function(error, data) {
          assert.isNull(error);
          return assert.isObject(data);
        }
      }
    }
  });

  suite.addBatch({
    'New video': {
      'was found': {
        topic: function() {
          Medias.get({
            'businessid': 'test',
            'type': 'video'
          }, this.callback);
        },
        'successfully': function(error, data) {
          assert.isNull(error);
          return assert.equal(data.length, 1);
        }
      }
    },
    'New video': {
      'was not found': {
        topic: function() {
          Medias.get({
            'businessid': '4e55d8e21aae4ed14d000001',
            'type': 'video'
          }, this.callback);
        },
        'successfully': function(error, data) {
          assert.isNull(error);
          return assert.equal(data.length, 0);
        }
      }
    },
    'New image': {
      'was found': {
        topic: function() {
          Medias.get({
            'businessid': 'test',
            'type': 'image'
          }, this.callback);
        },
        'successfully': function(error, data) {
          assert.isNull(error);
          return assert.equal(data.length, 1);
        }
      }
    },
    'New image': {
      'was not found': {
        topic: function() {
          Medias.get({
            'businessid': '4e55d8e21aae4ed14d000001',
            'type': 'image'
          }, this.callback);
        },
        'successfully': function(error, data) {
          assert.isNull(error);
          return assert.equal(data.length, 0);
        }
      }
    }
  });

  suite.addBatch({
    '2 videos': {
      'have summer tag': {
        topic: function() {
          Medias.get({
            'tags': 'summer'
          }, this.callback);
        },
        'successfully': function(error, data) {
          assert.isNull(error);
          return assert.equal(data.length, 2);
        }
      }
    },
    '1 video': {
      'has winter tag': {
        topic: function() {
          Medias.get({
            'tags': 'winter'
          }, this.callback);
        },
        'successfully': function(error, data) {
          assert.isNull(error);
          return assert.equal(data.length, 1);
        }
      }
    },
    '2 videos': {
      'have winter OR summer tags': {
        topic: function() {
          Medias.get({
            'tags': ['winter', 'summer']
          }, this.callback);
        },
        'successfully': function(error, data) {
          assert.isNull(error);
          return assert.equal(data.length, 2);
        }
      }
    },
    '1 video': {
      'has winter AND summer tags': {
        topic: function() {
          var query;
          query = Medias._query();
          query.all('tags', ['summer', 'winter']);
          query.exec(this.callback);
        },
        'successfully': function(error, data) {
          assert.isNull(error);
          return assert.equal(data.length, 1);
        }
      }
    }
  });

  suite.addBatch({
    'New video': {
      'was deleted': {
        topic: function() {
          Medias.remove(video._id, this.callback);
        },
        'successfully': function(error, data) {
          return assert.isNull(error);
        }
      }
    },
    'New image': {
      'was deleted': {
        topic: function() {
          Medias.remove(image._id, this.callback);
        },
        'successfully': function(error, data) {
          return assert.isNull(error);
        }
      }
    }
  });

  suite["export"](module);

}).call(this);
