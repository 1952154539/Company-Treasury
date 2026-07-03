import {
  StrategyAdded,
  StrategyRemoved,
  StrategyUpdated,
  YieldDeposited,
  YieldWithdrawn,
  YieldHarvested,
  YieldRebalanced,
} from "../generated/YieldManager/YieldManager";
import { Strategy, Position } from "../generated/schema";
import { BigInt } from "@graphprotocol/graph-ts";

export function handleStrategyAdded(event: StrategyAdded): void {
  let strategy = new Strategy(event.params.strategyId.toHexString());
  strategy.name = event.params.name;
  strategy.vault = event.params.vault;
  strategy.asset = event.params.asset;
  strategy.active = true;
  strategy.allocationCap = event.params.allocationCap;
  strategy.totalDeposited = BigInt.zero();
  strategy.riskLevel = 0;
  strategy.addedAt = event.block.timestamp;
  strategy.save();
}

export function handleStrategyRemoved(event: StrategyRemoved): void {
  let strategy = Strategy.load(event.params.strategyId.toHexString());
  if (strategy) {
    strategy.active = false;
    strategy.save();
  }
}

export function handleStrategyUpdated(event: StrategyUpdated): void {
  let strategy = Strategy.load(event.params.strategyId.toHexString());
  if (strategy) {
    strategy.allocationCap = event.params.newAllocationCap;
    strategy.save();
  }
}

export function handleYieldDeposited(event: YieldDeposited): void {
  let strategy = Strategy.load(event.params.strategyId.toHexString());
  if (strategy) {
    strategy.totalDeposited = strategy.totalDeposited.plus(event.params.amount);
    strategy.save();
  }

  let position = new Position(event.params.positionId.toHexString());
  position.strategy = event.params.strategyId.toHexString();
  position.depositedAssets = event.params.amount;
  position.vaultShares = event.params.shares;
  position.accruedYield = BigInt.zero();
  position.lastHarvestTime = event.block.timestamp;
  position.createdAt = event.block.timestamp;
  position.active = true;
  position.save();
}

export function handleYieldWithdrawn(event: YieldWithdrawn): void {
  let strategy = Strategy.load(event.params.strategyId.toHexString());
  if (strategy) {
    let newDeposited = strategy.totalDeposited.minus(event.params.assets);
    strategy.totalDeposited = newDeposited.gt(BigInt.zero()) ? newDeposited : BigInt.zero();
    strategy.save();
  }
}

export function handleYieldHarvested(event: YieldHarvested): void {
  let strategy = Strategy.load(event.params.strategyId.toHexString());
  if (strategy && event.params.amount.gt(BigInt.zero())) {
    // Yield harvested increases effective deposited (compounds)
    strategy.totalDeposited = strategy.totalDeposited.plus(event.params.amount);
    strategy.save();
  }
}

export function handleYieldRebalanced(event: YieldRebalanced): void {
  let fromStrategy = Strategy.load(event.params.fromStrategy.toHexString());
  let toStrategy = Strategy.load(event.params.toStrategy.toHexString());
  if (fromStrategy) {
    let newFrom = fromStrategy.totalDeposited.minus(event.params.amount);
    fromStrategy.totalDeposited = newFrom.gt(BigInt.zero()) ? newFrom : BigInt.zero();
    fromStrategy.save();
  }
  if (toStrategy) {
    toStrategy.totalDeposited = toStrategy.totalDeposited.plus(event.params.amount);
    toStrategy.save();
  }
}
