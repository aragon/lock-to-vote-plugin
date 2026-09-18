// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Action} from "@aragon/osx/common/executors/IExecutor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {LockToVotePlugin} from "../src/LockToVotePlugin.sol";
import {LockManagerERC20} from "../src/LockManagerERC20.sol";
import {MajorityVotingBase} from "../src/base/MajorityVotingBase.sol";
import {IMajorityVoting} from "../src/interfaces/IMajorityVoting.sol";
import {IMajorityVotingBaseExtended} from "../src/interfaces/IMajorityVotingBaseExtended.sol";
import {DaoBuilder} from "./builders/DaoBuilder.sol";
import {TestBase} from "./lib/TestBase.sol";

contract LockToVoteExtendedTest is TestBase {
    DAO internal dao;
    LockToVotePlugin internal plugin;
    LockManagerERC20 internal lockManager;
    IERC20 internal token;

    Action[] internal actions;

    event ProposalCreatedWithActions(
        uint256 indexed proposalId,
        address indexed creator,
        uint64 startDate,
        uint64 endDate,
        bytes metadata,
        Action[] actions,
        bytes32 indexed actionsHash,
        uint256 allowFailureMap
    );

    event ProposalCreatedWithActionHash(
        uint256 indexed proposalId,
        address indexed creator,
        uint64 startDate,
        uint64 endDate,
        bytes metadata,
        bytes32 indexed actionsHash,
        uint256 allowFailureMap
    );

    function setUp() public {
        vm.warp(1 days);
        vm.roll(100);

        (dao, plugin, lockManager, token) =
            new DaoBuilder().withTokenHolder(alice, 1 ether).withVotingPlugin().withProposer(alice).build();

        dao.grant(address(plugin), alice, plugin.EXECUTE_PROPOSAL_PERMISSION_ID());
        vm.deal(address(dao), 1 ether);
        actions.push(Action({to: david, value: 1 ether, data: bytes("")}));
    }

    function test_CreatesHashBackedProposalAndEmitsActions() external {
        bytes memory metadata = "ipfs://hash-backed";
        uint256 allowFailureMap = 1;
        bytes32 actionsHash = plugin.hashActions(actions);
        uint256 expectedProposalId = _expectedProposalId(actionsHash, metadata);

        vm.expectEmit(true, true, true, true, address(plugin));
        emit ProposalCreatedWithActions(
            expectedProposalId,
            alice,
            uint64(block.timestamp),
            uint64(block.timestamp + plugin.proposalDuration()),
            metadata,
            actions,
            actionsHash,
            allowFailureMap
        );

        vm.prank(alice);
        uint256 proposalId = plugin.createProposal(metadata, actions, 0, 0, allowFailureMap);

        assertEq(proposalId, expectedProposalId);
        assertEq(plugin.proposalExecutionHash(proposalId), actionsHash);

        (,,,, Action[] memory storedActions, uint256 storedFailureMap,) = plugin.getProposal(proposalId);
        assertEq(storedActions.length, 0);
        assertEq(storedFailureMap, allowFailureMap);
    }

    function test_CreatesProposalAndEmitsOnlyActionHash() external {
        bytes memory metadata = "ipfs://private-preimage";
        bytes32 actionsHash = plugin.hashActions(actions);
        uint256 expectedProposalId = _expectedProposalId(actionsHash, metadata);

        vm.expectEmit(true, true, true, true, address(plugin));
        emit ProposalCreatedWithActionHash(
            expectedProposalId,
            alice,
            uint64(block.timestamp),
            uint64(block.timestamp + plugin.proposalDuration()),
            metadata,
            actionsHash,
            0
        );

        vm.prank(alice);
        uint256 proposalId = plugin.createProposal(metadata, actionsHash, 0, 0, 0);

        (,,,, Action[] memory storedActions,,) = plugin.getProposal(proposalId);
        assertEq(storedActions.length, 0);
        assertEq(plugin.proposalExecutionHash(proposalId), actionsHash);
    }

    function test_ExecutesHashBackedProposalWithSuppliedActions() external {
        bytes32 actionsHash = plugin.hashActions(actions);
        vm.prank(alice);
        uint256 proposalId = plugin.createProposal("ipfs://execute", actionsHash, 0, 0, 0);
        _passProposal(proposalId);

        assertEq(david.balance, 0);
        vm.prank(alice);
        plugin.execute(proposalId, actions);

        (, bool executed,,,,,) = plugin.getProposal(proposalId);
        assertTrue(executed);
        assertEq(david.balance, 1 ether);
        assertEq(lockManager.knownProposalIdsLength(), 0);
    }

    function test_RevertsWhenSuppliedActionsDoNotMatch() external {
        vm.prank(alice);
        uint256 proposalId = plugin.createProposal("ipfs://execute", actions, 0, 0, 0);
        _passProposal(proposalId);

        Action[] memory differentActions = new Action[](1);
        differentActions[0] = Action({to: bob, value: 1 ether, data: bytes("")});

        bytes32 expectedHash = plugin.hashActions(actions);
        bytes32 actualHash = plugin.hashActions(differentActions);
        vm.expectRevert(
            abi.encodeWithSelector(
                MajorityVotingBase.ActionsHashMismatch.selector, proposalId, expectedHash, actualHash
            )
        );
        vm.prank(alice);
        plugin.execute(proposalId, differentActions);
    }

    function test_HashBackedProposalRequiresExecutionPayload() external {
        vm.prank(alice);
        uint256 proposalId = plugin.createProposal("ipfs://execute", actions, 0, 0, 0);
        _passProposal(proposalId);

        vm.expectRevert(abi.encodeWithSelector(MajorityVotingBase.ActionPayloadRequired.selector, proposalId));
        vm.prank(alice);
        plugin.execute(proposalId);
    }

    function test_StandardProposalRejectsSuppliedExecutionPayload() external {
        vm.prank(alice);
        uint256 proposalId = plugin.createProposal("ipfs://standard", actions, 0, 0, bytes(""));
        _passProposal(proposalId);

        vm.expectRevert(abi.encodeWithSelector(MajorityVotingBase.ProposalNotHashBacked.selector, proposalId));
        vm.prank(alice);
        plugin.execute(proposalId, actions);
    }

    function test_RevertsWhenCreatingWithZeroActionHash() external {
        vm.expectRevert(MajorityVotingBase.ZeroActionsHash.selector);
        vm.prank(alice);
        plugin.createProposal("ipfs://invalid", bytes32(0), 0, 0, 0);
    }

    function test_ExtendedInterfaceIsSupported() external view {
        assertTrue(plugin.supportsInterface(type(IMajorityVotingBaseExtended).interfaceId));
    }

    function _expectedProposalId(bytes32 _actionsHash, bytes memory _metadata) internal view returns (uint256) {
        bytes32 salt = keccak256(abi.encode(_actionsHash, _metadata));
        return uint256(keccak256(abi.encode(block.chainid, block.number, address(plugin), salt)));
    }

    function _passProposal(uint256 _proposalId) internal {
        vm.startPrank(alice);
        token.approve(address(lockManager), 1 ether);
        lockManager.lock();
        lockManager.vote(_proposalId, IMajorityVoting.VoteOption.Yes);
        vm.stopPrank();

        vm.warp(block.timestamp + plugin.proposalDuration() + 1);
    }
}
