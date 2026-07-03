.PHONY: build test test-fuzz test-unit test-integration gas coverage clean deploy-sepolia deploy-holesky lint fix-lint slither

# ---- Build ----
build:
	forge build

# ---- Test ----
test:
	forge test -vvv

test-unit:
	forge test --match-path test/TreasuryCore.t.sol -vvv

test-fuzz:
	forge test --fuzz-runs 5000 --match-path "test/fuzz/*" -vvv

test-integration:
	forge test --match-path "test/integration/*" -vvv

test-edge:
	forge test --match-path "test/edge/*" -vvv

test-invariants:
	forge test --match-path "test/invariants/*" -vvv

# ---- Gas & Coverage ----
gas:
	forge test --gas-report

coverage:
	forge coverage --report lcov

# ---- Lint & Format ----
lint:
	forge fmt --check

fix-lint:
	forge fmt

# ---- Static Analysis ----
slither:
	slither . --solc-remaps "@openzeppelin/contracts-upgradeable/=lib/openzeppelin-contracts-upgradeable/contracts/ @openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/ forge-std/=lib/forge-std/src/"

# ---- Deploy (testnet) ----
deploy-sepolia:
	forge script scripts/Deploy.s.sol --rpc-url sepolia --broadcast --verify -vvvv

deploy-holesky:
	forge script scripts/Deploy.s.sol --rpc-url holesky --broadcast --verify -vvvv

deploy-local:
	forge script scripts/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast -vvvv

# ---- Clean ----
clean:
	forge clean
