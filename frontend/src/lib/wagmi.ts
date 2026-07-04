import { createConfig, http } from "wagmi";
import { injected, walletConnect } from "wagmi/connectors";
import { sepolia, holesky, hardhat } from "wagmi/chains";

const isTestnet = process.env.NEXT_PUBLIC_CHAIN === "sepolia";
const chain = isTestnet ? sepolia : holesky;

const transports = {
  [sepolia.id]: http(process.env.NEXT_PUBLIC_SEPOLIA_RPC),
  [holesky.id]: http(process.env.NEXT_PUBLIC_HOLESKY_RPC),
  [hardhat.id]: http("http://localhost:8545"),
};

export const config = createConfig({
  chains: [chain, hardhat],
  transports,
  connectors: [
    injected({ shimDisconnect: true }),
    walletConnect({
      projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || "00000000000000000000000000000000",
    }),
  ],
  ssr: false,
});
