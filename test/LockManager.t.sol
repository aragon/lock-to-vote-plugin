// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {AragonTest} from "./util/AragonTest.sol";
import {DaoBuilder} from "./util/DaoBuilder.sol";
import {DAO, IDAO} from "@aragon/osx/src/core/dao/DAO.sol";
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

    address immutable LOCK_TO_VOTE_BASE = address(new LockToVotePlugin());
    address immutable LOCK_MANAGER_BASE = address(
        new LockManager(
            IDAO(address(0)), LockManagerSettings(UnlockMode.STRICT), IERC20(address(0)), IERC20(address(0))
        )
    );

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
        vm.skip(true);
    }

    function test_WhenConstructorWithValidParams() external givenDeployingTheContract {
        // It Registers the DAO address
        // It Stores the given settings
        // It Stores the given plugin and token addresses
        vm.skip(true);
    }

    modifier whenCallingUpdateSettings() {
        _;
    }

    function test_RevertWhen_UpdateSettingsWithoutThePermission() external whenCallingUpdateSettings {
        // It should revert
        vm.skip(true);
    }

    function test_WhenUpdateSettingsWithThePermission() external whenCallingUpdateSettings {
        // It should update the mode
        vm.skip(true);
    }

    function test_WhenCallingGetSettings() external whenCallingUpdateSettings {
        // It Should return the right value
        vm.skip(true);
    }

    function test_WhenCallingSupportsInterface() external {
        // It does not support the empty interface
        // It supports IERC165Upgradeable
        // It supports ILockManager
        vm.skip(true);
    }

    modifier givenNoLockedTokens() {
        _;
    }

    modifier givenNoTokenAllowanceNoLocked() {
        _;
    }

    function test_RevertWhen_CallingLock1() external givenNoLockedTokens givenNoTokenAllowanceNoLocked {
        // It Should revert
        vm.skip(true);
    }

    function test_RevertWhen_CallingLockAndVote1() external givenNoLockedTokens givenNoTokenAllowanceNoLocked {
        // It Should revert
        vm.skip(true);
    }

    function test_RevertWhen_CallingVote1() external givenNoLockedTokens givenNoTokenAllowanceNoLocked {
        // It Should revert
        vm.skip(true);
    }

    modifier givenWithTokenAllowanceNoLocked() {
        _;
    }

    function test_WhenCallingLock2() external givenNoLockedTokens givenWithTokenAllowanceNoLocked {
        // It Should allow any token holder to lock
        // It Should approve with the full token balance
        vm.skip(true);
    }

    function test_WhenCallingLockAndVote2() external givenNoLockedTokens givenWithTokenAllowanceNoLocked {
        // It Should allow any token holder to lock
        // It Should approve with the full token balance
        // It The allocated token balance should have the full new balance
        vm.skip(true);
    }

    function test_RevertWhen_CallingVote2() external givenNoLockedTokens givenWithTokenAllowanceNoLocked {
        // It Should revert
        vm.skip(true);
    }

    modifier givenLockedTokens() {
        _;
    }

    modifier givenNoTokenAllowanceSomeLocked() {
        _;
    }

    function test_RevertWhen_CallingLock3() external givenLockedTokens givenNoTokenAllowanceSomeLocked {
        // It Should revert
        vm.skip(true);
    }

    function test_RevertWhen_CallingLockAndVote3() external givenLockedTokens givenNoTokenAllowanceSomeLocked {
        // It Should revert
        vm.skip(true);
    }

    function test_RevertWhen_CallingVoteSameBalance3() external givenLockedTokens givenNoTokenAllowanceSomeLocked {
        // It Should revert
        vm.skip(true);
    }

    function test_WhenCallingVoteMoreLockedBalance3() external givenLockedTokens givenNoTokenAllowanceSomeLocked {
        // It Should approve with the full token balance
        vm.skip(true);
    }

    modifier givenWithTokenAllowanceSomeLocked() {
        _;
    }

    function test_WhenCallingLock4() external givenLockedTokens givenWithTokenAllowanceSomeLocked {
        // It Should allow any token holder to lock
        // It Should approve with the full token balance
        // It Should increase the locked amount
        vm.skip(true);
    }

    function test_WhenCallingLockAndVoteNoPriorVotes4() external givenLockedTokens givenWithTokenAllowanceSomeLocked {
        // It Should allow any token holder to lock
        // It Should approve with the full token balance
        // It Should increase the locked amount
        // It The allocated token balance should have the full new balance
        vm.skip(true);
    }

    function test_WhenCallingLockAndVoteWithPriorVotes4()
        external
        givenLockedTokens
        givenWithTokenAllowanceSomeLocked
    {
        // It Should allow any token holder to lock
        // It Should approve with the full token balance
        // It Should increase the locked amount
        // It The allocated token balance should have the full new balance
        vm.skip(true);
    }

    function test_RevertWhen_CallingVoteSameBalance4() external givenLockedTokens givenWithTokenAllowanceSomeLocked {
        // It Should revert
        vm.skip(true);
    }

    function test_WhenCallingVoteMoreLockedBalance4() external givenLockedTokens givenWithTokenAllowanceSomeLocked {
        // It Should approve with the full token balance
        vm.skip(true);
    }

    modifier givenCallingLockOrLockToVote() {
        _;
    }

    function test_GivenInvalidPlugin() external givenCallingLockOrLockToVote {
        // It Locking and voting should revert
        vm.skip(true);
    }

    function test_GivenInvalidToken() external givenCallingLockOrLockToVote {
        // It Locking should revert
        // It Locking and voting should revert
        // It Voting should revert
        vm.skip(true);
    }

    modifier givenProposalEndedIsCalled() {
        _;
    }

    function test_RevertWhen_TheCallerIsNotThePlugin() external givenProposalEndedIsCalled {
        // It Should revert
        vm.skip(true);
    }

    function test_WhenTheCallerIsThePlugin() external givenProposalEndedIsCalled {
        // It Removes the proposal ID from the list of known proposals
        vm.skip(true);
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
