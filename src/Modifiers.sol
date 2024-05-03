// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Verifications} from "./common/Verifications.sol";
import {Structs} from "./common/Structs.sol";

interface IModifier {
    function applyModifier(Structs.Trade calldata _trade, Structs.Modifier calldata _modifier) external view returns (Structs.Trade memory);
}

abstract contract Modifiers is Verifications {
    // keccak256("Modifier(Checks checks,uint256 modifierId,bytes data)Checks(uint256 uses,uint256 expiration,uint256 effective,bytes32 salt,uint256 contractSignatureIndex,uint256 signerSignatureIndex,address[] allowed,ExternalCheck[] externalChecks)ExternalCheck(address contractAddress,bytes4 selector,uint256 value,bool required)")
    bytes32 private constant MODIFIER_TYPE_HASH = 0x5f8554ec0f2e85d95d0a1c8b4b287d433c736606ae28b55167c9bc7caa0c4a19;

    address public marketplace;
    mapping(IModifier => bool) public allowlist;

    event AllowedModifier(address indexed _caller, IModifier indexed _modifier, bool _value);

    constructor(address _marketplace) {
        marketplace = _marketplace;
    }

    function allow(IModifier _modifier, bool _value) external onlyOwner {
        allowlist[_modifier] = _value;

        emit AllowedModifier(_msgSender(), _modifier, _value);
    }

    function applyModifier(Trade calldata _trade, Modifier calldata _modifier) external virtual returns (Trade memory);
}
