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

function awardKarmaPoints(){
  api.UnclaimedBarcodeStatistics.awardKarmaPoints("123456-123", "4f5c24edf9e111000000001e", 5, cbConsole);
};

function getAllKarmaPoints(){
  api.UnclaimedBarcodeStatistics.getKarmaPoints("123456-123", cbConsole);
};

function getKarmaPointsForBusiness(){
  api.UnclaimedBarcodeStatistics.getKarmaPoints("123456-123", "4f5c24edf9e111000000001e", cbConsole);
};

awardKarmaPoints();
getKarmaPointsForBusiness();
getAllKarmaPoints();