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
% Manages how DSWITCH states change over time based on trains passing through.
constraint if N_DSWITCHES > 0 then
    forall(t in 1..MAX_TIME, ds in 1..N_DSWITCHES)(
            let {
                % Check if any train just entered (not already on) an activation cell linked to this gate at the PREVIOUS timestep.
            var bool: was_activated = if t = 0 then false else exists(a in 1..N_ACTIVATIONS)(
                ACTIVATIONS[a].3 = DSWITCHES[ds].3 /\ % Check if activation `a` is linked to gate `g` by gate ID.
                exists(tr in 1..N_TRAINS)(
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
        } in
        % The DSWITCH's state at time `t` is the inverse of its state at `t-1` if triggered at `t-1`,
        % otherwise it remains unchanged.
        dswitch_toggled[ds, t] = if was_activated then not dswitch_toggled[ds, t - 1] else dswitch_toggled[ds, t - 1] endif
    )
else true endif;
