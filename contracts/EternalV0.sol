//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";

/**
 * @title Contract for eternal.finance
 * @author Nobody
 * @notice The Eternal contract holds all user-data as well as the Eternal Fund.
 */
contract EternalV0 is Context, Ownable {

    constructor (address eternalToken) {
        
    }

}
