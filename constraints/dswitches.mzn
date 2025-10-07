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
                % Count the NUMBER of trains that just entered activation cells linked to this dswitch at the PREVIOUS timestep.
                % Each train that enters an activation cell causes one toggle.
                % If the count is odd, the dswitch toggles; if even, it stays the same.
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
            % An odd number of activations toggles the state; an even number keeps it the same.
            var bool: should_toggle = (num_activations mod 2) = 1;
        } in
        % The DSWITCH's state at time `t` is the inverse of its state at `t-1` if an odd number of activations occurred,
        % otherwise it remains unchanged.
        dswitch_toggled[ds, t] = if should_toggle then not dswitch_toggled[ds, t - 1] else dswitch_toggled[ds, t - 1] endif
    )
else true endif;
