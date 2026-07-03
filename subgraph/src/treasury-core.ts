import {
  TransactionProposed,
  TransactionApproved,
  TransactionRejected,
  TransactionQueued,
  TransactionExecuted,
  TransactionCancelled,
  SignerAdded,
  SignerRemoved,
  GlobalThresholdUpdated,
  DefaultMinDelayUpdated,
  BudgetCreated,
  BudgetSpent,
  BudgetClosed,
  EmergencyPaused,
  EmergencyUnpaused,
  EmergencyShutdownTriggered,
  EmergencyRecoveryInitiated,
  EmergencyRecoveryExecuted,
  ModuleRegistered,
} from "../generated/TreasuryCore/TreasuryCore";
import {
  Treasury,
  Signer,
  Transaction,
  Approval,
  Budget,
  SpendRecord,
  EmergencyEvent,
} from "../generated/schema";
import { BigInt, Bytes, crypto, log } from "@graphprotocol/graph-ts";

function getOrCreateTreasury(): Treasury {
  let treasury = Treasury.load("TREASURY");
  if (!treasury) {
    treasury = new Treasury("TREASURY");
    treasury.address = Bytes.empty();
    treasury.admin = Bytes.empty();
    treasury.globalThreshold = BigInt.zero();
    treasury.defaultMinDelay = BigInt.zero();
    treasury.paused = false;
    treasury.emergencyShutdown = false;
    treasury.transactionCount = BigInt.zero();
    treasury.signerCount = BigInt.zero();
    treasury.save();
  }
  return treasury;
}

// ---- Multi-Sig Events ----

export function handleTransactionProposed(event: TransactionProposed): void {
  let treasury = getOrCreateTreasury();
  treasury.transactionCount = treasury.transactionCount.plus(BigInt.fromI32(1));
  treasury.save();

  let tx = new Transaction(event.params.txId.toString());
  tx.txId = event.params.txId;
  tx.proposer = event.params.proposer;
  tx.target = event.params.target;
  tx.value = event.params.value;
  tx.data = event.params.data;
  tx.status = "Draft";
  tx.approvalsRequired = event.params.approvalThreshold;
  tx.approvalCount = BigInt.zero();
  tx.minDelay = event.params.minDelay;
  tx.executableAt = BigInt.zero();
  tx.createdAt = event.block.timestamp;
  tx.description = event.params.description;
  tx.salt = Bytes.empty();
  tx.budgetId = Bytes.empty();
  tx.budgetAmount = BigInt.zero();
  tx.save();
}

export function handleTransactionApproved(event: TransactionApproved): void {
  let tx = Transaction.load(event.params.txId.toString());
  if (!tx) return;
  tx.approvalCount = tx.approvalCount.plus(BigInt.fromI32(1));
  tx.save();

  let approvalId = event.params.txId.toString() + "-" + event.params.signer.toHexString();
  let approval = new Approval(approvalId);
  approval.transaction = tx.id;
  approval.signer = event.params.signer.toHexString();
  approval.timestamp = event.block.timestamp;
  approval.save();

  // Update signer stats
  let signer = Signer.load(event.params.signer.toHexString());
  if (signer) {
    signer.approvalCount = signer.approvalCount.plus(BigInt.fromI32(1));
    signer.save();
  }
}

export function handleTransactionRejected(event: TransactionRejected): void {
  let tx = Transaction.load(event.params.txId.toString());
  if (!tx) return;
  tx.approvalCount = tx.approvalCount.minus(BigInt.fromI32(1));
  tx.save();
}

export function handleTransactionQueued(event: TransactionQueued): void {
  let tx = Transaction.load(event.params.txId.toString());
  if (!tx) return;
  tx.status = "Queued";
  tx.executableAt = event.params.executableAt;
  tx.save();
}

export function handleTransactionExecuted(event: TransactionExecuted): void {
  let tx = Transaction.load(event.params.txId.toString());
  if (!tx) return;
  tx.status = event.params.success ? "Executed" : "Failed";
  tx.save();
}

export function handleTransactionCancelled(event: TransactionCancelled): void {
  let tx = Transaction.load(event.params.txId.toString());
  if (!tx) return;
  tx.status = "Cancelled";
  tx.save();
}

// ---- Signer Events ----

export function handleSignerAdded(event: SignerAdded): void {
  let treasury = getOrCreateTreasury();
  treasury.signerCount = treasury.signerCount.plus(BigInt.fromI32(1));
  treasury.save();

  let signer = new Signer(event.params.signer.toHexString());
  signer.weight = event.params.weight;
  signer.active = true;
  signer.joinedAt = event.block.timestamp;
  signer.approvalCount = BigInt.zero();
  signer.save();
}

export function handleSignerRemoved(event: SignerRemoved): void {
  let treasury = getOrCreateTreasury();
  treasury.signerCount = treasury.signerCount.minus(BigInt.fromI32(1));
  treasury.save();

  let signer = Signer.load(event.params.signer.toHexString());
  if (signer) {
    signer.active = false;
    signer.save();
  }
}

export function handleGlobalThresholdUpdated(event: GlobalThresholdUpdated): void {
  let treasury = getOrCreateTreasury();
  treasury.globalThreshold = event.params.newThreshold;
  treasury.save();
}

export function handleDefaultMinDelayUpdated(event: DefaultMinDelayUpdated): void {
  let treasury = getOrCreateTreasury();
  treasury.defaultMinDelay = event.params.newDelay;
  treasury.save();
}

// ---- Budget Events ----

export function handleBudgetCreated(event: BudgetCreated): void {
  let budget = new Budget(event.params.budgetId.toHexString());
  budget.name = event.params.name;
  budget.owner = event.params.owner;
  budget.totalAllocated = event.params.totalAllocated;
  budget.totalSpent = BigInt.zero();
  budget.totalFrozen = BigInt.zero();
  budget.startTime = event.params.startTime;
  budget.endTime = event.params.endTime;
  budget.status = "Active";
  budget.maxSingleSpend = BigInt.zero();
  budget.approvalThreshold = event.params.approvalThreshold;
  budget.createdTx = event.transaction.hash;
  budget.save();
}

export function handleBudgetSpent(event: BudgetSpent): void {
  let budget = Budget.load(event.params.budgetId.toHexString());
  if (budget) {
    budget.totalFrozen = budget.totalFrozen.plus(event.params.amount);
    budget.save();
  }

  let spendId = event.params.budgetId.toHexString() + "-" + event.params.txId.toString();
  let spend = new SpendRecord(spendId);
  spend.budget = event.params.budgetId.toHexString();
  spend.transactionId = event.params.txId;
  spend.token = event.params.token;
  spend.amount = event.params.amount;
  spend.recipient = event.params.recipient;
  spend.timestamp = event.block.timestamp;
  spend.purpose = event.params.purpose;
  spend.save();
}

export function handleBudgetClosed(event: BudgetClosed): void {
  let budget = Budget.load(event.params.budgetId.toHexString());
  if (budget) {
    budget.status = "Closed";
    budget.save();
  }
}

// ---- Emergency Events ----

export function handleEmergencyPaused(event: EmergencyPaused): void {
  let treasury = getOrCreateTreasury();
  treasury.paused = true;
  treasury.save();

  let evt = new EmergencyEvent(
    event.transaction.hash.toHexString() + "-" + event.logIndex.toString()
  );
  evt.eventType = "Paused";
  evt.triggeredBy = event.params.triggeredBy;
  evt.timestamp = event.block.timestamp;
  evt.txHash = event.transaction.hash;
  evt.save();
}

export function handleEmergencyUnpaused(event: EmergencyUnpaused): void {
  let treasury = getOrCreateTreasury();
  treasury.paused = false;
  treasury.save();

  let evt = new EmergencyEvent(
    event.transaction.hash.toHexString() + "-" + event.logIndex.toString()
  );
  evt.eventType = "Unpaused";
  evt.triggeredBy = event.params.triggeredBy;
  evt.timestamp = event.block.timestamp;
  evt.txHash = event.transaction.hash;
  evt.save();
}

export function handleEmergencyShutdown(event: EmergencyShutdownTriggered): void {
  let treasury = getOrCreateTreasury();
  treasury.emergencyShutdown = true;
  treasury.paused = true;
  treasury.save();

  let evt = new EmergencyEvent(
    event.transaction.hash.toHexString() + "-" + event.logIndex.toString()
  );
  evt.eventType = "Shutdown";
  evt.triggeredBy = event.params.triggeredBy;
  evt.timestamp = event.block.timestamp;
  evt.txHash = event.transaction.hash;
  evt.save();
}

export function handleEmergencyRecoveryInitiated(event: EmergencyRecoveryInitiated): void {
  let evt = new EmergencyEvent(
    event.transaction.hash.toHexString() + "-" + event.logIndex.toString()
  );
  evt.eventType = "RecoveryInitiated";
  evt.triggeredBy = event.transaction.from;
  evt.timestamp = event.block.timestamp;
  evt.amount = event.params.amount;
  evt.unlockTime = event.params.unlockTime;
  evt.txHash = event.transaction.hash;
  evt.save();
}

export function handleEmergencyRecoveryExecuted(event: EmergencyRecoveryExecuted): void {
  let evt = new EmergencyEvent(
    event.transaction.hash.toHexString() + "-" + event.logIndex.toString()
  );
  evt.eventType = "RecoveryExecuted";
  evt.triggeredBy = event.transaction.from;
  evt.timestamp = event.block.timestamp;
  evt.amount = event.params.amount;
  evt.txHash = event.transaction.hash;
  evt.save();
}

export function handleModuleRegistered(event: ModuleRegistered): void {
  log.info("Module registered: {} at {}", [
    event.params.moduleName.toHexString(),
    event.params.moduleAddress.toHexString(),
  ]);
}
