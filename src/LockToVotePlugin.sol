// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import {ILockManager} from "./interfaces/ILockManager.sol";
import {ILockToVote, LockToVoteSettings, Proposal} from "./interfaces/ILockToVote.sol";
import {IDAO} from "@aragon/osx-commons-contracts/dao/IDAO.sol";
import {ProposalUpgradeable} from "@aragon/osx-commons-contracts/plugin/extensions/proposal/ProposalUpgradeable.sol";
import {IMembership} from "@aragon/osx-commons-contracts/plugin/extensions/membership/IMembership.sol";
import {IProposal} from "@aragon/osx-commons-contracts/plugin/extensions/proposal/IProposal.sol";
import {Action} from "@aragon/osx-commons-contracts/executors/IExecutor.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/plugin/IPlugin.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx-commons-contracts/plugin/PluginUUPSUpgradeable.sol";
import {MetadataExtensionUpgradeable} from "@aragon/osx-commons-contracts/utils/metadata/MetadataExtensionUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

contract LockToVotePlugin is
    ILockToVote,
    PluginUUPSUpgradeable,
    ProposalUpgradeable,
    MetadataExtensionUpgradeable,
    IMembership
{
    using SafeCastUpgradeable for uint256;

    LockToVoteSettings public settings;

    ILockManager public lockManager;

    mapping(uint256 => Proposal) proposals;

    /// @notice The ID of the permission required to call the `updateVotingSettings` function.
    bytes32 public constant UPDATE_VOTING_SETTINGS_PERMISSION_ID =
        keccak256("UPDATE_VOTING_SETTINGS_PERMISSION");

    /// @notice The ID of the permission required to call the `createProposal` functions.
    bytes32 public constant CREATE_PROPOSAL_PERMISSION_ID =
        keccak256("CREATE_PROPOSAL_PERMISSION");

    /// @notice The ID of the permission required to call the `execute` function.
    bytes32 public constant EXECUTE_PROPOSAL_PERMISSION_ID =
        keccak256("EXECUTE_PROPOSAL_PERMISSION");

    /// @notice Initializes the component.
    /// @dev This method is required to support [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822).
    /// @param _dao The IDAO interface of the associated DAO.
    /// @param _pluginSettings The voting settings.
    /// @param _targetConfig Configuration for the execution target, specifying the target address and operation type
    ///     (either `Call` or `DelegateCall`). Defined by `TargetConfig` in the `IPlugin` interface,
    ///     part of the `osx-commons-contracts` package, added in build 3.
    /// @param _pluginMetadata The plugin specific information encoded in bytes.
    ///     This can also be an ipfs cid encoded in bytes.
    function initialize(
        IDAO _dao,
        ILockManager _lockManager,
        LockToVoteSettings calldata _pluginSettings,
        IPlugin.TargetConfig calldata _targetConfig,
        bytes calldata _pluginMetadata
    ) external onlyCallAtInitialization reinitializer(1) {
        __PluginUUPSUpgradeable_init(_dao);
        _updatePluginSettings(_pluginSettings);
        _setTargetConfig(_targetConfig);
        _setMetadata(_pluginMetadata);

        lockManager = _lockManager;

        emit MembershipContractAnnounced({
            definingContract: address(_lockManager.token())
        });
    }

    /// @notice Checks if this or the parent contract supports an interface by its ID.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(
        bytes4 _interfaceId
    )
        public
        view
        virtual
        override(
            MetadataExtensionUpgradeable,
            PluginUUPSUpgradeable,
            ProposalUpgradeable
        )
        returns (bool)
    {
        return
            _interfaceId == type(IMembership).interfaceId ||
            _interfaceId == type(ILockToVote).interfaceId ||
            super.supportsInterface(_interfaceId);
    }

    /// @inheritdoc IProposal
    /// @dev Requires the `CREATE_PROPOSAL_PERMISSION_ID` permission.
    function createProposal(
        bytes calldata _metadata,
        Action[] calldata _actions,
        uint64 _startDate,
        uint64 _endDate,
        bytes memory _data
    )
        external
        auth(CREATE_PROPOSAL_PERMISSION_ID)
        returns (uint256 proposalId)
    {
        uint256 _allowFailureMap;

        if (_data.length != 0) {
            (_allowFailureMap) = abi.decode(_data, (uint256));
        }

        if (lockManager.token().totalSupply() == 0) {
            revert NoVotingPower();
        }

        (_startDate, _endDate) = _validateProposalDates(_startDate, _endDate);

        proposalId = _createProposalId(
            keccak256(abi.encode(_actions, _metadata))
        );

        // Store proposal related information
        Proposal storage proposal_ = proposals[proposalId];

        if (proposal_.parameters.startDate != 0) {
            revert ProposalAlreadyExists(proposalId);
        }

        proposal_.parameters.startDate = _startDate;
        proposal_.parameters.endDate = _endDate;
        proposal_.parameters.minApprovalRatio = settings.minApprovalRatio;

        proposal_.targetConfig = getTargetConfig();

        // Reduce costs
        if (_allowFailureMap != 0) {
            proposal_.allowFailureMap = _allowFailureMap;
        }

        for (uint256 i; i < _actions.length; ) {
            proposal_.actions.push(_actions[i]);
            unchecked {
                ++i;
            }
        }

        emit ProposalCreated(
            proposalId,
            _msgSender(),
            _startDate,
            _endDate,
            _metadata,
            _actions,
            _allowFailureMap
        );
    }

    /// @inheritdoc IProposal
    function customProposalParamsABI()
        external
        pure
        override
        returns (string memory)
    {
        return "(uint256 allowFailureMap)";
    }

    function votingToken() external view returns (IERC20) {
        return lockManager.token();
    }

    // Internal helpers

    /// @notice Validates and returns the proposal dates.
    /// @param _start The start date of the proposal.
    ///     If 0, the current timestamp is used and the vote starts immediately.
    /// @param _end The end date of the proposal. If 0, `_start + minDuration` is used.
    /// @return startDate The validated start date of the proposal.
    /// @return endDate The validated end date of the proposal.
    function _validateProposalDates(
        uint64 _start,
        uint64 _end
    ) internal view virtual returns (uint64 startDate, uint64 endDate) {
        uint64 currentTimestamp = block.timestamp.toUint64();

        if (_start == 0) {
            startDate = currentTimestamp;
        } else {
            startDate = _start;

            if (startDate < currentTimestamp) {
                revert DateOutOfBounds({
                    limit: currentTimestamp,
                    actual: startDate
                });
            }
        }

        // Since `minDuration` is limited to 1 year,
        // `startDate + minDuration` can only overflow if the `startDate` is after `type(uint64).max - minDuration`.
        // In this case, the proposal creation will revert and another date can be picked.
        uint64 earliestEndDate = startDate + settings.minProposalDuration;

        if (_end == 0) {
            endDate = earliestEndDate;
        } else {
            endDate = _end;

            if (endDate < earliestEndDate) {
                revert DateOutOfBounds({
                    limit: earliestEndDate,
                    actual: endDate
                });
            }
        }
    }

    function _updatePluginSettings(
        LockToVoteSettings memory _newSettings
    ) internal {
        settings.minApprovalRatio = _newSettings.minApprovalRatio;
        settings.minProposalDuration = _newSettings.minProposalDuration;
    }
}
