// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IComposableERC721} from "../interfaces/IComposableERC721.sol";

error InvalidFingerprint();

abstract contract ComposableERC721Transfer {
    function _transferComposableERC721(
        address _contractAddress,
        address _from,
        address _to,
        uint256 _tokenId,
        bytes memory _fingerprintAndData
    ) internal {
        IComposableERC721 composableErc721 = IComposableERC721(_contractAddress);

        (bytes32 fingerprint, bytes memory data) = abi.decode(_fingerprintAndData, (bytes32, bytes));

        if (!composableErc721.verifyFingerprint(_tokenId, abi.encode(fingerprint))) {
            revert InvalidFingerprint();
        }

        if (data.length > 0) {
            composableErc721.safeTransferFrom(_from, _to, _tokenId, data);
        } else {
            composableErc721.safeTransferFrom(_from, _to, _tokenId);
        }
    }
}
