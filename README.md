# Railbound Constraint Programming Solver

![Railbound Cover](cover.jpg)

A constraint programming solver for [Railbound](https://afterburn.games/railbound/) puzzles using [MiniZinc](https://www.minizinc.org/).

## About Railbound

Railbound is a comfy track-building puzzle game created by Afterburn. Players must place track pieces on a grid to guide trains to their destination without collisions. The game features charming aesthetics and increasingly complex puzzles involving switches, corners, and tunnels.

Learn more:
- Official website: https://afterburn.games/railbound/
- Wikipedia: https://en.wikipedia.org/wiki/Railbound

## About This Project

This project models Railbound puzzles as Constraint Satisfaction Problems (CSP) and solves them using MiniZinc, a high-level constraint modeling language. The solver can automatically find valid track layouts that guide all trains to their target destination in the correct order while respecting collision avoidance and track budget constraints.

## Features

- **Complete puzzle modeling**: Supports all core Railbound mechanics
  - Straight tracks and corners
  - Switches (3-way junctions)
  - Tunnels (teleportation between paired locations with directional entry restrictions)
  - Multiple trains with sequential arrival requirements
  - Collision avoidance (no train-to-train collisions or position swaps)
  - Track budget constraints
  - Pre-placed pieces

- **Flexible input format**: Easy-to-write `.dzn` data files for puzzle definitions
- **Automatic solving**: Finds valid solutions or proves unsatisfiability
- **Visual output**: Displays grid layout and train paths
- **Optimized solving**: Uses the Chuffed solver for efficient constraint propagation

## Requirements

- [MiniZinc](https://www.minizinc.org/software.html) (version 2.5+)
- A MiniZinc solver (Chuffed recommended, also supports Gecode or OR-Tools)

## Installation

1. Install MiniZinc from https://www.minizinc.org/software.html
2. Clone this repository:
   ```bash
   git clone <repository-url>
   cd railbound_cp
   ```

## Usage

Run the solver on a puzzle:

```bash
minizinc --solver chuffed railbound.mzn test/easy.dzn
```

Or with a time limit (in milliseconds):

```bash
minizinc --solver chuffed railbound.mzn test/2-8.dzn --time-limit 60000
```

For simpler puzzles, Gecode also works well:

```bash
minizinc --solver Gecode railbound.mzn test/easy.dzn
```

## Puzzle Format

Puzzles are defined in `.dzn` (MiniZinc data) files. Here's an example:

```minizinc
W=6;                    % Grid width
H=3;                    % Grid height

MAX_TIME=W*H;           % Maximum time steps
MAX_TRACKS=10;          % Track budget

TARGET_R=1;             % Target row
TARGET_C=6;             % Target column

N_TRAINS=1;             % Number of trains
TRAINS=[(3,1,TOP)];     % Train starting positions: (row, col, initial_direction)

N_INIT_POS=8;           % Number of pre-placed pieces
INIT_POS=[
  (3,1,STRAIGHT_TD),    % Pre-placed pieces: (row, col, piece_type)
  (1,6,STRAIGHT_RL),
  % ... more pieces
];

N_TUNNELS=0;            % Number of tunnel pairs
TUNNEL_PAIRS=[];        % Tunnel definitions: (row1,col1,dir1,row2,col2,dir2)
```

### Parameters

- **W, H**: Grid dimensions (columns × rows)
- **MAX_TIME**: Maximum number of time steps for simulation
- **MAX_TRACKS**: Maximum number of non-EMPTY track pieces that can be placed (excluding pre-placed pieces)
- **TARGET_R, TARGET_C**: The destination cell all trains must reach
- **TRAINS**: Array of train starting positions as tuples `(row, col, direction)`
  - Directions: `TOP`, `RIGHT`, `DOWN`, `LEFT`
- **INIT_POS**: Pre-placed pieces on the grid as tuples `(row, col, piece_type)`
- **TUNNEL_PAIRS**: Paired tunnel endpoints as tuples `(row_A, col_A, dir_A, row_B, col_B, dir_B)`

### Track Pieces

- **EMPTY**: No track
- **STRAIGHT_TD**: Vertical straight track (│) - connects TOP↔DOWN
- **STRAIGHT_RL**: Horizontal straight track (─) - connects RIGHT↔LEFT
- **CORNER_TR**: Corner connecting TOP↔RIGHT (└)
- **CORNER_TL**: Corner connecting TOP↔LEFT (┘)
- **CORNER_DR**: Corner connecting DOWN↔RIGHT (┌)
- **CORNER_DL**: Corner connecting DOWN↔LEFT (┐)
- **SWITCH_***: 3-way switches with naming pattern `SWITCH_<Single>_<Straight>_<Curve>`
  - Example: `SWITCH_T_D_R` connects TOP→DOWN (straight), DOWN→RIGHT (curve), RIGHT→DOWN
  - Example: `SWITCH_D_T_L` connects DOWN→TOP (straight), TOP→LEFT (curve), LEFT→TOP
- **TUNNEL_***: Tunnel entrances with **directional entry restrictions**
  - `TUNNEL_T`: Can only be entered from TOP, paired tunnel exits in TOP direction
  - `TUNNEL_R`: Can only be entered from RIGHT, paired tunnel exits in RIGHT direction
  - `TUNNEL_D`: Can only be entered from DOWN, paired tunnel exits in DOWN direction
  - `TUNNEL_L`: Can only be entered from LEFT, paired tunnel exits in LEFT direction
  - Tunnels work bidirectionally - either endpoint can be the entry point
  - When a train enters a tunnel, it teleports to the paired tunnel and exits in the specified direction

## Example Puzzles

The `test/` directory contains several example puzzles:

- `easy.dzn`: Simple single-train puzzle
- `1-3.dzn`: Single train with switches
- `1-9.dzn`: Two trains requiring coordination
- `1-11A.dzn`: Three trains with complex routing
- `2-8.dzn`: Three trains with tunnel teleportation
- And more...

### Running Multiple Tests

Test several puzzles at once:

```bash
for f in test/*.dzn; do
  echo "Solving $f..."
  minizinc --solver chuffed railbound.mzn "$f" -t 30000
done
```

## How It Works

The solver uses constraint programming to model the puzzle:

1. **Grid variables**: Each cell can contain any track piece
2. **Train state variables**: Position and direction for each train at each time step
3. **Constraints**:
   - Trains start at specified positions with initial exit directions
   - Train movement follows track piece routing rules (straights, corners, switches)
   - Tunnel teleportation with directional entry restrictions
   - Trains must reach the target in sequential order (no overtaking)
   - No collisions between trains (same cell or position swaps)
   - Connectivity validation for corners and switches
   - Respect the track budget (maximum number of placeable pieces)
   - Honor pre-placed pieces and tunnel placements

The MiniZinc solver (Chuffed recommended) explores the search space to find a valid assignment of tracks that satisfies all constraints.

### Key Implementation Details

- **Tunnel Logic**: Tunnels enforce one-way entry restrictions. When a train enters a tunnel, it instantly appears at the next cell after the paired tunnel, exiting in the paired tunnel's direction.
- **Switch Routing**: Switches have three connections with specific routing rules based on which direction the train enters.
- **Collision Avoidance**: Both same-cell occupancy and position-swap collisions are prevented (except at the target cell).
- **Sequential Arrival**: Trains must arrive at the target in order - later trains cannot reach the target before earlier trains.

## Contributing

Feel free to add more puzzle definitions or improve the model!

## License

This is an educational project for learning constraint programming. Railbound is a trademark of Afterburn.

## Acknowledgments

- Puzzle game design: [Afterburn](https://afterburn.games/)
- Constraint modeling: [MiniZinc](https://www.minizinc.org/)
