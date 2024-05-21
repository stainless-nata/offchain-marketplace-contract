// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract MockExternalChecks {
    address public ownerOfResult;
    uint256 public balanceOfResult;
    bool public customCheckFunctionResult;

    function setOwnerOfResult(address _ownerOfResult) external {
        ownerOfResult = _ownerOfResult;
    }

    function setBalanceOfResult(uint256 _balanceOfResult) external {
        balanceOfResult = _balanceOfResult;
    }

    function setCustomCheckFunctionResult(bool _customCheckFunctionResult) external {
        customCheckFunctionResult = _customCheckFunctionResult;
    }

    function ownerOf(uint256) external view returns (address) {
        return ownerOfResult;
    }

    function balanceOf(address) external view returns (uint256) {
        return balanceOfResult;
    }

    function customCheckFunction(address, uint256) external view returns (bool) {
        return customCheckFunctionResult;
    }
}
