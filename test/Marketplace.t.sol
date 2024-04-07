// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Marketplace, InvalidSigner} from "../src/Marketplace.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockERC721} from "../src/mocks/MockERC721.sol";

contract MarketplaceHarness is Marketplace {
    function getDomainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function hashAssets(Asset[] memory assets) external pure returns (bytes memory) {
        return _hashAssets(assets);
    }

    function getAssetTypeHash() external pure returns (bytes32) {
        return ASSET_TYPE_HASH;
    }

    function getTradeTypeHash() external pure returns (bytes32) {
        return TRADE_TYPE_HASH;
    }
}

contract Accept is Test {
    function setUp() public {}

    function test_SuccessERC20() public {
        uint256 signerPk = 0xB0C4;

        address signer = vm.addr(signerPk);
        address caller = vm.addr(signerPk + 1);

        MarketplaceHarness mkt = new MarketplaceHarness();

        MockERC20 erc20 = new MockERC20();

        erc20.mint(signer, 1 ether);
        erc20.mint(caller, 1 ether);

        vm.prank(signer);
        erc20.approve(address(mkt), 1 ether);

        vm.prank(caller);
        erc20.approve(address(mkt), 1 ether);

        assertEq(erc20.balanceOf(signer), 1 ether);
        assertEq(erc20.balanceOf(caller), 1 ether);

        Marketplace.Asset[] memory sent = new Marketplace.Asset[](1);
        sent[0] = Marketplace.Asset({
            assetType: Marketplace.AssetType.ERC20,
            contractAddress: address(erc20),
            amountOrTokenId: 0.75 ether
        });

        Marketplace.Asset[] memory received = new Marketplace.Asset[](1);
        received[0] = Marketplace.Asset({
            assetType: Marketplace.AssetType.ERC20,
            contractAddress: address(erc20),
            amountOrTokenId: 0.25 ether
        });

        bytes32 digest = MessageHashUtils.toTypedDataHash(
            mkt.getDomainSeparator(),
            keccak256(abi.encode(mkt.getTradeTypeHash(), mkt.hashAssets(sent), mkt.hashAssets(received)))
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        bytes memory signature = abi.encodePacked(r, s, v);

        Marketplace.Trade memory trade =
            Marketplace.Trade({signer: signer, signature: signature, sent: sent, received: received});

        vm.prank(caller);
        mkt.accept(trade);

        assertEq(erc20.balanceOf(signer), 0.5 ether);
        assertEq(erc20.balanceOf(caller), 1.5 ether);
    }

    function test_SuccessERC721() public {
        uint256 signerPk = 0xB0C4;

        address signer = vm.addr(signerPk);
        address caller = vm.addr(signerPk + 1);

        MarketplaceHarness mkt = new MarketplaceHarness();

        MockERC721 erc721 = new MockERC721();

        erc721.mint(signer, 1);
        erc721.mint(caller, 2);

        vm.prank(signer);
        erc721.approve(address(mkt), 1);

        vm.prank(caller);
        erc721.approve(address(mkt), 2);

        assertEq(erc721.ownerOf(1), signer);
        assertEq(erc721.ownerOf(2), caller);

        Marketplace.Asset[] memory sent = new Marketplace.Asset[](1);
        sent[0] = Marketplace.Asset({
            assetType: Marketplace.AssetType.ERC721,
            contractAddress: address(erc721),
            amountOrTokenId: 1
        });

        Marketplace.Asset[] memory received = new Marketplace.Asset[](1);
        received[0] = Marketplace.Asset({
            assetType: Marketplace.AssetType.ERC721,
            contractAddress: address(erc721),
            amountOrTokenId: 2
        });

        bytes32 digest = MessageHashUtils.toTypedDataHash(
            mkt.getDomainSeparator(),
            keccak256(abi.encode(mkt.getTradeTypeHash(), mkt.hashAssets(sent), mkt.hashAssets(received)))
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        bytes memory signature = abi.encodePacked(r, s, v);

        Marketplace.Trade memory trade =
            Marketplace.Trade({signer: signer, signature: signature, sent: sent, received: received});

        vm.prank(caller);
        mkt.accept(trade);

        assertEq(erc721.ownerOf(1), caller);
        assertEq(erc721.ownerOf(2), signer);
    }
}
