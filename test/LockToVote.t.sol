// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";

contract LockToVoteTest is Test {
    function test_WhenDeployingTheContract() external {
        // It should disable the initializers
        // It should initialize normally
        vm.skip(true);
    }

    function test_GivenADeployedContract() external {
        // It should refuse to initialize again
        vm.skip(true);
    }

    modifier givenANewProxy() {
        _;
    }

    function test_GivenCallingInitialize() external givenANewProxy {
        // It should set the DAO address
        // It should define the voting settings
        // It should define the target config
        // It should define the plugin metadata
        // It should define the lock manager
        vm.skip(true);
    }

    modifier whenCallingUpdateVotingSettings() {
        _;
    }

    function test_GivenTheCallerHasPermissionToCallUpdateVotingSettings() external whenCallingUpdateVotingSettings {
        // It Should set the new values
        // It Settings() should return the right values
        vm.skip(true);
    }

    function test_RevertGiven_TheCallerHasNoPermissionToCallUpdateVotingSettings()
        external
        whenCallingUpdateVotingSettings
    {
        // It Should revert
        vm.skip(true);
    }

    function test_WhenCallingSupportsInterface() external {
        // It does not support the empty interface
        // It supports IERC165Upgradeable
        // It supports IMembership
        // It supports ILockToVote
        vm.skip(true);
    }

    modifier whenCallingCreateProposal() {
        _;
    }

    modifier givenCreatePermission() {
        _;
    }

    modifier givenNoMinimumVotingPower() {
        _;
    }

    function test_GivenValidParameters()
        external
        whenCallingCreateProposal
        givenCreatePermission
        givenNoMinimumVotingPower
    {
        // It sets the given failuremap, if any
        // It proposalIds are predictable and reproducible
        // It sets the given voting mode, target, params and actions
        // It emits an event
        // It reports proposalCreated() on the lockManager
        vm.skip(true);
    }

    function test_GivenMinimumVotingPowerAboveZero() external whenCallingCreateProposal givenCreatePermission {
        // It should succeed when the creator has enough balance
        // It should revert otherwise
        vm.skip(true);
    }

    function test_RevertGiven_InvalidDates() external whenCallingCreateProposal givenCreatePermission {
        // It should revert
        vm.skip(true);
    }

    function test_RevertGiven_DuplicateProposalID() external whenCallingCreateProposal givenCreatePermission {
        // It should revert
        vm.skip(true);
    }

    function test_RevertGiven_NoCreatePermission() external whenCallingCreateProposal {
        // It should revert
        vm.skip(true);
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
        // It should return true when the voter locked balance is positive
        // It should return false when the voter has no locked balance
        // It should happen in all voting modes
        vm.skip(true);
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
        // It should return true when voting the same with more balance
        // It should return false otherwise
        vm.skip(true);
    }

    function test_GivenVoteReplacementMode()
        external
        whenCallingCanVote
        givenTheProposalIsOpen
        givenNonEmptyVote
        givenVotingAgain
    {
        // It should return true when the locked balance is higher
        // It should return false otherwise
        vm.skip(true);
    }

    function test_GivenEarlyExecutionMode()
        external
        whenCallingCanVote
        givenTheProposalIsOpen
        givenNonEmptyVote
        givenVotingAgain
    {
        // It should return false
        vm.skip(true);
    }

    function test_GivenEmptyVote() external whenCallingCanVote givenTheProposalIsOpen {
        // It should return false
        vm.skip(true);
    }

    function test_GivenTheProposalEnded() external whenCallingCanVote {
        // It should return false, regardless of prior votes
        // It should return false, regardless of the locked balance
        // It should return false, regardless of the voting mode
        vm.skip(true);
    }

    function test_RevertGiven_TheProposalIsNotCreated() external whenCallingCanVote {
        // It should revert
        vm.skip(true);
    }

    modifier whenCallingVote() {
        _;
    }

    function test_RevertGiven_CanVoteReturnsFalse() external whenCallingVote {
        // It should revert
        vm.skip(true);
    }

    modifier givenStandardVotingMode2() {
        _;
    }

    modifier givenVotingTheFirstTime() {
        _;
    }

    function test_GivenHasLockedBalance() external whenCallingVote givenStandardVotingMode2 givenVotingTheFirstTime {
        // It should set the right voter's usedVotingPower
        // It should set the right tally of the voted option
        // It should set the right total voting power
        // It should emit an event
        vm.skip(true);
    }

    function test_RevertGiven_NoLockedBalance()
        external
        whenCallingVote
        givenStandardVotingMode2
        givenVotingTheFirstTime
    {
        // It should revert
        vm.skip(true);
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
        // It should revert
        vm.skip(true);
    }

    function test_GivenVotingWithMoreLockedBalance()
        external
        whenCallingVote
        givenStandardVotingMode2
        givenVotingTheSameOption
    {
        // It should increase the voter's usedVotingPower
        // It should increase the tally of the voted option
        // It should increase the total voting power
        // It should emit an event
        vm.skip(true);
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
        // It should revert
        vm.skip(true);
    }

    function test_RevertGiven_VotingWithMoreLockedBalance2()
        external
        whenCallingVote
        givenStandardVotingMode2
        givenVotingAnotherOption
    {
        // It should revert
        vm.skip(true);
    }

    modifier givenVoteReplacementMode2() {
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
        // It should set the right voter's usedVotingPower
        // It should set the right tally of the voted option
        // It should set the right total voting power
        // It should emit an event
        vm.skip(true);
    }

    function test_RevertGiven_NoLockedBalance2()
        external
        whenCallingVote
        givenVoteReplacementMode2
        givenVotingTheFirstTime2
    {
        // It should revert
        vm.skip(true);
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
        // It should revert
        vm.skip(true);
    }

    function test_GivenVotingWithMoreLockedBalance3()
        external
        whenCallingVote
        givenVoteReplacementMode2
        givenVotingTheSameOption2
    {
        // It should increase the voter's usedVotingPower
        // It should increase the tally of the voted option
        // It should increase the total voting power
        // It should emit an event
        vm.skip(true);
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
        // It should deallocate the current voting power
        // It should allocate that voting power into the new vote option
        vm.skip(true);
    }

    function test_GivenVotingWithMoreLockedBalance4()
        external
        whenCallingVote
        givenVoteReplacementMode2
        givenVotingAnotherOption2
    {
        // It should deallocate the current voting power
        // It the voter's usedVotingPower should reflect the new balance
        // It should allocate to the tally of the voted option
        // It should update the total voting power
        // It should emit an event
        vm.skip(true);
    }

    modifier givenEarlyExecutionMode2() {
        _;
    }

    modifier givenVotingTheFirstTime3() {
        _;
    }

    function test_GivenHasLockedBalance3() external whenCallingVote givenEarlyExecutionMode2 givenVotingTheFirstTime3 {
        // It should set the right voter's usedVotingPower
        // It should set the right tally of the voted option
        // It should set the right total voting power
        // It should emit an event
        vm.skip(true);
    }

    function test_RevertGiven_NoLockedBalance3()
        external
        whenCallingVote
        givenEarlyExecutionMode2
        givenVotingTheFirstTime3
    {
        // It should revert
        vm.skip(true);
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
        // It should revert
        vm.skip(true);
    }

    function test_GivenVotingWithMoreLockedBalance5()
        external
        whenCallingVote
        givenEarlyExecutionMode2
        givenVotingTheSameOption3
    {
        // It should increase the voter's usedVotingPower
        // It should increase the tally of the voted option
        // It should increase the total voting power
        // It should emit an event
        vm.skip(true);
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
        // It should revert
        vm.skip(true);
    }

    function test_RevertGiven_VotingWithMoreLockedBalance6()
        external
        whenCallingVote
        givenEarlyExecutionMode2
        givenVotingAnotherOption3
    {
        // It should revert
        vm.skip(true);
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
        vm.skip(true);
    }

    modifier whenCallingClearvote() {
        _;
    }

    function test_GivenTheVoterHasNoPriorVotingPower() external whenCallingClearvote {
        // It should do nothing
        vm.skip(true);
    }

    function test_RevertGiven_TheProposalIsNotOpen() external whenCallingClearvote {
        // It should revert
        vm.skip(true);
    }

    function test_RevertGiven_EarlyExecutionMode3() external whenCallingClearvote {
        // It should revert
        vm.skip(true);
    }

    function test_GivenStandardVotingMode3() external whenCallingClearvote {
        // It should deallocate the current voting power
        // It should allocate that voting power into the new vote option
        vm.skip(true);
    }

    function test_GivenVoteReplacementMode3() external whenCallingClearvote {
        // It should deallocate the current voting power
        // It should allocate that voting power into the new vote option
        vm.skip(true);
    }

    modifier whenCallingGetVote() {
        _;
    }

    function test_GivenTheVoteExists() external whenCallingGetVote {
        // It should return the right data
        vm.skip(true);
    }

    function test_GivenTheVoteDoesNotExist() external whenCallingGetVote {
        // It should return empty values
        vm.skip(true);
    }

    modifier whenCallingTheProposalGetters() {
        _;
    }

    function test_GivenItDoesNotExist() external whenCallingTheProposalGetters {
        // It getProposal() returns empty values
        // It isProposalOpen() returns false
        // It hasSucceeded() should return false
        // It canExecute() should return false
        // It isSupportThresholdReachedEarly() should return false
        // It isSupportThresholdReached() should return false
        // It isMinVotingPowerReached() should return false
        // It isMinApprovalReached() should return false
        // It usedVotingPower() should return 0 for all voters
        vm.skip(true);
    }

    function test_GivenItHasNotStarted() external whenCallingTheProposalGetters {
        // It getProposal() returns the right values
        // It isProposalOpen() returns false
        // It hasSucceeded() should return false
        // It canExecute() should return false
        // It isSupportThresholdReachedEarly() should return false
        // It isSupportThresholdReached() should return false
        // It isMinVotingPowerReached() should return false
        // It isMinApprovalReached() should return false
        // It usedVotingPower() should return 0 for all voters
        vm.skip(true);
    }

    function test_GivenItHasNotPassedYet() external whenCallingTheProposalGetters {
        // It getProposal() returns the right values
        // It isProposalOpen() returns true
        // It hasSucceeded() should return false
        // It canExecute() should return false
        // It isSupportThresholdReachedEarly() should return false
        // It isSupportThresholdReached() should return false
        // It isMinVotingPowerReached() should return false
        // It isMinApprovalReached() should return false
        // It usedVotingPower() should return the appropriate values
        vm.skip(true);
    }

    modifier givenItDidNotPassAfterEndDate() {
        _;
    }

    function test_GivenItDidNotPassAfterEndDate()
        external
        whenCallingTheProposalGetters
        givenItDidNotPassAfterEndDate
    {
        // It getProposal() returns the right values
        // It isProposalOpen() returns false
        // It hasSucceeded() should return false
        // It canExecute() should return false
        // It isSupportThresholdReachedEarly() should return false
        // It usedVotingPower() should return the appropriate values
        vm.skip(true);
    }

    function test_GivenTheSupportThresholdWasNotAchieved()
        external
        whenCallingTheProposalGetters
        givenItDidNotPassAfterEndDate
    {
        // It isSupportThresholdReached() should return false
        vm.skip(true);
    }

    function test_GivenTheSupportThresholdWasAchieved()
        external
        whenCallingTheProposalGetters
        givenItDidNotPassAfterEndDate
    {
        // It isSupportThresholdReached() should return true
        vm.skip(true);
    }

    function test_GivenTheMinimumVotingPowerWasNotReached()
        external
        whenCallingTheProposalGetters
        givenItDidNotPassAfterEndDate
    {
        // It isMinVotingPowerReached() should return false
        vm.skip(true);
    }

    function test_GivenTheMinimumVotingPowerWasReached()
        external
        whenCallingTheProposalGetters
        givenItDidNotPassAfterEndDate
    {
        // It isMinVotingPowerReached() should return true
        vm.skip(true);
    }

    function test_GivenTheMinimumApprovalTallyWasNotAchieved()
        external
        whenCallingTheProposalGetters
        givenItDidNotPassAfterEndDate
    {
        // It isMinApprovalReached() should return false
        vm.skip(true);
    }

    function test_GivenTheMinimumApprovalTallyWasAchieved()
        external
        whenCallingTheProposalGetters
        givenItDidNotPassAfterEndDate
    {
        // It isMinApprovalReached() should return true
        vm.skip(true);
    }

    modifier givenItHasPassedAfterEndDate() {
        _;
    }

    function test_GivenItHasPassedAfterEndDate() external whenCallingTheProposalGetters givenItHasPassedAfterEndDate {
        // It getProposal() returns the right values
        // It isProposalOpen() returns false
        // It hasSucceeded() should return false
        // It isSupportThresholdReachedEarly() should return false
        // It isSupportThresholdReached() should return true
        // It isMinVotingPowerReached() should return true
        // It isMinApprovalReached() should return true
        // It usedVotingPower() should return the appropriate values
        vm.skip(true);
    }

    function test_GivenTheProposalHasNotBeenExecuted()
        external
        whenCallingTheProposalGetters
        givenItHasPassedAfterEndDate
    {
        // It canExecute() should return true
        vm.skip(true);
    }

    function test_GivenTheProposalHasBeenExecuted()
        external
        whenCallingTheProposalGetters
        givenItHasPassedAfterEndDate
    {
        // It canExecute() should return false
        vm.skip(true);
    }

    modifier givenItHasPassedEarly() {
        _;
    }

    function test_GivenItHasPassedEarly() external whenCallingTheProposalGetters givenItHasPassedEarly {
        // It getProposal() returns the right values
        // It isProposalOpen() returns false
        // It hasSucceeded() should return false
        // It isSupportThresholdReachedEarly() should return true
        // It isSupportThresholdReached() should return true
        // It isMinVotingPowerReached() should return true
        // It isMinApprovalReached() should return true
        // It usedVotingPower() should return the appropriate values
        vm.skip(true);
    }

    function test_GivenTheProposalHasNotBeenExecuted2() external whenCallingTheProposalGetters givenItHasPassedEarly {
        // It canExecute() should return true
        vm.skip(true);
    }

    function test_GivenTheProposalHasBeenExecuted2() external whenCallingTheProposalGetters givenItHasPassedEarly {
        // It canExecute() should return false
        vm.skip(true);
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
        // It canExecute() should return true
        // It hasSucceeded() should return true
        vm.skip(true);
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
        // It canExecute() should return false
        // It hasSucceeded() should return false
        vm.skip(true);
    }

    function test_GivenIsSupportThresholdReachedIsReached()
        external
        whenCallingCanExecuteAndHasSucceeded
        givenTheProposalExists
        givenTheProposalIsNotExecuted
        givenMinVotingPowerIsReached
        givenMinApprovalIsReached
    {
        // It canExecute() should return false before endDate
        // It hasSucceeded() should return false before endDate
        // It canExecute() should return true after endDate
        // It hasSucceeded() should return true after endDate
        vm.skip(true);
    }

    function test_GivenIsSupportThresholdReachedIsNotReached()
        external
        whenCallingCanExecuteAndHasSucceeded
        givenTheProposalExists
        givenTheProposalIsNotExecuted
        givenMinVotingPowerIsReached
        givenMinApprovalIsReached
    {
        // It canExecute() should return false
        // It hasSucceeded() should return false
        vm.skip(true);
    }

    function test_GivenMinApprovalIsNotReached()
        external
        whenCallingCanExecuteAndHasSucceeded
        givenTheProposalExists
        givenTheProposalIsNotExecuted
        givenMinVotingPowerIsReached
    {
        // It canExecute() should return false
        // It hasSucceeded() should return false
        vm.skip(true);
    }

    function test_GivenMinVotingPowerIsNotReached()
        external
        whenCallingCanExecuteAndHasSucceeded
        givenTheProposalExists
        givenTheProposalIsNotExecuted
    {
        // It canExecute() should return false
        // It hasSucceeded() should return false
        vm.skip(true);
    }

    function test_GivenTheProposalIsExecuted() external whenCallingCanExecuteAndHasSucceeded givenTheProposalExists {
        // It canExecute() should return false
        // It hasSucceeded() should return true
        vm.skip(true);
    }

    function test_GivenTheProposalDoesNotExist() external whenCallingCanExecuteAndHasSucceeded {
        // It canExecute() should revert
        // It hasSucceeded() should revert
        vm.skip(true);
    }

    modifier whenCallingExecute() {
        _;
    }

    function test_RevertGiven_TheCallerNoPermissionToCallExecute() external whenCallingExecute {
        // It should revert
        vm.skip(true);
    }

    modifier givenTheCallerHasPermissionToCallExecute2() {
        _;
    }

    function test_RevertGiven_CanExecuteReturnsFalse()
        external
        whenCallingExecute
        givenTheCallerHasPermissionToCallExecute2
    {
        // It should revert
        vm.skip(true);
    }

    function test_GivenCanExecuteReturnsTrue() external whenCallingExecute givenTheCallerHasPermissionToCallExecute2 {
        // It should mark the proposal as executed
        // It should make the target execute the proposal actions
        // It should emit an event
        // It should call proposalEnded on the LockManager
        vm.skip(true);
    }

    function test_WhenCallingIsMember() external {
        // It Should return true when the sender has positive balance or locked tokens
        // It Should return false otherwise
        vm.skip(true);
    }

    function test_WhenCallingCustomProposalParamsABI() external {
        // It Should return the right value
        vm.skip(true);
    }

    function test_WhenCallingCurrentTokenSupply() external {
        // It Should return the right value
        vm.skip(true);
    }

    function test_WhenCallingSupportThresholdRatio() external {
        // It Should return the right value
        vm.skip(true);
    }

    function test_WhenCallingMinParticipationRatio() external {
        // It Should return the right value
        vm.skip(true);
    }

    function test_WhenCallingProposalDuration() external {
        // It Should return the right value
        vm.skip(true);
    }

    function test_WhenCallingMinProposerVotingPower() external {
        // It Should return the right value
        vm.skip(true);
    }

    function test_WhenCallingMinApprovalRatio() external {
        // It Should return the right value
        vm.skip(true);
    }

    function test_WhenCallingVotingMode() external {
        // It Should return the right value
        vm.skip(true);
    }

    function test_WhenCallingCurrentTokenSupply2() external {
        // It Should return the right value
        vm.skip(true);
    }

    function test_WhenCallingLockManager() external {
        // It Should return the right address
        vm.skip(true);
    }

    function test_WhenCallingToken() external {
        // It Should return the right address
        vm.skip(true);
    }

    modifier whenCallingUnderlyingToken() {
        _;
    }

    function test_GivenUnderlyingTokenIsNotDefined() external whenCallingUnderlyingToken {
        // It Should use the (lockable) token's balance to compute the approval ratio
        vm.skip(true);
    }

    function test_GivenUnderlyingTokenIsDefined() external whenCallingUnderlyingToken {
        // It Should use the underlying token's balance to compute the approval ratio
        vm.skip(true);
    }
}
