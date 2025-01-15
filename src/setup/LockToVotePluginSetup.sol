// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {DAO} from "@aragon/osx/src/core/dao/DAO.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {PluginSetup, IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/PluginSetup.sol";
import {LockManager} from "../LockManager.sol";
import {LockToApprovePlugin} from "../LockToApprovePlugin.sol";
import {LockToVotePlugin} from "../LockToVotePlugin.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title LockToApprovePluginSetup
/// @author Aragon Association - 2022-2024
/// @notice The setup contract of the `LockToApprovePlugin` contract.
/// @custom:security-contact sirt@aragon.org
contract LockToApprovePluginSetup is PluginSetup {
    using Address for address;
    using Clones for address;
    using ERC165Checker for address;

    enum PluginMode {
        Approval,
        Voting
    }

    /// @notice The address of the `LockManager` implementation.
    LockManager private immutable lockManagerBase;

    /// @notice The address of the `LockToVotePlugin` implementation.
    LockToVotePlugin private immutable lockToVotePluginBase;

    /// @notice The address of the `LockToApprovePlugin` implementation.
    LockToApprovePlugin private immutable lockToApprovePluginBase;

    struct InstallationParameters {
        PluginMode pluginMode;
        LockManager.LockManagerSettings lockManagerSettings;
        LockToApprovePlugin.PluginSettings approvalSettings;
        LockToVotePlugin.VotingSettings votingSettings;
        uint64 minDuration;
        address createProposalCaller;
        address executeCaller;
        IERC20 token;
        IERC20 underlyingToken;
    }

    /// @notice Thrown if token address is passed which is not a token.
    /// @param token The token address
    error TokenNotContract(address token);

    /// @notice Thrown if token address is not ERC20.
    /// @param token The token address
    error TokenNotERC20(address token);

    /// @notice Thrown if passed helpers array is of wrong length.
    /// @param length The array length of passed helpers.
    error WrongHelpersArrayLength(uint256 length);

    /// @notice The contract constructor deploying the implementation contracts to use.
    constructor() {
        lockManagerBase = new LockManager();
        lockToApprovePluginBase = new LockToApprovePlugin();
        lockToVotePluginBase = new LockToVotePlugin();
    }

    /// @inheritdoc IPluginSetup
    function prepareInstallation(
        address _dao,
        bytes calldata _installParameters
    )
        external
        returns (address plugin, PreparedSetupData memory preparedSetupData)
    {
        // Decode `_installParameters` to extract the params needed for deploying and initializing `LockToVotePlugin` contract,
        // and the required helpers
        InstallationParameters
            memory installationParams = decodeInstallationParams(
                _installParameters
            );

        // Prepare helpers.
        address[] memory helpers = new address[](3);

        helpers[0] = address(
            new LockManager(
                dao,
                LockManagerSettings(unlockMode),
                lockableToken,
                underlyingToken
            )
        );

        if (!installationParams.token.isContract()) {
            revert TokenNotContract(installationParams.token);
        } else if (!_supportsErc20(installationParams.token)) {
            revert TokenNotERC20(installationParams.token);
        }

        if (installationParams.underlyingToken != address(0)) {
            if (!installationParams.underlyingToken.isContract()) {
                revert TokenNotContract(installationParams.underlyingToken);
            } else if (!_supportsErc20(installationParams.underlyingToken)) {
                revert TokenNotERC20(installationParams.underlyingToken);
            }
        }

        helpers[1] = installationParams.token;
        helpers[2] = installationParams.underlyingToken;

        // Prepare and deploy plugin proxy.
        if (installationParams.pluginMode == PluginMode.Approval) {
            plugin = createERC1967Proxy(
                address(lockToApprovePluginBase),
                abi.encodeCall(
                    LockToApprovePlugin.initialize,
                    (
                        IDAO(_dao),
                        installationParams.approvalSettings,
                        IVotesUpgradeable(token)
                    )
                )
            );
        } else {
            plugin = createERC1967Proxy(
                address(lockToVotePluginBase),
                abi.encodeCall(
                    LockToVotePlugin.initialize,
                    (
                        IDAO(_dao),
                        installationParams.votingSettings,
                        IVotesUpgradeable(token)
                    )
                )
            );
        }
        LockManager(helpers[0]).setPluginAddress(plugin);

        // Request the permissions to be granted
        PermissionLib.MultiTargetPermission[]
            memory permissions = new PermissionLib.MultiTargetPermission[](7);

        // The DAO can update the plugin settings
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            /// @dev lockToVotePluginBase and lockToApprovePluginBase return the same value for UPDATE_VOTING_SETTINGS_PERMISSION_ID
            permissionId: lockToVotePluginBase
                .UPDATE_VOTING_SETTINGS_PERMISSION_ID()
        });
        // The DAO can upgrade the plugin implementation
        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            /// @dev lockToVotePluginBase and lockToApprovePluginBase return the same value for UPGRADE_PLUGIN_PERMISSION_ID
            permissionId: lockToVotePluginBase.UPGRADE_PLUGIN_PERMISSION_ID()
        });

        // Grant `EXECUTE_PERMISSION` of the DAO to the plugin.
        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _dao,
            who: plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: DAO(payable(_dao)).EXECUTE_PERMISSION_ID()
        });

        // Allow createProposal calls on createProposalCaller
        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: createProposalCaller,
            condition: PermissionLib.NO_CONDITION,
            permissionId: lockToVotePluginBase.CREATE_PROPOSAL_PERMISSION_ID()
        });

        // Grant `SET_TARGET_CONFIG_PERMISSION_ID` of the DAO to the plugin.
        permissions[3] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: lockToVotePluginBase.SET_TARGET_CONFIG_PERMISSION_ID()
        });

        // Grant `SET_METADATA_PERMISSION_ID` of the DAO to the plugin.
        permissions[4] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: lockToVotePluginBase.SET_METADATA_PERMISSION_ID()
        });

        // Grant `EXECUTE_PROPOSAL_PERMISSION_ID` to the given address (could be ANY_ADDR)
        permissions[5] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: executeCaller,
            condition: PermissionLib.NO_CONDITION,
            permissionId: lockToVotePluginBase.EXECUTE_PROPOSAL_PERMISSION_ID()
        });

        permissions[6] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: helpers[0], // Lock Manager
            condition: PermissionLib.NO_CONDITION,
            permissionId: lockToVotePluginBase.LOCK_MANAGER_PERMISSION_ID()
        });

        preparedSetupData.helpers = helpers;
        preparedSetupData.permissions = permissions;
    }

    // /// @inheritdoc IPluginSetup
    // function prepareUninstallation(
    //     address _dao,
    //     SetupPayload calldata _payload
    // )
    //     external
    //     view
    //     returns (PermissionLib.MultiTargetPermission[] memory permissions)
    // {
    //     // Prepare permissions.
    //     uint256 helperLength = _payload.currentHelpers.length;
    //     if (helperLength != 1) {
    //         revert WrongHelpersArrayLength({length: helperLength});
    //     }
    //     // token can be either GovernanceERC20, GovernanceWrappedERC20, or IVotesUpgradeable, which
    //     // does not follow the GovernanceERC20 and GovernanceWrappedERC20 standard.
    //     address token = _payload.currentHelpers[0];
    //     bool isGovernanceERC20 = _supportsErc20(token) &&
    //         _supportsIVotes(token) &&
    //         !_supportsIGovernanceWrappedERC20(token);
    //     permissions = new PermissionLib.MultiTargetPermission[](
    //         isGovernanceERC20 ? 4 : 3
    //     );
    //     // Set permissions to be Revoked.
    //     permissions[0] = PermissionLib.MultiTargetPermission({
    //         operation: PermissionLib.Operation.Revoke,
    //         where: _payload.plugin,
    //         who: _dao,
    //         condition: PermissionLib.NO_CONDITION,
    //         permissionId: lockToVotePluginBase
    //             .UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
    //     });
    //     permissions[1] = PermissionLib.MultiTargetPermission({
    //         operation: PermissionLib.Operation.Revoke,
    //         where: _payload.plugin,
    //         who: _dao,
    //         condition: PermissionLib.NO_CONDITION,
    //         permissionId: lockToVotePluginBase.UPGRADE_PLUGIN_PERMISSION_ID()
    //     });
    //     permissions[2] = PermissionLib.MultiTargetPermission({
    //         operation: PermissionLib.Operation.Revoke,
    //         where: _dao,
    //         who: _payload.plugin,
    //         condition: PermissionLib.NO_CONDITION,
    //         permissionId: DAO(payable(_dao)).EXECUTE_PERMISSION_ID()
    //     });
    //     // Note: It no longer matters if proposers can still create proposals
    //     // Revocation of permission is necessary only if the deployed token is GovernanceERC20,
    //     // as GovernanceWrapped does not possess this permission. Only return the following
    //     // if it's type of GovernanceERC20, otherwise revoking this permission wouldn't have any effect.
    //     if (isGovernanceERC20) {
    //         permissions[3] = PermissionLib.MultiTargetPermission({
    //             operation: PermissionLib.Operation.Revoke,
    //             where: token,
    //             who: _dao,
    //             condition: PermissionLib.NO_CONDITION,
    //             permissionId: GovernanceERC20(token).MINT_PERMISSION_ID()
    //         });
    //     }
    // }

    /// @inheritdoc IPluginSetup
    function implementation() external view virtual override returns (address) {
        return address(lockToVotePluginBase);
    }

    /// @notice Encodes the given installation parameters into a byte array
    function encodeInstallationParams(
        InstallationParameters memory installationParams
    ) external pure returns (bytes memory) {
        return abi.encode(installationParams);
    }

    /// @notice Decodes the given byte array into the original installation parameters
    function decodeInstallationParams(
        bytes memory _data
    ) public pure returns (InstallationParameters memory installationParams) {
        installationParams = abi.decode(_data, (InstallationParameters));
    }

    /// @notice Unsatisfiably determines if the contract is an ERC20 token.
    /// @dev It's important to first check whether token is a contract prior to this call.
    /// @param token The token address
    function _supportsErc20(address token) private view returns (bool) {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeCall(IERC20Upgradeable.balanceOf, (address(this)))
        );
        if (!success || data.length != 0x20) return false;

        (success, data) = token.staticcall(
            abi.encodeCall(IERC20Upgradeable.totalSupply, ())
        );
        if (!success || data.length != 0x20) return false;

        (success, data) = token.staticcall(
            abi.encodeCall(
                IERC20Upgradeable.allowance,
                (address(this), address(this))
            )
        );
        if (!success || data.length != 0x20) return false;

        return true;
    }
}
