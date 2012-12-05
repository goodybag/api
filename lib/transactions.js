(function() {
  var api, async, btBarcodeClaimed, btTapped, choices, config, defaults, discussionCreated, discussionDeleted, discussionDonated, discussionDonationDistributed, discussionThanked, discussionUpdated, globals, hashlib, logger, loggers, pollAnswered, pollCreated, pollDeleted, pollUpdated, process, redemptionLogGoodyRedeemed, statBarcodeClaimed, statBtTapped, statPollAnswered, ucbsClaimed, utils, __deductFunds, __depositFunds, _cleanupTransaction, _deductFunds, _depositFunds, _incrementDonated, _setTransactionError, _setTransactionErrorAndRefund, _setTransactionProcessed, _setTransactionProcessedAndCreateNew, _setTransactionProcessing;

  async = require("async");

  globals = require("globals");

  config = globals.config;

  hashlib = globals.hashlib;

  loggers = require("./loggers");

  api = require("./api");

  logger = loggers.transaction;

  choices = globals.choices;

  defaults = globals.defaults;

  utils = globals.utils;

  process = function(document, transaction) {
    logger.debug("FINDING PROCESSOR FOR: " + transaction.action);
    switch (transaction.action) {
      case choices.transactions.actions.POLL_CREATED:
        return pollCreated(document, transaction);
      case choices.transactions.actions.POLL_UPDATED:
        return pollUpdated(document, transaction);
      case choices.transactions.actions.POLL_DELETED:
        return pollDeleted(document, transaction);
      case choices.transactions.actions.POLL_ANSWERED:
        return pollAnswered(document, transaction);
      case choices.transactions.actions.DISCUSSION_CREATED:
        return discussionCreated(document, transaction);
      case choices.transactions.actions.DISCUSSION_UPDATED:
        return discussionUpdated(document, transaction);
      case choices.transactions.actions.DISCUSSION_DELETED:
        return discussionDeleted(document, transaction);
      case choices.transactions.actions.DISCUSSION_DONATED:
        return discussionDonated(document, transaction);
      case choices.transactions.actions.DISCUSSION_THANKED:
        return discussionThanked(document, transaction);
      case choices.transactions.actions.DISCUSSION_DONATION_DISTRIBUTED:
        return discussionDonationDistributed(document, transaction);
      case choices.transactions.actions.BT_TAPPED:
        return btTapped(document, transaction);
      case choices.transactions.actions.BT_BARCODE_CLAIMED:
        return btBarcodeClaimed(document, transaction);
      case choices.transactions.actions.STAT_POLL_ANSWERED:
        return statPollAnswered(document, transaction);
      case choices.transactions.actions.STAT_BT_TAPPED:
        return statBtTapped(document, transaction);
      case choices.transactions.actions.STAT_BARCODE_CLAIMED:
        return statBarcodeClaimed(document, transaction);
      case choices.transactions.actions.UCBS_CLAIMED:
        return ucbsClaimed(document, transaction);
      case choices.transactions.actions.REDEMPTION_LOG_GOODY_REDEEMED:
        return redemptionLogGoodyRedeemed(document, transaction);
    }
  };

  _setTransactionProcessing = function(clazz, document, transaction, locking, callback) {
    var prepend;
    prepend = "ID: " + document._id + " - TID: " + transaction.id;
    logger.info("" + prepend + " transitioning state to processing");
    return clazz.setTransactionProcessing(document._id, transaction.id, locking, function(error, doc) {
      if (error != null) {
        logger.error(error);
        logger.error("" + prepend + " transitioning state to processing failed");
        callback(error);
      } else if (!(doc != null)) {
        logger.warn("" + prepend + " the transaction state is either processed or error - can not set to processing");
        callback({
          name: "TransactionAlreadyCompleted",
          message: "Document Does Not Exist"
        });
      } else {
        logger.info("" + prepend + " Processing Transaction");
        callback(null, doc);
      }
    });
  };

  _setTransactionProcessed = function(clazz, document, transaction, locking, removeLock, modifierDoc, callback) {
    var prepend;
    prepend = "ID: " + document._id + " - TID: " + transaction.id;
    logger.info("" + prepend + " transitioning state to processed");
    return clazz.setTransactionProcessed(document._id, transaction.id, locking, removeLock, modifierDoc, function(error, doc) {
      if (error != null) {
        logger.error(error);
        logger.error("" + prepend + " transitioning to state processed failed");
        callback(error);
      } else if (!(doc != null)) {
        logger.warn("" + prepend + " the transaction state is either processed or error - can not set to processed");
        callback({
          name: "TransactionAlreadyCompleted",
          message: "Unable to set state to processed. Transaction has already been processed, quitting further processing"
        });
      } else {
        logger.info("" + prepend + " transaction state is set to processed successfully");
        callback(null, doc);
      }
    });
  };

  _setTransactionProcessedAndCreateNew = function(clazz, document, transaction, newTransactions, locking, removeLock, modifierDoc, callback) {
    var prepend;
    prepend = "ID: " + document._id + " - TID: " + transaction.id;
    logger.info("" + prepend + " transitioning state to processed and creating new transaction");
    return clazz.setTransactionProcessed(document._id, transaction.id, locking, removeLock, modifierDoc, function(error, doc) {
      var newT, _fn, _i, _len;
      if (error != null) {
        logger.error(error);
        logger.error("" + prepend + " transitioning to state processed and create new transaction failed");
        callback(error);
      } else if (!(doc != null)) {
        logger.warn("" + prepend + " the transaction state is either processed or error - can not set to processed");
        callback({
          name: "TransactionAlreadyCompleted",
          message: "Unable to set state to processed. Transaction may have already been processed, quitting further processing"
        });
      } else {
        logger.info("" + prepend + " transaction state is set to processed successfully");
        callback(null, doc);
        if (!Object.isArray(newTransactions)) newTransactions = [newTransactions];
        _fn = function() {
          var trans;
          trans = newT;
          logger.debug(trans);
          return clazz.moveTransactionToLog(document._id, trans, function(error, doc2) {
            if (error != null) {
              logger.error(error);
              return logger.error("" + prepend + " moving " + trans.action + " transaction from temporary to log failed");
            } else if (!(doc2 != null)) {
              return logger.warn("" + prepend + " the new transaction is already in progress - pollers will move it if it is still in temp");
            } else {
              logger.info("" + prepend + " created " + trans.action + " transaction: " + trans.id);
              return process(document, trans);
            }
          });
        };
        for (_i = 0, _len = newTransactions.length; _i < _len; _i++) {
          newT = newTransactions[_i];
          _fn();
        }
      }
    });
  };

  _setTransactionError = function(clazz, document, transaction, locking, removeLock, error, data, callback) {
    var prepend;
    prepend = "ID: " + document._id + " - TID: " + transaction.id;
    return clazz.setTransactionError(document._id, transaction.id, locking, removeLock, error, data, function(error, doc) {
      if (error != null) {
        logger.error(error);
        logger.error("" + prepend + " problem setting transaction state to error");
        return callback(error);
      } else if (!(doc != null)) {
        logger.warn("" + prepend + " the document is already in a processed or error state");
        return callback({
          name: "TransactionWarning",
          messge: "Unable to set transaction state to error"
        });
      } else {
        logger.info("" + prepend + " set transaction state to error successfully");
        return callback(null, doc);
      }
    });
  };

  _setTransactionErrorAndRefund = function(clazz, document, transaction, locking, removeLock, error, data, callback) {
    var $inc, $update, prepend;
    prepend = "ID: " + document._id + " - TID: " + transaction.id;
    logger.warn("" + prepend + " Setting errored and refunding");
    $inc = {
      "funds.remaining": Math.abs(transaction.data.amount)
    };
    $update = {};
    $update.$inc = {};
    Object.merge($update, data);
    Object.merge($update.$inc, $inc);
    return _setTransactionError(clazz, document, transaction, locking, removeLock, error, $update, callback);
  };

  _cleanupTransaction = function(document, transaction, transactionContainerApiClass, transactionMemberApiClasses, callback) {
    var apiClass, doc, prepend, _i, _len;
    prepend = "ID: " + document._id + " - TID: " + transaction.id;
    for (_i = 0, _len = transactionMemberApiClasses.length; _i < _len; _i++) {
      apiClass = transactionMemberApiClasses[_i];
      apiClass.removeTransactionInvolvement(transaction.id, function(error, count) {
        if (error != null) {
          logger.error("" + prepend + " there were errors cleaning up transactions");
          logger.error(error);
          callback(error);
          return;
        }
        return logger.info("" + prepend + " cleaning up transactions - " + count + " documents affected");
      });
    }
    doc = {
      document: {
        type: transactionContainerApiClass.model.collection.name,
        id: document._id
      },
      transaction: transaction
    };
    logger.debug(document);
    return api.DBTransactions.add(doc, function(error, dbTransaction) {
      if (error != null) {
        logger.error(error);
        callback(error);
        return;
      }
      return transactionContainerApiClass.removeTransaction(document._id, transaction.id, function(error, count) {
        callback(error, count);
        if (!(error != null)) {
          logger.info("" + prepend + " finished cleaning up transactions");
        } else {
          logger.error("" + prepend + " there were errors cleaning up transactions");
        }
      });
    });
  };

  _deductFunds = function(classFrom, initialTransactionClass, document, transaction, locking, removeLock, callback) {
    __deductFunds(classFrom, initialTransactionClass, document, transaction, transaction.entity, transaction.data.amount, locking, removeLock, callback);
  };

  __deductFunds = function(classFrom, initialTransactionClass, document, transaction, entity, amount, locking, removeLock, callback) {
    var prepend;
    prepend = "ID: " + document._id + " - TID: " + transaction.id;
    return classFrom.deductFunds(entity.id, transaction.id, amount, function(error, doc) {
      if (error != null) {
        logger.error(error);
        logger.error("" + prepend + " deducting funds from " + entity.type + ": " + entity.id + " failed - database error");
        callback(error);
      } else if (!(doc != null)) {
        logger.info("" + prepend + " transaction may have occured, VERIFYING");
        classFrom.checkIfTransactionExists(entity.id, transaction.id, function(error, doc2) {
          if (error != null) {
            logger.error(error);
            return callback(error);
          } else if (doc2 != null) {
            logger.info("" + prepend + " transaction already occured");
            return callback(null, doc2);
          } else {
            logger.warn("" + prepend + " There were insufficient funds");
            return callback(null, null);
          }
        });
      } else {
        logger.info("" + prepend + " Successfully deducted funds");
        callback(null, doc);
      }
    });
  };

  _depositFunds = function(classTo, initialTransactionClass, document, transaction, locking, removeLock, callback) {
    __depositFunds(classTo, initialTransactionClass, document, transaction, transaction.entity, transaction.data.amount, locking, removeLock, callback);
  };

  __depositFunds = function(classTo, initialTransactionClass, document, transaction, entity, amount, locking, removeLock, callback) {
    var prepend;
    prepend = "ID: " + document._id + " - TID: " + transaction.id;
    return classTo.depositFunds(entity.id, transaction.id, amount, function(error, doc) {
      if (error != null) {
        logger.error(error);
        logger.error("" + prepend + " depositing funds into " + entity.type + ": " + entity.id + " failed - database error");
        callback(error);
      } else if (!(doc != null)) {
        logger.info("" + prepend + " transaction may have occured, VERIFYING");
        classTo.checkIfTransactionExists(entity.id, transaction.id, function(error, doc2) {
          if (error != null) {
            logger.error(error);
            logger.error("" + prepend + " database error");
            return callback(error);
          } else if (doc2 != null) {
            logger.info("" + prepend + " transaction already occured");
            return callback(null, doc2);
          } else {
            logger.warn("" + prepend + " Couldn't find the entity to deposit funds too");
            return callback(null, null);
          }
        });
      } else {
        logger.info("" + prepend + " Successfully deducted funds");
        callback(null, doc);
      }
    });
  };

  _incrementDonated = function(classFor, initialTransactionClass, document, transaction, entity, amount, locking, removeLock, callback) {
    var prepend;
    logger.silly("HERERERERRWRSDFSAGDSFGDSFGSFDHSFGJDGHJSDFFASRYAETYGADFGDFHADGFAVSCSHYSVBTUR");
    prepend = "ID: " + document._id + " - TID: " + transaction.id;
    return classFor.incrementDonated(entity.id, transaction.id, amount, function(error, doc) {
      if (error != null) {
        logger.error(error);
        logger.error("" + prepend + " incrementing donated into " + entity.type + ": " + entity.id + " failed - database error");
        callback(error);
      } else if (!(doc != null)) {
        logger.info("" + prepend + " transaction may have occured, VERIFYING");
        classFor.checkIfTransactionExists(entity.id, transaction.id, function(error, doc2) {
          if (error != null) {
            logger.error(error);
            logger.error("" + prepend + " database error");
            return callback(error);
          } else if (doc2 != null) {
            logger.info("" + prepend + " transaction already occured");
            return callback(null, doc2);
          } else {
            logger.warn("" + prepend + " Couldn't find the entity to incrment donation for");
            return callback(null, null);
          }
        });
      } else {
        logger.info("" + prepend + " Successfully incremented donations");
        callback(null, doc);
      }
    });
  };

  pollCreated = function(document, transaction) {
    var cleanup, prepend, setProcessed;
    prepend = "ID: " + document._id + " - TID: " + transaction.id;
    logger.info("Creating transaction for poll");
    logger.info("ID: " + document._id + " - TID: " + transaction.id + " - " + transaction.direction);
    cleanup = function(callback) {
      var entityClass;
      logger.info("" + prepend + " cleaning up");
      if (transaction.entity.type === choices.entities.CONSUMER) {
        entityClass = api.Consumers;
      } else if (transaction.entity.type === choices.entities.BUSINESS) {
        entityClass = api.Businesses;
      }
      return _cleanupTransaction(document, transaction, api.Polls, [api.Polls, entityClass], callback);
    };
    setProcessed = true;
    return async.series({
      setTransactionProcessing: function(callback) {
        _setTransactionProcessing(api.Polls, document, transaction, true, callback);
      },
      deductFunds: function(callback) {
        if (transaction.entity.type === choices.entities.BUSINESS) {
          _deductFunds(api.Businesses, api.Polls, document, transaction, true, true, function(error, doc) {
            if (error != null) {
              logger.error(error);
              return callback(error);
            } else if (doc != null) {
              return callback(null, doc);
            } else {
              error = {
                message: "there were insufficient funds"
              };
              return _setTransactionError(api.Polls, document, transaction, true, true, error, {}, function(error, doc) {
                setProcessed = false;
                return callback(null, null);
              });
            }
          });
        } else if (transaction.entity.type === choices.entities.CONSUMER) {
          _deductFunds(api.Consumers, api.Polls, document, transaction, true, true, function(error, doc) {
            if (error != null) {
              logger.error(error);
              return callback(error);
            } else if (doc != null) {
              return callback(null, doc);
            } else {
              error = {
                message: "there were insufficient funds"
              };
              return _setTransactionError(api.Polls, document, transaction, true, true, error, {}, function(error, doc) {
                setProcessed = false;
                return callback(null, null);
              });
            }
          });
        } else {
          callback({
            name: "NullError",
            message: "Unsupported Entity Type: " + transaction.entity.type
          });
        }
      },
      setProcessed: function(callback) {
        var $set, $update;
        if (setProcessed === false) {
          callback(null, null);
          return;
        }
        $set = {
          "funds.allocated": transaction.data.amount,
          "funds.remaining": transaction.data.amount
        };
        $update = {
          $set: $set
        };
        _setTransactionProcessed(api.Polls, document, transaction, true, true, $update, callback);
        return api.Streams.pollCreated(document);
      }
    }, function(error, results) {
      var clean;
      clean = false;
      if (error != null) {
        logger.error(error);
        if (error.name === "TransactionAlreadyCompleted") {
          clean = true;
        } else {
          logger.error("" + prepend + " the poller will try later");
          return;
        }
      } else if (results && (results.setProcessed != null)) {
        clean = true;
      }
      if (clean === true) {
        return cleanup(function(error, dbTransaction) {
          if (error != null) {
            logger.error(error);
            return logger.error("" + prepend + " unable to properly clean up - the poller will try later");
          }
        });
      }
    });
  };

  pollUpdated = function(document, transaction) {
    var cleanup, prepend, setProcessed;
    prepend = "ID: " + document._id + " - TID: " + transaction.id;
    logger.info("Creating transaction for a poll that was updated");
    logger.info("" + prepend + " - " + transaction.direction);
    cleanup = function(callback) {
      var entityClass;
      logger.info("" + prepend + " cleaning up");
      if (transaction.entity.type === choices.entities.CONSUMER) {
        entityClass = api.Consumers;
      } else if (transaction.entity.type === choices.entities.BUSINESS) {
        entityClass = api.Businesses;
      }
      return _cleanupTransaction(document, transaction, api.Polls, [api.Polls, entityClass], callback);
    };
    setProcessed = true;
    return async.series({
      setProcessing: function(callback) {
        _setTransactionProcessing(api.Polls, document, transaction, true, callback);
      },
      adjustFunds: function(callback) {
        transaction.data.amount = transaction.data.newAllocated - document.funds.allocated;
        if (transaction.entity.type === choices.entities.BUSINESS) {
          _deductFunds(api.Businesses, api.Polls, document, transaction, true, true, function(error, doc) {
            if (error != null) {
              logger.error(error);
              return callback(error);
            } else if (doc != null) {
              return callback(null, doc);
            } else {
              error = {
                message: "there were insufficient funds"
              };
              return _setTransactionError(api.Polls, document, transaction, true, true, error, {}, function(error, doc) {
                setProcessed = false;
                return callback(null, null);
              });
            }
          });
        } else if (transaction.entity.type === choices.entities.CONSUMER) {
          _deductFunds(api.Consumers, api.Polls, document, transaction, true, true, function(error, doc) {
            if (error != null) {
              logger.error(error);
              return callback(error);
            } else if (doc != null) {
              return callback(null, doc);
            } else {
              error = {
                message: "there were insufficient funds"
              };
              return _setTransactionError(api.Polls, document, transaction, true, true, error, {}, function(error, doc) {
                setProcessed = false;
                return callback(null, null);
              });
            }
          });
        } else {
          callback({
            name: "NullError",
            message: "Unsupported Entity Type: " + transaction.entity.type
          });
        }
      },
      setProcessed: function(callback) {
        var $set, $update;
        if (setProcessed === false) {
          callback();
          return;
        }
        $set = {
          "funds.allocated": transaction.data.newAllocated,
          "funds.remaining": document.funds.remaining + transaction.data.amount,
          "funds.perResponse": transaction.data.perResponse
        };
        $update = {
          $set: $set
        };
        _setTransactionProcessed(api.Polls, document, transaction, true, true, $update, callback);
        return api.Streams.pollUpdated(document);
      }
    }, function(error, results) {
      var clean;
      clean = false;
      if (error != null) {
        logger.error(error);
        if (error.name === "TransactionAlreadyCompleted") {
          clean = true;
        } else {
          logger.error("" + prepend + " the poller will try later");
          return;
        }
      } else if (results && (results.setProcessed != null)) {
        clean = true;
      }
      if (clean === true) {
        return cleanup(function(error, dbTransaction) {
          if (error != null) {
            logger.error(error);
            return logger.error("" + prepend + " unable to properly clean up - the poller will try later");
          }
        });
      }
    });
  };

  pollDeleted = function(document, transaction) {
    var cleanup, prepend, setProcessed;
    prepend = "ID: " + document._id + " - TID: " + transaction.id;
    logger.info("Creating transaction for a poll that was deleted");
    logger.info("" + prepend + " - " + transaction.direction);
    cleanup = function(callback) {
      var entityClass;
      logger.info("" + prepend + " cleaning up");
      if (transaction.entity.type === choices.entities.CONSUMER) {
        entityClass = api.Consumers;
      } else if (transaction.entity.type === choices.entities.BUSINESS) {
        entityClass = api.Businesses;
      }
      return _cleanupTransaction(document, transaction, api.Polls, [api.Polls, entityClass], callback);
    };
    setProcessed = true;
    return async.series({
      setTransactionProcessing: function(callback) {
        _setTransactionProcessing(api.Polls, document, transaction, true, callback);
      },
      depositFunds: function(callback) {
        transaction.entity.type = document.entity.type;
        transaction.entity.id = document.entity.id;
        transaction.data.amount = document.funds.remaining;
        logger.debug(transaction);
        logger.debug("" + prepend + " going to try and deposit funds: " + transaction.entity.id);
        if (transaction.entity.type === choices.entities.BUSINESS) {
          logger.debug("" + prepend + " attempting to deposit funds to business: " + transaction.entity.id);
          _depositFunds(api.Businesses, api.Polls, document, transaction, true, true, function(error, doc) {
            if (error != null) {
              logger.error(error);
              return callback(error);
            } else if (doc != null) {
              return callback(null, doc);
            } else {
              error = {
                message: "unable to deposit funds back"
              };
              return _setTransactionError(api.Polls, document, transaction, true, true, error, {}, function(error, doc) {
                setProcessed = false;
                return callback(null, null);
              });
            }
          });
        } else if (transaction.entity.type === choices.entities.CONSUMER) {
          logger.debug("" + prepend + " attempting to deposit funds to consumer: " + transaction.entity.id);
          _depositFunds(api.Consumers, api.Polls, document, transaction, true, true, function(error, doc) {
            if (error != null) {
              logger.error(error);
              return callback(error);
            } else if (doc != null) {
              return callback(null, doc);
            } else {
              error = {
                message: "unabled to deposit funds back"
              };
              return _setTransactionError(api.Polls, document, transaction, true, true, error, {}, function(error, doc) {
                setProcessed = false;
                return callback(null, null);
              });
            }
          });
        } else {
          callback({
            name: "NullError",
            message: "Unsupported Entity Type: " + transaction.entity.type
          });
        }
      },
      setProcessed: function(callback) {
        var $update;
        if (setProcessed === false) {
          callback(null, null);
          return;
        }
        $update = {};
        _setTransactionProcessed(api.Polls, document, transaction, true, true, $update, callback);
        return api.Streams.pollDeleted(document);
      }
    }, function(error, results) {
      var clean;
      clean = false;
      if (error != null) {
        logger.error(error);
        if (error.name === "TransactionAlreadyCompleted") {
          clean = true;
        } else {
          logger.error("" + prepend + " the poller will try later");
          return;
        }
      } else if (results && (results.setProcessed != null)) {
        clean = true;
      }
      if (clean === true) {
        return cleanup(function(error, dbTransaction) {
          if (error != null) {
            logger.error(error);
            return logger.error("" + prepend + " unable to properly clean up - the poller will try later");
          }
        });
      }
    });
  };

  pollAnswered = function(document, transaction) {
    var cleanup, prepend, setProcessed;
    prepend = "ID: " + document._id + " - TID: " + transaction.id;
    logger.info("Creating transaction for answered poll question");
    logger.info("" + prepend + " - " + transaction.direction);
    cleanup = function(callback) {
      logger.info("" + prepend + " cleaning up");
      return _cleanupTransaction(document, transaction, api.Polls, [api.Polls, api.Consumers], callback);
    };
    setProcessed = true;
    return async.series({
      setProcessing: function(callback) {
        _setTransactionProcessing(api.Polls, document, transaction, false, function(error, doc) {
          document = doc;
          return callback(error, doc);
        });
      },
      depositFunds: function(callback) {
        if (transaction.entity.type === choices.entities.CONSUMER) {
          logger.debug("" + prepend + " attempting to deposit funds to consumer: " + transaction.entity.id);
          _depositFunds(api.Consumers, api.Polls, document, transaction, false, false, function(error, doc) {
            if (error != null) {
              logger.error(error);
              return callback(error);
            } else if (doc != null) {
              return callback(null, doc);
            } else {
              error = {
                message: "entity to deposit funds to was not found"
              };
              return _setTransactionError(api.Polls, document, transaction, false, false, error, {}, function(error, doc) {
                setProcessed = false;
                return callback(null, null);
              });
            }
          });
        } else {
          callback({
            name: "NullError",
            message: "Unsupported Entity Type: " + transaction.entity.type
          });
        }
      },
      setProcessed: function(callback) {
        var $pushAll, $update, statTransaction;
        if (setProcessed === false) {
          callback();
          return;
        }
        statTransaction = api.Polls.createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.STAT_POLL_ANSWERED, {
          timestamp: transaction.data.timestamp
        }, choices.transactions.directions.OUTBOUND, transaction.entity);
        $pushAll = {
          "transactions.ids": [statTransaction.id],
          "transactions.temp": [statTransaction]
        };
        $update = {
          $pushAll: $pushAll
        };
        _setTransactionProcessedAndCreateNew(api.Polls, document, transaction, [statTransaction], false, false, $update, callback);
        return api.Streams.pollAnswered(transaction.entity, transaction.data.timestamp, document);
      }
    }, function(error, results) {
      var clean;
      clean = false;
      if (error != null) {
        logger.error(error);
        if (error.name === "TransactionAlreadyCompleted") {
          clean = true;
        } else {
          logger.error("" + prepend + " the poller will try later");
          return;
        }
      } else if (results && (results.setProcessed != null)) {
        clean = true;
      }
      if (clean === true) {
        return cleanup(function(error, dbTransaction) {
          if (error != null) {
            logger.error(error);
            return logger.error("" + prepend + " unable to properly clean up - the poller will try later");
          }
        });
      }
    });
  };

  btTapped = function(document, transaction) {
    var cleanup, prepend, setProcessed;
    prepend = "ID: " + document._id + " - TID: " + transaction.id;
    logger.info("Creating transaction for business transaction");
    logger.info("" + prepend + " - " + transaction.direction);
    cleanup = function(callback) {
      logger.info("" + prepend + " cleaning up");
      return _cleanupTransaction(document, transaction, api.BusinessTransactions, [api.BusinessTransactions, api.Consumers], callback);
    };
    setProcessed = true;
    return async.series({
      setProcessing: function(callback) {
        _setTransactionProcessing(api.BusinessTransactions, document, transaction, false, function(error, doc) {
          document = doc;
          return callback(error, doc);
        });
      },
      depositFunds: function(callback) {
        logger.debug(transaction.data);
        if (document.userEntity.type === choices.entities.CONSUMER) {
          logger.debug("" + prepend + " attempting to incrment donated for consumer: " + transaction.entity.id);
          _incrementDonated(api.Consumers, api.BusinessTransactions, document, transaction, document.userEntity, document.donationAmount, false, false, function(error, doc) {
            if (error != null) {
              logger.error(error);
              return callback(error);
            } else if (doc != null) {
              return callback(null, doc);
            } else {
              error = {
                message: "entity to increment donated for was not found"
              };
              return _setTransactionError(api.BusinessTransactions, document, transaction, false, false, error, {}, function(error, doc) {
                setProcessed = false;
                return callback(null, null);
              });
            }
          });
        } else {
          callback({
            name: "NullError",
            message: "Unsupported Entity Type: " + document.userEntity.type
          });
          return;
        }
      },
      setProcessed: function(callback) {
        var $pushAll, $update, statTransaction;
        if (setProcessed === false) {
          callback();
          return;
        }
        statTransaction = api.BusinessTransactions.createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.STAT_BT_TAPPED, {
          timestamp: transaction.data.timestamp
        }, choices.transactions.directions.OUTBOUND, transaction.entity);
        statTransaction.data = transaction.data;
        $pushAll = {
          "transactions.ids": [statTransaction.id],
          "transactions.temp": [statTransaction]
        };
        $update = {
          $pushAll: $pushAll
        };
        return _setTransactionProcessedAndCreateNew(api.BusinessTransactions, document, transaction, [statTransaction], false, false, $update, callback);
      }
    }, function(error, results) {
      var clean;
      clean = false;
      if (error != null) {
        logger.error(error);
        if (error.name === "TransactionAlreadyCompleted") {
          clean = true;
        } else {
          logger.error("" + prepend + " the poller will try later");
          return;
        }
      } else if (results && (results.setProcessed != null)) {
        clean = true;
      }
      if (clean === true) {
        return cleanup(function(error, dbTransaction) {
          if (error != null) {
            logger.error(error);
            return logger.error("" + prepend + " unable to properly clean up - the poller will try later");
          }
        });
      }
    });
  };

  btBarcodeClaimed = function(document, transaction) {
    var cleanup, prepend;
    prepend = "ID: " + document._id + " - TID: " + transaction.id;
    logger.info("BT - User claimed barcode");
    logger.info("" + prepend + " - " + transaction.direction);
    cleanup = function(callback) {
      logger.info("" + prepend + " cleaning up");
      return _cleanupTransaction(document, transaction, api.Consumers, [api.Consumers, api.BusinessTransactions], callback);
    };
    return async.series({
      setProcessing: function(callback) {
        _setTransactionProcessing(api.Consumers, document, transaction, false, function(error, doc) {
          document = doc;
          return callback(error, doc);
        });
      },
      claimBarcode: function(callback) {
        var transactionId;
        transactionId = transaction.id;
        return api.BusinessTransactions.claimBarcodeId(transaction.entity, document.barcodeId, function(error, count) {
          if (error != null) {
            logger.error(error);
            return callback(error);
          } else if (count > 0) {
            return callback(null, count);
          } else {
            return callback(null, null);
          }
        });
      },
      setProcessed: function(callback) {
        _setTransactionProcessed(api.Consumers, document, transaction, false, false, {}, callback);
      }
    }, function(error, results) {
      var clean;
      clean = false;
      if (error != null) {
        logger.error(error);
        if (error.name === "TransactionAlreadyCompleted") {
          clean = true;
        } else {
          logger.error("" + prepend + " the poller will try later");
          return;
        }
      } else if (results && (results.setProcessed != null)) {
        clean = true;
      }
      if (clean === true) {
        return cleanup(function(error, dbTransaction) {
          if (error != null) {
            logger.error(error);
            return logger.error("" + prepend + " unable to properly clean up - the poller will try later");
          }
        });
      }
    });
  };

  discussionCreated = function(document, transaction) {
    var cleanup, prepend, setProcessed;
    prepend = "ID: " + document._id + " - TID: " + transaction.id;
    logger.info("Creating transaction for discussion that was created");
    logger.info("ID: " + document._id + " - TID: " + transaction.id + " - " + transaction.direction);
    cleanup = function(callback) {
      var entityClass;
      logger.info("" + prepend + " cleaning up");
      if (transaction.entity.type === choices.entities.CONSUMER) {
        entityClass = api.Consumers;
      } else if (transaction.entity.type === choices.entities.BUSINESS) {
        entityClass = api.Businesses;
      }
      return _cleanupTransaction(document, transaction, api.Discussions, [api.Discussions, entityClass], callback);
    };
    setProcessed = true;
    return async.series({
      setTransactionProcessing: function(callback) {
        _setTransactionProcessing(api.Discussions, document, transaction, true, callback);
      },
      deductFunds: function(callback) {
        if (transaction.entity.type === choices.entities.BUSINESS) {
          _deductFunds(api.Businesses, api.Discussions, document, transaction, true, true, function(error, doc) {
            if (error != null) {
              logger.error(error);
              return callback(error);
            } else if (doc != null) {
              return callback(null, doc);
            } else {
              error = {
                message: "there were insufficient funds"
              };
              return _setTransactionError(api.Discussions, document, transaction, true, true, error, {}, function(error, doc) {
                setProcessed = false;
                return callback(null, null);
              });
            }
          });
        } else if (transaction.entity.type === choices.entities.CONSUMER) {
          _deductFunds(api.Consumers, api.Discussions, document, transaction, true, true, function(error, doc) {
            if (error != null) {
              logger.error(error);
              return callback(error);
            } else if (doc != null) {
              return callback(null, doc);
            } else {
              error = {
                message: "there were insufficient funds"
              };
              return _setTransactionError(api.Discussions, document, transaction, true, true, error, {}, function(error, doc) {
                setProcessed = false;
                return callback(null, null);
              });
            }
          });
        } else {
          callback({
            name: "NullError",
            message: "Unsupported Entity Type: " + transaction.entity.type
          });
        }
      },
      setProcessed: function(callback) {
        var $set, $update, da;
        if (setProcessed === false) {
          callback(null, null);
          return;
        }
        $set = {
          "funds.allocated": transaction.data.amount,
          "funds.remaining": transaction.data.amount,
          "donors": [transaction.entity]
        };
        da = "donationAmounts." + transaction.entity.type + "_" + transaction.entity.id.toString();
        $set[da] = {
          allocated: transaction.data.amount,
          remaining: transaction.data.amount
        };
        $update = {
          $set: $set
        };
        _setTransactionProcessed(api.Discussions, document, transaction, true, true, $update, callback);
        return api.Streams.discussionCreated(document);
      }
    }, function(error, results) {
      var clean;
      clean = false;
      if (error != null) {
        logger.error(error);
        if (error.name === "TransactionAlreadyCompleted") {
          clean = true;
        } else {
          logger.error("" + prepend + " the poller will try later");
          return;
        }
      } else if (results && (results.setProcessed != null)) {
        clean = true;
      }
      if (clean === true) {
        return cleanup(function(error, dbTransaction) {
          if (error != null) {
            logger.error(error);
            return logger.error("" + prepend + " unable to properly clean up - the poller will try later");
          }
        });
      }
    });
  };

  discussionUpdated = function(document, transaction) {
    var cleanup, prepend, setProcessed;
    prepend = "ID: " + document._id + " - TID: " + transaction.id;
    logger.info("Creating transaction for a discussion that was updated");
    logger.info("" + prepend + " - " + transaction.direction);
    cleanup = function(callback) {
      var entityClass;
      logger.info("" + prepend + " cleaning up");
      if (transaction.entity.type === choices.entities.CONSUMER) {
        entityClass = api.Consumers;
      } else if (transaction.entity.type === choices.entities.BUSINESS) {
        entityClass = api.Businesses;
      }
      return _cleanupTransaction(document, transaction, api.Discussions, [api.Discussions, entityClass], callback);
    };
    setProcessed = true;
    return async.series({
      setProcessing: function(callback) {
        _setTransactionProcessing(api.Discussions, document, transaction, true, callback);
      },
      adjustFunds: function(callback) {
        transaction.data.amount = transaction.data.newAllocated - document.funds.allocated;
        if (transaction.entity.type === choices.entities.BUSINESS) {
          _deductFunds(api.Businesses, api.Discussions, document, transaction, true, true, function(error, doc) {
            if (error != null) {
              logger.error(error);
              return callback(error);
            } else if (doc != null) {
              return callback(null, doc);
            } else {
              error = {
                message: "there were insufficient funds"
              };
              return _setTransactionError(api.Discussions, document, transaction, true, true, error, {}, function(error, doc) {
                setProcessed = false;
                return callback(null, null);
              });
            }
          });
        } else if (transaction.entity.type === choices.entities.CONSUMER) {
          _deductFunds(api.Consumers, api.Discussions, document, transaction, true, true, function(error, doc) {
            if (error != null) {
              logger.error(error);
              return callback(error);
            } else if (doc != null) {
              return callback(null, doc);
            } else {
              error = {
                message: "there were insufficient funds"
              };
              return _setTransactionError(api.Discussions, document, transaction, true, true, error, {}, function(error, doc) {
                setProcessed = false;
                return callback(null, null);
              });
            }
          });
        } else {
          callback({
            name: "NullError",
            message: "Unsupported Entity Type: " + transaction.entity.type
          });
        }
      },
      setProcessed: function(callback) {
        var $set, $update;
        if (setProcessed === false) {
          callback();
          return;
        }
        $set = {
          "funds.allocated": transaction.data.newAllocated,
          "funds.remaining": document.funds.remaining + transaction.data.amount,
          "funds.perResponse": transaction.data.perResponse,
          "donors": [transaction.data.entity]
        };
        $set["donationAmounts." + transaction.entity.type + "_" + transaction.entity.id] = {
          allocated: transaction.data.newAllocated,
          remaining: transaction.data.newAllocated
        };
        $update = {
          $set: $set
        };
        _setTransactionProcessed(api.Discussions, document, transaction, true, true, $update, callback);
        return api.Streams.discussionUpdated(document);
      }
    }, function(error, results) {
      var clean;
      clean = false;
      if (error != null) {
        logger.error(error);
        if (error.name === "TransactionAlreadyCompleted") {
          clean = true;
        } else {
          logger.error("" + prepend + " the poller will try later");
          return;
        }
      } else if (results && (results.setProcessed != null)) {
        clean = true;
      }
      if (clean === true) {
        return cleanup(function(error, dbTransaction) {
          if (error != null) {
            logger.error(error);
            return logger.error("" + prepend + " unable to properly clean up - the poller will try later");
          }
        });
      }
    });
  };

  discussionDeleted = function(document, transaction) {
    var cleanup, prepend, setProcessed;
    prepend = "ID: " + document._id + " - TID: " + transaction.id;
    logger.info("Creating transaction for a discussion that was deleted");
    logger.info("" + prepend + " - " + transaction.direction);
    cleanup = function(callback) {
      var entityClass;
      logger.info("" + prepend + " cleaning up");
      if (transaction.entity.type === choices.entities.CONSUMER) {
        entityClass = api.Consumers;
      } else if (transaction.entity.type === choices.entities.BUSINESS) {
        entityClass = api.Businesses;
      }
      return _cleanupTransaction(document, transaction, api.Discussions, [api.Discussions, entityClass], callback);
    };
    setProcessed = true;
    return async.series({
      setTransactionProcessing: function(callback) {
        _setTransactionProcessing(api.Discussions, document, transaction, true, callback);
      },
      depositFunds: function(callback) {
        transaction.entity.type = document.entity.type;
        transaction.entity.id = document.entity.id;
        transaction.data.amount = document.funds.remaining;
        logger.debug(transaction);
        logger.debug("" + prepend + " going to try and deposit funds: " + transaction.entity.id);
        if (transaction.entity.type === choices.entities.BUSINESS) {
          logger.debug("" + prepend + " attempting to deposit funds to business: " + transaction.entity.id);
          _depositFunds(api.Businesses, api.Discussions, document, transaction, true, true, function(error, doc) {
            if (error != null) {
              logger.error(error);
              return callback(error);
            } else if (doc != null) {
              return callback(null, doc);
            } else {
              error = {
                message: "unable to deposit funds back"
              };
              return _setTransactionError(api.Discussions, document, transaction, true, true, error, {}, function(error, doc) {
                setProcessed = false;
                return callback(null, null);
              });
            }
          });
        } else if (transaction.entity.type === choices.entities.CONSUMER) {
          logger.debug("" + prepend + " attempting to deposit funds to consumer: " + transaction.entity.id);
          _depositFunds(api.Consumers, api.Discussions, document, transaction, true, true, function(error, doc) {
            if (error != null) {
              logger.error(error);
              return callback(error);
            } else if (doc != null) {
              return callback(null, doc);
            } else {
              error = {
                message: "unabled to deposit funds back"
              };
              return _setTransactionError(api.Discussions, document, transaction, true, true, error, {}, function(error, doc) {
                setProcessed = false;
                return callback(null, null);
              });
            }
          });
        } else {
          callback({
            name: "NullError",
            message: "Unsupported Entity Type: " + transaction.entity.type
          });
        }
      },
      setProcessed: function(callback) {
        var $update;
        if (setProcessed === false) {
          callback(null, null);
          return;
        }
        $update = {};
        _setTransactionProcessed(api.Discussions, document, transaction, true, true, $update, callback);
        return api.Streams.discussionDeleted(document);
      }
    }, function(error, results) {
      var clean;
      clean = false;
      if (error != null) {
        logger.error(error);
        if (error.name === "TransactionAlreadyCompleted") {
          clean = true;
        } else {
          logger.error("" + prepend + " the poller will try later");
          return;
        }
      } else if (results && (results.setProcessed != null)) {
        clean = true;
      }
      if (clean === true) {
        return cleanup(function(error, dbTransaction) {
          if (error != null) {
            logger.error(error);
            return logger.error("" + prepend + " unable to properly clean up - the poller will try later");
          }
        });
      }
    });
  };

  discussionDonated = function(document, transaction) {
    var cleanup, prepend, setProcessed;
    prepend = "ID: " + document._id + " - TID: " + transaction.id;
    logger.info("Creating transaction for a discussion that was donated to");
    logger.info("" + prepend + " - " + transaction.direction);
    cleanup = function(callback) {
      var entityClass;
      logger.info("" + prepend + " cleaning up");
      if (transaction.entity.type === choices.entities.CONSUMER) {
        entityClass = api.Consumers;
      } else if (transaction.entity.type === choices.entities.BUSINESS) {
        entityClass = api.Businesses;
      }
      return _cleanupTransaction(document, transaction, api.Discussions, [api.Discussions, entityClass], callback);
    };
    setProcessed = true;
    return async.series({
      setProcessing: function(callback) {
        _setTransactionProcessing(api.Discussions, document, transaction, false, callback);
      },
      deductFunds: function(callback) {
        if (transaction.entity.type === choices.entities.BUSINESS) {
          _deductFunds(api.Businesses, api.Discussions, document, transaction, false, false, function(error, doc) {
            if (error != null) {
              logger.error(error);
              return callback(error);
            } else if (doc != null) {
              return callback(null, doc);
            } else {
              error = {
                message: "there were insufficient funds"
              };
              return _setTransactionError(api.Discussions, document, transaction, false, false, error, {}, function(error, doc) {
                setProcessed = false;
                return callback(null, null);
              });
            }
          });
        } else if (transaction.entity.type === choices.entities.CONSUMER) {
          _deductFunds(api.Consumers, api.Discussions, document, transaction, false, false, function(error, doc) {
            if (error != null) {
              logger.error(error);
              return callback(error);
            } else if (doc != null) {
              return callback(null, doc);
            } else {
              error = {
                message: "there were insufficient funds"
              };
              return _setTransactionError(api.Discussions, document, transaction, false, false, error, {}, function(error, doc) {
                setProcessed = false;
                return callback(null, null);
              });
            }
          });
        } else {
          callback({
            name: "NullError",
            message: "Unsupported Entity Type: " + transaction.entity.type
          });
        }
      },
      setProcessed: function(callback) {
        var $addToSet, $inc, $update;
        if (setProcessed === false) {
          callback();
          return;
        }
        $inc = {
          "funds.allocated": transaction.data.amount,
          "funds.remaining": transaction.data.amount
        };
        $inc["donationAmounts." + transaction.entity.type + "_" + transaction.entity.id + ".allocated"] = transaction.data.amount;
        $inc["donationAmounts." + transaction.entity.type + "_" + transaction.entity.id + ".remaining"] = transaction.data.amount;
        $addToSet = {
          "donors": transaction.entity
        };
        $update = {
          $addToSet: $addToSet,
          $inc: $inc
        };
        return _setTransactionProcessed(api.Discussions, document, transaction, false, false, $update, callback);
      }
    }, function(error, results) {
      var clean;
      clean = false;
      if (error != null) {
        logger.error(error);
        if (error.name === "TransactionAlreadyCompleted") {
          clean = true;
        } else {
          logger.error("" + prepend + " the poller will try later");
          return;
        }
      } else if (results && (results.setProcessed != null)) {
        clean = true;
      }
      if (clean === true) {
        return cleanup(function(error, dbTransaction) {
          if (error != null) {
            logger.error(error);
            return logger.error("" + prepend + " unable to properly clean up - the poller will try later");
          }
        });
      }
    });
  };

  discussionThanked = function(document, transaction) {
    var cleanup, error, prepend, setClean, setProcessed, thankedEntityApiClass, thankerEntityApiClass;
    prepend = "ID: " + document._id + " - TID: " + transaction.id;
    logger.info("Creating transaction for entity of type " + transaction.entity.type + " thanked in discussion by " + transaction.data.thankerEntity.type);
    logger.info("" + prepend + " - " + transaction.direction);
    thankerEntityApiClass = null;
    thankedEntityApiClass = null;
    if (transaction.data.thankerEntity.type === choices.entities.CONSUMER) {
      thankerEntityApiClass = api.Consumers;
    } else if (transaction.data.thankerEntity.type === choices.entities.BUSINESS) {
      thankerEntityApiClass = api.Businesses;
    } else {
      logger.error("" + prepend + " - THANKER ENTITY TYPE " + transaction.data.thankerEntity.type + " NOT SUPPORTED FOR THIS TRANSACTION");
      return;
    }
    if (transaction.entity.type === choices.entities.CONSUMER) {
      thankedEntityApiClass = api.Consumers;
    } else if (transaction.entity.type === choices.entities.BUSINESS) {
      thankedEntityApiClass = api.Businesses;
    } else {
      logger.error("" + prepend + " - THANKED ENTITY TYPE " + transaction.entity.type + " NOT SUPPORTED FOR THIS TRANSACTION");
      error = {
        message: "the entity type: " + transaction.entity.type + " is not supported"
      };
      _setTransactionErrorAndRefund(thankerEntityApiClass, document, transaction, false, false, error, {}, function(error, doc) {});
      return;
    }
    cleanup = function(callback) {
      logger.info("" + prepend + " cleaning up");
      return _cleanupTransaction(document, transaction, thankerEntityApiClass, [thankerEntityApiClass, thankedEntityApiClass], callback);
    };
    setProcessed = true;
    setClean = false;
    return async.series({
      setProcessing: function(callback) {
        _setTransactionProcessing(thankerEntityApiClass, document, transaction, false, function(error, doc) {
          document = doc;
          return callback(error, doc);
        });
      },
      depositFunds: function(callback) {
        logger.debug("" + prepend + " attempting to deposit funds to entity type: " + transaction.entity.type + " with id: " + transaction.entity.id);
        _depositFunds(thankedEntityApiClass, thankerEntityApiClass, document, transaction, false, false, function(error, doc) {
          if (error != null) {
            logger.error(error);
            return callback(error);
          } else if (doc != null) {
            logger.info("" + prepend + " successfully deposited funds");
            return callback(null, doc);
          } else {
            error = {
              message: "the entity to transfer funds to doesn't exist"
            };
            return _setTransactionErrorAndRefund(thankerEntityApiClass, document, transaction, false, false, error, {}, function(error, doc) {
              setProcessed = false;
              setClean = true;
              return callback();
            });
          }
        });
      },
      setProcessed: function(callback) {
        if (setProcessed === false) {
          callback();
          return;
        }
        return _setTransactionProcessed(thankerEntityApiClass, document, transaction, false, false, {}, function(error, doc) {
          var $inc, $push, $update;
          if (error != null) {
            return callback(error);
          } else if (!(doc != null)) {
            callback(error, doc);
          } else {
            callback(error, doc);
            $push = {
              "responses.$.thanks.by": {
                entity: transaction.data.thankerEntity,
                amount: transaction.data.amount
              }
            };
            $inc = {
              "responses.$.earned": transaction.data.amount,
              "responses.$.thanks.count": 1,
              "responses.$.thanks.amount": transaction.data.amount
            };
            $update = {
              $push: $push,
              $inc: $inc
            };
            return api.Discussions.model.collection.update({
              _id: transaction.data.discussionId,
              "responses._id": transaction.data.responseId
            }, $update);
          }
        });
      }
    }, function(error, results) {
      var clean;
      clean = setClean;
      if (error != null) {
        logger.error(error);
        if (error.name === "TransactionAlreadyCompleted") {
          clean = true;
        } else {
          logger.error("" + prepend + " the poller will try later");
          return;
        }
      } else if (results && (results.setProcessed != null)) {
        clean = true;
      }
      if (clean === true) {
        return cleanup(function(error, dbTransaction) {
          if (error != null) {
            logger.error(error);
            return logger.error("" + prepend + " unable to properly clean up - the poller will try later");
          }
        });
      }
    });
  };

  discussionDonationDistributed = function(document, transaction) {
    var cleanup, doneeEntityApiClass, error, prepend, setProcessed;
    prepend = "ID: " + document._id + " - TID: " + transaction.id;
    logger.info("Creating transaction for donation distributed to entity of type " + transaction.entity.type + " discussion by entity of type " + transaction.data.donorEntity.type);
    logger.info("" + prepend + " - " + transaction.direction);
    if (transaction.entity.type === choices.entities.CONSUMER) {
      doneeEntityApiClass = api.Consumers;
    } else if (transaction.entity.type === choices.entities.BUSINESS) {
      doneeEntityApiClass = api.Businesses;
    } else {
      logger.error("" + prepend + " - DONEE ENTITY TYPE " + transaction.entity.type + " NOT SUPPORTED FOR THIS TRANSACTION");
      error = {
        message: "the entity type: " + transaction.entity.type + " is not supported"
      };
      _setTransactionError(api.Discussions, document, transaction, false, false, error, {}, function(error, doc) {});
      return;
    }
    cleanup = function(callback) {
      logger.info("" + prepend + " cleaning up");
      return _cleanupTransaction(document, transaction, api.Discussions, [api.Discussions, doneeEntityApiClass], callback);
    };
    setProcessed = true;
    return async.series({
      setProcessing: function(callback) {
        _setTransactionProcessing(api.Discussions, document, transaction, false, function(error, doc) {
          document = doc;
          return callback(error, doc);
        });
      },
      depositFunds: function(callback) {
        logger.debug("" + prepend + " attempting to deposit funds to entity type: " + transaction.entity.type + " with id: " + transaction.entity.id);
        _depositFunds(doneeEntityApiClass, api.Discussions, document, transaction, false, false, function(error, doc) {
          if (error != null) {
            logger.error(error);
            return callback(error);
          } else if (doc != null) {
            logger.info("" + prepend + " successfully deposited funds");
            return callback(null, doc);
          } else {
            error = {
              message: "the entity to transfer funds to doesn't exist"
            };
            return _setTransactionError(api.Discussions, document, transaction, false, false, error, {}, function(error, doc) {
              setProcessed = false;
              return callback(null, null);
            });
          }
        });
      },
      setProcessed: function(callback) {
        if (setProcessed === false) {
          callback();
          return;
        }
        return _setTransactionProcessed(api.Discussions, document, transaction, false, false, {}, function(error, doc) {
          var $inc, $push, $update;
          if (error != null) {
            return callback(error);
          } else if (!(doc != null)) {
            callback(error, doc);
          } else {
            callback(error, doc);
            $push = {
              "responses.$.donations.by": {
                entity: transaction.data.donorEntity,
                amount: transaction.data.amount
              }
            };
            $inc = {
              "responses.$.earned": transaction.data.amount,
              "responses.$.donations.count": 1,
              "responses.$.donations.amount": transaction.data.amount
            };
            $inc["donationAmounts." + transaction.data.donorEntity.type + "_" + transaction.data.donorEntity.id + ".remaining"] = -1 * transaction.data.amount;
            $update = {
              $push: $push,
              $inc: $inc
            };
            return api.Discussions.model.collection.update({
              _id: transaction.data.discussionId,
              "responses._id": transaction.data.responseId
            }, $update);
          }
        });
      }
    }, function(error, results) {
      var clean;
      clean = false;
      if (error != null) {
        logger.error(error);
        if (error.name === "TransactionAlreadyCompleted") {
          clean = true;
        } else {
          logger.error("" + prepend + " the poller will try later");
          return;
        }
      } else if (results && (results.setProcessed != null)) {
        clean = true;
      }
      if (clean === true) {
        return cleanup(function(error, dbTransaction) {
          if (error != null) {
            logger.error(error);
            return logger.error("" + prepend + " unable to properly clean up - the poller will try later");
          }
        });
      }
    });
  };

  statPollAnswered = function(document, transaction) {
    var cleanup, prepend;
    prepend = "ID: " + document._id + " - TID: " + transaction.id;
    logger.info("STAT - User answered poll question");
    logger.info("" + prepend + " - " + transaction.direction);
    cleanup = function(callback) {
      logger.info("" + prepend + " cleaning up");
      return _cleanupTransaction(document, transaction, api.Polls, [api.Polls, api.Statistics], callback);
    };
    return async.series({
      setProcessing: function(callback) {
        _setTransactionProcessing(api.Polls, document, transaction, false, function(error, doc) {
          document = doc;
          return callback(error, doc);
        });
      },
      updateStats: function(callback) {
        var consumerId, org, transactionId;
        org = {
          type: document.entity.type,
          id: document.entity.id
        };
        consumerId = transaction.entity.id;
        transactionId = transaction.id;
        return api.Statistics.pollAnswered(org, consumerId, transactionId, transaction.data.timestamp, function(error, count) {
          if (error != null) {
            logger.error(error);
            return callback(error);
          } else if (count > 0) {
            return callback(null, count);
          } else {
            return callback(null, null);
          }
        });
      },
      setProcessed: function(callback) {
        _setTransactionProcessed(api.Polls, document, transaction, false, false, {}, callback);
      }
    }, function(error, results) {
      var clean;
      clean = false;
      if (error != null) {
        logger.error(error);
        if (error.name === "TransactionAlreadyCompleted") {
          clean = true;
        } else {
          logger.error("" + prepend + " the poller will try later");
          return;
        }
      } else if (results && (results.setProcessed != null)) {
        clean = true;
      }
      if (clean === true) {
        return cleanup(function(error, dbTransaction) {
          if (error != null) {
            logger.error(error);
            return logger.error("" + prepend + " unable to properly clean up - the poller will try later");
          }
        });
      }
    });
  };

  statBtTapped = function(document, transaction) {
    var apiStatClass, cleanup, prepend;
    prepend = "ID: " + document._id + " - TID: " + transaction.id;
    logger.info("STAT - User tapped in at a business");
    logger.info("" + prepend + " - " + transaction.direction);
    apiStatClass = void 0;
    cleanup = function(callback) {
      logger.info("" + prepend + " cleaning up");
      return _cleanupTransaction(document, transaction, api.BusinessTransactions, [api.BusinessTransactions, apiStatClass], callback);
    };
    return async.series({
      setProcessing: function(callback) {
        _setTransactionProcessing(api.BusinessTransactions, document, transaction, false, function(error, doc) {
          document = doc;
          return callback(error, doc);
        });
      },
      updateStats: function(callback) {
        var identifier, org, transactionId;
        org = document.organizationEntity;
        transactionId = transaction.id;
        if ((document.userEntity != null) && (document.userEntity.id != null)) {
          logger.info("" + prepend + " entity found - storing to Statistics");
          apiStatClass = api.Statistics;
          identifier = document.userEntity.id;
        } else {
          logger.info("" + prepend + " entity not found - storing to UnclaimedBarcodeStatistics");
          apiStatClass = api.UnclaimedBarcodeStatistics;
          identifier = document.barcodeId;
        }
        return apiStatClass.btTapped(org, identifier, transactionId, document.amount, document.karmaPoints, document.donationAmount, document.date, function(error, count) {
          if (error != null) {
            logger.error(error);
            return callback(error);
          } else if (count > 0) {
            return callback(null, count);
          } else {
            return callback(null, null);
          }
        });
      },
      setProcessed: function(callback) {
        _setTransactionProcessed(api.BusinessTransactions, document, transaction, false, false, {}, callback);
      }
    }, function(error, results) {
      var clean;
      clean = false;
      if (error != null) {
        logger.error(error);
        if (error.name === "TransactionAlreadyCompleted") {
          clean = true;
        } else {
          logger.error("" + prepend + " the poller will try later");
          return;
        }
      } else if (results && (results.setProcessed != null)) {
        clean = true;
      }
      if (clean === true) {
        return cleanup(function(error, dbTransaction) {
          if (error != null) {
            logger.error(error);
            return logger.error("" + prepend + " unable to properly clean up - the poller will try later");
          }
        });
      }
    });
  };

  statBarcodeClaimed = function(document, transaction) {
    var cleanup, copyStats, prepend, totalDonated;
    logger.silly(document);
    prepend = "ID: " + document._id + " - TID: " + transaction.id;
    logger.info("STAT - User claimed barcode");
    logger.info("" + prepend + " - " + transaction.direction);
    totalDonated = 0;
    cleanup = function(callback) {
      logger.info("" + prepend + " cleaning up");
      return _cleanupTransaction(document, transaction, api.Consumers, [api.Consumers, api.Statistics], callback);
    };
    copyStats = function(unclaimedBarcodeStatistic, callback) {
      var consumerId, donationAmount, karmaPointsEarned, org, spent, timestamp, totalTapIns;
      logger.info("" + prepend + " copying from UnclaimedBarcodeStatistics to Statistics");
      logger.silly(unclaimedBarcodeStatistic);
      org = unclaimedBarcodeStatistic.org;
      consumerId = transaction.entity.id;
      if ((unclaimedBarcodeStatistic.data != null) && (unclaimedBarcodeStatistic.data.tapIns != null)) {
        spent = unclaimedBarcodeStatistic.data.tapIns.totalAmountPurchased || 0;
        donationAmount = unclaimedBarcodeStatistic.data.tapIns.totalDonated || 0;
        karmaPointsEarned = unclaimedBarcodeStatistic.data.karmaPoints.earned || 0;
        timestamp = unclaimedBarcodeStatistic.data.tapIns.lastVisited;
        totalTapIns = unclaimedBarcodeStatistic.data.tapIns.totalTapIns || 0;
        totalDonated += donationAmount;
      } else {
        callback();
        return;
      }
      return api.Statistics.btTapped(org, consumerId, transaction.id, spent, karmaPointsEarned, donationAmount, timestamp, totalTapIns, function(error, count) {
        if (error != null) {
          callback(error);
          return;
        }
        callback();
      });
    };
    return async.series({
      setProcessing: function(callback) {
        _setTransactionProcessing(api.Consumers, document, transaction, false, function(error, doc) {
          document = doc;
          return callback(error, doc);
        });
      },
      updateStats: function(callback) {
        var barcodeId, claimId, transactionId;
        transactionId = transaction.id;
        claimId = transactionId;
        barcodeId = document.barcodeId;
        logger.info("" + prepend + " claiming barcode");
        return api.UnclaimedBarcodeStatistics.claimBarcodeId(barcodeId, transactionId, function(error, count) {
          if (error != null) {
            logger.error(error);
            callback(error);
            return;
          }
          logger.info("" + prepend + " get claimed");
          return api.UnclaimedBarcodeStatistics.getClaimed(claimId, function(error, unclaimedBarcodeStatistics) {
            if (error != null) {
              logger.error(error);
              callback(error);
              return;
            }
            logger.info("" + prepend + " loop through recently claimed");
            return async.forEach(unclaimedBarcodeStatistics, copyStats, function(error) {
              if (error != null) {
                callback(error);
                return;
              }
              callback();
            });
          });
        });
      },
      setProcessed: function(callback) {
        var $inc, $pushAll, $update, ucbsClaimedTransaction;
        ucbsClaimedTransaction = api.Consumers.createTransaction(choices.transactions.states.PENDING, choices.transactions.actions.UCBS_CLAIMED, {
          claimId: transaction.id
        }, choices.transactions.directions.OUTBOUND, transaction.entity);
        $inc = {
          "funds.donated": totalDonated
        };
        $pushAll = {
          "transactions.ids": [ucbsClaimedTransaction.id],
          "transactions.temp": [ucbsClaimedTransaction]
        };
        $update = {
          $pushAll: $pushAll,
          $inc: $inc
        };
        _setTransactionProcessedAndCreateNew(api.Consumers, document, transaction, [ucbsClaimedTransaction], false, false, $update, function(error, consumer) {
          var socketChannel;
          callback(error, consumer);
          if ((error != null) || !(consumer != null)) return;
          socketChannel = transaction.entity.id.toString();
          utils.sendMessage(socketChannel, "refreshUserHeader");
        });
      }
    }, function(error, results) {
      var clean;
      clean = false;
      if (error != null) {
        logger.error(error);
        if (error.name === "TransactionAlreadyCompleted") {
          clean = true;
        } else {
          logger.error("" + prepend + " the poller will try later");
          return;
        }
      } else if (results && (results.setProcessed != null)) {
        clean = true;
      }
      if (clean === true) {
        return cleanup(function(error, dbTransaction) {
          if (error != null) {
            logger.error(error);
            return logger.error("" + prepend + " unable to properly clean up - the poller will try later");
          }
        });
      }
    });
  };

  ucbsClaimed = function(document, transaction) {
    var cleanup, prepend;
    prepend = "ID: " + document._id + " - TID: " + transaction.id;
    logger.info("UCBS - Barcode has been claimed so remove the old unclaimed barcode statistics data");
    logger.info("" + prepend + " - " + transaction.direction);
    cleanup = function(callback) {
      logger.info("" + prepend + " cleaning up");
      return _cleanupTransaction(document, transaction, api.Consumers, [api.Consumers, api.UnclaimedBarcodeStatistics], callback);
    };
    return async.series({
      setProcessing: function(callback) {
        _setTransactionProcessing(api.Consumers, document, transaction, false, function(error, doc) {
          document = doc;
          return callback(error, doc);
        });
      },
      removeClaimedStatistics: function(callback) {
        logger.info("" + prepend + " removing claimed Barcode Statistic from UnclaimedBarcodeStatistics collection");
        return api.UnclaimedBarcodeStatistics.removeClaimed(transaction.data.claimId, function(error, count) {
          if (error != null) {
            callback(error);
            return;
          }
          callback();
        });
      },
      setProcessed: function(callback) {
        _setTransactionProcessed(api.Consumers, document, transaction, false, false, {}, callback);
      }
    }, function(error, results) {
      var clean;
      clean = false;
      if (error != null) {
        logger.error(error);
        if (error.name === "TransactionAlreadyCompleted") {
          clean = true;
        } else {
          logger.error("" + prepend + " the poller will try later");
          return;
        }
      } else if (results && (results.setProcessed != null)) {
        clean = true;
      }
      if (clean === true) {
        return cleanup(function(error, dbTransaction) {
          if (error != null) {
            logger.error(error);
            return logger.error("" + prepend + " unable to properly clean up - the poller will try later");
          }
        });
      }
    });
  };

  redemptionLogGoodyRedeemed = function(document, transaction) {
    var cleanup, prepend, redemptionLogDoc, setProcessed;
    prepend = "ID: " + document._id + " - TID: " + transaction.id;
    logger.info("Creating transaction for redemption log - consumer redeemed a goody");
    logger.info("" + prepend + " - " + transaction.direction);
    cleanup = function(callback) {
      logger.info("" + prepend + " cleaning up");
      return _cleanupTransaction(document, transaction, api.Statistics, [api.Statistics, api.RedemptionLogs], callback);
    };
    setProcessed = true;
    redemptionLogDoc = null;
    async.series({
      setProcessing: function(callback) {
        _setTransactionProcessing(api.Statistics, document, transaction, false, function(error, doc) {
          document = doc;
          callback(error, doc);
        });
      },
      addRedemptionLog: function(callback) {
        return api.RedemptionLogs.add(transaction.data.consumer, transaction.data.org, transaction.data.locationId, transaction.data.registerId, transaction.data.goody, transaction.data.dateRedeemed, transaction.id, function(error, doc) {
          if (error != null) {
            if (error.code === 11000 || error.code === 11001) {
              callback(null, null);
              return;
            }
            logger.error(error);
            callback(error);
            return;
          }
          redemptionLogDoc = doc;
          callback(null, doc);
        });
      },
      setProcessed: function(callback) {
        _setTransactionProcessed(api.Statistics, document, transaction, false, false, {}, callback);
      }
    }, function(error, results) {
      var clean;
      clean = false;
      if (error != null) {
        logger.error(error);
        if (error.name === "TransactionAlreadyCompleted") {
          clean = true;
        } else {
          logger.error("" + prepend + " the poller will try later");
          return;
        }
      } else if (results && (results.setProcessed != null)) {
        clean = true;
      }
      if (clean === true) {
        cleanup(function(error, dbTransaction) {
          if (error != null) {
            logger.error(error);
            logger.error("" + prepend + " unable to properly clean up - the poller will try later");
          }
        });
      }
    });
  };

  exports.process = process;

}).call(this);
