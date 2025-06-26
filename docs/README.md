# Docs

NOTE: This codebase is just a sample imeplementation, and is not intended to be used in production.
The goal is to demonstrate how one may implement the features and ideas presented in our recent paper about 
regulated payment tokens. 
The wallet infrastructure and server are DEFINITELY NOT SECURE and should not be treated as such. 
Likewise these smart contracts have not undergone security audits. 

## Regulatory Authorized Transaction

## Simple Summary
This proposal offers a method for requresting bank approval for an asset transfer, and for communicating the information.

## Abstract

Here, we propose a standard which aims to allow regulated institutions the ability to authorize on-chain transactions before they are accepted. 

This enables the entity to:
- Sign off on transactions
- Specify the target for authorization requests
- Define an expected interface

## Motivation

Institutions issuing regulated assets are often required to comply with government regulations, and frequently are required to authorize transactions before they can be processed. 
Some such institutions have recently expressed interest in issuing such tokenized assets on decentralized ledgers [cite payment token paper]. 
There are several existing specs which aim to solve this problem,however the models which they propose are not always sufficient, in particular when the entirety of the compliance check is better handled off-chain in the contemporary regulatory environment. 
There are a few reasons that performing these compliance checks off chain is advantageous. 
The first is there is then a reduced concern of information leakage of sensitive information required for compliance checks. The second is there is a smaller on-chain storage requirement. And the third is that in certain regulatory contexts, there is little room for error in when a user's approval status changes, and when transactions must stop being processed on their behalf.

The goal is to impose this standard such that web3 technology providers may design products (such as wallets) which may correspond with FIs in a consistent manner. Therefore this is as much of a standards proposal for FI interfaces as it is for smart contract design.

## Authorization Format

There are many valid constructions of an authorization commuinicated from the bank, and we do not presecribe a specific form. 

However, a requirement for these authorizations is that they must be tied to at least one piece of on-chain state, for the purpose of negating replay attacks.
One option is a per-account nonce, defined in the contract itself. The financial institution may sign over a transaction referring to this specific nonce, which is expired at the end of the transaction, therefore preventing the user from replaying an authorization. 
An extension of this might be to provide an authorization signed over multiple nonces, and therefore usable over multiple transactions meeting the authorization pattern.

![image](https://hackmd.io/_uploads/rkhTvQ-bxx.png)



## Controls Info Submission

Controls information, in our model, is processed by the bank. However, users must know how to send such information 
at the time of the transaction. As such, we specify that the wallet can request the corresponding URI via the request `authorizationURI()`.

Importantly, this simply returns a URI which the wallet can correspond with. It is the responsibility of the bank
to further store information either on-chain or elsewhere publicly that indicates to the wallet how it may 
submit authorization information to the bank. 
We implement this using the `payloadInfo()` call on our smart contract. 

<!--- Insert diagram here showing payload info, maybe an XML window ---> 

## Asset Siezure Control Flow

Asset seizure is a particular type of regulatory control that has a fairly specific requirement. 
In particular, there are requirements that seized assets are held in a particular account, from which
assets may flow back to the user, or be claimed by a regulatory authority or the bank. 
So we define a particular flow that indicates funds should move into an escrow account, from which they can flow into an account controlled
by the bank, or back to the user wallet. 
Importantly, this seizing process must be controllable by the bank.

# Existing Features

## Global Freeze

Many assets in the regulated asset category need the ability to halt all transactions. 
This is effectively to act as a circuit breaker, to stop activity before a percieved problem gets worse. 
OpenZeppelin's `Pausable` module enables such restrictions to be enforced. 

## Upgradability

Smart contracts in Ethereum-like environments are generally defined to be immutable, to prevent bad actors from modifying a piece of code that users trust. 
However, the requirements on regulated assets change over time, and modifications to the smart contracts involved may be required. 
To enable upgrades without breaching the trust in smart contracts, we may deploy this system as a proxied contract. 
In particular, we may use the proxy pattern defined in ERC-1967, which enables safe upgradability of the code defining the digital asset's behavior, while preserving the contract's state and the address users may use to interact with the asset. Additionally, this protocol offers methods by which it can be made clear and obvious when upgrades to the protcol are made. 

## Account Abstraction

One nice-to-have feature is the ability to represent accounts by human-readable strings, and further to enable key rotation under strenuous circumstances. Account abstraction protocols typically enable both of these features. 
ERC-4337 is the most well known example of account abstraction, though it requires some important assumptions about the underlying protocol. However this is the state of the art and should generally be used when looking to support account abstraction. 
We provide [link to code] another option for account abstraction as an example for test in debug envirionemnts. 

## Relevance to ERC-7579

ERC-7579