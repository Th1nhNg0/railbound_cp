enum Dir = { TOP, RIGHT, DOWN, LEFT };

enum Piece = {
  EMPTY,

  % Straights
  STRAIGHT_TD,  % Vertical track connecting Top and Down.
  STRAIGHT_RL,  % Horizontal track connecting Right and Left.

  % Corners
  CORNER_TR,    % 90-degree turn connecting Top and Right.
  CORNER_TL,    % 90-degree turn connecting Top and Left.
  CORNER_DR,    % 90-degree turn connecting Down and Right.
  CORNER_DL,    % 90-degree turn connecting Down and Left.

  % Deterministic Switches: SWITCH_<entry>_<straight_exit>_<curved_exit>
  SWITCH_T_D_R, % Enters from TOP, goes straight to DOWN or curves to RIGHT.
  SWITCH_T_D_L, % Enters from TOP, goes straight to DOWN or curves to LEFT.
  SWITCH_D_T_R, % Enters from DOWN, goes straight to TOP or curves to RIGHT.
  SWITCH_D_T_L, % Enters from DOWN, goes straight to TOP or curves to LEFT.
  SWITCH_R_L_T, % Enters from RIGHT, goes straight to LEFT or curves to TOP.
  SWITCH_R_L_D, % Enters from RIGHT, goes straight to LEFT or curves to DOWN.
  SWITCH_L_R_T, % Enters from LEFT, goes straight to RIGHT or curves to TOP.
  SWITCH_L_R_D, % Enters from LEFT, goes straight to RIGHT or curves to DOWN.

  % Dynamic Switches (stateful) - Toggle their exit path each time a train passes through.
  DSWITCH_T_D_R, DSWITCH_T_D_L, DSWITCH_D_T_R, DSWITCH_D_T_L,
  DSWITCH_R_L_T, DSWITCH_R_L_D, DSWITCH_L_R_T, DSWITCH_L_R_D,

  % Exit-triggered Switches (stateful) - Toggle their exit path each time any train exits the piece.
  ESWITCH_T_D_R, ESWITCH_T_D_L, ESWITCH_D_T_R, ESWITCH_D_T_L,
  ESWITCH_R_L_T, ESWITCH_R_L_D, ESWITCH_L_R_T, ESWITCH_L_R_D,

  % Tunnels - Directional entry points for teleportation.
  TUNNEL_T,     % Tunnel entry allowing entry from Top.
  TUNNEL_R,     % Tunnel entry allowing entry from Right.
  TUNNEL_D,     % Tunnel entry allowing entry from Down.
  TUNNEL_L,     % Tunnel entry allowing entry from Left.
  ROCK          % Rock piece (impassable terrain).
};

type Pos = tuple(int, int, Piece);


set of Piece: STRAIGHTS_SET = { STRAIGHT_TD, STRAIGHT_RL };
set of Piece: CORNERS_SET = { CORNER_TR, CORNER_TL, CORNER_DR, CORNER_DL };
set of Piece: SWITCHES_SET  = {
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
set of Piece: TUNNELS_SET= { TUNNEL_T, TUNNEL_R, TUNNEL_D, TUNNEL_L };