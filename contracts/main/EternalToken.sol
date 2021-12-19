//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "../interfaces/IEternalToken.sol";
import "../interfaces/IEternalTreasury.sol";
import "../interfaces/IEternalStorage.sol";
import "../inheritances/OwnableEnhanced.sol";

/**
 * @title Contract for the Eternal Token (ETRNL)
 * @author Nobody (me)
 * (credits to OpenZeppelin for initial framework and RFI for by far the most efficient way of implementing reward-distributing tokens)
 * @notice The Eternal Token contract holds all the deflationary, burn, reflect, funding and auto-liquidity provision mechanics
 */
contract EternalToken is IEternalToken, OwnableEnhanced {

    // The Eternal shared storage interface
    IEternalStorage public immutable eternalStorage;
    // The Eternal treasury interface
    IEternalTreasury private eternalTreasury;

    // The keccak256 hash of this contract's address
    bytes32 public immutable entity;

 /*
    ///---*****  Variables: Hidden Mappings *****---\\\

    // The reflected balances used to track reward-accruing users' total balances
    mapping (address => uint256) reflectedBalances

    // The true balances used to track non-reward-accruing addresses' total balances
    mapping (address => uint256) trueBalances

    // Keeps track of whether an address is excluded from rewards
    mapping (address => bool) isExcludedFromRewards

    // Keeps track of whether an address is excluded from transfer fees
    mapping (address => bool) isExcludedFromFees
    
    // Keeps track of how much an address allows any other address to spend on its behalf
    mapping (address => mapping (address => uint256)) allowances
*/

///---*****  Variables: Token Information *****---\\\
    // Keeps track of all reward-excluded addresses
    bytes32 public immutable excludedAddresses;
    // The true total ETRNL supply
    bytes32 public immutable totalTokenSupply;
    // The total ETRNL supply after taking reflections into account
    bytes32 public immutable totalReflectedSupply;
    // Threshold at which the contract swaps its ETRNL balance to provide liquidity (0.1% of total supply by default)
    bytes32 public immutable tokenLiquidityThreshold;

///---*****  Variables: Token Fee Rates *****---\\\
    // The percentage of the fee, taken at each transaction, that is stored in the Eternal Treasury (x 10 ** 5)
    bytes32 public immutable fundingRate;
    // The percentage of the fee, taken at each transaction, that is burned (x 10 ** 5)
    bytes32 public immutable burnRate;
    // The percentage of the fee, taken at each transaction, that is redistributed to holders (x 10 ** 5)
    bytes32 public immutable redistributionRate;
    // The percentage of the fee taken at each transaction, that is used to auto-lock liquidity (x 10 ** 5)
    bytes32 public immutable liquidityProvisionRate;

///---*****  Variables: Transaction Counting *****---\\\
    // The total number of times ETRNL has been transacted with fees in the last full 24h period
    bytes32 public immutable alpha;
    // The total number of times ETRNL has been transacted with fees in the current 24h period (ongoing)
    bytes32 public immutable transactionCount;
    // Keeps track of the UNIX time to recalculate the average transaction estimate
    bytes32 public immutable oneDayFromNow;

/////–––««« Constructors & Initializers »»»––––\\\\\

    constructor (address _eternalStorage) {
        eternalStorage = IEternalStorage(_eternalStorage);

        // Initialize keccak256 hashes
        entity = keccak256(abi.encodePacked(address(this)));
        totalTokenSupply = keccak256(abi.encodePacked("totalTokenSupply"));
        totalReflectedSupply = keccak256(abi.encodePacked("totalReflectedSupply"));
        tokenLiquidityThreshold = keccak256(abi.encodePacked("tokenLiquidityThreshold"));
        fundingRate = keccak256(abi.encodePacked("fundingRate"));
        burnRate = keccak256(abi.encodePacked("burnRate"));
        redistributionRate = keccak256(abi.encodePacked("redistributionRate"));
        liquidityProvisionRate = keccak256(abi.encodePacked("liquidityProvisionRate"));
        alpha = keccak256(abi.encodePacked("alpha"));
        transactionCount = keccak256(abi.encodePacked("transactionCount"));
        oneDayFromNow = keccak256(abi.encodePacked("oneDayFromNow"));
        excludedAddresses = keccak256(abi.encodePacked("excludedAddresses"));
    } 

    /**
     * @dev Initialize supplies and routers and create a pair. Mints total supply to the contract deployer. 
     * Exclude some addresses from fees and/or rewards. Sets initial rate values.
     */
    function initialize() external onlyAdmin() {

        // The largest possible number in a 256-bit integer
        uint256 max = ~uint256(0);

        // Initialize total supplies, liquidity threshold and transfer total supply to the owner
        eternalStorage.setUint(entity, totalTokenSupply, (10 ** 10) * (10 ** 18));
        eternalStorage.setUint(entity, totalReflectedSupply, (max - (max % ((10 ** 10) * (10 ** 18)))));
        eternalStorage.setUint(entity, tokenLiquidityThreshold, (10 ** 10) * (10 ** 18) / 1000);
        eternalStorage.setUint(entity, keccak256(abi.encodePacked("reflectedBalances", admin())), (max - (max % ((10**10) * (10 ** 18)))));

        // Exclude the temporary admin address from rewards and fees
        excludeFromReward(admin());
        eternalStorage.setBool(entity, keccak256(abi.encodePacked("isExcludedFromFees", admin())), true);
        // Exclude this contract from rewards and fees
        excludeFromReward(address(this));
        eternalStorage.setBool(entity, keccak256(abi.encodePacked("isExcludedFromFees", address(this))), true);
        // Exclude the burn address from rewards
        excludeFromReward(address(0));

        // Set initial rates for fees
        eternalStorage.setUint(entity, fundingRate, 500);
        eternalStorage.setUint(entity, burnRate, 500);
        eternalStorage.setUint(entity, redistributionRate, 5000);
        eternalStorage.setUint(entity, liquidityProvisionRate, 1500);

        //Initialize the transaction count time tracker
        eternalStorage.setUint(entity, oneDayFromNow, block.timestamp + 86400);
    }

/////–––««« Variable state-inspection functions »»»––––\\\\\

    /**
     * @dev View the name of the token. 
     * @return The token name
     */
    function name() external pure override returns (string memory) {
        return "Eternal Token";
    }

    /**
     * @dev View the token ticker.
     * @return The token ticker
     */
    function symbol() external pure override returns (string memory) {
        return "ETRNL";
    }

    /**
     * @dev View the maximum number of decimals for the Eternal token.
     * @return The number of decimals
     */
    function decimals() external pure override returns (uint8) {
        return 18;
    }
    
    /**
     * @dev View the total supply of the Eternal token.
     * @return Returns the total ETRNL supply.
     */
    function totalSupply() external view override returns (uint256){
        return eternalStorage.getUint(entity, totalTokenSupply);
    }

    /**
     * @dev View the balance of a given user's address.
     * @param account The address of the user
     * @return The balance of the account
     */
    function balanceOf(address account) public view override returns (uint256){
        if (eternalStorage.getBool(entity, keccak256(abi.encodePacked("isExcludedFromRewards", account)))) {
            return eternalStorage.getUint(entity, keccak256(abi.encodePacked("trueBalances", account)));
        }
        return convertFromReflectedToTrueAmount(eternalStorage.getUint(entity, keccak256(abi.encodePacked("reflectedBalances", account))));
    }

    /**
     * @dev View the allowance of a given owner address for a given spender address.
     * @param owner The address of whom we are checking the allowance of
     * @param spender The address of whom we are checking the allowance for
     * @return The allowance of the owner for the spender
     */
    function allowance(address owner, address spender) external view override returns (uint256){
        return eternalStorage.getUint(entity, keccak256(abi.encodePacked("allowances", owner, spender)));
    }

    /**
     * @dev Computes the current rate used to inter-convert from the mathematically reflected space to the "true" or total space.
     * @return The ratio of net reflected ETRNL to net total ETRNL
     */
    function getReflectionRate() public view override returns (uint256) {
        (uint256 netReflectedSupply, uint256 netTokenSupply) = getNetSupplies();
        return netReflectedSupply / netTokenSupply;
    }

/////–––««« IERC20/ERC20 functions »»»––––\\\\\

    /**
     * @dev Tranfers a given amount of ETRNL to a given receiver address.
     * @param recipient The destination to which the ETRNL are to be transferred
     * @param amount The amount of ETRNL to be transferred
     * @return True if the transfer is successful.
     */
    function transfer(address recipient, uint256 amount) external override returns (bool){
        _transfer(_msgSender(), recipient, amount);

        return true;
    }

    /**
     * @dev Sets the allowance for a given address to a given amount.
     * @param spender The address of whom we are changing the allowance for
     * @param amount The amount we are changing the allowance to
     * @return True if the approval is successful.
     */
    function approve(address spender, uint256 amount) external override returns (bool){
        _approve(_msgSender(), spender, amount);

        return true;
    }

    /**
     * @dev Transfers a given amount of ETRNL for a given sender address to a given recipient address.
     * @param sender The address whom we withdraw the ETRNL from
     * @param recipient The address which shall receive the ETRNL
     * @param amount The amount of ETRNL which is being transferred
     * @return True if the transfer and approval are both successful.
     *
     * Requirements:
     * 
     * - The caller must be allowed to spend (at least) the given amount on the sender's behalf
     */
    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = eternalStorage.getUint(entity, keccak256(abi.encodePacked("allowances", sender, _msgSender())));
        require(currentAllowance >= amount, "Not enough allowance");
        _approve(sender, _msgSender(), currentAllowance - amount);

        return true;
    }

    /**
     * @dev Sets the allowance of a given owner address for a given spender address to a given amount.
     * @param owner The adress of whom we are changing the allowance of
     * @param spender The address of whom we are changing the allowance for
     * @param amount The amount which we change the allowance to
     *
     * Requirements:
     * 
     * - Approve amount must be less than or equal to the actual total token supply
     * - Owner and spender cannot be the zero address
     */
    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "Approve from the zero address");
        require(spender != address(0), "Approve to the zero address");

        eternalStorage.setUint(entity, keccak256(abi.encodePacked("allowances", owner, spender)), amount);

        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Transfers a given amount of ETRNL from a given sender's address to a given recipient's address.
     * Bottleneck for what transfer equation to use.
     * @param sender The address of whom the ETRNL will be transferred from
     * @param recipient The address of whom the ETRNL will be transferred to
     * @param amount The amount of ETRNL to be transferred
     * 
     * Requirements:
     * 
     * - Sender or recipient cannot be the zero address
     * - Transferred amount must be greater than zero
     */
    function _transfer(address sender, address recipient, uint256 amount) private {
        uint256 balance = balanceOf(sender);
        require(balance >= amount, "Transfer amount exceeds balance");
        require(sender != address(0), "Transfer from the zero address");
        require(recipient != address(0), "Transfer to the zero address");
        require(amount > 0, "Transfer amount must exceed zero");

        // We only take fees if both the sender and recipient are susceptible to fees
        bool senderExcludedFromFees = eternalStorage.getBool(entity, keccak256(abi.encodePacked("isExcludedFromFees", sender)));
        bool recipientExcludedFromFees = eternalStorage.getBool(entity, keccak256(abi.encodePacked("isExcludedFromFees", recipient)));
        bool takeFee = (!senderExcludedFromFees && !recipientExcludedFromFees);

        (uint256 reflectedAmount, uint256 netReflectedTransferAmount, uint256 netTransferAmount) = getValues(amount, takeFee);
        
        // Always update the reflected balances of sender and recipient
        bytes32 reflectedSenderBalance = keccak256(abi.encodePacked("reflectedBalances", sender));
        bytes32 reflectedRecipientBalance = keccak256(abi.encodePacked("reflectedBalances", recipient));
        uint256 senderReflectedBalance = eternalStorage.getUint(entity, reflectedSenderBalance);
        uint256 recipientReflectedBalance = eternalStorage.getUint(entity, reflectedRecipientBalance);
        eternalStorage.setUint(entity, reflectedSenderBalance, senderReflectedBalance - reflectedAmount);
        eternalStorage.setUint(entity, reflectedRecipientBalance, recipientReflectedBalance + netReflectedTransferAmount);

        // Update true balances for any non-reward-accruing accounts 
        bool senderExcludedFromRewards = eternalStorage.getBool(entity, keccak256(abi.encodePacked("isExcludedFromRewards", sender)));
        bool recipientExcludedFromRewards = eternalStorage.getBool(entity, keccak256(abi.encodePacked("isExcludedFromRewards", recipient)));

        if (senderExcludedFromRewards) {
            bytes32 trueSenderBalance = keccak256(abi.encodePacked("trueBalances", sender));
            uint256 senderTrueBalance = eternalStorage.getUint(entity, trueSenderBalance);
            eternalStorage.setUint(entity, trueSenderBalance, senderTrueBalance - amount);
        }
        if (recipientExcludedFromRewards) {
            bytes32 trueRecipientBalance = keccak256(abi.encodePacked("trueBalances", recipient));
            uint256 recipientTrueBalance = eternalStorage.getUint(entity, trueRecipientBalance);
            eternalStorage.setUint(entity, trueRecipientBalance, recipientTrueBalance + netTransferAmount);
        }

        emit Transfer(sender, recipient, netTransferAmount);

        // Update the 24h transaction count if the current 24h period has not elapsed
        uint256 currentCount = eternalStorage.getUint(entity, transactionCount);
        uint256 aDayFromNow = eternalStorage.getUint(entity, oneDayFromNow);
        if (takeFee && block.timestamp < aDayFromNow) {
            eternalStorage.setUint(entity, transactionCount, currentCount + 1);
        } else if (takeFee && block.timestamp >= aDayFromNow) {
            // Else update alpha, and reset the transaction count and 24h period tracker
            eternalStorage.setUint(entity, alpha, currentCount);
            eternalStorage.setUint(entity, transactionCount, amount);
            eternalStorage.setUint(entity, oneDayFromNow, block.timestamp + 84600);
        }

        // Adjust the total reflected supply for the new fees
        // If the sender or recipient are excluded from fees, we ignore the fee altogether
        if (takeFee) {
            // Perform a burn based on the burn rate 
            uint256 deflationRate = eternalStorage.getUint(entity, burnRate);
            _burn(address(this), amount * deflationRate / 100000, reflectedAmount * deflationRate / 100000);
            // Redistribute based on the redistribution rate 
            uint256 reflectedSupply = eternalStorage.getUint(entity, totalReflectedSupply);
            uint256 rewardRate = eternalStorage.getUint(entity, redistributionRate);
            eternalStorage.setUint(entity, totalReflectedSupply, reflectedSupply - (reflectedAmount * rewardRate / 100000));
            // Store ETRNL away in the treasury based on the funding rate
            bytes32 treasuryBalance = keccak256(abi.encodePacked("reflectedBalances", address(eternalTreasury)));
            uint256 fundBalance = eternalStorage.getUint(entity, treasuryBalance);
            uint256 fundRate = eternalStorage.getUint(entity, fundingRate);
            eternalStorage.setUint(entity, treasuryBalance, fundBalance + (reflectedAmount * fundRate / 100000));
            // Provide liquidity to the ETRNL/AVAX pair on TraderJoe based on the liquidity provision rate
            uint256 liquidityRate = eternalStorage.getUint(entity, liquidityProvisionRate);
            storeLiquidityFunds(sender, amount * liquidityRate / 100000, reflectedAmount * liquidityRate / 100000);
        }
    }

    /**
     * @dev Burns a given amount of ETRNL.
     * @param amount The amount of ETRNL being burned
     * @return True if the burn is successful
     *
     * Requirements:
     * 
     * - Cannot burn from the burn address
     * - Burn amount cannot be greater than the msgSender's balance
     */
    function burn(uint256 amount) external returns (bool) {
        require(_msgSender() != address(0), "Burn from the zero address");
        uint256 balance = balanceOf(_msgSender());
        require(balance >= amount, "Burn amount exceeds balance");

        // Subtract the amounts from the sender before so we can reuse _burn elsewhere
        uint256 reflectedAmount;
        bool senderExcludedFromFees = eternalStorage.getBool(entity, keccak256(abi.encodePacked("isExcludedFromFees", _msgSender())));
        bool senderExcludedFromRewards = eternalStorage.getBool(entity, keccak256(abi.encodePacked("isExcludedFromRewards", _msgSender())));
        (,reflectedAmount,) = getValues(amount, !senderExcludedFromFees);
        bytes32 reflectedSenderBalance = keccak256(abi.encodePacked("reflectedBalances", _msgSender()));
        uint256 senderReflectedBalance = eternalStorage.getUint(entity, reflectedSenderBalance);
        eternalStorage.setUint(entity, reflectedSenderBalance, senderReflectedBalance - reflectedAmount);

        if (senderExcludedFromRewards) {
            bytes32 trueSenderBalance = keccak256(abi.encodePacked("trueBalances", _msgSender()));
            uint256 senderTrueBalance = eternalStorage.getUint(entity, trueSenderBalance);
            eternalStorage.setUint(entity, trueSenderBalance, senderTrueBalance - amount);
        }
        
        _burn(_msgSender(), amount, reflectedAmount);

        return true;
    }
    
    /**
     * @dev Burns the specified amount of ETRNL for a given sender by sending them to the 0x0 address.
     * @param sender The specified address burning ETRNL
     * @param amount The amount of ETRNL being burned
     * @param reflectedAmount The reflected equivalent of ETRNL being burned
     */
    function _burn(address sender, uint256 amount, uint256 reflectedAmount) private { 
        bytes32 burnReflectedBalance = keccak256(abi.encodePacked("reflectedBalances", address(0)));
        bytes32 burnTrueBalance = keccak256(abi.encodePacked("trueBalances", address(0)));

        // Send tokens to the 0x0 address
        uint256 reflectedZeroBalance = eternalStorage.getUint(entity, burnReflectedBalance);
        uint256 trueZeroBalance = eternalStorage.getUint(entity, burnTrueBalance);
        eternalStorage.setUint(entity, burnReflectedBalance, reflectedZeroBalance + reflectedAmount);
        eternalStorage.setUint(entity, burnTrueBalance, trueZeroBalance + amount);

        // Update supplies accordingly
        uint256 tokenSupply = eternalStorage.getUint(entity, totalTokenSupply);
        uint256 reflectedSupply = eternalStorage.getUint(entity, totalReflectedSupply);
        eternalStorage.setUint(entity, totalTokenSupply, tokenSupply - amount);
        eternalStorage.setUint(entity, totalReflectedSupply, reflectedSupply - reflectedAmount);

        emit Transfer(sender, address(0), amount);
    }

/////–––««« Reward-redistribution functions »»»––––\\\\\

    /**
     * @dev Translates a given reflected sum of ETRNL into the true amount of ETRNL it represents based on the current reserve rate.
     * @param reflectedAmount The specified reflected sum of ETRNL
     * @return The true amount of ETRNL representing by its reflected amount
     */
    function convertFromReflectedToTrueAmount(uint256 reflectedAmount) private view returns(uint256) {
        uint256 currentRate =  getReflectionRate();

        return reflectedAmount / currentRate;
    }

    /**
     * @dev Compute the reflected and net reflected transferred amounts and the net transferred amount from a given amount of ETRNL.
     * @param trueAmount The specified amount of ETRNL
     * @return The reflected amount, the net reflected transfer amount, the actual net transfer amount, and the total reflected fees
     */
    function getValues(uint256 trueAmount, bool takeFee) private view returns (uint256, uint256, uint256) {
        
        uint256 liquidityRate = eternalStorage.getUint(entity, liquidityProvisionRate);
        uint256 deflationRate = eternalStorage.getUint(entity, burnRate);
        uint256 fundRate = eternalStorage.getUint(entity, fundingRate);
        uint256 rewardRate = eternalStorage.getUint(entity, redistributionRate);

        uint256 feeRate = takeFee ? (liquidityRate + deflationRate + fundRate + rewardRate) : 0;

        // Calculate the total fees and transfered amount after fees
        uint256 totalFees = (trueAmount * feeRate) / 100000;
        uint256 netTransferAmount = trueAmount - totalFees;

        // Calculate the reflected amount, reflected total fees and reflected amount after fees
        uint256 currentRate = getReflectionRate();
        uint256 reflectedAmount = trueAmount * currentRate;
        uint256 reflectedTotalFees = totalFees * currentRate;
        uint256 netReflectedTransferAmount = reflectedAmount - reflectedTotalFees;
        
        return (reflectedAmount, netReflectedTransferAmount, netTransferAmount);
    }

    /**
     * @dev Computes the net reflected and total token supplies (adjusted for non-reward-accruing accounts).
     * @return The adjusted reflected supply and adjusted total token supply
     */
    function getNetSupplies() private view returns(uint256, uint256) {
        uint256 brutoReflectedSupply = eternalStorage.getUint(entity, totalReflectedSupply);
        uint256 brutoTokenSupply = eternalStorage.getUint(entity, totalTokenSupply);
        uint256 netReflectedSupply = brutoReflectedSupply;
        uint256 netTokenSupply = brutoTokenSupply;

        for (uint256 i = 0; i < eternalStorage.lengthAddress(excludedAddresses); i++) {
            // Failsafe for non-reward-accruing accounts owning too many tokens (highly unlikely; nonetheless possible)
            address excludedAddress = eternalStorage.getAddressArrayValue(excludedAddresses, i);
            uint256 reflectedBalance = eternalStorage.getUint(entity, keccak256(abi.encodePacked("reflectedBalances", excludedAddress)));
            uint256 trueBalance = eternalStorage.getUint(entity, keccak256(abi.encodePacked("trueBalances", excludedAddress)));
            if (reflectedBalance > netReflectedSupply || trueBalance > netTokenSupply) {
                return (brutoReflectedSupply, brutoTokenSupply);
            }
            // Subtracting each excluded account from both supplies yields the adjusted supplies
            netReflectedSupply -= reflectedBalance;
            netTokenSupply -= trueBalance;
        }
        // In case there are no tokens left in circulation for reward-accruing accounts
        if (netTokenSupply == 0 || netReflectedSupply < (brutoReflectedSupply / brutoTokenSupply)){
            return (brutoReflectedSupply, brutoTokenSupply);
        }

        return (netReflectedSupply, netTokenSupply);
    }

    /**
     * @dev Updates the contract's balance regarding the liquidity provision fee for a given transaction's amount.
     * If the contract's balance threshold is reached, also initiates automatic liquidity provision.
     * @param sender The address of whom the ETRNL is being transferred from
     * @param amount The amount of ETRNL being transferred
     * @param reflectedAmount The reflected amount of ETRNL being transferred
     */
    function storeLiquidityFunds(address sender, uint256 amount, uint256 reflectedAmount) private {

        // Update the contract's balance to account for the liquidity provision fee
        bytes32 thisReflectedBalance = keccak256(abi.encodePacked("reflectedBalances", address(this)));
        bytes32 thisTrueBalance = keccak256(abi.encodePacked("trueBalances", address(this)));
        uint256 reflectedBalance = eternalStorage.getUint(entity, thisReflectedBalance);
        uint256 trueBalance = eternalStorage.getUint(entity, thisTrueBalance);
        eternalStorage.setUint(entity, thisReflectedBalance, reflectedBalance + reflectedAmount);
        eternalStorage.setUint(entity, thisTrueBalance, trueBalance + amount);
        
        // Check whether the contract's balance threshold is reached; if so, initiate a liquidity swap
        uint256 contractBalance = balanceOf(address(this));
        if ((contractBalance >= eternalStorage.getUint(entity, tokenLiquidityThreshold)) && (sender != eternalTreasury.viewPair())) {
            _transfer(address(this), address(eternalTreasury), contractBalance);
            eternalTreasury.provideLiquidity(contractBalance);
        }
    }

/////–––««« Owner/Fund-only functions »»»––––\\\\\

    /**
     * @dev Excludes a given wallet or contract's address from accruing rewards. (Admin and Fund only)
     * @param account The wallet or contract's address
     *
     * Requirements:
     * – Account must not already be excluded from rewards.
     */
    function excludeFromReward(address account) public onlyAdminAndFund() {
        bytes32 excludedFromRewards = keccak256(abi.encodePacked("isExcludedFromRewards", account));
        require(!eternalStorage.getBool(entity, excludedFromRewards), "Account is already excluded");

        uint256 reflectedBalance = eternalStorage.getUint(entity, keccak256(abi.encodePacked("reflectedBalances", account)));
        if (reflectedBalance > 0) {
            // Compute the true token balance from non-empty reflected balances and update it
            // since we must use both reflected and true balances to make our reflected-to-total ratio even
            eternalStorage.setUint(entity, keccak256(abi.encodePacked("trueBalances", account)), convertFromReflectedToTrueAmount(reflectedBalance));
        }
        eternalStorage.setBool(entity, excludedFromRewards, true);
        eternalStorage.setAddressArrayValue(excludedAddresses, 0, account);
    }

    /**
     * @dev Allows a given wallet or contract's address to accrue rewards. (Admin and Fund only)
     * @param account The wallet or contract's address
     *
     * Requirements:
     * – Account must not already be accruing rewards.
     */
    function includeInReward(address account) external onlyAdminAndFund() {
        bytes32 excludedFromRewards = keccak256(abi.encodePacked("isExcludedFromRewards", account));
        require(eternalStorage.getBool(entity, excludedFromRewards), "Account is already included");
        for (uint i = 0; i < eternalStorage.lengthAddress(excludedAddresses); i++) {
            if (eternalStorage.getAddressArrayValue(excludedAddresses, i) == account) {
                eternalStorage.deleteAddress(excludedAddresses, i);
                // Set its deposit liabilities to 0 since we use the reserve balance for reward-accruing addresses
                eternalStorage.setUint(entity, keccak256(abi.encodePacked("trueBalances", account)), 0);
                eternalStorage.setBool(entity, excludedFromRewards, false);
                break;
            }
        }
    }

    /**
     * @dev Updates the address of the Eternal Liquidity contract
     * @param newContract The new address for the Eternal Liquidity contract
     */
    function setEternalTreasury(address newContract) external override onlyAdminAndFund() {
        address oldContract = address(eternalTreasury);
        emit UpdateEternalTreasury(oldContract, newContract);
        eternalTreasury = IEternalTreasury(newContract);
    }

    /**
     * @dev Attributes a given address to the Eternal Fund variable in this contract. (Admin and Fund only)
     * @param _fund The specified address of the designated fund
     */
    function designateFund(address _fund) external override onlyAdminAndFund() {
        eternalStorage.setBool(entity, keccak256(abi.encodePacked("isExcludedFromFees", fund())), false);
        eternalStorage.setBool(entity, keccak256(abi.encodePacked("isExcludedFromFees", _fund)), true);
        attributeFundRights(_fund);
    }
}