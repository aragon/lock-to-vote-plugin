// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {AragonTest} from "./lib/TestBase.sol";
import {DaoBuilder} from "./builders/DaoBuilder.sol";
import {DAO, IDAO} from "@aragon/osx/src/core/dao/DAO.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {createProxyAndCall} from "../src/util/proxy.sol";
import {LockToApprovePlugin} from "../src/LockToApprovePlugin.sol";
import {LockToVotePlugin, MajorityVotingBase} from "../src/LockToVotePlugin.sol";
import {LockManagerSettings, UnlockMode, PluginMode} from "../src/interfaces/ILockManager.sol";
import {IMajorityVoting} from "../src/interfaces/IMajorityVoting.sol";
import {LockManager} from "../src/LockManager.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LockManagerTest is AragonTest {
    DaoBuilder builder;
    DAO dao;
    LockToApprovePlugin ltaPlugin;
    LockToVotePlugin ltvPlugin;
    LockManager lockManager;
    IERC20 lockableToken;
    IERC20 underlyingToken;
    uint256 proposalId;

    event BalanceLocked(address voter, uint256 amount);
    event BalanceUnlocked(address voter, uint256 amount);
    event ProposalEnded(uint256 proposalId);

    error NoBalance();
    error NoNewBalance();

    function setUp() public {
        vm.startPrank(alice);
        vm.warp(1 days);
        vm.roll(100);

        builder = new DaoBuilder();
        (dao, ltaPlugin, ltvPlugin, lockManager, lockableToken, underlyingToken) = builder.withTokenHolder(
            alice, 1 ether
        ).withTokenHolder(bob, 10 ether).withTokenHolder(carol, 10 ether).withTokenHolder(david, 15 ether)
            .withStrictUnlock().withApprovalPlugin().build();
    }

    modifier givenTheContractIsBeingDeployed() {
        _;
    }

    function test_WhenDeployingWithValidParametersAndANonzeroUnderlyingToken()
        external
        givenTheContractIsBeingDeployed
    {
        // It Should set the DAO address correctly
        // It Should set the unlockMode correctly
        // It Should set the pluginMode correctly
        // It Should set the token address correctly
        // It Should set the underlying token address correctly
        // It Should initialize the plugin address to address(0)
        vm.skip(true);
    }

    function test_WhenDeployingWithAZeroaddressForTheUnderlyingToken() external givenTheContractIsBeingDeployed {
        // It Should set the underlying token address to address(0)
        vm.skip(true);
    }

    modifier givenThePluginAddressHasNotBeenSetYet() {
        _;
    }

    function test_WhenCallingSetPluginAddressWithAnAddressThatDoesNotSupportILockToVoteBase()
        external
        givenThePluginAddressHasNotBeenSetYet
    {
        // It Should revert with InvalidPlugin
        vm.skip(true);
    }

    modifier givenThePluginModeIsApproval() {
        _;
    }

    function test_WhenCallingSetPluginAddressWithAPluginThatSupportsILockToVoteBaseButNotILockToApprove()
        external
        givenThePluginAddressHasNotBeenSetYet
        givenThePluginModeIsApproval
    {
        // It Should revert with InvalidPlugin
        vm.skip(true);
    }

    function test_WhenCallingSetPluginAddressWithAValidApprovalPlugin()
        external
        givenThePluginAddressHasNotBeenSetYet
        givenThePluginModeIsApproval
    {
        // It Should set the plugin address
        vm.skip(true);
    }

    modifier givenThePluginModeIsVoting() {
        _;
    }

    function test_WhenCallingSetPluginAddressWithAPluginThatSupportsILockToVoteBaseButNotILockToVote()
        external
        givenThePluginAddressHasNotBeenSetYet
        givenThePluginModeIsVoting
    {
        // It Should revert with InvalidPlugin
        vm.skip(true);
    }

    function test_WhenCallingSetPluginAddressWithAValidVotingPlugin()
        external
        givenThePluginAddressHasNotBeenSetYet
        givenThePluginModeIsVoting
    {
        // It Should set the plugin address
        vm.skip(true);
    }

    modifier givenThePluginAddressHasAlreadyBeenSet() {
        _;
    }

    function test_WhenCallingSetPluginAddressAgain() external givenThePluginAddressHasAlreadyBeenSet {
        // It Should revert with SetPluginAddressForbidden
        vm.skip(true);
    }

    modifier givenAUserWantsToLockTokens() {
        _;
    }

    modifier whenTheUserHasNotApprovedTheLockManagerToSpendAnyTokens() {
        _;
    }

    function test_WhenCallingLock()
        external
        givenAUserWantsToLockTokens
        whenTheUserHasNotApprovedTheLockManagerToSpendAnyTokens
    {
        // It Should revert with NoBalance
        vm.skip(true);
    }

    modifier whenTheUserHasApprovedTheLockManagerToSpendTokens() {
        _;
    }

    function test_WhenCallingLock2()
        external
        givenAUserWantsToLockTokens
        whenTheUserHasApprovedTheLockManagerToSpendTokens
    {
        // It Should transfer the full allowance amount from the user
        // It Should increase the user's lockedBalances by the allowance amount
        // It Should emit a BalanceLocked event with the correct user and amount
        vm.skip(true);
    }

    modifier givenPluginModeIsVoting() {
        _;
    }

    modifier givenAPluginIsSetAndAProposalIsActive() {
        _;
    }

    function test_WhenCallingApprove() external givenPluginModeIsVoting givenAPluginIsSetAndAProposalIsActive {
        // It Should revert with InvalidPluginMode
        vm.skip(true);
    }

    function test_WhenCallingLockAndApprove() external givenPluginModeIsVoting givenAPluginIsSetAndAProposalIsActive {
        // It Should revert with InvalidPluginMode
        vm.skip(true);
    }

    modifier givenTheUserHasNoLockedBalance() {
        _;
    }

    function test_WhenCallingVote()
        external
        givenPluginModeIsVoting
        givenAPluginIsSetAndAProposalIsActive
        givenTheUserHasNoLockedBalance
    {
        // It Should revert with NoBalance
        vm.skip(true);
    }

    modifier givenTheUserHasNoTokenAllowanceForTheLockManager() {
        _;
    }

    function test_WhenCallingLockAndVote()
        external
        givenPluginModeIsVoting
        givenAPluginIsSetAndAProposalIsActive
        givenTheUserHasNoLockedBalance
        givenTheUserHasNoTokenAllowanceForTheLockManager
    {
        // It Should revert with NoBalance
        vm.skip(true);
    }

    modifier givenTheUserHasATokenAllowanceForTheLockManager() {
        _;
    }

    function test_WhenCallingLockAndVote2()
        external
        givenPluginModeIsVoting
        givenAPluginIsSetAndAProposalIsActive
        givenTheUserHasNoLockedBalance
        givenTheUserHasATokenAllowanceForTheLockManager
    {
        // It Should first lock the tokens by transferring the full allowance
        // It Should then call vote() on the plugin with the new balance
        vm.skip(true);
    }

    modifier givenTheUserHasALockedBalance() {
        _;
    }

    function test_WhenCallingVoteForTheFirstTimeOnAProposal()
        external
        givenPluginModeIsVoting
        givenAPluginIsSetAndAProposalIsActive
        givenTheUserHasALockedBalance
    {
        // It Should call vote() on the plugin with the user's full locked balance
        vm.skip(true);
    }

    modifier givenTheUserHasAlreadyVotedOnTheProposalWithTheirCurrentBalance() {
        _;
    }

    function test_WhenCallingVoteAgainWithTheSameParameters()
        external
        givenPluginModeIsVoting
        givenAPluginIsSetAndAProposalIsActive
        givenTheUserHasALockedBalance
        givenTheUserHasAlreadyVotedOnTheProposalWithTheirCurrentBalance
    {
        // It Should revert with NoNewBalance
        vm.skip(true);
    }

    modifier givenTheUserLocksMoreTokens() {
        _;
    }

    function test_WhenCallingVoteAgain()
        external
        givenPluginModeIsVoting
        givenAPluginIsSetAndAProposalIsActive
        givenTheUserHasALockedBalance
        givenTheUserLocksMoreTokens
    {
        // It Should call vote() on the plugin with the new, larger balance
        vm.skip(true);
    }

    modifier givenPluginModeIsApproval() {
        _;
    }

    modifier givenAPluginIsSetAndAProposalIsActive2() {
        _;
    }

    function test_WhenCallingVote2() external givenPluginModeIsApproval givenAPluginIsSetAndAProposalIsActive2 {
        // It Should revert with InvalidPluginMode
        vm.skip(true);
    }

    function test_WhenCallingLockAndVote3() external givenPluginModeIsApproval givenAPluginIsSetAndAProposalIsActive2 {
        // It Should revert with InvalidPluginMode
        vm.skip(true);
    }

    modifier givenTheUserHasNoLockedBalance2() {
        _;
    }

    function test_WhenCallingApprove2()
        external
        givenPluginModeIsApproval
        givenAPluginIsSetAndAProposalIsActive2
        givenTheUserHasNoLockedBalance2
    {
        // It Should revert with NoBalance
        vm.skip(true);
    }

    modifier givenTheUserHasNoTokenAllowanceForTheLockManager2() {
        _;
    }

    function test_WhenCallingLockAndApprove2()
        external
        givenPluginModeIsApproval
        givenAPluginIsSetAndAProposalIsActive2
        givenTheUserHasNoLockedBalance2
        givenTheUserHasNoTokenAllowanceForTheLockManager2
    {
        // It Should revert with NoBalance
        vm.skip(true);
    }

    modifier givenTheUserHasATokenAllowanceForTheLockManager2() {
        _;
    }

    function test_WhenCallingLockAndApprove3()
        external
        givenPluginModeIsApproval
        givenAPluginIsSetAndAProposalIsActive2
        givenTheUserHasNoLockedBalance2
        givenTheUserHasATokenAllowanceForTheLockManager2
    {
        // It Should first lock the tokens by transferring the full allowance
        // It Should then call approve() on the plugin with the new balance
        vm.skip(true);
    }

    modifier givenTheUserHasALockedBalance2() {
        _;
    }

    function test_WhenCallingApproveForTheFirstTimeOnAProposal()
        external
        givenPluginModeIsApproval
        givenAPluginIsSetAndAProposalIsActive2
        givenTheUserHasALockedBalance2
    {
        // It Should call approve() on the plugin with the user's full locked balance
        vm.skip(true);
    }

    modifier givenTheUserHasAlreadyApprovedTheProposalWithTheirCurrentBalance() {
        _;
    }

    function test_WhenCallingApproveAgain()
        external
        givenPluginModeIsApproval
        givenAPluginIsSetAndAProposalIsActive2
        givenTheUserHasALockedBalance2
        givenTheUserHasAlreadyApprovedTheProposalWithTheirCurrentBalance
    {
        // It Should revert with NoNewBalance
        vm.skip(true);
    }

    modifier givenTheUserLocksMoreTokens2() {
        _;
    }

    function test_WhenCallingApproveAgain2()
        external
        givenPluginModeIsApproval
        givenAPluginIsSetAndAProposalIsActive2
        givenTheUserHasALockedBalance2
        givenTheUserLocksMoreTokens2
    {
        // It Should call approve() on the plugin with the new, larger balance
        vm.skip(true);
    }

    modifier givenAUserWantsToUnlockTokens() {
        _;
    }

    modifier givenTheUserHasNoLockedBalance3() {
        _;
    }

    function test_WhenCallingUnlock() external givenAUserWantsToUnlockTokens givenTheUserHasNoLockedBalance3 {
        // It Should revert with NoBalance
        vm.skip(true);
    }

    modifier givenTheUserHasALockedBalance3() {
        _;
    }

    modifier givenUnlockModeIsStrict() {
        _;
    }

    modifier givenTheUserHasNoActiveVotesOnAnyOpenProposals() {
        _;
    }

    function test_WhenCallingUnlock2()
        external
        givenAUserWantsToUnlockTokens
        givenTheUserHasALockedBalance3
        givenUnlockModeIsStrict
        givenTheUserHasNoActiveVotesOnAnyOpenProposals
    {
        // It Should transfer the locked balance back to the user
        // It Should set the user's lockedBalances to 0
        // It Should emit a BalanceUnlocked event
        vm.skip(true);
    }

    modifier givenTheUserHasAnActiveVoteOnAtLeastOneOpenProposal() {
        _;
    }

    function test_WhenCallingUnlock3()
        external
        givenAUserWantsToUnlockTokens
        givenTheUserHasALockedBalance3
        givenUnlockModeIsStrict
        givenTheUserHasAnActiveVoteOnAtLeastOneOpenProposal
    {
        // It Should revert with LocksStillActive
        vm.skip(true);
    }

    modifier givenTheUserOnlyHasVotesOnProposalsThatAreNowClosed() {
        _;
    }

    function test_WhenCallingUnlock4()
        external
        givenAUserWantsToUnlockTokens
        givenTheUserHasALockedBalance3
        givenUnlockModeIsStrict
        givenTheUserOnlyHasVotesOnProposalsThatAreNowClosed
    {
        // It Should succeed and transfer the locked balance back to the user
        // It Should remove the closed proposal from knownProposalIds
        vm.skip(true);
    }

    modifier givenUnlockModeIsDefault() {
        _;
    }

    modifier givenTheUserHasNoActiveVotesOnAnyOpenProposals2() {
        _;
    }

    function test_WhenCallingUnlock5()
        external
        givenAUserWantsToUnlockTokens
        givenTheUserHasALockedBalance3
        givenUnlockModeIsDefault
        givenTheUserHasNoActiveVotesOnAnyOpenProposals2
    {
        // It Should succeed and transfer the locked balance back to the user
        vm.skip(true);
    }

    modifier givenTheUserHasVotesOnOpenProposals() {
        _;
    }

    function test_WhenCallingUnlock6()
        external
        givenAUserWantsToUnlockTokens
        givenTheUserHasALockedBalance3
        givenUnlockModeIsDefault
        givenTheUserHasVotesOnOpenProposals
    {
        // It Should call clearVote() on the plugin for each active proposal
        // It Should transfer the locked balance back to the user
        // It Should set the user's lockedBalances to 0
        // It Should emit a BalanceUnlocked event
        vm.skip(true);
    }

    modifier givenTheUserHasApprovalsOnOpenProposals() {
        _;
    }

    function test_WhenCallingUnlock7()
        external
        givenAUserWantsToUnlockTokens
        givenTheUserHasALockedBalance3
        givenUnlockModeIsDefault
        givenTheUserHasApprovalsOnOpenProposals
    {
        // It Should call clearApproval() on the plugin for each active proposal
        // It Should transfer the locked balance back to the user
        // It Should set the user's lockedBalances to 0
        // It Should emit a BalanceUnlocked event
        vm.skip(true);
    }

    modifier givenTheUserOnlyHasVotesOnProposalsThatAreNowClosedOrEnded() {
        _;
    }

    function test_WhenCallingUnlock8()
        external
        givenAUserWantsToUnlockTokens
        givenTheUserHasALockedBalance3
        givenUnlockModeIsDefault
        givenTheUserOnlyHasVotesOnProposalsThatAreNowClosedOrEnded
    {
        // It Should not attempt to clear votes for the closed proposal
        // It Should remove the closed proposal from knownProposalIds
        // It Should succeed and transfer the locked balance back to the user
        vm.skip(true);
    }

    modifier givenTheUserOnlyHasApprovalsOnProposalsThatAreNowClosedOrEnded() {
        _;
    }

    function test_WhenCallingUnlock9()
        external
        givenAUserWantsToUnlockTokens
        givenTheUserHasALockedBalance3
        givenUnlockModeIsDefault
        givenTheUserOnlyHasApprovalsOnProposalsThatAreNowClosedOrEnded
    {
        // It Should not attempt to clear votes for the closed proposal
        // It Should remove the closed proposal from knownProposalIds
        // It Should succeed and transfer the locked balance back to the user
        vm.skip(true);
    }

    modifier givenThePluginHasBeenSet() {
        _;
    }

    modifier givenTheCallerIsNotTheRegisteredPlugin() {
        _;
    }

    function test_WhenCallingProposalCreated()
        external
        givenThePluginHasBeenSet
        givenTheCallerIsNotTheRegisteredPlugin
    {
        // It Should revert with InvalidPluginAddress
        vm.skip(true);
    }

    function test_WhenCallingProposalEnded() external givenThePluginHasBeenSet givenTheCallerIsNotTheRegisteredPlugin {
        // It Should revert with InvalidPluginAddress
        vm.skip(true);
    }

    modifier givenTheCallerIsTheRegisteredPlugin() {
        _;
    }

    function test_WhenCallingProposalCreatedWithANewProposalID()
        external
        givenThePluginHasBeenSet
        givenTheCallerIsTheRegisteredPlugin
    {
        // It Should add the proposal ID to knownProposalIds
        vm.skip(true);
    }

    modifier givenAProposalIDIsAlreadyKnown() {
        _;
    }

    function test_WhenCallingProposalCreatedWithThatSameID()
        external
        givenThePluginHasBeenSet
        givenTheCallerIsTheRegisteredPlugin
        givenAProposalIDIsAlreadyKnown
    {
        // It Should not change the set of known proposals
        vm.skip(true);
    }

    function test_WhenCallingProposalEndedWithThatProposalID()
        external
        givenThePluginHasBeenSet
        givenTheCallerIsTheRegisteredPlugin
        givenAProposalIDIsAlreadyKnown
    {
        // It Should remove the proposal ID from knownProposalIds
        // It Should emit a ProposalEnded event
        vm.skip(true);
    }

    function test_RevertWhen_CallingProposalEndedWithANonexistentProposalID()
        external
        givenThePluginHasBeenSet
        givenTheCallerIsTheRegisteredPlugin
    {
        // It Should revert
        vm.skip(true);
    }

    modifier givenTheContractIsInitialized() {
        _;
    }

    modifier givenANonzeroUnderlyingTokenWasProvidedInTheConstructor() {
        _;
    }

    function test_WhenCallingUnderlyingToken()
        external
        givenTheContractIsInitialized
        givenANonzeroUnderlyingTokenWasProvidedInTheConstructor
    {
        // It Should return the address of the underlying token
        vm.skip(true);
    }

    modifier givenAZeroaddressUnderlyingTokenWasProvidedInTheConstructor() {
        _;
    }

    function test_WhenCallingUnderlyingToken2()
        external
        givenTheContractIsInitialized
        givenAZeroaddressUnderlyingTokenWasProvidedInTheConstructor
    {
        // It Should return the address of the main token
        vm.skip(true);
    }

    modifier givenAPluginIsSetAndAProposalExists() {
        _;
    }

    modifier givenPluginModeIsVoting2() {
        _;
    }

    function test_WhenCallingCanVote()
        external
        givenTheContractIsInitialized
        givenAPluginIsSetAndAProposalExists
        givenPluginModeIsVoting2
    {
        // It Should proxy the call to the plugin's canVote() and return its result
        vm.skip(true);
    }

    modifier givenPluginModeIsApproval2() {
        _;
    }

    function test_WhenCallingCanVote2()
        external
        givenTheContractIsInitialized
        givenAPluginIsSetAndAProposalExists
        givenPluginModeIsApproval2
    {
        // It Should proxy the call to the plugin's canApprove() and return its result
        vm.skip(true);
    }

    modifier givenTheContractHasSeveralKnownProposalIDs() {
        _;
    }

    function test_WhenCallingKnownProposalIdAtWithAValidIndex()
        external
        givenTheContractIsInitialized
        givenTheContractHasSeveralKnownProposalIDs
    {
        // It Should return the correct proposal ID at that index
        vm.skip(true);
    }

    function test_RevertWhen_CallingKnownProposalIdAtWithAnOutofboundsIndex()
        external
        givenTheContractIsInitialized
        givenTheContractHasSeveralKnownProposalIDs
    {
        // It Should revert
        vm.skip(true);
    }
}
