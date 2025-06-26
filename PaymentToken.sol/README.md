# Deposit Token Demo

Note: This is a bit stale

This repo defines an example deposit token interface and implementation.

## Interface

The interface is defined in `contracts/IDepToken.sol`.

## Implementation

The implementation is defined in `contracts/Deposit.sol`.

## Proxy Pattern

There is a proxy set up in `contracts/UpgradabilityProxy.sol`, which is a lightly modified version of Circle's upgradability proxy. We will upgrade this in the near future to a more well defined proxy for our uses. 


## Authorizations
Authorizations are assumed to be passed in as arguments to the `transfer` function.
To specify the structure, we use the `authorizationFormat` function. 
The format should be a string as follows: 
```
Authorization(<type> <field1>,<type> <field2>,...,<type> <fieldN>)
```


