// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @dev PackLock is a smartcontract, where users are
 * locking their tokens that they are swapped to another blockchain
 */
contract PakLock is Ownable {
    using SafeERC20 for IERC20;

    /// @notice PakBridge (PAK) token to use in fee for any transaction.
    IERC20 public pak;

    /// @dev the amount to use for registration
    uint256 private registerFee;

    /// @notice the address of bridge (the cosmos chain) representer.
    /// This representer ideally should act after voting process in the bridge.
    address public bridge;

    /// @dev Struct to track the registered tokens
    struct RegisteredToken {
	address targetToken;    // The token address deployed on
	                        // another blockchain
	bool active;            // Whether it was activated or not
	                        // means whether the token was deployed or not.
    }
    /// @dev Track registered tokens
    mapping(address => RegisteredToken) registeredTokens;
    
    constructor(address _pakAddress, uint256 _registerFee) {
	require(_registerFee > 0, "zero fee.");
	
	pak = IERC20(_pakAddress);
	registerFee = _registerFee;

	bridge = _msgSender();
    }

    modifier onlyBridge() {
	require(bridge == _msgSender(), "only bridge");
	_;
    }

    /**
     * @dev Return amount of PAK token to use for registration of a new bridge.
     */
    function getRegisterFee() external view returns(uint256) {
	return registerFee;
    }

    /**
     * @notice update the register fee
     */
    function setRegisterFee(uint256 _registerFee) external onlyBridge {
	require(_registerFee > 0, "zero register fee");
	registerFee = _registerFee;
    }

    /**
     * @notice Register a token to be bridged
     */
    function registerToken(address _token) external {
        RegisteredToken storage _registeredToken = registeredTokens[_token];
	require(_registeredToken.active == false, "already activated");

	/// We should redeem the PakBridge token for registeration fee
	require(pak.allowance(msg.sender, address(this)) >= registerFee, "no allowance");	
	pak.transferFrom(msg.sender, bridge, registerFee);
	
        _registeredToken.targetToken = address(0);
    }

    /**
     * @dev Activate registered token by passing the token address
     * in another blockchain
     */
    function activateRegistration(address _source, address _target) external onlyBridge {
        RegisteredToken storage _registeredToken = registeredTokens[_source];
	require(_registeredToken.active == false, "already activated");	

	_registeredToken.active = true;
	_registeredToken.targetToken = _target;
    }

    /**
     * @notice Deploy a new contract that is mapped to the token in another blockchain
     */
    function deployToken(address _sourceToken, uint256 _totalSupply) external onlyBridge {

    }
}
