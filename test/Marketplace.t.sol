// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Marketplace, InvalidSigner, Expired} from "../src/Marketplace.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockERC721} from "../src/mocks/MockERC721.sol";
import {MockCollection} from "../src/mocks/MockCollection.sol";

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
    uint256 signerPk;
    address signer;
    address caller;
    uint256 expiration;
    MarketplaceHarness mkt;
    MockERC20 erc20;
    MockERC721 erc721;
    MockCollection collection;

    function setUp() public {
        signerPk = 0xB0C4;

        signer = vm.addr(signerPk);
        caller = vm.addr(signerPk + 1);

        expiration = block.timestamp;

        mkt = new MarketplaceHarness();

        erc20 = new MockERC20();
        erc20.mint(signer, 1 ether);
        erc20.mint(caller, 1 ether);
        vm.prank(signer);
        erc20.approve(address(mkt), 1 ether);
        vm.prank(caller);
        erc20.approve(address(mkt), 1 ether);

        erc721 = new MockERC721();
        erc721.mint(signer, 1);
        erc721.mint(caller, 2);
        vm.prank(signer);
        erc721.approve(address(mkt), 1);
        vm.prank(caller);
        erc721.approve(address(mkt), 2);

        collection = new MockCollection();
    }

    function test_SetUpState() public {
        assertEq(erc20.balanceOf(signer), 1 ether);
        assertEq(erc20.balanceOf(caller), 1 ether);

        assertEq(erc721.ownerOf(1), signer);
        assertEq(erc721.ownerOf(2), caller);
    }

    function test_InvalidSignature() public {
        uint256 signerPk = 0xB0C4;

        address caller = vm.addr(signerPk + 1);

        MarketplaceHarness mkt = new MarketplaceHarness();

        Marketplace.Asset[] memory sent = new Marketplace.Asset[](0);
        Marketplace.Asset[] memory received = new Marketplace.Asset[](0);

        bytes32 digest = MessageHashUtils.toTypedDataHash(
            mkt.getDomainSeparator(),
            keccak256(abi.encode(mkt.getTradeTypeHash(), mkt.hashAssets(sent), mkt.hashAssets(received)))
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        bytes memory signature = abi.encodePacked(r, s, v);

        Marketplace.Trade memory trade = Marketplace.Trade({
            // The signer address would be correct in this case, but another one is being sent, so the InvalidSigner error should be expected.
            signer: caller,
            expiration: block.timestamp + 1,
            signature: signature,
            sent: sent,
            received: received
        });

        vm.prank(caller);
        vm.expectRevert(InvalidSigner.selector);
        mkt.accept(trade);
    }

    function test_Expiration() public {
        uint256 signerPk = 0xB0C4;

        address caller = vm.addr(signerPk + 1);

        MarketplaceHarness mkt = new MarketplaceHarness();

        Marketplace.Asset[] memory sent = new Marketplace.Asset[](0);
        Marketplace.Asset[] memory received = new Marketplace.Asset[](0);

        bytes32 digest = MessageHashUtils.toTypedDataHash(
            mkt.getDomainSeparator(),
            keccak256(abi.encode(mkt.getTradeTypeHash(), mkt.hashAssets(sent), mkt.hashAssets(received)))
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        bytes memory signature = abi.encodePacked(r, s, v);

        Marketplace.Trade memory trade = Marketplace.Trade({
            signer: caller,
            expiration: block.timestamp - 1,
            signature: signature,
            sent: sent,
            received: received
        });

        vm.prank(caller);
        vm.expectRevert(Expired.selector);
        mkt.accept(trade);
    }

    function test_Success() public {
        Marketplace.Asset[] memory sent = new Marketplace.Asset[](3);
        sent[0] = Marketplace.Asset({
            assetType: Marketplace.AssetType.ERC20,
            contractAddress: address(erc20),
            amountOrTokenId: 0.75 ether
        });
        sent[1] = Marketplace.Asset({
            assetType: Marketplace.AssetType.ERC721,
            contractAddress: address(erc721),
            amountOrTokenId: 1
        });
        sent[2] = Marketplace.Asset({
            assetType: Marketplace.AssetType.ITEM,
            contractAddress: address(collection),
            amountOrTokenId: 1
        });

        Marketplace.Asset[] memory received = new Marketplace.Asset[](3);
        received[0] = Marketplace.Asset({
            assetType: Marketplace.AssetType.ERC20,
            contractAddress: address(erc20),
            amountOrTokenId: 0.25 ether
        });
        received[1] = Marketplace.Asset({
            assetType: Marketplace.AssetType.ERC721,
            contractAddress: address(erc721),
            amountOrTokenId: 2
        });
        received[2] = Marketplace.Asset({
            assetType: Marketplace.AssetType.ITEM,
            contractAddress: address(collection),
            amountOrTokenId: 2
        });

        bytes32 digest = MessageHashUtils.toTypedDataHash(
            mkt.getDomainSeparator(),
            keccak256(abi.encode(mkt.getTradeTypeHash(), expiration, mkt.hashAssets(sent), mkt.hashAssets(received)))
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        bytes memory signature = abi.encodePacked(r, s, v);

        Marketplace.Trade memory trade = Marketplace.Trade({
            signer: signer,
            expiration: expiration,
            signature: signature,
            sent: sent,
            received: received
        });

        vm.prank(caller);
        mkt.accept(trade);

        assertEq(erc20.balanceOf(signer), 0.5 ether);
        assertEq(erc20.balanceOf(caller), 1.5 ether);
        assertEq(erc721.ownerOf(1), caller);
        assertEq(erc721.ownerOf(2), signer);
    }
}
