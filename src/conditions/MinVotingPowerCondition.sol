// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {ILockToGovernBase} from "../interfaces/ILockToGovernBase.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPermissionCondition} from "@aragon/osx-commons-contracts/src/permission/condition/IPermissionCondition.sol";
import {PermissionCondition} from "@aragon/osx-commons-contracts/src/permission/condition/PermissionCondition.sol";

/// @title MinVotingPowerCondition
/// @author Aragon X - 2024
/// @notice Checks if an account's voting power or token balance meets the threshold defined on the given plugin.
/// @custom:security-contact sirt@aragon.org
contract MinVotingPowerCondition is PermissionCondition {
    /// @notice The address of the `ILockToGovernBase` plugin used to fetch the settings from.
    ILockToGovernBase public immutable plugin;

    /// @notice The `IERC20` token used to check token balance.
    IERC20 public immutable token;

    /// @notice The (optional) underlying token from which `token` originates.
    IERC20 public immutable underlyingToken;

    /// @notice Initializes the contract with the `ILockToGovernBase` plugin address and caches the associated token.
    /// @param _plugin The address of the `ILockToGovernBase` plugin.
    constructor(ILockToGovernBase _plugin) {
        plugin = _plugin;
        token = _plugin.token();

        /// Checking the underlying token as well
        IERC20 _underlyingToken = _plugin.underlyingToken();
        /// @dev If the address is the same as the voting token, it means that there is no underlying token.
        if (address(_underlyingToken) != address(token)) {
            underlyingToken = _underlyingToken;
        }
    }

    /// @inheritdoc IPermissionCondition
    /// @dev The function checks both the voting power and token balance to ensure `_who` meets the minimum voting
    ///      threshold defined in the `TokenVoting` plugin. Returns `false` if the minimum requirement is unmet.
    function isGranted(address _where, address _who, bytes32 _permissionId, bytes calldata _data)
        public
        view
        override
        returns (bool)
    {
        (_where, _data, _permissionId);

        uint256 _minProposerVotingPower = plugin.minProposerVotingPower();

        uint256 _callerBalance = token.balanceOf(_who);
        if (address(underlyingToken) != address(0)) {
            _callerBalance += underlyingToken.balanceOf(_who);
        }

        return _callerBalance >= _minProposerVotingPower;
    }
}
