vows = require 'vows'
assert = require 'assert'
api = require '../lib/api'
db = require '../lib/db'
util = require 'util'

globals = require 'globals'
utils = globals.utils

Medias = api.Medias


suite = vows.describe 'Testing Medias'

video = null
image = null


#add
suite.addBatch {
  'New video': {
    'was added': {
      topic: ()->
        obj = {
          clientid    : 'test'
          type        : 'video'
          name        : 'video-1'
          url         : 'http://www.test.com'
          duration    : 425.45
          thumbs      : ['http://www.test.com/thumb1.jpg', 'http://www.test.com/thumb2.jpg']
          tags        : ['summer', 'winter']
        }
        Medias.add obj, this.callback
      
      'successfully': (err, data)->
        assert.isNull(err)
        assert.isObject(data)
        video = data
    }
  }
  'New image': {
    'was added': {
      topic: ()->
        obj = {
          clientid    : 'test'
          type        : 'image'
          name        : 'image-1'
          url         : 'http://www.test.com'
          duration    : 425.45
          tags        : ['summer']
        }
        Medias.add obj, this.callback
      
      'successfully': (err, data)->
        assert.isNull(err)
        assert.isObject(data)
        image = data
    }
  }
}

#get
suite.addBatch {
  'New video': {
    'was found': {
      topic: ()->
        Medias.get video._id, this.callback
        
      'successfully': (err, data)->
        assert.isNull(err)
        assert.isObject(data)
    }
  }
  'New image': {
    'was found': {
      topic: ()->
        Medias.get image._id, this.callback
      
      'successfully': (err, data)->
        assert.isNull(err)
        assert.isObject(data)
    }
  }
}

#getFiles
suite.addBatch {
  'New video': {
    'was found': {
      topic: ()->
        Medias.getFiles {'clientid': 'test', 'type':'video'}, this.callback
      
      'successfully': (err, data)->
        assert.isNull(err)
        assert.equal(data.length, 1)
    }
  }
  'New video': {
    'was not found': {
      topic: ()->
        Medias.getFiles {'clientid': 'fake', 'type': 'video'}, this.callback
      
      'successfully': (err, data)->
        assert.isNull(err)
        assert.equal(data.length, 0)
    }
  }
  'New image': {
    'was found': {
      topic: ()->
        Medias.getFiles {'clientid': 'test', 'type':'image'}, this.callback
      
      'successfully': (err, data)->
        assert.isNull(err)
        assert.equal(data.length, 1)
    }
  }
  'New image': {
    'was not found': {
      topic: ()->
        Medias.getFiles {'clientid': 'fake', 'type': 'image'}, this.callback
      
      'successfully': (err, data)->
        assert.isNull(err)
        assert.equal(data.length, 0)
    }
  }
}


#tags
suite.addBatch {
  '2 videos': {
    'have summer tag': {
      topic: ()->
        Medias.getFiles {'tags': 'summer'}, this.callback
        
      'successfully': (err, data)->
        assert.isNull(err)
        assert.equal(data.length, 2)
    }
  }
  '1 video': {
    'has winter tag': {
      topic: ()->
        Medias.getFiles {'tags': 'winter'}, this.callback
        
      'successfully': (err, data)->
        assert.isNull(err)
        assert.equal(data.length, 1)
    }
  }
  '2 videos': {
    'have winter OR summer tags': {
      topic: ()->
        Medias.getFiles {'tags': ['winter', 'summer']}, this.callback
        
      'successfully': (err, data)->
        assert.isNull(err)
        assert.equal(data.length, 2)
    }
  }
  '1 video': {
    'has winter AND summer tags': {
      topic: ()->
        query = Medias._query()
        #TODO: consider making this the default when calling getFiles
        query.where('clientid','test').all('tags', ['summer','winter'])
        query.exec this.callback
        return
        
      'successfully': (err, data)->
        assert.isNull(err)
        assert.equal(data.length, 1)
    }
  }
}


#remove
suite.addBatch {
  'New video': {
    'was deleted': {
      topic: ()->
        Medias.remove video._id, this.callback
      
      'successfully': (err, data)->
        assert.isNull(err)
    }
  }
  'New image': {
    'was deleted': {
      topic: ()->
        Medias.remove image._id, this.callback
      
      'successfully': (err, data)->
        assert.isNull(err)
    }
  }
}

#disconnect from database
suite.addBatch {
  'Disconnect': {
    'from database': {
      topic: ()->
        db.disconnect(this.callback)
      
      'successfully': (err, data)->
        assert.isNull(err)
    }
  }
}

suite.export module 
suite.run