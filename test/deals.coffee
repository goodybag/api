vows = require 'vows'
assert = require 'assert'
api = require '../lib/api'
groupon = require('groupon').client '9e1a051bc2b97495dc2601bf45c892bdd19695d5' #THIS GOT CHECKED IN!
util = require 'util'

globals = require 'globals'
utils = globals.utils

db = require '../lib/db'
#Deals = db.Deal

Deals = api.Deals

deal = null

suite = vows.describe 'Testing Deals'

#add a deal (using groupon api, consider not doing this and just inserting data)
#it should not be dependant on the api for this test (this is a good test for the dealer project)
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
        assert.isNotNull(data)
    }
  }
}

#liking and disliking deals
suite.addBatch {
  'A deal': {
    topic: ()->
      return deal
    'is liked': {
      topic: (d)->
        Deals.like deal._id, 'lalit', this.callback
      'successfully': (err, data)->
        assert.isNull(err)
    }
    'is disliked': {
      topic: (d)->
        Deals.dislike deal._id, 'lalit', this.callback
      'successfully': (err, data)->
        assert.isNull(err)
    }
    'is neutral': {
      topic: (d)->
        Deals.neutral deal._id, 'lalit', this.callback
      'successfully': (err, data)->
        assert.isNull(err)
    }
  }
}

#get single deal
suite.addBatch {
  'A deal': {
    topic: ()->
      return deal
    'is gotten':{
      topic: (d)->
        Deals.getDeal d._id, this.callback
      'successfully': (err, data)->
        assert.isNotNull(data)
    }  
  }
}

#get many deals
suite.addBatch {
  'Many deals': {
    topic: ()->
      return deal
    'are gotten':{
      topic: (d)->
        Deals.getDeals {city:'austin'}, this.callback
      'successfully': (err, data)->
        assert.isNotNull(data)
    }  
  }
}

#remove the deal
suite.addBatch {
  'A deal': {
    topic: ()->
      return deal
    'is removed':{
      topic: (d)->
        Deals.remove d._id, this.callback
      'successfully': (err, data)->
        assert.isNull(err)
    }  
  }
}


suite.export module 
suite.run