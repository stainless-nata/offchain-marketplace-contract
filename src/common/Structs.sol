// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

abstract contract Structs {
    struct ExternalCheck {
        address contractAddress;
        bytes4 selector;
        uint256 value;
        bool required;
    }

    struct Checks {
        uint256 uses;
        uint256 expiration;
        uint256 effective;
        bytes32 salt;
        uint256 contractSignatureIndex;
        uint256 signerSignatureIndex;
        address[] allowed;
        ExternalCheck[] externalChecks;
    }

    struct Asset {
        uint256 assetType;
        address contractAddress;
        uint256 value;
        address beneficiary;
        bytes extra;
        bytes unverifiedExtra;
    }

    struct Trade {
        address signer;
        bytes signature;
        Checks checks;
        Asset[] sent;
        Asset[] received;
    }

    struct Modifier {
        bytes signature;
        Checks checks;
        uint256 modifierType;
        bytes data;
    }
}
