% ============================================================
% constraints/semaphores.mzn - Semaphore Placement & Behavior
% ============================================================
% Models user-placeable semaphores that act like gates on track cells
% adjacent to switches. Semaphores start closed, then flip open one timestep
% after any train enters a connected switch that feeds their guarded track,
% remaining open for the rest of the run.
% ============================================================

function var bool: semaphore_trigger(1..H: r, 1..W: c, var 0..(MAX_TIME + 1): t) =
  if t < 2 then false
  else
    exists(d in Dir)(
      let {
        0..H+1: sr = r + dr[d];
        0..W+1: sc = c + dc[d];
      } in
      can_connect[grid[r, c], d] /\
      (
        if sr >= 1 /\ sr <= H /\ sc >= 1 /\ sc <= W then
          grid[sr, sc] in SWITCH_VARIANTS_SET /\
          can_connect[grid[sr, sc], opposite[d]] /\
          (
            exists(tr in 1..N_TRAINS)(
              arrival_time[tr] >= t /\
              train_row[tr, t - 1] = sr /\
              train_col[tr, t - 1] = sc /\
              (train_row[tr, t - 2] != sr \/ train_col[tr, t - 2] != sc) /\
              (train_row[tr, t] != r \/ train_col[tr, t] != c)
            ) \/
            exists(dq in 1..N_DECOYS)(
              decoy_row[dq, t - 1] = sr /\
              decoy_col[dq, t - 1] = sc /\
              (decoy_row[dq, t - 2] != sr \/ decoy_col[dq, t - 2] != sc) /\
              (decoy_row[dq, t] != r \/ decoy_col[dq, t] != c)
            )
          )
        else false endif
      )
    )
  endif;

% ==== SUPPLY CONSTRAINT ====
% Player cannot place more semaphores than provided by the puzzle.
constraint
  sum(r in 1..H, c in 1..W)(bool2int(semaphore_present[r, c])) <= SEMAPHORE_SUPPLY;

% Match count of occupied slots and present semaphores.
constraint
  sum(s in SEMAPHORE_SLOTS)(bool2int(semaphore_place_row[s] != 0)) =
  sum(r in 1..H, c in 1..W)(bool2int(semaphore_present[r, c]));

% Force coordinate slots to (0,0) when no semaphores are available.
constraint SEMAPHORE_SUPPLY = 0 ->
  forall(s in SEMAPHORE_SLOTS)(
    semaphore_place_row[s] = 0 /\ semaphore_place_col[s] = 0
  );
constraint SEMAPHORE_SUPPLY = 0 -> forall(r in 1..H, c in 1..W)(not semaphore_present[r, c]);

% Each semaphore slot is either unused (0,0) or references a valid cell pair.
constraint forall(s in SEMAPHORE_SLOTS)(
  (semaphore_place_row[s] = 0) <-> (semaphore_place_col[s] = 0)
);

% Prevent placing more than one semaphore on the same cell.
constraint forall(s1 in SEMAPHORE_SLOTS, s2 in s1 + 1..SEMAPHORE_SLOT_COUNT)(
  (semaphore_place_row[s1] = 0 /\ semaphore_place_col[s1] = 0) \/
  (semaphore_place_row[s2] = 0 /\ semaphore_place_col[s2] = 0) \/
  semaphore_place_row[s1] != semaphore_place_row[s2] \/
  semaphore_place_col[s1] != semaphore_place_col[s2]
);

% Symmetry breaking: enforce lexicographic ordering of semaphore slots.
constraint forall(s in 1..SEMAPHORE_SLOT_COUNT - 1)(
  lex_lesseq(
    [semaphore_place_row[s], semaphore_place_col[s]],
    [semaphore_place_row[s + 1], semaphore_place_col[s + 1]]
  )
);

% ==== SLOT TIMING RULES ====
% Unused slots have opening time 0; used slots respect semaphore timing bounds.
constraint forall(s in SEMAPHORE_SLOTS)(
  semaphore_place_row[s] = 0 -> semaphore_slot_open_time[s] = 0
);
constraint forall(s in SEMAPHORE_SLOTS)(
  semaphore_place_row[s] != 0 ->
    semaphore_slot_open_time[s] >= 2 /\
    semaphore_slot_open_time[s] <= MAX_TIME + 1
);

% ==== VALID PLACEMENT RULES ====
% Semaphores may only be placed on straights or corners that connect to at least one switch variant.
constraint forall(r in 1..H, c in 1..W)(
  semaphore_present[r, c] ->
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
);

% ==== BASE STATE ====
% Cells without a semaphore behave as always-open (open time = 0). Placed semaphores
% have an opening time of at least 2 (cannot open before the trigger timestep).
constraint forall(r in 1..H, c in 1..W)(
  (not semaphore_present[r, c]) -> semaphore_open_time[r, c] = 0
);
constraint forall(r in 1..H, c in 1..W)(
  semaphore_present[r, c] ->
    semaphore_open_time[r, c] >= 2 /\
    semaphore_open_time[r, c] <= MAX_TIME + 1
);

% ==== STATE EVOLUTION ====
% A placed semaphore opens at the earliest trigger timestep if one occurs, otherwise stays closed.
constraint forall(r in 1..H, c in 1..W)(
  semaphore_present[r, c] /\
  semaphore_open_time[r, c] <= MAX_TIME ->
    semaphore_trigger(r, c, semaphore_open_time[r, c])
);
constraint forall(r in 1..H, c in 1..W)(
  semaphore_present[r, c] ->
    forall(t in 2..MAX_TIME)(
      (t < semaphore_open_time[r, c]) -> not semaphore_trigger(r, c, t)
    )
);
