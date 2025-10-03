% ============================================================
% PIECE ROUTING LOGIC
%
% This file defines the core routing behavior for all track
% pieces, including entry/exit permissions and the routing
% tables that determine a train's path through a piece.
% ============================================================

% ============================================================
% PIECE ROUTING TABLES
% ============================================================
% Define which directions can enter/exit each piece type,
% and where trains go based on entry direction.

% --- Entry Permissions ---
% can_enter[piece, dir] = true if a train can enter a cell with
% this piece from the given direction.
array[Piece, Dir] of bool: can_enter = array2d(Piece, Dir, [
  %              TOP    RIGHT  DOWN   LEFT
  % EMPTY
                 false, false, false, false,
  % STRAIGHT_TD
                 true,  false, true,  false,
  % STRAIGHT_RL
                 false, true,  false, true,
  % CORNER_TR (TOP<->RIGHT)
                 true,  true,  false, false,
  % CORNER_TL (TOP<->LEFT)
                 true,  false, false, true,
  % CORNER_DR (DOWN<->RIGHT)
                 false, true,  true,  false,
  % CORNER_DL (DOWN<->LEFT)
                 false, false, true,  true,
  % SWITCH_T_D_R (entries {TOP,RIGHT,DOWN})
                 true,  true,  true,  false,
  % SWITCH_T_D_L (entries {TOP,LEFT,DOWN})
                 true,  false, true,  true,
  % SWITCH_D_T_R (entries {TOP,RIGHT,DOWN})
                 true,  true,  true,  false,
  % SWITCH_D_T_L (entries {TOP,LEFT,DOWN})
                 true,  false, true,  true,
  % SWITCH_R_L_T (entries {LEFT,TOP,RIGHT})
                 true,  true,  false, true,
  % SWITCH_R_L_D (entries {LEFT,DOWN,RIGHT})
                 false, true,  true,  true,
  % SWITCH_L_R_T (entries {RIGHT,TOP,LEFT})
                 true,  true,  false, true,
  % SWITCH_L_R_D (entries {RIGHT,DOWN,LEFT})
                 false, true,  true,  true,
  % DSWITCH_T_D_R (entries {TOP,RIGHT,DOWN})
                 true,  true,  true,  false,
  % DSWITCH_T_D_L (entries {TOP,LEFT,DOWN})
                 true,  false, true,  true,
  % DSWITCH_D_T_R (entries {TOP,RIGHT,DOWN})
                 true,  true,  true,  false,
  % DSWITCH_D_T_L (entries {TOP,LEFT,DOWN})
                 true,  false, true,  true,
  % DSWITCH_R_L_T (entries {LEFT,TOP,RIGHT})
                 true,  true,  false, true,
  % DSWITCH_R_L_D (entries {LEFT,DOWN,RIGHT})
                 false, true,  true,  true,
  % DSWITCH_L_R_T (entries {RIGHT,TOP,LEFT})
                 true,  true,  false, true,
  % DSWITCH_L_R_D (entries {RIGHT,DOWN,LEFT})
                 false, true,  true,  true,
  % TUNNEL_T (can only enter from TOP)
                 true,  false, false, false,
  % TUNNEL_R (can only enter from RIGHT)
                 false, true,  false, false,
  % TUNNEL_D (can only enter from DOWN)
                 false, false, true,  false,
  % TUNNEL_L (can only enter from LEFT)
                 false, false, false, true
]);

% --- Exit Permissions ---
% can_exit[piece, dir] = true if a piece has a physical exit in
% the given direction. This is primarily used for the first move
% from a train's starting position.
array[Piece, Dir] of bool: can_exit = array2d(Piece, Dir, [
  %              TOP    RIGHT  DOWN   LEFT
  % EMPTY
                 false, false, false, false,
  % STRAIGHT_TD
                 true,  false, true,  false,
  % STRAIGHT_RL
                 false, true,  false, true,
  % CORNER_TR
                 true,  true,  false, false,
  % CORNER_TL
                 true,  false, false, true,
  % CORNER_DR
                 false, true,  true,  false,
  % CORNER_DL
                 false, false, true,  true,
  % SWITCH_T_D_R (exits {DOWN, RIGHT})
                 false, true,  true,  false,
  % SWITCH_T_D_L (exits {DOWN, LEFT})
                 false, false, true,  true,
  % SWITCH_D_T_R (exits {TOP, RIGHT})
                 true,  true,  false, false,
  % SWITCH_D_T_L (exits {TOP, LEFT})
                 true,  false, false, true,
  % SWITCH_R_L_T (exits {LEFT, TOP})
                 true,  false, false, true,
  % SWITCH_R_L_D (exits {LEFT, DOWN})
                 false, false, true,  true,
  % SWITCH_L_R_T (exits {RIGHT, TOP})
                 true,  true,  false, false,
  % SWITCH_L_R_D (exits {RIGHT, DOWN})
                 false, true,  true,  false,
  % DSWITCH_T_D_R (exits {DOWN, RIGHT})
                 false, true,  true,  false,
  % DSWITCH_T_D_L (exits {DOWN, LEFT})
                 false, false, true,  true,
  % DSWITCH_D_T_R (exits {TOP, RIGHT})
                 true,  true,  false, false,
  % DSWITCH_D_T_L (exits {TOP, LEFT})
                 true,  false, false, true,
  % DSWITCH_R_L_T (exits {LEFT, TOP})
                 true,  false, false, true,
  % DSWITCH_R_L_D (exits {LEFT, DOWN})
                 false, false, true,  true,
  % DSWITCH_L_R_T (exits {RIGHT, TOP})
                 true,  true,  false, false,
  % DSWITCH_L_R_D (exits {RIGHT, DOWN})
                 false, true,  true,  false,
  % TUNNEL_T (exit at TOP)
                 true,  false, false, false,
  % TUNNEL_R (exit at RIGHT)
                 false, true,  false, false,
  % TUNNEL_D (exit at DOWN)
                 false, false, true,  false,
  % TUNNEL_L (exit at LEFT)
                 false, false, false, true
]);

% --- Routing Table ---
% exit_of[piece, entry_dir] = exit_dir
% Defines where a train exits based on which direction it entered from.
array[Piece, Dir] of Dir: exit_of = array2d(Piece, Dir, [
  %            TOP    RIGHT  DOWN   LEFT   (entry_dir)
  % EMPTY
               TOP,   TOP,   TOP,   TOP,
  % STRAIGHT_TD:  TOP->DOWN, DOWN->TOP
               DOWN,  TOP,   TOP,   TOP,
  % STRAIGHT_RL:  RIGHT->LEFT, LEFT->RIGHT
               TOP,   LEFT,  TOP,   RIGHT,
  % CORNER_TR:    TOP->RIGHT, RIGHT->TOP
               RIGHT, TOP,   TOP,   TOP,
  % CORNER_TL:    TOP->LEFT, LEFT->TOP
               LEFT,  TOP,   TOP,   TOP,
  % CORNER_DR:    DOWN->RIGHT, RIGHT->DOWN
               TOP,   DOWN,  RIGHT, TOP,
  % CORNER_DL:    DOWN->LEFT, LEFT->DOWN
               TOP,   TOP,   LEFT,  DOWN,
  % SWITCH_T_D_R: TOP->DOWN, DOWN->RIGHT, RIGHT->DOWN
               DOWN,  DOWN,  RIGHT, TOP,
  % SWITCH_T_D_L: TOP->DOWN, DOWN->LEFT, LEFT->DOWN
               DOWN,  TOP,   LEFT,  DOWN,
  % SWITCH_D_T_R: DOWN->TOP, TOP->RIGHT, RIGHT->TOP
               RIGHT, TOP,   TOP,   TOP,
  % SWITCH_D_T_L: DOWN->TOP, TOP->LEFT, LEFT->TOP
               LEFT,  TOP,   TOP,   TOP,
  % SWITCH_R_L_T: RIGHT->LEFT, LEFT->TOP, TOP->LEFT
               LEFT,  LEFT,  TOP,   TOP,
  % SWITCH_R_L_D: RIGHT->LEFT, LEFT->DOWN, DOWN->LEFT
               TOP,   LEFT,  LEFT,  DOWN,
  % SWITCH_L_R_T: LEFT->RIGHT, RIGHT->TOP, TOP->RIGHT
               RIGHT, TOP,   TOP,   RIGHT,
  % SWITCH_L_R_D: LEFT->RIGHT, RIGHT->DOWN, DOWN->RIGHT
               TOP,   DOWN,  RIGHT, RIGHT,
  % DSWITCH_T_D_R: TOP->DOWN, DOWN->RIGHT, RIGHT->DOWN (initial state)
               DOWN,  DOWN,  RIGHT, TOP,
  % DSWITCH_T_D_L: TOP->DOWN, DOWN->LEFT, LEFT->DOWN
               DOWN,  TOP,   LEFT,  DOWN,
  % DSWITCH_D_T_R: DOWN->TOP, TOP->RIGHT, RIGHT->TOP
               RIGHT, TOP,   TOP,   TOP,
  % DSWITCH_D_T_L: DOWN->TOP, TOP->LEFT, LEFT->TOP
               LEFT,  TOP,   TOP,   TOP,
  % DSWITCH_R_L_T: RIGHT->LEFT, LEFT->TOP, TOP->LEFT
               LEFT,  LEFT,  TOP,   TOP,
  % DSWITCH_R_L_D: RIGHT->LEFT, LEFT->DOWN, DOWN->LEFT
               TOP,   LEFT,  LEFT,  DOWN,
  % DSWITCH_L_R_T: LEFT->RIGHT, RIGHT->TOP, TOP->RIGHT
               RIGHT, TOP,   TOP,   RIGHT,
  % DSWITCH_L_R_D: LEFT->RIGHT, RIGHT->DOWN, DOWN->RIGHT
               TOP,   DOWN,  RIGHT, RIGHT,
  % TUNNEL_T
               TOP,   TOP,   TOP,   TOP,
  % TUNNEL_R
               RIGHT, RIGHT, RIGHT, RIGHT,
  % TUNNEL_D
               DOWN,  DOWN,  DOWN,  DOWN,
  % TUNNEL_L
               LEFT,  LEFT,  LEFT,  LEFT
]);

% --- Dynamic DSWITCH Routing Function ---
% Returns the exit direction for a DSWITCH piece based on entry direction
% and its current swap state (normal or swapped).
% When swapped, the Single and Straight connections are swapped, while the
% Curve connection remains unchanged.
function var Dir: dswitch_exit(var Piece: piece, var Dir: entry_dir, var bool: is_swapped) =
  if not is_swapped then
    % Normal state: use standard exit_of table
    exit_of[piece, entry_dir]
  else
    % Swapped state: Single and Straight are swapped
    if piece == DSWITCH_T_D_R then
      % Normal: TOP(single)->DOWN, DOWN(straight)->RIGHT, RIGHT(curve)->DOWN
      % Swapped: DOWN(single)->TOP, TOP(straight)->RIGHT, RIGHT(curve)->TOP
      if entry_dir == TOP then RIGHT      % Was straight, now goes to curve
      elseif entry_dir == DOWN then TOP   % Was single, now goes to straight
      elseif entry_dir == RIGHT then TOP  % Was curve, now goes to straight
      else TOP endif
    elseif piece == DSWITCH_T_D_L then
      % Normal: TOP->DOWN, DOWN->LEFT, LEFT->DOWN
      % Swapped: DOWN->TOP, TOP->LEFT, LEFT->TOP
      if entry_dir == TOP then LEFT       % Was straight, now goes to curve
      elseif entry_dir == DOWN then TOP   % Was single, now goes to straight
      elseif entry_dir == LEFT then TOP   % Was curve, now goes to straight
      else TOP endif
    elseif piece == DSWITCH_D_T_R then
      % Normal: DOWN->TOP, TOP->RIGHT, RIGHT->TOP
      % Swapped: TOP->DOWN, DOWN->RIGHT, RIGHT->DOWN
      if entry_dir == DOWN then RIGHT     % Was straight, now goes to curve
      elseif entry_dir == TOP then DOWN   % Was single, now goes to straight
      elseif entry_dir == RIGHT then DOWN % Was curve, now goes to straight
      else TOP endif
    elseif piece == DSWITCH_D_T_L then
      % Normal: DOWN->TOP, TOP->LEFT, LEFT->TOP
      % Swapped: TOP->DOWN, DOWN->LEFT, LEFT->DOWN
      if entry_dir == DOWN then LEFT      % Was straight, now goes to curve
      elseif entry_dir == TOP then DOWN   % Was single, now goes to straight
      elseif entry_dir == LEFT then DOWN  % Was curve, now goes to straight
      else TOP endif
    elseif piece == DSWITCH_R_L_T then
      % Normal: RIGHT->LEFT, LEFT->TOP, TOP->LEFT
      % Swapped: LEFT->RIGHT, RIGHT->TOP, TOP->RIGHT
      if entry_dir == RIGHT then TOP      % Was straight, now goes to curve
      elseif entry_dir == LEFT then RIGHT % Was single, now goes to straight
      elseif entry_dir == TOP then RIGHT  % Was curve, now goes to straight
      else TOP endif
    elseif piece == DSWITCH_R_L_D then
      % Normal: RIGHT->LEFT, LEFT->DOWN, DOWN->LEFT
      % Swapped: LEFT->RIGHT, RIGHT->DOWN, DOWN->RIGHT
      if entry_dir == RIGHT then DOWN     % Was straight, now goes to curve
      elseif entry_dir == LEFT then RIGHT % Was single, now goes to straight
      elseif entry_dir == DOWN then RIGHT % Was curve, now goes to straight
      else TOP endif
    elseif piece == DSWITCH_L_R_T then
      % Normal: LEFT->RIGHT, RIGHT->TOP, TOP->RIGHT
      % Swapped: RIGHT->LEFT, LEFT->TOP, TOP->LEFT
      if entry_dir == LEFT then TOP       % Was straight, now goes to curve
      elseif entry_dir == RIGHT then LEFT % Was single, now goes to straight
      elseif entry_dir == TOP then LEFT   % Was curve, now goes to straight
      else TOP endif
    elseif piece == DSWITCH_L_R_D then
      % Normal: LEFT->RIGHT, RIGHT->DOWN, DOWN->RIGHT
      % Swapped: RIGHT->LEFT, LEFT->DOWN, DOWN->LEFT
      if entry_dir == LEFT then DOWN      % Was straight, now goes to curve
      elseif entry_dir == RIGHT then LEFT % Was single, now goes to straight
      elseif entry_dir == DOWN then LEFT  % Was curve, now goes to straight
      else TOP endif
    else
      % Not a DSWITCH, shouldn't happen
      exit_of[piece, entry_dir]
    endif
  endif;