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
    
    // Sets the address of the Eternal Treasury contract
    function setEternalTreasury(address newContract) external;
    // View the rate used to convert between the reflection and true token space
    function getReflectionRate() external view returns (uint256);
    // Delegates the message sender's vote balance to a given user
    function delegate(address delegatee) external;
    // Determine the number of votes of a given account prior to a given block
    function getPriorVotes(address account, uint256 blockNumber) external view returns (uint256);

    // Signals a change of value of a given rate in the Eternal Token contract
    event UpdateRate(uint256 oldRate, uint256 newRate, Rate rate);
    // Signals a change of value of the token liquidity threshold
    event UpdateLiquidityThreshold(uint256 oldThreshold, uint256 newThreshold);
    // Signals a change of a given user's delegate
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    // Signals a change of a given delegate's vote balance
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);
}