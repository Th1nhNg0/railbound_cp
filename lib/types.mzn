% ============================================================
% lib/types.mzn - Type Definitions for Railbound Solver
% ============================================================
% Defines all enumerations and piece types representing the game elements:
% tracks (straights, corners), switches (deterministic, dynamic, exit-triggered),
% tunnels, and obstacles. Also defines helper sets for grouping piece types.
% ============================================================

% ==== DIRECTIONS ====
% Cardinal directions for movement and rotations.
enum Dir = { TOP, RIGHT, DOWN, LEFT };

% ==== PIECE TYPES ====
% All possible track and structural pieces in the puzzle grid.
enum Piece = {
  EMPTY,

  % Straights: Connect two opposite directions
  STRAIGHT_TD,  % Connects Top and Down (vertical).
  STRAIGHT_RL,  % Connects Right and Left (horizontal).

  % Corners: Connect two perpendicular directions
  CORNER_TR,    % Connects Top and Right.
  CORNER_TL,    % Connects Top and Left.
  CORNER_DR,    % Connects Down and Right.
  CORNER_DL,    % Connects Down and Left.

  % Deterministic Switches: Fixed route choice based on input direction
  % Naming: SWITCH_<entry>_<straight_exit>_<curved_exit>
  SWITCH_T_D_R, % Enters from Top; straight=Down, curved=Right.
  SWITCH_T_D_L, % Enters from Top; straight=Down, curved=Left.
  SWITCH_D_T_R, % Enters from Down; straight=Top, curved=Right.
  SWITCH_D_T_L, % Enters from Down; straight=Top, curved=Left.
  SWITCH_R_L_T, % Enters from Right; straight=Left, curved=Top.
  SWITCH_R_L_D, % Enters from Right; straight=Left, curved=Down.
  SWITCH_L_R_T, % Enters from Left; straight=Right, curved=Top.
  SWITCH_L_R_D, % Enters from Left; straight=Right, curved=Down.

  % Dynamic Switches: Stateful - toggle exit path each train pass through
  DSWITCH_T_D_R, DSWITCH_T_D_L, DSWITCH_D_T_R, DSWITCH_D_T_L,
  DSWITCH_R_L_T, DSWITCH_R_L_D, DSWITCH_L_R_T, DSWITCH_L_R_D,

  % Exit-triggered Switches: Stateful - toggle when any train exits the piece
  ESWITCH_T_D_R, ESWITCH_T_D_L, ESWITCH_D_T_R, ESWITCH_D_T_L,
  ESWITCH_R_L_T, ESWITCH_R_L_D, ESWITCH_L_R_T, ESWITCH_L_R_D,

  % Tunnels: Directional entry/exit points for instant teleportation
  TUNNEL_T,     % Tunnel allowing entry from Top.
  TUNNEL_R,     % Tunnel allowing entry from Right.
  TUNNEL_D,     % Tunnel allowing entry from Down.
  TUNNEL_L,     % Tunnel allowing entry from Left.
  
  ROCK          % Impassable obstacle (cannot place or cross).
};

% ==== HELPER SETS (for categorizing pieces) ====
set of Piece: STRAIGHTS_SET = { STRAIGHT_TD, STRAIGHT_RL };
set of Piece: CORNERS_SET = { CORNER_TR, CORNER_TL, CORNER_DR, CORNER_DL };
set of Piece: SWITCHES_SET = {
  SWITCH_T_D_R, SWITCH_T_D_L, SWITCH_D_T_R, SWITCH_D_T_L,
  SWITCH_R_L_T, SWITCH_R_L_D, SWITCH_L_R_T, SWITCH_L_R_D
};
set of Piece: DSWITCHES_SET = {
  DSWITCH_T_D_R, DSWITCH_T_D_L, DSWITCH_D_T_R, DSWITCH_D_T_L,
  DSWITCH_R_L_T, DSWITCH_R_L_D, DSWITCH_L_R_T, DSWITCH_L_R_D
};
set of Piece: ESWITCHES_SET = {
  ESWITCH_T_D_R, ESWITCH_T_D_L, ESWITCH_D_T_R, ESWITCH_D_T_L,
  ESWITCH_R_L_T, ESWITCH_R_L_D, ESWITCH_L_R_T, ESWITCH_L_R_D
};
set of Piece: TUNNELS_SET = { TUNNEL_T, TUNNEL_R, TUNNEL_D, TUNNEL_L };

% Pieces that cannot be placed dynamically (must be pre-placed in INIT_POS).
set of Piece: UNPLACEABLE_PIECES = DSWITCHES_SET union ESWITCHES_SET union TUNNELS_SET union { ROCK };

% ==== TYPE ALIASES ====
type Pos = tuple(int, int, Piece); % Position tuple: (row, col, piece_type).