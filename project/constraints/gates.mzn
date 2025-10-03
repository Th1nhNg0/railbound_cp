% ============================================================
% GATE AND ACTIVATION CONSTRAINTS
%
% Defines the logic for gates, which act as barriers, and
% activations, which toggle the state of gates.
% ============================================================

% 12) Gate validation: gates must be on non-EMPTY track pieces
constraint forall(g in GATES) (
  grid[g.1, g.2] != EMPTY
);

% 13) Gate validation: gates only on STRAIGHT, CORNER, or SWITCH tracks
constraint forall(g in GATES) (
  grid[g.1, g.2] in (STRAIGHTS union CORNERS union SWITCHES)
);

% 14) Activation validation: activations must be on non-EMPTY track pieces
constraint forall(a in ACTIVATIONS) (
  grid[a.1, a.2] != EMPTY
);

% 15) Activation validation: activations only on STRAIGHT, CORNER, SWITCH, or DSWITCH tracks
constraint forall(a in ACTIVATIONS) (
  grid[a.1, a.2] in (STRAIGHTS union CORNERS union SWITCHES union DSWITCHES_SET)
);

% 16) No coexistence: gates and activations cannot share the same cell
constraint forall(g in GATES, a in ACTIVATIONS) (
  not (g.1 = a.1 /\ g.2 = a.2)
);

% 17) Initial gate states (at time 0)
constraint forall(g in 1..N_GATES) (
  gate_open[g, 0] = GATES[g].4
);

% 18) Initial position safety: trains cannot start on closed gates
constraint forall(t in 1..N_TRAINS) (
  if N_GATES = 0 then
    true
  elseif cell_has_gate[TRAINS[t].1, TRAINS[t].2] then
    GATES[gate_index_at[TRAINS[t].1, TRAINS[t].2]].4
  else
    true
  endif
);

% 19) Gate state transitions: toggle when activation is triggered
%     Activations trigger if an odd number of trains enter an activation
%     cell linked to the gate's ID.
constraint forall(g in 1..N_GATES, time in 0..MAX_TIME-1) (
  let {
    int: gate_id = GATES[g].3;
    var int: num_entering = sum(t in 1..N_TRAINS, a in ACTIVATIONS where a.3 = gate_id) (
      bool2int( train_row[t, time] = a.1 /\ train_col[t, time] = a.2 /\
      (time = 0 \/ (train_row[t, time-1] != a.1 \/ train_col[t, time-1] != a.2)) )
    );
  } in
  if num_entering mod 2 = 1 then
    gate_open[g, time+1] = not gate_open[g, time]  % Toggle
  else
    gate_open[g, time+1] = gate_open[g, time]      % No change
  endif
);

% 20) Gate blocking: trains cannot move into cells with closed gates
constraint forall(t in 1..N_TRAINS, time in 0..MAX_TIME) (
  if N_GATES = 0 then
    true
  else
    let {
      var bool: at_gate = cell_has_gate[train_row[t, time], train_col[t, time]];
      var int: gate_idx = gate_index_at[train_row[t, time], train_col[t, time]];
    } in
      if at_gate then gate_open[gate_idx, time] else true endif
  endif
);