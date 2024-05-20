// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {Signatures} from "src/common/Signatures.sol";
import {CommonTypes} from "src/common/CommonTypes.sol";

/// @notice Contract that provides a function to verify Checks.
abstract contract Verifications is Signatures, CommonTypes {
    /// bytes4(keccak256("balanceOf(address)"))
    bytes4 private constant BALANCE_OF_SELECTOR = 0x70a08231;

    /// bytes4(keccak256("ownerOf(uint256)"))
    bytes4 private constant OWNER_OF_SELECTOR = 0x6352211e;

    error UsingCancelledSignature();
    error SignatureReuse();
    error NotEffective();
    error InvalidContractSignatureIndex();
    error InvalidSignerSignatureIndex();
    error Expired();
    error NotAllowed();
    error ExternalChecksFailed();

    /// @dev Verifies that the Check values are correct and that the signature has not been canceled or overused.
    /// @param _checks The Checks to verify.
    /// @param _hashedSignature The hash of the signature.
    /// @param _currentSignatureUses The number of times the signature has been used.
    /// @param _signer The address that created the signature.
    /// @param _caller The address that sent the transaction.
    function _verifyChecks(Checks memory _checks, bytes32 _hashedSignature, uint256 _currentSignatureUses, address _signer, address _caller)
        internal
        view
    {
        if (cancelledSignatures[_hashedSignature]) {
            revert UsingCancelledSignature();
        }

        if (_checks.uses > 0 && _currentSignatureUses >= _checks.uses) {
            revert SignatureReuse();
        }

        if (_checks.effective > block.timestamp) {
            revert NotEffective();
        }

        if (contractSignatureIndex != _checks.contractSignatureIndex) {
            revert InvalidContractSignatureIndex();
        }

        if (signerSignatureIndex[_signer] != _checks.signerSignatureIndex) {
            revert InvalidSignerSignatureIndex();
        }

        if (_checks.expiration < block.timestamp) {
            revert Expired();
        }

        if (_checks.allowedRoot != 0) {
            _verifyAllowed(_checks.allowedRoot, _checks.allowedProof, _caller);
        }

        if (_checks.externalChecks.length > 0) {
            _verifyExternalChecks(_checks.externalChecks, _caller);
        }
    }

    /// @dev Verifies that the provided caller is allowed.
    /// @param _allowedRoot The Merkle Root of the allowed addresses.
    /// @param _allowedProof The Merkle Proof that validates that the caller is allowed.
    /// @param _caller The address that sent the transaction.
    function _verifyAllowed(bytes32 _allowedRoot, bytes32[] memory _allowedProof, address _caller) private pure {
        if (!MerkleProof.verify(_allowedProof, _allowedRoot, keccak256(bytes.concat(keccak256(abi.encode(address(_caller))))))) {
            revert NotAllowed();
        }
    }

    /// @dev Verifies that the external checks are met.
    /// @param _externalChecks The external checks to verify.
    /// @param _caller The address that sent the transaction.
    ///
    /// External checks can be defined as required or optional. If any required check fails, the function will revert.
    /// Regarding optional checks, it only makes sense when there are more than one. If there is only one optional check, even if there are other required checks, it will be treated as required.
    /// For example:
    /// - 1 optional check === 1 required check.
    /// - 1 required check + 1 optional check === 2 required checks.
    ///
    /// If the selector is `balanceOf`, it will be checked that the balance is greater than or equal to the `value`.
    /// If the selector is `ownerOf`, it will be checked that the owner of `value` is the caller.
    /// Otherwise, the function will call the selector with the caller and expect it returns true.
    function _verifyExternalChecks(ExternalCheck[] memory _externalChecks, address _caller) private view {
        bool hasOptionalChecks = false;
        bool hasPassingOptionalCheck = false;

        for (uint256 i = 0; i < _externalChecks.length; i++) {
            ExternalCheck memory externalCheck = _externalChecks[i];

            bool isRequiredCheck = externalCheck.required;

            if (!isRequiredCheck && hasPassingOptionalCheck) {
                continue;
            }

            bytes4 selector = externalCheck.selector;

            bytes memory functionData;

            if (selector == OWNER_OF_SELECTOR) {
                functionData = abi.encodeWithSelector(selector, externalCheck.value);
            } else {
                functionData = abi.encodeWithSelector(selector, _caller);
            }

            (bool success, bytes memory data) = externalCheck.contractAddress.staticcall(functionData);

            if (!success) {
                // Do nothing here, an unsuccessful call will be treated as a failed check later.
            } else if (selector == BALANCE_OF_SELECTOR) {
                success = abi.decode(data, (uint256)) >= externalCheck.value;
            } else if (selector == OWNER_OF_SELECTOR) {
                success = abi.decode(data, (address)) == _caller;
            } else {
                success = abi.decode(data, (bool));
            }

            // There is no need to proceed if a required check fails.
            if (!success && isRequiredCheck) {
                revert ExternalChecksFailed();
            }

            if (!isRequiredCheck) {
                hasOptionalChecks = true;

                if (success) {
                    hasPassingOptionalCheck = true;
                }
            }
        }

        if (hasOptionalChecks && !hasPassingOptionalCheck) {
            revert ExternalChecksFailed();
        }
    }
}
