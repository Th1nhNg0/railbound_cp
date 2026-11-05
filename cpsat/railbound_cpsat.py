#!/usr/bin/env python3
"""Railbound solver on OR-Tools CP-SAT.

A Boolean port of the MiniZinc model in this repository (main.mzn and
constraints/), which is checked against the FoxtrotOnce/RailboundSolver
reference simulator.  It reads the same .dzn level files.

Encoding
--------
* Grid: one Boolean per (cell, piece); exactly one per cell.
* Every vehicle (trains, then decoys) has, per time step, one-hot Booleans
  for its cell, the side it entered from and its heading (the side it will
  leave by, fixed when it enters a cell).  Cell literals are only created for
  cells the vehicle can reach by then (shortest paths on the board).
* Movement, gates, switches, stations, semaphores and decoy crashes are
  clauses over those literals, mirroring the MiniZinc constraints one for one;
  toggle parities are XOR constraints.

Usage:
  python cpsat/railbound_cpsat.py data/8/8-1.dzn [--time-limit 60] [--workers 4]
  python cpsat/railbound_cpsat.py LEVEL.dzn --pin board.json   # check a board
"""

import argparse
import json
import re
import sys
import time
from collections import defaultdict
from pathlib import Path

from ortools.sat.python import cp_model

ROOT = Path(__file__).resolve().parent.parent
DIRS = ["TOP", "RIGHT", "DOWN", "LEFT"]
D_IDX = {d: i for i, d in enumerate(DIRS)}
DR = [-1, 0, 1, 0]
DC = [0, 1, 0, -1]


def opp(d):
    return (d + 2) % 4


# ---------------------------------------------------------------- tables ----
def load_tables():
    types = (ROOT / "lib" / "types.mzn").read_text()
    body = types[types.index("enum Piece = {") + len("enum Piece = {"): types.index("};", types.index("enum Piece"))]
    body = re.sub(r"%.*", "", body)
    pieces = [p.strip() for p in body.replace("\n", " ").split(",") if p.strip()]
    g = (ROOT / "lib" / "globals.mzn").read_text()

    def table(name):
        part = g[g.index(f"{name} = array2d(Piece, Dir, ["):]
        part = part[part.index("[") + 1: part.index("]);")]
        rows = {}
        for line in part.splitlines():
            m = re.match(r"\s*(.*?)%\s*(\w+)\s*$", line)
            if m:
                vals = [v.strip() for v in m.group(1).split(",") if v.strip()]
                if len(vals) == 4 and m.group(2) in pieces:
                    rows[m.group(2)] = vals
        return rows

    ce, cx, eo = table("can_enter"), table("can_exit"), table("exit_of")
    can_enter = {p: [v == "true" for v in ce[p]] for p in pieces}
    can_exit = {p: [v == "true" for v in cx[p]] for p in pieces}
    exit_of = {p: [D_IDX[v] for v in eo[p]] for p in pieces}
    can_connect = {p: [a or b for a, b in zip(can_enter[p], can_exit[p])] for p in pieces}
    return pieces, can_enter, exit_of, can_connect


PIECES, CAN_ENTER, EXIT_OF, CAN_CONNECT = load_tables()
STRAIGHTS = {"STRAIGHT_TD", "STRAIGHT_RL"}
CORNERS = {"CORNER_TR", "CORNER_TL", "CORNER_DR", "CORNER_DL"}
SWITCHES = {p for p in PIECES if p.startswith("SWITCH_")}
SWITCH_VARIANTS = {p for p in PIECES if "SWITCH_" in p}
ESWITCHES = {p for p in PIECES if p.startswith("ESWITCH_")}
PLACEABLE = ["EMPTY"] + sorted(STRAIGHTS) + sorted(CORNERS) + sorted(SWITCHES)
SEM_ELIGIBLE = STRAIGHTS | CORNERS


def switch_toggle(p):
    if p.startswith(("DSWITCH_", "ESWITCH_")):
        kind, a, b, c = p.split("_")
        return f"{kind}_{b}_{a}_{c}"
    return p


def tunnel_piece(d):
    return "TUNNEL_" + DIRS[d][0]


# ------------------------------------------------------------------ data ----
def parse_dzn(text):
    text = re.sub(r"%.*", "", text)
    vals = {}
    for m in re.finditer(r"(\w+)\s*=\s*(.*?);", text, re.S):
        vals[m.group(1)] = m.group(2).strip()
    W, H = int(vals["W"]), int(vals["H"])

    def tuples(key):
        v = vals.get(key, "[]")
        return [tuple(x.strip() for x in t.split(",")) for t in re.findall(r"\(([^)]*)\)", v)]

    num = lambda s: int(s)
    lvl = {
        "W": W, "H": H,
        "MAX_TIME": int(eval(vals["MAX_TIME"].replace("W", str(W)).replace("H", str(H)), {"__builtins__": {}})),
        "MAX_TRACKS": int(vals["MAX_TRACKS"]),
        "TARGET": tuple(map(int, re.findall(r"\d+", vals["TARGET"]))),
        "TRAINS": [(num(r), num(c), D_IDX[d]) for r, c, d in tuples("TRAINS")],
        "DECOYS": [(num(r), num(c), D_IDX[d]) for r, c, d in tuples("DECOYS")],
        "INIT_POS": [(num(r), num(c), p) for r, c, p in tuples("INIT_POS")],
        "TUNNEL_PAIRS": [(num(a), num(b), D_IDX[c], num(d), num(e), D_IDX[f]) for a, b, c, d, e, f in tuples("TUNNEL_PAIRS")],
        "GATES": [(num(r), num(c), num(i), o == "true") for r, c, i, o in tuples("GATES")],
        "ACTIVATIONS": [(num(r), num(c), num(i)) for r, c, i in tuples("ACTIVATIONS")],
        "DSWITCHES": [(num(r), num(c), num(i)) for r, c, i in tuples("DSWITCHES")],
        "STATIONS": [(num(r), num(c), num(v)) for r, c, v in tuples("STATIONS")],
        "SEMAPHORE_SUPPLY": int(vals.get("SEMAPHORE_SUPPLY", "0")),
        "FIXED_SEMAPHORES": [(num(r), num(c)) for r, c in tuples("FIXED_SEMAPHORES")],
    }
    return lvl


# ------------------------------------------------------------ the solver ----
class Railbound:
    def __init__(self, lvl, max_time=None):
        self.L = lvl
        self.W, self.H = lvl["W"], lvl["H"]
        self.N = self.W * self.H
        self.T = max_time or lvl["MAX_TIME"]
        self.m = cp_model.CpModel()
        self._and_cache, self._or_cache = {}, {}
        self.precompute()

    # ---------------------------------------------------------- helpers ----
    def cell(self, r, c):
        return (r - 1) * self.W + c

    def rc(self, p):
        return (p - 1) // self.W + 1, (p - 1) % self.W + 1

    @staticmethod
    def neg(l):
        if l is True:
            return False
        if l is False:
            return True
        return l.Not()

    def clause(self, lits):
        out = []
        for l in lits:
            if l is True:
                return
            if l is False:
                continue
            out.append(l)
        self.m.AddBoolOr(out)

    def implies(self, prem, concl):
        """AND(prem) -> each literal of concl."""
        np_ = [self.neg(l) for l in prem]
        for c in concl:
            self.clause(np_ + [c])

    def new(self, name=""):
        return self.m.NewBoolVar(name)

    def and_var(self, lits):
        lits = [l for l in lits if l is not True]
        if any(l is False for l in lits):
            return False
        if not lits:
            return True
        if len(lits) == 1:
            return lits[0]
        key = tuple(sorted(l.Index() for l in lits))
        if key in self._and_cache:
            return self._and_cache[key]
        b = self.new()
        for l in lits:
            self.m.AddImplication(b, l)
        self.m.AddBoolOr([l.Not() for l in lits] + [b])
        self._and_cache[key] = b
        return b

    def or_var(self, lits):
        lits = [l for l in lits if l is not False]
        if any(l is True for l in lits):
            return True
        if not lits:
            return False
        if len(lits) == 1:
            return lits[0]
        key = tuple(sorted(l.Index() for l in lits))
        if key in self._or_cache:
            return self._or_cache[key]
        b = self.new()
        for l in lits:
            self.m.AddImplication(l, b)
        self.m.AddBoolOr(lits + [b.Not()])
        self._or_cache[key] = b
        return b

    def eq(self, a, b):
        """a <-> b for literals/constants."""
        if a is True or a is False:
            a, b = b, a
        if a is True or a is False:
            if a != b:
                self.m.AddBoolOr([])
            return
        if b is True:
            self.m.AddBoolOr([a])
        elif b is False:
            self.m.AddBoolOr([a.Not()])
        else:
            self.m.AddImplication(a, b)
            self.m.AddImplication(b, a)

    def xor_var(self, lits):
        lits = [l for l in lits if l is not False]
        parity = sum(1 for l in lits if l is True) % 2
        lits = [l for l in lits if l is not True]
        if not lits:
            return parity == 1
        b = self.new()
        # XOR(lits) xor parity == b  <=>  XOR(lits + [not b]) == 1 xor parity
        self.m.AddBoolXOr(lits + [b.Not() if parity == 0 else b])
        return b

    def xor2(self, a, b):
        return self.xor_var([a, b])

    # ------------------------------------------------------ precompute ----
    def precompute(self):
        L, N, W, H = self.L, self.N, self.W, self.H
        self.nbr = [[0] * 4 for _ in range(N + 1)]
        for p in range(1, N + 1):
            r, c = self.rc(p)
            for d in range(4):
                rr, cc = r + DR[d], c + DC[d]
                self.nbr[p][d] = self.cell(rr, cc) if 1 <= rr <= H and 1 <= cc <= W else 0
        self.target = self.cell(*L["TARGET"])
        self.init_piece = {self.cell(r, c): p for r, c, p in L["INIT_POS"]}
        self.tunnel_dest, self.tunnel_exit, self.fixed = {}, {}, dict(self.init_piece)
        for r1, c1, d1, r2, c2, d2 in L["TUNNEL_PAIRS"]:
            a, b = self.cell(r1, c1), self.cell(r2, c2)
            self.tunnel_dest[a], self.tunnel_dest[b] = b, a
            self.tunnel_exit[a], self.tunnel_exit[b] = d2, d1
            self.fixed[a], self.fixed[b] = tunnel_piece(d1), tunnel_piece(d2)
        self.move_cell = [[0] * 4 for _ in range(N + 1)]
        self.move_entry = [[0] * 4 for _ in range(N + 1)]
        for p in range(1, N + 1):
            for e in range(4):
                q = self.nbr[p][e]
                if q and q in self.tunnel_dest:
                    self.move_cell[p][e] = self.tunnel_dest[q] if CAN_ENTER[self.fixed[q]][opp(e)] else 0
                    self.move_entry[p][e] = self.tunnel_exit[q]
                else:
                    self.move_cell[p][e] = q
                    self.move_entry[p][e] = opp(e)
        self.gate_at = {self.cell(r, c): i for i, (r, c, _, _) in enumerate(L["GATES"])}
        self.dswitch_at = {self.cell(r, c): i for i, (r, c, _) in enumerate(L["DSWITCHES"])}
        self.eswitch_cells = [p for p, pc in sorted(self.init_piece.items()) if pc in ESWITCHES]
        self.eswitch_at = {p: i for i, p in enumerate(self.eswitch_cells)}
        self.act_cells = {self.cell(r, c) for r, c, _ in L["ACTIVATIONS"]}
        self.station_cells = {self.cell(r, c) for r, c, _ in L["STATIONS"]}
        self.toggles = len(L["DSWITCHES"]) + len(self.eswitch_cells) > 0
        # pieces each cell may hold
        self.domain = {}
        for p in range(1, N + 1):
            self.domain[p] = [self.fixed[p]] if p in self.fixed else PLACEABLE
        # vehicles: trains then decoys
        self.NT, self.ND = len(L["TRAINS"]), len(L["DECOYS"])
        self.starts = [(self.cell(r, c), d) for r, c, d in L["TRAINS"] + L["DECOYS"]]
        self.NV = self.NT + self.ND
        # semaphores
        fixed_sem = {self.cell(r, c) for r, c in L["FIXED_SEMAPHORES"]}
        start_cells = {p for p, _ in self.starts}
        self.fixed_sem = fixed_sem
        self.has_sem = L["SEMAPHORE_SUPPLY"] > 0 or bool(fixed_sem)
        self.sem_cand = {p for p in range(1, N + 1) if p in fixed_sem or (
            L["SEMAPHORE_SUPPLY"] > 0 and p not in self.gate_at and p not in self.act_cells and
            p not in self.tunnel_dest and p != self.target and p not in self.station_cells and p not in start_cells)}
        self.reachability()

    def reachability(self):
        N = self.N
        states = lambda p: ([x for x in PLACEABLE if x != "EMPTY"] if p not in self.fixed
                            else list({self.fixed[p], switch_toggle(self.fixed[p])}))
        succ = defaultdict(set)
        for p in range(1, N + 1):
            if self.fixed.get(p) == "ROCK":
                continue
            exits = {EXIT_OF[x][d] for x in states(p) for d in range(4)}
            for e in exits:
                q = self.move_cell[p][e]
                if q and self.fixed.get(q) != "ROCK" and any(CAN_ENTER[x][self.move_entry[p][e]] for x in states(q)):
                    succ[p].add(q)
        self.succ = succ
        pred = defaultdict(set)
        for p, qs in succ.items():
            for q in qs:
                pred[q].add(p)
        INF = 10 ** 6

        def bfs(seeds, nb):
            dist = {p: INF for p in range(1, N + 1)}
            frontier = []
            for p, d0 in seeds:
                if d0 < dist[p]:
                    dist[p] = d0
            changed = True
            while changed:
                changed = False
                for q in range(1, N + 1):
                    best = min([dist[q]] + [dist[n] + 1 for n in nb[q]])
                    if best < dist[q]:
                        dist[q] = best
                        changed = True
            return dist
        self.dist_start = []
        for p0, d0 in self.starts:
            p1 = self.move_cell[p0][d0]
            seeds = [(p0, 0)] + ([(p1, 1)] if p1 else [])
            self.dist_start.append(bfs(seeds, pred))
        self.dist_target = bfs([(self.target, 0)], succ)
        # pairs of cells two vehicles could swap between in one step
        td = lambda p: self.tunnel_dest.get(p, p)
        near = lambda x, y: x == y or x in succ[y]
        self.swap_partners = {a: [b for b in range(1, N + 1) if near(td(a), b) and near(td(b), a)]
                              for a in range(1, N + 1)}

    # ------------------------------------------------------------ model ----
    def build(self, pin=None):
        L, m, T, N = self.L, self.m, self.T, self.N
        NT, NV = self.NT, self.NV
        # ---- grid
        self.g = {}
        for p in range(1, N + 1):
            for x in self.domain[p]:
                self.g[p, x] = True if len(self.domain[p]) == 1 else self.new(f"g{p}_{x}")
            if len(self.domain[p]) > 1:
                m.AddExactlyOne([self.g[p, x] for x in self.domain[p]])
        if pin:
            for p, x in pin.get("grid", {}).items():
                if (p, x) in self.g:
                    self.clause([self.g[p, x]])
                elif p not in self.fixed:
                    raise ValueError(f"piece {x} not allowed at cell {p}")
        free = [p for p in range(1, N + 1) if p not in self.fixed]
        m.Add(sum(self.g[p, "EMPTY"].Not() for p in free) <= L["MAX_TRACKS"])
        # connectivity of placed pieces
        conn = {}
        for p in range(1, N + 1):
            for d in range(4):
                q = self.nbr[p][d]
                conn[p, d] = False if not q else self.or_var(
                    [self.g[q, y] for y in self.domain[q] if CAN_CONNECT[y][opp(d)]])
        for p in free:
            for x in self.domain[p]:
                if x == "EMPTY":
                    continue
                need = 2 if x in SWITCHES else 1
                sides = [conn[p, d] for d in range(4) if CAN_CONNECT[x][d]]
                sides = [s for s in sides if s is not False]
                if any(s is True for s in sides):
                    k_true = sum(1 for s in sides if s is True)
                    sides = [s for s in sides if s is not True]
                    need -= k_true
                if need <= 0:
                    continue
                if len(sides) < need:
                    self.clause([self.neg(self.g[p, x])])
                else:
                    m.Add(sum(sides) >= need).OnlyEnforceIf(self.g[p, x])

        self.enterable = {}
        for q in range(1, N + 1):
            for d in range(4):
                self.enterable[q, d] = self.or_var([self.g[q, x] for x in self.domain[q] if CAN_ENTER[x][d]])
        self.nonempty = {p: (True if p in self.fixed and self.fixed[p] != "EMPTY" else
                             (False if p in self.fixed else self.g[p, "EMPTY"].Not())) for p in range(1, N + 1)}

        # ---- vehicle state literals
        self.at, self.en, self.hd = {}, {}, {}
        for v in range(NV):
            p0, d0 = self.starts[v]
            dist = self.dist_start[v]
            latest = T - (NT - 1 - v) if v < NT else T
            for t in range(T + 1):
                if t == 0:
                    cells = [p0]
                else:
                    cells = [p for p in range(1, N + 1) if dist[p] <= t and (
                        v >= NT or p == self.target or self.dist_target[p] <= latest - t)]
                if v >= NT or True:
                    pass
                for p in cells:
                    self.at[v, t, p] = True if (t == 0) else self.new(f"at{v}_{t}_{p}")
                if t > 0:
                    lits = [self.at[v, t, p] for p in cells]
                    if not lits:
                        m.AddBoolOr([])
                    else:
                        m.AddExactlyOne(lits)
                    for d in range(4):
                        self.en[v, t, d] = self.new()
                        self.hd[v, t, d] = self.new()
                    m.AddExactlyOne([self.en[v, t, d] for d in range(4)])
                    m.AddExactlyOne([self.hd[v, t, d] for d in range(4)])
                else:
                    for d in range(4):
                        self.hd[v, 0, d] = (d == d0)
        AT = lambda v, t, p: self.at.get((v, t, p), False)
        self.AT = AT

        # ---- arrival
        self.arr = {}
        for v in range(NT):
            self.arr[v, 0] = False
            for t in range(1, T + 1):
                self.arr[v, t] = self.new(f"arr{v}_{t}")
                if t > 1:
                    m.AddImplication(self.arr[v, t - 1], self.arr[v, t])
            self.clause([self.arr[v, T]])
            # A_v >= v+1, <= T - (NT-1-v); A_v < A_{v+1}
            for t in range(1, v + 1):
                self.clause([self.neg(self.arr[v, t])])
            latest = T - (NT - 1 - v)
            self.clause([self.arr[v, latest]])
            if v > 0:
                for t in range(1, T + 1):
                    # arr[v][t] -> arr[v-1][t-1]
                    self.implies([self.arr[v, t]], [self.arr[v - 1, t - 1] if t - 1 >= 1 else False])
            for t in range(1, T + 1):
                self.implies([self.arr[v, t]], [AT(v, t, self.target), self.en[v, t, D_IDX["LEFT"]]])
        tgt_ok = (self.fixed.get(self.target) == "STRAIGHT_RL" and L["TARGET"][1] == self.W and
                  self.target not in self.station_cells)
        if tgt_ok:
            for v in range(NT):
                for t in range(1, T + 1):
                    self.eq(AT(v, t, self.target), self.arr[v, t])
        # active(v, t): train still running at time t (t < A_v)
        self.active = {}
        for v in range(NT):
            for t in range(0, T + 1):
                self.active[v, t] = self.neg(self.arr[v, t]) if t > 0 else True
        # reachability: i < A -> A >= i + dtt[p]
        for v in range(NT):
            for t in range(1, T + 1):
                for p in range(1, N + 1):
                    if (v, t, p) in self.at and p != self.target:
                        k = t + self.dist_target[p] - 1
                        if k > t and k <= T:
                            self.implies([self.at[v, t, p], self.active[v, t]], [self.neg(self.arr[v, k])])

        self.mechanics()
        self.movement()
        self.collisions()
        if pin and "semaphores" in pin:
            for p in range(1, N + 1):
                lit = self.sem_present.get(p, False)
                self.eq(lit, p in pin["semaphores"])

    # ------------------------------------------------------ mechanics ----
    def entered(self, v, q, t):
        """Vehicle v stepped onto q at time t-1 (as in activations.mzn)."""
        lits = [self.AT(v, t - 1, q)]
        if t >= 2:
            lits.append(self.neg(self.AT(v, t - 2, q)))
        if v < self.NT:
            lits.append(self.active[v, t - 1])
        return self.and_var(lits)

    def mechanics(self):
        L, T, N = self.L, self.T, self.N
        # activation groups
        ids = {i for *_, i in L["ACTIVATIONS"]} | {g[2] for g in L["GATES"]} | {d[2] for d in L["DSWITCHES"]}
        self.should_toggle = {}
        for a in ids:
            tiles = [self.cell(r, c) for r, c, i in L["ACTIVATIONS"] if i == a]
            for t in range(1, T + 1):
                self.should_toggle[a, t] = self.xor_var(
                    [self.entered(v, q, t) for q in tiles for v in range(self.NV)])
        self.gate_open = {}
        for gi, (r, c, a, op) in enumerate(L["GATES"]):
            self.gate_open[gi, 0] = op
            for t in range(1, T + 1):
                self.gate_open[gi, t] = self.xor2(self.gate_open[gi, t - 1], self.should_toggle[a, t])
        self.ds_tog = {}
        for di, (r, c, a) in enumerate(L["DSWITCHES"]):
            self.ds_tog[di, 0] = False
            for t in range(1, T + 1):
                self.ds_tog[di, t] = self.xor2(self.ds_tog[di, t - 1], self.should_toggle[a, t])
        self.es_tog = {}
        for ei, q in enumerate(self.eswitch_cells):
            self.es_tog[ei, 0] = False
            for t in range(1, T + 1):
                self.es_tog[ei, t] = self.xor_var(
                    [self.es_tog[ei, t - 1]] + [self.entered(v, q, t) for v in range(self.NV)])
        self.semaphores()
        # blocked[p, t]
        self.blk = {}
        for p in range(1, N + 1):
            for t in range(1, T + 1):
                parts = []
                if p in self.gate_at:
                    parts.append(self.neg(self.gate_open[self.gate_at[p], t]))
                if p in self.sem_closed_cells:
                    parts.append(self.sem_closed[p, t])
                self.blk[p, t] = self.or_var(parts)
        self.stations()

    def eff_lit(self, p, t, x):
        """Literal: cell p routes like piece x at time t."""
        if p in self.dswitch_at or p in self.eswitch_at:
            base = self.init_piece[p]
            tog = self.ds_tog[self.dswitch_at[p], t] if p in self.dswitch_at else self.es_tog[self.eswitch_at[p], t]
            if x == base:
                return self.neg(tog)
            if x == switch_toggle(base):
                return tog
            return False
        return self.g.get((p, x), False)

    def eff_pieces(self, p):
        if p in self.dswitch_at or p in self.eswitch_at:
            return [self.init_piece[p], switch_toggle(self.init_piece[p])]
        return self.domain[p]

    def semaphores(self):
        T, N = self.T, self.N
        self.sem_present, self.sem_closed, self.sem_closed_cells = {}, {}, set()
        if not self.has_sem:
            return
        for q in sorted(self.sem_cand):
            self.sem_present[q] = True if q in self.fixed_sem else self.new(f"sem{q}")
            if q not in self.fixed_sem:
                self.implies([self.sem_present[q]], [self.or_var([self.g[q, x] for x in self.domain[q] if x in SEM_ELIGIBLE])])
        self.m.Add(sum(self.sem_present[q] for q in self.sem_present if q not in self.fixed_sem)
                   <= self.L["SEMAPHORE_SUPPLY"])
        for q in sorted(self.sem_cand):
            fired = False
            for t in range(1, T + 1):
                k = t - 1
                fired = self.or_var([fired, self.trigger(q, k)])
                self.sem_closed[q, t] = self.and_var([self.sem_present[q], self.neg(fired)])
            self.sem_closed_cells.add(q)

    def v_active(self, v, k):
        if v < self.NT:
            return self.active[v, k]
        return self.neg(self.crashed[v, k]) if hasattr(self, "crashed") and (v, k) in self.crashed else self._decoy_crash_lit(v, k)

    def _decoy_crash_lit(self, v, k):
        # crashed literals are created lazily so semaphores can refer to them
        if not hasattr(self, "crashed"):
            self.crashed = {}
        if (v, k) not in self.crashed:
            self.crashed[v, k] = False if k == 0 else self.new(f"cr{v}_{k}")
        return self.neg(self.crashed[v, k])

    def trigger(self, q, k):
        """Semaphore on q opens after step k (semaphores.mzn)."""
        faces = []
        for a in range(self.NV):
            lits = []
            for p in range(1, self.N + 1):
                for e in range(4):
                    if self.nbr[p][e] == q and (a, k, p) in self.at:
                        lits.append(self.and_var([self.at[a, k, p], self.hd[a, k, e]]))
            faces.append(self.or_var(lits))
        far = []
        for b in range(self.NV):
            lits = []
            for d in range(4):
                n = self.nbr[q][d]
                if n and (b, k, n) in self.at:
                    connects = self.or_var([self.g[q, x] for x in self.domain[q] if CAN_CONNECT[x][d]])
                    lits.append(self.and_var([connects, self.at[b, k, n], self.neg(self.hd[b, k, opp(d)])]))
            far.append(self.or_var(lits))
        terms = []
        for a in range(self.NV):
            if faces[a] is False:
                continue
            others = [self.and_var([self.v_active(b, k), far[b]]) for b in range(self.NV) if b != a]
            terms.append(self.and_var([self.v_active(a, k), faces[a], self.or_var(others)]))
        return self.or_var(terms)

    def stations(self):
        L, T = self.L, self.T
        self.visited, self.wait = {}, {}
        for st, (r, c, vid) in enumerate(L["STATIONS"]):
            v = vid - 1 if vid > 0 else self.NT + (-vid) - 1
            q = self.cell(r, c)
            prev = False
            for t in range(0, T + 1):
                here = self.AT(v, t, q)
                self.visited[st, t] = self.or_var([prev, here])
                prev = self.visited[st, t]
        for v in range(self.NV):
            vid = v + 1 if v < self.NT else -(v - self.NT + 1)
            mine = [st for st, (_, _, x) in enumerate(L["STATIONS"]) if x == vid]
            if not mine:
                continue
            cells = {st: self.cell(*L["STATIONS"][st][:2]) for st in mine}
            w2p = w1p = False
            for t in range(0, T + 1):
                at_any = self.or_var([self.AT(v, t, cells[st]) for st in mine])
                if t == 0:
                    first = at_any
                else:
                    first = self.or_var([self.and_var([self.AT(v, t, cells[st]), self.neg(self.visited[st, t - 1])])
                                         for st in mine])
                w2 = first
                w1 = self.and_var([self.neg(first), at_any, w2p]) if t > 0 else False
                self.wait[v, t] = self.or_var([w2, w1])
                w2p, w1p = w2, w1
        for st, (r, c, vid) in enumerate(L["STATIONS"]):
            if vid > 0:
                v = vid - 1
                for t in range(1, T + 1):
                    self.implies([self.arr[v, t]], [self.visited[st, t - 1]])
            else:
                self.clause([self.visited[st, T]])

    # ------------------------------------------------------- movement ----
    def heading(self, v, t, moved):
        """hd[v,t] = exit on entry if moved into the cell at t, else hd[v,t-1]."""
        N = self.N
        for p in range(1, N + 1):
            if (v, t, p) not in self.at:
                continue
            for x in self.eff_pieces(p):
                lx = self.eff_lit(p, t, x)
                if lx is False:
                    continue
                for d in range(4):
                    self.implies([moved, self.at[v, t, p], self.en[v, t, d], lx], [self.hd[v, t, EXIT_OF[x][d]]])
        for e in range(4):
            self.implies([self.neg(moved), self.hd[v, t - 1, e]], [self.hd[v, t, e]])

    def movement(self):
        T, N, NT = self.T, self.N, self.NT
        AT = self.AT
        for v in range(self.NV):
            if not hasattr(self, "crashed"):
                self.crashed = {}
            is_train = v < NT
            p0, d0 = self.starts[v]
            for tau in range(0, T):
                t1 = tau + 1
                act = self.active[v, tau] if is_train else True
                waiting = self.wait.get((v, tau), False) if tau >= 1 else False
                # contexts: (cell, heading) the vehicle is in at tau
                ctx = []
                for p in range(1, N + 1):
                    if (v, tau, p) not in self.at:
                        continue
                    for e in range(4):
                        h = self.hd[v, tau, e]
                        if h is False:
                            continue
                        ctx.append((p, e, self.and_var([self.at[v, tau, p], h])))
                if is_train:
                    stay = self.new()
                    for p, e, c in ctx:
                        ip, ied = self.move_cell[p][e], self.move_entry[p][e]
                        prem = [act, self.neg(waiting), c]
                        if ip == 0:
                            self.clause([self.neg(l) for l in prem])
                            continue
                        self.implies(prem, [self.enterable[ip, ied]])
                        b = self.blk[ip, t1]
                        self.implies(prem, [self.eq_lit(stay, b)])
                        self.implies(prem + [self.neg(b)], [AT(v, t1, ip), self.en[v, t1, ied]])
                        if tau == 0:
                            self.implies(prem + [b], [self.en[v, t1, ied]])
                    self.implies([act, waiting], [stay])
                    if tau >= 1 or True:
                        for p in range(1, N + 1):
                            if (v, tau, p) in self.at:
                                self.implies([act, stay, self.at[v, tau, p]], [AT(v, t1, p)])
                        if tau >= 1:
                            for d in range(4):
                                self.implies([act, stay, self.en[v, tau, d]], [self.en[v, t1, d]])
                    moved = self.and_var([act, self.neg(stay)])
                    self.heading(v, t1, moved)
                else:
                    cr = self.neg(self._decoy_crash_lit(v, tau))          # crashed at tau
                    cr_next = self.neg(self._decoy_crash_lit(v, t1))
                    STL, VAL, OCC = self.new(), self.new(), self.new()
                    d_idx = v - NT
                    for p, e, c in ctx:
                        ip, ied = self.move_cell[p][e], self.move_entry[p][e]
                        on_track = True if tau == 0 else self.nonempty[p]
                        if ip == 0:
                            self.implies([c], [self.neg(STL), self.neg(VAL), self.neg(OCC)])
                            continue
                        self.implies([c], [self.eq_lit(STL, self.blk[ip, t1])])
                        self.implies([c], [self.eq_lit(VAL, self.and_var([on_track, self.enterable[ip, ied]]))])
                        occ = [self.and_var([self.active[t, tau], AT(t, t1, ip)]) for t in range(NT)]
                        for v2 in range(NT, self.NV):
                            if v2 < v:
                                occ.append(AT(v2, t1, ip))
                            elif v2 > v:
                                toward = self.or_var([self.hd[v2, tau, e2] for e2 in range(4)
                                                      if self.move_cell[ip][e2] == p])
                                occ.append(self.and_var([AT(v2, tau, ip), self.or_var([AT(v2, t1, ip), toward])]))
                        self.implies([c], [self.eq_lit(OCC, self.or_var(occ))])
                        M = self.and_var([self.neg(cr), self.neg(waiting), self.neg(STL), VAL, self.neg(OCC)])
                        self.implies([c, M], [AT(v, t1, ip), self.en[v, t1, ied]])
                        if tau == 0:
                            self.implies([c, self.neg(M)], [self.en[v, t1, ied]])
                    M = self.and_var([self.neg(cr), self.neg(waiting), self.neg(STL), VAL, self.neg(OCC)])
                    crash_now = self.and_var([self.neg(waiting), self.neg(STL), self.or_var([self.neg(VAL), OCC])])
                    self.eq(cr_next, self.or_var([cr, crash_now]))
                    for p in range(1, N + 1):
                        if (v, tau, p) in self.at:
                            self.implies([self.neg(M), self.at[v, tau, p]], [AT(v, t1, p)])
                    if tau >= 1:
                        for d in range(4):
                            self.implies([self.neg(M), self.en[v, tau, d]], [self.en[v, t1, d]])
                    self.heading(v, t1, M)

    def eq_lit(self, a, b):
        """Literal for a <-> b."""
        if b is True:
            return a
        if b is False:
            return self.neg(a)
        x = self.new()
        self.m.AddBoolXOr([a, b, x])  # x = (a == b)
        return x

    def collisions(self):
        T, N, NT, NV = self.T, self.N, self.NT, self.NV
        AT = self.AT
        td = lambda p: self.tunnel_dest.get(p, p)
        game_active = (lambda i: self.active[NT - 1, i - 1]) if NT else (lambda i: True)  # i <= A_last
        for v1 in range(NV):
            for v2 in range(v1 + 1, NV):
                both_trains = v2 < NT
                dec_dec = v1 >= NT
                for i in range(1, T + 1):
                    if both_trains:
                        cond = self.active[v1, i]                    # i < A_v1
                    elif dec_dec:
                        cond = game_active(i)                         # i <= game_end
                    else:
                        cond = self.active[v1, i - 1]                 # i <= A_t (v1 is the train)
                    for p in range(1, N + 1):
                        a, b = AT(v1, i, p), AT(v2, i, p)
                        if a is not False and b is not False:
                            self.clause([self.neg(cond), self.neg(a), self.neg(b)])
                # swaps
                for i in range(1, T):
                    if both_trains or not dec_dec:
                        cond = self.active[v1, i]
                    else:
                        cond = game_active(i + 1)                     # i < game_end
                    for a in range(1, N + 1):
                        if (v1, i, a) not in self.at:
                            continue
                        for b in self.swap_partners[a]:
                            if (v2, i, b) not in self.at:
                                continue
                            x1, x2 = AT(v2, i + 1, td(a)), AT(v1, i + 1, td(b))
                            if x1 is False or x2 is False:
                                continue
                            self.clause([self.neg(cond), self.neg(self.at[v1, i, a]), self.neg(self.at[v2, i, b]),
                                         self.neg(x1), self.neg(x2)])
        for v in range(NT, NV):
            for i in range(1, T + 1):
                a = AT(v, i, self.target)
                if a is not False:
                    self.clause([self.neg(game_active(i)), self.neg(a)])

    # ------------------------------------------------------------ solve ----
    def solve(self, time_limit=60.0, workers=4, log=False):
        s = cp_model.CpSolver()
        s.parameters.max_time_in_seconds = time_limit
        s.parameters.num_workers = workers
        s.parameters.log_search_progress = log
        st = s.Solve(self.m)
        return s, st

    def extract(self, s):
        val = lambda l: l if isinstance(l, bool) else bool(s.Value(l))
        grid = {}
        for p in range(1, self.N + 1):
            for x in self.domain[p]:
                if val(self.g[p, x]):
                    grid[p] = x
        paths = []
        for v in range(self.NV):
            path = []
            for t in range(self.T + 1):
                for p in range(1, self.N + 1):
                    if (v, t, p) in self.at and val(self.at[v, t, p]):
                        path.append(p)
            paths.append(path)
        arrivals = [1 + sum(1 for t in range(1, self.T + 1) if not val(self.arr[v, t])) for v in range(self.NT)]
        sems = [p for p, l in self.sem_present.items() if val(l)]
        return grid, paths, arrivals, sems


def horizon_lower_bound(rb):
    """Earliest possible arrival of the last train (shortest paths + ordering)."""
    lb = 1
    for v in range(rb.NT):
        lb = max(lb, rb.dist_start[v][rb.target] + (rb.NT - 1 - v), rb.NT)
    return lb


def solve_once(lvl, T, pin, time_limit, workers, log=False):
    t0 = time.time()
    rb = Railbound(lvl, T)
    rb.build(pin)
    t1 = time.time()
    s, st = rb.solve(max(0.1, time_limit - (t1 - t0)), workers, log)
    return rb, s, st, t1 - t0, time.time() - t1


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("level")
    ap.add_argument("--time-limit", type=float, default=60, help="total seconds")
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--max-time", type=int, help="override MAX_TIME")
    ap.add_argument("--deepen", action="store_true",
                    help="iterative deepening: try short horizons first, growing up to MAX_TIME")
    ap.add_argument("--pin", help="JSON {grid: {cell: piece}, semaphores: [cells]} to check")
    ap.add_argument("--json", action="store_true", help="print the solution as JSON")
    ap.add_argument("--log", action="store_true")
    args = ap.parse_args()
    start = time.time()
    lvl = parse_dzn(Path(args.level).read_text())
    T_max = args.max_time or lvl["MAX_TIME"]
    pin = None
    if args.pin:
        raw = json.loads(Path(args.pin).read_text())
        pin = {"grid": {int(k): v for k, v in raw.get("grid", {}).items()}, "semaphores": set(raw.get("semaphores", []))}
    horizons = [T_max]
    if args.deepen:
        lb = min(T_max, horizon_lower_bound(Railbound(lvl, T_max)))
        horizons, T = [], lb
        while T < T_max:
            horizons.append(T)
            T = max(T + 2, int(T * 1.25 + 0.999))
        horizons.append(T_max)
    build_s = solve_s = 0.0
    for i, T in enumerate(horizons):
        left = args.time_limit - (time.time() - start)
        if left <= 0:
            break
        last = i == len(horizons) - 1
        budget = left if last else max(1.0, left * 0.25)
        rb, s, st, b, so = solve_once(lvl, T, pin, budget, args.workers, args.log)
        build_s += b
        solve_s += so
        if st in (cp_model.OPTIMAL, cp_model.FEASIBLE):
            break
    if st in (cp_model.OPTIMAL, cp_model.FEASIBLE):
        grid, paths, arr, sems = rb.extract(s)
        if args.json:
            print(json.dumps({"status": "SATISFIED", "grid": grid, "paths": paths, "arrivals": arr, "horizon": T,
                              "semaphores": sems, "build_s": round(build_s, 3), "solve_s": round(solve_s, 3)}))
        else:
            W = rb.W
            print("SOLUTION FOUND")
            for r in range(1, rb.H + 1):
                print(" ".join(f"{grid[rb.cell(r, c)]:>13s}" for c in range(1, W + 1)))
            for v, path in enumerate(paths):
                kind = f"Train {v + 1} (arrives t={arr[v]})" if v < rb.NT else f"Decoy {v - rb.NT + 1}"
                print(kind + ": " + " ".join("(%d,%d)" % rb.rc(p) for p in path))
            if sems:
                print("Semaphores: " + " ".join("(%d,%d)" % rb.rc(p) for p in sems))
            print(f"% horizon {T}, build {build_s:.2f}s, solve {solve_s:.2f}s")
        return 0
    status = "UNSATISFIABLE" if st == cp_model.INFEASIBLE and T == T_max else "UNKNOWN"
    if args.json:
        print(json.dumps({"status": status, "build_s": round(build_s, 3), "solve_s": round(solve_s, 3)}))
    else:
        print("=====UNSATISFIABLE=====" if status == "UNSATISFIABLE" else "% UNKNOWN")
        print(f"% build {build_s:.2f}s, solve {solve_s:.2f}s")
    return 1


if __name__ == "__main__":
    sys.exit(main())
