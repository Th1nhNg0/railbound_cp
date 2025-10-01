#!/usr/bin/env python3
"""
Convert levels from levels.json (old brute force solver format)
to MiniZinc .dzn format for the CP solver.

Usage:
  python convert_levels.py [--force]

Options:
  --force    Force convert all levels, overwriting existing files
             (default: only convert levels that don't exist in test/)
"""

import argparse
import json
import sys
from pathlib import Path
from typing import Dict, List, Tuple, Any

# Mapping from old board values to MiniZinc track types
# Based on classes.ts Track enum and reverse-engineered from existing .dzn files
BOARD_TO_TRACK = {
    0: None,  # EMPTY - not placed initially
    1: "STRAIGHT_RL",  # HORIZONTAL_TRACK
    2: "STRAIGHT_TD",  # VERTICAL_TRACK
    3: "STRAIGHT_RL",  # CAR_ENDING_TRACK_RIGHT - target
    4: "EMPTY",  # ROADBLOCK - explicitly empty (fence/rock)
    5: "CORNER_DR",  # BOTTOM_RIGHT_TURN (DOWN-RIGHT in MiniZinc)
    6: "CORNER_DL",  # BOTTOM_LEFT_TURN (DOWN-LEFT in MiniZinc)
    7: "CORNER_TR",  # TOP_RIGHT_TURN
    8: "CORNER_TL",  # TOP_LEFT_TURN
    9: "SWITCH_R_L_D",  # BOTTOM_RIGHT_LEFT_3WAY - based on testing
    10: "SWITCH_T_D_R",  # BOTTOM_RIGHT_TOP_3WAY - or DSWITCH_T_D_R if mod=5
    11: "SWITCH_R_L_D",  # BOTTOM_LEFT_RIGHT_3WAY - confirmed from 1-3
    12: "SWITCH_T_D_L",  # BOTTOM_LEFT_TOP_3WAY
    13: "SWITCH_L_R_T",  # TOP_RIGHT_LEFT_3WAY - enters from right
    14: "SWITCH_D_T_R",  # TOP_RIGHT_BOTTOM_3WAY
    15: "SWITCH_R_L_T",  # TOP_LEFT_RIGHT_3WAY - enters from left
    16: "SWITCH_D_T_L",  # TOP_LEFT_BOTTOM_3WAY
    17: "TUNNEL_L",  # LEFT_FACING_TUNNEL
    18: "TUNNEL_R",  # RIGHT_FACING_TUNNEL
    19: "TUNNEL_D",  # DOWN_FACING_TUNNEL
    20: "TUNNEL_T",  # UP_FACING_TUNNEL - note: uses T not U in MiniZinc
    21: "STRAIGHT_RL",  # NCAR_ENDING_TRACK_RIGHT
    22: "STRAIGHT_RL",  # NCAR_ENDING_TRACK_LEFT
    29: "STRAIGHT_RL",  # CAR_ENDING_TRACK_LEFT
    30: "STRAIGHT_TD",  # CAR_ENDING_TRACK_DOWN
    31: "STRAIGHT_TD",  # CAR_ENDING_TRACK_UP
}

# Mapping from old mod values
# Based on classes.ts Mod enum
MOD_SWITCH = 1
MOD_TUNNEL = 2
MOD_CLOSED_GATE = 3
MOD_OPEN_GATE = 4
MOD_SWAPPING_TRACK = 5
MOD_STARTING_CAR = 10

# Direction mapping from string to MiniZinc enum
DIRECTION_MAP = {
    "RIGHT": "RIGHT",
    "LEFT": "LEFT",
    "UP": "TOP",
    "DOWN": "DOWN",
}

# Tunnel direction mapping
# Based on analysis: TUNNEL_X in MiniZinc means "enter from X direction"
# When a train enters tunnel A, it teleports to tunnel B and exits in the direction
# specified in the tunnel pair (exit_dir_B).
# The exit direction should be the same as the tunnel type direction.
TUNNEL_DIR = {
    17: "LEFT",  # LEFT_FACING_TUNNEL - enter from LEFT
    18: "RIGHT",  # RIGHT_FACING_TUNNEL - enter from RIGHT
    19: "DOWN",  # DOWN_FACING_TUNNEL - enter from DOWN (note: DOWN not BOTTOM in board)
    20: "TOP",  # UP_FACING_TUNNEL - enter from TOP (note: UP is TOP in MiniZinc)
}


def convert_level(level_name: str, level_data: Dict[str, Any]) -> str:
    """Convert a single level from JSON format to MiniZinc .dzn format."""

    board = level_data["board"]
    mods = level_data["mods"]
    mod_nums = level_data["mod_nums"]
    cars = level_data["cars"]
    tracks = level_data["tracks"]

    H = len(board)
    W = len(board[0]) if H > 0 else 0

    # Find target position (first occurrence of value 3 in board)
    target = None
    for r in range(H):
        for c in range(W):
            if board[r][c] == 3:
                target = (r + 1, c + 1)  # 1-indexed
                break
        if target:
            break

    if not target:
        print(
            f"Warning: No target found for level {level_name}, using default",
            file=sys.stderr,
        )
        target = (1, W)

    # Collect train information (only NORMAL cars)
    trains = []
    for car in cars:
        if car["type"] == "NORMAL":
            r, c = car["pos"]
            direction = DIRECTION_MAP[car["direction"]]
            trains.append((r + 1, c + 1, direction))  # 1-indexed

    # Collect initial positions and dynamic switches
    init_pos = []
    dswitches = []

    for r in range(H):
        for c in range(W):
            board_val = board[r][c]
            mod_val = mods[r][c]

            # Skip tunnels - they are handled separately in TUNNEL_PAIRS
            if mod_val == MOD_TUNNEL:
                continue

            # Starting car positions are marked with mod 10
            if mod_val == MOD_STARTING_CAR:
                # This is handled in trains, but we still need the track piece
                if board_val in BOARD_TO_TRACK and BOARD_TO_TRACK[board_val]:
                    track_type = BOARD_TO_TRACK[board_val]
                    init_pos.append((r + 1, c + 1, track_type))
            # Target position
            elif board_val == 3:
                init_pos.append((r + 1, c + 1, "STRAIGHT_RL"))
            # Empty/roadblock positions (explicitly marked)
            elif board_val == 4:
                init_pos.append((r + 1, c + 1, "EMPTY"))
            # Pre-placed tracks
            elif board_val != 0 and board_val in BOARD_TO_TRACK:
                track = BOARD_TO_TRACK[board_val]
                if track and track != "EMPTY":
                    # Check if it's a dynamic switch (swapping track)
                    if mod_val == MOD_SWAPPING_TRACK and track.startswith("SWITCH_"):
                        # Convert SWITCH to DSWITCH
                        dswitch_track = track.replace("SWITCH_", "DSWITCH_")
                        init_pos.append((r + 1, c + 1, dswitch_track))
                        # Track this as a dynamic switch
                        mod_num = mod_nums[r][c]
                        if mod_num > 0:
                            dswitches.append((r + 1, c + 1, mod_num))
                    else:
                        init_pos.append((r + 1, c + 1, track))

    # Collect tunnel pairs
    tunnel_pairs = []
    tunnel_endpoints = {}  # tunnel_num -> [(pos, board_val), ...]

    for r in range(H):
        for c in range(W):
            board_val = board[r][c]
            mod_val = mods[r][c]

            if mod_val == MOD_TUNNEL and board_val in TUNNEL_DIR:
                tunnel_num = mod_nums[r][c]
                pos = (r + 1, c + 1)  # 1-indexed

                if tunnel_num not in tunnel_endpoints:
                    tunnel_endpoints[tunnel_num] = []
                tunnel_endpoints[tunnel_num].append((pos, board_val))

    # Create tunnel pairs from collected endpoints
    for tunnel_num in sorted(tunnel_endpoints.keys()):
        endpoints = tunnel_endpoints[tunnel_num]
        if len(endpoints) == 2:
            (r1, c1), board_val1 = endpoints[0]
            (r2, c2), board_val2 = endpoints[1]
            # Use the direction from the tunnel type
            # exit_dir_A is where train exits when going from B to A
            # exit_dir_B is where train exits when going from A to B
            exit_dir_A = TUNNEL_DIR[board_val1]
            exit_dir_B = TUNNEL_DIR[board_val2]
            tunnel_pairs.append((r1, c1, exit_dir_A, r2, c2, exit_dir_B))

    # Collect gates
    gates = []
    for r in range(H):
        for c in range(W):
            mod_val = mods[r][c]
            if mod_val in (MOD_CLOSED_GATE, MOD_OPEN_GATE):
                gate_num = mod_nums[r][c]
                is_open = mod_val == MOD_OPEN_GATE
                gates.append((r + 1, c + 1, gate_num, str(is_open).lower()))

    # Collect activations (switches that control gates)
    activations = []
    for r in range(H):
        for c in range(W):
            mod_val = mods[r][c]
            if mod_val == MOD_SWITCH:
                switch_num = mod_nums[r][c]
                if switch_num > 0:  # Connected to a gate
                    activations.append((r + 1, c + 1, switch_num))

    # Generate the .dzn content
    lines = [
        f"W={W};",
        f"H={H};",
        "",
        "MAX_TIME=W*H;",
        f"MAX_TRACKS={tracks};",
        "",
        f"TARGET=({target[0]},{target[1]});",
        "",
        f"N_TRAINS={len(trains)};",
    ]

    # Format trains
    if trains:
        trains_str = ",".join([f"({r},{c},{d})" for r, c, d in trains])
        lines.append(f"TRAINS=[{trains_str}];")
    else:
        lines.append("TRAINS=[];")

    lines.append("")
    lines.append(f"N_INIT_POS={len(init_pos)};")

    if init_pos:
        lines.append("INIT_POS=[")
        for r, c, track in init_pos:
            lines.append(f"({r},{c},{track}),")
        lines.append("];")
    else:
        lines.append("INIT_POS=[];")

    lines.append(f"N_TUNNELS={len(tunnel_pairs)};")
    if tunnel_pairs:
        lines.append("TUNNEL_PAIRS=[")
        for r1, c1, entry, r2, c2, exit_dir in tunnel_pairs:
            lines.append(f"  ({r1}, {c1}, {entry}, {r2}, {c2}, {exit_dir}),")
        lines.append("];")
    else:
        lines.append("TUNNEL_PAIRS=[];")

    lines.append("")
    lines.append(f"N_GATES={len(gates)};")
    if gates:
        lines.append("GATES=[")
        for r, c, num, is_open in gates:
            lines.append(f"({r},{c},{num},{is_open}),")
        lines.append("];")
    else:
        lines.append("GATES=[];")

    lines.append(f"N_ACTIVATIONS={len(activations)};")
    if activations:
        lines.append("ACTIVATIONS=[")
        for r, c, num in activations:
            lines.append(f"({r},{c},{num}),")
        lines.append("];")
    else:
        lines.append("ACTIVATIONS=[];")

    lines.append("")
    lines.append(f"N_DSWITCHES={len(dswitches)};")
    if dswitches:
        lines.append("DSWITCHES=[")
        for r, c, num in dswitches:
            lines.append(f"({r},{c},{num}),")
        lines.append("];")
    else:
        lines.append("DSWITCHES=[];")

    return "\n".join(lines) + "\n"


def main():
    # Parse command line arguments
    parser = argparse.ArgumentParser(
        description="Convert levels from levels.json to MiniZinc .dzn format",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python convert_levels.py           # Convert only missing levels
  python convert_levels.py --force   # Force convert all levels
        """,
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Force convert all levels, overwriting existing files",
    )
    args = parser.parse_args()

    # Load levels.json
    json_path = Path("/Users/tardis89/Desktop/me/RailboundSolver/levels.json")
    output_dir = Path("/Users/tardis89/Desktop/me/railbound_cp/test")

    with open(json_path, "r") as f:
        levels = json.load(f)

    # Filter to only worlds 1-4
    def is_world_1_4(level_name: str) -> bool:
        # Level names like "1-1", "2-3A", "3-10C", "4-5B"
        # Skip levels starting with #, or worlds 5+
        if level_name.startswith("#"):
            return False
        world = level_name.split("-")[0]
        try:
            return 1 <= int(world) <= 4
        except ValueError:
            return False

    print(
        f"{'Force converting' if args.force else 'Converting missing'} world 1-4 levels..."
    )
    converted = 0
    skipped = 0
    skipped_existing = 0

    for level_name, level_data in sorted(levels.items()):
        if not is_world_1_4(level_name):
            skipped += 1
            continue

        output_path = output_dir / f"{level_name}.dzn"

        # Skip if file exists and not forcing
        if not args.force and output_path.exists():
            skipped_existing += 1
            continue

        try:
            dzn_content = convert_level(level_name, level_data)
            output_path.write_text(dzn_content)
            converted += 1
            if converted % 10 == 0:
                print(f"  Converted {converted} levels...")
        except Exception as e:
            print(f"Error converting {level_name}: {e}", file=sys.stderr)

    print(f"\nConversion complete!")
    print(f"  Converted: {converted} levels from worlds 1-4")
    if not args.force and skipped_existing > 0:
        print(f"  Skipped (already exist): {skipped_existing} levels")
    print(f"  Skipped (other worlds): {skipped} levels")


if __name__ == "__main__":
    main()
