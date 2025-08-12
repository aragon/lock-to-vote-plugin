// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx-commons-contracts/src/plugin/PluginUUPSUpgradeable.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {ILockManager} from "./ILockManager.sol";

/// @title ILockToGovernBase
/// @author Aragon X 2024-2025
interface ILockToGovernBase {
    /// @notice Returns the address of the manager contract, which holds the locked balances and the allocated vote balances.
    function lockManager() external view returns (ILockManager);

    /// @notice Returns the address of the token contract used to determine the voting power.
    /// @return The address of the token used for voting.
    function token() external view returns (IERC20);

    /// @notice Returns whether the account has voted for the proposal.
    /// @param proposalId The ID of the proposal.
    /// @param voter The account address to be checked.
    /// @return The amount of balance that has been allocated to the proposal by the given account.
    function usedVotingPower(uint256 proposalId, address voter) external view returns (uint256);

    /// @notice Returns the minimum voting power required to create a proposal stored in the voting settings.
    /// @return The minimum voting power required to create a proposal.
    function minProposerVotingPower() external view returns (uint256);

    /// @notice Returns wether a proposal is open or not.
    /// @param _proposalId The ID of the proposal.
    /// @return True if the proposal is open, false otherwise.
    function isProposalOpen(uint256 _proposalId) external view returns (bool);

    /// @notice Returns wether a proposal has ended or not.
    /// @param _proposalId The ID of the proposal.
    /// @return True if the proposal is executed or past the endDate, false otherwise.
    function isProposalEnded(uint256 _proposalId) external view returns (bool);
}
