vows = require 'vows'
assert = require 'assert'
api = require '../lib/api'
groupon = require('groupon').client '9e1a051bc2b97495dc2601bf45c892bdd19695d5' #THIS GOT CHECKED IN!

globals = require 'globals'
utils = globals.utils

Deals = new api.Deals

deal = null

suite = vows.describe 'Testing Deals'
suite.addBatch {
  'A deal': {
    'was added': {
      topic: ()->
        self = this
        groupon.getDeals {'division_id': 'austin'}, (err, data)->
          #for deal in data.deals #insert many
          #console.log data.deals.length
          
          deal = data.deals[0] #insert only one
                    
          #if there are multiple options in this deal, find cheapest
          #and save that for the costs key
          lowestPrice = 0
          lowestIndex = 0
          for option, index in deal['options']
            if option['price']['amount'] < lowestPrice
              lowestPrice = option['price']['amount']
              lowestIndex = index
          #take the address from the option selected
          address = deal['options'][lowestIndex]['redemptionLocations'][lowestIndex]
          obj = {
            did             : 'groupon'+'-'+deal['id']
            provider        : 'groupon'
            title           : deal['title']
            description     : deal['pitchHtml']
            image           : deal['mediumImageUrl']
            business: { 
              name          : deal['merchant']['name']
              street1       : address['streetAddress1']
              street2       : address['streetAddress2']
              city          : address['city']
              state         : address['state']
              zip           : address['postalCode']
              country       : 'us'
              lat           : address['lat']
              lng           : address['lng']
            } 
            city            : 'austin'
            state           : 'texas'
            country         : 'us'
            costs: {         
             actual         : deal['options'][lowestIndex]['value']['amount']
             discounted     : deal['options'][lowestIndex]['price']['amount']
            }
            dates: {
             start          : utils.dateGMT(new Date(deal['startAt']))
             end            : utils.dateGMT(new Date(deal['endAt']))
            }
            timezone        : deal['division']['timezone']
            image           : deal['largeImageUrl']
            tipped          : deal['isTipped']
            available       : deal['isSoldOut']

            url             : deal['dealUrl']
            data            : deal
          }

          Deals.add obj, self.callback
      'successfully': (err, data)->
        deal = data
        assert.isNull(err)
      'A deal': {
        topic: ()->
          return deal
        'is liked': {
          topic: (d)->
            Deals.like deal._id, 'lalit', this.callback
          'successfully': (err, deal)->
            assert.isNull(err)
        }
        'is disliked': {
          topic: (d)->
            Deals.dislike deal._id, 'lalit', this.callback
          'successfully': (err, deal)->
            assert.isNull(err)
        }
        'is neutral': {
          topic: (d)->
            Deals.neutral deal._id, 'lalit', this.callback
          'successfully': (err, deal)->
            assert.isNull(err)
        }
      }
    }
  }
}

###suite.addBatch {
  'A deal': {
    topic: ()->
      console.log deal
      return deal
    'is liked': {
      topic: (d)->
        #console.log deal
        #Deals.like deal._id, this.callback
      'successfully': (error, deal)->
        assert.isNull(err)
    }
    'is disliked': {
      topic: (d)->
        Deals.dislike deal._id, this.callback
      'successfully': (error, deal)->
        assert.isNull(err)
    }
    'is unLiked': {
      topic: (d)->
        Deals.unlike deal._id, this.callback
      'successfully': (error, deal)->
        assert.isNull(err)
    }
    'is unDisliked': {
      topic: (d)->
        Deals.undislike deal._id, this.callback
      'successfully': (error, deal)->
        assert.isNull(err)
    }
  }
}###

suite.export module 
suite.run