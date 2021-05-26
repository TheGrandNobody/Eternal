//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title Contract for the HODL Token (HODLS)
 * @author Nobody (credits to OpenZeppelin for the IERC20 and IERC20Metadata interfaces)
 * @notice The HODL Token contract holds 
 */
contract HodlTokenV0 is IERC20, IERC20Metadata {

    mapping (address => uint256) private balances;

    mapping (address => mapping (address => uint256)) private allowances;

    uint256 private totalTokenSupply;

    string private tokenName;
    string private tokenTicker;

    /**
     * @dev Sets the token ticker and token name. Mints the total supply to the contract deployer.
     */
    constructor () {
        tokenName = "HODL Token";
        tokenTicker = "HODLS";
        totalTokenSupply = 10**10 * 10**9;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public pure override returns (string memory) {
        return "HODL Token";
    }

    /**
     * @dev Returns the token ticker 
     */
    function symbol() public pure override returns (string memory) {
        return "HODLS";
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     */
    function decimals() public pure override returns (uint8) {
        return 9;
    }
    
    /**
     * @dev Returns the total supply of the HODL token.
     */
    function totalSupply() external view override returns (uint256){
        return totalTokenSupply;
    }

    /**
     * @dev Returns the balance of a given user's address.
     * @param account The address of the user
     */
    function balanceOf(address account) external view override returns (uint256){
        return balances[account];
    }

    /**
     * @dev Tranfers a given amount of HODLS to a given user address (recipient)
     * @param recipient The destination to which the HODLS are to be transferred
     * @param amount The amount of HODLS to be transferred
     */
    function transfer(address recipient, uint256 amount) external override returns (bool){
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256){

    }

    function approve(address spender, uint256 amount) external override returns (bool){

    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {

    }
    
    /**
     * @dev Transfers a given amount of tokens from a given sender's address to a given recipient's address
     * @param sender The address of whom the tokens will be transferred from
     * @param recipient The address of whom the tokens will be transferred to
     * @param amount The amount of tokens to be transferred
     */
    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "HodlTokenV0::_transfer(): transfer from the zero address");
        require(recipient != address(0), "HodlTokenV0::_transfer(): transfer to the zero address");
        require(amount > 0, "HodlTokenV0::_transfer(): transfer amount must be greater than zero");

        uint256 senderBalance = balances[sender];
        require(senderBalance >= amount, "HodlTokenV0::_transfer(): transfer amount exceeds balance");
        balances[sender] = senderBalance - amount;
        balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }
}