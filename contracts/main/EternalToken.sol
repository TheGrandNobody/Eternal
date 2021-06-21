//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IEternalToken.sol";
import "../interfaces/IEternalFundV0.sol";
import "../inheritances/OwnableEnhanced.sol";

/**
 * @title Contract for the Eternal Token (ETRNL)
 * @author Nobody (me)
 * (credits to OpenZeppelin for initial framework and RFI for figuring out by far the most efficient way of implementing reward-distributing tokens)
 * @notice The Eternal Token contract holds all the deflationary, burn, reflect, funding and auto-liquidity provision mechanics
 */
contract EternalToken is IEternalToken, OwnableEnhanced {

    // Keeps track of all reward-excluded addresses
    address[] private excludedAddresses;

    // The reflected balances used to track reward-accruing users' total balances
    mapping (address => uint256) private reflectedBalances;
    // The true balances used to track non-reward-accruing addresses' total balances
    mapping (address => uint256) private trueBalances;
    // Keeps track of whether an address is excluded from rewards
    mapping (address => bool) private isExcludedFromRewards;
    // Keeps track of whether an address is excluded from transfer fees
    mapping (address => bool) private isExcludedFromFees;
    // Keeps track of how much an address allows any other address to spend on its behalf
    mapping (address => mapping (address => uint256)) private allowances;
    // The Eternal Fund interface
    IEternalFundV0 eternalFund;

    // The total ETRNL supply after taking reflections into account
    uint256 private totalReflectedSupply;
    // Threshold at which the contract swaps its ETRNL balance to provide liquidity (0.1% of total supply by default)
    uint64 private tokenLiquidityThreshold;
    // The true total ETRNL supply 
    uint64 private totalTokenSupply;

    // The percentage of the fee, taken at each transaction, that is stored in the EternalFund
    uint8 private fundingRate;
    // The percentage of the fee, taken at each transaction, that is burned
    uint8 private burnRate;
    // The percentage of the fee, taken at each transaction, that is redistributed to holders
    uint8 private redistributionRate;
    // The percentage of the fee taken at each transaction, that is used to auto-lock liquidity
    uint8 private liquidityProvisionRate;

    // Allows contract to receive AVAX tokens from Pangolin
    receive() external payable {}

    /**
     * @dev Initialize supplies and routers and create a pair. Mints total supply to the contract deployer. Exclude some addresses from fees and/or rewards.
     */
    constructor () {

        // The largest possible number in a 256-bit integer
        uint256 max = ~uint256(0);

        // Initialize total supplies, liquidity threshold and transfer total supply to the owner
        totalTokenSupply = (10**10) * (10**9);
        totalReflectedSupply = (max - (max % totalTokenSupply));
        tokenLiquidityThreshold = totalTokenSupply / 1000;
        reflectedBalances[_msgSender()] = totalReflectedSupply;

        // Exclude the owner from rewards and fees
        excludeFromReward(owner());
        isExcludedFromFees[owner()] = true;

        // Exclude this contract from rewards and fees
        excludeFromReward(address(this));
        isExcludedFromFees[address(this)] = true;

        // Exclude the burn address from rewards
        isExcludedFromRewards[address(0)];

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
     * @dev View the token ticker
     * @return The token ticker
     */
    function symbol() external pure override returns (string memory) {
        return "ETRNL";
    }

    /**
     * @dev View the maximum number of decimals for the Eternal token
     * @return The number of decimals
     */
    function decimals() external pure override returns (uint8) {
        return 9;
    }
    
    /**
     * @dev View the total supply of the Eternal token.
     * @return Returns the total ETRNL supply.
     */
    function totalSupply() external view override returns (uint256){
        return totalTokenSupply;
    }

    /**
     * @dev View the balance of a given user's address.
     * @param account The address of the user
     * @return The balance of the account
     */
    function balanceOf(address account) public view override returns (uint256){
        if (isExcludedFromRewards[account]) {
            return trueBalances[account];
        }
        return convertFromReflectedToTrueAmount(reflectedBalances[account]);
    }

    /**
     * @dev View the allowance of a given owner address for a given spender address.
     * @param owner The address of whom we are checking the allowance of
     * @param spender The address of whom we are checking the allowance for
     * @return The allowance of the owner for the spender
     */
    function allowance(address owner, address spender) external view override returns (uint256){
        return allowances[owner][spender];
    }

    /**
     * @dev View whether a given wallet or contract's address is excluded from transaction fees.
     * @param account The wallet or contract's address
     * @return Whether the account is excluded from transaction fees.
     */
    function isExcludedFromFee(address account) external view returns (bool) {
        return isExcludedFromFees[account];
    }

    /**
     * @dev View whether a given wallet or contract's address is excluded from rewards.
     * @param account The wallet or contract's address
     * @return Whether the account is excluded from rewards.
     */
    function isExcludedFromReward(address account) external view returns (bool) {
        return isExcludedFromRewards[account];
    }

/////–––««« IERC20/ERC20 functions »»»––––\\\\\
    
    /**
     * @dev Increases the allowance for a given spender address by a given amount.
     * @param spender The address whom we are increasing the allowance for
     * @param addedValue The amount by which we increase the allowance
     * @return True if the increase in allowance is successful
     */
    function increaseAllowance(address spender, uint256 addedValue) external virtual returns (bool) {
        _approve(_msgSender(), spender, (allowances[_msgSender()][spender] + addedValue));
        return true;
    }
    
    /**
     * @dev Decreases the allowance for a given spender address by a given amount.
     * @param spender The address whom we are decrease the allowance for
     * @param subtractedValue The amount by which we decrease the allowance
     * @return True if the decrease in allowance is successful
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) external virtual returns (bool) {
        _approve(_msgSender(), spender, (allowances[_msgSender()][spender] - subtractedValue));
        return true;
    }

    /**
     * @dev Tranfers a given amount of ETRNL to a given receiver address.
     * @param recipient The destination to which the ETRNL are to be transferred
     * @param amount The amount of ETRNL to be transferred
     * @return True if the transfer is successful.
     */
    function transfer(address recipient, uint256 amount) external override returns (bool){
        _transfer(_msgSender(), recipient, uint64(amount));
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
        _transfer(sender, recipient, uint64(amount));

        uint256 currentAllowance = allowances[sender][_msgSender()];
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

        allowances[owner][spender] = amount;

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

        (uint256 reflectedAmount, uint256 netReflectedTransferAmount, uint256 netTransferAmount) = getValues(amount);

        // Always update the reflected balances of sender and recipient
        reflectedBalances[sender] -= reflectedAmount;
        reflectedBalances[recipient] += netReflectedTransferAmount;

        // Update true balances for any non-reward-accruing accounts 
        trueBalances[sender] = isExcludedFromRewards[sender] ? (trueBalances[sender] - amount) : trueBalances[sender]; 
        trueBalances[recipient] = isExcludedFromRewards[recipient] ? (trueBalances[recipient] + netTransferAmount) : trueBalances[recipient]; 

        // Adjust the total reflected supply for the new fees
        // If the sender or recipient are excluded from fees, we ignore the fee altogether
        if (!isExcludedFromFees[sender] && !isExcludedFromFees[recipient]) {
            // Perform a burn based on the burn rate 
            _burn(address(this), uint64(amount) * burnRate / 100, reflectedAmount * burnRate / 100);
            // Redistribute based on the redistribution rate 
            totalReflectedSupply -= reflectedAmount * redistributionRate / 100;
            // Store ETRNL away in the EternalFund based on the funding rate
            reflectedBalances[fund()] += reflectedAmount * fundingRate / 100;
            // Provide liqudity to the ETRNL/AVAX pair on Pangolin based on the liquidity provision rate
            storeLiquidityFunds(sender, amount * liquidityProvisionRate / 100, reflectedAmount * liquidityProvisionRate / 100);
        }

        emit Transfer(sender, recipient, netTransferAmount);
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
    function burn(uint64 amount) external returns (bool) {
        address sender = _msgSender();
        require(sender != address(0), "Burn from the zero address");
        uint256 balance = balanceOf(sender);
        require(balance >= amount, "Burn amount exceeds balance");

        // Subtract the amounts from the sender before so we can reuse _burn elsewhere
        uint256 reflectedAmount = convertFromTrueToReflectedAmount(amount, false);
        reflectedBalances[sender] -= reflectedAmount;
        trueBalances[sender] = isExcludedFromRewards[sender] ? (trueBalances[sender] - amount) : trueBalances[sender];

        _burn(sender, amount, reflectedAmount);
        return true;
    }
    
    /**
     * @dev Burns the specified amount of ETRNL for a given sender by sending them to the 0x0 address.
     * @param sender The specified address burning ETRNL
     * @param amount The amount of ETRNL being burned
     * @param reflectedAmount The reflected equivalent of ETRNL being burned
     */
    function _burn(address sender, uint64 amount, uint256 reflectedAmount) private {
        // Send tokens to the 0x0 address
        reflectedBalances[address(0)] += reflectedAmount;
        trueBalances[address(0)] += amount;

        // Update supplies accordingly
        totalTokenSupply -= amount;
        totalReflectedSupply -= reflectedAmount;

        emit Transfer(sender, address(0), amount);
    }

/////–––««« Reward-redistribution functions »»»––––\\\\\

    /**
     * @dev Translates a given amount of ETRNL into its reflected sum variant (with the transfer fee deducted if specified).
     * @param amount The specified amount of ETRNL
     * @param deductTransferFee Boolean – True if we deduct the transfer fee from the reflected sum variant. False otherwise.
     * @return The reflected amount proportional to the given amount of ETRNL if False, else the fee-adjusted variant of said reflected amount
     *
     * Requirements:
     * 
     * - Given ETRNL amount cannot be greater than the total token supply
     */
    function convertFromTrueToReflectedAmount(uint256 amount, bool deductTransferFee) public view returns(uint256) {
        require(amount <= totalTokenSupply, "Amount exceeds total supply");
        if (!deductTransferFee) {
            (uint256 reflectedAmount,,) = getValues(amount);
            return reflectedAmount;
        } else {
            (,uint256 netReflectedTransferAmount,) = getValues(amount);
            return netReflectedTransferAmount;
        }
    }

    /**
     * @dev Translates a given reflected sum of ETRNL into the true amount of ETRNL it represents based on the current reserve rate.
     * @param reflectedAmount The specified reflected sum of ETRNL
     * @return The true amount of ETRNL representing by its reflected amount
     * Requirements:
     * 
     * - Given reflected ETRNL amount cannot be greater than the total reflected token supply
     */
    function convertFromReflectedToTrueAmount(uint256 reflectedAmount) public view returns(uint256) {
        require(reflectedAmount <= totalReflectedSupply, "Amount exceeds reflected supply");
        uint256 currentRate =  getReflectionRate();
        return reflectedAmount / currentRate;
    }

    /**
     * @dev Compute the reflected and net reflected transferred amounts and the net transferred amount from a given amount of ETRNL
     * @param trueAmount The specified amount of ETRNL
     * @return The reflected amount, the net reflected transfer amount, the actual net transfer amount, and the total reflected fees
     */
    function getValues(uint256 trueAmount) private view returns (uint256, uint256, uint256) {

        // Calculate the total fees and transfered amount after fees
        uint256 totalFees = (trueAmount * (liquidityProvisionRate + burnRate + fundingRate + redistributionRate)) / 100;
        uint256 netTransferAmount = trueAmount - totalFees;

        // Calculate the reflected amount, reflected total fees and reflected amount after fees
        uint256 currentRate = getReflectionRate();
        uint256 reflectedAmount = trueAmount * currentRate;
        uint256 reflectedTotalFees = totalFees * currentRate;
        uint256 netReflectedTransferAmount = reflectedAmount - reflectedTotalFees;
        
        return (reflectedAmount, netReflectedTransferAmount, netTransferAmount);
    }

    /**
     * @dev Computes the current rate used to inter-convert from the mathematically reflected space to the "true" or total space
     * @return The ratio of net reflected ETRNL to net total ETRNL
     */
    function getReflectionRate() private view returns(uint256) {
        (uint256 netReflectedSupply, uint256 netTokenSupply) = getNetSupplies();
        return netReflectedSupply / netTokenSupply;
    }

    /**
     * @dev Computes the net reflected and total token supplies (adjusted for non-reward-accruing accounts)
     * @return The adjusted reflected supply and adjusted total token supply
     */
    function getNetSupplies() private view returns(uint256, uint256) {
        uint256 netReflectedSupply = totalReflectedSupply;
        uint256 netTokenSupply = totalTokenSupply;  

        for (uint256 i = 0; i < excludedAddresses.length; i++) {
            // Failsafe for non-reward-accruing accounts owning too many tokens (highly unlikely; nonetheless possible)
            if (reflectedBalances[excludedAddresses[i]] > netReflectedSupply || trueBalances[excludedAddresses[i]] > netTokenSupply) {
                return (totalReflectedSupply, totalTokenSupply);
            }
            // Subtracting each excluded account from both supplies yields the adjusted supplies
            netReflectedSupply -= reflectedBalances[excludedAddresses[i]];
            netTokenSupply -= trueBalances[excludedAddresses[i]];
        }
        // In case there are no tokens left in circulation for reward-accruing accounts
        if (netTokenSupply == 0 || netReflectedSupply < (totalReflectedSupply / totalTokenSupply)){
            return (totalReflectedSupply, totalTokenSupply);
        }

        return (netReflectedSupply, netTokenSupply);
    }

    /**
     * @dev Sets the value of a given rate to a given rate type (Owner and Fund only)
     * @param newRate The specified new rate value
     * @param rate The type of the specified rate
     *
     * Requirements:
     *
     * - Rate type must be either Liquidity, Funding, Redistribution or Burn
     * - Rate value must be positive
     * - The sum of all rates cannot exceed 25 percent
     */
    function setRate(uint8 newRate, Rate rate) external override onlyOwnerAndFund() {
        require((uint(rate) >= 0 && uint(rate) <= 3), "Invalid rate type");
        require(newRate >= 0, "The new rate must be positive");

        uint256 oldRate;

        if (rate == Rate.Liquidity) {
            require((newRate + fundingRate + redistributionRate + burnRate) < 25, "Total rate exceeds 25%");
            oldRate = liquidityProvisionRate;
            liquidityProvisionRate = newRate;
        } else if (rate == Rate.Funding) {
            require((liquidityProvisionRate + newRate + redistributionRate + burnRate) < 25, "Total rate exceeds 25%");
            oldRate = fundingRate;
            fundingRate = newRate;
        } else if (rate == Rate.Redistribution) {
            require((liquidityProvisionRate + fundingRate + newRate + burnRate) < 25, "Total rate exceeds 25%");
            oldRate = redistributionRate;
            redistributionRate = newRate;
        } else {
            require((liquidityProvisionRate + fundingRate + redistributionRate + newRate) < 25, "Total rate exceeds 25%");
            oldRate = burnRate;
            burnRate = newRate;
        }

        emit UpdateRate(oldRate, newRate, rate);
    }

    /**
     * @dev Excludes a given wallet or contract's address from accruing rewards. (Owner only)
     * @param account The wallet or contract's address
     *
     * Requirements:
     * – Account must not already be excluded from rewards.
     */
    function excludeFromReward(address account) public onlyOwnerAndFund() {
        require(!isExcludedFromRewards[account], "Account is already excluded");
        if(reflectedBalances[account] > 0) {
            // Compute the true token balance from non-empty reflected balances and update it
            // since we must use both reflected and true balances to make our reflected-to-total ratio even
            trueBalances[account] =  convertFromReflectedToTrueAmount(reflectedBalances[account]);
        }
        isExcludedFromRewards[account] = true;
        excludedAddresses.push(account);
    }

    /**
     * @dev Allows a given wallet or contract's address to accrue rewards. (Owner only)
     * @param account The wallet or contract's address
     *
     * Requirements:
     * – Account must not already be accruing rewards.
     */
    function includeInReward(address account) external onlyOwnerAndFund() {
        require(isExcludedFromRewards[account], "Account is already included");
        for (uint i = 0; i < excludedAddresses.length; i++) {
            if (excludedAddresses[i] == account) {
                // Swap last address with current address we want to include so that we can delete it
                excludedAddresses[i] = excludedAddresses[excludedAddresses.length - 1];
                // Set its deposit liabilities to 0 since we use the reserve balance for reward-accruing addresses
                trueBalances[account] = 0;
                excludedAddresses.pop();
                isExcludedFromRewards[account] = false;
                break;
            }
        }
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
        reflectedBalances[address(this)] += reflectedAmount;
        trueBalances[address(this)] += amount;
        
        // Check whether the contract's balance threshold is reached; if so, initiate a liquidity swap
        uint256 contractBalance = balanceOf(address(this));
        if ((contractBalance >= tokenLiquidityThreshold) && (sender != eternalFund.viewPair())) {
            _transfer(address(this), fund(), contractBalance);
            eternalFund.provideLiquidity(contractBalance);
        }
    }

/////–––««« Owner/Fund-only functions »»»––––\\\\\

    /**
     * Attributes a given address to the Eternal Fund variable in this contract. (Owner and Fund only)
     * @param _fund The specified address of the designated fund
     */
    function designateFund(address _fund) external override onlyOwnerAndFund() {
        isExcludedFromFees[fund()] = false;
        eternalFund = IEternalFundV0(_fund);
        isExcludedFromFees[_fund] = true;
        attributeFundRights(_fund);
    }
}