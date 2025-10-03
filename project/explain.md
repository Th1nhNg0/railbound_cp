# Railbound MiniZinc Model (`railbound.mzn`) Explained

This document provides a detailed explanation of the `railbound.mzn` model, a Constraint Satisfaction Problem (CSP) solver for the puzzle game Railbound, written in the MiniZinc modeling language.

## 1. Overview

The primary goal of this model is to find a valid track layout on a grid that allows a set of trains to travel from their starting positions to a common target destination. The model must adhere to several rules: trains must arrive in a specific order, they cannot collide, and the number of placed track pieces is limited.

The model solves the puzzle by:
1.  **Defining the puzzle's parameters:** Grid size, number of trains, locations of pre-placed elements, etc.
2.  **Declaring decision variables:** These are the unknowns the solver must determine, such as the type of track piece on each grid cell and the position of each train at every point in time.
3.  **Stating constraints:** These are the rules of the game, which define the relationships between the variables and what constitutes a valid solution.
4.  **Defining an objective:** The model seeks to find a solution that minimizes the "cost" of the track pieces used, preferring simpler pieces (straights) over more complex ones (switches).

---

## 2. Model Components

### Parameters (`PARAMETERS`)

These are the inputs that define a specific puzzle level. They must be provided in a separate data file (`.dzn`).

-   `W`, `H`: The width and height of the puzzle grid.
-   `N_TRAINS`: The total number of trains.
-   `MAX_TIME`: The maximum number of time steps for the simulation. This is an upper bound to ensure the solver finishes.
-   `MAX_TRACKS`: The maximum number of new track pieces that can be placed on the grid.
-   `TARGET`: The `(row, col)` coordinates of the destination cell that all trains must reach.
-   `N_INIT_POS`: The number of track pieces that are already pre-placed on the grid.
-   `N_TUNNELS`: The number of tunnel pairs.
-   `N_GATES`, `N_ACTIVATIONS`: The number of gates and their corresponding activation triggers.
-   `N_DSWITCHES`: The number of dynamic switches.

### Type Definitions (`TYPE DEFINITIONS`)

To make the model more readable and robust, several custom types are defined.

-   **`Dir`**: An enumeration `{ TOP, RIGHT, DOWN, LEFT }` representing the four cardinal directions.
-   **`Piece`**: An enumeration for all possible track pieces, including `EMPTY`, straights, corners, switches, dynamic switches, and tunnels. The naming convention for switches (`SWITCH_<Single>_<Straight>_<Curve>`) describes the connections from the perspective of the "single" entry point.
-   **Type Aliases**: `Pos`, `TrainStart`, `TunnelPair`, etc., are tuples that structure related data, like a train's starting coordinates and initial direction.

### Input Data

These arrays are populated by the `.dzn` data file and represent the specific layout of the puzzle.

-   `TRAINS`: An array storing the starting `(row, col, initial_exit_dir)` for each train.
-   `INIT_POS`: An array of pre-placed track pieces.
-   `TUNNEL_PAIRS`: Defines the connections between tunnel entrances and exits, including their locations and the exit directions.
-   `GATES`, `ACTIVATIONS`, `DSWITCHES`: Define the locations and IDs of dynamic elements on the grid.

### Helper Constants and Predicates

-   `dr`, `dc`: Arrays that map a `Dir` to a row or column change (e.g., `dr[TOP]` is -1).
-   `opposite`: An array that maps a `Dir` to its opposite (e.g., `opposite[LEFT]` is `RIGHT`).
-   `set of Piece`: Various sets (`STRAIGHTS`, `CORNERS`, etc.) are defined to make constraints more concise (e.g., `p in CORNERS`).
-   `in_bounds(r, c)`: A predicate that checks if a given `(r, c)` coordinate is within the grid.

### Tunnel Lookup Arrays

To improve solver performance, the model pre-computes the destination and exit direction for every tunnel cell.
-   `tunnel_dest[r, c]`: If `(r, c)` is a tunnel entrance, this 2D array stores the `(row, col)` of the corresponding tunnel exit. Otherwise, it's `(0,0)`.
-   `tunnel_exit_dir[r, c]`: Stores the integer value of the exit direction for the destination tunnel.

### Piece Routing Tables

These tables define the core logic of how trains move through different track pieces.

-   **`can_enter[piece, dir]`**: A boolean table that is `true` if a train can legally enter a given `piece` from a given `dir`. For example, `can_enter[STRAIGHT_TD, RIGHT]` is `false`.
-   **`can_exit[piece, dir]`**: A boolean table that is `true` if a track `piece` has a physical connection pointing in `dir`. This is primarily used to validate the first move of a train from its starting tile.
-   **`exit_of[piece, entry_dir]`**: The main routing table. For a given `piece` and `entry_dir`, it returns the corresponding `exit_dir`. For example, `exit_of[CORNER_TR, TOP]` returns `RIGHT`.

### Dynamic DSWITCH Routing (`dswitch_exit` function)

Dynamic switches (DSWITCHes) can change their connections. This function calculates the correct exit direction for a DSWITCH based on its `is_swapped` state.
-   If `is_swapped` is `false`, it behaves like a normal switch and uses the `exit_of` table.
-   If `is_swapped` is `true`, the "single" and "straight" paths are swapped. The function contains the hardcoded logic for this swapped behavior for each DSWITCH type.

### Decision Variables

These are the unknowns that the MiniZinc solver will find values for.

-   `grid[1..H, 1..W]`: A 2D array of `var Piece`, representing the final track layout. This is the primary variable.
-   `train_row[t, time]`, `train_col[t, time]`: 2D arrays storing the `(row, col)` position of each train `t` at each `time` step.
-   `train_dir[t, time]`: A 2D array storing the direction from which train `t` *entered* its cell at `time`.
-   `arrival_time[t]`: The time step at which train `t` first reaches the `TARGET`.
-   `gate_open[g, time]`: A boolean array indicating if gate `g` is open at `time`.
-   `dswitch_swapped[ds, time]`: A boolean array indicating if dynamic switch `ds` is in its "swapped" state at `time`.

---

## 3. Constraints

Constraints are the rules that define a valid solution.

1.  **Initial Positions**: At `time = 0`, every train is at its starting location as defined in the `TRAINS` array.
2.  **First Movement**: The first move (`time = 1`) is determined by the train's initial exit direction. The move is only valid if the starting piece `can_exit` in that direction and the destination piece `can_enter` from the opposite direction. If the destination is blocked by a closed gate, the train stays put.
3.  **Subsequent Movements**: For all subsequent time steps, a train's next position is determined by its current position and the track piece on it.
    -   If at the `TARGET`, the train stays there.
    -   Otherwise, the model calculates the `exit_dir` based on the piece type (using `exit_of` for static pieces and `dswitch_exit` for dynamic ones).
    -   If the piece is a `TUNNEL`, the train teleports to the destination defined in `tunnel_dest`.
    -   If the calculated next cell is blocked by a closed gate, the train waits in its current cell.
    -   Otherwise, it moves to the next cell.
4.  **Arrival Ordering**: Trains must arrive at the `TARGET` sequentially. `arrival_time[t] < arrival_time[t+1]`. Once a train arrives, it stays at the target for all subsequent time steps.
5.  **Collision Avoidance**: At any given `time`, no two trains can be in the same cell, unless that cell is the `TARGET`.
6.  **Position Swaps**: Prevents two trains from "passing through" each other by swapping cells in a single time step (e.g., train A moves from cell X to Y while train B moves from Y to X). This is allowed if one of the cells involved is the `TARGET`.
7.  **Pre-placed Pieces**: The `grid` must respect the pieces defined in `INIT_POS`.
8.  **Tunnel Placement**: The `grid` must have the correct `TUNNEL` pieces at the locations defined in `TUNNEL_PAIRS`.
9.  **Track Budget**: The total number of non-`EMPTY` pieces placed on the grid (excluding pre-placed pieces and tunnels) cannot exceed `MAX_TRACKS`.
10. **Connectivity**: Ensures that complex pieces (corners, switches) are placed logically. Each of their entry points must connect to an adjacent non-`EMPTY` piece that can accept a train from that direction.
11. **Restricted Placement**: `TUNNEL` and `DSWITCH` pieces can only be placed at locations explicitly defined in the `TUNNEL_PAIRS` and `DSWITCHES` input arrays, respectively. This prevents the solver from placing them arbitrarily.

### Gate and Activation Constraints

12. - 16. **Validation**: These constraints ensure that gates and activations are placed on valid track types (not `EMPTY`, not on top of each other, etc.).
17. **Initial Gate States**: At `time = 0`, each gate's state (`open` or `closed`) is set from the input data.
18. **Initial Position Safety**: A train cannot start on a tile that has a closed gate.
19. **Gate State Transitions**: A gate toggles its state (`open` -> `closed` or vice-versa) at `time+1` if a train *enters* a linked activation cell at `time`. An entry is defined as the train being at the activation cell at the current time but not at the previous time.
20. **Gate Blocking**: A train can only be on a cell with a gate if the gate is open at that time.

### DSWITCH Constraints

21. - 22. **Validation**: Dynamic switches must be pre-placed and cannot share a cell with a gate or activation.
23. **Initial DSWITCH States**: At `time = 0`, all dynamic switches are in their normal (non-swapped) state.
24. **DSWITCH State Transitions**: Similar to gates, a DSWITCH toggles its `swapped` state at `time+1` if a train enters a linked activation cell at `time`. All DSWITCHes with the same ID toggle simultaneously.

---

## 4. Solve and Output

### Optimization

-   **`piece_cost`**: An array that assigns an integer cost to each piece type. Straights cost 1, corners 2, and switches 3. Fixed pieces like tunnels and DSWITCHes have a cost of 0.
-   **`solve minimize total_cost;`**: This is the objective function. It instructs the solver to find a solution that satisfies all constraints while minimizing the sum of costs of all pieces in the `grid`. This encourages solutions with simpler, "cheaper" tracks.

### Output

The model is configured to produce several outputs:
-   A 2D text representation of the solved `grid`.
-   The `total_cost` of the solution.
-   The arrival time of the last train.
-   A step-by-step path `(row, col)` for each train from its start to the target.
-   A JSON object for use with `vis.mzn`, which can render the solution in a web-based visualizer (`viz.html`).
