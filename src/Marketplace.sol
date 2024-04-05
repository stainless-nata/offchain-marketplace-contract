// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

struct Asset {
    address contractAddress;
    uint256 amount;
}

struct Trade {
    address signer;
    bytes signature;
    bool testBool;
    // Asset[] received;
    // Asset[] sent;
}

contract Marketplace is EIP712 {
    constructor() EIP712("Marketplace", "0.0.1") {}

    function accept(Trade calldata trade) external pure {
        ECDSA.recover(keccak256(abi.encode(keccak256("Trade(bool testBool)"), true)), trade.signature);
    }
}
