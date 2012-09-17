bcrypt = require "bcrypt"
uuid = require "node-uuid"
generatePassword = require "password-generator"
util = require "util"
async = require "async"

globals = require "globals"
loggers = require "../loggers"

db = require "../db"

exports = module.exports
exports.install = (context)->
  context.bcrypt = bcrypt
  context.uuid = uuid
  context.generatePassword = generatePassword
  context.util = util
  context.async = async
  context.globals = globals
  context.loggers = loggers

  context.db = db

  context.config = globals.config
  context.utils = globals.utils
  context.choices = globals.choices
  context.defaults = globals.defaults
  context.errors = globals.errors
  context.transloadit = globals.transloadit
  context.guidGen = globals.guid
  context.fb = globals.facebook
  context.urlShortner = globals.urlShortner
  context.hashlib = globals.hashlib

  context.ObjectId = globals.mongoose.Types.ObjectId
  context.Binary = globals.mongoose.mongo.BSONPure.Binary

  context.logger = loggers.api

  context.async = async

  context.ObjectId = globals.mongoose.Types.ObjectId
  context.Binary = globals.mongoose.mongo.BSONPure.Binary

  context.DBTransaction             = db.DBTransaction
  context.Consumer                  = db.Consumer
  context.Client                    = db.Client
  context.Business                  = db.Business
  context.Goody                     = db.Goody
  context.Statistic                 = db.Statistic
  context.Media                     = db.Media
  context.ClientInvitation          = db.ClientInvitation
  context.Tag                       = db.Tag
  context.BusinessTransaction       = db.BusinessTransaction
  context.BusinessRequest           = db.BusinessRequest
  context.Stream                    = db.Stream
  context.Statistic                 = db.Statistic
  context.UnclaimedBarcodeStatistic = db.UnclaimedBarcodeStatistic
  context.Organization              = db.Organization
  context.PasswordResetRequest      = db.PasswordResetRequest
  context.Referral                  = db.Referral
  context.Barcode                   = db.Barcode
  context.CardRequest               = db.CardRequest
  context.RedemptionLog             = db.RedemptionLog
  context.Sequence                  = db.Sequence
  return