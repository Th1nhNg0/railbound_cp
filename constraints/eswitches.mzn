% ============================================================
% constraints/eswitches.mzn - Exit-Triggered Switch Mechanics
% ============================================================
% Defines exit-triggered switch (ESWITCH) behavior: they toggle their
% orientation each time any train exits from them.
% ============================================================

% ==== ESWITCH INITIAL STATE ====
% All exit-triggered switches start in non-toggled state.
constraint if N_ESWITCHES > 0 then
    forall(es in 1..N_ESWITCHES)(
        eswitch_toggled[es, 0] = false /\ % Not toggled at time 0.
        eswitch_toggled[es, 1] = false  % Not toggled at time 1.
    )
else true endif;

% ==== ESWITCH STATE PROPAGATION ====
% Exit-triggered switches toggle based on how many trains exit on each timestep.
constraint if N_ESWITCHES > 0 then
    forall(es in 1..N_ESWITCHES, t in 2..MAX_TIME)(
        let {
            % Count exits: train/decoy at eswitch cell at t-1 but not at t (or came from different cell at t-2).
            var 0..N_TRAINS+N_DECOYS: num_exits = sum(tr in 1..N_TRAINS where arrival_time[tr] >= t)(
                bool2int(
                    train_row[tr, t - 1] = ESWITCHES_DERIVED[es].1 /\ % At eswitch cell now.
                    train_col[tr, t - 1] = ESWITCHES_DERIVED[es].2 /\
                    (train_row[tr, t-2] != ESWITCHES_DERIVED[es].1 \/ train_col[tr, t-2] != ESWITCHES_DERIVED[es].2) % Different cell before.
                )
            ) + sum(d in 1..N_DECOYS)(
                bool2int(
                    decoy_row[d, t - 1] = ESWITCHES_DERIVED[es].1 /\ % At eswitch cell now.
                    decoy_col[d, t - 1] = ESWITCHES_DERIVED[es].2 /\
                    (decoy_row[d, t] != ESWITCHES_DERIVED[es].1 \/ decoy_col[d, t] != ESWITCHES_DERIVED[es].2) /\ % Different cell next.
                    (decoy_row[d, t-2] != ESWITCHES_DERIVED[es].1 \/ decoy_col[d, t-2] != ESWITCHES_DERIVED[es].2) % Different cell before.
                )
            );
            var bool: should_be_toggle = num_exits mod 2 = 1; % Toggle if odd number of exits.
        } in
        % Toggle state if odd exits, else maintain previous state.
        eswitch_toggled[es, t] = if should_be_toggle then not eswitch_toggled[es, t - 1] else eswitch_toggled[es, t - 1] endif
    )
else true endif;