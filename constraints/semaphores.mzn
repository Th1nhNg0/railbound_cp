% ============================================================
% constraints/semaphores.mzn - Semaphore Placement & Behavior
% ============================================================
% Models user-placeable semaphores that act like gates on track cells
% adjacent to switches. Semaphores start closed, then flip open one timestep
% after any train enters a connected switch that feeds their guarded track,
% remaining open for the rest of the run.
% ============================================================

function var bool: semaphore_trigger(1..H: r, 1..W: c, var 0..(MAX_TIME + 1): t) :: cache_result =
  if t < 1 \/ t > MAX_TIME then false
  else
    exists(d in Dir)(
      let {
        0..H+1: sr = r + dr[d];
        0..W+1: sc = c + dc[d];
      } in
      can_connect[grid[r, c], d] /\
      sr >= 1 /\ sr <= H /\ sc >= 1 /\ sc <= W /\
      grid[sr, sc] in SWITCH_VARIANTS_SET /\
      can_connect[grid[sr, sc], opposite[d]] /\
      (
        exists(tr in 1..N_TRAINS where
          arrival_time[tr] >= t /\
          train_row[tr, t - 1] = sr /\
          train_col[tr, t - 1] = sc)(
            (t = 1 \/ train_row[tr, max(0, t - 2)] != sr \/ train_col[tr, max(0, t - 2)] != sc)
        ) \/
        (if N_DECOYS = 0 then false else
          exists(dq in 1..N_DECOYS where
            decoy_row[dq, t - 1] = sr /\
            decoy_col[dq, t - 1] = sc)(
              (t = 1 \/ decoy_row[dq, max(0, t - 2)] != sr \/ decoy_col[dq, max(0, t - 2)] != sc)
          )
        endif)
      )
    )
  endif;

% ==== SUPPLY CONSTRAINT ====
% Player cannot place more semaphores than provided by the puzzle.
constraint
  sum(r in 1..H, c in 1..W)(bool2int(semaphore_present[r, c])) <= SEMAPHORE_SUPPLY;

% Force presence to false when no semaphores are available.
constraint SEMAPHORE_SUPPLY = 0 -> forall(r in 1..H, c in 1..W)(not semaphore_present[r, c]);

% ==== PLACEMENT ELIGIBILITY CONSTRAINTS ====
% Direct verification on semaphore_present cell attributes:
constraint forall(r in 1..H, c in 1..W)(
  semaphore_present[r, c] -> (
      grid[r, c] in SEMAPHORE_ELIGIBLE_SET /\
      (N_GATES = 0 \/ not cell_has_gate[r, c]) /\
      (if N_ACTIVATIONS = 0 then true else
        forall(a in 1..N_ACTIVATIONS)(
          ACTIVATIONS[a].1 != r \/ ACTIVATIONS[a].2 != c
        )
      endif) /\
      exists(d in Dir)(
        let {
          0..H+1: sr = r + dr[d];
          0..W+1: sc = c + dc[d];
        } in
        if sr >= 1 /\ sr <= H /\ sc >= 1 /\ sc <= W then
          can_connect[grid[r, c], d] /\
          grid[sr, sc] in SWITCH_VARIANTS_SET /\
          can_connect[grid[sr, sc], opposite[d]]
        else false endif
      )
  )
);

% ==== TIMING & STATE EVOLUTION RULES ====
% Unused cells have open time 0. Placed semaphores open at the earliest trigger timestep,
% or stay closed (represented by MAX_TIME + 1).
constraint forall(r in 1..H, c in 1..W)(
  (not semaphore_present[r, c]) -> semaphore_open_time[r, c] = 0
);

constraint forall(r in 1..H, c in 1..W)(
  semaphore_present[r, c] -> (
    semaphore_open_time[r, c] >= 1 /\
    semaphore_open_time[r, c] <= MAX_TIME + 1 /\
    (semaphore_open_time[r, c] <= MAX_TIME -> semaphore_trigger(r, c, semaphore_open_time[r, c])) /\
    forall(t in 1..MAX_TIME)(
      (t < semaphore_open_time[r, c]) -> not semaphore_trigger(r, c, t)
    )
  )
);
