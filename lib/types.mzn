% ============================================================
% Types and Enumerations
% ------------------------------------------------------------
% Shared type definitions and enums used across the Railbound
% model. Include this file before declaring any data that uses
% these types.
% ============================================================

% Direction indices for grid navigation
enum Dir = { TOP, RIGHT, DOWN, LEFT };

% Track piece catalogue
% Visual guide:
%   STRAIGHT_TD : │ (TOP<->DOWN)
%   STRAIGHT_RL : ─ (RIGHT<->LEFT)
%   CORNER_*    : └┘┌┐ (two-way corners)
%   SWITCH_*    : 3-way switches with deterministic routing
%   DSWITCH_*   : Dynamic switches that toggle routing
%   TUNNEL_*    : Teleport entries paired with another tunnel
enum Piece = {
  EMPTY,

  % Straights
  STRAIGHT_TD,
  STRAIGHT_RL,

  % Corners
  CORNER_TR,
  CORNER_TL,
  CORNER_DR,
  CORNER_DL,

  % Switches: SWITCH_<Single>_<Straight>_<Curve>
  SWITCH_T_D_R,
  SWITCH_T_D_L,
  SWITCH_D_T_R,
  SWITCH_D_T_L,
  SWITCH_R_L_T,
  SWITCH_R_L_D,
  SWITCH_L_R_T,
  SWITCH_L_R_D,

  % Dynamic switches
  DSWITCH_T_D_R,
  DSWITCH_T_D_L,
  DSWITCH_D_T_R,
  DSWITCH_D_T_L,
  DSWITCH_R_L_T,
  DSWITCH_R_L_D,
  DSWITCH_L_R_T,
  DSWITCH_L_R_D,

  % Tunnel entries
  TUNNEL_T,
  TUNNEL_R,
  TUNNEL_D,
  TUNNEL_L
};

% Aliases for structured inputs
% (row, col, piece)
type Pos = tuple(int, int, Piece);
% (row, col, initial_exit_direction)
type TrainStart = tuple(int, int, Dir);
% Tunnel pair: endpoint A -> endpoint B with exit directions
type TunnelPair = tuple(int, int, Dir, int, int, Dir);
% Gate metadata: location, id, initial state
type Gate = tuple(int, int, int, bool);
% Activation cell location -> linked id
type Activation = tuple(int, int, int);
% Dynamic switch metadata
type DSwitch = tuple(int, int, int);
% Station metadata: location and train assignment
type Station = tuple(int, int, int);

% Categorisations of pieces used for constraint grouping
set of Piece: STRAIGHTS = { STRAIGHT_TD, STRAIGHT_RL };
set of Piece: CORNERS   = { CORNER_TR, CORNER_TL, CORNER_DR, CORNER_DL };
set of Piece: SWITCHES  = {
  SWITCH_T_D_R, SWITCH_T_D_L, SWITCH_D_T_R, SWITCH_D_T_L,
  SWITCH_R_L_T, SWITCH_R_L_D, SWITCH_L_R_T, SWITCH_L_R_D
};
set of Piece: DSWITCHES_SET = {
  DSWITCH_T_D_R, DSWITCH_T_D_L, DSWITCH_D_T_R, DSWITCH_D_T_L,
  DSWITCH_R_L_T, DSWITCH_R_L_D, DSWITCH_L_R_T, DSWITCH_L_R_D
};
set of Piece: TUNNELS = { TUNNEL_T, TUNNEL_R, TUNNEL_D, TUNNEL_L };
