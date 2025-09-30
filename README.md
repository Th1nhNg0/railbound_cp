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

- **Optimization**: Prefers simpler solutions
  - Cost-based optimization minimizes puzzle complexity
  - Automatically prefers straight tracks over switches when both work
  - Produces cleaner, more elegant solutions

- **Flexible input format**: Easy-to-write `.dzn` data files for puzzle definitions
- **Automatic solving**: Finds optimal solutions or proves unsatisfiability
- **Visual output**: Displays grid layout, piece costs, and train paths
- **Multiple solvers**: Supports Gecode, Chuffed, and other MiniZinc solvers
- **Well-documented code**: Clean, readable implementation with clear section organization

## Requirements

- [MiniZinc](https://www.minizinc.org/software.html) (version 2.5+)
- A MiniZinc solver:
  - **Gecode** (recommended for most puzzles) - Fast and reliable
  - **Chuffed** - Good for complex puzzles
  - **OR-Tools** - Alternative option

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
minizinc --solver Gecode railbound.mzn test/2-1.dzn
```

Or use Chuffed for more complex puzzles:

```bash
minizinc --solver Chuffed railbound.mzn test/2-8.dzn
```

With a time limit (in milliseconds):

```bash
minizinc --solver Gecode railbound.mzn test/2-8.dzn --time-limit 60000
```

### Output

The solver produces:
```
============================================================
SOLUTION FOUND
============================================================

GRID LAYOUT:
[|       EMPTY,       EMPTY,       EMPTY, TUNNEL_R, STRAIGHT_RL, STRAIGHT_RL, STRAIGHT_RL
 |       EMPTY,       EMPTY,       EMPTY,    EMPTY,       EMPTY,       EMPTY,       EMPTY
 |       EMPTY,       EMPTY,       EMPTY,    EMPTY,       EMPTY,       EMPTY,       EMPTY
 | STRAIGHT_RL, STRAIGHT_RL, STRAIGHT_RL, TUNNEL_L,       EMPTY,       EMPTY,       EMPTY
 |]

Total piece cost: 6 (straights=1, corners=2, switches=3)
Latest arrival time: 6
TRAIN PATHS:
Train 1: arrival at time 6
  Path: [(4, 1), (4, 2), (4, 3), (4, 4), (1, 5), (1, 6), (1, 7)]
```

The **total piece cost** shows how simple the solution is - lower is better!

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

- `2-1.dzn`: Simple puzzle demonstrating cost optimization (prefers straights over switches)
- `easy.dzn`: Single-train puzzle
- `1-3.dzn`: Single train with switches
- `1-9.dzn`: Two trains requiring coordination
- `1-11A.dzn`: Three trains with complex routing
- `2-8.dzn`: Three trains with tunnel teleportation
- And more...

### Running Multiple Tests

Test several puzzles at once:

```bash
# PowerShell
Get-ChildItem test\*.dzn | ForEach-Object {
  Write-Host "Solving $_..."
  minizinc --solver Gecode railbound.mzn $_.FullName
}

# Bash
for f in test/*.dzn; do
  echo "Solving $f..."
  minizinc --solver Gecode railbound.mzn "$f"
done
```

## How It Works

The solver uses constraint programming with optimization to model the puzzle:

### 1. **Variables**
- **Grid variables**: Each cell can contain any track piece
- **Train state variables**: Position and direction for each train at each time step
- **Arrival times**: When each train reaches the target

### 2. **Constraints**
- Trains start at specified positions with initial exit directions
- Train movement follows track piece routing rules (straights, corners, switches)
- Tunnel teleportation with directional entry restrictions
- Trains must reach the target in sequential order (no overtaking)
- No collisions between trains (same cell or position swaps)
- Connectivity validation for corners and switches (all entry points must connect)
- Respect the track budget (maximum number of placeable pieces)
- Honor pre-placed pieces and tunnel placements

### 3. **Optimization**
The solver minimizes the total piece cost to prefer simpler solutions:
- **Straight pieces**: cost = 1 (simplest)
- **Corner pieces**: cost = 2
- **Switch pieces**: cost = 3 (most complex)
- **Empty/Tunnel pieces**: cost = 0 (fixed)

This ensures the solver finds the cleanest, most elegant solution rather than arbitrary complex arrangements.

### Key Implementation Details

- **Tunnel Logic**: Tunnels enforce one-way entry restrictions. When a train enters a tunnel, it instantly appears at the next cell after the paired tunnel, exiting in the paired tunnel's direction.
- **Switch Routing**: Switches have three connections with specific routing rules based on which direction the train enters.
- **Collision Avoidance**: Both same-cell occupancy and position-swap collisions are prevented (except at the target cell).
- **Sequential Arrival**: Trains must arrive at the target in order - later trains cannot reach the target before earlier trains.
- **Connectivity Enforcement**: All entry points of corners and switches must connect to valid adjacent cells, preventing switches at boundaries where simpler pieces would work.

## Project Structure

```
railbound_cp/
├── railbound.mzn           # Main MiniZinc model (well-documented and refactored)
├── test/                   # Example puzzle data files
│   ├── 2-1.dzn
│   ├── easy.dzn
│   ├── 1-3.dzn
│   └── ...
├── README.md               # This file
├── OPTIMIZATION_NOTES.md   # Details on cost-based optimization
├── SOLUTION_SUMMARY.md     # Quick reference for the optimization approach
└── REFACTORING_SUMMARY.md  # Code refactoring improvements
```

## Documentation

- **README.md**: Main documentation (this file)
- **OPTIMIZATION_NOTES.md**: Deep dive into why cost optimization is needed and how it works
- **SOLUTION_SUMMARY.md**: Quick reference for the cost-based preference system
- **REFACTORING_SUMMARY.md**: Details on code organization improvements

## Code Quality

The `railbound.mzn` model features:
- ✅ Clean, well-organized structure with clear section headers
- ✅ Comprehensive inline documentation
- ✅ Logical grouping of related components
- ✅ Helper predicates and constants for readability
- ✅ Cost optimization for elegant solutions
- ✅ Tested with multiple solvers (Gecode, Chuffed)

## Contributing

Feel free to add more puzzle definitions or improve the model!

### Adding New Puzzles

1. Create a new `.dzn` file in the `test/` directory
2. Define the grid size, trains, and constraints
3. Test with: `minizinc --solver Gecode railbound.mzn test/your-puzzle.dzn`

### Improving the Model

The code is well-documented and refactored for readability. See `REFACTORING_SUMMARY.md` for details on the code structure.

## License

This is an educational project for learning constraint programming. Railbound is a trademark of Afterburn.

## Acknowledgments

- Puzzle game design: [Afterburn](https://afterburn.games/)
- Constraint modeling: [MiniZinc](https://www.minizinc.org/)
