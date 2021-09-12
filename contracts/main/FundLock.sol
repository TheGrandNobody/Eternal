//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IEternalToken.sol";

/**
 * @title FundLock contract
 * @author Nobody (me)
 * @notice The FundLock contract holds funds for a given time period. This is particularly useful for automated token vesting. 
 */
contract FundLock{

    // The Eternal Token interface
    IEternalToken private immutable eternal;

    address public immutable recipient;

    // Keeps track of the time at which the funds become available
    uint256 public immutable timeOfRelease;
    // Keeps track of the total amount of time to be waited
    uint256 public immutable totalWaitingTime;
    // Keeps track of the total withdrawals the recipient can perform
    uint256 public immutable split;
    // Keeps track of the number of withdrawals left
    uint256 public counter;

    constructor (uint256 _totalWaitingTime, uint256 _split, address _eternal, address _recipient) {
        eternal = IEternalToken(_eternal);
        timeOfRelease = block.timestamp + _totalWaitingTime;
        totalWaitingTime = _totalWaitingTime;
        recipient = _recipient;
        split = _split;
        counter = _split;
    }

    /**
     * @dev Withraws locked funds to the Eternal Fund if the total waiting time has elapsed since deployment.
     */
    function withdrawFunds() external {
        if (counter == 1) {
            require(block.timestamp >= timeOfRelease, "Funds are still locked");
        } else { 
            counter -= 1;
            require(block.timestamp * (10**6) >= ((timeOfRelease * (10**6)) - ((totalWaitingTime * (10**6) * counter) / split)), "Funds are still locked");
        }
        eternal.transfer(recipient, eternal.balanceOf(address(this)) / split);
    }
}