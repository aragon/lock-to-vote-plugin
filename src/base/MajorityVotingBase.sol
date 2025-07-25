// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

/* solhint-disable max-line-length */

import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import {ProposalUpgradeable} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/ProposalUpgradeable.sol";
import {RATIO_BASE, RatioOutOfBounds} from "@aragon/osx-commons-contracts/src/utils/math/Ratio.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx-commons-contracts/src/plugin/PluginUUPSUpgradeable.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IProposal} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {MetadataExtensionUpgradeable} from
    "@aragon/osx-commons-contracts/src/utils/metadata/MetadataExtensionUpgradeable.sol";
import {_applyRatioCeiled} from "@aragon/osx-commons-contracts/src/utils/math/Ratio.sol";
import {IMajorityVoting} from "../interfaces/IMajorityVoting.sol";

/* solhint-enable max-line-length */

/// @title MajorityVotingBase
/// @author Aragon X - 2022-2025
/// @notice The abstract implementation of majority voting plugins.
///
/// ### Parameterization
///
/// We define two parameters
/// $$\texttt{support} = \frac{N_\text{yes}}{N_\text{yes} + N_\text{no}} \in [0,1]$$
/// and
/// $$\texttt{participation} = \frac{N_\text{yes} + N_\text{no} + N_\text{abstain}}{N_\text{total}} \in [0,1],$$
/// where $N_\text{yes}$, $N_\text{no}$, and $N_\text{abstain}$ are the yes, no, and abstain votes that have been
/// cast and $N_\text{total}$ is the total voting power available at proposal creation time.
///
/// #### Limit Values: Support Threshold & Minimum Participation
///
/// Two limit values are associated with these parameters and decide if a proposal execution should be possible:
/// $\texttt{supportThresholdRatio} \in [0,1)$ and $\texttt{minParticipationRatio} \in [0,1]$.
///
/// For threshold values, $>$ comparison is used. This **does not** include the threshold value.
/// E.g., for $\texttt{supportThresholdRatio} = 50\%$,
/// the criterion is fulfilled if there is at least one more yes than no votes ($N_\text{yes} = N_\text{no} + 1$).
/// For minimum values, $\ge{}$ comparison is used. This **does** include the minimum participation value.
/// E.g., for $\texttt{minParticipationRatio} = 40\%$ and $N_\text{total} = 10$,
/// the criterion is fulfilled if 4 out of 10 votes were casted.
///
/// Majority voting implies that the support threshold is set with
/// $$\texttt{supportThresholdRatio} \ge 50\% .$$
/// However, this is not enforced by the contract code and developers can make unsafe parameters and
/// only the frontend will warn about bad parameter settings.
///
/// ### Execution Criteria
///
/// After the vote is closed, two criteria decide if the proposal passes.
///
/// #### The Support Criterion
///
/// For a proposal to pass, the required ratio of yes and no votes must be met:
/// $$(1- \texttt{supportThresholdRatio}) \cdot N_\text{yes} > \texttt{supportThresholdRatio} \cdot N_\text{no}.$$
/// Note, that the inequality yields the simple majority voting condition for $\texttt{supportThresholdRatio}=\frac{1}{2}$.
///
/// #### The Participation Criterion
///
/// For a proposal to pass, the minimum voting power must have been cast:
/// $$N_\text{yes} + N_\text{no} + N_\text{abstain} \ge \texttt{minVotingPower},$$
/// where $\texttt{minVotingPower} = \texttt{minParticipationRatio} \cdot N_\text{total}$.
///
/// ### Vote Replacement
///
/// The contract allows votes to be replaced. Voters can vote multiple times
/// and only the latest voteOption is tallied.
///
/// ### Early Execution
///
/// This contract allows a proposal to be executed early,
/// iff the vote outcome cannot change anymore by more people voting.
/// Accordingly, vote replacement and early execution are mutually exclusive options.
/// The outcome cannot change anymore
/// iff the support threshold is met even if all remaining votes are no votes.
/// We call this number the worst-case number of no votes and define it as
///
/// $$N_\text{no, worst-case} = N_\text{no} + \texttt{remainingVotes}$$
///
/// where
///
/// $$\texttt{remainingVotes} =
/// N_\text{total}-\underbrace{(N_\text{yes}+N_\text{no}+N_\text{abstain})}_{\text{turnout}}.$$
///
/// We can use this quantity to calculate the worst-case support that would be obtained
/// if all remaining votes are casted with no:
///
/// $$
/// \begin{align*}
///   \texttt{worstCaseSupport}
///   &= \frac{N_\text{yes}}{N_\text{yes} + (N_\text{no, worst-case})} \\[3mm]
///   &= \frac{N_\text{yes}}{N_\text{yes} + (N_\text{no} + \texttt{remainingVotes})} \\[3mm]
///   &= \frac{N_\text{yes}}{N_\text{yes} +  N_\text{no} + N_\text{total}
///      - (N_\text{yes} + N_\text{no} + N_\text{abstain})} \\[3mm]
///   &= \frac{N_\text{yes}}{N_\text{total} - N_\text{abstain}}
/// \end{align*}
/// $$
///
/// In analogy, we can modify [the support criterion](#the-support-criterion)
/// from above to allow for early execution:
///
/// $$
/// \begin{align*}
///   (1 - \texttt{supportThresholdRatio}) \cdot N_\text{yes}
///   &> \texttt{supportThresholdRatio} \cdot  N_\text{no, worst-case} \\[3mm]
///   &> \texttt{supportThresholdRatio} \cdot (N_\text{no} + \texttt{remainingVotes}) \\[3mm]
///   &> \texttt{supportThresholdRatio} \cdot (N_\text{no}
///     + N_\text{total}-(N_\text{yes}+N_\text{no}+N_\text{abstain})) \\[3mm]
///   &> \texttt{supportThresholdRatio} \cdot (N_\text{total} - N_\text{yes} - N_\text{abstain})
/// \end{align*}
/// $$
///
/// Accordingly, early execution is possible when the vote is open,
///     the modified support criterion, and the particicpation criterion are met.
/// @dev This contract implements the `IMajorityVoting` interface.
/// @custom:security-contact sirt@aragon.org
abstract contract MajorityVotingBase is
    IMajorityVoting,
    Initializable,
    ERC165Upgradeable,
    MetadataExtensionUpgradeable,
    PluginUUPSUpgradeable,
    ProposalUpgradeable
{
    using SafeCastUpgradeable for uint256;

    /// @notice The different voting modes available.
    /// @param Standard In standard mode, early execution and vote replacement are disabled.
    /// @param EarlyExecution In early execution mode, a proposal can be executed
    ///     early before the end date if the vote outcome cannot mathematically change by more voters voting.
    /// @param VoteReplacement In vote replacement mode, voters can change their vote
    ///     multiple times and only the latest vote option is tallied.
    enum VotingMode {
        Standard,
        EarlyExecution,
        VoteReplacement
    }

    /// @notice A container for the majority voting settings that will be applied as parameters on proposal creation.
    /// @param votingMode A parameter to select the vote mode.
    ///     In standard mode (0), early execution and vote replacement are disabled.
    ///     In early execution mode (1), a proposal can be executed early before the end date
    ///     if the vote outcome cannot mathematically change by more voters voting.
    ///     In vote replacement mode (2), voters can change their vote multiple times
    ///     and only the latest vote option is tallied.
    /// @param supportThresholdRatio The support threshold ratio.
    ///     Its value has to be in the interval [0, 10^6] defined by `RATIO_BASE = 10**6`.
    /// @param minParticipationRatio The minimum participation ratio.
    ///     Its value has to be in the interval [0, 10^6] defined by `RATIO_BASE = 10**6`.
    /// @param minApprovalRatio The minimum ratio of approvals the proposal needs to succeed.
    ///     Its value has to be in the interval [0, 10^6] defined by `RATIO_BASE = 10**6`.
    /// @param proposalDuration The duration of the proposal vote in seconds.
    /// @param minProposerVotingPower The minimum voting power required to create a proposal.
    struct VotingSettings {
        VotingMode votingMode;
        uint32 supportThresholdRatio;
        uint32 minParticipationRatio;
        uint32 minApprovalRatio;
        uint64 proposalDuration;
        uint256 minProposerVotingPower;
    }

    /// @notice A container for proposal-related information.
    /// @param executed Whether the proposal is executed or not.
    /// @param parameters The proposal parameters at the time of the proposal creation.
    /// @param tally The vote tally of the proposal.
    /// @param votes The voting power cast by each voter.
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
        Tally tally;
        mapping(address => VoteEntry) votes;
        Action[] actions;
        uint256 allowFailureMap;
        TargetConfig targetConfig;
    }

    /// @notice A container for the proposal parameters at the time of proposal creation.
    /// @param votingMode A parameter to select the vote mode.
    /// @param supportThresholdRatio The support threshold ratio.
    ///     The value has to be in the interval [0, 10^6] defined by `RATIO_BASE = 10**6`.
    /// @param startDate The start date of the proposal vote.
    /// @param endDate The end date of the proposal vote.
    /// @param minParticipationRatio The minimum voting power ratio needed for a proposal to reach minimum participation.
    ///     The value has to be in the interval [0, 10^6] defined by `RATIO_BASE = 10**6`.
    /// @param minApprovalRatio Minimum ratio of allocated YES votes.
    ///     The value has to be in the interval [0, 10^6] defined by `RATIO_BASE = 10**6`.
    struct ProposalParameters {
        VotingMode votingMode;
        uint32 supportThresholdRatio;
        uint64 startDate;
        uint64 endDate;
        uint256 minParticipationRatio;
        uint256 minApprovalRatio;
    }

    /// @notice A container for the proposal vote tally.
    /// @param abstain The number of abstain votes casted.
    /// @param yes The number of yes votes casted.
    /// @param no The number of no votes casted.
    struct Tally {
        uint256 abstain;
        uint256 yes;
        uint256 no;
    }

    /// @notice The [ERC-165](https://eips.ethereum.org/EIPS/eip-165) interface ID of the contract.
    bytes4 internal constant MAJORITY_VOTING_BASE_INTERFACE_ID = this.proposalDuration.selector
        ^ this.minProposerVotingPower.selector ^ this.votingMode.selector ^ this.currentTokenSupply.selector
        ^ this.getProposal.selector ^ this.updateVotingSettings.selector;

    /// @notice The ID of the permission required to call the `updateVotingSettings` function.
    bytes32 public constant UPDATE_SETTINGS_PERMISSION_ID = keccak256("UPDATE_SETTINGS_PERMISSION");

    /// @notice The ID of the permission required to call the `execute` function.
    bytes32 public constant EXECUTE_PROPOSAL_PERMISSION_ID = keccak256("EXECUTE_PROPOSAL_PERMISSION");

    /// @notice A mapping between proposal IDs and proposal information.
    // solhint-disable-next-line named-parameters-mapping
    mapping(uint256 => Proposal) internal proposals;

    /// @notice The struct storing the voting settings.
    VotingSettings private votingSettings;

    /// @notice Thrown if a date is out of bounds.
    /// @param limit The limit value.
    /// @param actual The actual value.
    error DateOutOfBounds(uint64 limit, uint64 actual);

    /// @notice Thrown if the proposal duration value is out of bounds (less than one hour or greater than 1 year).
    /// @param limit The limit value.
    /// @param actual The actual value.
    error ProposalDurationOutOfBounds(uint64 limit, uint64 actual);

    /// @notice Thrown when a sender is not allowed to create a proposal.
    /// @param sender The sender address.
    error ProposalCreationForbidden(address sender);

    /// @notice Thrown when a proposal doesn't exist.
    /// @param proposalId The ID of the proposal which doesn't exist.
    error NonexistentProposal(uint256 proposalId);

    /// @notice Thrown if an account is not allowed to cast a vote. This can be because the vote
    /// - has not started,
    /// - has ended,
    /// - was executed, or
    /// - the account doesn't have voting powers.
    /// @param proposalId The ID of the proposal.
    /// @param account The address of the _account.
    error VoteCastForbidden(uint256 proposalId, address account);

    /// @notice Thrown if the proposal execution is forbidden.
    /// @param proposalId The ID of the proposal.
    error ProposalExecutionForbidden(uint256 proposalId);

    /// @notice Thrown if the proposal with same actions and metadata already exists.
    /// @param proposalId The id of the proposal.
    error ProposalAlreadyExists(uint256 proposalId);

    /// @notice Emitted when the voting settings are updated.
    /// @param votingMode A parameter to select the vote mode.
    /// @param supportThresholdRatio The support threshold ratio.
    /// @param minParticipationRatio The minimum participation ratio.
    /// @param minApprovalRatio The minimum ratio of yes votes over the token supply needed for the proposal advance.
    /// @param proposalDuration The duration of the proposal in seconds.
    /// @param minProposerVotingPower The minimum voting power required to create a proposal.
    event VotingSettingsUpdated(
        VotingMode votingMode,
        uint32 supportThresholdRatio,
        uint32 minParticipationRatio,
        uint32 minApprovalRatio,
        uint64 proposalDuration,
        uint256 minProposerVotingPower
    );

    /// @notice Initializes the component to be used by inheriting contracts.
    /// @dev This method is required to support [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822).
    /// @param _dao The IDAO interface of the associated DAO.
    /// @param _votingSettings The voting settings.
    /// @param _targetConfig Configuration for the execution target, specifying the target address and operation type
    ///     (either `Call` or `DelegateCall`). Defined by `TargetConfig` in the `IPlugin` interface,
    ///     part of the `osx-commons-contracts` package, added in build 3.
    /// @param _pluginMetadata The plugin specific information encoded in bytes.
    ///     This can also be an ipfs cid encoded in bytes.
    // solhint-disable-next-line func-name-mixedcase
    function __MajorityVotingBase_init(
        IDAO _dao,
        VotingSettings calldata _votingSettings,
        TargetConfig calldata _targetConfig,
        bytes calldata _pluginMetadata
    ) internal onlyInitializing {
        __PluginUUPSUpgradeable_init(_dao);
        _updateVotingSettings(_votingSettings);
        _setTargetConfig(_targetConfig);
        _setMetadata(_pluginMetadata);
    }

    /// @notice Checks if this or the parent contract supports an interface by its ID.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(bytes4 _interfaceId)
        public
        view
        virtual
        override(ERC165Upgradeable, MetadataExtensionUpgradeable, PluginUUPSUpgradeable, ProposalUpgradeable)
        returns (bool)
    {
        return _interfaceId == MAJORITY_VOTING_BASE_INTERFACE_ID || _interfaceId == type(IMajorityVoting).interfaceId
            || super.supportsInterface(_interfaceId);
    }

    /// @inheritdoc IProposal
    /// @dev Requires the `EXECUTE_PROPOSAL_PERMISSION_ID` permission.
    function execute(uint256 _proposalId)
        public
        virtual
        override(IMajorityVoting, IProposal)
        auth(EXECUTE_PROPOSAL_PERMISSION_ID)
    {
        if (!_canExecute(_proposalId)) {
            revert ProposalExecutionForbidden(_proposalId);
        }

        _execute(_proposalId);
    }

    /// @inheritdoc IMajorityVoting
    function getVote(uint256 _proposalId, address _voter) public view virtual returns (VoteEntry memory) {
        return (proposals[_proposalId].votes[_voter]);
    }

    /// @inheritdoc IMajorityVoting
    /// @dev Reverts if the proposal with the given `_proposalId` does not exist.
    function canExecute(uint256 _proposalId) public view virtual override(IMajorityVoting, IProposal) returns (bool) {
        if (!_proposalExists(_proposalId)) {
            revert NonexistentProposal(_proposalId);
        }

        return _canExecute(_proposalId);
    }

    /// @inheritdoc IProposal
    /// @dev Reverts if the proposal with the given `_proposalId` does not exist.
    function hasSucceeded(uint256 _proposalId) public view virtual returns (bool) {
        if (!_proposalExists(_proposalId)) {
            revert NonexistentProposal(_proposalId);
        }

        return _hasSucceeded(_proposalId);
    }

    /// @inheritdoc IMajorityVoting
    function isSupportThresholdReached(uint256 _proposalId) public view virtual returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        // The code below implements the formula of the support criterion explained in the top of this file.
        // `(1 - supportThresholdRatio) * N_yes > supportThresholdRatio *  N_no`
        return (RATIO_BASE - proposal_.parameters.supportThresholdRatio) * proposal_.tally.yes
            > proposal_.parameters.supportThresholdRatio * proposal_.tally.no;
    }

    /// @inheritdoc IMajorityVoting
    function isSupportThresholdReachedEarly(uint256 _proposalId) public view virtual returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        uint256 noVotesWorstCase = currentTokenSupply() - proposal_.tally.yes - proposal_.tally.abstain;

        // The code below implements the formula of the
        // early execution support criterion explained in the top of this file.
        // `(1 - supportThreshold) * N_yes > supportThreshold *  N_no,worst-case`
        return (RATIO_BASE - proposal_.parameters.supportThresholdRatio) * proposal_.tally.yes
            > proposal_.parameters.supportThresholdRatio * noVotesWorstCase;
    }

    /// @inheritdoc IMajorityVoting
    function isMinVotingPowerReached(uint256 _proposalId) public view virtual returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        uint256 _minVotingPower = _applyRatioCeiled(currentTokenSupply(), proposal_.parameters.minParticipationRatio);

        // The code below implements the formula of the
        // participation criterion explained in the top of this file.
        // `N_yes + N_no + N_abstain >= minVotingPower = minParticipationRatio * N_total`
        return proposal_.tally.yes + proposal_.tally.no + proposal_.tally.abstain >= _minVotingPower;
    }

    /// @inheritdoc IMajorityVoting
    function isMinApprovalReached(uint256 _proposalId) public view virtual returns (bool) {
        uint256 _minApprovalPower =
            _applyRatioCeiled(currentTokenSupply(), proposals[_proposalId].parameters.minApprovalRatio);
        return proposals[_proposalId].tally.yes >= _minApprovalPower;
    }

    /// @inheritdoc IMajorityVoting
    function supportThresholdRatio() public view virtual returns (uint32) {
        return votingSettings.supportThresholdRatio;
    }

    /// @inheritdoc IMajorityVoting
    function minParticipationRatio() public view virtual returns (uint32) {
        return votingSettings.minParticipationRatio;
    }

    /// @notice Returns the proposal duration parameter stored in the voting settings.
    /// @return The proposal duration in seconds.
    function proposalDuration() public view virtual returns (uint64) {
        return votingSettings.proposalDuration;
    }

    /// @notice Returns the minimum voting power required to create a proposal stored in the voting settings.
    /// @return The minimum voting power required to create a proposal.
    function minProposerVotingPower() public view virtual returns (uint256) {
        return votingSettings.minProposerVotingPower;
    }

    /// @inheritdoc IMajorityVoting
    function minApprovalRatio() public view virtual returns (uint256) {
        return votingSettings.minApprovalRatio;
    }

    /// @notice Returns the vote mode stored in the voting settings.
    /// @return The vote mode parameter.
    function votingMode() public view virtual returns (VotingMode) {
        return votingSettings.votingMode;
    }

    /// @notice Returns the current voting settings
    function getVotingSettings() public view virtual returns (VotingSettings memory) {
        return votingSettings;
    }

    /// @notice Returns the current token supply.
    /// @return The token supply.
    function currentTokenSupply() public view virtual returns (uint256);

    /// @notice Returns all information for a proposal by its ID.
    /// @param _proposalId The ID of the proposal.
    /// @return open Whether the proposal is open or not.
    /// @return executed Whether the proposal is executed or not.
    /// @return parameters The parameters of the proposal.
    /// @return tally The current tally of the proposal.
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
            ProposalParameters memory parameters,
            Tally memory tally,
            Action[] memory actions,
            uint256 allowFailureMap,
            TargetConfig memory targetConfig
        )
    {
        Proposal storage proposal_ = proposals[_proposalId];

        open = _isProposalOpen(proposal_);
        executed = proposal_.executed;
        parameters = proposal_.parameters;
        tally = proposal_.tally;
        actions = proposal_.actions;
        allowFailureMap = proposal_.allowFailureMap;
        targetConfig = proposal_.targetConfig;
    }

    /// @notice Updates the voting settings.
    /// @dev Requires the `UPDATE_SETTINGS_PERMISSION_ID` permission.
    /// @param _votingSettings The new voting settings.
    function updateVotingSettings(VotingSettings calldata _votingSettings)
        external
        virtual
        auth(UPDATE_SETTINGS_PERMISSION_ID)
    {
        _updateVotingSettings(_votingSettings);
    }

    /// @notice Internal function to execute a proposal. It assumes the queried proposal exists.
    /// @param _proposalId The ID of the proposal.
    function _execute(uint256 _proposalId) internal virtual {
        Proposal storage proposal_ = proposals[_proposalId];

        proposal_.executed = true;

        _execute(
            proposal_.targetConfig.target,
            bytes32(_proposalId),
            proposal_.actions,
            proposal_.allowFailureMap,
            proposal_.targetConfig.operation
        );

        emit ProposalExecuted(_proposalId);
    }

    /// @notice An internal function that checks if the proposal succeeded or not.
    /// @param _proposalId The ID of the proposal.
    /// @return Returns `true` if the proposal succeeded depending on the thresholds and voting modes.
    function _hasSucceeded(uint256 _proposalId) internal view virtual returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        // Support threshold, depending on the status and mode
        if (_isProposalOpen(proposal_)) {
            // If the proposal is still open and the voting mode is not EarlyExecution,
            // success cannot be determined until the voting period ends.
            if (proposal_.parameters.votingMode != VotingMode.EarlyExecution) {
                return false;
            }
            // For EarlyExecution, check if the support threshold
            // has been reached early to determine success while proposal is still open.
            else if (!isSupportThresholdReachedEarly(_proposalId)) {
                return false;
            }
        } else {
            // Normal execution
            if (!isSupportThresholdReached(_proposalId)) {
                return false;
            }
        }

        // Check the rest
        if (!isMinVotingPowerReached(_proposalId)) {
            return false;
        } else if (!isMinApprovalReached(_proposalId)) {
            return false;
        }

        return true;
    }

    /// @notice Internal function to check if a proposal can be executed. It assumes the queried proposal exists.
    /// @dev Threshold and minimal values are compared with `>` and `>=` comparators, respectively.
    /// @param _proposalId The ID of the proposal.
    /// @return True if the proposal can be executed, false otherwise.
    function _canExecute(uint256 _proposalId) internal view virtual returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        // Verify that the vote has not been executed already.
        if (proposal_.executed) {
            return false;
        } else if (!_hasSucceeded(_proposalId)) {
            return false;
        }
        /// @dev Handling the case of Standard and VoteReplacement voting modes
        /// @dev Enforce waiting until endDate, which is not covered by _hasSucceeded()
        else if (
            proposal_.parameters.votingMode != VotingMode.EarlyExecution
                && block.timestamp.toUint64() < proposal_.parameters.endDate
        ) {
            return false;
        }

        return true;
    }

    /// @notice Internal function to check if a proposal is still open.
    /// @param proposal_ The proposal struct.
    /// @return True if the proposal is open, false otherwise.
    function _isProposalOpen(Proposal storage proposal_) internal view virtual returns (bool) {
        uint64 currentTime = block.timestamp.toUint64();

        return proposal_.parameters.startDate <= currentTime && currentTime < proposal_.parameters.endDate
            && !proposal_.executed;
    }

    /// @notice Internal function to update the plugin-wide proposal settings.
    /// @param _votingSettings The voting settings to be validated and updated.
    function _updateVotingSettings(VotingSettings calldata _votingSettings) internal virtual {
        // Require the support threshold value to be in the interval [0, 10^6-1],
        // because `>` comparison is used in the support criterion and >100% could never be reached.
        if (_votingSettings.supportThresholdRatio > RATIO_BASE - 1) {
            revert RatioOutOfBounds({limit: RATIO_BASE - 1, actual: _votingSettings.supportThresholdRatio});
        }
        // Require the minimum participation value to be in the interval [0, 10^6],
        // because `>=` comparison is used in the participation criterion.
        else if (_votingSettings.minParticipationRatio > RATIO_BASE) {
            revert RatioOutOfBounds({limit: RATIO_BASE, actual: _votingSettings.minParticipationRatio});
        } else if (_votingSettings.proposalDuration < 60 minutes) {
            revert ProposalDurationOutOfBounds({limit: 60 minutes, actual: _votingSettings.proposalDuration});
        } else if (_votingSettings.proposalDuration > 365 days) {
            revert ProposalDurationOutOfBounds({limit: 365 days, actual: _votingSettings.proposalDuration});
        }
        // Require the minimum approval value to be in the interval [0, 10^6],
        // because `>=` comparison is used in the participation criterion.
        else if (_votingSettings.minApprovalRatio > RATIO_BASE) {
            revert RatioOutOfBounds({limit: RATIO_BASE, actual: _votingSettings.minApprovalRatio});
        }

        votingSettings = _votingSettings;

        emit VotingSettingsUpdated({
            votingMode: _votingSettings.votingMode,
            supportThresholdRatio: _votingSettings.supportThresholdRatio,
            minParticipationRatio: _votingSettings.minParticipationRatio,
            proposalDuration: _votingSettings.proposalDuration,
            minProposerVotingPower: _votingSettings.minProposerVotingPower,
            minApprovalRatio: _votingSettings.minApprovalRatio
        });
    }

    /// @notice Checks if proposal exists or not.
    /// @param _proposalId The ID of the proposal.
    /// @return Returns `true` if proposal exists, otherwise false.
    function _proposalExists(uint256 _proposalId) internal view returns (bool) {
        return proposals[_proposalId].parameters.startDate != 0;
    }

    /// @notice Validates and returns the proposal dates.
    /// @param _start The start date of the proposal.
    ///     If 0, the current timestamp is used and the vote starts immediately.
    /// @param _end The end date of the proposal. If 0, `_start + proposalDuration` is used.
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
        // Since `proposalDuration` is limited to 1 year,
        // `startDate + proposalDuration` can only overflow if the `startDate` is after `type(uint64).max - proposalDuration`.
        // In this case, the proposal creation will revert and another date can be picked.
        uint64 earliestEndDate = startDate + votingSettings.proposalDuration;

        if (_end == 0) {
            endDate = earliestEndDate;
        } else {
            endDate = _end;

            if (endDate < earliestEndDate) {
                revert DateOutOfBounds({limit: earliestEndDate, actual: endDate});
            }
        }
    }

    /// @notice This empty reserved space is put in place to allow future versions to add
    /// new variables without shifting down storage in the inheritance chain
    /// (see [OpenZeppelin's guide about storage gaps]
    /// (https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps)).
    uint256[47] private __gap;
}
