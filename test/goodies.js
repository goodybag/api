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
    { org         : org
    , name        : "goody"
    , karmaPoints : 150};

  api.Goodies.add(goody, cbConsole);
};

function update(){
  var org =
    { type  : globals.choices.organizations.BUSINESS
    , id    : new ObjectId("4f5c24edf9e111000000001e")
    , name  : "Goodybag"};

  var data =
    {
      org         : org
    , name        : "goodies"
    , karmaPoints : 300
    };

  api.Goodies.update(new ObjectId("4fb6999fff64955b3d00000f"), data, cbConsole);
};

function get(){
  api.Goodies.get("4fb6999fff64955b3d00000f", cbConsole);
};

function getByBusiness(){
  api.Goodies.getByBusiness("4f5c24edf9e111000000001e", cbConsole);
};

function remove(){
  api.Goodies.remove("4fb6999fff64955b3d00000f", cbConsole);
};

//add();
//update();
get();
getByBusiness();
remove();