// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./PakToken.sol";

/**
 * @dev PackLock is a smartcontract, where users are
 * locking their tokens that they are swapped to another blockchain
 */
contract PakLock is Ownable {
    using SafeERC20 for IERC20;

    /// @notice PakBridge (PAK) token to use in fee
    /// for any transaction.
    IERC20 public pak;

    /// @dev the amount to use for registration
    uint256 private registerFee;

    /// @notice the address of bridge (the cosmos chain)
    /// representer. This representer ideally should act
    /// after voting process in the bridge.
    address public bridge;

    /// @dev Struct to track the registered tokens
    struct RegisteredToken {
	address targetToken;    // The token address deployed on
	                        // another blockchain
	bool active;            // Whether it was activated or not
	                        // means whether the token was
	                        // deployed or not.
    }
    /// @dev Track registered tokens
    mapping(address => RegisteredToken) registeredTokens;

    /// @dev swapping fee
    uint256 swapFee;

    /// @dev Locked amount of tokens:
    /// token => user => balance;
    mapping(address => mapping(address => uint256)) locks;

    /// @dev Debts of user
    mapping(address => mapping(address => uint256)) debts;

    /// @notice Total amount of locked tokens
    uint256 public lockAmount;
    
    event RegisterToken(address indexed token);
    event ActivateToken(address indexed source,
			address indexed target);
    event DeployToken(address indexed source,
		      address indexed target,
		      uint256 totalSupply,
		      string name,
		      string symbol);
    event SwapBegin(address indexed user,
		    address indexed source,
		    address indexed target,
		    uint256 amount);
    event SwapEnd(address indexed user,
		    address indexed source,
		    address indexed target,
		    uint256 amount);
    
    constructor(address _pakAddress, uint256 _registerFee,
		uint256 _swapFee) {
	require(_registerFee > 0, "register zero fee.");
	require(_swapFee > 0, "swap zero fee.");
	
	pak = IERC20(_pakAddress);
	registerFee = _registerFee;
	swapFee = _swapFee;

	bridge = _msgSender();
    }

    modifier onlyBridge() {
	require(bridge == _msgSender(), "only bridge");
	_;
    }

    /**
     * @dev Return amount of PAK token to use for 
     * registration of a new bridge.
     */
    function getRegisterFee() external view returns(uint256) {
	return registerFee;
    }

    /**
     * @notice update the register fee
     */
    function setRegisterFee(uint256 _registerFee)
	external onlyBridge {
	require(_registerFee > 0, "zero register fee");
	registerFee = _registerFee;
    }

    /**
     * @notice Register a token to be bridged
     */
    function registerToken(address _token) external {
        RegisteredToken storage _registeredToken
	    = registeredTokens[_token];
	
	require(_registeredToken.active == false,
		"already activated");

	// We should redeem the PakBridge token
	// for registeration fee
	uint256 allowance
	    = pak.allowance(msg.sender, address(this));

	require(allowance >= registerFee, "no allowance");	

	pak.transferFrom(msg.sender, bridge, registerFee);
	
        _registeredToken.targetToken = address(0);

	emit RegisterToken(_token);
    }

    /**
     * @dev Activate registered token by passing the token address
     * in another blockchain
     */
    function activateRegistration(address _source, address _target)
	external onlyBridge {
        RegisteredToken storage _registeredToken
	    = registeredTokens[_source];
	require(_registeredToken.active == false,
		"already activated");	

	_registeredToken.active = true;
	_registeredToken.targetToken = _target;

	emit ActivateToken(_source, _target);
    }

    /**
     * @notice Deploy a new contract that is mapped 
     * to the token in another blockchain
     */
    function deployToken(address _sourceToken,
			 uint256 _totalSupply,
			 string calldata _name,
			 string calldata _symbol)
		external onlyBridge	
	returns (address _targetToken) {
	
	bytes memory bytecode = type(PakToken).creationCode;
	bytes32 salt = keccak256(abi.encodePacked(_sourceToken,
						 _totalSupply));
	 
	assembly {
	_targetToken := create2(0,
				add(bytecode, 32),
				mload(bytecode), salt)
	}
	require(registeredTokens[_targetToken].active,
		"already deployed");

	registeredTokens[_targetToken]
	    = RegisteredToken(_sourceToken, true);

	PakToken(_targetToken)
	    .initialize(_name, _symbol, _totalSupply);
	
	emit DeployToken(_sourceToken,
		      _targetToken,
		      _totalSupply,
		      _name,
		      _symbol);

	emit RegisterToken(_targetToken);
	emit ActivateToken(_targetToken, _sourceToken);
	
    }

    ///////////////////////////
    ///
    /// Swap
    ///
    /// User locks his token in one blockchain.
    /// Then in another blockchain he gets that amount of token.
    /// The amount that user gets in another blockchain
    /// From total locked tokens.
    ///
    /// Risks: If using a token more favorable
    /// in one of the chains, most users will transfer to that
    /// chain their tokens. Meaning It will be hard for users
    /// to transfer to other chain
    ///////////////////////////

    function getSwapFee() external view returns(uint256) {
	return swapFee;
    }

    /**
     * @notice update the swap fee
     */
    function setSwapFee(uint256 _swapFee)
	external onlyBridge {
	require(_swapFee > 0, "zero register fee");
        swapFee = _swapFee;
    }
    
    /**
     * @notice Lock the Tokens that will be 
     * unlocked in another blockchain
     * 
     * requirements:
     * token to lock should be registered and active
     */
    function beginSwap(address _token, uint256 _amount) external {
	require(registeredTokens[_token].active,
		"token not registered yet");

	uint256 allowance
	    = pak.allowance(msg.sender, address(this));

	require(allowance >= swapFee, "no swap allowance");

	IERC20 token = IERC20(_token);
	require(token.balanceOf(msg.sender) >= _amount,
		"not enough balance");

	uint256 tokenAllowance
	    = token.allowance(msg.sender, address(this));

	require(tokenAllowance >= _amount,
		"no lock allowance");

	pak.transferFrom(msg.sender, bridge, swapFee);
	token.transferFrom(msg.sender, address(this), _amount);

	locks[_token][msg.sender] =
	    locks[_token][msg.sender] + _amount;

	lockAmount = lockAmount + _amount;

	emit SwapBegin(msg.sender, _token,
		       registeredTokens[_token].targetToken,
		       _amount);
	
    }

    /**
     * @notice Forcefully initiate from player part to
     * To cancel swapping.
     * 
     * Warning! Do it only if smartcontrac was hacked.
     *
     * TODO!
     */
    function dangerBeginSwap(address _token) external view {
	require(registeredTokens[_token].active, "not active");
    }

    function dangerEndSwap(address _token) external view onlyBridge {

    }

    function endSwap(address _user,
			 address _token, uint256 _amount)
	external onlyBridge {
	require(_amount <= lockAmount, "Not enough token.");
	require(registeredTokens[_token].active, "not active");
	
	IERC20 token = IERC20(_token);

	token.transferFrom(address(this), _user, _amount);

	debts[_token][msg.sender] = debts[_token][_user]
	    + _amount;

	emit SwapEnd(_user, _token,
		       registeredTokens[_token].targetToken,
		       _amount);

    }
}
