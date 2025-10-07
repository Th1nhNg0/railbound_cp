% constraints/gates.mzn
%
% Defines constraints for gate and activation cell mechanics.
%
% This module manages the behavior of gates, which act as barriers on tracks.
% Gates can be opened or closed, and their state is toggled when a train passes
% over a linked activation cell. The constraints ensure:
% 1. Gates start in their specified initial state (open or closed).
% 2. The state of a gate flips when a train occupies its corresponding activation cell.
% 3. Trains cannot pass through a closed gate.

% --- Gate Initial State ---
% Sets the initial state (open/closed) for each gate at time 0.
constraint forall(g in 1..N_GATES)(
    gate_open[g, 0] = GATES[g].4
);

% --- Gate State Propagation ---
% Manages how gate states change over time based on activation cells.
constraint forall(t in 1..MAX_TIME, g in 1..N_GATES)(
    let {
        % Count the number of trains that newly entered activation cells linked to this gate in the previous timestep.
        % Each newly entered activation triggers one toggle.
        % Odd number of triggers: gate toggles state; even number: gate remains unchanged.
        var int: num_activations = if t = 0 then 0 else sum(a in 1..N_ACTIVATIONS, tr in 1..N_TRAINS)(
            bool2int(
                ACTIVATIONS[a].3 = GATES[g].3 /\ % Check if activation `a` is linked to gate `g` by gate ID.
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
    % Gate state at time t is toggled from t-1 if should_toggle is true, otherwise unchanged.
    gate_open[g, t] = if should_toggle then not gate_open[g, t - 1] else gate_open[g, t - 1] endif
);

% --- Gate Passage Constraint ---
% Prevents trains from entering a cell with a closed gate.
constraint if N_GATES > 0 then
    forall(t in 1..N_TRAINS, i in 1..arrival_time[t])(
        if cell_has_gate[train_row[t, i], train_col[t, i]] then
            % If the cell has a gate, the gate must be open for the train to be there.
            gate_open[gate_index_at[train_row[t, i], train_col[t, i]], i]
        else
            true
        endif
    )
else true endif;