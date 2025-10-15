% constraints/eswitches.mzn
%
% Defines constraints for exit-triggered switch mechanics.
%
% Exit-triggered switches (ESWITCHES) toggle their orientation each time a train
% exits from them. The constraints ensure:
% 1. ESWITCHES start in their default (non-toggled) state.
% 2. The state of an ESWITCH flips when a train exits the ESWITCH cell.
% 3. The exit direction depends on the current toggle state.

% --- ESWITCH Initial State ---
% All exit-triggered switches start in the non-toggled state at time 0.
constraint if N_ESWITCHES > 0 then
    forall(es in 1..N_ESWITCHES)(
        eswitch_toggled[es, 0] = false /\
        eswitch_toggled[es, 1] = false
    )
else true endif;

% --- ESWITCH State Propagation ---
% Manages how exit-triggered switch states change over time based on train exits.
constraint if N_ESWITCHES > 0 then
    forall(es in 1..N_ESWITCHES, t in 2..MAX_TIME)(
        let {
            % Count the number of trains and decoys that exited from this eswitch cell in the previous timestep.
            % A train/decoy exits when it was at the eswitch cell at time t-1 but is somewhere else at time t.
            var 0..N_TRAINS+N_DECOYS: num_exits = sum(tr in 1..N_TRAINS where arrival_time[tr] >= t)(
                bool2int(
                    % Train was at eswitch cell at time t-1
                    train_row[tr, t - 1] = ESWITCHES_DERIVED[es].1 /\
                    train_col[tr, t - 1] = ESWITCHES_DERIVED[es].2 /\
                    % Train is NOT at this cell at time t (has exited)
                    (train_row[tr, t-2] != ESWITCHES_DERIVED[es].1 \/ train_col[tr, t-2] != ESWITCHES_DERIVED[es].2)
                )
            ) + sum(d in 1..N_DECOYS)(
                bool2int(
                    % Decoy was at eswitch cell at time t-1
                    decoy_row[d, t - 1] = ESWITCHES_DERIVED[es].1 /\
                    decoy_col[d, t - 1] = ESWITCHES_DERIVED[es].2 /\
                    (decoy_row[d, t] != ESWITCHES_DERIVED[es].1 \/ decoy_col[d, t] != ESWITCHES_DERIVED[es].2) /\
                    % Decoy is NOT at this cell at time t (has exited)
                    (decoy_row[d, t-2] != ESWITCHES_DERIVED[es].1 \/ decoy_col[d, t-2] != ESWITCHES_DERIVED[es].2)
                )
            );
            % Toggle occurs if an odd number of exits happened.
            var bool: should_be_toggle = num_exits mod 2 = 1;
        } in
        % Exit-triggered switch state at time t is toggled from t-1 if should_toggle is true, otherwise unchanged.
        eswitch_toggled[es, t] = if should_be_toggle then not eswitch_toggled[es, t - 1] else eswitch_toggled[es, t - 1] endif
    )
else true endif;