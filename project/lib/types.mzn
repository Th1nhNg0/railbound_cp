% ============================================================
% TYPE DEFINITIONS
%
% Defines all custom types, enums, and type aliases used in
% the Railbound model.
% ============================================================

% --- Directions ---
% Represents the four cardinal directions for train movement and
% piece connections.
enum Dir = { TOP, RIGHT, DOWN, LEFT };

% --- Track Piece Types ---
% Represents all possible pieces that can be placed on the grid.
% Visual guide:
%   STRAIGHT_TD : │ (connects TOP<->DOWN)
%   STRAIGHT_RL : ─ (connects RIGHT<->LEFT)
%   CORNER_*    : └┘┌┐ (two-way, 90° corners)
%   SWITCH_*    : 3-way with one 'single' end and two exits
%                 Naming: SWITCH_<SingleEnd>_<StraightEnd>_<CurveEnd>
%   DSWITCH_*   : Dynamic switches that can change configuration.
%   TUNNEL_*    : Teleport entry (paired with another tunnel).
enum Piece = {
  EMPTY,

  % Straights
  STRAIGHT_TD,  % │ connects TOP <-> DOWN
  STRAIGHT_RL,  % ─ connects RIGHT <-> LEFT

  % Corners
  CORNER_TR,    % └ connects TOP <-> RIGHT
  CORNER_TL,    % ┘ connects TOP <-> LEFT
  CORNER_DR,    % ┌ connects DOWN <-> RIGHT
  CORNER_DL,    % ┐ connects DOWN <-> LEFT

  % Switches: SWITCH_<Single>_<Straight>_<Curve>
  % Rule: Single->Straight, Straight->Curve, Curve->Straight
  SWITCH_T_D_R,  % TOP->DOWN, DOWN->RIGHT, RIGHT->DOWN
  SWITCH_T_D_L,  % TOP->DOWN, DOWN->LEFT, LEFT->DOWN
  SWITCH_D_T_R,  % DOWN->TOP, TOP->RIGHT, RIGHT->TOP
  SWITCH_D_T_L,  % DOWN->TOP, TOP->LEFT, LEFT->TOP
  SWITCH_R_L_T,  % RIGHT->LEFT, LEFT->TOP, TOP->LEFT
  SWITCH_R_L_D,  % RIGHT->LEFT, LEFT->DOWN, DOWN->LEFT
  SWITCH_L_R_T,  % LEFT->RIGHT, RIGHT->TOP, TOP->RIGHT
  SWITCH_L_R_D,  % LEFT->RIGHT, RIGHT->DOWN, DOWN->RIGHT

  % Dynamic Switches: DSWITCH_<Single>_<Straight>_<Curve>
  % Can swap Single and Straight connections when activated
  DSWITCH_T_D_R,  % TOP->DOWN, DOWN->RIGHT, RIGHT->DOWN (initial state)
  DSWITCH_T_D_L,  % TOP->DOWN, DOWN->LEFT, LEFT->DOWN
  DSWITCH_D_T_R,  % DOWN->TOP, TOP->RIGHT, RIGHT->TOP
  DSWITCH_D_T_L,  % DOWN->TOP, TOP->LEFT, LEFT->TOP
  DSWITCH_R_L_T,  % RIGHT->LEFT, LEFT->TOP, TOP->LEFT
  DSWITCH_R_L_D,  % RIGHT->LEFT, LEFT->DOWN, DOWN->LEFT
  DSWITCH_L_R_T,  % LEFT->RIGHT, RIGHT->TOP, TOP->RIGHT
  DSWITCH_L_R_D,  % LEFT->RIGHT, RIGHT->DOWN, DOWN->RIGHT

  % Tunnels: TUNNEL_X means enter from X, paired tunnel exits in X direction
  TUNNEL_T,     % Enter from TOP only
  TUNNEL_R,     % Enter from RIGHT only
  TUNNEL_D,     % Enter from DOWN only
  TUNNEL_L      % Enter from LEFT only
};

% --- Type Aliases for Clarity ---
% Provides meaningful names for complex tuple types used in data files.
type Pos = tuple(int, int, Piece);           % (row, col, piece)
type TrainStart = tuple(int, int, Dir);       % (row, col, initial_exit_dir)
type TunnelPair = tuple(int, int, Dir,        % (row_A, col_A, exit_dir_A,
                        int, int, Dir);       %  row_B, col_B, exit_dir_B)
type Gate = tuple(int, int, int, bool);      % (row, col, gate_id, initially_open)
type Activation = tuple(int, int, int);      % (row, col, gate_id)
type DSwitch = tuple(int, int, int);         % (row, col, dswitch_id)
type Station = tuple(int, int, int);         % (row, col, train_id)