//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "../inheritances/OwnableEnhanced.sol";
import "../interfaces/IEternalFactory.sol";
import "../interfaces/IEternalToken.sol";
import "../interfaces/IEternalTreasury.sol";
import "../interfaces/IEternalStorage.sol";
import "../interfaces/ILoyaltyGage.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoeRouter02.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoeFactory.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoePair.sol";

/**
 * @dev Contract for the Eternal Treasury
 * @author Nobody (me)
 * @notice The Eternal Treasury contract holds all treasury logic
 */
 contract EternalTreasury is IEternalTreasury, OwnableEnhanced {

    IEternalStorage public immutable eternalStorage;
    IEternalFactory private eternalFactory;
    IEternalToken private eternal;
    IJoeFactory private joeFactory;
    IJoeRouter02 private joeRouter;

    /**
    The amount of ETRNL staked by any given individual user, converted to the "reserve" number space for fee distribution
    mapping (address => uint256) reserveBalances
    The amount of ETRNL staked by any given individual user, converted to the regular number space (raw number, no fees)
    mapping (address => uint256) stakedBalances
    The amount of a given asset provided by a user in a liquid gage of said asset
    mapping (address => mapping (address => uint256)) amountProvided;
    The amount of liquidity tokens provided for a given ETRNL/Asset pair
    mapping (address => mapping (address => uint256)) liquidityProvided;
    */

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
    // The total number of ETRNL staked by users 
    bytes32 public immutable totalStakedBalances;
    // Used to increase or decrease everyone's accumulated fees
    bytes32 public immutable reserveStakedBalances;
    // Holds all addresses of tokens held by the treasury
    bytes32 public immutable tokenTreasury;
    // The (percentage) fee rate applied to any gage-reward computations not using ETRNL (x 10 ** 5)
    bytes32 public immutable feeRate;

    // Allows contract to receive AVAX tokens
    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

/////–––««« Constructors & Initializers »»»––––\\\\\

    constructor (address _eternalStorage, address _eternalFactory, address _eternal) {
        // Set initial Storage, Factory and Token addresses
        eternalStorage = IEternalStorage(_eternalStorage);
        eternalFactory = IEternalFactory(_eternalFactory);
        eternal = IEternalToken(_eternal);
        // Initialize the Trader Joe router
        IJoeRouter02 _joeRouter = IJoeRouter02(0x60aE616a2155Ee3d9A68541Ba4544862310933d4);
        joeRouter = _joeRouter;


        // Initialize keccak256 hashes
        entity = keccak256(abi.encodePacked(address(this)));
        totalLiquidity = keccak256(abi.encodePacked("totalLiquidity"));
        autoLiquidityProvision = keccak256(abi.encodePacked("autoLiquidityProvision"));
        totalStakedBalances = keccak256(abi.encodePacked("totalStakedBalances"));
        reserveStakedBalances = keccak256(abi.encodePacked("reserveStakedBalances"));
        tokenTreasury = keccak256(abi.encodePacked("tokenTreasury"));
        feeRate = keccak256(abi.encodePacked("feeRate"));
    }

    function initialize() external onlyAdmin {
        // The largest possible number in a 256-bit integer 
        uint256 max = ~uint256(0);
        // Set initial staking balances
        uint256 totalStake = eternal.balanceOf(address(this));
        eternalStorage.setUint(entity, totalStakedBalances, totalStake);
        eternalStorage.setUint(entity, reserveStakedBalances, (max - (max % totalStake)));
        // Create pair address
        joePair = IJoeFactory(joeRouter.factory()).createPair(address(eternal), joeRouter.WAVAX());
        eternalStorage.setBool(entity, autoLiquidityProvision, true);
        // Set initial feeRate
        eternalStorage.setUint(entity, feeRate, 500);
        joeFactory = IJoeFactory(joeRouter.factory());
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

/////–––««« Reserve Utility functions »»»––––\\\\\

    /**
     * @dev Converts a given staked amount to the "reserve" number space
     * @param amount The specified staked amount
     */
    function convertToReserve(uint256 amount) private view returns(uint256) {
        uint256 currentRate = eternalStorage.getUint(entity, reserveStakedBalances) / eternalStorage.getUint(entity, totalStakedBalances);
        return amount * currentRate;
    }

    /**
     * @dev Converts a given reserve amount to the regular number space (staked)
     * @param reserveAmount The specified reserve amount
     */
    function convertToStaked(uint256 reserveAmount) private view returns(uint256) {
        uint256 currentRate = eternalStorage.getUint(entity, reserveStakedBalances) / eternalStorage.getUint(entity, totalStakedBalances);
        return reserveAmount / currentRate;
    }

    function computeMinAmounts(address asset, uint256 amountAsset, uint256 uncertainty) private view returns(uint256, uint256, uint256) {
        // Get the reserve ratios for the ETRNL-Asset pair
        (uint256 reserveA, uint256 reserveB,) = IJoePair(joeFactory.getPair(address(eternal), asset)).getReserves();
        (uint256 reserveETRNL, uint256 reserveAsset) = address(eternal) < asset ? (reserveA, reserveB) : (reserveB, reserveA);
        // Determine a reasonable minimum amount of ETRNL and Asset based on current reserves (with a tolerance of 0.5%)
        uint256 amountETRNL = joeRouter.quote(amountAsset, reserveAsset, reserveETRNL);
        uint256 minAsset = joeRouter.quote(amountETRNL, reserveETRNL, reserveAsset);
        uint256 minETRNL = amountETRNL - (amountETRNL / uncertainty);
        minAsset -= minAsset / uncertainty;

        return (minETRNL, minAsset, amountETRNL);
    }

/////–––««« Gage-logic functions »»»––––\\\\\

    /**
     * @dev Funds a given liquidity gage with ETRNL, provides liquidity using ETRNL and the receiver's asset and transfers a bonus to the receiver
     * @param gage The address of the specified liquidity gage
     * @param receiver The address of the receiver
     * @param asset The address of the asset provided by the receiver
     * @param userAmount The amount of the asset provided by the receiver
     * @param rRisk The treasury's (distributor) risk percentage 
     * @param dRisk The receiver's bonus percentage
     * 
     * Requirements:
     *
     * - Only callable by the Eternal Platform
     * - Does not work with non-existent liquidity pairs
     */
    function fundEternalLiquidGage(address gage, address receiver, address asset, uint256 userAmount, uint256 rRisk, uint256 dRisk) external override {
        require(_msgSender() == address(eternalFactory), "msg.sender must be the platform");
        require(joeFactory.getPair(address(eternal), asset) != address(0), "Unable to find pair on Dex");

        uint256 providedETRNL;
        uint256 providedAsset;
        uint256 liquidity;
        (uint256 minETRNL, uint256 minAsset, uint256 amountETRNL) = computeMinAmounts(asset, userAmount, 200);
        // Add liquidity to the ETRNL/Asset pair
        require(eternal.approve(address(joeRouter), amountETRNL), "Approve failed");
        if (asset == joeRouter.WAVAX()) {
            (providedETRNL, providedAsset, liquidity) = joeRouter.addLiquidityAVAX{value: userAmount}(address(eternal), amountETRNL, minETRNL, minAsset, address(this), block.timestamp);
        } else {
            (providedETRNL, providedAsset, liquidity) = joeRouter.addLiquidity(address(eternal), asset, amountETRNL, userAmount, minETRNL, minAsset, address(this), block.timestamp);
        }
        // Save the true amount provided as liquidity by the receiver and the actual liquidity amount
        eternalStorage.setUint(entity, keccak256(abi.encodePacked("amountProvided", receiver, asset)), providedAsset);
        eternalStorage.setUint(entity, keccak256(abi.encodePacked("liquidity", receiver, asset)), liquidity);
        // Initialize the liquid gage and transfer the user's instant reward
        ILoyaltyGage(gage).initialize(asset, address(eternal), userAmount, providedETRNL, rRisk, dRisk);
        eternal.transfer(receiver, providedETRNL * dRisk / (10 ** 4));
    }

    function settleEternalLiquidGage(address receiver, uint256 id, bool winner) external override {
        bytes32 factory = keccak256(abi.encodePacked(address(eternalFactory)));
        address gageAddress = eternalStorage.getAddress(factory, keccak256(abi.encodePacked("gages", id)));
        require(_msgSender() == gageAddress, "msg.sender must be the gage");
        ILoyaltyGage gage = ILoyaltyGage(gageAddress);
        (address rAsset,, uint256 rRisk) = gage.viewUserData(receiver);
        (,uint256 dAmount, uint256 dRisk) = gage.viewUserData(address(this));
        uint256 liquidity = eternalStorage.getUint(entity, keccak256(abi.encodePacked("liquidity", receiver, rAsset)));
        uint256 providedAsset = eternalStorage.getUint(entity, keccak256(abi.encodePacked("amountProvided", receiver, rAsset)));

        // Remove the liquidity for this gage
        (uint256 minETRNL, uint256 minAsset,) = computeMinAmounts(rAsset, providedAsset, 200);
        (uint256 amountETRNL, uint256 amountAsset) = joeRouter.removeLiquidity(address(eternal), rAsset, liquidity, minETRNL, minAsset, address(this), block.timestamp);
        // Compute and transfer the net gage deposit + any rewards due to the receiver
        uint256 eternalRewards = amountETRNL > dAmount ? amountETRNL - dAmount : 0;
        uint256 eternalFee = eternalStorage.getUint(entity, feeRate) * providedAsset / (10 ** 5);
        if (winner) {
            eternal.transfer(receiver, amountETRNL * dRisk / (10 ** 4));
            // Compute the net liquidity rewards left to distribute to stakers
            eternalRewards -= eternalRewards * dRisk / (10 ** 4);
        } else {
            amountAsset -= amountAsset * rRisk / (10 ** 4);
            // Compute the net liquidity rewards + gage deposit left to distribute to staker
            eternalRewards = amountETRNL * rRisk / (10 ** 4);
        }
        IERC20(rAsset).transfer(receiver, amountAsset - eternalFee);
        // Update staker's fees w.r.t the gage fee, gage rewards and liquidity rewards
        uint256 totalFee = eternalRewards + (dAmount * eternalStorage.getUint(entity, feeRate) / (10 ** 5));
        eternalStorage.setUint(entity, reserveStakedBalances, eternalStorage.getUint(entity, reserveStakedBalances) - convertToReserve(totalFee));
    }

/////–––««« Staking-logic functions »»»––––\\\\\

    /**
     * @dev Stakes a given amount of ETRNL into the treasury
     * @param amount The specified amount of ETRNL being staked
     * 
     * Requirements:
     * 
     * - Staked amount must be greater than 0
     */
    function stake(uint256 amount) external override {
        require(amount > 0, "Amount must be greater than 0");

        eternal.transferFrom(_msgSender(), address(this), amount);
        emit Stake(_msgSender(), amount);

        // Update user/total staked and reserve balances
        bytes32 reserveBalances = keccak256(abi.encodePacked("reserveBalances", _msgSender()));
        bytes32 stakedBalances = keccak256(abi.encodePacked("stakedBalances", _msgSender()));
        uint256 reserveAmount = convertToReserve(amount);
        uint256 reserveBalance = eternalStorage.getUint(entity, reserveBalances);
        uint256 stakedBalance = eternalStorage.getUint(entity, stakedBalances);
        eternalStorage.setUint(entity, reserveBalances, reserveBalance + reserveAmount);
        eternalStorage.setUint(entity, stakedBalances, stakedBalance + amount);
        eternalStorage.setUint(entity, reserveStakedBalances, eternalStorage.getUint(entity, reserveStakedBalances) + reserveAmount);
        eternalStorage.setUint(entity, totalStakedBalances, eternalStorage.getUint(entity, totalStakedBalances) + amount);
    }

    /**
     * @dev Unstakes a user's given amount of ETRNL and transfers the user's accumulated rewards
     * @param amount The specified amount of ETRNL being unstaked
     * 
     * Requirements:
     *
     * - User staked balance must have enough tokens to support the withdrawal 
     */
    function unstake(uint256 amount) external override {
        bytes32 stakedBalances = keccak256(abi.encodePacked("stakedBalances", _msgSender()));
        uint256 stakedBalance = eternalStorage.getUint(entity, stakedBalances);
        require(amount <= stakedBalance , "Amount exceeds staked balance");

        emit Unstake(_msgSender(), amount);
        // Update user/total staked and reserve balances
        bytes32 reserveBalances = keccak256(abi.encodePacked("reserveBalances", _msgSender()));
        uint256 reserveBalance = eternalStorage.getUint(entity, reserveBalances);
        // Reward user with percentage of fees proportional to the amount he is withdrawing
        uint256 reserveAmount = amount * reserveBalance / stakedBalance;
        eternalStorage.setUint(entity, reserveBalances, reserveBalance - reserveAmount);
        eternalStorage.setUint(entity, stakedBalances, stakedBalance - amount);
        eternalStorage.setUint(entity, reserveStakedBalances, eternalStorage.getUint(entity, reserveStakedBalances) - reserveAmount);
        eternalStorage.setUint(entity, totalStakedBalances, eternalStorage.getUint(entity, totalStakedBalances) - amount);

        eternal.transfer(_msgSender(), convertToStaked(reserveAmount));
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