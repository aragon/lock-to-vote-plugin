// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {TestBase} from "./lib/TestBase.sol";
import {LockToApprovePlugin} from "../src/LockToApprovePlugin.sol";
import {LockManager} from "../src/LockManager.sol";
import {LockManagerSettings, UnlockMode, PluginMode} from "../src/interfaces/ILockManager.sol";
import {ILockToApprove} from "../src/interfaces/ILockToApprove.sol";
import {DaoBuilder} from "./builders/DaoBuilder.sol";
import {DAO, IDAO} from "@aragon/osx/src/core/dao/DAO.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {TestToken} from "./mocks/TestToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IMembership} from "@aragon/osx-commons-contracts/src/plugin/extensions/membership/IMembership.sol";
import {IProposal} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {createProxyAndCall, createSaltedProxyAndCall, predictProxyAddress} from "../src/util/proxy.sol";

contract LockToApproveTest is TestBase {
    using SafeCastUpgradeable for uint256;

    DaoBuilder builder;
    DAO dao;
    LockToApprovePlugin plugin;
    LockManager lockManager;
    IERC20 lockableToken;
    IERC20 underlyingToken;
    uint256 proposalId;

    address immutable LOCK_TO_APPROVE_BASE = address(new LockToApprovePlugin());
    address immutable LOCK_MANAGER_BASE = address(
        new LockManager(
            IDAO(address(0)),
            LockManagerSettings(UnlockMode.Strict, PluginMode.Approval),
            IERC20(address(0)),
            IERC20(address(0))
        )
    );

    bytes32 constant CREATE_PROPOSAL_PERMISSION_ID = keccak256("CREATE_PROPOSAL_PERMISSION");
    bytes32 constant EXECUTE_PROPOSAL_PERMISSION_ID = keccak256("EXECUTE_PROPOSAL_PERMISSION");
    bytes32 constant LOCK_MANAGER_PERMISSION_ID = keccak256("LOCK_MANAGER_PERMISSION");
    bytes32 constant UPDATE_SETTINGS_PERMISSION_ID = keccak256("UPDATE_SETTINGS_PERMISSION");

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed creator,
        uint64 startDate,
        uint64 endDate,
        bytes metadata,
        Action[] actions,
        uint256 allowFailureMap
    );

    event ApprovalCast(uint256 proposalId, address voter, uint256 newVotingPower);
    event ProposalEnded(uint256 proposalId);
    event ApprovalCleared(uint256 proposalId, address voter);
    event ProposalExecuted(uint256 indexed proposalId);

    error AlreadyInitialized();

    function setUp() public {
        vm.startPrank(alice);
        vm.warp(10 days);
        vm.roll(100);

        builder = new DaoBuilder();
        (dao, plugin,, lockManager, lockableToken, underlyingToken) = builder.withTokenHolder(alice, 1 ether)
            .withTokenHolder(bob, 10 ether).withTokenHolder(carol, 10 ether).withTokenHolder(david, 15 ether)
            .withApprovalPlugin().build();
        // .withStrictUnlock()
        // .withMinApprovalRatio(100_000)
        // .withDuration(10 days)
    }

    function test_WhenDeployingTheContract() public {
        // It should disable the initializers

        vm.expectRevert();
        plugin.initialize(
            dao,
            lockManager,
            LockToApprovePlugin.ApprovalSettings({
                minApprovalRatio: 100_000, // 10%
                proposalDuration: 10 days,
                minProposerVotingPower: 0
            }),
            IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.Call}),
            abi.encode(uint256(0))
        );
    }

    function test_GivenADeployedContract() external {
        // It should refuse to initialize again
        vm.expectRevert(AlreadyInitialized.selector);
        plugin.initialize(
            dao,
            lockManager,
            LockToApprovePlugin.ApprovalSettings({
                minApprovalRatio: 100_000, // 10%
                proposalDuration: 10 days,
                minProposerVotingPower: 0
            }),
            IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.Call}),
            abi.encode(uint256(0))
        );
    }

    modifier givenANewProxy() {
        _;
    }

    function test_GivenCallingInitialize() external givenANewProxy {
        // It should set the DAO address
        // It should define the approval settings
        // It should define the target config
        // It should define the plugin metadata
        // It should define the lock manager

        LockToApprovePlugin newPlugin;
        LockManager newLockManager;
        DAO newDao =
            DAO(payable(createProxyAndCall(DAO_BASE, abi.encodeCall(DAO.initialize, ("", alice, address(0x0), "")))));
        TestToken newToken = new TestToken();

        LockToApprovePlugin.ApprovalSettings memory settings = LockToApprovePlugin.ApprovalSettings({
            minApprovalRatio: 110_000, // 11%
            proposalDuration: 12 days,
            minProposerVotingPower: 1234
        });
        IPlugin.TargetConfig memory targetConfig =
            IPlugin.TargetConfig({target: address(newDao), operation: IPlugin.Operation.Call});
        bytes memory pluginMetadata = "ipfs://1234";

        newLockManager = new LockManager(
            newDao, LockManagerSettings(UnlockMode.Standard, PluginMode.Approval), newToken, IERC20(address(0))
        );

        newPlugin = LockToApprovePlugin(
            createProxyAndCall(
                address(LOCK_TO_APPROVE_BASE),
                abi.encodeCall(
                    LockToApprovePlugin.initialize, (newDao, newLockManager, settings, targetConfig, pluginMetadata)
                )
            )
        );

        // It should set the DAO address
        assertEq(address(newPlugin.dao()), address(newDao));

        // It should define the approval settings
        (uint32 _ratio, uint64 _duration, uint256 _minVp) = newPlugin.settings();
        assertEq(_ratio, settings.minApprovalRatio);
        assertEq(_duration, settings.proposalDuration);
        assertEq(_minVp, settings.minProposerVotingPower);

        // It should define the target config
        IPlugin.TargetConfig memory config = newPlugin.getCurrentTargetConfig();
        assertEq(config.target, targetConfig.target);
        assertEq(uint8(config.operation), uint8(targetConfig.operation));

        // It should define the lock manager
        assertEq(address(newPlugin.lockManager()), address(newLockManager));
    }

    function test_WhenCallingInitialize() public givenANewProxy {
        // It should set the DAO address
        // It should initialize normally
        // It should define the given settings

        LockToApprovePlugin.ApprovalSettings memory settings = LockToApprovePlugin.ApprovalSettings({
            minApprovalRatio: 110_000, // 11%
            proposalDuration: 12 days,
            minProposerVotingPower: 1234
        });
        IPlugin.TargetConfig memory targetConfig =
            IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.Call});
        bytes memory pluginMetadata = "";

        plugin = LockToApprovePlugin(
            createProxyAndCall(
                address(LOCK_TO_APPROVE_BASE),
                abi.encodeCall(
                    LockToApprovePlugin.initialize, (dao, lockManager, settings, targetConfig, pluginMetadata)
                )
            )
        );

        assertEq(address(plugin.dao()), address(dao), "Incorrect DAO");
        assertEq(address(plugin.lockManager()), address(lockManager), "Incorrect lockManager");

        (uint32 _ratio, uint64 _duration, uint256 _minVp) = plugin.settings();
        assertEq(_ratio, settings.minApprovalRatio);
        assertEq(_duration, settings.proposalDuration);
        assertEq(_minVp, settings.minProposerVotingPower);
    }

    modifier whenCallingUpdateSettings() {
        _;
    }

    function test_RevertWhen_UpdateSettingsWithoutThePermission() public whenCallingUpdateSettings {
        // It should revert
        vm.startPrank(address(bob));
        vm.expectRevert();
        LockToApprovePlugin.ApprovalSettings memory newSettings = LockToApprovePlugin.ApprovalSettings({
            minApprovalRatio: 600000, // 60%
            proposalDuration: 5 days,
            minProposerVotingPower: 500_000_000
        });
        plugin.updateApprovalSettings(newSettings);

        vm.startPrank(address(0x1337));
        vm.expectRevert();
        newSettings = LockToApprovePlugin.ApprovalSettings({
            minApprovalRatio: 800000, // 80%
            proposalDuration: 7 days,
            minProposerVotingPower: 200
        });
        plugin.updateApprovalSettings(newSettings);

        (uint32 minApprovalRatio, uint64 proposalDuration, uint256 minPvp) = plugin.settings();
        assertEq(minApprovalRatio, 100_000, "Incorrect minApprovalRatio");
        assertEq(proposalDuration, 10 days, "Incorrect proposalDuration");
        assertEq(minPvp, 0, "Incorrect minProposerVotingPower");
    }

    function test_WhenUpdateSettingsWithThePermission() public whenCallingUpdateSettings {
        // It should update the values

        // vm.startPrank(alice);
        dao.grant(address(plugin), alice, plugin.UPDATE_SETTINGS_PERMISSION_ID());
        LockToApprovePlugin.ApprovalSettings memory newSettings = LockToApprovePlugin.ApprovalSettings({
            minApprovalRatio: 700000, // 70%
            proposalDuration: 3 days,
            minProposerVotingPower: 0
        });
        plugin.updateApprovalSettings(newSettings);

        (uint32 minApprovalRatio, uint64 proposalDuration, uint256 minPvp) = plugin.settings();
        assertEq(minApprovalRatio, newSettings.minApprovalRatio, "Incorrect minApprovalRatio");
        assertEq(proposalDuration, newSettings.proposalDuration, "Incorrect proposalDuration");
        assertEq(minPvp, newSettings.minProposerVotingPower, "Incorrect minProposerVotingPower");
    }

    function test_WhenCallingSupportsInterface() public view {
        // It does not support the empty interface
        assertFalse(plugin.supportsInterface(0x00000000));
        // It supports IERC165Upgradeable
        assertTrue(plugin.supportsInterface(0x01ffc9a7));
        // It supports IMembership
        assertTrue(plugin.supportsInterface(type(IMembership).interfaceId));
        // It supports ILockToApprove
        assertTrue(plugin.supportsInterface(type(ILockToApprove).interfaceId));
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
                DaoUnauthorized.selector, address(dao), address(plugin), bob, CREATE_PROPOSAL_PERMISSION_ID
            )
        );
        proposalId = plugin.createProposal("0x", new Action[](0), 0, 0, abi.encode(uint256(0)));

        vm.startPrank(carol);
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(plugin), carol, CREATE_PROPOSAL_PERMISSION_ID
            )
        );
        proposalId = plugin.createProposal("0x", new Action[](0), 0, 0, abi.encode(uint256(0)));

        // OK

        vm.startPrank(alice);
        proposalId = plugin.createProposal("0x", new Action[](0), 0, 0, abi.encode(uint256(0)));
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
        // It Should end after proposalDuration
        // It Should emit an event
        // It Should call proposalCreated on the lockManager

        vm.expectEmit();
        emit ProposalCreated(
            13876840710005004095411466095926402277614448292371379428030366522978619098280,
            alice,
            block.timestamp.toUint64(),
            (block.timestamp + 10 days).toUint64(),
            "hello",
            new Action[](0),
            3
        );

        proposalId = plugin.createProposal("hello", new Action[](0), 0, 0, abi.encode(uint256(3)));

        (
            bool open,
            bool executed,
            LockToApprovePlugin.ProposalParameters memory parameters,
            uint256 approvalTally,
            Action[] memory actions,
            uint256 allowFailureMap,
            IPlugin.TargetConfig memory targetConfig
        ) = plugin.getProposal(proposalId);

        assertTrue(open);
        assertFalse(executed);
        assertEq(approvalTally, 0);
        assertEq(parameters.startDate, block.timestamp);
        assertEq(parameters.endDate, block.timestamp + 10 days);
        assertEq(parameters.minApprovalRatio, 100_000);
        assertEq(allowFailureMap, 3);
        assertEq(actions.length, 0);
        assertEq(targetConfig.target, address(dao));
        assertEq(uint8(targetConfig.operation), uint8(IPlugin.Operation.Call));

        // Check if proposalCreated was called on the lockManager
        assertEq(lockManager.knownProposalIdAt(0), proposalId);
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
        uint64 endDate = uint64(startDate + 10 days);
        Action[] memory actions = new Action[](1);
        actions[0].to = alice;
        actions[0].value = 0.01 ether;

        vm.expectEmit();
        emit ProposalCreated(
            77014594595155826630278684923227134408666612923500769942032796858285014477046,
            alice,
            startDate,
            endDate,
            "0x",
            actions,
            5
        );

        proposalId = plugin.createProposal("0x", actions, startDate, endDate, abi.encode(uint256(5)));

        (
            bool open,
            bool executed,
            LockToApprovePlugin.ProposalParameters memory parameters,
            uint256 approvalTally,
            Action[] memory pActions,
            uint256 allowFailureMap,
            IPlugin.TargetConfig memory targetConfig
        ) = plugin.getProposal(proposalId);

        assertEq(proposalId, 77014594595155826630278684923227134408666612923500769942032796858285014477046);
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
        assertEq(lockManager.knownProposalIdAt(0), proposalId);

        // Revert if endDate is before minDuration
        vm.expectRevert();
        proposalId = plugin.createProposal("0x", new Action[](0), startDate, startDate, abi.encode(uint256(0)));

        vm.expectRevert();
        proposalId = plugin.createProposal("0x", new Action[](0), startDate, endDate - 1, abi.encode(uint256(0)));
    }

    function test_RevertWhen_CallingCreateProposalWithDuplicateData()
        external
        givenProposalNotCreated
        givenProposalCreationPermissionGranted
    {
        // It Should revert
        // It Different data should produce different proposalId's

        proposalId = plugin.createProposal("hello", new Action[](0), 0, 0, abi.encode(uint256(0)));
        vm.expectRevert(abi.encodeWithSelector(LockToApprovePlugin.ProposalAlreadyExists.selector, proposalId));
        plugin.createProposal("hello", new Action[](0), 0, 0, abi.encode(uint256(0)));

        // different
        uint256 proposalId2 = plugin.createProposal("---", new Action[](0), 0, 0, abi.encode(uint256(0)));
        assertNotEq(proposalId, proposalId2);

        uint256 proposalId3 = plugin.createProposal("hello", new Action[](1), 0, 0, abi.encode(uint256(0)));
        assertNotEq(proposalId3, proposalId2);
        assertNotEq(proposalId3, proposalId);
    }

    function test_WhenCallingTheGettersNotCreated() public givenProposalNotCreated {
        // It getProposal should return empty values
        // It isProposalOpen should return false
        // It canApprove should return false
        // It hasSucceeded should return false
        // It canExecute should return false

        proposalId = 0;

        (
            bool open,
            bool executed,
            LockToApprovePlugin.ProposalParameters memory parameters,
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
        assertFalse(plugin.canApprove(proposalId, alice));

        vm.expectRevert(abi.encodeWithSelector(LockToApprovePlugin.NonexistentProposal.selector, proposalId));
        assertFalse(plugin.hasSucceeded(proposalId));
        vm.expectRevert(abi.encodeWithSelector(LockToApprovePlugin.NonexistentProposal.selector, proposalId));
        assertFalse(plugin.canExecute(proposalId));
    }

    function test_WhenCallingTheRestOfMethods() public givenProposalNotCreated {
        // It Should revert, even with the required permissions

        proposalId = 0;

        vm.startPrank(address(lockManager));
        vm.expectRevert(abi.encodeWithSelector(LockToApprovePlugin.ApprovalForbidden.selector, proposalId, alice));
        plugin.approve(proposalId, alice, 0.1 ether);

        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(plugin), alice, EXECUTE_PROPOSAL_PERMISSION_ID
            )
        );
        plugin.execute(proposalId);

        dao.grant(address(plugin), alice, EXECUTE_PROPOSAL_PERMISSION_ID);
        vm.expectRevert(abi.encodeWithSelector(LockToApprovePlugin.ProposalExecutionForbidden.selector, proposalId));
        plugin.execute(proposalId);
    }

    modifier givenProposalCreated() {
        Action[] memory actions = new Action[](1);
        actions[0].to = address(dao);
        actions[0].value = 0.01 ether;
        actions[0].data = abi.encodeCall(DAO.setMetadata, "0x");

        proposalId = plugin.createProposal("0x5555", actions, 0, 0, abi.encode(uint256(7)));
        _;
    }

    function test_WhenCallingGetProposal() public givenProposalCreated {
        // It Should return the right values
        (
            bool open,
            bool executed,
            LockToApprovePlugin.ProposalParameters memory parameters,
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

    function test_WhenCallingCanApprove() public givenProposalCreated {
        // It Should return true when there is balance left to allocate

        lockableToken.approve(address(lockManager), 0.1 ether);
        lockManager.lock();
        assertTrue(plugin.canApprove(proposalId, alice));

        // It Should return false when there is no balance left to allocate
        lockManager.approve(proposalId);
        assertFalse(plugin.canApprove(proposalId, alice));

        vm.startPrank(bob);
        assertFalse(plugin.canApprove(proposalId, bob));
    }

    modifier givenNoLockManagerPermission() {
        vm.startPrank(alice);
        dao.revoke(address(plugin), address(lockManager), LOCK_MANAGER_PERMISSION_ID);
        _;
    }

    function test_WhenCallingApprove() public givenProposalCreated givenNoLockManagerPermission {
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
        plugin.approve(proposalId, alice, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(plugin),
                address(lockManager),
                LOCK_MANAGER_PERMISSION_ID
            )
        );
        plugin.approve(proposalId, bob, 100);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(plugin),
                address(lockManager),
                LOCK_MANAGER_PERMISSION_ID
            )
        );
        plugin.approve(proposalId, carol, 100000);

        // OK
        vm.startPrank(alice);
        dao.grant(address(plugin), address(lockManager), LOCK_MANAGER_PERMISSION_ID);
        vm.startPrank(address(lockManager));
        plugin.approve(proposalId, carol, 100000);
    }

    function test_WhenCallingClearApproval() public givenProposalCreated givenNoLockManagerPermission {
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
        plugin.clearApproval(proposalId, alice);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(plugin),
                address(lockManager),
                LOCK_MANAGER_PERMISSION_ID
            )
        );
        plugin.clearApproval(proposalId, bob);
    }

    modifier givenLockManagerPermissionIsGranted() {
        _;
    }

    function test_GivenProposalCreatedUnstarted() public givenProposalCreated givenLockManagerPermissionIsGranted {
        // It Calling vote should revert, with or without balance

        proposalId = plugin.createProposal(
            "0x",
            new Action[](0),
            uint64(block.timestamp + 1 days), // future start
            0,
            ""
        );

        vm.startPrank(address(lockManager));

        vm.expectRevert(abi.encodeWithSelector(LockToApprovePlugin.ApprovalForbidden.selector, proposalId, alice));
        plugin.approve(proposalId, alice, 0.1 ether);

        // 2
        vm.expectRevert(abi.encodeWithSelector(LockToApprovePlugin.ApprovalForbidden.selector, proposalId, bob));
        plugin.approve(proposalId, bob, 0.1 ether);

        // 2
        vm.expectRevert(abi.encodeWithSelector(LockToApprovePlugin.ApprovalForbidden.selector, proposalId, carol));
        plugin.approve(proposalId, carol, 0.1 ether);
    }

    modifier givenProposalCreatedAndStarted() {
        proposalId = plugin.createProposal("0x", new Action[](0), 0, 0, abi.encode(uint256(0)));

        _;
    }

    function test_RevertWhen_CallingApproveNoNewLockedBalance()
        public
        givenProposalCreated
        givenLockManagerPermissionIsGranted
        givenProposalCreatedAndStarted
    {
        // It Should revert

        lockableToken.approve(address(lockManager), 0.1 ether);
        lockManager.lock();
        lockManager.approve(proposalId);

        vm.expectRevert(abi.encodeWithSelector(LockToApprovePlugin.ApprovalForbidden.selector, proposalId, alice));
        lockManager.approve(proposalId);

        vm.startPrank(address(lockManager));

        vm.expectRevert(abi.encodeWithSelector(LockToApprovePlugin.ApprovalForbidden.selector, proposalId, alice));
        plugin.approve(proposalId, alice, 0.1 ether);
    }

    function test_WhenCallingApproveNewLockedBalance()
        public
        givenProposalCreated
        givenLockManagerPermissionIsGranted
        givenProposalCreatedAndStarted
    {
        // It Should increase the tally by the new amount
        // It Should emit an event

        vm.startPrank(address(lockManager));

        vm.expectEmit();
        emit ApprovalCast(proposalId, alice, 0.1 ether);
        plugin.approve(proposalId, alice, 0.1 ether);

        (,,, uint256 approvalTally,,,) = plugin.getProposal(proposalId);
        assertEq(approvalTally, 0.1 ether);
        assertEq(plugin.usedVotingPower(proposalId, alice), 0.1 ether);

        vm.expectEmit();
        emit ApprovalCast(proposalId, alice, 0.25 ether);
        plugin.approve(proposalId, alice, 0.25 ether);

        (,,, approvalTally,,,) = plugin.getProposal(proposalId);
        assertEq(approvalTally, 0.25 ether);
        assertEq(plugin.usedVotingPower(proposalId, alice), 0.25 ether);
    }

    function test_WhenCallingClearApprovalNoApproveBalance()
        external
        givenProposalCreated
        givenLockManagerPermissionIsGranted
        givenProposalCreatedAndStarted
    {
        // It Should do nothing
        (,,, uint256 approvalTallyBefore,,,) = plugin.getProposal(proposalId);
        assertEq(approvalTallyBefore, 0);

        vm.startPrank(address(lockManager));
        plugin.clearApproval(proposalId, alice);

        (,,, uint256 approvalTallyAfter,,,) = plugin.getProposal(proposalId);
        assertEq(approvalTallyAfter, 0);
        assertEq(plugin.usedVotingPower(proposalId, alice), 0);
    }

    function test_WhenCallingClearApprovalWithApproveBalance()
        external
        givenProposalCreated
        givenLockManagerPermissionIsGranted
        givenProposalCreatedAndStarted
    {
        // It Should unassign the current approver's approval
        // It Should decrease the proposal tally by the right amount
        // It Should emit an event
        // It usedVotingPower should return the right value
        uint256 approvalAmount = 0.5 ether;

        vm.startPrank(address(lockManager));
        plugin.approve(proposalId, alice, approvalAmount);

        (,,, uint256 approvalTallyBefore,,,) = plugin.getProposal(proposalId);
        assertEq(approvalTallyBefore, approvalAmount);
        assertEq(plugin.usedVotingPower(proposalId, alice), approvalAmount);

        vm.expectEmit();
        emit ApprovalCleared(proposalId, alice);
        plugin.clearApproval(proposalId, alice);

        (,,, uint256 approvalTallyAfter,,,) = plugin.getProposal(proposalId);
        assertEq(approvalTallyAfter, 0);
        assertEq(plugin.usedVotingPower(proposalId, alice), 0);
    }

    function test_WhenCallingClearApproveNoApproveBalance()
        public
        givenProposalCreated
        givenLockManagerPermissionIsGranted
        givenProposalCreatedAndStarted
    {
        // It Should do nothing

        vm.startPrank(address(lockManager));
        plugin.clearApproval(proposalId, alice);

        (,,, uint256 approvalTally,,,) = plugin.getProposal(proposalId);
        assertEq(approvalTally, 0);

        plugin.clearApproval(proposalId, bob);

        (,,, approvalTally,,,) = plugin.getProposal(proposalId);
        assertEq(approvalTally, 0);
    }

    function test_WhenCallingClearApproveWithApproveBalance()
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
        plugin.approve(proposalId, alice, 0.1 ether);

        (,,, uint256 approvalTally,,,) = plugin.getProposal(proposalId);
        assertEq(approvalTally, 0.1 ether);
        assertEq(plugin.usedVotingPower(proposalId, alice), 0.1 ether);

        vm.expectEmit();
        emit ApprovalCleared(proposalId, alice);
        plugin.clearApproval(proposalId, alice);

        (,,, approvalTally,,,) = plugin.getProposal(proposalId);
        assertEq(approvalTally, 0);
        assertEq(plugin.usedVotingPower(proposalId, alice), 0);
    }

    function test_WhenCallingHasSucceededCanExecuteCreated() public givenProposalCreated {
        // It hasSucceeded should return false
        // It canExecute should return false

        assertFalse(plugin.hasSucceeded(proposalId));
        assertFalse(plugin.canExecute(proposalId));
    }

    function test_WhenCallingExecuteCreated() public givenProposalCreated {
        // It Should revert, even with the required permission

        dao.grant(address(plugin), alice, EXECUTE_PROPOSAL_PERMISSION_ID);

        vm.expectRevert(abi.encodeWithSelector(LockToApprovePlugin.ProposalExecutionForbidden.selector, proposalId));
        plugin.execute(proposalId);
    }

    modifier givenProposalDefeated() {
        proposalId = plugin.createProposal("0x", new Action[](0), 0, 0, abi.encode(uint256(123)));

        vm.startPrank(address(lockManager));
        plugin.approve(proposalId, alice, 0.001 ether);

        vm.warp(block.timestamp + 10 days);

        _;
    }

    function test_WhenCallingTheGettersDefeated() public givenProposalDefeated {
        // It getProposal should return the right values
        // It isProposalOpen should return false
        // It canApprove should return false
        // It hasSucceeded should return false
        // It canExecute should return false

        // vm.startPrank(alice);

        (
            bool open,
            bool executed,
            LockToApprovePlugin.ProposalParameters memory parameters,
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
        assertFalse(plugin.canApprove(proposalId, alice));
        assertFalse(plugin.hasSucceeded(proposalId));
        assertFalse(plugin.canExecute(proposalId));
    }

    function test_WhenCallingApproveOrClearApprovalDefeated() public givenProposalDefeated {
        // It Should revert for vote, despite having the permission
        // It clearApprove should revert

        vm.startPrank(address(lockManager));

        vm.expectRevert(abi.encodeWithSelector(LockToApprovePlugin.ApprovalForbidden.selector, proposalId, alice));
        plugin.approve(proposalId, alice, 1);

        vm.expectRevert(
            abi.encodeWithSelector(LockToApprovePlugin.ApprovalRemovalForbidden.selector, proposalId, alice)
        );
        plugin.clearApproval(proposalId, alice);
    }

    function test_WhenCallingExecuteDefeated() public givenProposalDefeated {
        // It Should revert, with or without permission

        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(plugin), alice, EXECUTE_PROPOSAL_PERMISSION_ID
            )
        );
        plugin.execute(proposalId);

        dao.grant(address(plugin), alice, EXECUTE_PROPOSAL_PERMISSION_ID);

        vm.expectRevert(abi.encodeWithSelector(LockToApprovePlugin.ProposalExecutionForbidden.selector, proposalId));
        plugin.execute(proposalId);
    }

    modifier givenProposalPassed() {
        proposalId = plugin.createProposal("0x", new Action[](0), 0, 0, abi.encode(uint256(0)));

        lockableToken.approve(address(lockManager), 0.1 ether);
        lockManager.lock();

        vm.startPrank(carol);
        lockableToken.approve(address(lockManager), 10 ether);
        lockManager.lock();

        vm.startPrank(david);
        lockableToken.approve(address(lockManager), 15 ether);
        lockManager.lock();

        vm.startPrank(address(lockManager));
        plugin.approve(proposalId, alice, 0.1 ether);
        plugin.approve(proposalId, address(carol), 10 ether);
        plugin.approve(proposalId, address(david), 15 ether);

        // The consumer needs to advance to block.timestamp + 10 days

        _;
    }

    function test_WhenCallingTheGettersPassed() public givenProposalPassed {
        // It getProposal should return the right values
        // It isProposalOpen should return false
        // It canApprove should return false
        // It hasSucceeded should return true
        // It canExecute should return true

        // vm.startPrank(alice);

        (
            bool open,
            bool executed,
            LockToApprovePlugin.ProposalParameters memory parameters,
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
        assertFalse(plugin.canApprove(proposalId, alice));
        assertTrue(plugin.hasSucceeded(proposalId));
        assertTrue(plugin.canExecute(proposalId));

        // If not executed, after endDate

        vm.warp(block.timestamp + 10 days);

        (open,, parameters,,,,) = plugin.getProposal(proposalId);
        assertEq(parameters.startDate, block.timestamp - 10 days);
        assertEq(parameters.endDate, block.timestamp);
        assertFalse(open);
    }

    function test_WhenCallingApproveOrClearApprovalPassed() public givenProposalPassed {
        // It Should revert, despite having the permission

        vm.warp(block.timestamp + 10 days);

        vm.startPrank(address(lockManager));

        vm.expectRevert(abi.encodeWithSelector(LockToApprovePlugin.ApprovalForbidden.selector, proposalId, alice));
        plugin.approve(proposalId, alice, 1);

        // Nop
        (,,, uint256 approvalTally,,,) = plugin.getProposal(proposalId);
        assertEq(approvalTally, 25.1 ether);
        assertEq(plugin.usedVotingPower(proposalId, alice), 0.1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(LockToApprovePlugin.ApprovalRemovalForbidden.selector, proposalId, alice)
        );
        plugin.clearApproval(proposalId, alice);

        (,,, approvalTally,,,) = plugin.getProposal(proposalId);
        assertEq(approvalTally, 25.1 ether);
        assertEq(plugin.usedVotingPower(proposalId, alice), 0.1 ether);
    }

    modifier givenNoExecuteProposalPermission() {
        // Redundant, but just in case
        vm.startPrank(alice);
        dao.revoke(address(plugin), alice, EXECUTE_PROPOSAL_PERMISSION_ID);
        _;
    }

    function test_RevertWhen_CallingExecuteNoPerm() public givenProposalPassed givenNoExecuteProposalPermission {
        // It Should revert

        // alice
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(plugin), alice, EXECUTE_PROPOSAL_PERMISSION_ID
            )
        );
        plugin.execute(proposalId);
    }

    modifier givenExecuteProposalPermission() {
        vm.startPrank(alice);
        dao.grant(address(plugin), alice, EXECUTE_PROPOSAL_PERMISSION_ID);

        _;
    }

    function test_WhenCallingExecutePassed() public givenProposalPassed givenExecuteProposalPermission {
        // It Should execute the actions of the proposal on the target
        // It Should call proposalEnded on the LockManager
        // It Should emit an event

        vm.warp(block.timestamp + 10 days);

        vm.expectEmit();
        emit ProposalExecuted(proposalId);

        vm.expectEmit();
        emit ProposalEnded(proposalId);

        plugin.execute(proposalId);

        (bool open, bool executed,,,,,) = plugin.getProposal(proposalId);
        assertFalse(open);
        assertTrue(executed);

        // Check if proposalEnded was called on the lockManager
        vm.expectRevert();
        lockManager.knownProposalIdAt(0);
    }

    modifier givenProposalExecuted() {
        Action[] memory actions = new Action[](1);
        actions[0].to = address(dao);
        actions[0].value = 0 ether;
        actions[0].data = abi.encodeCall(DAO.setMetadata, "hello");

        proposalId = plugin.createProposal("0x", actions, 0, 0, abi.encode(uint256(1)));

        lockableToken.approve(address(lockManager), 0.1 ether);
        lockManager.lock();

        vm.startPrank(carol);
        lockableToken.approve(address(lockManager), 10 ether);
        lockManager.lock();

        vm.startPrank(david);
        lockableToken.approve(address(lockManager), 15 ether);
        lockManager.lock();

        vm.startPrank(address(lockManager));
        plugin.approve(proposalId, alice, 0.1 ether);
        plugin.approve(proposalId, address(carol), 10 ether);
        plugin.approve(proposalId, address(david), 15 ether);

        vm.startPrank(alice);
        dao.grant(address(plugin), alice, EXECUTE_PROPOSAL_PERMISSION_ID);

        plugin.execute(proposalId);

        _;
    }

    function test_WhenCallingTheGettersExecuted() public givenProposalExecuted {
        // It getProposal should return the right values
        // It isProposalOpen should return false
        // It canApprove should return false
        // It hasSucceeded should return false
        // It canExecute should return false

        (
            bool open,
            bool executed,
            LockToApprovePlugin.ProposalParameters memory parameters,
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
        assertFalse(plugin.canApprove(proposalId, alice));
        assertTrue(plugin.hasSucceeded(proposalId));
        assertFalse(plugin.canExecute(proposalId));
    }

    function test_WhenCallingApproveOrClearApprovalExecuted() public givenProposalExecuted {
        // It Should revert, despite having the permission

        vm.startPrank(address(lockManager));

        vm.expectRevert(abi.encodeWithSelector(LockToApprovePlugin.ApprovalForbidden.selector, proposalId, alice));
        plugin.approve(proposalId, alice, 200 ether);

        // Nop
        (,,, uint256 approvalTally,,,) = plugin.getProposal(proposalId);
        assertEq(approvalTally, 25.1 ether);
        assertEq(plugin.usedVotingPower(proposalId, alice), 0.1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(LockToApprovePlugin.ApprovalRemovalForbidden.selector, proposalId, alice)
        );
        plugin.clearApproval(proposalId, alice);

        (,,, approvalTally,,,) = plugin.getProposal(proposalId);
        assertEq(approvalTally, 25.1 ether);
        assertEq(plugin.usedVotingPower(proposalId, alice), 0.1 ether);
    }

    function test_WhenCallingExecuteExecuted() public givenProposalExecuted {
        // It Should revert regardless of the permission

        vm.expectRevert(abi.encodeWithSelector(LockToApprovePlugin.ProposalExecutionForbidden.selector, proposalId));
        plugin.execute(proposalId);
    }

    function test_WhenUnderlyingTokenIsNotDefined() external {
        // It Should use the lockable token's balance to compute the approval ratio
        builder = new DaoBuilder();
        (dao, plugin,, lockManager, lockableToken,) = builder.withTokenHolder(alice, 5 ether).withTokenHolder(
            bob, 5 ether
        ).withApprovalPlugin().withMinApprovalRatio(500_000).build();

        // Total supply is 10 ether. 50% is 5 ether.
        assertEq(lockableToken.totalSupply(), 10 ether);

        proposalId = plugin.createProposal("0x", new Action[](0), 0, 0, "");

        // Alice locks and approves with 4.9 ether. Should not pass.
        vm.startPrank(alice);
        lockableToken.approve(address(lockManager), 4.9 ether);
        lockManager.lockAndApprove(proposalId);

        assertFalse(plugin.hasSucceeded(proposalId), "Should not succeed with 4.9 ether");

        // Alice increases her approval to 5 ether. Should pass.
        lockableToken.approve(address(lockManager), 0.1 ether);
        lockManager.lockAndApprove(proposalId);

        assertTrue(plugin.hasSucceeded(proposalId), "Should succeed with 5 ether");
    }

    function test_WhenUnderlyingTokenIsDefined() external {
        // It Should use the underlying token's balance to compute the approval ratio
        TestToken underlyingTkn = new TestToken();
        // The total supply of the underlying token will be used for the ratio calculation.
        underlyingTkn.mint(address(this), 100 ether);

        builder = new DaoBuilder();
        // We give Alice and Bob enough lockable tokens to potentially meet the threshold.
        (dao, plugin,, lockManager, lockableToken, underlyingToken) = builder.withTokenHolder(alice, 60 ether)
            .withTokenHolder(bob, 20 ether).withApprovalPlugin().withMinApprovalRatio(500_000).withUnderlyingToken(
            underlyingTkn
        ).build();

        // Underlying token supply is 100 ether, not 60+20
        // The check should be against the underlying token's supply.
        // Required approval: 50% of 100 ether = 50 ether.
        assertEq(underlyingToken.totalSupply(), 100 ether);

        proposalId = plugin.createProposal("0x", new Action[](0), 0, 0, "");

        // Alice locks and approves with 49 ether. Should not be enough.
        vm.startPrank(alice);
        lockableToken.approve(address(lockManager), 49 ether);
        lockManager.lockAndApprove(proposalId);

        assertFalse(plugin.hasSucceeded(proposalId), "Should not succeed with 49 ether approval");

        // Bob locks and approves with 1 ether. Total approval is now 50 ether. Should pass.
        vm.startPrank(bob);
        lockableToken.approve(address(lockManager), 1 ether);
        lockManager.lockAndApprove(proposalId);

        assertTrue(plugin.hasSucceeded(proposalId), "Should succeed with 50 ether total approval");
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

    modifier givenUpdateApprovalSettingsPermissionGranted() {
        dao.grant(address(plugin), alice, UPDATE_SETTINGS_PERMISSION_ID);
        _;
    }

    function test_WhenCallingUpdatePluginSettingsGranted() public givenUpdateApprovalSettingsPermissionGranted {
        // It Should set the new values
        // It Settings() should return the right values

        LockToApprovePlugin.ApprovalSettings memory newSettings = LockToApprovePlugin.ApprovalSettings({
            minApprovalRatio: 612345, // 61%
            proposalDuration: 13.4 days,
            minProposerVotingPower: 505050505
        });

        plugin.updateApprovalSettings(newSettings);

        (uint32 minApprovalRatio, uint64 proposalDuration, uint256 minVp) = plugin.settings();
        assertEq(minApprovalRatio, 612345);
        assertEq(proposalDuration, 13.4 days);
        assertEq(minVp, 505050505);
    }

    modifier givenNoUpdateApprovalSettingsPermission() {
        dao.revoke(address(plugin), alice, UPDATE_SETTINGS_PERMISSION_ID);
        _;
    }

    function test_RevertWhen_CallingUpdatePluginSettingsNotGranted() public givenNoUpdateApprovalSettingsPermission {
        // It Should revert

        LockToApprovePlugin.ApprovalSettings memory newSettings = LockToApprovePlugin.ApprovalSettings({
            minApprovalRatio: 612345, // 61%
            proposalDuration: 13.4 days,
            minProposerVotingPower: 55555
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(plugin), alice, UPDATE_SETTINGS_PERMISSION_ID
            )
        );
        plugin.updateApprovalSettings(newSettings);

        (uint32 minApprovalRatio, uint64 proposalDuration, uint256 minVp) = plugin.settings();
        assertEq(minApprovalRatio, 100000);
        assertEq(proposalDuration, 10 days);
        assertEq(minVp, 0);
    }
}
