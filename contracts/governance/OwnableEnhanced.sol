// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 *
 * @notice This is a modified version of Openzeppelin's Ownable.sol, made to add certain functionalities
 * such as different modifiers (onlyFund and onlyOwnerAndFund)
 */
abstract contract OwnableEnhanced is Context {
    address private _owner;
    address private _previousOwner;
    address private _fund;
    
    uint256 private _lockPeriod;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event FundRightsAttributed(address indexed newFund);

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyFund() {
        require(fund() == _msgSender(), "Ownable: caller is not the Eternal Fund");
        _;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwnerAndFund() {
        require((owner() == _msgSender()) || (fund() == _msgSender()), "Ownable: caller is not the owner or the Eternal Fund");
        _;
    }


    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

/////–––««« Variable state-inspection functions »»»––––\\\\\

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    function fund() public view virtual returns (address) {
        return _fund;
    }

    /**
     * @dev View the amount of time (in seconds) left before the previous owner can regain ownership
     */
    function getUnlockTime() public view returns (uint256) {
        return _lockPeriod;
    }

/////–––««« Ownable-logic functions »»»––––\\\\\

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Attributes fund-rights for the Eternal Fund to a given address.
     * @param newFund The address of the new fund 
     *
     * Requirements:
     *
     * - New owner cannot be the zero address
     */
    function attributeFundRights(address newFund) public virtual onlyOwnerAndFund {
        require(newFund != address(0), "Ownable: new fund is the zero address");
        _fund = newFund;
        emit FundRightsAttributed(newFund);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     * @param newOwner The address of the new owner
     *
     * Requirements:
     *
     * - New owner cannot be the zero address
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    /**
     * @dev Owner gives up the ownership for a given amount of time
     * @param time The amount of time (in seconds) that the ownership is locked
     */
    function lockOwnership(uint256 time) public onlyOwner {
        _previousOwner = _owner;
        _owner = address(0);
        _lockPeriod = block.timestamp + time;
        emit OwnershipTransferred(_owner, address(0));
    }

    /**
     * @dev Used to regain ownership of a previously locked contract
     *
     * Requirements:
     *
     * - Message sender must be the previous owner address
     * - The locking period must have elapsed
     */
    function unlock() public {
        require(_previousOwner == msg.sender, "Only the previous owner can unlock onwership");
        require(block.timestamp > _lockPeriod, "The contract is still locked");
        emit OwnershipTransferred(_owner, _previousOwner);
        _owner = _previousOwner;
        _previousOwner = address(0);
    }
}