%============================================================================
% DECOY CONSTRAINTS
%============================================================================
% This file defines the movement and behavior constraints for decoy trains
% in the Railbound puzzle solving system. Decoys are AI-controlled trains
% that follow predetermined paths and can interact with game elements.
%============================================================================

% --- DECOY INITIALIZATION CONSTRAINT ---
% Sets up the initial position and first movement for each decoy train.
% Each decoy starts at a specified position with a given initial direction.
constraint forall(d in 1..N_DECOYS) (
  let {
    int: r0 = DECOYS[d].1;                    % Initial row position
    int: c0 = DECOYS[d].2;                    % Initial column position
    Dir: dir0 = DECOYS[d].3;                  % Initial movement direction
    int: intended_r = r0 + dr[dir0];          % Target row for first move
    int: intended_c = c0 + dc[dir0];          % Target column for first move
    Dir: intended_entry_dir = opposite[dir0]; % Direction decoy will face when entering target cell
    % Check if a gate blocks the intended first move
    var bool: blocked_by_gate =
      if N_GATES >0 /\ cell_has_gate[intended_r, intended_c] then
        not gate_open[gate_index_at[intended_r, intended_c], 1]
      else false endif;
  } in
  % Set initial position at time 0
  decoy_row[d, 0] = r0 /\
  decoy_col[d, 0] = c0 /\
  % Ensure the intended target cell can be entered from the decoy's direction
  can_enter[grid[intended_r, intended_c], intended_entry_dir] /\
  % Handle first move: if blocked by gate, stay in place; otherwise move to intended cell
  if blocked_by_gate then
    decoy_row[d, 1] = r0 /\
    decoy_col[d, 1] = c0 /\
    decoy_dir[d, 1] = intended_entry_dir
  else
    decoy_row[d, 1] = intended_r /\
    decoy_col[d, 1] = intended_c /\
    decoy_dir[d, 1] = intended_entry_dir
  endif
);


% --- DECOY MOVEMENT CONSTRAINT ---
% Defines how decoys move through the grid at each time step.
% Handles various game mechanics including tunnels, switches, gates, and stations.
constraint forall(d in 1..N_DECOYS, time in 1..MAX_TIME-1) (
    let {
        var 1..H: r = decoy_row[d, time];                     % Current row position
        var 1..W: c = decoy_col[d, time];                     % Current column position
        var Dir: entry_dir = decoy_dir[d, time];              % Direction decoy entered current cell
        var Piece: piece = grid[r, c];                        % Type of piece at current position
        var Dir: exit_dir;                                    % Direction decoy will exit current cell
        var 1..H: next_r = decoy_row[d, time+1];             % Next row position
        var 1..W: next_c = decoy_col[d, time+1];             % Next column position
        var Dir: next_entry_dir = decoy_dir[d, time+1];       % Direction decoy will face in next cell
        var 0..H+1: intended_r;                              % Intended target row (may be out of bounds)
        var 0..W+1: intended_c;                              % Intended target column (may be out of bounds)
        var Dir: intended_entry_dir;                         % Direction decoy would face in intended target
        % Check if a gate blocks movement to the intended destination
        var bool: blocked_by_gate = if N_GATES >0 /\ cell_has_gate[intended_r, intended_c] then
                not gate_open[gate_index_at[intended_r, intended_c], time+1]
            else false endif;
        % Determine the effective piece type, accounting for switch states
        var Piece: effective_piece = 
            if N_DSWITCHES > 0 /\ cell_has_dswitch[r, c] then dswitch_effective_piece(piece, dswitch_toggled[dswitch_index_at[r, c], time]) 
            elseif N_ESWITCHES > 0 /\ cell_has_eswitch[r, c] then eswitch_effective_piece(piece, eswitch_toggled[eswitch_index_at[r, c], time])
            else piece endif;
    } in

    % Movement logic: decoys stay stationary if waiting at station or on empty cell
    if piece = EMPTY then
        (next_r, next_c, next_entry_dir) = (r, c, entry_dir)
    else
        % Handle special case: tunnel teleportation
        (if piece in TUNNELS_SET then
                 let {
                         var tuple(1..H, 1..W): dest = tunnel_dest[r, c];        % Tunnel exit coordinates
                         var Dir: dest_exit_dir_enum = to_enum(Dir, tunnel_exit_dir[r, c]);
                         var 1..H: dest_r = dest.1;                            % Tunnel exit row
                         var 1..W: dest_c = dest.2;                            % Tunnel exit column
                 } in
                 % Set intended position as one step beyond tunnel exit
                 intended_r = dest_r + dr[dest_exit_dir_enum] /\
                 intended_c = dest_c + dc[dest_exit_dir_enum] /\
                 intended_entry_dir = opposite[dest_exit_dir_enum]
         else
                 % Normal movement: follow track piece geometry
                 exit_dir = exit_of[effective_piece, entry_dir] /\
                 intended_r = r + dr[exit_dir] /\
                 intended_c = c + dc[exit_dir] /\
                 intended_entry_dir = opposite[exit_dir]
         endif) /\
        % Check if movement to intended position is valid
        if (intended_c >= 1 /\ intended_c <= W /\ intended_r >= 1 /\ intended_r <= H /\
            can_enter[grid[intended_r, intended_c], intended_entry_dir] /\ 
            grid[intended_r,intended_c] !=EMPTY /\ 
            not blocked_by_gate
        ) then
                % Valid move: proceed to intended position
                (next_r, next_c, next_entry_dir) = (intended_r, intended_c, intended_entry_dir)
        else
                % Invalid move: stay in current position
                (next_r, next_c, next_entry_dir) = (r, c, entry_dir)
        endif
    endif
);


% --- COLLISION AVOIDANCE CONSTRAINTS ---

% DECOY-DECOY COLLISION PREVENTION
% Ensures no two decoys occupy the same cell at the same time
constraint forall(t1 in 1..N_DECOYS, t2 in t1 + 1..N_DECOYS, i in 1..MAX_TIME)(
    (decoy_row[t1, i] != decoy_row[t2, i] \/ decoy_col[t1, i] != decoy_col[t2, i])
);

% DECOY-TRAIN COLLISION PREVENTION  
% Ensures decoys don't collide with player trains while trains are active
constraint forall(d in 1..N_DECOYS, t in 1..N_TRAINS, i in 1..MAX_TIME where i<=arrival_time[t])(
    (decoy_row[d, i] != train_row[t, i] \/ decoy_col[d, i] != train_col[t, i])
);

% TARGET PROTECTION
% Prevents decoys from occupying the target destination cell
constraint forall(d in 1..N_DECOYS, i in 1..MAX_TIME)(
    decoy_row[d, i] != TARGET.1 \/ decoy_col[d, i] != TARGET.2
);


% --- POSITION SWAP PREVENTION CONSTRAINTS ---
% Prevents entities from swapping positions in consecutive time steps.
% This is crucial for realistic movement physics and avoiding impossible scenarios
% where entities pass through each other (including through tunnel teleportation).

% DECOY-DECOY POSITION SWAP PREVENTION
% Ensures two decoys cannot exchange positions between consecutive time steps
constraint forall(d1 in 1..N_DECOYS, d2 in d1 + 1..N_DECOYS, i in 1..MAX_TIME-1)(
    let {
        % Get effective positions (accounting for tunnel exits)
        var tuple(1..H, 1..W): eff_pos1 = get_effective_pos(decoy_row[d1, i], decoy_col[d1, i]),
        var tuple(1..H, 1..W): eff_pos2 = get_effective_pos(decoy_row[d2, i], decoy_col[d2, i])
    } in
    % Prevent position swapping: if decoy1 is at position A and decoy2 at position B,
    % then decoy1 cannot move to B while decoy2 moves to A
    eff_pos1 != (decoy_row[d2, i+1], decoy_col[d2, i+1]) \/
    eff_pos2 != (decoy_row[d1, i+1], decoy_col[d1, i+1])
);

% DECOY-TRAIN POSITION SWAP PREVENTION
% Ensures decoys and player trains cannot exchange positions between consecutive time steps
constraint forall(d1 in 1..N_DECOYS, d2 in 1..N_TRAINS, i in 1..MAX_TIME-1 where i <= arrival_time[d2])(
    let {
        % Get effective positions (accounting for tunnel exits)
        var tuple(1..H, 1..W): eff_pos1 = get_effective_pos(decoy_row[d1, i], decoy_col[d1, i]),
        var tuple(1..H, 1..W): eff_pos2 = get_effective_pos(train_row[d2, i], train_col[d2, i])
    } in
    % Prevent position swapping between decoys and trains
    eff_pos1 != (train_row[d2, i+1], train_col[d2, i+1]) \/
    eff_pos2 != (decoy_row[d1, i+1], decoy_col[d1, i+1])
);
