// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Marketplace} from "../Marketplace.sol";

abstract contract ERC20Transfer {
    function _transferERC20(Marketplace.Asset memory _asset, address _from) internal {
        SafeERC20.safeTransferFrom(IERC20(_asset.contractAddress), _from, _asset.beneficiary, _asset.value);
    }
}
