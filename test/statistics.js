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

function getAllKarmaPoints(){
  api.Statistics.getKarmaPoints("4f3301b2d0910de36d000067", cbConsole);
};

function getKarmaPointsForBusiness(){
  api.Statistics.getKarmaPoints("4f3301b2d0910de36d000067", "4f5c24edf9e111000000001e", cbConsole);
};

function earnKarmaPoints(){
  api.Statistics.earnKarmaPoints("4f3301b2d0910de36d000067", "4f5c24edf9e111000000001e", 5, cbConsole);
};

function useKarmaPoints(){
  api.Statistics.useKarmaPoints("4f3301b2d0910de36d000067", "4f5c24edf9e111000000001e", 5, cbConsole);
};


earnKarmaPoints();
getKarmaPointsForBusiness();

useKarmaPoints();
getKarmaPointsForBusiness();

getAllKarmaPoints();