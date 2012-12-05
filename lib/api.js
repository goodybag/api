(function() {
  var API, Barcode, Barcodes, Binary, Business, BusinessRequest, BusinessRequests, BusinessTransaction, BusinessTransactions, Businesses, CardRequest, CardRequests, Client, ClientInvitation, ClientInvitations, Clients, Consumer, Consumers, DBTransaction, DBTransactions, Discussion, Discussions, EmailSubmission, EmailSubmissions, Event, EventRequest, EventRequests, Events, Goodies, Goody, Media, Medias, ObjectId, Organization, Organizations, PasswordResetRequest, PasswordResetRequests, Poll, Polls, RedemptionLog, RedemptionLogs, Referral, Referrals, Response, Sequence, Sequences, Statistic, Statistics, Stream, Streams, Tag, Tags, UnclaimedBarcodeStatistic, UnclaimedBarcodeStatistics, Users, async, bcrypt, choices, config, db, defaults, errors, exports, fb, generatePassword, globals, guidGen, hashlib, logger, loggers, tp, transloadit, urlShortner, util, utils, uuid,
    __hasProp = Object.prototype.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor; child.__super__ = parent.prototype; return child; },
    __indexOf = Array.prototype.indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

  exports = module.exports;

  bcrypt = require("bcrypt");

  uuid = require("node-uuid");

  generatePassword = require("password-generator");

  util = require("util");

  async = require("async");

  globals = require("globals");

  loggers = require("./loggers");

  db = require("./db");

  tp = require("./transactions");

  logger = loggers.api;

  config = globals.config;

  utils = globals.utils;

  choices = globals.choices;

  defaults = globals.defaults;

  errors = globals.errors;

  transloadit = globals.transloadit;

  guidGen = globals.guid;

  fb = globals.facebook;

  urlShortner = globals.urlShortner;

  hashlib = globals.hashlib;

  ObjectId = globals.mongoose.Types.ObjectId;

  Binary = globals.mongoose.mongo.BSONPure.Binary;

  DBTransaction = db.DBTransaction;

  Sequence = db.Sequence;

  Client = db.Client;

  RedemptionLog = db.RedemptionLog;

  Consumer = db.Consumer;

  Goody = db.Goody;

  Business = db.Business;

  Media = db.Media;

  Poll = db.Poll;

  Discussion = db.Discussion;

  Response = db.Response;

  ClientInvitation = db.ClientInvitation;

  Tag = db.Tag;

  EventRequest = db.EventRequest;

  Event = db.Event;

  Stream = db.Stream;

  BusinessTransaction = db.BusinessTransaction;

  BusinessRequest = db.BusinessRequest;

  PasswordResetRequest = db.PasswordResetRequest;

  Statistic = db.Statistic;

  UnclaimedBarcodeStatistic = db.UnclaimedBarcodeStatistic;

  Organization = db.Organization;

  Referral = db.Referral;

  Barcode = db.Barcode;

  CardRequest = db.CardRequest;

  EmailSubmission = db.EmailSubmission;

  API = (function() {

    API.model = null;

    function API() {}

    API._flattenDoc = function(doc, startPath) {
      var flat, flatten;
      flat = {};
      flatten = function(obj, path) {
        var i, key;
        if (Object.isObject(obj)) {
          path = !(path != null) ? "" : path + ".";
          for (key in obj) {
            flatten(obj[key], path + key);
          }
        } else if (Object.isArray(obj)) {
          path = !(path != null) ? "" : path + ".";
          i = 0;
          while (i < obj.length) {
            flatten(obj[i], path + i);
            i++;
          }
        } else {
          flat[path] = obj;
        }
        return flat;
      };
      return flatten(doc, startPath);
    };

    API._copyFields = utils.copyFields;

    API._query = function() {
      return this.model.find();
    };

    API.query = API._query;

    API._queryOne = function() {
      return this.model.findOne();
    };

    API.queryOne = API._queryOne;

    API.optionParser = function(options, q) {
      return this._optionParser(options, q);
    };

    API._optionParser = function(options, q) {
      var query;
      query = q || this._query();
      if (options.limit != null) query.limit(options.limit);
      if (options.skip != null) query.skip(options.skip);
      if (options.sort != null) {
        query.sort(options.sort.field, options.sort.direction);
      }
      return query;
    };

    API.add = function(data, callback) {
      return this._add(data, callback);
    };

    API._add = function(data, callback) {
      var instance;
      instance = new this.model(data);
      instance.save(callback);
    };

    API.update = function(id, data, callback) {
      if (Object.isString(id)) id = new ObjectId(id);
      return this.model.findById(id, function(err, obj) {
        var k, v;
        for (k in data) {
          if (!__hasProp.call(data, k)) continue;
          v = data[k];
          obj[k] = v;
        }
        return obj.save(callback);
      });
    };

    API._update = function(id, updateDoc, dbOptions, callback) {
      if (Object.isString(id)) id = new ObjectId(id);
      if (id instanceof ObjectId) {
        id = {
          _id: id
        };
      }
      if (Object.isFunction(dbOptions)) {
        callback = dbOptions;
        dbOptions = {
          safe: true
        };
      }
      this.model.update(id, updateDoc, dbOptions, callback);
    };

    API.remove = function(id, callback) {
      return this._remove(id, callback);
    };

    API._remove = function(id, callback) {
      if (Object.isString(id)) id = new ObjectId(id);
      if (id instanceof ObjectId) {
        id = {
          _id: id
        };
      }
      logger.silly(id);
      this.model.remove(id, callback);
    };

    API.del = API.remove;

    API.one = function(id, fieldsToReturn, dbOptions, callback) {
      return this._one(id, fieldsToReturn, dbOptions, callback);
    };

    API._one = function(id, fieldsToReturn, dbOptions, callback) {
      if (Object.isString(id)) id = new ObjectId(id);
      if (id instanceof ObjectId) {
        id = {
          _id: id
        };
      }
      if (Object.isFunction(fieldsToReturn)) {
        callback = fieldsToReturn;
        fieldsToReturn = {};
        dbOptions = {
          safe: true
        };
      }
      if (Object.isFunction(dbOptions)) {
        callback = dbOptions;
        dbOptions = {
          safe: true
        };
      }
      this.model.findOne(id, fieldsToReturn, dbOptions, callback);
    };

    API.get = function(options, fieldsToReturn, callback) {
      var query;
      if (Object.isFunction(fieldsToReturn)) {
        callback = fieldsToReturn;
        fieldsToReturn = {};
      }
      query = this.optionParser(options);
      query.fields(fieldsToReturn);
      logger.silly(fieldsToReturn);
      logger.debug(query);
      query.exec(callback);
    };

    API.bulkInsert = function(docs, options, callback) {
      this.model.collection.insert(docs, options, callback);
    };

    API.getByEntity = function(entityType, entityId, id, fields, callback) {
      if (Object.isFunction(fields)) {
        callback = fields;
        this.model.findOne({
          _id: id,
          'entity.type': entityType,
          'entity.id': entityId
        }, callback);
      } else {
        this.model.findOne({
          _id: id,
          'entity.type': entityType,
          'entity.id': entityId
        }, fields, callback);
      }
    };

    API.createTransaction = function(state, action, data, direction, entity) {
      var transaction;
      if ((entity != null) && Object.isString(entity.id)) {
        entity.id = new ObjectId(entity.id);
      }
      transaction = {
        _id: new ObjectId(),
        id: new ObjectId(),
        state: state,
        action: action,
        error: {},
        dates: {
          created: new Date(),
          lastModified: new Date()
        },
        data: data,
        direction: direction,
        entity: entity != null ? entity : void 0
      };
      return transaction;
    };

    API.moveTransactionToLog = function(id, transaction, callback) {
      var $pull, $push, $query, $update;
      if (Object.isString(id)) id = new ObjectId(id);
      $query = {
        _id: id,
        "transactions.ids": transaction.id
      };
      $push = {
        "transactions.log": transaction
      };
      $pull = {
        "transactions.temp": {
          id: transaction.id
        }
      };
      $update = {
        $push: $push,
        $pull: $pull
      };
      return this.model.collection.findAndModify($query, [], $update, {
        safe: true,
        "new": true
      }, callback);
    };

    API.removeTransaction = function(documentId, transactionId, callback) {
      var $update;
      if (Object.isString(documentId)) documentId = new ObjectId(documentId);
      if (Object.isString(transactionId)) {
        transactionId = new ObjectId(transactionId);
      }
      $update = {
        "$pull": {
          "transactions.log": {
            id: transactionId
          }
        }
      };
      return this.model.collection.update({
        "_id": documentId
      }, $update, {
        safe: true,
        multi: true
      }, function(error, count) {
        if (error != null) logger.error(error);
        return callback(error, count);
      });
    };

    API.removeTransactionInvolvement = function(transactionId, callback) {
      var $update;
      if (Object.isString(transactionId)) {
        transactionId = new ObjectId(transactionId);
      }
      $update = {
        "$pull": {
          "transactions.ids": transactionId
        }
      };
      return this.model.collection.update({
        "transactions.ids": transactionId
      }, $update, {
        safe: true,
        multi: true
      }, function(error, count) {
        if (error != null) logger.error(error);
        return callback(error, count);
      });
    };

    API.__setTransactionPending = function(id, transactionId, locking, callback) {
      var $query, $set;
      if (Object.isString(id)) id = new ObjectId(id);
      if (Object.isString(transactionId)) {
        transactionId = new ObjectId(transactionId);
      }
      $query = {
        _id: id,
        "transactions.log": {
          $elemMatch: {
            "id": transactionId,
            "state": {
              $nin: [choices.transactions.states.PENDING, choices.transactions.states.PROCESSING, choices.transactions.states.PROCESSED, choices.transactions.states.ERROR]
            }
          }
        }
      };
      $set = {
        "transactions.log.$.state": choices.transactions.states.PENDING,
        "transactions.log.$.dates.lastModified": new Date(),
        "transactions.locked": locked
      };
      if (locking === true) {
        $set["transactions.state"] = choices.transactions.states.PENDING;
      }
      return this.model.collection.findAndModify($query, [], {
        $set: $set
      }, {
        "new": true,
        safe: true
      }, callback);
    };

    API.__setTransactionProcessing = function(id, transactionId, locking, callback) {
      var $inc, $query, $set;
      if (Object.isString(id)) id = new ObjectId(id);
      if (Object.isString(transactionId)) {
        transactionId = new ObjectId(transactionId);
      }
      $query = {
        _id: id,
        "transactions.log": {
          $elemMatch: {
            "id": transactionId,
            "state": {
              $nin: [choices.transactions.states.PROCESSED, choices.transactions.states.ERROR]
            }
          }
        }
      };
      $set = {
        "transactions.log.$.state": choices.transactions.states.PROCESSING,
        "transactions.log.$.dates.lastModified": new Date()
      };
      $inc = {
        "transactions.log.$.attempts": 1
      };
      if (locking === true) {
        $set["transactions.state"] = choices.transactions.states.PROCESSING;
      }
      return this.model.collection.findAndModify($query, [], {
        $set: $set,
        $inc: $inc
      }, {
        "new": true,
        safe: true
      }, callback);
    };

    API.__setTransactionProcessed = function(id, transactionId, locking, removeLock, modifierDoc, callback) {
      var $query, $set, $update;
      if (Object.isString(id)) id = new ObjectId(id);
      if (Object.isString(transactionId)) {
        transactionId = new ObjectId(transactionId);
      }
      $query = {
        _id: id,
        "transactions.log": {
          $elemMatch: {
            "id": transactionId,
            "state": {
              $nin: [choices.transactions.states.PROCESSED, choices.transactions.states.ERROR]
            }
          }
        }
      };
      $set = {
        "transactions.log.$.state": choices.transactions.states.PROCESSED,
        "transactions.log.$.dates.lastModified": new Date(),
        "transactions.log.$.dates.completed": new Date()
      };
      if (locking === true) {
        $set["transactions.state"] = choices.transactions.states.PROCESSED;
      }
      if (removeLock === true) $set["transactions.locked"] = false;
      $update = {};
      $update.$set = {};
      Object.merge($update, modifierDoc);
      Object.merge($update.$set, $set);
      return this.model.collection.findAndModify($query, [], $update, {
        "new": true,
        safe: true
      }, function(error, doc) {
        return callback(error, doc);
      });
    };

    API.__setTransactionError = function(id, transactionId, locking, removeLock, errorObj, modifierDoc, callback) {
      var $query, $set, $update;
      if (Object.isString(id)) id = new ObjectId(id);
      if (Object.isString(transactionId)) {
        transactionId = new ObjectId(transactionId);
      }
      $query = {
        _id: id,
        "transactions.log": {
          $elemMatch: {
            "id": transactionId,
            "state": {
              $nin: [choices.transactions.states.PROCESSED, choices.transactions.states.ERROR]
            }
          }
        }
      };
      $set = {
        "transactions.log.$.state": choices.transactions.states.ERROR,
        "transactions.log.$.dates.lastModified": new Date(),
        "transactions.log.$.dates.completed": new Date(),
        "transactions.log.$.error": errorObj
      };
      if (locking === true) {
        $set["transactions.state"] = choices.transactions.states.ERROR;
      }
      if (removeLock === true) $set["transactions.locked"] = false;
      $update = {};
      $update.$set = {};
      Object.merge($update, modifierDoc);
      Object.merge($update.$set, $set);
      logger.debug($update);
      return this.model.collection.findAndModify($query, [], $update, {
        "new": true,
        safe: true
      }, callback);
    };

    API.checkIfTransactionExists = function(id, transactionId, callback) {
      var $query;
      if (Object.isString(id)) id = new ObjectId(id);
      if (Object.isString(transactionId)) {
        transactionId = new ObjectId(transactionId);
      }
      $query = {
        _id: id,
        "transactions.ids": transactionId
      };
      return this.model.findOne($query, callback);
    };

    return API;

  })();

  DBTransactions = (function(_super) {

    __extends(DBTransactions, _super);

    function DBTransactions() {
      DBTransactions.__super__.constructor.apply(this, arguments);
    }

    DBTransactions.model = DBTransaction;

    return DBTransactions;

  })(API);

  Sequences = (function(_super) {

    __extends(Sequences, _super);

    function Sequences() {
      Sequences.__super__.constructor.apply(this, arguments);
    }

    Sequences.model = Sequence;

    Sequences.current = function(key, callback) {
      var $fields;
      $fields = {};
      $fields[key] = 1;
      return this.model.collection.findOne({
        _id: new ObjectId(0)
      }, {
        fields: $fields
      }, function(error, doc) {
        if (error != null) {
          return callback(error);
        } else if (!(doc != null)) {
          return callback({
            "sequence": "could not find sequence document"
          });
        } else {
          return callback(null, doc[key]);
        }
      });
    };

    Sequences.next = function(key, count, callback) {
      var $fields, $inc, $update;
      if (Object.isFunction(count)) {
        callback = count;
        count = 1;
      }
      $inc = {};
      $inc[key] = count;
      $update = {
        $inc: $inc
      };
      $fields = {};
      $fields[key] = 1;
      return this.model.collection.findAndModify({
        _id: new ObjectId(0)
      }, [], $update, {
        "new": true,
        safe: true,
        fields: $fields,
        upsert: true
      }, function(error, doc) {
        if (error != null) {
          return callback(error);
        } else if (!(doc != null)) {
          return callback({
            "sequence": "could not find sequence document"
          });
        } else {
          return callback(null, doc[key]);
        }
      });
    };

    return Sequences;

  })(API);

  RedemptionLogs = (function(_super) {

    __extends(RedemptionLogs, _super);

    function RedemptionLogs() {
      RedemptionLogs.__super__.constructor.apply(this, arguments);
    }

    RedemptionLogs.model = RedemptionLog;

    RedemptionLogs.byBusiness = function(bid, options, callback) {
      var $query;
      if (Object.isString(bid)) bid = new ObjectId(bid);
      if (Object.isFunction(options)) {
        callback = options;
        options = {};
      }
      $query = {
        "org.id": bid
      };
      if (options["dates.redeemed"] != null) {
        $query["dates.redeemed"] = options["dates.redeemed"];
      }
      return this.model.collection.find($query, options, function(error, cursor) {
        if (error != null) return callback(error);
        if (options.count) {
          return cursor.count(callback);
        } else {
          return cursor.toArray(callback);
        }
      });
    };

    RedemptionLogs.add = function(consumer, org, locationId, registerId, goody, dateRedeemed, transactionId, callback) {
      var doc;
      try {
        if (Object.isString(consumer.id)) consumer.id = new ObjectId(consumer.id);
        if (Object.isString(org.id)) org.id = new ObjectId(org.id);
        if (Object.isString(locationId)) locationId = new ObjectId(locationId);
        if (Object.isString(registerId)) registerId = new ObjectId(registerId);
      } catch (error) {
        logger.error(error);
        callback(error);
        return;
      }
      doc = {
        _id: transactionId,
        consumer: consumer,
        org: org,
        locationId: locationId,
        registerId: registerId,
        goody: {
          id: goody._id,
          name: goody.name,
          karmaPointsRequired: goody.karmaPointsRequired
        },
        dates: {
          created: new Date(),
          redeemed: dateRedeemed
        },
        transactions: {
          ids: [transactionId]
        }
      };
      return this.model.collection.insert(doc, {
        safe: true
      }, function(error, logEntry) {
        if (error != null) {
          logger.error(error);
          cb(error);
          return;
        }
        callback(error, logEntry);
      });
    };

    return RedemptionLogs;

  })(API);

  Users = (function(_super) {

    __extends(Users, _super);

    function Users() {
      Users.__super__.constructor.apply(this, arguments);
    }

    Users._sendFacebookPicToTransloadit = function(entityId, screenName, guid, picURL, callback) {
      var client, fields, params;
      logger.debug("TRANSLOADIT - send fbpic - " + "notifyURL:" + config.transloadit.notifyURL + ",guid:" + guid + ",picURL:" + picURL + ",entityId:" + entityId);
      client = new transloadit(config.transloadit.authKey, config.transloadit.authSecret);
      params = {
        auth: {
          key: config.transloadit.authKey
        },
        notify_url: config.transloadit.notifyURL,
        template_id: config.transloadit.consumerFromURLTemplateId,
        steps: {
          ':original': {
            robot: '/http/import',
            url: picURL
          },
          export85: {
            path: "consumers/" + entityId + "-85.png"
          },
          export128: {
            path: "consumers/" + entityId + "-128.png"
          },
          export85Secure: {
            path: "consumers-secure/" + screenName + "-85.png"
          },
          export128Secure: {
            path: "consumers-secure/" + screenName + "-128.png"
          }
        }
      };
      fields = {
        mediaFor: "consumer",
        entityId: entityId.toString(),
        guid: guid
      };
      client.send(params, fields, function(success) {
        logger.debug("Transloadit Response - " + success);
        if (callback != null) callback(null, true);
      }, function(error) {
        logger.error(new errors.TransloaditError('Transloadit error on facebook login, updating profile picture', error));
        if (callback != null) callback(error);
      });
    };

    Users._updatePasswordHelper = function(id, password, callback) {
      var self;
      self = this;
      return this.encryptPassword(password, function(error, hash) {
        if (error != null) {
          callback(new errors.ValidationError("Invalid Password", {
            "password": "Invalid Password"
          }));
          return;
        }
        password = hash;
        self.update(id, {
          password: hash
        }, callback);
      });
    };

    Users.one = function(id, fieldsToReturn, dbOptions, callback) {
      if (Object.isString(id)) id = new ObjectId(id);
      if (id instanceof ObjectId) {
        id = {
          _id: id
        };
      }
      if (Object.isFunction(fieldsToReturn && !(fieldsToReturn != null))) {
        callback(new errors.ValidationError({
          "fieldsToReturn": "fieldsToReturn",
          "Database error, fields must always be specified.": "Database error, fields must always be specified."
        }));
        dbOptions = {
          safe: true
        };
        return;
      }
      if (Object.isFunction(dbOptions)) {
        callback = dbOptions;
        dbOptions = {};
      }
      this.model.findOne(id, fieldsToReturn, dbOptions, callback);
    };

    Users.update = function(id, doc, dbOptions, callback) {
      var where;
      if (Object.isString(id)) id = new ObjectId(id);
      if (Object.isFunction(dbOptions)) {
        callback = dbOptions;
        dbOptions = {
          safe: true
        };
      }
      where = {
        _id: id
      };
      this.model.update(where, doc, dbOptions, callback);
    };

    Users.encryptPassword = function(password, callback) {
      var _this = this;
      bcrypt.gen_salt(10, function(error, salt) {
        if (error != null) {
          callback(error);
          return;
        }
        bcrypt.encrypt(password + defaults.passwordSalt, salt, function(error, hash) {
          if (error != null) {
            callback(error);
            return;
          }
          callback(null, hash);
        });
      });
    };

    Users.validatePassword = function(id, password, callback) {
      var query;
      if (Object.isString(id)) id = new ObjectId(id);
      query = this._query();
      query.where('_id', id);
      query.fields(['password']);
      return query.findOne(function(error, user) {
        if (error != null) {
          callback(error, user);
        } else if (user != null) {
          return bcrypt.compare(password + defaults.passwordSalt, user.password, function(error, valid) {
            if (error != null) {
              callback(error);
            } else {
              if (valid) {
                callback(null, true);
              } else {
                callback(null, false);
              }
            }
          });
        } else {
          callback(new errors.ValidationError("Invalid id", {
            "id": "invalid"
          }));
        }
      });
    };

    Users.login = function(email, password, fieldsToReturn, callback) {
      var addedPasswordToFields, query;
      if (Object.isFunction(fieldsToReturn)) {
        callback = fieldsToReturn;
        fieldsToReturn = {};
      }
      if (!Object.isEmpty(fieldsToReturn || fieldsToReturn.password !== 1)) {
        fieldsToReturn.password = 1;
        addedPasswordToFields = true;
      }
      if (!(fieldsToReturn.facebook != null) || fieldsToReturn["facebook.id"] !== 1) {
        fieldsToReturn["facebook.id"] = 1;
      }
      query = this._query();
      query.where('email', email);
      query.fields(fieldsToReturn);
      return query.findOne(function(error, consumer) {
        if (error != null) {
          callback(error, consumer);
        } else if (consumer != null) {
          return bcrypt.compare(password + defaults.passwordSalt, consumer.password, function(error, success) {
            if ((error != null) || !success) {
              callback(new errors.ValidationError("Invalid Password", {
                "login": "invalid password"
              }));
            } else {
              delete consumer._doc.password;
              callback(null, consumer);
            }
          });
        } else {
          callback(new errors.ValidationError("Invalid Email Address", {
            "login": "invalid email address"
          }));
        }
      });
    };

    Users.getByEmail = function(email, fieldsToReturn, callback) {
      var query;
      if (Object.isFunction(fieldsToReturn)) {
        callback = fieldsToReturn;
        fieldsToReturn = {};
      }
      query = this._query();
      query.where('email', email);
      query.fields(fieldsToReturn);
      query.findOne(function(error, user) {
        if (error != null) {
          callback(error);
        } else {
          callback(null, user);
        }
      });
    };

    Users.updateWithPassword = function(id, password, data, callback) {
      var self;
      self = this;
      if (Object.isString(id) != null) id = new ObjectId(id);
      this.validatePassword(id, password, function(error, success) {
        var e;
        if (error != null) {
          logger.error(error);
          e = new errors.ValidationError({
            "Invalid password, unable to save.": "Invalid password, unable to save.",
            "password": "Unable to validate password"
          });
          callback(e);
          return;
        } else if (!success) {
          e = new errors.ValidationError("Incorrect password.", {
            "password": "Incorrect Password"
          });
          callback(e);
          return;
        }
        return async.series({
          encryptPassword: function(cb) {
            if (data.password != null) {
              return self.encryptPassword(data.password, function(error, hash) {
                if (error != null) {
                  callback(new errors.ValidationError("Invalid password, unable to save.", {
                    "password": "Unable to encrypt password"
                  }));
                  cb(error);
                } else {
                  data.password = hash;
                  cb(null);
                }
              });
            } else {
              cb(null);
            }
          },
          updateDb: function(cb) {
            var query;
            query = self._query();
            query.where('_id', id);
            query.findOne(function(error, client) {
              var set;
              if (error != null) {
                callback(error);
                cb(error);
              } else if (client != null) {
                set = data;
                self.update(id, {
                  $set: set
                }, callback);
              } else {
                e = new errors.ValidationError("Incorrect password.", {
                  'password': "Incorrect Password"
                });
                callback(e);
                cb(e);
              }
            });
          }
        }, function(error, results) {});
      });
    };

    Users.updateWithFacebookAuthNonce = function(id, facebookAccessToken, facebookAuthNonce, data, callback) {
      var options, self, url;
      self = this;
      url = '/oauth/access_token_info';
      options = {
        client_id: config.facebook.appId
      };
      fb.get(url, facebookAccessToken, options, function(error, accessTokenInfo) {
        var set;
        if (accessTokenInfo.auth_nonce !== facebookAuthNonce) {
          callback(new errors.ValidationError('Facebook authentication errors.', {
            'Auth Nonce': 'Incorrect.'
          }));
        } else {
          set = data;
          self.update(id, {
            $set: set
          }, callback);
        }
      });
    };

    Users.updateMedia = function(id, media, callback) {
      var self;
      self = this;
      Medias.validateAndGetMediaURLs("consumer", id, "consumer", media, function(error, validatedMedia) {
        var mediaToReturn, update;
        if (error != null) {
          callback(error);
          return;
        }
        logger.silly(validatedMedia);
        update = {};
        if (!(validatedMedia != null)) {
          mediaToReturn = null;
          update.$unset = {
            media: 1
          };
        } else {
          mediaToReturn = validatedMedia;
          update.$set = {
            media: validatedMedia
          };
        }
        self.update(id, update, function(error, count) {
          if (error != null) {
            callback(error);
            return;
          }
          if (count === 0) {
            callback(new errors.ValidationError({
              "id": "Consumer Id not found."
            }));
          } else {
            callback(null, mediaToReturn);
          }
        });
      });
    };

    Users.updateMediaWithFacebook = function(id, screenName, fbid, callback) {
      var accessToken, self;
      self = this;
      if (Object.isString(id)) id = new ObjectId(id);
      accessToken = "";
      async.series({
        accessToken: function(callback) {
          return self.model.findById(id, {
            "facebook.access_token": 1
          }, function(error, user) {
            if (error != null) {
              callback(error);
              return;
            }
            accessToken = user.facebook.access_token;
            callback(null, accessToken);
          });
        },
        fbPicURL: function(callback) {
          return fb.get(["me/picture"], accessToken, function(error, fbData) {
            var fbPicURL, i, picResponse, v, _len, _ref;
            if (error != null) {
              callback(error);
              return;
            }
            picResponse = fbData[0];
            if (picResponse.headers[5].name === "Location") {
              fbPicURL = picResponse.headers[5].value;
            } else {
              _ref = picResponse.headers;
              for (v = 0, _len = _ref.length; v < _len; v++) {
                i = _ref[v];
                if (v.name === "Location") fbPicURL = v.value;
              }
            }
            if (!(fbPicURL != null) || fb.isDefaultProfilePic(fbPicURL, fbid)) {
              callback(new errors.ValidationError({
                "pic": "Since you have no facebook picture, we left your picture as the default goodybag picture."
              }));
              return;
            }
            callback(null, fbPicURL);
          });
        }
      }, function(error, data) {
        var guid, media, set;
        if (error != null) {
          callback(error);
          return;
        }
        guid = guidGen.v1();
        media = {
          guid: guid,
          thumb: data.fbPicURL,
          url: data.fbPicURL,
          mediaId: null
        };
        set = {
          media: media,
          "facebook.pic": data.fbPicURL
        };
        return self.update({
          _id: id
        }, {
          $set: set
        }, function(error, success) {
          if (error != null) {
            callback(error);
            return;
          }
          self._sendFacebookPicToTransloadit(id, screenName, guid, data.fbPicURL, function(error, success) {
            if (error != null) {
              callback(error);
            } else {
              callback(null, media);
            }
          });
        });
      });
    };

    Users.updateMediaByGuid = function(id, guid, mediasDoc, callback) {
      var query, set;
      if (Object.isString(id)) id = new ObjectId(id);
      query = this._query();
      query.where("_id", id);
      query.where("media.guid", guid);
      set = {
        media: Medias.mediaFieldsForType(mediasDoc, "consumer"),
        secureMedia: Medias.mediaFieldsForType(mediasDoc, "consumer-secure")
      };
      query.update({
        $set: set
      }, function(error, success) {
        if (error != null) {
          callback(error);
        } else {
          callback(null, success);
        }
      });
    };

    Users.delMedia = function(id, callback) {
      if (Object.isString(id)) id = new ObjectId(id);
      this.model.update({
        _id: id
      }, {
        $set: {
          "permissions.media": false
        },
        $unset: {
          media: 1,
          secureMedia: 1,
          "facebook.pic": 1
        }
      }, callback);
    };

    Users.updateEmailRequest = function(id, password, newEmail, callback) {
      var data;
      logger.debug("###### ID ######");
      logger.debug(id);
      this.getByEmail(newEmail, function(error, user) {
        if (error != null) {
          callback(error);
          return;
        }
        if (user != null) {
          if (id === user._id) {
            callback(new errors.ValidationError("That is your current email", {
              "email": "That is your current email"
            }));
          } else {
            callback(new errors.ValidationError("Another user is already using this email", {
              "email": "Another user is already using this email"
            }));
          }
        }
      });
      data = {};
      data.changeEmail = {
        newEmail: newEmail,
        key: hashlib.md5(config.secretWord + newEmail + (new Date().toString())) + '-' + generatePassword(12, false, /\d/),
        expirationDate: Date.create("next week")
      };
      this.updateWithPassword(id, password, data, function(error, count) {
        if (count === 0) {
          callback(new errors.ValidationError({
            "password": "Incorrect password."
          }));
          return;
        }
        callback(error, data.changeEmail);
      });
    };

    Users.updateFBEmailRequest = function(id, facebookAccessToken, facebookAuthNonce, newEmail, callback) {
      var data;
      this.getByEmail(newEmail, function(error, user) {
        if (error != null) {
          callback(error);
          return;
        }
        if (user != null) {
          if (id === user._id) {
            callback(new errors.ValidationError("That is your current email", {
              "email": "That is your current email"
            }));
          } else {
            callback(new errors.ValidationError("Another user is already using this email", {
              "email": "Another user is already using this email"
            }));
          }
        }
      });
      data = {};
      data.changeEmail = {
        newEmail: newEmail,
        key: hashlib.md5(config.secretWord + newEmail + (new Date().toString())) + '-' + generatePassword(12, false, /\d/),
        expirationDate: Date.create("next week")
      };
      this.updateWithFacebookAuthNonce(id, facebookAccessToken, facebookAuthNonce, data, function(error, count) {
        if (error) callback(error);
        callback(error, data.changeEmail);
      });
    };

    Users.updateEmailComplete = function(key, callback) {
      var query;
      query = this._query();
      query.where('changeEmail.key', key);
      query.fields("changeEmail");
      query.findOne(function(error, user) {
        if (error != null) {
          callback(error);
          return;
        }
        if (!(user != null)) {
          callback(new errors.ValidationError({
            "key": "Invalid key, expired or already used."
          }));
          return;
        }
        user = user._doc;
        if (new Date() > user.changeEmail.expirationDate) {
          callback(new errors.ValidationError({
            "key": "Key expired."
          }));
          query.update({
            $set: {
              changeEmail: null
            }
          }, function(error, success) {});
          return;
        }
        query.update({
          $set: {
            email: user.changeEmail.newEmail,
            changeEmail: null
          }
        }, function(error, count) {
          if (error != null) {
            if (errors.code === 11000 || errors.code === 11001) {
              callback(new errors.ValidationError("Email Already Exists", {
                "email": "Email Already Exists"
              }));
            } else {
              callback(error);
            }
            return;
          }
          callback(null, user.changeEmail.newEmail);
        });
      });
    };

    return Users;

  })(API);

  Consumers = (function(_super) {

    __extends(Consumers, _super);

    function Consumers() {
      Consumers.__super__.constructor.apply(this, arguments);
    }

    Consumers.model = Consumer;

    Consumers.initialUpdate = function(entity, data, callback) {
      var $pushAll, $query, $update, affiliationId, btTransaction, fieldsToReturn, set, statTransaction, transactionData;
      if (Object.isString(entity.id)) entity.id = new ObjectId(entity.id);
      set = {};
      if (!utils.isBlank(data.barcodeId)) {
        logger.silly("addBarcodeId");
        set.barcodeId = data.barcodeId;
      }
      if (!utils.isBlank(data.affiliationId)) {
        logger.silly("addAffil");
        affiliationId = new ObjectId(affiliationId);
        set["profile.affiliations"] = [data.affiliationId];
      }
      if (utils.isBlank(data.screenName)) {
        callback(new errors.ValidationError("Alias is required.", {
          "screenName": "required"
        }));
        return;
      } else {
        logger.silly("addScreenName");
        set.screenName = data.screenName;
        set.setScreenName = true;
      }
      if (Object.isEmpty(set)) {
        callback(new errors.ValidationError("Nothing to update..", {
          "update": "required"
        }));
        return;
      }
      entity.screenName = data.screenName;
      $pushAll = {};
      if (set.barcodeId != null) {
        transactionData = {};
        btTransaction = this.createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.BT_BARCODE_CLAIMED, transactionData, choices.transactions.directions.OUTBOUND, entity);
        statTransaction = this.createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.STAT_BARCODE_CLAIMED, transactionData, choices.transactions.directions.OUTBOUND, entity);
        $pushAll = {
          "transactions.ids": [btTransaction.id, statTransaction.id],
          "transactions.log": [btTransaction, statTransaction]
        };
      }
      $update = {
        $pushAll: $pushAll,
        $set: set
      };
      $query = {
        _id: entity.id,
        setScreenName: false
      };
      if (set.barcodeId != null) {
        $query.barcodeId = {
          $ne: set.barcodeId
        };
      }
      fieldsToReturn = {
        _id: 1,
        barcodeId: 1
      };
      this.model.collection.findAndModify($query, [], $update, {
        safe: true,
        fields: fieldsToReturn,
        "new": true
      }, function(error, consumer) {
        var success;
        if (error != null) {
          if (error.code === 11000 || error.code === 11001) {
            if (error.message.indexOf("barcodeId")) {
              callback(new errors.ValidationError("Sorry, that TapIn Id is already taken.", {
                "TapIn Id": "not unique"
              }));
            } else {
              callback(new errors.ValidationError("Sorry, that Alias is already taken.", {
                "screenName": "not unique"
              }));
            }
            return;
          }
          callback(error);
          return;
        } else if (!(consumer != null)) {
          callback(new errors.ValidationError("This is already your TapIn code, or you've already set your alias", {
            "barcodeId": "this is already your tapIn code",
            "screenname": "already set"
          }));
          return;
        }
        if (set.barcodeId != null) {
          tp.process(consumer, btTransaction);
          tp.process(consumer, statTransaction);
        }
        success = consumer != null ? true : false;
        return callback(null, success);
      });
    };

    Consumers.getIdsAndScreenNames = function(options, callback) {
      var query;
      if (Object.isFunction(options)) {
        callback = options;
        options = {};
      }
      query = this.query();
      query.only("_id", "screenName", "setScreenName");
      query.skip(options.skip || 0);
      query.limit(options.limit || 25);
      return query.exec(callback);
    };

    Consumers.getScreenNamesByIds = function(ids, callback) {
      var query;
      query = this.query();
      query.only(["_id", "screenName", "setScreenName"]);
      query["in"]("_id", ids);
      query.exec(callback);
    };

    /* _getByBarcodeId_
    */

    Consumers.getByBarcodeId = function(barcodeId, fields, callback) {
      var $query;
      if (Object.isFunction(fields)) {
        callback = fields;
        fields = null;
      }
      $query = {
        $or: [
          {
            barcodeId: barcodeId
          }, {
            "updateVerification.data.barcodeId": barcodeId,
            "updateVerification.expiration": {
              $gt: new Date()
            }
          }
        ]
      };
      return this.model.collection.findOne($query, fields, function(error, consumer) {
        if (error != null) {
          callback(error);
          return;
        }
        callback(null, consumer);
      });
    };

    /* _findByBarcodeIds_
    */

    Consumers.findByBarcodeIds = function(barcodeIds, fields, callback) {
      var $query;
      if (Object.isFunction(fields)) {
        callback = fields;
        fields = null;
      }
      $query = {
        barcodeId: {
          $in: barcodeIds
        }
      };
      return this.model.collection.find($query, fields, function(error, cursor) {
        if (error != null) {
          callback(error);
          return;
        }
        return cursor.toArray(function(error, consumers) {
          callback(null, consumers);
        });
      });
    };

    Consumers.getByEmail = function(email, fields, callback) {
      var $query;
      if (Object.isFunction(fields)) {
        callback = fields;
        fields = null;
      }
      $query = {
        email: email
      };
      return this.model.collection.findOne($query, {
        fields: fields
      }, function(error, consumer) {
        if (error != null) {
          callback(error);
          return;
        }
        callback(null, consumer);
      });
    };

    Consumers.updateBarcodeId = function(entity, barcodeId, callback) {
      var $pushAll, $query, $set, $update, btTransaction, fieldsToReturn, statTransaction, transactionData;
      if (Object.isString(entity.id)) entity.id = new ObjectId(entity.id);
      if (!(barcodeId != null)) {
        callback(null, false);
        return;
      }
      $query = {
        _id: entity.id,
        barcodeId: {
          $ne: barcodeId
        }
      };
      transactionData = {};
      btTransaction = this.createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.BT_BARCODE_CLAIMED, transactionData, choices.transactions.directions.OUTBOUND, entity);
      statTransaction = this.createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.STAT_BARCODE_CLAIMED, transactionData, choices.transactions.directions.OUTBOUND, entity);
      $set = {
        barcodeId: barcodeId
      };
      $pushAll = {
        "transactions.ids": [btTransaction.id, statTransaction.id],
        "transactions.log": [btTransaction, statTransaction]
      };
      $update = {
        $pushAll: $pushAll,
        $set: $set
      };
      fieldsToReturn = {
        _id: 1,
        barcodeId: 1
      };
      this.model.collection.findAndModify($query, [], $update, {
        safe: true,
        fields: fieldsToReturn,
        "new": true
      }, function(error, consumer) {
        var success;
        if (error != null) {
          if (error.code === 11000 || error.code === 11001) {
            callback(new errors.ValidationError("TapIn code is already in use", {
              "barcodeId": "tapIn code is already in use"
            }));
            return;
          }
          callback(error);
          return;
        } else if (!(consumer != null)) {
          callback(new errors.ValidationError("This is already your TapIn code", {
            "barcodeId": "this is already your tapIn code"
          }));
          return;
        }
        tp.process(consumer, btTransaction);
        tp.process(consumer, statTransaction);
        success = consumer != null ? true : false;
        return callback(null, success);
      });
    };

    Consumers.claimBarcodeId = function(entity, barcodeId, callback) {
      var $pushAll, $query, $set, $update, btTransaction, fieldsToReturn, statTransaction, transactionData;
      if (Object.isString(entity.id)) entity.id = new ObjectId(entity.id);
      if (!(barcodeId != null)) {
        callback(null, false);
        return;
      }
      $query = {
        _id: entity.id
      };
      transactionData = {};
      btTransaction = this.createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.BT_BARCODE_CLAIMED, transactionData, choices.transactions.directions.OUTBOUND, entity);
      statTransaction = this.createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.STAT_BARCODE_CLAIMED, transactionData, choices.transactions.directions.OUTBOUND, entity);
      $set = {
        barcodeId: barcodeId
      };
      $pushAll = {
        "transactions.ids": [btTransaction.id, statTransaction.id],
        "transactions.log": [btTransaction, statTransaction]
      };
      $update = {
        $pushAll: $pushAll,
        $set: $set
      };
      fieldsToReturn = {
        _id: 1,
        barcodeId: 1
      };
      this.model.collection.findAndModify($query, [], $update, {
        safe: true,
        fields: fieldsToReturn,
        "new": true
      }, function(error, consumer) {
        var success;
        if (error != null) {
          callback(error);
          return;
        } else if (!(consumer != null)) {
          callback(new errors.ValidationError("Consumer with that identifer doesn't exist"));
          return;
        }
        tp.process(consumer, btTransaction);
        tp.process(consumer, statTransaction);
        success = consumer != null ? true : false;
        return callback(null, success);
      });
    };

    /*
      # acceptable parameters
      # uid, value, callback
      # uid, accessToken, value, callback
    */

    Consumers.updateTapinsToFacebook = function(uid, accessToken, value, callback) {
      var _this = this;
      if (Object.isBoolean(accessToken)) {
        callback = value;
        value = accessToken;
      }
      if (!(value != null)) {
        callback(null, false);
        return;
      }
      if (value === true) {
        if (!(accessToken != null)) {
          callback({
            message: "There was not enough information from facebook to complete this request"
          });
          return;
        }
        logger.silly("attempting to save tapIns To Facebook");
        return fb.get('me/permissions', accessToken, function(error, response) {
          var permissions;
          permissions = response.data[0];
          logger.debug(permissions);
          if (error != null) {
            callback({
              message: "Sorry, it seems facebook isn't responding right now, please try again in a short while."
            });
          } else if ((permissions != null) && permissions.publish_stream === 1 && permissions.offline_access === 1) {
            logger.silly("Permissions are good. Saving tapIns to Facebook value");
            return _this.update(uid, {
              tapinsToFacebook: true,
              "facebook.access_token": accessToken
            }, function(error, count) {
              if (error != null) {
                callback(error);
                return;
              }
              callback(null, count);
            });
          } else {
            callback({
              message: "Not Enough Permissions"
            });
          }
        });
      } else {
        logger.silly("attempting to no longer saving tapIns To Facebook");
        return this.update(uid, {
          tapinsToFacebook: false
        }, function(error, count) {
          if (error != null) {
            callback(error);
            return;
          }
          callback(null, count);
        });
      }
    };

    Consumers.register = function(data, fieldsToReturn, callback) {
      var self;
      self = this;
      data.aliasId = new ObjectId();
      this.encryptPassword(data.password, function(error, hash) {
        if (error != null) {
          callback(new errors.ValidationError("Invalid Password", {
            "password": "Invalid Password"
          }));
          return;
        } else {
          data.password = hash;
          data.referralCodes = {};
          Sequences.next('urlShortner', 2, function(error, sequence) {
            var tapInCode, userCode;
            if (error != null) {
              callback(error);
              return;
            }
            tapInCode = urlShortner.encode(sequence - 1);
            userCode = urlShortner.encode(sequence);
            data.referralCodes.tapIn = tapInCode;
            data.referralCodes.user = userCode;
            return self.add(data, function(error, consumer) {
              var entity;
              if (error != null) {
                if (error.code === 11000 || error.code === 11001) {
                  callback(new errors.ValidationError("Email Already Exists", {
                    "email": "Email Already Exists"
                  }));
                } else {
                  callback(error);
                }
              } else {
                entity = {
                  type: choices.entities.CONSUMER,
                  id: consumer._doc._id
                };
                Referrals.addUserLink(entity, "/", userCode);
                Referrals.addTapInLink(entity, "/", tapInCode);
                consumer = self._copyFields(consumer, fieldsToReturn);
                callback(error, consumer);
              }
            });
          });
          return;
        }
      });
    };

    /* _registerPendingAndClaim_
    */

    Consumers.registerAsPendingAndClaim = function(data, fields, callback) {
      if (Object.isFunction(fields)) {
        callback = fields;
        fields = null;
      }
      data.signUpVerification = {};
      data.signUpVerification.key = hashlib.md5(data.email) + "|" + uuid.v4();
      data.signUpVerification.expiration = Date.create().addYears(1);
      return this.register(data, fields, function(error, consumer) {
        var entity;
        if (error != null) {
          callback(error);
          return;
        }
        callback(null, consumer);
        entity = {
          id: consumer._id,
          name: "" + consumer.firstName + " " + consumer.lastName,
          screenName: consumer.screenName
        };
        return Consumers.claimBarcodeId(entity, consumer.barcodeId, function(error) {
          if (error != null) return logger.error(error);
        });
      });
    };

    /* _tapInUpdateData_
    */

    Consumers.tapInUpdateData = function(id, data, fields, callback) {
      var $set;
      if (Object.isFunction(fields)) {
        callback = fields;
        fields = null;
      }
      if (Object.isString(id)) id = new ObjectId(id);
      $set = {};
      $set.updateVerification = {
        key: id.toString() + "|" + uuid.v4(),
        expiration: Date.create().addWeeks(2),
        data: {}
      };
      if (data.charity != null) {
        $set.updateVerification.data.charity = data.charity;
      }
      if (data.barcodeId != null) {
        $set.updateVerification.data.barcodeId = data.barcodeId;
      }
      return this.model.collection.findAndModify({
        _id: id
      }, [], {
        $set: $set
      }, {
        fields: fields,
        "new": true,
        safe: true
      }, function(error, consumer) {
        if (error != null) {
          logger.error;
          callback({
            name: "DatabaseError",
            message: "Unable to update the consumer"
          });
          return;
        }
        return callback(null, consumer);
      });
    };

    Consumers.getFacebookData = function(accessToken, callback) {
      var urls;
      urls = ["app", "me", "me/picture"];
      return fb.get(urls, accessToken, function(error, data) {
        var appResponse, facebookData, fbPicURL, fbid, i, meResponse, picResponse, v, _len, _ref;
        if (error != null) {
          callback(error);
          return;
        }
        appResponse = data[0];
        meResponse = data[1];
        picResponse = data[2];
        if (appResponse.code !== 200) {
          callback(new errors.HttpError('Error connecting with Facebook, try again later.', 'facebookBatch:' + urls[0], appResponse.code));
          return;
        }
        logger.silly("#####################################");
        logger.silly(JSON.parse(appResponse.body).id);
        logger.silly(config.facebook.appId);
        logger.silly("%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%");
        if (JSON.parse(appResponse.body).id !== config.facebook.appId) {
          return callback(new errors.ValidationError({
            'accessToken': "Incorrect access token. Not for Goodybag's app."
          }));
        }
        if (meResponse.code !== 200) {
          callback(new errors.HttpError('Error connecting with Facebook, try again later.', 'facebookBatch:' + urls[1], appResponse.code));
          return;
        }
        if (picResponse.code !== 302 && picResponse.code !== 200 && picResponse.code !== 301) {
          callback(new errors.HttpError('Error connecting with Facebook, try again later.', 'facebookBatch:' + urls[1], appResponse.code));
          return;
        }
        meResponse.body = JSON.parse(meResponse.body);
        fbid = meResponse.body.id;
        if (picResponse.headers[5].name === "Location") {
          fbPicURL = picResponse.headers[5].value;
        } else {
          _ref = picResponse.headers;
          for (v = 0, _len = _ref.length; v < _len; v++) {
            i = _ref[v];
            if (v.name === "Location") fbPicURL = v.value;
          }
        }
        facebookData = {
          me: meResponse.body,
          pic: !(fbPicURL != null) || fb.isDefaultProfilePic(fbPicURL, fbid) ? null : fbPicURL
        };
        return callback(null, facebookData);
      });
    };

    Consumers.facebookLogin = function(accessToken, fieldsToReturn, referralCode, callback) {
      var createOrUpdateUser, self, urls;
      if (Object.isFunction(fieldsToReturn)) {
        callback = fieldsToReturn;
        fieldsToReturn = {};
      }
      self = this;
      accessToken = accessToken.split("&")[0];
      urls = ["app", "me", "me/picture"];
      fb.get(urls, accessToken, function(error, data) {
        var appResponse, facebookData, fbPicURL, fbid, i, meResponse, picResponse, v, _len, _ref;
        if (error != null) {
          callback(error);
          return;
        }
        appResponse = data[0];
        meResponse = data[1];
        picResponse = data[2];
        if (appResponse.code !== 200) {
          callback(new errors.HttpError('Error connecting with Facebook, try again later.', 'facebookBatch:' + urls[0], appResponse.code));
          return;
        }
        if (JSON.parse(appResponse.body).id !== config.facebook.appId) {
          callback(new errors.ValidationError({
            'accessToken': "Incorrect access token. Not for Goodybag's app."
          }));
        }
        if (meResponse.code !== 200) {
          callback(new errors.HttpError('Error connecting with Facebook, try again later.', 'facebookBatch:' + urls[1], appResponse.code));
          return;
        }
        if (picResponse.code !== 302 && picResponse.code !== 200 && picResponse.code !== 301) {
          callback(new errors.HttpError('Error connecting with Facebook, try again later.', 'facebookBatch:' + urls[1], appResponse.code));
          return;
        }
        meResponse.body = JSON.parse(meResponse.body);
        fbid = meResponse.body.id;
        if (picResponse.headers[5].name === "Location") {
          fbPicURL = picResponse.headers[5].value;
        } else {
          _ref = picResponse.headers;
          for (v = 0, _len = _ref.length; v < _len; v++) {
            i = _ref[v];
            if (v.name === "Location") fbPicURL = v.value;
          }
        }
        facebookData = {
          me: meResponse.body,
          pic: !(fbPicURL != null) || fb.isDefaultProfilePic(fbPicURL, fbid) ? null : fbPicURL
        };
        createOrUpdateUser(facebookData);
      });
      createOrUpdateUser = function(facebookData) {
        var consumer, fbid;
        fbid = facebookData.me.id;
        consumer = {
          firstName: facebookData.me.first_name,
          lastName: facebookData.me.last_name
        };
        consumer['facebook.access_token'] = accessToken;
        consumer['facebook.id'] = facebookData.me.id;
        consumer['facebook.me'] = facebookData.me;
        if (facebookData.pic != null) consumer['facebook.pic'] = facebookData.pic;
        consumer['profile.birthday'] = facebookData.me.birthday != null ? utils.setDateToUTC(facebookData.me.birthday) : void 0;
        consumer['profile.gender'] = facebookData.me.gender;
        consumer['profile.location'] = facebookData.me.location != null ? facebookData.me.location.name : void 0;
        consumer['profile.hometown'] = facebookData.me.hometown != null ? facebookData.me.hometown.name : void 0;
        return self.model.findOne({
          $or: [
            {
              "facebook.id": facebookData.me.id
            }, {
              email: facebookData.me.email
            }
          ]
        }, {
          _id: 1,
          "permissions.media": 1,
          "facebook.fbid": 1,
          "facebook.pic": 1
        }, null, function(error, consumerAlreadyRegistered) {
          var callTransloadit, facebookPicFound, facebookPicIsNew, mediaGuid, mediaPermission;
          if (error != null) {
            callback(error);
          } else {
            callTransloadit = false;
            if (consumerAlreadyRegistered != null) {
              consumerAlreadyRegistered = consumerAlreadyRegistered._doc;
              mediaPermission = consumerAlreadyRegistered.permissions.media;
              facebookPicFound = facebookData.pic != null;
              facebookPicIsNew = consumerAlreadyRegistered.facebook.pic !== facebookData.pic;
              if (mediaPermission && facebookPicFound && facebookPicIsNew) {
                mediaGuid = guidGen.v1();
                consumer.media = {
                  guid: mediaGuid,
                  url: facebookData.pic,
                  thumb: facebookData.pic,
                  mediaId: null
                };
                callTransloadit = true;
              }
              self.model.collection.findAndModify({
                $or: [
                  {
                    "facebook.id": facebookData.me.id
                  }, {
                    email: facebookData.me.email
                  }
                ]
              }, [], {
                $set: consumer,
                $inc: {
                  loginCount: 1
                }
              }, {
                fields: fieldsToReturn,
                "new": true,
                safe: true
              }, function(error, consumerToReturn) {
                callback(error, consumerToReturn);
                if (callTransloadit && !(error != null)) {
                  self._sendFacebookPicToTransloadit(consumerToReturn._id, consumerToReturn.screenName, mediaGuid, facebookData.pic);
                }
              });
            } else {
              consumer.password = hashlib.md5(config.secretWord + facebookData.me.email + (new Date().toString())) + '-' + generatePassword(12, false, /\d/);
              consumer.screenName = new ObjectId();
              self.encryptPassword(consumer.password, function(error, hash) {
                if (error != null) {
                  callback(new errors.ValidationError("Invalid Password", {
                    "password": "Invalid Password"
                  }));
                  return;
                }
                consumer.password = hash;
                consumer.email = facebookData.me.email;
                consumer.facebook = {};
                consumer.facebook.access_token = accessToken;
                consumer.facebook.id = facebookData.me.id;
                if (facebookData.pic != null) {
                  mediaGuid = guidGen.v1();
                  consumer.media = {
                    guid: mediaGuid,
                    url: facebookData.pic,
                    thumb: facebookData.pic,
                    mediaId: null
                  };
                  callTransloadit = true;
                }
                consumer.referralCodes = {};
                Sequences.next('urlShortner', 2, function(error, sequence) {
                  var newUserModel, tapInCode, userCode;
                  if (error != null) {
                    callback(error);
                    return;
                  }
                  tapInCode = urlShortner.encode(sequence - 1);
                  userCode = urlShortner.encode(sequence);
                  consumer.referralCodes.tapIn = tapInCode;
                  consumer.referralCodes.user = userCode;
                  newUserModel = new self.model(consumer);
                  newUserModel.save(function(error, newUser) {
                    var entity, newUserFields;
                    if (error != null) {
                      callback(error);
                    } else {
                      newUserFields = self._copyFields(newUser, fieldsToReturn);
                      callback(null, newUserFields);
                      entity = {
                        type: choices.entities.CONSUMER,
                        id: newUser._id
                      };
                      Referrals.addUserLink(entity, "/", userCode);
                      Referrals.addTapInLink(entity, "/", tapInCode);
                      if (!utils.isBlank(referralCode)) {
                        Referrals.signUp(referralCode, entity);
                      }
                      if (callTransloadit) {
                        self._sendFacebookPicToTransloadit(newUser._id, newUser.screenName, mediaGuid, facebookData.pic);
                      }
                    }
                  });
                });
              });
            }
          }
        });
      };
    };

    Consumers.getProfile = function(id, callback) {
      var facebookMeFields, fieldsToReturn;
      fieldsToReturn = {
        _id: 1,
        firstName: 1,
        lastName: 1,
        email: 1,
        profile: 1,
        permissions: 1,
        transactions: 1
      };
      fieldsToReturn["facebook.id"] = 1;
      facebookMeFields = {
        work: 1,
        education: 1
      };
      Object.merge(fieldsToReturn, this._flattenDoc(facebookMeFields, "facebook.me"));
      this.one(id, fieldsToReturn, function(error, consumer) {
        if (error != null) {
          callback(error);
          return;
        }
        callback(null, consumer);
      });
    };

    Consumers.getPublicProfile = function(id, callback) {
      var facebookMeFields, fieldsToReturn, self;
      self = this;
      fieldsToReturn = {
        _id: 1,
        firstName: 1,
        lastName: 1,
        email: 1,
        profile: 1,
        permissions: 1,
        media: 1
      };
      fieldsToReturn["facebook.id"] = 1;
      facebookMeFields = {
        work: 1,
        education: 1
      };
      Object.merge(fieldsToReturn, this._flattenDoc(facebookMeFields, "facebook.me"));
      this.one(id, fieldsToReturn, function(error, consumer) {
        var facebookFieldItems, field, i, idsToRemove, item, _len, _ref, _ref2;
        if (error != null) {
          callback(error);
          return;
        }
        if (!consumer.permissions.email) delete consumer.email;
        consumer.profile = self._copyFields(consumer.profile, consumer.permissions);
        consumer.facebook = self._copyFields(consumer.facebook, consumer.permissions);
        _ref = consumer.permissions.hiddenFacebookItems;
        for (field in _ref) {
          idsToRemove = _ref[field];
          if ((idsToRemove != null) && idsToRemove.length > 0) {
            facebookFieldItems = consumer.facebook[field];
            for (item = 0, _len = facebookFieldItems.length; item < _len; item++) {
              i = facebookFieldItems[item];
              if ((_ref2 = item.id, __indexOf.call(idsToRemove, _ref2) >= 0)) {
                facebookFieldItems.splice(i, 1);
                break;
              }
            }
          }
        }
        callback(null, consumer);
      });
    };

    Consumers.updateHonorScore = function(id, eventId, amount, callback) {
      if (Object.isString(id)) id = new ObjectId(id);
      if (Object.isString(eventId)) eventId = new ObjectId(eventId);
      return this.model.findAndModify({
        _id: id
      }, [], {
        $push: {
          "events.ids": eventId
        },
        $inc: {
          honorScore: amount
        }
      }, {
        "new": true,
        safe: true
      }, callback);
    };

    Consumers.deductFunds = function(id, transactionId, amount, callback) {
      if (isNaN(amount)) {
        callback({
          message: "amount is not a number"
        });
        return;
      }
      amount = parseInt(amount);
      if (amount < 0) {
        callback({
          message: "amount cannot be negative"
        });
        return;
      }
      if (Object.isString(id)) id = new ObjectId(id);
      if (Object.isString(transactionId)) {
        transactionId = new ObjectId(transactionId);
      }
      return this.model.collection.findAndModify({
        _id: id,
        'funds.remaining': {
          $gte: amount
        },
        'transactions.ids': {
          $ne: transactionId
        }
      }, [], {
        $addToSet: {
          "transactions.ids": transactionId
        },
        $inc: {
          'funds.remaining': -1 * amount
        }
      }, {
        "new": true,
        safe: true
      }, callback);
    };

    Consumers.incrementDonated = function(id, transactionId, amount, callback) {
      logger.debug("incrementing donated");
      if (isNaN(amount)) {
        callback({
          message: "amount is not a number"
        });
        return;
      }
      amount = parseInt(amount);
      if (amount <= 0) {
        callback({
          message: "amount cannot be zero or negative"
        });
        return;
      }
      if (Object.isString(id)) id = new ObjectId(id);
      if (Object.isString(transactionId)) {
        transactionId = new ObjectId(transactionId);
      }
      logger.debug("attempting to increment donated for " + id + " by: " + amount);
      return this.model.collection.findAndModify({
        _id: id,
        'transactions.ids': {
          $ne: transactionId
        }
      }, [], {
        $addToSet: {
          "transactions.ids": transactionId
        },
        $inc: {
          'funds.donated': amount
        }
      }, {
        "new": true,
        safe: true
      }, callback);
    };

    Consumers.depositFunds = function(id, transactionId, amount, callback) {
      if (isNaN(amount)) {
        callback({
          message: "amount is not a number"
        });
        return;
      }
      amount = parseInt(amount);
      if (amount < 0) {
        callback({
          message: "amount cannot be negative"
        });
        return;
      }
      if (Object.isString(id)) id = new ObjectId(id);
      if (Object.isString(transactionId)) {
        transactionId = new ObjectId(transactionId);
      }
      return this.model.collection.findAndModify({
        _id: id,
        'transactions.ids': {
          $ne: transactionId
        }
      }, [], {
        $addToSet: {
          "transactions.ids": transactionId
        },
        $inc: {
          'funds.remaining': amount,
          'funds.allocated': amount
        }
      }, {
        "new": true,
        safe: true
      }, callback);
    };

    Consumers.updatePermissions = function(id, data, callback) {
      var consumerModel, doc, k, permission, permissionsKeys, pull, push, set, v, where;
      if (Object.isString(id)) id = new ObjectId(id);
      if (!(data != null) && Object.keys(data).length > 1) {
        callback(new errors.ValidationError({
          "permissions": "You can only update one permission at a time"
        }));
        return;
      }
      where = {
        _id: id
      };
      set = {};
      push = {};
      pull = {};
      consumerModel = new this.model;
      permissionsKeys = Object.keys(consumerModel._doc.permissions);
      permissionsKeys.remove("hiddenFacebookItems");
      for (k in data) {
        v = data[k];
        permission = "permissions." + k;
        if (!(__indexOf.call(permissionsKeys, k) >= 0)) {
          callback(new errors.ValidationError({
            "permissionKey": "Unknown value."
          }));
          return;
        }
      }
      set[permission] = v === "true" || v === true;
      doc = {};
      if (!Object.isEmpty(set)) {
        doc["$set"] = set;
      } else {
        callback(new errors.ValidationError({
          "data": "No new updates."
        }));
        return;
      }
      this.model.update(where, doc, {
        safe: true
      }, callback);
    };

    Consumers.updateHiddenFacebookItems = function(id, data, callback) {
      var doc, entry, facebookItemKeys, fbid, pull, push, where;
      if (Object.isString(id)) id = new ObjectId(id);
      if (!(data != null)) {
        callback(new errors.ValidationError({
          "data": "No update data."
        }));
        return;
      }
      if (Object.keys(data).length > 1) {
        callback(new errors.ValidationError({
          "entry": "You can only update one entry at a time"
        }));
        return;
      }
      where = {
        _id: id
      };
      push = {};
      pull = {};
      facebookItemKeys = ["work", "education"];
      for (entry in data) {
        fbid = data[entry];
        if (!(__indexOf.call(facebookItemKeys, entry) >= 0)) {
          callback(new errors.ValidationError({
            "facebookItemKey": "Unknown value (" + entry + ")."
          }));
          return;
        }
        if (Object.isString(fbid)) {
          if (fbid.substr(0, 1) === "-") {
            fbid = fbid.slice(1);
            where["permissions.hiddenFacebookItems." + entry] = fbid;
            pull["permissions.hiddenFacebookItems." + entry] = fbid;
          } else {
            if (entry === "work") {
              where["facebook.me.work.employer.id"] = fbid;
            } else if (entry === "education") {
              where["facebook.me.education.school.id"] = fbid;
            }
            push["permissions.hiddenFacebookItems." + entry] = fbid;
          }
        } else {
          callback(new errors.ValidationError({
            "fbid": "Invalid value (must be a string)."
          }));
          return;
        }
      }
      doc = {};
      if (!Object.isEmpty(push)) {
        doc["$push"] = push;
      } else if (!Object.isEmpty(pull)) {
        doc["$pull"] = pull;
      } else {
        callback(new errors.ValidationError({
          "data": "No new updates."
        }));
        return;
      }
      this.model.update(where, doc, {
        safe: true
      }, callback);
    };

    Consumers.addRemoveWork = function(op, id, data, callback) {
      var doc, where;
      if (Object.isString(id)) id = new ObjectId(id);
      if (op === "add") {
        where = {
          _id: id,
          "profile.work.name": {
            $ne: data.name
          }
        };
        doc = {
          $push: {
            "profile.work": data
          }
        };
      } else if (op === "remove") {
        where = {
          _id: id
        };
        doc = {
          $pull: {
            "profile.work": data
          }
        };
      } else {
        callback(new errors.ValidationError({
          "op": "Invalid value."
        }));
        return;
      }
      this.model.update(where, doc, function(error, success) {
        if (success === 0) {
          callback(new errors.ValidationError("Whoops, looks like you already added that company.", {
            "name": "Company with that name already added."
          }));
        } else {
          callback(error, success);
        }
      });
    };

    Consumers.addRemoveEducation = function(op, id, data, callback) {
      var doc, where;
      if (Object.isString(id)) id = new ObjectId(id);
      if (op === "add") {
        where = {
          _id: id,
          "profile.education.name": {
            $ne: data.name
          }
        };
        doc = {
          $push: {
            "profile.education": data
          }
        };
      } else if (op === "remove") {
        where = {
          _id: id
        };
        doc = {
          $pull: {
            "profile.education": data
          }
        };
      } else {
        callback(new errors.ValidationError({
          "op": "Invalid value."
        }));
        return;
      }
      this.model.update(where, doc, function(error, success) {
        if (success === 0) {
          callback(new errors.ValidationError("Whoops, looks like you already added that school.", {
            "name": "School with that name already added."
          }));
        } else {
          callback(error, success);
        }
      });
    };

    Consumers.addRemoveInterest = function(op, id, data, callback) {
      var doc, where;
      if (Object.isString(id)) id = new ObjectId(id);
      if (op === "add") {
        where = {
          _id: id,
          "profile.interests.name": {
            $ne: data.name
          }
        };
        doc = {
          $push: {
            "profile.interests": data
          }
        };
      } else if (op === "remove") {
        where = {
          _id: id
        };
        doc = {
          $pull: {
            "profile.interests": data
          }
        };
      } else {
        callback(new errors.ValidationError({
          "op": "Invalid value."
        }));
        return;
      }
      this.model.update(where, doc, function(error, success) {
        if (success === 0) {
          callback(new errors.ValidationError("Whoops, looks like you already added that interest.", {
            "name": "Interest already added."
          }));
        } else {
          callback(error, success);
        }
      });
    };

    Consumers.updateProfile = function(id, data, callback) {
      var consumerModel, key, nonFacebookProfileKeys, where;
      if (Object.isString(id)) id = new ObjectId(id);
      where = {
        _id: id
      };
      consumerModel = new this.model;
      nonFacebookProfileKeys = Object.keys(consumerModel._doc.permissions);
      nonFacebookProfileKeys.remove("aboutme");
      for (key in data) {
        if (__indexOf.call(nonFacebookProfileKeys, key) >= 0) {
          where["facebook.id"] = {
            $exists: false
          };
        }
      }
      data = this._flattenDoc(data, "profile");
      this.model.update(where, {
        $set: data
      }, function(error, count) {
        if (count === 0) {
          callback(new errors.ValidationError({
            "user": "Facebook User: to update your information edit your profile on facebook."
          }));
          return;
        }
        callback(error, count);
      });
    };

    Consumers.addRemoveAffiliation = function(op, id, affiliationId, callback) {
      var doc, where;
      if (Object.isString(id)) id = new ObjectId(id);
      if (Object.isString(affiliationId)) {
        affiliationId = new ObjectId(affiliationId);
      }
      if (op === "add") {
        where = {
          _id: id,
          "profile.affiliations": {
            $ne: affiliationId
          }
        };
        doc = {
          $set: {
            "profile.affiliations": [affiliationId]
          }
        };
      } else if (op === "remove") {
        where = {
          _id: id
        };
        doc = {
          $set: {
            "profile.affiliations": []
          }
        };
      } else {
        callback(new errors.ValidationError({
          "op": "Invalid value."
        }));
        return;
      }
      this.model.update(where, doc, function(error, success) {
        return callback(error, success);
      });
    };

    Consumers.addFunds = function(id, amount, callback) {
      var $update;
      amount = parseFloat(amount);
      if (isNaN(amount)) {
        callback({
          message: "amount is not a number"
        });
        return;
      } else if (amount < 0) {
        callback({
          message: "amount cannot be negative"
        });
        return;
      }
      amount = parseFloat(Math.abs(amount.toFixed(2)));
      $update = {
        $inc: {
          "funds.remaining": amount,
          "funds.allocated": amount
        }
      };
      return this.model.collection.update({
        _id: id
      }, $update, {
        safe: true
      }, callback);
    };

    Consumers.setTransactonPending = Consumers.__setTransactionPending;

    Consumers.setTransactionProcessing = Consumers.__setTransactionProcessing;

    Consumers.setTransactionProcessed = Consumers.__setTransactionProcessed;

    Consumers.setTransactionError = Consumers.__setTransactionError;

    return Consumers;

  })(Users);

  Clients = (function(_super) {

    __extends(Clients, _super);

    function Clients() {
      Clients.__super__.constructor.apply(this, arguments);
    }

    Clients.model = Client;

    Clients._updatePasswordHelper = function(id, password, callback) {
      var self;
      self = this;
      return this.encryptPassword(password, function(error, hash) {
        if (error != null) {
          callback(new errors.ValidationError("Invalid Password", {
            "password": "Invalid Password"
          }));
          return;
        }
        password = hash;
        self.update(id, {
          password: hash
        }, callback);
      });
    };

    Clients.updateIdentity = function(id, data, callback) {
      var entityType, self;
      self = this;
      logger.silly(id);
      if (Object.isString(id)) id = new ObjectId(id);
      entityType = "client";
      Medias.validateAndGetMediaURLs(entityType, id, "client", data.media, function(error, validatedMedia) {
        var updateDoc;
        if (error != null) {
          callback(error);
          return;
        }
        updateDoc = {};
        if (!(validatedMedia != null)) {
          delete data.media;
        } else {
          data.media = validatedMedia;
        }
        updateDoc.$set = data;
        logger.silly(data);
        self.model.collection.findAndModify({
          _id: id
        }, [], updateDoc, {
          safe: true
        }, callback);
      });
    };

    Clients.register = function(data, fieldsToReturn, callback) {
      var self;
      self = this;
      data.screenName = new ObjectId();
      this.encryptPassword(data.password, function(error, hash) {
        if (error != null) {
          callback(new errors.ValidationError("Invalid Password", {
            "password": "Invalid Password"
          }));
          return;
        } else {
          data.password = hash;
          data.referralCodes = {};
          Sequences.next('urlShortner', 2, function(error, sequence) {
            var tapInCode, userCode;
            if (error != null) {
              callback(error);
              return;
            }
            tapInCode = urlShortner.encode(sequence - 1);
            userCode = urlShortner.encode(sequence);
            data.referralCodes.tapIn = tapInCode;
            data.referralCodes.user = userCode;
            return self.add(data, function(error, client) {
              if (error != null) {
                if (error.code === 11000 || error.code === 11001) {
                  callback(new errors.ValidationError("Email Already Exists", {
                    "email": "Email Already Exists"
                  }));
                } else {
                  callback(error);
                }
              } else {
                client = self._copyFields(client, fieldsToReturn);
                callback(error, client);
              }
            });
          });
          return;
        }
      });
    };

    Clients.validatePassword = function(id, password, callback) {
      var query;
      if (Object.isString(id)) id = new ObjectId(id);
      query = this._query();
      query.where('_id', id);
      query.fields(['password']);
      return query.findOne(function(error, client) {
        if (error != null) {
          callback(error, client);
        } else if (client != null) {
          return bcrypt.compare(password + defaults.passwordSalt, client.password, function(error, valid) {
            if (error != null) {
              callback(error);
            } else {
              if (valid) {
                callback(null, true);
              } else {
                callback(null, false);
              }
            }
          });
        } else {
          callback(new error.ValidationError("Invalid id", {
            "id": "id",
            "invalid": "invalid"
          }));
        }
      });
    };

    Clients.encryptPassword = function(password, callback) {
      var _this = this;
      return bcrypt.gen_salt(10, function(error, salt) {
        if (error != null) {
          callback(error);
          return;
        }
        return bcrypt.encrypt(password + defaults.passwordSalt, salt, function(error, hash) {
          if (error != null) {
            callback(error);
            return;
          }
          callback(null, hash);
        });
      });
    };

    Clients.register = function(data, callback) {
      var self;
      self = this;
      return this.encryptPassword(data.password, function(error, hash) {
        if (error != null) {
          callback(new errors.ValidationError("Invalid Password", {
            "password": "Invalid Password"
          }));
        } else {
          data.password = hash;
          return self.add(data, function(error, client) {
            if (error != null) {
              if (error.code === 11000 || error.code === 11001) {
                callback(new errors.ValidationError("Email Already Exists", {
                  "email": "Email Already Exists"
                }));
              } else {
                callback(error);
              }
            } else {
              callback(error, client);
            }
          });
        }
      });
    };

    Clients.login = function(email, password, callback) {
      var query;
      query = this._query();
      query.where('email', email);
      return query.findOne(function(error, client) {
        if (error != null) {
          callback(error, client);
        } else if (client != null) {
          return bcrypt.compare(password + defaults.passwordSalt, client.password, function(error, success) {
            if ((error != null) || !success) {
              callback(new errors.ValidationError("Incorrect Password.", {
                "login": "passwordincorrect"
              }));
            } else {
              callback(error, client);
            }
          });
        } else {
          callback(new errors.ValidationError("Email address not found.", {
            "login": "emailnotfound"
          }));
        }
      });
    };

    Clients.getBusinessIds = function(id, callback) {
      var query;
      query = Businesses.model.find();
      query.only('_id');
      query.where('clients', id);
      return query.exec(function(error, businesses) {
        var business, ids, _i, _len;
        if (error != null) {
          return callback(error, null);
        } else {
          ids = [];
          for (_i = 0, _len = businesses.length; _i < _len; _i++) {
            business = businesses[_i];
            ids.push(business.id);
          }
          return callback(null, ids);
        }
      });
    };

    Clients.getByEmail = function(email, fieldsToReturn, callback) {
      var query;
      if (Object.isFunction(fieldsToReturn)) {
        callback = fieldsToReturn;
        fieldsToReturn = {};
      }
      query = this._query();
      query.where('email', email);
      query.fields(fieldsToReturn);
      query.findOne(function(error, user) {
        if (error != null) {
          callback(error);
        } else {
          callback(null, user);
        }
      });
    };

    Clients.updateMediaByGuid = function(id, guid, mediasDoc, callback) {
      var query, set;
      if (Object.isString(id)) id = new ObjectId(id);
      query = this._query();
      query.where("_id", id);
      query.where("media.guid", guid);
      set = {
        media: Medias.mediaFieldsForType(mediasDoc, "client")
      };
      set["media.guid"] = data.guid;
      query.update({
        $set: set
      }, function(error, success) {
        if (error != null) {
          callback(error);
        } else {
          callback(null, success);
        }
      });
    };

    Clients.updateEmail = function(id, password, newEmail, callback) {
      if (Object.isString(id)) id = new ObjectId(id);
      return async.parallel({
        validatePassword: function(cb) {
          return Clients.validatePassword(id, password, function(error, success) {
            var e;
            if (error != null) {
              e = new errors.ValidationError("Unable to validate password", {
                "password": "Unable to validate password"
              });
              callback(e);
              cb(e);
            } else {
              if (!success) {
                e = new errors.ValidationError("Incorrect Password.", {
                  "password": "Incorrect Password"
                });
                callback(e);
                cb(e);
              } else {
                cb(null);
              }
            }
          });
        },
        checkExists: function(cb) {
          return Clients.getByEmail(newEmail, function(error, client) {
            var e;
            if (error != null) {
              callback(error);
              cb(error);
            } else if (client != null) {
              if (client._id === id) {
                e = new errors.ValidationError("That is your current email", {
                  "email": "That is your current email"
                });
                callback(e);
                cb(e);
              } else {
                e = new errors.ValidationError("Another user is already using this email", {
                  "email": "Another user is already using this email"
                });
                callback(e);
                cb(e);
              }
            } else {
              cb(null);
            }
          });
        }
      }, function(error, results) {
        var key, query, set;
        if (error != null) return;
        query = Clients._query();
        query.where("_id", id);
        key = hashlib.md5(config.secretWord + newEmail + (new Date().toString())) + '-' + generatePassword(12, false, /\d/);
        set = {
          changeEmail: {
            newEmail: newEmail,
            key: key,
            expirationDate: Date.create("next week")
          }
        };
        return query.update({
          $set: set
        }, function(error, success) {
          if (error != null) {
            if (error.code === 11000 || error.code === 11001) {
              callback(new errors.ValidationError("Email Already Exists", {
                "email": "Email Already Exists"
              }));
            } else {
              callback(error);
            }
          } else if (!success) {
            callback(new errors.ValidationError("User Not Found", {
              "user": "User Not Found"
            }));
          } else {
            callback(null, key);
          }
        });
      });
    };

    Clients.updateEmailComplete = function(key, email, callback) {
      var query;
      query = this._query();
      query.where('changeEmail.key', key);
      query.where('changeEmail.newEmail', email);
      return query.update({
        $set: {
          email: email
        },
        $unset: {
          changeEmail: 1
        }
      }, function(error, success) {
        if (error != null) {
          if (error.code === 11000 || error.code === 11001) {
            callback(new errors.ValidationError("Email Already Exists", {
              "email": "Email Already Exists"
            }));
          } else {
            callback(error);
          }
          return;
        }
        if (success === 0) {
          callback("Invalid key, expired or already used.", new errors.ValidationError({
            "key": "Invalid key, expired or already used."
          }));
          return;
        }
        callback(null, success);
      });
    };

    Clients.updateWithPassword = function(id, password, data, callback) {
      if (Object.isString(id) != null) id = new ObjectId(id);
      this.validatePassword(id, password, function(error, success) {
        var e;
        if (error != null) {
          logger.error(error);
          e = new errors.ValidationError({
            "password": "Unable to validate password"
          });
          callback(e);
          return;
        } else if (!(success != null)) {
          e = new errors.ValidationError({
            "password": "Invalid Password"
          });
          callback(e);
          return;
        }
        return async.series({
          encryptPassword: function(cb) {
            if (data.password != null) {
              return Clients.encryptPassword(data.password, function(error, hash) {
                if (error != null) {
                  callback(new errors.ValidationError("Invalid Password", {
                    "password": "Invalid Password"
                  }));
                  cb(error);
                } else {
                  data.password = hash;
                  cb(null);
                }
              });
            } else {
              cb(null);
            }
          },
          updateDb: function(cb) {
            var query;
            query = Clients._query();
            query.where('_id', id);
            query.findOne(function(error, client) {
              var k, v;
              if (error != null) {
                callback(error);
                cb(error);
              } else if (client != null) {
                for (k in data) {
                  if (!__hasProp.call(data, k)) continue;
                  v = data[k];
                  client[k] = v;
                }
                client.save(callback);
                cb(null);
              } else {
                e = new errors.ValidationError({
                  'password': "Wrong Password"
                });
                callback(e);
                cb(e);
              }
            });
          }
        }, function(error, results) {});
      });
    };

    Clients.updatePassword = function(id, password, callback) {
      var options, query, update;
      if (Object.isString(id)) id = new ObjectId(id);
      query = {
        _id: id
      };
      update = {
        $set: {
          password: password
        }
      };
      options = {
        remove: false,
        "new": true,
        upsert: false
      };
      return this.model.collection.findAndModify(query, [], update, options, function(error, user) {
        if (error != null) {
          callback(error);
          return;
        }
        if (!(user != null)) {
          callback(new errors.ValidationError({
            "_id": "_id does not exist"
          }));
          return;
        }
        if (user != null) callback(error, user);
      });
    };

    Clients.setTransactonPending = Clients.__setTransactionPending;

    Clients.setTransactionProcessing = Clients.__setTransactionProcessing;

    Clients.setTransactionProcessed = Clients.__setTransactionProcessed;

    Clients.setTransactionError = Clients.__setTransactionError;

    return Clients;

  })(API);

  Businesses = (function(_super) {

    __extends(Businesses, _super);

    function Businesses() {
      Businesses.__super__.constructor.apply(this, arguments);
    }

    Businesses.model = Business;

    Businesses.optionParser = function(options, q) {
      var query;
      query = this._optionParser(options, q);
      if (options.deleted != null) {
        options.deleted = options.deleted;
      } else {
        options.deleted = false;
      }
      if (options.clientId != null) query["in"]('clients', [options.clientId]);
      query.where('deleted', options.deleted);
      if (options.tapins != null) query.where('locations.tapins', true);
      if (options.charity != null) query.where('isCharity', options.charity);
      if (options.equipped != null) query.where('gbEquipped', true);
      if (options.type != null) query.where('type', options.type);
      if ((options.alphabetical != null) && options.alphabetical === true) {
        query.sort('publicName', 1);
      }
      return query;
    };

    Businesses.updateSettings = function(id, pin, data, callback) {
      var $options, $query,
        _this = this;
      if (Object.isString(id)) id = new ObjectId(id);
      $query = {
        _id: id
      };
      $options = {
        remove: false,
        "new": true,
        upsert: false
      };
      Businesses.validatePin(id, pin, function(error) {
        var $update;
        if (error != null) {
          callback(error);
          return;
        }
        if (data.pin != null) {
          Businesses.encryptPin(data.pin, function(error, encrypted) {
            var $update;
            if (error != null) {
              callback(error);
              return;
            }
            data.pin = encrypted;
            $update = {
              $set: _this._flattenDoc(data)
            };
            return _this.model.collection.findAndModify($query, [], $update, $options, callback);
          });
        } else {
          $update = {
            $set: _this._flattenDoc(data)
          };
          _this.model.collection.findAndModify($query, [], $update, $options, callback);
        }
      });
    };

    Businesses.getMultiple = function(idArray, fieldsToReturn, callback) {
      var query;
      query = this.query();
      query["in"]("_id", idArray);
      query.fields(fieldsToReturn);
      query.find(callback);
    };

    Businesses.getOneEquipped = function(id, fieldsToReturn, callback) {
      var query;
      query = this._queryOne();
      return this.model.findOne({
        _id: id,
        'gbEquipped': true
      }, fieldsToReturn, callback);
    };

    Businesses.encryptPin = function(password, callback) {
      var _this = this;
      bcrypt.gen_salt(10, function(error, salt) {
        if (error != null) {
          callback(error);
          return;
        }
        bcrypt.encrypt(password + defaults.passwordSalt, salt, function(error, hash) {
          if (error != null) {
            callback(error);
            return;
          }
          callback(null, hash);
        });
      });
    };

    Businesses.updatePin = function(id, pin, callback) {
      var self;
      self = this;
      Businesses.encryptPin(pin, function(error, hash) {
        if (error != null) {
          callback(error);
          return;
        }
        Businesses.update(id, {
          pin: hash
        }, function(error, business) {
          if (error != null) {
            callback(error);
            return;
          }
          callback(null, business.pin);
        });
      });
    };

    Businesses.validatePin = function(id, pin, callback) {
      if (!(id != null) || !(pin != null)) {
        callback({
          message: "No arguments given"
        });
        return;
      }
      return Businesses.one(id, function(error, business) {
        if (error != null) {
          callback(error);
          return;
        }
        if (!(business != null)) {
          callback(error);
          return;
        }
        if (!(business.pin != null)) {
          return Businesses.updatePin(business._id, 'asdf', function(error, hash) {
            if (error != null) {
              callback(error);
              return;
            }
            return bcrypt.compare(pin + defaults.passwordSalt, hash, function(error, success) {
              if ((error != null) || !success) {
                callback(error);
                return;
              }
              callback(error, business);
            });
          });
        } else {
          return bcrypt.compare(pin + defaults.passwordSalt, business.pin, function(error, success) {
            if ((error != null) || !success) {
              callback(new errors.ValidationError("Validation Error", {
                "pin": "Invalid Pin"
              }));
              return;
            }
            callback(error, business);
          });
        }
      });
    };

    Businesses.add = function(clientId, data, callback) {
      var instance, k, v;
      instance = new this.model();
      for (k in data) {
        if (!__hasProp.call(data, k)) continue;
        v = data[k];
        instance[k] = v;
      }
      if ((data['locations'] != null) && data['locations'] !== []) {
        instance.markModified('locations');
      }
      if (!(data.pin != null)) instance.pin = "asdf";
      instance.cardCode = utils.randomPassword(6).toUpperCase();
      instance['clients'] = [clientId];
      instance['clientGroups'] = {};
      instance['clientGroups'][clientId] = choices.businesses.groups.OWNERS;
      instance['groups'][choices.businesses.groups.OWNERS] = [clientId];
      Businesses.encryptPin(instance.pin, function(error, hash) {
        if (error != null) {
          callback(error);
          return;
        }
        instance.pin = hash;
        return instance.save(callback);
      });
    };

    Businesses.addClient = function(id, clientId, groupName, callback) {
      var updateDoc;
      if (!(__indexOf.call(choices.businesses.groups._enum, groupName) >= 0)) {
        callback(new errors.ValidationError({
          "groupName": "Group does not Exist"
        }));
        return;
      }
      if (Object.isString(clientId)) clientId = new ObjectId(clientId);
      if (Object.isString(id)) id = new ObjectId(id);
      updateDoc = {};
      updateDoc['$addToSet'] = {};
      updateDoc['$addToSet']['clients'] = clientId;
      updateDoc['$addToSet']['groups.' + groupName] = clientId;
      updateDoc['$set'] = {};
      updateDoc['$set']['clientGroups.' + clientId] = groupName;
      this.model.collection.update({
        _id: id
      }, updateDoc, {
        safe: true
      }, callback);
    };

    Businesses.addManager = function(id, clientId, callback) {
      this.addClient(id, clientId, choices.businesses.groups.MANAGERS, callback);
    };

    Businesses.addOwner = function(id, clientId, callback) {
      this.addClient(id, clientId, choices.businesses.groups.OWNERS, callback);
    };

    Businesses.delClient = function(id, clientId, callback) {
      var self;
      self = this;
      if (Object.isString(clientId)) clientId = new ObjectId(clientId);
      if (Object.isString(id)) id = new ObjectId(id);
      this.one(id, function(error, business) {
        var group, updateDoc;
        if (error != null) {
          callback(error);
          return;
        } else {
          updateDoc = {};
          updateDoc['$pull'] = {};
          updateDoc['$pull']['clients'] = clientId;
          updateDoc['$unset'] = {};
          group = business.clientGroups[clientId];
          updateDoc['$pull']['groups.' + group] = clientId;
          updateDoc['$unset']['clientGroups.' + clientId] = 1;
          self.model.collection.update({
            _id: id
          }, updateDoc, callback);
        }
      });
    };

    Businesses.updateIsCharity = function(businessId, isCharity, callback) {
      var set;
      if (!(businessId != null) || businessId.length !== 24) {
        callback(new errors.ValidationError("Please select a business.", {
          "business": "invalid businessId"
        }));
        return;
      } else {
        if (Object.isString(businessId)) businessId = new ObjectId(businessId);
      }
      set = {
        isCharity: isCharity
      };
      this.model.collection.update({
        _id: businessId
      }, {
        $set: set
      }, {
        safe: true
      }, function(error, count) {
        if (error != null) {
          callback(error);
          return;
        }
        return callback(error, count > 0);
      });
    };

    Businesses.updateIdentity = function(id, data, callback) {
      var entityType, self;
      self = this;
      if (Object.isString(id)) id = new ObjectId(id);
      entityType = "business";
      Medias.validateAndGetMediaURLs(entityType, id, "business", data.media, function(error, validatedMedia) {
        var updateDoc;
        if (error != null) {
          callback(error);
          return;
        }
        updateDoc = {};
        if (!(validatedMedia != null)) {
          delete data.media;
        } else {
          data.media = validatedMedia;
        }
        updateDoc.$set = data;
        self.model.collection.update({
          _id: id
        }, updateDoc, {
          safe: true
        }, callback);
      });
    };

    Businesses.updateMediaByGuid = function(id, guid, mediasDoc, callback) {
      var query, set;
      if (Object.isString(id)) id = new ObjectId(id);
      query = this._query();
      query.where("_id", id);
      query.where("media.guid", guid);
      set = {
        media: Medias.mediaFieldsForType(mediasDoc, "business")
      };
      query.update({
        $set: set
      }, function(error, success) {
        if (error != null) {
          callback(error);
        } else {
          callback(null, success);
        }
      });
    };

    Businesses.addLocation = function(id, data, callback) {
      if (Object.isString(id)) id = new ObjectId(id);
      data._id = new ObjectId();
      return this.model.collection.update({
        _id: id
      }, {
        $push: {
          "locations": data
        }
      }, {
        safe: true
      }, function(error, count) {
        return callback(error, count, data._id);
      });
    };

    Businesses.updateLocation = function(id, locationId, data, callback) {
      if (Object.isString(id)) id = new ObjectId(id);
      if (Object.isString(locationId)) locationId = new ObjectId(locationId);
      data._id = locationId;
      return this.model.collection.update({
        _id: id,
        'locations._id': locationId
      }, {
        $set: {
          "locations.$": data
        }
      }, {
        safe: true
      }, callback);
    };

    Businesses.delLocations = function(id, locationIds, callback) {
      var $pull, locationId, objIds, self, _i, _len;
      objIds = [];
      self = this;
      if (Object.isArray(locationIds)) {
        for (_i = 0, _len = locationIds.length; _i < _len; _i++) {
          locationId = locationIds[_i];
          objIds.push(new ObjectId(locationId));
        }
      } else {
        objIds = [locationIds];
      }
      if (Object.isString(id)) id = new ObjectId(id);
      this.model.collection.findOne({
        _id: id
      }, {
        registers: 1,
        locRegister: 1
      }, function(err, results) {
        var $unset, location, register, _j, _k, _len2, _len3, _ref;
        if (err != null) {
          return callback(err, null);
        } else {
          $unset = {};
          for (_j = 0, _len2 = objIds.length; _j < _len2; _j++) {
            location = objIds[_j];
            if (results.locRegister[location] != null) {
              $unset["locRegister." + location] = 1;
            }
            _ref = results.locRegister[location];
            for (_k = 0, _len3 = _ref.length; _k < _len3; _k++) {
              register = _ref[_k];
              if (results.registers[register] != null) {
                $unset["registers." + register] = 1;
              }
            }
          }
          return self.model.collection.findAndModify({
            _id: id
          }, [], {
            $unset: $unset
          }, {
            safe: true
          }, function(err, response) {
            if (err != null) return callback(err, null);
          });
        }
      });
      $pull = {};
      $pull["locations"] = {
        _id: {
          $in: objIds
        }
      };
      $pull["registerData"] = {
        locationId: {
          $in: objIds
        }
      };
      return this.model.collection.update({
        _id: id
      }, {
        $pull: $pull
      }, {
        safe: true
      }, callback);
    };

    Businesses.getGroup = function(id, groupName, callback) {
      var data;
      data = {};
      data.groupName = groupName;
      return this.one(id, function(error, business) {
        var query, userId, userIds, _i, _len, _ref;
        if (error != null) {
          return callback(error, business);
        } else {
          userIds = [];
          _ref = business.groups[groupName];
          for (_i = 0, _len = _ref.length; _i < _len; _i++) {
            userId = _ref[_i];
            userIds.push(userId);
          }
          query = Client.find();
          query["in"]('_id', userIds);
          query.exclude(['created', 'password']);
          return query.exec(function(error, clients) {
            if (error != null) {
              return callback(error, null);
            } else {
              data.members = clients;
              return callback(null, data);
            }
          });
        }
      });
    };

    Businesses.getGroupPending = function(id, groupName, callback) {
      return ClientInvitations.list(id, groupName, callback);
    };

    Businesses.deductFunds = function(id, transactionId, amount, callback) {
      if (Object.isString(id)) id = new ObjectId(id);
      if (Object.isString(transactionId)) {
        transactionId = new ObjectId(transactionId);
      }
      return this.model.collection.findAndModify({
        _id: id,
        'funds.remaining': {
          $gte: amount
        },
        'transactions.ids': {
          $ne: transactionId
        }
      }, [], {
        $addToSet: {
          "transactions.ids": transactionId
        },
        $inc: {
          'funds.remaining': -1 * amount
        }
      }, {
        "new": true,
        safe: true
      }, callback);
    };

    Businesses.depositFunds = function(id, transactionId, amount, callback) {
      if (Object.isString(id)) id = new ObjectId(id);
      if (Object.isString(transactionId)) {
        transactionId = new ObjectId(transactionId);
      }
      return this.model.collection.findAndModify({
        _id: id,
        'transactions.ids': {
          $ne: transactionId
        }
      }, [], {
        $addToSet: {
          "transactions.ids": transactionId
        },
        $inc: {
          'funds.remaining': amount,
          'funds.allocated': amount
        }
      }, {
        "new": true,
        safe: true
      }, callback);
    };

    Businesses.listWithTapins = function(callback) {
      var query;
      query = this._query();
      query.where('locations.tapins', true);
      return query.exec(callback);
    };

    Businesses.addFunds = function(id, amount, callback) {
      var $update;
      amount = parseFloat(amount);
      if (amount < 0) {
        callback({
          message: "amount cannot be negative"
        });
        return;
      }
      $update = {
        $inc: {
          "funds.remaining": amount,
          "funds.allocated": amount
        }
      };
      return this.model.collection.update({
        _id: id
      }, $update, {
        safe: true
      }, callback);
    };

    Businesses.validateTransactionEntity = function(businessId, locationId, registerId, callback) {
      var query;
      if (Object.isString(businessId)) businessId = new ObjectId(businessId);
      if (Object.isString(locationId)) locationId = new ObjectId(locationId);
      if (Object.isString(registerId)) registerId = new ObjectId(registerId);
      query = {};
      query["_id"] = businessId;
      query["locRegister." + locationId] = registerId;
      query["registers." + registerId + ".locationId"] = locationId;
      return this.model.collection.findOne(query, {
        _id: 1,
        publicName: 1
      }, callback);
    };

    Businesses.addRegister = function(businessId, locationId, callback) {
      var registerId,
        _this = this;
      if (Object.isString(businessId)) businessId = new ObjectId(businessId);
      if (Object.isString(locationId)) locationId = new ObjectId(locationId);
      registerId = new ObjectId();
      return Sequences.next("register-setup-id", function(error, value) {
        var $push, $query, $set, $update;
        if (error != null) {
          callback(error);
          return;
        }
        $query = {
          _id: businessId
        };
        $set = {
          registers: {}
        };
        $push = {};
        $set.registers[registerId] = {};
        $set.registers[registerId].locationId = locationId;
        $set.registers[registerId].setupId = value;
        $push["registerData"] = {
          locationId: locationId,
          registerId: registerId,
          setupId: value
        };
        $push["locRegister." + locationId] = registerId;
        $set = API._flattenDoc($set);
        $update = {
          $set: $set,
          $push: $push
        };
        return _this.model.collection.findAndModify($query, [], $update, {
          safe: true
        }, function(error) {
          return callback(error, registerId);
        });
      });
    };

    Businesses.delRegister = function(businessId, locationId, registerId, callback) {
      var $pull, $query, $unset, $update;
      if (Object.isString(businessId)) businessId = new ObjectId(businessId);
      $query = {
        _id: businessId
      };
      $unset = {};
      $pull = {};
      $unset["registers." + registerId] = 1;
      $pull["locRegister." + locationId] = new ObjectId(registerId);
      $pull["registerData"] = {
        registerId: new ObjectId(registerId)
      };
      $update = {
        $unset: $unset,
        $pull: $pull
      };
      return this.model.collection.findAndModify($query, [], $update, {
        safe: true
      }, callback);
    };

    Businesses.isCharity = function(id, fields, callback) {
      if (Object.isString(id)) id = new ObjectId(id);
      return this.model.collection.findOne({
        _id: id,
        isCharity: true
      }, {
        fields: fields
      }, function(error, charity) {
        if (error != null) {
          callback(error);
          return;
        }
        return callback(null, charity);
      });
    };

    Businesses.getRandomCharity = function(fields, callback) {
      var _this = this;
      return this.model.collection.count({
        isCharity: true
      }, function(error, count) {
        var $opts;
        if (error != null) {
          callback(error);
          return;
        }
        if (count <= 0) {
          callback(null);
          return;
        }
        $opts = {
          fields: fields,
          limit: -1
        };
        if (count === 1) {
          $opts.skip = 0;
        } else {
          $opts.skip = Number.random(0, count - 1);
        }
        return _this.model.collection.find({
          isCharity: true
        }, $opts, function(error, cursor) {
          if (error != null) {
            callback(error);
            return;
          }
          return cursor.toArray(function(error, charities) {
            if (charities.length > 0) {
              callback(error, charities[0]);
            } else {
              callback(error);
            }
          });
        });
      });
    };

    Businesses.validateRegister = function(businessId, locationId, registerId, fields, callback) {
      var $query;
      if (Object.isString(businessId)) businessId = new ObjectId(businessId);
      if (Object.isString(locationId)) locationId = new ObjectId(locationId);
      if (Object.isString(registerId)) registerId = new ObjectId(registerId);
      $query = {
        _id: businessId
      };
      $query["locRegister." + locationId.toString()] = registerId;
      return this.model.collection.findOne($query, fields, function(error, business) {
        if (error != null) {
          callback(error);
          return;
        }
        return callback(null, business);
      });
    };

    Businesses.getBySetupId = function(setupId, fields, callback) {
      var $query;
      $query = {
        "registerData.setupId": setupId
      };
      return this.model.collection.findOne($query, fields, function(error, business) {
        if (error != null) {
          callback(error);
          return;
        }
        return callback(null, business);
      });
    };

    return Businesses;

  })(API);

  Organizations = (function(_super) {

    __extends(Organizations, _super);

    function Organizations() {
      Organizations.__super__.constructor.apply(this, arguments);
    }

    Organizations.model = Organization;

    Organizations.search = function(name, type, callback) {
      var query, re;
      re = new RegExp("^" + name + ".*", 'i');
      query = this._query();
      if ((name != null) && !name.isBlank()) query.where('name', re);
      if (__indexOf.call(choices.organizations._enum, type) >= 0) {
        query.where('type', type);
      }
      query.limit(100);
      return query.exec(callback);
    };

    Organizations.setTransactonPending = Organizations.__setTransactionPending;

    Organizations.setTransactionProcessing = Organizations.__setTransactionProcessing;

    Organizations.setTransactionProcessed = Organizations.__setTransactionProcessed;

    Organizations.setTransactionError = Organizations.__setTransactionError;

    return Organizations;

  })(API);

  Polls = (function(_super) {

    __extends(Polls, _super);

    function Polls() {
      Polls.__super__.constructor.apply(this, arguments);
    }

    Polls.model = Poll;

    Polls.optionParser = function(options, q) {
      var query;
      query = this._optionParser(options, q);
      if (options.entityType != null) {
        query.where('entity.type', options.entityType);
      }
      if (options.entityId != null) query.where('entity.id', options.entityId);
      if (options.start != null) query.where('dates.start').gte(options.start);
      if (options.state != null) query.where('transaction.state', state);
      return query;
    };

    Polls.add = function(pollData, amount, callback) {
      var entityClass, self;
      self = this;
      if (Object.isString(pollData.entity.id)) {
        pollData.entity.id = new ObjectId(pollData.entity.id);
      }
      logger.debug("pollData.entity");
      logger.debug(pollData.entity);
      switch (pollData.entity.type) {
        case choices.entities.BUSINESS:
          entityClass = Businesses;
          break;
        case choices.entities.CONSUMER:
          entityClass = Consumers;
      }
      async.parallel({
        checkFunds: function(cb) {
          if (Object.isString(pollData.entity.id)) {
            pollData.entity.id = new ObjectId(pollData.entity.id);
          }
          return entityClass.one(pollData.entity.id, {
            funds: 1
          }, function(error, entity) {
            if (error != null) {
              cb(error);
              return;
            }
            if (!(entity != null)) {
              cb(new errors.ValidationError("Entity id not found.", {
                "entity": "Entity not found."
              }));
              return;
            }
            if (entity.funds.remaining < (pollData.funds.perResponse * pollData.responses.max)) {
              cb(new errors.ValidationError("Insufficient funds.", {
                "entity": "Insufficient funds"
              }));
              return;
            }
            return cb(null, entity);
          });
        },
        validatedMediaQuestion: function(cb) {
          if (!(pollDate.mediaQuestion != null)) {
            return Medias.validateAndGetMediaURLs(pollData.entity.type, pollData.entity.id, "poll", pollData.mediaQuestion, function(error, validatedMedia) {
              if (error != null) {
                cb(error);
                return;
              }
              if (!(validatedMedia != null)) {
                delete pollData.mediaQuestion;
                cb(null, null);
              } else {
                pollData.mediaQuestion = validatedMedia;
                cb(null, validatedMedia);
              }
            });
          } else {
            delete pollData.mediaQuestion;
            return cb(null, null);
          }
        },
        validatedMediaResults: function(cb) {
          if (!(pollDate.mediaResults != null)) {
            return Medias.validateAndGetMediaURLs(pollData.entity.type, pollData.entity.id, "poll", pollData.mediaResults, function(error, validatedMedia) {
              if (error != null) {
                cb(error);
                return;
              }
              if (!(validatedMedia != null)) {
                delete pollData.mediaResults;
                cb(null, null);
              } else {
                pollData.mediaResults = validatedMedia;
                cb(null, validatedMedia);
              }
            });
          } else {
            delete pollData.mediaResults;
            return cb(null, null);
          }
        }
      }, function(error, asyncResults) {
        var instance, transaction, transactionData;
        if (error != null) {
          callback(error);
          return;
        }
        logger.debug("POLL pollData");
        logger.debug(pollData);
        instance = new self.model(pollData);
        transactionData = {
          amount: amount
        };
        transaction = self.createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.POLL_CREATED, transactionData, choices.transactions.directions.INBOUND, instance._doc.entity);
        instance.transactions.state = choices.transactions.states.PENDING;
        instance.transactions.locked = true;
        instance.transactions.ids = [transaction.id];
        instance.transactions.log = [transaction];
        instance.save(function(error, poll) {
          logger.debug(error);
          logger.debug(poll);
          if (error != null) {
            logger.debug("error");
            callback(error);
          } else {
            callback(error, poll._doc);
            tp.process(poll._doc, transaction);
          }
        });
      });
    };

    Polls.update = function(entityType, entityId, pollId, pollData, newAllocated, perResponse, callback) {
      var instance, self;
      self = this;
      instance = new this.model(pollData);
      if (Object.isString(pollId)) pollId = new ObjectId(pollId);
      if (Object.isString(entityId)) entityId = new ObjectId(entityId);
      async.parallel({
        validatedMediaQuestion: function(cb) {
          return Medias.validateAndGetMediaURLs(entityType, entityId, "poll", pollData.mediaQuestion, function(error, validatedMedia) {
            if (error != null) {
              cb(error);
              return;
            }
            if (!(validatedMedia != null)) {
              delete pollData.mediaQuestion;
              cb(null, null);
            } else {
              pollData.mediaQuestion = validatedMedia;
              cb(null, validatedMedia);
            }
          });
        },
        validatedMediaResults: function(cb) {
          return Medias.validateAndGetMediaURLs(entityType, entityId, "poll", pollData.mediaResults, function(error, validatedMedia) {
            if (error != null) {
              cb(error);
              return;
            }
            if (!(validatedMedia != null)) {
              delete pollData.mediaResults;
              cb(null, null);
            } else {
              pollData.mediaResults = validatedMedia;
              cb(null, validatedMedia);
            }
          });
        }
      }, function(error, asyncData) {
        var transaction, transactionData, transactionEntity, updateDoc, where;
        if (error != null) {
          callback(error);
          return;
        }
        updateDoc = {};
        updateDoc.$unset = {};
        if (!(asyncData.validatedMediaQuestion != null)) {
          updateDoc.$unset.mediaQuestion = 1;
        }
        if (!(asyncData.validatedMediaResults != null)) {
          updateDoc.$unset.mediaResults = 1;
        }
        if (Object.isEmpty(updateDoc.$unset)) delete updateDoc.$unset;
        updateDoc.$set = {
          entity: {
            type: entityType,
            id: entityId,
            name: pollData.entity.name
          },
          lastModifiedBy: {
            type: pollData.lastModifiedBy.type,
            id: pollData.lastModifiedBy.id
          },
          name: pollData.name,
          type: pollData.type,
          question: pollData.question,
          choices: pollData.choices,
          numChoices: parseInt(pollData.numChoices),
          responses: {
            remaining: parseInt(pollData.responses.max),
            max: parseInt(pollData.responses.max),
            log: pollData.responses.log,
            dates: pollData.responses.dates,
            choiceCounts: pollData.responses.choiceCounts
          },
          showStats: pollData.showStats,
          displayName: pollData.displayName
        };
        updateDoc.$set["dates.start"] = new Date(pollData.dates.start);
        updateDoc.$set["transactions.locked"] = true;
        updateDoc.$set["transactions.state"] = choices.transactions.states.PENDING;
        transactionEntity = {
          type: entityType,
          id: entityId
        };
        transactionData = {
          newAllocated: newAllocated,
          perResponse: perResponse
        };
        transaction = self.createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.POLL_UPDATED, transactionData, choices.transactions.directions.INBOUND, transactionEntity);
        updateDoc.$push = {
          "transactions.ids": transaction.id,
          "transactions.log": transaction
        };
        where = {
          _id: pollId,
          "entity.type": entityType,
          "entity.id": entityId,
          "transactions.locked": false,
          "deleted": false,
          $or: [
            {
              "dates.start": {
                $gt: new Date()
              },
              "transactions.state": choices.transactions.states.PROCESSED
            }, {
              "transactions.state": choices.transactions.states.ERROR
            }
          ]
        };
        self.model.collection.findAndModify(where, [], updateDoc, {
          safe: true,
          "new": true
        }, function(error, poll) {
          if (error != null) {
            callback(error, null);
          } else if (!(poll != null)) {
            callback(new errors.ValidationError({
              "poll": "Poll does not exist or not editable."
            }));
          } else {
            callback(null, poll);
            tp.process(poll, transaction);
          }
        });
      });
    };

    Polls.updateMediaByGuid = function(entityType, entityId, guid, mediasDoc, mediaKey, callback) {
      var query, set;
      if (Object.isString(entityId)) entityId = new ObjectId(entityId);
      if (Object.isFunction(mediaKey)) {
        callback = mediaKey;
        mediaKey = "media";
      }
      query = this._query();
      query.where("entity.type", entityType);
      query.where("entity.id", entityId);
      query.where("" + mediaKey + ".guid", guid);
      set = {};
      set["" + mediaKey] = Medias.mediaFieldsForType(mediasDoc, "poll");
      query.update({
        $set: set
      }, function(error, success) {
        if (error != null) {
          callback(error);
        } else {
          callback(null, success);
        }
      });
    };

    Polls.list = function(entityType, entityId, stage, options, callback) {
      var fieldsToReturn, query;
      query = this._query();
      query.where("entity.type", entityType);
      query.where("entity.id", entityId);
      switch (stage) {
        case "active":
          query.where('responses.remaining').gt(0);
          query.where('dates.start').lte(new Date());
          query.where('transactions.state').ne(choices.transactions.states.ERROR);
          query.where("deleted").ne(true);
          fieldsToReturn = {
            _id: 1,
            name: 1,
            question: 1,
            "responses.remaining": 1,
            "responses.max": 1,
            dates: 1,
            "transactions.state": 1
          };
          break;
        case "future":
          query.where('dates.start').gt(new Date());
          query.where('responses.remaining').gt(0);
          query.where('transactions.state').ne(choices.transactions.states.ERROR);
          query.where("deleted").ne(true);
          fieldsToReturn = {
            _id: 1,
            name: 1,
            question: 1,
            dates: 1,
            "transactions.state": 1
          };
          break;
        case "completed":
          query.where('responses.remaining').lte(0);
          query.where('transactions.state').ne(choices.transactions.states.ERROR);
          query.where("deleted").ne(true);
          fieldsToReturn = {
            _id: 1,
            name: 1,
            question: 1,
            "responses.remaining": 1,
            "responses.max": 1,
            dates: 1,
            "transactions.state": 1,
            "funds.allocated": 1
          };
          break;
        case "errored":
          query.where('transactions.state', choices.transactions.states.ERROR);
          fieldsToReturn = {
            _id: 1,
            name: 1,
            question: 1,
            "responses.remaining": 1,
            "responses.max": 1,
            dates: 1,
            "transactions.state": 1,
            "funds.allocated": 1
          };
          break;
        default:
          fieldsToReturn = {
            _id: 1,
            name: 1,
            question: 1,
            "responses.remaining": 1,
            "responses.max": 1,
            dates: 1,
            "transactions.state": 1,
            "funds.allocated": 1
          };
      }
      if (!options.count) {
        query.sort("dates.start", -1);
        query.fields(fieldsToReturn);
        query.skip(options.skip || 0);
        query.limit(options.limit || 25);
        query.exec(callback);
      } else {
        query.count(callback);
      }
    };

    Polls.del = function(entityType, entityId, pollId, lastModifiedBy, callback) {
      var $push, $set, $update, entity, self, transaction, transactionData, where;
      self = this;
      if (Object.isString(entityId)) entityId = new ObjectId(entityId);
      if (Object.isString(pollId)) pollId = new ObjectId(pollId);
      if (Object.isString(lastModifiedBy.id)) {
        lastModifiedBy.id = new ObjectId(lastModifiedBy.id);
      }
      entity = {};
      transactionData = {};
      transaction = self.createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.POLL_DELETED, transactionData, choices.transactions.directions.OUTBOUND, entity);
      $set = {
        "lastModifiedBy.type": lastModifiedBy.type,
        "lastModifiedBy.id": lastModifiedBy.id,
        "deleted": true,
        "transactions.locked": true,
        "transactions.state": choices.transactions.states.PENDING
      };
      $push = {
        "transactions.ids": transaction.id,
        "transactions.log": transaction
      };
      $update = {
        $set: $set,
        $push: $push
      };
      where = {
        _id: pollId,
        "entity.type": entityType,
        "entity.id": entityId,
        "transactions.locked": false,
        "deleted": false,
        $or: [
          {
            "dates.start": {
              $gt: new Date()
            },
            "transactions.state": choices.transactions.states.PROCESSED
          }, {
            "transactions.state": choices.transactions.states.ERROR
          }
        ]
      };
      this.model.collection.findAndModify(where, [], $update, {
        safe: true,
        "new": true
      }, function(error, poll) {
        if (error != null) {
          logger.error("POLLS - DELETE: unable to findAndModify");
          logger.error(error);
          return callback(error, null);
        } else if (!(poll != null)) {
          logger.warn("POLLS - DELETE: no document found to modify");
          return callback(new errors.ValidationError({
            "poll": "Poll does not exist or Access Denied."
          }));
        } else {
          logger.info("POLLS - DELETE: findAndModify succeeded, transaction starting");
          callback(null, poll);
          return tp.process(poll, transaction);
        }
      });
    };

    Polls.answered = function(consumerId, options, callback) {
      var fieldsToReturn, query;
      if (Object.isString(consumerId)) consumerId = new ObjectId(consumerId);
      query = this.optionParser(options);
      query.where('responses.consumers', consumerId);
      fieldsToReturn = {
        _id: 1,
        question: 1,
        choices: 1,
        displayName: 1,
        displayMedia: 1,
        "entity.name": 1,
        media: 1,
        "funds.perResponse": 1
      };
      fieldsToReturn["responses.log." + consumerId] = 1;
      query.fields(fieldsToReturn);
      query.sort("responses.log." + consumerId + ".timestamp", -1);
      return query.exec(function(error, polls) {
        if (error != null) {
          callback(error);
          return;
        }
        Polls.removePollPrivateFields(polls);
        callback(null, polls);
      });
    };

    Polls.answer = function(entity, pollId, answers, callback) {
      var maxAnswer, minAnswer, perResponse, self, timestamp;
      if (Object.isString(pollId)) pollId = new ObjectId(pollId);
      if (Object.isString(entity.id)) entity.id = new ObjectId(entity.id);
      minAnswer = Math.min.apply(Math, answers);
      maxAnswer = Math.max.apply(Math, answers);
      if (minAnswer < 0 || isNaN(minAnswer) || isNaN(maxAnswer)) {
        callback(new errors.ValidationError({
          "answers": "Out of Range"
        }));
        return;
      }
      timestamp = new Date();
      perResponse = 0.0;
      self = this;
      return async.series({
        findPerResponse: function(cb) {
          return self.model.findOne({
            _id: pollId
          }, {
            funds: 1
          }, function(error, poll) {
            if (error != null) {
              cb(error);
            } else if (!(poll != null)) {
              cb(new errors.ValidationError({
                "poll": "Invalid poll."
              }));
            } else {
              perResponse = poll.funds.perResponse;
              return cb();
            }
          });
        },
        save: function(cb) {
          var fieldsToReturn, i, inc, push, query, set, transaction, transactionData, update;
          inc = new Object();
          set = new Object();
          push = new Object();
          transactionData = {
            amount: perResponse,
            timestamp: new Date()
          };
          transaction = self.createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.POLL_ANSWERED, transactionData, choices.transactions.directions.OUTBOUND, entity);
          push["transactions.ids"] = transaction.id;
          push["transactions.log"] = transaction;
          inc["funds.remaining"] = -1 * perResponse;
          inc["responses.remaining"] = -1;
          i = 0;
          while (i < answers.length) {
            inc["responses.choiceCounts." + answers[i]] = 1;
            i++;
          }
          set["responses.log." + entity.id] = {
            answers: answers,
            timestamp: timestamp
          };
          push["responses.dates"] = {
            consumerId: entity.id,
            timestamp: timestamp
          };
          push["responses.consumers"] = entity.id;
          update = {
            $inc: inc,
            $push: push,
            $set: set
          };
          fieldsToReturn = {
            _id: 1,
            question: 1,
            choices: 1,
            "responses.choiceCounts": 1,
            showStats: 1,
            displayName: 1,
            displayMedia: 1,
            "entity.name": 1,
            media: 1,
            dates: 1,
            "funds.perResponse": 1
          };
          fieldsToReturn["responses.log." + entity.id] = 1;
          query = {
            _id: pollId,
            "entity.id": {
              $ne: entity.id
            },
            numChoices: {
              $gt: maxAnswer
            },
            "responses.consumers": {
              $ne: entity.id
            },
            "responses.skipConsumers": {
              $ne: entity.id
            },
            "responses.flagConsumers": {
              $ne: entity.id
            },
            "dates.start": {
              $lte: new Date()
            },
            "transactions.state": choices.transactions.states.PROCESSED,
            "deleted": false
          };
          query.type = answers.length === 1 ? "single" : "multiple";
          return self.model.collection.findAndModify(query, [], update, {
            "new": true,
            safe: true,
            fields: fieldsToReturn
          }, function(error, poll) {
            if (error != null) {
              cb(error);
              return;
            }
            if (!(poll != null)) {
              cb(new errors.ValidationError({
                "poll": "Invalid poll, Invalid answer, You are owner of the poll, or You've already answered."
              }));
              return;
            }
            Polls.removePollPrivateFields(poll);
            cb(null, poll);
            tp.process(poll, transaction);
          });
        }
      }, function(error, results) {
        if (error != null) {
          callback(error);
          return;
        }
        callback(null, results.save);
      });
    };

    Polls.skip = function(consumerId, pollId, callback) {
      var query;
      if (Object.isString(consumerId)) consumerId = new ObjectId(consumerId);
      query = this._query();
      query.where('_id', pollId);
      query.where('entity.id').ne(consumerId);
      query.where('responses.consumers').ne(consumerId);
      query.where('responses.skipConsumers').ne(consumerId);
      query.where('responses.flagConsumers').ne(consumerId);
      query.where('dates.start').lte(new Date());
      query.where('transactions.state', choices.transactions.states.PROCESSED);
      return query.update({
        $push: {
          "responses.skipConsumers": consumerId
        },
        $inc: {
          "responses.skipCount": 1
        }
      }, function(error, success) {
        callback(error, success);
      });
    };

    Polls.flag = function(consumerId, pollId, callback) {
      var query;
      if (Object.isString(consumerId)) consumerId = new ObjectId(consumerId);
      query = this._query();
      query.where('_id', pollId);
      query.where('entity.id').ne(consumerId);
      query.where('responses.consumers').ne(consumerId);
      query.where('responses.skipConsumers').ne(consumerId);
      query.where('responses.flagConsumers').ne(consumerId);
      query.where('dates.start').lte(new Date());
      query.where('transactions.state', choices.transactions.states.PROCESSED);
      return query.update({
        $push: {
          "responses.flagConsumers": consumerId
        },
        $inc: {
          "responses.flagCount": 1
        }
      }, function(error, success) {
        callback(error, success);
      });
    };

    Polls.next = function(consumerId, callback) {
      var query;
      if (Object.isString(consumerId)) consumerId = new ObjectId(consumerId);
      query = this._query();
      query.where('entity.id').ne(consumerId);
      query.where('responses.consumers').ne(consumerId);
      query.where('responses.skipConsumers').ne(consumerId);
      query.where('responses.flagConsumers').ne(consumerId);
      query.where('responses.remaining').gt(0);
      query.where('dates.start').lte(new Date());
      query.where('transactions.state', choices.transactions.states.PROCESSED);
      query.where('deleted').ne(true);
      query.limit(1);
      query.fields({
        _id: 1,
        type: 1,
        question: 1,
        choices: 1,
        displayName: 1,
        displayMedia: 1,
        "entity.name": 1,
        media: 1,
        "funds.perResponse": 1
      });
      return query.exec(function(error, poll) {
        if (error != null) {
          callback(error);
          return;
        }
        callback(null, poll);
      });
    };

    Polls.removePollPrivateFields = function(polls) {
      var i;
      if (!Object.isArray(polls)) {
        if (!polls.displayName) delete polls.entity;
        if (!polls.displayMedia) delete media;
        if (!polls.showStats && (polls.responses != null)) {
          delete polls.responses.choiceCounts;
        }
      } else {
        i = 0;
        while (i < polls.length) {
          if (!polls[i].displayName) delete polls[i].entity;
          if (!polls[i].displayMedia) delete media;
          if (!polls[i].showStats) delete polls[i].responses.choiceCounts;
          i++;
        }
      }
    };

    Polls.setTransactonPending = Polls.__setTransactionPending;

    Polls.setTransactionProcessing = Polls.__setTransactionProcessing;

    Polls.setTransactionProcessed = Polls.__setTransactionProcessed;

    Polls.setTransactionError = Polls.__setTransactionError;

    return Polls;

  })(API);

  Discussions = (function(_super) {

    __extends(Discussions, _super);

    function Discussions() {
      Discussions.__super__.constructor.apply(this, arguments);
    }

    Discussions.model = Discussion;

    Discussions.optionParser = function(options, q) {
      var query;
      query = this._optionParser(options, q);
      if (options.entityType != null) {
        query.where('entity.type', options.entityType);
      }
      if (options.entityId != null) query.where('entity.id', options.entityId);
      if (options.start != null) query.where('dates.start').gte(options.start);
      if (options.state != null) query.where('transaction.state', state);
      return query;
    };

    Discussions.add = function(data, amount, callback) {
      var instance, transaction, transactionData;
      instance = new this.model(data);
      if (data.tags != null) Tags.addAll(data.tags);
      transactionData = {
        amount: amount
      };
      transaction = this.createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.DISCUSSION_CREATED, transactionData, choices.transactions.directions.INBOUND, instance._doc.entity);
      instance.transactions.locked = true;
      instance.transactions.ids = [transaction.id];
      instance.transactions.log = [transaction];
      instance.save(function(error, discussion) {
        callback(error, discussion);
        if (error != null) {} else {
          return tp.process(discussion._doc, transaction);
        }
      });
    };

    Discussions.update = function(entityType, entityId, discussionId, newAllocated, data, callback) {
      var $push, $set, $update, entity, instance, self, transaction, transactionData, where;
      self = this;
      instance = new this.model(data);
      if (Object.isString(entityId)) entityId = new ObjectId(entityId);
      if (Object.isString(discussionId)) discussionId = new ObjectId(discussionId);
      if ((data.media != null) && Object.isString(data.media.mediaId) && data.media.mediaId.length > 0) {
        data.media.mediaId = new ObjectId(data.media.mediaId);
      }
      if (data.tags != null) {
        Tags.addAll(data.tags, choices.tags.types.DISCUSSIONS);
      }
      $set = {
        entity: {
          type: entityType,
          id: entityId,
          name: data.entity.name
        },
        lastModifiedBy: {
          type: data.lastModifiedBy.type,
          id: data.lastModifiedBy.id
        },
        name: data.name,
        question: data.question,
        details: data.details,
        tags: data.tags,
        displayMedia: data.displayMedia,
        media: data.media
      };
      $set["dates.start"] = new Date(data.dates.start);
      entity = {
        type: entityType,
        id: entityId
      };
      transactionData = {
        newAllocated: newAllocated
      };
      transaction = self.createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.DISCUSSION_UPDATED, transactionData, choices.transactions.directions.INBOUND, entity);
      $set["transactions.locked"] = true;
      $set["transactions.state"] = choices.transactions.states.PENDING;
      $push = {
        "transactions.ids": transaction.id,
        "transactions.log": transaction
      };
      logger.info(data);
      $update = {
        $set: $set,
        $push: $push
      };
      where = {
        _id: discussionId,
        "entity.type": entityType,
        "entity.id": entityId,
        "transactions.locked": false,
        "deleted": false,
        $or: [
          {
            "dates.start": {
              $gt: new Date()
            },
            "transactions.state": choices.transactions.states.PROCESSED
          }, {
            "transactions.state": choices.transactions.states.ERROR
          }
        ]
      };
      this.model.collection.findAndModify(where, [], $update, {
        safe: true,
        "new": true
      }, function(error, discussion) {
        if (error != null) {
          return callback(error, null);
        } else if (!(discussion != null)) {
          return callback(new errors.ValidationError({
            "discussion": "Discussion does not exist or Access Denied."
          }));
        } else {
          callback(null, discussion);
          return tp.process(discussion, transaction);
        }
      });
    };

    Discussions.del = function(entityType, entityId, discussionId, lastModifiedBy, callback) {
      var $push, $set, $update, entity, self, transaction, transactionData, where;
      self = this;
      if (Object.isString(entityId)) entityId = new ObjectId(entityId);
      if (Object.isString(discussionId)) discussionId = new ObjectId(discussionId);
      if (Object.isString(lastModifiedBy.id)) {
        lastModifiedBy.id = new ObjectId(lastModifiedBy.id);
      }
      entity = {};
      transactionData = {};
      transaction = self.createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.DISCUSSION_DELETED, transactionData, choices.transactions.directions.OUTBOUND, entity);
      $set = {
        "deleted": true,
        "transactions.locked": true,
        "transactions.state": choices.transactions.states.PENDING,
        "lastModifiedBy.type": lastModifiedBy.type,
        "lastModifiedBy.id": lastModifiedBy.id
      };
      $push = {
        "transactions.ids": transaction.id,
        "transactions.log": transaction
      };
      $update = {
        $set: $set,
        $push: $push
      };
      where = {
        _id: discussionId,
        "entity.type": entityType,
        "entity.id": entityId,
        "transactions.locked": false,
        "deleted": false,
        $or: [
          {
            "dates.start": {
              $gt: new Date()
            },
            "transactions.state": choices.transactions.states.PROCESSED
          }, {
            "transactions.state": choices.transactions.states.ERROR
          }
        ]
      };
      this.model.collection.findAndModify(where, [], $update, {
        safe: true,
        "new": true
      }, function(error, discussion) {
        if (error != null) {
          logger.error("DISCUSSIONS - DELETE: unable to findAndModify");
          logger.error(error);
          return callback(error, null);
        } else if (!(discussion != null)) {
          logger.warn("DISCUSSIONS - DELETE: no document found to modify");
          return callback(new errors.ValidationError({
            "discussion": "Discussion does not exist or Access Denied."
          }));
        } else {
          logger.info("DISCUSSIONS - DELETE: findAndModify succeeded, transaction starting");
          callback(null, discussion);
          return tp.process(discussion, transaction);
        }
      });
    };

    Discussions.updateMediaByGuid = function(entityType, entityId, guid, mediasDoc, callback) {
      var query, set;
      if (Object.isString(entityId)) entityId = new ObjectId(entityId);
      query = this._query();
      query.where("entity.type", entityType);
      query.where("entity.id", entityId);
      query.where("media.guid", guid);
      set = {
        media: Medias.mediaFieldsForType(mediasDoc, "discussion")
      };
      query.update({
        $set: set
      }, function(error, success) {
        if (error != null) {
          callback(error);
        } else {
          callback(null, success);
        }
      });
    };

    Discussions.listCampaigns = function(entityType, entityId, stage, options, callback) {
      var fieldsToReturn, query;
      query = this._query();
      query.where("entity.type", entityType);
      query.where("entity.id", entityId);
      switch (stage) {
        case "active":
          query.where("funds.remaining").gte(0);
          query.where("dates.start").lte(new Date());
          query.where('transactions.state').ne(choices.transactions.states.ERROR);
          query.where("deleted").ne(true);
          fieldsToReturn = {
            _id: 1,
            name: 1,
            question: 1,
            "responses.count": 1,
            dates: 1,
            funds: 1,
            "transactions.state": 1
          };
          break;
        case "future":
          query.where("funds.remaining").gte(0);
          query.where('dates.start').gt(new Date());
          query.where('transactions.state').ne(choices.transactions.states.ERROR);
          query.where("deleted").ne(true);
          fieldsToReturn = {
            _id: 1,
            name: 1,
            question: 1,
            dates: 1,
            funds: 1,
            "transactions.state": 1
          };
          break;
        case "completed":
          query.where("funds.remaining").lte(0);
          query.where('transactions.state').ne(choices.transactions.states.ERROR);
          query.where("deleted").ne(true);
          fieldsToReturn = {
            _id: 1,
            name: 1,
            question: 1,
            "responses.count": 1,
            dates: 1,
            funds: 1,
            "transactions.state": 1
          };
          break;
        case "errored":
          query.where('transactions.state', choices.transactions.states.ERROR);
          fieldsToReturn = {
            _id: 1,
            name: 1,
            question: 1,
            dates: 1,
            "transactions.state": 1,
            "funds.allocated": 1
          };
          break;
        default:
          fieldsToReturn = {
            _id: 1,
            name: 1,
            question: 1,
            "responses.count": 1,
            dates: 1,
            "transactions.state": 1,
            "funds.allocated": 1
          };
      }
      if (!options.count) {
        query.sort("dates.start", -1);
        query.fields(fieldsToReturn);
        query.skip(options.skip);
        query.limit(options.limit);
        query.exec(callback);
      } else {
        query.count(callback);
      }
    };

    /* _list_
    */

    Discussions.list = function(options, callback) {
      var $fields, $query, $sort, cursor, sort, _ref;
      if (Object.isFunction(options)) {
        callback = options;
        options = {};
      }
      options.limit = options.limit || 25;
      options.skip = options.skip || 0;
      if ((options.sort != null) && (_ref = options.sort, __indexOf.call(choices.discussions.sorts._enum, _ref) >= 0)) {
        sort = options.sort;
      } else {
        options.sort = choices.discussions.sorts.DATE_DESCENDING;
      }
      $query = {
        "dates.start": {
          $lte: new Date()
        },
        $or: [
          {
            deleted: false
          }, {
            deleted: {
              $exists: false
            }
          }
        ],
        "transactions.state": choices.transactions.states.PROCESSED,
        "transactions.locked": {
          $ne: true
        }
      };
      $sort = {};
      switch (sort) {
        case choices.discussions.sorts.DATE_ASCENDING:
          $sort = {
            'dates.start': 1
          };
          break;
        case choices.discussions.sorts.DATE_DESCENDING:
          $sort = {
            'dates.start': -1
          };
          break;
        case choices.discussions.sorts.RECENTLY_POPULAR_7:
          $query["dates.start"].$gte = Date.create().addWeeks(-1);
          $sort = {
            'dates.start': -1
          };
          $sort = {
            'responseCount': 1
          };
          break;
        case choices.discussions.sorts.RECENTLY_POPULAR_14:
          $query["dates.start"].$gte = Date.create().addWeeks(-2);
          $sort = {
            'dates.start': -1,
            'responseCount': 1
          };
          break;
        case choices.discussions.sorts.RECENTLY_POPULAR_1:
          $query["dates.start"].$gte = Date.create().addDays(-1);
          $sort = {
            'dates.start': -1,
            'responseCount': 1
          };
      }
      $fields = {
        question: 1,
        tags: 1,
        media: 1,
        thanker: 1,
        donors: 1,
        donationAmounts: 1,
        dates: 1,
        funds: 1,
        donationCount: 1,
        thankCount: 1
      };
      return cursor = this.model.collection.find($query, $fields, function(err, cursor) {
        if (typeof error !== "undefined" && error !== null) {
          callback(error);
          return;
        }
        cursor.limit(options.limit);
        cursor.skip(options.skip);
        cursor.sort($sort);
        return cursor.toArray(function(error, discussions) {
          return callback(error, discussions);
        });
      });
    };

    /* _get_
    */

    Discussions.get = function(discussionId, responseOptions, callback) {
      var $fields, $query;
      if (Object.isString(discussionId)) discussionId = new ObjectId(discussionId);
      if (Object.isFunction(responseOptions)) {
        callback = responseOptions;
        responseOptions = {};
      }
      responseOptions.limit = responseOptions.limit || 10;
      responseOptions.skip = responseOptions.skip || 0;
      $query = {
        "dates.start": {
          $lte: new Date()
        },
        deleted: {
          $ne: true
        },
        "transactions.state": choices.transactions.states.PROCESSED,
        "transactions.locked": {
          $ne: true
        }
      };
      $fields = {
        question: 1,
        tags: 1,
        media: 1,
        thanker: 1,
        donors: 1,
        donationAmounts: 1,
        dates: 1,
        funds: 1,
        donationCount: 1,
        thankCount: 1,
        responses: {
          $slice: [responseOptions.skip, responseOptions.skip + responseOptions.limit]
        }
      };
      return this.model.collection.findOne($query, $fields, function(error, discussion) {
        return callback(error, discussion);
      });
    };

    /* _getResponses_
    */

    Discussions.getResponses = function(discussionId, responseOptions, callback) {
      var $fields, $query;
      if (Object.isString(discussionId)) discussionId = new ObjectId(discussionId);
      if (Object.isFunction(responseOptions)) {
        callback = responseOptions;
        responseOptions = {};
      }
      responseOptions.limit = responseOptions.limit || 10;
      responseOptions.skip = responseOptions.skip || 0;
      $query = {
        "dates.start": {
          $lte: new Date()
        },
        deleted: {
          $ne: true
        },
        "transactions.state": choices.transactions.states.PROCESSED,
        "transactions.locked": {
          $ne: true
        }
      };
      $fields = {
        _id: 1,
        responses: {
          $slice: [responseOptions.skip, responseOptions.skip + responseOptions.limit]
        }
      };
      return this.model.collection.findOne($query, $fields, function(error, discussion) {
        return callback(error, discussion.responses);
      });
    };

    Discussions.getByEntity = function(entityType, entityId, discussionId, callback) {
      this.model.findOne({
        _id: discussionId,
        'entity.type': entityType,
        'entity.id': entityId
      }, callback);
    };

    /* _thank_
    */

    Discussions.thank = function(discussionId, responseId, thankerEntity, amount, callback) {
      var entityThanked, fieldsToReturn, thankerApiClass,
        _this = this;
      if (Object.isString(discussionId)) discussionId = new ObjectId(discussionId);
      if (Object.isString(responseId)) responseId = new ObjectId(responseId);
      if (Object.isString(thankerEntity.id)) {
        thankerEntity.id = new ObjectId(thankerEntity.id);
      }
      amount = parseFloat(amount);
      if (amount < 0) {
        callback(new errors.ValidationError({
          "discussion": "can not thank a negative amount"
        }));
      }
      thankerApiClass = null;
      if (thankerEntity.type === choices.entities.CONSUMER) {
        thankerApiClass = Consumers;
      } else if (thankerEntity.type === choices.entities.BUSINESS) {
        thankerApiClass = Businesses;
      } else {
        callback(new errors.ValidationError({
          "discussion": "Entity type: " + thankerEntity.type + " is invalid or unsupported"
        }));
        return;
      }
      fieldsToReturn = {};
      fieldsToReturn["responseEntities." + (responseId.toString())] = 1;
      entityThanked = null;
      return async.series({
        getResponseEntity: function(cb) {
          return _this.model.collection.findOne({
            _id: discussionId
          }, fieldsToReturn, function(error, discussion) {
            if (error != null) {
              cb(error);
            } else if (!(discussion != null)) {
              cb(new errors.ValidationError({
                "discussion": "response doesn't exist"
              }));
            } else {
              entityThanked = discussion.responseEntities["" + (responseId.toString())];
              cb();
            }
          });
        },
        save: function(cb) {
          var $inc, $push, $set, $update, transaction, transactionData;
          transactionData = {
            amount: amount,
            thankerEntity: thankerEntity,
            discussionId: discussionId,
            responseId: responseId,
            timestamp: new Date()
          };
          transaction = _this.createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.DISCUSSION_THANKED, transactionData, choices.transactions.directions.OUTBOUND, entityThanked);
          $set = {};
          $push = {
            "transactions.ids": transaction.id,
            "transactions.log": transaction
          };
          $inc = {
            "funds.remaining": -1 * amount
          };
          $update = {
            $push: $push,
            $set: $set,
            $inc: $inc
          };
          fieldsToReturn = {
            _id: 1
          };
          return thankerApiClass.model.collection.findAndModify({
            _id: thankerEntity.id,
            "funds.remaining": {
              $gte: amount
            }
          }, [], $update, {
            safe: true,
            fields: fieldsToReturn
          }, function(error, doc) {
            if (error != null) {
              return cb(error);
            } else if (!(doc != null)) {
              return cb(new errors.ValidationError({
                "funds.remaining": "insufficient funds remaining"
              }));
            } else {
              callback(null, 1);
              tp.process(doc, transaction);
              return cb();
            }
          });
        }
      }, function(error, results) {
        if (error != null) return callback(error);
      });
    };

    /* _donate_
    */

    Discussions.donate = function(discussionId, entity, amount, callback) {
      var $push, $set, $update, fieldsToReturn, transaction, transactionData;
      if (Object.isString(discussionId)) discussionId = new ObjectId(discussionId);
      if (Object.isString(entity.id)) entity.id = new ObjectId(entity.id);
      amount = parseFloat(amount);
      if (amount < 0) {
        callback(new errors.ValidationError({
          "discussion": "can not donate negative funds"
        }));
      }
      transactionData = {
        amount: amount,
        timestamp: new Date()
      };
      transaction = this.createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.DISCUSSION_DONATED, transactionData, choices.transactions.directions.INBOUND, entity);
      $set = {};
      $push = {
        "transactions.ids": transaction.id,
        "transactions.log": transaction
      };
      $update = {
        $push: $push,
        $set: $set
      };
      fieldsToReturn = {
        _id: 1
      };
      return this.model.collection.findAndModify({
        _id: discussionId
      }, [], $update, {
        safe: true,
        fields: fieldsToReturn
      }, function(error, discussion) {
        if (error != null) {
          return callback(error);
        } else if (!(discussion != null)) {
          return callback(new errors.ValidationError({
            "discussion": "Discussion does not exist or is not editable."
          }));
        } else {
          callback(null, 1);
          return tp.process(discussion, transaction);
        }
      });
    };

    /* distributeDonation
    */

    Discussions.distributeDonation = function(discussionId, responseId, donorEntity, amount, callback) {
      var doneeEntity, fieldsToReturn,
        _this = this;
      if (Object.isString(discussionId)) discussionId = new ObjectId(discussionId);
      if (Object.isString(responseId)) responseId = new ObjectId(responseId);
      if (Object.isString(donorEntity.id)) {
        donorEntity.id = new ObjectId(donorEntity.id);
      }
      amount = parseFloat(amount);
      if (amount < 0) {
        callback(new errors.ValidationError({
          "discussion": "can not distribute negative funds"
        }));
      }
      fieldsToReturn = {};
      fieldsToReturn["responseEntities." + (responseId.toString())] = 1;
      doneeEntity = null;
      return async.series({
        getResponseEntity: function(cb) {
          return _this.model.collection.findOne({
            _id: discussionId
          }, fieldsToReturn, function(error, discussion) {
            if (error != null) {
              cb(error);
            } else if (!(discussion != null)) {
              cb(new errors.ValidationError({
                "discussion": "response doesn't exist"
              }));
            } else {
              doneeEntity = discussion.responseEntities["" + (responseId.toString())];
              cb();
            }
          });
        },
        save: function(cb) {
          var $inc, $push, $query, $set, $update, transaction, transactionData;
          transactionData = {
            amount: amount,
            donorEntity: donorEntity,
            discussionId: discussionId,
            responseId: responseId,
            timestamp: new Date()
          };
          transaction = _this.createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.DISCUSSION_DONATION_DISTRIBUTED, transactionData, choices.transactions.directions.OUTBOUND, doneeEntity);
          $set = {};
          $push = {
            "transactions.ids": transaction.id,
            "transactions.log": transaction
          };
          $inc = {
            "funds.remaining": -1 * amount
          };
          $update = {
            $push: $push,
            $set: $set,
            $inc: $inc
          };
          fieldsToReturn = {
            _id: 1
          };
          $query = {
            _id: discussionId
          };
          $query["donationAmounts." + donorEntity.type + "_" + donorEntity.id + ".remaining"] = {
            $gte: amount
          };
          logger.debug($query);
          logger.debug($update);
          return _this.model.collection.findAndModify($query, [], $update, {
            safe: true,
            fields: fieldsToReturn
          }, function(error, doc) {
            if (error != null) {
              return cb(error);
            } else if (!(doc != null)) {
              return cb(new errors.ValidationError({
                "funds.remaining": "insufficient funds remaining"
              }));
            } else {
              callback(null, 1);
              tp.process(doc, transaction);
              return cb();
            }
          });
        }
      }, function(error, results) {
        if (error != null) return callback(error);
      });
    };

    /* _respond_
    */

    Discussions.respond = function(discussionId, entity, content, callback) {
      var $inc, $push, $set, $update, response;
      if (Object.isString(discussionId)) discussionId = new ObjectId(discussionId);
      if (Object.isString(entity.id)) entity.id = new ObjectId(entity.id);
      response = {
        _id: new ObjectId(),
        entity: entity,
        content: content,
        commentCount: 0,
        dates: {
          created: new Date(),
          lastModified: new Date()
        }
      };
      $push = {
        responses: response
      };
      $set = {};
      $set["responseEntities." + (response._id.toString())] = entity;
      $inc = {
        responseCount: 1
      };
      $update = {
        $push: $push,
        $inc: $inc,
        $set: $set
      };
      return this.model.collection.update({
        _id: discussionId
      }, $update, {
        safe: true
      }, callback);
    };

    /* _comment_
    */

    Discussions.comment = function(discussionId, responseId, entity, content, callback) {
      var $inc, $push, $update, comment;
      if (Object.isString(discussionId)) discussionId = new ObjectId(discussionId);
      if (Object.isString(responseId)) responseId = new ObjectId(responseId);
      if (Object.isString(entity.id)) {
        entity.id = new ObjectId(entity.id);
        comment = {
          _id: new ObjectId(),
          entity: entity,
          content: content,
          dates: {
            created: new Date(),
            lastModified: new Date()
          }
        };
        $push = {
          "responses.$.comments": comment
        };
        $inc = {
          "responses.$.commentCount": 1
        };
        $update = {
          $push: $push,
          $inc: $inc
        };
        return this.model.collection.update({
          _id: discussionId,
          "responses._id": responseId
        }, $update, {
          safe: true
        }, callback);
      }
    };

    /* _voteUp_
    */

    Discussions.voteUp = function(discussionId, responseId, entity, callback) {
      return this._vote(discussionId, responseId, entity, choices.votes.UP, callback);
    };

    /* _voteDown_
    */

    Discussions.voteDown = function(discussionId, responseId, entity, callback) {
      return this._vote(discussionId, responseId, entity, choices.votes.DOWN, callback);
    };

    /* _\_vote_
    */

    Discussions._vote = function(discussionId, responseId, entity, direction, callback) {
      var $inc, $push, $query, $set, $update, d, opposite, score;
      if (Object.isString(discussionId)) discussionId = new ObjectId(discussionId);
      if (Object.isString(responseId)) responseId = new ObjectId(responseId);
      if (Object.isString(entity.id)) entity.id = new ObjectId(entity.id);
      d = "up";
      score = 1;
      opposite = choices.votes.DOWN;
      if (direction === choices.votes.DOWN) {
        d = "down";
        score = -1;
        opposite = choices.votes.UP;
      }
      this._undoVote(discussionId, responseId, entity, opposite, function(error, data) {});
      entity._id = new ObjectId();
      $query = {
        _id: discussionId,
        "responses._id": responseId
      };
      $inc = {
        "votes.count": 1,
        "votes.score": score,
        "responses.$.votes.count": 1
      };
      $set = {};
      $push = {};
      $query["responses.votes." + d + ".by.id"] = {
        $ne: entity.id
      };
      $inc["responses.$.votes." + d + ".count"] = 1;
      $inc["votes." + d] = 1;
      $push["responses.$.votes." + d + ".by"] = entity;
      $set["responses.$.votes." + d + ".ids." + entity.type + "_" + (entity.id.toString())] = 1;
      $update = {
        $inc: $inc,
        $push: $push,
        $set: $set
      };
      return this.model.collection.update($query, $update, {
        safe: false
      }, callback);
    };

    /* _undoVoteUp_
    */

    Discussions.undoVoteUp = function(discussionId, responseId, entity, callback) {
      return this._undoVote(discussionId, responseId, entity, choices.votes.UP, callback);
    };

    /* _undoVoteDown_
    */

    Discussions.undoVoteDown = function(discussionId, responseId, entity, callback) {
      return this._undoVote(discussionId, responseId, entity, choices.votes.DOWN, callback);
    };

    /* _\_undoVote_
    */

    Discussions._undoVote = function(discussionId, responseId, entity, direction, callback) {
      var $inc, $pull, $query, $unset, $update, d, score;
      if (Object.isString(discussionId)) discussionId = new ObjectId(discussionId);
      if (Object.isString(responseId)) responseId = new ObjectId(responseId);
      if (Object.isString(entity.id)) entity.id = new ObjectId(entity.id);
      d = "up";
      score = -1;
      if (direction === choices.votes.DOWN) {
        d = "down";
        score = 1;
      }
      $query = {
        _id: discussionId,
        "responses._id": responseId
      };
      $pull = {};
      $inc = {
        "votes.count": -1,
        "votes.score": score,
        "responses.$.votes.count": -1
      };
      $unset = {};
      $query["responses.votes." + d + ".by.id"] = entity.id;
      $pull["responses.$.votes." + d + ".by"] = {
        type: entity.type,
        id: entity.id
      };
      $inc["responses.$.votes." + d + ".count"] = -1;
      $inc["votes." + d] = -1;
      $unset["responses.$.votes." + d + ".ids." + entity.type + "_" + (entity.id.toString())] = 1;
      $update = {
        $inc: $inc,
        $pull: $pull,
        $unset: $unset
      };
      return this.model.collection.update($query, $update, {
        safe: false
      }, callback);
    };

    Discussions.setTransactonPending = Discussions.__setTransactionPending;

    Discussions.setTransactionProcessing = Discussions.__setTransactionProcessing;

    Discussions.setTransactionProcessed = Discussions.__setTransactionProcessed;

    Discussions.setTransactionError = Discussions.__setTransactionError;

    return Discussions;

  })(API);

  Medias = (function(_super) {

    __extends(Medias, _super);

    function Medias() {
      Medias.__super__.constructor.apply(this, arguments);
    }

    Medias.model = Media;

    Medias.mediaFieldsForType = function(mediasDoc, mediaFor) {
      var imageType, media;
      switch (mediaFor) {
        case 'event':
        case 'poll':
        case 'discussion':
          imageType = 'landscape';
          break;
        case 'business':
        case 'consumer':
        case 'client':
          imageType = 'square';
          break;
        case 'consumer-secure':
          imageType = 'secureSquare';
      }
      if (imageType === "square") {
        media = {
          url: mediasDoc.sizes.s128,
          thumb: mediasDoc.sizes.s85,
          mediaId: mediasDoc._id
        };
      } else if (imageType === "secureSquare") {
        media = {
          url: mediasDoc.sizes['s128-secure'],
          thumb: mediasDoc.sizes['s85-secure'],
          mediaId: mediasDoc._id
        };
      } else if (imageType === "landscape") {
        media = {
          url: mediasDoc.sizes.s320x240,
          thumb: mediasDoc.sizes.s100x75,
          mediaId: mediasDoc._id
        };
      }
      return media;
    };

    Medias.validateMedia = function(media, imageType, callback) {
      var validatedMedia;
      validatedMedia = {};
      if (!(media != null)) {
        callback(new errors.ValidationError({
          "media": "Media is null."
        }));
        return;
      }
      if (!utils.isBlank(media.mediaId)) {
        delete media.tempURL;
        if (!utils.isBlank(media.url) || !utils.isBlank(media.thumb)) {
          logger.debug("validateMedia - mediaId supplied, missing urls, fetch urls from db.");
          return Medias.one(media.mediaId, function(error, data) {
            if (error != null) {
              callback(error);
              return;
            } else if (!(data != null) || data.length === 0) {
              callback(new errors.ValidationError({
                "mediaId": "Invalid MediaId"
              }));
              return;
            }
            if (imageType === "square") {
              validatedMedia.mediaId = data._id;
              validatedMedia.thumb = data.sizes.s85;
              validatedMedia.url = data.sizes.s128;
              if (!utils.isBlank(media.rotateDegrees) && media.rotateDegrees !== 0) {
                validatedMedia.rotateDegrees = media.rotateDegrees;
              }
              callback(null, validatedMedia);
            } else if (imageType === "landscape") {
              logger.debug("imageType-landscape");
              logger.debug(data);
              validatedMedia.mediaId = data._id;
              validatedMedia.thumb = data.sizes.s100x75;
              validatedMedia.url = data.sizes.s320x240;
              if (!utils.isBlank(media.rotateDegrees) && media.rotateDegrees !== 0) {
                validatedMedia.rotateDegrees = media.rotateDegrees;
              }
              callback(null, validatedMedia);
            } else {
              callback(new errors.ValidationError({
                "imageType": "Unknown value."
              }));
            }
          });
        } else {
          logger.debug("validateMedia - mediaId supplied with both URLs, no updates required.");
          callback(null, media);
        }
      } else if (!utils.isBlank(media.guid)) {
        validatedMedia.guid = media.guid;
        if (!utils.isBlank(media.rotateDegrees) && media.rotateDegrees !== 0) {
          validatedMedia.rotateDegrees = media.rotateDegrees;
        }
        if (!utils.isBlank(media.tempURL)) {
          validatedMedia.url = media.tempURL;
          validatedMedia.thumb = media.tempURL;
          callback(null, validatedMedia);
        } else {
          if (utils.isBlank(media.url) || utils.isBlank(media.thumb)) {
            callback(new errors.ValidationError({
              "media": "'tempURL' or ('url' and 'thumb') is required when supplying guid."
            }));
          } else {
            validatedMedia.url = media.url;
            validatedMedia.thumb = media.thumb;
            callback(null, validatedMedia);
          }
        }
      } else if ((media.url != null) || (media.thumb != null)) {
        callback(new errors.ValidationError({
          "media": "'guid' or 'mediaId' is required when supplying a media.url"
        }));
      } else {
        callback(null, {});
      }
    };

    Medias.validateAndGetMediaURLs = function(entityType, entityId, mediaFor, media, callback) {
      var validatedMedia;
      validatedMedia = {};
      if (!utils.isBlank(media.rotateDegrees) && !isNaN(parseInt(media.rotateDegrees))) {
        validatedMedia.rotateDegrees = media.rotateDegrees;
      }
      if (!(media != null)) {
        callback(null, null);
        return;
      }
      if (!utils.isBlank(media.mediaId)) {
        if (utils.isBlank(media.url) || utils.isBlank(media.thumb)) {
          logger.debug("validateMedia - mediaId supplied, missing urls, fetch urls from db.");
          if (Object.isString(media.mediaId)) {
            media.mediaId = new ObjectId(media.mediaId);
          }
          return Medias.one(media.mediaId, function(error, mediasDoc) {
            if (error != null) {
              callback(error);
              return;
            } else if (!(mediasDoc != null) || mediasDoc.length === 0) {
              callback(new errors.ValidationError({
                "mediaId": "Invalid MediaId"
              }));
              return;
            }
            validatedMedia = Medias.mediaFieldsForType(mediasDoc._doc, mediaFor);
            callback(null, validatedMedia);
          });
        } else {
          logger.debug("validateMedia - mediaId supplied with both URLs, no updates required.");
          callback(null, media);
        }
      } else if (!utils.isBlank(media.guid)) {
        validatedMedia.guid = media.guid;
        return Medias.getByGuid(entityType, entityId, validatedMedia.guid, function(error, mediasDoc) {
          if (error != null) {
            callback(error);
          } else if (mediasDoc != null) {
            logger.debug("validateMedia - guid supplied, found guid in Medias.");
            validatedMedia = Medias.mediaFieldsForType(mediasDoc._doc, mediaFor);
            callback(null, validatedMedia);
          } else {
            logger.debug("validateMedia - guid supplied, guid not found (use temp. URLs for now).");
            if (!utils.isBlank(media.tempURL)) {
              validatedMedia.url = media.tempURL;
              validatedMedia.thumb = media.tempURL;
              callback(null, validatedMedia);
            } else {
              if (utils.isBlank(media.url) || utils.isBlank(media.thumb)) {
                callback(new errors.ValidationError({
                  "media": "'tempURL' or ('url' and 'thumb') is required when supplying guid."
                }));
              } else {
                validatedMedia.url = media.url;
                validatedMedia.thumb = media.thumb;
                callback(null, validatedMedia);
              }
            }
          }
        });
      } else if (!utils.isBlank(media.url) || !utils.isBlank(media.thumb)) {
        callback(new errors.ValidationError({
          "media": "'guid' or 'mediaId' is required when supplying a media.url"
        }));
      } else {
        callback(null, null);
      }
    };

    Medias.addOrUpdate = function(media, callback) {
      if (Object.isString(media.entity.id)) {
        media.entity.id = new ObjectId(media.entity.id);
      }
      this.model.collection.findAndModify({
        guid: media.guid
      }, [], {
        $set: media
      }, {
        "new": true,
        safe: true,
        upsert: true
      }, function(error, mediaCreated) {
        if (error != null) {
          callback(error);
          return;
        }
        logger.debug(mediaCreated);
        callback(null, mediaCreated);
      });
    };

    Medias.optionParser = function(options, q) {
      var query;
      query = this._optionParser(options, q);
      if (options.entityType != null) {
        query.where('entity.type', options.entityType);
      }
      if (options.entityId != null) query.where('entity.id', options.entityId);
      if (options.type != null) query.where('type', options.type);
      if (options.guid != null) query.where('guid', options.guid);
      if (options.tags != null) query["in"]('tags', options.tags);
      if (options.start != null) query.where('uploaddate').gte(options.start);
      if (options.end != null) query.where('uploaddate').lte(options.end);
      return query;
    };

    Medias.getByEntity = function(entityType, entityId, type, callback) {
      if (Object.isFunction(type)) {
        callback = type;
        this.get({
          entityType: entityType,
          entityId: entityId
        }, callback);
      } else {
        this.get({
          entityType: entityType,
          entityId: entityId,
          type: type
        }, callback);
      }
    };

    Medias.getByGuid = function(entityType, entityId, guid, callback) {
      if (Object.isString(entityId)) entityId = entityId;
      return this.get({
        entityType: entityType,
        entityId: entityId,
        guid: guid
      }, function(error, mediasDoc) {
        if ((mediasDoc != null) && mediasDoc.length) {
          return callback(null, mediasDoc[0]);
        } else {
          return callback(error, null);
        }
      });
    };

    return Medias;

  })(API);

  ClientInvitations = (function(_super) {

    __extends(ClientInvitations, _super);

    function ClientInvitations() {
      ClientInvitations.__super__.constructor.apply(this, arguments);
    }

    ClientInvitations.model = ClientInvitation;

    ClientInvitations.add = function(businessId, groupName, email, callback) {
      var key;
      key = hashlib.md5(config.secretWord + email + (new Date().toString())) + '-' + generatePassword(12, false, /\d/);
      return this._add({
        businessId: businessId,
        groupName: groupName,
        email: email,
        key: key
      }, callback);
    };

    ClientInvitations.list = function(businessId, groupName, callback) {
      var query;
      query = this._query();
      query.where("businessId", businessId);
      query.where("groupName", groupName);
      query.fields({
        email: 1
      });
      return query.exec(callback);
    };

    ClientInvitations.validate = function(key, callback) {
      return this.model.collection.findAndModify({
        key: key,
        status: choices.invitations.state.PENDING
      }, [], {
        $set: {
          status: choices.invitations.state.PROCESSED
        }
      }, {
        "new": true,
        safe: true
      }, function(error, invite) {
        if (error != null) {
          callback(error);
        } else if (!(invite != null)) {
          callback(new errors.ValidationError({
            "key": "Invalid Invite Key"
          }));
        } else {
          callback(null, invite);
        }
      });
    };

    ClientInvitations.del = function(businessId, groupName, pendingId, callback) {
      var query;
      query = this._query();
      query.where("businessId", businessId);
      query.where("groupName", groupName);
      query.where("_id", pendingId);
      return query.remove(callback);
    };

    return ClientInvitations;

  })(API);

  Tags = (function(_super) {

    __extends(Tags, _super);

    function Tags() {
      Tags.__super__.constructor.apply(this, arguments);
    }

    Tags.model = Tag;

    Tags.add = function(name, type, callback) {
      return this._add({
        name: name,
        type: type
      }, callback);
    };

    Tags.addAll = function(nameArr, type, callback) {
      var countUpdates, i, val, _len, _results;
      countUpdates = 0;
      _results = [];
      for (i = 0, _len = nameArr.length; i < _len; i++) {
        val = nameArr[i];
        _results.push(this.model.update({
          name: val,
          type: type
        }, {
          $inc: {
            count: 1
          }
        }, {
          upsert: true,
          safe: true
        }, function(error, success) {
          if (error != null) {
            callback(error);
            return;
          }
          if (++countUpdates === nameArr.length && Object.isFunction(callback)) {
            callback(null, countUpdates);
          }
        }));
      }
      return _results;
    };

    Tags.search = function(name, type, callback) {
      var query, re;
      re = new RegExp("^" + name + ".*", 'i');
      query = this._query();
      if ((name != null) || name.isBlank()) query.where('name', re);
      if (__indexOf.call(choices.tags.types._enum, type) >= 0) {
        query.where('type', type);
      }
      query.limit(10);
      return query.exec(callback);
    };

    return Tags;

  })(API);

  EventRequests = (function(_super) {

    __extends(EventRequests, _super);

    function EventRequests() {
      EventRequests.__super__.constructor.apply(this, arguments);
    }

    EventRequests.model = EventRequest;

    EventRequests.requestsPending = function(businessId, callback) {
      var query;
      if (Object.isString(businessId)) businessId = new ObjectId(businessId);
      query = this._query();
      query.where('organizationEntity.id', businessId);
      query.where('date.responded').exists(false);
      return query.exec(callback);
    };

    EventRequests.respond = function(requestId, callback) {
      var $options, $query, $update;
      if (Object.isString(requestId)) requestId = new ObjectId(requestId);
      $query = {
        _id: requestId
      };
      $update = {
        $set: {
          'date.responded': new Date()
        }
      };
      $options = {
        remove: false,
        "new": true,
        upsert: false
      };
      return this.model.collection.findAndModify($query, [], $update, $options, callback);
    };

    return EventRequests;

  })(API);

  Events = (function(_super) {

    __extends(Events, _super);

    function Events() {
      Events.__super__.constructor.apply(this, arguments);
    }

    Events.model = Event;

    Events.add = function(event, callback) {
      var self;
      self = Events;
      Medias.validateAndGetMediaURLs(event.entity.type, event.entity.id, "event", event.media, function(error, validatedMedia) {
        if (error != null) {
          callback(error);
          return;
        }
        if (!(validatedMedia != null)) {
          delete event.media;
        } else {
          event.media = validatedMedia;
        }
        return self._add(event, callback);
      });
    };

    Events.optionParser = function(options, q) {
      var query;
      query = this._optionParser(options, q);
      if (options.not != null) query.where('_id').$ne(options.not);
      if (options.upcoming != null) query.where('dates.actual').$gt(Date.now());
      return query;
    };

    Events.unRsvp = function(eventId, userId, callback) {
      var options, query, update;
      if (Object.isString(eventId)) eventId = new ObjectId(eventId);
      if (Object.isString(userId)) userId = new ObjectId(userId);
      query = {
        _id: eventId
      };
      update = {
        $pop: {
          rsvp: userId
        }
      };
      options = {
        remove: false,
        "new": true,
        upsert: false
      };
      return this.model.collection.findAndModify(query, [], update, options, callback);
    };

    Events.updateMediaByGuid = function(entityType, entityId, guid, mediasDoc, callback) {
      var query, set;
      if (Object.isString(entityId)) entityId = new ObjectId(entityId);
      query = this._query();
      query.where("entity.type", entityType);
      query.where("entity.id", entityId);
      query.where("media.guid", guid);
      set = {
        media: Medias.mediaFieldsForType(mediasDoc, "event")
      };
      query.update({
        $set: set
      }, function(error, success) {
        if (error != null) {
          callback(error);
        } else {
          callback(null, success);
        }
      });
    };

    Events.rsvp = function(eventId, userId, callback) {
      var $options, $push, $query, $update;
      if (Object.isString(eventId)) eventId = new ObjectId(eventId);
      if (Object.isString(userId)) userId = new ObjectId(userId);
      $push = {
        rsvp: userId
      };
      $query = {
        _id: eventId
      };
      $update = {
        $push: $push
      };
      $options = {
        remove: false,
        "new": true,
        upsert: false
      };
      return this.model.collection.findAndModify($query, [], $update, $options, function(error, event) {
        var who;
        callback(error, event);
        if (!(error != null)) {
          who = {
            type: choices.entities.CONSUMER,
            id: userId
          };
          return Streams.eventRsvped(who, event);
        }
      });
    };

    Events.setTransactonPending = Events.__setTransactionPending;

    Events.setTransactionProcessing = Events.__setTransactionProcessing;

    Events.setTransactionProcessed = Events.__setTransactionProcessed;

    Events.setTransactionError = Events.__setTransactionError;

    return Events;

  })(API);

  BusinessTransactions = (function(_super) {

    __extends(BusinessTransactions, _super);

    function BusinessTransactions() {
      BusinessTransactions.__super__.constructor.apply(this, arguments);
    }

    BusinessTransactions.model = db.BusinessTransaction;

    BusinessTransactions.add = function(data, callback) {
      var accessToken, amount, doc, self, timestamp,
        _this = this;
      if (Object.isString(data.organizationEntity.id)) {
        data.organizationEntity.id = new ObjectId(data.organizationEntity.id);
      }
      if (Object.isString(data.charity.id)) {
        data.organizationEntity.id = new ObjectId(data.charity.id);
      }
      if (Object.isString(data.locationId)) {
        data.locationId = new ObjectId(data.locationId);
      }
      if (Object.isString(data.registerId)) {
        data.registerId = new ObjectId(data.registerId);
      }
      if (!isNaN(data.timestamp)) {
        timestamp = Date.create(parseFloat(data.timestamp));
      } else {
        timestamp = Date.create(data.timestamp);
      }
      amount = void 0;
      if (data.amount != null) {
        amount = !isNaN(parseInt(data.amount)) ? Math.abs(parseInt(amount)) : void 0;
      }
      doc = {
        organizationEntity: {
          type: data.organizationEntity.type,
          id: data.organizationEntity.id,
          name: data.organizationEntity.name
        },
        charity: {
          type: choices.entities.CHARITY,
          id: data.charity.id,
          name: data.charity.name
        },
        postToFacebook: data.postToFacebook,
        locationId: data.locationId,
        registerId: data.registerId,
        barcodeId: !utils.isBlank(data.barcodeId) ? data.barcodeId + "" : void 0,
        transactionId: void 0,
        date: timestamp,
        time: new Date(0, 0, 0, timestamp.getHours(), timestamp.getMinutes(), timestamp.getSeconds(), timestamp.getMilliseconds()),
        amount: amount,
        receipt: void 0,
        hasReceipt: false,
        karmaPoints: 0,
        donationType: defaults.bt.donationType,
        donationValue: defaults.bt.donationValue,
        donationAmount: defaults.bt.donationAmount
      };
      if (data.userEntity != null) {
        doc.userEntity = {
          type: choices.entities.CONSUMER,
          id: data.userEntity.id,
          name: data.userEntity.name,
          screenName: data.userEntity.screenName
        };
      }
      self = this;
      accessToken = data.accessToken || null;
      return async.series({
        findRecentTapIns: function(cb) {
          if (doc.barcodeId != null) {
            return BusinessTransactions.findLastTapInByBarcodeIdAtBusinessSince(doc.barcodeId, doc.organizationEntity.id, doc.date.clone().addHours(-3), function(error, bt) {
              if (error != null) {
                cb(error, null);
              } else if (bt != null) {
                logger.warn("Ignoring tapIn - occcured within 3 hour time frame at this business");
                cb({
                  name: "IgnoreTapIn",
                  message: "User has tapped in multiple times with in a 3 hour time frame"
                });
              } else {
                return cb(null);
              }
            });
          } else {
            return cb(null);
          }
        },
        save: function(cb) {
          return Goodies.count({
            active: true,
            businessId: data.organizationEntity.id
          }, function(error, count) {
            var transaction, transactionData;
            if (error != null) {
              logger.error(error);
              cb(error, null);
              return;
            }
            if (count > 0) {
              logger.info("goodies exist, so we will be awarding karma points");
              doc.karmaPoints = globals.defaults.tapIns.karmaPointsEarned;
              if (doc.postToFacebook) {
                doc.karmaPoints = globals.defaults.tapIns.karmaPointsEarnedFB;
                doc.donationAmount += defaults.bt.donationFacebook;
              }
            }
            transactionData = {};
            transaction = void 0;
            if (doc.userEntity != null) {
              logger.silly("BT_TAPPED TRANSACTION CREATED");
              transaction = _this.createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.BT_TAPPED, transactionData, choices.transactions.directions.OUTBOUND, doc.userEntity);
            } else {
              transaction = _this.createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.STAT_BT_TAPPED, transactionData, choices.transactions.directions.OUTBOUND, void 0);
            }
            doc.transactions = {};
            doc.transactions.locked = false;
            doc.transactions.ids = [transaction.id];
            doc.transactions.log = [transaction];
            return _this.model.collection.insert(doc, {
              safe: true
            }, function(error, bt) {
              if (error != null) {
                logger.error(error);
                cb(error);
                return;
              }
              bt = Object.clone(bt[0]);
              tp.process(bt, transaction);
              Streams.btTapped(bt);
              cb(null, true);
              if (doc.userEntity != null) {
                logger.debug(accessToken);
                logger.debug(doc.postToFacebook);
                if ((accessToken != null) && doc.postToFacebook) {
                  logger.verbose("Posting tapIn to facebook");
                  fb.post('me/feed', accessToken, {
                    message: "I just tapped in at " + doc.organizationEntity.name + " and raised " + doc.donationAmount + "¢ for " + doc.charity.name + ", :)",
                    link: "http://www.goodybag.com/",
                    name: "Goodybag",
                    picture: "http://www.goodybag.com/static/images/gb-logo.png"
                  }, function(error, response) {
                    if (error != null) {
                      return logger.error(error);
                    } else {
                      return logger.debug(response);
                    }
                  });
                }
                return;
              }
            });
          });
        }
      }, function(error, results) {
        if (error != null) {
          if ((error.name != null) && error.name === "IgnoreTapIn") {
            callback(null, {
              ignored: true
            });
            return;
          }
          callback(error);
        } else if (results.save != null) {
          callback(null, {
            ignored: false
          });
        }
      });
    };

    BusinessTransactions.findLastTapInByBarcodeIdAtBusinessSince = function(barcodeId, businessId, since, callback) {
      if (Object.isString(businessId)) businessId = new ObjectId(businessId);
      this.model.collection.findOne({
        barcodeId: barcodeId,
        "organizationEntity.id": businessId,
        date: {
          $gte: since
        }
      }, {
        sort: {
          date: -1
        },
        limit: 1
      }, callback);
    };

    BusinessTransactions.findOneRecentTapIn = function(businessId, locationId, registerId, callback) {
      if (Object.isString(businessId)) businessId = new ObjectId(businessId);
      if (Object.isString(locationId)) locationId = new ObjectId(locationId);
      if (Object.isString(registerId)) registerId = new ObjectId(registerId);
      this.model.collection.findOne({
        "organizationEntity.id": businessId,
        locationId: locationId,
        registerId: registerId
      }, {
        sort: {
          date: -1
        }
      }, callback);
    };

    BusinessTransactions.associateReceipt = function(id, receipt, callback) {
      if (Object.isString(id)) id = new ObjectId(id);
      this.model.collection.update({
        _id: id,
        hasReceipt: false
      }, {
        $set: {
          receipt: new Binary(receipt),
          hasReceipt: true
        }
      }, {
        safe: true
      }, callback);
    };

    BusinessTransactions.claimBarcodeId = function(entity, barcodeId, callback) {
      var $set;
      if (Object.isString(entity.id)) entity.id = new ObjectId(entity.id);
      barcodeId = barcodeId + "";
      $set = {
        userEntity: {
          type: choices.entities.CONSUMER,
          id: entity.id,
          name: entity.name,
          screenName: entity.screenName
        }
      };
      this.model.collection.update({
        barcodeId: barcodeId
      }, {
        $set: $set
      }, {
        multi: true,
        safe: true
      }, callback);
    };

    BusinessTransactions.replaceBarcodeId = function(oldId, barcodeId, callback) {
      var $set;
      if (utils.isBlank(oldId)) {
        callback(new errors.ValidationError("oldId is required fields"));
        return;
      }
      if (utils.isBlank(barcodeId)) {
        callback(new errors.ValidationError("barcodeId is required fields"));
        return;
      }
      $set = {
        barcodeId: barcodeId
      };
      this.model.collection.update({
        barcodeId: oldId
      }, {
        $set: $set
      }, {
        multi: true,
        safe: true
      }, callback);
    };

    BusinessTransactions.byUser = function(userId, options, callback) {
      var query;
      if (Object.isFunction(options)) {
        callback = options;
        options = {};
      }
      query = this.optionParser(options);
      query.where('userEntity.id', userId);
      return query.exec(callback);
    };

    BusinessTransactions.byBarcode = function(barcodeId, options, callback) {
      var query;
      if (Object.isFunction(options)) {
        callback = options;
        options = {};
      }
      query = this.optionParser(options);
      query.where('barcodeId', barcodeId);
      return query.exec(callback);
    };

    BusinessTransactions.byBusiness = function(businessId, options, callback) {
      var query;
      if (Object.isFunction(options)) {
        callback = options;
        options = {};
      }
      query = this.optionParser(options);
      query.fields(["_id", "amount", "barcodeId", "date", "donationAmount", "locationId", "organizationEntity", "registerId", "time", "transactionId", "userEntity.screenName"]);
      query.where('organizationEntity.id', businessId);
      if (options.location != null) query.where('locationId', options.location);
      if (options.date != null) query.where('date', options.date);
      logger.info(options);
      return query.exec(callback);
    };

    BusinessTransactions.byBusinessCount = function(businessId, options, callback) {
      var query;
      if (Object.isFunction(options)) {
        callback = options;
        options = {};
      }
      query = this.optionParser(options);
      query.fields(["_id"]);
      query.where('organizationEntity.id', businessId);
      if (options.location != null) query.where('locationId', options.location);
      if (options.date != null) query.where('date', options.date);
      logger.info(options);
      query.count();
      return query.exec(callback);
    };

    BusinessTransactions.byBusinessGbCostumers = function(businessId, options, callback) {
      var query;
      if (Object.isFunction(options)) {
        callback = options;
        options = {};
      }
      if (!(options.limit != null)) options.limit = 25;
      if (!(options.skip != null)) options.skip = 0;
      query = this.optionParser(options);
      query.where('organizationEntity.id', businessId);
      query.where('userEntity.id').exists(true);
      if (options.location != null) query.where('locationId', options.location);
      return query.exec(callback);
    };

    BusinessTransactions.test = function(callback) {
      var data;
      data = {
        "barcodeId": "aldkfjs12lsdfl12lskdjf",
        "registerId": "asdlf3jljsdlfoiuwirljf",
        "locationId": new ObjectId("4efd61571927c5951200002b"),
        "date": new Date(2011, 11, 30, 12, 22, 22),
        "time": new Date(0, 0, 0, 12, 22, 22),
        "amount": 18.54,
        "donationAmount": 0.03,
        "organizationEntity": {
          "id": new ObjectId("4eda8f766412f8805e6e864c"),
          "type": "client"
        },
        "userEntity": {
          "id": new ObjectId("4eebdcc12e7501d8d7036cb1"),
          "type": "consumer"
        }
      };
      return this.model.collection.insert(data, {
        safe: true
      }, callback);
    };

    BusinessTransactions.setTransactonPending = BusinessTransactions.__setTransactionPending;

    BusinessTransactions.setTransactionProcessing = BusinessTransactions.__setTransactionProcessing;

    BusinessTransactions.setTransactionProcessed = BusinessTransactions.__setTransactionProcessed;

    BusinessTransactions.setTransactionError = BusinessTransactions.__setTransactionError;

    return BusinessTransactions;

  })(API);

  BusinessRequests = (function(_super) {

    __extends(BusinessRequests, _super);

    function BusinessRequests() {
      BusinessRequests.__super__.constructor.apply(this, arguments);
    }

    BusinessRequests.model = BusinessRequest;

    BusinessRequests.add = function(userId, business, callback) {
      var data, instance;
      data = {
        businessName: business
      };
      if (userId != null) {
        data.userEntity = {
          type: choices.entities.CONSUMER,
          id: userId
        };
        data.loggedin = true;
      } else {
        data.loggedin = false;
      }
      instance = new this.model(data);
      return instance.save(callback);
    };

    return BusinessRequests;

  })(API);

  Streams = (function(_super) {

    __extends(Streams, _super);

    function Streams() {
      Streams.__super__.constructor.apply(this, arguments);
    }

    Streams.model = Stream;

    Streams.add = function(stream, callback) {
      var instance, model;
      model = {
        who: stream.who,
        by: stream.by,
        entitiesInvolved: stream.entitiesInvolved,
        what: stream.what,
        when: stream.when || new Date(),
        where: stream.where,
        events: stream.events,
        private: stream.private || false,
        data: stream.data || {},
        feeds: stream.feeds,
        feedSpecificData: stream.feedSpecificData,
        entitySpecificData: stream.entitySpecificData,
        dates: {
          created: new Date(),
          lastModified: new Date()
        }
      };
      instance = new this.model(model);
      return instance.save(callback);
    };

    Streams.fundsDonated = function(who, charity, donationLogDoc, callback) {
      var donation, stream;
      if (Object.isString(who.id)) who.id = new ObjectId(who.id);
      if (Object.isString(charity.id)) charity.id = new ObjectId(charity.id);
      donation = {
        id: donationLogDoc._id,
        type: choices.objects.DONATION_LOG
      };
      stream = {
        who: who,
        entitiesInvolved: [who, charity],
        what: donation,
        when: donationLogDoc.dates.donated,
        events: [choices.eventTypes.FUNDS_DONATED],
        data: {},
        feeds: {
          global: true
        },
        private: false
      };
      stream.data = {
        amount: donationLogDoc.amount
      };
      stream.feedSpecificData = {};
      stream.feedSpecificData.involved = {
        charity: charity
      };
      logger.silly(stream.data);
      this.add(stream, function(error, data) {
        if (error != null) logger.error(error);
        logger.debug(data);
        if (callback != null) callback(error, data);
      });
    };

    Streams.pollCreated = function(pollDoc, callback) {
      var poll, stream, user, who;
      if (Object.isString(pollDoc._id)) pollDoc._id = new ObjectId(pollDoc._id);
      if (Object.isString(pollDoc.entity.id)) {
        pollDoc.entity.id = new ObjectId(pollDoc.entity.id);
      }
      if (Object.isString(pollDoc.createdBy.id)) {
        pollDoc.createdBy.id = new ObjectId(pollDoc.createdBy.id);
      }
      who = pollDoc.entity;
      poll = {
        type: choices.objects.POLL,
        id: pollDoc._id
      };
      user = void 0;
      if (who.type === choices.entities.BUSINESS) {
        user = {
          type: pollDoc.createdBy.type,
          id: pollDoc.createdBy.id
        };
      }
      stream = {
        who: who,
        entitiesInvolved: [who],
        what: poll,
        when: pollDoc.dates.created,
        events: [choices.eventTypes.POLL_CREATED],
        data: {},
        feeds: {
          global: false
        },
        private: false
      };
      if (user != null) {
        stream.by = user;
        stream.entitiesInvolved.push(user);
      }
      stream.data = {
        poll: {
          question: pollDoc.question,
          name: pollDoc.name
        }
      };
      logger.debug(stream);
      return this.add(stream, callback);
    };

    Streams.pollUpdated = function(pollDoc, callback) {
      var poll, stream, user, who;
      if (Object.isString(pollDoc._id)) pollDoc._id = new ObjectId(pollDoc._id);
      if (Object.isString(pollDoc.entity.id)) {
        pollDoc.entity.id = new ObjectId(pollDoc.entity.id);
      }
      if (Object.isString(pollDoc.lastModifiedBy.id)) {
        pollDoc.lastModifiedBy.id = new ObjectId(pollDoc.lastModifiedBy.id);
      }
      who = pollDoc.entity;
      poll = {
        type: choices.objects.POLL,
        id: pollDoc._id
      };
      user = void 0;
      if (who.type === choices.entities.BUSINESS) {
        user = {
          type: pollDoc.lastModifiedBy.type,
          id: pollDoc.lastModifiedBy.id
        };
      }
      stream = {
        who: who,
        entitiesInvolved: [who],
        what: poll,
        when: pollDoc.dates.lastModified,
        events: [choices.eventTypes.POLL_UPDATED],
        data: {},
        feeds: {
          global: false
        },
        private: false
      };
      if (user != null) {
        stream.by = user;
        stream.entitiesInvolved.push(user);
      }
      stream.data = {
        poll: {
          question: pollDoc.question,
          name: pollDoc.name
        }
      };
      return this.add(stream, callback);
    };

    Streams.pollDeleted = function(pollDoc, callback) {
      var poll, stream, user, who;
      if (Object.isString(pollDoc._id)) pollDoc._id = new ObjectId(pollDoc._id);
      if (Object.isString(pollDoc.entity.id)) {
        pollDoc.entity.id = new ObjectId(pollDoc.entity.id);
      }
      if (Object.isString(pollDoc.lastModifiedBy.id)) {
        pollDoc.lastModifiedBy.id = new ObjectId(pollDoc.lastModifiedBy.id);
      }
      who = pollDoc.entity.type;
      poll = {
        type: choices.objects.POLL,
        id: pollDoc._id
      };
      user = void 0;
      if (who.type === choices.entities.BUSINESS) user = pollDoc.lastModifiedBy;
      stream = {
        who: who,
        entitiesInvolved: [who],
        what: poll,
        when: pollDoc.dates.lastModified,
        events: [choices.eventTypes.POLL_DELETED],
        data: {},
        feeds: {
          global: false
        },
        private: false
      };
      if (user != null) {
        stream.by = user;
        stream.entitiesInvolved.push(user);
      }
      stream.data = {
        poll: {
          question: pollDoc.question,
          name: pollDoc.name
        }
      };
      return this.add(stream, callback);
    };

    Streams.pollAnswered = function(who, timestamp, pollDoc, callback) {
      var poll, stream;
      if (Object.isString(who.id)) who.id = new ObjectId(who.id);
      if (Object.isString(pollDoc._id)) pollDoc._id = new ObjectId(pollDoc._id);
      if (Object.isString(pollDoc.entity.id)) {
        pollDoc.entity.id = new ObjectId(pollDoc.entity.id);
      }
      poll = {
        type: choices.objects.POLL,
        id: pollDoc._id
      };
      stream = {
        who: who,
        entitiesInvolved: [who, pollDoc.entity],
        what: poll,
        when: timestamp,
        events: [choices.eventTypes.POLL_ANSWERED],
        data: {},
        feeds: {
          global: false
        },
        private: false
      };
      stream.data = {
        poll: {
          question: pollDoc.question,
          name: pollDoc.name
        }
      };
      return this.add(stream, callback);
    };

    Streams.discussionCreated = function(discussionDoc, callback) {
      var discussion, stream, user, who;
      logger.debug(discussionDoc);
      if (Object.isString(discussionDoc._id)) {
        discussionDoc._id = new ObjectId(discussionDoc._id);
      }
      if (Object.isString(discussionDoc.entity.id)) {
        discussionDoc.entity.id = new ObjectId(discussionDoc.entity.id);
      }
      if (Object.isString(discussionDoc.createdBy.id)) {
        discussionDoc.createdBy.id = new ObjectId(discussionDoc.createdBy.id);
      }
      who = discussionDoc.entity;
      discussion = {
        type: choices.objects.DISCUSSION,
        id: discussionDoc._id
      };
      user = void 0;
      if (who.type === choices.entities.BUSINESS) {
        user = {
          type: discussionDoc.createdBy.type,
          id: discussionDoc.createdBy.id
        };
      }
      stream = {
        who: who,
        entitiesInvolved: [who],
        what: discussion,
        when: discussionDoc.dates.created,
        events: [choices.eventTypes.DISCUSSION_CREATED],
        data: {},
        feeds: {
          global: false
        }
      };
      if (user != null) {
        stream.by = user;
        stream.entitiesInvolved.push(user);
      }
      stream.data = {
        discussion: {
          name: discussionDoc.name
        }
      };
      logger.debug(stream);
      return this.add(stream, callback);
    };

    Streams.discussionUpdated = function(discussionDoc, callback) {
      var discussion, stream, user, who;
      if (Object.isString(discussionDoc._id)) {
        discussionDoc._id = new ObjectId(discussionDoc._id);
      }
      if (Object.isString(discussionDoc.entity.id)) {
        discussionDoc.entity.id = new ObjectId(discussionDoc.entity.id);
      }
      if (Object.isString(discussionDoc.lastModifiedBy.id)) {
        discussionDoc.lastModifiedBy.id = new ObjectId(discussionDoc.lastModifiedBy.id);
      }
      who = discussionDoc.entity;
      discussion = {
        type: choices.objects.DISCUSSION,
        id: discussionDoc._id
      };
      user = void 0;
      if (who.type === choices.entities.BUSINESS) {
        user = {
          type: discussionDoc.lastModifiedBy.type,
          id: discussionDoc.lastModifiedBy.id
        };
      }
      stream = {
        who: who,
        entitiesInvolved: [who],
        what: discussion,
        when: discussionDoc.dates.lastModified,
        events: [choices.eventTypes.DISCUSSION_UPDATED],
        data: {},
        feeds: {
          global: false
        }
      };
      if (user != null) {
        stream.by = user;
        stream.entitiesInvolved.push(user);
      }
      stream.data = {
        discussion: {
          name: discussionDoc.name
        }
      };
      return this.add(stream, callback);
    };

    Streams.discussionDeleted = function(discussionDoc, callback) {
      var discussion, stream, user, who;
      if (Object.isString(discussionDoc._id)) {
        discussionDoc._id = new ObjectId(discussionDoc._id);
      }
      if (Object.isString(discussionDoc.entity.id)) {
        discussionDoc.entity.id = new ObjectId(discussionDoc.entity.id);
      }
      if (Object.isString(discussionDoc.lastModifiedBy.id)) {
        discussionDoc.lastModifiedBy.id = new ObjectId(discussionDoc.lastModifiedBy.id);
      }
      who = discussionDoc.entity;
      discussion = {
        type: choices.objects.DISCUSSION,
        id: discussionDoc._id
      };
      user = void 0;
      if (who.type === choices.entities.BUSINESS) {
        user = {
          type: discussionDoc.lastModifiedBy.type,
          id: discussionDoc.lastModifiedBy.id
        };
      }
      stream = {
        who: who,
        entitiesInvolved: [who],
        what: discussion,
        when: discussionDoc.dates.lastModified,
        events: [choices.eventTypes.DISCUSSION_DELETED],
        data: {},
        feeds: {
          global: false
        }
      };
      if (user != null) {
        stream.by = user;
        stream.entitiesInvolved.push(user);
      }
      stream.data = {
        discussion: {
          name: discussionDoc.name
        }
      };
      return this.add(stream, callback);
    };

    Streams.discussionAnswered = function(who, timestamp, discussionDoc, callback) {
      var discussion, stream;
      if (Object.isString(who.id)) who.id = new ObjectId(who.id);
      if (Object.isString(discussionDoc._id)) {
        discussionDoc._id = new ObjectId(discussionDoc._id);
      }
      if (Object.isString(discussionDoc.entity.id)) {
        discussionDoc.entity.id = new ObjectId(discussionDoc.entity.id);
      }
      discussion = {
        type: choices.objects.DISCUSSION,
        id: discussionDoc._id
      };
      stream = {
        who: who,
        entitiesInvolved: [who, discussionDoc.entity],
        what: discussion,
        when: timestamp,
        events: [choices.eventTypes.DISCUSSION_ANSWERED],
        data: {},
        feeds: {
          global: false
        }
      };
      stream.data = {
        discussion: {
          name: discussionDoc.name
        }
      };
      return this.add(stream, callback);
    };

    Streams.eventRsvped = function(who, eventDoc, callback) {
      var event, stream;
      if (Object.isString(who.id)) who.id = new ObjectId(who.id);
      event = {
        type: choices.objects.EVENT,
        id: eventDoc._id
      };
      stream = {
        who: who,
        entitiesInvolved: [who, eventDoc.entity],
        what: event,
        when: new Date(),
        events: [choices.eventTypes.EVENT_RSVPED],
        data: {},
        feeds: {
          global: true
        }
      };
      stream.data = {
        event: {
          entity: {
            name: eventDoc.entity.name
          },
          locationId: eventDoc.locationId,
          location: eventDoc.location,
          dates: {
            actual: eventDoc.dates.actual
          }
        }
      };
      return this.add(stream, callback);
    };

    Streams.btTapped = function(btDoc, callback) {
      var stream, tapIn, who;
      if (Object.isString(btDoc._id)) btDoc._id = new ObjectId(btDoc._id);
      if (Object.isString(btDoc.organizationEntity.id)) {
        btDoc.organizationEntity.id = new ObjectId(btDoc.organizationEntity.id);
      }
      if ((btDoc.userEntity != null) && (btDoc.userEntity.id != null)) {
        if (Object.isString(btDoc.userEntity.id)) {
          btDoc.userEntity.id = new ObjectId(btDoc.userEntity.id);
        }
      } else {
        btDoc.userEntity = {};
        btDoc.userEntity.type = choices.entities.CONSUMER;
        btDoc.userEntity.id = new ObjectId("000000000000000000000000");
        btDoc.userEntity.name = "Someone";
      }
      tapIn = {
        type: choices.objects.TAPIN,
        id: btDoc._id
      };
      who = btDoc.userEntity;
      stream = {
        who: who,
        entitiesInvolved: [who, btDoc.organizationEntity, btDoc.charity],
        what: tapIn,
        when: btDoc.date,
        where: {
          org: btDoc.organizationEntity,
          locationId: btDoc.locationId
        },
        events: [choices.eventTypes.BT_TAPPED],
        data: {
          donationAmount: btDoc.donationAmount,
          charity: btDoc.charity
        },
        feeds: {
          global: true
        }
      };
      stream.feedSpecificData = {};
      stream.feedSpecificData.involved = {
        amount: btDoc.amount,
        donationAmount: btDoc.donationAmount
      };
      logger.debug(stream);
      return this.add(stream, callback);
    };

    /*
      example1: client created a poll:
        who = client
        what = [client, business, poll]
        when = timestamp that poll was created
        where = undefined
        events = [pollCreated]
        entitiesInvolved = [client, business]
        data:
          pollCreated:
            pollId: ObjectId
            pollName: String
            businessId: ObjectId
    */

    /*
      example2: consumer created a poll:
        who = consumer
        what = [consumer, poll]
        when = timestamp that poll was created
        where = undefined
        events = [pollCreated]
        entitiesInvolved = [client]
        data:
          pollCreated:
            pollId: ObjectId
            pollName: String
    */

    /*
      example3: consumer attend an event and tapped in:
        who = consumer
        what = [consumer, business, businessTransaction]
        when = timestamp the user tappedIn
        where: undefined
          org:
            type: business
            id: ObjectId
          orgName: String
          locationId: ObjectId
          locationName: String
        events = [attended, eventTapIn]
        entitiesInvolved = [client, business]
        data:
          eventTapIn:
            eventId: ObjectId
            businessTransactionId: ObjectId
            spent: XX.xx
    */

    Streams.global = function(options, callback) {
      var query;
      query = this.optionParser(options);
      query.where("feeds.global", true);
      query.sort("dates.lastModified", -1);
      query.fields(["who.type", "who.screenName", "by", "what", "when", "where", "events", "dates", "data"]);
      return query.exec(callback);
    };

    Streams.business = function(businessId, options, callback) {
      var query;
      query = this.optionParser(options);
      query.sort("dates.lastModified", -1);
      query.where("entitiesInvolved.type", choices.entities.BUSINESS);
      query.where("entitiesInvolved.id", businessId);
      query.only({
        "who.type": 1,
        "who.screenName": 1,
        "by": 1,
        "what": 1,
        "when": 1,
        "where": 1,
        "events": 1,
        "dates": 1,
        "data": 1,
        "feedSpecificData.involved": 1,
        "_id": 0,
        "id": 0
      });
      return query.exec(callback);
    };

    Streams.businessWithConsumerByScreenName = function(businessId, screenName, options, callback) {
      var query;
      query = this.optionParser(options);
      query.sort("dates.lastModified", -1);
      query.where("entitiesInvolved.type", choices.entities.BUSINESS);
      query.where("entitiesInvolved.id", businessId);
      query.where("who.type", choices.entities.CONSUMER);
      query.where("who.screenName", screenName);
      query.fields(["who.type", "who.screenName", "what", "when", "where", "events", "dates", "data", "feedSpecificData.involved"]);
      return query.exec(callback);
    };

    Streams.consumerPersonal = function(consumerId, options, callback) {
      var query;
      query = this.optionParser(options);
      query.sort("dates.lastModified", -1);
      query.where("who.type", choices.entities.CONSUMER);
      query.where("who.id", consumerId);
      query.fields(["who.type", "who.name", "who.screenName", "who.id", "by", "what", "when", "where", "events", "dates", "data", "feedSpecificData.involved"]);
      return query.exec(callback);
    };

    Streams.getLatest = function(entity, limit, offset, callback) {
      var query;
      query = this._query();
      query.limit(limit);
      query.skip(offset);
      query.sort("dates.lastModified", -1);
      if (entity != null) {
        query.where("entity.type", entity.type);
        query.where("entity.id", entity.id);
      }
      return query.exec(function(error, activities) {
        var activity, cQuery, ids, _i, _len;
        if (error != null) {
          callback(error);
          return;
        } else if (activities.length <= 0) {
          callback(error, {
            activities: [],
            consumers: []
          });
          return;
        }
        ids = [];
        for (_i = 0, _len = activities.length; _i < _len; _i++) {
          activity = activities[_i];
          ids.push({
            _id: activity.entity.id
          });
        }
        cQuery = Consumers._query();
        cQuery.or(ids);
        cQuery.only("email");
        return cQuery.exec(function(error, consumers) {
          if (error != null) {
            callback(error);
            return;
          }
          return callback(error, {
            activities: activities,
            consumers: consumers
          });
        });
      });
    };

    return Streams;

  })(API);

  PasswordResetRequests = (function(_super) {

    __extends(PasswordResetRequests, _super);

    function PasswordResetRequests() {
      PasswordResetRequests.__super__.constructor.apply(this, arguments);
    }

    PasswordResetRequests.model = PasswordResetRequest;

    PasswordResetRequests.update = function(id, doc, dbOptions, callback) {
      var where;
      if (Object.isString(id)) id = new ObjectId(id);
      if (Object.isFunction(dbOptions)) {
        callback = dbOptions;
        dbOptions = {
          safe: true
        };
      }
      where = {
        _id: id
      };
      this.model.update(where, doc, dbOptions, callback);
    };

    PasswordResetRequests.add = function(type, email, callback) {
      var UserClass,
        _this = this;
      if (type === choices.entities.CONSUMER) {
        UserClass = Consumers;
      } else if (type === choices.entities.CLIENT) {
        UserClass = Clients;
      } else {
        callback(new errors.ValidationError({
          "type": "Not a valid entity type."
        }));
        return;
      }
      UserClass.getByEmail(email, {
        _id: 1,
        "facebook.id": 1
      }, function(error, user) {
        var instance, request;
        if (error != null) {
          callback(error);
          return;
        }
        if (!(user != null)) {
          callback(new errors.ValidationError("That email is not registered with Goodybag.", {
            "email": "not found"
          }));
          return;
        }
        if ((user.facebook != null) && (user.facebook.id != null)) {
          callback(new errors.ValidationError("Your account is authenticated through Facebook.", {
            "user": "facebookuser"
          }));
          return;
        }
        request = {
          entity: {
            type: type,
            id: user._id
          },
          key: hashlib.md5(config.secretWord + email + (new Date().toString()))
        };
        instance = new _this.model(request);
        instance.save(callback);
      });
    };

    PasswordResetRequests.pending = function(key, callback) {
      var date, where;
      date = (new Date()).addMinutes(0 - globals.defaults.passwordResets.keyLife);
      where = {
        key: key,
        date: {
          $gt: date
        },
        consumed: false
      };
      this.model.findOne(where, callback);
    };

    PasswordResetRequests.consume = function(key, newPassword, callback) {
      var id, self;
      self = this;
      if (Object.isString(id)) id = new ObjectId(id);
      self.pending(key, function(error, resetRequest) {
        var userClass;
        if (error != null) {
          callback(error);
          return;
        }
        if (!(resetRequest != null)) {
          callback(new errors.ValidationError("The password-reset key is invalid, expired or already used.", {
            "key": "invalid, expired,or used"
          }));
          return;
        }
        switch (resetRequest.entity.type) {
          case choices.entities.CONSUMER:
            userClass = Consumers;
            break;
          case choices.entities.CLIENT:
            userClass = Clients;
            break;
          default:
            callback(new errors.ValidationError({
              "type": "Not a valid entity type."
            }));
        }
        userClass._updatePasswordHelper(resetRequest.entity.id, newPassword, function(error, count) {
          var success;
          if (error != null) {
            callback(error);
            return;
          }
          success = count > 0;
          callback(null, success);
          self.update(resetRequest._id, {
            $set: {
              consumed: true
            }
          }, function(error) {
            if (error != null) {
              logger.error(error);
              return;
            }
          });
        });
      });
    };

    return PasswordResetRequests;

  })(API);

  Goodies = (function(_super) {

    __extends(Goodies, _super);

    function Goodies() {
      Goodies.__super__.constructor.apply(this, arguments);
    }

    Goodies.model = Goody;

    Goodies.updateWithBusiness = function(gid, bid, data, callback) {
      var $query, $update;
      if (Object.isString(gid)) gid = ObjectId(gid);
      if (Object.isString(bid)) bid = ObjectId(bid);
      if (data.karmaPointsRequired % 10 !== 0 || data.karmaPointsRequired < 10) {
        return callback(new errors.ValidationError("karmaPointsRequired is invalid", {
          karmaPointsRequired: "must be divisible by 10"
        }));
      }
      $query = {
        "_id": gid,
        "org.id": bid
      };
      $update = {
        $set: data
      };
      return this.model.collection.update($query, $update, callback);
    };

    /*
       * Gets statistics on a specific goody
       *   {
       *     timesRedeemed: 5
       *   }
       * @param  {String} goodyId The ID of the goody
    */

    Goodies.statistics = function(gid, callback) {
      var $fields, $query, query, results;
      if (Object.isString(gid)) gid = ObjectId(gid);
      results = {};
      $query = {
        "goody.id": gid
      };
      $fields = {
        "_id": 1
      };
      query = RedemptionLogs.model.find($query);
      query.count();
      return query.exec(function(error, count) {
        if (error != null) return callback(error);
        results.timesRedeemed = count;
        return callback(null, results);
      });
    };

    /* _add_
    */

    Goodies.add = function(data, callback) {
      var doc;
      try {
        if (Object.isString(data.org.id)) data.org.id = ObjectId(data.org.id);
      } catch (error) {
        callback(error);
        return;
      }
      if (data.karmaPointsRequired % 10 !== 0 || data.karmaPointsRequired < 10) {
        callback(new errors.ValidationError("karmaPointsRequired is invalid", {
          karmaPointsRequired: "must be divisible by 10"
        }));
        return;
      }
      if (utils.isBlank(data.name)) {
        callback(new errors.ValidationError("name is required"));
        return;
      }
      doc = {
        _id: new ObjectId(),
        org: data.org,
        name: data.name,
        description: data.description != null ? data.description : void 0,
        active: data.active != null ? data.active : true,
        karmaPointsRequired: parseInt(data.karmaPointsRequired)
      };
      this.model.collection.insert(doc, {
        safe: true
      }, function(err, num) {
        if (err != null) {
          logger.error(err);
          callback(err);
          return;
        } else if (num < 1) {
          error = new Error("Goody was not saved!");
          logger.error(error);
          callback(error);
          return;
        }
        return callback(null, doc._id);
      });
    };

    /* _update_
    */

    Goodies.update = function(goodyId, data, callback) {
      var $where, doc;
      try {
        if (Object.isString(goodyId)) goodyId = new ObjectId(goodyId);
        if (Object.isString(data.org.id)) data.org.id = new ObjectId(data.org.id);
      } catch (error) {
        callback(error);
        return;
      }
      if (data.karmaPointsRequired % 10 !== 0 || data.karmaPointsRequired < 10) {
        callback(new errors.ValidationError("karmaPointsRequired is invalid", {
          karmaPointsRequired: "must be a factor of 10"
        }));
        return;
      }
      if (utils.isBlank(data.name)) {
        callback(new errors.ValidationError("name is required"));
        return;
      }
      doc = {
        org: data.org,
        name: data.name,
        description: data.description != null ? data.description : void 0,
        active: data.active != null ? data.active : true,
        karmaPointsRequired: parseInt(data.karmaPointsRequired)
      };
      $where = {
        _id: goodyId
      };
      this.model.collection.update($where, doc, {
        safe: true
      }, function(err, num) {
        if (err != null) {
          logger.error(err);
          callback(err);
          return;
        } else if (num < 1) {
          error = new Error("Goody was not saved!");
          logger.error(error);
          callback(error);
          return;
        }
        return callback(null, true);
      });
    };

    /* _get_
    */

    Goodies.get = function(goodyId, businessId, callback) {
      var $query;
      try {
        if (Object.isString(goodyId)) goodyId = new ObjectId(goodyId);
      } catch (error) {
        callback(error);
        return;
      }
      if (Object.isFunction(businessId)) {
        callback = businessId;
        delete businessId;
      } else {
        try {
          if (Object.isString(businessId)) businessId = new ObjectId(businessId);
        } catch (error) {
          callback(error);
          return;
        }
      }
      $query = {};
      $query["_id"] = goodyId;
      $query["active"] = true;
      if (businessId != null) {
        $query["org.type"] = choices.organizations.BUSINESS;
        $query["org.id"] = businessId;
      }
      return this.model.collection.findOne($query, function(error, goody) {
        if (error != null) {
          logger.error(error);
          callback(error);
          return;
        }
        callback(error, goody);
      });
    };

    /* _getByBusiness_
    */

    Goodies.getByBusiness = function(businessId, options, callback) {
      var $query, defaultOpts;
      defaultOpts = {
        active: true,
        sort: 1
      };
      try {
        if (Object.isString(businessId)) businessId = new ObjectId(businessId);
      } catch (error) {
        callback(error);
        return;
      }
      if (Object.isFunction(options)) {
        callback = options;
        options = defaultOpts;
      } else {
        options = {
          active: options.active != null ? options.active : defaultOpts.active,
          sort: options.sort || defaultOpts.sort
        };
      }
      $query = {
        "org.id": businessId,
        "active": options.active
      };
      this.model.collection.find($query, {
        sort: {
          karmaPointsRequired: 1
        }
      }, function(error, cursor) {
        if (error != null) {
          logger.error(error);
          callback(error);
          return;
        }
        return cursor.toArray(function(error, goodies) {
          return callback(error, goodies);
        });
      });
    };

    /* _remove_
    */

    Goodies.remove = function(goodyId, callback) {
      try {
        if (Object.isString(goodyId)) goodyId = new ObjectId(goodyId);
      } catch (error) {
        callback(error);
        return;
      }
      return this.model.collection.update({
        _id: goodyId
      }, {
        $set: {
          active: false
        }
      }, {
        safe: true
      }, function(err) {
        if (err != null) {
          logger.error(err);
          callback(err);
        } else {
          callback(err);
        }
      });
    };

    /* _count_
    */

    Goodies.count = function(options, callback) {
      var $query;
      $query = {};
      if (Object.isFunction(options)) {
        callback = options;
        delete options;
      } else {
        if (options.businessId != null) {
          try {
            if (Object.isString(options.businessId)) {
              options.businessId = new ObjectId(options.businessId);
            }
          } catch (error) {
            logger.error(error);
            callback(error);
            return;
          }
          $query["org.type"] = choices.organizations.BUSINESS;
          $query["org.id"] = options.businessId;
        }
        if (options.active != null) $query["active"] = options.active;
      }
      return this.model.collection.count($query, function(error, count) {
        if (error != null) {
          logger.error(error);
          callback(error);
        } else {
          callback(error, count);
        }
      });
    };

    /* _redeem_
    */

    Goodies.redeem = function(goodyId, consumerId, businessId, locationId, registerId, timestamp, callback) {
      try {
        if (Object.isString(goodyId)) goodyId = new ObjectId(goodyId);
        if (Object.isString(consumerId)) consumerId = new ObjectId(consumerId);
        if (Object.isString(businessId)) businessId = new ObjectId(businessId);
        if (Object.isString(locationId)) locationId = new ObjectId(locationId);
        if (Object.isString(registerId)) registerId = new ObjectId(registerId);
        timestamp = Date.create(timestamp);
      } catch (error) {
        callback(error);
        return;
      }
      return this.get(goodyId, businessId, function(error, goody) {
        if (error != null) {
          logger.error(error);
          callback(error);
          return;
        }
        if (!(goody != null) || !goody.active) {
          error = {
            message: "sorry that goody doesn't exists or is no longer active"
          };
          logger.error(error);
          callback(error, false);
          return;
        }
        return Consumers.one(consumerId, {
          firstName: 1,
          lastName: 1,
          screenName: 1
        }, function(error, consumer) {
          var $inc, $pushAll, $query, $update, entity, fields, redemptionLogTransaction, transactionData, transactionEntity;
          if (error != null) {
            logger.error;
            callback(error);
            return;
          }
          if (!(consumer != null)) {
            error = {
              message: "consumer does not exist"
            };
            logger.error(error);
            callback(error);
            return;
          }
          entity = {
            type: choices.entities.CONSUMER,
            id: consumerId,
            name: "" + consumer.firstName + " " + consumer.lastName,
            screenName: consumer.screenName
          };
          transactionEntity = entity;
          transactionData = {
            goody: goody,
            consumer: entity,
            org: {
              type: choices.organizations.BUSINESS,
              id: businessId
            },
            locationId: locationId,
            registerId: registerId,
            dateRedeemed: timestamp
          };
          redemptionLogTransaction = Consumers.createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.REDEMPTION_LOG_GOODY_REDEEMED, transactionData, choices.transactions.directions.OUTBOUND, transactionEntity);
          $query = {};
          $query["consumerId"] = consumerId;
          $query["org.type"] = choices.organizations.BUSINESS;
          $query["org.id"] = businessId;
          $query["data.karmaPoints.remaining"] = {
            $gte: parseInt(goody.karmaPointsRequired)
          };
          $inc = {};
          $pushAll = {};
          $inc["data.karmaPoints.remaining"] = -1 * goody.karmaPointsRequired;
          $inc["data.karmaPoints.used"] = parseInt(goody.karmaPointsRequired);
          $pushAll = {
            "transactions.ids": [redemptionLogTransaction.id],
            "transactions.log": [redemptionLogTransaction]
          };
          $update = {
            $inc: $inc,
            $pushAll: $pushAll
          };
          fields = {
            _id: 1
          };
          return Statistics.model.collection.findAndModify($query, [], $update, {
            safe: true,
            "new": true,
            fields: fields
          }, function(error, statistic) {
            if (error != null) {
              logger.error(error);
              callback(error, false);
              return;
            }
            if (!(statistic != null)) {
              callback(error, false);
              return;
            }
            callback(error, true);
            tp.process(statistic, redemptionLogTransaction);
          });
        });
      });
    };

    return Goodies;

  })(API);

  UnclaimedBarcodeStatistics = (function(_super) {

    __extends(UnclaimedBarcodeStatistics, _super);

    function UnclaimedBarcodeStatistics() {
      UnclaimedBarcodeStatistics.__super__.constructor.apply(this, arguments);
    }

    UnclaimedBarcodeStatistics.model = UnclaimedBarcodeStatistic;

    UnclaimedBarcodeStatistics.byBusiness = function(bid, options, callback) {
      var $query;
      if (Object.isString(bid)) bid = new ObjectId(bid);
      if (Object.isFunction(options)) {
        callback = options;
        options = {};
      }
      $query = {
        "org.id": bid
      };
      if (options["data.tapIns.totalTapIns"] != null) {
        $query["data.tapIns.totalTapIns"] = options["data.tapIns.totalTapIns"];
      }
      if (options["data.tapIns.lastVisited"] != null) {
        $query["data.tapIns.lastVisited"] = options["data.tapIns.lastVisited"];
      }
      if (options["data.tapIns.firstVisited"] != null) {
        $query["data.tapIns.firstVisited"] = options["data.tapIns.firstVisited"];
      }
      options.skip = options.skip || 0;
      options.limit = options.limit || 25;
      return this.model.collection.find($query, options, function(error, cursor) {
        if (options.count) return cursor.count(callback);
        return cursor.toArray(callback);
      });
    };

    UnclaimedBarcodeStatistics.add = function(data, callback) {
      var instance, obj;
      obj = {
        org: {
          type: data.org.type,
          id: data.org.id
        },
        barcodeId: data.barcodeId,
        data: data.data || {}
      };
      instance = new this.model(obj);
      return instance.save(callback);
    };

    UnclaimedBarcodeStatistics.claimBarcodeId = function(barcodeId, claimId, callback) {
      if (Object.isString(claimId)) claimId = new ObjectId(claimId);
      this.model.collection.update({
        barcodeId: barcodeId
      }, {
        $set: {
          claimId: claimId
        }
      }, {
        safe: true
      }, callback);
    };

    UnclaimedBarcodeStatistics.replaceBarcodeId = function(oldId, barcodeId, callback) {
      var $set;
      if (utils.isBlank(oldId)) {
        callback(new errors.ValidationError("oldId is required fields"));
        return;
      }
      if (utils.isBlank(barcodeId)) {
        callback(new errors.ValidationError("barcodeId is required fields"));
        return;
      }
      $set = {
        barcodeId: barcodeId
      };
      this.model.collection.update({
        barcodeId: oldId
      }, {
        $set: $set
      }, {
        safe: true,
        multi: true
      }, callback);
    };

    UnclaimedBarcodeStatistics.getClaimed = function(claimId, callback) {
      if (Object.isString(claimId)) claimId = new ObjectId(claimId);
      return this.model.collection.find({
        claimId: claimId
      }, function(err, cursor) {
        if (typeof error !== "undefined" && error !== null) {
          callback(error);
          return;
        }
        cursor.toArray(function(error, unclaimedBarcodeStatistics) {
          return callback(error, unclaimedBarcodeStatistics);
        });
      });
    };

    UnclaimedBarcodeStatistics.removeClaimed = function(claimId, callback) {
      return this.model.collection.remove({
        claimId: claimId
      }, {
        safe: true
      }, callback);
    };

    UnclaimedBarcodeStatistics.btTapped = function(orgEntity, barcodeId, transactionId, spent, karmaPointsEarned, donationAmount, timestamp, callback) {
      var $inc, $push, $set, $update, org;
      if (Object.isString(orgEntity.id)) orgEntity.id = new ObjectId(orgEntity.id);
      if (Object.isString(transactionId)) {
        transactionId = new ObjectId(transactionId);
      }
      $inc = {};
      $inc["data.tapIns.totalTapIns"] = 1;
      $inc["data.tapIns.totalDonated"] = !isNaN(donationAmount) ? parseInt(donationAmount) : 0;
      if ((spent != null) && !isNaN(spent)) {
        $inc["data.tapIns.totalAmountPurchased"] = parseInt(spent);
      }
      if ((karmaPointsEarned != null) && !isNaN(karmaPointsEarned)) {
        $inc["data.karmaPoints.earned"] = parseInt(karmaPointsEarned);
        $inc["data.karmaPoints.remaining"] = parseInt(karmaPointsEarned);
      }
      $set = {};
      $set["data.tapIns.lastVisited"] = new Date(timestamp);
      $push = {};
      $push["transactions.ids"] = transactionId;
      $update = {
        $set: $set,
        $inc: $inc,
        $push: $push
      };
      org = {
        type: orgEntity.type,
        id: orgEntity.id
      };
      this.model.collection.update({
        org: org,
        barcodeId: barcodeId,
        'transactions.ids': {
          $ne: transactionId
        }
      }, $update, {
        safe: true,
        upsert: true
      }, callback);
    };

    /* _getKarmaPoints_
    */

    UnclaimedBarcodeStatistics.getKarmaPoints = function(barcodeId, businessId, callback) {
      var $options, $query, getAll;
      getAll = true;
      if (Object.isFunction(businessId)) {
        callback = businessId;
        delete businessId;
      } else {
        try {
          if (Object.isString(businessId)) businessId = new ObjectId(businessId);
          getAll = false;
        } catch (error) {
          callback(error);
          return;
        }
      }
      $query = {};
      $options = {};
      $query["barcodeId"] = barcodeId;
      if (!getAll) {
        $query["org.type"] = choices.organizations.BUSINESS;
        $query["org.id"] = businessId;
        $options["limit"] = 1;
      }
      return this.model.collection.find($query, {
        barcodeId: 1,
        org: 1,
        "data.karmaPoints": 1
      }, $options, function(error, cursor) {
        if (error != null) {
          logger.error(error);
          callback(error);
          return;
        }
        return cursor.toArray(function(error, statistics) {
          if (!getAll && statistics.length === 1) {
            callback(error, statistics[0]);
            return;
          }
          return callback(error, statistics);
        });
      });
    };

    /* _awardKarmaPoints_
    */

    UnclaimedBarcodeStatistics.awardKarmaPoints = function(barcodeId, businessId, amount, callback) {
      var $query;
      try {
        if (Object.isString(businessId)) businessId = new ObjectId(businessId);
      } catch (error) {
        callback(error);
        return;
      }
      amount = parseInt(amount);
      if (amount < 0) {
        callback({
          message: "amount needs to be a positive integer"
        });
        return;
      }
      $query = {};
      $query["barcodeId"] = barcodeId;
      $query["org.type"] = choices.organizations.BUSINESS;
      $query["org.id"] = businessId;
      return this.model.collection.update($query, {
        $inc: {
          "data.karmaPoints.earned": amount,
          "data.karmaPoints.remaining": amount
        }
      }, {
        safe: true,
        upsert: true
      }, function(error, count) {
        if (error != null) logger.error(error);
        callback(error, count);
      });
    };

    return UnclaimedBarcodeStatistics;

  })(API);

  Statistics = (function(_super) {

    __extends(Statistics, _super);

    function Statistics() {
      Statistics.__super__.constructor.apply(this, arguments);
    }

    Statistics.model = Statistic;

    /* _getKarmaPoints_
    */

    Statistics.getKarmaPoints = function(consumerId, businessId, callback) {
      var $options, $query, getAll;
      getAll = true;
      try {
        if (Object.isString(consumerId)) consumerId = new ObjectId(consumerId);
      } catch (error) {
        callback(error);
        return;
      }
      if (Object.isFunction(businessId)) {
        callback = businessId;
      } else {
        try {
          if (Object.isString(businessId)) businessId = new ObjectId(businessId);
          getAll = false;
        } catch (error) {
          callback(error);
          return;
        }
      }
      $query = {};
      $options = {};
      $query["consumerId"] = consumerId;
      if (!getAll) {
        $query["org.type"] = choices.organizations.BUSINESS;
        $query["org.id"] = businessId;
        $options["limit"] = 1;
      }
      return this.model.collection.find($query, {
        consumerId: 1,
        org: 1,
        "data.karmaPoints": 1
      }, $options, function(error, cursor) {
        if (error != null) {
          logger.error(error);
          callback(error);
          return;
        }
        return cursor.toArray(function(error, statistics) {
          if (!getAll && statistics.length === 1) {
            callback(error, statistics[0]);
            return;
          }
          return callback(error, statistics);
        });
      });
    };

    /* _awardKarmaPoints_
    */

    Statistics.awardKarmaPoints = function(consumerId, businessId, amount, callback) {
      var $query;
      try {
        if (Object.isString(consumerId)) consumerId = new ObjectId(consumerId);
        if (Object.isString(businessId)) businessId = new ObjectId(businessId);
      } catch (error) {
        callback(error);
        return;
      }
      amount = parseInt(amount);
      if (amount < 0) {
        callback({
          message: "amount needs to be a positive integer"
        });
        return;
      }
      $query = {};
      $query["consumerId"] = consumerId;
      $query["org.type"] = choices.organizations.BUSINESS;
      $query["org.id"] = businessId;
      return this.model.collection.update($query, {
        $inc: {
          "data.karmaPoints.earned": amount,
          "data.karmaPoints.remaining": amount
        }
      }, {
        safe: true,
        upsert: true
      }, function(error, count) {
        if (error != null) logger.error(error);
        return callback(error, count);
      });
    };

    /* _useKarmaPoints_
    */

    Statistics.useKarmaPoints = function(consumerId, businessId, amount, callback) {
      var $query;
      try {
        if (Object.isString(consumerId)) consumerId = new ObjectId(consumerId);
        if (Object.isString(businessId)) businessId = new ObjectId(businessId);
      } catch (error) {
        callback(error);
        return;
      }
      amount = parseInt(amount);
      if (amount < 0) {
        callback({
          message: "amount needs to be a positive integer"
        });
        return;
      }
      $query = {};
      $query["consumerId"] = consumerId;
      $query["org.type"] = choices.organizations.BUSINESS;
      $query["org.id"] = businessId;
      return this.model.collection.update($query, {
        $inc: {
          "data.karmaPoints.remaining": -1 * amount,
          "data.karmaPoints.used": amount
        }
      }, {
        safe: true
      }, function(error, count) {
        var success;
        success = false;
        if (error != null) logger.error(error);
        if (count === 1) success = true;
        return callback(error, success);
      });
    };

    Statistics.add = function(data, callback) {
      var instance, obj;
      obj = {
        org: {
          type: data.org.type,
          id: data.org.id
        },
        consumerId: data.consumerId,
        data: data.data || {}
      };
      instance = new this.model(obj);
      return instance.save(callback);
    };

    Statistics.list = function(org, callback) {
      var query;
      query = this.query();
      query.where("org.type", org.type);
      query.where("org.id", org.id);
      query.exec(callback);
    };

    Statistics.byBusiness = function(bid, options, callback) {
      var $query;
      if (Object.isString(bid)) bid = new ObjectId(bid);
      if (Object.isFunction(options)) {
        callback = options;
        options = {};
      }
      $query = {
        "org.id": bid
      };
      if (options["data.tapIns.totalTapIns"] != null) {
        $query["data.tapIns.totalTapIns"] = options["data.tapIns.totalTapIns"];
      }
      if (options["data.tapIns.lastVisited"] != null) {
        $query["data.tapIns.lastVisited"] = options["data.tapIns.lastVisited"];
      }
      if (options["data.tapIns.firstVisited"] != null) {
        $query["data.tapIns.firstVisited"] = options["data.tapIns.firstVisited"];
      }
      options.skip = options.skip || 0;
      options.limit = options.limit || 25;
      return this.model.collection.find($query, options, function(error, cursor) {
        if (options.count) return cursor.count(callback);
        return cursor.toArray(callback);
      });
    };

    Statistics.withTapIns = function(org, options, callback) {
      if (Object.isString(org.id)) org.id = new ObjectId(org.id);
      if (Object.isFunction(options)) {
        callback = options;
        options = {};
      }
      options.skip = options.skip || 0;
      options.limit = options.limit || 25;
      options.sort = options.sort || {
        "data.tapIns.lastVisited": -1
      };
      return this.model.collection.find({
        "org.type": org.type,
        "org.id": org.id
      }, options, function(error, cursor) {
        if (error != null) {
          callback(error);
          return;
        }
        return cursor.toArray(function(error, statistics) {
          logger.debug(statistics);
          return callback(error, statistics);
        });
      });
    };

    Statistics.getByConsumerIds = function(org, consumerIds, callback) {
      var query;
      query = this.query();
      query.where("org.type", org.type);
      query.where("org.id", org.id);
      query["in"]("consumerId", consumerIds);
      query.exec(callback);
    };

    Statistics.getConsumerTapinCountByBusiness = function(cid, bid, callback) {
      var $query;
      if (Object.isString(cid)) cid = ObjectId(cid);
      if (Object.isString(bid)) bid = ObjectId(bid);
      $query = {
        "consumerId": cid,
        "org.id": bid
      };
      return this.model.collection.findOne($query, function(error, results) {
        if (error != null) return callback(error);
        if (!(results != null)) return callback(null, 0);
        return callback(null, results.data.tapIns.totalTapIns);
      });
    };

    Statistics.getConsumerTapinCount = function(id, callback) {
      var amount, query;
      amount = 0;
      query = this.query();
      query.where("consumerId", id);
      query.fields({
        "data.tapIns.totalTapIns": 1
      });
      return query.find(function(error, results) {
        var x, y, _len, _results;
        if (error != null) return callback(error);
        if (results.length === 0) return callback(null, 0);
        _results = [];
        for (x = 0, _len = results.length; x < _len; x++) {
          y = results[x];
          _results.push((function(x, y) {
            amount += y.data.tapIns.totalTapIns;
            if (x === results.length - 1) return callback(null, amount);
          })(x, y));
        }
        return _results;
      });
    };

    Statistics.getLocationsByTapins = function(id, options, callback) {
      var output, query;
      output = [];
      query = this.query();
      query.where("consumerId", id);
      query.limit(options.amount || 10);
      query.fields({
        "data.tapIns.totalTapIns": 1,
        "org.id": 1
      });
      query.sort("data.tapIns.totalTapIns", -1);
      query.find(function(error, results) {
        var x, y, _len, _results;
        if (error != null) {
          callback(error);
          return;
        }
        _results = [];
        for (x = 0, _len = results.length; x < _len; x++) {
          y = results[x];
          _results.push((function(x, y) {
            output[x] = {
              business: y
            };
            return Businesses.model.collection.findOne(y.org.id, {
              publicName: 1
            }, function(error, business) {
              if (error === null && business !== null) {
                output[x].name = business.publicName;
              }
              if (x === results.length - 1) return callback(null, output);
            });
          })(x, y));
        }
        return _results;
      });
    };

    Statistics.pollAnswered = function(org, consumerId, transactionId, timestamp, callback) {
      var $update;
      if (Object.isString(org.id)) org.id = new ObjectId(org.id);
      if (Object.isString(consumerId)) consumerId = new ObjectId(consumerId);
      if (Object.isString(transactionId)) {
        transactionId = new ObjectId(transactionId);
      }
      $update = {
        $set: {
          "data.polls.lastAnsweredDate": timestamp
        },
        $inc: {
          "data.polls.totalAnswered": 1
        },
        $push: {
          "transactions.ids": transactionId
        }
      };
      return this.model.collection.update({
        org: org,
        consumerId: consumerId
      }, $update, {
        safe: true,
        upsert: true
      }, callback);
    };

    Statistics.discussionAnswered = function(org, consumerId, transactionId, timestamp, callback) {};

    Statistics.eventRsvped = function(org, consumerId, transactionId, timestamp, callback) {};

    Statistics.btTapped = function(orgEntity, consumerId, transactionId, spent, karmaPointsEarned, donationAmount, timestamp, totalTapIns, callback) {
      var $inc, $push, $set, $update, org;
      if (Object.isFunction(totalTapIns)) {
        callback = totalTapIns;
        totalTapIns = 1;
      }
      if (Object.isString(orgEntity.id)) orgEntity.id = new ObjectId(orgEntity.id);
      if (Object.isString(consumerId)) consumerId = new ObjectId(consumerId);
      if (Object.isString(transactionId)) {
        transactionId = new ObjectId(transactionId);
      }
      $inc = {};
      $inc["data.tapIns.totalTapIns"] = totalTapIns;
      if ((spent != null) && !isNaN(spent)) {
        $inc["data.tapIns.totalAmountPurchased"] = parseInt(spent);
      }
      if ((karmaPointsEarned != null) && !isNaN(karmaPointsEarned)) {
        $inc["data.karmaPoints.earned"] = parseInt(karmaPointsEarned);
        $inc["data.karmaPoints.remaining"] = parseInt(karmaPointsEarned);
      }
      if ((donationAmount != null) && !isNaN(donationAmount)) {
        $inc["data.tapIns.totalDonated"] = !isNaN(donationAmount) ? parseInt(donationAmount) : 0;
      }
      $set = {};
      $set["data.tapIns.lastVisited"] = new Date(timestamp);
      $push = {};
      $push["transactions.ids"] = transactionId;
      $update = {
        $set: $set,
        $inc: $inc,
        $push: $push
      };
      org = {
        type: orgEntity.type,
        id: orgEntity.id
      };
      this.model.collection.update({
        org: org,
        consumerId: consumerId,
        'transactions.ids': {
          $ne: transactionId
        }
      }, $update, {
        safe: true,
        upsert: true
      }, callback);
    };

    Statistics._inc = function(org, consumerId, field, value, callback) {
      var $inc, query;
      if (Object.isFunction(value)) {
        callback = value;
        value = 1;
      }
      query = this.queryOne();
      query.where("org.type", org.type);
      query.where("org.id", org.id);
      query.where("consumerId", consumerId);
      $inc = {};
      $inc["data." + field] = value;
      query.update({
        $inc: $inc
      }, callback);
    };

    Statistics.setTransactonPending = Statistics.__setTransactionPending;

    Statistics.setTransactionProcessing = Statistics.__setTransactionProcessing;

    Statistics.setTransactionProcessed = Statistics.__setTransactionProcessed;

    Statistics.setTransactionError = Statistics.__setTransactionError;

    return Statistics;

  })(API);

  Referrals = (function(_super) {

    __extends(Referrals, _super);

    function Referrals() {
      Referrals.__super__.constructor.apply(this, arguments);
    }

    Referrals.model = Referral;

    Referrals.addUserLink = function(entity, link, code, callback) {
      var doc;
      doc = {
        _id: new ObjectId(),
        type: choices.referrals.types.LINK,
        entity: {
          type: entity.type,
          id: entity.id
        },
        incentives: {
          referrer: defaults.referrals.incentives.referrers.USER,
          referred: defaults.referrals.incentives.referreds.USER
        },
        link: {
          code: code,
          url: link,
          type: choices.referrals.links.types.USER,
          visits: 0
        },
        signups: 0,
        referredUsers: []
      };
      return this.model.collection.insert(doc, {
        safe: true
      }, callback);
    };

    Referrals.addTapInLink = function(entity, link, code, callback) {
      var doc;
      doc = {
        _id: new ObjectId(),
        type: choices.referrals.types.LINK,
        entity: {
          type: entity.type,
          id: entity.id
        },
        incentives: {
          referrer: defaults.referrals.incentives.referrers.TAP_IN,
          referred: defaults.referrals.incentives.referreds.TAP_IN
        },
        link: {
          code: code,
          url: link,
          type: choices.referrals.links.types.TAPIN,
          visits: 0
        },
        signups: 0,
        referredUsers: []
      };
      return this.model.collection.insert(doc, {
        safe: true
      }, callback);
    };

    Referrals.signUp = function(code, referredEntity, callback) {
      var $fields, $update;
      $update = {
        $inc: {
          signups: 1
        },
        $push: {
          referredUsers: referredEntity
        }
      };
      $fields = {
        _id: 1,
        entity: 1,
        incentives: 1
      };
      logger.info("code: " + code);
      return this.model.collection.findAndModify({
        "link.code": code
      }, [], $update, {
        safe: true,
        "new": true,
        fields: $fields
      }, function(error, doc) {
        var referralFound;
        if (error != null) {
          if (callback != null) callback(error);
        } else {
          logger.debug(doc);
          referralFound = doc != null;
          if (callback != null) callback(null, referralFound);
          if (doc.entity.type === choices.entities.CONSUMER) {
            Consumers.addFunds(referredEntity.id, doc.incentives.referred);
          } else if (choices.entities.BUSINESS) {
            Businesses.addFunds(referredEntity.id, doc.incentives.referred);
          }
          if (doc.entity.type === choices.entities.CONSUMER) {
            return Consumers.addFunds(doc.entity.id, doc.incentives.referrer);
          } else if (choices.entities.BUSINESS) {
            return Businesses.addFunds(doc.entity.id, doc.incentives.referrer);
          }
        }
      });
    };

    return Referrals;

  })(API);

  Barcodes = (function(_super) {

    __extends(Barcodes, _super);

    function Barcodes() {
      Barcodes.__super__.constructor.apply(this, arguments);
    }

    Barcodes.model = Barcode;

    Barcodes.assignNew = function(entity, callback) {
      var self,
        _this = this;
      self = this;
      return Sequences.next("barcodeId", function(error, value) {
        var barcodeId, security;
        value = defaults.barcode.offset + value;
        security = utils.randomBarcodeSecurityString(3);
        barcodeId = "" + value + "-" + security;
        return _this.model.collection.insert({
          barcodeId: barcodeId
        }, {
          safe: true
        }, function(error, barcode) {
          if (error != null) {
            callback(error);
          } else if (barcode != null) {
            barcode = barcode[0];
            logger.silly("UPDATING CONSUMER BARCODE TO " + barcodeId);
            return Consumers.updateBarcodeId(entity, barcodeId, function(error, success) {
              if (error != null) {
                callback(error);
                return;
              }
              if (success === true) {
                callback(error, barcode);
              } else {
                callback({
                  "name": "barcodeAssociationError",
                  message: "unable to properly associate barcodeId with user"
                });
              }
            });
          } else {
            callback(null, null);
          }
        });
      });
    };

    return Barcodes;

  })(API);

  CardRequests = (function(_super) {

    __extends(CardRequests, _super);

    function CardRequests() {
      CardRequests.__super__.constructor.apply(this, arguments);
    }

    CardRequests.model = CardRequest;

    CardRequests.pending = function(id, callback) {
      var $query;
      if (Object.isString(id)) id = new ObjectId(id);
      $query = {
        'entity.id': id,
        'dates.responded': {
          $exists: false
        }
      };
      return this.model.findOne($query, {}, {
        sort: {
          "dates.requested": -1
        }
      }, callback);
    };

    return CardRequests;

  })(API);

  EmailSubmissions = (function(_super) {

    __extends(EmailSubmissions, _super);

    function EmailSubmissions() {
      EmailSubmissions.__super__.constructor.apply(this, arguments);
    }

    EmailSubmissions.model = EmailSubmission;

    EmailSubmissions.add = function(data, callback) {
      if (Object.isString(data.businessId)) {
        data.businessId = new ObjectId(data.businessId);
      }
      if (Object.isString(data.locationId)) {
        data.locationId = new ObjectId(data.locationId);
      }
      if (Object.isString(data.registerId)) {
        data.registerId = new ObjectId(data.registerId);
      }
      return this._add(data, callback);
    };

    return EmailSubmissions;

  })(API);

  exports.DBTransactions = DBTransactions;

  exports.Consumers = Consumers;

  exports.Clients = Clients;

  exports.Businesses = Businesses;

  exports.Polls = Polls;

  exports.Discussions = Discussions;

  exports.Goodies = Goodies;

  exports.Statistics = Statistics;

  exports.Medias = Medias;

  exports.ClientInvitations = ClientInvitations;

  exports.Tags = Tags;

  exports.EventRequests = EventRequests;

  exports.Events = Events;

  exports.BusinessTransactions = BusinessTransactions;

  exports.BusinessRequests = BusinessRequests;

  exports.Streams = Streams;

  exports.Statistics = Statistics;

  exports.UnclaimedBarcodeStatistics = UnclaimedBarcodeStatistics;

  exports.Organizations = Organizations;

  exports.PasswordResetRequests = PasswordResetRequests;

  exports.Referrals = Referrals;

  exports.Barcodes = Barcodes;

  exports.CardRequests = CardRequests;

  exports.EmailSubmissions = EmailSubmissions;

  exports.RedemptionLogs = RedemptionLogs;

}).call(this);
