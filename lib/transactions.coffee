async = require "async"

globals = require "globals"
api = require "./api"

choices = globals.choices

process = (document, transaction)-> #this is just a router
  switch transaction.action
    when choices.transactions.actions.POLL_CREATE
      pollCreate(document, transaction)

pollCreate = (document, transaction)->
  #1 deduct transactions from entity and place transactionId in transactions.ids list
  #2 write that transaction completed in log ## WE ARE SKIPPING THIS FOR NOW WILL DETERMINE IF POSSIBLE LATER
  #3 
  #4 update polls collection to set that transaction as processed

  async.series {
    setProcessing: (callback)->
      api.polls.__setTransactionProcessing document.id, transaction.id, (error, poll)->
        if error? #determine what type of error it is and then whether to setTransactionError or ignore and let the poller pick it up later (the later is probably the case)
          callback(error)
        else
          callback()
        return
        
    deductFunds: (callback)->
      if transaction.entity.type is choices.entities.BUSINESS
        api.businesses.deductFunds transaction.entity.id, transaction.id, transaction.data.amount, (error, business)->
          if error? #determine what type of error it is and then whether to setTransactionError or ignore and let the poller pick it up later (the later is probably the case)
            callback(error)
          else if !business? #if the business doesn't exist then either the transaction occured previously, there aren't enough funds, or the business doesn't exist
            api.businesses.checkIfTransactionExists transaction.entity.id, transaction.id, (error, business)->
              if error?
                callback(error)
              else if business? #transaction already occured
                callback()
              else #either not enough funds or business does not exist
                error = {
                  message: "Either the business entity does not exists, or there were insufficient funds"
                }
                api.polls.__setTransactionError document.id, transaction.id, error, true, (error, poll)->
                  if error?
                    callback(error)
                  else
                    callback()
          else #transaction went through
            callback()
          return
      else
        transaction.entity.type is choices.entities.CONSUMER
          api.consumers.deductPledgeCash transaction.entity.id, transaction.id, transaction.amount, (error, consumer)->
            if error?
              callback(error)
            else
              callback()
            return

    setProcessed: (callback)->
      $update = {
        $set: {
          "funds.allocated": transaction.data.amount
          "funds.remaining": transaction.data.amount
        }
      }

      api.polls.__setTransactionProcessed document.id, transaction.id, true, $update (error, poll)->
        if error?
          callback(error)
        else
          callback()
        return
  }, (error, results)->
    console.log error
