require("coffee-script");

var mocha = require("mocha")
  , globals = require("globals")
  , api = require("../lib/api")
  , mongoose = globals.mongoose
  , ObjectId = globals.mongoose.Types.ObjectId;

mongoose.connect("mongodb://localhost:1337/goodybag");

function cbConsole(err, result){
  console.error(err);
  console.log(result);
};

function add(){
  var org =
    { type  : globals.choices.organizations.BUSINESS
    , id    : new ObjectId("4f5c24edf9e111000000001e")
    , name  : "Goodybag"};

  var goody =
    { org                 : org
    , name                : "goody"
    , karmaPointsRequired : 150};

  api.Goodies.add(goody, cbConsole);
};

function update(){
  var org =
    { type  : globals.choices.organizations.BUSINESS
    , id    : new ObjectId("4f5c24edf9e111000000001e")
    , name  : "Goodybag"};

  var data =
    { org                 : org
    , name                : "goodies"
    , karmaPointsRequired : 300};

  api.Goodies.update(new ObjectId("4fb8f5094dfc91000000000f"), data, cbConsole);
};

function get(){
  api.Goodies.get("4fb8f5094dfc91000000000f", cbConsole);
};

function getWithBusinessId(){
  api.Goodies.get("4fb8f5094dfc91000000000f", "4f5c24edf9e111000000001e", cbConsole);
};

function getByBusiness(){
  api.Goodies.getByBusiness("4fb8f5094dfc91000000000f", cbConsole);
};

function count(){
  api.Goodies.count({}, cbConsole);
};

function countActive(){
  api.Goodies.count({active: true}, cbConsole);
};

function countWithBusinessId(){
  api.Goodies.count({businessId: "4f5c24edf9e111000000001e"}, cbConsole);
};

function countActiveWithBusinessId(){
  api.Goodies.count({active: true, businessId: "4f5c24edf9e111000000001e"}, cbConsole);
};

function remove(){
  api.Goodies.remove("4fb8f5094dfc91000000000f", cbConsole);
};

// add();
// update();
// get();
// getWithBusinessId();
// getByBusiness();
// count();
// countActive();
// countWithBusinessId();
// countActiveWithBusinessId();
// remove();