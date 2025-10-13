
/******************************************************************************
 * Activations, Gates, and DSwitches
 *
 * This file models the behavior of activation cells and the gates and
 * dynamic switches (dswitches) they control. When a train enters an
 * activation cell, it triggers a toggle event for its linked gate or dswitch.
 ******************************************************************************/

% The highest ID used for any activation.
int: MAX_ID = if N_ACTIVATIONS > 0 then max([ACTIVATIONS[i].3 | i in 1..N_ACTIVATIONS]) else 0 endif;

% should_toggle[a, t] is true if activation 'a' should toggle its linked
% gate at time 't'. This happens when an odd number of trains newly enter
% the corresponding activation cell at time 't-1'.
array[1..MAX_ID, 0..MAX_TIME] of var bool: should_toggle;

% Initially, no gates are toggled at time 0.
constraint forall(a in 1..MAX_ID)(
    should_toggle[a, 0] = false /\
    should_toggle[a, 1] = false
);

% Determine if a toggle should occur at each time step.
constraint forall(a in 1..MAX_ID, t in 2..MAX_TIME)(
    should_toggle[a, t] = (sum(
        act in 1..N_ACTIVATIONS, tr in 1..N_TRAINS
        where ACTIVATIONS[act].3 = a /\ arrival_time[tr] > t
    )(
        bool2int(
            % Train is at activation cell at time t-1
            train_row[tr, t - 1] = ACTIVATIONS[act].1 /\
            train_col[tr, t - 1] = ACTIVATIONS[act].2 /\
            % Train was NOT at this cell at time t-2 (newly entered)
            (train_row[tr, t - 2] != ACTIVATIONS[act].1 \/ train_col[tr, t - 2] != ACTIVATIONS[act].2)
        )
    ) mod 2 = 1)
);

% Set the initial state of each gate based on the input data.
constraint N_ACTIVATIONS > 0 /\ N_GATES > 0 -> forall(g in 1..N_GATES)(gate_open[g, 0] = GATES[g].4);

constraint N_ACTIVATIONS >0 /\ N_DSWITCHES > 0 ->
    forall(ds in 1..N_DSWITCHES)(
        dswitch_toggled[ds, 0] = false
    );

% Update gate states based on toggle events.
constraint N_GATES > 0 /\ N_ACTIVATIONS > 0 ->
    forall(g in 1..N_GATES, t in 1..MAX_TIME)(
        gate_open[g, t] = if should_toggle[GATES[g].3, t] then not gate_open[g, t - 1] else gate_open[g, t - 1] endif
    );
constraint N_DSWITCHES > 0 /\ N_ACTIVATIONS > 0 ->
    forall(ds in 1..N_DSWITCHES, t in 1..MAX_TIME)(
        dswitch_toggled[ds, t] = if should_toggle[DSWITCHES[ds].3, t] then not dswitch_toggled[ds, t - 1] else dswitch_toggled[ds, t - 1] endif
    );
