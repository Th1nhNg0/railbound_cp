% ============================================================
% Helper Predicates & Functions
% ------------------------------------------------------------
% Reusable logic for bounds checks and dynamic switch routing.
% Requires lib/globals.mzn for exit tables.
% ============================================================

predicate in_bounds(int: r, int: c) =
  r >= 1 /\ r <= H /\ c >= 1 /\ c <= W;

% Dynamic switch routing logic.
% When swapped, single and straight exits are exchanged while the
% curve path remains unchanged.
function var Dir: dswitch_exit(var Piece: piece, var Dir: entry_dir, var bool: is_swapped) =
  if not is_swapped then
    exit_of[piece, entry_dir]
  else
    if piece == DSWITCH_T_D_R then
      if entry_dir == TOP then RIGHT
      elseif entry_dir == DOWN then TOP
      elseif entry_dir == RIGHT then TOP
      else TOP endif
    elseif piece == DSWITCH_T_D_L then
      if entry_dir == TOP then LEFT
      elseif entry_dir == DOWN then TOP
      elseif entry_dir == LEFT then TOP
      else TOP endif
    elseif piece == DSWITCH_D_T_R then
      if entry_dir == DOWN then RIGHT
      elseif entry_dir == TOP then DOWN
      elseif entry_dir == RIGHT then DOWN
      else TOP endif
    elseif piece == DSWITCH_D_T_L then
      if entry_dir == DOWN then LEFT
      elseif entry_dir == TOP then DOWN
      elseif entry_dir == LEFT then DOWN
      else TOP endif
    elseif piece == DSWITCH_R_L_T then
      if entry_dir == RIGHT then TOP
      elseif entry_dir == LEFT then RIGHT
      elseif entry_dir == TOP then RIGHT
      else TOP endif
    elseif piece == DSWITCH_R_L_D then
      if entry_dir == RIGHT then DOWN
      elseif entry_dir == LEFT then RIGHT
      elseif entry_dir == DOWN then RIGHT
      else TOP endif
    elseif piece == DSWITCH_L_R_T then
      if entry_dir == LEFT then TOP
      elseif entry_dir == RIGHT then LEFT
      elseif entry_dir == TOP then LEFT
      else TOP endif
    elseif piece == DSWITCH_L_R_D then
      if entry_dir == LEFT then DOWN
      elseif entry_dir == RIGHT then LEFT
      elseif entry_dir == DOWN then LEFT
      else TOP endif
    else
      exit_of[piece, entry_dir]
    endif
  endif;
