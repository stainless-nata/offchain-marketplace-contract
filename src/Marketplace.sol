// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {EIP712} from "./external/EIP712.sol";
import {Verifications} from "./common/Verifications.sol";
import {ICoupons} from "./interfaces/ICoupons.sol";
import {AssetTransfers} from "./AssetTransfers.sol";
import {NativeMetaTransaction} from "./external/NativeMetaTransaction.sol";

contract Marketplace is NativeMetaTransaction, AssetTransfers, Verifications, Pausable, ReentrancyGuard {
    ICoupons public coupons;
    mapping(bytes32 => bool) public usedTradeIds;

    event CouponsUpdated(address indexed _caller, address indexed _coupons);
    event Traded(address indexed _caller, bytes32 indexed _signature);

    error UsedTradeId();
    error TradesAndCouponsLengthMismatch();

    constructor(address _owner, address _coupons, string memory _eip712Name, string memory _eip712Version)
        Ownable(_owner)
        EIP712(_eip712Name, _eip712Version)
    {
        _updateCoupons(_coupons);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function updateCoupons(address _coupons) external onlyOwner {
        _updateCoupons(_coupons);
    }

    function cancelSignature(Trade[] calldata _trades) external {
        address caller = _msgSender();

        for (uint256 i = 0; i < _trades.length; i++) {
            Trade memory trade = _trades[i];
            _verifyTradeSignature(trade, caller);
            bytes32 hashedSignature = keccak256(trade.signature);
            _cancelSignature(hashedSignature);
        }
    }

    function accept(Trade[] calldata _trades) external whenNotPaused nonReentrant {
        address caller = _msgSender();

        for (uint256 i = 0; i < _trades.length; i++) {
            _verifyTrade(_trades[i], caller);
            _accept(_trades[i], caller);
        }
    }

    function acceptWithCoupon(Trade[] calldata _trades, Coupon[] calldata _coupons) external whenNotPaused nonReentrant {
        address caller = _msgSender();

        if (_trades.length != _coupons.length) {
            revert TradesAndCouponsLengthMismatch();
        }

        for (uint256 i = 0; i < _trades.length; i++) {
            _verifyTrade(_trades[i], caller);
            _accept(coupons.applyCoupon(_trades[i], _coupons[i]), caller);
        }
    }

    function _accept(Trade memory _trade, address _caller) private {
        bytes32 hashedSignature = keccak256(_trade.signature);
        address signer = _trade.signer;

        emit Traded(_caller, hashedSignature);

        _transferAssets(_trade.sent, signer, _caller, signer, _caller);
        _transferAssets(_trade.received, _caller, signer, signer, _caller);
    }

    function getTradeId(Trade memory _trade, address _caller) public pure returns (bytes32) {
        bytes32 tradeId = keccak256(abi.encodePacked(_trade.checks.salt, _caller));

        for (uint256 i = 0; i < _trade.received.length; i++) {
            Asset memory asset = _trade.received[i];

            tradeId = keccak256(abi.encodePacked(tradeId, asset.contractAddress, asset.value));
        }

        return tradeId;
    }

    function _verifyTrade(Trade memory _trade, address _caller) private {
        bytes32 hashedSignature = keccak256(_trade.signature);
        address signer = _trade.signer;
        bytes32 tradeId = getTradeId(_trade, _caller);
        uint256 currentSignatureUses = signatureUses[hashedSignature];

        if (usedTradeIds[tradeId]) {
            revert UsedTradeId();
        }

        _verifyChecks(_trade.checks, hashedSignature, currentSignatureUses, signer, _caller);
        _verifyTradeSignature(_trade, signer);

        if (currentSignatureUses + 1 == _trade.checks.uses) {
            usedTradeIds[tradeId] = true;
        }

        signatureUses[hashedSignature]++;
    }

    function _verifyTradeSignature(Trade memory _trade, address _signer) private view {
        _verifySignature(_hashTrade(_trade), _trade.signature, _signer);
    }

    function _transferAssets(Asset[] memory _assets, address _from, address _to, address _signer, address _caller) private {
        for (uint256 i = 0; i < _assets.length; i++) {
            Asset memory asset = _assets[i];

            if (asset.beneficiary == address(0)) {
                asset.beneficiary = _to;
            }

            _transferAsset(asset, _from, _signer, _caller);
        }
    }

    function _msgSender() internal view override returns (address) {
        return _getMsgSender();
    }

    function _updateCoupons(address _coupons) private {
        coupons = ICoupons(_coupons);

        emit CouponsUpdated(_msgSender(), _coupons);
    }
}
