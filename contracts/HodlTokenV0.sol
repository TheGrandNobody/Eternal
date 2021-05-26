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

    uint256 private totalSupply;

    string private tokenName;
    string private tokenTicker;

    /**
     * @dev Sets the token ticker and token name. Mints the total supply to the contract deployer.
     */
    constructor () {
        tokenName = "HODL Token";
        tokenTicker = "HODLS";
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return tokenName;
    }

    /**
     * @dev Returns the token ticker 
     */
    function symbol() public view virtual override returns (string memory) {
        return tokenTicker;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

}