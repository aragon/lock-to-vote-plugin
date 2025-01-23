// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {DAO} from "@aragon/osx/src/core/dao/DAO.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {PluginSetup, IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/PluginSetup.sol";
import {LockToApprovePlugin} from "../LockToApprovePlugin.sol";
import {LockToVotePlugin} from "../LockToVotePlugin.sol";
import {LockManager} from "../LockManager.sol";
import {LockManagerSettings, UnlockMode, PluginMode} from "../../src/interfaces/ILockManager.sol";
import {ILockToVoteBase} from "../../src/interfaces/ILockToVoteBase.sol";
import {MinVotingPowerCondition} from "../../src/conditions/MinVotingPowerCondition.sol";
import {createProxyAndCall} from "../util/proxy.sol";

/// @title LockToVotePluginSetup
/// @author Aragon Association - 2022-2024
/// @notice The setup contract of the `LockToApprovePlugin` contract.
/// @custom:security-contact sirt@aragon.org
contract LockToVotePluginSetup is PluginSetup {
    using Address for address;
    using Clones for address;
    using ERC165Checker for address;

    /// @notice The address of the `LockManager` implementation.
    LockManager private immutable lockManagerBase;

    /// @notice The address of the `LockToApprovePlugin` implementation.
    LockToApprovePlugin private immutable lockToApprovePluginBase;

    /// @notice The address of the `LockToVotePlugin` implementation.
    LockToVotePlugin private immutable lockToVotePluginBase;

    struct InstallationParameters {
        PluginMode pluginMode;
        UnlockMode unlockMode;
        bytes pluginMetadata;
        IPlugin.TargetConfig targetConfig;
        LockToApprovePlugin.ApprovalSettings approvalSettings;
        LockToVotePlugin.VotingSettings votingSettings;
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
        lockManagerBase = new LockManager(
            IDAO(address(0)),
            LockManagerSettings(UnlockMode(0), PluginMode(0)),
            IERC20(address(0)),
            IERC20(address(0))
        );
        lockToApprovePluginBase = new LockToApprovePlugin();
        lockToVotePluginBase = new LockToVotePlugin();
    }

    /// @inheritdoc IPluginSetup
    function prepareInstallation(
        address _dao,
        bytes calldata _installParameters
    ) external returns (address plugin, PreparedSetupData memory preparedSetupData) {
        // Decode `_installParameters` to extract the params needed for deploying and initializing `LockToVotePlugin` contract,
        // and the required helpers
        InstallationParameters memory installationParams = decodeInstallationParams(_installParameters);

        // Prepare helpers.
        address[] memory helpers = new address[](3);

        // Lock Manager
        helpers[0] = address(
            new LockManager(
                IDAO(_dao),
                LockManagerSettings(installationParams.unlockMode, installationParams.pluginMode),
                installationParams.token,
                installationParams.underlyingToken
            )
        );

        if (!address(installationParams.token).isContract()) {
            revert TokenNotContract(address(installationParams.token));
        } else if (!_supportsErc20(address(installationParams.token))) {
            revert TokenNotERC20(address(installationParams.token));
        }

        if (address(installationParams.underlyingToken) != address(0)) {
            if (!address(installationParams.underlyingToken).isContract()) {
                revert TokenNotContract(address(installationParams.underlyingToken));
            } else if (!_supportsErc20(address(installationParams.underlyingToken))) {
                revert TokenNotERC20(address(installationParams.underlyingToken));
            }
        }

        helpers[1] = address(installationParams.token);
        helpers[2] = address(installationParams.underlyingToken);

        // Prepare and deploy plugin proxy.
        if (installationParams.pluginMode == PluginMode.Approval) {
            plugin = createProxyAndCall(
                address(lockToApprovePluginBase),
                abi.encodeCall(
                    LockToApprovePlugin.initialize,
                    (
                        IDAO(_dao),
                        LockManager(helpers[0]),
                        installationParams.approvalSettings,
                        installationParams.targetConfig,
                        installationParams.pluginMetadata
                    )
                )
            );
        } else {
            plugin = createProxyAndCall(
                address(lockToVotePluginBase),
                abi.encodeCall(
                    LockToVotePlugin.initialize,
                    (
                        IDAO(_dao),
                        LockManager(helpers[0]),
                        installationParams.votingSettings,
                        installationParams.targetConfig,
                        installationParams.pluginMetadata
                    )
                )
            );
        }
        LockManager(helpers[0]).setPluginAddress(ILockToVoteBase(plugin));

        // Condition
        MinVotingPowerCondition minVotingPowerCondition = new MinVotingPowerCondition(ILockToVoteBase(plugin));

        // Request the permissions to be granted
        PermissionLib.MultiTargetPermission[] memory permissions = new PermissionLib.MultiTargetPermission[](8);

        // The plugin can execute on the DAO
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _dao,
            who: plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: DAO(payable(_dao)).EXECUTE_PERMISSION_ID()
        });

        // The DAO can update the plugin settings
        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            /// @dev lockToVotePluginBase and lockToApprovePluginBase return the same value for UPDATE_VOTING_SETTINGS_PERMISSION_ID
            permissionId: lockToVotePluginBase.UPDATE_SETTINGS_PERMISSION_ID()
        });

        // The DAO can upgrade the plugin implementation
        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            /// @dev lockToVotePluginBase and lockToApprovePluginBase return the same value for UPGRADE_PLUGIN_PERMISSION_ID
            permissionId: lockToVotePluginBase.UPGRADE_PLUGIN_PERMISSION_ID()
        });

        // The DAO can update the target config
        permissions[3] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: lockToVotePluginBase.SET_TARGET_CONFIG_PERMISSION_ID()
        });

        // The DAO can set update the plugin metadata
        permissions[4] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: lockToVotePluginBase.SET_METADATA_PERMISSION_ID()
        });

        // createProposalCaller can create proposals on the plugin
        permissions[5] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: installationParams.createProposalCaller,
            condition: address(minVotingPowerCondition),
            permissionId: lockToVotePluginBase.CREATE_PROPOSAL_PERMISSION_ID()
        });

        // The LockManager can vote/approve on the plugin
        permissions[6] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: helpers[0], // Lock Manager
            condition: PermissionLib.NO_CONDITION,
            permissionId: lockToVotePluginBase.LOCK_MANAGER_PERMISSION_ID()
        });

        // executeCaller (possibly ANY_ADDR) can call execute() on the plugin
        permissions[7] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: installationParams.executeCaller,
            condition: PermissionLib.NO_CONDITION,
            permissionId: lockToVotePluginBase.EXECUTE_PROPOSAL_PERMISSION_ID()
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
    function implementation() public view virtual override returns (address) {
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
        (bool success, bytes memory data) = token.staticcall(abi.encodeCall(IERC20.balanceOf, (address(this))));
        if (!success || data.length != 0x20) return false;

        (success, data) = token.staticcall(abi.encodeCall(IERC20.totalSupply, ()));
        if (!success || data.length != 0x20) return false;

        (success, data) = token.staticcall(abi.encodeCall(IERC20.allowance, (address(this), address(this))));
        if (!success || data.length != 0x20) return false;

        return true;
    }
}
