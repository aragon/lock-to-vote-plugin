# Test tree definitions

Below is the graphical summary of the tests described within [test/*.t.yaml](./test)

```
LockManagerERC20Test
├── Given The contract is being deployed
│   └── When Deploying with valid parameters
│       ├── It Should set the DAO address correctly
│       ├── It Should set the pluginMode correctly
│       ├── It Should set the token address correctly
│       └── It Should initialize the plugin address to address(0)
├── Given The plugin address has not been set yet
│   ├── When Calling setPluginAddress with an address that does not support ILockToGovernBase
│   │   └── It Should revert with InvalidPlugin
│   ├── When Calling setPluginAddress from a different address than the deployer
│   │   └── It Should revert with SetPluginAddressForbidden
│   └── Given The pluginMode is Voting
│       ├── When Calling setPluginAddress with a plugin that supports ILockToGovernBase but not ILockToVote
│       │   └── It Should revert with InvalidPlugin
│       └── When Calling setPluginAddress with a valid Voting plugin
│           └── It Should set the plugin address
├── Given The plugin address has already been set
│   └── When Calling setPluginAddress again
│       └── It Should revert with SetPluginAddressForbidden
├── Given A user wants to lock tokens // The user has a non-zero token balance
│   ├── When The user has not approved the LockManager to spend any tokens // Allowance is 0
│   │   └── When Calling lock
│   │       └── It Should revert with NoBalance
│   ├── When The user has approved the LockManager to spend tokens // Allowance is > 0
│   │   └── When Calling lock 2
│   │       ├── It Should transfer the full allowance amount from the user
│   │       ├── It Should increase the user's lockedBalances by the allowance amount
│   │       └── It Should emit a BalanceLocked event with the correct user and amount
│   ├── When The user has approved the LockManager to spend more than the balance // Allowance is ∞
│   │   └── When Calling lock 3
│   │       ├── It Should transfer the full balance from the user
│   │       ├── It Should increase the user's lockedBalances by the balance
│   │       └── It Should emit a BalanceLocked event with the correct user and amount
│   └── When The user tries to lock more than his balance
│       └── When Calling lock 4
│           └── It Should revert
├── Given pluginMode is Voting
│   └── Given A plugin is set and a proposal is active
│       ├── Given The user has no locked balance
│       │   ├── When Calling vote
│       │   │   └── It Should revert with NoBalance
│       │   ├── Given The user has no token allowance for the LockManager
│       │   │   └── When Calling lockAndVote
│       │   │       └── It Should revert with NoBalance
│       │   └── Given The user has a token allowance for the LockManager
│       │       └── When Calling lockAndVote 2
│       │           ├── It Should first lock the tokens by transferring the full allowance
│       │           └── It Should then call vote() on the plugin with the new balance
│       └── Given The user has a locked balance
│           ├── When Calling vote for the first time on a proposal
│           │   └── It Should call vote() on the plugin with the user's full locked balance
│           ├── Given The user has already voted on the proposal with their current balance
│           │   └── When Calling vote again with the same parameters
│           │       └── It Should revert with VoteCastForbidden
│           └── Given The user locks more tokens
│               └── When Calling vote again
│                   └── It Should call vote() on the plugin with the new, larger balance
├── Given A user wants to unlock tokens
│   ├── Given The user has no locked balance 2
│   │   └── When Calling unlock
│   │       └── It Should revert with NoBalance
│   └── Given The user has a locked balance 2
│       ├── Given No votes on open proposals and no active proposals created
│       │   └── When Calling unlock 2
│       │       └── It Should succeed and transfer the locked balance back to the user
│       ├── Given The user has votes on open proposals
│       │   ├── Given Standard voting mode
│       │   │   └── When Calling unlock 3
│       │   │       └── It Should revert
│       │   └── Given Vote replacement mode
│       │       └── When Calling unlock 4
│       │           ├── It Should call clearVote() on the plugin for each active proposal
│       │           ├── It Should transfer the locked balance back to the user
│       │           ├── It Should set the user's lockedBalances to 0
│       │           └── It Should emit a BalanceUnlocked event
│       ├── Given The user created active proposals
│       │   └── When Calling unlock 5
│       │       ├── It Should revert with ProposalCreatedStillActive (standard voting)
│       │       └── It Should revert with ProposalCreatedStillActive (vote replacement)
│       └── Given The user only has votes on proposals that are now closed or ended // The contract should garbage-collect the closed proposal during the check
│           └── When Calling unlock 6
│               ├── It Should not attempt to clear votes for the closed proposal
│               ├── It Should remove the closed proposal from knownProposalIds
│               └── It Should succeed and transfer the locked balance back to the user
├── Given The plugin has been set
│   ├── Given The caller is not the registered plugin
│   │   ├── When Calling proposalCreated
│   │   │   └── It Should revert with InvalidPluginAddress
│   │   └── When Calling proposalSettled
│   │       └── It Should revert with InvalidPluginAddress
│   └── Given The caller is the registered plugin
│       ├── When Calling proposalCreated with a new proposal ID
│       │   ├── It Should add the proposal ID to knownProposalIds
│       │   ├── It Should register the creator
│       │   └── It activeProposalsCreatedBy() should increase for the creator
│       ├── Given A proposal ID is already known
│       │   ├── When Calling proposalCreated with that same ID
│       │   │   ├── It Should not change the set of known proposals
│       │   │   └── It activeProposalsCreatedBy() should remain the same for the creator
│       │   └── When Calling proposalSettled with that proposal ID
│       │       ├── It Should remove the proposal ID from knownProposalIds
│       │       ├── It Should emit a ProposalSettled event
│       │       └── It activeProposalsCreatedBy() should decrease for the creator
│       └── When Calling proposalSettled with a nonexistent proposal ID
│           └── It Should do nothing
└── Given The contract is initialized
    ├── Given A plugin is set and a proposal exists
    │   └── Given pluginMode is Voting 2
    │       └── When Calling canVote
    │           └── It Should proxy the call to the plugin's canVote() and return its result
    └── Given The contract has several known proposal IDs
        ├── When Calling knownProposalIdAt with a valid index
        │   └── It Should return the correct proposal ID at that index
        ├── When Calling knownProposalIdAt with an outofbounds index
        │   └── It Should revert
        └── When Calling pruneProposals
            ├── It Should keep the open proposals on the konwnProposalIds list
            ├── It Should remove the ended proposals from the list
            └── It Should remove the executed proposals from the list
```

```
LockToVoteTest
├── When deploying the contract
│   └── It should initialize normally
├── Given a deployed contract
│   └── It should refuse to initialize again
├── Given a new proxy
│   └── Given calling initialize
│       ├── It should set the DAO address
│       ├── It should define the voting settings
│       ├── It should define the target config
│       ├── It should define the plugin metadata
│       └── It should define the lock manager
├── When calling updateVotingSettings
│   ├── Given the caller has permission to call updateVotingSettings
│   │   ├── It Should set the new values
│   │   └── It Settings() should return the right values
│   └── Given the caller has no permission to call updateVotingSettings
│       └── It Should revert
├── When calling setTargetConfig
│   └── Given the caller has no permission to call setTargetConfig
│       ├── It should revert if the new target is the pugin
│       ├── It should revert if the new target is the LockManager
│       └── It should revert if the new operation is delegatecall
├── When calling supportsInterface
│   ├── It does not support the empty interface
│   ├── It supports IERC165Upgradeable
│   ├── It supports IMembership
│   └── It supports ILockToVote
├── When calling createProposal
│   ├── Given create permission
│   │   ├── Given no minimum voting power
│   │   │   └── Given valid parameters
│   │   │       ├── It sets the given failuremap, if any
│   │   │       ├── It proposalIds are predictable and reproducible
│   │   │       ├── It sets the given voting mode, target, params and actions
│   │   │       ├── It emits an event
│   │   │       └── It reports proposalCreated() on the lockManager
│   │   ├── Given minimum voting power above zero
│   │   │   ├── It should succeed when the creator has enough balance
│   │   │   └── It should revert otherwise
│   │   ├── Given invalid dates
│   │   │   └── It should revert
│   │   └── Given duplicate proposal ID
│   │       └── It should revert
│   └── Given no create permission
│       └── It should revert
├── When calling canVote
│   ├── Given the proposal is open
│   │   ├── Given non empty vote
│   │   │   ├── Given submitting the first vote
│   │   │   │   ├── It should return true when the voter locked balance is positive
│   │   │   │   ├── It should return false when the voter has no locked balance
│   │   │   │   └── It should happen in all voting modes
│   │   │   └── Given voting again
│   │   │       ├── Given standard voting mode
│   │   │       │   ├── It should return true when voting the same with more balance
│   │   │       │   └── It should return false otherwise
│   │   │       └── Given vote replacement mode
│   │   │           ├── It should return true when the locked balance is higher
│   │   │           └── It should return false otherwise
│   │   └── Given empty vote
│   │       └── It should return false
│   ├── Given the proposal ended
│   │   ├── It should return false, regardless of prior votes
│   │   ├── It should return false, regardless of the locked balance
│   │   └── It should return false, regardless of the voting mode
│   └── Given the proposal is not created
│       └── It should revert
├── When calling vote
│   ├── Given canVote returns false // This relies on the tests above for canVote()
│   │   └── It should revert
│   ├── Given standard voting mode 2
│   │   ├── Given Voting the first time
│   │   │   ├── Given Has locked balance
│   │   │   │   ├── It should set the right voter's usedVotingPower
│   │   │   │   ├── It should set the right tally of the voted option
│   │   │   │   ├── It should set the right total voting power
│   │   │   │   └── It should emit an event
│   │   │   └── Given No locked balance // Redundant with canVote being false
│   │   │       └── It should revert
│   │   ├── Given Voting the same option
│   │   │   ├── Given Voting with the same locked balance // Redundant with canVote being false
│   │   │   │   └── It should revert
│   │   │   └── Given Voting with more locked balance
│   │   │       ├── It should increase the voter's usedVotingPower
│   │   │       ├── It should increase the tally of the voted option
│   │   │       ├── It should increase the total voting power
│   │   │       └── It should emit an event
│   │   └── Given Voting another option // Redundant with canVote being false
│   │       ├── Given Voting with the same locked balance 2
│   │       │   └── It should revert
│   │       └── Given Voting with more locked balance 2
│   │           └── It should revert
│   └── Given vote replacement mode 2
│       ├── Given Voting the first time 2
│       │   ├── Given Has locked balance 2
│       │   │   ├── It should set the right voter's usedVotingPower
│       │   │   ├── It should set the right tally of the voted option
│       │   │   ├── It should set the right total voting power
│       │   │   └── It should emit an event
│       │   └── Given No locked balance 2 // Redundant with canVote being false
│       │       └── It should revert
│       ├── Given Voting the same option 2
│       │   ├── Given Voting with the same locked balance 3 // Redundant with canVote being false
│       │   │   └── It should revert
│       │   └── Given Voting with more locked balance 3
│       │       ├── It should increase the voter's usedVotingPower
│       │       ├── It should increase the tally of the voted option
│       │       ├── It should increase the total voting power
│       │       └── It should emit an event
│       └── Given Voting another option 2
│           ├── Given Voting with the same locked balance 4
│           │   ├── It should deallocate the current voting power
│           │   └── It should allocate that voting power into the new vote option
│           └── Given Voting with more locked balance 4
│               ├── It should deallocate the current voting power
│               ├── It the voter's usedVotingPower should reflect the new balance
│               ├── It should allocate to the tally of the voted option
│               ├── It should update the total voting power
│               └── It should emit an event
├── When calling clearvote
│   ├── Given the voter has no prior voting power
│   │   └── It should do nothing
│   ├── Given the proposal is not open
│   │   └── It should revert
│   ├── Given standard voting mode 3
│   │   └── It should revert
│   └── Given vote replacement mode 3
│       ├── Given the caller is not the LockManager
│       │   └── It should revert
│       └── It should deallocate the current voting power
├── When calling getVote
│   ├── Given the vote exists
│   │   └── It should return the right data
│   └── Given the vote does not exist
│       └── It should return empty values
├── When Calling the proposal getters
│   ├── Given it does not exist
│   │   ├── It getProposal() returns empty values
│   │   ├── It isProposalOpen() returns false
│   │   ├── It isProposalEnded() returns false
│   │   ├── It hasSucceeded() should return false
│   │   ├── It canExecute() should return false
│   │   ├── It isSupportThresholdReached() should return false
│   │   ├── It isMinVotingPowerReached() should return true
│   │   ├── It isMinApprovalReached() should return true
│   │   └── It usedVotingPower() should return 0 for all voters
│   ├── Given it has not started
│   │   ├── It getProposal() returns the right values
│   │   ├── It isProposalOpen() returns false
│   │   ├── It isProposalEnded() returns false
│   │   ├── It hasSucceeded() should return false
│   │   ├── It canExecute() should return false
│   │   ├── It isSupportThresholdReached() should return false
│   │   ├── It isMinVotingPowerReached() should return false
│   │   ├── It isMinApprovalReached() should return false
│   │   └── It usedVotingPower() should return 0 for all voters
│   ├── Given it has not passed yet
│   │   ├── It getProposal() returns the right values
│   │   ├── It isProposalOpen() returns true
│   │   ├── It isProposalEnded() returns false
│   │   ├── It hasSucceeded() should return false
│   │   ├── It canExecute() should return false
│   │   ├── It isSupportThresholdReached() should return true
│   │   ├── It isMinVotingPowerReached() should return false
│   │   ├── It isMinApprovalReached() should return false
│   │   └── It usedVotingPower() should return the appropriate values
│   ├── Given it did not pass after endDate
│   │   ├── It getProposal() returns the right values
│   │   ├── It isProposalOpen() returns false
│   │   ├── It isProposalEnded() returns true
│   │   ├── It hasSucceeded() should return false
│   │   ├── It canExecute() should return false
│   │   ├── Given the support threshold was not achieved
│   │   │   └── It isSupportThresholdReached() should return false
│   │   ├── Given the support threshold was achieved
│   │   │   └── It isSupportThresholdReached() should return true
│   │   ├── Given the minimum voting power was not reached
│   │   │   └── It isMinVotingPowerReached() should return false
│   │   ├── Given the minimum voting power was reached
│   │   │   └── It isMinVotingPowerReached() should return true
│   │   ├── Given the minimum approval tally was not achieved
│   │   │   └── It isMinApprovalReached() should return false
│   │   ├── Given the minimum approval tally was achieved
│   │   │   └── It isMinApprovalReached() should return true
│   │   └── It usedVotingPower() should return the appropriate values
│   └── Given it has passed after endDate
│       ├── It getProposal() returns the right values
│       ├── It isProposalOpen() returns false
│       ├── It isProposalEnded() returns true
│       ├── It hasSucceeded() should return false
│       ├── Given The proposal has not been executed
│       │   ├── It canExecute() should return true
│       │   └── It isProposalEnded() returns true
│       ├── Given The proposal has been executed
│       │   ├── It canExecute() should return false
│       │   └── It isProposalEnded() returns true
│       ├── It isSupportThresholdReached() should return true
│       ├── It isMinVotingPowerReached() should return true
│       ├── It isMinApprovalReached() should return true
│       └── It usedVotingPower() should return the appropriate values
├── When calling canExecute and hasSucceeded
│   ├── Given the proposal exists
│   │   ├── Given the proposal is not executed
│   │   │   ├── Given minVotingPower is reached
│   │   │   │   ├── Given minApproval is reached
│   │   │   │   │   ├── Given isSupportThresholdReached is reached
│   │   │   │   │   │   ├── It canExecute() should return false before endDate
│   │   │   │   │   │   ├── It hasSucceeded() should return false before endDate
│   │   │   │   │   │   ├── It canExecute() should return true after endDate
│   │   │   │   │   │   └── It hasSucceeded() should return true after endDate
│   │   │   │   │   └── Given isSupportThresholdReached is not reached
│   │   │   │   │       ├── It canExecute() should return false
│   │   │   │   │       └── It hasSucceeded() should return false
│   │   │   │   └── Given minApproval is not reached
│   │   │   │       ├── It canExecute() should return false
│   │   │   │       └── It hasSucceeded() should return false
│   │   │   └── Given minVotingPower is not reached
│   │   │       ├── It canExecute() should return false
│   │   │       └── It hasSucceeded() should return false
│   │   └── Given the proposal is executed
│   │       ├── It canExecute() should return false
│   │       └── It hasSucceeded() should return true
│   └── Given the proposal does not exist
│       ├── It canExecute() should revert
│       └── It hasSucceeded() should revert
├── When calling execute
│   ├── Given the caller no permission to call execute
│   │   └── It should revert
│   └── Given the caller has permission to call execute
│       ├── Given canExecute returns false // This relies on the tests above for canExecute()
│       │   └── It should revert
│       └── Given canExecute returns true
│           ├── It should mark the proposal as executed
│           ├── It should make the target execute the proposal actions
│           ├── It should emit an event
│           └── It should call proposalEnded on the LockManager
├── When Calling isMember
│   ├── It Should return true when the sender has positive balance or locked tokens
│   └── It Should return false otherwise
├── When Calling customProposalParamsABI
│   └── It Should return the right value
├── When Calling currentTokenSupply
│   └── It Should return the right value
├── When Calling supportThresholdRatio
│   └── It Should return the right value
├── When Calling minParticipationRatio
│   └── It Should return the right value
├── When Calling proposalDuration
│   └── It Should return the right value
├── When Calling minProposerVotingPower
│   └── It Should return the right value
├── When Calling minApprovalRatio
│   └── It Should return the right value
├── When Calling votingMode
│   └── It Should return the right value
├── When Calling currentTokenSupply 2
│   └── It Should return the right value
├── When Calling lockManager
│   └── It Should return the right address
└── When Calling token
    └── It Should return the right address
```

```
LockToVotePluginSetupTest
├── When deploying a new instance
│   └── It completes without errors
├── When preparing an installation
│   ├── When passing an invalid token contract
│   │   └── It should revert
│   ├── It should return the plugin address
│   ├── It should return a list with the 3 helpers
│   ├── It all plugins use the same implementation
│   ├── It the plugin has the given settings
│   ├── It should set the address of the lockManager on the plugin
│   ├── It the plugin should have the right lockManager address
│   └── It the list of permissions should match
└── When preparing an uninstallation
    ├── Given a list of helpers with more or less than 3
    │   └── It should revert
    └── It generates a correct list of permission changes
```

```
MinVotingPowerConditionTest
├── When deploying the contract
│   ├── It records the given plugin address
│   └── It records the plugin's token address
└── When calling isGranted
    ├── Given a plugin with zero minimum voting power
    │   └── It should return true
    ├── Given a plugin with a minimum voting power
    │   ├── It should return true when 'who' holds the minimum voting power
    │   └── It should return false when 'who' holds less than the minimum voting power
    └── Given the sender created many proposals
        └── It the voting power required should be proportional to the amount of proposals created
```

```
PluginSetupForkTest
└── Given The deployer can install plugins
    ├── When Preparing and applying an installation
    │   └── It Successfully sets the appropriate permissions
    ├── When Installing a plugin without a minimum proposer voting power
    │   ├── It Anyone with the permission can create proposals
    │   ├── It Should revert when creating a proposal without permission
    │   └── It Anyone with the permission can execute proposals
    └── When Installing a plugin with a minimum proposer voting power
        ├── It Anyone with the permission and enough voting power can create proposals
        ├── It Should revert otherwise
        └── It Anyone with the permission can execute proposals
```

