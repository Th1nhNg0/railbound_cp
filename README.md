# Railbound Constraint Programming Solver

![Railbound Cover](cover.jpg)

This project provides a robust solver for the delightful puzzle game [Railbound](https://afterburn.games/railbound/), built using the power of **Constraint Programming** with [MiniZinc](https://www.minizinc.org/). It can automatically find valid track layouts for even the most complex puzzles.

![Gameplay Preview](game.gif)

## About The Project

Railbound's gameplay, which involves laying a limited number of tracks to connect train cars to a locomotive, is a natural fit for a Constraint Satisfaction Problem (CSP). This solver models the game's rules, mechanics, and objectives as a set of mathematical constraints. A MiniZinc solver then explores the vast space of possible track layouts to find a working solution.

This repository is a comprehensive resource for anyone interested in constraint programming, puzzle solving, or the technical details of Railbound's mechanics.

## Features

- **Complete Mechanic Support**: Models all major game mechanics, including straights, corners, tunnels, gates, stations, and all variants of stateful switches (dynamic and exit-triggered).
- **Automated Solving**: Finds valid solutions for 100+ puzzles from the game.
- **Efficient Search**: Utilizes an optimized search strategy that prioritizes grid layout to prune the search space effectively.
- **Extensible Data Format**: Puzzles are defined in simple `.dzn` data files, making it easy to add new ones.
- **Tooling for Development**: Includes scripts for converting legacy puzzle formats and for running comprehensive benchmarks to test solver performance.
- **Cross-Platform**: Works on any system with MiniZinc installed, with benchmark scripts for both Bash (Linux/macOS) and PowerShell (Windows).

## Setup and Installation

To get the solver up and running, you need to install the MiniZinc IDE, which includes the command-line toolchain.

1.  **Download MiniZinc**: Go to the [official MiniZinc download page](https://www.minizinc.org/software.html) and download the IDE bundle for your operating system (Windows, macOS, or Linux).

2.  **Install MiniZinc**: Follow the installation instructions for your system.

3.  **Add MiniZinc to PATH**: Ensure the `minizinc` command-line tool is accessible from your terminal. The installer usually handles this, but you can verify by opening a terminal and running:
    ```bash
    minizinc --version
    ```
    If the command is not found, you may need to add the MiniZinc binary directory to your system's `PATH` environment variable manually.

4.  **Clone the Repository**:
    ```bash
    git clone https://github.com/your-username/railbound-cp.git
    cd railbound-cp
    ```

You are now ready to solve some puzzles!

## How to Run the Solver

### Solving a Single Puzzle

You can solve any individual puzzle by running `minizinc` from the command line, specifying a solver, the main model file (`main.mzn`), and a puzzle data file (`.dzn`).

```bash
# Basic solving with the Gecode solver
minizinc --solver gecode main.mzn data/1/1-1.dzn

# Using a more powerful solver like CP-SAT with parallel processing (recommended)
minizinc --solver cp-sat -p 8 main.mzn data/3/3-5.dzn

# Setting a time limit (e.g., 30 seconds)
minizinc --solver cp-sat -p 8 --time-limit 30000 main.mzn data/8/8-12.dzn
```
The solution, if found, will be printed to the console as an ASCII art grid and a list of train paths.

### Visualizing the Solution

The `viz.html` file provides an interactive, graphical visualization of the solution output.

1.  Run the solver and pipe the output to a text file:
    ```bash
    minizinc --solver cp-sat main.mzn data/1/1-1.dzn > solution.txt
    ```
2.  Open `viz.html` in your web browser.
3.  Click the "Load Solution from File" button and select `solution.txt`.
4.  The grid and train paths will be rendered visually.

### Running Benchmarks

This repository includes powerful benchmark scripts to test the solver's performance across many puzzles.

**For Linux/macOS (Bash):**
```bash
# Run on all levels with the default solver (cp-sat)
./run_benchmarks.sh

# Run on specific levels (e.g., worlds 1 and 2) with the 'gecode' solver
./run_benchmarks.sh -l "1,2" -s gecode
```

**For Windows (PowerShell):**
```powershell
# Run on all levels with the default solver (cp-sat)
.\run_benchmarks.ps1

# Run on specific levels (e.g., worlds 1 and 2) with the 'gecode' solver
.\run_benchmarks.ps1 -Levels "1,2" -Solver gecode
```
These scripts generate timestamped CSV and summary files in the `benchmark_results/` directory.

## How It Works: The CSP Model

The solver is built around a central Constraint Satisfaction Problem (CSP) model defined in MiniZinc. Here is a high-level overview:

#### Decision Variables

The solver's goal is to find values for these key variables:
-   `grid[H, W]`: A 2D array representing the puzzle grid. Each cell is a variable that can be assigned a `Piece` enum (e.g., `CORNER_TR`, `STRAIGHT_TD`).
-   `train_row[T, I]`, `train_col[T, I]`: The row and column of each train `T` at each timestep `I`.
-   `train_dir[T, I]`: The direction of each train `T` at each timestep `I`.
-   `arrival_time[T]`: The timestep when each train `T` reaches the target.
-   Stateful variables for mechanics like `gate_open`, `dswitch_swapped`, etc., tracked over time.

#### Core Constraints

The game's rules are enforced through constraints:
-   **Capacity**: The number of placed tracks cannot exceed `MAX_TRACKS`.
-   **Scheduling & Pathfinding**: Defines how trains move from one cell to the next based on the track piece, direction, and any special mechanics (tunnels, switches). This is the heart of the simulation.
-   **Collision**: No two trains can occupy the same cell at the same time.
-   **Connectivity**: A train can only move between two cells if the track pieces in them connect correctly.
-   **Mechanics**: Dedicated constraints for gates, stations, and stateful switches ensure they behave as they do in the game.

#### Search Strategy

Finding a solution can be slow without guidance. The `main.mzn` model uses a two-phase search strategy to improve performance:
1.  **Solve for the `grid` first**: The model prioritizes determining the layout of the track pieces. This is the most constrained part of the problem, and finding a valid layout first dramatically reduces the search space for the train paths.
2.  **Solve for `arrival_time` next**: Once the grid is set, finding the train schedules is much simpler.

## Project Structure

The repository is organized to separate the model, constraints, data, and tooling.

```
.
├── main.mzn                # The main MiniZinc model entry point.
├── lib/                    # Core library files for the model.
│   ├── types.mzn           # Defines all enums (Piece, Dir) and type aliases.
│   ├── globals.mzn         # Pre-computes lookup tables (e.g., tunnel destinations, routing).
│   └── predicates.mzn      # Defines helper functions and predicates (e.g., in_bounds).
├── constraints/            # Modules containing specific game rule constraints.
│   ├── capacity.mzn        # Limits on placeable tracks.
│   ├── collision.mzn       # Prevents trains from crashing.
│   ├── scheduling.mzn      # Governs train movement and pathfinding.
│   └── ...                 # (gates.mzn, stations.mzn, etc.)
├── data/                   # Puzzle data files, organized by world.
│   └── 1/
│       ├── 1-1.dzn
│       └── ...
├── output/                 # Contains the output formatting logic.
│   └── formatting.mzn
├── util/                   # Utility and helper scripts.
│   └── convert_levels.py   # Converts levels from a legacy JSON format to .dzn.
├── run_benchmarks.sh       # Benchmark script for Linux/macOS.
├── run_benchmarks.ps1      # Benchmark script for Windows.
├── viz.html                # Tool for visualizing solution files.
└── README.md               # This file.
```

## Data Format (`.dzn` files)

Puzzles are defined in `.dzn` (MiniZinc data) files. The format is human-readable and easy to edit. See the existing files in `data/` for examples. The key parameters are detailed in `main.mzn` and `lib/types.mzn`.

## Utilities

### `convert_levels.py`

This Python script is used to convert puzzle data from an old JSON format (used by a previous solver) into the `.dzn` format used by this project. It is located in the `util/` directory and contains all the necessary logic to map old piece and modifier codes to the new enum-based system.

**Usage:**
```bash
python util/convert_levels.py --json-path /path/to/levels.json
```

## Contributing

Contributions are welcome! Here are some ways you can help:
-   **Add New Puzzles**: If you find puzzles that are missing, you can create a new `.dzn` file for them in the appropriate `data/<world>/` directory.
-   **Improve the Model**: Can you think of a better constraint or a faster search strategy? Feel free to experiment and submit a pull request.
-   **Enhance Documentation**: If something is unclear, improving the documentation is a great way to contribute.

To test your changes, run the solver on a relevant puzzle:
`minizinc --solver gecode main.mzn data/<world>/your-puzzle.dzn`

## Roadmap

- [ ] Add remaining puzzle levels from all worlds.
- [ ] Further optimize the model and search strategy for speed.
- [ ] Create a more integrated visualization tool.

## License

This is an educational project created for fun. Railbound is a trademark of [Afterburn](https://afterburn.games/).