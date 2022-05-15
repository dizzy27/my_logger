import Cycles "mo:base/ExperimentalCycles";

module IC {
    public type canister_settings = {
        freezing_threshold: ?Nat;
        controllers: ?[Principal];
        memory_allocation: ?Nat;
        compute_allocation: ?Nat;
    };

    public type definite_canister_settings = {
        freezing_threshold: Nat;
        controllers: [Principal];
        memory_allocation: Nat;
        compute_allocation: Nat;
    };
    public type user_id = Principal;

    public type WasmModule = [Nat8];
    public type CanisterId = Principal;
    public type ICActor = actor {
        canister_status: shared { canister_id: CanisterId } -> async {
            status: { #stopped; #stopping; #running };
            memory_size: Nat;
            cycles: Nat;
            settings: definite_canister_settings;
            module_hash: ?[Nat8];
        };

        create_canister: shared { settings : ?canister_settings } -> async {
            canister_id: CanisterId;
        };

        delete_canister: shared { canister_id: CanisterId } -> async ();

        deposit_cycles: shared { canister_id: CanisterId } -> async ();

        install_code: shared {
            arg: [Nat8];
            wasm_module: WasmModule;
            mode: { #reinstall; #upgrade; #install };
            canister_id: CanisterId;
            } -> async ();

        provisional_create_canister_with_cycles: shared {
            settings: ?canister_settings;
            amount: ?Nat;
            } -> async { canister_id: CanisterId };

        provisional_top_up_canister: shared {
            canister_id: CanisterId;
            amount: Nat;
            } -> async ();

        raw_rand : shared () -> async [Nat8];
        start_canister: shared { canister_id: CanisterId } -> async ();
        stop_canister: shared { canister_id: CanisterId } -> async ();
        uninstall_code: shared { canister_id: CanisterId } -> async ();

        update_settings: shared {
            canister_id: Principal;
            settings: canister_settings;
            } -> async ();
    };
}