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
          businessid  : '4e4af2c8a022988a14000006'
          type        : 'video'
          name        : 'video-1'
          url         : 'http://www.test.com'
          thumb       : 'http://www.test.com'
          duration    : 425.45
          thumbs      : ['http://www.test.com/thumb1.jpg', 'http://www.test.com/thumb2.jpg']
          tags        : ['summer', 'winter']
        }
        Medias.add obj, this.callback
        return
      'successfully': (error, data)->
        assert.isNull(error)
        assert.isObject(data)
        video = data
    }
  }
  'New image': {
    'was added': {
      topic: ()->
        obj = {
          businessid  : '4e4af2c8a022988a14000006'
          type        : 'image'
          name        : 'image-1'
          url         : 'http://www.test.com'
          thumb       : 'http://www.test.com'
          duration    : 425.45
          tags        : ['summer']
        }
        Medias.add obj, this.callback
        return
      'successfully': (error, data)->
        assert.isNull(error)
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
        Medias.one video._id, this.callback
        return
      'successfully': (error, data)->
        assert.isNull(error)
        assert.isObject(data)
    }
  }
  'New image': {
    'was found': {
      topic: ()->
        Medias.one image._id, this.callback
        return
      'successfully': (error, data)->
        assert.isNull(error)
        assert.isObject(data)
    }
  }
}

#get
suite.addBatch {
  'New video': {
    'was found': {
      topic: ()->
        Medias.get {'businessid': 'test', 'type':'video'}, this.callback
        return
      'successfully': (error, data)->
        assert.isNull(error)
        assert.equal(data.length, 1)
    }
  }
  'New video': {
    'was not found': {
      topic: ()->
        Medias.get {'businessid': '4e55d8e21aae4ed14d000001', 'type': 'video'}, this.callback
        return
      'successfully': (error, data)->
        assert.isNull(error)
        assert.equal(data.length, 0)
    }
  }
  'New image': {
    'was found': {
      topic: ()->
        Medias.get {'businessid': 'test', 'type':'image'}, this.callback
        return
      'successfully': (error, data)->
        assert.isNull(error)
        assert.equal(data.length, 1)
    }
  }
  'New image': {
    'was not found': {
      topic: ()->
        Medias.get {'businessid': '4e55d8e21aae4ed14d000001', 'type': 'image'}, this.callback
        return
      'successfully': (error, data)->
        assert.isNull(error)
        assert.equal(data.length, 0)
    }
  }
}


#tags
suite.addBatch {
  '2 videos': {
    'have summer tag': {
      topic: ()->
        Medias.get {'tags': 'summer'}, this.callback
        return
      'successfully': (error, data)->
        assert.isNull(error)
        assert.equal(data.length, 2)
    }
  }
  '1 video': {
    'has winter tag': {
      topic: ()->
        Medias.get {'tags': 'winter'}, this.callback
        return
      'successfully': (error, data)->
        assert.isNull(error)
        assert.equal(data.length, 1)
    }
  }
  '2 videos': {
    'have winter OR summer tags': {
      topic: ()->
        Medias.get {'tags': ['winter', 'summer']}, this.callback
        return
      'successfully': (error, data)->
        assert.isNull(error)
        assert.equal(data.length, 2)
    }
  }
  '1 video': {
    'has winter AND summer tags': {
      topic: ()->
        query = Medias._query()
        #TODO: consider making this the default when calling get
        query.all('tags', ['summer','winter'])
        query.exec this.callback
        return
      'successfully': (error, data)->
        assert.isNull(error)
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
        return
      'successfully': (error, data)->
        assert.isNull(error)
    }
  }
  'New image': {
    'was deleted': {
      topic: ()->
        Medias.remove image._id, this.callback
        return
      'successfully': (error, data)->
        assert.isNull(error)
    }
  }
}

suite.export module
