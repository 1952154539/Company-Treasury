import { createConfig, http } from "wagmi";
import { injected, walletConnect } from "wagmi/connectors";
import { sepolia, holesky, hardhat } from "wagmi/chains";

const chainEnv = process.env.NEXT_PUBLIC_CHAIN;
const defaultChain = chainEnv === "sepolia" ? sepolia : chainEnv === "holesky" ? holesky : hardhat;

const transports = {
  [sepolia.id]: http(process.env.NEXT_PUBLIC_SEPOLIA_RPC || "https://ethereum-sepolia-rpc.publicnode.com"),
  [holesky.id]: http(process.env.NEXT_PUBLIC_HOLESKY_RPC || "https://ethereum-holesky-rpc.publicnode.com"),
  [hardhat.id]: http("http://localhost:8545"),
};

// Deduplicate by chain id
const allChains = [defaultChain, sepolia, holesky, hardhat];
const seen = new Set<number>();
const chains = allChains.filter((c) => {
  if (seen.has(c.id)) return false;
  seen.add(c.id);
  return true;
});

export const config = createConfig({
  chains,
  transports,
  connectors: [
    injected({ shimDisconnect: true }),
    walletConnect({
      projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || "00000000000000000000000000000000",
    }),
  ],
  ssr: false,
});
