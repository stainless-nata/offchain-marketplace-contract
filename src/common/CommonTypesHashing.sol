// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {CommonTypes} from "src/common/CommonTypes.sol";

/// @notice Hashing of the common types, used for EIP712 signature verification.
abstract contract CommonTypesHashing is CommonTypes {
    // keccak256("ExternalCheck(address contractAddress,bytes4 selector,uint256 value,bool required)")
    bytes32 private constant EXTERNAL_CHECK_TYPE_HASH = 0xdf361982fbc6415130c9d78e2e25ec087cf4812d4c0714d41cc56537ee15ac24;

    // keccak256("Checks(uint256 uses,uint256 expiration,uint256 effective,bytes32 salt,uint256 contractSignatureIndex,uint256 signerSignatureIndex,bytes32 allowedRoot,ExternalCheck[] externalChecks)ExternalCheck(address contractAddress,bytes4 selector,uint256 value,bool required)")
    bytes32 private constant CHECKS_TYPE_HASH = 0x89557aec12ebc349b5ea5576eaa65f16d3aa268692e31952528ce35c48cb9b3a;

    function _hashExternalChecks(ExternalCheck[] memory _externalChecks) private pure returns (bytes32[] memory) {
        bytes32[] memory hashes = new bytes32[](_externalChecks.length);

        for (uint256 i = 0; i < hashes.length; i++) {
            ExternalCheck memory externalCheck = _externalChecks[i];

            hashes[i] = keccak256(
                abi.encode(
                    EXTERNAL_CHECK_TYPE_HASH,
                    externalCheck.contractAddress,
                    externalCheck.selector,
                    externalCheck.value,
                    externalCheck.required
                )
            );
        }

        return hashes;
    }

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
                _checks.allowedRoot,
                keccak256(abi.encodePacked(_hashExternalChecks(_checks.externalChecks)))
            )
        );
    }
}
