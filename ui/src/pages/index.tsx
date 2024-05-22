import { useMemo, useState } from "react";
import { StandardMerkleTree } from "@openzeppelin/merkle-tree";
import { useWeb3ModalProvider } from "@web3modal/ethers/react";
import { AbiCoder, ethers } from "ethers";

const MARKETPLACE = "0x5FbDB2315678afecb367f032d93F642f64180aa3";
const SALT = ethers.zeroPadValue(ethers.toBeArray(31337), 32);

export default function Home() {
  return (
    <main>
      <Signature />
      <MerkleTree />
    </main>
  );
}

const Signature = () => {
  const { walletProvider } = useWeb3ModalProvider();

  const onSign = async () => {
    if (!walletProvider) {
      throw new Error("Wallet provider is not available");
    }

    const browserProvider = new ethers.BrowserProvider(walletProvider);

    const signer = await browserProvider.getSigner();

    const signature = await signer.signTypedData(
      {
        name: "Marketplace",
        version: "1.0.0",
        verifyingContract: MARKETPLACE,
        salt: SALT,
      },
      {
        Trade: [
          { name: "checks", type: "Checks" },
          { name: "sent", type: "AssetWithoutBeneficiary[]" },
          { name: "received", type: "Asset[]" },
        ],
        Asset: [
          { name: "assetType", type: "uint256" },
          { name: "contractAddress", type: "address" },
          { name: "value", type: "uint256" },
          { name: "extra", type: "bytes" },
          { name: "beneficiary", type: "address" },
        ],
        AssetWithoutBeneficiary: [
          { name: "assetType", type: "uint256" },
          { name: "contractAddress", type: "address" },
          { name: "value", type: "uint256" },
          { name: "extra", type: "bytes" },
        ],
        Checks: [
          { name: "uses", type: "uint256" },
          { name: "expiration", type: "uint256" },
          { name: "effective", type: "uint256" },
          { name: "salt", type: "bytes32" },
          { name: "contractSignatureIndex", type: "uint256" },
          { name: "signerSignatureIndex", type: "uint256" },
          { name: "allowedRoot", type: "bytes32" },
          { name: "externalChecks", type: "ExternalCheck[]" },
        ],
        ExternalCheck: [
          { name: "contractAddress", type: "address" },
          { name: "selector", type: "bytes4" },
          { name: "value", type: "uint256" },
          { name: "required", type: "bool" },
        ],
      },
      {
        checks: {
          uses: 1,
          expiration: 2,
          effective: 3,
          salt: SALT,
          contractSignatureIndex: 4,
          signerSignatureIndex: 5,
          allowedRoot: ethers.zeroPadValue(ethers.toBeArray(0), 32),
          externalChecks: [
            {
              contractAddress: MARKETPLACE,
              selector: "0x70a08231",
              value: 1,
              required: true,
            },
          ],
        },
        sent: [
          {
            assetType: 1,
            contractAddress: MARKETPLACE,
            value: 1,
            extra: AbiCoder.defaultAbiCoder().encode(["uint256", "address"], [1, MARKETPLACE]),
          },
        ],
        received: [
          {
            assetType: 1,
            contractAddress: MARKETPLACE,
            value: 1,
            extra: AbiCoder.defaultAbiCoder().encode(["uint256", "address"], [1, MARKETPLACE]),
            beneficiary: MARKETPLACE,
          },
        ],
      }
    );

    console.log("signature", signature);

    const abi = [
      {
        type: "function",
        name: "accept",
        inputs: [
          {
            name: "_trades",
            type: "tuple[]",
            internalType: "struct MarketplaceTypes.Trade[]",
            components: [
              { name: "signer", type: "address", internalType: "address" },
              { name: "signature", type: "bytes", internalType: "bytes" },
              {
                name: "checks",
                type: "tuple",
                internalType: "struct CommonTypes.Checks",
                components: [
                  { name: "uses", type: "uint256", internalType: "uint256" },
                  { name: "expiration", type: "uint256", internalType: "uint256" },
                  { name: "effective", type: "uint256", internalType: "uint256" },
                  { name: "salt", type: "bytes32", internalType: "bytes32" },
                  { name: "contractSignatureIndex", type: "uint256", internalType: "uint256" },
                  { name: "signerSignatureIndex", type: "uint256", internalType: "uint256" },
                  { name: "allowedRoot", type: "bytes32", internalType: "bytes32" },
                  { name: "allowedProof", type: "bytes32[]", internalType: "bytes32[]" },
                  {
                    name: "externalChecks",
                    type: "tuple[]",
                    internalType: "struct CommonTypes.ExternalCheck[]",
                    components: [
                      { name: "contractAddress", type: "address", internalType: "address" },
                      { name: "selector", type: "bytes4", internalType: "bytes4" },
                      { name: "value", type: "uint256", internalType: "uint256" },
                      { name: "required", type: "bool", internalType: "bool" },
                    ],
                  },
                ],
              },
              {
                name: "sent",
                type: "tuple[]",
                internalType: "struct MarketplaceTypes.Asset[]",
                components: [
                  { name: "assetType", type: "uint256", internalType: "uint256" },
                  { name: "contractAddress", type: "address", internalType: "address" },
                  { name: "value", type: "uint256", internalType: "uint256" },
                  { name: "beneficiary", type: "address", internalType: "address" },
                  { name: "extra", type: "bytes", internalType: "bytes" },
                ],
              },
              {
                name: "received",
                type: "tuple[]",
                internalType: "struct MarketplaceTypes.Asset[]",
                components: [
                  { name: "assetType", type: "uint256", internalType: "uint256" },
                  { name: "contractAddress", type: "address", internalType: "address" },
                  { name: "value", type: "uint256", internalType: "uint256" },
                  { name: "beneficiary", type: "address", internalType: "address" },
                  { name: "extra", type: "bytes", internalType: "bytes" },
                ],
              },
            ],
          },
        ],
        outputs: [],
        stateMutability: "nonpayable",
      },
    ];

    const contract = new ethers.Contract(MARKETPLACE, abi, signer);

    await contract.accept([
      {
        signer: signer.address,
        signature: signature,
        checks: {
          uses: 1,
          expiration: 2,
          effective: 3,
          salt: SALT,
          contractSignatureIndex: 4,
          signerSignatureIndex: 5,
          allowedRoot: ethers.zeroPadValue(ethers.toBeArray(0), 32),
          allowedProof: [],
          externalChecks: [
            {
              contractAddress: MARKETPLACE,
              selector: "0x70a08231",
              value: 1,
              required: true,
            },
          ],
        },
        sent: [
          {
            assetType: 1,
            contractAddress: MARKETPLACE,
            value: 1,
            extra: AbiCoder.defaultAbiCoder().encode(["uint256", "address"], [1, MARKETPLACE]),
            beneficiary: MARKETPLACE,
          },
        ],
        received: [
          {
            assetType: 1,
            contractAddress: MARKETPLACE,
            value: 1,
            extra: AbiCoder.defaultAbiCoder().encode(["uint256", "address"], [1, MARKETPLACE]),
            beneficiary: MARKETPLACE,
          },
        ],
      },
    ]);
  };

  return (
    <div>
      <h1>Signature</h1>
      <w3m-button />
      <button onClick={onSign}>Sign</button>
    </div>
  );
};

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
