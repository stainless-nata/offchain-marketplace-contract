// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import {EIP712} from "../external/EIP712.sol";

abstract contract Signatures is Ownable, EIP712 {
    uint256 public contractSignatureIndex;
    mapping(address => uint256) public signerSignatureIndex;
    mapping(bytes32 => bool) public cancelledSignatures;
    mapping(bytes32 => uint256) public signatureUses;

    event ContractSignatureIndexIncreased(address indexed _caller, uint256 indexed _newValue);
    event SignerSignatureIndexIncreased(address indexed _caller, uint256 indexed _newValue);
    event SignatureCancelled(address indexed _caller, bytes32 indexed _signature);

    error CancelledSignature();
    error SignatureReuse();
    error InvalidSignature();

    function increaseContractSignatureIndex() external onlyOwner {
        uint256 newIndex = ++contractSignatureIndex;

        emit ContractSignatureIndexIncreased(_msgSender(), newIndex);
    }

    function increaseSignerSignatureIndex() external {
        address caller = _msgSender();
        uint256 newIndex = ++signerSignatureIndex[caller];

        emit SignerSignatureIndexIncreased(caller, newIndex);
    }

    function _cancelSignature(bytes32 _signature) internal {
        cancelledSignatures[_signature] = true;

        emit SignatureCancelled(_msgSender(), _signature);
    }

    function _verifySignature(bytes32 _typeHash, bytes memory _signature, address _signer) internal view {
        if (!SignatureChecker.isValidSignatureNow(_signer, _hashTypedDataV4(_typeHash), _signature)) {
            revert InvalidSignature();
        }
    }
}