async = require "async"

globals = require "globals"
api = require "./api"

choices = globals.choices

process = (document, transaction)-> #this is just a router
  switch transaction.action
    when choices.transactions.actions.POLL_CREATE
      pollCreate(document, transaction)
    when choices.transactions.actions.POLL_ANSWER
      pollAnswer(document, transaction)

pollCreate = (document, transaction)->
  #1 deduct transactions from entity and place transactionId in transactions.ids list
  #2 write that transaction completed in log ## WE ARE SKIPPING THIS FOR NOW WILL DETERMINE IF POSSIBLE LATER
  #3 
  #4 update polls collection to set that transaction as processed

  console.log "Create Poll Question".green
  console.log "\nPID: #{document._id}\nTID: #{transaction.id}\n".green
  async.series {
    setProcessing: (callback)->
      #console.log document
      console.log "SET PROCESSING".green
      api.Polls.setTransactionProcessing document._id, transaction.id, (error, poll)->
        if error? #determine what type of error it is and then whether to setTransactionError or ignore and let the poller pick it up later (the later is probably the case)
          callback(error)
        else
          callback()
        return
        
    deductFunds: (callback)->
      console.log "DEDUCT FUNDS".green
      if transaction.entity.type is choices.entities.BUSINESS
        api.Businesses.deductFunds transaction.entity.id, transaction.id, transaction.data.amount, (error, business)->
          console.log "BID: #{business._id}".green
          if error? #determine what type of error it is and then whether to setTransactionError or ignore and let the poller pick it up later (the later is probably the case)
            callback(error)
          else if !business? #if the business object doesn't exist then either the transaction occured previously, there aren't enough funds, or the business doesn't exist
            api.Businesses.checkIfTransactionExists transaction.entity.id, transaction.id, (error, business)->
              if error?
                callback(error)
              else if business? #transaction already occured
                callback()
              else #either not enough funds or business does not exist - in either case report insufficient funds
                error = {
                  message: "there were insufficient funds"
                }
                api.Polls.setTransactionError document._id, transaction.id, error, true, (error, poll)->
                  if error?
                    callback(error)
                  else
                    callback()
          else #transaction went through
            callback()
          return
      else if transaction.entity.type is choices.entities.CONSUMER
        api.Consumers.deductFunds transaction.entity.id, transaction.id, transaction.data.amount, (error, consumer)->
          console.log "CID: #{consumer._id}".green
          if error? #determine what type of error it is and then whether to setTransactionError or ignore and let the poller pick it up later (the later is probably the case)
            callback(error)
          else if !consumer? #if the consumer object doesn't exist then either the transaction occured previously, or the consumer doesn't exist
            api.Consumers.checkIfTransactionExists transaction.entity.id, transaction.id, (error, consumer)->
              if error?
                callback(error)
              else if consumer? #transaction already occured
                callback()
              else #either not enough funds or the consumer doesn't exist - in either case report insufficient funds
                error = {
                  message: "there were insufficient funds"
                }
                api.Polls.setTransactionError document._id, transaction.id, error, true, (error, poll)->
                  if error?
                    callback(error)
                  else
                    callback()

    setProcessed: (callback)->
      console.log "SET PROCESSED".green
      $update = {
        $set: {
          "funds.allocated": transaction.data.amount
          "funds.remaining": transaction.data.amount
        }
      }

      api.Polls.setTransactionProcessed document._id, transaction.id, true, $update, (error, poll)->
        if error?
          console.log "ERROR SETTING PROCESSED".red
          callback(error)
        else if poll is null
          console.log "THE DOCUMENT WITH THAT TRANSACTION ID WAS NOT FOUND - POSSIBLY HANDLED ALREADY, IF NOT POLLER WILL TAKE CARE OF IT LATER".yellow
          callback()
        else
          callback()
        return
  }, 
  (error, results)->
    if error?
      console.log error
    #console.log results


pollAnswer = (document, transaction)->
  #1 deduct transactions from entity and place transactionId in transactions.ids list
  #4 update polls collection to set that transaction as processed
  console.log "User Answered Poll Question".green
  console.log "\nPID: #{document._id}\nTID: #{transaction.id}\n".green

  async.series {
    setProcessing: (callback)->
      console.log "SET PROCESSING".green
      api.Polls.setTransactionProcessing document._id, transaction.id, (error, poll)->
        if error? #determine what type of error it is and then whether to setTransactionError or ignore and let the poller pick it up later (the later is probably the case)
          callback(error)
        else
          callback()
        return
    
    depositFunds: (callback)->
      console.log "DEPOSIT FUNDS".green
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
              api.Polls.setTransactionError document._id, transaction.id, error, true, $update, (error, poll)->
                if error?
                  callback(error)
                else
                  callback()
        else
          callback()
        return
          
    setProcessed: (callback)->
      console.log "SET PROCESSED".green
      api.Polls.setTransactionProcessed document._id, transaction.id, false, {}, (error, poll)->
        if error?
          console.log "ERROR SETTING PROCESSED".red
          callback(error)
        else if poll is null
          console.log "THE DOCUMENT WITH THAT TRANSACTION ID WAS NOT FOUND - POSSIBLY HANDLED ALREADY, IF NOT POLLER WILL TAKE CARE OF IT LATER".yellow
          callback()
        else
          callback()
        return
  },
  (error, results)->
    if error?
      console.log "POLLER WILL RETRY LATER".red
      console.log error
  
  
exports.process = process
