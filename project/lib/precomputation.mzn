% ============================================================
% Pre-computation and Domain Reduction
%
% This module contains pre-computation logic to reduce the
% search space of the model. It calculates the set of
% valid pieces for each cell based on its position and
% proximity to pre-placed pieces.
% ============================================================

% ============================================================
% 1. VALID PIECES BASED ON BOUNDARY CONDITIONS
% ============================================================

% Sets of pieces that have a connection point in a given direction.
set of Piece: PIECES_REQUIRING_TOP = {
  STRAIGHT_TD, CORNER_TR, CORNER_TL,
  SWITCH_T_D_R, SWITCH_T_D_L, SWITCH_D_T_R, SWITCH_D_T_L, SWITCH_R_L_T, SWITCH_L_R_T,
  DSWITCH_T_D_R, DSWITCH_T_D_L, DSWITCH_D_T_R, DSWITCH_D_T_L, DSWITCH_R_L_T, DSWITCH_L_R_T,
  TUNNEL_T
};
set of Piece: PIECES_REQUIRING_RIGHT = {
  STRAIGHT_RL, CORNER_TR, CORNER_DR,
  SWITCH_T_D_R, SWITCH_D_T_R, SWITCH_R_L_T, SWITCH_R_L_D, SWITCH_L_R_T, SWITCH_L_R_D,
  DSWITCH_T_D_R, DSWITCH_D_T_R, DSWITCH_R_L_T, DSWITCH_R_L_D, DSWITCH_L_R_T, DSWITCH_L_R_D,
  TUNNEL_R
};
set of Piece: PIECES_REQUIRING_DOWN = {
  STRAIGHT_TD, CORNER_DR, CORNER_DL,
  SWITCH_T_D_R, SWITCH_T_D_L, SWITCH_D_T_R, SWITCH_D_T_L, SWITCH_R_L_D, SWITCH_L_R_D,
  DSWITCH_T_D_R, DSWITCH_T_D_L, DSWITCH_D_T_R, DSWITCH_D_T_L, DSWITCH_R_L_D, DSWITCH_L_R_D,
  TUNNEL_D
};
set of Piece: PIECES_REQUIRING_LEFT = {
  STRAIGHT_RL, CORNER_TL, CORNER_DL,
  SWITCH_T_D_L, SWITCH_D_T_L, SWITCH_R_L_T, SWITCH_R_L_D, SWITCH_L_R_T, SWITCH_L_R_D,
  DSWITCH_T_D_L, DSWITCH_D_T_L, DSWITCH_R_L_T, DSWITCH_R_L_D, DSWITCH_L_R_T, DSWITCH_L_R_D,
  TUNNEL_L
};

% The full set of all possible pieces.
set of Piece: ALL_PIECES = {p | p in Piece};

% Create a grid that holds only the pre-placed pieces for easy lookup.
array[1..H, 1..W] of Piece: init_grid = array2d(1..H, 1..W, [
  let {
    % Find the index of the pre-placed piece at (r,c), if it exists.
    array[1..N_INIT_POS] of int: match_indices = [
      if N_INIT_POS > 0 /\ INIT_POS[i].1 = r /\ INIT_POS[i].2 = c then i else 0 endif | i in 1..N_INIT_POS
    ];
    int: idx = max(match_indices);
  } in (if idx > 0 then INIT_POS[idx].3 else EMPTY endif)
  | r in 1..H, c in 1..W
]);

% ============================================================
% 2. FINAL COMBINED VALID PIECES
% ============================================================

% For each cell, calculate the final set of valid pieces.
array[1..H, 1..W] of set of Piece: valid_pieces =
  array2d(1..H, 1..W, [
    % If a piece is pre-placed, that is the only valid piece for this cell.
    if init_grid[r,c] != EMPTY then {init_grid[r,c]}
    else
      % Otherwise, calculate the domain by intersecting boundary and neighbor constraints.
      let {
        % Boundary constraints
        set of Piece: boundary_set =
          let {
            set of Piece: disallowed =
              (if r = 1 then PIECES_REQUIRING_TOP else {} endif) union
              (if r = H then PIECES_REQUIRING_DOWN else {} endif) union
              (if c = 1 then PIECES_REQUIRING_LEFT else {} endif) union
              (if c = W then PIECES_REQUIRING_RIGHT else {} endif);
          } in (ALL_PIECES diff disallowed);

        % Neighbor constraints
        set of Piece: neighbor_set =
          let {
            set of Piece: from_top =
              if r = 1 then ALL_PIECES
              else let { Piece: p = init_grid[r-1, c]; } in
                if p = EMPTY then ALL_PIECES
                elseif can_enter[p, DOWN] then PIECES_REQUIRING_TOP
                else ALL_PIECES diff PIECES_REQUIRING_TOP endif
              endif;
            set of Piece: from_bottom =
              if r = H then ALL_PIECES
              else let { Piece: p = init_grid[r+1, c]; } in
                if p = EMPTY then ALL_PIECES
                elseif can_enter[p, TOP] then PIECES_REQUIRING_DOWN
                else ALL_PIECES diff PIECES_REQUIRING_DOWN endif
              endif;
            set of Piece: from_left =
              if c = 1 then ALL_PIECES
              else let { Piece: p = init_grid[r, c-1]; } in
                if p = EMPTY then ALL_PIECES
                elseif can_enter[p, RIGHT] then PIECES_REQUIRING_LEFT
                else ALL_PIECES diff PIECES_REQUIRING_LEFT endif
              endif;
            set of Piece: from_right =
              if c = W then ALL_PIECES
              else let { Piece: p = init_grid[r, c+1]; } in
                if p = EMPTY then ALL_PIECES
                elseif can_enter[p, LEFT] then PIECES_REQUIRING_RIGHT
                else ALL_PIECES diff PIECES_REQUIRING_RIGHT endif
              endif;
          } in (from_top intersect from_bottom intersect from_left intersect from_right);
      } in (boundary_set intersect neighbor_set)
    endif
    | r in 1..H, c in 1..W
  ]);