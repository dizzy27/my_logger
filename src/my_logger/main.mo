// Persistent logger keeping track of what is going on.

import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Cycles "mo:base/ExperimentalCycles";
// import Debug "mo:base/Debug";
import IC "./ic";
import ICLogger "mo:ic-logger/Logger";
import MyLogger "./logger";
import Nat "mo:base/Nat";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import RBT "mo:base/RBTree";
import Text "mo:base/Text";

shared(msg) actor class Logger() = self {
  let N: Nat = 3;

  private stable var new_logger_index: Nat = 0;
  private let logger_cans = RBT.RBTree<Nat, Principal>(Nat.compare); //存储创建的logger canister
  
  private let CYCLE_LIMIT = 1_000_000_000_000; //根据需要进行分配

  public shared({caller}) func createLogger(): async ?Principal {
    Cycles.add(CYCLE_LIMIT);

    let ic: IC.Self = actor("aaaaa-aa"); //ledger actor的ID
    let logger_can = await MyLogger.MyLogger(caller);
    let principal = Principal.fromActor(logger_can);
    await ic.update_settings({
      canister_id = principal;
      settings = {
        freezing_threshold = ?2592000;
        controllers = ?[caller];
        memory_allocation = ?0;
        compute_allocation = ?0;
      }
    });
    logger_cans.put(new_logger_index, principal);
    new_logger_index += 1;
    Option.make(principal)
    // #ok(principal)

    // let ic: IC.Self = actor("aaaaa-aa"); //ledger actor的ID
    // let logger_can = MyLogger.MyLogger(caller);
    // let settings = {
    //   freezing_threshold = null;
    //   controllers = ?[caller];
    //   memory_allocation = null;
    //   compute_allocation = null;
    // };
    // let result = await ic.create_canister({ settings = ?settings; });
    // logger_cans.put(new_logger_index, result.canister_id);
    // new_logger_index += 1;
    // result.canister_id
  };

  public query({caller}) func cycleBalance(): async Nat{
    Cycles.balance()
  };

  public shared({caller}) func wallet_receive(): async Nat {
    Cycles.accept(Cycles.available())
  };

  private stable var num_logs: Nat = 0;
  type LoggerCan = actor {
    allow: shared([Principal]) -> async ();
    append: shared([Text]) -> async ();
    stats: shared() -> async ICLogger.Stats;
    view: shared(Nat, Nat) -> async ICLogger.View<Text>;
  };

  public query (msg) func get_logger(idx: Nat): async Text {
    let logger = logger_cans.get(idx);
    switch (logger) {
      case (?logger) {
        Principal.toText(logger)
      };
      case (null) { "null" }
    }
  };

  public query (msg) func get_num_logs(): async Nat {
    num_logs
  };

  // a % b
  func mod(a: Nat, b: Nat): Nat {
    a - a / b * b
  };

  func size_of(msgs: [Text]): Nat {
    var msgs_size = 0;
    for (_ in msgs.vals()) {
      msgs_size += 1;
    };
    msgs_size
  };

  func append_to_logger(msgs: [Text], logger_index: Nat): async() {
    var logger = logger_cans.get(logger_index);
    switch (logger) {
      case (?logger) {
        num_logs += size_of(msgs);

        let logger_canister: LoggerCan = actor(Principal.toText(logger));
        await logger_canister.append(msgs);
      };
      case (null) { assert(false) }
    };
  };

  func split_msgs(head: Nat, len: Nat, msgs: [Text]): [[Text]] {
    assert(len > 0);
    var splits = Buffer.Buffer<[Text]>(size_of(msgs) / N + 1);
    var split_element = Buffer.Buffer<Text>(len);
    var idx = 0;
    let msgs_size = size_of(msgs);
    assert(msgs_size >= 1);

    for (msg in msgs.vals()) {
      split_element.add(msg);

      if (head > 0 and idx == head - 1) {
        splits.add(split_element.toArray());
        split_element.clear();
      };

      if (idx + 1 > head and idx + 1 - head>= len and mod(idx + 1 - head, len) == 0) {
        splits.add(split_element.toArray());
        split_element.clear();
      };

      if (idx == msgs_size - 1) {
        splits.add(split_element.toArray());
        split_element.clear();
      };

      idx += 1;
    };
    splits.toArray()
  };

  // Add a set of messages to the log.
  public shared (msg) func append(msgs: [Text]): async() {
    let msgs_size = size_of(msgs);
    let new_logger_nums = (num_logs + msgs_size - 1) / N + 1 - new_logger_index;
    assert(new_logger_nums >= 0);

    if (new_logger_nums > 0) {
      // create enough loggers first
      var i = 0;
      while (i < new_logger_nums) {
        let _ = await createLogger();
        i += 1;
      };
    } else {
      // append messages
      let _ = await append_to_logger(msgs, new_logger_index - 1);
      return;
      // var b = Buffer.Buffer<[Text]>(1);
      // b.add(msgs);
      // return b.toArray()
    };

    let capacity_left = if (mod(num_logs, N) == 0) 0 else N - mod(num_logs, N);
    let from_can = num_logs / N;
    let msgs_splits = split_msgs(capacity_left, N, msgs);
    var idx = 0;
    for (msg_split in msgs_splits.vals()) {
      if (size_of(msg_split) != 0) {
        let _ = await append_to_logger(msg_split, from_can + idx);
        idx += 1;
      };
    };
    // msgs_splits
  };

  func append_array(buf: Buffer.Buffer<Text>, msgs: [Text]): Buffer.Buffer<Text> {
    for (msg in msgs.vals()) {
      buf.add(msg);
    };
    buf
  };

  func view_from_logger(logger_index: Nat, from: Nat, to: Nat): async [Text] {
    let logger = logger_cans.get(logger_index);
    switch (logger) {
      case (?logger) {
        let logger_canister: LoggerCan = actor(Principal.toText(logger));
        let logs_in_can = await logger_canister.view(from, to);
        logs_in_can.messages
      };
      case (null) { assert(false); [] }
    };
  };

  // Return the messages between from and to indice (inclusive).
  public shared (msg) func view(from: Nat, to: Nat): async ICLogger.View<Text> {
    assert(to >= from);
    if (num_logs == 0) {
      return {
        start_index = from;
        messages = [];
      }
    };

    let from_logger_idx = from / N;
    let actual_to = if (to >= num_logs) num_logs - 1 else to;
    let to_logger_idx = actual_to / N;

    var logs = Buffer.Buffer<Text>(actual_to - from + 1);
    var i = from_logger_idx;
    while (i <= to_logger_idx and i >= from_logger_idx) {
      var log_from = 0;
      var log_to = N - 1;
      if (i == from_logger_idx) log_from := mod(from, N);
      if (i == to_logger_idx) log_to := mod(actual_to, N);

      let logs_in_can = await view_from_logger(i, log_from, log_to);
      logs := append_array(logs, logs_in_can);

      i += 1;
    };
    {
      start_index = from;
      messages = logs.toArray();
    }
  };
}