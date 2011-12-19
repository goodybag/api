async = require "async"

globals = require "globals"
api = require "./api"

choices = globals.choices

process = (document, transaction)-> #this is just a router
  switch transaction.action

    #FINANCIAL
    when choices.transactions.actions.POLL_CREATE
      pollCreate(document, transaction)
    when choices.transactions.actions.POLL_ANSWER
      pollAnswer(document, transaction)

    #EVENTS
    when choices.transactions.actions.EVENT_POLL_CREATED
      eventPollCreated(document, transaction)
    when choices.transactions.actions.EVENT_POLL_ANSWERED
      eventPollAnswered(document, transaction)
    when choices.transactions.actions.EVENT_EVENT_RSVPED
      eventEventRsvp(document, transaction)

#INBOUND
pollCreate = (document, transaction)->
  console.log "\nCreate Poll Question".green
  console.log "\nPID: #{document._id}\nTID: #{transaction.id}\n#{transaction.direction}\n".green

  async.series {
    setProcessing: (callback)->
      #console.log document
      console.log "SET PROCESSING".green
      api.Polls.setTransactionProcessing document._id, transaction.id, true, (error, poll)->
        if error? #determine what type of error it is and then whether to setTransactionError or ignore and let the poller pick it up later (the later is probably the case)
          callback(error)
        else if !poll? #if poll doesn't exist
          callback({name: "NullError", message: "Document Does Not Exist"})
        else
          callback()
        return
        
    deductFunds: (callback)->
      console.log "DEDUCT FUNDS".green
      if transaction.entity.type is choices.entities.BUSINESS
        api.Businesses.deductFunds transaction.entity.id, transaction.id, transaction.data.amount, (error, business)->
          #console.log "BID: #{business._id}".green
          if error? #determine what type of error it is and then whether to setTransactionError or ignore and let the poller pick it up later (the later is probably the case)
            callback(error)
          else if !business? #if the business object doesn't exist then either the transaction occured previously, there aren't enough funds, or the business doesn't exist
            api.Businesses.checkIfTransactionExists transaction.entity.id, transaction.id, (error, business)->
              if error?
                callback(error)
              else if business? #transaction already occured
                console.log "TRANSACTION ALREADY COMPLETED"
                callback()
              else #either not enough funds or business does not exist - in either case report insufficient funds
                error = {
                  message: "there were insufficient funds"
                }
                console.log "SET ERROR".green
                api.Polls.setTransactionError document._id, transaction.id, true, true, error, {}, (error, poll)->
                  if error?
                    callback(error)
                  else if !poll?
                    console.log "PROBLEM SETTING ERROR".red
                    callback({name: "TransactionError", messge: "Unable to set transaction state to error in polls"})
                  else
                    callback({name: "TransactionError", messge: "There were insufficient funds"})
          else #transaction went through
            callback()
          return

      else if transaction.entity.type is choices.entities.CONSUMER
        api.Consumers.deductFunds transaction.entity.id, transaction.id, transaction.data.amount, (error, consumer)->
          #console.log "CID: #{consumer._id}".green
          if error? #determine what type of error it is and then whether to setTransactionError or ignore and let the poller pick it up later (the later is probably the case)
            callback(error)
          else if !consumer? #if the consumer object doesn't exist then either the transaction occured previously, or the consumer doesn't exist
            api.Consumers.checkIfTransactionExists transaction.entity.id, transaction.id, (error, consumer)->
              if error?
                callback(error)
              else if consumer? #transaction already occured
                console.log "TRANSACTION ALREADY COMPLETED"
                callback()
              else #either not enough funds or the consumer doesn't exist - in either case report insufficient funds
                error = {
                  message: "there were insufficient funds"
                }
                console.log "SET ERROR".green
                api.Polls.setTransactionError document._id, transaction.id, true, true, error, {}, (error, poll)->
                  if error?
                    callback(error)
                  else if !poll?
                    console.log "PROBLEM SETTING ERROR".red
                    callback({name: "TransactionError", messge: "Unable to set transaction state to error in poll"})
                  else
                    callback({name: "TransactionError", messge: "There were insufficient funds"})
          else
            callback()

    setProcessed: (callback)->
      console.log "SET PROCESSED".green
      
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
      
      api.Polls.setTransactionProcessed document._id, transaction.id, true, true, $update, (error, poll)->
        if error?
          console.log "ERROR SETTING PROCESSED".red
          callback(error)
        else if !poll?
          console.log "THE DOCUMENT WITH THAT TRANSACTION ID WAS NOT FOUND - POSSIBLY HANDLED ALREADY, IF NOT POLLER WILL TAKE CARE OF IT LATER".yellow
          callback({name: "TransactionWarning", message:"Unable to set state to processed. Transaction may have already been processed, quitting further processing"})
        else
          console.log "TRANSACTION SUCCESSFUL".green
          callback()
          api.Polls.moveTransactionToLog document._id, eventTransaction, (error, poll)->
            if error?
              console.log "ERROR MOVING TRANSACTION FROM TEMP TO LOG - POLLER WILL HAVE TO PICK UP".red
            else if !poll?
              console.log "LOOKS LIKE IT MAY HAVE BEEN MOVED ALREADY OR PROCESSED".yellow
            else
              console.log "SUCCESSFULLY MOVED TRANSACTION FROM TEMP TO LOG".green
              process(document, eventTransaction)
        return
  }, 
  (error, results)->
    if error?
      console.log "POLLER WILL RETRY LATER".red
      console.log error
    #console.log results


#OUTBOUND
pollAnswer = (document, transaction)->
  console.log "\nUser Answered Poll Question".green
  console.log "\nPID: #{document._id}\nTID: #{transaction.id}\n#{transaction.direction}\n".green

  async.series {
    setProcessing: (callback)->
      console.log "SET PROCESSING".green
      api.Polls.setTransactionProcessing document._id, transaction.id, false, (error, poll)->
        if error? #determine what type of error it is and then whether to setTransactionError or ignore and let the poller pick it up later (the later is probably the case)
          callback(error)
        else if !poll? #if poll doesn't exist
          callback({name: "NullError", message: "Document Does Not Exist"})
        else
          callback()
        return
    
    depositFunds: (callback)->
      console.log "\nDEPOSIT FUNDS".green
      api.Consumers.depositFunds transaction.entity.id, transaction.id, transaction.data.amount, (error, consumer)->
        if error?
          callback(error) #determine what type of error it is and then whether to setTransactionError or ignore and let the poller pick it up later (the later is probably the case)
        else if !consumer? #if the consumer object doesn't exist then either the transaction occured previously, there aren't enough funds, or the consumer doesn't exist
          api.Consumers.checkIfTransactionExists transaction.entity.id, transaction.id, (error, consumer)->
            if error?
              callback(error)
            else if consumer? #transaction already occured
              callback()
            else #consumer doesn't exist
              error = {
                message: "unable to find the consumer"
              }
              $update = {
                $inc: {
                  "funds.remaining": transaction.data.amount
                }
              }
              console.log "SET ERROR".green
              api.Polls.setTransactionError document._id, transaction.id, false, false, $update, (error, poll)->
                if error?
                  callback(error)
                else if !poll?
                  console.log "PROBLEM SETTING ERROR".red
                  callback({name: "TransactionError", messge: "Unable to set transaction state to error in poll"})
                else
                  callback({name: "TransactionError", messge: "Unable to find consumer"})

        else
          callback()
        return
          
    setProcessed: (callback)->
      console.log "SET PROCESSED".green
      
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
      
      api.Polls.setTransactionProcessed document._id, transaction.id, false, false, $update, (error, poll)->
        if error?
          console.log "ERROR SETTING PROCESSED".red
          callback(error)
        else if !poll?
          console.log "THE DOCUMENT WITH THAT TRANSACTION ID WAS NOT FOUND - POSSIBLY HANDLED ALREADY, IF NOT POLLER WILL TAKE CARE OF IT LATER".yellow
          callback({name: "TransactionWarning", message:"Unable to set state to processed. Transaction may have already been processed, quitting further processing"})
        else
          console.log "TRANSACTION SUCCESSFUL"
          callback()
          api.Polls.moveTransactionToLog document._id, eventTransaction, (error, poll)->
            if error?
              console.log "ERROR MOVING TRANSACTION FROM TEMP TO LOG - POLLER WILL HAVE TO PICK UP".red
            else if !poll?
              console.log "LOOKS LIKE IT MAY HAVE BEEN MOVED ALREADY OR PROCESSED".yellow
            else
              console.log "SUCCESSFULLY MOVED TRANSACTION FROM TEMP TO LOG".green
              process(document, eventTransaction)
        return
  },
  (error, results)->
    if error?
      console.log "POLLER WILL RETRY LATER".red
      console.log error


eventPollCreated = (document, transaction)->
  console.log "\nEVENT - User CREATED Poll Question".green
  console.log "\nPID: #{document._id}\nTID: #{transaction.id}\n#{transaction.direction}\n".green

  console.log "SET PROCESSING".green
  api.Polls.setTransactionProcessing document._id, transaction.id, false, (error, poll)->
    if error? #determine what type of error it is and then whether to setTransactionError or ignore and let the poller pick it up later (the later is probably the case)
      console.log error
      return
    else if !poll? #if poll doesn't exist
      console.log {name: "NullError", message: "Could Not Find Poll"}
      return
    else
      console.log "PROCESSING SET"
      timestamp   = transaction.dates.created
      entity      = transaction.entity

      completed = true #successful
      async.parallel {
        stream: (callback)->
          # ADD TO CONSUMER ACTIVITY STREAM
          api.Streams.add entity, choices.eventTypes.POLL_CREATED, transaction.id, document._id, timestamp, "created a poll - #{poll.question}", {}, (error, stream)-> #upsert with findAndModify
            if error?
              console.log "ERROR CREATING STREAM DOCUMENT - IT MAY ALREADY EXIST".red
              #check if it exists - it will return an error if there is a unique index contraint set (one per transaction?)
              completed = false
              callback error, false
            else if !stream?
              console.log "STREAM IS NULL".red
              callback {name: "NullError", message: "Could Not Add To Stream"}
            else
              callback null, true
        # honor: (callback)->
        #   # UPDATE HONOR SCORE
        #   amount = 1.0
        #   api.Consumers.updateHonorScore entity.id, eventId, amount, (error, consumer)-> #amount is positive to increment by or negative to decrement by
        #     if error?
        #       completed = false
        #       callback error, false
        #     else if consumer?
        #       callback null, true
      }, (error, results)->
        if results?
          if completed
            console.log "SET PROCESSED".green
            api.Polls.setTransactionProcessed document._id, transaction.id, false, false, {}, (error, poll)->
              if error?
                console.log "ERROR SETTING PROCESSED".red
                console.log error
                return
              else if !poll?
                console.log "THE DOCUMENT WITH THAT TRANSACTION ID WAS NOT FOUND - POSSIBLY HANDLED ALREADY, IF NOT POLLER WILL TAKE CARE OF IT LATER".yellow
                console.log {name: "TransactionWarning", message:"Unable to set state to processed. Transaction may have already been processed, quitting further processing"}
                return
              else
                console.log "TRANSACITON PROCESSED".green
                return
          else #NOT COMPLETED
            if transaction.attempts > 5 #if we fail more than 5 times then there is something wrong so error out
              console.log "SET ERROR".green
              api.Polls.setTransactionError document._id, transaction.id, false, false, {}, (error, poll)->
                if error?
                  callback(error)
                else if !poll?
                  console.log "PROBLEM SETTING ERROR".red
                  console.log {name: "TransactionError", messge: "Unable to set transaction state to error in poll"}
                else
                  console.log {name: "TransactionError", messge: "Unable to find consumer"}
      # else #the event has either been processed or marked with an error, in either case we don't want to do any work on it, so move on
      return
  
eventPollAnswered = (document, transaction)->
  console.log "\nEVENT - User Answered Poll Question".green
  console.log "\nPID: #{document._id}\nTID: #{transaction.id}\n#{transaction.direction}\n".green

  console.log "SET PROCESSING".green
  api.Polls.setTransactionProcessing document._id, transaction.id, false, (error, poll)->
    if error? #determine what type of error it is and then whether to setTransactionError or ignore and let the poller pick it up later (the later is probably the case)
      console.log error
      console.log poll
      return
    else if !poll? #if poll doesn't exist
      console.log {name: "NullError", message: "Could Not Find Poll"}
      return
    else
      console.log "PROCESSING SET"
      timestamp   = transaction.dates.created
      entity      = transaction.entity

      completed = true #successful
      async.parallel {
        stream: (callback)->
          # ADD TO CONSUMER ACTIVITY STREAM
          api.Streams.add entity, choices.eventTypes.POLL_ANSWERED, transaction.id, document._id, timestamp, "answered a poll - #{poll.question}", {}, (error, stream)-> #upsert with findAndModify
            if error?
              console.log "ERROR CREATING STREAM DOCUMENT - IT MAY ALREADY EXIST".red
              #check if it exists - it will return an error if there is a unique index contraint set (one per transaction?)
              completed = false
              callback error, false
            else if !stream?
              console.log "STREAM IS NULL".red
              callback {name: "NullError", message: "Could Not Add To Stream"}
            else
              callback null, true
        # honor: (callback)->
        #   # UPDATE HONOR SCORE
        #   amount = 1.0
        #   api.Consumers.updateHonorScore entity.id, eventId, amount, (error, consumer)-> #amount is positive to increment by or negative to decrement by
        #     if error?
        #       completed = false
        #       callback error, false
        #     else if consumer?
        #       callback null, true
      }, (error, results)->
        if results?
          if completed
            console.log "SET PROCESSED".green
            api.Polls.setTransactionProcessed document._id, transaction.id, false, false, {}, (error, poll)->
              if error?
                console.log "ERROR SETTING PROCESSED".red
                console.log error
                return
              else if !poll?
                console.log "THE DOCUMENT WITH THAT TRANSACTION ID WAS NOT FOUND - POSSIBLY HANDLED ALREADY, IF NOT POLLER WILL TAKE CARE OF IT LATER".yellow
                console.log {name: "TransactionWarning", message:"Unable to set state to processed. Transaction may have already been processed, quitting further processing"}
                return
              else
                console.log "TRANSACITON PROCESSED".green
                return
          else #NOT COMPLETED
            if transaction.attempts > 5 #if we fail more than 5 times then there is something wrong so error out
              console.log "SET ERROR".green
              api.Polls.setTransactionError document._id, transaction.id, false, false, {}, (error, poll)->
                if error?
                  callback(error)
                else if !poll?
                  console.log "PROBLEM SETTING ERROR".red
                  console.log {name: "TransactionError", messge: "Unable to set transaction state to error in poll"}
                else
                  console.log {name: "TransactionError", messge: "Unable to find consumer"}
      # else #the event has either been processed or marked with an error, in either case we don't want to do any work on it, so move on
      return

eventEventRsvp = (document, transaction)->
  console.log "\nEVENT - User Rsvped for an event".green
  console.log "\nPID: #{document._id}\nTID: #{transaction.id}\n#{transaction.direction}\n".green

  console.log "SET PROCESSING".green
  timestamp   = transaction.dates.created
  entity      = transaction.entity

  completed = true #successful
  async.parallel {
    stream: (callback)->
      # ADD TO CONSUMER ACTIVITY STREAM
      _writeToStream document, transaction, choices.eventTypes.EVENT_RSVPED, "RSVPed to attend an event at #{document.location.name}", {}, callback

    # honor: (callback)->
    #   # UPDATE HONOR SCORE
    #   amount = 1.0
    #   api.Consumers.updateHonorScore entity.id, eventId, amount, (error, consumer)-> #amount is positive to increment by or negative to decrement by
    #     if error?
    #       completed = false
    #       callback error, false
    #     else if consumer?
    #       callback null, true
  }, (error, results)->
    if error?
      completed = false
    if results? #this means all the async callbacks have completed
      if completed
        console.log "SET PROCESSED".green
        api.Events.setTransactionProcessed document._id, transaction.id, false, false, {}, (error, poll)->
          if error?
            console.log "ERROR SETTING PROCESSED".red
            console.log error
            return
          else if !poll?
            console.log "THE DOCUMENT WITH THAT TRANSACTION ID WAS NOT FOUND - POSSIBLY HANDLED ALREADY, IF NOT POLLER WILL TAKE CARE OF IT LATER".yellow
            console.log {name: "TransactionWarning", message:"Unable to set state to processed. Transaction may have already been processed, quitting further processing"}
            return
          else
            console.log "TRANSACITON PROCESSED".green
            return
      else #NOT COMPLETED
        if transaction.attempts > 5 #if we fail more than 5 times then there is something wrong so error out
          console.log "SET ERROR".green
          api.Events.setTransactionError document._id, transaction.id, false, false, {}, (error, poll)->
            if error?
              callback(error)
            else if !poll?
              console.log "PROBLEM SETTING ERROR".red
              console.log {name: "TransactionError", messge: "Unable to set transaction state to error in poll"}
            else
              console.log {name: "TransactionError", messge: "Unable to find consumer"}
  # else #the event has either been processed or marked with an error, in either case we don't want to do any work on it, so move on
  return

_writeToStream = (document, transaction, eventType, message, data, callback)->
  #@add = (entity, eventType, eventId, documentId, timestamp, data, callback)
  api.Streams.add transaction.entity, eventType, transaction.id, document.id, transaction.dates.created, message, data, (error, stream)->
    if error?
      console.log "ERROR CREATING STREAM DOCUMENT - IT MAY ALREADY EXIST".red
      #check if it exists - it will return an error if there is a unique index contraint set (one per transaction?)
      callback error
    else if !stream?
      console.log "STREAM IS NULL".red
      callback {name: "NullError", message: "Could Not Add To Stream"}
    else
      callback null, stream
    

exports.process = process
