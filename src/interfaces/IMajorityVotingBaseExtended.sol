// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {Action} from "@aragon/osx/common/executors/IExecutor.sol";

/// @title IMajorityVotingBaseExtended
/// @notice Optional hash-backed proposal creation and execution functions for majority voting plugins.
/// @dev Hash-backed proposals commit to `keccak256(abi.encode(actions))` instead of storing actions.
interface IMajorityVotingBaseExtended {
    /// @notice Emitted when the actions are published in the creation log but only their hash is stored.
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

    /// @notice Emitted when only a precomputed actions hash is published and stored.
    event ProposalCreatedWithActionHash(
        uint256 indexed proposalId,
        address indexed creator,
        uint64 startDate,
        uint64 endDate,
        bytes metadata,
        bytes32 indexed actionsHash,
        uint256 allowFailureMap
    );

    /// @notice Creates a hash-backed proposal while publishing its actions in the creation event.
    /// @dev This overload uses a direct `uint256` failure map to distinguish it from `IProposal.createProposal`.
    function createProposal(
        bytes memory _metadata,
        Action[] memory _actions,
        uint64 _startDate,
        uint64 _endDate,
        uint256 _allowFailureMap
    ) external returns (uint256 proposalId);

    /// @notice Creates a hash-backed proposal without publishing its actions.
    /// @param _actionsHash The `keccak256(abi.encode(actions))` commitment supplied again at execution.
    function createProposal(
        bytes memory _metadata,
        bytes32 _actionsHash,
        uint64 _startDate,
        uint64 _endDate,
        uint256 _allowFailureMap
    ) external returns (uint256 proposalId);

    /// @notice Executes a hash-backed proposal after verifying the supplied actions against its commitment.
    function execute(uint256 _proposalId, Action[] calldata _actions) external;

    /// @notice Returns the action commitment for a hash-backed proposal, or zero for a standard proposal.
    function proposalExecutionHash(uint256 _proposalId) external view returns (bytes32);

    /// @notice Returns the canonical commitment used by hash-backed proposal creation and execution.
    function hashActions(Action[] calldata _actions) external pure returns (bytes32);
}
