//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";

/**
 * @title Contract for the shared Eternal storage
 * @author Nobody (me)
 * @notice The Shared Eternal Storage contract holds all variables of all other Eternal contracts
 */
contract SharedEternalStorage is Context {

    // Scalars
    mapping (bytes32 => mapping (bytes32 => uint256)) private uints;
    mapping (bytes32 => mapping (bytes32 => address)) private addresses;
    mapping (bytes32 => mapping (bytes32 => bool)) private bools;
    mapping (bytes32 => mapping (bytes32 => bytes32)) private bytes32s;

    // Multi-value variables
    mapping(bytes32 => uint256[]) private manyUints;
    mapping(bytes32 => address[]) private manyAddresses;
    mapping(bytes32 => bool[]) private manyBools;
    mapping(bytes32 => bytes32[]) private manyBytes;

constructor () {
    bytes32 eternalStorage = keccak256(abi.encodePacked(address(this)));    
    bytes32 nobody = keccak256(abi.encodePacked(_msgSender()));
    addresses[eternalStorage][nobody] = _msgSender();
}

/////–––««« Modifiers »»»––––\\\\\

    /**
     * @dev Ensures that only the latest contracts can modify variables' states
     */
    modifier onlyLatestVersion() {
        bytes32 eternalStorage = keccak256(abi.encodePacked(address(this)));
        bytes32 entity = keccak256(abi.encodePacked(_msgSender()));
        require(_msgSender() == addresses[eternalStorage][entity], "Old contract can't edit storage");
        _;
    }

/////–––««« Setters »»»––––\\\\\

    /**
     * @dev Sets a uint256 value for a given contract and key
     * @param entity The keccak256 hash of the contract's address
     * @param key The specified mapping key
     * @param value The specified uint256 value
     */
    function setUint(bytes32 entity, bytes32 key, uint256 value) external onlyLatestVersion() {
        uints[entity][key] = value;
    }

    /**
     * @dev Sets an address value for a given contract and key
     * @param entity The keccak256 hash of the contract's address
     * @param key The specified mapping key
     * @param value The specified address value
     */
    function setAddress(bytes32 entity, bytes32 key, address value) external onlyLatestVersion() {
        addresses[entity][key] = value;
    }

    /**
     * @dev Sets a boolean value for a given contract and key
     * @param entity The keccak256 hash of the contract's address
     * @param key The specified mapping key
     * @param value The specified boolean value
     */
    function setBool(bytes32 entity, bytes32 key, bool value) external onlyLatestVersion() {
        bools[entity][key] = value;
    }    

    /**
     * @dev Sets a bytes32 value for a given contract and key
     * @param entity The keccak256 hash of the contract's address
     * @param key The specified mapping key
     * @param value The specified bytes32 value
     */
    function setBytes(bytes32 entity, bytes32 key, bytes32 value) external onlyLatestVersion() {
        bytes32s[entity][key] = value;
    }    

    /**
     * @dev Sets a uin256 array's element's value for a given key and index
     * @param key The specified mapping key
     * @param index The specified index of the array's element being modified
     * @param value The specified uint256 value
     */
    function setUintArrayValue(bytes32 key, uint256 index, uint256 value) external onlyLatestVersion() {
        manyUints[key][index] = value;
    }

    /**
     * @dev Sets an address array's element's value for a given key and index
     * @param key The specified mapping key
     * @param index The specified index of the array's element being modified
     * @param value The specified address value
     */
    function setAddressArrayValue(bytes32 key, uint256 index, address value) external onlyLatestVersion() {
        manyAddresses[key][index] = value;
    }   

    /**
     * @dev Sets a boolean array's element's value for a given key and index
     * @param key The specified mapping key
     * @param index The specified index of the array's element being modified
     * @param value The specified boolean value
     */
    function setBoolArrayValue(bytes32 key, uint256 index, bool value) external onlyLatestVersion() {
        manyBools[key][index] = value;
    }    

    /**
     * @dev Sets a bytes32 array's element's value for a given key and index
     * @param key The specified mapping key
     * @param index The specified index of the array's element being modified
     * @param value The specified bytes32value
     */
    function setBytesArrayValue(bytes32 key, bytes32 value, uint256 index) external onlyLatestVersion() {
        manyBytes[key][index] = value;
    }   

/////–––««« Getters »»»––––\\\\\
    /**
     * @dev Returns a uint256 value for a given contract and key
     * @param entity The keccak256 hash of the specified contract
     * @param key The specified mapping key
     * @return The uint256 value mapped to the key
     */
    function getUint(bytes32 key, bytes32 entity) external view returns (uint256) {
        return uints[entity][key];
    }

    /**
     * @dev Returns an address value for a given contract and key
     * @param entity The keccak256 hash of the specified contract
     * @param key The specified mapping key
     * @return The address value mapped to the key
     */
    function getAddress(bytes32 entity, bytes32 key) external view returns (address) {
        return addresses[entity][key];
    }

    /**
     * @dev Returns a boolean value for a given contract and key
     * @param entity The keccak256 hash of the specified contract
     * @param key The specified mapping key
     * @return The boolean value mapped to the key
     */    
    function getBool(bytes32 entity, bytes32 key) external view returns (bool) {
        return bools[entity][key];
    }

    /**
     * @dev Returns a bytes32 value for a given contract and key
     * @param entity The keccak256 hash of the specified contract
     * @param key The specified mapping key
     * @return The bytes32 value mapped to the key
     */
    function getBytes(bytes32 entity, bytes32 key) external view returns (bytes32) {
        return bytes32s[entity][key];
    }  

    /**
     * @dev Returns a uint256 array's element's value for a given key and index
     * @param key The specified mapping key
     * @param index The specified index of the desired element
     * @return The uint256 value at the specified index for the specified array
     */
    function getUintArrayValue(bytes32 key, uint256 index) external view returns (uint256) {
        return manyUints[key][index];
    }

    /**
     * @dev Returns an address array's element's value for a given key and index
     * @param key The specified mapping key
     * @param index The specified index of the desired element
     * @return The address value at the specified index for the specified array
     */
    function getAddressArrayValue(bytes32 key, uint256 index) external view returns (address) {
        return manyAddresses[key][index];
    }

    /**
     * @dev Returns a boolean array's element's value for a given key and index
     * @param key The specified mapping key
     * @param index The specified index of the desired element
     * @return The boolean value at the specified index for the specified array
     */
    function getBoolArrayValue(bytes32 key, uint256 index) external view returns (bool) {
        return manyBools[key][index];
    }

    /**
     * @dev Returns a bytes32 array's element's value for a given key and index
     * @param key The specified mapping key
     * @param index The specified index of the desired element
     * @return The bytes32 value at the specified index for the specified array
     */
    function getBytes32ArrayValue(bytes32 key, uint256 index) external view returns (bytes32) {
        return manyBytes[key][index];
    }

/////–––««« Array Deletion »»»––––\\\\\

    /** 
     * @dev Deletes a uint256 array's element for a given key and index
     * @param key The specified mapping key
     * @param index The specified index of the desired element
     */
    function deleteUint(bytes32 key, uint256 index) external onlyLatestVersion() {
        uint256 length = manyUints[key].length;
        manyUints[key][index] = manyUints[key][length - 1];
        manyUints[key].pop();
    }

    /** 
     * @dev Deletes an address array's element for a given key and index
     * @param key The specified mapping key
     * @param index The specified index of the desired element
     */
    function deleteAddress(bytes32 key, uint256 index) external onlyLatestVersion() {
        uint256 length = manyAddresses[key].length;
        manyAddresses[key][index] = manyAddresses[key][length - 1];
        manyAddresses[key].pop();
    }

    /** 
     * @dev Deletes a boolean array's element for a given key and index
     * @param key The specified mapping key
     * @param index The specified index of the desired element
     */
    function deleteBool(bytes32 key, uint256 index) external onlyLatestVersion() {
        uint256 length = manyBools[key].length;
        manyBools[key][index] = manyBools[key][length - 1];
        manyBools[key].pop();
    }

    /** 
     * @dev Deletes a bytes32 array's element for a given key and index
     * @param key The specified mapping key
     * @param index The specified index of the desired element
     */
    function deleteBytes32(bytes32 key, uint256 index) external onlyLatestVersion() {
        uint256 length = manyBytes[key].length;
        manyBytes[key][index] = manyBytes[key][length - 1];
        manyBytes[key].pop();
    }

}