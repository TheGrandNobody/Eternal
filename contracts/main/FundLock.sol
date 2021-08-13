pragma solidity ^0.8.0;

import "../inheritances/OwnableEnhanced.sol";
import "../interfaces/IEternalToken.sol";

/**
 * @title FundLock contract
 * @author Nobody (me)
 * @notice The FundLock contract holds funds for a given time period
 */
contract FundLock is OwnableEnhanced {

    // The Eternal Token interface
    IEternalToken private immutable eternal;

    address public immutable recipient;

    // Keeps track of the time at which the funds become available
    uint256 public immutable timeOfRelease;
    // Keeps track of the total amount of time to be waited
    uint256 public immutable totalWaitingTime;

    constructor (uint256 _totalWaitingTime, address _eternal, address _recipient) {
        eternal = IEternalToken(_eternal);
        timeOfRelease = block.timestamp + _totalWaitingTime;
        totalWaitingTime = _totalWaitingTime;
        recipient = _recipient;
    }

    /**
     * @dev Withraws locked funds to the Eternal Fund if the total waiting time has elapsed since deployment.
     */
    function withdrawFunds() external {
        require(block.timestamp <= timeOfRelease, "Funds are still locked");

        eternal.transfer(recipient, eternal.balanceOf(address(this)));
    }
}