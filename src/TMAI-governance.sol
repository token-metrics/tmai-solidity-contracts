// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interface/ITimelock.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./utils/SignatureVerifier.sol";

/**
 * @title Token Metrics Governor Alpha
 * @dev This contract allows the community to create proposals and vote on them to govern the system. Proposals require a minimum TMAI holding to be created, and votes determine the outcome based on quorum and majority thresholds.
 */
contract GovernorAlpha is Initializable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20 for IERC20;
    /// @notice Contract name
    string public constant name = "Token Metrics Governor Alpha";


    uint256 public votingPeriod; // ~7 days in blocks
    uint256 public blocksPerDay; // Number of blocks per day
    uint256 public votingDelay; // Delay before voting starts
    uint256 public minProposalTimeIntervalSec; // Minimum time interval for new proposals
    uint256 public lastProposalTimeIntervalSec; // Last proposal time
    uint256 public lastProposal; // Last proposal ID
    uint256 public minProposalTMAIHolding; // Minimum TMAI holdings required to create a proposal
    uint256 public quorumPercentage; // Minimum percentage of token holders required to vote (e.g. 25%)
    uint256 public yesVoteThresholdPercentage; // YES votes must exceed NO votes by at least this percentage (e.g. 10%)
    uint256 public revenueSharePercent; // Percentage of revenue for distribution
    uint256 public buybackAndBurnPercent; // Percentage of revenue for buyback and burn

    address public admin; // Admin address
    address public baseStableCoin; // Stablecoin for revenue distribution

    TimelockInterface public timelock;
    SignatureVerifier public signatureVerifier;
    IERC20 public TMAI;

    uint256 public proposalCount;
    uint256 public totalTarget;
    uint256 public totalTokenHolders; // Store the current number of token holders

    struct Proposal {
        uint256 id; // Proposal ID
        address proposer; // Proposal creator
        uint256 eta; // Time after which the proposal can be executed
        address[] targets; // Target addresses
        uint256[] values; // Values for each target
        string[] signatures; // Function signatures to be called
        bytes[] calldatas; // Calldata for each call
        uint256 startBlock; // Block at which voting starts
        uint256 endBlock; // Block at which voting ends
        uint256 forVotes; // Number of votes in favor
        uint256 againstVotes; // Number of votes against
        uint256 totalVoters; // Total number of voters for the proposal
        bool canceled; // Whether the proposal was canceled
        bool executed; // Whether the proposal was executed
        mapping(address => Receipt) receipts; // Receipts of ballots for voters
    }

    struct Receipt {
        bool hasVoted; // Whether the voter has cast a vote
        bool support; // Whether the voter supports the proposal
        uint256 votes; // Number of votes cast
    }

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

    mapping(uint256 => Proposal) public proposals;
    mapping(address => uint256) public latestProposalIds;
    mapping(uint256 => uint256) public proposalCreatedTime;
    mapping(uint256 => bool) public isProposalQueued;

    /// @notice Events for key governance actions
    event ProposalCreated(
        uint256 id,
        address proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );
    event VoteCast(
        address voter,
        uint256 proposalId,
        bool support,
        uint256 votes
    );
    event VoteChanged(
        address voter,
        uint256 proposalId,
        bool support,
        uint256 votes
    );
    event ProposalCanceled(uint256 id);
    event ProposalQueued(uint256 id, uint256 eta);
    event ProposalExecuted(uint256 id);
    event RevenueDistributed(
        uint256 revenue,
        address buybackAndBurnReceiver,
        uint256 buybackAndBurn,
        address revenueShareReceiver,
        uint256 revenueShareAmount
    );

    /**
     * @notice Initialize the contract with necessary parameters
     * @param timelock_ The timelock contract address
     * @param TMAI_ The governance token address
     * @param _baseStableCoin The stablecoin address for revenue distribution
     * @param _signatureVerifier The signature verifier contract
     * @param _quorumPercentage The quorum percentage for voting
     * @param _yesVoteThresholdPercentage The threshold for YES votes to pass a proposal
     */
    function initialize(
        address timelock_,
        address TMAI_,
        address _baseStableCoin,
        address _signatureVerifier,
        uint256 _quorumPercentage,
        uint256 _yesVoteThresholdPercentage
    ) external initializer {
        require(timelock_ != address(0), "Zero Address");
        require(TMAI_ != address(0), "Zero Address");
        require(quorumPercentage <= 100 && quorumPercentage > 0, "Invalid quorum percentage");
        require(_baseStableCoin != address(0), "Zero Address");

        timelock = TimelockInterface(timelock_);
        TMAI = IERC20(TMAI_);
        minProposalTMAIHolding = 50000000e18;
        minProposalTimeIntervalSec = 1 days;
        votingDelay = 1;
        totalTarget = 3;
        votingPeriod = 2016000; // ~7 days in blocks, assuming 0.3s block time on Arbitrum
        blocksPerDay = 288000; // Assuming 0.3s block time on Arbitrum
        revenueSharePercent = 50;
        buybackAndBurnPercent = 50;
        quorumPercentage = _quorumPercentage;
        yesVoteThresholdPercentage = _yesVoteThresholdPercentage;
        admin = msg.sender;
        baseStableCoin = _baseStableCoin;
        signatureVerifier = SignatureVerifier(_signatureVerifier);
    }

    /**
     * @notice Update Quorum Value
     * @param _quorumPercentage New quorum Value.
     * @dev Update Quorum Votes
     */
    function updateQuorumValue(uint256 _quorumPercentage) external {
        require(
            msg.sender == address(timelock),
            "Call must come from Timelock."
        );
        require(quorumPercentage <= 100 && quorumPercentage > 0, "Invalid quorum percentage");

        quorumPercentage = _quorumPercentage;
    }

    /**
     * @notice Update Admin
     * @param _admin New Admin address.
     * @dev Update admin
     */
    function updateAdmin(address _admin) external {
        require(msg.sender == admin, "Call must come from Admin.");
        require(_admin != address(0), "Zero Address");
        admin = _admin;
    }

    /**
     * @notice Update Voting Period
     * @param _votingPeriod New voting period value.
     * @dev Update voting period value
     */
    function updateVotingPeriod(uint256 _votingPeriod) external {
        require(
            msg.sender == address(timelock),
            "Call must come from Timelock."
        );
        votingPeriod = _votingPeriod;
    }

    /**
     * @notice update Minimum  Proposal Time Interval Sec.
     * @param _minProposalTimeIntervalSec New minimum proposal interval.
     * @dev Update number of minimum Time for Proposal.
     */
    function updateMinProposalTimeIntervalSec(
        uint256 _minProposalTimeIntervalSec
    ) external {
        require(
            msg.sender == address(timelock),
            "Call must come from Timelock."
        );
        minProposalTimeIntervalSec = _minProposalTimeIntervalSec;
    }

    /**
     * @notice update Revenue Share Percent.
     * @param _newRevenueSharePercent New Revenue Share Percent.
     * @dev Update percentage for revenue share.
     */

    function updateRevenueSharePercent(
        uint256 _newRevenueSharePercent
    ) external {
        require(
            msg.sender == address(timelock),
            "Call must come from Timelock."
        );
        require(
            _newRevenueSharePercent <= 100,
            "Revenue Share Percent should be less than 100"
        );
        revenueSharePercent = _newRevenueSharePercent;
        buybackAndBurnPercent = 100 - _newRevenueSharePercent;
    }

    /**
     * @notice update Buyback And Burn Percent
     * @param _newBuybackAndBurnPercent New Buyback And Burn Percent.
     * @dev Update percentage for Buyback And Burn.
     */

    function updateBuybackAndBurnPercent(
        uint256 _newBuybackAndBurnPercent
    ) external {
        require(
            msg.sender == address(timelock),
            "Call must come from Timelock."
        );
        require(
            _newBuybackAndBurnPercent <= 100,
            "Revenue Share Percent should be less than 100"
        );
        buybackAndBurnPercent = _newBuybackAndBurnPercent;
        revenueSharePercent = 100 - _newBuybackAndBurnPercent;
    }

    /**
     * @notice Update number of target.
     * @param _totalTarget New maxium target.
     * @dev Update number of maxium target.
     */

    function updateTotalTarget(uint256 _totalTarget) external {
        require(
            msg.sender == address(timelock),
            "Call must come from Timelock."
        );
        require(_totalTarget <= 10, "Target count too high");
        totalTarget = _totalTarget;
    }

    function _acceptAdmin() external {
        timelock.acceptAdmin();
    }

    /**
     * @notice Create a new proposal
     * @param targets Target addresses
     * @param values Values (ether) to send
     * @param signatures Function signatures to call
     * @param calldatas Parameters in calldata
     * @param description Description of the proposal
     * @return The ID of the newly created proposal
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) public returns (uint256) {
        require(
            TMAI.balanceOf(msg.sender) >= minProposalTMAIHolding,
            "Insufficient TMAI holdings"
        );
        require(
            targets.length == values.length &&
                targets.length == signatures.length &&
                targets.length == calldatas.length,
            "Invalid input lengths"
        );
        require(targets.length != 0, "Must provide actions");
        require(targets.length <= totalTarget, "Too many actions");

        uint256 timeSinceLastProposal = block.timestamp -
            lastProposalTimeIntervalSec;
        require(
            timeSinceLastProposal >= minProposalTimeIntervalSec,
            "Proposal too soon"
        );

        uint256 latestProposalId = latestProposalIds[msg.sender];
        if (latestProposalId != 0) {
            ProposalState proposersLatestProposalState = state(
                latestProposalId
            );
            require(
                proposersLatestProposalState != ProposalState.Active &&
                    proposersLatestProposalState != ProposalState.Pending,
                "Active or pending proposal exists"
            );
        }

        uint256 proposalId = setProposalDetail(
            targets,
            values,
            signatures,
            calldatas,
            description
        );
        return proposalId;
    }

    /**
     * @dev Internal function to set proposal details
     */
    function setProposalDetail(
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) internal returns (uint256) {
        uint256 startBlock = block.number +
            votingDelay;
        uint256 endBlock = startBlock + votingPeriod;

        proposalCount++;
        Proposal storage newProposal = proposals[proposalCount];
        newProposal.id = proposalCount;
        newProposal.proposer = msg.sender;
        newProposal.startBlock = startBlock;
        newProposal.endBlock = endBlock;
        newProposal.targets = targets;
        newProposal.values = values;
        newProposal.signatures = signatures;
        newProposal.calldatas = calldatas;

        proposalCreatedTime[proposalCount] = block.number;
        latestProposalIds[msg.sender] = newProposal.id;
        lastProposalTimeIntervalSec = block.timestamp;

        emit ProposalCreated(
            newProposal.id,
            msg.sender,
            targets,
            values,
            signatures,
            calldatas,
            startBlock,
            endBlock,
            description
        );
        return newProposal.id;
    }

    /**
     * @notice Queue a proposal that has passed
     * @param proposalId The ID of the proposal to queue
     */
    function queue(uint256 proposalId) external {
        require(
            state(proposalId) == ProposalState.Succeeded,
            "Proposal not succeeded"
        );
        Proposal storage proposal = proposals[proposalId];
        uint256 eta = block.timestamp + timelock.delay();

        for (uint256 i = 0; i < proposal.targets.length; i++) {
            _queueOrRevert(
                proposal.targets[i],
                proposal.values[i],
                proposal.signatures[i],
                proposal.calldatas[i],
                eta
            );
        }
        proposal.eta = eta;
        isProposalQueued[proposalId] = true;
        emit ProposalQueued(proposalId, eta);
    }

    /**
     * @dev Internal function to queue or revert proposal
     */
    function _queueOrRevert(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 eta
    ) internal {
        require(
            !timelock.queuedTransactions(
                keccak256(abi.encode(target, value, signature, data, eta))
            ),
            "Action already queued"
        );
        timelock.queueTransaction(target, value, signature, data, eta);
    }

    /**
     * @notice Execute a proposal after it is queued
     * @param proposalId The ID of the proposal to execute
     */
    function execute(uint256 proposalId) external payable {
        require(
            state(proposalId) == ProposalState.Queued,
            "Proposal not queued"
        );
        Proposal storage proposal = proposals[proposalId];
        proposal.executed = true;
        for (uint256 i = 0; i < proposal.targets.length; i++) {
            timelock.executeTransaction{value: proposal.values[i]}(
                proposal.targets[i],
                proposal.values[i],
                proposal.signatures[i],
                proposal.calldatas[i],
                proposal.eta
            );
        }
        lastProposal = proposalId;
        emit ProposalExecuted(proposalId);
    }

    /**
     * @notice Cancel a proposal
     * @param proposalId The ID of the proposal to cancel
     */
    function cancel(uint256 proposalId) external {
        ProposalState _state = state(proposalId);
        require(_state != ProposalState.Executed, "Proposal already executed");

        Proposal storage proposal = proposals[proposalId];
        require(msg.sender == proposal.proposer, "Only proposer can cancel");

        proposal.canceled = true;
        for (uint256 i = 0; i < proposal.targets.length; i++) {
            timelock.cancelTransaction(
                proposal.targets[i],
                proposal.values[i],
                proposal.signatures[i],
                proposal.calldatas[i],
                proposal.eta
            );
        }

        emit ProposalCanceled(proposalId);
    }

    /**
     * @notice Get Actions details
     * @param proposalId Proposal Id.
     * @dev Get the details of Functions that will be called.
     */

    function getActions(
        uint256 proposalId
    )
        external
        view
        returns (
            address[] memory targets,
            uint256[] memory values,
            string[] memory signatures,
            bytes[] memory calldatas
        )
    {
        Proposal storage p = proposals[proposalId];
        return (p.targets, p.values, p.signatures, p.calldatas);
    }

    /**
     * @notice Get Receipt
     * @param proposalId Proposal Id.
     * @param voter Voter address
     * @dev Get the details of voted on a particular proposal for a user.
     */

    function getReceipt(
        uint256 proposalId,
        address voter
    ) external view returns (Receipt memory) {
        return proposals[proposalId].receipts[voter];
    }

    /**
     * @notice Update the signature verifier contract address. Only the admin can call this.
     */
    function updateSignatureVerifier(address _signatureVerifier) external {
        require(msg.sender == admin, "Call must come from admin.");
        require(_signatureVerifier != address(0), "Zero Address.");
        signatureVerifier = SignatureVerifier(_signatureVerifier);
    }

    /**
     * @notice Get the voting status for a specific voter on a specific proposal.
     * @param _voter The address of the voter.
     * @param proposalId The ID of the proposal.
     * @return True if the voter has voted on the proposal, false otherwise.
     */
    function getVotingStatus(
        address _voter,
        uint256 proposalId
    ) external view returns (bool) {
        return proposals[proposalId].receipts[_voter].hasVoted;
    }

    /**
     * @notice Get the state of a proposal
     * @param proposalId The ID of the proposal
     * @return The current state of the proposal
     */
    function state(uint256 proposalId) public view returns (ProposalState) {
        require(
            proposalCount >= proposalId && proposalId > 0,
            "Invalid proposal ID"
        );

        Proposal storage proposal = proposals[proposalId];

        // Check if the proposal is canceled
        if (proposal.canceled) {
            return ProposalState.Canceled;
        }

        // Check if the proposal is already executed
        if (proposal.executed) {
            return ProposalState.Executed;
        }

        // Check if the proposal has not yet started
        if (block.number <= proposal.startBlock) {
            return ProposalState.Pending;
        }

        // Check if the proposal is still active (voting is ongoing)
        if (block.number <= proposal.endBlock) {
            return ProposalState.Active;
        }

        // Check if the proposal failed to meet the quorum or the YES vote threshold
        uint256 requiredQuorum = quorumVotes();
        uint256 requiredYesPercentage = proposal
            .againstVotes
            .mul(yesVoteThresholdPercentage)
            .div(100);

        if (
            proposal.totalVoters < requiredQuorum ||
            proposal.forVotes < proposal.againstVotes.add(requiredYesPercentage)
        ) {
            return ProposalState.Defeated;
        }

        // Check if the proposal succeeded but not yet queued for execution
        if (
            proposal.eta == 0 &&
            block.timestamp >= proposalCreatedTime[proposalId] + 1 days
        ) {
            return ProposalState.Succeeded;
        }

        // Check if the proposal is queued for execution
        if (block.timestamp >= proposal.eta + timelock.GRACE_PERIOD()) {
            return ProposalState.Expired;
        }

        return ProposalState.Queued;
    }

    /**
     * @dev Calculate the minimum number of votes required to reach quorum
     * @return The number of votes required to reach quorum
     */
    function quorumVotes() public view returns (uint256) {
        return totalTokenHolders.mul(quorumPercentage).div(100);
    }

    /**
     * @notice Cast a vote for a proposal
     * @param signature The signature of the voter
     * @dev Cast a vote for a proposal and update total token holders accordingly
     */
    function castVote(SignatureVerifier.Signature memory signature) external {
        SignatureVerifier.GovernanceMessage memory message = signatureVerifier
            .verifyGovernanceSignature(signature);

        // Before casting vote, update total token holders
        totalTokenHolders = message.totalTokenHolders;

        _castVote(
            message.userAddress,
            message.proposalId,
            message.support,
            message.averageBalance
        );
    }

    /**
     * @notice Cast a vote for a proposal
     * @param proposalId The ID of the proposal
     * @param support The support value of the vote
     * @param averageBalance The average balance of the voter
     * @dev Cast a vote for a proposal
     */
    function _castVote(
        address voter,
        uint256 proposalId,
        bool support,
        uint256 averageBalance
    ) internal {
        require(
            state(proposalId) == ProposalState.Active,
            "GovernorAlpha::_castVote: voting is closed"
        );

        Proposal storage proposal = proposals[proposalId];
        Receipt storage receipt = proposal.receipts[voter];

        // Cast vote if the voter hasn't voted yet
        if (!receipt.hasVoted) {
            if (support) {
                proposal.forVotes += averageBalance;
            } else {
                proposal.againstVotes += averageBalance;
            }
            proposal.totalVoters++;
            receipt.hasVoted = true;
            receipt.support = support;
            receipt.votes = averageBalance;
            emit VoteCast(voter, proposalId, support, averageBalance);
        } else {
            // Change the vote if it's different from the previous vote
            require(
                support != receipt.support,
                "GovernorAlpha::_castVote: voter already voted"
            );
            if (support) {
                proposal.againstVotes -= receipt.votes;
                proposal.forVotes += averageBalance;
            } else {
                proposal.forVotes -= receipt.votes;
                proposal.againstVotes += averageBalance;
            }
            receipt.support = support;
            receipt.votes = averageBalance;
            emit VoteChanged(voter, proposalId, support, averageBalance);
        }
    }

    /**
     * @notice Distribute revenue between buyback and burn and revenue share
     * @param receiverBuyBackandBurn The address to receive buyback and burn funds
     * @param receiverRevenueShare The address to receive revenue share funds
     */
    function distributeRevenue(
        address receiverBuyBackandBurn,
        address receiverRevenueShare
    ) external {
        require(msg.sender == admin, "Only admin can distribute revenue");
        uint256 revenue = IERC20(baseStableCoin).balanceOf(address(this));
        require(revenue > 0, "No revenue to distribute");
        uint256 buyBackandBurnAmount = revenue.mul(buybackAndBurnPercent).div(
            100
        );
        uint256 revenueShareAmount = revenue.sub(buyBackandBurnAmount);
        IERC20(baseStableCoin).safeTransfer(
            receiverBuyBackandBurn,
            buyBackandBurnAmount
        );
        IERC20(baseStableCoin).safeTransfer(
            receiverRevenueShare,
            revenueShareAmount
        );
        emit RevenueDistributed(
            revenue,
            receiverBuyBackandBurn,
            buyBackandBurnAmount,
            receiverRevenueShare,
            revenueShareAmount
        );
    }
}
