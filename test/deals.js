(function() {
  var Deals, api, assert, db, did, globals, groupon, suite, util, utils, vows;

  vows = require('vows');

  assert = require('assert');

  api = require('../lib/api');

  groupon = require('groupon').client('9e1a051bc2b97495dc2601bf45c892bdd19695d5');

  util = require('util');

  globals = require('globals');

  utils = globals.utils;

  db = require('../lib/db');

  Deals = api.Deals;

  did = null;

  suite = vows.describe('Testing Deals');

  suite.addBatch({
    'A deal': {
      'was added': {
        topic: function() {
          var assertCallback;
          assertCallback = this.callback;
          return groupon.getDeals({
            'division_id': 'austin'
          }, function(err, data) {
            var address, deal, index, lowestIndex, lowestPrice, obj, option, _len, _ref;
            deal = data.deals[0];
            lowestPrice = 0;
            lowestIndex = 0;
            _ref = deal['options'];
            for (index = 0, _len = _ref.length; index < _len; index++) {
              option = _ref[index];
              if (option['price']['amount'] < lowestPrice) {
                lowestPrice = option['price']['amount'];
                lowestIndex = index;
              }
            }
            address = deal['options'][lowestIndex]['redemptionLocations'][lowestIndex];
            obj = {
              did: 'groupon' + '-' + deal['id'],
              provider: 'groupon',
              title: deal['title'],
              description: deal['pitchHtml'],
              image: deal['mediumImageUrl'],
              business: {
                name: deal['merchant']['name'],
                street1: address['streetAddress1'],
                street2: address['streetAddress2'],
                city: address['city'],
                state: address['state'],
                zip: address['postalCode'],
                country: 'us',
                lat: address['lat'],
                lng: address['lng']
              },
              city: 'austin',
              state: 'texas',
              country: 'us',
              costs: {
                actual: deal['options'][lowestIndex]['value']['amount'],
                discounted: deal['options'][lowestIndex]['price']['amount']
              },
              dates: {
                start: utils.dateGMT(new Date(deal['startAt'])),
                end: utils.dateGMT(new Date(deal['endAt']))
              },
              timezone: deal['division']['timezone'],
              image: deal['largeImageUrl'],
              tipped: deal['isTipped'],
              available: deal['isSoldOut'],
              url: deal['dealUrl'],
              data: deal
            };
            did = obj.did;
            Deals.add(obj, assertCallback);
          });
        },
        'successfully': function(err, data) {
          assert.isNull(err);
          return assert.equal(data, 1);
        }
      }
    }
  });

  suite.addBatch({
    'A deal': {
      topic: function() {
        return did;
      },
      'was gotten': {
        topic: function(d) {
          Deals.getDeal(d, this.callback);
        },
        'successfully': function(err, data) {
          return assert.isNotNull(data);
        }
      }
    }
  });

  suite.addBatch({
    'Many deals': {
      topic: function() {
        return did;
      },
      'were gotten': {
        topic: function(d) {
          Deals.getDeals({
            city: 'austin'
          }, this.callback);
        },
        'successfully': function(err, data) {
          return assert.isNotNull(data);
        }
      }
    }
  });

  suite.addBatch({
    'A deal': {
      topic: function() {
        return did;
      },
      'was liked': {
        topic: function(d) {
          Deals.like(d, 'lalit', this.callback);
        },
        'successfully': function(err, data) {
          return assert.isNull(err);
        }
      },
      'was disliked': {
        topic: function(d) {
          Deals.dislike(d, 'lalit', this.callback);
        },
        'successfully': function(err, data) {
          return assert.isNull(err);
        }
      },
      'was neutral': {
        topic: function(d) {
          Deals.neutral(d, 'lalit', this.callback);
        },
        'successfully': function(err, data) {
          return assert.isNull(err);
        }
      }
    }
  });

  suite.addBatch({
    'A deal': {
      topic: function() {
        return did;
      },
      'was removed': {
        topic: function(d) {
          Deals.remove(d, this.callback);
        },
        'successfully': function(err, data) {
          return assert.isNull(err);
        }
      }
    }
  });

  suite["export"](module);

}).call(this);
