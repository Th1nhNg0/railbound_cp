% ============================================================
% SEQUENCING AND COLLISION CONSTRAINTS
%
% Ensures trains arrive in the correct order, do not occupy
% the same cell at the same time (except at the target), and
% do not swap positions.
% ============================================================

% 4) Arrival ordering: trains arrive sequentially, stay at target
%    Each train reaches the target at a specific time and remains there.
%    Trains must arrive in order: train[i] arrives before train[i+1].
constraint forall(t in 1..N_TRAINS)(
  forall(time in 0..MAX_TIME) (
    (train_row[t, time] = TARGET.1 /\ train_col[t, time] = TARGET.2)
    <-> (time >= arrival_time[t])
  )
);

constraint forall(t in 1..N_TRAINS-1) (
  arrival_time[t] < arrival_time[t+1]
);

% 5) Collision avoidance: no two trains at same cell except at target
%    Prevents trains from occupying the same cell simultaneously.
%    Exception: multiple trains can be at the target cell.
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
%    Two trains cannot swap positions between consecutive timesteps.
%    This prevents "passing through" each other.
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
    % Either not swapping,
    not ( (r1t = r2n /\ c1t = c2n) /\ (r2t = r1n /\ c2t = c1n) )
    % or one of the trains is at the target (in either step).
    \/ (r1t = TARGET.1 /\ c1t = TARGET.2)
    \/ (r2t = TARGET.1 /\ c2t = TARGET.2)
    \/ (r1n = TARGET.1 /\ c1n = TARGET.2)
    \/ (r2n = TARGET.1 /\ c2n = TARGET.2)
  )
);