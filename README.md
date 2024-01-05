# Decentralised shared wallet platform based on the Ethereum blockchain. 

## Main functionality:
- create a new shared wallet or check your existing ones
- Accept or decline invitations from other users to join their shared wallets
- Votes to send invitations,remove members, withdraw ether or destroy the wallet
- In order to do any operation at least 51% of the wallet members should agree

## Tech stack:
- Building: Solidity, Foundry,  OpenZeppelin 
- Testing: Foundry/Solidity

## Additional:
- Tried my best to optimize gas for all the calls
- Following EIP1167 minimal proxy pattern for cheap deploying of multiple wallets
- Big test coverage of 93%
- Tried to follow the same style guide for all the contracts to make the code consistent