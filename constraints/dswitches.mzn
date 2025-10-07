% constraints/dswitches.mzn
%
% Defines constraints for dynamic switch mechanics.
%
% Dynamic switches (DSWITCHES) toggle their orientation each time a train
% passes through them. The constraints ensure:
% 1. DSWITCHES start in their default (non-toggled) state.
% 2. The state of a DSWITCH flips when a train enters the DSWITCH cell.
% 3. The exit direction depends on the current toggle state.

% --- DSWITCH Initial State ---
% All dynamic switches start in the non-toggled state at time 0.
constraint if N_DSWITCHES > 0 then
    forall(ds in 1..N_DSWITCHES)(
        dswitch_toggled[ds, 0] = false
    )
else true endif;

% --- DSWITCH State Propagation ---
% Manages how dynamic switch states change over time based on activation cells.
constraint if N_DSWITCHES > 0 then
    forall(t in 1..MAX_TIME, ds in 1..N_DSWITCHES)(
            let {
                % Count the number of trains that newly entered activation cells linked to this dswitch in the previous timestep.
                % Each newly entered activation triggers one toggle.
                % Odd number of triggers: dswitch toggles state; even number: dswitch remains unchanged.
            var int: num_activations = if t = 0 then 0 else sum(a in 1..N_ACTIVATIONS, tr in 1..N_TRAINS)(
                bool2int(
                    ACTIVATIONS[a].3 = DSWITCHES[ds].3 /\ % Check if activation `a` is linked to dswitch `ds` by ID.
                    % Train is at activation cell at time t-1
                    train_row[tr, t - 1] = ACTIVATIONS[a].1 /\
                    train_col[tr, t - 1] = ACTIVATIONS[a].2 /\
                    % Train was NOT at this cell at time t-2 (newly entered)
                    (if t > 1 then
                        train_row[tr, t - 2] != ACTIVATIONS[a].1 \/
                        train_col[tr, t - 2] != ACTIVATIONS[a].2
                    else % At t=1, we compare against the initial position at t=0.
                        train_row[tr, 0] != ACTIVATIONS[a].1 \/
                        train_col[tr, 0] != ACTIVATIONS[a].2
                    endif)
                )
            ) endif;
            % Toggle occurs if an odd number of activations happened.
            var bool: should_toggle = (num_activations mod 2) = 1;
        } in
        % Dynamic switch state at time t is toggled from t-1 if should_toggle is true, otherwise unchanged.
        dswitch_toggled[ds, t] = if should_toggle then not dswitch_toggled[ds, t - 1] else dswitch_toggled[ds, t - 1] endif
    )
else true endif;
