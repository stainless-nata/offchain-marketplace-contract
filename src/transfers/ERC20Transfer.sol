// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Marketplace} from "../Marketplace.sol";

error ERC20TransferFailed();

abstract contract ERC20Transfer {
    function _transferERC20(Marketplace.Asset memory _asset, address _from) internal {
        bool result = IERC20(_asset.contractAddress).transferFrom(_from, _asset.beneficiary, _asset.value);

        if (!result) {
            revert ERC20TransferFailed();
        }
    }
}
