(function() {
  var files, fs, globals, stdout, winston;

  fs = require("fs");

  globals = require("globals");

  winston = globals.winston;

  files = {
    all: fs.createWriteStream('logs/all.log', {
      flags: 'a'
    }),
    db: fs.createWriteStream('logs/db.log', {
      flags: 'a'
    }),
    api: fs.createWriteStream('logs/api.log', {
      flags: 'a'
    }),
    transaction: fs.createWriteStream('logs/transaction.log', {
      flags: 'a'
    })
  };

  stdout = process.stdout;

  exports.db = new winston.Logger({
    transports: [
      new winston.transports.WinstonStream({
        stream: [files.all, files.db],
        namespace: "db"
      })
    ],
    exceptionHandlers: [
      new winston.transports.File({
        filename: 'logs/exceptions.log'
      })
    ],
    exitOnError: false
  });

  exports.api = new winston.Logger({
    transports: [
      new winston.transports.WinstonStream({
        stream: [files.all, files.api],
        namespace: "api"
      })
    ],
    exceptionHandlers: [
      new winston.transports.File({
        filename: 'logs/exceptions.log'
      })
    ],
    exitOnError: false
  });

  exports.transaction = new winston.Logger({
    transports: [
      new winston.transports.WinstonStream({
        stream: [files.all, files.transaction],
        namespace: "transaction"
      })
    ],
    exceptionHandlers: [
      new winston.transports.File({
        filename: 'logs/exceptions.log'
      })
    ],
    exitOnError: false
  });

}).call(this);
