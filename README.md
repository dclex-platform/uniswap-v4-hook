![1](https://github.com/user-attachments/assets/28fac85d-c169-4504-9fe4-a3f00ba957aa)

# DCLEX Uniswap V4 Hook

## Description
The DCLEX Hook is an innovative solution to ensure compliant trading of tokenized stocks in Uniswap V4. 

Uniswap V4 introduces hooks, a powerful new feature that allows to create customizable trading pools. The DCLEX Hook leverages this capability to prevent minting of ERC-6909 claim tokens, which would otherwise allow users to bypass DCLEX's identity verification system and violate securities regulations.

To address this, tokenized stocks issued by DCLEX can only be used with Uniswap V4 pools that have the DCLEX Hook. This requires a modification to the token contract, but DCLEX implemented this modification in its tokenized stocks in a way that it could be reused by other protocols to provide flash loans mechanism.

## Video
https://youtu.be/IPxoEpmu8CQ
