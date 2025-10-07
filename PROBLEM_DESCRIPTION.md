# Railbound Puzzle Problem Description

## Overview

This project models and solves puzzles from the game **Railbound** using **Constraint Programming (CP)** with MiniZinc. Railbound is a puzzle game where players must connect trains to a target location by strategically placing a limited number of track pieces on a grid.

## The Problem

### Core Objective

Given:

- A rectangular grid of dimensions `W × H`
- One or more trains starting at specific positions with initial directions
- A single target cell where all trains must arrive
- A limited budget of `MAX_TRACKS` track pieces that can be placed
- Various pre-placed track pieces, switches, tunnels, and gates

Find:

- A valid placement of track pieces on the grid
- That allows all trains to travel from their starting positions to the target
- While respecting all game mechanics and constraints
- Using no more than the allowed number of tracks

### Problem Classification

This is a **Constraint Satisfaction Problem (CSP)** with optimization components:

- **Decision Variables**: Track piece placement and train movement paths
- **Constraints**: Game rules, physics, and mechanics
- **Objective**: Minimize the number of tracks used (or time taken)

## Game Mechanics

### 1. Grid and Track Pieces

The game takes place on a 2D grid where each cell can contain:

#### Basic Track Pieces

- **EMPTY**: No track piece
- **STRAIGHT_TD**: Vertical straight track (Top ↔ Down)
- **STRAIGHT_RL**: Horizontal straight track (Right ↔ Left)
- **CORNER_TR**: 90° corner (Top ↔ Right)
- **CORNER_TL**: 90° corner (Top ↔ Left)
- **CORNER_DR**: 90° corner (Down ↔ Right)
- **CORNER_DL**: 90° corner (Down ↔ Left)

#### Static Switches (Deterministic)

Three-way junctions where trains always take the straight path:

- **SWITCH_T_D_R**: Enter from Top → straight to Down, or from Right
- **SWITCH_T_D_L**: Enter from Top → straight to Down, or from Left
- **SWITCH_D_T_R**: Enter from Down → straight to Top, or from Right
- **SWITCH_D_T_L**: Enter from Down → straight to Top, or from Left
- **SWITCH_R_L_T**: Enter from Right → straight to Left, or from Top
- **SWITCH_R_L_D**: Enter from Right → straight to Left, or from Down
- **SWITCH_L_R_T**: Enter from Left → straight to Right, or from Top
- **SWITCH_L_R_D**: Enter from Left → straight to Right, or from Down

#### Dynamic Switches (Stateful)

Switches that **toggle their state** each time a train enters their **activation cell**:

- **DSWITCH\_\*** variants: Toggle between straight and curved exit paths
- State tracked per switch across time
- Multiple trains can affect the same switch

#### Exit-Triggered Switches (Stateful)

Switches that toggle when any train **exits** the piece:

- **ESWITCH\_\*** variants: Similar to DSWITCH but triggered on exit
- Used for more complex puzzle mechanics

#### Tunnels

Teleportation pairs that instantly transport trains:

- **TUNNEL_T**: Entry from Top
- **TUNNEL_R**: Entry from Right
- **TUNNEL_D**: Entry from Down
- **TUNNEL_L**: Entry from Left
- Always come in pairs with specified exit directions
- Format: `(r1, c1, entry_dir, r2, c2, exit_dir)`

### 2. Train Dynamics

#### Train Properties

- **Position**: (row, column) on the grid at each timestep
- **Direction**: Entry direction into current cell (TOP, RIGHT, DOWN, LEFT)
- **Arrival Time**: Timestep when train reaches the target

#### Movement Rules

1. Trains move one cell per timestep
2. Movement determined by:
   - Current piece type
   - Entry direction
   - Switch state (for dynamic switches)
3. Trains must follow valid connections:
   - `can_enter[piece, direction]`: Valid entry?
   - `can_exit[piece, direction]`: Valid exit?
   - `exit_of[piece, entry_dir]`: Determines exit direction

#### Special Behaviors

- **Tunnels**: Train teleports to paired tunnel exit
- **Gates**: Train waits if gate is closed
- **Target**: Train stays at target after arrival
- **Waiting**: Train remains in place if path is blocked

### 3. Gates and Activations

#### Gate System

- **Gates**: Barriers that can be open or closed
- **Initial State**: Each gate starts either open or closed
- **Activation Cells**: Special cells that toggle linked gates

#### Toggle Mechanism

- When a train **newly enters** an activation cell:
  - All gates with matching ID toggle their state
  - Open → Closed or Closed → Open
- Multiple activations in one timestep:
  - Odd count: Gate toggles
  - Even count: Gate stays the same

#### Format

- **GATES**: `[(row, col, gate_id, is_initially_open), ...]`
- **ACTIVATIONS**: `[(row, col, gate_id), ...]`

### 4. Stations

Stations are waiting points where trains must pause:

- Each station is linked to a specific train
- Train must wait at station for a predetermined duration
- Used to synchronize train movements in complex puzzles

### 5. Time and Sequencing

#### Time System

- Discrete timesteps from `0` to `MAX_TIME`
- `MAX_TIME` typically set to `W * H` (grid size)
- Each train tracked individually across time

#### Arrival Ordering

- Trains must arrive in **sequential order**
- Train 1 must arrive before Train 2, etc.
- Prevents optimization tricks that violate game rules

## Key Constraints

### 1. Grid Constraints

#### Track Budget

```minizinc
sum(newly_placed_tracks) <= MAX_TRACKS
```

- Count only tracks not in `INIT_POS` or `TUNNEL_PAIRS`

#### Pre-placed Pieces

- Pieces in `INIT_POS` must remain fixed
- Tunnels must be at specified positions
- Special pieces (switches, tunnels) cannot be dynamically placed

#### Switch Connectivity

- Switches must have exactly 3 valid neighbors
- Ensures switches connect properly to adjacent tracks

### 2. Train Constraints

#### Initial Position

- Each train starts at specified `(row, col)` with given direction
- First move respects gate state

#### Movement Validity

- Trains can only move on non-empty cells
- Must follow piece routing rules
- Cannot enter cells with closed gates

#### No Collisions

- No two trains occupy same cell simultaneously
- No position swapping in consecutive timesteps
- Applies to active trains (before arrival)

#### Sequential Arrival

- `arrival_time[t] < arrival_time[t+1]` for all trains

### 3. Gate/Switch State Constraints

#### Initial States

- Gates start at specified open/closed state
- Dynamic switches start un-toggled
- Exit switches start in default orientation

#### State Propagation

- Gate state at time `t` depends on:
  - State at time `t-1`
  - Activations between `t-1` and `t`
- Switch state toggles on train interaction

## Optimization Objectives

The solver can optimize for:

### Primary: Minimize Tracks Used

```minizinc
minimize sum(newly_placed_non_empty_tracks)
```

- Encourages elegant, minimal solutions
- Matches game's star rating system

### Secondary: Minimize Time

```minizinc
minimize max(arrival_time)
```

- Fastest solution for given track budget
- Can be used as tiebreaker

## Problem Complexity

### Computational Challenges

1. **State Space Explosion**

   - Grid size: `W × H` cells
   - Track choices per cell: ~35 piece types
   - Time dimension: `MAX_TIME` timesteps
   - Switch states: Boolean per switch per timestep

2. **Interdependent Constraints**

   - Train paths depend on track placement
   - Switch states depend on train movements
   - Gates affect train movements
   - All must be satisfied simultaneously

3. **Temporal Dependencies**
   - Future state depends on past actions
   - Must track state evolution over time
   - Prevents decomposition into subproblems

### Why Constraint Programming?

CP is ideal for this problem because:

- **Declarative**: Express what is valid, not how to find it
- **Global Constraints**: Handles complex relationships naturally
- **Efficient Propagation**: Prunes invalid states early
- **Satisfiability**: Finds if solution exists before optimizing
- **Flexibility**: Easy to add new mechanics or constraints

## Input Format (.dzn files)

Example puzzle specification:

```minizinc
W=8;              % Grid width
H=5;              % Grid height
MAX_TIME=18;      % Time limit
MAX_TRACKS=10;    % Track budget
TARGET=(4,8);     % Target cell (1-indexed)

TRAINS=[(1,5,DOWN)];  % (row, col, initial_direction)

INIT_POS=[         % Pre-placed pieces
  (1,5,STRAIGHT_TD),
  (4,8,STRAIGHT_RL),
];

TUNNEL_PAIRS=[     % Tunnel teleportation pairs
  (1,1,DOWN, 5,4,RIGHT),
];

GATES=[            % Gate barriers
  (4,7,1,false),   % (row, col, gate_id, initially_open)
];

ACTIVATIONS=[      % Gate toggle triggers
  (3,1,1),         % (row, col, gate_id)
];

DSWITCHES=[        % Dynamic switch IDs
  (2,3,1),         % (row, col, switch_id)
];

STATIONS=[         % Train waiting points
  (3,4,1),         % (row, col, train_id)
];
```

## Solution Output

The solver produces:

1. **Complete Grid Layout**: Track placement for all cells
2. **Train Paths**: Sequence of positions for each train
3. **Arrival Times**: When each train reaches target
4. **Metrics**:
   - Tracks used
   - Time taken
   - Solution validity

## Current Status

### Solved Worlds

- ✅ World 1: Tutorial levels (21 levels)
- ✅ World 2: Basic mechanics (9 levels)
- ✅ World 3: Intermediate puzzles (23 levels)
- ✅ World 4: Advanced puzzles (22 levels)
- ✅ World 5: Complex mechanics (19 levels)
- ✅ World 6: Expert levels (27 levels)
- ✅ World 7: Currently testing (3 levels)
- ⏳ World 8: In progress (2 levels)

### Performance

- Simple puzzles: Seconds to solve
- Complex puzzles: Minutes to hours
- Uses CP-SAT solver (Google OR-Tools backend)
- Benchmark results tracked in `benchmark_results/`

## Related Files

- **Main Model**: `main.mzn` - Core problem definition
- **Type Definitions**: `lib/types.mzn` - Enums and types
- **Global Tables**: `lib/globals.mzn` - Lookup tables and helpers
- **Constraints**:
  - `constraints/grid.mzn` - Grid and placement rules
  - `constraints/trains.mzn` - Train movement and collisions
  - `constraints/gates.mzn` - Gate/activation mechanics
  - `constraints/dswitches.mzn` - Dynamic switch behavior
- **Formatting**: `formatting.mzn` - Output visualization
- **Data**: `data/*/` - Level specifications (121+ levels)

## Visualization

The solver integrates with MiniZinc IDE visualization:

- `viz.html`: Interactive solution viewer
- Shows grid layout with placed tracks
- Animates train movements over time
- Highlights gates, switches, and special pieces

## Future Enhancements

Potential extensions:

- [ ] Full exit-switch (ESWITCH) implementation
- [ ] Station waiting time mechanics
- [ ] Multi-objective optimization (time + tracks)
- [ ] Symmetry breaking for faster solving
- [ ] Parallel solving for multiple levels
- [ ] Solution explanation generation
