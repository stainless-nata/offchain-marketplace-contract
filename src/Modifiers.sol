// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Verifications} from "./common/Verifications.sol";
import {Structs} from "./common/Structs.sol";

interface IModifier {
    function applyModifier(Structs.Trade calldata _trade, Structs.Modifier calldata _modifier) external view returns (Structs.Trade memory);
}

abstract contract Modifiers is Verifications {
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
