// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/TMAI-timelock.sol";
import "../../src/mock/TMAI-staking-mock.sol";
import "../../src/TMAI-Token.sol";
import "../../src/mock/ERC20Mock.sol";
import "../../src/mock/TMAI-governance-mock.sol";
// import "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol";
// import "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";

contract GovernanceTest is Test {
    GovernorAlpha public governance;
    TMAIToken public tmai;
    TMAIStakingMock public staking;
    ERC20Mock public lp;
    ERC20Mock public weth;
    ERC20Mock public usdc;
    Timelock public timelock;
    address public owner = address(this);
    address public user1 = address(1);
    address public user2 = address(2);
    // Parameters for a proposal 
    address[] public targets;
    uint256[] public values;
    string[] public signatures;
    bytes[] public calldatas;
    string public description;
    bool public fundametalChanges;


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

        // // AxelarGasSerive contract on L1
        // address gasService = address(0x013459EC3E8Aeced878C5C4bFfe126A366cd19E9);
        // // AxelarGateway contract on L1
        // address axelarGateway = address(0x28f8B50E1Be6152da35e923602a2641491E71Ed8);

        timelock = new Timelock(address(this), 120);


        staking = new TMAIStakingMock();
        staking.initialize(tmai, 243457567, 243467567, 1000000);
        governance = new GovernorAlpha();
        governance.initialize(address(timelock), address(tmai), address(staking), address(usdc));
        staking.whitelistDepositContract(address(governance), true);
        //Configure tmai contract
        tmai.transfer(user1, 10000000 * (10**18));
        tmai.transfer(user2, 10000000 * (10**18));
        timelock.setPendingAdmin(address(governance));
        governance._acceptAdmin();
        tmai.approve(address(staking), 1000000000 * (10**18));
        staking.deposit(100 * (10**18), 0, false);
        staking.deposit(100000000 * (10**18), 0, false);
        vm.prank(user1);
        tmai.approve(address(staking), 1000000000 * (10**18));
        vm.prank(user1);
        staking.deposit(10000000 * (10**18), 0, false);
        vm.prank(user2);
        tmai.approve(address(staking), 1000000000 * (10**18));
        vm.prank(user2);
        staking.deposit(10000000 * (10**18), 0, false);

    }

    function testCreatePropose() public {
        
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        fundametalChanges = false;
        tmai.approve(address(governance), 1000000000000000000000000000000);
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        //console.log(staking.getLevelForUser(address(this)));
        governance.propose(targets, values, signatures, calldatas, description, fundametalChanges);
        assertEq(governance.proposalCount(), 1);
    }

    function testCreateProposeFailOnlyOneProposalPerDay() public {

        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        fundametalChanges = false;
        tmai.approve(address(governance), 1000000000000000000000000000000);
        vm.warp(block.timestamp + 1 days);
        vm.warp(36 days);
        governance.propose( targets, values, signatures, calldatas, description, fundametalChanges);
        vm.expectRevert(bytes("GovernorAlpha::propose: Only one proposal can be create in one day"));
        governance.propose( targets, values, signatures, calldatas, description, fundametalChanges);
    }

    function testCreateProposeFailInfoMismatch() public {
        targets.push(address(governance));  
        values.push(0);        
        //signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        fundametalChanges = false;
        tmai.approve(address(governance), 1000000000000000000000000000000);
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        vm.expectRevert(bytes("GovernorAlpha::propose: proposal function information arity mismatch"));
        governance.propose(targets, values, signatures, calldatas, description, fundametalChanges);
    }

    function testCreateProposeFailNoAction() public {
        tmai.approve(address(governance), 1000000000000000000000000000000);
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        vm.expectRevert(bytes("GovernorAlpha::propose: must provide actions"));
        governance.propose(targets, values, signatures, calldatas, description, fundametalChanges);
    }

    function testCreateProposeFailOnlyOneActiveProposalPerUser() public {
        
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        fundametalChanges = false;
        tmai.approve(address(governance), 1000000000000000000000000000000);
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose( targets, values, signatures, calldatas, description, fundametalChanges);
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert(bytes("GovernorAlpha::propose: one live proposal per proposer, found an already pending proposal"));
        governance.propose( targets, values, signatures, calldatas, description, fundametalChanges);
    }

        function testCreateProposeFailUserLevelLessThan4() public {
        
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        fundametalChanges = false;
        tmai.approve(address(governance), 1000000000000000000000000000000);
        vm.warp(block.timestamp + 1 days);
        vm.expectRevert(bytes("User Level is less than 4"));
        governance.propose( targets, values, signatures, calldatas, description, fundametalChanges);
    }


    function testVote() public {
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        fundametalChanges = false;
        tmai.approve(address(governance), 1000000000000000000000000000000);
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description, fundametalChanges);
        vm.roll(3);
        governance.castVote(1, true);
    }

    function testVoteFailVotingClosed() public {
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        fundametalChanges = false;
        tmai.approve(address(governance), 1000000000000000000000000000000);
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description, fundametalChanges);
        vm.warp(15 days);
        vm.expectRevert(bytes("GovernorAlpha::_castVote: voting is closed"));
        governance.castVote(1, true);
    }

    function testVoteFailVoterVoted() public {
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        fundametalChanges = false;
        tmai.approve(address(governance), 1000000000000000000000000000000);
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description, fundametalChanges);
        vm.roll(3);
        governance.castVote(1, true);
        vm.expectRevert(bytes("GovernorAlpha::_castVote: voter already voted"));
        governance.castVote(1, true);
    }

    function testQueue() public {
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        fundametalChanges = false;
        address user = address(0);
        for( uint160 i = 1; i <= 33;i++) {
            user = address(i);
            tmai.transfer(user, 100000 * (10**18));
            vm.startPrank(user);

            tmai.approve(address(staking), 1000000000 * (10**18));
            staking.deposit(10000 * (10**18), 0, false);
            vm.stopPrank();

        } 
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description, fundametalChanges);
        vm.roll(3);
        
        for( uint160 i = 1; i <= 33;i++) {
            user = address(i);
            vm.startPrank(user);
            governance.castVote(1, true);

            vm.stopPrank();

        } 
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
        fundametalChanges = false;
        tmai.approve(address(governance), 1000000000000000000000000000000);
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description, fundametalChanges);  
        vm.expectRevert(bytes("GovernorAlpha::queue: proposal can only be queued if it is succeeded"));
        governance.queue(1);

    }

    function testExecuteFailNotQueued() public {
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        fundametalChanges = false;
        address user = address(0);
        for( uint160 i = 1; i <= 33;i++) {
            user = address(i);
            tmai.transfer(user, 100000 * (10**18));
            vm.startPrank(user);

            tmai.approve(address(staking), 1000000000 * (10**18));
            staking.deposit(10000 * (10**18), 0, false);
            vm.stopPrank();

        } 
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description, fundametalChanges);
        vm.roll(3);
        
        for( uint160 i = 1; i <= 33;i++) {
            user = address(i);
            vm.startPrank(user);
            governance.castVote(1, true);

            vm.stopPrank();

        } 
        vm.roll(2016501);

        vm.expectRevert(bytes("GovernorAlpha::execute: proposal can only be executed if it is queued"));
        governance.execute(1);

    }

    function testExecuteFailTimelock() public {
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        fundametalChanges = false;
        address user = address(0);
        for( uint160 i = 1; i <= 33;i++) {
            user = address(i);
            tmai.transfer(user, 100000 * (10**18));
            vm.startPrank(user);

            tmai.approve(address(staking), 1000000000 * (10**18));
            staking.deposit(10000 * (10**18), 0, false);
            vm.stopPrank();

        } 
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description, fundametalChanges);
        vm.roll(3);
        
        for( uint160 i = 1; i <= 33;i++) {
            user = address(i);
            vm.startPrank(user);
            governance.castVote(1, true);

            vm.stopPrank();

        } 
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
        fundametalChanges = false;
        address user = address(0);
        for( uint160 i = 1; i <= 33;i++) {
            user = address(i);
            tmai.transfer(user, 100000 * (10**18));
            vm.startPrank(user);

            tmai.approve(address(staking), 1000000000 * (10**18));
            staking.deposit(10000 * (10**18), 0, false);
            vm.stopPrank();

        } 
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description, fundametalChanges);
        vm.roll(3);
        
        for( uint160 i = 1; i <= 33;i++) {
            user = address(i);
            vm.startPrank(user);
            governance.castVote(1, true);

            vm.stopPrank();

        } 
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
        fundametalChanges = false;
        tmai.approve(address(governance), 1000000000000000000000000000000);
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description, fundametalChanges);
        vm.roll(3);
        governance.castVote(1, true);
        vm.roll(2016501);
        assertEq(uint(governance.state(1)), 3);

    }

    function testCancelFailProposalExecuted() public {
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        fundametalChanges = false;
        address user = address(0);
        for( uint160 i = 1; i <= 33;i++) {
            user = address(i);
            tmai.transfer(user, 100000 * (10**18));
            vm.startPrank(user);

            tmai.approve(address(staking), 1000000000 * (10**18));
            staking.deposit(10000 * (10**18), 0, false);
            vm.stopPrank();

        } 
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description, fundametalChanges);
        vm.roll(3);
        
        for( uint160 i = 1; i <= 33;i++) {
            user = address(i);
            vm.startPrank(user);
            governance.castVote(1, true);

            vm.stopPrank();

        } 
        vm.roll(2016501);
        governance.queue(1);
        vm.warp(block.timestamp + 1 days + 1150);
        governance.execute(1);
        vm.expectRevert(bytes("GovernorAlpha::cancel: cannot cancel executed proposal"));
        governance.cancel(1);

    }

    function testCancelFailNotCreator() public {
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        fundametalChanges = false;
        tmai.approve(address(governance), 1000000000000000000000000000000);
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description, fundametalChanges);
        vm.roll(3);
        governance.castVote(1, true);
        vm.prank(user1);
        vm.expectRevert(bytes("GovernorAlpha::cancel: Only creator can cancel"));
        governance.cancel(1);
    }

    function testCancel() public {
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateMinProposalTimeIntervalSec(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        fundametalChanges = false;
        tmai.approve(address(governance), 1000000000000000000000000000000);
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description, fundametalChanges);
        vm.roll(3);
        governance.castVote(1, true);
        governance.cancel(1);
        assertEq(uint(governance.state(1)), 2);
    }

    function testUpdateRevenueSharePercent() public {
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateRevenueSharePercent(uint256)");
        calldatas.push(abi.encode(20));
        description = "Description";
        fundametalChanges = false;
        address user = address(0);
        for( uint160 i = 1; i <= 33;i++) {
            user = address(i);
            tmai.transfer(user, 100000 * (10**18));
            vm.startPrank(user);

            tmai.approve(address(staking), 1000000000 * (10**18));
            staking.deposit(10000 * (10**18), 0, false);
            vm.stopPrank();

        } 
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description, fundametalChanges);
        vm.roll(3);
        
        for( uint160 i = 1; i <= 33;i++) {
            user = address(i);
            vm.startPrank(user);
            governance.castVote(1, true);

            vm.stopPrank();

        } 
        vm.roll(2016501);
        governance.queue(1);
        vm.warp(block.timestamp + 1 days + 1150);
        governance.execute(1);
        assertEq(uint(governance.state(1)), 7);
        assertEq(governance.revenueSharePercent(), 20);
    }

    function testUpdateRevenueSharePercentFailGreaterThan100() public {
        targets.push(address(governance));  
        values.push(0);        
        signatures.push("updateRevenueSharePercent(uint256)");
        calldatas.push(abi.encode(120));
        description = "Description";
        fundametalChanges = false;
        address user = address(0);
        for( uint160 i = 1; i <= 33;i++) {
            user = address(i);
            tmai.transfer(user, 100000 * (10**18));
            vm.startPrank(user);

            tmai.approve(address(staking), 1000000000 * (10**18));
            staking.deposit(10000 * (10**18), 0, false);
            vm.stopPrank();

        } 
        vm.warp(block.timestamp + 1 days);
        vm.warp(365 days);
        governance.propose(targets, values, signatures, calldatas, description, fundametalChanges);
        vm.roll(3);
        
        for( uint160 i = 1; i <= 33;i++) {
            user = address(i);
            vm.startPrank(user);
            governance.castVote(1, true);

            vm.stopPrank();

        } 
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
        vm.expectRevert("Call must come from Admin.");
        governance.distributeRevenue(user1, user2);

    }

    function testDistributeRevenueFailNoRevenueToDistribute() public {
        assertEq(usdc.balanceOf(user1), 0);
        assertEq(usdc.balanceOf(user2), 0);
        vm.expectRevert("No Revenue to distribute");
        governance.distributeRevenue(user1, user2);

    }



}
