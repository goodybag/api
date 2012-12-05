(function() {
  var config, db, gb, gbapi, globals, mongoConnStr, mongoose, server, servers, _i, _len, _ref;

  globals = require("globals");

  gb = require("goodybag-api");

  gbapi = gb.api;

  config = require("./config");

  mongoose = globals.mongoose;

  servers = [];

  _ref = config.mongo.servers;
  for (_i = 0, _len = _ref.length; _i < _len; _i++) {
    server = _ref[_i];
    servers.push("" + server + "/" + config.mongo.dbs.goodybag);
  }

  mongoConnStr = servers.join(",");

  console.log(mongoConnStr);

  db = mongoose.connect(mongoConnStr, {}, function(error, conn) {
    if (error != null) {
      return console.log('could not connect to database');
    } else {
      return console.log("connected to database");
    }
  });

  gbapi.Consumers.get("4efc3800b78cea5683859057", function(error, data) {
    console.log("what");
    console.log(error);
    console.log(data);
  });

}).call(this);
