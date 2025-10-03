% ============================================================
% STATION CONSTRAINTS
%
% Defines the logic for stations, which require specific trains
% to visit them and wait for a set duration before proceeding.
% ============================================================

% 25) Station validation: stations must be on non-EMPTY track pieces
constraint forall(st in STATIONS) (
  grid[st.1, st.2] != EMPTY
);

% 26) Station validation: stations only on STRAIGHT, CORNER, or SWITCH tracks
constraint forall(st in STATIONS) (
  grid[st.1, st.2] in (STRAIGHTS union CORNERS union SWITCHES)
);

% 27) Station ID validation: each station's train_id must be valid
constraint forall(st in STATIONS) (
  st.3 >= 1 /\ st.3 <= N_TRAINS
);

% 28) No coexistence: stations cannot share cells with gates, activations, or dswitches
constraint forall(st in STATIONS, g in GATES) (
  not (st.1 = g.1 /\ st.2 = g.2)
);
constraint forall(st in STATIONS, a in ACTIVATIONS) (
  not (st.1 = a.1 /\ st.2 = a.2)
);
constraint forall(st in STATIONS, ds in DSWITCHES) (
  not (st.1 = ds.1 /\ st.2 = ds.2)
);

% 29) Station visit requirement: each train must visit all its assigned stations before reaching the target.
constraint forall(st in 1..N_STATIONS) (
  let {
    int: train_id = STATIONS[st].3;
    int: station_r = STATIONS[st].1;
    int: station_c = STATIONS[st].2;
  } in
    % The station must be visited by the correct train before that train arrives at the target.
    station_visited[train_id, st] = exists(time in 0..MAX_TIME) (
      train_row[train_id, time] = station_r /\
      train_col[train_id, time] = station_c /\
      time < arrival_time[train_id]
    )
);

% 29b) Enforce station visit requirement: all required visits must happen.
constraint forall(st in 1..N_STATIONS) (
  station_visited[STATIONS[st].3, st]
);

% 30) Station wait mechanics: wait 2 steps the first time a train reaches each assigned station
constraint forall(t in 1..N_TRAINS, time in 0..MAX_TIME) (
  if N_STATIONS = 0 then
    station_wait_time[t, time] = 0
  else
    let {
      set of int: matching_stations = {st | st in 1..N_STATIONS where STATIONS[st].3 = t};
    } in
    if card(matching_stations) = 0 then
      station_wait_time[t, time] = 0
    else
      let {
        var bool: entering_first_station =
          exists(st in matching_stations)(
            let {
              int: station_r = STATIONS[st].1;
              int: station_c = STATIONS[st].2;
              var bool: at_station_now =
                train_row[t, time] = station_r /\ train_col[t, time] = station_c;
              var bool: was_at_station_prev =
                if time = 0 then false
                else train_row[t, time-1] = station_r /\ train_col[t, time-1] = station_c
                endif;
              var bool: visited_before =
                if time = 0 then false
                else exists(prev in 0..time-1)(
                  train_row[t, prev] = station_r /\ train_col[t, prev] = station_c
                )
                endif;
            } in
              at_station_now /\ not was_at_station_prev /\ not visited_before
          );
      } in
      if entering_first_station then
        station_wait_time[t, time] = 2
      elseif time = 0 then
        station_wait_time[t, time] = 0
      elseif station_wait_time[t, time-1] > 0 then
        station_wait_time[t, time] = station_wait_time[t, time-1] - 1
      else
        station_wait_time[t, time] = 0
      endif
    endif
  endif
);