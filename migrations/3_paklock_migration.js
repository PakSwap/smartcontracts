const PakBridge = artifacts.require("PakBridge");
const PakLock = artifacts.require("PakLock");

const registerFee = web3.utils.toWei('10', 'ether');

module.exports = function(deployer) {
    deployer.deploy(PakLock, PakBridge.address, registerFee).then(function() {
	console.log("PakLock was deployed at: "+PakLock.address);
    });
};
