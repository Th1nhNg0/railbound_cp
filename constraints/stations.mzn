% ============================================================
% STATION CONSTRAINTS
% ============================================================

% --- Station Decision Variables ---
% Tracks the remaining wait time for each train at each timestep.
% 0 means no waiting, positive values mean the train must wait for that many more timesteps.
array[1..N_TRAINS, 0..MAX_TIME] of var 0..2: station_wait_time;

% Tracks whether each station has been visited by its assigned train at or before each timestep.
% Once true at timestep t, it remains true for all subsequent timesteps.
array[1..max(1, N_STATIONS), 0..MAX_TIME] of var bool: station_visited_by_time;

% --- Station Assignment Mapping ---
% For efficiency, pre-calculate all stations assigned to each train.
% Returns an array of all station indices for each train, padded with zeros.
int: MAX_STATIONS_PER_TRAIN = if N_STATIONS = 0 then 1 else N_STATIONS endif;
array[1..N_TRAINS, 1..MAX_STATIONS_PER_TRAIN] of int: train_station_indices = array2d(1..N_TRAINS, 1..MAX_STATIONS_PER_TRAIN, [
  if N_STATIONS = 0 then 0
  else
    let { 
      % Find all stations that match this train ID
      array[int] of int: matching_stations = [st | st in 1..N_STATIONS where STATIONS[st].3 = t];
      int: num_matches = length(matching_stations);
    } in
    if s <= num_matches then matching_stations[s] else 0 endif
  endif
| t in 1..N_TRAINS, s in 1..MAX_STATIONS_PER_TRAIN]);

% Count how many stations each train has
array[1..N_TRAINS] of int: train_station_count = [
  if N_STATIONS = 0 then 0
  else length([st | st in 1..N_STATIONS where STATIONS[st].3 = t])
  endif
| t in 1..N_TRAINS];

% --- Station Visitation Tracking ---
% Track whether each station has been visited by its assigned train by each timestep.
constraint forall(st in 1..max(1, N_STATIONS), time in 0..MAX_TIME) (
  if N_STATIONS = 0 then
    station_visited_by_time[st, time] = false
  else
    let {
      int: train_id = STATIONS[st].3;
      int: station_r = STATIONS[st].1;
      int: station_c = STATIONS[st].2;
      var bool: train_at_station_now = (train_row[train_id, time] = station_r /\ train_col[train_id, time] = station_c);
      var bool: was_visited_before = if time = 0 then false else station_visited_by_time[st, time-1] endif;
    } in
    station_visited_by_time[st, time] = (train_at_station_now \/ was_visited_before)
  endif
);

% --- Station Wait Time Constraints ---
% Manage the waiting behavior at stations.
constraint forall(t in 1..N_TRAINS, time in 0..MAX_TIME) (
  let {
    int: num_stations = train_station_count[t];
    % Check if train is at any of its assigned stations
    var bool: at_any_station = if num_stations = 0 then false
      else exists(s in 1..num_stations where train_station_indices[t, s] > 0)(
        let {
          int: st_idx = train_station_indices[t, s];
          int: station_r = STATIONS[st_idx].1;
          int: station_c = STATIONS[st_idx].2;
        } in
        train_row[t, time] = station_r /\ train_col[t, time] = station_c
      ) endif;
    % Check if train is at a station for the first time
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
    % Train has no assigned stations, so no waiting
    station_wait_time[t, time] = 0
  else
    % Train has assigned stations
    if time = 0 then
      % At timestep 0, initialize wait time
      if at_any_station then
        station_wait_time[t, time] = 2
      else
        station_wait_time[t, time] = 0
      endif
    else
      % For subsequent timesteps
      if is_first_visit_any then
        % First time at any station: start waiting for 2 timesteps
        station_wait_time[t, time] = 2
      elseif at_any_station /\ station_wait_time[t, time-1] > 0 then
        % Still at station and was waiting: decrement wait time (but minimum 0)
        station_wait_time[t, time] = max(0, station_wait_time[t, time-1] - 1)
      else
        % Not at station or already visited: no waiting
        station_wait_time[t, time] = 0
      endif
    endif
  endif
);

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
    int: train_id = STATIONS[st].3;
  } in
  exists(time in 0..MAX_TIME)(
    time < arrival_time[train_id] /\
    station_visited_by_time[st, time]
  )
);

