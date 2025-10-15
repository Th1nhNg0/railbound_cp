# Railbound MiniZinc Data Format

Railbound instances in `data/` are plain-text MiniZinc `.dzn` files. Each file declares the parameters consumed by `main.mzn`. This guide documents every field, the coordinate system, and the enumerated values expected by the solver.

## Coordinate System and Enumerations

- Cells are addressed as `(row, column)` with both indices starting at 1 in the top-left corner of the grid. Rows increase downward; columns increase to the right.
- Directions follow `enum Dir = { TOP, RIGHT, DOWN, LEFT };`. A direction always refers to the heading of a train or the side of a tile that is entered/exited.
- Track pieces come from `enum Piece` (defined in `lib/types.mzn`). The names encode both geometry and orientation:
  - `EMPTY` - solver may place track here.
  - Straights: `STRAIGHT_TD`, `STRAIGHT_RL`.
  - Corners: `CORNER_TR`, `CORNER_TL`, `CORNER_DR`, `CORNER_DL`.
  - Deterministic switches: `SWITCH_<entry>_<straight>_<turn>` (e.g. `SWITCH_T_D_R`).
  - Dynamic switches: `DSWITCH_*` (toggle on activation).
  - Exit-triggered switches: `ESWITCH_*` (toggle each time a train exits).
  - Tunnels: `TUNNEL_T`, `TUNNEL_R`, `TUNNEL_D`, `TUNNEL_L` (entry direction encoded in the suffix).
  - `ROCK` - impassable cell.
  - Switches, tunnels, exit-triggered switches, and rocks are considered "unplaceable" by the solver and must appear in `INIT_POS` or `TUNNEL_PAIRS`.

## Scalar Parameters

- `W`, `H` - grid width and height.
- `MAX_TIME` - discrete time horizon. Must be long enough for every train to reach the target.
- `MAX_TRACKS` - maximum number of non-empty, non-initial cells the solver may fill with new pieces.
- `TARGET = (row, col)` - destination cell shared by all trains. The model expects the exit to be on the right edge so trains finish facing `LEFT`.

## Vehicle Seeds

- `TRAINS = [(row, col, Dir), ...];`
  - Order matters: train `1` must arrive before train `2`, etc.
  - The tuple stores the cell occupied at time 0 and the direction the locomotive is pointing (toward its first move).
- `DECOYS = [(row, col, Dir), ...];`
  - Same structure as trains but decoy cars are not required to reach `TARGET`.
  - Leave the array empty (`DECOYS=[];`) if a level has no decoys.

## Board Initialization

- `INIT_POS = [(row, col, Piece), ...];`
  - Pre-placed tiles. The solver fixes these cells to the supplied pieces for the entire run.
  - Include every unplaceable tile and any pre-laid track segments supplied by the level.
- `TUNNEL_PAIRS = [(r1, c1, entry_dir1, r2, c2, entry_dir2), ...];`
  - Each tuple links two tunnel entrances. The third and sixth fields record the direction from which a train may legally enter each end.
  - The solver plants the corresponding `TUNNEL_*` pieces automatically; you do not need extra `INIT_POS` entries for them.

## Activation-Driven Mechanics

- `GATES = [(row, col, activation_id, initially_open), ...];`
  - `initially_open` is a Boolean (`true`/`false`) state at time 0.
  - Multiple gates may share the same `activation_id` to toggle together.
- `ACTIVATIONS = [(row, col, activation_id), ...];`
  - When any train or decoy enters `(row, col)`, every gate or dynamic switch with the matching `activation_id` toggles on the next step.
- `DSWITCHES = [(row, col, activation_id), ...];`
  - Identifies dynamic switches on the grid and links them to their controlling activation tiles. The piece itself must be pre-seeded in `INIT_POS`.

## Stations

- `STATIONS = [(row, col, vehicle_id), ...];`
  - `vehicle_id > 0` references train `vehicle_id`.
  - `vehicle_id < 0` references decoy `abs(vehicle_id)`.
  - The solver enforces a two-step dwell time the first time the assigned train or decoy visits any of its stations and requires trains to finish all station visits before reaching `TARGET`.

## Empty Collections

Any optional feature can be omitted by providing an empty list. MiniZinc accepts either `[];` or `[ ];` - both styles appear in this repository.

## Example Skeleton

```minizinc
W=5;
H=3;
MAX_TIME=20;
MAX_TRACKS=12;
TARGET=(2,5);

TRAINS=[(2,1,RIGHT)];
DECOYS=[];

INIT_POS=[
  (2,5,STRAIGHT_RL),
  (3,3,ROCK),
];

TUNNEL_PAIRS=[
  (1,3,DOWN, 3,1,LEFT),
];

GATES=[
  (2,4,1,true),
];
ACTIVATIONS=[
  (1,2,1),
];
DSWITCHES=[];

STATIONS=[
  (2,3,1),
];
```
