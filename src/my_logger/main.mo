// Persistent logger keeping track of what is going on.

import Array "mo:base/Array";
import Cycles "mo:base/ExperimentalCycles";
import MyLogger "./logger";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Principal "mo:base/Principal";
import RBT "mo:base/RBTree";
import Types "./types";

shared(msg) actor class Logger() {
  let N: Nat = 3;

  private stable var logger_index : Nat = 0;
  private let logger_cans = RBT.RBTree<Nat, Principal>(Nat.compare); //存储创建的logger canister

  private let IC: Types.IC.ICActor = actor("aaaaa-aa"); //ledger actor的ID
  private let CYCLE_LIMIT = 1_000_000_000_000; //根据需要进行分配

  private shared({caller}) func createLogger(): async Result.Result<Principal, Text> {
    Cycles.add(CYCLE_LIMIT);
    let logger_can = await MyLogger.MyLogger(caller);
    let principal = Principal.fromActor(logger_can);
    await IC.update_settings({
      canister_id = principal;
      settings = {
        freezing_threshold = ?2592000;
        controllers = ?[caller];
        memory_allocation = ?0;
        compute_allocation = ?0;
      }
    });
    logger_cans.put(logger_index, principal);
    logger_index += 1;
    #ok(principal)
  };

  public query({caller}) func cycleBalance() : async Nat{
    Cycles.balance()
  };

  public shared({caller}) func wallet_receive() : async Nat {
    Cycles.accept(Cycles.available())
  };

  private stable var num_logs: Nat64 = 0;
  type LoggerCan = actor {
    allow: shared([Principal]) -> async ();
    append: shared([Text]) -> async ();
    stats: shared() -> async Logger.Stats;
    view: shared(from: Nat, to: Nat) -> async Logger.View<Text>;
  };

  // Add a set of messages to the log.
  public shared (msg) func append(msgs: [Text]) {
    let logger_idx = num_logs / Nat64.fromNat(N);
    if (num_logs - N * logger_idx == 0) {
      createLogger();
    };
    
    let logger = logger_cans.get(logger_idx);
    switch (logger) {
      case (?logger) {
        let logger_canister: LoggerCan = actor(Principal.toText(logger));
        await logger_canister.append(msgs);
        num_logs += 1;
      };
      case (null) { assert(false); }
    };
  };

  // Return the messages between from and to indice (inclusive).
  public shared (msg) func view(from: Nat, to: Nat) : async Logger.View<Text> {
    let from_logger_idx = from / N;
    let to_logger_idx = to / N;

    var logs_view: Logger.View<Text> = {
      start_index = from;
      messages = [Text];
    };
    var i = from_logger_idx;
    while (i <= to_logger_idx and i >= from_logger_idx) {
      let logger = logger_cans.get(i);
      switch (logger) {
        case (?logger) {
          var log_from = from - N * i;
          var log_to = to - N * i;
          if (i > from_logger_idx) log_from := 0;
          if (i < to_logger_idx) log_to := N;

          let logger_canister: LoggerCan = actor(Principal.toText(logger));
          let logs_in_can = await logger_canister.view(log_from, log_to);
          logs_view.messages := Array.append(logs_view.messages, logs_in_can.messages);

          i += 1;
        };
        case (null) { assert(false); }
      };
    };
    logs_view
  };
}