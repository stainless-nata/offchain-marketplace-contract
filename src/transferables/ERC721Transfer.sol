// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

abstract contract ERC721Transfer {
    function _transferERC721(
        address _contractAddress,
        address _from,
        address _to,
        uint256 _tokenId,
        bytes memory _data
    ) internal {
        IERC721 erc721 = IERC721(_contractAddress);

        if (_data.length > 0) {
            erc721.safeTransferFrom(_from, _to, _tokenId, _data);
        } else {
            erc721.safeTransferFrom(_from, _to, _tokenId);
        }
    }
}
