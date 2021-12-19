//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoeFactory.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoeRouter02.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoePair.sol";
import "../interfaces/IEternalToken.sol";
import "../interfaces/IEternalStorage.sol";
import "../interfaces/IEternalLiquidity.sol";
import "../inheritances/OwnableEnhanced.sol";

/**
 * @title Eternal automatic liquidity provider contract
 * @author Nobody (me)
 * @notice The Eternal Liquidity provides liquidity for the Eternal Token
 */
contract EternalLiquidity is IEternalLiquidity, OwnableEnhanced {

    // Trader Joe Router interface to swap tokens for AVAX and add liquidity
    IJoeRouter02 private immutable joeRouter;
    // The Eternal Storage interface
    IEternalStorage public immutable eternalStorage;
    // The ETRNL token
    IEternalToken private eternal;
    // The address of the ETRNL/AVAX pair
    address private joePair;
    // Determines whether an auto-liquidity provision process is undergoing
    bool private undergoingSwap;

    // The keccak256 hash of this contract's address
    bytes32 public immutable entity;
    // The total amount of liquidity provided by ETRNL
    bytes32 public immutable totalLiquidity;
    // Determines whether the contract is tasked with providing liquidity using part of the transaction fees
    bytes32 public immutable autoLiquidityProvision;

    // Allows contract to receive AVAX tokens
    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

/////–––««« Constructors & Initializers »»»––––\\\\\

    constructor (address _eternal, address _eternalStorage) {
        // Initialize router
        IJoeRouter02 _joeRouter= IJoeRouter02(0x60aE616a2155Ee3d9A68541Ba4544862310933d4);
        joeRouter = _joeRouter;

        // Initialize the Eternal Token and storage
        eternal = IEternalToken(_eternal);
        eternalStorage = IEternalStorage(_eternalStorage);

        // Initialize keccak256 hashes
        entity = keccak256(abi.encodePacked(address(this)));
        totalLiquidity = keccak256(abi.encodePacked("totalLiquidity"));
        autoLiquidityProvision = keccak256(abi.encodePacked("autoLiquidityProvision"));
    }

    function initialize() external onlyAdmin() {
        // Create pair address
        joePair = IJoeFactory(joeRouter.factory()).createPair(address(eternal), joeRouter.WAVAX());
        eternalStorage.setBool(entity, autoLiquidityProvision, true);
    }

/////–––««« Modifiers »»»––––\\\\\
    /**
     * Ensures the contract doesn't swap when it's already swapping (prevents it from getting caught in a circular liquidity event).
     */
    modifier haltsLiquidityProvision() {
        undergoingSwap = true;
        _;
        undergoingSwap = false;
    }

/////–––««« Variable state-inspection functions »»»––––\\\\\

    /**
     * @dev View the address of the ETRNL/AVAX pair on Trader Joe.
     */
    function viewPair() external view override returns(address) {
        return joePair;
    }

/////–––««« Automatic liquidity provision functions »»»––––\\\\\

    /**
     * @dev Swaps a given amount of ETRNL for AVAX using Trader Joe. (Used for auto-liquidity swaps)
     * @param amount The amount of ETRNL to be swapped for AVAX
     */
    function swapTokensForAVAX(uint256 amount, uint256 reserveETRNL, uint256 reserveAVAX) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = joeRouter.WAVAX();

        // Calculate the minimum amount of AVAX to swap the ETRNL for (with a tolerance of 1%)
        uint256 minAVAX = joeRouter.getAmountOut(amount, reserveETRNL, reserveAVAX);
        minAVAX -= minAVAX / 100;

        // Swap the ETRNL for AVAX
        require(eternal.approve(address(joeRouter), amount), "Approve failed");
        joeRouter.swapExactTokensForAVAXSupportingFeeOnTransferTokens(amount, minAVAX, path, address(this), block.timestamp);
    }

    /**
     * @dev Provides liquidity to the ETRNL/AVAX pair on Trader Joe for the EternalToken contract.
     * @param contractBalance The contract's ETRNL balance
     *
     * Requirements:
     * 
     * - Automatic liquidity provision must be enabled
     * - There cannot already be a liquidity swap in progress
     * - Caller can only be the ETRNL contract
     */
    function provideLiquidity(uint256 contractBalance) external override {
        require(_msgSender() == address(eternal), "Only callable by ETRNL contract");
        require(eternalStorage.getBool(entity, autoLiquidityProvision), "Auto-liquidity is disabled");
        require(!undergoingSwap, "A liquidity swap is in progress");

        _provideLiquidity(contractBalance);
    } 

    /**
     * @dev Converts half the contract's balance to AVAX and adds liquidity to the ETRNL/AVAX pair.
     * @param contractBalance The contract's ETRNL balance
     */
    function _provideLiquidity(uint256 contractBalance) private haltsLiquidityProvision() {
        // Split the contract's balance into two halves
        uint256 half = contractBalance / 2;
        uint256 amountETRNL = contractBalance - half;

        // Capture the initial balance to later compute the difference
        uint256 initialBalance = address(this).balance;
        // Get the reserve ratios for the ETRNL-AVAX pair
        (uint256 reserveA, uint256 reserveB,) = IJoePair(joePair).getReserves();
        (uint256 reserveETRNL, uint256 reserveAVAX) = address(eternal) < joeRouter.WAVAX() ? (reserveA, reserveB) : (reserveB, reserveA);
        // Swap half the contract's ETRNL balance to AVAX
        swapTokensForAVAX(half, reserveETRNL, reserveAVAX);
        // Compute the amount of AVAX received from the swap
        uint256 amountAVAX = address(this).balance - initialBalance;
        
        // Determine a reasonable minimum amount of ETRNL and AVAX based on current reserves (with a tolerance of 1%)
        uint256 minAVAX = joeRouter.quote(amountETRNL, reserveETRNL, reserveAVAX);
        minAVAX -= minAVAX / 100;
        uint256 minETRNL = joeRouter.quote(amountAVAX, reserveAVAX, reserveETRNL);
        minETRNL -= minETRNL / 100;

        // Add liquidity to the ETRNL/AVAX pair
        emit AutomaticLiquidityProvision(amountETRNL, contractBalance, amountAVAX);
        eternal.approve(address(joeRouter), amountETRNL);
        // Update the total liquidity 
        (,,uint256 liquidity) = joeRouter.addLiquidityAVAX{value: amountAVAX}(address(eternal), amountETRNL, minETRNL, minAVAX, address(this), block.timestamp);
        uint256 entireLiquidity = eternalStorage.getUint(entity, totalLiquidity);
        eternalStorage.setUint(entity, totalLiquidity, entireLiquidity + liquidity);
    }

/////–––««« Fund-only functions »»»––––\\\\\

    /**
     * @dev Transfers a given amount of AVAX from the contract to an address. (Fund only)
     * @param recipient The address to which the AVAX is to be sent
     * @param amount The specified amount of AVAX to transfer
     * 
     * Requirements:
     * 
     * - The contract's balance must have enough funds to accomodate the withdrawal
     */
    function withdrawAVAX(address payable recipient, uint256 amount) external override onlyFund() {
        require(amount < address(this).balance, "Insufficient balance");

        emit AVAXTransferred(amount, recipient);
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Failed to transfer AVAX");
    }

    /**
     * @dev Transfers a given amount of a token from the contract to an address. (Fund only)
     * @param asset The address of the asset being withdrawn
     * @param recipient The address to which the ETRNL is to be sent
     * @param amount The specified amount of ETRNL to transfer
     */
    function withdrawAsset(address asset, address recipient, uint256 amount) external override onlyFund() {
        emit AssetTransferred(asset, amount, recipient);
        require(IERC20(asset).transfer(recipient, amount), "Asset withdrawal failed");
    }
}