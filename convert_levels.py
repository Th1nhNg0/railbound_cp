#!/usr/bin/env python3
"""Converts puzzle levels from a legacy JSON format to the MiniZinc `.dzn` format.

This script reads level data from a `levels.json` file, which was used by a
previous brute-force solver, and transforms it into the structured `.dzn` data
files required by the MiniZinc constraint programming model.

It handles the mapping of various numeric codes from the JSON to their
corresponding MiniZinc enumeration types for tracks, switches, tunnels, and
other game mechanics.

The script can be run to convert all levels or only those that do not yet
exist in the target `data/` directory.

Usage:
  python convert_levels.py [--force]

Options:
  --force    Force conversion of all levels, overwriting existing `.dzn` files.
             By default, the script only converts levels that are missing.
"""

import argparse
import json
import sys
from pathlib import Path
from typing import Dict, Any, Tuple, List

# ============================================================
# MAPPINGS FROM JSON TO MINIZINC
# ============================================================

# Mapping from old board integer values to MiniZinc `Piece` enum strings.
# Based on the enums in the original solver's `classes.ts` and reverse-engineered
# from existing `.dzn` files.
BOARD_TO_TRACK: Dict[int, str | None] = {
    0: None,  # ROCK - Not placed initially, solver determines this.
    1: "STRAIGHT_RL",  # HORIZONTAL_TRACK
    2: "STRAIGHT_TD",  # VERTICAL_TRACK
    3: "STRAIGHT_RL",  # CAR_ENDING_TRACK_RIGHT - The target cell.
    4: "ROCK",  # ROADBLOCK - Explicitly an empty, impassable cell.
    5: "CORNER_DR",  # BOTTOM_RIGHT_TURN
    6: "CORNER_DL",  # BOTTOM_LEFT_TURN
    7: "CORNER_TR",  # TOP_RIGHT_TURN
    8: "CORNER_TL",  # TOP_LEFT_TURN
    9: "SWITCH_L_R_D",  # BOTTOM_RIGHT_LEFT_3WAY
    10: "SWITCH_T_D_R",  # BOTTOM_RIGHT_TOP_3WAY
    11: "SWITCH_L_R_D",  # BOTTOM_LEFT_RIGHT_3WAY
    12: "SWITCH_T_D_L",  # BOTTOM_LEFT_TOP_3WAY
    13: "SWITCH_L_R_T",  # TOP_RIGHT_LEFT_3WAY
    14: "SWITCH_D_T_R",  # TOP_RIGHT_BOTTOM_3WAY
    15: "SWITCH_R_L_T",  # TOP_LEFT_RIGHT_3WAY
    16: "SWITCH_D_T_L",  # TOP_LEFT_BOTTOM_3WAY
    17: "TUNNEL_L",  # LEFT_FACING_TUNNEL
    18: "TUNNEL_R",  # RIGHT_FACING_TUNNEL
    19: "TUNNEL_D",  # DOWN_FACING_TUNNEL
    20: "TUNNEL_T",  # UP_FACING_TUNNEL (Note: 'U' becomes 'T')
    21: "STRAIGHT_RL",  # NCAR_ENDING_TRACK_RIGHT
    22: "STRAIGHT_RL",  # NCAR_ENDING_TRACK_LEFT
    29: "STRAIGHT_RL",  # CAR_ENDING_TRACK_LEFT
    30: "STRAIGHT_TD",  # CAR_ENDING_TRACK_DOWN
    31: "STRAIGHT_TD",  # CAR_ENDING_TRACK_UP
    34: "ROCK",  # STATION_ROCK - Empty space near a station.
    35: "ROCK",  # ANOTHER_STATION_ROCK
    36: "ROCK",  # ANOTHER_STATION_ROCK
    37: "ROCK",  # ANOTHER_STATION_ROCK
}

# Mapping from old `mods` integer values to their semantic meaning.
# Based on the `Mod` enum in `classes.ts`.
MOD_SWITCH = 1
MOD_TUNNEL = 2
MOD_CLOSED_GATE = 3
MOD_OPEN_GATE = 4
MOD_SWAPPING_TRACK = 5  # Corresponds to DSWITCH
MOD_STATION = 6
MOD_SWITCH_RAIL = 7  # Corresponds to ESWITCH
MOD_STARTING_CAR = 10

# Mapping from JSON direction strings to MiniZinc `Dir` enum strings.
DIRECTION_MAP: Dict[str, str] = {
    "RIGHT": "RIGHT",
    "LEFT": "LEFT",
    "UP": "TOP",
    "DOWN": "DOWN",
}

# Mapping from tunnel piece values to their corresponding exit direction.
# In MiniZinc, `TUNNEL_X` implies a train can enter from direction `X`. The
# exit direction from the *other* end of the tunnel pair is defined by this.
TUNNEL_DIR: Dict[int, str] = {
    17: "LEFT",
    18: "RIGHT",
    19: "DOWN",
    20: "TOP",
}


def convert_level(level_name: str, level_data: Dict[str, Any]) -> str:
    """Converts a single level from JSON to a MiniZinc .dzn data string.

    Args:
        level_name: The name of the level (e.g., "1-1").
        level_data: The dictionary containing the raw level data from JSON.

    Returns:
        A string containing the complete, formatted .dzn file content.

    Raises:
        KeyError: If essential keys are missing from the level data.
        ValueError: If a target cell cannot be found.
    """
    # Extract data from the JSON structure
    board: List[List[int]] = level_data["board"]
    mods: List[List[int]] = level_data["mods"]
    mod_nums: List[List[int]] = level_data["mod_nums"]
    cars: List[Dict[str, Any]] = level_data["cars"]
    tracks: int = level_data["tracks"]

    H = len(board)
    W = len(board[0]) if H > 0 else 0

    # --- Find Target Cell ---
    target: Tuple[int, int] | None = None
    for r, row in enumerate(board):
        for c, val in enumerate(row):
            if val == 3:  # `3` is the ending track value
                target = (r + 1, c + 1)  # Convert to 1-based indexing
                break
        if target:
            break
    if not target:
        raise ValueError(f"No target found for level {level_name}")

    # --- Collect Train and Decoy Information ---
    trains: List[Tuple[int, int, str]] = []
    decoys: List[Tuple[int, int, str]] = []
    for car in cars:
        if car["type"] == "NORMAL":
            r, c = car["pos"]
            direction = DIRECTION_MAP[car["direction"]]
            trains.append((r + 1, c + 1, direction))  # 1-based indexing
        elif car["type"] == "DECOY":
            r, c = car["pos"]
            direction = DIRECTION_MAP[car["direction"]]
            decoys.append((r + 1, c + 1, direction))  # 1-based indexing

    # --- Process Grid for Initial Pieces and Switches ---
    init_pos: List[Tuple[int, int, str]] = []
    dswitches: List[Tuple[int, int, int]] = []

    for r, row in enumerate(board):
        for c, board_val in enumerate(row):
            mod_val = mods[r][c]

            # Tunnels are handled separately via TUNNEL_PAIRS
            if mod_val == MOD_TUNNEL:
                continue

            track_type = BOARD_TO_TRACK.get(board_val)
            if track_type is None:
                continue  # Skip empty cells that are not explicitly defined roadblocks

            # Handle stateful switches (DSWITCH/ESWITCH)
            is_dswitch = mod_val == MOD_SWAPPING_TRACK
            is_eswitch = mod_val == MOD_SWITCH_RAIL

            if (is_dswitch or is_eswitch) and track_type.startswith("SWITCH_"):
                if is_dswitch:
                    track_type = track_type.replace("SWITCH_", "DSWITCH_")
                else:  # is_eswitch
                    track_type = track_type.replace("SWITCH_", "ESWITCH_")

                # Register the DSwitch with its ID for state tracking
                mod_num = mod_nums[r][c]
                if mod_num > 0:
                    dswitches.append((r + 1, c + 1, mod_num))

            init_pos.append((r + 1, c + 1, track_type))

    # --- Collect and Pair Tunnels ---
    tunnel_pairs: List[Tuple[int, int, str, int, int, str]] = []
    tunnel_endpoints: Dict[int, List[Tuple[Tuple[int, int], int]]] = {}

    for r, row in enumerate(board):
        for c, board_val in enumerate(row):
            if mods[r][c] == MOD_TUNNEL and board_val in TUNNEL_DIR:
                tunnel_num = mod_nums[r][c]
                pos = (r + 1, c + 1)
                if tunnel_num not in tunnel_endpoints:
                    tunnel_endpoints[tunnel_num] = []
                tunnel_endpoints[tunnel_num].append((pos, board_val))

    for tunnel_num in sorted(tunnel_endpoints.keys()):
        endpoints = tunnel_endpoints[tunnel_num]
        if len(endpoints) == 2:
            (r1, c1), val1 = endpoints[0]
            (r2, c2), val2 = endpoints[1]
            exit_dir_A = TUNNEL_DIR[val1]  # Exit direction from B to A
            exit_dir_B = TUNNEL_DIR[val2]  # Exit direction from A to B
            tunnel_pairs.append((r1, c1, exit_dir_A, r2, c2, exit_dir_B))

    # --- Collect Gates and Activations ---
    gates: List[Tuple[int, int, int, str]] = []
    activations: List[Tuple[int, int, int]] = []

    for r, row in enumerate(mods):
        for c, mod_val in enumerate(row):
            mod_num = mod_nums[r][c]
            if mod_val in (MOD_CLOSED_GATE, MOD_OPEN_GATE):
                is_open = str(mod_val == MOD_OPEN_GATE).lower()
                gates.append((r + 1, c + 1, mod_num, is_open))
            elif mod_val == MOD_SWITCH and mod_num > 0:
                activations.append((r + 1, c + 1, mod_num))

    # --- Collect Stations ---
    stations: List[Tuple[int, int, int]] = []
    for r, row in enumerate(mods):
        for c, mod_val in enumerate(row):
            if mod_val == MOD_STATION:
                # JSON train IDs are 0-based, MiniZinc are 1-based
                minizinc_train_id = mod_nums[r][c] + 1
                stations.append((r + 1, c + 1, minizinc_train_id))

    # --- Assemble .dzn Content ---
    lines = [
        f"W={W};",
        f"H={H};",
        "",
        "MAX_TIME=W*H;",
        f"MAX_TRACKS={tracks};",
        "",
        f"TARGET=({target[0]},{target[1]});",
        "",
    ]

    # Format trains
    if trains:
        trains_str = ",".join([f"({r},{c},{d})" for r, c, d in trains])
        lines.append(f"TRAINS=[{trains_str}];")
    else:
        lines.append("TRAINS=[];")

    # Format decoys
    if decoys:
        decoys_str = ",".join([f"({r},{c},{d})" for r, c, d in decoys])
        lines.append(f"DECOYS=[{decoys_str}];")
    else:
        lines.append("DECOYS=[];")

    lines.append("")

    if init_pos:
        lines.append("INIT_POS=[")
        for r, c, track in init_pos:
            lines.append(f"({r},{c},{track}),")
        lines.append("];")
    else:
        lines.append("INIT_POS=[];")

    if tunnel_pairs:
        lines.append("TUNNEL_PAIRS=[")
        for r1, c1, entry, r2, c2, exit_dir in tunnel_pairs:
            lines.append(f"  ({r1}, {c1}, {entry}, {r2}, {c2}, {exit_dir}),")
        lines.append("];")
    else:
        lines.append("TUNNEL_PAIRS=[];")

    lines.append("")

    if gates:
        lines.append("GATES=[")
        for r, c, num, is_open in gates:
            lines.append(f"({r},{c},{num},{is_open}),")
        lines.append("];")
    else:
        lines.append("GATES=[];")

    if activations:
        lines.append("ACTIVATIONS=[")
        for r, c, num in activations:
            lines.append(f"({r},{c},{num}),")
        lines.append("];")
    else:
        lines.append("ACTIVATIONS=[];")

    lines.append("")

    if dswitches:
        lines.append("DSWITCHES=[")
        for r, c, num in dswitches:
            lines.append(f"({r},{c},{num}),")
        lines.append("];")
    else:
        lines.append("DSWITCHES=[];")

    if stations:
        lines.append("STATIONS=[")
        for r, c, train_id in stations:
            lines.append(f"  ({r},{c},{train_id}),")
        lines.append("];")
    else:
        lines.append("STATIONS=[];")

    return "\n".join(lines) + "\n"


def main():
    """Main execution function to parse arguments and convert levels."""
    parser = argparse.ArgumentParser(
        description="Convert levels from levels.json to MiniZinc .dzn format.",
        formatter_class=argparse.RawTextHelpFormatter,
        epilog="""
Examples:
  python convert_levels.py           # Convert only missing levels
  python convert_levels.py --force   # Force convert all levels
        """,
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Force conversion, overwriting existing .dzn files.",
    )
    parser.add_argument(
        "--json-path",
        type=Path,
        default="levels.json",
        help="Path to the input levels.json file.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default="data",
        help="Directory to save the output .dzn files.",
    )
    parser.add_argument(
        "--level-prefix",
        type=str,
        help="Only convert levels with names starting with this prefix (e.g., '6-', '7-1').",
    )
    args = parser.parse_args()

    # Load levels.json
    if not args.json_path.exists():
        print(
            f"Error: Input JSON file not found at '{args.json_path}'", file=sys.stderr
        )
        sys.exit(1)

    with open(args.json_path, "r") as f:
        levels = json.load(f)

    if args.level_prefix:
        print(
            f"{'Force converting' if args.force else 'Converting missing'} levels with prefix '{args.level_prefix}'..."
        )
    else:
        print(
            f"{'Force converting' if args.force else 'Converting missing'} all levels..."
        )

    converted = 0
    skipped_prefix = 0
    skipped_existing = 0

    base_output_dir = args.output_dir

    for level_name, level_data in sorted(levels.items()):
        if level_name.startswith("#"):
            # These are comments or disabled levels in the source JSON
            continue

        if args.level_prefix and not level_name.startswith(args.level_prefix):
            skipped_prefix += 1
            continue

        try:
            world = level_name.split("-")[0]
            output_dir = base_output_dir / world
            output_dir.mkdir(parents=True, exist_ok=True)

            output_path = output_dir / f"{level_name}.dzn"

            # Skip if file exists and not forcing
            if not args.force and output_path.exists():
                skipped_existing += 1
                continue

            dzn_content = convert_level(level_name, level_data)
            output_path.write_text(dzn_content)
            converted += 1
            if converted > 0 and converted % 10 == 0:
                print(f"  Converted {converted} levels...")
        except Exception as e:
            print(f"Error converting {level_name}: {e}", file=sys.stderr)

    print("\nConversion complete!")
    print(f"  Converted: {converted} levels")
    if not args.force and skipped_existing > 0:
        print(f"  Skipped (already exist): {skipped_existing} levels")
    if skipped_prefix > 0:
        print(f"  Skipped (prefix mismatch): {skipped_prefix} levels")


if __name__ == "__main__":
    main()
