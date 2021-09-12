//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev Eternal interface
 * @author Nobody (me)
 * @notice Methods are used for all gage-related functioning
 */
interface IEternal {

    function withdraw(address user, uint256 id) external;

}