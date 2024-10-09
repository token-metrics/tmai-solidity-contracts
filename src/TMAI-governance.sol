// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interface/ITimelock.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@arbitrum/nitro-contracts/src/precompiles/ArbSys.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./utils/SignatureVerifier.sol";

contract GovernorAlpha is Initializable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20 for IERC20;

    /// The name of this contract
    string public constant name = "Token Metrics Governor Alpha";

    address public constant ARBSYS_ADDRESS =
        0x0000000000000000000000000000000000000064;

    uint256 private quorumVote;

    uint256 private minVoterCount;

    /// The duration of voting on a proposal, in blocks
    uint256 public votingPeriod; // ~7 days in blocks

    // Number of blocks per day
    uint256 public blocksPerDay;

    // Minimum time interval for proposal
    uint256 public minProposalTimeIntervalSec;

    // Last proposal time interval
    uint256 public lastProposalTimeIntervalSec;

    // Last proposal id
    uint256 public lastProposal;

    address public admin;

    address public baseStableCoin;

    /// @notice The number of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed
    function quorumVotes() public view returns (uint256) {
        return quorumVote;
    }

    /// @notice The maximum number of actions that can be included in a proposal
    function proposalMaxOperations() public pure returns (uint256) {
        return 10;
    } // 10 actions

    /// @notice The delay before voting on a proposal may take place, once proposed
    function votingDelay() public pure returns (uint256) {
        return 1;
    } // 1 block

    /// @notice Minimum number of voters
    function minVotersCount() external view returns (uint256) {
        return minVoterCount;
    }

    /// @notice The address of the TMAI Protocol Timelock
    TimelockInterface public timelock;

    /// @notice Signature Verifier
    SignatureVerifier public signatureVerifier;

    /// @notice The address of the TMAI governance token
    IERC20 public TMAI;

    /// @notice The total number of proposals
    uint256 public proposalCount;

    /// @notice The total number of targets.
    uint256 public totalTarget;

    /// @notice Percent fort revenue share
    uint256 public revenueSharePercent;

    /// @notice Percent to buyback and burn
    uint256 public buybackAndBurnPercent;

    /// @notice voter info
    struct VoterInfo {
        mapping(address => bool) voterAddress;
        uint256 voterCount;
        uint256 governors;
    }

    struct Proposal {
        /// @notice Unique id for looking up a proposal
        uint256 id;
        /// @notice Creator of the proposal
        address proposer;
        /// @notice The timestamp that the proposal will be available for execution, set once the vote succeeds
        uint256 eta;
        /// @notice the ordered list of target addresses for calls to be made
        address[] targets;
        /// @notice The ordered list of values (i.e. msg.value) to be passed to the calls to be made
        uint256[] values;
        /// @notice The ordered list of function signatures to be called
        string[] signatures;
        /// @notice The ordered list of calldata to be passed to each call
        bytes[] calldatas;
        /// @notice The block at which voting begins: holders must delegate their votes prior to this block
        uint256 startBlock;
        /// @notice The block at which voting ends: votes must be cast prior to this block
        uint256 endBlock;
        /// @notice Current number of votes in favor of this proposal
        uint256 forVotes;
        /// @notice Current number of votes in opposition to this proposal
        uint256 againstVotes;
        /// @notice Flag marking whether the proposal has been canceled
        bool canceled;
        /// @notice Flag marking whether the proposal has been executed
        bool executed;
        /// @notice Receipts of ballots for the entire set of voters
        mapping(address => Receipt) receipts;
    }

    /// @notice Track Time proposal is created.
    mapping(uint256 => uint256) public proposalCreatedTime;

    /// @notice Track total proposal user voted on.
    mapping(address => uint256) public proposalVoted;

    /// @notice Ballot receipt record for a voter
    struct Receipt {
        /// @notice Whether or not a vote has been cast
        bool hasVoted;
        /// @notice Whether or not the voter supports the proposal
        bool support;
        /// @notice The number of votes the voter had, which were cast
        uint256 votes;
    }

    /// @notice Possible states that a proposal may be in
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

    /// @notice The record of all voters with proposal id
    mapping(uint256 => VoterInfo) public votersInfo;

    /// @notice The record of all proposals ever proposed
    mapping(uint256 => Proposal) public proposals;

    /// @notice The latest proposal for each proposer
    mapping(address => uint256) public latestProposalIds;

    mapping(uint256 => bool) public isProposalQueued;

    /// @notice An event emitted when a new proposal is created
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

    /// @notice An event emitted when a vote has been cast on a proposal
    event VoteCast(
        address voter,
        uint256 proposalId,
        bool support,
        uint256 votes
    );

    /// @notice An event emitted when a user changes their vote on a proposal
    event VoteChanged(
        address voter,
        uint256 proposalId,
        bool support,
        uint256 votes
    );

    /// @notice An event emitted when a proposal has been canceled
    event ProposalCanceled(uint256 id);

    /// @notice An event emitted when a proposal has been queued in the Timelock
    event ProposalQueued(uint256 id, uint256 eta);

    /// @notice An event emitted when a proposal has been executed in the Timelock
    event ProposalExecuted(uint256 id);

    /// @notice An event emitted when a revenue is distributed for Revenue Share and Buyback and Burn
    event RevenueDistributed(
        uint256 revenue,
        address buybackAndBurnReceiver,
        uint256 buybackAndBurn,
        address revenueShareReceiver,
        uint256 revenueShareAmount
    );
    

    function initialize(
        address timelock_,
        address TMAI_,
        address _baseStableCoin,
        address _signatureVerifier
    ) external initializer {
        require(timelock_ != address(0), "Zero Address");
        require(TMAI_ != address(0), "Zero Address");
        timelock = TimelockInterface(timelock_);
        TMAI = IERC20(TMAI_);
        quorumVote = 40e18;
        minVoterCount = 1;
        minProposalTimeIntervalSec = 1 days;
        totalTarget = 3;
        votingPeriod = 2016000; // ~7 days in blocks, assuming 0.3s block time on Arbitrum
        blocksPerDay = 288000; // Assuming 0.3s block time on Arbitrum
        revenueSharePercent = 50;
        buybackAndBurnPercent = 50;
        admin = msg.sender;
        baseStableCoin = _baseStableCoin;
        signatureVerifier = SignatureVerifier(_signatureVerifier);
    }
    /**
     * @notice Update Quorum Value
     * @param _quorumValue New quorum Value.
     * @dev Update Quorum Votes
     */
    function updateQuorumValue(uint256 _quorumValue) external {
        require(
            msg.sender == address(timelock),
            "Call must come from Timelock."
        );
        quorumVote = _quorumValue;
    }

    /**
     * @notice Update Admin
     * @param _admin New Admin address.
     * @dev Update admin
     */
    function updateAdmin(address _admin) external {
        require(msg.sender == admin, "Call must come from Admin.");
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
     * @notice Update Min Voter Value
     * @param _minVotersValue New minimum Votes Value.
     * @dev Update nummber of minimum voters
     */

    function updateMinVotersValue(uint256 _minVotersValue) external {
        require(
            msg.sender == address(timelock),
            "Call must come from Timelock."
        );
        minVoterCount = _minVotersValue;
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
        totalTarget = _totalTarget;
    }

    function _acceptAdmin() external {
        timelock.acceptAdmin();
    }

    /**
     * @notice Create a new Proposal
     * @param targets Target contract whose functions will be called.
     * @param values Amount of ether required for function calling.
     * @param signatures Function that will be called.
     * @param calldatas Paramete that will be passed in function paramt in bytes format.
     * @param description Description about proposal.
     * @dev Create new proposal. Her only top stakers can create proposal and Need to submit 50000000 TMAIa tokens to create proposal
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) public returns (uint256) {
        // Check if entered configuration is correct or not.
        // require(timelock.getL2GovernanceContract(chain) != address(0), "GovernorAlpha::propose: Governance Contract not set for chain");
        require(
            targets.length <= totalTarget,
            "GovernorAlpha::propose: Target must be in range"
        );
        require(
            targets.length == values.length &&
                targets.length == signatures.length &&
                targets.length == calldatas.length,
            "GovernorAlpha::propose: proposal function information arity mismatch"
        );
        require(
            targets.length != 0,
            "GovernorAlpha::propose: must provide actions"
        );
        require(
            targets.length <= proposalMaxOperations(),
            "GovernorAlpha::propose: too many actions"
        );

        // @Todo: Check User for eligibility to create proposal

        // Check the minimum proposal that can be created in a single day.
        uint256 timeSinceLastProposal = block.timestamp -
            lastProposalTimeIntervalSec;

        require(
            timeSinceLastProposal >= minProposalTimeIntervalSec,
            "GovernorAlpha::propose: Only one proposal can be created in one day"
        );

        // Check if caller has active proposal or not. If so previous proposal must be accepted or failed first.
        uint256 latestProposalId = latestProposalIds[msg.sender];
        if (latestProposalId != 0) {
            ProposalState proposersLatestProposalState = state(
                latestProposalId
            );
            require(
                proposersLatestProposalState != ProposalState.Active,
                "GovernorAlpha::propose: one live proposal per proposer, found an already active proposal"
            );
            require(
                proposersLatestProposalState != ProposalState.Pending,
                "GovernorAlpha::propose: one live proposal per proposer, found an already pending proposal"
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
     * @dev Internal function for creating proposal parameter details is similar to propose functions.
     */

    function setProposalDetail(
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) internal returns (uint256) {
        // Set voting time for proposal.
        uint256 startBlock = ArbSys(ARBSYS_ADDRESS).arbBlockNumber() +
            votingDelay();
        uint256 endBlock = startBlock + votingPeriod;

        proposalCount++;

        Proposal storage newProposal = proposals[proposalCount];

        newProposal.id = proposalCount;
        newProposal.proposer = msg.sender;
        newProposal.eta = 0;
        newProposal.targets = targets;
        newProposal.values = values;
        newProposal.signatures = signatures;
        newProposal.calldatas = calldatas;
        newProposal.startBlock = startBlock;
        newProposal.endBlock = endBlock;
        newProposal.forVotes = 0;
        newProposal.againstVotes = 0;
        newProposal.canceled = false;
        newProposal.executed = false;

        // Update details for proposal.
        proposalCreatedTime[proposalCount] = ArbSys(ARBSYS_ADDRESS)
            .arbBlockNumber();

        latestProposalIds[newProposal.proposer] = newProposal.id;
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
     * @notice Queue your proposal.
     * @param proposalId Proposal Id.
     * @dev Once proposal is accepted put them in queue over timelock. Proposal can only be put in queue if it is succeeded and crossed minimum voter.
     */

    function queue(uint256 proposalId) external {
        require(
            state(proposalId) == ProposalState.Succeeded,
            "GovernorAlpha::queue: proposal can only be queued if it is succeeded"
        );
        require(
            votersInfo[proposalId].voterCount >= minVoterCount,
            "GovernorAlpha::queue: proposal require atleast min governers quorum"
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
     * @dev Internal function called by queue to check if proposal can be queued or not.
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
            "GovernorAlpha::_queueOrRevert: proposal action already queued at eta"
        );
        timelock.queueTransaction(target, value, signature, data, eta);
    }

    /**
     * @notice Execute your proposal.
     * @param proposalId Proposal Id.
     * @dev Once queue time is over you can execute proposal fucntion from here.
     */

    function execute(uint256 proposalId) external payable {
        require(
            state(proposalId) == ProposalState.Queued,
            "GovernorAlpha::execute: proposal can only be executed if it is queued"
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
     * @notice Cancel your proposal.
     * @param proposalId Proposal Id.
     * @dev If proposal is not executed you can cancel that proposal from here.
     */

    function cancel(uint256 proposalId) external {
        ProposalState _state = state(proposalId);
        require(
            _state != ProposalState.Executed,
            "GovernorAlpha::cancel: cannot cancel executed proposal"
        );

        Proposal storage proposal = proposals[proposalId];

        require(
            msg.sender == proposal.proposer,
            "GovernorAlpha::cancel: Only creator can cancel"
        );

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
        require(
            msg.sender == admin,
            "GovernorAlpha::updateSignatureVerifier: Call must come from admin."
        );
        require(
            _signatureVerifier != address(0),
            "GovernorAlpha::updateSignatureVerifier: Zero Address."
        );
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
     * @notice Get state of proposal
     * @param proposalId Proposal Id.
     * @dev Check the status of proposal
     */

    function state(uint256 proposalId) public view returns (ProposalState) {
        require(
            proposalCount >= proposalId && proposalId > 0,
            "GovernorAlpha::state: invalid proposal id"
        );

        Proposal storage proposal = proposals[proposalId];

        bool checkifMinGovenor = votersInfo[proposalId].governors >= 33;
        bool checkFastVote = checkfastvote(proposalId);

        uint256 percentage = 10;

        if (
            checkFastVote && checkifMinGovenor && !isProposalQueued[proposalId]
        ) {
            return ProposalState.Succeeded;
        }
        if (proposal.canceled) {
            return ProposalState.Canceled;
        }
        if (
            ArbSys(ARBSYS_ADDRESS).arbBlockNumber() <= proposal.startBlock &&
            proposal.eta == 0
        ) {
            return ProposalState.Pending;
        }
        if (
            ArbSys(ARBSYS_ADDRESS).arbBlockNumber() <= proposal.endBlock &&
            proposal.eta == 0
        ) {
            return ProposalState.Active;
        }
        if (
            (proposal.forVotes <= proposal.againstVotes ||
                proposal.forVotes < quorumVotes()) && proposal.eta == 0
        ) {
            return ProposalState.Defeated;
        }
        if (proposal.eta == 0) {
            if (checkifMinGovenor) {
                if (proposal.againstVotes == 0) {
                    return ProposalState.Succeeded;
                }
                uint256 votePercentage = ((proposal.forVotes -
                    proposal.againstVotes) * 100) / proposal.againstVotes;
                if (votePercentage > percentage) {
                    return ProposalState.Succeeded;
                }
            }
            return ProposalState.Defeated;
        }
        if (proposal.executed) {
            return ProposalState.Executed;
        }
        if (block.timestamp >= proposal.eta + timelock.GRACE_PERIOD()) {
            return ProposalState.Expired;
        }

        return ProposalState.Queued;
    }

    /**
     * @notice Get fast vote state of proposal
     * @param proposalId Proposal Id.
     * @dev Check the fast vote status of proposal
     */

    function checkfastvote(uint256 proposalId) public view returns (bool) {
        require(
            proposalCount >= proposalId && proposalId > 0,
            "GovernorAlpha::state: invalid proposal id"
        );

        Proposal storage proposal = proposals[proposalId];
        uint256 oneDayBlockLimit = proposalCreatedTime[proposalId] +
            blocksPerDay;
        uint256 percentageThreshold = 10;

        if (ArbSys(ARBSYS_ADDRESS).arbBlockNumber() <= oneDayBlockLimit) {
            if (
                ArbSys(ARBSYS_ADDRESS).arbBlockNumber() <= proposal.endBlock &&
                proposal.againstVotes <= proposal.forVotes &&
                proposal.forVotes >= quorumVotes()
            ) {
                if (proposal.againstVotes == 0) {
                    return true;
                }

                uint256 votePercentage = ((proposal.forVotes -
                    proposal.againstVotes) * 100) / proposal.againstVotes;
                if (votePercentage > percentageThreshold) {
                    return true;
                }
            }
        }

        return false;
    }

    /**
     * @notice Cast a vote for a proposal
     * @param signature The signature of the voter
     * @dev Cast a vote for a proposal
     */
    function castVote(
        SignatureVerifier.Signature memory signature
    ) external {
        SignatureVerifier.GovernanceMessage
            memory message = signatureVerifier.verifyGovernanceSignature(signature);

        _castVote(
            message.userAddress,
            message.proposalId,
            message.support,
            message.isGovernor,
            message.averageBalance
        );
    }

    /**
     * @notice Cast a vote for a proposal
     * @param proposalId The ID of the proposal
     * @param support The support value of the vote
     * @param isGovernor The status of the voter
     * @param averageBalance The average balance of the voter
     * @dev Cast a vote for a proposal
     */
    function _castVote(
        address voter,
        uint256 proposalId,
        bool support,
        bool isGovernor,
        uint256 averageBalance
    ) internal {
        require(
            state(proposalId) == ProposalState.Active,
            "GovernorAlpha::_castVote: voting is closed"
        );

        // Mark the voter and update count if not already done
        VoterInfo storage voterInfo = votersInfo[proposalId];
        if (!voterInfo.voterAddress[voter]) {
            voterInfo.voterAddress[voter] = true;
            voterInfo.voterCount++;
            if (isGovernor) {
                voterInfo.governors++;
            }
        }

        Proposal storage proposal = proposals[proposalId];
        Receipt storage receipt = proposal.receipts[voter];

        // Cast vote if the voter hasn't voted yet
        if (!receipt.hasVoted) {
            if (support) {
                proposal.forVotes += averageBalance;
            } else {
                proposal.againstVotes += averageBalance;
            }
            proposalVoted[voter]++;
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
     * @dev Function to claim buyback and burn funds
     * @param receiverBuyBackandBurn address to receive funds for buyback and burn
     * @param receiverRevenueShare address to receive funds for revenueShare
     */
    function distributeRevenue(
        address receiverBuyBackandBurn,
        address receiverRevenueShare
    ) external {
        require(msg.sender == admin, "Call must come from Admin.");
        uint256 revenue = IERC20(baseStableCoin).balanceOf(address(this));
        require(revenue > 0, "No Revenue to distribute");
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
