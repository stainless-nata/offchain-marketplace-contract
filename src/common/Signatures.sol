// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {EIP712} from "src/common/EIP712.sol";

/// @dev Adds some functions to manage signatures.
abstract contract Signatures is Ownable, EIP712 {
    /// @notice Value of the current contract signature index.
    /// The owner of the contract can update this value to revoke signatures created with another value.
    uint256 public contractSignatureIndex;

    /// @notice Value of the current signer signature index.
    /// Signers can update this value to revoke signatures created with another value.
    mapping(address => uint256) public signerSignatureIndex;

    /// @notice Mapping of cancelled signatures.
    /// Signers can invalidate any particular signature by adding it to this mapping.
    mapping(bytes32 => bool) public cancelledSignatures;

    /// @notice Mapping of signature uses.
    /// Tracks how many times a signature has been used.
    /// Useful in case the signer wants to determine how many times a signature can be used.
    mapping(bytes32 => uint256) public signatureUses;

    event ContractSignatureIndexIncreased(address indexed _caller, uint256 indexed _newValue);
    event SignerSignatureIndexIncreased(address indexed _caller, uint256 indexed _newValue);
    event SignatureCancelled(address indexed _caller, bytes32 indexed _signature);

    error InvalidSignature();

    /// @notice Allows the owner of the contract to increase the contract signature index.
    /// Revokes all signatures created with a previous index.
    function increaseContractSignatureIndex() external onlyOwner {
        uint256 newIndex = ++contractSignatureIndex;
        emit ContractSignatureIndexIncreased(_msgSender(), newIndex);
    }

    /// @notice Allows the signer to increase their signature index.
    /// Revokes all signatures created by the signer with a previous index.
    function increaseSignerSignatureIndex() external {
        address caller = _msgSender();
        uint256 newIndex = ++signerSignatureIndex[caller];
        emit SignerSignatureIndexIncreased(caller, newIndex);
    }

    /// @dev Useful to cancel a signature so it cannot be used anymore.
    /// The implementation should call this function after validating that the caller is the creator of the signature.
    /// @param _hashedSignature The hash of the signature to cancel.
    function _cancelSignature(bytes32 _hashedSignature) internal {
        cancelledSignatures[_hashedSignature] = true;
        emit SignatureCancelled(_msgSender(), _hashedSignature);
    }

    /// @dev Verifies that a signature has been signed by a particular signer.
    /// @param _typeHash The type hash.
    /// @param _signature The signature.
    /// @param _signer The signer who is supposed to have signed the signature.
    function _verifySignature(bytes32 _typeHash, bytes memory _signature, address _signer) internal view {
        if (!SignatureChecker.isValidSignatureNow(_signer, _hashTypedDataV4(_typeHash), _signature)) {
            revert InvalidSignature();
        }
    }
}
