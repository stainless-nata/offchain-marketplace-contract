// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {VmSafe} from "lib/forge-std/src/Vm.sol";
import {EthereumMarketplace} from "../src/EthereumMarketplace.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {MessageHashUtils} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC721} from "lib/openzeppelin-contracts/contracts/interfaces/IERC721.sol";
import {IComposableERC721} from "../src/interfaces/IComposableERC721.sol";

contract MarketplaceHarness is EthereumMarketplace {
    constructor(address _owner) EthereumMarketplace(_owner) {}

    function getDomainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function hashTrade(Trade memory _trade) external pure returns (bytes32) {
        return _hashTrade(_trade);
    }
}

contract EthereumMarketplaceTest is Test {
    VmSafe.Wallet signer;
    address caller;

    MarketplaceHarness marketplace;

    error UnsupportedAssetType(uint256 _assetType);
    error InvalidFingerprint();

    function setUp() public {
        string memory rpcUrl = "https://rpc.decentraland.org/mainnet";
        uint256 blockNumber = 19684477; // Apr-18-2024 07:38:35 PM +UTC

        uint256 forkId = vm.createFork(rpcUrl, blockNumber);
        vm.selectFork(forkId);

        signer = vm.createWallet("signer");
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

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(
                signer.privateKey,
                MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0]))
            );

            trades[0].signer = signer.addr;
            trades[0].signature = abi.encodePacked(r, s, v);
        }

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(UnsupportedAssetType.selector, assetType));
        marketplace.accept(trades);
    }

    function test_accept_sendLAND_receiveMANA() public {
        IERC20 mana = IERC20(0x0F5D2fB29fb7d3CFeE444a200298f468908cC942);
        IERC721 land = IERC721(0xF87E31492Faf9A91B02Ee0dEAAd50d51d56D5d4d);
        uint256 landId = 20416942015256307807802476445906092687221;

        {
            address originalLandOwner = 0x9cbe520Aa4bFD545109026Bb1fdf9Ea54f476e5E;
            address originalManaHolder = 0x46f80018211D5cBBc988e853A8683501FCA4ee9b;

            vm.prank(originalLandOwner);
            land.transferFrom(originalLandOwner, signer.addr, landId);

            vm.prank(originalManaHolder);
            mana.transfer(caller, 1 ether);

            vm.prank(signer.addr);
            land.setApprovalForAll(address(marketplace), true);

            vm.prank(caller);
            mana.approve(address(marketplace), 1 ether);

            assertEq(land.ownerOf(landId), signer.addr);
            assertEq(mana.balanceOf(caller), 1 ether);
        }

        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        {
            trades[0].expiration = block.timestamp;

            trades[0].sent = new MarketplaceHarness.Asset[](1);

            trades[0].sent[0].assetType = marketplace.ERC721_ID();
            trades[0].sent[0].contractAddress = address(land);
            trades[0].sent[0].value = landId;

            trades[0].received = new MarketplaceHarness.Asset[](1);

            trades[0].received[0].assetType = marketplace.ERC20_ID();
            trades[0].received[0].contractAddress = address(mana);
            trades[0].received[0].value = 1 ether;

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(
                signer.privateKey,
                MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0]))
            );

            trades[0].signer = signer.addr;
            trades[0].signature = abi.encodePacked(r, s, v);
        }

        vm.prank(caller);
        marketplace.accept(trades);

        assertEq(land.ownerOf(landId), caller);
        assertEq(mana.balanceOf(signer.addr), 1 ether);
    }

    function test_accept_sendLAND_receiveMANA_withDAOFee() public {
        IERC20 mana = IERC20(0x0F5D2fB29fb7d3CFeE444a200298f468908cC942);
        IERC721 land = IERC721(0xF87E31492Faf9A91B02Ee0dEAAd50d51d56D5d4d);
        uint256 landId = 20416942015256307807802476445906092687221;
        address dao = 0x9A6ebE7E2a7722F8200d0ffB63a1F6406A0d7dce;
        uint256 daoBalance = mana.balanceOf(dao);

        {
            address originalLandOwner = 0x9cbe520Aa4bFD545109026Bb1fdf9Ea54f476e5E;
            address originalManaHolder = 0x46f80018211D5cBBc988e853A8683501FCA4ee9b;

            vm.prank(originalLandOwner);
            land.transferFrom(originalLandOwner, signer.addr, landId);

            vm.prank(originalManaHolder);
            mana.transfer(caller, 1 ether);

            vm.prank(signer.addr);
            land.setApprovalForAll(address(marketplace), true);

            vm.prank(caller);
            mana.approve(address(marketplace), 1 ether);

            assertEq(land.ownerOf(landId), signer.addr);
            assertEq(mana.balanceOf(caller), 1 ether);
        }

        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        {
            trades[0].expiration = block.timestamp;

            trades[0].sent = new MarketplaceHarness.Asset[](1);

            trades[0].sent[0].assetType = marketplace.ERC721_ID();
            trades[0].sent[0].contractAddress = address(land);
            trades[0].sent[0].value = landId;

            trades[0].received = new MarketplaceHarness.Asset[](2);

            trades[0].received[0].assetType = marketplace.ERC20_ID();
            trades[0].received[0].contractAddress = address(mana);
            trades[0].received[0].value = 0.7 ether;

            trades[0].received[1].assetType = marketplace.ERC20_ID();
            trades[0].received[1].contractAddress = address(mana);
            trades[0].received[1].value = 0.3 ether;
            trades[0].received[1].beneficiary = dao;

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(
                signer.privateKey,
                MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0]))
            );

            trades[0].signer = signer.addr;
            trades[0].signature = abi.encodePacked(r, s, v);
        }

        vm.prank(caller);
        marketplace.accept(trades);

        assertEq(land.ownerOf(landId), caller);
        assertEq(mana.balanceOf(signer.addr), 0.7 ether);
        assertEq(mana.balanceOf(dao), daoBalance + 0.3 ether);
    }

    function test_accept_sendEstate_receiveMANA() public {
        IERC20 mana = IERC20(0x0F5D2fB29fb7d3CFeE444a200298f468908cC942);
        IComposableERC721 estate = IComposableERC721(0x959e104E1a4dB6317fA58F8295F586e1A978c297);
        uint256 estateId = 5668;

        {
            address originalEstateOwner = 0x877a61D298eAf59f6d574e089216aC764ec00D2D;
            address originalManaHolder = 0x46f80018211D5cBBc988e853A8683501FCA4ee9b;

            vm.prank(originalEstateOwner);
            estate.transferFrom(originalEstateOwner, signer.addr, estateId);

            vm.prank(originalManaHolder);
            mana.transfer(caller, 1 ether);

            vm.prank(signer.addr);
            estate.setApprovalForAll(address(marketplace), true);

            vm.prank(caller);
            mana.approve(address(marketplace), 1 ether);

            assertEq(estate.ownerOf(estateId), signer.addr);
            assertEq(mana.balanceOf(caller), 1 ether);
        }

        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        {
            trades[0].expiration = block.timestamp;

            trades[0].sent = new MarketplaceHarness.Asset[](1);

            trades[0].sent[0].assetType = marketplace.COMPOSABLE_ERC721_ID();
            trades[0].sent[0].contractAddress = address(estate);
            trades[0].sent[0].value = estateId;
            trades[0].sent[0].extra = abi.encode(estate.getFingerprint(estateId), bytes(""));

            trades[0].received = new MarketplaceHarness.Asset[](1);

            trades[0].received[0].assetType = marketplace.ERC20_ID();
            trades[0].received[0].contractAddress = address(mana);
            trades[0].received[0].value = 1 ether;

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(
                signer.privateKey,
                MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0]))
            );

            trades[0].signer = signer.addr;
            trades[0].signature = abi.encodePacked(r, s, v);
        }

        vm.prank(caller);
        marketplace.accept(trades);

        assertEq(estate.ownerOf(estateId), caller);
        assertEq(mana.balanceOf(signer.addr), 1 ether);
    }

    function test_accept_sendEstate_receiveMANA_RevertsIfFingerprintIsInvalid() public {
        IERC20 mana = IERC20(0x0F5D2fB29fb7d3CFeE444a200298f468908cC942);
        IComposableERC721 estate = IComposableERC721(0x959e104E1a4dB6317fA58F8295F586e1A978c297);
        uint256 estateId = 5668;

        {
            address originalEstateOwner = 0x877a61D298eAf59f6d574e089216aC764ec00D2D;
            address originalManaHolder = 0x46f80018211D5cBBc988e853A8683501FCA4ee9b;

            vm.prank(originalEstateOwner);
            estate.transferFrom(originalEstateOwner, signer.addr, estateId);

            vm.prank(originalManaHolder);
            mana.transfer(caller, 1 ether);

            vm.prank(signer.addr);
            estate.setApprovalForAll(address(marketplace), true);

            vm.prank(caller);
            mana.approve(address(marketplace), 1 ether);

            assertEq(estate.ownerOf(estateId), signer.addr);
            assertEq(mana.balanceOf(caller), 1 ether);
        }

        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        {
            trades[0].expiration = block.timestamp;

            trades[0].sent = new MarketplaceHarness.Asset[](1);

            trades[0].sent[0].assetType = marketplace.COMPOSABLE_ERC721_ID();
            trades[0].sent[0].contractAddress = address(estate);
            trades[0].sent[0].value = estateId;
            trades[0].sent[0].extra = abi.encode(bytes32(uint256(123)), bytes(""));

            trades[0].received = new MarketplaceHarness.Asset[](1);

            trades[0].received[0].assetType = marketplace.ERC20_ID();
            trades[0].received[0].contractAddress = address(mana);
            trades[0].received[0].value = 1 ether;

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(
                signer.privateKey,
                MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0]))
            );

            trades[0].signer = signer.addr;
            trades[0].signature = abi.encodePacked(r, s, v);
        }

        vm.prank(caller);
        vm.expectRevert(InvalidFingerprint.selector);
        marketplace.accept(trades);
    }

    function test_accept_sendName_receiveMANA() public {
        IERC20 mana = IERC20(0x0F5D2fB29fb7d3CFeE444a200298f468908cC942);
        IERC721 registrar = IERC721(0x2A187453064356c898cAe034EAed119E1663ACb8);
        uint256 nameId = 111953866685194181316179970749576144183152508562302674483221441304598033207711;

        {
            address originalNameOwner = 0x6a45De91B516C17CacEC184506d719947613465E;
            address originalManaHolder = 0x46f80018211D5cBBc988e853A8683501FCA4ee9b;

            vm.prank(originalNameOwner);
            registrar.transferFrom(originalNameOwner, signer.addr, nameId);

            vm.prank(originalManaHolder);
            mana.transfer(caller, 1 ether);

            vm.prank(signer.addr);
            registrar.setApprovalForAll(address(marketplace), true);

            vm.prank(caller);
            mana.approve(address(marketplace), 1 ether);

            assertEq(registrar.ownerOf(nameId), signer.addr);
            assertEq(mana.balanceOf(caller), 1 ether);
        }

        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        {
            trades[0].expiration = block.timestamp;

            trades[0].sent = new MarketplaceHarness.Asset[](1);

            trades[0].sent[0].assetType = marketplace.ERC721_ID();
            trades[0].sent[0].contractAddress = address(registrar);
            trades[0].sent[0].value = nameId;

            trades[0].received = new MarketplaceHarness.Asset[](1);

            trades[0].received[0].assetType = marketplace.ERC20_ID();
            trades[0].received[0].contractAddress = address(mana);
            trades[0].received[0].value = 1 ether;

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(
                signer.privateKey,
                MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0]))
            );

            trades[0].signer = signer.addr;
            trades[0].signature = abi.encodePacked(r, s, v);
        }

        vm.prank(caller);
        marketplace.accept(trades);

        assertEq(registrar.ownerOf(nameId), caller);
        assertEq(mana.balanceOf(signer.addr), 1 ether);
    }

    function test_accept_sendNameLANDAndEstate_receiveMANA() public {
        IERC20 mana = IERC20(0x0F5D2fB29fb7d3CFeE444a200298f468908cC942);

        IERC721 land = IERC721(0xF87E31492Faf9A91B02Ee0dEAAd50d51d56D5d4d);
        uint256 landId = 20416942015256307807802476445906092687221;

        IComposableERC721 estate = IComposableERC721(0x959e104E1a4dB6317fA58F8295F586e1A978c297);
        uint256 estateId = 5668;

        IERC721 registrar = IERC721(0x2A187453064356c898cAe034EAed119E1663ACb8);
        uint256 nameId = 111953866685194181316179970749576144183152508562302674483221441304598033207711;

        {
            address originalLandOwner = 0x9cbe520Aa4bFD545109026Bb1fdf9Ea54f476e5E;
            address originalEstateOwner = 0x877a61D298eAf59f6d574e089216aC764ec00D2D;
            address originalNameOwner = 0x6a45De91B516C17CacEC184506d719947613465E;
            address originalManaHolder = 0x46f80018211D5cBBc988e853A8683501FCA4ee9b;

            vm.prank(originalLandOwner);
            land.transferFrom(originalLandOwner, signer.addr, landId);

            vm.prank(originalEstateOwner);
            estate.transferFrom(originalEstateOwner, signer.addr, estateId);

            vm.prank(originalNameOwner);
            registrar.transferFrom(originalNameOwner, signer.addr, nameId);

            vm.prank(originalManaHolder);
            mana.transfer(caller, 1 ether);

            vm.prank(signer.addr);
            land.setApprovalForAll(address(marketplace), true);

            vm.prank(signer.addr);
            estate.setApprovalForAll(address(marketplace), true);

            vm.prank(signer.addr);
            registrar.setApprovalForAll(address(marketplace), true);

            vm.prank(caller);
            mana.approve(address(marketplace), 1 ether);

            assertEq(land.ownerOf(landId), signer.addr);
            assertEq(estate.ownerOf(estateId), signer.addr);
            assertEq(registrar.ownerOf(nameId), signer.addr);
            assertEq(mana.balanceOf(caller), 1 ether);
        }

        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        {
            trades[0].expiration = block.timestamp;

            trades[0].sent = new MarketplaceHarness.Asset[](3);

            trades[0].sent[0].assetType = marketplace.ERC721_ID();
            trades[0].sent[0].contractAddress = address(land);
            trades[0].sent[0].value = landId;

            trades[0].sent[1].assetType = marketplace.COMPOSABLE_ERC721_ID();
            trades[0].sent[1].contractAddress = address(estate);
            trades[0].sent[1].value = estateId;
            trades[0].sent[1].extra = abi.encode(estate.getFingerprint(estateId), bytes(""));

            trades[0].sent[2].assetType = marketplace.ERC721_ID();
            trades[0].sent[2].contractAddress = address(registrar);
            trades[0].sent[2].value = nameId;

            trades[0].received = new MarketplaceHarness.Asset[](1);

            trades[0].received[0].assetType = marketplace.ERC20_ID();
            trades[0].received[0].contractAddress = address(mana);
            trades[0].received[0].value = 1 ether;

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(
                signer.privateKey,
                MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0]))
            );

            trades[0].signer = signer.addr;
            trades[0].signature = abi.encodePacked(r, s, v);
        }

        vm.prank(caller);
        marketplace.accept(trades);

        assertEq(land.ownerOf(landId), caller);
        assertEq(estate.ownerOf(estateId), caller);
        assertEq(registrar.ownerOf(nameId), caller);
        assertEq(mana.balanceOf(signer.addr), 1 ether);
    }

    // function test_accept_anvil() public {
    //     uint256 anvilForkId = vm.createFork("http://127.0.0.1:8545");
    //     vm.selectFork(anvilForkId);

    //     EthereumMarketplace anvilMarketplace = new EthereumMarketplace(vm.addr(0x1));

    //     bytes memory input = hexStringToBytes(
    //         "0xa3cb363b000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb922660000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000970e081c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007a690000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001e0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002200000000000000000000000000000000000000000000000000000000000000041d337e663fcee1a17bf1b0e5242498bdc0d4262e02034476698b53f1eb76afff61ffe33ab239e0f77bb389e423b4aa332677a717c28f6a80415f4c734e951a6071c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
    //     );

    //     vm.prank(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
    //     address(anvilMarketplace).call(input);
    // }

    // // Helper function to convert a hex string to bytes
    // function hexStringToBytes(string memory hexString) public pure returns (bytes memory) {
    //     // Check if string is prefixed with '0x' and adjust the starting position accordingly
    //     bytes memory stringBytes = bytes(hexString);
    //     uint256 offset = (stringBytes[1] == "x") ? 2 : 0;

    //     bytes memory bytesArray = new bytes((stringBytes.length - offset) / 2);
    //     for (uint256 i = 0; i < bytesArray.length; i++) {
    //         uint8 tmp1 = uint8(stringBytes[i * 2 + offset]);
    //         uint8 tmp2 = uint8(stringBytes[i * 2 + offset + 1]);
    //         bytesArray[i] = bytes1(uint8(fromHexChar(tmp1)) * 16 + uint8(fromHexChar(tmp2)));
    //     }
    //     return bytesArray;
    // }

    // // Convert hex character to bytes
    // function fromHexChar(uint8 c) public pure returns (uint8) {
    //     return c - (c < 58 ? 48 : (c < 97 ? 55 : 87));
    // }
}
