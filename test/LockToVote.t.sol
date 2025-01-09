// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {AragonTest} from "./util/AragonTest.sol";
import {LockToVotePlugin} from "../src/LockToVotePlugin.sol";
import {LockManager} from "../src/LockManager.sol";
import {LockManagerSettings} from "../src/interfaces/ILockManager.sol";
import {ILockToVote} from "../src/interfaces/ILockToVote.sol";
import {DaoBuilder} from "./util/DaoBuilder.sol";
import {DAO, IDAO} from "@aragon/osx/src/core/dao/DAO.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {LockToVoteSettings, Proposal, ProposalParameters} from "../src/interfaces/ILockToVote.sol";
import {UnlockMode} from "../src/interfaces/ILockManager.sol";
import {TestToken} from "./mocks/TestToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IMembership} from "@aragon/osx-commons-contracts/src/plugin/extensions/membership/IMembership.sol";
import {IProposal} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {createProxyAndCall, createSaltedProxyAndCall, predictProxyAddress} from "../src/util/proxy.sol";

contract LockToVoteTest is AragonTest {
    using SafeCastUpgradeable for uint256;

    DaoBuilder builder;
    DAO dao;
    LockToVotePlugin plugin;
    LockManager lockManager;
    IERC20 lockableToken;
    IERC20 underlyingToken;
    uint256 proposalId;

    address immutable LOCK_TO_VOTE_BASE = address(new LockToVotePlugin());
    address immutable LOCK_MANAGER_BASE =
        address(
            new LockManager(
                IDAO(address(0)),
                LockManagerSettings(UnlockMode.STRICT),
                IERC20(address(0)),
                IERC20(address(0))
            )
        );

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed creator,
        uint64 startDate,
        uint64 endDate,
        bytes metadata,
        Action[] actions,
        uint256 allowFailureMap
    );

    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        uint256 newVotingPower
    );

    event ProposalEnded(uint256 proposalId);

    event VoteCleared(uint256 indexed proposalId, address indexed voter);

    event Executed(uint256 indexed proposalId);

    bytes32 constant CREATE_PROPOSAL_PERMISSION_ID =
        keccak256("CREATE_PROPOSAL_PERMISSION");
    bytes32 constant EXECUTE_PROPOSAL_PERMISSION_ID =
        keccak256("EXECUTE_PROPOSAL_PERMISSION");
    bytes32 constant LOCK_MANAGER_PERMISSION_ID =
        keccak256("LOCK_MANAGER_PERMISSION");
    bytes32 constant UPDATE_VOTING_SETTINGS_PERMISSION_ID =
        keccak256("UPDATE_VOTING_SETTINGS_PERMISSION");

    function setUp() public {
        vm.startPrank(alice);
        vm.warp(10 days);
        vm.roll(100);

        builder = new DaoBuilder();
        (dao, plugin, lockManager, lockableToken, underlyingToken) = builder
            .withTokenHolder(alice, 1 ether)
            .withTokenHolder(bob, 10 ether)
            .withTokenHolder(carol, 10 ether)
            .withTokenHolder(david, 15 ether)
            .build();
        // .withUnlockMode(UnlockMode.STRICT)
        // .withMinApprovalRatio(100_000)
        // .withMinDuration(10 days)
    }

    function test_WhenDeployingTheContract() public {
        // It should disable the initializers

        vm.expectRevert();
        plugin.initialize(
            dao,
            lockManager,
            LockToVoteSettings({
                minApprovalRatio: 100_000, // 10%
                minProposalDuration: 10 days
            }),
            IPlugin.TargetConfig({
                target: address(dao),
                operation: IPlugin.Operation.Call
            }),
            abi.encode(uint256(0))
        );
    }

    modifier givenANewProxy() {
        _;
    }

    function test_WhenCallingInitialize() public givenANewProxy {
        // It should set the DAO address
        // It should initialize normally

        LockToVoteSettings memory pluginSettings = LockToVoteSettings({
            minApprovalRatio: 100_000, // 10%
            minProposalDuration: 10 days
        });
        IPlugin.TargetConfig memory targetConfig = IPlugin.TargetConfig({
            target: address(dao),
            operation: IPlugin.Operation.Call
        });
        bytes memory pluginMetadata = "";

        plugin = LockToVotePlugin(
            createProxyAndCall(
                address(LOCK_TO_VOTE_BASE),
                abi.encodeCall(
                    LockToVotePlugin.initialize,
                    (
                        dao,
                        lockManager,
                        pluginSettings,
                        targetConfig,
                        pluginMetadata
                    )
                )
            )
        );

        assertEq(address(plugin.dao()), address(dao), "Incorrect DAO");
        assertEq(
            address(plugin.lockManager()),
            address(lockManager),
            "Incorrect lockManager"
        );
    }

    modifier whenCallingUpdateSettings() {
        _;
    }

    function test_RevertWhen_UpdateSettingsWithoutThePermission()
        public
        whenCallingUpdateSettings
    {
        // It should revert
        vm.startPrank(address(bob));
        vm.expectRevert();
        LockToVoteSettings memory newSettings = LockToVoteSettings({
            minApprovalRatio: 600000, // 60%
            minProposalDuration: 5 days
        });
        plugin.updatePluginSettings(newSettings);

        vm.startPrank(address(0x1337));
        vm.expectRevert();
        newSettings = LockToVoteSettings({
            minApprovalRatio: 600000, // 60%
            minProposalDuration: 5 days
        });
        plugin.updatePluginSettings(newSettings);

        (uint32 minApprovalRatio, uint64 minProposalDuration) = plugin
            .settings();
        assertEq(minApprovalRatio, 100_000, "Incorrect minApprovalRatio");
        assertEq(minProposalDuration, 10 days, "Incorrect minProposalDuration");
    }

    function test_WhenUpdateSettingsWithThePermission()
        public
        whenCallingUpdateSettings
    {
        // It should update the values

        // vm.startPrank(alice);
        dao.grant(
            address(plugin),
            alice,
            plugin.UPDATE_VOTING_SETTINGS_PERMISSION_ID()
        );
        LockToVoteSettings memory newSettings = LockToVoteSettings({
            minApprovalRatio: 700000, // 70%
            minProposalDuration: 3 days
        });
        plugin.updatePluginSettings(newSettings);

        (uint32 minApprovalRatio, uint64 minProposalDuration) = plugin
            .settings();
        assertEq(
            minApprovalRatio,
            newSettings.minApprovalRatio,
            "Incorrect minApprovalRatio"
        );
        assertEq(
            minProposalDuration,
            newSettings.minProposalDuration,
            "Incorrect minProposalDuration"
        );
    }

    function test_WhenCallingSupportsInterface() public view {
        // It does not support the empty interface
        assertFalse(plugin.supportsInterface(0x00000000));
        // It supports IERC165Upgradeable
        assertTrue(plugin.supportsInterface(0x01ffc9a7));
        // It supports IMembership
        assertTrue(plugin.supportsInterface(type(IMembership).interfaceId));
        // It supports ILockToVote
        assertTrue(plugin.supportsInterface(type(ILockToVote).interfaceId));
    }

    modifier givenProposalNotCreated() {
        _;
    }

    modifier givenNoProposalCreationPermission() {
        _;
    }

    function test_RevertWhen_CallingCreateProposalNoPerm()
        public
        givenProposalNotCreated
        givenNoProposalCreationPermission
    {
        // It Should revert

        vm.startPrank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(plugin),
                bob,
                CREATE_PROPOSAL_PERMISSION_ID
            )
        );
        proposalId = plugin.createProposal(
            "0x",
            new Action[](0),
            0,
            0,
            abi.encode(uint256(0))
        );

        vm.startPrank(carol);
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(plugin),
                carol,
                CREATE_PROPOSAL_PERMISSION_ID
            )
        );
        proposalId = plugin.createProposal(
            "0x",
            new Action[](0),
            0,
            0,
            abi.encode(uint256(0))
        );

        // OK

        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(plugin),
                david,
                CREATE_PROPOSAL_PERMISSION_ID
            )
        );
        proposalId = plugin.createProposal(
            "0x",
            new Action[](0),
            0,
            0,
            abi.encode(uint256(0))
        );
    }

    modifier givenProposalCreationPermissionGranted() {
        _;
    }

    function test_WhenCallingCreateProposalEmptyDates()
        public
        givenProposalNotCreated
        givenProposalCreationPermissionGranted
    {
        // It Should register the new proposal
        // It Should assign a unique proposalId to it
        // It Should register the given parameters
        // It Should start immediately
        // It Should end after minDuration
        // It Should emit an event
        // It Should call proposalCreated on the lockManager

        vm.expectEmit();
        emit ProposalCreated(
            57321900169284754386507643382684434334472220819073678651923483349408902837995,
            alice,
            block.timestamp.toUint64(),
            (block.timestamp + 10 days).toUint64(),
            "0x",
            new Action[](0),
            0
        );

        proposalId = plugin.createProposal(
            "0x",
            new Action[](0),
            0,
            0,
            abi.encode(uint256(0))
        );

        (
            bool open,
            bool executed,
            ProposalParameters memory parameters,
            uint256 approvalTally,
            Action[] memory actions,
            uint256 allowFailureMap,
            IPlugin.TargetConfig memory targetConfig
        ) = plugin.getProposal(proposalId);

        assertFalse(open);
        assertFalse(executed);
        assertEq(approvalTally, 0);
        assertEq(parameters.startDate, block.timestamp);
        assertEq(parameters.endDate, block.timestamp + 10 days);
        assertEq(parameters.minApprovalRatio, 100_000);
        assertEq(allowFailureMap, 0);
        assertEq(actions.length, 0);
        assertEq(targetConfig.target, address(dao));
        assertEq(uint8(targetConfig.operation), uint8(IPlugin.Operation.Call));

        // Check if proposalCreated was called on the lockManager
        assertEq(lockManager.knownProposalIds(0), proposalId);
    }

    function test_WhenCallingCreateProposalExplicitDates()
        public
        givenProposalNotCreated
        givenProposalCreationPermissionGranted
    {
        // It Should start at the given startDate
        // It Should revert if endDate is before minDuration
        // It Should end on the given endDate
        // It Should call proposalCreated on the lockManager
        // It Should emit an event

        uint64 startDate = (block.timestamp + 7 days).toUint64();
        uint64 endDate = uint64(startDate + 7 days);
        Action[] memory actions = new Action[](1);
        actions[0].to = alice;
        actions[0].value = 0.01 ether;

        vm.expectEmit();
        emit ProposalCreated(
            57321900169284754386507643382684434334472220819073678651923483349408902837995,
            alice,
            startDate,
            endDate,
            "0x",
            actions,
            0
        );

        proposalId = plugin.createProposal(
            "0x",
            actions,
            startDate,
            endDate,
            abi.encode(uint256(5))
        );

        (
            bool open,
            bool executed,
            ProposalParameters memory parameters,
            uint256 approvalTally,
            Action[] memory pActions,
            uint256 allowFailureMap,
            IPlugin.TargetConfig memory targetConfig
        ) = plugin.getProposal(proposalId);

        assertEq(
            proposalId,
            57321900169284754386507643382684434334472220819073678651923483349408902837995
        );
        assertFalse(open);
        assertFalse(executed);
        assertEq(approvalTally, 0);
        assertEq(parameters.startDate, startDate);
        assertEq(parameters.endDate, endDate);
        assertEq(parameters.minApprovalRatio, 100_000);
        assertEq(targetConfig.target, address(dao));
        assertEq(uint8(targetConfig.operation), uint8(IPlugin.Operation.Call));
        assertEq(allowFailureMap, 5);
        assertEq(pActions.length, 1);
        assertEq(pActions[0].to, alice);
        assertEq(pActions[0].value, 0.01 ether);

        // Check if proposalCreated was called on the lockManager
        assertEq(lockManager.knownProposalIds(0), proposalId);

        // Revert if endDate is before minDuration
        vm.expectRevert();
        proposalId = plugin.createProposal(
            "0x",
            new Action[](0),
            startDate,
            startDate,
            abi.encode(uint256(0))
        );

        vm.expectRevert();
        proposalId = plugin.createProposal(
            "0x",
            new Action[](0),
            startDate,
            endDate - 1,
            abi.encode(uint256(0))
        );
    }

    function test_WhenCallingTheGettersNotCreated()
        public
        givenProposalNotCreated
    {
        // It getProposal should return empty values
        // It isProposalOpen should return false
        // It canVote should return false
        // It hasSucceeded should return false
        // It canExecute should return false

        proposalId = 0;

        (
            bool open,
            bool executed,
            ProposalParameters memory parameters,
            uint256 approvalTally,
            Action[] memory actions,
            uint256 allowFailureMap,
            IPlugin.TargetConfig memory targetConfig
        ) = plugin.getProposal(proposalId);

        assertFalse(open);
        assertFalse(executed);
        assertEq(parameters.startDate, 0);
        assertEq(parameters.endDate, 0);
        assertEq(parameters.minApprovalRatio, 0);
        assertEq(approvalTally, 0);
        assertEq(actions.length, 0);
        assertEq(allowFailureMap, 0);
        assertEq(targetConfig.target, address(0));
        assertEq(uint8(targetConfig.operation), uint8(0));

        assertFalse(plugin.isProposalOpen(proposalId));
        assertFalse(plugin.canVote(proposalId, alice));
        assertFalse(plugin.hasSucceeded(proposalId));
        assertFalse(plugin.canExecute(proposalId));
    }

    function test_WhenCallingTheRestOfMethods() public givenProposalNotCreated {
        // It Should revert, even with the required permissions

        proposalId = 0;

        vm.startPrank(address(lockManager));
        vm.expectRevert(
            abi.encodeWithSelector(
                ILockToVote.VoteCastForbidden.selector,
                proposalId,
                alice
            )
        );
        plugin.vote(proposalId, alice, 0.1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILockToVote.ExecutionForbidden.selector,
                proposalId
            )
        );
        plugin.execute(proposalId);
    }

    modifier givenProposalCreated() {
        Action[] memory actions = new Action[](1);
        actions[0].to = address(dao);
        actions[0].value = 0.01 ether;
        actions[0].data = abi.encodeCall(DAO.setMetadata, "0x");

        proposalId = plugin.createProposal(
            "0x5555",
            actions,
            0,
            0,
            abi.encode(uint256(7))
        );
        _;
    }

    function test_WhenCallingGetProposal() public givenProposalCreated {
        // It Should return the right values
        (
            bool open,
            bool executed,
            ProposalParameters memory parameters,
            uint256 approvalTally,
            Action[] memory actions,
            uint256 allowFailureMap,
            IPlugin.TargetConfig memory targetConfig
        ) = plugin.getProposal(proposalId);

        assertTrue(open);
        assertFalse(executed);
        assertEq(parameters.startDate, block.timestamp);
        assertEq(parameters.endDate, block.timestamp + 10 days);
        assertEq(parameters.minApprovalRatio, 100_000);
        assertEq(approvalTally, 0);
        assertEq(actions.length, 1);
        assertEq(actions[0].to, address(dao));
        assertEq(actions[0].value, 0.01 ether);
        assertEq(actions[0].data, abi.encodeCall(DAO.setMetadata, "0x"));
        assertEq(allowFailureMap, 7);
        assertEq(targetConfig.target, address(dao));
        assertEq(uint8(targetConfig.operation), uint8(IPlugin.Operation.Call));
    }

    function test_WhenCallingIsProposalOpen() public givenProposalCreated {
        // It Should return true
        assertTrue(plugin.isProposalOpen(proposalId));

        // KO
        assertFalse(plugin.isProposalOpen(0));
        assertFalse(plugin.isProposalOpen(1));
        assertFalse(plugin.isProposalOpen(1234));
        assertFalse(plugin.isProposalOpen(proposalId + 1));
    }

    function test_WhenCallingCanVote() public givenProposalCreated {
        // It Should return true when there is balance left to allocate

        lockableToken.approve(address(lockManager), 0.1 ether);
        lockManager.lock();
        assertTrue(plugin.canVote(proposalId, alice));

        // It Should return false when there is no balance left to allocate
        lockManager.vote(proposalId);
        assertFalse(plugin.canVote(proposalId, alice));

        vm.startPrank(bob);
        assertFalse(plugin.canVote(proposalId, bob));
    }

    modifier givenNoLockManagerPermission() {
        dao.revoke(
            address(lockManager),
            address(plugin),
            LOCK_MANAGER_PERMISSION_ID
        );
        _;
    }

    function test_WhenCallingVote()
        public
        givenProposalCreated
        givenNoLockManagerPermission
    {
        // It Reverts, regardless of the balance

        vm.startPrank(address(lockManager));

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(plugin),
                address(lockManager),
                LOCK_MANAGER_PERMISSION_ID
            )
        );
        plugin.vote(proposalId, alice, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(plugin),
                address(lockManager),
                LOCK_MANAGER_PERMISSION_ID
            )
        );
        plugin.vote(proposalId, bob, 100);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(plugin),
                address(lockManager),
                LOCK_MANAGER_PERMISSION_ID
            )
        );
        plugin.vote(proposalId, carol, 100000);

        // OK
        dao.grant(
            address(lockManager),
            address(plugin),
            LOCK_MANAGER_PERMISSION_ID
        );
        plugin.vote(proposalId, carol, 100000);
    }

    function test_WhenCallingClearVote()
        public
        givenProposalCreated
        givenNoLockManagerPermission
    {
        // It Reverts, regardless of the balance

        vm.startPrank(address(lockManager));

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(plugin),
                address(lockManager),
                LOCK_MANAGER_PERMISSION_ID
            )
        );
        plugin.clearVote(proposalId, alice);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(plugin),
                address(lockManager),
                LOCK_MANAGER_PERMISSION_ID
            )
        );
        plugin.clearVote(proposalId, bob);
    }

    modifier givenLockManagerPermissionIsGranted() {
        _;
    }

    function test_GivenProposalCreatedUnstarted()
        public
        givenProposalCreated
        givenLockManagerPermissionIsGranted
    {
        // It Calling vote should revert, with or without balance

        proposalId = plugin.createProposal(
            "0x",
            new Action[](0),
            uint64(block.timestamp + 1 days), // future start
            0,
            ""
        );

        vm.startPrank(address(lockManager));

        vm.expectRevert(
            abi.encodeWithSelector(
                ILockToVote.VoteCastForbidden.selector,
                proposalId,
                alice
            )
        );
        plugin.vote(proposalId, alice, 0.1 ether);

        // 2
        vm.expectRevert(
            abi.encodeWithSelector(
                ILockToVote.VoteCastForbidden.selector,
                proposalId,
                bob
            )
        );
        plugin.vote(proposalId, bob, 0.1 ether);

        // 2
        vm.expectRevert(
            abi.encodeWithSelector(
                ILockToVote.VoteCastForbidden.selector,
                proposalId,
                carol
            )
        );
        plugin.vote(proposalId, carol, 0.1 ether);
    }

    modifier givenProposalCreatedAndStarted() {
        proposalId = plugin.createProposal(
            "0x",
            new Action[](0),
            0,
            0,
            abi.encode(uint256(0))
        );

        _;
    }

    function test_RevertWhen_CallingVoteNoNewLockedBalance()
        public
        givenProposalCreated
        givenLockManagerPermissionIsGranted
        givenProposalCreatedAndStarted
    {
        // It Should revert

        lockableToken.approve(address(lockManager), 0.1 ether);
        lockManager.lock();
        lockManager.vote(proposalId);

        vm.expectRevert();
        lockManager.vote(proposalId);

        vm.startPrank(address(lockManager));
        plugin.vote(proposalId, alice, 0.1 ether);
    }

    function test_WhenCallingVoteNewLockedBalance()
        public
        givenProposalCreated
        givenLockManagerPermissionIsGranted
        givenProposalCreatedAndStarted
    {
        // It Should increase the tally by the new amount
        // It Should emit an event

        vm.startPrank(address(lockManager));

        vm.expectEmit();
        emit VoteCast(proposalId, alice, 0.1 ether);
        plugin.vote(proposalId, alice, 0.1 ether);

        (, , , uint256 approvalTally, , , ) = plugin.getProposal(proposalId);
        assertEq(approvalTally, 0.1 ether);
        assertEq(plugin.usedVotingPower(proposalId, alice), 0.1 ether);

        vm.expectEmit();
        emit VoteCast(proposalId, alice, 0.25 ether);
        plugin.vote(proposalId, alice, 0.25 ether);

        (, , , approvalTally, , , ) = plugin.getProposal(proposalId);
        assertEq(approvalTally, 0.25 ether);
        assertEq(plugin.usedVotingPower(proposalId, alice), 0.25 ether);
    }

    function test_WhenCallingClearVoteNoVoteBalance()
        public
        givenProposalCreated
        givenLockManagerPermissionIsGranted
        givenProposalCreatedAndStarted
    {
        // It Should do nothing

        vm.startPrank(address(lockManager));
        plugin.clearVote(proposalId, alice);

        (, , , uint256 approvalTally, , , ) = plugin.getProposal(proposalId);
        assertEq(approvalTally, 0);

        plugin.clearVote(proposalId, bob);

        (, , , approvalTally, , , ) = plugin.getProposal(proposalId);
        assertEq(approvalTally, 0);
    }

    function test_WhenCallingClearVoteWithVoteBalance()
        public
        givenProposalCreated
        givenLockManagerPermissionIsGranted
        givenProposalCreatedAndStarted
    {
        // It Should unassign the current voter's approval
        // It Should decrease the proposal tally by the right amount
        // It Should emit an event
        // It usedVotingPower should return the right value

        vm.startPrank(address(lockManager));
        plugin.vote(proposalId, alice, 0.1 ether);

        (, , , uint256 approvalTally, , , ) = plugin.getProposal(proposalId);
        assertEq(approvalTally, 0.1 ether);
        assertEq(plugin.usedVotingPower(proposalId, alice), 0.1 ether);

        vm.expectEmit();
        emit VoteCleared(proposalId, alice);
        plugin.clearVote(proposalId, alice);

        (, , , approvalTally, , , ) = plugin.getProposal(proposalId);
        assertEq(approvalTally, 0);
        assertEq(plugin.usedVotingPower(proposalId, alice), 0);
    }

    function test_WhenCallingHasSucceededCanExecuteCreated()
        public
        givenProposalCreated
    {
        // It hasSucceeded should return false
        // It canExecute should return false

        assertFalse(plugin.hasSucceeded(proposalId));
        assertFalse(plugin.canExecute(proposalId));
    }

    function test_WhenCallingExecuteCreated() public givenProposalCreated {
        // It Should revert, even with the required permission
        vm.expectRevert(
            abi.encodeWithSelector(
                ILockToVote.ExecutionForbidden.selector,
                proposalId
            )
        );
        plugin.execute(proposalId);
    }

    modifier givenProposalDefeated() {
        proposalId = plugin.createProposal(
            "0x",
            new Action[](0),
            0,
            0,
            abi.encode(uint256(123))
        );

        vm.startPrank(address(lockManager));
        plugin.vote(proposalId, alice, 0.001 ether);

        vm.startPrank(alice);
        vm.warp(block.timestamp + 10 days);

        _;
    }

    function test_WhenCallingTheGettersDefeated() public givenProposalDefeated {
        // It getProposal should return the right values
        // It isProposalOpen should return false
        // It canVote should return false
        // It hasSucceeded should return false
        // It canExecute should return false

        (
            bool open,
            bool executed,
            ProposalParameters memory parameters,
            uint256 approvalTally,
            Action[] memory actions,
            uint256 allowFailureMap,
            IPlugin.TargetConfig memory targetConfig
        ) = plugin.getProposal(proposalId);

        assertFalse(open);
        assertFalse(executed);
        assertEq(parameters.startDate, block.timestamp - 10 days);
        assertEq(parameters.endDate, block.timestamp);
        assertEq(parameters.minApprovalRatio, 100_000);
        assertEq(approvalTally, 0.001 ether);
        assertEq(actions.length, 0);
        assertEq(allowFailureMap, 123);
        assertEq(targetConfig.target, address(dao));
        assertEq(uint8(targetConfig.operation), uint8(IPlugin.Operation.Call));

        assertFalse(plugin.isProposalOpen(proposalId));
        assertFalse(plugin.canVote(proposalId, alice));
        assertFalse(plugin.hasSucceeded(proposalId));
        assertFalse(plugin.canExecute(proposalId));
    }

    function test_WhenCallingVoteOrClearVoteDefeated()
        public
        givenProposalDefeated
    {
        // It Should revert for vote, despite having the permission
        // It Should do nothing for clearVote

        vm.startPrank(address(lockManager));

        vm.expectRevert(
            abi.encodeWithSelector(
                ILockToVote.VoteCastForbidden.selector,
                proposalId,
                alice
            )
        );
        plugin.vote(proposalId, alice, 1);

        // Nop
        plugin.clearVote(proposalId, alice);
    }

    function test_WhenCallingExecuteDefeated() public givenProposalDefeated {
        // It Should revert, with or without permission
        vm.expectRevert(
            abi.encodeWithSelector(
                ILockToVote.ExecutionForbidden.selector,
                proposalId
            )
        );
        plugin.execute(proposalId);
    }

    modifier givenProposalPassed() {
        proposalId = plugin.createProposal(
            "0x",
            new Action[](0),
            0,
            0,
            abi.encode(uint256(0))
        );

        lockableToken.approve(address(lockManager), 0.1 ether);
        lockManager.lock();

        vm.startPrank(carol);
        lockableToken.approve(address(lockManager), 10 ether);
        lockManager.lock();

        vm.startPrank(david);
        lockableToken.approve(address(lockManager), 15 ether);
        lockManager.lock();

        vm.startPrank(address(lockManager));
        plugin.vote(proposalId, alice, 0.1 ether);
        plugin.vote(proposalId, address(carol), 10 ether);
        plugin.vote(proposalId, address(david), 15 ether);

        vm.startPrank(alice);

        // The consumer needs to advance to block.timestamp + 10 days

        _;
    }

    function test_WhenCallingTheGettersPassed() public givenProposalPassed {
        // It getProposal should return the right values
        // It isProposalOpen should return false
        // It canVote should return false
        // It hasSucceeded should return true
        // It canExecute should return true

        (
            bool open,
            bool executed,
            ProposalParameters memory parameters,
            uint256 approvalTally,
            Action[] memory actions,
            uint256 allowFailureMap,
            IPlugin.TargetConfig memory targetConfig
        ) = plugin.getProposal(proposalId);

        assertTrue(open);
        assertFalse(executed);
        assertEq(parameters.startDate, block.timestamp);
        assertEq(parameters.endDate, block.timestamp + 10 days);
        assertEq(parameters.minApprovalRatio, 100_000);
        assertEq(approvalTally, 25.1 ether);
        assertEq(actions.length, 0);
        assertEq(allowFailureMap, 0);
        assertEq(targetConfig.target, address(dao));
        assertEq(uint8(targetConfig.operation), uint8(IPlugin.Operation.Call));

        assertTrue(plugin.isProposalOpen(proposalId));
        assertFalse(plugin.canVote(proposalId, alice));
        assertTrue(plugin.hasSucceeded(proposalId));
        assertTrue(plugin.canExecute(proposalId));

        // If not executed, after endDate

        vm.warp(block.timestamp + 10 days);

        (open, , parameters, , , , ) = plugin.getProposal(proposalId);
        assertEq(parameters.startDate, block.timestamp - 10 days);
        assertEq(parameters.endDate, block.timestamp);
        assertFalse(open);
    }

    function test_WhenCallingVoteOrClearVotePassed()
        public
        givenProposalPassed
    {
        // It Should revert, despite having the permission

        vm.warp(block.timestamp + 10 days);

        vm.startPrank(address(lockManager));

        vm.expectRevert(
            abi.encodeWithSelector(
                ILockToVote.VoteCastForbidden.selector,
                proposalId,
                alice
            )
        );
        plugin.vote(proposalId, alice, 1);

        // Nop
        (, , , uint256 approvalTally, , , ) = plugin.getProposal(proposalId);
        assertEq(approvalTally, 25.1 ether);
        assertEq(plugin.usedVotingPower(proposalId, alice), 0.1 ether);

        plugin.clearVote(proposalId, alice);

        (, , , approvalTally, , , ) = plugin.getProposal(proposalId);
        assertEq(approvalTally, 25.1 ether);
        assertEq(plugin.usedVotingPower(proposalId, alice), 0.1 ether);
    }

    modifier givenNoExecuteProposalPermission() {
        // Redundant, but just in case
        dao.revoke(address(plugin), alice, EXECUTE_PROPOSAL_PERMISSION_ID);
        _;
    }

    function test_RevertWhen_CallingExecuteNoPerm()
        public
        givenProposalPassed
        givenNoExecuteProposalPermission
    {
        // It Should revert

        // alice
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(plugin),
                alice,
                CREATE_PROPOSAL_PERMISSION_ID
            )
        );
        plugin.execute(proposalId);
    }

    modifier givenExecuteProposalPermission() {
        dao.grant(address(plugin), alice, EXECUTE_PROPOSAL_PERMISSION_ID);

        _;
    }

    function test_WhenCallingExecutePassed()
        public
        givenProposalPassed
        givenExecuteProposalPermission
    {
        // It Should execute the actions of the proposal on the target
        // It Should call proposalEnded on the LockManager
        // It Should emit an event

        vm.warp(block.timestamp + 10 days);

        vm.expectEmit();
        emit Executed(proposalId);

        vm.expectEmit();
        emit ProposalEnded(proposalId);

        plugin.execute(proposalId);

        (bool open, bool executed, , , , , ) = plugin.getProposal(proposalId);
        assertFalse(open);
        assertTrue(executed);

        // Check if proposalEnded was called on the lockManager
        vm.expectRevert();
        lockManager.knownProposalIds(0);
    }

    modifier givenProposalExecuted() {
        Action[] memory actions = new Action[](1);
        actions[0].to = address(dao);
        actions[0].value = 0 ether;
        actions[0].data = abi.encodeCall(DAO.setMetadata, "hello");

        proposalId = plugin.createProposal(
            "0x",
            actions,
            0,
            0,
            abi.encode(uint256(1))
        );

        lockableToken.approve(address(lockManager), 0.1 ether);
        lockManager.lock();

        vm.startPrank(carol);
        lockableToken.approve(address(lockManager), 10 ether);
        lockManager.lock();

        vm.startPrank(david);
        lockableToken.approve(address(lockManager), 15 ether);
        lockManager.lock();

        vm.startPrank(address(lockManager));
        plugin.vote(proposalId, alice, 0.1 ether);
        plugin.vote(proposalId, address(carol), 10 ether);
        plugin.vote(proposalId, address(david), 15 ether);

        vm.startPrank(alice);
        dao.grant(address(plugin), alice, EXECUTE_PROPOSAL_PERMISSION_ID);

        plugin.execute(proposalId);

        _;
    }

    function test_WhenCallingTheGettersExecuted() public givenProposalExecuted {
        // It getProposal should return the right values
        // It isProposalOpen should return false
        // It canVote should return false
        // It hasSucceeded should return false
        // It canExecute should return false

        (
            bool open,
            bool executed,
            ProposalParameters memory parameters,
            uint256 approvalTally,
            Action[] memory actions,
            uint256 allowFailureMap,
            IPlugin.TargetConfig memory targetConfig
        ) = plugin.getProposal(proposalId);

        assertFalse(open);
        assertTrue(executed);
        assertEq(parameters.startDate, block.timestamp);
        assertEq(parameters.endDate, block.timestamp + 10 days);
        assertEq(parameters.minApprovalRatio, 100_000);
        assertEq(approvalTally, 25.1 ether);
        assertEq(actions.length, 1);
        assertEq(actions[0].to, address(dao));
        assertEq(actions[0].value, 0);
        assertEq(actions[0].data, abi.encodeCall(DAO.setMetadata, "hello"));
        assertEq(allowFailureMap, 1);
        assertEq(targetConfig.target, address(dao));
        assertEq(uint8(targetConfig.operation), uint8(IPlugin.Operation.Call));

        assertFalse(plugin.isProposalOpen(proposalId));
        assertFalse(plugin.canVote(proposalId, alice));
        assertTrue(plugin.hasSucceeded(proposalId));
        assertFalse(plugin.canExecute(proposalId));
    }

    function test_WhenCallingVoteOrClearVoteExecuted()
        public
        givenProposalExecuted
    {
        // It Should revert, despite having the permission

        vm.startPrank(address(lockManager));

        vm.expectRevert(
            abi.encodeWithSelector(
                ILockToVote.VoteCastForbidden.selector,
                proposalId,
                alice
            )
        );
        plugin.vote(proposalId, alice, 200 ether);

        // Nop
        (, , , uint256 approvalTally, , , ) = plugin.getProposal(proposalId);
        assertEq(approvalTally, 25.1 ether);
        assertEq(plugin.usedVotingPower(proposalId, alice), 0.1 ether);

        plugin.clearVote(proposalId, alice);

        (, , , approvalTally, , , ) = plugin.getProposal(proposalId);
        assertEq(approvalTally, 25.1 ether);
        assertEq(plugin.usedVotingPower(proposalId, alice), 0.1 ether);
    }

    function test_WhenCallingExecuteExecuted() public givenProposalExecuted {
        // It Should revert regardless of the permission

        vm.expectRevert(
            abi.encodeWithSelector(
                ILockToVote.ExecutionForbidden.selector,
                proposalId
            )
        );
        plugin.execute(proposalId);
    }

    function test_WhenCallingIsMember() public {
        // It Should return true when the sender has positive balance or locked tokens
        // It Should return false otherwise

        assertEq(lockableToken.balanceOf(address(0x1234)), 0);
        assertFalse(plugin.isMember(address(0x1234)));
        assertEq(lockableToken.balanceOf(address(0x2345)), 0);
        assertFalse(plugin.isMember(address(0x2345)));

        assertTrue(lockableToken.balanceOf(alice) > 0);
        assertTrue(plugin.isMember(alice));
        assertTrue(lockableToken.balanceOf(bob) > 0);
        assertTrue(plugin.isMember(address(bob)));

        lockableToken.approve(address(lockManager), 0.1 ether);
        lockManager.lock();
        assertTrue(plugin.isMember(alice));

        vm.startPrank(bob);
        lockableToken.approve(address(lockManager), 0.1 ether);
        lockManager.lock();
        assertTrue(plugin.isMember(address(bob)));
    }

    function test_WhenCallingCustomProposalParamsABI() public view {
        // It Should return the right value
        assertEq(plugin.customProposalParamsABI(), "(uint256 allowFailureMap)");
    }

    modifier givenUpdateVotingSettingsPermissionGranted() {
        dao.grant(address(plugin), alice, UPDATE_VOTING_SETTINGS_PERMISSION_ID);
        _;
    }

    function test_WhenCallingUpdatePluginSettingsGranted()
        public
        givenUpdateVotingSettingsPermissionGranted
    {
        // It Should set the new values
        // It Settings() should return the right values

        LockToVoteSettings memory newSettings = LockToVoteSettings({
            minApprovalRatio: 612345, // 61%
            minProposalDuration: 13.4 days
        });

        plugin.updatePluginSettings(newSettings);

        (uint32 minApprovalRatio, uint64 minProposalDuration) = plugin
            .settings();
        assertEq(minApprovalRatio, 612345);
        assertEq(minProposalDuration, 13.4 days);
    }

    modifier givenNoUpdateVotingSettingsPermission() {
        dao.revoke(
            address(plugin),
            alice,
            UPDATE_VOTING_SETTINGS_PERMISSION_ID
        );
        _;
    }

    function test_RevertWhen_CallingUpdatePluginSettingsNotGranted()
        public
        givenNoUpdateVotingSettingsPermission
    {
        // It Should revert

        LockToVoteSettings memory newSettings = LockToVoteSettings({
            minApprovalRatio: 612345, // 61%
            minProposalDuration: 13.4 days
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(plugin),
                alice,
                UPDATE_VOTING_SETTINGS_PERMISSION_ID
            )
        );
        plugin.updatePluginSettings(newSettings);

        (uint32 minApprovalRatio, uint64 minProposalDuration) = plugin
            .settings();
        assertEq(minApprovalRatio, 100000);
        assertEq(minProposalDuration, 10 days);
    }
}
