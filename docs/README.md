# Docs

NOTE: This codebase is just a sample imeplementation, and is not intended to be used in production.
The goal is to demonstrate how one may implement the features and ideas presented in our recent paper about 
regulated payment tokens. 
The wallet infrastructure and server are DEFINITELY NOT SECURE and should not be treated as such. 
Likewise these smart contracts have not undergone security audits. 

## Regulatory Authorized Transaction

## Simple Summary

This proposal offers a method for requresting bank approval for an asset transfer, and for communicating the information. 
This proposal also implements a number of administrative features, that are modern requirements for regulated assets. 

## Abstract

Here, we propose a standard which aims to allow regulated institutions the ability to authorize on-chain transactions before they are accepted. 

This enables the entity to:
- Sign off on transactions
- Specify the target for authorization requests
- Define an expected interface

## Motivation

Recently, there has been a growing interest in issuing regulated assets in non-traditional environments, such as on decentralized ledgers. 
These platforms have new and useful features that users enjoy, but so far, regulated asset issuers have had challenges in integrating with them. 
Largely, this is due to the fact that the regulatory processes are often quite complex, and the information required to perform the regulatory checks should not be stored on-chain due to reasonable privacy concerns. 
Here, we look to offer a solution that allows regulated institutions to issue assets on decentralized ledgers with minimal overhead, while still complying with the regulatory requirements. 

There are several existing specs which aim to solve this problem, and here we offer another model. 
Our design aims to be a minimal extension to the existing ERC-20 standard that enables off-chain compliance integration, with minimal additional requirements. 
This simple extension enables regulated institutions to handle regulatory compliance off-chain, and define their regulatory processes independent of the on-chain assets. 
Further, we hope that standardizing this model helps the development community to build tools that can work with a variety of regulated assets, without introducing significant development overhead. 

One additional goal of this proposal is to provide a demonstration for regulated asset issuers to use as a reference for how some regulatory processes may be implemented, and to further increase regulatory comfort in this space.

## Authorization Format

There are many valid constructions of an authorization commuinicated from the bank, and we do not presecribe a specific form. 
We do instead define a method by which wallets can reliably communicate with the bank to request authorizations.

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

## Global Freeze

Many assets in the regulated asset category need the ability to halt all transactions. 
This is effectively to act as a circuit breaker, to stop activity before a percieved problem gets worse. 
OpenZeppelin's `Pausable` module enables such restrictions to be enforced. 

## Per Account Freezing

Users of this platform may want to freeze their account for a variety of reasons, such as to prevent unauthorized access to their funds. 
Here, we offer a simple modifier which can be used to freeze an account, and restrict the ability for funds to flow through it until the account is unfrozen. 

## Upgradability

Smart contracts in Ethereum-like environments are generally defined to be immutable, to prevent bad actors from modifying a piece of code that users trust. 
However, the requirements on regulated assets change over time, and modifications to the smart contracts involved may be required. 
To enable upgrades without breaching the trust in smart contracts, we may deploy this system as a proxied contract. 
In particular, we may use the proxy pattern defined in ERC-1967, which enables safe upgradability of the code defining the digital asset's behavior, while preserving the contract's state and the address users may use to interact with the asset. Additionally, this protocol offers methods by which it can be made clear and obvious when upgrades to the protcol are made. 

## Account Abstraction

One nice-to-have feature is the ability to represent accounts by human-readable strings, and further to enable key rotation under strenuous circumstances. Account abstraction protocols typically enable both of these features. 
ERC-4337 is the most well known example of account abstraction, though it requires some important assumptions about the underlying protocol. However this is the state of the art and should generally be used when looking to support account abstraction. 
We provide [link to code] another option for account abstraction as an example for test in debug envirionemnts. 

## Key Rotation

One common issue in the cryptocurrency landscape is lost keys. Since this system has a centralized operator or owner, it is possible to rotate keys in a controlled manner, and is not difficult to implement. 
Assuming there is a controlled way to communicate with the bank, then accounts should be rotatable, and we demonstrate how this may be done.

## Relevance to ERC-7579

ERC-7579 may be another approach for implementing this sort of a regulated asset. The validation logic may be harbored in a specific module, and if a universal standard contract is accepted, then each regulated insitution may be better off implementing their compliance logic in a module rather than in a unique contract. 
There are many solutions in this space worth exploring, though the core features defined in this example are likely to be useful or required for regulated assets regardless of the underlying architecture.