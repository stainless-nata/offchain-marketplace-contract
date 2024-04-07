// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

error InvalidSigner();

contract Marketplace is EIP712 {
    // keccak256("Asset(address contractAddress,uint256 amount)")
    bytes32 internal constant ASSET_TYPE_HASH = 0x3701fad26cac0416b3131e281bc886d3be98b66236cc4499a46950ad69037484;
    // keccak256("Trade(Asset[] sent, Asset[] received)Asset(address contractAddress,uint256 amount)")
    bytes32 internal constant TRADE_TYPE_HASH = 0xfda8eceb8abd3b6d6244a7652f0fb9aa18cd5cc92b769dc5ff72415b859f1b8f;

    struct Asset {
        address contractAddress;
        uint256 amount;
    }

    struct Trade {
        address signer;
        bytes signature;
        Asset[] sent;
        Asset[] received;
    }

    constructor() EIP712("Marketplace", "0.0.1") {}

    function accept(Trade calldata _trade) external {
        address recovered = ECDSA.recover(
            _hashTypedDataV4(
                keccak256(abi.encode(TRADE_TYPE_HASH, _hashAssets(_trade.sent), _hashAssets(_trade.received)))
            ),
            _trade.signature
        );

        if (recovered != _trade.signer) {
            revert InvalidSigner();
        }

        _transferAssets(_trade.sent, _trade.signer, msg.sender);
        _transferAssets(_trade.received, msg.sender, _trade.signer);
    }

    function _hashAssets(Asset[] memory _assets) internal pure returns (bytes memory) {
        bytes32[] memory hashes = new bytes32[](_assets.length);

        for (uint256 i = 0; i < hashes.length; i++) {
            hashes[i] = keccak256(abi.encode(ASSET_TYPE_HASH, _assets[i].contractAddress, _assets[i].amount));
        }

        return abi.encodePacked(hashes);
    }

    function _transferAssets(Asset[] memory _assets, address _from, address _to) internal {
        for (uint256 i = 0; i < _assets.length; i++) {
            IERC20(_assets[i].contractAddress).transferFrom(_from, _to, _assets[i].amount);
        }
    }
}
