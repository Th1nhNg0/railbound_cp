% ============================================================
% constraints/eswitches.mzn - Exit-Triggered Switch Mechanics
% ============================================================
% An exit-triggered switch (ESWITCH, the game's "switch rail") flips its
% routing each time a vehicle arrives on it.  The arriving vehicle keeps the
% exit it was given on entry (see train_heading); vehicles entering later see
% the flipped routing.  Arrivals at time t - 1 take effect at time t, the same
% timing as activation tiles.
% ============================================================

constraint forall(es in ESWITCH_INDICES)(
  let { int: q = ESWITCH_CELLS[es]; } in
  eswitch_toggled[es, 0] = false /\
  forall(t in 1..MAX_TIME)(
    eswitch_toggled[es, t] = (eswitch_toggled[es, t - 1] xor xorall(
      [ train_entered(tr, q, t) | tr in 1..N_TRAINS ] ++
      [ decoy_entered(d, q, t) | d in 1..N_DECOYS ]
    ))
  )
);
