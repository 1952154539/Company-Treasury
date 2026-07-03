import {
  StreamCreated,
  StreamWithdrawn,
  StreamCancelled,
} from "../generated/StreamingManager/StreamingManager";
import { Stream, StreamWithdrawal } from "../generated/schema";
import { BigInt, Bytes } from "@graphprotocol/graph-ts";

export function handleStreamCreated(event: StreamCreated): void {
  let stream = new Stream(event.params.streamId.toString());
  stream.streamId = event.params.streamId;
  stream.sender = event.params.sender;
  stream.recipient = event.params.recipient;
  stream.token = event.params.token;
  stream.totalAmount = event.params.amount;
  stream.remainingBalance = event.params.amount;
  stream.startTime = event.params.startTime;
  stream.cliffDuration = event.params.cliffDuration;
  stream.endTime = event.params.endTime;
  stream.lastWithdrawalTime = event.params.startTime;
  stream.withdrawnAmount = BigInt.zero();
  stream.cancelable = event.params.cancelable;
  stream.active = true;
  stream.budgetId = Bytes.empty();
  stream.save();
}

export function handleStreamWithdrawn(event: StreamWithdrawn): void {
  let stream = Stream.load(event.params.streamId.toString());
  if (stream) {
    stream.withdrawnAmount = stream.withdrawnAmount.plus(event.params.amount);
    stream.remainingBalance = stream.totalAmount.minus(stream.withdrawnAmount);
    stream.lastWithdrawalTime = event.block.timestamp;
    // Check if fully withdrawn
    if (stream.withdrawnAmount >= stream.totalAmount) {
      stream.active = false;
    }
    stream.save();
  }

  let withdrawalId =
    event.params.streamId.toString() + "-" + event.transaction.hash.toHexString();
  let withdrawal = new StreamWithdrawal(withdrawalId);
  withdrawal.stream = event.params.streamId.toString();
  withdrawal.recipient = event.params.recipient;
  withdrawal.amount = event.params.amount;
  withdrawal.txHash = event.transaction.hash;
  withdrawal.timestamp = event.block.timestamp;
  withdrawal.save();
}

export function handleStreamCancelled(event: StreamCancelled): void {
  let stream = Stream.load(event.params.streamId.toString());
  if (stream) {
    stream.active = false;
    stream.remainingBalance = BigInt.zero();
    stream.save();
  }
}
