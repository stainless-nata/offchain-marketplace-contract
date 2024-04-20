// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IComposableERC721} from "../interfaces/IComposableERC721.sol";
import {Marketplace} from "../Marketplace.sol";

error InvalidFingerprint();

abstract contract ComposableERC721Transfer {
    function _transferComposableERC721(Marketplace.Asset memory _asset, address _from) internal {
        IComposableERC721 composableErc721 = IComposableERC721(_asset.contractAddress);

        (bytes32 fingerprint, bytes memory data) = abi.decode(_asset.extra, (bytes32, bytes));

        if (!composableErc721.verifyFingerprint(_asset.value, abi.encode(fingerprint))) {
            revert InvalidFingerprint();
        }

        composableErc721.safeTransferFrom(_from, _asset.beneficiary, _asset.value, data);
    }
}
