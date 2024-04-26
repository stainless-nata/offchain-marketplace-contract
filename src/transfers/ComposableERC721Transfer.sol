// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IComposable} from "../interfaces/IComposable.sol";
import {Marketplace} from "../Marketplace.sol";

abstract contract ComposableERC721Transfer {
    error InvalidFingerprint();

    function _transferComposableERC721(Marketplace.Asset memory _asset, address _from) internal {
        IComposable composable = IComposable(_asset.contractAddress);

        (bytes32 fingerprint) = abi.decode(_asset.extra, (bytes32));

        if (!composable.verifyFingerprint(_asset.value, abi.encode(fingerprint))) {
            revert InvalidFingerprint();
        }

        composable.safeTransferFrom(_from, _asset.beneficiary, _asset.value);
    }
}
