require("./helpers").install(global)
Api = require("./Api")
tp = require "../transactions" #transaction processor

exports = module.exports = class Barcodes extends Api
  @model = Barcode

  @assignNew: (entity, callback)->
    self = this
    Sequences.next "barcodeId", (error, value)=>
      value = defaults.barcode.offset + value
      security = utils.randomBarcodeSecurityString(3)
      barcodeId = "#{value}-#{security}"
      @model.collection.insert {barcodeId: barcodeId}, {safe: true}, (error, barcode)->
        if error?
          callback(error)
          return
        else if barcode?
          barcode = barcode[0]
          logger.silly "UPDATING CONSUMER BARCODE TO #{barcodeId}"
          Consumers.updateBarcodeId entity, barcodeId, (error, success)->
            if error?
              callback(error)
              return
            if success is true
              callback(error, barcode)
              return
            else
              callback({"name": "barcodeAssociationError", message: "unable to properly associate barcodeId with user"})
              return
        else
          callback(null, null)
          return