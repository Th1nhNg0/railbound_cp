% ============================================================
% constraints/activations.mzn - Activation Tiles & Gate/Dswitch Toggling
% ============================================================
% Defines activation tile behavior: when a train enters an activation cell,
% it triggers toggles for linked gates and dynamic switches.
% ============================================================

% Maximum activation ID used in the puzzle.
int: MAX_ID = if N_ACTIVATIONS > 0 then max([ACTIVATIONS[i].3 | i in 1..N_ACTIVATIONS]) else 0 endif;

% ==== TOGGLE STATE TRACKING ====
% should_toggle[a, t]: true if activation 'a' should toggle at time t (odd number of new entries).
array[1..MAX_ID, 0..MAX_TIME] of var bool: should_toggle;

% ==== INITIAL TOGGLE STATE ====
% No toggles at time 0 or 1 (before any train can activate).
constraint forall(a in 1..MAX_ID)(
    should_toggle[a, 0] = false /\
    should_toggle[a, 1] = false
);

% ==== DETERMINE TOGGLE AT EACH TIMESTEP ====
% Toggle occurs when odd number of trains/decoys newly enter the activation cell.
constraint forall(a in 1..MAX_ID, t in 2..MAX_TIME)(
    should_toggle[a, t] = ((sum(
        act in 1..N_ACTIVATIONS where ACTIVATIONS[act].3 = a
    )(
        sum(tr in 1..N_TRAINS where arrival_time[tr] >= t)(
            bool2int(
                train_row[tr, t - 1] = ACTIVATIONS[act].1 /\ % At activation cell now.
                train_col[tr, t - 1] = ACTIVATIONS[act].2 /\
                (train_row[tr, t - 2] != ACTIVATIONS[act].1 \/ train_col[tr, t - 2] != ACTIVATIONS[act].2) % But not before.
            )
        ) + sum(d in 1..N_DECOYS)(
            bool2int(
                decoy_row[d, t - 1] = ACTIVATIONS[act].1 /\ % At activation cell now.
                decoy_col[d, t - 1] = ACTIVATIONS[act].2 /\
                (decoy_row[d, t - 2] != ACTIVATIONS[act].1 \/ decoy_col[d, t - 2] != ACTIVATIONS[act].2) % But not before.
            )
        )
    )) mod 2 = 1) % Odd number = toggle.
);

% ==== GATE INITIAL STATE ====
% Gates start in the state specified by the input data.
constraint N_ACTIVATIONS > 0 /\ N_GATES > 0 -> forall(g in 1..N_GATES)(gate_open[g, 0] = GATES[g].4);

% ==== DSWITCH INITIAL STATE ====
% Dynamic switches start in non-toggled state.
constraint N_ACTIVATIONS >0 /\ N_DSWITCHES > 0 ->
    forall(ds in 1..N_DSWITCHES)(
        dswitch_toggled[ds, 0] = false
    );

% ==== GATE STATE TRANSITION ====
% Gates toggle when their activation ID triggers, else maintain state.
constraint N_GATES > 0 /\ N_ACTIVATIONS > 0 ->
    forall(g in 1..N_GATES, t in 1..MAX_TIME)(
        gate_open[g, t] = if should_toggle[GATES[g].3, t] then not gate_open[g, t - 1] else gate_open[g, t - 1] endif % Toggle or hold.
    );

% ==== DSWITCH STATE TRANSITION ====
% Dynamic switches toggle when their activation ID triggers, else maintain state.
constraint N_DSWITCHES > 0 /\ N_ACTIVATIONS > 0 ->
    forall(ds in 1..N_DSWITCHES, t in 1..MAX_TIME)(
        dswitch_toggled[ds, t] = if should_toggle[DSWITCHES[ds].3, t] then not dswitch_toggled[ds, t - 1] else dswitch_toggled[ds, t - 1] endif % Toggle or hold.
    );