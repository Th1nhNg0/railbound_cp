% ============================================================
% constraints/eswitches.mzn - Exit-Triggered Switch Mechanics
% ============================================================
% Defines exit-triggered switch (ESWITCH) behavior: they toggle their
% orientation each time a vehicle that arrived on them leaves.
% ============================================================

constraint forall(es in ESWITCH_INDICES)(
  let { int: q = ESWITCH_CELLS[es]; } in
  % All exit-triggered switches start in the non-toggled state.
  eswitch_toggled[es, 0] = false /\
  eswitch_toggled[es, 1] = false /\
  forall(t in 2..MAX_TIME)(
    % An exit: on the switch at t - 1, elsewhere at t and at t - 2.
    eswitch_toggled[es, t] = (eswitch_toggled[es, t - 1] xor xorall(
      [ arrival_time[tr] >= t /\
        train_pos[tr, t - 1] = q /\ train_pos[tr, t] != q /\ train_pos[tr, t - 2] != q
      | tr in 1..N_TRAINS ] ++
      [ decoy_pos[d, t - 1] = q /\ decoy_pos[d, t] != q /\ decoy_pos[d, t - 2] != q
      | d in 1..N_DECOYS ]
    ))
  )
);
