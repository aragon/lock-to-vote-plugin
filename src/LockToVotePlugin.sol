// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import {ILockManager} from "./interfaces/ILockManager.sol";
import {ILockToVoteBase, VoteOption} from "./interfaces/ILockToVote.sol";
import {ILockToVote, ProposalVoting, ProposalVotingParameters, LockToVoteSettings, VoteTally} from "./interfaces/ILockToVote.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IMembership} from "@aragon/osx-commons-contracts/src/plugin/extensions/membership/IMembership.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {_applyRatioCeiled} from "@aragon/osx-commons-contracts/src/utils/math/Ratio.sol";
import {MajorityVotingBase} from "./base/MajorityVotingBase.sol";

contract LockToVotePlugin is ILockToVote, IMembership, MajorityVotingBase {
    using SafeCastUpgradeable for uint256;

    /// @inheritdoc ILockToVoteBase
    ILockManager public lockManager;

    mapping(uint256 => ProposalVoting) proposals;

    /// @notice The ID of the permission required to call the `execute` function.
    bytes32 public constant LOCK_MANAGER_PERMISSION_ID =
        keccak256("LOCK_MANAGER_PERMISSION");

    /// @notice The ID of the permission required to call the `updateVotingSettings` function.
    bytes32 public constant UPDATE_VOTING_SETTINGS_PERMISSION_ID =
        keccak256("UPDATE_VOTING_SETTINGS_PERMISSION");

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
            _interfaceId == type(ILockToVoteBase).interfaceId ||
            _interfaceId == type(ILockToVote).interfaceId ||
            super.supportsInterface(_interfaceId);
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

    /// @inheritdoc IProposal
    /// @dev Requires the `CREATE_PROPOSAL_PERMISSION_ID` permission.
    function createProposal(
        bytes calldata _metadata,
        Action[] memory _actions,
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
        ProposalVoting storage proposal_ = proposals[proposalId];

        if (proposal_.parameters.startDate != 0) {
            revert ProposalAlreadyExists(proposalId);
        }

        proposal_.parameters.startDate = _startDate;
        proposal_.parameters.endDate = _endDate;
        proposal_.parameters.minVotingPower = settings.minVotingPower;
        proposal_.parameters.minApprovalPower = settings.minApprovalPower;
        proposal_.parameters.supportThreshold = settings.supportThreshold;

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

        lockManager.proposalCreated(proposalId);
    }

    /// @notice Returns all information for a proposal by its ID.
    /// @param _proposalId The ID of the proposal.
    /// @return open Whether the proposal is open or not.
    /// @return executed Whether the proposal is executed or not.
    /// @return parameters The parameters of the proposal.
    /// @return tally The current tally of the proposal.
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
            ProposalVotingParameters memory parameters,
            VoteTally memory tally,
            Action[] memory actions,
            uint256 allowFailureMap,
            TargetConfig memory targetConfig
        )
    {
        ProposalVoting storage proposal_ = proposals[_proposalId];

        open = _isProposalOpen(proposal_);
        executed = proposal_.executed;
        parameters = proposal_.parameters;
        tally = proposal_.tally;
        actions = proposal_.actions;
        allowFailureMap = proposal_.allowFailureMap;
        targetConfig = proposal_.targetConfig;
    }

    /// @inheritdoc ILockToVoteBase
    function isProposalOpen(
        uint256 _proposalId
    ) external view virtual returns (bool) {
        ProposalVoting storage proposal_ = proposals[_proposalId];
        return _isProposalOpen(proposal_);
    }

    /// @inheritdoc IMembership
    function isMember(address _account) external view returns (bool) {
        if (lockManager.lockedBalances(_account) > 0) return true;
        else if (lockManager.token().balanceOf(_account) > 0) return true;
        return false;
    }

    /// @inheritdoc ILockToVoteBase
    function canVote(
        uint256 _proposalId,
        address _voter
    ) external view returns (bool) {
        ProposalVoting storage proposal_ = proposals[_proposalId];

        return _canVote(proposal_, _voter, lockManager.lockedBalances(_voter));
    }

    /// @inheritdoc ILockToVote
    function vote(
        uint256 _proposalId,
        address _voter,
        VoteOption _voteOption,
        uint256 _votingPower
    ) external auth(LOCK_MANAGER_PERMISSION_ID) {
        ProposalVoting storage proposal_ = proposals[_proposalId];

        if (!_canVote(proposal_, _voter, _votingPower)) {
            revert VoteCastForbidden(_proposalId, _voter);
        } else if (_voteOption == VoteOption.None) {
            revert VotingNoneForbidden(_proposalId, _voter);
        } else if (_votingPower < proposal_.votes[_voter].votingPower) {
            revert LowerBalanceForbidden();
        }

        // Same vote
        if (_voteOption == proposal_.votes[_voter].voteOption) {
            // Same balance, nothing to do
            if (_votingPower == proposal_.votes[_voter].votingPower) return;

            // More balance
            uint256 diff = _votingPower - proposal_.votes[_voter].votingPower;
            proposal_.votes[_voter].votingPower = _votingPower;

            if (proposal_.votes[_voter].voteOption == VoteOption.Yes) {
                proposal_.tally.yes += diff;
            } else if (proposal_.votes[_voter].voteOption == VoteOption.No) {
                proposal_.tally.no += diff;
            } else {
                proposal_.tally.abstain += diff;
            }
        } else {
            // Was there a vote?
            if (proposal_.votes[_voter].votingPower > 0) {
                // Undo that vote
                if (proposal_.votes[_voter].voteOption == VoteOption.Yes) {
                    proposal_.tally.yes -= proposal_.votes[_voter].votingPower;
                } else if (
                    proposal_.votes[_voter].voteOption == VoteOption.No
                ) {
                    proposal_.tally.no -= proposal_.votes[_voter].votingPower;
                } else {
                    proposal_.tally.abstain -= proposal_
                        .votes[_voter]
                        .votingPower;
                }
            }

            // Register the new vote
            if (_voteOption == VoteOption.Yes) {
                proposal_.tally.yes += _votingPower;
            } else if (_voteOption == VoteOption.No) {
                proposal_.tally.no += _votingPower;
            } else {
                proposal_.tally.abstain += _votingPower;
            }
            proposal_.votes[_voter].voteOption = _voteOption;
            proposal_.votes[_voter].votingPower = _votingPower;
        }

        emit VoteCast(_proposalId, _voter, _voteOption, _votingPower);

        _checkEarlyExecution(_proposalId, proposal_, _voter);
    }

    /// @inheritdoc ILockToVote
    function clearVote(
        uint256 _proposalId,
        address _voter
    ) external auth(LOCK_MANAGER_PERMISSION_ID) {
        ProposalVoting storage proposal_ = proposals[_proposalId];

        if (
            proposal_.votes[_voter].votingPower == 0 ||
            !_isProposalOpen(proposal_)
        ) {
            // Nothing to do
            return;
        }

        // Undo that vote
        if (proposal_.votes[_voter].voteOption == VoteOption.Yes) {
            proposal_.tally.yes -= proposal_.votes[_voter].votingPower;
        } else if (proposal_.votes[_voter].voteOption == VoteOption.No) {
            proposal_.tally.no -= proposal_.votes[_voter].votingPower;
        } else {
            proposal_.tally.abstain -= proposal_.votes[_voter].votingPower;
        }
        proposal_.votes[_voter].votingPower = 0;

        emit VoteCleared(_proposalId, _voter);
    }

    /// @inheritdoc ILockToVote
    function usedVotingPower(
        uint256 _proposalId,
        address _voter
    ) public view returns (uint256) {
        return proposals[_proposalId].votes[_voter].votingPower;
    }

    /// @inheritdoc IProposal
    function hasSucceeded(uint256 _proposalId) external view returns (bool) {
        ProposalVoting storage proposal_ = proposals[_proposalId];
        return _hasSucceeded(proposal_);
    }

    /// @inheritdoc IProposal
    function canExecute(uint256 _proposalId) external view returns (bool) {
        ProposalVoting storage proposal_ = proposals[_proposalId];
        return _canExecute(proposal_);
    }

    /// @inheritdoc IProposal
    function execute(
        uint256 _proposalId
    ) external auth(EXECUTE_PROPOSAL_PERMISSION_ID) {
        ProposalVoting storage proposal_ = proposals[_proposalId];

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

    /// @inheritdoc ILockToVote
    function updatePluginSettings(
        LockToVoteSettings calldata _newSettings
    ) external auth(UPDATE_VOTING_SETTINGS_PERMISSION_ID) {
        _updatePluginSettings(_newSettings);
    }

    // Internal helpers

    function _isProposalOpen(
        ProposalVoting storage proposal_
    ) internal view returns (bool) {
        uint64 currentTime = block.timestamp.toUint64();

        return
            proposal_.parameters.startDate <= currentTime &&
            currentTime < proposal_.parameters.endDate &&
            !proposal_.executed;
    }

    function _canVote(
        ProposalVoting storage proposal_,
        address _voter,
        uint256 _newVotingBalance
    ) internal view returns (bool) {
        // The proposal vote hasn't started or has already ended.
        if (!_isProposalOpen(proposal_)) {
            return false;
        }
        // More balance could be added
        else if (_newVotingBalance <= proposal_.votes[_voter]) {
            return false;
        }

        return true;
    }

    function _canExecute(
        ProposalVoting storage proposal_
    ) internal view returns (bool) {
        if (proposal_.executed) {
            return false;
        } else if (proposal_.parameters.endDate < block.timestamp) {
            return false;
        } else if (!_hasSucceeded(proposal_)) {
            return false;
        }

        return true;
    }

    function _minApprovalTally(
        ProposalVoting storage proposal_
    ) internal view returns (uint256 _minTally) {
        /// @dev Checking against the totalSupply() of the **underlying token**.
        /// @dev LP tokens could have important supply variations and this would impact the value of existing votes, after created.
        /// @dev However, the total supply of the underlying token (USDC, USDT, DAI, etc) will experiment little to no variations in comparison.

        // NOTE: Assuming a 1:1 correlation between token() and underlyingToken()

        _minTally = _applyRatioCeiled(
            lockManager.underlyingToken().totalSupply(),
            proposal_.parameters.minApprovalRatio
        );
    }

    function _hasSucceeded(
        ProposalVoting storage proposal_
    ) internal view returns (bool) {
        return
            proposal_.approvalTally >= _minApprovalTally(proposal_) &&
            proposal_.approvalTally > 0;
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

    function _checkEarlyExecution(
        uint256 _proposalId,
        ProposalVoting storage proposal_,
        address _voter
    ) internal {
        if (!_canExecute(proposal_)) {
            return;
        } else if (
            !dao().hasPermission(
                address(this),
                _voter,
                EXECUTE_PROPOSAL_PERMISSION_ID,
                _msgData()
            )
        ) {
            return;
        }

        _execute(_proposalId, proposal_);
    }

    function _execute(
        uint256 _proposalId,
        ProposalVoting storage proposal_
    ) internal {
        proposal_.executed = true;

        // IProposal's target execution
        _execute(
            proposal_.targetConfig.target,
            bytes32(_proposalId),
            proposal_.actions,
            proposal_.allowFailureMap,
            proposal_.targetConfig.operation
        );

        emit Executed(_proposalId);

        // Notify the LockManager to stop tracking this proposal ID
        lockManager.proposalEnded(_proposalId);
    }

    function _updatePluginSettings(
        LockToVoteSettings memory _newSettings
    ) internal {
        settings.minApprovalRatio = _newSettings.minApprovalRatio;
        settings.minProposalDuration = _newSettings.minProposalDuration;
    }
}
