// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

error InvalidSigner();

contract Marketplace is EIP712 {
    bytes32 public constant TRADE_TYPEHASH = keccak256("Trade(bool testBool)");

    struct Asset {
        address contractAddress;
        uint256 amount;
    }

    struct Trade {
        address signer;
        bytes signature;
        bool testBool;
    }

    constructor() EIP712("Marketplace", "0.0.1") {}

    function getDomainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function accept(Trade calldata trade) external pure {
        address signer = ECDSA.recover(keccak256(abi.encode(TRADE_TYPEHASH, trade.testBool)), trade.signature);

        if (signer != trade.signer) {
            revert InvalidSigner();
        }
    }
}
