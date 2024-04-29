// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {EthereumMarketplace} from "../src/EthereumMarketplace.sol";
import {IComposable} from "../src/interfaces/IComposable.sol";

contract EthereumMarketplaceHarness is EthereumMarketplace {
    constructor(address _owner) EthereumMarketplace(_owner) {}

    function eip712Name() external view returns (string memory) {
        return _EIP712Name();
    }

    function eip712Version() external view returns (string memory) {
        return _EIP712Version();
    }

    function eip712TradeHash(Trade memory _trade) external view returns (bytes32) {
        return _hashTypedDataV4(_hashTrade(_trade));
    }
}

abstract contract EthereumMarketplaceTests is Test {
    VmSafe.Wallet signer;
    address other;
    EthereumMarketplaceHarness marketplace;

    function setUp() public virtual {
        uint256 forkId = vm.createFork("https://rpc.decentraland.org/mainnet", 19755898); // Apr-28-2024 07:27:59 PM +UTC
        vm.selectFork(forkId);

        signer = vm.createWallet("signer");
        other = 0x79c63172C7B01A8a5B074EF54428a452E0794E7A;
        marketplace = new EthereumMarketplaceHarness(0x9A6ebE7E2a7722F8200d0ffB63a1F6406A0d7dce); // DAO Agent;
    }

    function signTrade(EthereumMarketplace.Trade memory _trade) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.privateKey, marketplace.eip712TradeHash(_trade));
        return abi.encodePacked(r, s, v);
    }
}

contract UnsupportedAssetTypeTests is EthereumMarketplaceTests {
    error UnsupportedAssetType(uint256 _assetType);

    function test_RevertsIfAssetTypeIsInvalid() public {
        uint256 invalidAssetType = 100;

        EthereumMarketplace.Trade[] memory trades = new EthereumMarketplace.Trade[](1);
        trades[0].expiration = block.timestamp;
        trades[0].sent = new EthereumMarketplace.Asset[](1);
        trades[0].sent[0].assetType = invalidAssetType;
        trades[0].signer = signer.addr;
        trades[0].signature = signTrade(trades[0]);

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(UnsupportedAssetType.selector, invalidAssetType));
        marketplace.accept(trades);
    }
}

contract TransferERC20Tests is EthereumMarketplaceTests {
    IERC20 erc20;
    uint256 erc20Sent;
    address erc20OriginalHolder;

    event Transfer(address indexed from, address indexed to, uint256 value);

    error FailedInnerCall();

    function setUp() public override {
        super.setUp();
        erc20 = IERC20(0x0F5D2fB29fb7d3CFeE444a200298f468908cC942);
        erc20Sent = 1 ether;
        erc20OriginalHolder = 0x67c231cF2B0E9518aBa46bDea6b10E0D0C5fEd1B;
    }

    function test_RevertsIfSignerHasNotApprovedTheMarketplaceToSendERC20() public {
        EthereumMarketplace.Trade[] memory trades = new EthereumMarketplace.Trade[](1);
        trades[0].expiration = block.timestamp;
        trades[0].sent = new EthereumMarketplace.Asset[](1);
        trades[0].sent[0].assetType = marketplace.ERC20_ID();
        trades[0].sent[0].contractAddress = address(erc20);
        trades[0].sent[0].value = erc20Sent;
        trades[0].signer = signer.addr;
        trades[0].signature = signTrade(trades[0]);

        vm.prank(other);
        vm.expectRevert(FailedInnerCall.selector);
        marketplace.accept(trades);
    }

    function test_RevertsIfSignerDoesNotHaveEnoughERC20Balance() public {
        assertEq(erc20.allowance(signer.addr, address(marketplace)), 0);
        vm.prank(signer.addr);
        erc20.approve(address(marketplace), erc20Sent);
        assertEq(erc20.allowance(signer.addr, address(marketplace)), erc20Sent);

        assertEq(erc20.balanceOf(signer.addr), 0);

        EthereumMarketplace.Trade[] memory trades = new EthereumMarketplace.Trade[](1);
        trades[0].expiration = block.timestamp;
        trades[0].sent = new EthereumMarketplace.Asset[](1);
        trades[0].sent[0].assetType = marketplace.ERC20_ID();
        trades[0].sent[0].contractAddress = address(erc20);
        trades[0].sent[0].value = erc20Sent;
        trades[0].signer = signer.addr;
        trades[0].signature = signTrade(trades[0]);

        vm.prank(other);
        vm.expectRevert(FailedInnerCall.selector);
        marketplace.accept(trades);
    }

    function test_TransfersERC20FromSignerToCaller() public {
        assertEq(erc20.allowance(signer.addr, address(marketplace)), 0);
        vm.prank(signer.addr);
        erc20.approve(address(marketplace), erc20Sent);
        assertEq(erc20.allowance(signer.addr, address(marketplace)), erc20Sent);

        vm.prank(erc20OriginalHolder);
        erc20.transfer(signer.addr, erc20Sent);
        assertEq(erc20.balanceOf(signer.addr), erc20Sent);

        EthereumMarketplace.Trade[] memory trades = new EthereumMarketplace.Trade[](1);
        trades[0].expiration = block.timestamp;
        trades[0].sent = new EthereumMarketplace.Asset[](1);
        trades[0].sent[0].assetType = marketplace.ERC20_ID();
        trades[0].sent[0].contractAddress = address(erc20);
        trades[0].sent[0].value = erc20Sent;
        trades[0].signer = signer.addr;
        trades[0].signature = signTrade(trades[0]);

        vm.prank(other);
        vm.expectEmit(address(erc20));
        emit Transfer(signer.addr, other, erc20Sent);
        marketplace.accept(trades);

        assertEq(erc20.balanceOf(signer.addr), 0);
        assertEq(erc20.balanceOf(other), erc20Sent);
    }
}

contract TransferERC721Tests is EthereumMarketplaceTests {
    IERC721 erc721;
    uint256 erc721TokenId;
    address erc721OriginalHolder;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    function setUp() public override {
        super.setUp();
        erc721 = IERC721(0xF87E31492Faf9A91B02Ee0dEAAd50d51d56D5d4d);
        erc721TokenId = 1;
        erc721OriginalHolder = 0x959e104E1a4dB6317fA58F8295F586e1A978c297;
    }

    function test_RevertsIfSignerHasNotApprovedTheMarketplaceToSendERC721() public {
        EthereumMarketplace.Trade[] memory trades = new EthereumMarketplace.Trade[](1);
        trades[0].expiration = block.timestamp;
        trades[0].sent = new EthereumMarketplace.Asset[](1);
        trades[0].sent[0].assetType = marketplace.ERC721_ID();
        trades[0].sent[0].contractAddress = address(erc721);
        trades[0].sent[0].value = erc721TokenId;
        trades[0].signer = signer.addr;
        trades[0].signature = signTrade(trades[0]);

        vm.prank(other);
        vm.expectRevert();
        marketplace.accept(trades);
    }

    function test_RevertsIfSignerDoesNotHaveTheERC721Token() public {
        assertFalse(erc721.isApprovedForAll(signer.addr, address(marketplace)));
        vm.prank(signer.addr);
        erc721.setApprovalForAll(address(marketplace), true);
        assertTrue(erc721.isApprovedForAll(signer.addr, address(marketplace)));

        assertNotEq(erc721.ownerOf(erc721TokenId), signer.addr);

        EthereumMarketplace.Trade[] memory trades = new EthereumMarketplace.Trade[](1);
        trades[0].expiration = block.timestamp;
        trades[0].sent = new EthereumMarketplace.Asset[](1);
        trades[0].sent[0].assetType = marketplace.ERC721_ID();
        trades[0].sent[0].contractAddress = address(erc721);
        trades[0].sent[0].value = erc721TokenId;
        trades[0].signer = signer.addr;
        trades[0].signature = signTrade(trades[0]);

        vm.prank(other);
        vm.expectRevert();
        marketplace.accept(trades);
    }

    function test_TransfersERC721FromSignerToCaller() public {
        assertFalse(erc721.isApprovedForAll(signer.addr, address(marketplace)));
        vm.prank(signer.addr);
        erc721.setApprovalForAll(address(marketplace), true);
        assertTrue(erc721.isApprovedForAll(signer.addr, address(marketplace)));

        vm.prank(erc721OriginalHolder);
        erc721.transferFrom(erc721OriginalHolder, signer.addr, erc721TokenId);
        assertEq(erc721.ownerOf(erc721TokenId), signer.addr);

        EthereumMarketplace.Trade[] memory trades = new EthereumMarketplace.Trade[](1);
        trades[0].expiration = block.timestamp;
        trades[0].sent = new EthereumMarketplace.Asset[](1);
        trades[0].sent[0].assetType = marketplace.ERC721_ID();
        trades[0].sent[0].contractAddress = address(erc721);
        trades[0].sent[0].value = erc721TokenId;
        trades[0].signer = signer.addr;
        trades[0].signature = signTrade(trades[0]);

        vm.prank(other);
        vm.expectEmit(address(erc721));
        emit Transfer(signer.addr, other, erc721TokenId);
        marketplace.accept(trades);

        assertEq(erc721.ownerOf(erc721TokenId), other);
    }
}

contract TransferComposableTokenTests is EthereumMarketplaceTests {
    IComposable composable;
    uint256 composableTokenId;
    address composableOriginalHolder;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    error InvalidFingerprint();

    function setUp() public override {
        super.setUp();
        composable = IComposable(0x959e104E1a4dB6317fA58F8295F586e1A978c297);
        composableTokenId = 1;
        composableOriginalHolder = 0x9aBdCb8825696CC2Ef3A0a955f99850418847F5D;
    }

    function test_RevertsIfFingerprintIsInvalid() public {
        EthereumMarketplace.Trade[] memory trades = new EthereumMarketplace.Trade[](1);
        trades[0].expiration = block.timestamp;
        trades[0].sent = new EthereumMarketplace.Asset[](1);
        trades[0].sent[0].assetType = marketplace.COMPOSABLE_ERC721_ID();
        trades[0].sent[0].contractAddress = address(composable);
        trades[0].sent[0].value = composableTokenId;
        trades[0].sent[0].extra = abi.encode(uint256(123));
        trades[0].signer = signer.addr;
        trades[0].signature = signTrade(trades[0]);

        vm.prank(other);
        vm.expectRevert(InvalidFingerprint.selector);
        marketplace.accept(trades);
    }

    function test_RevertsIfSignerIsNotTheOwnerOfTheComposableToken() public {
        EthereumMarketplace.Trade[] memory trades = new EthereumMarketplace.Trade[](1);
        trades[0].expiration = block.timestamp;
        trades[0].sent = new EthereumMarketplace.Asset[](1);
        trades[0].sent[0].assetType = marketplace.COMPOSABLE_ERC721_ID();
        trades[0].sent[0].contractAddress = address(composable);
        trades[0].sent[0].value = composableTokenId;
        trades[0].sent[0].extra = abi.encode(composable.getFingerprint(composableTokenId));
        trades[0].signer = signer.addr;
        trades[0].signature = signTrade(trades[0]);

        vm.prank(other);
        vm.expectRevert("Only owner or operator can transfer");
        marketplace.accept(trades);
    }

    function test_RevertsIfSignerHasNotApprovedTheMarketplaceContractToTransferTheComposableToken() public {
        vm.prank(composableOriginalHolder);
        composable.transferFrom(composableOriginalHolder, signer.addr, composableTokenId);

        EthereumMarketplace.Trade[] memory trades = new EthereumMarketplace.Trade[](1);
        trades[0].expiration = block.timestamp;
        trades[0].sent = new EthereumMarketplace.Asset[](1);
        trades[0].sent[0].assetType = marketplace.COMPOSABLE_ERC721_ID();
        trades[0].sent[0].contractAddress = address(composable);
        trades[0].sent[0].value = composableTokenId;
        trades[0].sent[0].extra = abi.encode(composable.getFingerprint(composableTokenId));
        trades[0].signer = signer.addr;
        trades[0].signature = signTrade(trades[0]);

        vm.prank(other);
        vm.expectRevert("Only owner or operator can transfer");
        marketplace.accept(trades);
    }

    function test_TransfersComposableTokenFromSignerToCaller() public {
        vm.prank(composableOriginalHolder);
        composable.transferFrom(composableOriginalHolder, signer.addr, composableTokenId);

        vm.prank(signer.addr);
        composable.setApprovalForAll(address(marketplace), true);

        EthereumMarketplace.Trade[] memory trades = new EthereumMarketplace.Trade[](1);
        trades[0].expiration = block.timestamp;
        trades[0].sent = new EthereumMarketplace.Asset[](1);
        trades[0].sent[0].assetType = marketplace.COMPOSABLE_ERC721_ID();
        trades[0].sent[0].contractAddress = address(composable);
        trades[0].sent[0].value = composableTokenId;
        trades[0].sent[0].extra = abi.encode(composable.getFingerprint(composableTokenId));
        trades[0].signer = signer.addr;
        trades[0].signature = signTrade(trades[0]);

        vm.prank(other);
        vm.expectEmit(address(composable));
        emit Transfer(signer.addr, other, composableTokenId);
        marketplace.accept(trades);

        assertEq(composable.ownerOf(composableTokenId), other);
    }
}
