import "@/styles/globals.css";
import { createWeb3Modal, defaultConfig } from "@web3modal/ethers/react";
import type { AppProps } from "next/app";
import { useEffect, useState } from "react";

// 1. Get projectId
const projectId = process.env.NEXT_PUBLIC_PROJECT_ID || "";

// 2. Set chains
const mainnet = {
  chainId: 1,
  name: "Ethereum",
  currency: "ETH",
  explorerUrl: "https://etherscan.io",
  rpcUrl: "https://cloudflare-eth.com",
};

const anvil = {
  chainId: 31337,
  name: "Anvil",
  currency: "GO",
  explorerUrl: "https://etherscan.io",
  rpcUrl: "http://127.0.0.1:8545",
};

// 3. Create a metadata object
const metadata = {
  name: "My Website",
  description: "My Website description",
  url: "https://mywebsite.com", // origin must match your domain & subdomain
  icons: ["https://avatars.mywebsite.com/"],
};

// 4. Create Ethers config
const ethersConfig = defaultConfig({
  /*Required*/
  metadata,
});

// 5. Create a Web3Modal instance
createWeb3Modal({
  ethersConfig,
  chains: [mainnet, anvil],
  projectId,
  enableAnalytics: true, // Optional - defaults to your Cloud configuration
});

export default function App({ Component, pageProps }: AppProps) {
  const [ready, setReady] = useState(false);

  useEffect(() => {
    setReady(true);
  }, []);

  return <>{ready ? <Component {...pageProps} /> : null}</>;
}

// import "@/styles/globals.css";
// import { createWeb3Modal, defaultWagmiConfig } from "@web3modal/wagmi/react";

// import { WagmiConfig } from "wagmi";
// import type { AppProps } from "next/app";
// import { useEffect, useState } from "react";
// import {
// 	arbitrum,
// 	avalanche,
// 	bsc,
// 	fantom,
// 	gnosis,
// 	mainnet,
// 	optimism,
// 	polygon,
// } from "wagmi/chains";

// const chains = [
// 	mainnet,
// 	polygon,
// 	avalanche,
// 	arbitrum,
// 	bsc,
// 	optimism,
// 	gnosis,
// 	fantom,
// ];

// // 1. Get projectID at https://cloud.walletconnect.com

// const projectId = process.env.NEXT_PUBLIC_PROJECT_ID || "";

// const metadata = {
// 	name: "Next Starter Template",
// 	description: "A Next.js starter template with Web3Modal v3 + Wagmi",
// 	url: "https://web3modal.com",
// 	icons: ["https://avatars.githubusercontent.com/u/37784886"],
// };

// const wagmiConfig = defaultWagmiConfig({ chains, projectId, metadata });

// createWeb3Modal({ wagmiConfig, projectId, chains });

// export default function App({ Component, pageProps }: AppProps) {
// 	const [ready, setReady] = useState(false);

// 	useEffect(() => {
// 		setReady(true);
// 	}, []);
// 	return (
// 		<>
// 			{ready ? (
// 				<WagmiConfig config={wagmiConfig}>
// 					<Component {...pageProps} />
// 				</WagmiConfig>
// 			) : null}
// 		</>
// 	);
// }
