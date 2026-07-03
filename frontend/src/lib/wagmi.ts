import { createConfig, http } from "wagmi";
import { mainnet, sepolia, holesky, hardhat } from "wagmi/chains";
import { getDefaultConfig } from "connectkit";

const isTestnet = process.env.NEXT_PUBLIC_CHAIN === "sepolia";

export const config = createConfig(
  getDefaultConfig({
    appName: "Company Treasury",
    appDescription: "On-chain Corporate Treasury System",
    appUrl: "https://company-treasury.vercel.app",
    chains: [isTestnet ? sepolia : holesky, hardhat],
    transports: {
      [sepolia.id]: http(process.env.NEXT_PUBLIC_SEPOLIA_RPC),
      [holesky.id]: http(process.env.NEXT_PUBLIC_HOLESKY_RPC),
      [hardhat.id]: http("http://localhost:8545"),
    },
    walletConnectProjectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || "",
  })
);
