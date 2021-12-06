//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @dev ETRNL interface
 * @author Nobody (me)
 * @notice Methods are used for the DAO-governed section of Eternal and the gaging platform
 */
interface IEternalToken is IERC20, IERC20Metadata {

    // Holds all the different types of rates
    enum Rate {
        Liquidity,
        Funding,
        Redistribution,
        Burn
    }
    
    // Sets the value of any given rate
    function setRate(Rate rate, uint256 newRate) external;
    // Sets the address of the Eternal Liquidity contract
    function setEternalLiquidity(address newContract) external;
    // Sets the liquidity threshold to a given value
    function setLiquidityThreshold(uint256 value) external;
    // Designates a new Eternal DAO address
    function designateFund(address fund) external;
    // View the rate used to convert between the reflection and true token space
    function getReflectionRate() external view returns (uint256);
    // View whether an address is excluded from the transaction fees
    function isExcludedFromFee(address account) external view returns (bool);
    // View whether an address is excluded from rewards
    function isExcludedFromReward(address account) external view returns (bool);
    // View the total fee
    function viewTotalRate() external view returns (uint256);
    // View the rate of deflation of the Eternal token
    function viewBurnRate() external view returns (uint256);

    // Signals a change of value of a given rate in the Eternal Token contract
    event UpdateRate(uint256 oldRate, uint256 newRate, Rate rate);
    // Signals a change of address for the Eternal Liquidity contract
    event UpdateEternalLiquidity(address indexed oldContract, address indexed newContract);
    // Signals a change of value of the token liquidity threshold
    event UpdateLiquidityThreshold(uint256 oldThreshold, uint256 newThreshold);
}