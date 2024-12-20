// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {AragonTest} from "./util/AragonTest.sol";
import {DaoBuilder} from "./util/DaoBuilder.sol";
import {DAO, IDAO} from "@aragon/osx/src/core/dao/DAO.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {createProxyAndCall} from "../src/util/proxy.sol";
import {IProposal} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {LockToVotePlugin} from "../src/LockToVotePlugin.sol";
import {LockManagerSettings, UnlockMode} from "../src/interfaces/ILockManager.sol";
import {LockManager} from "../src/LockManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LockManagerTest is AragonTest {
    DaoBuilder builder;
    DAO dao;
    LockToVotePlugin plugin;
    LockManager lockManager;
    IERC20 lockableToken;
    IERC20 underlyingToken;
    uint256 proposalId;

    address immutable LOCK_TO_VOTE_BASE = address(new LockToVotePlugin());
    address immutable LOCK_MANAGER_BASE = address(
        new LockManager(
            IDAO(address(0)), LockManagerSettings(UnlockMode.STRICT), IERC20(address(0)), IERC20(address(0))
        )
    );

    error InvalidUnlockMode();
    error NoBalance();

    function setUp() public {
        vm.startPrank(alice);
        vm.warp(1 days);
        vm.roll(100);

        builder = new DaoBuilder();
        (dao, plugin, lockManager, lockableToken, underlyingToken) = builder.withTokenHolder(alice, 1 ether)
            .withTokenHolder(bob, 10 ether).withTokenHolder(carol, 10 ether).withTokenHolder(david, 15 ether).build();
    }

    modifier givenDeployingTheContract() {
        _;
    }

    function test_RevertWhen_ConstructorHasInvalidUnlockMode() external givenDeployingTheContract {
        // It Should revert
        vm.expectRevert();
        new LockManager(
            IDAO(address(0)), LockManagerSettings(UnlockMode(uint8(2))), IERC20(address(0)), IERC20(address(0))
        );

        vm.expectRevert();
        new LockManager(
            IDAO(address(0)), LockManagerSettings(UnlockMode(uint8(0))), IERC20(address(0)), IERC20(address(0))
        );

        // OK
        new LockManager(
            IDAO(address(0)), LockManagerSettings(UnlockMode.STRICT), IERC20(address(0)), IERC20(address(0))
        );
        new LockManager(IDAO(address(0)), LockManagerSettings(UnlockMode.EARLY), IERC20(address(0)), IERC20(address(0)));
    }

    function test_WhenConstructorWithValidParams() external givenDeployingTheContract {
        // It Registers the DAO address
        // It Stores the given settings
        // It Stores the given token addresses

        // 1
        lockManager = new LockManager(
            IDAO(address(1234)), LockManagerSettings(UnlockMode.STRICT), IERC20(address(2345)), IERC20(address(3456))
        );
        assertEq(address(lockManager.dao()), address(1234));
        assertEq(address(lockManager.token()), address(2345));
        assertEq(address(lockManager.underlyingToken()), address(3456));

        // 2
        lockManager = new LockManager(
            IDAO(address(5555)), LockManagerSettings(UnlockMode.EARLY), IERC20(address(6666)), IERC20(address(7777))
        );
        assertEq(address(lockManager.dao()), address(5555));
        assertEq(address(lockManager.token()), address(6666));
        assertEq(address(lockManager.underlyingToken()), address(7777));
    }

    modifier whenCallingSetPluginAddress() {
        _;
    }

    function test_RevertWhen_SetPluginAddressWithoutThePermission() external whenCallingSetPluginAddress {
        // It should revert

        (, LockToVotePlugin plugin2,,,) = builder.build();
        (, LockToVotePlugin plugin3,,,) = builder.build();

        lockManager = new LockManager(dao, LockManagerSettings(UnlockMode.STRICT), lockableToken, underlyingToken);

        // 1
        vm.expectRevert();
        lockManager.setPluginAddress(plugin2);

        // 2
        vm.expectRevert();
        lockManager.setPluginAddress(plugin3);

        // OK

        dao.grant(address(lockManager), alice, lockManager.UPDATE_SETTINGS_PERMISSION_ID());
        lockManager.setPluginAddress(plugin2);

        // OK 2

        lockManager = new LockManager(dao, LockManagerSettings(UnlockMode.STRICT), lockableToken, underlyingToken);
        dao.grant(address(lockManager), alice, lockManager.UPDATE_SETTINGS_PERMISSION_ID());
        lockManager.setPluginAddress(plugin3);
    }

    function test_WhenSetPluginAddressWithThePermission() external whenCallingSetPluginAddress {
        // It should update the address

        (, LockToVotePlugin plugin2,,,) = builder.build();
        (, LockToVotePlugin plugin3,,,) = builder.build();

        lockManager = new LockManager(dao, LockManagerSettings(UnlockMode.STRICT), lockableToken, underlyingToken);
        dao.grant(address(lockManager), alice, lockManager.UPDATE_SETTINGS_PERMISSION_ID());
        lockManager.setPluginAddress(plugin2);
        assertEq(address(lockManager.plugin()), address(plugin2));

        // OK 2

        lockManager = new LockManager(dao, LockManagerSettings(UnlockMode.STRICT), lockableToken, underlyingToken);
        dao.grant(address(lockManager), alice, lockManager.UPDATE_SETTINGS_PERMISSION_ID());
        lockManager.setPluginAddress(plugin3);
        assertEq(address(lockManager.plugin()), address(plugin3));
    }

    modifier givenNoLockedTokens() {
        Action[] memory _actions = new Action[](0);
        proposalId = plugin.createProposal(bytes(""), _actions, 0, 0, bytes(""));

        _;
    }

    modifier givenNoTokenAllowanceNoLocked() {
        _;
    }

    function test_RevertWhen_CallingLock1() external givenNoLockedTokens givenNoTokenAllowanceNoLocked {
        // It Should revert

        // 1
        vm.startPrank(randomWallet);
        assertEq(lockableToken.balanceOf(randomWallet), 0);
        assertEq(lockableToken.allowance(randomWallet, address(lockManager)), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.lock();

        // 2
        vm.startPrank(address(0x1234));
        assertEq(lockableToken.balanceOf(address(0x1234)), 0);
        assertEq(lockableToken.allowance(address(0x1234), address(lockManager)), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.lock();

        // OK
        vm.startPrank(alice);
        assertEq(lockableToken.balanceOf(alice), 1 ether);
        assertEq(lockableToken.allowance(alice, address(lockManager)), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.lock();

        lockableToken.approve(address(lockManager), 0.5 ether);
        lockManager.lock();

        assertEq(lockableToken.balanceOf(alice), 0.5 ether);
        assertEq(lockableToken.allowance(alice, address(lockManager)), 0);

        assertEq(lockableToken.balanceOf(address(lockManager)), 0.5 ether);
    }

    function test_RevertWhen_CallingLockAndVote1() external givenNoLockedTokens givenNoTokenAllowanceNoLocked {
        // It Should revert
        vm.startPrank(randomWallet);
        assertEq(lockableToken.balanceOf(randomWallet), 0);
        assertEq(lockableToken.allowance(randomWallet, address(lockManager)), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.lockAndVote(proposalId);

        vm.startPrank(address(0x1234));
        assertEq(lockableToken.balanceOf(address(0x1234)), 0);
        assertEq(lockableToken.allowance(address(0x1234), address(lockManager)), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.lockAndVote(proposalId);

        // vm.startPrank(alice);
        assertEq(lockableToken.balanceOf(alice), 1 ether);
        assertEq(lockableToken.allowance(alice, address(lockManager)), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.lockAndVote(proposalId);
    }

    function test_RevertWhen_CallingVote1() external givenNoLockedTokens givenNoTokenAllowanceNoLocked {
        // It Should revert
        vm.startPrank(randomWallet);
        assertEq(lockManager.lockedBalances(randomWallet), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.vote(proposalId);

        vm.startPrank(address(0x1234));
        assertEq(lockManager.lockedBalances(address(0x1234)), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.vote(proposalId);

        // vm.startPrank(alice);
        assertEq(lockManager.lockedBalances(alice), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.vote(proposalId);
    }

    modifier givenWithTokenAllowanceNoLocked() {
        lockableToken.approve(address(lockManager), 0.1 ether);
        vm.startPrank(bob);
        lockableToken.approve(address(lockManager), 0.1 ether);
        vm.startPrank(alice);

        _;
    }

    function test_WhenCallingLock2() external givenNoLockedTokens givenWithTokenAllowanceNoLocked {
        // It Should allow any token holder to lock
        // It Should approve with the full token balance

        // vm.startPrank(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);
        uint256 allowance = lockableToken.allowance(alice, address(lockManager));
        lockManager.lock();
        assertEq(lockableToken.balanceOf(alice), initialBalance - allowance);
        assertEq(lockManager.lockedBalances(alice), allowance);
        assertEq(lockableToken.balanceOf(address(lockManager)), allowance);

        vm.startPrank(bob);
        initialBalance = lockableToken.balanceOf(bob);
        allowance = lockableToken.allowance(bob, address(lockManager));
        lockManager.lock();
        assertEq(lockableToken.balanceOf(bob), initialBalance - allowance);
        assertEq(lockManager.lockedBalances(bob), allowance);
        assertEq(lockableToken.balanceOf(address(lockManager)), 0.2 ether);
    }

    function test_WhenCallingLockAndVote2() external givenNoLockedTokens givenWithTokenAllowanceNoLocked {
        // It Should allow any token holder to lock
        // It Should approve with the full token balance
        // It The allocated token balance should have the full new balance

        // vm.startPrank(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);
        uint256 allowance = lockableToken.allowance(alice, address(lockManager));
        lockManager.lockAndVote(proposalId);
        assertEq(lockableToken.balanceOf(alice), initialBalance - allowance);
        assertEq(lockManager.lockedBalances(alice), allowance);
        assertEq(lockableToken.balanceOf(address(lockManager)), allowance);
        assertEq(plugin.usedVotingPower(proposalId, alice), allowance);

        vm.startPrank(bob);
        initialBalance = lockableToken.balanceOf(bob);
        allowance = lockableToken.allowance(bob, address(lockManager));
        lockManager.lockAndVote(proposalId);
        assertEq(lockableToken.balanceOf(bob), initialBalance - allowance);
        assertEq(lockManager.lockedBalances(bob), allowance);
        assertEq(lockableToken.balanceOf(address(lockManager)), 0.2 ether);
        assertEq(plugin.usedVotingPower(proposalId, bob), allowance);
    }

    function test_RevertWhen_CallingVote2() external givenNoLockedTokens givenWithTokenAllowanceNoLocked {
        // It Should revert

        // vm.startPrank(alice);
        assertEq(lockManager.lockedBalances(alice), 0);
        vm.expectRevert(NoBalance.selector);
        lockManager.vote(proposalId);

        vm.startPrank(bob);
        assertEq(lockManager.lockedBalances(bob), 0);
        vm.expectRevert(NoBalance.selector);
        lockManager.vote(proposalId);
    }

    modifier givenLockedTokens() {
        lockableToken.approve(address(lockManager), 0.1 ether);
        lockManager.lock();

        _;
    }

    modifier givenNoTokenAllowanceSomeLocked() {
        _;
    }

    function test_RevertWhen_CallingLock3() external givenLockedTokens givenNoTokenAllowanceSomeLocked {
        // It Should revert

        // 1
        assertEq(lockableToken.allowance(alice, address(lockManager)), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.lock();

        // OK
        lockableToken.approve(address(lockManager), 0.5 ether);
        lockManager.lock();

        assertEq(lockableToken.balanceOf(alice), 0.4 ether);
        assertEq(lockableToken.allowance(alice, address(lockManager)), 0);

        assertEq(lockableToken.balanceOf(address(lockManager)), 0.6 ether);
    }

    function test_RevertWhen_CallingLockAndVote3() external givenLockedTokens givenNoTokenAllowanceSomeLocked {
        // It Should revert

        assertEq(lockableToken.allowance(alice, address(lockManager)), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.lockAndVote(proposalId);

        lockableToken.approve(address(lockManager), 0.5 ether);
        lockManager.lockAndVote(proposalId);

        assertEq(lockableToken.balanceOf(alice), 0.4 ether);
        assertEq(lockableToken.allowance(alice, address(lockManager)), 0);

        assertEq(lockableToken.balanceOf(address(lockManager)), 0.6 ether);
    }

    function test_RevertWhen_CallingVoteSameBalance3() external givenLockedTokens givenNoTokenAllowanceSomeLocked {
        // Prior vote
        lockManager.vote(proposalId);

        // It Should revert

        vm.expectRevert();
        lockManager.vote(proposalId);
    }

    function test_WhenCallingVoteMoreLockedBalance3() external givenLockedTokens givenNoTokenAllowanceSomeLocked {
        // It Should approve with the full token balance

        // vm.startPrank(alice);
        lockManager.vote(proposalId);
        assertEq(plugin.usedVotingPower(proposalId, alice), 0.1 ether);

        // More
        assertEq(lockManager.lockedBalances(alice), 0.1 ether);

        lockableToken.approve(address(lockManager), 0.5 ether);
        lockManager.lock();

        assertEq(lockManager.lockedBalances(alice), 0.6 ether);

        lockManager.vote(proposalId);
        assertEq(plugin.usedVotingPower(proposalId, alice), 0.6 ether);
    }

    modifier givenWithTokenAllowanceSomeLocked() {
        lockableToken.approve(address(lockManager), 0.5 ether);

        _;
    }

    function test_WhenCallingLock4() external givenLockedTokens givenWithTokenAllowanceSomeLocked {
        // It Should allow any token holder to lock
        // It Should approve with the full token balance
        // It Should increase the locked amount

        // vm.startPrank(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);
        uint256 allowance = lockableToken.allowance(alice, address(lockManager));
        lockManager.lock();

        assertEq(lockableToken.balanceOf(alice), initialBalance - allowance);
        assertEq(lockManager.lockedBalances(alice), 0.1 ether + allowance);
        assertEq(lockableToken.balanceOf(address(lockManager)), 0.1 ether + allowance);
    }

    function test_WhenCallingLockAndVoteNoPriorVotes4() external givenLockedTokens givenWithTokenAllowanceSomeLocked {
        // It Should allow any token holder to lock
        // It Should approve with the full token balance
        // It Should increase the locked amount
        // It The allocated token balance should have the full new balance

        // vm.startPrank(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);
        uint256 allowance = lockableToken.allowance(alice, address(lockManager));
        lockManager.lockAndVote(proposalId);
        assertEq(lockableToken.balanceOf(alice), initialBalance - allowance);
        assertEq(lockManager.lockedBalances(alice), 0.1 ether + allowance);
        assertEq(lockableToken.balanceOf(address(lockManager)), 0.1 ether + allowance);
        assertEq(plugin.usedVotingPower(proposalId, alice), 0.1 ether + allowance);
    }

    function test_WhenCallingLockAndVoteWithPriorVotes4()
        external
        givenLockedTokens
        givenWithTokenAllowanceSomeLocked
    {
        lockManager.vote(proposalId);

        // It Should allow any token holder to lock
        // It Should approve with the full token balance
        // It Should increase the locked amount
        // It The allocated token balance should have the full new balance

        // vm.startPrank(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);
        uint256 allowance = lockableToken.allowance(alice, address(lockManager));
        lockManager.lockAndVote(proposalId);
        assertEq(lockableToken.balanceOf(alice), initialBalance - allowance);
        assertEq(lockManager.lockedBalances(alice), 0.1 ether + allowance);
        assertEq(lockableToken.balanceOf(address(lockManager)), 0.1 ether + allowance);
        assertEq(plugin.usedVotingPower(proposalId, alice), 0.1 ether + allowance);
    }

    function test_RevertWhen_CallingVoteSameBalance4() external givenLockedTokens givenWithTokenAllowanceSomeLocked {
        // It Should revert

        // vm.startPrank(alice);
        lockManager.vote(proposalId);
        
        vm.expectRevert();
        lockManager.vote(proposalId);
    }

    function test_WhenCallingVoteMoreLockedBalance4() external givenLockedTokens givenWithTokenAllowanceSomeLocked {
        lockManager.vote(proposalId);

        // It Should approve with the full token balance

        // vm.startPrank(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);
        lockManager.lock();

        assertEq(lockableToken.balanceOf(alice), initialBalance - 0.5 ether);
        assertEq(lockManager.lockedBalances(alice), 0.6 ether);
        lockManager.vote(proposalId);
        assertEq(plugin.usedVotingPower(proposalId, alice), 0.6 ether);
    }

    modifier givenCallingLockOrLockToVote() {
        _;
    }

    function test_GivenInvalidPlugin() external givenCallingLockOrLockToVote {
        // It Locking and voting should revert

        lockManager = new LockManager(dao, LockManagerSettings(UnlockMode.STRICT), lockableToken, underlyingToken);
        dao.grant(address(lockManager), alice, lockManager.UPDATE_SETTINGS_PERMISSION_ID());
        lockManager.setPluginAddress(LockToVotePlugin(address(0x5555)));

        lockableToken.approve(address(lockManager), 0.1 ether);
        
        vm.expectRevert();
        lockManager.lockAndVote(proposalId);

        vm.expectRevert();
        lockManager.vote(proposalId);
    }

    function test_GivenInvalidToken() external givenCallingLockOrLockToVote {
        // It Locking should revert
        // It Locking and voting should revert
        // It Voting should revert

        lockManager =
            new LockManager(dao, LockManagerSettings(UnlockMode.STRICT), IERC20(address(0x1234)), underlyingToken);
        lockableToken.approve(address(lockManager), 0.1 ether);
        vm.expectRevert();
        lockManager.lock();

        vm.expectRevert();
        lockManager.lockAndVote(proposalId);

        vm.expectRevert();
        lockManager.vote(proposalId);
    }

    modifier givenProposalEndedIsCalled() {
        _;
    }

    function test_RevertWhen_TheCallerIsNotThePlugin() external givenProposalEndedIsCalled {
        // It Should revert

        vm.expectRevert();
        lockManager.proposalEnded(proposalId);
        
        vm.startPrank(bob);
        vm.expectRevert();
        lockManager.proposalEnded(proposalId);
    }

    function test_WhenTheCallerIsThePlugin() external givenProposalEndedIsCalled {
        // It Removes the proposal ID from the list of known proposals

        lockableToken.approve(address(lockManager), 0.1 ether);
        lockManager.lockAndVote(proposalId);
        assertEq(lockManager.knownProposalIds(0), proposalId);

        vm.startPrank(address(plugin));
        lockManager.proposalEnded(proposalId);
        assertEq(lockManager.knownProposalIds(0), 0);
    }

    modifier givenStrictModeIsSet() {
        _;
    }

    modifier givenDidntLockAnythingStrict() {
        _;
    }

    function test_WhenTryingToUnlock1Strict() external givenStrictModeIsSet givenDidntLockAnythingStrict {
        // It Should do nothing
        vm.skip(true);
    }

    modifier givenLockedButDidntVoteAnywhereStrict() {
        _;
    }

    function test_WhenTryingToUnlock2Strict() external givenStrictModeIsSet givenLockedButDidntVoteAnywhereStrict {
        // It Should unlock and refund the full amount right away
        vm.skip(true);
    }

    modifier givenLockedButVotedOnEndedOrExecutedProposalsStrict() {
        _;
    }

    function test_WhenTryingToUnlock3Strict()
        external
        givenStrictModeIsSet
        givenLockedButVotedOnEndedOrExecutedProposalsStrict
    {
        // It Should unlock and refund the full amount right away
        vm.skip(true);
    }

    modifier givenLockedAnvVotedOnCurrentlyActiveProposalsStrict() {
        _;
    }

    function test_RevertWhen_TryingToUnlock4Strict()
        external
        givenStrictModeIsSet
        givenLockedAnvVotedOnCurrentlyActiveProposalsStrict
    {
        // It Should revert
        vm.skip(true);
    }

    modifier givenFlexibleModeIsSet() {
        _;
    }

    modifier givenDidntLockAnythingFlexible() {
        _;
    }

    function test_WhenTryingToUnlock1Flexible() external givenFlexibleModeIsSet givenDidntLockAnythingFlexible {
        // It Should do nothing
        vm.skip(true);
    }

    modifier givenLockedButDidntVoteAnywhereFlexible() {
        _;
    }

    function test_WhenTryingToUnlock2Flexible()
        external
        givenFlexibleModeIsSet
        givenLockedButDidntVoteAnywhereFlexible
    {
        // It Should unlock and refund the full amount right away
        vm.skip(true);
    }

    modifier givenLockedButVotedOnEndedOrExecutedProposalsFlexible() {
        _;
    }

    function test_WhenTryingToUnlock3Flexible()
        external
        givenFlexibleModeIsSet
        givenLockedButVotedOnEndedOrExecutedProposalsFlexible
    {
        // It Should unlock and refund the full amount right away
        vm.skip(true);
    }

    modifier givenLockedAnvVotedOnCurrentlyActiveProposalsFlexible() {
        _;
    }

    function test_WhenTryingToUnlock4Flexible()
        external
        givenFlexibleModeIsSet
        givenLockedAnvVotedOnCurrentlyActiveProposalsFlexible
    {
        // It Should deallocate the existing voting power from active proposals
        // It Should unlock and refund the full amount
        vm.skip(true);
    }

    modifier givenAProposalHasEnded() {
        _;
    }

    modifier givenBeforeProposalEndedIsCalled() {
        _;
    }

    modifier givenProposalVoterCallsUnlockNoProposalEnded() {
        _;
    }

    function test_WhenExecutedProposal()
        external
        givenAProposalHasEnded
        givenBeforeProposalEndedIsCalled
        givenProposalVoterCallsUnlockNoProposalEnded
    {
        // It Should allow voters from that proposal to unlock right away
        vm.skip(true);
    }

    function test_WhenDefeatedProposal()
        external
        givenAProposalHasEnded
        givenBeforeProposalEndedIsCalled
        givenProposalVoterCallsUnlockNoProposalEnded
    {
        // It Should allow voters from that proposal to unlock right away
        vm.skip(true);
    }

    function test_RevertWhen_ActiveProposal()
        external
        givenAProposalHasEnded
        givenBeforeProposalEndedIsCalled
        givenProposalVoterCallsUnlockNoProposalEnded
    {
        // It Should revert
        vm.skip(true);
    }

    modifier whenAfterProposalEndedIsCalled() {
        _;
    }

    function test_WhenProposalVoterCallsUnlockReleased()
        external
        givenAProposalHasEnded
        whenAfterProposalEndedIsCalled
    {
        // It Should allow voters from that proposal to unlock right away
        // It Should revert on voters who have any other unreleased proposal votes
        vm.skip(true);
    }

    function test_WhenCallingPlugin() external {
        // It Should return the right address
        vm.skip(true);
    }

    function test_WhenCallingToken() external {
        // It Should return the right address
        vm.skip(true);
    }

    modifier givenNoUnderlyingToken() {
        _;
    }

    function test_WhenCallingUnderlyingTokenEmpty() external givenNoUnderlyingToken {
        // It Should return the token address
        vm.skip(true);
    }

    modifier givenUnderlyingTokenDefined() {
        _;
    }

    function test_WhenCallingUnderlyingTokenSet() external givenUnderlyingTokenDefined {
        // It Should return the right address
        vm.skip(true);
    }

    function test_GivenPermissions() external {
        // It Should revert if proposalEnded is called by an incompatible plugin
        vm.skip(true);
    }
}
