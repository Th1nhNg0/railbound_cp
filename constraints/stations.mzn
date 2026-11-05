% ============================================================
% constraints/stations.mzn - Station Visitation & Dwell Time
% ============================================================
% Defines station mechanics: trains must visit assigned stations,
% incur a 2-step dwell time on first arrival, and visit all stations
% before reaching the target.  STATIONS[st].3 > 0 names a train,
% < 0 names decoy -STATIONS[st].3.
% ============================================================

array[1..N_STATIONS] of CELLS: station_cell = [ cell(STATIONS[st].1, STATIONS[st].2) | st in 1..N_STATIONS ];

% ==== STATION VISITATION TRACKING ====
% station_visited_by_time[st, t]: the assigned vehicle has been on st by time t.
constraint forall(st in 1..N_STATIONS, time in 0..MAX_TIME)(
  let {
    int: v = STATIONS[st].3;
    var bool: here = if v > 0 then train_pos[v, time] = station_cell[st]
                     else decoy_pos[-v, time] = station_cell[st] endif;
  } in
  station_visited_by_time[st, time] =
    if time = 0 then here else (here \/ station_visited_by_time[st, time - 1]) endif
);

% ==== STATION WAIT TIME ====
% A vehicle waits 2 steps on the first arrival at any of its stations.
predicate station_dwell(array[int] of var 0..2: wait, array[int] of var CELLS: pos, int: vehicle_id) =
  let { array[int] of int: mine = [ st | st in 1..N_STATIONS where STATIONS[st].3 = vehicle_id ]; } in
  forall(time in STATION_TIMES)(
    if length(mine) = 0 then
      wait[time] = 0
    else
      let {
        var bool: at_any = exists(st in mine)(pos[time] = station_cell[st]);
        var bool: first_visit = if time = 0 then at_any else
          exists(st in mine)(pos[time] = station_cell[st] /\ not station_visited_by_time[st, time - 1]) endif;
      } in
      wait[time] =
        if first_visit then 2
        elseif time > 0 then (if at_any /\ wait[time - 1] > 0 then wait[time - 1] - 1 else 0 endif)
        else 0 endif
    endif
  );

constraint forall(t in 1..N_TRAINS)(
  station_dwell(array1d(STATION_TIMES, [station_wait_time[t, i] | i in STATION_TIMES]),
                array1d(STATION_TIMES, [train_pos[t, i] | i in STATION_TIMES]), t)
);
constraint forall(d in 1..N_DECOYS)(
  station_dwell(array1d(STATION_TIMES, [decoy_station_wait_time[d, i] | i in STATION_TIMES]),
                array1d(STATION_TIMES, [decoy_pos[d, i] | i in STATION_TIMES]), -d)
);

% ==== ALL STATIONS MUST BE VISITED ====
% Trains must visit their stations before reaching the target; decoys at
% some point within the horizon.  Visits are monotone, so one lookup suffices.
constraint forall(st in 1..N_STATIONS)(
  let { int: v = STATIONS[st].3; } in
  if v > 0 then station_visited_by_time[st, arrival_time[v] - 1]
  else station_visited_by_time[st, MAX_TIME] endif
);
