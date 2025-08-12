// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {TestBase} from "./lib/TestBase.sol";
import {DaoBuilder} from "./builders/DaoBuilder.sol";
import {DAO, IDAO} from "@aragon/osx/src/core/dao/DAO.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {createProxyAndCall} from "../src/util/proxy.sol";
import {LockToVotePlugin, MajorityVotingBase} from "../src/LockToVotePlugin.sol";
import {LockManagerSettings, PluginMode} from "../src/interfaces/ILockManager.sol";
import {IMajorityVoting} from "../src/interfaces/IMajorityVoting.sol";
import {LockManagerBase} from "../src/base/LockManagerBase.sol";
import {LockManagerERC20} from "../src/LockManagerERC20.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TestToken} from "./mocks/TestToken.sol";
import {ILockToGovernBase} from "../src/interfaces/ILockToGovernBase.sol";

contract LockManagerERC20Test is TestBase {
    DaoBuilder builder;
    DAO dao;
    LockToVotePlugin ltvPlugin;
    LockManagerERC20 lockManager;
    IERC20 lockableToken;
    uint256 proposalId;

    event BalanceLocked(address voter, uint256 amount);
    event BalanceUnlocked(address voter, uint256 amount);
    event ProposalEnded(uint256 proposalId);

    error NoBalance();
    error VoteCastForbidden(uint256 proposalId, address account);
    error SetPluginAddressForbidden();
    error InvalidPluginMode();
    error InvalidPluginAddress();

    function setUp() public {
        vm.warp(1 days);
        vm.roll(100);

        builder = new DaoBuilder();
        (dao, ltvPlugin, lockManager, lockableToken) = builder.withTokenHolder(alice, 1 ether).withTokenHolder(
            bob, 10 ether
        ).withTokenHolder(carol, 10 ether).withTokenHolder(david, 15 ether).build();
    }

    modifier givenTheContractIsBeingDeployed() {
        _;
    }

    modifier givenThePluginAddressHasNotBeenSetYet() {
        lockManager = new LockManagerERC20(LockManagerSettings(PluginMode.Voting), lockableToken);
        _;
    }

    function test_WhenCallingSetPluginAddressWithAnAddressThatDoesNotSupportILockToGovernBase()
        external
        givenThePluginAddressHasNotBeenSetYet
    {
        // It Should revert with InvalidPlugin
        vm.expectRevert(LockManagerBase.InvalidPlugin.selector);
        lockManager.setPluginAddress(ILockToGovernBase(address(dao)));
    }

    modifier givenThePluginModeIsVoting() {
        // The default setup is Voting mode, so no changes needed
        _;
    }

    function test_WhenCallingSetPluginAddressWithAValidVotingPlugin()
        external
        givenThePluginAddressHasNotBeenSetYet
        givenThePluginModeIsVoting
    {
        // It Should set the plugin address
        (, LockToVotePlugin votingPlugin,,) = builder.withVotingPlugin().build();

        assertEq(address(lockManager.plugin()), address(0));
        lockManager.setPluginAddress(votingPlugin);
        assertEq(address(lockManager.plugin()), address(votingPlugin));
    }

    modifier givenThePluginAddressHasAlreadyBeenSet() {
        // The default setup already sets a plugin
        _;
    }

    function test_WhenCallingSetPluginAddressAgain() external givenThePluginAddressHasAlreadyBeenSet {
        // It Should revert with SetPluginAddressForbidden
        vm.expectRevert(SetPluginAddressForbidden.selector);
        lockManager.setPluginAddress(ltvPlugin);
    }

    modifier givenAUserWantsToLockTokens() {
        _;
    }

    modifier whenTheUserHasNotApprovedTheLockManagerToSpendAnyTokens() {
        TestToken(address(lockableToken)).mint(bob, 1 ether);

        vm.prank(bob);
        assertEq(lockableToken.allowance(bob, address(lockManager)), 0);
        _;
    }

    function test_WhenCallingLock()
        external
        givenAUserWantsToLockTokens
        whenTheUserHasNotApprovedTheLockManagerToSpendAnyTokens
    {
        // It Should revert with NoBalance
        vm.prank(bob);
        vm.expectRevert(NoBalance.selector);
        lockManager.lock();
    }

    modifier whenTheUserHasApprovedTheLockManagerToSpendTokens() {
        TestToken(address(lockableToken)).mint(bob, 1 ether);

        vm.prank(bob);
        lockableToken.approve(address(lockManager), 1 ether);
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
        uint256 allowance = lockableToken.allowance(bob, address(lockManager));
        uint256 initialBobBalance = lockableToken.balanceOf(bob);

        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit BalanceLocked(bob, allowance);
        lockManager.lock();

        assertEq(lockManager.getLockedBalance(bob), allowance, "Locked balance incorrect");
        assertEq(lockableToken.balanceOf(bob), initialBobBalance - allowance, "User balance incorrect");
    }

    modifier whenTheUserHasApprovedTheLockManagerToSpendMoreThanTheBalance() {
        TestToken(address(lockableToken)).mint(bob, 1 ether);

        vm.prank(bob);
        lockableToken.approve(address(lockManager), 1000000000 ether);

        _;
    }

    function test_WhenCallingLock3()
        external
        givenAUserWantsToLockTokens
        whenTheUserHasApprovedTheLockManagerToSpendMoreThanTheBalance
    {
        // It Should transfer the full balance from the user
        // It Should increase the user's lockedBalances by the balance
        // It Should emit a BalanceLocked event with the correct user and amount

        uint256 allowance = lockableToken.allowance(bob, address(lockManager));
        uint256 initialBobBalance = lockableToken.balanceOf(bob);

        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit BalanceLocked(bob, initialBobBalance);
        lockManager.lock();

        assertEq(lockManager.getLockedBalance(bob), initialBobBalance, "Incorrect locked balance");
        assertEq(lockableToken.balanceOf(bob), 0, "Incorrect user balance");
        assertEq(
            lockableToken.allowance(bob, address(lockManager)),
            allowance - initialBobBalance,
            "Incorrect allowance left"
        );
    }

    modifier whenTheUserTriesToLockMoreThanHisBalance() {
        TestToken(address(lockableToken)).mint(bob, 1 ether);

        vm.prank(bob);
        lockableToken.approve(address(lockManager), 1 ether);

        _;
    }

    function test_RevertWhen_CallingLock4()
        external
        givenAUserWantsToLockTokens
        whenTheUserTriesToLockMoreThanHisBalance
    {
        // It Should revert

        vm.prank(bob);
        vm.expectRevert("ERC20: insufficient allowance");
        lockManager.lock(100 ether);

        vm.prank(bob);
        vm.expectRevert("ERC20: insufficient allowance");
        lockManager.lock(1.1 ether);

        // OK
        vm.prank(bob);
        lockManager.lock(1 ether);
    }

    modifier givenVotingPluginIsActive() {
        (dao, ltvPlugin, lockManager, lockableToken) =
            builder.withVotingPlugin().withTokenHolder(alice, 1 ether).build();
        Action[] memory _actions = new Action[](0);
        proposalId = ltvPlugin.createProposal(bytes(""), _actions, 0, 0, bytes(""));
        vm.prank(address(ltvPlugin));
        lockManager.proposalCreated(proposalId);
        _;
    }

    modifier givenTheUserHasNoLockedBalance() {
        vm.prank(alice);
        assertEq(lockManager.getLockedBalance(alice), 0);
        _;
    }

    function test_WhenCallingVote() external givenVotingPluginIsActive givenTheUserHasNoLockedBalance {
        // It Should revert with NoBalance
        vm.prank(david);
        vm.expectRevert(abi.encodeWithSelector(VoteCastForbidden.selector, proposalId, david));
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);
    }

    modifier givenTheUserHasNoTokenAllowanceForTheLockManager() {
        assertEq(lockableToken.allowance(alice, address(lockManager)), 0);
        _;
    }

    function test_WhenCallingLockAndVote()
        external
        givenVotingPluginIsActive
        givenTheUserHasNoLockedBalance
        givenTheUserHasNoTokenAllowanceForTheLockManager
    {
        // It Should revert with NoBalance
        vm.expectRevert(NoBalance.selector);
        lockManager.lockAndVote(proposalId, IMajorityVoting.VoteOption.Yes);
    }

    modifier givenTheUserHasATokenAllowanceForTheLockManager() {
        TestToken(address(lockableToken)).mint(alice, 1 ether);

        vm.prank(alice);
        lockableToken.approve(address(lockManager), 1 ether);
        _;
    }

    function test_WhenCallingLockAndVote2()
        external
        givenVotingPluginIsActive
        givenTheUserHasNoLockedBalance
        givenTheUserHasATokenAllowanceForTheLockManager
    {
        // It Should first lock the tokens by transferring the full allowance
        // It Should then call vote() on the plugin with the new balance
        uint256 allowance = lockableToken.allowance(alice, address(lockManager));
        uint256 initialBalance = lockableToken.balanceOf(alice);

        vm.prank(alice);
        vm.expectCall(
            address(ltvPlugin),
            abi.encodeWithSelector(
                ltvPlugin.vote.selector, proposalId, alice, IMajorityVoting.VoteOption.Yes, allowance
            )
        );
        lockManager.lockAndVote(proposalId, IMajorityVoting.VoteOption.Yes);

        assertEq(lockManager.getLockedBalance(alice), allowance, "Locked balance incorrect");
        assertEq(lockableToken.balanceOf(alice), initialBalance - allowance, "User balance not transferred");
    }

    modifier givenTheUserHasALockedBalance() {
        TestToken(address(lockableToken)).mint(alice, 0.5 ether);

        vm.prank(alice);
        lockableToken.approve(address(lockManager), 0.5 ether);
        vm.prank(alice);
        lockManager.lock();
        assertEq(lockManager.getLockedBalance(alice), 0.5 ether);
        _;
    }

    function test_WhenCallingVoteForTheFirstTimeOnAProposal()
        external
        givenVotingPluginIsActive
        givenTheUserHasALockedBalance
    {
        // It Should call vote() on the plugin with the user's full locked balance
        uint256 lockedBalance = lockManager.getLockedBalance(alice);

        vm.prank(alice);
        vm.expectCall(
            address(ltvPlugin),
            abi.encodeWithSelector(
                ltvPlugin.vote.selector, proposalId, alice, IMajorityVoting.VoteOption.Yes, lockedBalance
            )
        );
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);
    }

    modifier givenTheUserHasAlreadyVotedOnTheProposalWithTheirCurrentBalance() {
        uint256 lockedBalance = lockManager.getLockedBalance(alice);
        vm.prank(alice);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), lockedBalance);
        _;
    }

    function test_WhenCallingVoteAgainWithTheSameParameters()
        external
        givenVotingPluginIsActive
        givenTheUserHasALockedBalance
        givenTheUserHasAlreadyVotedOnTheProposalWithTheirCurrentBalance
    {
        // It Should revert with VoteCastForbidden

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(VoteCastForbidden.selector, proposalId, alice));
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);
    }

    modifier givenTheUserLocksMoreTokens() {
        vm.prank(alice);
        lockableToken.approve(address(lockManager), 0.5 ether);
        vm.prank(alice);
        lockManager.lock();
        _;
    }

    function test_WhenCallingVoteAgain()
        external
        givenVotingPluginIsActive
        givenTheUserHasALockedBalance
        givenTheUserHasAlreadyVotedOnTheProposalWithTheirCurrentBalance
        givenTheUserLocksMoreTokens
    {
        // It Should call vote() on the plugin with the new, larger balance
        // Note: For this to work, votingMode must be VoteReplacement
        (dao, ltvPlugin, lockManager, lockableToken) =
            builder.withVotingPlugin().withVoteReplacement().withTokenHolder(alice, 2 ether).build();
        Action[] memory _actions = new Action[](0);
        proposalId = ltvPlugin.createProposal(bytes(""), _actions, 0, 0, bytes(""));

        vm.prank(address(ltvPlugin));
        lockManager.proposalCreated(proposalId);

        vm.prank(alice);
        lockableToken.approve(address(lockManager), 0.5 ether);
        vm.prank(alice);
        lockManager.lockAndVote(proposalId, IMajorityVoting.VoteOption.Yes);

        vm.prank(alice);
        lockableToken.approve(address(lockManager), 0.5 ether);
        vm.prank(alice);
        lockManager.lock();

        uint256 newLockedBalance = lockManager.getLockedBalance(alice);
        assertGt(newLockedBalance, 0.5 ether);

        vm.prank(alice);
        vm.expectCall(
            address(ltvPlugin),
            abi.encodeWithSelector(
                ltvPlugin.vote.selector, proposalId, alice, IMajorityVoting.VoteOption.No, newLockedBalance
            )
        );
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.No);
    }

    modifier givenAUserWantsToUnlockTokens() {
        _;
    }

    modifier givenTheUserHasNoLockedBalance3() {
        assertEq(lockManager.getLockedBalance(alice), 0);
        _;
    }

    function test_WhenCallingUnlock() external givenAUserWantsToUnlockTokens givenTheUserHasNoLockedBalance3 {
        // It Should revert with NoBalance
        vm.prank(alice);
        vm.expectRevert(NoBalance.selector);
        lockManager.unlock();
    }

    modifier givenTheUserHasALockedBalance3() {
        (dao, ltvPlugin, lockManager, lockableToken) = builder.withTokenHolder(alice, 1 ether).build();

        vm.prank(alice);
        lockableToken.approve(address(lockManager), 1 ether);
        vm.prank(alice);
        lockManager.lock();
        _;
    }

    modifier givenTheUserHasNoActiveVotesOnAnyOpenProposals2() {
        // User has locked tokens but not voted/approved
        _;
    }

    function test_WhenCallingUnlock5()
        external
        givenAUserWantsToUnlockTokens
        givenTheUserHasALockedBalance3
        givenTheUserHasNoActiveVotesOnAnyOpenProposals2
    {
        // It Should succeed and transfer the locked balance back to the user
        uint256 lockedAmount = lockManager.getLockedBalance(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);

        vm.prank(alice);
        lockManager.unlock();

        assertEq(lockManager.getLockedBalance(alice), 0);
        assertEq(lockableToken.balanceOf(alice), initialBalance + lockedAmount);
    }

    modifier givenTheUserHasVotesOnOpenProposals() {
        (dao, ltvPlugin, lockManager, lockableToken) =
            builder.withVotingPlugin().withVoteReplacement().withTokenHolder(alice, 1 ether).build();

        Action[] memory _actions = new Action[](0);
        proposalId = ltvPlugin.createProposal(bytes(""), _actions, 0, 0, bytes(""));
        vm.prank(address(ltvPlugin));
        lockManager.proposalCreated(proposalId);

        vm.prank(alice);
        lockableToken.approve(address(lockManager), 1 ether);
        vm.prank(alice);
        lockManager.lockAndVote(proposalId, IMajorityVoting.VoteOption.Yes);
        _;
    }

    function test_WhenCallingUnlock6() external givenAUserWantsToUnlockTokens givenTheUserHasVotesOnOpenProposals {
        // It Should call clearVote() on the plugin for each active proposal
        // It Should transfer the locked balance back to the user
        // It Should set the user's lockedBalances to 0
        // It Should emit a BalanceUnlocked event
        uint256 lockedAmount = lockManager.getLockedBalance(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);

        vm.expectCall(address(ltvPlugin), abi.encodeWithSelector(ltvPlugin.clearVote.selector, proposalId, alice));
        vm.expectEmit(true, true, true, true);
        emit BalanceUnlocked(alice, lockedAmount);

        vm.prank(alice);
        lockManager.unlock();

        assertEq(lockManager.getLockedBalance(alice), 0);
        assertEq(lockableToken.balanceOf(alice), initialBalance + lockedAmount);
    }

    modifier givenTheUserOnlyHasVotesOnProposalsThatAreNowClosedOrEnded() {
        (dao, ltvPlugin, lockManager, lockableToken) =
            builder.withVotingPlugin().withVoteReplacement().withTokenHolder(alice, 1 ether).build();
        Action[] memory _actions = new Action[](0);
        proposalId = ltvPlugin.createProposal(bytes(""), _actions, 0, 0, bytes(""));
        vm.prank(address(ltvPlugin));
        lockManager.proposalCreated(proposalId);

        vm.prank(alice);
        lockableToken.approve(address(lockManager), 1 ether);
        vm.prank(alice);
        lockManager.lockAndVote(proposalId, IMajorityVoting.VoteOption.Yes);

        vm.warp(block.timestamp + ltvPlugin.proposalDuration() + 1 days);
        assertFalse(ltvPlugin.isProposalOpen(proposalId));
        _;
    }

    function test_WhenCallingUnlock8()
        external
        givenAUserWantsToUnlockTokens
        givenTheUserOnlyHasVotesOnProposalsThatAreNowClosedOrEnded
    {
        // It Should not attempt to clear votes for the closed proposal
        // It Should remove the closed proposal from knownProposalIds
        // It Should succeed and transfer the locked balance back to the user
        uint256 lockedAmount = lockManager.getLockedBalance(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);

        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), 1 ether);
        vm.prank(alice);
        lockManager.unlock();
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), 1 ether);

        assertEq(lockManager.getLockedBalance(alice), 0);
        assertEq(lockableToken.balanceOf(alice), initialBalance + lockedAmount);
        vm.expectRevert();
        lockManager.knownProposalIdAt(0);
    }

    modifier givenThePluginHasBeenSet() {
        // Default setup has a plugin set
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
        vm.prank(bob);
        vm.expectRevert(InvalidPluginAddress.selector);
        lockManager.proposalCreated(1);
    }

    function test_WhenCallingProposalEnded() external givenThePluginHasBeenSet givenTheCallerIsNotTheRegisteredPlugin {
        // It Should revert with InvalidPluginAddress
        vm.prank(bob);
        vm.expectRevert(InvalidPluginAddress.selector);
        lockManager.proposalEnded(1);
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
        vm.prank(address(lockManager.plugin()));
        lockManager.proposalCreated(123);
        assertEq(lockManager.knownProposalIdAt(0), 123);
    }

    modifier givenAProposalIDIsAlreadyKnown() {
        vm.prank(address(lockManager.plugin()));
        lockManager.proposalCreated(123);
        _;
    }

    function test_WhenCallingProposalCreatedWithThatSameID()
        external
        givenThePluginHasBeenSet
        givenTheCallerIsTheRegisteredPlugin
        givenAProposalIDIsAlreadyKnown
    {
        // It Should not change the set of known proposals
        uint256 initialLength = lockManager.knownProposalIdsLength();
        vm.prank(address(lockManager.plugin()));
        lockManager.proposalCreated(123);
        assertEq(lockManager.knownProposalIdsLength(), initialLength);
    }

    function test_WhenCallingProposalEndedWithThatProposalID()
        external
        givenThePluginHasBeenSet
        givenTheCallerIsTheRegisteredPlugin
        givenAProposalIDIsAlreadyKnown
    {
        // It Should remove the proposal ID from knownProposalIds
        // It Should emit a ProposalEnded event
        vm.expectEmit(true, false, false, true);
        emit ProposalEnded(123);
        vm.prank(address(lockManager.plugin()));
        lockManager.proposalEnded(123);

        vm.expectRevert();
        lockManager.knownProposalIdAt(0);
    }

    function test_WhenCallingProposalEndedWithANonexistentProposalID()
        external
        givenThePluginHasBeenSet
        givenTheCallerIsTheRegisteredPlugin
    {
        // It Should do nothing
        vm.prank(address(lockManager.plugin()));
        lockManager.proposalEnded(999);
        vm.prank(address(lockManager.plugin()));
        lockManager.proposalEnded(55667788);
        vm.prank(address(lockManager.plugin()));
        lockManager.proposalEnded(0);
        vm.prank(address(lockManager.plugin()));
        lockManager.proposalEnded(1000);
    }

    modifier givenTheContractIsInitialized() {
        _;
    }

    modifier givenAPluginIsSetAndAProposalExists() {
        // This will be handled by more specific modifiers
        _;
    }

    function test_WhenCallingCanVote() external givenVotingPluginIsActive {
        // It Should proxy the call to the plugin's canVote() and return its result
        vm.prank(alice);
        vm.expectCall(
            address(ltvPlugin),
            abi.encodeWithSelector(ltvPlugin.canVote.selector, proposalId, alice, IMajorityVoting.VoteOption.Yes)
        );
        lockManager.canVote(proposalId, alice, IMajorityVoting.VoteOption.Yes);
    }

    modifier givenTheContractHasSeveralKnownProposalIDs() {
        vm.startPrank(address(ltvPlugin));
        lockManager.proposalCreated(101);
        lockManager.proposalCreated(102);
        lockManager.proposalCreated(103);
        vm.stopPrank();

        _;
    }

    function test_WhenCallingKnownProposalIdAtWithAValidIndex()
        external
        givenTheContractIsInitialized
        givenTheContractHasSeveralKnownProposalIDs
    {
        // It Should return the correct proposal ID at that index
        assertEq(lockManager.knownProposalIdAt(0), 101);
        assertEq(lockManager.knownProposalIdAt(1), 102);
        assertEq(lockManager.knownProposalIdAt(2), 103);
    }

    function test_RevertWhen_CallingKnownProposalIdAtWithAnOutofboundsIndex()
        external
        givenTheContractIsInitialized
        givenTheContractHasSeveralKnownProposalIDs
    {
        // It Should revert
        vm.expectRevert();
        lockManager.knownProposalIdAt(3);
        vm.expectRevert();
        lockManager.knownProposalIdAt(10);
    }
}
