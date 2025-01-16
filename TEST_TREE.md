# Test tree definitions

Below is the graphical definition of the contract tests implemented on [the test folder](./test)

```
LockManagerTest
├── Given Deploying the contract
│   ├── When Constructor has invalid unlock mode
│   │   └── It Should revert
│   └── When Constructor with valid params
│       ├── It Registers the DAO address
│       ├── It Stores the given settings
│       └── It Stores the given token addresses
├── When calling setPluginAddress
│   ├── Given Invalid plugin
│   │   └── It should revert
│   ├── When setPluginAddress without the permission
│   │   └── It should revert
│   └── When setPluginAddress with the permission
│       └── It should update the address
├── Given No locked tokens
│   ├── Given No token allowance no locked
│   │   ├── When Calling lock 1
│   │   │   └── It Should revert
│   │   ├── When Calling lockAndVote 1
│   │   │   └── It Should revert
│   │   └── When Calling vote 1
│   │       └── It Should revert
│   └── Given With token allowance no locked
│       ├── When Calling lock 2
│       │   ├── It Should allow any token holder to lock
│       │   ├── It Should approve with the full token balance
│       │   └── It Should emit an event
│       ├── When Calling lockAndVote 2
│       │   ├── It Should allow any token holder to lock
│       │   ├── It Should approve with the full token balance
│       │   ├── It The allocated token balance should have the full new balance
│       │   └── It Should emit an event
│       └── When Calling vote 2
│           └── It Should revert
├── Given Locked tokens
│   ├── Given No token allowance some locked
│   │   ├── When Calling lock 3
│   │   │   └── It Should revert
│   │   ├── When Calling lockAndVote 3
│   │   │   └── It Should revert
│   │   ├── When Calling vote same balance 3
│   │   │   └── It Should revert
│   │   └── When Calling vote more locked balance 3
│   │       ├── It Should approve with the full token balance
│   │       └── It Should emit an event
│   └── Given With token allowance some locked
│       ├── When Calling lock 4
│       │   ├── It Should allow any token holder to lock
│       │   ├── It Should approve with the full token balance
│       │   ├── It Should increase the locked amount
│       │   └── It Should emit an event
│       ├── When Calling lockAndVote no prior votes 4
│       │   ├── It Should allow any token holder to lock
│       │   ├── It Should approve with the full token balance
│       │   ├── It Should increase the locked amount
│       │   ├── It The allocated token balance should have the full new balance
│       │   └── It Should emit an event
│       ├── When Calling lockAndVote with prior votes 4
│       │   ├── It Should allow any token holder to lock
│       │   ├── It Should approve with the full token balance
│       │   ├── It Should increase the locked amount
│       │   ├── It The allocated token balance should have the full new balance
│       │   └── It Should emit an event
│       ├── When Calling vote same balance 4
│       │   └── It Should revert
│       └── When Calling vote more locked balance 4
│           ├── It Should approve with the full token balance
│           └── It Should emit an event
├── Given Calling lock or lockToVote
│   ├── Given Empty plugin
│   │   └── It Locking and voting should revert
│   └── Given Invalid token
│       ├── It Locking should revert
│       ├── It Locking and voting should revert
│       └── It Voting should revert
├── Given ProposalCreated is called
│   ├── When The caller is not the plugin proposalCreated
│   │   └── It Should revert
│   └── When The caller is the plugin proposalCreated
│       └── It Adds the proposal ID to the list of known proposals
├── Given ProposalEnded is called
│   ├── When The caller is not the plugin ProposalEnded
│   │   └── It Should revert
│   └── When The caller is the plugin ProposalEnded
│       └── It Removes the proposal ID from the list of known proposals
├── Given Strict mode is set
│   ├── Given Didnt lock anything strict
│   │   └── When Trying to unlock 1 strict
│   │       └── It Should revert
│   ├── Given Locked but didnt vote anywhere strict
│   │   └── When Trying to unlock 2 strict
│   │       ├── It Should unlock and refund the full amount right away
│   │       └── It Should emit an event
│   ├── Given Locked but voted on ended or executed proposals strict
│   │   └── When Trying to unlock 3 strict
│   │       ├── It Should unlock and refund the full amount right away
│   │       └── It Should emit an event
│   └── Given Locked and voted on currently active proposals strict
│       └── When Trying to unlock 4 strict
│           └── It Should revert
├── Given Flexible mode is set
│   ├── Given Didnt lock anything flexible
│   │   └── When Trying to unlock 1 flexible
│   │       └── It Should revert
│   ├── Given Locked but didnt vote anywhere flexible
│   │   └── When Trying to unlock 2 flexible
│   │       ├── It Should unlock and refund the full amount right away
│   │       └── It Should emit an event
│   ├── Given Locked but voted on ended or executed proposals flexible
│   │   └── When Trying to unlock 3 flexible
│   │       ├── It Should unlock and refund the full amount right away
│   │       └── It Should emit an event
│   └── Given Locked and voted on currently active proposals flexible
│       └── When Trying to unlock 4 flexible
│           ├── It Should deallocate the existing voting power from active proposals
│           ├── It Should unlock and refund the full amount
│           └── It Should emit an event
├── When Calling plugin
│   └── It Should return the right address
├── When Calling token
│   └── It Should return the right address
├── Given No underlying token
│   └── When Calling underlyingToken empty
│       └── It Should return the token address
└── Given Underlying token defined
    └── When Calling underlyingToken set
        └── It Should return the right address
```

```
LockToVoteTest
├── When deploying the contract
│   └── It should disable the initializers
├── Given A new proxy
│   └── When calling initialize
│       ├── It should set the DAO address
│       └── It should initialize normally
├── When calling updateSettings
│   ├── When updateSettings without the permission
│   │   └── It should revert
│   └── When updateSettings with the permission
│       └── It should update the values
├── When calling supportsInterface
│   ├── It does not support the empty interface
│   ├── It supports IERC165Upgradeable
│   ├── It supports IMembership
│   └── It supports ILockToVote
├── Given Proposal not created
│   ├── Given No proposal creation permission
│   │   └── When Calling createProposal no perm
│   │       └── It Should revert
│   ├── Given Proposal creation permission granted
│   │   ├── When Calling createProposal empty dates
│   │   │   ├── It Should register the new proposal
│   │   │   ├── It Should assign a unique proposalId to it
│   │   │   ├── It Should register the given parameters
│   │   │   ├── It Should start immediately
│   │   │   ├── It Should end after minDuration
│   │   │   ├── It Should emit an event
│   │   │   └── It Should call proposalCreated on the manager
│   │   ├── When Calling createProposal explicit dates
│   │   │   ├── It Should start at the given startDate
│   │   │   ├── It Should revert if endDate is before minDuration
│   │   │   ├── It Should end on the given endDate
│   │   │   ├── It Should call proposalCreated on the manager
│   │   │   └── It Should emit an event
│   │   └── When Calling createProposal with duplicate data
│   │       ├── It Should revert
│   │       └── It Different data should produce different proposalId's
│   ├── When Calling the getters not created
│   │   ├── It getProposal should return empty values
│   │   ├── It isProposalOpen should return false
│   │   ├── It canVote should return false
│   │   ├── It hasSucceeded should return false
│   │   └── It canExecute should return false
│   └── When Calling the rest of methods
│       └── It Should revert, even with the required permissions
├── Given Proposal created
│   ├── When Calling getProposal
│   │   └── It Should return the right values
│   ├── When Calling isProposalOpen
│   │   └── It Should return true
│   ├── When Calling canVote
│   │   └── It Should return true when there is balance left to allocate
│   ├── Given No lock manager permission
│   │   ├── When Calling vote
│   │   │   └── It Reverts, regardless of the balance
│   │   └── When Calling clearVote
│   │       └── It Reverts, regardless of the balance
│   ├── Given Lock manager permission is granted
│   │   ├── Given Proposal created unstarted
│   │   │   └── It Calling vote should revert, with or without balance
│   │   └── Given Proposal created and started
│   │       ├── When Calling vote no new locked balance
│   │       │   └── It Should revert
│   │       ├── When Calling vote new locked balance
│   │       │   ├── It Should increase the tally by the new amount
│   │       │   └── It Should emit an event
│   │       ├── When Calling clearVote no vote balance
│   │       │   └── It Should do nothing
│   │       └── When Calling clearVote with vote balance
│   │           ├── It Should unassign the current voter's approval
│   │           ├── It Should decrease the proposal tally by the right amount
│   │           ├── It Should emit an event
│   │           └── It usedVotingPower should return the right value
│   ├── When Calling hasSucceeded canExecute created
│   │   ├── It hasSucceeded should return false
│   │   └── It canExecute should return false
│   └── When Calling execute created
│       └── It Should revert, even with the required permission
├── Given Proposal defeated
│   ├── When Calling the getters defeated
│   │   ├── It getProposal should return the right values
│   │   ├── It isProposalOpen should return false
│   │   ├── It canVote should return false
│   │   ├── It hasSucceeded should return false
│   │   └── It canExecute should return false
│   ├── When Calling vote or clearVote defeated
│   │   ├── It Should revert for vote, despite having the permission
│   │   └── It Should do nothing for clearVote
│   └── When Calling execute defeated
│       └── It Should revert, with or without permission
├── Given Proposal passed
│   ├── When Calling the getters passed
│   │   ├── It getProposal should return the right values
│   │   ├── It isProposalOpen should return false
│   │   ├── It canVote should return false
│   │   ├── It hasSucceeded should return true
│   │   └── It canExecute should return true
│   ├── When Calling vote or clearVote passed
│   │   └── It Should revert, despite having the permission
│   ├── Given No execute proposal permission
│   │   └── When Calling execute no perm
│   │       └── It Should revert
│   └── Given Execute proposal permission
│       └── When Calling execute passed
│           ├── It Should execute the actions of the proposal on the target
│           ├── It Should call proposalEnded on the LockManager
│           └── It Should emit an event
├── Given Proposal executed
│   ├── When Calling the getters executed
│   │   ├── It getProposal should return the right values
│   │   ├── It isProposalOpen should return false
│   │   ├── It canVote should return false
│   │   ├── It hasSucceeded should return false
│   │   └── It canExecute should return false
│   ├── When Calling vote or clearVote executed
│   │   └── It Should revert, despite having the permission
│   └── When Calling execute executed
│       └── It Should revert regardless of the permission
├── When Calling isMember
│   ├── It Should return true when the sender has positive balance or locked tokens
│   └── It Should return false otherwise
├── When Calling customProposalParamsABI
│   └── It Should return the right value
├── Given Update voting settings permission granted
│   └── When Calling updatePluginSettings granted
│       ├── It Should set the new values
│       └── It Settings() should return the right values
└── Given No update voting settings permission
    └── When Calling updatePluginSettings not granted
        └── It Should revert
```

