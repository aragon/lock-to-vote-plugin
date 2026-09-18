// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {Action} from "@aragon/osx/common/executors/IExecutor.sol";

/// @title IMajorityVotingBaseExtended
/// @notice Optional proposal overloads for storing an action hash instead of the actions.
/// @dev Interface-only POC. Existing creation and execution functions retain their stored-action behavior.
interface IMajorityVotingBaseExtended {
    /// @notice Emitted when the actions are published in the creation log but only their hash is stored.
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed creator,
        uint64 startDate,
        uint64 endDate,
        bytes metadata,
        Action[] actions,
        uint256 allowFailureMap,
        bytes32 actionsHash
    );

    /// @notice Creates a proposal, optionally storing only the hash of its actions.
    /// @dev Compute `actionsHash = _hashActions ? keccak256(abi.encode(_actions)) : bytes32(0)`
    /// and pass it, alongside the original arguments, to a shared internal creation function.
    /// The existing creation entry point calls the same internal function with a zero hash.
    /// Keep the existing permission, action validation, proposal ID, voting settings and LockManager logic.
    /// With a zero hash, store the actions and emit the original `IProposal.ProposalCreated` event.
    /// Otherwise, store only the hash in a proposal-ID mapping and emit this extended event with actions and hash.
    /// If the mapping is added to the upgradeable base, consume one slot from its storage gap.
    /// Keep storing the proposal's failure map and execution target configuration as before.
    /// @param _endDate Unused; the implementation computes the end date. Set to zero.
    /// @param _data ABI-encoded `uint256 allowFailureMap`, or empty bytes for zero.
    function createProposal(
        bytes memory _metadata,
        Action[] memory _actions,
        uint64 _startDate,
        uint64 _endDate,
        bytes memory _data,
        bool _hashActions
    ) external returns (uint256 proposalId);

    /// @notice Executes a hash-backed proposal after verifying the supplied actions against its commitment.
    /// @dev Apply the existing execution permission and proposal eligibility checks, then require a nonzero
    /// stored hash equal to `keccak256(abi.encode(_actions))`. Mark the proposal executed before external calls,
    /// execute the supplied actions using its stored failure map and target configuration, emit `ProposalExecuted`,
    /// and notify the LockManager as usual. The original `execute(proposalId)` must reject proposals with a
    /// nonzero stored hash so they cannot execute an empty stored action array.
    function execute(uint256 _proposalId, Action[] calldata _actions) external;
}
