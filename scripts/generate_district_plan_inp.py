#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
规划型给水管网算例（EPANET 2.2，公制 LPS）。

仅两个约束参数（用户可调）：
  --total-m3d     区域日总需水量 (m³/d)，默认 30000（3 万 m³/d）
  --source-head   两座水库水头 (m)，同一标高，默认 52

其余：双水源、混合用地（住宅/商业/学校/企业）按规划比例分配日水量；
拓扑：规划示意——主干折线 + 支路 + Poisson 填空布点，Delaunay 上取欧氏 MST 为输水骨架，
再补若干较短 Delaunay 弦边形成环网（非街网网格、非纯三角剖分满铺）；
管径为离散 DN，按距水源 BFS 深度分档。

用法：
  python3 scripts/generate_district_plan_inp.py \\
    --total-m3d 30000 --source-head 52 \\
    --out \"epanet  resource/example/可计算 算例管网 inp/rivervale_district.inp\"
"""

from __future__ import annotations

import argparse
import math
import random
from collections import Counter, defaultdict, deque
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

Vec2 = Tuple[float, float]

# 离散公称直径 DN（mm），GB/ISO 常用系列
DN_MM: Tuple[int, ...] = (100, 125, 150, 200, 250, 300, 350, 400, 450, 500)

# 规划分区日水量占比（合计 1.0），参考城镇混合用地综合用水结构（示意，非项目实测）
# 住宅为主、商业/公建/工业按块分配；可在脚本内据可研调整。
LAND_USE_FRACTION: Dict[str, float] = {
    "residential": 0.52,
    "commercial": 0.16,
    "school": 0.08,
    "enterprise": 0.24,
}


def dist(a: Vec2, b: Vec2) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def circumcenter(a: Vec2, b: Vec2, c: Vec2) -> Optional[Tuple[float, float]]:
    ax, ay = a
    bx, by = b
    cx, cy = c
    d = 2.0 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
    if abs(d) < 1e-18:
        return None
    a2 = ax * ax + ay * ay
    b2 = bx * bx + by * by
    c2 = cx * cx + cy * cy
    ux = (a2 * (by - cy) + b2 * (cy - ay) + c2 * (ay - by)) / d
    uy = (a2 * (cx - bx) + b2 * (ax - cx) + c2 * (bx - ax)) / d
    return ux, uy


def in_circumcircle(a: Vec2, b: Vec2, c: Vec2, p: Vec2) -> bool:
    cc = circumcenter(a, b, c)
    if cc is None:
        return False
    ux, uy = cc
    r2 = (a[0] - ux) ** 2 + (a[1] - uy) ** 2
    d2 = (p[0] - ux) ** 2 + (p[1] - uy) ** 2
    return d2 < r2 - 1e-9


def orient(a: Vec2, b: Vec2, c: Vec2) -> float:
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def bowyer_watson(points: List[Vec2]) -> List[Tuple[int, int, int]]:
    n = len(points)
    if n < 3:
        return []

    minx = min(p[0] for p in points)
    maxx = max(p[0] for p in points)
    miny = min(p[1] for p in points)
    maxy = max(p[1] for p in points)
    dx = maxx - minx
    dy = maxy - miny
    span = max(dx, dy) * 3.0 + 100.0
    midx = 0.5 * (minx + maxx)
    midy = 0.5 * (miny + maxy)

    p0 = (midx - 2.0 * span, midy - span)
    p1 = (midx + 2.0 * span, midy - span)
    p2 = (midx, midy + 2.5 * span)
    pts = list(points) + [p0, p1, p2]
    ia, ib, ic = n, n + 1, n + 2
    if orient(p0, p1, p2) < 0:
        ia, ib = ib, ia

    triangles: List[Tuple[int, int, int]] = [(ia, ib, ic)]

    for pi in range(n):
        p = pts[pi]
        bad: List[Tuple[int, int, int]] = []
        for tri in triangles:
            i, j, k = tri
            a, b, c = pts[i], pts[j], pts[k]
            if orient(a, b, c) < 0:
                a, b, c = a, c, b
                i, j, k = i, k, j
            if in_circumcircle(a, b, c, p):
                bad.append(tri)

        edge_count: Counter[Tuple[int, int]] = Counter()
        for tri in bad:
            u, v, w = tri
            for e in ((u, v), (v, w), (w, u)):
                a, b = min(e[0], e[1]), max(e[0], e[1])
                edge_count[(a, b)] += 1

        boundary = [e for e, c in edge_count.items() if c == 1]

        for tri in bad:
            triangles.remove(tri)

        for e in boundary:
            i1, i2 = e[0], e[1]
            a, b, c = pts[i1], pts[i2], p
            if orient(a, b, c) < 0:
                triangles.append((i1, i2, pi))
            else:
                triangles.append((i2, i1, pi))

    out: List[Tuple[int, int, int]] = []
    sup = {n, n + 1, n + 2}
    for tri in triangles:
        if any(t in sup for t in tri):
            continue
        out.append(tri)
    return out


def edges_from_triangles(
    triangles: List[Tuple[int, int, int]],
) -> Set[Tuple[int, int]]:
    edges: Set[Tuple[int, int]] = set()
    for i, j, k in triangles:
        for a, b in ((i, j), (j, k), (k, i)):
            if a > b:
                a, b = b, a
            edges.add((a, b))
    return edges


def collect_planning_nodes(
    width: float, height: float, rng: random.Random
) -> List[Vec2]:
    """
    不规则布点：西南—东北向略弯主干 + 短支路 + Poisson 最小间距填空，
    避免矩形网格与满三角剖分的「玩具感」。
    """
    min_d = 82.0
    pts: List[Vec2] = []
    n_bb = 7
    for k in range(n_bb):
        t = k / max(1, n_bb - 1)
        x = width * (0.06 + 0.88 * t) + rng.uniform(-30.0, 30.0)
        y = height * (0.08 + 0.82 * t + 0.14 * math.sin(t * math.pi * 1.45))
        y += rng.uniform(-24.0, 24.0)
        pts.append(
            (max(35.0, min(width - 35.0, x)), max(35.0, min(height - 35.0, y)))
        )
    for _ in range(6):
        if len(pts) < 2:
            break
        base = pts[rng.randrange(min(6, len(pts)))]
        ang = rng.uniform(-math.pi * 0.35, math.pi * 0.85)
        leg = rng.uniform(75.0, 148.0)
        for step in (1, 2):
            nx_ = base[0] + leg * step * 0.55 * math.cos(ang) + rng.uniform(-20.0, 20.0)
            ny_ = base[1] + leg * step * 0.55 * math.sin(ang) + rng.uniform(-20.0, 20.0)
            nx_ = max(30.0, min(width - 30.0, nx_))
            ny_ = max(30.0, min(height - 30.0, ny_))
            if all(dist((nx_, ny_), p) >= 52.0 for p in pts):
                pts.append((nx_, ny_))
    attempts = 0
    while len(pts) < 54 and attempts < 14000:
        attempts += 1
        x = rng.uniform(0.05 * width, 0.95 * width)
        y = rng.uniform(0.05 * height, 0.95 * height)
        if all(dist((x, y), p) >= min_d for p in pts):
            pts.append((x, y))
    return pts


def _dsu_find(parent: List[int], x: int) -> int:
    while parent[x] != x:
        parent[x] = parent[parent[x]]
        x = parent[x]
    return x


def _dsu_union(parent: List[int], rank: List[int], a: int, b: int) -> bool:
    ra, rb = _dsu_find(parent, a), _dsu_find(parent, b)
    if ra == rb:
        return False
    if rank[ra] < rank[rb]:
        parent[ra] = rb
    elif rank[ra] > rank[rb]:
        parent[rb] = ra
    else:
        parent[rb] = ra
        rank[ra] += 1
    return True


def kruskal_mst_from_edges(
    n: int, weighted_edges: List[Tuple[float, int, int]]
) -> List[Tuple[int, int]]:
    """在已给边集上求 MST（用于 Delaunay 边集上的欧氏 MST）。"""
    parent = list(range(n))
    rank = [0] * n
    mst: List[Tuple[int, int]] = []
    for w, a, b in sorted(weighted_edges):
        if _dsu_union(parent, rank, a, b):
            mst.append((a, b))
        if len(mst) == n - 1:
            break
    return mst


def build_organic_planning_network(
    width: float,
    height: float,
    rng_seed: int = 42,
) -> Tuple[List[Vec2], List[Tuple[int, int, float]]]:
    """
    Delaunay 边集上 Kruskal 得输水树，再按长度优先补若干非树边成环。
    返回 (节点, 管段 1-based)。
    """
    rng = random.Random(rng_seed)
    nodes = collect_planning_nodes(width, height, rng)
    n = len(nodes)
    if n < 3:
        raise RuntimeError("too few junctions for a network")

    tris = bowyer_watson(nodes)
    del_edges = edges_from_triangles(tris)
    weighted: List[Tuple[float, int, int]] = []
    for a, b in del_edges:
        pa, pb = nodes[a], nodes[b]
        w = dist(pa, pb)
        if w < 1e-6:
            continue
        weighted.append((w, a, b))

    mst = kruskal_mst_from_edges(n, weighted)
    mst_set = {tuple(sorted((a, b))) for a, b in mst}

    # 环网：在余下 Delaunay 边中优先加较短边，数量与规模成比例
    extra_target = max(8, min(52, int(round(n * 0.62))))
    candidates: List[Tuple[float, int, int]] = []
    for a, b in del_edges:
        key = tuple(sorted((a, b)))
        if key in mst_set:
            continue
        pa, pb = nodes[a], nodes[b]
        w = dist(pa, pb)
        if w < 1e-6:
            continue
        candidates.append((w, a, b))
    candidates.sort(key=lambda t: t[0])

    pipe_keys: Set[Tuple[int, int]] = set(mst_set)
    for w, a, b in candidates:
        if len(pipe_keys) >= (n - 1) + extra_target:
            break
        pipe_keys.add(tuple(sorted((a, b))))

    pipes: List[Tuple[int, int, float]] = []
    for a, b in sorted(pipe_keys):
        pa, pb = nodes[a], nodes[b]
        L = dist(pa, pb)
        if L < 1e-6:
            continue
        pipes.append((a + 1, b + 1, L))

    return nodes, pipes


def land_use_at(p: Vec2) -> str:
    """
    用地类型（示意平面分区）：东翼企业、北部教育、中心商业、其余住宅。
    坐标单位 m，范围约 0..width × 0..height。
    """
    x, y = p
    if x > 920.0 and 180.0 < y < 780.0:
        return "enterprise"
    if y > 720.0 and 350.0 < x < 720.0:
        return "school"
    dx = (x - 620.0) / 240.0
    dy = (y - 420.0) / 200.0
    if dx * dx + dy * dy <= 1.0:
        return "commercial"
    return "residential"


def m3d_to_total_lps(total_m3d: float) -> float:
    """日总 m³/d → 平均 LPS（24h 平均流量）。"""
    return total_m3d * 1000.0 / 86400.0


def pattern_24h_normalized(kind: str) -> List[float]:
    """24 小时乘子，均值归一为 1.0，与基值相乘后日积分与基值日量一致。"""
    raw: List[float] = []
    for h in range(24):
        if kind == "residential":
            if h <= 5 or h >= 23:
                raw.append(0.38)
            elif 6 <= h <= 8:
                raw.append(1.12)
            elif 9 <= h <= 16:
                raw.append(0.88)
            elif 17 <= h <= 22:
                raw.append(1.25)
            else:
                raw.append(1.0)
        elif kind == "commercial":
            if 9 <= h <= 20:
                raw.append(1.28)
            elif 7 <= h <= 8 or 21 <= h <= 22:
                raw.append(0.95)
            else:
                raw.append(0.42)
        elif kind == "school":
            if 8 <= h <= 16:
                raw.append(1.35)
            elif h in (7, 17):
                raw.append(0.75)
            else:
                raw.append(0.28)
        else:  # enterprise
            if 8 <= h <= 18:
                raw.append(1.08)
            else:
                raw.append(0.92)
    m = sum(raw) / 24.0
    return [v / m for v in raw]


def format_pattern_lines(pat_id: int, mults: List[float]) -> List[str]:
    """每行 6 个乘子，共 4 行 = 24 h。"""
    lines: List[str] = []
    for row in range(0, 24, 6):
        chunk = mults[row : row + 6]
        s = " ".join(f"{x:.4f}".rjust(10) for x in chunk)
        lines.append(f" {pat_id:<16}{s}")
    return lines


def build_adj(n_nodes: int, pipes: List[Tuple[int, int, float]]) -> Dict[int, List[int]]:
    adj: Dict[int, List[int]] = defaultdict(list)
    for a, b, _ in pipes:
        adj[a].append(b)
        adj[b].append(a)
    return adj


def bfs_depth(
    n_nodes: int, adj: Dict[int, List[int]], sources: Tuple[int, int]
) -> List[int]:
    depth = [-1] * (n_nodes + 1)
    q: deque[int] = deque()
    for s in sources:
        if 1 <= s <= n_nodes:
            depth[s] = 0
            q.append(s)
    while q:
        u = q.popleft()
        for v in adj[u]:
            if depth[v] == -1:
                depth[v] = depth[u] + 1
                q.append(v)
    return depth


def dn_for_edge(
    depth: List[int], a: int, b: int, max_depth_observed: int
) -> int:
    da = depth[a] if 0 <= a < len(depth) and depth[a] >= 0 else max_depth_observed
    db = depth[b] if 0 <= b < len(depth) and depth[b] >= 0 else max_depth_observed
    md = min(da, db)
    if max_depth_observed <= 0:
        return DN_MM[len(DN_MM) // 2]
    t = 1.0 - min(md / max_depth_observed, 1.0)
    idx = int(t * (len(DN_MM) - 1) + 1e-9)
    idx = max(0, min(len(DN_MM) - 1, idx))
    return DN_MM[idx]


def pick_two_sources(nodes: List[Vec2]) -> Tuple[int, int]:
    sw = min(range(1, len(nodes) + 1), key=lambda k: nodes[k - 1][0] + nodes[k - 1][1])
    ne = max(range(1, len(nodes) + 1), key=lambda k: nodes[k - 1][0] + nodes[k - 1][1])
    if sw == ne and len(nodes) > 1:
        ne = 2 if sw == 1 else 1
    return sw, ne


def emit_inp(
    out_path: Path,
    total_m3d: float,
    source_head_m: float,
) -> None:
    width, height = 1280.0, 960.0
    nodes, pipes = build_organic_planning_network(width, height, rng_seed=42)

    n_j = len(nodes)
    src1, src2 = pick_two_sources(nodes)

    # 用地与水量分配（水源节点不参与配水，在分配时排除）
    zone_nodes: Dict[str, List[int]] = defaultdict(list)
    for k in range(1, n_j + 1):
        z = land_use_at(nodes[k - 1])
        zone_nodes[z].append(k)

    total_lps = m3d_to_total_lps(total_m3d)
    demand_lps: Dict[int, float] = {}
    orphan_lps = 0.0
    for z, frac in LAND_USE_FRACTION.items():
        q_zone = total_lps * frac
        ids = [k for k in zone_nodes[z] if k not in (src1, src2)]
        if not ids:
            orphan_lps += q_zone
            continue
        q_each = q_zone / len(ids)
        for k in ids:
            demand_lps[k] = q_each

    if orphan_lps > 1e-9:
        res_ids = [k for k in zone_nodes["residential"] if k not in (src1, src2)]
        if res_ids:
            add = orphan_lps / len(res_ids)
            for k in res_ids:
                demand_lps[k] = demand_lps.get(k, 0.0) + add
        else:
            all_d = [k for k in range(1, n_j + 1) if k not in (src1, src2)]
            if all_d:
                add = orphan_lps / len(all_d)
                for k in all_d:
                    demand_lps[k] = demand_lps.get(k, 0.0) + add

    pat_ids = {"residential": 1, "commercial": 2, "school": 3, "enterprise": 4}
    patterns = {k: pattern_24h_normalized(k) for k in pat_ids}

    adj = build_adj(n_j, pipes)
    depth = bfs_depth(n_j, adj, (src1, src2))
    valid_d = [depth[i] for i in range(1, n_j + 1) if depth[i] >= 0]
    max_dep = max(valid_d) if valid_d else 1

    w_src = max(3, len(str(n_j)))
    lines: List[str] = []
    lines.append("[TITLE]")
    lines.append(
        f"Rivervale district — planned mixed use, {total_m3d:g} m3/d, dual sources (EPANET 2.2)."
    )
    lines.append("")
    lines.append("[JUNCTIONS]")
    lines.append(";ID               Elev        Demand      Pattern")
    for k in range(1, n_j + 1):
        jid = f"J{k:0{w_src}d}"
        if k in (src1, src2):
            dem, pat = 0.0, ""
        else:
            dem = demand_lps.get(k, 0.0)
            z = land_use_at(nodes[k - 1])
            pid = pat_ids.get(z, 1)
            pat = str(pid)
        lines.append(f" {jid:<16} 0.0         {dem:<11g} {pat}")

    lines.append("")
    lines.append("[RESERVOIRS]")
    lines.append(";ID               Head            Pattern")
    lines.append(f" R1               {source_head_m:.1f}")
    lines.append(f" R2               {source_head_m:.1f}")
    lines.append("")

    lines.append("[TANKS]")
    lines.append("")

    lines.append("[PIPES]")
    lines.append(
        ";ID               Node1           Node2           Length  Diameter Roughness MinorLoss Status"
    )
    for idx, (a, b, L) in enumerate(pipes, start=1):
        pid = f"P{idx:04d}"
        dmm = dn_for_edge(depth, a, b, max_dep)
        lines.append(
            f" {pid:<16} J{a:0{w_src}d}            J{b:0{w_src}d}            {L:7.1f} {dmm:7d} 110       0         Open"
        )

    lines.append("")
    lines.append("[PUMPS]")
    lines.append(";ID               Node1           Node2           Parameters")
    lines.append(f" PUMP01           R1              J{src1:0{w_src}d}            HEAD 1")
    lines.append(f" PUMP02           R2              J{src2:0{w_src}d}            HEAD 1")
    lines.append("")

    lines.append("[VALVES]")
    lines.append("")
    lines.append("[TAGS]")
    lines.append("")
    lines.append("[DEMANDS]")
    lines.append("")
    lines.append("[STATUS]")
    lines.append("")

    lines.append("[PATTERNS]")
    lines.append(";ID               Multipliers (24 h, 4×6)")
    for key, pid in pat_ids.items():
        lines.extend(format_pattern_lines(pid, patterns[key]))
    lines.append("")

    lines.append("[CURVES]")
    lines.append(";ID               X-Value         Y-Value")
    lines.append(" 1                0               55")
    lines.append(" 1                200             42")
    lines.append(" 1                800             28")
    lines.append(" 1                2000            12")
    lines.append("")

    lines.append("[CONTROLS]")
    lines.append("")
    lines.append("[RULES]")
    lines.append("")

    lines.append("[ENERGY]")
    lines.append(" Global Efficiency      75")
    lines.append(" Global Price           0")
    lines.append(" Demand Charge          0")
    lines.append("")

    lines.append("[EMITTERS]")
    lines.append("")
    lines.append("[QUALITY]")
    lines.append("")
    lines.append("[SOURCES]")
    lines.append("")

    lines.append("[REACTIONS]")
    lines.append(" Order Bulk             0")
    lines.append(" Order Tank             0")
    lines.append(" Order Wall             0")
    lines.append(" Global Bulk            0")
    lines.append(" Global Wall            0")
    lines.append(" Limiting Potential     0")
    lines.append(" Roughness Correlation  0")
    lines.append("")

    lines.append("[MIXING]")
    lines.append("")

    lines.append("[TIMES]")
    lines.append(" Duration               24:00")
    lines.append(" Hydraulic Timestep     1:00")
    lines.append(" Quality Timestep       1:00")
    lines.append(" Pattern Timestep       1:00")
    lines.append(" Pattern Start          0:00")
    lines.append(" Report Timestep        1:00")
    lines.append(" Report Start           0:00")
    lines.append(" Start ClockTime        12 am")
    lines.append(" Statistic              None")
    lines.append("")

    lines.append("[REPORT]")
    lines.append(" Status                 Yes")
    lines.append(" Summary                No")
    lines.append(" Page                   0")
    lines.append("")

    lines.append("[OPTIONS]")
    lines.append(" Units                  LPS")
    lines.append(" Headloss               H-W")
    lines.append(" Specific Gravity       1")
    lines.append(" Viscosity              1")
    lines.append(" Trials                 40")
    lines.append(" Accuracy               0.001")
    lines.append(" CHECKFREQ              2")
    lines.append(" MAXCHECK               10")
    lines.append(" DAMPLIMIT              0")
    lines.append(" Unbalanced             Continue 10")
    lines.append(" Pattern                1")
    lines.append(" Demand Multiplier      1")
    lines.append(" Emitter Exponent       0.5")
    lines.append(" Quality                NONE")
    lines.append(" Diffusivity            1")
    lines.append(" Tolerance              0.01")
    lines.append("")

    x0 = min(p[0] for p in nodes)
    y0 = min(p[1] for p in nodes)
    sx1, sy1 = nodes[src1 - 1]
    sx2, sy2 = nodes[src2 - 1]
    lines.append("[COORDINATES]")
    lines.append(";Node             X-Coord         Y-Coord")
    lines.append(f" R1               {sx1 - x0 - 200:15.1f} {sy1 - y0:15.1f}")
    lines.append(f" R2               {sx2 - x0 + 200:15.1f} {sy2 - y0:15.1f}")
    for k in range(1, n_j + 1):
        x, y = nodes[k - 1]
        lines.append(f" J{k:0{w_src}d}            {x - x0:15.1f} {y - y0:15.1f}")

    lines.append("")
    lines.append("[VERTICES]")
    lines.append("")
    lines.append("[END]")
    lines.append("")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines), encoding="utf-8")

    sum_dem = sum(demand_lps.values())
    print(
        f"Wrote {out_path}\n"
        f"  Parameters: total_m3d={total_m3d:g}, source_head_m={source_head_m:g}\n"
        f"  Average total flow ≈ {total_lps:.4f} LPS (= {total_m3d:g} m³/d / 86400 × 1000)\n"
        f"  Sum of base demands ≈ {sum_dem:.4f} LPS\n"
        f"  Junctions: {n_j}, pipes: {len(pipes)}, "
        f"topology: organic (MST + Delaunay loop chords, seed=42)\n"
        f"  Land use zones: { {k: len(v) for k, v in zone_nodes.items()} }\n"
        f"  Pumps: R1→J{src1:0{w_src}d}, R2→J{src2:0{w_src}d}"
    )


def main() -> None:
    ap = argparse.ArgumentParser(
        description="规划区给水管网 .inp（双水源、用地分配；仅 total-m3d 与 source-head 为约束参数）"
    )
    ap.add_argument(
        "--total-m3d",
        type=float,
        default=30000.0,
        help="区域日总需水量 (m³/d)，例如 30000 表示 3 万 m³/d",
    )
    ap.add_argument(
        "--source-head",
        type=float,
        default=52.0,
        help="两座水库水头 (m)，同一标高",
    )
    ap.add_argument(
        "--out",
        type=Path,
        default=Path("epanet  resource/example/可计算 算例管网 inp/rivervale_district.inp"),
        help="输出 .inp 路径",
    )
    args = ap.parse_args()
    root = Path(__file__).resolve().parents[1]
    out = args.out if args.out.is_absolute() else root / args.out
    emit_inp(out, total_m3d=args.total_m3d, source_head_m=args.source_head)


if __name__ == "__main__":
    main()
