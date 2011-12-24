async = require "async"

globals = require "globals"
loggers = require "./loggers"
api = require "./api"

logger = loggers.transaction
choices = globals.choices

process = (document, transaction)-> #this is just a router
  switch transaction.action

    #FINANCIAL
    when choices.transactions.actions.POLL_CREATED
      pollCreated(document, transaction)
    when choices.transactions.actions.POLL_UPDATED
      pollUpdated(document, transaction)
    when choices.transactions.actions.POLL_ANSWERED
      pollAnswered(document, transaction)
    when choices.transactions.actions.DISCUSSION_CREATED
      discussionCreated(document, transaction)

    #EVENTS
    when choices.transactions.actions.EVENT_POLL_CREATED
      eventPollCreated(document, transaction)
    when choices.transactions.actions.EVENT_POLL_ANSWERED
      eventPollAnswered(document, transaction)
    when choices.transactions.actions.EVENT_POLL_UPDATED
      eventPollUpdated(document, transaction)
    when choices.transactions.actions.EVENT_EVENT_RSVPED
      eventEventRsvped(document, transaction)
    when choices.transactions.actions.EVENT_DISCUSSION_CREATED
      eventDiscussionCreated(document, transaction)
    when choices.transactions.actions.DISCUSSION_CREATE
      discussionCreate(document, transaction)

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

_setTransactionProcessedAndCreateNew = (clazz, document, transaction, newTransaction, locking, removeLock, modifierDoc, callback)->
  prepend = "ID: #{document._id} - TID: #{transaction.id}"
  logger.info "#{locking} AND #{removeLock}"
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
      clazz.moveTransactionToLog document._id, newTransaction, (error, doc2)->
        if error?
          logger.error "#{prepend} moving event transaction from temporary to log failed"
        else if !doc2?
          logger.warn "#{prepend} the new transaction is already in progress - pollers will move it if it is still in temp"
        else
          logger.info "#{prepend} created event transaction: #{newTransaction.id}"
          process(document, newTransaction)
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
      logger.error "#{prepend} deducting funds from #{transaction.entity.type}: #{transaction.entity.id} failed"
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
      logger.error "#{prepend} depositing funds into #{transaction.entity.type}: #{transaction.entity.id} failed"
      callback(error) #determine what type of error it is and then whether to setTransactionError or ignore and let the poller pick it up later (the later is probably the case)
    else if !doc? #if the consumer object doesn't exist then either the transaction occured previously, there aren't enough funds, or the entity doesn't exist
      logger.info "#{prepend} transaction may have occured, VERIFYING"
      classTo.checkIfTransactionExists transaction.entity.id, transaction.id, (error, doc2)->
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

# _writeToStream = (document, transaction, eventType, message, data, callback)->
#   #@add = (entity, eventType, eventId, documentId, timestamp, data, callback)
#   api.Streams.add transaction.entity, eventType, transaction.id, document._id, transaction.dates.created, message, data, (error, stream)->
#     if error?
#       logger.error "#{prepend} writing to stream failed"
#       #check if it exists - it will return an error if there is a unique index contraint set (one per transaction?)
#       callback error
#     else if !stream?
#       _checkIfTransactionExists api.Streams, transaction.entity.id, transaction.id, (error, trans)->

#         if error?
#           callback(error)
#           return
#         else if stream2?
#           #it exists, so we're good
#           logger.info "#{prepend} action already in stream"
#           callback(null, stream2)
#           return
#         else
#           logger.info
#           callback {name: "NullError", message: "Could Not Write To "}, null
#           return
#       logger.warn "#{prepend} action may have already been written to the stream"
#     else
#       callback null, stream


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
      #Create Poll Created Event Transaction
      eventTransaction = api.Polls.createTransaction(
        choices.transactions.states.PENDING
        , choices.transactions.actions.EVENT_POLL_CREATED
        , {}
        , choices.transactions.directions.OUTBOUND
        , transaction.entity
      )
      
      $set = {
        "funds.allocated": transaction.data.amount
        "funds.remaining": transaction.data.amount
      }

      $push = {
        "transactions.ids": eventTransaction.id
        "transactions.temp": eventTransaction
      }

      $update = {
        $set: $set
        $push: $push
      }
      
      _setTransactionProcessedAndCreateNew(api.Polls, document, transaction, eventTransaction, true, true, $update, callback)
      #if it went through great, if it didn't go through then the poller will take care of it
      #, no other state changes need to occur
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
      transaction.data.amount = transaction.data.amount - document.funds.allocated
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

      #Create Poll Created Event Transaction
      eventTransaction = api.Polls.createTransaction(
        choices.transactions.states.PENDING
        , choices.transactions.actions.EVENT_POLL_UPDATED
        , {}
        , choices.transactions.directions.OUTBOUND
        , transaction.entity
      )

      $push = {
        "transactions.ids": eventTransaction.id
        "transactions.temp": eventTransaction
      }

      $update = {
        $push: $push
      }
      
      _setTransactionProcessedAndCreateNew api.Polls, document, transaction, eventTransaction, true, true, $update, callback
      #if it went through great, if it didn't go through then the poller will take care of it
      #, no other state changes need to occur
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
      _setTransactionProcessing api.Polls, document, transaction, false, callback
      return


    depositFunds: (callback)->
      if transaction.entity.type is choices.entities.BUSINESS
        _depositFunds api.Businesses, api.Polls, document, transaction, false, false, (error, doc)->
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
      else if transaction.entity.type is choices.entities.CONSUMER
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

      #Create Poll Created Event Transaction
      eventTransaction = api.Polls.createTransaction(
        choices.transactions.states.PENDING
        , choices.transactions.actions.EVENT_POLL_ANSWERED
        , {}
        , choices.transactions.directions.OUTBOUND
        , transaction.entity
      )

      $push = {
        "transactions.ids": eventTransaction.id
        "transactions.temp": eventTransaction
      }

      $update = {
        $push: $push
      }
      
      _setTransactionProcessedAndCreateNew api.Polls, document, transaction, eventTransaction, false, false, $update, callback
      #if it went through great, if it didn't go through then the poller will take care of it
      #, no other state changes need to occur
  },
  (error, results)->
    if error?
      logger.error "#{prepend} the poller will try later"

#INBOUND
discussionCreated = (document, transaction)->
  prepend = "ID: #{document._id} - TID: #{transaction.id}"
  logger.info "Creating transaction for discussion"
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
      #Create Poll Created Event Transaction
      eventTransaction = api.Discussions.createTransaction(
        choices.transactions.states.PENDING
        , choices.transactions.actions.EVENT_DISCUSSION_CREATED
        , {}
        , choices.transactions.directions.OUTBOUND
        , transaction.entity
      )
      
      $set = {
        "funds.allocated": transaction.data.amount
        "funds.remaining": transaction.data.amount
      }

      $push = {
        "transactions.ids": eventTransaction.id
        "transactions.temp": eventTransaction
      }

      $update = {
        $set: $set
        $push: $push
      }
      
      _setTransactionProcessedAndCreateNew(api.Discussions, document, transaction, eventTransaction, true, true, $update, callback)
      #if it went through great, if it didn't go through then the poller will take care of it
      #, no other state changes need to occur
  }, 
  (error, results)->
    if error?
      logger.error "#{prepend} the poller will try later"

eventPollCreated = (document, transaction)->
  prepend = "ID: #{document._id} - TID: #{transaction.id}"
  logger.info "EVENT - User created poll question"
  logger.log "#{prepend}- #{transaction.direction}"

  _setTransactionProcessing api.Polls, document, transaction, false, (error)->
    if error?
      return
    else
      completed = true
      async.parallel {
        stream: (callback)->
          message = "created a poll - {#{document.question}}"
          # ADD TO CONSUMER ACTIVITY STREAM
          #_writeToStream document, transaction, choices.eventTypes.POLL_CREATED, "created a poll - {#{document.question}}", {}, callback
          
          # THIS IS NON-TRANSACTIONAL AT THE MOMENT
          api.Streams.add transaction.entity, choices.eventTypes.POLL_CREATED, transaction.id, document._id, transaction.dates.created, message, {}, (error, stream)->
            if stream?
              logger.info "#{prepend} wrote action to stream"
            callback()
            return

      }, 
      (error, results)->
        if error?
          completed = false
          logger.error "#{prepend} the poller will try later"
        if results?
          if completed
            logger.info "#{prepend} all processing operations completed"
            _setTransactionProcessed api.Polls, document, transaction, false, false, {}, (error)->
              return
          else #NOT COMPLETED
            if transaction.attempts > 5 #if we fail more than 5 times then there is something wrong so error out
              _setTransactionError api.Polls, document, transaction, false, false, {}, (error)->
                return
      return

eventPollUpdated = (document, transaction)->
  prepend = "ID: #{document._id} - TID: #{transaction.id}"
  logger.info "EVENT - User updated poll question"
  logger.log "#{prepend}- #{transaction.direction}"

  _setTransactionProcessing api.Polls, document, transaction, false, (error)->
    if error?
      return
    else
      completed = true
      async.parallel {
        stream: (callback)->
          message = "updated a poll - {#{document.question}}"
          # ADD TO CONSUMER ACTIVITY STREAM
          #_writeToStream document, transaction, choices.eventTypes.POLL_CREATED, "created a poll - {#{document.question}}", {}, callback
          
          # THIS IS NON-TRANSACTIONAL AT THE MOMENT
          api.Streams.add transaction.entity, choices.eventTypes.POLL_UPDATED, transaction.id, document._id, transaction.dates.created, message, {}, (error, stream)->
            if stream?
              logger.info "#{prepend} wrote action to stream"
            callback()
            return

      }, 
      (error, results)->
        if error?
          completed = false
          logger.error "#{prepend} the poller will try later"
        if results?
          if completed
            logger.info "#{prepend} all processing operations completed"
            _setTransactionProcessed api.Polls, document, transaction, false, false, {}, (error)->
              return
          else #NOT COMPLETED
            if transaction.attempts > 5 #if we fail more than 5 times then there is something wrong so error out
              _setTransactionError api.Polls, document, transaction, false, false, {}, (error)->
                return
      return

eventPollAnswered = (document, transaction)->
  prepend = "ID: #{document._id} - TID: #{transaction.id}"
  logger.info "EVENT - User answered poll question"
  logger.log "#{prepend}- #{transaction.direction}"

  _setTransactionProcessing api.Polls, document, transaction, false, (error)->
    if error?
      return
    else
      completed = true
      async.parallel {
        stream: (callback)->
          message = "answered a poll - {#{document.question}}"
          # ADD TO CONSUMER ACTIVITY STREAM
          #_writeToStream document, transaction, choices.eventTypes.POLL_ANSWERED, "answered a poll - {#{poll.question}}", {}, callback

          # THIS IS NON-TRANSACTIONAL AT THE MOMENT
          api.Streams.add transaction.entity, choices.eventTypes.POLL_ANSWERED, transaction.id, document._id, transaction.dates.created, message, {}, (error, stream)->
            if stream?
              logger.info "#{prepend} wrote action to stream"
            callback()
            return

      }, 
      (error, results)->
        if error?
          completed = false
          logger.error "#{prepend} the poller will try later"
        if results?
          if completed
            logger.info "#{prepend} all processing operations completed"
            _setTransactionProcessed api.Polls, document, transaction, false, false, {}, (error)->
              return
          else #NOT COMPLETED
            if transaction.attempts > 5 #if we fail more than 5 times then there is something wrong so error out
              _setTransactionError api.Polls, document, transaction, false, false, {}, (error)->
                return
      return

eventDiscussionCreated = (document, transaction)->
  prepend = "ID: #{document._id} - TID: #{transaction.id}"
  logger.info "EVENT - User created discussion question"
  logger.log "#{prepend}- #{transaction.direction}"

  _setTransactionProcessing api.Discussions, document, transaction, false, (error)->
    if error?
      return
    else
      completed = true
      async.parallel {
        stream: (callback)->
          message = "created a discussion - {#{document.question}}"
          # ADD TO CONSUMER ACTIVITY STREAM
          #_writeToStream document, transaction, choices.eventTypes.DISCUSSION_CREATED, "created a discussion - {#{document.question}}", {}, callback

          # THIS IS NON-TRANSACTIONAL AT THE MOMENT
          api.Streams.add transaction.entity, choices.eventTypes.DISCUSSION_CREATED, transaction.id, document._id, transaction.dates.created, message, {}, (error, stream)->
            if stream?
              logger.info "#{prepend} wrote action to stream"
            callback()
            return

      }, 
      (error, results)->
        if error?
          completed = false
          logger.error "#{prepend} the poller will try later"
        if results?
          if completed
            logger.info "#{prepend} all processing operations completed"
            _setTransactionProcessed api.Discussions, document, transaction, false, false, {}, (error)->
              return
          else #NOT COMPLETED
            if transaction.attempts > 5 #if we fail more than 5 times then there is something wrong so error out
              _setTransactionError api.Discussions, document, transaction, false, false, {}, (error)->
                return
      return

eventEventRsvped = (document, transaction)->
  prepend = "ID: #{document._id} - TID: #{transaction.id}"
  logger.info "EVENT - User rsvped to an event"
  logger.log "#{prepend}- #{transaction.direction}"

  _setTransactionProcessing api.Events, document, transaction, false, (error)->
    if error?
      return
    else
      completed = true
      async.parallel {
        stream: (callback)->
          message = "RSVPed to attend an {event} at #{document.location.name}"
          # ADD TO CONSUMER ACTIVITY STREAM
          # _writeToStream document, transaction, choices.eventTypes.EVENT_RSVPED, "RSVPed to attend an {event} at #{document.location.name}", {}, callback

          # THIS IS NON-TRANSACTIONAL AT THE MOMENT
          api.Streams.add transaction.entity, choices.eventTypes.EVENT_RSVPED, transaction.id, document._id, transaction.dates.created, message, {}, (error, stream)->
            if stream?
              logger.info "#{prepend} wrote action to stream"
            callback()
            return

      }, 
      (error, results)->
        if error?
          completed = false
          logger.error "#{prepend} the poller will try later"
        if results?
          if completed
            logger.info "#{prepend} all processing operations completed"
            _setTransactionProcessed api.Events, document, transaction, false, false, {}, (error)->
              return
          else #NOT COMPLETED
            if transaction.attempts > 5 #if we fail more than 5 times then there is something wrong so error out
              _setTransactionError api.Events, document, transaction, false, false, {}, (error)->
                return
      return

    

exports.process = process
