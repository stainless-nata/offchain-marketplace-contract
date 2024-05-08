import Head from "next/head";
import Image from "next/image";
import { useMemo, useState } from "react";
import { useWeb3ModalAccount, useWeb3ModalProvider } from "@web3modal/ethers/react";
import { ethers } from "ethers";
import { StandardMerkleTree } from "@openzeppelin/merkle-tree";
import styles from "@/styles/Home.module.css";

const expiration = 2534279196; // 2050
const chainId = 31337;
const salt = ethers.zeroPadValue(ethers.toBeArray(chainId), 32);
const contractAddress = "0x5FbDB2315678afecb367f032d93F642f64180aa3";

export default function Home() {
  const { walletProvider } = useWeb3ModalProvider();
  const { address } = useWeb3ModalAccount();

  const [isNetworkSwitchHighlighted, setIsNetworkSwitchHighlighted] = useState(false);
  const [isConnectHighlighted, setIsConnectHighlighted] = useState(false);
  const [signature, setSignature] = useState("");

  const closeAll = () => {
    setIsNetworkSwitchHighlighted(false);
    setIsConnectHighlighted(false);
  };

  const handleOnSign = async () => {
    if (!walletProvider || !address) {
      return;
    }

    const provider = new ethers.BrowserProvider(walletProvider);

    const signer = await provider.getSigner();

    const signature = await signer.signTypedData(
      {
        name: "Marketplace",
        version: "1.0.0",
        verifyingContract: contractAddress,
        salt,
      },
      {
        Trade: [
          {
            name: "uses",
            type: "uint256",
          },
          {
            name: "expiration",
            type: "uint256",
          },
          {
            name: "effective",
            type: "uint256",
          },
          {
            name: "salt",
            type: "bytes32",
          },
          {
            name: "contractSignatureIndex",
            type: "uint256",
          },
          {
            name: "signerSignatureIndex",
            type: "uint256",
          },
          {
            name: "allowed",
            type: "address[]",
          },
          {
            name: "sent",
            type: "AssetWithoutBeneficiary[]",
          },
          {
            name: "received",
            type: "Asset[]",
          },
        ],
        Asset: [
          {
            name: "assetType",
            type: "uint256",
          },
          {
            name: "contractAddress",
            type: "address",
          },
          {
            name: "value",
            type: "uint256",
          },
          {
            name: "extra",
            type: "bytes",
          },
          {
            name: "beneficiary",
            type: "address",
          },
        ],
        AssetWithoutBeneficiary: [
          {
            name: "assetType",
            type: "uint256",
          },
          {
            name: "contractAddress",
            type: "address",
          },
          {
            name: "value",
            type: "uint256",
          },
          {
            name: "extra",
            type: "bytes",
          },
        ],
      },
      {
        uses: 1,
        expiration,
        effective: 0,
        salt,
        contractSignatureIndex: 0,
        signerSignatureIndex: 0,
        allowed: [address],
        sent: [
          {
            assetType: 0,
            contractAddress: ethers.ZeroAddress,
            value: 1000,
            extra: ethers.toUtf8Bytes("sdfgdsfgsdfgfsd"),
          },
          {
            assetType: 1,
            contractAddress: ethers.ZeroAddress,
            value: 532523462354,
            extra: ethers.toUtf8Bytes("sadfasdgasdg"),
          },
        ],
        received: [
          {
            assetType: 0,
            contractAddress: ethers.ZeroAddress,
            value: 1000,
            extra: ethers.toUtf8Bytes("sdfgdsfgsdfgfsd"),
            beneficiary: ethers.ZeroAddress,
          },
          {
            assetType: 1,
            contractAddress: ethers.ZeroAddress,
            value: 532523462354,
            extra: ethers.toUtf8Bytes("sadfasdgasdg"),
            beneficiary: address,
          },
        ],
      }
    );

    setSignature(signature);
  };

  const handleAccept = async () => {
    if (!address || !walletProvider) {
      return;
    }

    const provider = new ethers.BrowserProvider(walletProvider);

    const signer = await provider.getSigner();

    const contract = new ethers.Contract(
      contractAddress,
      [
        {
          type: "function",
          name: "accept",
          inputs: [
            {
              name: "_trades",
              type: "tuple[]",
              internalType: "struct Marketplace.Trade[]",
              components: [
                { name: "signer", type: "address", internalType: "address" },
                { name: "signature", type: "bytes", internalType: "bytes" },
                { name: "uses", type: "uint256", internalType: "uint256" },
                { name: "expiration", type: "uint256", internalType: "uint256" },
                { name: "effective", type: "uint256", internalType: "uint256" },
                { name: "salt", type: "bytes32", internalType: "bytes32" },
                { name: "contractSignatureIndex", type: "uint256", internalType: "uint256" },
                { name: "signerSignatureIndex", type: "uint256", internalType: "uint256" },
                { name: "allowed", type: "address[]", internalType: "address[]" },
                {
                  name: "sent",
                  type: "tuple[]",
                  internalType: "struct Marketplace.Asset[]",
                  components: [
                    { name: "assetType", type: "uint256", internalType: "uint256" },
                    { name: "contractAddress", type: "address", internalType: "address" },
                    { name: "value", type: "uint256", internalType: "uint256" },
                    { name: "extra", type: "bytes", internalType: "bytes" },
                    { name: "beneficiary", type: "address", internalType: "address" },
                  ],
                },
                {
                  name: "received",
                  type: "tuple[]",
                  internalType: "struct Marketplace.Asset[]",
                  components: [
                    { name: "assetType", type: "uint256", internalType: "uint256" },
                    { name: "contractAddress", type: "address", internalType: "address" },
                    { name: "value", type: "uint256", internalType: "uint256" },
                    { name: "extra", type: "bytes", internalType: "bytes" },
                    { name: "beneficiary", type: "address", internalType: "address" },
                  ],
                },
              ],
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
      ],
      signer
    );

    await contract.accept([
      {
        signer: address,
        signature: signature,
        uses: 1,
        expiration,
        effective: 0,
        salt,
        contractSignatureIndex: 0,
        signerSignatureIndex: 0,
        allowed: [address],
        sent: [
          {
            assetType: 0,
            contractAddress: ethers.ZeroAddress,
            value: 1000,
            extra: ethers.toUtf8Bytes("sdfgdsfgsdfgfsd"),
            beneficiary: ethers.ZeroAddress,
          },
          {
            assetType: 1,
            contractAddress: ethers.ZeroAddress,
            value: 532523462354,
            extra: ethers.toUtf8Bytes("sadfasdgasdg"),
            beneficiary: address,
          },
        ],
        received: [
          {
            assetType: 0,
            contractAddress: ethers.ZeroAddress,
            value: 1000,
            extra: ethers.toUtf8Bytes("sdfgdsfgsdfgfsd"),
            beneficiary: ethers.ZeroAddress,
          },
          {
            assetType: 1,
            contractAddress: ethers.ZeroAddress,
            value: 532523462354,
            extra: ethers.toUtf8Bytes("sadfasdgasdg"),
            beneficiary: address,
          },
        ],
      },
    ]);
  };

  return (
    <main>
      <MerkleTree />
    </main>
  );
}

const MerkleTree = () => {
  const values = [
    ["0x0000000000000000000000000000000000000001"],
    ["0x0000000000000000000000000000000000000002"],
    ["0x0000000000000000000000000000000000000003"],
    ["0x0000000000000000000000000000000000000004"],
    ["0x0000000000000000000000000000000000000005"],
    ["0x0000000000000000000000000000000000000006"],
    ["0x0000000000000000000000000000000000000007"],
    ["0x0000000000000000000000000000000000000008"],
    ["0x0000000000000000000000000000000000000009"],
    ["0x2e234DAe75C793f67A35089C9d99245E1C58470b"],
  ];

  const tree = StandardMerkleTree.of(values, ["address"]);

  const [value, setValue] = useState(values[0][0]);

  const proof = useMemo(() => {
    for (const [i, v] of tree.entries()) {
      if (v[0] === value) {
        return tree.getProof(i);
      }
    }
  }, [value]);

  return (
    <div>
      <h1>Merkle Tree</h1>
      <h2>Address</h2>
      <select value={value} onChange={(e) => setValue(e.target.value)}>
        {values.map((value) => {
          return (
            <option key={value[0]} value={value[0]}>
              {value[0]}
            </option>
          );
        })}
      </select>
      <h2>Proof</h2>
      <pre>{JSON.stringify(proof, null, 2)}</pre>
      <h2>Root</h2>
      <pre>{tree.root}</pre>
      <h2>Tree</h2>
      <pre>{JSON.stringify(tree, null, 2)}</pre>
    </div>
  );
};
