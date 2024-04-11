// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

error ERC20TransferFailed();

abstract contract ERC20Transfer {
    function _transferERC20(address _contractAddress, address _from, address _to, uint256 _amount) internal {
        bool result = IERC20(_contractAddress).transferFrom(_from, _to, _amount);

        if (!result) {
            revert ERC20TransferFailed();
        }
    }
}
