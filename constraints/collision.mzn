% ============================================================
% Collision Avoidance
% ------------------------------------------------------------
% Ensures trains never occupy the same cell simultaneously and
% prevents position swaps between consecutive timesteps.
% ============================================================

% 5) Collision avoidance: no two trains at same cell except at target
constraint forall(time in 0..MAX_TIME, t1 in 1..N_TRAINS, t2 in t1+1..N_TRAINS) (
  let {
    var 1..H: r1 = train_row[t1, time];
    var 1..W: c1 = train_col[t1, time];
    var 1..H: r2 = train_row[t2, time];
    var 1..W: c2 = train_col[t2, time];
  } in
  (r1, c1) != (r2, c2) \/ (r1 = TARGET.1 /\ c1 = TARGET.2)
);

% 6) Prevent position swaps between timesteps (except at target)
constraint forall(time in 0..MAX_TIME-1, t1 in 1..N_TRAINS, t2 in t1+1..N_TRAINS) (
  let {
    var 1..H: r1t = train_row[t1, time];
    var 1..W: c1t = train_col[t1, time];
    var 1..H: r2t = train_row[t2, time];
    var 1..W: c2t = train_col[t2, time];
    var 1..H: r1n = train_row[t1, time+1];
    var 1..W: c1n = train_col[t1, time+1];
    var 1..H: r2n = train_row[t2, time+1];
    var 1..W: c2n = train_col[t2, time+1];
  } in
  (
    not ((r1t = r2n /\ c1t = c2n) /\ (r2t = r1n /\ c2t = c1n))
    \/ (r1t = TARGET.1 /\ c1t = TARGET.2)
    \/ (r2t = TARGET.1 /\ c2t = TARGET.2)
    \/ (r1n = TARGET.1 /\ c1n = TARGET.2)
    \/ (r2n = TARGET.1 /\ c2n = TARGET.2)
  )
);
