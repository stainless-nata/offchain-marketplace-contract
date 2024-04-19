// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {VmSafe} from "lib/forge-std/src/Vm.sol";
import {EthereumMarketplace} from "../src/EthereumMarketplace.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {MessageHashUtils} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC721} from "lib/openzeppelin-contracts/contracts/interfaces/IERC721.sol";

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

    function test_accept_sendLAND_receiveMANA() public {
        IERC20 mana = IERC20(0x0F5D2fB29fb7d3CFeE444a200298f468908cC942);
        IERC721 land = IERC721(0xF87E31492Faf9A91B02Ee0dEAAd50d51d56D5d4d);
        uint256 landTokenId = 20416942015256307807802476445906092687221;

        {
            address originalLandOwner = 0x9cbe520Aa4bFD545109026Bb1fdf9Ea54f476e5E;
            address originalManaHolder = 0x46f80018211D5cBBc988e853A8683501FCA4ee9b;

            vm.prank(originalLandOwner);
            land.transferFrom(originalLandOwner, signer.addr, landTokenId);

            vm.prank(originalManaHolder);
            mana.transfer(caller, 1 ether);

            vm.prank(signer.addr);
            land.setApprovalForAll(address(marketplace), true);

            vm.prank(caller);
            mana.approve(address(marketplace), 1 ether);

            assertEq(land.ownerOf(landTokenId), signer.addr);
            assertEq(mana.balanceOf(caller), 1 ether);
        }

        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        {
            trades[0].expiration = block.timestamp;

            trades[0].sent = new MarketplaceHarness.Asset[](1);

            trades[0].sent[0].assetType = marketplace.ERC721_ID();
            trades[0].sent[0].contractAddress = address(land);
            trades[0].sent[0].value = landTokenId;

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

        assertEq(land.ownerOf(landTokenId), caller);
        assertEq(mana.balanceOf(signer.addr), 1 ether);
    }
}
