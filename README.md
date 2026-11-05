# Railbound Constraint Programming Solver

![Railbound Cover](docs/cover.jpg)

This repository contains a MiniZinc-based solver for the puzzle game [Railbound](https://afterburn.games/railbound/). It treats each puzzle as a constraint satisfaction problem: every piece of track, switch, or gate is represented as a decision variable, and the solver searches the space of legal assignments to produce a valid route for each train. The goal of the project is to capture the full set of mechanics found in the main campaign while keeping the model readable for people learning constraint programming.

## Solver Coverage

- 12 main-line levels are tracked in this project.
- Levels 1–9 are currently solved automatically; levels 10–12 are work in progress.
- Instances for solved levels live in `data/` as ready-to-run MiniZinc data files.

![Gameplay Preview](docs/game.gif)

### Level Feature Map

| Level | Key Mechanics                               | Solver Status |
| ----- | ------------------------------------------- | ------------- |
| 1     | Straights, curves, basic switches           | ✅ solved     |
| 2     | Tunnels                                     | ✅ solved     |
| 3     | Activation tiles, timed gates               | ✅ solved     |
| 4     | Dynamic switches (`DSWITCH`)                | ✅ solved     |
| 5     | Stations with enforced dwell times          | ✅ solved     |
| 6     | Exit-triggered switches (`ESWITCH`)         | ✅ solved     |
| 7     | Decoy cars that must be delayed or rerouted | ✅ solved     |
| 8     | Large-grid search stress test               | ✅ solved     |
| 9     | Semaphores (three-way stop tile)            | ✅ solved     |
| 10    | Semaphores (three-way stop tile)            | ⏳ modeling   |
| 11    | Two target locations (dual goals)           | ⏳ modeling   |
| 12    | Two target locations (dual goals)           | ⏳ modeling   |

## Mechanics Modeled

**Track placement** – Straights, curves, and switches are modeled with finite-domain variables that encode both geometry and orientation. Capacity constraints ensure no two trains attempt to occupy the same segment simultaneously.

**Train movement** – A discrete time horizon tracks every train. Sequential arrival rules are enforced by ordering constraints so that cars couple with the locomotive in the intended order.

**Switch logic** – Deterministic switches route by entry side. Dynamic switches (`DSWITCH`) flip when an activation tile of their group is entered; exit-triggered switches (`ESWITCH`, the game's switch rails) flip each time a vehicle arrives on them. A vehicle keeps the exit it was given when it entered a cell, even if the switch flips while it waits there.

**Gates and activators** – Gates listen to activation tiles that flip after a train crosses them. Timing constraints ensure a gate is open when a train reaches it and closed otherwise.

**Stations** – Stations are indexed as `(row, col, train_id)`. Each train must visit all assigned stations before termination and incurs a two-step dwell time the first time it arrives at any of its stations.

**Tunnels** – Driving into a tunnel mouth puts the vehicle directly on the paired tunnel tile, facing out of it; the next step leaves through that mouth.

**Decoys** – Decoy cars follow the track like trains but never need to arrive. A decoy whose track runs out, leaves the board, or whose next cell is taken by another car crashes and stays where it is for the rest of the run (it waits, rather than crashing, at closed gates and semaphores). Decoys may never reach the target, and nothing they do after the last train has arrived matters.

**Semaphores** – Placed on straights or corners (some levels also pre-place them). A semaphore starts closed, so a car about to enter it waits in front of it. It opens for good once, while a car is waiting at it, another car stands on the cell at its other end without heading into it.

**Dual targets** – Some levels require trains to reach two distinct destination locations. Feasibility requires satisfying both targets; the model enforces completion only when all assigned trains have visited both goal tiles in the required order (if any).

## Repository Layout

- `main.mzn` – Entry point: input parameters, decision variables, and the shared per-cell state (effective switch routing, blocked cells).
- `lib/types.mzn` – `Dir` / `Piece` enums and piece-category sets.
- `lib/globals.mzn` – Parameter lookup tables (cell indexing, neighbours, tunnels, routing tables, switch toggles).
- `constraints/` – One file per mechanic: grid, trains, decoys, activations, eswitches, semaphores, stations.
- `formatting.mzn` – Solution output (board, track usage, and train/decoy paths).
- `data/` – MiniZinc `.dzn` instances for each campaign puzzle currently modeled.
- `convert_levels.py` – Converts the legacy `levels.json` dump into `.dzn` files.
- `scripts/solve.py` – Runs both search orders in parallel and prints the first solution.
- `cpsat/railbound_cpsat.py` – OR-Tools CP-SAT solver (same model, Boolean encoding).
- `scripts/crosscheck_cpp.py` – Checks that every board found by the RailboundSolver C++ simulator is accepted by this model.
- `images/` – Static artwork shipped with the project (used in documentation).
- `docs/` – Reference assets such as the cover image and gameplay animation embedded above.
- `viz.html` – Lightweight viewer that turns solver output into an interactive grid.
- `project.mzp` – MiniZinc project file capturing IDE configuration for this workspace.

### Encoding notes

Board cells are addressed by a single row-major index `cell(r, c) = (r - 1) * W + c`, so each vehicle has one position variable per timestep. Collision, swap, station, and activation checks are single integer comparisons, and moving to the next cell (including tunnel teleports) is one lookup in the precomputed `move_cell` / `move_entry` tables. Switch toggles and gate/semaphore blocking are computed once per cell and timestep and shared by every train and decoy.

`main.mzn` offers two search orders: `SEARCH=1` (train-major: earliest arrivals, then each train's route in turn) and `SEARCH=2` (time-major: all trains advance together one step at a time, nearest-to-target cell first). Neither wins everywhere, so `scripts/solve.py` races both. On the 181 bundled levels (Chuffed, 60 s limit) the portfolio solves 173.

## Installation

1. Install the latest [MiniZinc bundle](https://www.minizinc.org/software.html). It ships with the command-line tools, the MiniZinc IDE, and the Chuffed and OR-Tools CP-SAT solvers.
2. Clone the repository and ensure the `minizinc` executable is on your `PATH`.
   ```bash
   git clone https://github.com/your-user/railbound_cp.git
   cd railbound_cp
   ```

## Running The Solver

If you're crafting your own `.dzn` instances, see the data schema in [docs/data_format.md](docs/data_format.md).

**CLI**

- Choose a data file from `data/` (for example `data/8/8-1.dzn`).
- Run MiniZinc with your preferred backend:
  ```bash
  minizinc --solver chuffed main.mzn data/8/8-1.dzn
  ```
- Or race both search orders and keep the first answer (recommended):
  ```bash
  python scripts/solve.py data/8/8-1.dzn --time-limit 60
  ```
  A single order can be chosen with `-D "SEARCH=2;"` on the plain `minizinc` command.
- The output shows the solved board, track usage, and each train's path as `(row,col)` cells. Add `--output-mode json` to get the raw decision variables (e.g. for `viz.html`).

**CP-SAT (fastest)**

`cpsat/railbound_cpsat.py` is a Boolean port of the same model for Google OR-Tools CP-SAT (`pip install ortools`). It reads the same `.dzn` files:
```bash
python cpsat/railbound_cpsat.py data/8/8-1.dzn --time-limit 60 --workers 4
```
On the 181 bundled levels (4 workers, 60 s per level) it solves 176, versus 173 for the MiniZinc portfolio. Its solutions are accepted by `main.mzn`, and it accepts the boards found by the RailboundSolver C++ simulator. `--pin board.json` checks a given board, `--json` prints machine-readable output, and `--deepen` tries shorter horizons first.

**MiniZinc IDE**

- Launch the MiniZinc IDE and open `project.mzp`.
- Select a solver configuration (Chuffed is the project default; OR-Tools CP-SAT also works well).
- Press Run and choose a data file when prompted.

![Example visualization](docs/viz.gif)

Solver performance depends on the level size: levels 1–7 typically solve in under a second, while level 8 requires broader search and may take up to a minute on laptop hardware.

## Contributing

The mechanics follow the reference simulator of [FoxtrotOnce/RailboundSolver](https://github.com/FoxtrotOnce/RailboundSolver): every board its C++ solver finds for the bundled levels is accepted by this model. `scripts/crosscheck_cpp.py` re-runs that check (it needs a built copy of that solver). Level data is generated from its `levels.json` with `python convert_levels.py -f --keep-max-time -j path/to/levels.json`, which keeps the hand-tuned `MAX_TIME` horizons.

Open an issue or discussion thread if you spot a mechanic that is not yet captured. Pull requests that improve the MiniZinc model, add tests, or document the remaining four levels are welcome.

## Similar Work

[FoxtrotOnce/RailboundSolver](https://github.com/FoxtrotOnce/RailboundSolver) is a logic-driven solver that aims to compute optimal Railbound layouts and is currently being integrated into a public website frontend. Its documentation includes a detailed program flowchart, and many of the visuals in this project appear courtesy of [FoxtrotOnce](https://github.com/FoxtrotOnce).
