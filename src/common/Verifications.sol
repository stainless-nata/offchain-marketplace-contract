// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Signatures} from "./Signatures.sol";
import {Structs} from "./Structs.sol";

abstract contract Verifications is Signatures, Structs {
    // keccak256("ExternalCheck(address contractAddress,bytes4 selector,uint256 value,bool required)")
    bytes32 private constant EXTERNAL_CHECK_TYPE_HASH = 0xdf361982fbc6415130c9d78e2e25ec087cf4812d4c0714d41cc56537ee15ac24;

    // keccak256("Checks(uint256 uses,uint256 expiration,uint256 effective,bytes32 salt,uint256 contractSignatureIndex,uint256 signerSignatureIndex,address[] allowed,ExternalCheck[] externalChecks)ExternalCheck(address contractAddress,bytes4 selector,uint256 value,bool required)")
    bytes32 private constant CHECKS_TYPE_HASH = 0x2f962336c5429beb00c5ed44703aebcb2aaf2600ba276ef74dc82ca3bc073651;

    /// bytes4(keccak256("balanceOf(address)"))
    bytes4 private constant BALANCE_OF_SELECTOR = 0x70a08231;

    /// bytes4(keccak256("ownerOf(uint256)"))
    bytes4 private constant OWNER_OF_SELECTOR = 0x6352211e;

    error NotEffective();
    error InvalidContractSignatureIndex();
    error InvalidSignerSignatureIndex();
    error Expired();
    error NotAllowed();
    error ExternalChecksFailed();

    function _hashChecks(Checks memory _checks) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                CHECKS_TYPE_HASH,
                _checks.uses,
                _checks.expiration,
                _checks.effective,
                _checks.salt,
                _checks.contractSignatureIndex,
                _checks.signerSignatureIndex,
                keccak256(abi.encodePacked(_checks.allowed)),
                keccak256(abi.encodePacked(_hashExternalChecks(_checks.externalChecks)))
            )
        );
    }

    function _hashExternalChecks(ExternalCheck[] memory _externalChecks) internal pure returns (bytes32[] memory) {
        bytes32[] memory hashes = new bytes32[](_externalChecks.length);

        for (uint256 i = 0; i < hashes.length; i++) {
            ExternalCheck memory externalCheck = _externalChecks[i];

            hashes[i] = keccak256(
                abi.encode(
                    EXTERNAL_CHECK_TYPE_HASH, externalCheck.contractAddress, externalCheck.selector, externalCheck.value, externalCheck.required
                )
            );
        }

        return hashes;
    }

    function _verifyChecks(Checks memory _checks, uint256 _currentSignatureUses, address _signer, address _caller) internal view {
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

        if (_checks.allowed.length > 0) {
            _verifyAllowed(_checks.allowed, _caller);
        }

        if (_checks.externalChecks.length > 0) {
            _verifyExternalChecks(_checks.externalChecks, _caller);
        }
    }

    function _verifyAllowed(address[] memory _allowed, address _caller) private pure {
        for (uint256 j = 0; j < _allowed.length; j++) {
            if (_allowed[j] == _caller) {
                return;
            }
        }

        revert NotAllowed();
    }

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