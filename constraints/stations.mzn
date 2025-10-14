% ============================================================ 
% STATION CONSTRAINTS
% ============================================================ 

% --- Station Decision Variables ---
% Tracks the remaining wait time for each train at each timestep.
% 0 means no waiting, positive values mean the train must wait for that many more timesteps.
array[1..N_TRAINS, 0..MAX_TIME] of var 0..2: station_wait_time;
array[1..max(1, N_DECOYS), 0..MAX_TIME] of var 0..2: decoy_station_wait_time;

% Tracks whether each station has been visited by its assigned vehicle at or before each timestep.
% Once true at timestep t, it remains true for all subsequent timesteps.
array[1..max(1, N_STATIONS), 0..MAX_TIME] of var bool: station_visited_by_time;

% --- Station Assignment Mapping ---
% For efficiency, pre-calculate all stations assigned to each vehicle.
int: MAX_STATIONS_PER_VEHICLE = if N_STATIONS = 0 then 1 else N_STATIONS endif;

% For Trains
array[1..N_TRAINS, 1..MAX_STATIONS_PER_VEHICLE] of int: train_station_indices = array2d(1..N_TRAINS, 1..MAX_STATIONS_PER_VEHICLE, [
  if N_STATIONS = 0 then 0
  else
    let { 
      array[int] of int: matching_stations = [st | st in 1..N_STATIONS where STATIONS[st].3 = t];
      int: num_matches = length(matching_stations);
    } in
    if s <= num_matches then matching_stations[s] else 0 endif
  endif
| t in 1..N_TRAINS, s in 1..MAX_STATIONS_PER_VEHICLE]);

array[1..N_TRAINS] of int: train_station_count = [
  if N_STATIONS = 0 then 0
  else length([st | st in 1..N_STATIONS where STATIONS[st].3 = t])
  endif
| t in 1..N_TRAINS];

% For Decoys
array[1..max(1, N_DECOYS), 1..MAX_STATIONS_PER_VEHICLE] of int: decoy_station_indices = array2d(1..max(1, N_DECOYS), 1..MAX_STATIONS_PER_VEHICLE, [
  if N_STATIONS = 0 then 0
  else
    let { 
      array[int] of int: matching_stations = [st | st in 1..N_STATIONS where STATIONS[st].3 = -d];
      int: num_matches = length(matching_stations);
    } in
    if s <= num_matches then matching_stations[s] else 0 endif
  endif
| d in 1..max(1, N_DECOYS), s in 1..MAX_STATIONS_PER_VEHICLE]);

array[1..max(1, N_DECOYS)] of int: decoy_station_count = [
  if N_STATIONS = 0 then 0
  else length([st | st in 1..N_STATIONS where STATIONS[st].3 = -d])
  endif
| d in 1..max(1, N_DECOYS)];

% --- Station Visitation Tracking ---
% Track whether each station has been visited by its assigned vehicle by each timestep.
constraint if N_STATIONS > 0 then
  forall(st in 1..N_STATIONS)(
    let {
      int: vehicle_id = STATIONS[st].3;
      int: station_r = STATIONS[st].1;
      int: station_c = STATIONS[st].2;
    } in
    forall(time in 0..MAX_TIME)(
      let {
        var bool: vehicle_at_station_now = 
            if vehicle_id > 0 then
                let { int: train_id = vehicle_id; } in
                train_row[train_id, time] = station_r /\ train_col[train_id, time] = station_c
            elseif vehicle_id < 0 then
                let { int: decoy_id = -vehicle_id; } in
                decoy_row[decoy_id, time] = station_r /\ decoy_col[decoy_id, time] = station_c
            else false endif;
        var bool: was_visited_before = if time = 0 then false else station_visited_by_time[st, time-1] endif;
      } in
      station_visited_by_time[st, time] = (vehicle_at_station_now \/ was_visited_before)
    )
  )
else
  forall(time in 0..MAX_TIME)(station_visited_by_time[1, time] = false)
endif;

% --- Station Wait Time Constraints ---
% Manage the waiting behavior at stations for trains.
constraint forall(t in 1..N_TRAINS, time in 0..MAX_TIME) (
  let {
    int: num_stations = train_station_count[t];
    var bool: at_any_station = if num_stations = 0 then false
      else exists(s in 1..num_stations where train_station_indices[t, s] > 0)(
        let {
          int: st_idx = train_station_indices[t, s];
          int: station_r = STATIONS[st_idx].1;
          int: station_c = STATIONS[st_idx].2;
        } in
        train_row[t, time] = station_r /\ train_col[t, time] = station_c
      ) endif;
    var bool: is_first_visit_any = if num_stations = 0 then false
      else exists(s in 1..num_stations where train_station_indices[t, s] > 0)(
        let {
          int: st_idx = train_station_indices[t, s];
          int: station_r = STATIONS[st_idx].1;
          int: station_c = STATIONS[st_idx].2;
          var bool: at_this_station = (train_row[t, time] = station_r /\ train_col[t, time] = station_c);
          var bool: was_visited_before = if time = 0 then false else station_visited_by_time[st_idx, time-1] endif;
        } in
        at_this_station /\ not was_visited_before
      ) endif;
  } in
  if num_stations = 0 then
    station_wait_time[t, time] = 0
  else
    if time = 0 then
      if at_any_station then
        station_wait_time[t, time] = 2
      else
        station_wait_time[t, time] = 0
      endif
    else
      if is_first_visit_any then
        station_wait_time[t, time] = 2
      elseif at_any_station /\ station_wait_time[t, time-1] > 0 then
        station_wait_time[t, time] = max(0, station_wait_time[t, time-1] - 1)
      else
        station_wait_time[t, time] = 0
      endif
    endif
  endif
);

% Manage the waiting behavior at stations for decoys.
constraint if N_DECOYS > 0 then forall(d in 1..N_DECOYS, time in 0..MAX_TIME) (
  let {
    int: num_stations = decoy_station_count[d];
    var bool: at_any_station = if num_stations = 0 then false
      else exists(s in 1..num_stations where decoy_station_indices[d, s] > 0)(
        let {
          int: st_idx = decoy_station_indices[d, s];
          int: station_r = STATIONS[st_idx].1;
          int: station_c = STATIONS[st_idx].2;
        } in
        decoy_row[d, time] = station_r /\ decoy_col[d, time] = station_c
      ) endif;
    var bool: is_first_visit_any = if num_stations = 0 then false
      else exists(s in 1..num_stations where decoy_station_indices[d, s] > 0)(
        let {
          int: st_idx = decoy_station_indices[d, s];
          int: station_r = STATIONS[st_idx].1;
          int: station_c = STATIONS[st_idx].2;
          var bool: at_this_station = (decoy_row[d, time] = station_r /\ decoy_col[d, time] = station_c);
          var bool: was_visited_before = if time = 0 then false else station_visited_by_time[st_idx, time-1] endif;
        } in
        at_this_station /\ not was_visited_before
      ) endif;
  } in
  if num_stations = 0 then
    decoy_station_wait_time[d, time] = 0
  else
    if time = 0 then
      if at_any_station then
        decoy_station_wait_time[d, time] = 2
      else
        decoy_station_wait_time[d, time] = 0
      endif
    else
      if is_first_visit_any then
        decoy_station_wait_time[d, time] = 2
      elseif at_any_station /\ decoy_station_wait_time[d, time-1] > 0 then
        decoy_station_wait_time[d, time] = max(0, decoy_station_wait_time[d, time-1] - 1)
      else
        decoy_station_wait_time[d, time] = 0
      endif
    endif
  endif
) endif;

% --- Station Arrival Precedence Constraint ---
% Trains must visit ALL of their assigned stations before reaching the target.
constraint forall(t in 1..N_TRAINS where train_station_count[t] > 0) (
  forall(s in 1..train_station_count[t] where train_station_indices[t, s] > 0)(
    let {
      int: st_idx = train_station_indices[t, s];
      int: station_r = STATIONS[st_idx].1;
      int: station_c = STATIONS[st_idx].2;
    } in
    exists(time in 0..MAX_TIME)(
      time < arrival_time[t] /\ 
      train_row[t, time] = station_r /\ train_col[t, time] = station_c
    )
  )
);

% --- All Stations Must Be Visited ---
% Ensure every station is visited by its assigned train before they reach the target.
constraint forall(st in 1..N_STATIONS)(
  let {
    int: vehicle_id = STATIONS[st].3;
  } in
  if vehicle_id > 0 then
    let { int: train_id = vehicle_id; } in
    exists(time in 0..MAX_TIME)(
      time < arrival_time[train_id] /\ 
      station_visited_by_time[st, time]
    )
  else
    true % No arrival time for decoys, so no constraint
  endif
);