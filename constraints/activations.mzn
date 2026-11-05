% ============================================================
% constraints/activations.mzn - Activation Tiles & Gate/Dswitch Toggling
% ============================================================
% Defines activation tile behavior: when a train enters an activation cell,
% it triggers toggles for linked gates and dynamic switches.
% ============================================================

% ==== ENTRY EVENTS (shared with semaphores) ====
% train_entered(tr, q, t): active train tr stepped onto cell q at time t - 1
% (it was elsewhere at t - 2, or t = 1 and q is its start cell).
function var bool: train_entered(int: tr, int: q, int: t) =
  arrival_time[tr] >= t /\
  train_pos[tr, t - 1] = q /\
  (t = 1 \/ train_pos[tr, t - 2] != q);

% decoy_entered(d, q, t): same event for decoy d (decoys never retire).
function var bool: decoy_entered(int: d, int: q, int: t) =
  decoy_pos[d, t - 1] = q /\
  (t = 1 \/ decoy_pos[d, t - 2] != q);

% Include every ID used by an activation consumer.  A gate or dynamic switch
% may intentionally have no matching activation tile; its toggle group must
% still exist and evaluate to false rather than causing an out-of-bounds read.
int: MAX_ACTIVATION_ID = max([0] ++ [ACTIVATIONS[i].3 | i in 1..N_ACTIVATIONS]);
int: MAX_GATE_ACTIVATION_ID = max([0] ++ [GATES[g].3 | g in GATE_INDICES]);
int: MAX_DSWITCH_ACTIVATION_ID = max([0] ++ [DSWITCHES[ds].3 | ds in DSWITCH_INDICES]);
int: MAX_ID = max([MAX_ACTIVATION_ID, MAX_GATE_ACTIVATION_ID, MAX_DSWITCH_ACTIVATION_ID]);
set of int: ACTIVATION_IDS = 1..MAX_ID;

% ==== TOGGLE STATE TRACKING ====
% should_toggle[a, t]: activation group 'a' toggles at time t (an odd number
% of entries onto its tiles at t - 1).  Parity is expressed with xorall
% rather than a sum mod 2, which keeps it a pure Boolean constraint.
array[ACTIVATION_IDS, 0..MAX_TIME] of var bool: should_toggle = array2d(ACTIVATION_IDS, 0..MAX_TIME, [
  if t = 0 then false
  else
    xorall(
      [ train_entered(tr, cell(ACTIVATIONS[act].1, ACTIVATIONS[act].2), t)
      | act in 1..N_ACTIVATIONS where ACTIVATIONS[act].3 = a, tr in 1..N_TRAINS ] ++
      [ decoy_entered(d, cell(ACTIVATIONS[act].1, ACTIVATIONS[act].2), t)
      | act in 1..N_ACTIVATIONS where ACTIVATIONS[act].3 = a, d in 1..N_DECOYS ]
    )
  endif
| a in ACTIVATION_IDS, t in 0..MAX_TIME ]);

% ==== GATE STATE ====
% Gates start in the state given by the data and flip whenever their group toggles.
constraint forall(g in GATE_INDICES)(
    gate_open[g, 0] = GATES[g].4 /\
    forall(t in 1..MAX_TIME)(
        gate_open[g, t] = (gate_open[g, t - 1] xor should_toggle[GATES[g].3, t])
    )
);

% ==== DSWITCH STATE ====
% Dynamic switches start untoggled and flip whenever their group toggles.
constraint forall(ds in DSWITCH_INDICES)(
    dswitch_toggled[ds, 0] = false /\
    forall(t in 1..MAX_TIME)(
        dswitch_toggled[ds, t] = (dswitch_toggled[ds, t - 1] xor should_toggle[DSWITCHES[ds].3, t])
    )
);
