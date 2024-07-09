# bun-token
Boundless Network Token


## Audit

TBD

## Specification

* ERC20
* ERC20Permit
* Ownable
* Burnable
* Pausable
* Access Control
  * admin role - admin operations(add role user or admin)
  * pause role - pause contract
  * system role - lock, revoke lock

## Contract

### Dependencies
 * OpenZeppelin Contracts ^5.0.0
 * solidity : ^0.8.20

### files
 * BunToken.sol  - bun token contract



## Compile contract

### compile
``
$ hardhat compile
``

then, json file for contract will be generated in artifacts/contracts/{BunToken.sol}.

### clean 

``
 $ hardhat clean
``

Then, artifacts directory will be removed.

## Flatten contract
``
$ hardhat flatten contracts/BunToken.sol > flatten-token.sol
``
