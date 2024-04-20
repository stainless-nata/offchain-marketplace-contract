// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {Marketplace} from "../Marketplace.sol";

abstract contract ERC721Transfer {
    function _transferERC721(Marketplace.Asset memory _asset, address _from) internal {
        IERC721(_asset.contractAddress).safeTransferFrom(_from, _asset.beneficiary, _asset.value, _asset.extra);
    }
}
