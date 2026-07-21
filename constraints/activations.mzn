% ============================================================
% constraints/activations.mzn - Activation Tiles & Gate/Dswitch Toggling
% ============================================================
% Defines activation tile behavior: when a train enters an activation cell,
% it triggers toggles for linked gates and dynamic switches.
% ============================================================

% Include every ID used by an activation consumer.  A gate or dynamic switch
% may intentionally have no matching activation tile; its toggle group must
% still exist and evaluate to false rather than causing an out-of-bounds read.
int: MAX_ACTIVATION_ID = if N_ACTIVATIONS > 0 then max([ACTIVATIONS[i].3 | i in 1..N_ACTIVATIONS]) else 0 endif;
int: MAX_GATE_ACTIVATION_ID = if N_GATES > 0 then max([GATES[g].3 | g in GATE_INDICES]) else 0 endif;
int: MAX_DSWITCH_ACTIVATION_ID = if N_DSWITCHES > 0 then max([DSWITCHES[ds].3 | ds in DSWITCH_INDICES]) else 0 endif;
int: MAX_ID = max([MAX_ACTIVATION_ID, MAX_GATE_ACTIVATION_ID, MAX_DSWITCH_ACTIVATION_ID]);
set of int: ACTIVATION_IDS = if MAX_ID = 0 then {} else 1..MAX_ID endif;

% ==== TOGGLE STATE TRACKING ====
% should_toggle[a, t]: true if activation 'a' should toggle at time t (odd number of new entries).
array[ACTIVATION_IDS, 0..MAX_TIME] of var bool: should_toggle;

% ==== INITIAL TOGGLE STATE ====
constraint if MAX_ID > 0 then
    forall(a in ACTIVATION_IDS)(
        should_toggle[a, 0] = false
    ) /\
    forall(a in ACTIVATION_IDS, t in 1..MAX_TIME)(
        should_toggle[a, t] = ((sum(
            act in 1..N_ACTIVATIONS where ACTIVATIONS[act].3 = a
        )(
            sum(tr in 1..N_TRAINS where arrival_time[tr] >= t)(
                bool2int(
                    train_row[tr, t - 1] = ACTIVATIONS[act].1 /\
                    train_col[tr, t - 1] = ACTIVATIONS[act].2 /\
                    (t = 1 \/ train_row[tr, max(0, t - 2)] != ACTIVATIONS[act].1 \/ train_col[tr, max(0, t - 2)] != ACTIVATIONS[act].2)
                )
            ) + sum(d in 1..N_DECOYS)(
                bool2int(
                    decoy_row[d, t - 1] = ACTIVATIONS[act].1 /\
                    decoy_col[d, t - 1] = ACTIVATIONS[act].2 /\
                    (t = 1 \/ decoy_row[d, max(0, t - 2)] != ACTIVATIONS[act].1 \/ decoy_col[d, max(0, t - 2)] != ACTIVATIONS[act].2)
                )
            )
        )) mod 2 = 1)
    )
else true endif;

% ==== GATE INITIAL STATE ====
% Gates start in the state specified by the input data.
constraint N_GATES > 0 -> forall(g in GATE_INDICES)(gate_open[g, 0] = GATES[g].4);

% ==== DSWITCH INITIAL STATE ====
% Dynamic switches start in non-toggled state.
constraint N_DSWITCHES > 0 ->
    forall(ds in DSWITCH_INDICES)(
        dswitch_toggled[ds, 0] = false
    );

% ==== GATE STATE TRANSITION ====
% Gates toggle when their activation ID triggers, else maintain state.
constraint N_GATES > 0 /\ MAX_ID > 0 ->
    forall(g in GATE_INDICES, t in 1..MAX_TIME)(
        gate_open[g, t] = if should_toggle[GATES[g].3, t] then not gate_open[g, t - 1] else gate_open[g, t - 1] endif % Toggle or hold.
    );

% ==== DSWITCH STATE TRANSITION ====
% Dynamic switches toggle when their activation ID triggers, else maintain state.
constraint N_DSWITCHES > 0 /\ MAX_ID > 0 ->
    forall(ds in DSWITCH_INDICES, t in 1..MAX_TIME)(
        dswitch_toggled[ds, t] = if should_toggle[DSWITCHES[ds].3, t] then not dswitch_toggled[ds, t - 1] else dswitch_toggled[ds, t - 1] endif % Toggle or hold.
    );
