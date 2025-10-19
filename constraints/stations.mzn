% ============================================================
% constraints/stations.mzn - Station Visitation & Dwell Time
% ============================================================
% Defines station mechanics: trains must visit assigned stations,
% incur a 2-step dwell time on first arrival, and visit all stations
% before reaching the target.
% ============================================================

% ==== STATION DECISION VARIABLES ====
% station_wait_time[t, time]: remaining wait steps (0 = no waiting, >0 = waiting).
array[1..N_TRAINS, 0..MAX_TIME] of var 0..2: station_wait_time;

% station_visited_by_time[st, time]: true if station st visited by time step.
array[1..N_STATIONS, 0..MAX_TIME] of var bool: station_visited_by_time;

% ==== STATION ASSIGNMENT MAPPING ====
% Pre-compute which stations each train must visit.
int: MAX_STATIONS_PER_VEHICLE = N_STATIONS; % Max stations per train.

% Train station indices for each train (pre-computed from STATIONS data).
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

% Count of stations assigned to each train.
array[1..N_TRAINS] of int: train_station_count = [
  if N_STATIONS = 0 then 0
  else length([st | st in 1..N_STATIONS where STATIONS[st].3 = t])
  endif
| t in 1..N_TRAINS];

% ==== STATION VISITATION TRACKING ====
% Track if each station has been visited by its assigned train by each timestep.
constraint if N_STATIONS > 0 then
  forall(st in 1..N_STATIONS)(
    let {
      1..N_TRAINS: vehicle_id = STATIONS[st].3;
      1..H: station_r = STATIONS[st].1;
      1..W: station_c = STATIONS[st].2;
    } in
    forall(time in 0..MAX_TIME)(
      let {
        var bool: vehicle_at_station_now = % Train currently at this station.
            if vehicle_id > 0 then
                let { 1..N_TRAINS: train_id = vehicle_id; } in
                train_row[train_id, time] = station_r /\ train_col[train_id, time] = station_c
            else false endif;
        var bool: was_visited_before = if time = 0 then false else station_visited_by_time[st, time-1] endif; % Visited before now.
      } in
      station_visited_by_time[st, time] = (vehicle_at_station_now \/ was_visited_before) % Visited now or before.
    )
  )
endif;

% ==== STATION WAIT TIME CONSTRAINT ====
% Trains wait 2 steps on first arrival at any assigned station.
constraint forall(t in 1..N_TRAINS, time in 0..MAX_TIME) (
  let {
    int: num_stations = train_station_count[t];
    var bool: at_any_station = if num_stations = 0 then false % No stations assigned.
      else exists(s in 1..num_stations where train_station_indices[t, s] > 0)(
        let {
          1..N_STATIONS: st_idx = train_station_indices[t, s];
          1..H: station_r = STATIONS[st_idx].1;
          1..W: station_c = STATIONS[st_idx].2;
        } in
        train_row[t, time] = station_r /\ train_col[t, time] = station_c % At any assigned station.
      ) endif;
    var bool: is_first_visit_any = if num_stations = 0 then false % No stations assigned.
      else exists(s in 1..num_stations where train_station_indices[t, s] > 0)(
        let {
          1..N_STATIONS: st_idx = train_station_indices[t, s];
          1..H: station_r = STATIONS[st_idx].1;
          1..W: station_c = STATIONS[st_idx].2;
          var bool: at_this_station = (train_row[t, time] = station_r /\ train_col[t, time] = station_c); % At station now.
          var bool: was_visited_before = if time = 0 then false else station_visited_by_time[st_idx, time-1] endif; % Visited before.
        } in
        at_this_station /\ not was_visited_before % First visit to any assigned station.
      ) endif;
  } in
  if num_stations = 0 then
    station_wait_time[t, time] = 0 % No waiting if no stations.
  else
    if time = 0 then
      if at_any_station then
        station_wait_time[t, time] = 2 % Start with 2-step wait if at station.
      else
        station_wait_time[t, time] = 0 % No wait if not at station.
      endif
    else
      if is_first_visit_any then
        station_wait_time[t, time] = 2 % Start 2-step wait on first visit.
      elseif at_any_station /\ station_wait_time[t, time-1] > 0 then
        station_wait_time[t, time] = max(0, station_wait_time[t, time-1] - 1) % Decrement wait.
      else
        station_wait_time[t, time] = 0 % No waiting.
      endif
    endif
  endif
);

% ==== STATION ARRIVAL PRECEDENCE ====
% All assigned stations must be visited before reaching target.
constraint forall(t in 1..N_TRAINS where train_station_count[t] > 0) (
  forall(s in 1..train_station_count[t] where train_station_indices[t, s] > 0)(
    let {
      1..N_STATIONS: st_idx = train_station_indices[t, s];
      1..H: station_r = STATIONS[st_idx].1;
      1..W: station_c = STATIONS[st_idx].2;
    } in
    exists(time in 0..MAX_TIME)(
      time < arrival_time[t] /\ % Before arrival at target.
      train_row[t, time] = station_r /\ train_col[t, time] = station_c % At this station.
    )
  )
);

% ==== ALL STATIONS MUST BE VISITED ====
% Ensure every station is visited by its assigned train before reaching target.
constraint forall(st in 1..N_STATIONS)(
  let {
    1..N_TRAINS: vehicle_id = STATIONS[st].3;
    1..N_TRAINS: train_id = vehicle_id;
  } in
  exists(time in 0..MAX_TIME)(
    time < arrival_time[train_id] /\ % Before arrival at target.
    station_visited_by_time[st, time] % At this station.
  )
);
