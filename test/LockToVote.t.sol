// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {TestBase} from "./lib/TestBase.sol";
import {DaoBuilder} from "./builders/DaoBuilder.sol";
import {DAO, IDAO} from "@aragon/osx/src/core/dao/DAO.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {createProxyAndCall} from "../src/util/proxy.sol";
import {LockToVotePlugin, MajorityVotingBase} from "../src/LockToVotePlugin.sol";
import {LockManagerSettings, PluginMode} from "../src/interfaces/ILockManager.sol";
import {IMajorityVoting} from "../src/interfaces/IMajorityVoting.sol";
import {LockManagerERC20} from "../src/LockManagerERC20.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TestToken} from "./mocks/TestToken.sol";
import {ILockToVote} from "../src/interfaces/ILockToVote.sol";
import {ILockToGovernBase} from "../src/interfaces/ILockToGovernBase.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IMembership} from "@aragon/osx-commons-contracts/src/plugin/extensions/membership/IMembership.sol";
import {IERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {RATIO_BASE} from "@aragon/osx-commons-contracts/src/utils/math/Ratio.sol";
import {MinVotingPowerCondition} from "../src/conditions/MinVotingPowerCondition.sol";

contract LockToVoteTest is TestBase {
    DaoBuilder builder;
    DAO dao;
    LockToVotePlugin ltvPlugin;
    LockManagerERC20 lockManager;
    IERC20 lockableToken;
    uint256 proposalId;

    // Default actions for proposal creation
    Action[] internal actions;

    error DateOutOfBounds(uint256 limit, uint256 actual);
    error ProposalAlreadyExists(uint256 proposalId);
    error VoteCastForbidden(uint256 proposalId, address account);
    error NonexistentProposal(uint256 proposalId);
    error AlreadyInitialized();
    error NoBalance();
    error VoteRemovalForbidden(uint256 proposalId, address voter);

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed creator,
        uint64 startDate,
        uint64 endDate,
        bytes metadata,
        Action[] actions,
        uint256 allowFailureMap
    );
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalEnded(uint256 indexed proposalId);

    function setUp() public {
        vm.warp(1 days);
        vm.roll(100);

        builder = new DaoBuilder();
        (dao, ltvPlugin, lockManager, lockableToken) = builder.withTokenHolder(alice, 1 ether).withTokenHolder(
            bob, 10 ether
        ).withTokenHolder(carol, 10 ether).withTokenHolder(david, 15 ether).withVotingPlugin().withProposer(alice).build(
        );

        for (uint256 i = 0; i < actions.length; i++) {
            actions.pop();
        }

        // Grant alice permission for simplicity in some tests
        dao.grant(address(ltvPlugin), alice, ltvPlugin.EXECUTE_PROPOSAL_PERMISSION_ID());
    }

    function test_WhenDeployingTheContract() external {
        ltvPlugin = LockToVotePlugin(createProxyAndCall(address(new LockToVotePlugin()), bytes("")));

        MajorityVotingBase.VotingSettings memory votingSettings = MajorityVotingBase.VotingSettings({
            votingMode: MajorityVotingBase.VotingMode.Standard,
            supportThresholdRatio: 500_000, // 50%
            minParticipationRatio: 100_000, // 10%
            minApprovalRatio: 0,
            proposalDuration: 7 days,
            minProposerVotingPower: 1 ether
        });
        IPlugin.TargetConfig memory targetConfig =
            IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.Call});
        bytes memory pluginMetadata = "ipfs://1234";

        // It should initialize normally
        ltvPlugin.initialize(dao, lockManager, votingSettings, targetConfig, pluginMetadata);
    }

    function test_GivenADeployedContract() external {
        // It should refuse to initialize again
        MajorityVotingBase.VotingSettings memory votingSettings = ltvPlugin.getVotingSettings();
        IPlugin.TargetConfig memory targetConfig = ltvPlugin.getTargetConfig();

        vm.expectRevert(AlreadyInitialized.selector);
        ltvPlugin.initialize(dao, lockManager, votingSettings, targetConfig, "");
    }

    modifier givenANewProxy() {
        (dao,,, lockableToken) = builder.withTokenHolder(alice, 1 ether).withTokenHolder(bob, 10 ether).withTokenHolder(
            carol, 10 ether
        ).withTokenHolder(david, 15 ether).build();

        lockManager = new LockManagerERC20(LockManagerSettings({pluginMode: PluginMode.Voting}), lockableToken);

        ltvPlugin = LockToVotePlugin(createProxyAndCall(address(new LockToVotePlugin()), bytes("")));

        lockManager.setPluginAddress(ILockToGovernBase(address(ltvPlugin)));

        dao.grant(address(ltvPlugin), address(lockManager), ltvPlugin.LOCK_MANAGER_PERMISSION_ID());

        _;
    }

    function test_GivenCallingInitialize() external givenANewProxy {
        MajorityVotingBase.VotingSettings memory votingSettings = MajorityVotingBase.VotingSettings({
            votingMode: MajorityVotingBase.VotingMode.Standard,
            supportThresholdRatio: 500_000, // 50%
            minParticipationRatio: 100_000, // 10%
            minApprovalRatio: 0,
            proposalDuration: 7 days,
            minProposerVotingPower: 1 ether
        });
        IPlugin.TargetConfig memory targetConfig =
            IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.Call});
        bytes memory pluginMetadata = "ipfs://1234";

        ltvPlugin.initialize(dao, lockManager, votingSettings, targetConfig, pluginMetadata);

        // It should set the DAO address
        assertEq(address(ltvPlugin.dao()), address(dao));
        // It should define the voting settings
        MajorityVotingBase.VotingSettings memory votingSettings2 = ltvPlugin.getVotingSettings();
        assertEq(uint8(votingSettings2.votingMode), uint8(votingSettings.votingMode));
        assertEq(votingSettings2.supportThresholdRatio, votingSettings.supportThresholdRatio);
        assertEq(votingSettings2.minParticipationRatio, votingSettings.minParticipationRatio);
        assertEq(votingSettings2.minApprovalRatio, votingSettings.minApprovalRatio);
        assertEq(votingSettings2.proposalDuration, votingSettings.proposalDuration);
        assertEq(votingSettings2.minProposerVotingPower, votingSettings.minProposerVotingPower);
        // It should define the target config
        IPlugin.TargetConfig memory cfg = ltvPlugin.getTargetConfig();
        assertEq(cfg.target, targetConfig.target);
        assertEq(uint8(cfg.operation), uint8(targetConfig.operation));
        // It should define the plugin metadata
        assertEq(ltvPlugin.getMetadata(), pluginMetadata);
        // It should define the lock manager
        assertEq(address(ltvPlugin.lockManager()), address(lockManager));
    }

    modifier whenCallingUpdateVotingSettings() {
        _;
    }

    function test_GivenTheCallerHasPermissionToCallUpdateVotingSettings() external whenCallingUpdateVotingSettings {
        dao.grant(address(ltvPlugin), alice, ltvPlugin.UPDATE_SETTINGS_PERMISSION_ID());

        MajorityVotingBase.VotingSettings memory newSettings = MajorityVotingBase.VotingSettings({
            votingMode: MajorityVotingBase.VotingMode.VoteReplacement,
            supportThresholdRatio: 600_000, // 60%
            minParticipationRatio: 200_000, // 20%
            minApprovalRatio: 100_000, // 10%
            proposalDuration: 14 days,
            minProposerVotingPower: 2 ether
        });

        vm.prank(alice);
        ltvPlugin.updateVotingSettings(newSettings);

        // It Should set the new values
        // It getVotingSettings() should return the right values

        MajorityVotingBase.VotingSettings memory actualVotingSettings = ltvPlugin.getVotingSettings();
        assertEq(uint8(actualVotingSettings.votingMode), uint8(newSettings.votingMode));
        assertEq(actualVotingSettings.supportThresholdRatio, newSettings.supportThresholdRatio);
        assertEq(actualVotingSettings.minParticipationRatio, newSettings.minParticipationRatio);
        assertEq(actualVotingSettings.minApprovalRatio, newSettings.minApprovalRatio);
        assertEq(actualVotingSettings.proposalDuration, newSettings.proposalDuration);
        assertEq(actualVotingSettings.minProposerVotingPower, newSettings.minProposerVotingPower);
    }

    function test_RevertGiven_TheCallerHasNoPermissionToCallUpdateVotingSettings()
        external
        whenCallingUpdateVotingSettings
    {
        // It Should revert
        MajorityVotingBase.VotingSettings memory someSettings = ltvPlugin.getVotingSettings();

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(ltvPlugin),
                randomWallet,
                ltvPlugin.UPDATE_SETTINGS_PERMISSION_ID()
            )
        );
        vm.prank(randomWallet);
        ltvPlugin.updateVotingSettings(someSettings);
    }

    function test_WhenCallingSupportsInterface() external view {
        // It does not support the empty interface
        assertFalse(ltvPlugin.supportsInterface(0xffffffff));
        // It supports IERC165Upgradeable
        assertTrue(ltvPlugin.supportsInterface(type(IERC165Upgradeable).interfaceId));
        // It supports IMembership
        assertTrue(ltvPlugin.supportsInterface(type(IMembership).interfaceId));
        // It supports ILockToVote
        assertTrue(ltvPlugin.supportsInterface(type(ILockToVote).interfaceId));
    }

    modifier whenCallingCreateProposal() {
        _;
    }

    modifier givenCreatePermission() {
        _;
    }

    modifier givenNoMinimumVotingPower() {
        // Default setup has minProposerVotingPower = 0
        _;
    }

    function test_GivenValidParameters()
        external
        whenCallingCreateProposal
        givenCreatePermission
        givenNoMinimumVotingPower
    {
        // It sets the given failuremap, if any
        bytes memory metadata = "ipfs://test";
        uint256 failureMap = 127;
        bytes memory customParams = abi.encode(failureMap);

        // It sets the given failuremap, if any
        vm.prank(alice);
        uint256 propId1 = ltvPlugin.createProposal(metadata, actions, 0, 0, customParams);
        (, bool executed,,, Action[] memory pActions, uint256 pFailureMap,) = ltvPlugin.getProposal(propId1);
        assertFalse(executed);
        assertEq(pFailureMap, failureMap);
        assertEq(pActions.length, actions.length);

        // It proposalIds are predictable and reproducible
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ProposalAlreadyExists.selector, propId1));
        ltvPlugin.createProposal(metadata, actions, 0, 0, customParams);

        // It sets the given voting mode, target, params and actions
        (,, MajorityVotingBase.ProposalParameters memory params,,,,) = ltvPlugin.getProposal(propId1);
        assertEq(uint8(params.votingMode), uint8(ltvPlugin.votingMode()));

        failureMap = 0;
        customParams = bytes("");
        metadata = "ipfs://different-metadata";

        // It emits an event
        vm.expectEmit(true, true, true, true);
        emit ProposalCreated(
            7835924699308567771993176782677466443726840862277041205897480900284296603105,
            alice,
            uint64(block.timestamp),
            uint64(block.timestamp + 10 days),
            metadata,
            actions,
            failureMap
        );
        vm.prank(alice);
        ltvPlugin.createProposal(metadata, actions, 0, 0, customParams);

        // It reports proposalCreated() on the lockManager
        assertEq(lockManager.knownProposalIdAt(0), propId1);
    }

    function test_GivenMinimumVotingPowerAboveZero() external whenCallingCreateProposal givenCreatePermission {
        // Re-setup with condition
        (dao, ltvPlugin, lockManager, lockableToken) =
            new DaoBuilder().withTokenHolder(alice, 1 ether).withVotingPlugin().build();

        // Revoke unconditional permission for alice (default proposer in my setUp)
        dao.revoke(address(ltvPlugin), alice, ltvPlugin.CREATE_PROPOSAL_PERMISSION_ID());

        // Set minProposerVotingPower
        MajorityVotingBase.VotingSettings memory settings = ltvPlugin.getVotingSettings();
        settings.minProposerVotingPower = 2 ether;
        dao.grant(address(ltvPlugin), address(dao), ltvPlugin.UPDATE_SETTINGS_PERMISSION_ID());
        vm.prank(address(dao));
        ltvPlugin.updateVotingSettings(settings);

        // Create and grant permission with condition
        MinVotingPowerCondition condition = new MinVotingPowerCondition(ILockToGovernBase(address(ltvPlugin)));
        dao.grantWithCondition(address(ltvPlugin), alice, ltvPlugin.CREATE_PROPOSAL_PERMISSION_ID(), condition);

        // It should revert when the creator has not enough balance
        // Alice has 1 ether, min is 2 ether.
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(ltvPlugin),
                alice,
                ltvPlugin.CREATE_PROPOSAL_PERMISSION_ID()
            )
        );
        vm.prank(alice);
        ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        // It should succeed when the creator has enough balance
        TestToken(address(lockableToken)).mint(alice, 1 ether); // now alice has 2 ether
        vm.prank(alice);
        ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));
    }

    function test_RevertGiven_InvalidDates() external whenCallingCreateProposal givenCreatePermission {
        // It should revert
        uint64 start = uint64(block.timestamp + 1 days);
        uint64 end = start + 1 hours; // Less than default 10 days duration

        vm.expectRevert(abi.encodeWithSelector(DateOutOfBounds.selector, start + ltvPlugin.proposalDuration(), end));
        vm.prank(alice);
        ltvPlugin.createProposal("", actions, start, end, bytes(""));
    }

    function test_RevertGiven_DuplicateProposalID() external whenCallingCreateProposal givenCreatePermission {
        // It should revert
        vm.prank(alice);
        uint256 propId = ltvPlugin.createProposal("", actions, 0, 0, bytes(""));

        vm.expectRevert(abi.encodeWithSelector(ProposalAlreadyExists.selector, propId));
        vm.prank(alice);
        ltvPlugin.createProposal("", actions, 0, 0, bytes(""));
    }

    function test_RevertGiven_NoCreatePermission() external whenCallingCreateProposal {
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(ltvPlugin),
                randomWallet,
                ltvPlugin.CREATE_PROPOSAL_PERMISSION_ID()
            )
        );
        vm.prank(randomWallet);
        ltvPlugin.createProposal("", actions, 0, 0, bytes(""));
    }

    modifier whenCallingCanVote() {
        _;
    }

    modifier givenTheProposalIsOpen() {
        _;
    }

    modifier givenNonEmptyVote() {
        _;
    }

    function test_GivenSubmittingTheFirstVote() external whenCallingCanVote givenTheProposalIsOpen givenNonEmptyVote {
        // It should happen in all voting modes
        _testCanVoteFirstTime(MajorityVotingBase.VotingMode.Standard);
        _testCanVoteFirstTime(MajorityVotingBase.VotingMode.VoteReplacement);
        _testCanVoteFirstTime(MajorityVotingBase.VotingMode.EarlyExecution);
    }

    function _testCanVoteFirstTime(MajorityVotingBase.VotingMode mode) internal {
        (dao, ltvPlugin, lockManager, lockableToken) =
            new DaoBuilder().withVotingPlugin().withTokenHolder(alice, 1 ether).withProposer(alice).build();
        MajorityVotingBase.VotingSettings memory settings = ltvPlugin.getVotingSettings();
        settings.votingMode = mode;

        dao.grant(address(ltvPlugin), address(dao), ltvPlugin.UPDATE_SETTINGS_PERMISSION_ID());

        vm.prank(address(dao));
        ltvPlugin.updateVotingSettings(settings);

        vm.prank(alice);
        uint256 propId = ltvPlugin.createProposal("", actions, 0, 0, bytes(""));

        vm.prank(alice);
        lockableToken.approve(address(lockManager), 1 ether);
        vm.prank(alice);
        lockManager.lock();

        // It should return true when the voter locked balance is positive
        assertTrue(ltvPlugin.canVote(propId, alice, IMajorityVoting.VoteOption.Yes));
        // It should return false when the voter has no locked balance
        assertFalse(ltvPlugin.canVote(propId, bob, IMajorityVoting.VoteOption.Yes));
    }

    modifier givenVotingAgain() {
        _;
    }

    function test_GivenStandardVotingMode()
        external
        whenCallingCanVote
        givenTheProposalIsOpen
        givenNonEmptyVote
        givenVotingAgain
    {
        (dao, ltvPlugin, lockManager, lockableToken) =
            builder.withStandardVoting().withVotingPlugin().withProposer(alice).withTokenHolder(alice, 1 ether).build();

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _vote(alice, IMajorityVoting.VoteOption.Yes, 0.5 ether);

        // It should return true when voting the same with more balance
        _lock(alice, 0.5 ether);
        assertTrue(ltvPlugin.canVote(proposalId, alice, IMajorityVoting.VoteOption.Yes));

        // It should return false otherwise
        assertFalse(ltvPlugin.canVote(proposalId, alice, IMajorityVoting.VoteOption.No)); // different option
    }

    function test_GivenVoteReplacementMode()
        external
        whenCallingCanVote
        givenTheProposalIsOpen
        givenNonEmptyVote
        givenVotingAgain
    {
        (dao, ltvPlugin, lockManager, lockableToken) =
            builder.withVoteReplacement().withVotingPlugin().withProposer(alice).withTokenHolder(alice, 1 ether).build();

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _vote(alice, IMajorityVoting.VoteOption.Yes, 0.5 ether);

        // It should return true when the locked balance is higher
        _lock(alice, 0.5 ether);
        assertTrue(ltvPlugin.canVote(proposalId, alice, IMajorityVoting.VoteOption.No));

        // It should return false otherwise
        assertTrue(ltvPlugin.canVote(proposalId, alice, IMajorityVoting.VoteOption.No));
    }

    function test_GivenEarlyExecutionMode()
        external
        whenCallingCanVote
        givenTheProposalIsOpen
        givenNonEmptyVote
        givenVotingAgain
    {
        (dao, ltvPlugin, lockManager, lockableToken) =
            builder.withEarlyExecution().withVotingPlugin().withProposer(alice).withTokenHolder(alice, 1 ether).build();

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _vote(alice, IMajorityVoting.VoteOption.Yes, 0.5 ether);

        // It should return false
        assertFalse(ltvPlugin.canVote(proposalId, alice, IMajorityVoting.VoteOption.Yes));
    }

    function test_GivenEmptyVote() external whenCallingCanVote givenTheProposalIsOpen {
        (dao, ltvPlugin, lockManager, lockableToken) =
            builder.withVoteReplacement().withVotingPlugin().withProposer(alice).withTokenHolder(alice, 1 ether).build();

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        // It should return false
        assertFalse(ltvPlugin.canVote(proposalId, alice, IMajorityVoting.VoteOption.None));
    }

    function test_GivenTheProposalEnded() external whenCallingCanVote {
        (dao, ltvPlugin, lockManager, lockableToken) =
            builder.withStandardVoting().withVotingPlugin().withProposer(alice).withTokenHolder(alice, 1 ether).build();

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));
        _lock(alice, 1 ether);
        assertTrue(ltvPlugin.canVote(proposalId, alice, IMajorityVoting.VoteOption.Yes));

        vm.warp(block.timestamp + ltvPlugin.proposalDuration() + 1);
        // It should return false, regardless of prior votes
        // It should return false, regardless of the locked balance
        assertFalse(ltvPlugin.canVote(proposalId, alice, IMajorityVoting.VoteOption.Yes));
        assertFalse(ltvPlugin.canVote(proposalId, bob, IMajorityVoting.VoteOption.Yes));

        // It should return false, regardless of the voting mode

        (dao, ltvPlugin, lockManager, lockableToken) =
            builder.withVoteReplacement().withVotingPlugin().withProposer(alice).withTokenHolder(alice, 1 ether).build();

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));
        _lock(alice, 1 ether);
        assertTrue(ltvPlugin.canVote(proposalId, alice, IMajorityVoting.VoteOption.Yes));

        vm.warp(block.timestamp + ltvPlugin.proposalDuration() + 1);
        assertFalse(ltvPlugin.canVote(proposalId, alice, IMajorityVoting.VoteOption.Yes));
        assertFalse(ltvPlugin.canVote(proposalId, bob, IMajorityVoting.VoteOption.Yes));

        // 2

        (dao, ltvPlugin, lockManager, lockableToken) =
            builder.withEarlyExecution().withVotingPlugin().withProposer(alice).withTokenHolder(alice, 1 ether).build();

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));
        _lock(alice, 1 ether);
        assertTrue(ltvPlugin.canVote(proposalId, alice, IMajorityVoting.VoteOption.Yes));

        vm.warp(block.timestamp + ltvPlugin.proposalDuration() + 1);
        assertFalse(ltvPlugin.canVote(proposalId, alice, IMajorityVoting.VoteOption.Yes));
        assertFalse(ltvPlugin.canVote(proposalId, bob, IMajorityVoting.VoteOption.Yes));
    }

    function test_RevertGiven_TheProposalIsNotCreated() external whenCallingCanVote {
        // It should revert
        vm.expectRevert(abi.encodeWithSelector(NonexistentProposal.selector, 999));
        ltvPlugin.canVote(999, alice, IMajorityVoting.VoteOption.Yes);
    }

    modifier whenCallingVote() {
        _;
    }

    function test_RevertGiven_CanVoteReturnsFalse() external whenCallingVote {
        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        // It should revert
        // Case: No locked balance
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(VoteCastForbidden.selector, proposalId, bob));
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);

        // OK
        _lock(alice, 1 ether);
        vm.prank(alice);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);
    }

    modifier givenStandardVotingMode2() {
        (dao, ltvPlugin, lockManager, lockableToken) =
            builder.withStandardVoting().withVotingPlugin().withProposer(alice).withTokenHolder(alice, 1 ether).build();

        _;
    }

    modifier givenVotingTheFirstTime() {
        _;
    }

    function test_GivenHasLockedBalance() external whenCallingVote givenStandardVotingMode2 givenVotingTheFirstTime {
        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _lock(alice, 1 ether);

        uint256 aliceBalance = lockManager.getLockedBalance(alice);

        vm.expectEmit(true, true, true, true);
        emit IMajorityVoting.VoteCast(proposalId, alice, IMajorityVoting.VoteOption.Yes, aliceBalance);

        vm.prank(alice);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);

        // It should set the right voter's usedVotingPower
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), aliceBalance);

        // It should set the right tally of the voted option
        (,,, MajorityVotingBase.Tally memory tally,,,) = ltvPlugin.getProposal(proposalId);
        assertEq(tally.yes, aliceBalance);

        // It should set the right total voting power
        assertEq(tally.yes + tally.no + tally.abstain, aliceBalance);
    }

    function test_RevertGiven_NoLockedBalance()
        external
        whenCallingVote
        givenStandardVotingMode2
        givenVotingTheFirstTime
    {
        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        vm.prank(bob);
        vm.expectRevert();
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);

        // It should keep the right voter's usedVotingPower
        assertEq(ltvPlugin.usedVotingPower(proposalId, bob), 0);

        // It should set the right tally
        (,,, MajorityVotingBase.Tally memory tally,,,) = ltvPlugin.getProposal(proposalId);
        assertEq(tally.yes + tally.no + tally.abstain, 0);
    }

    modifier givenVotingTheSameOption() {
        _;
    }

    function test_RevertGiven_VotingWithTheSameLockedBalance()
        external
        whenCallingVote
        givenStandardVotingMode2
        givenVotingTheSameOption
    {
        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _lock(alice, 1 ether);

        uint256 aliceBalance = lockManager.getLockedBalance(alice);
        vm.prank(alice);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);

        // It should revert
        vm.expectRevert(abi.encodeWithSelector(VoteCastForbidden.selector, proposalId, alice));
        vm.prank(alice);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);

        //
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), aliceBalance);

        (,,, MajorityVotingBase.Tally memory tally,,,) = ltvPlugin.getProposal(proposalId);
        assertEq(tally.yes, aliceBalance);

        assertEq(tally.yes + tally.no + tally.abstain, aliceBalance);
    }

    function test_GivenVotingWithMoreLockedBalance()
        external
        whenCallingVote
        givenStandardVotingMode2
        givenVotingTheSameOption
    {
        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _vote(alice, IMajorityVoting.VoteOption.Yes, 0.5 ether);

        uint256 aliceBalance = lockManager.getLockedBalance(alice);

        _lock(alice, 0.5 ether);
        // It should emit an event
        vm.expectEmit(true, true, true, true);
        emit IMajorityVoting.VoteCast(proposalId, alice, IMajorityVoting.VoteOption.Yes, aliceBalance + 0.5 ether);
        vm.prank(alice);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);

        // It should increase the voter's usedVotingPower
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), aliceBalance + 0.5 ether);

        // It should increase the right tally of the voted option
        (,,, MajorityVotingBase.Tally memory tally,,,) = ltvPlugin.getProposal(proposalId);
        assertEq(tally.yes, aliceBalance + 0.5 ether);

        // It should increase the right total voting power
        assertEq(tally.yes + tally.no + tally.abstain, aliceBalance + 0.5 ether);
    }

    modifier givenVotingAnotherOption() {
        _;
    }

    function test_RevertGiven_VotingWithTheSameLockedBalance2()
        external
        whenCallingVote
        givenStandardVotingMode2
        givenVotingAnotherOption
    {
        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _vote(alice, IMajorityVoting.VoteOption.Yes, 0.5 ether);

        uint256 aliceBalance = lockManager.getLockedBalance(alice);

        // It should revert
        vm.expectRevert(abi.encodeWithSelector(VoteCastForbidden.selector, proposalId, alice));
        vm.prank(alice);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.No);

        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), aliceBalance);

        (,,, MajorityVotingBase.Tally memory tally,,,) = ltvPlugin.getProposal(proposalId);
        assertEq(tally.yes, aliceBalance);
        assertEq(tally.yes + tally.no + tally.abstain, aliceBalance);
    }

    function test_RevertGiven_VotingWithMoreLockedBalance2()
        external
        whenCallingVote
        givenStandardVotingMode2
        givenVotingAnotherOption
    {
        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _vote(alice, IMajorityVoting.VoteOption.Yes, 0.5 ether);

        uint256 aliceBalance = lockManager.getLockedBalance(alice);
        _lock(alice, 0.5 ether);

        // It should revert
        vm.expectRevert(abi.encodeWithSelector(VoteCastForbidden.selector, proposalId, alice));
        vm.prank(alice);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.No);

        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), aliceBalance);

        (,,, MajorityVotingBase.Tally memory tally,,,) = ltvPlugin.getProposal(proposalId);
        assertEq(tally.yes, aliceBalance);
        assertEq(tally.yes + tally.no + tally.abstain, aliceBalance);
    }

    modifier givenVoteReplacementMode2() {
        (dao, ltvPlugin, lockManager, lockableToken) =
            builder.withVoteReplacement().withVotingPlugin().withProposer(alice).withTokenHolder(alice, 1 ether).build();

        _;
    }

    modifier givenVotingTheFirstTime2() {
        _;
    }

    function test_GivenHasLockedBalance2()
        external
        whenCallingVote
        givenVoteReplacementMode2
        givenVotingTheFirstTime2
    {
        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _lock(alice, 1 ether);

        uint256 aliceBalance = lockManager.getLockedBalance(alice);

        // It should emit an event
        vm.expectEmit(true, true, true, true);
        emit IMajorityVoting.VoteCast(proposalId, alice, IMajorityVoting.VoteOption.Yes, aliceBalance);

        vm.prank(alice);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);

        // It should set the right voter's usedVotingPower
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), aliceBalance);

        // It should set the right tally of the voted option
        (,,, MajorityVotingBase.Tally memory tally,,,) = ltvPlugin.getProposal(proposalId);
        assertEq(tally.yes, aliceBalance);

        // It should set the right total voting power
        assertEq(tally.yes + tally.no + tally.abstain, aliceBalance);
    }

    function test_RevertGiven_NoLockedBalance2()
        external
        whenCallingVote
        givenVoteReplacementMode2
        givenVotingTheFirstTime2
    {
        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        vm.prank(bob);
        vm.expectRevert();
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);

        // It should keep the right voter's usedVotingPower
        assertEq(ltvPlugin.usedVotingPower(proposalId, bob), 0);

        // It should set the right tally
        (,,, MajorityVotingBase.Tally memory tally,,,) = ltvPlugin.getProposal(proposalId);
        assertEq(tally.yes + tally.no + tally.abstain, 0);
    }

    modifier givenVotingTheSameOption2() {
        _;
    }

    function test_RevertGiven_VotingWithTheSameLockedBalance3()
        external
        whenCallingVote
        givenVoteReplacementMode2
        givenVotingTheSameOption2
    {
        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _lock(alice, 1 ether);

        uint256 aliceBalance = lockManager.getLockedBalance(alice);
        vm.prank(alice);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);

        // It should revert
        vm.expectRevert(abi.encodeWithSelector(VoteCastForbidden.selector, proposalId, alice));
        vm.prank(alice);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);

        //
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), aliceBalance);

        (,,, MajorityVotingBase.Tally memory tally,,,) = ltvPlugin.getProposal(proposalId);
        assertEq(tally.yes, aliceBalance);

        assertEq(tally.yes + tally.no + tally.abstain, aliceBalance);
    }

    function test_GivenVotingWithMoreLockedBalance3()
        external
        whenCallingVote
        givenVoteReplacementMode2
        givenVotingTheSameOption2
    {
        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _vote(alice, IMajorityVoting.VoteOption.Yes, 0.5 ether);

        uint256 aliceBalance = lockManager.getLockedBalance(alice);

        _lock(alice, 0.5 ether);
        // It should emit an event
        vm.expectEmit(true, true, true, true);
        emit IMajorityVoting.VoteCast(proposalId, alice, IMajorityVoting.VoteOption.Yes, aliceBalance + 0.5 ether);
        vm.prank(alice);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);

        // It should increase the voter's usedVotingPower
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), aliceBalance + 0.5 ether);

        // It should increase the right tally of the voted option
        (,,, MajorityVotingBase.Tally memory tally,,,) = ltvPlugin.getProposal(proposalId);
        assertEq(tally.yes, aliceBalance + 0.5 ether);

        // It should increase the right total voting power
        assertEq(tally.yes + tally.no + tally.abstain, aliceBalance + 0.5 ether);
    }

    modifier givenVotingAnotherOption2() {
        _;
    }

    function test_GivenVotingWithTheSameLockedBalance4()
        external
        whenCallingVote
        givenVoteReplacementMode2
        givenVotingAnotherOption2
    {
        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _vote(alice, IMajorityVoting.VoteOption.Yes, 0.5 ether);

        uint256 aliceBalance = lockManager.getLockedBalance(alice);

        (,,, MajorityVotingBase.Tally memory tally,,,) = ltvPlugin.getProposal(proposalId);
        assertEq(tally.yes, aliceBalance);
        assertEq(tally.no, 0);
        assertEq(tally.abstain, 0);

        // It should deallocate the current voting power
        // It should allocate that voting power into the new vote option

        // It should emit an event
        vm.expectEmit(true, true, true, true);
        emit IMajorityVoting.VoteCast(proposalId, alice, IMajorityVoting.VoteOption.No, aliceBalance);

        vm.prank(alice);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.No);
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), aliceBalance);

        (,,, tally,,,) = ltvPlugin.getProposal(proposalId);
        assertEq(tally.yes, 0);
        assertEq(tally.no, aliceBalance);
        assertEq(tally.abstain, 0);

        // It should deallocate the current voting power
        // It should allocate that voting power into the new vote option

        vm.prank(alice);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Abstain);
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), aliceBalance);

        (,,, tally,,,) = ltvPlugin.getProposal(proposalId);
        assertEq(tally.yes, 0);
        assertEq(tally.no, 0);
        assertEq(tally.abstain, aliceBalance);
    }

    function test_GivenVotingWithMoreLockedBalance4()
        external
        whenCallingVote
        givenVoteReplacementMode2
        givenVotingAnotherOption2
    {
        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _vote(alice, IMajorityVoting.VoteOption.Yes, 0.5 ether);

        uint256 aliceBalance = lockManager.getLockedBalance(alice);

        (,,, MajorityVotingBase.Tally memory tally,,,) = ltvPlugin.getProposal(proposalId);
        assertEq(tally.yes, aliceBalance);
        assertEq(tally.no, 0);
        assertEq(tally.abstain, 0);

        // It should deallocate the current voting power
        // It the voter's usedVotingPower should reflect the new balance
        // It should allocate that voting power into the new vote option

        _lock(alice, 0.2 ether);

        // It should emit an event
        vm.expectEmit(true, true, true, true);
        emit IMajorityVoting.VoteCast(proposalId, alice, IMajorityVoting.VoteOption.No, aliceBalance + 0.2 ether);

        vm.prank(alice);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.No);
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), aliceBalance + 0.2 ether);

        (,,, tally,,,) = ltvPlugin.getProposal(proposalId);
        assertEq(tally.yes, 0);
        assertEq(tally.no, aliceBalance + 0.2 ether);
        assertEq(tally.abstain, 0);

        // It should deallocate the current voting power
        // It should allocate that voting power into the new vote option

        vm.prank(alice);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Abstain);
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), aliceBalance + 0.2 ether);

        // It should update the total voting power

        (,,, tally,,,) = ltvPlugin.getProposal(proposalId);
        assertEq(tally.yes, 0);
        assertEq(tally.no, 0);
        assertEq(tally.abstain, aliceBalance + 0.2 ether);
    }

    modifier givenEarlyExecutionMode2() {
        (dao, ltvPlugin, lockManager, lockableToken) =
            builder.withEarlyExecution().withVotingPlugin().withProposer(alice).withTokenHolder(alice, 1 ether).build();

        _;
    }

    modifier givenVotingTheFirstTime3() {
        _;
    }

    function test_GivenHasLockedBalance3() external whenCallingVote givenEarlyExecutionMode2 givenVotingTheFirstTime3 {
        // It should set the right voter's usedVotingPower
        // It should set the right tally of the voted option
        // It should set the right total voting power

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _lock(alice, 1 ether);

        uint256 aliceBalance = lockManager.getLockedBalance(alice);

        // It should emit an event
        vm.expectEmit(true, true, true, true);
        emit IMajorityVoting.VoteCast(proposalId, alice, IMajorityVoting.VoteOption.Yes, aliceBalance);

        vm.prank(alice);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);

        // It should set the right voter's usedVotingPower
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), aliceBalance);

        // It should set the right tally of the voted option
        (,,, MajorityVotingBase.Tally memory tally,,,) = ltvPlugin.getProposal(proposalId);
        assertEq(tally.yes, aliceBalance);

        // It should set the right total voting power
        assertEq(tally.yes + tally.no + tally.abstain, aliceBalance);
    }

    function test_RevertGiven_NoLockedBalance3()
        external
        whenCallingVote
        givenEarlyExecutionMode2
        givenVotingTheFirstTime3
    {
        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        vm.prank(bob);
        vm.expectRevert();
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);

        // It should keep the right voter's usedVotingPower
        assertEq(ltvPlugin.usedVotingPower(proposalId, bob), 0);

        // It should set the right tally
        (,,, MajorityVotingBase.Tally memory tally,,,) = ltvPlugin.getProposal(proposalId);
        assertEq(tally.yes + tally.no + tally.abstain, 0);
    }

    modifier givenVotingTheSameOption3() {
        _;
    }

    function test_RevertGiven_VotingWithTheSameLockedBalance5()
        external
        whenCallingVote
        givenEarlyExecutionMode2
        givenVotingTheSameOption3
    {
        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _lock(alice, 1 ether);

        uint256 aliceBalance = lockManager.getLockedBalance(alice);
        vm.prank(alice);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);

        // It should revert
        vm.expectRevert(abi.encodeWithSelector(VoteCastForbidden.selector, proposalId, alice));
        vm.prank(alice);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);

        //
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), aliceBalance);

        (,,, MajorityVotingBase.Tally memory tally,,,) = ltvPlugin.getProposal(proposalId);
        assertEq(tally.yes, aliceBalance);

        assertEq(tally.yes + tally.no + tally.abstain, aliceBalance);
    }

    function test_GivenVotingWithMoreLockedBalance5()
        external
        whenCallingVote
        givenEarlyExecutionMode2
        givenVotingTheSameOption3
    {
        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _vote(alice, IMajorityVoting.VoteOption.Yes, 0.5 ether);

        uint256 aliceBalance = lockManager.getLockedBalance(alice);

        _lock(alice, 0.5 ether);
        // It should emit an event
        vm.expectEmit(true, true, true, true);
        emit IMajorityVoting.VoteCast(proposalId, alice, IMajorityVoting.VoteOption.Yes, aliceBalance + 0.5 ether);
        vm.prank(alice);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);

        // It should increase the voter's usedVotingPower
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), aliceBalance + 0.5 ether);

        // It should increase the right tally of the voted option
        (,,, MajorityVotingBase.Tally memory tally,,,) = ltvPlugin.getProposal(proposalId);
        assertEq(tally.yes, aliceBalance + 0.5 ether);

        // It should increase the right total voting power
        assertEq(tally.yes + tally.no + tally.abstain, aliceBalance + 0.5 ether);
    }

    modifier givenVotingAnotherOption3() {
        _;
    }

    function test_RevertGiven_VotingWithTheSameLockedBalance6()
        external
        whenCallingVote
        givenEarlyExecutionMode2
        givenVotingAnotherOption3
    {
        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _vote(alice, IMajorityVoting.VoteOption.Yes, 0.5 ether);

        uint256 aliceBalance = lockManager.getLockedBalance(alice);
        _lock(alice, 0.5 ether);

        // It should revert
        vm.expectRevert(abi.encodeWithSelector(VoteCastForbidden.selector, proposalId, alice));
        vm.prank(alice);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.No);

        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), aliceBalance);

        (,,, MajorityVotingBase.Tally memory tally,,,) = ltvPlugin.getProposal(proposalId);
        assertEq(tally.yes, aliceBalance);
        assertEq(tally.yes + tally.no + tally.abstain, aliceBalance);
    }

    function test_RevertGiven_VotingWithMoreLockedBalance6()
        external
        whenCallingVote
        givenEarlyExecutionMode2
        givenVotingAnotherOption3
    {
        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _vote(alice, IMajorityVoting.VoteOption.Yes, 0.5 ether);

        uint256 aliceBalance = lockManager.getLockedBalance(alice);
        _lock(alice, 0.5 ether);

        // It should revert
        vm.expectRevert(abi.encodeWithSelector(VoteCastForbidden.selector, proposalId, alice));
        vm.prank(alice);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.No);

        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), aliceBalance);

        (,,, MajorityVotingBase.Tally memory tally,,,) = ltvPlugin.getProposal(proposalId);
        assertEq(tally.yes, aliceBalance);
        assertEq(tally.yes + tally.no + tally.abstain, aliceBalance);
    }

    modifier givenTheVoteMakesTheProposalPass() {
        _;
    }

    function test_GivenTheCallerHasPermissionToCallExecute()
        external
        whenCallingVote
        givenEarlyExecutionMode2
        givenTheVoteMakesTheProposalPass
    {
        // It hasSucceeded() should return true
        // It canExecute() should return true
        // It isSupportThresholdReachedEarly() should return true
        // It isMinVotingPowerReached() should return true
        // It isMinApprovalReached() should return true
        // It should execute the proposal
        // It the proposal should be marked as executed
        // It should emit an event

        (dao, ltvPlugin, lockManager, lockableToken) = new DaoBuilder().withEarlyExecution().withVotingPlugin()
            .withProposer(alice).withTokenHolder(alice, 50 ether).withTokenHolder(bob, 50 ether).withSupportThresholdRatio(
            500_000
        ).build();
        dao.grant(address(ltvPlugin), address(lockManager), ltvPlugin.EXECUTE_PROPOSAL_PERMISSION_ID());

        assertEq(lockableToken.balanceOf(alice), 50 ether);
        assertEq(lockableToken.balanceOf(bob), 50 ether);
        assertEq(lockableToken.totalSupply(), 100 ether);

        vm.deal(address(dao), 1 ether);
        actions.push(Action({to: david, value: 1 ether, data: bytes("")}));

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _vote(alice, IMajorityVoting.VoteOption.Yes, 50 ether);
        _lock(bob, 0.01 ether);

        vm.prank(bob);
        vm.expectEmit();
        emit ProposalExecuted(proposalId);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);

        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), 50 ether);
        assertEq(ltvPlugin.usedVotingPower(proposalId, bob), 0.01 ether);

        (,,, MajorityVotingBase.Tally memory tally,,,) = ltvPlugin.getProposal(proposalId);
        assertEq(tally.yes, 50.01 ether);
        assertEq(tally.yes + tally.no + tally.abstain, 50.01 ether);

        assertTrue(ltvPlugin.isSupportThresholdReachedEarly(proposalId));
        assertTrue(ltvPlugin.isMinVotingPowerReached(proposalId));
        assertTrue(ltvPlugin.isMinApprovalReached(proposalId));
        assertTrue(ltvPlugin.hasSucceeded(proposalId));
        assertFalse(ltvPlugin.canExecute(proposalId));

        (bool open, bool executed,,,,,) = ltvPlugin.getProposal(proposalId);
        assertFalse(open);
        assertTrue(executed);

        assertEq(address(dao).balance, 0);
        assertEq(david.balance, 1 ether);
    }

    modifier whenCallingClearvote() {
        _;
    }

    function test_GivenTheVoterHasNoPriorVotingPower() external whenCallingClearvote {
        // It should do nothing

        (dao, ltvPlugin, lockManager, lockableToken) =
            new DaoBuilder().withVoteReplacement().withVotingPlugin().withProposer(alice).build();

        assertEq(lockableToken.balanceOf(alice), 0);
        assertEq(lockableToken.totalSupply(), 10 ether);

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), 0);

        vm.prank(address(lockManager));
        ltvPlugin.clearVote(proposalId, alice);

        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), 0);

        (,,, MajorityVotingBase.Tally memory tally,,,) = ltvPlugin.getProposal(proposalId);
        assertEq(tally.yes, 0);
        assertEq(tally.yes + tally.no + tally.abstain, 0);
    }

    function test_RevertGiven_TheProposalIsNotOpen() external whenCallingClearvote {
        // It should revert

        (dao, ltvPlugin, lockManager, lockableToken) =
            new DaoBuilder().withStandardVoting().withVotingPlugin().withProposer(alice).build();

        assertEq(lockableToken.balanceOf(alice), 0);
        assertEq(lockableToken.totalSupply(), 10 ether);

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        vm.prank(address(lockManager));
        vm.expectRevert();
        ltvPlugin.clearVote(proposalId + 1, alice);

        assertEq(ltvPlugin.usedVotingPower(proposalId + 1, alice), 0);

        (,,, MajorityVotingBase.Tally memory tally,,,) = ltvPlugin.getProposal(proposalId + 1);
        assertEq(tally.yes, 0);
        assertEq(tally.yes + tally.no + tally.abstain, 0);
    }

    function test_RevertGiven_EarlyExecutionMode3() external whenCallingClearvote {
        // It should revert

        (dao, ltvPlugin, lockManager, lockableToken) = new DaoBuilder().withEarlyExecution().withVotingPlugin()
            .withProposer(alice).withTokenHolder(alice, 50 ether).build();

        assertEq(lockableToken.balanceOf(alice), 50 ether);
        assertEq(lockableToken.totalSupply(), 50 ether);

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _vote(alice, IMajorityVoting.VoteOption.Yes, 50 ether);

        vm.prank(address(lockManager));
        vm.expectRevert(abi.encodeWithSelector(VoteRemovalForbidden.selector, proposalId, alice));
        ltvPlugin.clearVote(proposalId, alice);

        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), 50 ether);

        (,,, MajorityVotingBase.Tally memory tally,,,) = ltvPlugin.getProposal(proposalId);
        assertEq(tally.yes, 50 ether);
        assertEq(tally.yes + tally.no + tally.abstain, 50 ether);
    }

    function test_GivenStandardVotingMode3() external whenCallingClearvote {
        // It should revert

        (dao, ltvPlugin, lockManager, lockableToken) = new DaoBuilder().withStandardVoting().withVotingPlugin()
            .withProposer(alice).withTokenHolder(alice, 50 ether).build();

        assertEq(lockableToken.balanceOf(alice), 50 ether);
        assertEq(lockableToken.totalSupply(), 50 ether);

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _vote(alice, IMajorityVoting.VoteOption.Yes, 50 ether);

        vm.prank(address(lockManager));
        vm.expectRevert(abi.encodeWithSelector(VoteRemovalForbidden.selector, proposalId, alice));
        ltvPlugin.clearVote(proposalId, alice);

        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), 50 ether);

        (,,, MajorityVotingBase.Tally memory tally,,,) = ltvPlugin.getProposal(proposalId);
        assertEq(tally.yes, 50 ether);
        assertEq(tally.yes + tally.no + tally.abstain, 50 ether);
    }

    function test_GivenVoteReplacementMode3() external whenCallingClearvote {
        // It should deallocate the current voting power

        (dao, ltvPlugin, lockManager, lockableToken) = new DaoBuilder().withVoteReplacement().withVotingPlugin()
            .withProposer(alice).withTokenHolder(alice, 50 ether).build();

        assertEq(lockableToken.balanceOf(alice), 50 ether);
        assertEq(lockableToken.totalSupply(), 50 ether);

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _vote(alice, IMajorityVoting.VoteOption.Yes, 50 ether);

        vm.prank(address(lockManager));
        ltvPlugin.clearVote(proposalId, alice);

        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), 0);

        (,,, MajorityVotingBase.Tally memory tally,,,) = ltvPlugin.getProposal(proposalId);
        assertEq(tally.yes, 0);
        assertEq(tally.yes + tally.no + tally.abstain, 0);
    }

    modifier givenVoteReplacementMode3() {
        _;
    }

    function test_RevertGiven_TheCallerIsNotTheLockManager() external whenCallingClearvote givenVoteReplacementMode3 {
        // It should revert
        //
        (dao, ltvPlugin, lockManager, lockableToken) = new DaoBuilder().withVoteReplacement().withVotingPlugin()
            .withProposer(alice).withTokenHolder(alice, 50 ether).build();

        assertEq(lockableToken.balanceOf(alice), 50 ether);
        assertEq(lockableToken.totalSupply(), 50 ether);

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _vote(alice, IMajorityVoting.VoteOption.Yes, 50 ether);

        // revert
        vm.prank(address(dao));
        vm.expectRevert(abi.encodeWithSelector(VoteRemovalForbidden.selector, proposalId, alice));
        ltvPlugin.clearVote(proposalId, alice);

        vm.prank(address(ltvPlugin));
        vm.expectRevert(abi.encodeWithSelector(VoteRemovalForbidden.selector, proposalId, alice));
        ltvPlugin.clearVote(proposalId, alice);

        vm.prank(david);
        vm.expectRevert(abi.encodeWithSelector(VoteRemovalForbidden.selector, proposalId, alice));
        ltvPlugin.clearVote(proposalId, alice);
    }

    modifier whenCallingGetVote() {
        (dao, ltvPlugin, lockManager, lockableToken) = new DaoBuilder().withVoteReplacement().withVotingPlugin()
            .withProposer(alice).withTokenHolder(alice, 50 ether).build();

        _;
    }

    function test_GivenTheVoteExists() external whenCallingGetVote {
        // It should return the right data

        assertEq(lockableToken.balanceOf(alice), 50 ether);
        assertEq(lockableToken.totalSupply(), 50 ether);

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _vote(alice, IMajorityVoting.VoteOption.Yes, 25 ether);
        assertEq(uint8(ltvPlugin.getVote(proposalId, alice).voteOption), uint8(IMajorityVoting.VoteOption.Yes));
        assertEq(ltvPlugin.getVote(proposalId, alice).votingPower, 25 ether);

        _vote(alice, IMajorityVoting.VoteOption.Yes, 10 ether);
        assertEq(uint8(ltvPlugin.getVote(proposalId, alice).voteOption), uint8(IMajorityVoting.VoteOption.Yes));
        assertEq(ltvPlugin.getVote(proposalId, alice).votingPower, 35 ether);

        _vote(alice, IMajorityVoting.VoteOption.No, 5 ether);
        assertEq(uint8(ltvPlugin.getVote(proposalId, alice).voteOption), uint8(IMajorityVoting.VoteOption.No));
        assertEq(ltvPlugin.getVote(proposalId, alice).votingPower, 40 ether);

        _vote(alice, IMajorityVoting.VoteOption.Abstain, 5 ether);
        assertEq(uint8(ltvPlugin.getVote(proposalId, alice).voteOption), uint8(IMajorityVoting.VoteOption.Abstain));
        assertEq(ltvPlugin.getVote(proposalId, alice).votingPower, 45 ether);
    }

    function test_GivenTheVoteDoesNotExist() external whenCallingGetVote {
        // It should return empty values

        assertEq(lockableToken.balanceOf(alice), 50 ether);
        assertEq(lockableToken.totalSupply(), 50 ether);

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        assertEq(uint8(ltvPlugin.getVote(proposalId, alice).voteOption), uint8(IMajorityVoting.VoteOption.None));
        assertEq(ltvPlugin.getVote(proposalId, alice).votingPower, 0);

        assertEq(uint8(ltvPlugin.getVote(proposalId, bob).voteOption), uint8(IMajorityVoting.VoteOption.None));
        assertEq(ltvPlugin.getVote(proposalId, bob).votingPower, 0);

        assertEq(uint8(ltvPlugin.getVote(proposalId, carol).voteOption), uint8(IMajorityVoting.VoteOption.None));
        assertEq(ltvPlugin.getVote(proposalId, carol).votingPower, 0);
    }

    modifier whenCallingTheProposalGetters() {
        _;
    }

    function test_GivenItDoesNotExist() external whenCallingTheProposalGetters {
        (dao, ltvPlugin, lockManager, lockableToken) = new DaoBuilder().withVotingPlugin().withProposer(alice).build();

        // It getProposal() returns empty values
        (
            bool open,
            bool executed,
            MajorityVotingBase.ProposalParameters memory parameters,
            MajorityVotingBase.Tally memory tally,
            Action[] memory actions_,
            uint256 allowFailureMap,
            IPlugin.TargetConfig memory targetConfig
        ) = ltvPlugin.getProposal(proposalId + 54321);

        assertFalse(open);
        assertFalse(executed);
        assertEq(uint8(parameters.votingMode), uint8(0));
        assertEq(uint32(parameters.supportThresholdRatio), uint32(0));
        assertEq(uint64(parameters.startDate), uint64(0));
        assertEq(uint64(parameters.endDate), uint64(0));
        assertEq(parameters.minParticipationRatio, 0);
        assertEq(parameters.minApprovalRatio, 0);

        assertEq(tally.yes, 0);
        assertEq(tally.no, 0);
        assertEq(tally.abstain, 0);

        assertEq(actions_.length, 0);

        assertEq(allowFailureMap, 0);

        assertEq(targetConfig.target, address(0));
        assertEq(uint8(targetConfig.operation), uint8(0));

        // It isProposalOpen() returns false
        assertFalse(ltvPlugin.isProposalOpen(proposalId + 54321));

        // It hasSucceeded() should return false
        vm.expectRevert(abi.encodeWithSelector(NonexistentProposal.selector, proposalId + 54321));
        ltvPlugin.hasSucceeded(proposalId + 54321);

        // It canExecute() should return false
        vm.expectRevert(abi.encodeWithSelector(NonexistentProposal.selector, proposalId + 54321));
        ltvPlugin.canExecute(proposalId + 54321);

        // It isSupportThresholdReachedEarly() should return false
        assertFalse(ltvPlugin.isSupportThresholdReachedEarly(proposalId + 54321));

        // It isSupportThresholdReached() should return false
        assertFalse(ltvPlugin.isSupportThresholdReached(proposalId + 54321));

        // It isMinVotingPowerReached() should return true
        assertTrue(ltvPlugin.isMinVotingPowerReached(proposalId + 54321));

        // It isMinApprovalReached() should return true
        assertTrue(ltvPlugin.isMinApprovalReached(proposalId + 54321));

        // It usedVotingPower() should return 0 for all voters
        assertEq(ltvPlugin.usedVotingPower(proposalId + 54321, alice), 0);
        assertEq(ltvPlugin.usedVotingPower(proposalId + 54321, bob), 0);
        assertEq(ltvPlugin.usedVotingPower(proposalId + 54321, carol), 0);
        assertEq(ltvPlugin.usedVotingPower(proposalId + 54321, david), 0);
    }

    function test_GivenItHasNotStarted() external whenCallingTheProposalGetters {
        vm.deal(address(dao), 1 ether);
        actions.push(Action({to: david, value: 1 ether, data: bytes("")}));
        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, uint64(block.timestamp + 1), 0, bytes(""));

        // It getProposal() returns the right values
        (
            bool open,
            bool executed,
            MajorityVotingBase.ProposalParameters memory parameters,
            MajorityVotingBase.Tally memory tally,
            Action[] memory actions_,
            uint256 allowFailureMap,
            IPlugin.TargetConfig memory targetConfig
        ) = ltvPlugin.getProposal(proposalId);

        assertFalse(open);
        assertFalse(executed);
        assertEq(uint8(parameters.votingMode), uint8(MajorityVotingBase.VotingMode.Standard));
        assertEq(uint32(parameters.supportThresholdRatio), uint32(100_000));
        assertEq(uint64(parameters.startDate), uint64(block.timestamp + 1));
        assertEq(uint64(parameters.endDate), uint64(block.timestamp + 1 + 10 days));
        assertEq(parameters.minParticipationRatio, 100_000);
        assertEq(parameters.minApprovalRatio, 100_000);

        assertEq(tally.yes, 0);
        assertEq(tally.no, 0);
        assertEq(tally.abstain, 0);

        assertEq(actions_.length, 1);

        assertEq(allowFailureMap, 0);

        assertEq(targetConfig.target, address(dao));
        assertEq(uint8(targetConfig.operation), uint8(IPlugin.Operation.Call));

        // It isProposalOpen() returns false
        assertFalse(ltvPlugin.isProposalOpen(proposalId));

        // It hasSucceeded() should return false
        assertFalse(ltvPlugin.hasSucceeded(proposalId));

        // It canExecute() should return false
        assertFalse(ltvPlugin.canExecute(proposalId));

        // It isSupportThresholdReachedEarly() should return false
        assertFalse(ltvPlugin.isSupportThresholdReachedEarly(proposalId));

        // It isSupportThresholdReached() should return false
        assertFalse(ltvPlugin.isSupportThresholdReached(proposalId));

        // It isMinVotingPowerReached() should return false
        assertFalse(ltvPlugin.isMinVotingPowerReached(proposalId));

        // It isMinApprovalReached() should return false
        assertFalse(ltvPlugin.isMinApprovalReached(proposalId));

        // It usedVotingPower() should return 0 for all voters
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), 0);
        assertEq(ltvPlugin.usedVotingPower(proposalId, bob), 0);
        assertEq(ltvPlugin.usedVotingPower(proposalId, carol), 0);
        assertEq(ltvPlugin.usedVotingPower(proposalId, david), 0);
    }

    function test_GivenItHasNotPassedYet() external whenCallingTheProposalGetters {
        vm.deal(address(dao), 1 ether);
        actions.push(Action({to: david, value: 1 ether, data: bytes("")}));
        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _vote(alice, IMajorityVoting.VoteOption.Yes, 1 ether);

        // It getProposal() returns the right values
        (
            bool open,
            bool executed,
            MajorityVotingBase.ProposalParameters memory parameters,
            MajorityVotingBase.Tally memory tally,
            Action[] memory actions_,
            uint256 allowFailureMap,
            IPlugin.TargetConfig memory targetConfig
        ) = ltvPlugin.getProposal(proposalId);

        assertTrue(open);
        assertFalse(executed);
        assertEq(uint8(parameters.votingMode), uint8(MajorityVotingBase.VotingMode.Standard));
        assertEq(uint32(parameters.supportThresholdRatio), uint32(100_000));
        assertEq(uint64(parameters.startDate), uint64(block.timestamp));
        assertEq(uint64(parameters.endDate), uint64(block.timestamp + 10 days));
        assertEq(parameters.minParticipationRatio, 100_000);
        assertEq(parameters.minApprovalRatio, 100_000);

        assertEq(tally.yes, 1 ether);
        assertEq(tally.no, 0);
        assertEq(tally.abstain, 0);

        assertEq(actions_.length, 1);

        assertEq(allowFailureMap, 0);

        assertEq(targetConfig.target, address(dao));
        assertEq(uint8(targetConfig.operation), uint8(IPlugin.Operation.Call));

        // It isProposalOpen() returns true
        assertTrue(ltvPlugin.isProposalOpen(proposalId));

        // It hasSucceeded() should return false
        assertFalse(ltvPlugin.hasSucceeded(proposalId));

        // It canExecute() should return false
        assertFalse(ltvPlugin.canExecute(proposalId));

        // It isSupportThresholdReachedEarly() should return false
        assertFalse(ltvPlugin.isSupportThresholdReachedEarly(proposalId));

        // It isSupportThresholdReached() should return true
        assertTrue(ltvPlugin.isSupportThresholdReached(proposalId));

        // It isMinVotingPowerReached() should return false
        assertFalse(ltvPlugin.isMinVotingPowerReached(proposalId));

        // It isMinApprovalReached() should return false
        assertFalse(ltvPlugin.isMinApprovalReached(proposalId));

        // It usedVotingPower() should return 0 for all voters
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), 1 ether);
        assertEq(ltvPlugin.usedVotingPower(proposalId, bob), 0);
        assertEq(ltvPlugin.usedVotingPower(proposalId, carol), 0);
        assertEq(ltvPlugin.usedVotingPower(proposalId, david), 0);
    }

    modifier givenItDidNotPassAfterEndDate() {
        _;
    }

    function test_GivenItDidNotPassAfterEndDate()
        external
        whenCallingTheProposalGetters
        givenItDidNotPassAfterEndDate
    {
        vm.deal(address(dao), 1 ether);
        actions.push(Action({to: david, value: 1 ether, data: bytes("")}));
        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _vote(alice, IMajorityVoting.VoteOption.Yes, 1 ether);
        vm.warp(block.timestamp + 10 days + 1);

        // It getProposal() returns the right values
        (
            bool open,
            bool executed,
            MajorityVotingBase.ProposalParameters memory parameters,
            MajorityVotingBase.Tally memory tally,
            Action[] memory actions_,
            uint256 allowFailureMap,
            IPlugin.TargetConfig memory targetConfig
        ) = ltvPlugin.getProposal(proposalId);

        assertFalse(open);
        assertFalse(executed);
        assertEq(uint8(parameters.votingMode), uint8(MajorityVotingBase.VotingMode.Standard));
        assertEq(uint32(parameters.supportThresholdRatio), uint32(100_000));
        assertEq(uint64(parameters.startDate), uint64(block.timestamp - 10 days - 1));
        assertEq(uint64(parameters.endDate), uint64(block.timestamp - 1));
        assertEq(parameters.minParticipationRatio, 100_000);
        assertEq(parameters.minApprovalRatio, 100_000);

        assertEq(tally.yes, 1 ether);
        assertEq(tally.no, 0);
        assertEq(tally.abstain, 0);

        assertEq(actions_.length, 1);

        assertEq(allowFailureMap, 0);

        assertEq(targetConfig.target, address(dao));
        assertEq(uint8(targetConfig.operation), uint8(IPlugin.Operation.Call));

        // It isProposalOpen() returns false
        assertFalse(ltvPlugin.isProposalOpen(proposalId));

        // It hasSucceeded() should return false
        assertFalse(ltvPlugin.hasSucceeded(proposalId));

        // It canExecute() should return false
        assertFalse(ltvPlugin.canExecute(proposalId));

        // It isSupportThresholdReachedEarly() should return false
        assertFalse(ltvPlugin.isSupportThresholdReachedEarly(proposalId));

        // It isSupportThresholdReached() should return true
        assertTrue(ltvPlugin.isSupportThresholdReached(proposalId));

        // It isMinVotingPowerReached() should return false
        assertFalse(ltvPlugin.isMinVotingPowerReached(proposalId));

        // It isMinApprovalReached() should return false
        assertFalse(ltvPlugin.isMinApprovalReached(proposalId));

        // It usedVotingPower() should return 0 for all voters
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), 1 ether);
        assertEq(ltvPlugin.usedVotingPower(proposalId, bob), 0);
        assertEq(ltvPlugin.usedVotingPower(proposalId, carol), 0);
        assertEq(ltvPlugin.usedVotingPower(proposalId, david), 0);
    }

    function test_GivenTheSupportThresholdWasNotAchieved()
        external
        whenCallingTheProposalGetters
        givenItDidNotPassAfterEndDate
    {
        vm.deal(address(dao), 1 ether);
        actions.push(Action({to: david, value: 1 ether, data: bytes("")}));
        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _vote(alice, IMajorityVoting.VoteOption.No, 1 ether);
        vm.warp(block.timestamp + 10 days + 1);

        // It getProposal() returns the right values
        (
            bool open,
            bool executed,
            MajorityVotingBase.ProposalParameters memory parameters,
            MajorityVotingBase.Tally memory tally,
            Action[] memory actions_,
            uint256 allowFailureMap,
            IPlugin.TargetConfig memory targetConfig
        ) = ltvPlugin.getProposal(proposalId);

        assertFalse(open);
        assertFalse(executed);
        assertEq(uint8(parameters.votingMode), uint8(MajorityVotingBase.VotingMode.Standard));
        assertEq(uint32(parameters.supportThresholdRatio), uint32(100_000));
        assertEq(uint64(parameters.startDate), uint64(block.timestamp - 10 days - 1));
        assertEq(uint64(parameters.endDate), uint64(block.timestamp - 1));
        assertEq(parameters.minParticipationRatio, 100_000);
        assertEq(parameters.minApprovalRatio, 100_000);

        assertEq(tally.yes, 0);
        assertEq(tally.no, 1 ether);
        assertEq(tally.abstain, 0);

        assertEq(actions_.length, 1);

        assertEq(allowFailureMap, 0);

        assertEq(targetConfig.target, address(dao));
        assertEq(uint8(targetConfig.operation), uint8(IPlugin.Operation.Call));

        // It isProposalOpen() returns false
        assertFalse(ltvPlugin.isProposalOpen(proposalId));

        // It hasSucceeded() should return false
        assertFalse(ltvPlugin.hasSucceeded(proposalId));

        // It canExecute() should return false
        assertFalse(ltvPlugin.canExecute(proposalId));

        // It isSupportThresholdReachedEarly() should return false
        assertFalse(ltvPlugin.isSupportThresholdReachedEarly(proposalId));

        // It isSupportThresholdReached() should return false
        assertFalse(ltvPlugin.isSupportThresholdReached(proposalId));

        // It isMinVotingPowerReached() should return false
        assertFalse(ltvPlugin.isMinVotingPowerReached(proposalId));

        // It isMinApprovalReached() should return false
        assertFalse(ltvPlugin.isMinApprovalReached(proposalId));

        // It usedVotingPower() should return 0 for all voters
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), 1 ether);
        assertEq(ltvPlugin.usedVotingPower(proposalId, bob), 0);
        assertEq(ltvPlugin.usedVotingPower(proposalId, carol), 0);
        assertEq(ltvPlugin.usedVotingPower(proposalId, david), 0);
    }

    function test_GivenTheSupportThresholdWasAchieved()
        external
        whenCallingTheProposalGetters
        givenItDidNotPassAfterEndDate
    {
        vm.deal(address(dao), 1 ether);
        actions.push(Action({to: david, value: 1 ether, data: bytes("")}));
        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _vote(alice, IMajorityVoting.VoteOption.Yes, 1 ether);
        vm.warp(block.timestamp + 10 days + 1);

        // It getProposal() returns the right values
        (
            bool open,
            bool executed,
            MajorityVotingBase.ProposalParameters memory parameters,
            MajorityVotingBase.Tally memory tally,
            Action[] memory actions_,
            uint256 allowFailureMap,
            IPlugin.TargetConfig memory targetConfig
        ) = ltvPlugin.getProposal(proposalId);

        assertFalse(open);
        assertFalse(executed);
        assertEq(uint8(parameters.votingMode), uint8(MajorityVotingBase.VotingMode.Standard));
        assertEq(uint32(parameters.supportThresholdRatio), uint32(100_000));
        assertEq(uint64(parameters.startDate), uint64(block.timestamp - 10 days - 1));
        assertEq(uint64(parameters.endDate), uint64(block.timestamp - 1));
        assertEq(parameters.minParticipationRatio, 100_000);
        assertEq(parameters.minApprovalRatio, 100_000);

        assertEq(tally.yes, 1 ether);
        assertEq(tally.no, 0);
        assertEq(tally.abstain, 0);

        assertEq(actions_.length, 1);

        assertEq(allowFailureMap, 0);

        assertEq(targetConfig.target, address(dao));
        assertEq(uint8(targetConfig.operation), uint8(IPlugin.Operation.Call));

        // It isProposalOpen() returns false
        assertFalse(ltvPlugin.isProposalOpen(proposalId));

        // It hasSucceeded() should return false
        assertFalse(ltvPlugin.hasSucceeded(proposalId));

        // It canExecute() should return false
        assertFalse(ltvPlugin.canExecute(proposalId));

        // It isSupportThresholdReachedEarly() should return false
        assertFalse(ltvPlugin.isSupportThresholdReachedEarly(proposalId));

        // It isSupportThresholdReached() should return true
        assertTrue(ltvPlugin.isSupportThresholdReached(proposalId));

        // It isMinVotingPowerReached() should return false
        assertFalse(ltvPlugin.isMinVotingPowerReached(proposalId));

        // It isMinApprovalReached() should return false
        assertFalse(ltvPlugin.isMinApprovalReached(proposalId));

        // It usedVotingPower() should return 0 for all voters
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), 1 ether);
        assertEq(ltvPlugin.usedVotingPower(proposalId, bob), 0);
        assertEq(ltvPlugin.usedVotingPower(proposalId, carol), 0);
        assertEq(ltvPlugin.usedVotingPower(proposalId, david), 0);
    }

    function test_GivenTheMinimumVotingPowerWasNotReached()
        external
        whenCallingTheProposalGetters
        givenItDidNotPassAfterEndDate
    {
        vm.deal(address(dao), 1 ether);
        actions.push(Action({to: david, value: 1 ether, data: bytes("")}));
        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _vote(bob, IMajorityVoting.VoteOption.Yes, 2 ether);
        vm.warp(block.timestamp + 10 days + 1);

        // It getProposal() returns the right values
        (
            bool open,
            bool executed,
            MajorityVotingBase.ProposalParameters memory parameters,
            MajorityVotingBase.Tally memory tally,
            Action[] memory actions_,
            uint256 allowFailureMap,
            IPlugin.TargetConfig memory targetConfig
        ) = ltvPlugin.getProposal(proposalId);

        assertFalse(open);
        assertFalse(executed);
        assertEq(uint8(parameters.votingMode), uint8(MajorityVotingBase.VotingMode.Standard));
        assertEq(uint32(parameters.supportThresholdRatio), uint32(100_000));
        assertEq(uint64(parameters.startDate), uint64(block.timestamp - 10 days - 1));
        assertEq(uint64(parameters.endDate), uint64(block.timestamp - 1));
        assertEq(parameters.minParticipationRatio, 100_000);
        assertEq(parameters.minApprovalRatio, 100_000);

        assertEq(tally.yes, 2 ether);
        assertEq(tally.no, 0);
        assertEq(tally.abstain, 0);

        assertEq(actions_.length, 1);

        assertEq(allowFailureMap, 0);

        assertEq(targetConfig.target, address(dao));
        assertEq(uint8(targetConfig.operation), uint8(IPlugin.Operation.Call));

        // It isProposalOpen() returns false
        assertFalse(ltvPlugin.isProposalOpen(proposalId));

        // It hasSucceeded() should return false
        assertFalse(ltvPlugin.hasSucceeded(proposalId));

        // It canExecute() should return false
        assertFalse(ltvPlugin.canExecute(proposalId));

        // It isSupportThresholdReachedEarly() should return false
        assertFalse(ltvPlugin.isSupportThresholdReachedEarly(proposalId));

        // It isSupportThresholdReached() should return true
        assertTrue(ltvPlugin.isSupportThresholdReached(proposalId));

        // It isMinVotingPowerReached() should return false
        assertFalse(ltvPlugin.isMinVotingPowerReached(proposalId));

        // It isMinApprovalReached() should return false
        assertFalse(ltvPlugin.isMinApprovalReached(proposalId));

        // It usedVotingPower() should return 0 for all voters
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), 0);
        assertEq(ltvPlugin.usedVotingPower(proposalId, bob), 2 ether);
        assertEq(ltvPlugin.usedVotingPower(proposalId, carol), 0);
        assertEq(ltvPlugin.usedVotingPower(proposalId, david), 0);
    }

    function test_GivenTheMinimumVotingPowerWasReached()
        external
        whenCallingTheProposalGetters
        givenItDidNotPassAfterEndDate
    {
        (dao, ltvPlugin, lockManager, lockableToken) = new DaoBuilder().withVotingPlugin().withSupportThresholdRatio(
            500_000
        ).withProposer(alice).withTokenHolder(alice, 5 ether).withTokenHolder(bob, 10 ether).build();

        vm.deal(address(dao), 1 ether);
        actions.push(Action({to: david, value: 1 ether, data: bytes("")}));
        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _vote(alice, IMajorityVoting.VoteOption.Yes, 2 ether);
        _vote(bob, IMajorityVoting.VoteOption.No, 3 ether);
        vm.warp(block.timestamp + 10 days + 1);

        // It getProposal() returns the right values
        (
            bool open,
            bool executed,
            MajorityVotingBase.ProposalParameters memory parameters,
            MajorityVotingBase.Tally memory tally,
            Action[] memory actions_,
            uint256 allowFailureMap,
            IPlugin.TargetConfig memory targetConfig
        ) = ltvPlugin.getProposal(proposalId);

        assertFalse(open);
        assertFalse(executed);
        assertEq(uint8(parameters.votingMode), uint8(MajorityVotingBase.VotingMode.Standard));
        assertEq(uint32(parameters.supportThresholdRatio), uint32(500_000));
        assertEq(uint64(parameters.startDate), uint64(block.timestamp - 10 days - 1));
        assertEq(uint64(parameters.endDate), uint64(block.timestamp - 1));
        assertEq(parameters.minParticipationRatio, 100_000);
        assertEq(parameters.minApprovalRatio, 100_000);

        assertEq(tally.yes, 2 ether);
        assertEq(tally.no, 3 ether);
        assertEq(tally.abstain, 0);

        assertEq(actions_.length, 1);

        assertEq(allowFailureMap, 0);

        assertEq(targetConfig.target, address(dao));
        assertEq(uint8(targetConfig.operation), uint8(IPlugin.Operation.Call));

        // It isProposalOpen() returns false
        assertFalse(ltvPlugin.isProposalOpen(proposalId));

        // It hasSucceeded() should return false
        assertFalse(ltvPlugin.hasSucceeded(proposalId));

        // It canExecute() should return false
        assertFalse(ltvPlugin.canExecute(proposalId));

        // It isSupportThresholdReachedEarly() should return false
        assertFalse(ltvPlugin.isSupportThresholdReachedEarly(proposalId));

        // It isSupportThresholdReached() should return false
        assertFalse(ltvPlugin.isSupportThresholdReached(proposalId));

        // It isMinVotingPowerReached() should return true
        assertTrue(ltvPlugin.isMinVotingPowerReached(proposalId));

        // It isMinApprovalReached() should return true
        assertTrue(ltvPlugin.isMinApprovalReached(proposalId));

        // It usedVotingPower() should return 0 for all voters
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), 2 ether);
        assertEq(ltvPlugin.usedVotingPower(proposalId, bob), 3 ether);
        assertEq(ltvPlugin.usedVotingPower(proposalId, carol), 0);
        assertEq(ltvPlugin.usedVotingPower(proposalId, david), 0);
    }

    function test_GivenTheMinimumApprovalTallyWasNotAchieved()
        external
        whenCallingTheProposalGetters
        givenItDidNotPassAfterEndDate
    {
        // It isMinApprovalReached() should return false
        (dao, ltvPlugin, lockManager, lockableToken) = new DaoBuilder().withVotingPlugin().withMinApprovalRatio(500_000)
            .withTokenHolder(alice, 10 ether).withTokenHolder(bob, 90 ether).withProposer(alice) // 50%
            .build();

        // Total supply is 100 ether. Min approval is 50 ether.
        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        // Alice votes yes with 10 ether. Not enough.
        _vote(alice, IMajorityVoting.VoteOption.Yes, 10 ether);

        vm.warp(block.timestamp + ltvPlugin.proposalDuration() + 1);

        assertFalse(ltvPlugin.isMinApprovalReached(proposalId));
        assertFalse(ltvPlugin.hasSucceeded(proposalId));
        assertFalse(ltvPlugin.canExecute(proposalId));
    }

    function test_GivenTheMinimumApprovalTallyWasAchieved()
        external
        whenCallingTheProposalGetters
        givenItDidNotPassAfterEndDate
    {
        // It isMinApprovalReached() should return true
        (dao, ltvPlugin, lockManager, lockableToken) = new DaoBuilder().withVotingPlugin().withMinApprovalRatio(100_000)
            .withMinParticipationRatio(100_000).withSupportThresholdRatio(500_000).withTokenHolder(alice, 10 ether)
            .withTokenHolder(bob, 90 ether).withProposer(alice).build();
        dao.grant(address(ltvPlugin), alice, ltvPlugin.EXECUTE_PROPOSAL_PERMISSION_ID());

        // Total supply is 100 ether. Min approval is 10 ether. Min participation is 10 ether.
        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        // Alice votes yes with 10 ether. Enough for all conditions.
        _vote(alice, IMajorityVoting.VoteOption.Yes, 10 ether);

        vm.warp(block.timestamp + ltvPlugin.proposalDuration() + 1);

        assertTrue(ltvPlugin.isMinApprovalReached(proposalId));
        assertTrue(ltvPlugin.isMinVotingPowerReached(proposalId));
        assertTrue(ltvPlugin.isSupportThresholdReached(proposalId));
        assertTrue(ltvPlugin.hasSucceeded(proposalId));
        assertTrue(ltvPlugin.canExecute(proposalId));
    }

    modifier givenItHasPassedAfterEndDate() {
        _;
    }

    function test_GivenItHasPassedAfterEndDate() external whenCallingTheProposalGetters givenItHasPassedAfterEndDate {
        (dao, ltvPlugin, lockManager, lockableToken) = new DaoBuilder().withVotingPlugin().withMinApprovalRatio(100_000)
            .withMinParticipationRatio(100_000).withSupportThresholdRatio(500_000).withTokenHolder(alice, 10 ether)
            .withTokenHolder(bob, 90 ether).withProposer(alice).build();
        dao.grant(address(ltvPlugin), alice, ltvPlugin.EXECUTE_PROPOSAL_PERMISSION_ID());

        vm.deal(address(dao), 1 ether);
        actions.push(Action({to: david, value: 1 ether, data: bytes("")}));

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _vote(alice, IMajorityVoting.VoteOption.Yes, 10 ether);
        uint64 creationTimestamp = uint64(block.timestamp);

        vm.warp(block.timestamp + ltvPlugin.proposalDuration() + 1);

        // It getProposal() returns the right values
        (
            bool open,
            bool executed,
            MajorityVotingBase.ProposalParameters memory params,
            MajorityVotingBase.Tally memory tally,
            Action[] memory pActions,
            ,
        ) = ltvPlugin.getProposal(proposalId);
        assertFalse(open);
        assertFalse(executed);
        assertEq(params.startDate, creationTimestamp);
        assertEq(tally.yes, 10 ether);
        assertEq(pActions.length, 1);

        // It isProposalOpen() returns false
        assertFalse(ltvPlugin.isProposalOpen(proposalId));

        // It hasSucceeded() should return true
        assertTrue(ltvPlugin.hasSucceeded(proposalId));

        // It isSupportThresholdReachedEarly() should return false (because total supply is large)
        assertFalse(ltvPlugin.isSupportThresholdReachedEarly(proposalId));

        // It isSupportThresholdReached() should return true
        assertTrue(ltvPlugin.isSupportThresholdReached(proposalId));

        // It isMinVotingPowerReached() should return true
        assertTrue(ltvPlugin.isMinVotingPowerReached(proposalId));

        // It isMinApprovalReached() should return true
        assertTrue(ltvPlugin.isMinApprovalReached(proposalId));

        // It usedVotingPower() should return the appropriate values
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), 10 ether);
        assertEq(ltvPlugin.usedVotingPower(proposalId, bob), 0);
    }

    function test_GivenTheProposalHasNotBeenExecuted()
        external
        whenCallingTheProposalGetters
        givenItHasPassedAfterEndDate
    {
        (dao, ltvPlugin, lockManager, lockableToken) = new DaoBuilder().withVotingPlugin().withMinApprovalRatio(100_000)
            .withMinParticipationRatio(100_000).withSupportThresholdRatio(500_000).withTokenHolder(alice, 10 ether)
            .withTokenHolder(bob, 90 ether).withProposer(alice).build();
        dao.grant(address(ltvPlugin), alice, ltvPlugin.EXECUTE_PROPOSAL_PERMISSION_ID());

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));
        _vote(alice, IMajorityVoting.VoteOption.Yes, 10 ether);
        vm.warp(block.timestamp + ltvPlugin.proposalDuration() + 1);

        // It canExecute() should return true
        assertTrue(ltvPlugin.canExecute(proposalId));
    }

    function test_GivenTheProposalHasBeenExecuted()
        external
        whenCallingTheProposalGetters
        givenItHasPassedAfterEndDate
    {
        (dao, ltvPlugin, lockManager, lockableToken) = new DaoBuilder().withVotingPlugin().withMinApprovalRatio(100_000)
            .withMinParticipationRatio(100_000).withSupportThresholdRatio(500_000).withTokenHolder(alice, 10 ether)
            .withTokenHolder(bob, 90 ether).withProposer(alice).build();
        dao.grant(address(ltvPlugin), alice, ltvPlugin.EXECUTE_PROPOSAL_PERMISSION_ID());

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));
        _vote(alice, IMajorityVoting.VoteOption.Yes, 10 ether);
        vm.warp(block.timestamp + ltvPlugin.proposalDuration() + 1);

        vm.prank(alice);
        ltvPlugin.execute(proposalId);

        // It canExecute() should return false
        assertFalse(ltvPlugin.canExecute(proposalId));
    }

    modifier givenItHasPassedEarly() {
        _;
    }

    function test_GivenItHasPassedEarly() external whenCallingTheProposalGetters givenItHasPassedEarly {
        (dao, ltvPlugin, lockManager, lockableToken) = new DaoBuilder().withEarlyExecution().withVotingPlugin()
            .withMinApprovalRatio(500_000).withMinParticipationRatio(500_000).withSupportThresholdRatio(500_000)
            .withTokenHolder(alice, 51 ether).withTokenHolder(bob, 49 ether).withProposer(alice).build();
        dao.grant(address(ltvPlugin), alice, ltvPlugin.EXECUTE_PROPOSAL_PERMISSION_ID());

        vm.deal(address(dao), 1 ether);
        actions.push(Action({to: david, value: 1 ether, data: bytes("")}));

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        _vote(alice, IMajorityVoting.VoteOption.Yes, 51 ether);
        uint64 creationTimestamp = uint64(block.timestamp);

        // It getProposal() returns the right values
        (
            bool open,
            bool executed,
            MajorityVotingBase.ProposalParameters memory params,
            MajorityVotingBase.Tally memory tally,
            Action[] memory pActions,
            ,
        ) = ltvPlugin.getProposal(proposalId);
        assertTrue(open);
        assertFalse(executed);
        assertEq(params.startDate, creationTimestamp);
        assertEq(tally.yes, 51 ether);
        assertEq(pActions.length, 1);

        // It isProposalOpen() returns true
        assertTrue(ltvPlugin.isProposalOpen(proposalId));

        // It hasSucceeded() should return true
        assertTrue(ltvPlugin.hasSucceeded(proposalId));

        // It isSupportThresholdReachedEarly() should return true
        assertTrue(ltvPlugin.isSupportThresholdReachedEarly(proposalId));

        // It isSupportThresholdReached() should return true
        assertTrue(ltvPlugin.isSupportThresholdReached(proposalId));

        // It isMinVotingPowerReached() should return true
        assertTrue(ltvPlugin.isMinVotingPowerReached(proposalId));

        // It isMinApprovalReached() should return true
        assertTrue(ltvPlugin.isMinApprovalReached(proposalId));

        // It usedVotingPower() should return the appropriate values
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), 51 ether);
        assertEq(ltvPlugin.usedVotingPower(proposalId, bob), 0);
    }

    function test_GivenTheProposalHasNotBeenExecuted2() external whenCallingTheProposalGetters givenItHasPassedEarly {
        (dao, ltvPlugin, lockManager, lockableToken) = new DaoBuilder().withEarlyExecution().withVotingPlugin()
            .withMinApprovalRatio(500_000).withMinParticipationRatio(500_000).withSupportThresholdRatio(500_000)
            .withTokenHolder(alice, 51 ether).withTokenHolder(bob, 49 ether).withProposer(alice).build();
        dao.grant(address(ltvPlugin), alice, ltvPlugin.EXECUTE_PROPOSAL_PERMISSION_ID());

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));
        _vote(alice, IMajorityVoting.VoteOption.Yes, 51 ether);

        // It canExecute() should return true
        assertTrue(ltvPlugin.canExecute(proposalId));
    }

    function test_GivenTheProposalHasBeenExecuted2() external whenCallingTheProposalGetters givenItHasPassedEarly {
        (dao, ltvPlugin, lockManager, lockableToken) = new DaoBuilder().withEarlyExecution().withVotingPlugin()
            .withMinApprovalRatio(500_000).withMinParticipationRatio(500_000).withSupportThresholdRatio(500_000)
            .withTokenHolder(alice, 51 ether).withTokenHolder(bob, 49 ether).withProposer(alice).build();
        dao.grant(address(ltvPlugin), alice, ltvPlugin.EXECUTE_PROPOSAL_PERMISSION_ID());

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));
        _vote(alice, IMajorityVoting.VoteOption.Yes, 51 ether);

        vm.prank(alice);
        ltvPlugin.execute(proposalId);

        // It canExecute() should return false
        assertFalse(ltvPlugin.canExecute(proposalId));
    }

    modifier whenCallingCanExecuteAndHasSucceeded() {
        _;
    }

    modifier givenTheProposalExists() {
        _;
    }

    modifier givenTheProposalIsNotExecuted() {
        _;
    }

    modifier givenMinVotingPowerIsReached() {
        _;
    }

    modifier givenMinApprovalIsReached() {
        _;
    }

    modifier givenIsSupportThresholdReachedEarlyWasReachedBeforeEndDate() {
        _;
    }

    function test_GivenTheProposalAllowsEarlyExecution()
        external
        whenCallingCanExecuteAndHasSucceeded
        givenTheProposalExists
        givenTheProposalIsNotExecuted
        givenMinVotingPowerIsReached
        givenMinApprovalIsReached
        givenIsSupportThresholdReachedEarlyWasReachedBeforeEndDate
    {
        (dao, ltvPlugin, lockManager, lockableToken) = new DaoBuilder().withEarlyExecution().withVotingPlugin()
            .withMinApprovalRatio(500_000).withMinParticipationRatio(500_000).withSupportThresholdRatio(500_000)
            .withTokenHolder(alice, 51 ether).withTokenHolder(bob, 49 ether).withProposer(alice).build();
        dao.grant(address(ltvPlugin), alice, ltvPlugin.EXECUTE_PROPOSAL_PERMISSION_ID());

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));
        _vote(alice, IMajorityVoting.VoteOption.Yes, 51 ether);

        // It canExecute() should return true
        assertTrue(ltvPlugin.canExecute(proposalId));
        // It hasSucceeded() should return true
        assertTrue(ltvPlugin.hasSucceeded(proposalId));
    }

    function test_GivenTheProposalDoesNotAllowEarlyExecution()
        external
        whenCallingCanExecuteAndHasSucceeded
        givenTheProposalExists
        givenTheProposalIsNotExecuted
        givenMinVotingPowerIsReached
        givenMinApprovalIsReached
        givenIsSupportThresholdReachedEarlyWasReachedBeforeEndDate
    {
        // 1
        (dao, ltvPlugin, lockManager, lockableToken) = new DaoBuilder().withStandardVoting().withVotingPlugin()
            .withMinApprovalRatio(500_000).withMinParticipationRatio(500_000).withSupportThresholdRatio(500_000)
            .withTokenHolder(alice, 51 ether).withTokenHolder(bob, 49 ether).withProposer(alice) // No early execution
            .build();
        dao.grant(address(ltvPlugin), alice, ltvPlugin.EXECUTE_PROPOSAL_PERMISSION_ID());

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));
        _vote(alice, IMajorityVoting.VoteOption.Yes, 51 ether);

        // It canExecute() should return false
        assertFalse(ltvPlugin.canExecute(proposalId));
        // It hasSucceeded() should return false
        assertFalse(ltvPlugin.hasSucceeded(proposalId));

        vm.warp(block.timestamp + 10 days);

        // It canExecute() should return true when ended
        assertTrue(ltvPlugin.canExecute(proposalId));
        // It hasSucceeded() should return true when ended
        assertTrue(ltvPlugin.hasSucceeded(proposalId));

        // 2
        (dao, ltvPlugin, lockManager, lockableToken) = new DaoBuilder().withVoteReplacement().withVotingPlugin()
            .withMinApprovalRatio(500_000).withMinParticipationRatio(500_000).withSupportThresholdRatio(500_000)
            .withTokenHolder(alice, 51 ether).withTokenHolder(bob, 49 ether).withProposer(alice) // No early execution
            .build();
        dao.grant(address(ltvPlugin), alice, ltvPlugin.EXECUTE_PROPOSAL_PERMISSION_ID());

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));
        _vote(alice, IMajorityVoting.VoteOption.Yes, 51 ether);

        // It canExecute() should return false
        assertFalse(ltvPlugin.canExecute(proposalId));
        // It hasSucceeded() should return false
        assertFalse(ltvPlugin.hasSucceeded(proposalId));

        vm.warp(block.timestamp + 10 days);

        // It canExecute() should return true when ended
        assertTrue(ltvPlugin.canExecute(proposalId));
        // It hasSucceeded() should return true when ended
        assertTrue(ltvPlugin.hasSucceeded(proposalId));
    }

    function test_GivenIsSupportThresholdReachedIsReached()
        external
        whenCallingCanExecuteAndHasSucceeded
        givenTheProposalExists
        givenTheProposalIsNotExecuted
        givenMinVotingPowerIsReached
        givenMinApprovalIsReached
    {
        (dao, ltvPlugin, lockManager, lockableToken) = new DaoBuilder().withStandardVoting().withVotingPlugin()
            .withMinApprovalRatio(10_000).withMinParticipationRatio(10_000).withSupportThresholdRatio(500_000)
            .withTokenHolder(alice, 10 ether).withTokenHolder(bob, 90 ether).withProposer(alice).build();
        dao.grant(address(ltvPlugin), alice, ltvPlugin.EXECUTE_PROPOSAL_PERMISSION_ID());

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));
        _vote(alice, IMajorityVoting.VoteOption.Yes, 10 ether);

        // It canExecute() should return false before endDate
        assertFalse(ltvPlugin.canExecute(proposalId));
        // It hasSucceeded() should return false before endDate
        assertFalse(ltvPlugin.hasSucceeded(proposalId));

        vm.warp(block.timestamp + ltvPlugin.proposalDuration() + 1);

        // It canExecute() should return true after endDate
        assertTrue(ltvPlugin.canExecute(proposalId));
        // It hasSucceeded() should return true after endDate
        assertTrue(ltvPlugin.hasSucceeded(proposalId));
    }

    function test_GivenIsSupportThresholdReachedIsNotReached()
        external
        whenCallingCanExecuteAndHasSucceeded
        givenTheProposalExists
        givenTheProposalIsNotExecuted
        givenMinVotingPowerIsReached
        givenMinApprovalIsReached
    {
        (dao, ltvPlugin, lockManager, lockableToken) = new DaoBuilder().withStandardVoting().withVotingPlugin()
            .withMinApprovalRatio(10_000).withMinParticipationRatio(10_000).withSupportThresholdRatio(500_000)
            .withTokenHolder(alice, 10 ether).withTokenHolder(bob, 10 ether).withProposer(alice).build();
        dao.grant(address(ltvPlugin), alice, ltvPlugin.EXECUTE_PROPOSAL_PERMISSION_ID());

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));
        _vote(alice, IMajorityVoting.VoteOption.Yes, 10 ether);
        _vote(bob, IMajorityVoting.VoteOption.No, 10 ether); // Tie, so support threshold not reached

        vm.warp(block.timestamp + ltvPlugin.proposalDuration() + 1);

        // It canExecute() should return false
        assertFalse(ltvPlugin.canExecute(proposalId));
        // It hasSucceeded() should return false
        assertFalse(ltvPlugin.hasSucceeded(proposalId));
    }

    function test_GivenMinApprovalIsNotReached()
        external
        whenCallingCanExecuteAndHasSucceeded
        givenTheProposalExists
        givenTheProposalIsNotExecuted
        givenMinVotingPowerIsReached
    {
        (dao, ltvPlugin, lockManager, lockableToken) = new DaoBuilder().withStandardVoting().withVotingPlugin()
            .withMinApprovalRatio(200_000).withMinParticipationRatio(10_000).withSupportThresholdRatio(500_000)
            .withTokenHolder(alice, 10 ether).withTokenHolder(bob, 90 ether).withProposer(alice).build();
        dao.grant(address(ltvPlugin), alice, ltvPlugin.EXECUTE_PROPOSAL_PERMISSION_ID());

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));
        _vote(alice, IMajorityVoting.VoteOption.Yes, 10 ether); // 10% approval, not enough

        vm.warp(block.timestamp + ltvPlugin.proposalDuration() + 1);

        // It canExecute() should return false
        assertFalse(ltvPlugin.canExecute(proposalId));
        // It hasSucceeded() should return false
        assertFalse(ltvPlugin.hasSucceeded(proposalId));
    }

    function test_GivenMinVotingPowerIsNotReached()
        external
        whenCallingCanExecuteAndHasSucceeded
        givenTheProposalExists
        givenTheProposalIsNotExecuted
    {
        (dao, ltvPlugin, lockManager, lockableToken) = new DaoBuilder().withStandardVoting().withVotingPlugin()
            .withMinApprovalRatio(10_000).withMinParticipationRatio(200_000).withSupportThresholdRatio(500_000)
            .withTokenHolder(alice, 10 ether).withTokenHolder(bob, 90 ether).withProposer(alice).build();
        dao.grant(address(ltvPlugin), alice, ltvPlugin.EXECUTE_PROPOSAL_PERMISSION_ID());

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));
        _vote(alice, IMajorityVoting.VoteOption.Yes, 10 ether); // 10% participation, not enough

        vm.warp(block.timestamp + ltvPlugin.proposalDuration() + 1);

        // It canExecute() should return false
        assertFalse(ltvPlugin.canExecute(proposalId));
        // It hasSucceeded() should return false
        assertFalse(ltvPlugin.hasSucceeded(proposalId));
    }

    function test_GivenTheProposalIsExecuted() external whenCallingCanExecuteAndHasSucceeded givenTheProposalExists {
        (dao, ltvPlugin, lockManager, lockableToken) = new DaoBuilder().withStandardVoting().withVotingPlugin()
            .withMinApprovalRatio(10_000).withMinParticipationRatio(10_000).withSupportThresholdRatio(500_000)
            .withTokenHolder(alice, 10 ether).withTokenHolder(bob, 90 ether).withProposer(alice).build();
        dao.grant(address(ltvPlugin), alice, ltvPlugin.EXECUTE_PROPOSAL_PERMISSION_ID());

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));
        _vote(alice, IMajorityVoting.VoteOption.Yes, 10 ether);

        vm.warp(block.timestamp + ltvPlugin.proposalDuration() + 1);
        vm.prank(alice);
        ltvPlugin.execute(proposalId);

        // It canExecute() should return false
        assertFalse(ltvPlugin.canExecute(proposalId));
        // It hasSucceeded() should return true
        assertTrue(ltvPlugin.hasSucceeded(proposalId));
    }

    function test_GivenTheProposalDoesNotExist() external whenCallingCanExecuteAndHasSucceeded {
        // It canExecute() should revert
        vm.expectRevert(abi.encodeWithSelector(NonexistentProposal.selector, 999));
        ltvPlugin.canExecute(999);

        // It hasSucceeded() should revert
        vm.expectRevert(abi.encodeWithSelector(NonexistentProposal.selector, 999));
        ltvPlugin.hasSucceeded(999);
    }

    modifier whenCallingExecute() {
        _;
    }

    function test_RevertGiven_TheCallerNoPermissionToCallExecute() external whenCallingExecute {
        (dao, ltvPlugin, lockManager, lockableToken) = new DaoBuilder().withStandardVoting().withVotingPlugin()
            .withMinApprovalRatio(10_000).withMinParticipationRatio(10_000).withSupportThresholdRatio(500_000)
            .withTokenHolder(alice, 10 ether).withProposer(alice).build();

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));
        _vote(alice, IMajorityVoting.VoteOption.Yes, 10 ether);
        vm.warp(block.timestamp + ltvPlugin.proposalDuration() + 1);

        // It should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(ltvPlugin),
                randomWallet,
                ltvPlugin.EXECUTE_PROPOSAL_PERMISSION_ID()
            )
        );
        vm.prank(randomWallet);
        ltvPlugin.execute(proposalId);
    }

    modifier givenTheCallerHasPermissionToCallExecute2() {
        _;
    }

    function test_RevertGiven_CanExecuteReturnsFalse()
        external
        whenCallingExecute
        givenTheCallerHasPermissionToCallExecute2
    {
        dao.grant(address(ltvPlugin), alice, ltvPlugin.EXECUTE_PROPOSAL_PERMISSION_ID());

        // It should revert
        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));
        // Proposal is not passable yet
        assertFalse(ltvPlugin.canExecute(proposalId));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MajorityVotingBase.ProposalExecutionForbidden.selector, proposalId));
        ltvPlugin.execute(proposalId);
    }

    function test_GivenCanExecuteReturnsTrue() external whenCallingExecute givenTheCallerHasPermissionToCallExecute2 {
        // It should mark the proposal as executed
        // It should make the target execute the proposal actions
        // It should emit an event
        // It should call proposalEnded on the LockManager

        dao.grant(address(ltvPlugin), address(lockManager), ltvPlugin.EXECUTE_PROPOSAL_PERMISSION_ID());

        vm.deal(address(dao), 1 ether);
        actions.push(Action({to: david, value: 1 ether, data: bytes("")}));

        vm.prank(alice);
        proposalId = ltvPlugin.createProposal("ipfs://", actions, 0, 0, bytes(""));
        assertEq(lockManager.knownProposalIdAt(0), proposalId);

        assertFalse(ltvPlugin.canExecute(proposalId));

        _vote(alice, IMajorityVoting.VoteOption.Yes, 1 ether);
        _vote(bob, IMajorityVoting.VoteOption.Yes, 10 ether);
        _vote(carol, IMajorityVoting.VoteOption.Yes, 10 ether);

        vm.warp(block.timestamp + 10 days);
        vm.expectEmit(true, false, false, true);
        emit ProposalExecuted(proposalId);

        assertEq(david.balance, 0);

        vm.prank(address(lockManager));
        ltvPlugin.execute(proposalId);

        // It should mark the proposal as executed
        (, bool executed,,,,,) = ltvPlugin.getProposal(proposalId);
        assertTrue(executed);

        // It should make the target execute the proposal actions
        assertEq(david.balance, 1 ether);

        // It should call proposalEnded on the LockManager
        assertEq(lockManager.knownProposalIdsLength(), 0);
    }

    function test_WhenCallingIsMember() external {
        // It Should return true when the sender has positive balance or locked tokens

        assertTrue(ltvPlugin.isMember(alice)); // has balance
        _lock(bob, 1 ether);
        assertTrue(ltvPlugin.isMember(bob)); // has locked tokens

        // It Should return false otherwise
        assertFalse(ltvPlugin.isMember(randomWallet));
    }

    function test_WhenCallingCustomProposalParamsABI() external view {
        // It Should return the right value
        assertEq(ltvPlugin.customProposalParamsABI(), "(uint256 allowFailureMap)");
    }

    function test_WhenCallingCurrentTokenSupply() external {
        // It Should return the right value
        assertEq(ltvPlugin.currentTokenSupply(), lockableToken.totalSupply());

        TestToken(address(lockableToken)).mint(alice, 50 ether);
        assertEq(ltvPlugin.currentTokenSupply(), lockableToken.totalSupply());
    }

    function test_WhenCallingSupportThresholdRatio() external view {
        // It Should return the right value
        assertEq(ltvPlugin.supportThresholdRatio(), ltvPlugin.getVotingSettings().supportThresholdRatio);
    }

    function test_WhenCallingMinParticipationRatio() external view {
        // It Should return the right value
        assertEq(ltvPlugin.minParticipationRatio(), ltvPlugin.getVotingSettings().minParticipationRatio);
    }

    function test_WhenCallingProposalDuration() external view {
        // It Should return the right value
        assertEq(ltvPlugin.proposalDuration(), ltvPlugin.getVotingSettings().proposalDuration);
    }

    function test_WhenCallingMinProposerVotingPower() external view {
        // It Should return the right value
        assertEq(ltvPlugin.minProposerVotingPower(), ltvPlugin.getVotingSettings().minProposerVotingPower);
    }

    function test_WhenCallingMinApprovalRatio() external view {
        // It Should return the right value
        assertEq(ltvPlugin.minApprovalRatio(), ltvPlugin.getVotingSettings().minApprovalRatio);
    }

    function test_WhenCallingVotingMode() external view {
        // It Should return the right value
        assertEq(uint8(ltvPlugin.votingMode()), uint8(ltvPlugin.getVotingSettings().votingMode));
    }

    function test_WhenCallingCurrentTokenSupply2() external {
        // It Should return the right value
        assertEq(ltvPlugin.currentTokenSupply(), lockableToken.totalSupply());

        TestToken(address(lockableToken)).mint(alice, 10 ether);

        assertEq(ltvPlugin.currentTokenSupply(), lockableToken.totalSupply());
    }

    function test_WhenCallingLockManager() external view {
        // It Should return the right address
        assertEq(address(ltvPlugin.lockManager()), address(lockManager));
    }

    function test_WhenCallingToken() external view {
        // It Should return the right address
        assertEq(address(ltvPlugin.token()), address(lockableToken));
    }

    // HELPERS

    function _lock(address who, uint256 amount) internal {
        vm.startPrank(who);
        lockableToken.approve(address(lockManager), amount);
        lockManager.lock();
        vm.stopPrank();
    }

    function _vote(address who, IMajorityVoting.VoteOption option, uint256 amount) internal {
        _lock(who, amount);
        vm.prank(who);
        lockManager.vote(proposalId, option);
    }
}
