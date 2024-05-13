// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {MarketplaceTypes} from "src/marketplace/MarketplaceTypes.sol";

abstract contract FeeCollector is MarketplaceTypes {
    address public feeCollector;
    uint256 public feeRate;

    event FeeCollectorUpdated(address indexed _caller, address indexed _feeCollector);
    event FeeRateUpdated(address indexed _caller, uint256 _feeRate);

    constructor(address _feeCollector, uint256 _feeRate) {
        _updateFeeCollector(msg.sender, _feeCollector);
        _updateFeeRate(msg.sender, _feeRate);
    }

    function _updateFeeCollector(address _caller, address _feeCollector) internal {
        feeCollector = _feeCollector;

        emit FeeCollectorUpdated(_caller, _feeCollector);
    }

    function _updateFeeRate(address _caller, uint256 _feeRate) internal {
        feeRate = _feeRate;

        emit FeeRateUpdated(_caller, _feeRate);
    }

    function _transferERC20WithCollectorFee(Asset memory _asset, address _from, address _feeCollector, uint256 _feeRate) internal {
        uint256 originalValue = _asset.value;
        uint256 fee = originalValue * _feeRate / 1_000_000;

        IERC20 erc20 = IERC20(_asset.contractAddress);

        SafeERC20.safeTransferFrom(erc20, _from, _asset.beneficiary, originalValue - fee);
        SafeERC20.safeTransferFrom(erc20, _from, _feeCollector, fee);
    }
}
