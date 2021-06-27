const PakBridge = artifacts.require("PakBridge");

const initialSupply = web3.utils.toWei('1000000', 'ether');

module.exports = function(deployer) {
    deployer.deploy(PakBridge, initialSupply).then(function() {
	console.log("PakBridge (PAK) was deployed at: "+PakBridge.address);
    });
};
