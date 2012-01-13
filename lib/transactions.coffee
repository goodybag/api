async = require "async"

globals = require "globals"
loggers = require "./loggers"
api = require "./api"

logger = loggers.transaction
choices = globals.choices

process = (document, transaction)-> #this is just a router
  switch transaction.action

    #FINANCIAL - POLLS
    when choices.transactions.actions.POLL_CREATED
      pollCreated(document, transaction)
    when choices.transactions.actions.POLL_UPDATED
      pollUpdated(document, transaction)
    when choices.transactions.actions.POLL_DELETED
      pollDeleted(document, transaction)
    when choices.transactions.actions.POLL_ANSWERED
      pollAnswered(document, transaction)

    #FINANCIAL - DISCUSSIONS
    when choices.transactions.actions.DISCUSSION_CREATED
      discussionCreated(document, transaction)

    when choices.transactions.actions.DISCUSSION_UPDATED
      discussionUpdated(document, transaction)

    when choices.transactions.actions.DISCUSSION_DELETED
      discussionDeleted(document, transaction)

    #STAT - POLLS
    when choices.transactions.actions.STAT_POLL_ANSWERED
      statPollAnswered(document, transaction)

_setTransactionProcessing = (clazz, document, transaction, locking, callback)->
  prepend = "ID: #{document._id} - TID: #{transaction.id}"
  clazz.setTransactionProcessing document._id, transaction.id, locking, (error, doc)->
    if error?
      logger.error "#{prepend} transitioning state to processing failed"
      callback(error)
    else if !doc? #if document doesn't exist
      logger.warn "#{prepend} the transaction state may have moved to processed or error" #if not the poller will take care of it
      callback({name: "NullError", message: "Document Does Not Exist"})
    else
      logger.info "#{prepend} Processing Transaction"

      callback(null, doc)
    return

_setTransactionProcessed = (clazz, document, transaction, locking, removeLock, modifierDoc, callback)->
  prepend = "ID: #{document._id} - TID: #{transaction.id}"
  clazz.setTransactionProcessed document._id, transaction.id, locking, removeLock, modifierDoc, (error, doc)->
    if error?
      logger.error "#{prepend} transitioning to state processed failed"
      callback(error)
    else if !doc?
      logger.warn "#{prepend} the transaction state may already be processed" #if not the poller will take care of it
      callback({name: "TransactionWarning", message:"Unable to set state to processed. Transaction may have already been processed, quitting further processing"})
    else
      logger.info "#{prepend} transaction state is set to processed successfully"
      callback(null, doc)
    return

_setTransactionProcessedAndCreateNew = (clazz, document, transaction, newTransactions, locking, removeLock, modifierDoc, callback)->
  prepend = "ID: #{document._id} - TID: #{transaction.id}"
  clazz.setTransactionProcessed document._id, transaction.id, locking, removeLock, modifierDoc, (error, doc)->
    if error?
      logger.error "#{prepend} transitioning to state processed failed"
      callback(error)
    else if !doc?
      logger.warn "#{prepend} the transaction state may already be processed" #if not the poller will take care of it
      callback({name: "TransactionWarning", message:"Unable to set state to processed. Transaction may have already been processed, quitting further processing"})
    else
      logger.info "#{prepend} transaction state is set to processed successfully"
      callback(null, doc)
      if !Object.isArray(newTransactions)
        newTransactions = [newTransactions]

      #process each transaction that is is to be processed
      for newT in newTransactions
        (
          ()->
            trans = newT
            logger.debug trans
            clazz.moveTransactionToLog document._id, trans, (error, doc2)->
              if error?
                logger.error "#{prepend} moving #{trans.action} transaction from temporary to log failed"
              else if !doc2?
                logger.warn "#{prepend} the new transaction is already in progress - pollers will move it if it is still in temp"
              else
                logger.info "#{prepend} created #{trans.action} transaction: #{trans.id}"
                process(document, trans)
        )()
    return

_setTransactionError = (clazz, document, transaction, locking, removeLock, error, data, callback)->
  prepend = "ID: #{document._id} - TID: #{transaction.id}"
  clazz.setTransactionError document._id, transaction.id, locking, removeLock, error, data, (error, doc)->
    if error?
      logger.error "#{prepend} problem setting transaction state to error"
      callback(error)
    else if !doc?
      logger.error "#{prepend} the document is already in a processed or error state" #if not the poller will retry
      callback({name: "TransactionError", messge: "Unable to set transaction state to error"})
    else
      logger.info "#{prepend} set transaction state to error successfully"
      callback(null, doc)

_deductFunds = (classFrom, initialTransactionClass, document, transaction, locking, removeLock, callback)->
  prepend = "ID: #{document._id} - TID: #{transaction.id}"
  classFrom.deductFunds transaction.entity.id, transaction.id, transaction.data.amount, (error, doc)->
    if error? #determine what type of error it is and then whether to setTransactionError or ignore and let the poller pick it up later (the later is probably the case)
      logger.error "#{prepend} deducting funds from #{transaction.entity.type}: #{transaction.entity.id} failed - database error"
      callback(error)
    else if !doc? #if the entity  object doesn't exist then either the transaction occured previously, there aren't enough funds, or the entity doesn't exist
      logger.info "#{prepend} transaction may have occured, VERIFYING"
      classFrom.checkIfTransactionExists transaction.entity.id, transaction.id, (error, doc2)->
        if error? #error querying, try again later
          callback(error)
        else if doc2? #transaction already occured
          logger.info "#{prepend} transaction already occured"
          callback(null, doc2)
        else #either not enough funds or the entity doesn't exist - in either case report insufficient funds
          logger.warn "#{prepend} There were insufficient funds"
          callback(null, null)

    else #transaction went through
      logger.info "#{prepend} Successfully deducted funds"
      callback(null, doc)
    return

_depositFunds = (classTo, initialTransactionClass, document, transaction, locking, removeLock, callback)->
  prepend = "ID: #{document._id} - TID: #{transaction.id}"
  classTo.depositFunds transaction.entity.id, transaction.id, transaction.data.amount, (error, doc)->
    if error?
      logger.error "#{prepend} depositing funds into #{transaction.entity.type}: #{transaction.entity.id} failed - database error"
      callback(error) #determine what type of error it is and then whether to setTransactionError or ignore and let the poller pick it up later (the later is probably the case)
    else if !doc? #if the consumer object doesn't exist then either the transaction occured previously, there aren't enough funds, or the entity doesn't exist
      logger.info "#{prepend} transaction may have occured, VERIFYING"
      classTo.checkIfTransactionExists transaction.entity.id, transaction.id, (error, doc2)->
        if error? #error querying, try again later
          logger.error "#{prepend} database error"
          callback(error)
        else if doc2? #transaction already occured
          logger.info "#{prepend} transaction already occured"
          callback(null, doc2)
        else #either not enough funds or the entity doesn't exist - in either case report insufficient funds
          logger.warn "#{prepend} There were insufficient funds"
          callback(null, null)
    else #transaction went through
      logger.info "#{prepend} Successfully deducted funds"
      callback(null, doc)
    return

#INBOUND
pollCreated = (document, transaction)->
  prepend = "ID: #{document._id} - TID: #{transaction.id}"
  logger.info "Creating transaction for poll"
  logger.info "ID: #{document._id} - TID: #{transaction.id} - #{transaction.direction}"

  setProcessed = true #setProcessed, unless something sets this to false
  async.series {
    setTransactionProcessing: (callback)->
      _setTransactionProcessing(api.Polls, document, transaction, true, callback)
      return

    deductFunds: (callback)->
      if transaction.entity.type is choices.entities.BUSINESS
        _deductFunds api.Businesses, api.Polls, document, transaction, true, true, (error, doc)->
          if error? #mongo errored out
            callback(error)
          else if doc?  #transaction was successful, so continue to set processed
            callback(null, doc)
          else #null, null passed in which meas insufficient funds, so set error, and exit
            error = {message: "there were insufficient funds"}
            _setTransactionError api.Polls, document, transaction, true, true, error, {}, (error, doc)->
              #we don't care if it set or if it didn't set because:
              # 1. if there was a mongo error then the poller will pick it up and work on it later
              # 2. if it did set then fantastic, we will exit because we don't want to set to processed
              # 3. if it did not set (no error, and no document updated) then we want to exit because
              #    it is already in an error or processed state. In that case we want to do nothing
              setProcessed = false
              callback(null, null)
      else if transaction.entity.type is choices.entities.CONSUMER
        _deductFunds api.Consumers, api.Polls, document, transaction, true, true, (error, doc)->
          if error? #mongo errored out
            callback(error)
          else if doc?  #transaction was successful, so continue to set processed
            callback(null, doc)
          else #null, null passed in which meas insufficient funds, so set error, and exit
            error = {message: "there were insufficient funds"}
            _setTransactionError api.Polls, document, transaction, true, true, error, {}, (error, doc)->
              #we don't care if it set or if it didn't set because:
              # 1. if there was a mongo error then the poller will pick it up and work on it later
              # 2. if it did set then fantastic, we will exit because we don't want to set to processed
              # 3. if it did not set (no error, and no document updated) then we want to exit because
              #    it is already in an error or processed state. In that case we want to do nothing
              setProcessed = false
              callback(null, null)
      else
        callback({name:"NullError", message: "Unsupported Entity Type: #{transaction.entity.type}"})
      return

    setProcessed: (callback)->
      if setProcessed is false
        callback(null, null) #we are not suppose to set to processed so exit cleanly
        return
      $set = {
        "funds.allocated": transaction.data.amount
        "funds.remaining": transaction.data.amount
      }

      $update = {
        $set: $set
      }

      _setTransactionProcessed(api.Polls, document, transaction, true, true, $update, callback)
      #if it went through great, if it didn't go through then the poller will take care of it
      #, no other state changes need to occur

      #Write to the event stream
      api.Streams.pollCreated(document) #we don't care about the callback
  },
  (error, results)->
    if error?
      logger.error "#{prepend} the poller will try later"

#INBOUND
pollUpdated = (document, transaction)->
  prepend = "ID: #{document._id} - TID: #{transaction.id}"
  logger.info "Creating transaction for a poll that was updated"
  logger.info "#{prepend} - #{transaction.direction}"

  setProcessed = true #setProcessed, unless something sets this to false
  async.series {
    setProcessing: (callback)->
      _setTransactionProcessing api.Polls, document, transaction, true, callback
      return

    adjustFunds: (callback)->
      #adjust balance before sending it to get adjusted
      transaction.data.amount = transaction.data.newAllocated - document.funds.allocated

      if transaction.entity.type is choices.entities.BUSINESS
        _deductFunds api.Businesses, api.Polls, document, transaction, true, true, (error, doc)->
          if error? #mongo errored out
            callback(error)
          else if doc?  #transaction was successful, so continue to set processed
            callback(null, doc)
          else #null, null passed in which meas insufficient funds, so set error, and exit
            error = {message: "there were insufficient funds"}
            _setTransactionError api.Polls, document, transaction, true, true, error, {}, (error, doc)->
              #we don't care if it set or if it didn't set because:
              # 1. if there was a mongo error then the poller will pick it up and work on it later
              # 2. if it did set then fantastic, we will exit because we don't want to set to processed
              # 3. if it did not set (no error, and no document updated) then we want to exit because
              #    it is already in an error or processed state. In that case we want to do nothing
              setProcessed = false
              callback(null, null)
      else if transaction.entity.type is choices.entities.CONSUMER
        _deductFunds api.Consumers, api.Polls, document, transaction, true, true, (error, doc)->
          if error? #mongo errored out
            callback(error)
          else if doc?  #transaction was successful, so continue to set processed
            callback(null, doc)
          else #null, null passed in which meas insufficient funds, so set error, and exit
            error = {message: "there were insufficient funds"}
            _setTransactionError api.Polls, document, transaction, true, true, error, {}, (error, doc)->
              #we don't care if it set or if it didn't set because:
              # 1. if there was a mongo error then the poller will pick it up and work on it later
              # 2. if it did set then fantastic, we will exit because we don't want to set to processed
              # 3. if it did not set (no error, and no document updated) then we want to exit because
              #    it is already in an error or processed state. In that case we want to do nothing
              setProcessed = false
              callback(null, null)
      else
        callback({name:"NullError", message: "Unsupported Entity Type: #{transaction.entity.type}"})
      return

    setProcessed: (callback)->
      if setProcessed is false
        callback() #we are not suppose to set to processed so exit cleanly
        return

      $set = {
        "funds.allocated": transaction.data.newAllocated
        "funds.remaining": document.funds.remaining + transaction.data.amount
        "funds.perResponse": transaction.data.perResponse
      }

      $update = {
        $set: $set
      }

      _setTransactionProcessed api.Polls, document, transaction, true, true, $update, callback
      #if it went through great, if it didn't go through then the poller will take care of it
      #, no other state changes need to occur

      #Write to the event stream
      api.Streams.pollUpdated(document) #we don't care about the callback
  },
  (error, results)->
    if error?
      logger.error "#{prepend} the poller will try later"


pollDeleted = (document, transaction)->
  prepend = "ID: #{document._id} - TID: #{transaction.id}"
  logger.info "Creating transaction for a poll that was deleted"
  logger.info "#{prepend} - #{transaction.direction}"

  setProcessed = true #setProcessed, unless something sets this to false
  async.series {
    setTransactionProcessing: (callback)->
      _setTransactionProcessing(api.Polls, document, transaction, true, callback)
      return

    depositFunds: (callback)->
      #we set this here, we want to use remaing not allocated, just in case money has been spent
      transaction.entity.type = document.entity.type
      transaction.entity.id = document.entity.id
      transaction.data.amount = document.funds.remaining

      logger.debug transaction

      logger.debug "#{prepend} going to try and deposit funds: #{transaction.entity.id}"
      if transaction.entity.type is choices.entities.BUSINESS
        logger.debug "#{prepend} attempting to deposit funds to business: #{transaction.entity.id}"
        _depositFunds api.Businesses, api.Polls, document, transaction, true, true, (error, doc)->
          if error? #mongo errored out
            callback(error)
          else if doc?  #transaction was successful, so continue to set processed
            callback(null, doc)
          else #null, null passed in which meas insufficient funds, so set error, and exit
            error = {message: "unable to deposit funds back"}
            _setTransactionError api.Polls, document, transaction, true, true, error, {}, (error, doc)->
              #we don't care if it set or if it didn't set because:
              # 1. if there was a mongo error then the poller will pick it up and work on it later
              # 2. if it did set then fantastic, we will exit because we don't want to set to processed
              # 3. if it did not set (no error, and no document updated) then we want to exit because
              #    it is already in an error or processed state. In that case we want to do nothing
              setProcessed = false
              callback(null, null)
      else if transaction.entity.type is choices.entities.CONSUMER
        logger.debug "#{prepend} attempting to deposit funds to consumer: #{transaction.entity.id}"
        _depositFunds api.Consumers, api.Polls, document, transaction, true, true, (error, doc)->
          if error? #mongo errored out
            callback(error)
          else if doc?  #transaction was successful, so continue to set processed
            callback(null, doc)
          else #null, null passed in which meas insufficient funds, so set error, and exit
            error = {message: "unabled to deposit funds back"}
            _setTransactionError api.Polls, document, transaction, true, true, error, {}, (error, doc)->
              #we don't care if it set or if it didn't set because:
              # 1. if there was a mongo error then the poller will pick it up and work on it later
              # 2. if it did set then fantastic, we will exit because we don't want to set to processed
              # 3. if it did not set (no error, and no document updated) then we want to exit because
              #    it is already in an error or processed state. In that case we want to do nothing
              setProcessed = false
              callback(null, null)
      else
        callback({name:"NullError", message: "Unsupported Entity Type: #{transaction.entity.type}"})
      return

    setProcessed: (callback)->
      if setProcessed is false
        callback(null, null) #we are not suppose to set to processed so exit cleanly
        return
      #Create Poll Deleted Event Transaction

      $update = {}

      _setTransactionProcessed(api.Polls, document, transaction, true, true, $update, callback)
      #if it went through great, if it didn't go through then the poller will take care of it
      #, no other state changes need to occur

      #Write to the event stream
      api.Streams.pollDeleted(document) #we don't care about the callback
  },
  (error, results)->
    if error?
      logger.error "#{prepend} the poller will try later"


#OUTBOUND
pollAnswered = (document, transaction)->
  prepend = "ID: #{document._id} - TID: #{transaction.id}"
  logger.info "Creating transaction for answered poll question"
  logger.info "#{prepend} - #{transaction.direction}"

  setProcessed = true #setProcessed, unless something sets this to false
  async.series {
    setProcessing: (callback)->
      _setTransactionProcessing api.Polls, document, transaction, false, (error, doc)->
        document = doc #we do this because the entities object is missing when the poll is answered
        callback error, doc
      return
    depositFunds: (callback)->
      if transaction.entity.type is choices.entities.CONSUMER
        logger.debug "#{prepend} attempting to deposit funds to consumer: #{transaction.entity.id}"
        _depositFunds api.Consumers, api.Polls, document, transaction, false, false, (error, doc)->
          if error? #mongo errored out
            callback(error)
          else if doc?  #transaction was successful, so continue to set processed
            callback(null, doc)
          else #null, null passed in which meas insufficient funds, so set error, and exit
            error = {message: "there were insufficient funds"}
            _setTransactionError api.Polls, document, transaction, false, false, error, {}, (error, doc)->
              #we don't care if it set or if it didn't set because:
              # 1. if there was a mongo error then the poller will pick it up and work on it later
              # 2. if it did set then fantastic, we will exit because we don't want to set to processed
              # 3. if it did not set (no error, and no document updated) then we want to exit because
              #    it is already in an error or processed state. In that case we want to do nothing
              setProcessed = false
              callback(null, null)
      else
        callback({name:"NullError", message: "Unsupported Entity Type: #{transaction.entity.type}"})
      return

    setProcessed: (callback)->
      if setProcessed is false
        callback() #we are not suppose to set to processed so exit cleanly
        return

      #Create Poll Created Statistic Transaction
      statTransaction = api.Polls.createTransaction(
        choices.transactions.states.PENDING
        , choices.transactions.actions.STAT_POLL_ANSWERED
        , {timestamp: transaction.data.timestamp}
        , choices.transactions.directions.OUTBOUND
        , transaction.entity
      )

      $pushAll = {
        "transactions.ids": [statTransaction.id]
        "transactions.temp": [statTransaction]
      }

      $update = {
        $pushAll: $pushAll
      }

      _setTransactionProcessedAndCreateNew api.Polls, document, transaction, [statTransaction], false, false, $update, callback
      #if it went through great, if it didn't go through then the poller will take care of it
      #, no other state changes need to occur

      #Write to the event stream
      api.Streams.pollAnswered(transaction.entity, transaction.data.timestamp, document) #we don't care about the callback
  },
  (error, results)->
    if error?
      logger.error "#{prepend} the poller will try later"

#INBOUND
discussionCreated = (document, transaction)->
  prepend = "ID: #{document._id} - TID: #{transaction.id}"
  logger.info "Creating transaction for discussion that was created"
  logger.info "ID: #{document._id} - TID: #{transaction.id} - #{transaction.direction}"

  setProcessed = true #setProcessed, unless something sets this to false
  async.series {
    setTransactionProcessing: (callback)->
      _setTransactionProcessing(api.Discussions, document, transaction, true, callback)
      return

    deductFunds: (callback)->
      if transaction.entity.type is choices.entities.BUSINESS
        _deductFunds api.Businesses, api.Discussions, document, transaction, true, true, (error, doc)->
          if error? #mongo errored out
            callback(error)
          else if doc?  #transaction was successful, so continue to set processed
            callback(null, doc)
          else #null, null passed in which meas insufficient funds, so set error, and exit
            error = {message: "there were insufficient funds"}
            _setTransactionError api.Discussions, document, transaction, true, true, error, {}, (error, doc)->
              #we don't care if it set or if it didn't set because:
              # 1. if there was a mongo error then the poller will pick it up and work on it later
              # 2. if it did set then fantastic, we will exit because we don't want to set to processed
              # 3. if it did not set (no error, and no document updated) then we want to exit because
              #    it is already in an error or processed state. In that case we want to do nothing
              setProcessed = false
              callback(null, null)

      else if transaction.entity.type is choices.entities.CONSUMER
        _deductFunds api.Consumers, api.Discussions, document, transaction, true, true, (error, doc)->
          if error? #mongo errored out
            callback(error)
          else if doc?  #transaction was successful, so continue to set processed
            callback(null, doc)
          else #null, null passed in which meas insufficient funds, so set error, and exit
            error = {message: "there were insufficient funds"}
            _setTransactionError api.Discussions, document, transaction, true, true, error, {}, (error, doc)->
              #we don't care if it set or if it didn't set because:
              # 1. if there was a mongo error then the poller will pick it up and work on it later
              # 2. if it did set then fantastic, we will exit because we don't want to set to processed
              # 3. if it did not set (no error, and no document updated) then we want to exit because
              #    it is already in an error or processed state. In that case we want to do nothing
              setProcessed = false
              callback(null, null)

      else
        callback({name:"NullError", message: "Unsupported Entity Type: #{transaction.entity.type}"})
      return

    setProcessed: (callback)->
      if setProcessed is false
        callback(null, null) #we are not suppose to set to processed so exit cleanly
        return

      $set = {
        "funds.allocated": transaction.data.amount
        "funds.remaining": transaction.data.amount
      }

      $update = {
        $set: $set
      }

      _setTransactionProcessed(api.Discussions, document, transaction, true, true, $update, callback)
      #if it went through great, if it didn't go through then the poller will take care of it
      #, no other state changes need to occur

      #Write to the event stream
      api.Streams.discussionCreated(document) #we don't care about the callback
  },
  (error, results)->
    if error?
      logger.error "#{prepend} the poller will try later"


#INBOUND
discussionUpdated = (document, transaction)->
  prepend = "ID: #{document._id} - TID: #{transaction.id}"
  logger.info "Creating transaction for a discussion that was updated"
  logger.info "#{prepend} - #{transaction.direction}"

  setProcessed = true #setProcessed, unless something sets this to false
  async.series {
    setProcessing: (callback)->
      _setTransactionProcessing api.Discussions, document, transaction, true, callback
      return

    adjustFunds: (callback)->
      #adjust balance before sending it to get adjusted
      transaction.data.amount = transaction.data.newAllocated - document.funds.allocated

      if transaction.entity.type is choices.entities.BUSINESS
        _deductFunds api.Businesses, api.Discussions, document, transaction, true, true, (error, doc)->
          if error? #mongo errored out
            callback(error)
          else if doc?  #transaction was successful, so continue to set processed
            callback(null, doc)
          else #null, null passed in which meas insufficient funds, so set error, and exit
            error = {message: "there were insufficient funds"}
            _setTransactionError api.Discussions, document, transaction, true, true, error, {}, (error, doc)->
              #we don't care if it set or if it didn't set because:
              # 1. if there was a mongo error then the poller will pick it up and work on it later
              # 2. if it did set then fantastic, we will exit because we don't want to set to processed
              # 3. if it did not set (no error, and no document updated) then we want to exit because
              #    it is already in an error or processed state. In that case we want to do nothing
              setProcessed = false
              callback(null, null)
      else if transaction.entity.type is choices.entities.CONSUMER
        _deductFunds api.Consumers, api.Discussions, document, transaction, true, true, (error, doc)->
          if error? #mongo errored out
            callback(error)
          else if doc?  #transaction was successful, so continue to set processed
            callback(null, doc)
          else #null, null passed in which meas insufficient funds, so set error, and exit
            error = {message: "there were insufficient funds"}
            _setTransactionError api.Discussions, document, transaction, true, true, error, {}, (error, doc)->
              #we don't care if it set or if it didn't set because:
              # 1. if there was a mongo error then the poller will pick it up and work on it later
              # 2. if it did set then fantastic, we will exit because we don't want to set to processed
              # 3. if it did not set (no error, and no document updated) then we want to exit because
              #    it is already in an error or processed state. In that case we want to do nothing
              setProcessed = false
              callback(null, null)
      else
        callback({name:"NullError", message: "Unsupported Entity Type: #{transaction.entity.type}"})
      return

    setProcessed: (callback)->
      if setProcessed is false
        callback() #we are not suppose to set to processed so exit cleanly
        return

      $set = {
        "funds.allocated": transaction.data.newAllocated
        "funds.remaining": document.funds.remaining + transaction.data.amount
        "funds.perResponse": transaction.data.perResponse
      }

      $update = {
        $set: $set
      }

      _setTransactionProcessed api.Discussions, document, transaction, true, true, $update, callback
      #if it went through great, if it didn't go through then the poller will take care of it
      #, no other state changes need to occur

      #Write to the event stream
      api.Streams.discussionUpdated(document) #we don't care about the callback
  },
  (error, results)->
    if error?
      logger.error "#{prepend} the poller will try later"


discussionDeleted = (document, transaction)->
  prepend = "ID: #{document._id} - TID: #{transaction.id}"
  logger.info "Creating transaction for a discussion that was deleted"
  logger.info "#{prepend} - #{transaction.direction}"

  setProcessed = true #setProcessed, unless something sets this to false
  async.series {
    setTransactionProcessing: (callback)->
      _setTransactionProcessing(api.Discussions, document, transaction, true, callback)
      return

    depositFunds: (callback)->
      #we set this here, we want to use remaing not allocated, just in case money has been spent
      transaction.entity.type = document.entity.type
      transaction.entity.id = document.entity.id
      transaction.data.amount = document.funds.remaining

      logger.debug transaction

      logger.debug "#{prepend} going to try and deposit funds: #{transaction.entity.id}"
      if transaction.entity.type is choices.entities.BUSINESS
        logger.debug "#{prepend} attempting to deposit funds to business: #{transaction.entity.id}"
        _depositFunds api.Businesses, api.Discussions, document, transaction, true, true, (error, doc)->
          if error? #mongo errored out
            callback(error)
          else if doc?  #transaction was successful, so continue to set processed
            callback(null, doc)
          else #null, null passed in which meas insufficient funds, so set error, and exit
            error = {message: "unable to deposit funds back"}
            _setTransactionError api.Discussions, document, transaction, true, true, error, {}, (error, doc)->
              #we don't care if it set or if it didn't set because:
              # 1. if there was a mongo error then the poller will pick it up and work on it later
              # 2. if it did set then fantastic, we will exit because we don't want to set to processed
              # 3. if it did not set (no error, and no document updated) then we want to exit because
              #    it is already in an error or processed state. In that case we want to do nothing
              setProcessed = false
              callback(null, null)
      else if transaction.entity.type is choices.entities.CONSUMER
        logger.debug "#{prepend} attempting to deposit funds to consumer: #{transaction.entity.id}"
        _depositFunds api.Consumers, api.Discussions, document, transaction, true, true, (error, doc)->
          if error? #mongo errored out
            callback(error)
          else if doc?  #transaction was successful, so continue to set processed
            callback(null, doc)
          else #null, null passed in which meas insufficient funds, so set error, and exit
            error = {message: "unabled to deposit funds back"}
            _setTransactionError api.Discussions, document, transaction, true, true, error, {}, (error, doc)->
              #we don't care if it set or if it didn't set because:
              # 1. if there was a mongo error then the poller will pick it up and work on it later
              # 2. if it did set then fantastic, we will exit because we don't want to set to processed
              # 3. if it did not set (no error, and no document updated) then we want to exit because
              #    it is already in an error or processed state. In that case we want to do nothing
              setProcessed = false
              callback(null, null)
      else
        callback({name:"NullError", message: "Unsupported Entity Type: #{transaction.entity.type}"})
      return

    setProcessed: (callback)->
      if setProcessed is false
        callback(null, null) #we are not suppose to set to processed so exit cleanly
        return
      #Create Poll Deleted Event Transaction

      $update = {}

      _setTransactionProcessed(api.Discussions, document, transaction, true, true, $update, callback)
      #if it went through great, if it didn't go through then the poller will take care of it
      #, no other state changes need to occur

      #Write to the event stream
      api.Streams.discussionDeleted(document) #we don't care about the callback
  },
  (error, results)->
    if error?
      logger.error "#{prepend} the poller will try later"

#OUTBOUND
discussionAnswered = (document, transaction)->
  prepend = "ID: #{document._id} - TID: #{transaction.id}"
  logger.info "Creating transaction for answered discussion question"
  logger.info "#{prepend} - #{transaction.direction}"

  setProcessed = true #setProcessed, unless something sets this to false
  async.series {
    setProcessing: (callback)->
      _setTransactionProcessing api.Discussions, document, transaction, false, (error, doc)->
        document = doc #we do this because the entities object is missing when the discussion is answered
        callback error, doc
      return
    depositFunds: (callback)->
      if transaction.entity.type is choices.entities.CONSUMER
        logger.debug "#{prepend} attempting to deposit funds to consumer: #{transaction.entity.id}"
        _depositFunds api.Consumers, api.Discussions, document, transaction, false, false, (error, doc)->
          if error? #mongo errored out
            callback(error)
          else if doc?  #transaction was successful, so continue to set processed
            callback(null, doc)
          else #null, null passed in which meas insufficient funds, so set error, and exit
            error = {message: "there were insufficient funds"}
            _setTransactionError api.Discussions, document, transaction, false, false, error, {}, (error, doc)->
              #we don't care if it set or if it didn't set because:
              # 1. if there was a mongo error then the poller will pick it up and work on it later
              # 2. if it did set then fantastic, we will exit because we don't want to set to processed
              # 3. if it did not set (no error, and no document updated) then we want to exit because
              #    it is already in an error or processed state. In that case we want to do nothing
              setProcessed = false
              callback(null, null)
      else
        callback({name:"NullError", message: "Unsupported Entity Type: #{transaction.entity.type}"})
      return

    setProcessed: (callback)->
      if setProcessed is false
        callback() #we are not suppose to set to processed so exit cleanly
        return

      #Create Discussion Created Statistic Transaction
      statTransaction = api.Discussions.createTransaction(
        choices.transactions.states.PENDING
        , choices.transactions.actions.STAT_DISCUSSION_ANSWERED
        , {timestamp: transaction.data.timestamp}
        , choices.transactions.directions.OUTBOUND
        , transaction.entity
      )

      $pushAll = {
        "transactions.ids": [statTransaction.id]
        "transactions.temp": [statTransaction]
      }

      $update = {
        $pushAll: $pushAll
      }

      _setTransactionProcessedAndCreateNew api.Discussions, document, transaction, [statTransaction], false, false, $update, callback
      #if it went through great, if it didn't go through then the poller will take care of it
      #, no other state changes need to occur

      #Write to the event stream
      api.Streams.discussionAnswered(transaction.entity, transaction.data.timestamp, document) #we don't care about the callback
  },
  (error, results)->
    if error?
      logger.error "#{prepend} the poller will try later"


#OUTBOUND
statPollAnswered = (document, transaction)->
  prepend = "ID: #{document._id} - TID: #{transaction.id}"
  logger.info "STAT - User answered poll question"
  logger.info "#{prepend} - #{transaction.direction}"
  # logger.debug document
  async.series {
    setProcessing: (callback)->
      _setTransactionProcessing api.Polls, document, transaction, false, (error, doc)->
        #We need to replace the passed in document with this new one because
        #the document passed in doesn't have the entity object (we had removed it)
        document = doc
        callback(error, doc)
      return

    updateStats: (callback)->
      # logger.debug document
      org = {type: document.entity.type, id: document.entity.id}
      consumerId = transaction.entity.id
      transactionId = transaction.id
      api.Statistics.pollAnswered org, consumerId, transactionId, transaction.data.timestamp, (error, count)->
        if error? #mongo errored out
          callback(error)
        else if count>0
          callback(null, count)
        else #transaction already occurred - we did an upsert to create the relationship if it doesn't exist
          callback(null, null)

    setProcessed: (callback)->
      _setTransactionProcessed api.Polls, document, transaction, false, false, {}, callback
      return
      #if it went through great, if it didn't go through then the poller will take care of it,
      #no other state changes need to occur

  },
  (error, results)->
    if error?
      logger.error "#{prepend} the poller will try later"


exports.process = process
