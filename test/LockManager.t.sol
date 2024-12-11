// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {AragonTest} from "./util/AragonTest.sol";

contract LockManagerTest is AragonTest {
    modifier whenCallingUpdateSettings() {
        _;
    }

    function test_RevertWhen_UpdateSettingsWithoutThePermission()
        external
        whenCallingUpdateSettings
    {
        // It should revert
        vm.skip(true);
    }

    function test_WhenUpdateSettingsWithThePermission()
        external
        whenCallingUpdateSettings
    {
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

    function test_WhenLockingTokens() external {
        // It Should allow any token holder to lock
        // It Should use the full allowance
        vm.skip(true);
    }

    modifier whenLockingAndOrVoting() {
        _;
    }

    function test_GivenInvalidPlugin() external whenLockingAndOrVoting {
        // It Locking and voting should revert
        // It Voting should revert
        vm.skip(true);
    }

    modifier givenValidLockToVotePlugin() {
        _;
    }

    function test_RevertWhen_NoTokenBalance()
        external
        whenLockingAndOrVoting
        givenValidLockToVotePlugin
    {
        // It Should revert
        vm.skip(true);
    }

    function test_RevertWhen_NoTokenAllowance()
        external
        whenLockingAndOrVoting
        givenValidLockToVotePlugin
    {
        // It Should revert
        vm.skip(true);
    }

    function test_WhenInvalidOrInactiveProposal()
        external
        whenLockingAndOrVoting
        givenValidLockToVotePlugin
    {
        // It Locking and voting should revert
        // It Voting should revert
        vm.skip(true);
    }

    modifier whenValidProposal() {
        _;
    }

    function test_WhenAlreadyVoted()
        external
        whenLockingAndOrVoting
        givenValidLockToVotePlugin
        whenValidProposal
    {
        // It Should update the voting balance and the proposal tally
        // It Should increase the voting power by the full allowance
        vm.skip(true);
    }

    function test_WhenNotVotedYet()
        external
        whenLockingAndOrVoting
        givenValidLockToVotePlugin
        whenValidProposal
    {
        // It Should allow any token holder to vote
        // It Should use the full allowance to vote
        vm.skip(true);
    }

    function test_WhenCallingGetTokens()
        external
        whenLockingAndOrVoting
        givenValidLockToVotePlugin
        whenValidProposal
    {
        // It Should return the token addresses where votes have been cast
        vm.skip(true);
    }

    function test_GivenCallingGetLocks()
        external
        whenLockingAndOrVoting
        givenValidLockToVotePlugin
        whenValidProposal
    {
        // It Should return the active proposals with 1+ locks
        vm.skip(true);
    }

    modifier givenStrictModeIsSet() {
        _;
    }

    modifier givenDidntLockAnythingStrict() {
        _;
    }

    function test_WhenTryingToUnlock1Strict()
        external
        givenStrictModeIsSet
        givenDidntLockAnythingStrict
    {
        // It Should do nothing
        vm.skip(true);
    }

    modifier givenLockedButDidntVoteAnywhereStrict() {
        _;
    }

    function test_WhenTryingToUnlock2Strict()
        external
        givenStrictModeIsSet
        givenLockedButDidntVoteAnywhereStrict
    {
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

    function test_WhenTryingToUnlock1Flexible()
        external
        givenFlexibleModeIsSet
        givenDidntLockAnythingFlexible
    {
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

    modifier givenBeforeReleaseLockIsCalled() {
        _;
    }

    modifier givenProposalVoterCallsUnlockNoReleaseLock() {
        _;
    }

    function test_WhenExecutedProposal()
        external
        givenAProposalHasEnded
        givenBeforeReleaseLockIsCalled
        givenProposalVoterCallsUnlockNoReleaseLock
    {
        // It Should allow voters from that proposal to unlock right away
        vm.skip(true);
    }

    function test_WhenDefeatedProposal()
        external
        givenAProposalHasEnded
        givenBeforeReleaseLockIsCalled
        givenProposalVoterCallsUnlockNoReleaseLock
    {
        // It Should allow voters from that proposal to unlock right away
        vm.skip(true);
    }

    function test_RevertWhen_ActiveProposal()
        external
        givenAProposalHasEnded
        givenBeforeReleaseLockIsCalled
        givenProposalVoterCallsUnlockNoReleaseLock
    {
        // It Should revert
        vm.skip(true);
    }

    modifier whenAfterReleaseLockIsCalled() {
        _;
    }

    function test_WhenProposalVoterCallsUnlockReleased()
        external
        givenAProposalHasEnded
        whenAfterReleaseLockIsCalled
    {
        // It Should allow voters from that proposal to unlock right away
        // It Should revert on voters who have any other unreleased proposal votes
        vm.skip(true);
    }

    function test_GivenPermissions() external {
        // It Should revert if releaseLock is called by an incompatible plugin
        // It Should revert if updateSettings is called by an address without the permission
        vm.skip(true);
    }
}
