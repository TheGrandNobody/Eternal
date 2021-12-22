//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "../interfaces/IEternalToken.sol";
import "../interfaces/ITimelock.sol";

/**
 * @title The Eternal Fund contract
 * @author Taken from Compound Finance (COMP) and tweaked/detailed by Nobody (me)
 * @notice The Eternal Fund serves as the governing body of Eternal
 */
contract EternalFund {

/////–––««« Variables: Interfaces and Addresses »»»––––\\\\\

    // The timelock interface
    ITimelock public timelock;
    // The Eternal token interface
    IEternalToken public eternal;
    // The address of the Governor Guardian
    address public guardian;

/////–––««« Variable: Voting »»»––––\\\\\

    // The total number of proposals
    uint256 public proposalCount;

    // Holds all proposal data
    struct Proposal {
        uint256 id;                              // Unique id for looking up a proposal
        address proposer;                        // Creator of the proposal
        uint256 eta;                             // The timestamp that the proposal will be available for execution, set once the vote succeeds
        address[] targets;                       // The ordered list of target addresses for calls to be made
        uint256[] values;                        // The ordered list of values (i.e. msg.value) to be passed to the calls to be made
        string[] signatures;                     // The ordered list of function signatures to be called
        bytes[] calldatas;                       // The ordered list of calldata to be passed to each call
        uint256 startTime;                       // The timestamp at which voting begins: holders must delegate their votes prior to this time
        uint256 endTime;                         // The timestamp at which voting ends: votes must be cast prior to this block
        uint256 startBlock;                      // The block at which voting began: holders must have delegated their votes prior to this block
        uint256 forVotes;                        // Current number of votes in favor of this proposal
        uint256 againstVotes;                    // Current number of votes in opposition to this proposal
        bool canceled;                           // Flag marking whether the proposal has been canceled
        bool executed;                           // Flag marking whether the proposal has been executed
        mapping (address => Receipt) receipts;   // Receipts of ballots for the entire set of voters
    }

    // Ballot receipt record for a voter
    struct Receipt {
        bool hasVoted;       // Whether or not a vote has been cast
        bool support;        // Whether or not the voter supports the proposal
        uint256 votes;        // The number of votes the voter had, which were cast
    }

    // Possible states that a proposal may be in
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    // The official record of all proposals ever proposed
    mapping (uint256 => Proposal) public proposals;
    // The latest proposal for each proposer
    mapping (address => uint256) public latestProposalIds;

/////–––««« Variables: Voting by signature »»»––––\\\\\

    // The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    // The EIP-712 typehash for the ballot struct used by the contract
    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,bool support)");

/////–––««« Events »»»––––\\\\\

    // Emitted when a new proposal is created
    event ProposalCreated(uint256 id, address proposer, address[] targets, uint256[] values, string[] signatures, bytes[] calldatas, uint256 startTime, uint256 endTime, string description);
    // Emitted when the first vote is cast in a proposal
    event StartBlockSet(uint256 proposalId, uint256 startBlock);
    // Emitted when a vote has been cast on a proposal
    event VoteCast(address voter, uint256 proposalId, bool support, uint256 votes);
    // Emitted when a proposal has been canceled
    event ProposalCanceled(uint256 id);

    // Emitted when a proposal has been queued in the Timelock
    event ProposalQueued(uint256 id, uint256 eta);
    // Emitted when a proposal has been executed in the Timelock
    event ProposalExecuted(uint256 id);

/////–––««« Constructor »»»––––\\\\\

    constructor (address _timelock, address _eternal, address _guardian) {
        timelock = ITimelock(_timelock);
        eternal = IEternalToken(_eternal);
        guardian = _guardian;
    }

/////–––««« Variable state-inspection functions »»»––––\\\\\
    /** 
     * @notice The number of votes required in order for a voter to become a proposer
     * @return 0.5 percent of the initial supply 
     */
    function proposalThreshold() public pure returns (uint256) { 
        return 5 * (10 ** 7) * (10 ** 18); // 50 000 000ETRNL = initially 0.5% (increases over time)
    } 

    /**
     * @notice View the maximum number of operations that can be included in a proposal
     * @return The maximum number of actions per proposal
     */
    function proposalMaxOperations() public pure returns (uint256) { 
        return 15; 
    }

    /**
     * @notice View the delay before voting on a proposal may take place, once proposed
     * @return 1 day (in seconds)
     */
    function votingDelay() public pure returns (uint256) { 
        return 1 days; 
    }

    /**
     * @notice The duration of voting on a proposal, in blocks
     * @return 3 days (in seconds)
     */
    function votingPeriod() public pure returns (uint256) { 
        return 3 days; 
    }

/////–––««« Governance logic functions »»»––––\\\\\

    /**
     * @notice Initiates a proposal
     * @param targets An ordered list of contract addresses used to make the calls
     * @param values A list of values passed in each call
     * @param signatures A list of function signatures used to make the calls
     * @param calldatas A list of function parameter hashes used to make the calls
     * @param description A description of the proposal
     * @return The current proposal count
     *
     * Requirements:
     * 
     * - Proposer must have a voting balance equal to at least 0.5 percent of the initial ETRNL supply
     * - All lists must have the same length
     * - Lists must contain at least one element but no more than 15 elements
     * - Proposer can only have one live proposal at a time
     */
    function propose(address[] memory targets, uint256[] memory values, string[] memory signatures, bytes[] memory calldatas, string memory description) public returns (uint256) {
        require(eternal.getPriorVotes(msg.sender, block.number - 1) > proposalThreshold(), "Vote balance below threshold");
        require(targets.length == values.length && targets.length == signatures.length && targets.length == calldatas.length, "Arity mismatch in proposal");
        require(targets.length != 0, "Must provide actions");
        require(targets.length <= proposalMaxOperations(), "Too many actions");

        uint256 latestProposalId = latestProposalIds[msg.sender];
        if (latestProposalId != 0) {
          ProposalState proposersLatestProposalState = state(latestProposalId);
          require(proposersLatestProposalState != ProposalState.Active && proposersLatestProposalState != ProposalState.Pending, "One live proposal per proposer");
        }

        uint256 startTime = block.timestamp + votingDelay();
        uint256 endTime = block.timestamp + votingPeriod() + votingDelay();

        proposalCount += 1;
        proposals[proposalCount].id = proposalCount;
        proposals[proposalCount].proposer = msg.sender;
        proposals[proposalCount].eta = 0;
        proposals[proposalCount].targets = targets;
        proposals[proposalCount].values = values;
        proposals[proposalCount].signatures = signatures;
        proposals[proposalCount].calldatas = calldatas;
        proposals[proposalCount].startTime = startTime;
        proposals[proposalCount].startBlock = 0;
        proposals[proposalCount].endTime = endTime;
        proposals[proposalCount].forVotes = 0;
        proposals[proposalCount].againstVotes = 0;
        proposals[proposalCount].canceled = false;
        proposals[proposalCount].executed = false;

        latestProposalIds[msg.sender] = proposalCount;

        emit ProposalCreated(proposalCount, msg.sender, targets, values, signatures, calldatas, startTime, endTime, description);
        return proposalCount;
    }

    /**
     * @notice Queues all of a given proposal's actions into the timelock contract
     * @param proposalId The id of the specified proposal
     *
     * Requirements:
     *
     * - The proposal needs to have passed
     */
    function queue(uint256 proposalId) public {
        require(state(proposalId) == ProposalState.Succeeded, "Proposal state must be Succeeded");
        Proposal storage proposal = proposals[proposalId];
        uint256 eta = block.timestamp + timelock.viewDelay();
        for (uint256 i = 0; i < proposal.targets.length; i++) {
            _queueOrRevert(proposal.targets[i], proposal.values[i], proposal.signatures[i], proposal.calldatas[i], eta);
        }
        proposal.eta = eta;
        emit ProposalQueued(proposalId, eta);
    }

    /**
     * @notice Queues an individual proposal action into the timelock contract
     * @param target The address of the contract whose function is being called
     * @param value The amount of AVAX being transferred in this transaction
     * @param signature The function signature of this proposal's action
     * @param data The function parameters of this proposal's action
     * @param eta The estimated minimum UNIX time (in seconds) at which this transaction is to be executed 
     * 
     * Requirements:
     *
     * - The transaction should not have been queued
     */
    function _queueOrRevert(address target, uint256 value, string memory signature, bytes memory data, uint256 eta) private {
        require(!timelock.queuedTransaction(keccak256(abi.encode(target, value, signature, data, eta))), "Proposal action already queued");
        timelock.queueTransaction(target, value, signature, data, eta);
    }

    /**
     * @notice Executes all of a given's proposal's actions
     * @param proposalId The id of the specified proposal
     * 
     * Requirements:
     *
     * - The proposal must already be in queue
     */
    function execute(uint256 proposalId) public payable {
        require(state(proposalId) == ProposalState.Queued, "Proposal is not queued");
        Proposal storage proposal = proposals[proposalId];
        proposal.executed = true;
        for (uint256 i = 0; i < proposal.targets.length; i++) {
            timelock.executeTransaction{value: proposal.values[i]}(proposal.targets[i], proposal.values[i], proposal.signatures[i], proposal.calldatas[i], proposal.eta);
        }
        emit ProposalExecuted(proposalId);
    }

    /**
     * @notice Cancels all of a given proposal's actions
     * @param proposalId The id of the specified proposal
     * 
     * Requirements:
     *
     * - The proposal should not have been executed
     * - The proposer's vote balance should be below the threshold
     */
    function cancel(uint proposalId) public {
        ProposalState _state = state(proposalId);
        require(_state != ProposalState.Executed, "Cannot cancel executed proposal");

        Proposal storage proposal = proposals[proposalId];
        require(eternal.getPriorVotes(proposal.proposer, block.number - 1) < proposalThreshold(), "Proposer above threshold");

        proposal.canceled = true;
        for (uint256 i = 0; i < proposal.targets.length; i++) {
            timelock.cancelTransaction(proposal.targets[i], proposal.values[i], proposal.signatures[i], proposal.calldatas[i], proposal.eta);
        }
        emit ProposalCanceled(proposalId);
    }

    /**
     * @notice View a given proposal's lists of actions
     * @param proposalId The id of the specified proposal
     * @return targets The proposal's targets
     * @return values The proposal's values
     * @return signatures The proposal's signatures
     * @return calldatas The proposal's calldatas
     */
    function getActions(uint256 proposalId) public view returns (address[] memory targets, uint256[] memory values, string[] memory signatures, bytes[] memory calldatas) {
        Proposal storage p = proposals[proposalId];
        return (p.targets, p.values, p.signatures, p.calldatas);
    }

    /**
     * @notice View a given proposal's ballot receipt for a given voter
     * @param proposalId The id of the specified proposal
     * @param voter The address of the specified voter
     * @return The ballot receipt of that voter for the proposal
     */
    function getReceipt(uint256 proposalId, address voter) public view returns (Receipt memory) {
        return proposals[proposalId].receipts[voter];
    }

    /**
     * @notice View the state of a given proposal
     * @param proposalId The id of the specified proposal
     * @return The state of the proposal
     *
     * Requirements:
     *
     * - Proposal must exist
     */
    function state(uint256 proposalId) public view returns (ProposalState) {
        require(proposalCount >= proposalId && proposalId > 0, "Invalid proposal id");
        Proposal storage proposal = proposals[proposalId];
        if (proposal.canceled) {
            return ProposalState.Canceled;
        } else if (block.timestamp <= proposal.startTime) {
            return ProposalState.Pending;
        } else if (block.timestamp <= proposal.endTime) {
            return ProposalState.Active;
        } else if (proposal.forVotes <= proposal.againstVotes) {
            return ProposalState.Defeated;
        } else if (proposal.eta == 0) {
            return ProposalState.Succeeded;
        } else if (proposal.executed) {
            return ProposalState.Executed;
        } else if (block.timestamp >= proposal.eta + timelock.viewGracePeriod()) {
            return ProposalState.Expired;
        } else {
            return ProposalState.Queued;
        }
    }

    /**
     * @notice Casts a vote for a given proposal
     * @param proposalId The id of the specified proposal
     * @param support Whether the user is in support of the proposal or not
     */
    function castVote(uint256 proposalId, bool support) public {
        return _castVote(msg.sender, proposalId, support);
    }

    /**
     * @notice Casts a vote through signature
     * @param proposalId The id of teh specified proposal
     * @param support Whether the user is in support of the proposal or not
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     * 
     * Requirements:
     *
     * - Must be a valid signature
     */
    function castVoteBySig(uint256 proposalId, bool support, uint8 v, bytes32 r, bytes32 s) public {
        uint chainId;
        // solhint-disable-next-line no-inline-assembly
        assembly { chainId := chainid() }

        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), chainId, address(this)));
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "Invalid signature");
        return _castVote(signatory, proposalId, support);
    }

    /**
     * @notice Casts a vote for a given voter and proposal 
     * @param voter The address of the specified voter
     * @param proposalId The id of the specified proposal
     * @param support Whether the voter is in support of the proposal or not
     *
     * Requirements:
     *
     * - Voting period for the proposal needs to be ongoing 
     * - The voter must not have already voted
     */
    function _castVote(address voter, uint256 proposalId, bool support) private {
        require(state(proposalId) == ProposalState.Active, "Voting is closed");
        Proposal storage proposal = proposals[proposalId];
        if (proposal.startBlock == 0) {
            proposal.startBlock = block.number - 1;
            emit StartBlockSet(proposalId, block.number);
        }
        Receipt storage receipt = proposal.receipts[voter];
        require(receipt.hasVoted == false, "Voter already voted");
        uint256 votes = eternal.getPriorVotes(voter, proposal.startBlock);

        if (support) {
            proposal.forVotes = proposal.forVotes + votes;
        } else {
            proposal.againstVotes = proposal.againstVotes + votes;
        }

        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = votes;

        emit VoteCast(voter, proposalId, support, votes);
    }

    /**
     * @notice Allow the Eternal Fund to take over control of the timelock contract
     *
     * Requirements:
     *
     * - Only callable by the current guardian
     */
    function __acceptFund() public {
        require(msg.sender == guardian, "Caller must be the guardian");
        timelock.acceptFund();
    }

    /**
     * @notice Renounce the role of guardianship
     *
     * Requirements:
     *
     * - Only callable by the current guardian
     */
    function __abdicate() public {
        require(msg.sender == guardian, "Caller must be the guardian");
        guardian = address(0);
    }

    /**
     * @notice Queues the transaction which will give governing power to the Eternal Fund 
     *
     * Requirements:
     *
     * - Only callable by the current guardian
     */
    function __queueSetTimelockPendingAdmin(address newPendingAdmin, uint256 eta) public {
        require(msg.sender == guardian, "Caller must be the guardian");
        timelock.queueTransaction(address(timelock), 0, "setPendingAdmin(address)", abi.encode(newPendingAdmin), eta);
    }

    /**
     * @notice Executes the transaction which will give governing power to the Eternal Fund 
     *
     * Requirements:
     *
     * - Only callable by the current guardian
     */
    function __executeSetTimelockPendingAdmin(address newPendingAdmin, uint256 eta) public {
        require(msg.sender == guardian, "Caller must be the guardian");
        timelock.executeTransaction(address(timelock), 0, "setPendingAdmin(address)", abi.encode(newPendingAdmin), eta);
    }
}