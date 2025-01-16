// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import {ILockManager} from "./interfaces/ILockManager.sol";
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
    bytes32 public constant CREATE_PROPOSAL_PERMISSION_ID =
        keccak256("CREATE_PROPOSAL_PERMISSION");

    /// @notice The ID of the permission required to call the `execute` function.
    bytes32 public constant EXECUTE_PROPOSAL_PERMISSION_ID =
        keccak256("EXECUTE_PROPOSAL_PERMISSION");

    /// @notice The ID of the permission required to call the `execute` function.
    bytes32 public constant LOCK_MANAGER_PERMISSION_ID =
        keccak256("LOCK_MANAGER_PERMISSION");

    /// @notice The ID of the permission required to call the `updateVotingSettings` function.
    bytes32 public constant UPDATE_VOTING_SETTINGS_PERMISSION_ID =
        keccak256("UPDATE_VOTING_SETTINGS_PERMISSION");

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

        (_startDate, _endDate) = _validateProposalDates(_startDate, _endDate);

        proposalId = _createProposalId(keccak256(abi.encode(_actions, _metadata)));

        // Store proposal related information
        ProposalApproval storage proposal_ = proposals[proposalId];

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

        for (uint256 i; i < _actions.length;) {
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
    function getProposal(uint256 _proposalId)
        public
        view
        virtual
        returns (
            bool open,
            bool executed,
            ProposalApprovalParameters memory parameters,
            uint256 approvalTally,
            Action[] memory actions,
            uint256 allowFailureMap,
            TargetConfig memory targetConfig
        )
    {
        ProposalApproval storage proposal_ = proposals[_proposalId];

        open = _isProposalOpen(proposal_);
        executed = proposal_.executed;
        parameters = proposal_.parameters;
        approvalTally = proposal_.approvalTally;
        actions = proposal_.actions;
        allowFailureMap = proposal_.allowFailureMap;
        targetConfig = proposal_.targetConfig;
    }

    /// @inheritdoc ILockToVoteBase
    function isProposalOpen(uint256 _proposalId) external view virtual returns (bool) {
        ProposalApproval storage proposal_ = proposals[_proposalId];
        return _isProposalOpen(proposal_);
    }

    /// @inheritdoc IMembership
    function isMember(address _account) external view returns (bool) {
        if (lockManager.lockedBalances(_account) > 0) return true;
        else if (lockManager.token().balanceOf(_account) > 0) return true;
        return false;
    }

    /// @inheritdoc ILockToApprove
    function canApprove(uint256 _proposalId, address _voter) external view returns (bool) {
        ProposalApproval storage proposal_ = proposals[_proposalId];

        return _canVote(proposal_, _voter, lockManager.lockedBalances(_voter));
    }

    /// @inheritdoc ILockToApprove
    function approve(uint256 _proposalId, address _voter, uint256 _newVotingPower)
        external
        auth(LOCK_MANAGER_PERMISSION_ID)
    {
        ProposalApproval storage proposal_ = proposals[_proposalId];

        if (!_canVote(proposal_, _voter, _newVotingPower)) {
            revert ApprovalForbidden(_proposalId, _voter);
        }

        // Add the difference between the new voting power and the current one

        uint256 diff = _newVotingPower - proposal_.approvals[_voter];
        proposal_.approvalTally += diff;
        proposal_.approvals[_voter] += diff;

        emit Approved(_proposalId, _voter, _newVotingPower);

        _checkEarlyExecution(_proposalId, proposal_, _voter);
    }

    /// @inheritdoc ILockToApprove
    function clearApproval(uint256 _proposalId, address _voter) external auth(LOCK_MANAGER_PERMISSION_ID) {
        ProposalApproval storage proposal_ = proposals[_proposalId];

        if (proposal_.approvals[_voter] == 0 || !_isProposalOpen(proposal_)) return;

        // Subtract the old votes from the global tally
        proposal_.approvalTally -= proposal_.approvals[_voter];

        // Clear the voting power
        proposal_.approvals[_voter] = 0;

        emit VoteCleared(_proposalId, _voter);
    }

    /// @inheritdoc ILockToVoteBase
    function usedVotingPower(uint256 proposalId, address voter) public view returns (uint256) {
        return proposals[proposalId].approvals[voter];
    }

    /// @inheritdoc IProposal
    function hasSucceeded(uint256 _proposalId) external view returns (bool) {
        ProposalApproval storage proposal_ = proposals[_proposalId];
        return _hasSucceeded(proposal_);
    }

    /// @inheritdoc IProposal
    function canExecute(uint256 _proposalId) external view returns (bool) {
        ProposalApproval storage proposal_ = proposals[_proposalId];
        return _canExecute(proposal_);
    }

    /// @inheritdoc IProposal
    function execute(uint256 _proposalId) external auth(EXECUTE_PROPOSAL_PERMISSION_ID) {
        ProposalApproval storage proposal_ = proposals[_proposalId];

        if (!_canExecute(proposal_)) {
            revert ExecutionForbidden(_proposalId);
        }

        _execute(_proposalId, proposal_);
    }

    /// @inheritdoc ILockToVoteBase
    function underlyingToken() external view returns (IERC20) {
        return lockManager.underlyingToken();
    }

    /// @inheritdoc ILockToVoteBase
    function token() external view returns (IERC20) {
        return lockManager.token();
    }

    /// @inheritdoc ILockToApprove
    function updatePluginSettings(LockToApproveSettings calldata _newSettings)
        external
        auth(UPDATE_VOTING_SETTINGS_PERMISSION_ID)
    {
        _updatePluginSettings(_newSettings);
    }

    // Internal helpers

    function _isProposalOpen(ProposalApproval storage proposal_) internal view returns (bool) {
        uint64 currentTime = block.timestamp.toUint64();

        return proposal_.parameters.startDate <= currentTime && currentTime < proposal_.parameters.endDate
            && !proposal_.executed;
    }

    function _canVote(ProposalApproval storage proposal_, address _voter, uint256 _newVotingBalance)
        internal
        view
        returns (bool)
    {
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

    function _canExecute(ProposalApproval storage proposal_) internal view returns (bool) {
        if (proposal_.executed) {
            return false;
        } else if (proposal_.parameters.endDate < block.timestamp) {
            return false;
        } else if (!_hasSucceeded(proposal_)) {
            return false;
        }

        return true;
    }

    function _minApprovalTally(ProposalApproval storage proposal_) internal view returns (uint256 _minTally) {
        /// @dev Checking against the totalSupply() of the **underlying token**.
        /// @dev LP tokens could have important supply variations and this would impact the value of existing votes, after created.
        /// @dev However, the total supply of the underlying token (USDC, USDT, DAI, etc) will experiment little to no variations in comparison.

        // NOTE: Assuming a 1:1 correlation between token() and underlyingToken()

        _minTally =
            _applyRatioCeiled(lockManager.underlyingToken().totalSupply(), proposal_.parameters.minApprovalRatio);
    }

    function _hasSucceeded(ProposalApproval storage proposal_) internal view returns (bool) {
        return proposal_.approvalTally >= _minApprovalTally(proposal_) && proposal_.approvalTally > 0;
    }

    /// @notice Validates and returns the proposal dates.
    /// @param _start The start date of the proposal.
    ///     If 0, the current timestamp is used and the vote starts immediately.
    /// @param _end The end date of the proposal. If 0, `_start + minDuration` is used.
    /// @return startDate The validated start date of the proposal.
    /// @return endDate The validated end date of the proposal.
    function _validateProposalDates(uint64 _start, uint64 _end)
        internal
        view
        virtual
        returns (uint64 startDate, uint64 endDate)
    {
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

    function _checkEarlyExecution(uint256 _proposalId, ProposalApproval storage proposal_, address _voter) internal {
        if (!_canExecute(proposal_)) {
            return;
        } else if (!dao().hasPermission(address(this), _voter, EXECUTE_PROPOSAL_PERMISSION_ID, _msgData())) {
            return;
        }

        _execute(_proposalId, proposal_);
    }

    function _execute(uint256 _proposalId, ProposalApproval storage proposal_) internal {
        proposal_.executed = true;

        // IProposal's target execution
        _execute(bytes32(_proposalId), proposal_.actions, proposal_.allowFailureMap);

        emit Executed(_proposalId);

        // Notify the LockManager to stop tracking this proposal ID
        lockManager.proposalEnded(_proposalId);
    }

    function _updatePluginSettings(LockToApproveSettings memory _newSettings) internal {
        settings.minApprovalRatio = _newSettings.minApprovalRatio;
        settings.minProposalDuration = _newSettings.minProposalDuration;
    }
}
