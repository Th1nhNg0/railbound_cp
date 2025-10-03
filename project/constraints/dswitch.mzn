% ============================================================
% DYNAMIC SWITCH (DSWITCH) CONSTRAINTS
%
% Defines the logic for dynamic switches, which can change
% their routing configuration when triggered by an activation.
% ============================================================

% 21) DSWITCH validation: DSWITCHes must be pre-placed via INIT_POS
constraint forall(ds in DSWITCHES) (
  grid[ds.1, ds.2] in DSWITCHES_SET
);

% 22) No coexistence: DSWITCHes cannot share cells with gates or activations
constraint forall(ds in DSWITCHES, g in GATES) (
  not (ds.1 = g.1 /\ ds.2 = g.2)
);
constraint forall(ds in DSWITCHES, a in ACTIVATIONS) (
  not (ds.1 = a.1 /\ ds.2 = a.2)
);

% 23) Initial DSWITCH states (at time 0) - all start in normal state
constraint forall(ds in 1..N_DSWITCHES) (
  dswitch_swapped[ds, 0] = false
);

% 24) DSWITCH state transitions: toggle when linked activation is triggered
%     Activations trigger if an odd number of trains enter an activation
%     cell linked to the dswitch's ID.
constraint forall(ds in 1..N_DSWITCHES, time in 0..MAX_TIME-1) (
  let {
    int: dswitch_id = DSWITCHES[ds].3;
    var int: num_entering = sum(t in 1..N_TRAINS, a in ACTIVATIONS where a.3 = dswitch_id) (
      bool2int( train_row[t, time] = a.1 /\ train_col[t, time] = a.2 /\
      (time = 0 \/ (train_row[t, time-1] != a.1 \/ train_col[t, time-1] != a.2)) )
    );
  } in
  if num_entering mod 2 = 1 then
    dswitch_swapped[ds, time+1] = not dswitch_swapped[ds, time]  % Toggle
  else
    dswitch_swapped[ds, time+1] = dswitch_swapped[ds, time]      % No change
  endif
);