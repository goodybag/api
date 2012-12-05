(function() {
  var api, comment, db, discussionId, distributeDonation, donate, entity, get, getResponses, globals, list, mongoose, respond, responseId, thank, undoVoteUp, voteDown, voteUp;

  api = require("../lib/api");

  globals = require("globals");

  mongoose = globals.mongoose;

  db = mongoose.connect("mongodb://127.0.0.1:1337/goodybag", {
    auto_reconnect: true
  }, function(error, conn) {
    if (error != null) {
      return console.log("could not connect to database");
    } else {
      return console.log("connected to database");
    }
  });

  discussionId = "4f2a4eaa2be51c4e1800000c";

  responseId = "4f2a521d667303221a00000c";

  entity = {
    type: "consumer",
    id: "4f3301b2d0910de36d000067",
    name: "lalit",
    screenName: "secret"
  };

  respond = function() {
    var content, response;
    content = "blah blah blah";
    response = {
      entity: entity,
      content: content
    };
    return api.Discussions.respond(discussionId, entity, content, function(error, success) {
      console.log(error);
      return console.log(success);
    });
  };

  voteUp = function() {
    return api.Discussions.voteUp(discussionId, responseId, entity, function(error, success) {
      console.log(error);
      return console.log(success);
    });
  };

  voteDown = function() {
    return api.Discussions.voteDown(discussionId, responseId, entity, function(error, success) {
      console.log(error);
      return console.log(success);
    });
  };

  undoVoteUp = function() {
    return api.Discussions.undoVoteUp(discussionId, responseId, entity, function(error, success) {
      console.log(error);
      return console.log(success);
    });
  };

  comment = function() {
    var content;
    entity = entity;
    content = "COMMENTING YAY YAY!!";
    return api.Discussions.comment(discussionId, responseId, entity, content, function(error, success) {
      console.log(error);
      return console.log(success);
    });
  };

  donate = function() {
    var amount;
    amount = 0.01;
    return api.Discussions.donate(discussionId, entity, amount, function(error, success) {
      console.log(error);
      return console.log(success);
    });
  };

  thank = function() {
    var amount;
    amount = 0.01;
    return api.Discussions.thank(discussionId, responseId, entity, amount, function(error, success) {
      console.log(error);
      return console.log(success);
    });
  };

  distributeDonation = function() {
    var amount;
    amount = 0.01;
    return api.Discussions.distributeDonation(discussionId, responseId, entity, amount, function(error, success) {
      console.log(error);
      return console.log(success);
    });
  };

  list = function() {
    return api.Discussions.list(function(error, discussions) {
      console.log(error);
      return console.log(discussions);
    });
  };

  get = function() {
    return api.Discussions.get(discussionId, function(error, discussion) {
      console.log(error);
      return console.log(discussion);
    });
  };

  getResponses = function() {
    return api.Discussions.getResponses(discussionId, {
      start: 0,
      stop: 2
    }, function(error, responses) {
      console.log(error);
      return console.log(responses);
    });
  };

}).call(this);
