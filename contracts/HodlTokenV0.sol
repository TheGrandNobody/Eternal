//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@pangolindex/exchange-contracts/contracts/pangolin-core/interfaces/IPangolinFactory.sol";
import "@pangolindex/exchange-contracts/contracts/pangolin-periphery/interfaces/IPangolinRouter.sol";

/**
 * @title Contract for the HODL Token (HODLS)
 * @author Nobody (credits to OpenZeppelin for the IERC20 and IERC20Metadata interfaces)
 * @notice The HODL Token contract holds 
 */
contract HodlTokenV0 is Context, IERC20, IERC20Metadata, Ownable {

    // Keeps track of how much an address allows any other address to spend on its behalf
    mapping (address => mapping (address => uint256)) private allowances;
    // The reflected balances used to track dividend-accruing users' total balances
    mapping (address => uint256) private reflectedBalances;
    // The true balances used to track non-dividend-accruing addresses' total balances
    mapping (address => uint256) private trueBalances;
    // Keeps track of whether an address is excluded from dividends
    mapping (address => bool) private isExcludedFromReflections;
    // Keeps track of whether an address is excluded from transfer fees
    mapping (address => bool) private isExcludedFromFees;

    // Keeps track of all dividend-excluded addresses
    address[] private excludedAddresses;

    // The largest possible number in a 256-bit integer
    uint256 private constant MAX = ~uint256(0);
    // The true total token supply 
    uint256 private constant totalTokenSupply = 10**10 * 10**9;
    // The total token supply after taking reflections into account
    uint256 private totalReflectedSupply;
    uint256 private liquefactionRate;
    uint256 private burnRate;

    IPangolinRouter public immutable pangolinRouter;
    address public immutable pangolinPair;

    /**
     * @dev Sets the token ticker and token name. Mints the total supply to the contract deployer.
     */
    constructor () {
        // Initialize name, ticker symbol and total supply
        totalReflectedSupply = (MAX - (MAX % totalTokenSupply));
        reflectedBalances[msg.sender] = totalTokenSupply;

        // Create pair address
        IPangolinRouter _pangolinRouter = IPangolinRouter(0xE54Ca86531e17Ef3616d22Ca28b0D458b6C89106);
        pangolinPair = IPangolinFactory(_pangolinRouter.factory()).createPair(address(this), _pangolinRouter.WAVAX());

        // Initialize Pangolin Router
        pangolinRouter = _pangolinRouter;
    }

    /**
     * @dev Returns the name of the token. 
     */
    function name() public pure override returns (string memory) {
        return "HODL Token";
    }

    /**
     * @dev Returns the token ticker.
     */
    function symbol() public pure override returns (string memory) {
        return "HODLS";
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     */
    function decimals() public pure override returns (uint8) {
        return 9;
    }
    
    /**
     * @dev Returns the total supply of the HODL token.
     */
    function totalSupply() external view override returns (uint256){
        return totalTokenSupply;
    }

    /**
     * @dev Returns the balance of a given user's address.
     * @param account The address of the user
     */
    function balanceOf(address account) external view override returns (uint256){
        if (isExcludedFromReflections[account]) {
            return trueBalances[account];
        }
        return convertFromReflectedToTrueAmount(reflectedBalances[account]);
    }

    /**
     * @dev Returns the allowance of a given owner address for a given spender address.
     * @param owner The address of whom we are checking the allowance of
     * @param spender The address of whom we are checking the allowance for
     */
    function allowance(address owner, address spender) external view override returns (uint256){
        return allowances[owner][spender];
    }
    
    /**
     * @dev Returns whether a given wallet or contract's address is excluded from dividends.
     * @param account The wallet or contract's address
     */
    function isExcludedFromFee(address account) public view returns (bool) {
        return isExcludedFromFees[account];
    }

    /**
     * @dev Returns whether a given wallet or contract's address is excluded from transaction fees.
     * @param account The wallet or contract's address
     */
    function isExcludedFromReflection(address account) public view returns (bool) {
        return isExcludedFromReflections[account];
    }
    
    /**
     * @dev Excludes a given wallet or contract's address from obtaining dividends. (Owner only)
     * @param account The wallet or contract's address
     *
     * Requirements:
     * – Account must not already be excluded.
     */
    function excludeFromReward(address account) public onlyOwner() {
        require(!isExcludedFromReflections[account], "HodlTokenV0::excludeFromReward(): Account is already excluded.");
        if(reflectedBalances[account] > 0) {
            // Compute the true token balance and update it in deposit liabilities
            // since we use deposit liabilities for non-dividend-accruing addresses
            trueBalances[account] = convertFromReflectedToTrueAmount(reflectedBalances[account]);
        }
        isExcludedFromReflections[account] = true;
        excludedAddresses.push(account);
    }

    /**
     * @dev Includes a given wallet or contract's address into accruing dividends. (Owner only)
     * @param account The wallet or contract's address
     *
     * Requirements:
     * – Account must not already be included.
     */
    function includeInReward(address account) external onlyOwner() {
        require(isExcludedFromReflections[account], "HodlTokenV0::IncludeInReward(): Account is already included");
        for (uint256 i = 0; i < excludedAddresses.length; i++) {
            if (excludedAddresses[i] == account) {
                // Swap last address with current address we want to include so that we can delete it
                excludedAddresses[i] = excludedAddresses[excludedAddresses.length - 1];
                // Set its deposit liabilities to 0 since we use the reserve balance for dividend-accruing addresses
                trueBalances[account] = 0;
                excludedAddresses.pop();
                isExcludedFromReflections[account] = false;
                break;
            }
        }
    }
    
    /**
     * @dev Increases the allowance for a given spender address by a given amount.
     * @param spender The address whom we are increasing the allowance for
     * @param addedValue The amount by which we increase the allowance
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(msg.sender, spender, (allowances[msg.sender][spender] + addedValue));
        return true;
    }
    
    /**
     * @dev Decreases the allowance for a given spender address by a given amount.
     * @param spender The address whom we are decrease the allowance for
     * @param subtractedValue The amount by which we decrease the allowance
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(msg.sender, spender, (allowances[_msgSender()][spender] - subtractedValue));
        return true;
    }
    
    /**
     * @dev Translates a given amount of tokens into its reflected sum variant (with the transfer fee deducted if specified).
     * @param trueAmount The specified amount of tokens 
     * @param deductTransferFee Boolean – True if we deduct the transfer fee from the reflected sum variant. False otherwise.
     */
    function convertFromTrueToReflectedAmount(uint256 trueAmount, bool deductTransferFee) public view returns(uint256) {
        require(trueAmount <= totalTokenSupply, "HodlTokenV0::convertFromTrueToReflectedAmount(): Amount must be less than total token supply");
        if (!deductTransferFee) {
            (uint256 reflectedAmount,,,,) = getValues(trueAmount);
            return reflectedAmount;
        } else {
            (,uint256 reflectedTransferAmount,,,) = getValues(trueAmount);
            return reflectedTransferAmount;
        }
    }

    /**
     * @dev Translates a given reflected sum of tokens into the true amount of tokens it represents based on the current reserve rate.
     * @param reflectedAmount The specified reflected sum of tokens
     */
    function convertFromReflectedToTrueAmount(uint256 reflectedAmount) public view returns(uint256) {
        require(reflectedAmount <= totalReflectedSupply, "HodlTokenV0::convertFromReflectedToTrueAmount(): Amount must be less than total reflected supply");
        uint256 currentRate =  getRate();
        return reflectedAmount / currentRate;
    }

    /**
     * @dev Tranfers a given amount of HODLS to a given receiver address. Returns True if successful.
     * @param recipient The destination to which the HODLS are to be transferred
     * @param amount The amount of HODLS to be transferred
     */
    function transfer(address recipient, uint256 amount) external override returns (bool){
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    /**
     * @dev Sets the allowance for a given address to a given amount. Returns True if successful.
     * @param spender The address of whom we are changing the allowance for
     * @param amount The amount we are changing the allowance to
     */
    function approve(address spender, uint256 amount) external override returns (bool){
        _approve(msg.sender, spender, amount);
        return true;
    }

    /**
     * @dev Transfers a given amount of HODLS for a given sender address to a given recipient address.
     * @param sender The address whom we withdraw the HODLS from
     * @param recipient The address which shall receive the HODLS
     * @param amount The amount of HODLS which is being transferred
     */
    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = allowances[sender][msg.sender];
        require(currentAllowance >= amount, "HodlTokenV0::transferFrom(): transfer amount exceeds allowance");
        _approve(sender, msg.sender, currentAllowance - amount);

        return true;
    }

    /**
     * @dev Sets the allowance of a given owner address for a given spender address to a given amount.
     * @param owner The adress of whom we are changing the allowance of
     * @param spender The address of whom we are changing the allowance for
     * @param amount The amount which we change the allowance to
     */
    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "HodlTokenV0::_approve(): approve from the zero address");
        require(spender != address(0), "HodlTokenV0::_approve(): approve to the zero address");

        allowances[owner][spender] = amount;

        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Transfers a given amount of HODLS from a given sender's address to a given recipient's address.
     * Bottleneck for what transfer equation to use.
     * @param sender The address of whom the HODLS will be transferred from
     * @param recipient The address of whom the HODLS will be transferred to
     * @param amount The amount of HODLS to be transferred
     */
    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "HodlTokenV0::_transfer(): transfer from the zero address");
        require(recipient != address(0), "HodlTokenV0::_transfer(): transfer to the zero address");
        require(amount > 0, "HodlTokenV0::_transfer(): transfer amount must be greater than zero");

        if (isExcludedFromReflections[sender] && !isExcludedFromReflections[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!isExcludedFromReflections[sender] && isExcludedFromReflections[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        } else if (isExcludedFromReflections[sender] && isExcludedFromReflections[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }
    }

    /**
     * @dev Swaps a given amount of HODLS for AVAX using PangolinDEX. (Used for auto-liquidity swaps)
     * @param amount The amount of HODLS to be swapped for AVAX
     */
    function swapTokensForAVAX(uint256 amount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = pangolinRouter.WAVAX();

        _approve(address(this), address(pangolinRouter), amount);

        pangolinRouter.swapExactTokensForAVAXSupportingFeeOnTransferTokens(amount, 0, path, address(this), block.timestamp);
    }
    
    // Allows contract to receive AVAX tokens from Pangolin
    receive() external payable {}
}