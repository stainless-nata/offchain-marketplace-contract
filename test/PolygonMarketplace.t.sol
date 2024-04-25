// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {VmSafe} from "lib/forge-std/src/Vm.sol";
import {PolygonMarketplace} from "../src/PolygonMarketplace.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {MessageHashUtils} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC721} from "lib/openzeppelin-contracts/contracts/interfaces/IERC721.sol";
import {ICollection} from "src/interfaces/ICollection.sol";
import {NativeMetaTransaction} from "src/external/NativeMetaTransaction.sol";

contract MarketplaceHarness is PolygonMarketplace {
    constructor(address _owner) PolygonMarketplace(_owner) {}

    function getDomainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function hashTrade(Trade memory _trade) external pure returns (bytes32) {
        return _hashTrade(_trade);
    }
}

contract PolygonMarketplaceTest is Test {
    VmSafe.Wallet signer;
    VmSafe.Wallet signer2;

    address caller;

    MarketplaceHarness marketplace;

    error UnsupportedAssetType(uint256 _assetType);
    error InvalidFingerprint();
    error NotCreator();

    function setUp() public {
        string memory rpcUrl = "https://rpc.decentraland.org/polygon";
        uint256 blockNumber = 56166590; // Apr-23-2024 03:17:09 PM +UTC

        uint256 forkId = vm.createFork(rpcUrl, blockNumber);
        vm.selectFork(forkId);

        signer = vm.createWallet("signer");
        signer2 = vm.createWallet("signer2");

        caller = vm.addr(0xB0C4);

        address owner = vm.addr(0x1);
        marketplace = new MarketplaceHarness(owner);
    }

    function test_accept_RevertsIfUnsupportedAssetType() public {
        uint256 assetType = 3;

        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        {
            trades[0].expiration = block.timestamp;

            trades[0].sent = new MarketplaceHarness.Asset[](1);
            trades[0].sent[0].assetType = assetType;

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(signer.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

            trades[0].signer = signer.addr;
            trades[0].signature = abi.encodePacked(r, s, v);
        }

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(UnsupportedAssetType.selector, assetType));
        marketplace.accept(trades);
    }

    function test_accept_sendWearable_receiveMANA() public {
        IERC20 mana = IERC20(0xA1c57f48F0Deb89f569dFbE6E2B7f46D33606fD4);
        IERC721 collection = IERC721(0x04e154dB53007bDfF215cc95b944018bBac81bc0);
        uint256 tokenId = 8;

        {
            address originalNftOwner = 0xa6c6DC29B99E8e7c919a5d2Ea426874ad15eA0ed;
            address originalManaHolder = 0x673e6B75a58354919FF5db539AA426727B385D17;

            vm.prank(originalNftOwner);
            collection.transferFrom(originalNftOwner, signer.addr, tokenId);

            vm.prank(originalManaHolder);
            mana.transfer(caller, 1 ether);

            vm.prank(signer.addr);
            collection.setApprovalForAll(address(marketplace), true);

            vm.prank(caller);
            mana.approve(address(marketplace), 1 ether);

            assertEq(collection.ownerOf(tokenId), signer.addr);
            assertEq(mana.balanceOf(caller), 1 ether);
        }

        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        {
            trades[0].expiration = block.timestamp;

            trades[0].sent = new MarketplaceHarness.Asset[](1);

            trades[0].sent[0].assetType = marketplace.ERC721_ID();
            trades[0].sent[0].contractAddress = address(collection);
            trades[0].sent[0].value = tokenId;

            trades[0].received = new MarketplaceHarness.Asset[](1);

            trades[0].received[0].assetType = marketplace.ERC20_ID();
            trades[0].received[0].contractAddress = address(mana);
            trades[0].received[0].value = 1 ether;

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(signer.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

            trades[0].signer = signer.addr;
            trades[0].signature = abi.encodePacked(r, s, v);
        }

        vm.prank(caller);
        marketplace.accept(trades);

        assertEq(collection.ownerOf(tokenId), caller);
        assertEq(mana.balanceOf(signer.addr), 1 ether);
    }

    function test_accept_sendWearable_receiveMANA_MetaTransaction() public {
        IERC20 mana = IERC20(0xA1c57f48F0Deb89f569dFbE6E2B7f46D33606fD4);
        IERC721 collection = IERC721(0x04e154dB53007bDfF215cc95b944018bBac81bc0);
        uint256 tokenId = 8;

        {
            address originalNftOwner = 0xa6c6DC29B99E8e7c919a5d2Ea426874ad15eA0ed;
            address originalManaHolder = 0x673e6B75a58354919FF5db539AA426727B385D17;

            vm.prank(originalNftOwner);
            collection.transferFrom(originalNftOwner, signer.addr, tokenId);

            vm.prank(originalManaHolder);
            mana.transfer(signer2.addr, 1 ether);

            vm.prank(signer.addr);
            collection.setApprovalForAll(address(marketplace), true);

            vm.prank(signer2.addr);
            mana.approve(address(marketplace), 1 ether);

            assertEq(collection.ownerOf(tokenId), signer.addr);
            assertEq(mana.balanceOf(signer2.addr), 1 ether);
        }

        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        {
            trades[0].expiration = block.timestamp;

            trades[0].sent = new MarketplaceHarness.Asset[](1);

            trades[0].sent[0].assetType = marketplace.ERC721_ID();
            trades[0].sent[0].contractAddress = address(collection);
            trades[0].sent[0].value = tokenId;

            trades[0].received = new MarketplaceHarness.Asset[](1);

            trades[0].received[0].assetType = marketplace.ERC20_ID();
            trades[0].received[0].contractAddress = address(mana);
            trades[0].received[0].value = 1 ether;

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(signer.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

            trades[0].signer = signer.addr;
            trades[0].signature = abi.encodePacked(r, s, v);
        }

        NativeMetaTransaction.MetaTransaction memory metaTrx;
        bytes memory metaTrxSignature;

        {
            metaTrx.nonce = 0;
            metaTrx.from = signer2.addr;
            metaTrx.functionData = abi.encodeWithSelector(marketplace.accept.selector, trades);

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(
                signer2.privateKey,
                MessageHashUtils.toTypedDataHash(
                    marketplace.getDomainSeparator(),
                    keccak256(
                        abi.encode(
                            keccak256(bytes("MetaTransaction(uint256 nonce,address from,bytes functionData)")),
                            metaTrx.nonce,
                            metaTrx.from,
                            keccak256(metaTrx.functionData)
                        )
                    )
                )
            );

            metaTrxSignature = abi.encodePacked(r, s, v);
        }

        vm.prank(caller);
        marketplace.executeMetaTransaction(metaTrx.from, metaTrx.functionData, metaTrxSignature);

        assertEq(collection.ownerOf(tokenId), signer2.addr);
        assertEq(mana.balanceOf(signer.addr), 1 ether);
    }

    function test_accept_sendWearable_receiveMANA_withDAOFee() public {
        IERC20 mana = IERC20(0xA1c57f48F0Deb89f569dFbE6E2B7f46D33606fD4);
        IERC721 collection = IERC721(0x04e154dB53007bDfF215cc95b944018bBac81bc0);
        uint256 tokenId = 8;
        address dao = 0xB08E3e7cc815213304d884C88cA476ebC50EaAB2;
        uint256 daoBalance = mana.balanceOf(dao);

        {
            address originalNftOwner = 0xa6c6DC29B99E8e7c919a5d2Ea426874ad15eA0ed;
            address originalManaHolder = 0x673e6B75a58354919FF5db539AA426727B385D17;

            vm.prank(originalNftOwner);
            collection.transferFrom(originalNftOwner, signer.addr, tokenId);

            vm.prank(originalManaHolder);
            mana.transfer(caller, 1 ether);

            vm.prank(signer.addr);
            collection.setApprovalForAll(address(marketplace), true);

            vm.prank(caller);
            mana.approve(address(marketplace), 1 ether);

            assertEq(collection.ownerOf(tokenId), signer.addr);
            assertEq(mana.balanceOf(caller), 1 ether);
        }

        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        {
            trades[0].expiration = block.timestamp;

            trades[0].sent = new MarketplaceHarness.Asset[](1);

            trades[0].sent[0].assetType = marketplace.ERC721_ID();
            trades[0].sent[0].contractAddress = address(collection);
            trades[0].sent[0].value = tokenId;

            trades[0].received = new MarketplaceHarness.Asset[](2);

            trades[0].received[0].assetType = marketplace.ERC20_ID();
            trades[0].received[0].contractAddress = address(mana);
            trades[0].received[0].value = 0.7 ether;

            trades[0].received[1].assetType = marketplace.ERC20_ID();
            trades[0].received[1].contractAddress = address(mana);
            trades[0].received[1].value = 0.3 ether;
            trades[0].received[1].beneficiary = dao;

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(signer.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

            trades[0].signer = signer.addr;
            trades[0].signature = abi.encodePacked(r, s, v);
        }

        vm.prank(caller);
        marketplace.accept(trades);

        assertEq(collection.ownerOf(tokenId), caller);
        assertEq(mana.balanceOf(signer.addr), 0.7 ether);
        assertEq(mana.balanceOf(dao), daoBalance + 0.3 ether);
    }

    function test_accept_mintItem_receiveMANA() public {
        IERC20 mana = IERC20(0xA1c57f48F0Deb89f569dFbE6E2B7f46D33606fD4);
        ICollection collection = ICollection(0x05267a0E08C9B756a000362d2B2c7E3ce29E740D);
        uint256 itemId = 0;

        {
            address originalCollectionCreator = 0x9B3ae2dD9EAAD174cF5700420D4861A5a73a2d2A;
            address originalManaHolder = 0x673e6B75a58354919FF5db539AA426727B385D17;

            vm.prank(originalCollectionCreator);
            collection.transferCreatorship(signer.addr);

            address[] memory _minters = new address[](1);
            _minters[0] = address(marketplace);

            bool[] memory _values = new bool[](1);
            _values[0] = true;

            vm.prank(signer.addr);
            collection.setMinters(_minters, _values);

            vm.prank(originalManaHolder);
            mana.transfer(caller, 1 ether);

            vm.prank(caller);
            mana.approve(address(marketplace), 1 ether);

            assertEq(collection.creator(), signer.addr);
            assertEq(mana.balanceOf(caller), 1 ether);
        }

        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        {
            trades[0].expiration = block.timestamp;

            trades[0].sent = new MarketplaceHarness.Asset[](1);
            trades[0].sent[0].assetType = marketplace.COLLECTION_ITEM_ID();
            trades[0].sent[0].contractAddress = address(collection);
            trades[0].sent[0].value = itemId;

            trades[0].received = new MarketplaceHarness.Asset[](1);
            trades[0].received[0].assetType = marketplace.ERC20_ID();
            trades[0].received[0].contractAddress = address(mana);
            trades[0].received[0].value = 1 ether;

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(signer.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

            trades[0].signer = signer.addr;
            trades[0].signature = abi.encodePacked(r, s, v);
        }

        vm.prank(caller);
        marketplace.accept(trades);

        assertEq(collection.ownerOf(1), caller);
        assertEq(mana.balanceOf(signer.addr), 1 ether);
    }

    function test_accept_mintItem_receiveMANA_TradeHas2Uses_CanBeMintedTwice() public {
        IERC20 mana = IERC20(0xA1c57f48F0Deb89f569dFbE6E2B7f46D33606fD4);
        ICollection collection = ICollection(0x05267a0E08C9B756a000362d2B2c7E3ce29E740D);
        uint256 itemId = 0;

        {
            address originalCollectionCreator = 0x9B3ae2dD9EAAD174cF5700420D4861A5a73a2d2A;
            address originalManaHolder = 0x673e6B75a58354919FF5db539AA426727B385D17;

            vm.prank(originalCollectionCreator);
            collection.transferCreatorship(signer.addr);

            address[] memory _minters = new address[](1);
            _minters[0] = address(marketplace);

            bool[] memory _values = new bool[](1);
            _values[0] = true;

            vm.prank(signer.addr);
            collection.setMinters(_minters, _values);

            vm.prank(originalManaHolder);
            mana.transfer(caller, 2 ether);

            vm.prank(caller);
            mana.approve(address(marketplace), 2 ether);

            assertEq(collection.creator(), signer.addr);
            assertEq(mana.balanceOf(caller), 2 ether);
        }

        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        {
            trades[0].expiration = block.timestamp;
            trades[0].uses = 2;

            trades[0].sent = new MarketplaceHarness.Asset[](1);
            trades[0].sent[0].assetType = marketplace.COLLECTION_ITEM_ID();
            trades[0].sent[0].contractAddress = address(collection);
            trades[0].sent[0].value = itemId;

            trades[0].received = new MarketplaceHarness.Asset[](1);
            trades[0].received[0].assetType = marketplace.ERC20_ID();
            trades[0].received[0].contractAddress = address(mana);
            trades[0].received[0].value = 1 ether;

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(signer.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

            trades[0].signer = signer.addr;
            trades[0].signature = abi.encodePacked(r, s, v);
        }

        vm.expectRevert();
        collection.ownerOf(1);

        vm.prank(caller);
        marketplace.accept(trades);

        assertEq(collection.ownerOf(1), caller);
        vm.expectRevert();
        collection.ownerOf(2);
        assertEq(mana.balanceOf(caller), 1 ether);
        assertEq(mana.balanceOf(signer.addr), 1 ether);

        vm.prank(caller);
        marketplace.accept(trades);

        assertEq(collection.ownerOf(1), caller);
        assertEq(collection.ownerOf(2), caller);
        assertEq(mana.balanceOf(caller), 0);
        assertEq(mana.balanceOf(signer.addr), 2 ether);
    }

    function test_accept_mintItem_receiveMANA_RevertsIfSignerNorCallerIsTheCreator() public {
        ICollection collection = ICollection(0x05267a0E08C9B756a000362d2B2c7E3ce29E740D);
        uint256 itemId = 0;

        {
            address originalCollectionCreator = 0x9B3ae2dD9EAAD174cF5700420D4861A5a73a2d2A;

            address[] memory _minters = new address[](1);
            _minters[0] = address(marketplace);

            bool[] memory _values = new bool[](1);
            _values[0] = true;

            vm.prank(originalCollectionCreator);
            collection.setMinters(_minters, _values);
        }

        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        {
            trades[0].expiration = block.timestamp;

            trades[0].sent = new MarketplaceHarness.Asset[](1);
            trades[0].sent[0].assetType = marketplace.COLLECTION_ITEM_ID();
            trades[0].sent[0].contractAddress = address(collection);
            trades[0].sent[0].value = itemId;

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(signer.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

            trades[0].signer = signer.addr;
            trades[0].signature = abi.encodePacked(r, s, v);
        }

        vm.prank(caller);
        vm.expectRevert(NotCreator.selector);
        marketplace.accept(trades);
    }

    function test_accept_sendMANA_mintItem() public {
        IERC20 mana = IERC20(0xA1c57f48F0Deb89f569dFbE6E2B7f46D33606fD4);
        ICollection collection = ICollection(0x05267a0E08C9B756a000362d2B2c7E3ce29E740D);
        uint256 itemId = 0;

        {
            address originalCollectionCreator = 0x9B3ae2dD9EAAD174cF5700420D4861A5a73a2d2A;
            address originalManaHolder = 0x673e6B75a58354919FF5db539AA426727B385D17;

            vm.prank(originalCollectionCreator);
            collection.transferCreatorship(caller);

            address[] memory _minters = new address[](1);
            _minters[0] = address(marketplace);

            bool[] memory _values = new bool[](1);
            _values[0] = true;

            vm.prank(caller);
            collection.setMinters(_minters, _values);

            vm.prank(originalManaHolder);
            mana.transfer(signer.addr, 1 ether);

            vm.prank(signer.addr);
            mana.approve(address(marketplace), 1 ether);

            assertEq(collection.creator(), caller);
            assertEq(mana.balanceOf(signer.addr), 1 ether);
        }

        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        {
            trades[0].expiration = block.timestamp;

            trades[0].sent = new MarketplaceHarness.Asset[](1);
            trades[0].sent[0].assetType = marketplace.ERC20_ID();
            trades[0].sent[0].contractAddress = address(mana);
            trades[0].sent[0].value = 1 ether;

            trades[0].received = new MarketplaceHarness.Asset[](1);
            trades[0].received[0].assetType = marketplace.COLLECTION_ITEM_ID();
            trades[0].received[0].contractAddress = address(collection);
            trades[0].received[0].value = itemId;

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(signer.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

            trades[0].signer = signer.addr;
            trades[0].signature = abi.encodePacked(r, s, v);
        }

        vm.prank(caller);
        marketplace.accept(trades);

        assertEq(collection.ownerOf(1), signer.addr);
        assertEq(mana.balanceOf(caller), 1 ether);
        assertEq(mana.balanceOf(signer.addr), 0);
    }

    function test_accept_sendMANA_mintItem_RevertsIfSignerNorCallerIsTheCreator() public {
        IERC20 mana = IERC20(0xA1c57f48F0Deb89f569dFbE6E2B7f46D33606fD4);
        ICollection collection = ICollection(0x05267a0E08C9B756a000362d2B2c7E3ce29E740D);
        uint256 itemId = 0;

        {
            address originalCollectionCreator = 0x9B3ae2dD9EAAD174cF5700420D4861A5a73a2d2A;
            address originalManaHolder = 0x673e6B75a58354919FF5db539AA426727B385D17;

            address[] memory _minters = new address[](1);
            _minters[0] = address(marketplace);

            bool[] memory _values = new bool[](1);
            _values[0] = true;

            vm.prank(originalCollectionCreator);
            collection.setMinters(_minters, _values);

            vm.prank(originalManaHolder);
            mana.transfer(signer.addr, 1 ether);

            vm.prank(signer.addr);
            mana.approve(address(marketplace), 1 ether);

            assertEq(collection.creator(), originalCollectionCreator);
            assertEq(mana.balanceOf(signer.addr), 1 ether);
        }

        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        {
            trades[0].expiration = block.timestamp;

            trades[0].sent = new MarketplaceHarness.Asset[](1);
            trades[0].sent[0].assetType = marketplace.ERC20_ID();
            trades[0].sent[0].contractAddress = address(mana);
            trades[0].sent[0].value = 1 ether;

            trades[0].received = new MarketplaceHarness.Asset[](1);
            trades[0].received[0].assetType = marketplace.COLLECTION_ITEM_ID();
            trades[0].received[0].contractAddress = address(collection);
            trades[0].received[0].value = itemId;

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(signer.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

            trades[0].signer = signer.addr;
            trades[0].signature = abi.encodePacked(r, s, v);
        }

        vm.prank(caller);
        vm.expectRevert(NotCreator.selector);
        marketplace.accept(trades);
    }
}
