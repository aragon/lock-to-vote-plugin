// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import {ILockManager, UnlockMode} from "./interfaces/ILockManager.sol";
import {ILockToVoteBase} from "./interfaces/ILockToVote.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {LockToVoteBase} from "./base/LockToVoteBase.sol";
import {ILockToApprove} from "./interfaces/ILockToApprove.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {ProposalUpgradeable} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/ProposalUpgradeable.sol";
import {IProposal} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx-commons-contracts/src/plugin/PluginUUPSUpgradeable.sol";
import {MetadataExtensionUpgradeable} from "@aragon/osx-commons-contracts/src/utils/metadata/MetadataExtensionUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {_applyRatioCeiled} from "@aragon/osx-commons-contracts/src/utils/math/Ratio.sol";

contract LockToApprovePlugin is
    ILockToApprove,
    Initializable,
    ERC165Upgradeable,
    MetadataExtensionUpgradeable,
    PluginUUPSUpgradeable,
    ProposalUpgradeable,
    LockToVoteBase
{
    using SafeCastUpgradeable for uint256;

    /// @notice A container for the approval settings that will be applied as parameters on proposal creation.
    /// @param minApprovalRatio The minimum approval ratio required to approve over the total supply.
    ///     Its value has to be in the interval [0, 10^6] defined by `RATIO_BASE = 10**6`.
    /// @param minProposalDuration The minimum duration of the proposal approval stage in seconds.
    struct ApprovalSettings {
        uint32 minApprovalRatio;
        uint64 minProposalDuration;
    }

    /// @notice A container for proposal-related information.
    /// @param executed Whether the proposal is executed or not.
    /// @param parameters The proposal parameters at the time of the proposal creation.
    /// @param approvalTally The vote tally of the proposal.
    /// @param approvals The voting power cast by each voter.
    /// @param actions The actions to be executed when the proposal passes.
    /// @param allowFailureMap A bitmap allowing the proposal to succeed, even if individual actions might revert.
    ///     If the bit at index `i` is 1, the proposal succeeds even if the `i`th action reverts.
    ///     A failure map value of 0 requires every action to not revert.
    /// @param targetConfig Configuration for the execution target, specifying the target address and operation type
    ///     (either `Call` or `DelegateCall`). Defined by `TargetConfig` in the `IPlugin` interface,
    ///     part of the `osx-commons-contracts` package, added in build 3.
    struct Proposal {
        bool executed;
        ProposalParameters parameters;
        uint256 approvalTally;
        mapping(address => uint256) approvals;
        Action[] actions;
        uint256 allowFailureMap;
        IPlugin.TargetConfig targetConfig;
    }

    /// @notice A container for the proposal parameters at the time of proposal creation.
    /// @param minApprovalRatio The approval threshold above which the proposal becomes executable.
    ///     The value has to be in the interval [0, 10^6] defined by `RATIO_BASE = 10**6`.
    /// @param startDate The start date of the proposal vote.
    /// @param endDate The end date of the proposal vote.
    struct ProposalParameters {
        uint32 minApprovalRatio;
        uint64 startDate;
        uint64 endDate;
    }

    /// @notice The ID of the permission required to call the `createProposal` functions.
    bytes32 public constant CREATE_PROPOSAL_PERMISSION_ID = keccak256("CREATE_PROPOSAL_PERMISSION");

    /// @notice The ID of the permission required to call the `execute` function.
    bytes32 public constant EXECUTE_PROPOSAL_PERMISSION_ID = keccak256("EXECUTE_PROPOSAL_PERMISSION");

    /// @notice The ID of the permission required to call the `execute` function.
    bytes32 public constant LOCK_MANAGER_PERMISSION_ID = keccak256("LOCK_MANAGER_PERMISSION");

    /// @notice The ID of the permission required to call the `updateVotingSettings` function.
    bytes32 public constant UPDATE_VOTING_SETTINGS_PERMISSION_ID = keccak256("UPDATE_VOTING_SETTINGS_PERMISSION");

    /// @notice The [ERC-165](https://eips.ethereum.org/EIPS/eip-165) interface ID of the contract.
    bytes4 internal constant LOCK_TO_APPROVE_INTERFACE_ID =
        this.minDuration.selector ^
            this.minProposerVotingPower.selector ^
            this.votingMode.selector ^
            this.totalVotingPower.selector ^
            this.getProposal.selector ^
            this.updateVotingSettings.selector ^
            this.createProposal.selector;

    ApprovalSettings public settings;

    mapping(uint256 => Proposal) proposals;

    event ApprovalCast(uint256 proposalId, address voter, uint256 newVotingPower);
    event ApprovalCleared(uint256 proposalId, address voter);
    event ApprovalSettingsUpdated(uint32 minApprovalRatio, uint64 minProposalDuration);

    error ApprovalForbidden(uint256 proposalId, address voter);
    error DateOutOfBounds(uint256 limit, uint256 actual);

    /// @notice Thrown when a proposal doesn't exist.
    /// @param proposalId The ID of the proposal which doesn't exist.
    error NonexistentProposal(uint256 proposalId);

    /// @notice Thrown if the proposal execution is forbidden.
    /// @param proposalId The ID of the proposal.
    error ProposalExecutionForbidden(uint256 proposalId);

    /// @notice Thrown if the proposal with same actions and metadata already exists.
    /// @param proposalId The id of the proposal.
    error ProposalAlreadyExists(uint256 proposalId);

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
        ApprovalSettings calldata _pluginSettings,
        IPlugin.TargetConfig calldata _targetConfig,
        bytes calldata _pluginMetadata
    ) external onlyCallAtInitialization reinitializer(1) {
        __PluginUUPSUpgradeable_init(_dao);
        _updatePluginSettings(_pluginSettings);
        _setTargetConfig(_targetConfig);
        _setMetadata(_pluginMetadata);
        __LockToVoteBase_init(_lockManager);

        emit MembershipContractAnnounced({definingContract: address(_lockManager.token())});
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
            ERC165Upgradeable,
            MetadataExtensionUpgradeable,
            PluginUUPSUpgradeable,
            ProposalUpgradeable,
            LockToVoteBase
        )
        returns (bool)
    {
        return
            _interfaceId == LOCK_TO_APPROVE_INTERFACE_ID ||
            _interfaceId == type(ILockToApprove).interfaceId ||
            super.supportsInterface(_interfaceId);
    }

    /// @inheritdoc IProposal
    function customProposalParamsABI() external pure override returns (string memory) {
        return "(uint256 allowFailureMap)";
    }

    /// @inheritdoc IProposal
    /// @dev Requires the `CREATE_PROPOSAL_PERMISSION_ID` permission.
    function createProposal(
        bytes calldata _metadata,
        Action[] memory _actions,
        uint64 _startDate,
        uint64 _endDate,
        bytes memory _data
    ) external auth(CREATE_PROPOSAL_PERMISSION_ID) returns (uint256 proposalId) {
        uint256 _allowFailureMap;

        if (_data.length != 0) {
            (_allowFailureMap) = abi.decode(_data, (uint256));
        }

        if (lockManager.token().totalSupply() == 0) {
            revert NoVotingPower();
        }

        /// @dev `minProposerVotingPower` will be checked by the permission condition behind auth(CREATE_PROPOSAL_PERMISSION_ID)

        (_startDate, _endDate) = _validateProposalDates(_startDate, _endDate);

        proposalId = _createProposalId(keccak256(abi.encode(_actions, _metadata)));

        if (_proposalExists(proposalId)) {
            revert ProposalAlreadyExists(proposalId);
        }

        // Store proposal related information
        Proposal storage proposal_ = proposals[proposalId];

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

        emit ProposalCreated(proposalId, _msgSender(), _startDate, _endDate, _metadata, _actions, _allowFailureMap);

        lockManager.proposalCreated(proposalId);
    }

    /// @notice Returns all information for a proposal by its ID.
    /// @param _proposalId The ID of the proposal.
    /// @return open Whether the proposal is open or not.
    /// @return executed Whether the proposal is executed or not.
    /// @return parameters The parameters of the proposal.
    /// @return approvalTally The current tally of the proposal.
    /// @return actions The actions to be executed to the `target` contract address.
    /// @return allowFailureMap The bit map representations of which actions are allowed to revert so tx still succeeds.
    /// @return targetConfig Execution configuration, applied to the proposal when it was created. Added in build 3.
    function getProposal(
        uint256 _proposalId
    )
        public
        view
        virtual
        returns (
            bool open,
            bool executed,
            ProposalParameters memory parameters,
            uint256 approvalTally,
            Action[] memory actions,
            uint256 allowFailureMap,
            TargetConfig memory targetConfig
        )
    {
        Proposal storage proposal_ = proposals[_proposalId];

        open = _isProposalOpen(proposal_);
        executed = proposal_.executed;
        parameters = proposal_.parameters;
        approvalTally = proposal_.approvalTally;
        actions = proposal_.actions;
        allowFailureMap = proposal_.allowFailureMap;
        targetConfig = proposal_.targetConfig;
    }

    /// @inheritdoc ILockToApprove
    function canApprove(uint256 _proposalId, address _voter) external view returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        return _canApprove(proposal_, _voter, lockManager.lockedBalances(_voter));
    }

    /// @inheritdoc ILockToApprove
    function approve(
        uint256 _proposalId,
        address _voter,
        uint256 _currentVotingPower
    ) external auth(LOCK_MANAGER_PERMISSION_ID) {
        Proposal storage proposal_ = proposals[_proposalId];

        if (!_canApprove(proposal_, _voter, _currentVotingPower)) {
            revert ApprovalForbidden(_proposalId, _voter);
        }

        // Add the difference between the new voting power and the current one

        uint256 diff = _currentVotingPower - proposal_.approvals[_voter];
        proposal_.approvalTally += diff;
        proposal_.approvals[_voter] += diff;

        emit ApprovalCast(_proposalId, _voter, _currentVotingPower);

        // Check if we may execute early
        (UnlockMode unlockMode, ) = lockManager.settings();
        if (unlockMode == UnlockMode.STRICT) {
            if (
                _canExecute(proposal_) &&
                dao().hasPermission(address(this), _msgSender(), EXECUTE_PROPOSAL_PERMISSION_ID, _msgData())
            ) {
                _execute(_proposalId, proposal_);
            }
        }
    }

    /// @inheritdoc ILockToApprove
    function clearApproval(uint256 _proposalId, address _voter) external auth(LOCK_MANAGER_PERMISSION_ID) {
        Proposal storage proposal_ = proposals[_proposalId];

        if (proposal_.approvals[_voter] == 0 || !_isProposalOpen(proposal_)) return;

        // Subtract the old votes from the global tally
        proposal_.approvalTally -= proposal_.approvals[_voter];

        // Clear the voting power
        proposal_.approvals[_voter] = 0;

        emit ApprovalCleared(_proposalId, _voter);
    }

    /// @inheritdoc ILockToVoteBase
    function isProposalOpen(uint256 _proposalId) external view returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];
        return _isProposalOpen(proposal_);
    }

    /// @inheritdoc ILockToVoteBase
    function usedVotingPower(uint256 _proposalId, address _voter) public view returns (uint256) {
        return proposals[_proposalId].approvals[_voter];
    }

    /// @inheritdoc IProposal
    function canExecute(uint256 _proposalId) external view returns (bool) {
        if (!_proposalExists(_proposalId)) {
            revert NonexistentProposal(_proposalId);
        }

        Proposal storage proposal_ = proposals[_proposalId];
        return _canExecute(proposal_);
    }

    /// @inheritdoc IProposal
    function hasSucceeded(uint256 _proposalId) external view returns (bool) {
        if (!_proposalExists(_proposalId)) {
            revert NonexistentProposal(_proposalId);
        }

        Proposal storage proposal_ = proposals[_proposalId];
        return _hasSucceeded(proposal_);
    }

    /// @inheritdoc IProposal
    function execute(uint256 _proposalId) external auth(EXECUTE_PROPOSAL_PERMISSION_ID) {
        Proposal storage proposal_ = proposals[_proposalId];

        if (!_canExecute(proposal_)) {
            revert ProposalExecutionForbidden(_proposalId);
        }

        _execute(_proposalId, proposal_);
    }

    /// @notice Updates the LockManager approval settings to the given new values.
    function updatePluginSettings(
        ApprovalSettings calldata _newSettings
    ) external auth(UPDATE_VOTING_SETTINGS_PERMISSION_ID) {
        _updatePluginSettings(_newSettings);
    }

    // Internal helpers

    function _isProposalOpen(Proposal storage proposal_) internal view returns (bool) {
        uint64 currentTime = block.timestamp.toUint64();

        return
            proposal_.parameters.startDate <= currentTime &&
            currentTime < proposal_.parameters.endDate &&
            !proposal_.executed;
    }

    /// @notice Checks if proposal exists or not.
    /// @param _proposalId The ID of the proposal.
    /// @return Returns `true` if proposal exists, otherwise false.
    function _proposalExists(uint256 _proposalId) internal view returns (bool) {
        return proposals[_proposalId].parameters.startDate != 0;
    }

    function _canApprove(
        Proposal storage proposal_,
        address _voter,
        uint256 _newVotingBalance
    ) internal view returns (bool) {
        // The proposal vote hasn't started or has already ended.
        if (!_isProposalOpen(proposal_)) {
            return false;
        }
        // More balance could be added
        else if (_newVotingBalance <= proposal_.approvals[_voter]) {
            return false;
        }

        return true;
    }

    function _canExecute(Proposal storage proposal_) internal view returns (bool) {
        // Verify that the vote has not been executed already.
        if (proposal_.executed) {
            return false;
        }

        return _hasSucceeded(proposal_);
    }

    function _hasSucceeded(Proposal storage proposal_) internal view returns (bool) {
        if (proposal_.approvalTally == 0) {
            // Avoid empty proposals to be reported as succeeded
            return false;
        }
        return proposal_.approvalTally >= _minApprovalTally(proposal_);
    }

    function _minApprovalTally(Proposal storage proposal_) internal view returns (uint256 _minTally) {
        /// @dev Checking against the totalSupply() of the **underlying token**.
        /// @dev LP tokens could have important supply variations and this would impact the value of existing votes, after created.
        /// @dev However, the total supply of the underlying token (USDC, USDT, DAI, etc) will experiment little to no variations in comparison.

        // NOTE: Assuming a 1:1 correlation between token() and underlyingToken()

        _minTally = _applyRatioCeiled(
            lockManager.underlyingToken().totalSupply(),
            proposal_.parameters.minApprovalRatio
        );
    }

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
                revert DateOutOfBounds({limit: currentTimestamp, actual: startDate});
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
                revert DateOutOfBounds({limit: earliestEndDate, actual: endDate});
            }
        }
    }

    function _execute(uint256 _proposalId, Proposal storage proposal_) internal {
        proposal_.executed = true;

        // IProposal's target execution
        _execute(
            proposal_.targetConfig.target,
            bytes32(_proposalId),
            proposal_.actions,
            proposal_.allowFailureMap,
            proposal_.targetConfig.operation
        );

        emit ProposalExecuted(_proposalId);

        // Notify the LockManager to stop tracking this proposal ID
        lockManager.proposalEnded(_proposalId);
    }

    function _updatePluginSettings(ApprovalSettings memory _newSettings) internal {
        settings.minApprovalRatio = _newSettings.minApprovalRatio;
        settings.minProposalDuration = _newSettings.minProposalDuration;
    }

    /// @notice This empty reserved space is put in place to allow future versions to add
    /// new variables without shifting down storage in the inheritance chain
    /// (see [OpenZeppelin's guide about storage gaps]
    /// (https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps)).
    uint256[48] private __gap;
}
