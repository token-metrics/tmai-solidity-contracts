// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/TMAI-timelock.sol";
import "../../src/TMAI-Token.sol";
import "../../src/mock/ERC20Mock.sol";
import "../../src/mock/TMAI-governance-mock.sol";
import "../../src/utils/SignatureVerifier.sol";
// import "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol";
// import "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";

contract GovernanceTest is Test {
    GovernorAlphaMock public governance;
    TMAIToken public tmai;
    ERC20Mock public lp;
    ERC20Mock public weth;
    ERC20Mock public usdc;
    Timelock public timelock;
    SignatureVerifier public signatureVerifier; 
    address public owner = address(this);
    address public user1 = address(1);
    address public user2 = address(2);
    uint256 public signerpvtKey = 123;
    address public signerpubkey = vm.addr(signerpvtKey);

    // address public signer = address(3);
    // Parameters for a proposal 
    address[] public targets;
    uint256[] public values;
    string[] public signatures;
    bytes[] public calldatas;
    string public description;
    uint public quorumPercentage;
    uint public yesVoteThreshold;


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

    function setUp() public {
        weth = new ERC20Mock("Weth", "WETH", 1000000000000000000000000000);
        lp = new ERC20Mock("LPToken", "LP", 1000000000000000000000000000);
        usdc = new ERC20Mock("USDC Coin", "USDC", 1000000000000000000000000000);
        tmai = new TMAIToken();
        tmai.initialize(address(this));
        yesVoteThreshold = 10;
        quorumPercentage = 25;


        // // AxelarGasSerive contract on L1
        // address gasService = address(0x013459EC3E8Aeced878C5C4bFfe126A366cd19E9);
        // // AxelarGateway contract on L1
        // address axelarGateway = address(0x28f8B50E1Be6152da35e923602a2641491E71Ed8);

        timelock = new Timelock(address(this), 120);
        signatureVerifier = new SignatureVerifier();
        signatureVerifier.initialize(signerpubkey);
        governance = new GovernorAlphaMock();
        governance.initialize(address(timelock), address(tmai), address(usdc), address(signatureVerifier), quorumPercentage, yesVoteThreshold);
  
        //Configure tmai contract
        tmai.transfer(user1, 10000000 * (10**18));
        tmai.transfer(user2, 1000 * (10**18));
        timelock.setPendingAdmin(address(governance));
        governance._acceptAdmin();
    }

    function testCreatePropose() public {
        
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        tmai.approve(address(governance), 1000000000000000000000000000000);
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description);
        assertEq(governance.proposalCount(), 1);
    }

    function testCreateProposeFailOnlyOneProposalPerDay() public {

        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        tmai.approve(address(governance), 1000000000000000000000000000000);
        vm.warp(block.timestamp + 1 days);
        vm.warp(36 days);
        governance.propose( targets, values, signatures, calldatas, description);
        vm.expectRevert(bytes("Proposal too soon"));
        governance.propose( targets, values, signatures, calldatas, description);
    }

    function testCreateProposeFailInfoMismatch() public {
        targets.push(address(governance));  
        values.push(0);        
        //signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        tmai.approve(address(governance), 1000000000000000000000000000000);
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        vm.expectRevert(bytes("Invalid input lengths"));
        governance.propose(targets, values, signatures, calldatas, description);
    }

    function testCreateProposeFailNoAction() public {
        tmai.approve(address(governance), 1000000000000000000000000000000);
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        vm.expectRevert(bytes("Must provide actions"));
        governance.propose(targets, values, signatures, calldatas, description);
    }

    function testCreateProposeFailOnlyOneActiveProposalPerUser() public {
        
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        tmai.approve(address(governance), 1000000000000000000000000000000);
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose( targets, values, signatures, calldatas, description);
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert(bytes("Active or pending proposal exists"));
        governance.propose( targets, values, signatures, calldatas, description);
    }

        function testCreateProposeFailUserLevelLessThan4() public {
        
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        tmai.approve(address(governance), 1000000000000000000000000000000);
        vm.warp(block.timestamp + 1 days);
        vm.prank(user2);
        vm.expectRevert(bytes("Insufficient TMAI holdings"));
        governance.propose( targets, values, signatures, calldatas, description);
    }


    function testVote() public {
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        tmai.approve(address(governance), 1000000000000000000000000000000);
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description);
        vm.roll(3);


        uint256 proposalId = 1;
        uint256 averageBalance = 1000 * 10 ** 18;
        bool support = true;
        uint256 totalTokenHolders = 100;
        uint256 validity = block.number + 10;

        // Encode the message (equivalent to `encodeAbiParameters`)
        bytes memory encodedMessage = abi.encode(
            signerpubkey,
            proposalId,
            averageBalance,
            support,
            totalTokenHolders,
            validity
        );

        bytes32  messageHash = keccak256(encodedMessage);
        bytes32 ethmessagehash = getEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerpvtKey, ethmessagehash);
        bytes memory signature = abi.encodePacked(r, s, v);
        SignatureVerifier.Signature memory sig =  SignatureVerifier.Signature({
            encodedMessage: encodedMessage,
            messageHash: messageHash,
            signature: signature
        });

        governance.castVote(sig);
    }

    function testVoteChange() public {
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        tmai.approve(address(governance), 1000000000000000000000000000000);
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description);
        vm.roll(3);

                uint256 proposalId = 1;
        uint256 averageBalance = 1000 * 10 ** 18;
        bool support = true;
        uint256 totalTokenHolders = 100;
        uint256 validity = block.number + 10;

        // Encode the message (equivalent to `encodeAbiParameters`)
        bytes memory encodedMessage = abi.encode(
            signerpubkey,
            proposalId,
            averageBalance,
            support,
            totalTokenHolders,
            validity
        );

        bytes32  messageHash = keccak256(encodedMessage);
        bytes32 ethmessagehash = getEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerpvtKey, ethmessagehash);
        bytes memory signature = abi.encodePacked(r, s, v);
        SignatureVerifier.Signature memory sig =  SignatureVerifier.Signature({
            encodedMessage: encodedMessage,
            messageHash: messageHash,
            signature: signature
        });

        governance.castVote(sig);


        support = false;

        // Encode the message (equivalent to `encodeAbiParameters`)
        encodedMessage = abi.encode(
            signerpubkey,
            proposalId,
            averageBalance,
            support,
            totalTokenHolders,
            validity
        );

        messageHash = keccak256(encodedMessage);
        ethmessagehash = getEthSignedMessageHash(messageHash);
        (v, r,  s) = vm.sign(signerpvtKey, ethmessagehash);
        signature = abi.encodePacked(r, s, v);
        sig =  SignatureVerifier.Signature({
            encodedMessage: encodedMessage,
            messageHash: messageHash,
            signature: signature
        });

        governance.castVote(sig);
    }

    
    function testVoteFailVotingClosed() public {
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        tmai.approve(address(governance), 1000000000000000000000000000000);
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description);
        vm.warp(15 days);

        uint256 proposalId = 1;
        uint256 averageBalance = 1000 * 10 ** 18;
        bool support = true;
        uint256 totalTokenHolders = 100;
        uint256 validity = block.number + 10;

        // Encode the message (equivalent to `encodeAbiParameters`)
        bytes memory encodedMessage = abi.encode(
            signerpubkey,
            proposalId,
            averageBalance,
            support,
            totalTokenHolders,
            validity
        );

        bytes32  messageHash = keccak256(encodedMessage);
        bytes32 ethmessagehash = getEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerpvtKey, ethmessagehash);
        bytes memory signature = abi.encodePacked(r, s, v);
        SignatureVerifier.Signature memory sig =  SignatureVerifier.Signature({
            encodedMessage: encodedMessage,
            messageHash: messageHash,
            signature: signature
        });

        vm.expectRevert(bytes("GovernorAlpha::_castVote: voting is closed"));
        governance.castVote(sig);
    }

    function testVoteFailVoterVoted() public {
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        tmai.approve(address(governance), 1000000000000000000000000000000);
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description);
        vm.roll(3);
        
        uint256 proposalId = 1;
        uint256 averageBalance = 1000 * 10 ** 18;
        bool support = true;
        uint256 totalTokenHolders = 100;
        uint256 validity = block.number + 10;

        // Encode the message (equivalent to `encodeAbiParameters`)
        bytes memory encodedMessage = abi.encode(
            signerpubkey,
            proposalId,
            averageBalance,
            support,
            totalTokenHolders,
            validity
        );

        bytes32  messageHash = keccak256(encodedMessage);
        bytes32 ethmessagehash = getEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerpvtKey, ethmessagehash);
        bytes memory signature = abi.encodePacked(r, s, v);
        SignatureVerifier.Signature memory sig =  SignatureVerifier.Signature({
            encodedMessage: encodedMessage,
            messageHash: messageHash,
            signature: signature
        });

        governance.castVote(sig);
        vm.expectRevert(bytes("GovernorAlpha::_castVote: voter already voted"));
        governance.castVote(sig);
    }

    function testQueue() public {
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        address user = address(0);
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description);
        vm.roll(3);

        uint256 proposalId = 1;
        uint256 averageBalance = 1000 * 10 ** 18;
        bool support = true;
        uint256 totalTokenHolders = 1;
        uint256 validity = block.number + 10;

        // Encode the message (equivalent to `encodeAbiParameters`)
        bytes memory encodedMessage = abi.encode(
            signerpubkey,
            proposalId,
            averageBalance,
            support,
            totalTokenHolders,
            validity
        );

        bytes32  messageHash = keccak256(encodedMessage);
        bytes32 ethmessagehash = getEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerpvtKey, ethmessagehash);
        bytes memory signature = abi.encodePacked(r, s, v);
        SignatureVerifier.Signature memory sig =  SignatureVerifier.Signature({
            encodedMessage: encodedMessage,
            messageHash: messageHash,
            signature: signature
        });

        governance.castVote(sig);
        
        vm.roll(2016501);
        console.log(uint(governance.state(1)));
        // (,uint256 governors) = governance.votersInfo(1);
        // console.log(governors);       
        governance.queue(1);
        assertEq(uint(governance.state(1)), 5);

    }

    function testQueueFailVotingNotEnd() public {
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        tmai.approve(address(governance), 1000000000000000000000000000000);
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description);  
        vm.expectRevert(bytes("Proposal not succeeded"));
        governance.queue(1);

    }

    function testExecuteFailNotQueued() public {
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description);
        vm.roll(3);
        
        
        uint256 proposalId = 1;
        uint256 averageBalance = 1000 * 10 ** 18;
        bool support = true;
        uint256 totalTokenHolders = 1;
        uint256 validity = block.number + 10;

        // Encode the message (equivalent to `encodeAbiParameters`)
        bytes memory encodedMessage = abi.encode(
            signerpubkey,
            proposalId,
            averageBalance,
            support,
            totalTokenHolders,
            validity
        );

        bytes32  messageHash = keccak256(encodedMessage);
        bytes32 ethmessagehash = getEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerpvtKey, ethmessagehash);
        bytes memory signature = abi.encodePacked(r, s, v);
        SignatureVerifier.Signature memory sig =  SignatureVerifier.Signature({
            encodedMessage: encodedMessage,
            messageHash: messageHash,
            signature: signature
        });

        governance.castVote(sig);

        vm.roll(2016501);

        vm.expectRevert(bytes("Proposal not queued"));
        governance.execute(1);

    }

    function testExecuteFailTimelock() public {
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";

        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description);
        vm.roll(3);
        
        
        uint256 proposalId = 1;
        uint256 averageBalance = 1000 * 10 ** 18;
        bool support = true;
        uint256 totalTokenHolders = 1;
        uint256 validity = block.number + 10;

        // Encode the message (equivalent to `encodeAbiParameters`)
        bytes memory encodedMessage = abi.encode(
            signerpubkey,
            proposalId,
            averageBalance,
            support,
            totalTokenHolders,
            validity
        );

        bytes32  messageHash = keccak256(encodedMessage);
        bytes32 ethmessagehash = getEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerpvtKey, ethmessagehash);
        bytes memory signature = abi.encodePacked(r, s, v);
        SignatureVerifier.Signature memory sig =  SignatureVerifier.Signature({
            encodedMessage: encodedMessage,
            messageHash: messageHash,
            signature: signature
        });

        governance.castVote(sig);

        vm.roll(2016501);
        governance.queue(1);
        vm.expectRevert(bytes("Timelock::executeTransaction: Transaction hasn't surpassed time lock."));
        governance.execute(1);

    }

    function testExecute() public {
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
 
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description);
        vm.roll(3);
        
        
        uint256 proposalId = 1;
        uint256 averageBalance = 1000 * 10 ** 18;
        bool support = true;
        uint256 totalTokenHolders = 1;
        uint256 validity = block.number + 10;

        // Encode the message (equivalent to `encodeAbiParameters`)
        bytes memory encodedMessage = abi.encode(
            signerpubkey,
            proposalId,
            averageBalance,
            support,
            totalTokenHolders,
            validity
        );

        bytes32  messageHash = keccak256(encodedMessage);
        bytes32 ethmessagehash = getEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerpvtKey, ethmessagehash);
        bytes memory signature = abi.encodePacked(r, s, v);
        SignatureVerifier.Signature memory sig =  SignatureVerifier.Signature({
            encodedMessage: encodedMessage,
            messageHash: messageHash,
            signature: signature
        });

        governance.castVote(sig);

        vm.roll(2016501);
        governance.queue(1);
        vm.warp(block.timestamp + 1 days + 1150);
        governance.execute(1);
        assertEq(uint(governance.state(1)), 7);
        assertEq(governance.minProposalTimeIntervalSec(), 120);

    }

    function testProposalDefeatedNotenoughGovernor() public {
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        tmai.approve(address(governance), 1000000000000000000000000000000);
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description);
        vm.roll(3);
        uint256 proposalId = 1;
        uint256 averageBalance = 1000 * 10 ** 18;
        bool support = true;
        uint256 totalTokenHolders = 100;
        uint256 validity = block.number + 10;

        // Encode the message (equivalent to `encodeAbiParameters`)
        bytes memory encodedMessage = abi.encode(
            signerpubkey,
            proposalId,
            averageBalance,
            support,
            totalTokenHolders,
            validity
        );

        bytes32  messageHash = keccak256(encodedMessage);
        bytes32 ethmessagehash = getEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerpvtKey, ethmessagehash);
        bytes memory signature = abi.encodePacked(r, s, v);
        SignatureVerifier.Signature memory sig =  SignatureVerifier.Signature({
            encodedMessage: encodedMessage,
            messageHash: messageHash,
            signature: signature
        });

        governance.castVote(sig);

        vm.roll(2016501);
        assertEq(uint(governance.state(1)), 3);

    }

    function testCancelFailProposalExecuted() public {
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
    
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description);
        vm.roll(3);
        
        uint256 proposalId = 1;
        uint256 averageBalance = 1000 * 10 ** 18;
        bool support = true;
        uint256 totalTokenHolders = 1;
        uint256 validity = block.number + 10;

        // Encode the message (equivalent to `encodeAbiParameters`)
        bytes memory encodedMessage = abi.encode(
            signerpubkey,
            proposalId,
            averageBalance,
            support,
            totalTokenHolders,
            validity
        );

        bytes32  messageHash = keccak256(encodedMessage);
        bytes32 ethmessagehash = getEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerpvtKey, ethmessagehash);
        bytes memory signature = abi.encodePacked(r, s, v);
        SignatureVerifier.Signature memory sig =  SignatureVerifier.Signature({
            encodedMessage: encodedMessage,
            messageHash: messageHash,
            signature: signature
        });

        governance.castVote(sig);

        vm.roll(2016501);
        governance.queue(1);
        vm.warp(block.timestamp + 1 days + 1150);
        governance.execute(1);
        vm.expectRevert(bytes("Proposal already executed"));
        governance.cancel(1);

    }

    function testCancelFailNotCreator() public {
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        tmai.approve(address(governance), 1000000000000000000000000000000);
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description);
        vm.roll(3);
        
        vm.prank(user1);
        vm.expectRevert(bytes("Only proposer can cancel"));
        governance.cancel(1);
    }

    function testCancel() public {
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        tmai.approve(address(governance), 1000000000000000000000000000000);
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description);
        vm.roll(3);
        governance.cancel(1);
        assertEq(uint(governance.state(1)), 2);
    }

    function testUpdateRevenueSharePercent() public {
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateRevenueSharePercent(uint256)");
        calldatas.push(abi.encode(20));
        description = "Description";

        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description);
        vm.roll(3);
        
        uint256 proposalId = 1;
        uint256 averageBalance = 1000 * 10 ** 18;
        bool support = true;
        uint256 totalTokenHolders = 1;
        uint256 validity = block.number + 10;

        // Encode the message (equivalent to `encodeAbiParameters`)
        bytes memory encodedMessage = abi.encode(
            signerpubkey,
            proposalId,
            averageBalance,
            support,
            totalTokenHolders,
            validity
        );

        bytes32  messageHash = keccak256(encodedMessage);
        bytes32 ethmessagehash = getEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerpvtKey, ethmessagehash);
        bytes memory signature = abi.encodePacked(r, s, v);
        SignatureVerifier.Signature memory sig =  SignatureVerifier.Signature({
            encodedMessage: encodedMessage,
            messageHash: messageHash,
            signature: signature
        });

        governance.castVote(sig);

        vm.roll(2016501);
        governance.queue(1);
        vm.warp(block.timestamp + 1 days + 1150);
        governance.execute(1);
        assertEq(governance.revenueSharePercent(), 20);
    }

    function testUpdateRevenueSharePercentFailGreaterThan100() public {
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateRevenueSharePercent(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description);
        vm.roll(3);
        
        uint256 proposalId = 1;
        uint256 averageBalance = 1000 * 10 ** 18;
        bool support = true;
        uint256 totalTokenHolders = 1;
        uint256 validity = block.number + 10;

        // Encode the message (equivalent to `encodeAbiParameters`)
        bytes memory encodedMessage = abi.encode(
            signerpubkey,
            proposalId,
            averageBalance,
            support,
            totalTokenHolders,
            validity
        );

        bytes32  messageHash = keccak256(encodedMessage);
        bytes32 ethmessagehash = getEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerpvtKey, ethmessagehash);
        bytes memory signature = abi.encodePacked(r, s, v);
        SignatureVerifier.Signature memory sig =  SignatureVerifier.Signature({
            encodedMessage: encodedMessage,
            messageHash: messageHash,
            signature: signature
        });

        governance.castVote(sig);

        vm.roll(2016501);
        governance.queue(1);
        vm.warp(block.timestamp + 1 days + 1150);
        vm.expectRevert(bytes("Timelock::executeTransaction: Transaction execution reverted."));
        governance.execute(1);
    }

    function testDistributeRevenue() public {
        usdc.transfer(address(governance), 10000000 * (10**6));
        assertEq(usdc.balanceOf(user1), 0);
        assertEq(usdc.balanceOf(user2), 0);
        governance.distributeRevenue(user1, user2);
        assertEq(usdc.balanceOf(user1), 5000000 * (10**6));
        assertEq(usdc.balanceOf(user2), 5000000 * (10**6));


    }

    function testDistributeRevenueFailCallMustComeFromAdmin() public {
        usdc.transfer(address(governance), 10000000 * (10**6));
        assertEq(usdc.balanceOf(user1), 0);
        assertEq(usdc.balanceOf(user2), 0);
        vm.prank(user1);
        vm.expectRevert("Only admin can distribute revenue");
        governance.distributeRevenue(user1, user2);

    }

    function testDistributeRevenueFailNoRevenueToDistribute() public {
        assertEq(usdc.balanceOf(user1), 0);
        assertEq(usdc.balanceOf(user2), 0);
        vm.expectRevert("No revenue to distribute");
        governance.distributeRevenue(user1, user2);

    }


    function getEthSignedMessageHash(
        bytes32 _messageHash
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    _messageHash
                )
            );
    }




}
