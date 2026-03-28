#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 Amberfield 双水源公制演示管网（约 100 管段）。

拓扑：平面 Delaunay 三角网（不规则点集）→ 边为道路中心线；面以三角形为主，
并夹杂四边形、五边形等（取决于剖分与长边剖分），避免「整齐 4×4 街区」观感。

管径：采用工程常用离散公称直径 DN（mm），不按连续区间取模。
分配：以两水源为根做多源 BFS，hop 越小越靠近主干 → 取较大 DN；末端取较小 DN。

依赖：仅 Python 标准库。
"""

from __future__ import annotations

import math
from collections import Counter, defaultdict, deque
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

Vec2 = Tuple[float, float]

# ---------------------------------------------------------------------------
# 离散管径（分析说明，见脚本顶部文档）
# 参照 GB/T 常用给水塑料管 / 球墨铸铁管公称直径系列，取 10 档覆盖 100–500 mm，
# 不含非标准中间值；算例中按「距水源 hop」分桶映射，模拟主干→支管。
# ---------------------------------------------------------------------------
DN_MM: Tuple[int, ...] = (100, 125, 150, 200, 250, 300, 350, 400, 450, 500)


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
    """点 p 是否在三角形 abc 外接圆内（a,b,c 须为逆时针）。"""
    cc = circumcenter(a, b, c)
    if cc is None:
        return False
    ux, uy = cc
    r2 = (a[0] - ux) ** 2 + (a[1] - uy) ** 2
    d2 = (p[0] - ux) ** 2 + (p[1] - uy) ** 2
    return d2 < r2 - 1e-9


def orient(a: Vec2, b: Vec2, c: Vec2) -> float:
    """叉积 (b-a)×(c-a)，>0 则 c 在 ab 左侧。"""
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def bowyer_watson(points: List[Vec2]) -> List[Tuple[int, int, int]]:
    """二维 Delaunay 三角剖分，返回三角形顶点索引（逆时针）。"""
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


def deterministic_irregular_points(
    target: int,
    min_dist: float,
    width: float,
    height: float,
) -> List[Vec2]:
    """确定性「类 Poisson」点集，避免规则网格。"""
    pts: List[Vec2] = []
    for k in range(80000):
        if len(pts) >= target:
            break
        t = k * 0.618033988749895
        x = (math.sin(t * 2.17) * 0.48 + 0.52) * width
        y = (math.cos(t * 1.63) * 0.48 + 0.52) * height
        x += 55.0 * math.sin(k * 0.31 + 1.2)
        y += 48.0 * math.cos(k * 0.27 - 0.7)
        x = max(0.0, min(width, x))
        y = max(0.0, min(height, y))
        if all(dist((x, y), p) >= min_dist for p in pts):
            pts.append((x, y))
    return pts


def subdivide_long_edges(
    points: List[Vec2],
    edges: Set[Tuple[int, int]],
    target_m: float,
    max_tol: float = 0.5,
) -> Tuple[List[Vec2], List[Tuple[int, int, float]]]:
    """将长度超过 target_m 的边在直线上插点剖分，保持平面嵌入。"""
    pts = list(points)
    edge_list = sorted(edges)
    new_edges: List[Tuple[int, int, float]] = []

    def find_or_add(p: Vec2) -> int:
        for idx, q in enumerate(pts):
            if dist(p, q) < max_tol:
                return idx + 1
        pts.append(p)
        return len(pts)

    for a0, b0 in edge_list:
        pa, pb = pts[a0], pts[b0]
        L = dist(pa, pb)
        if L < 1e-6:
            continue
        # 用 ceil：保证长边被拆成多段，管长接近 target_m（round 会把长边留成一条超长管）
        nseg = max(1, int(math.ceil(L / target_m - 1e-12)))
        if nseg == 1:
            new_edges.append((a0 + 1, b0 + 1, L))
            continue
        chain: List[int] = []
        for s in range(nseg):
            t = s / nseg
            x = pa[0] + t * (pb[0] - pa[0])
            y = pa[1] + t * (pb[1] - pa[1])
            chain.append(find_or_add((x, y)))
        chain.append(find_or_add(pb))
        # 去重链上连续重复
        slim: List[int] = []
        for nid in chain:
            if not slim or slim[-1] != nid:
                slim.append(nid)
        for u, v in zip(slim, slim[1:]):
            if u == v:
                continue
            d = dist(pts[u - 1], pts[v - 1])
            if d < 1e-3:
                continue
            a, b = (u, v) if u < v else (v, u)
            new_edges.append((a, b, d))

    # 去重无向边（保留较短记录或合并）
    best: Dict[Tuple[int, int], float] = {}
    for a, b, d in new_edges:
        if a > b:
            a, b = b, a
        key = (a, b)
        if key not in best:
            best[key] = d
    merged = [(a, b, best[(a, b)]) for a, b in sorted(best.keys())]
    return pts, merged


def build_adj(n_nodes: int, pipes: List[Tuple[int, int, float]]) -> Dict[int, List[int]]:
    adj: Dict[int, List[int]] = defaultdict(list)
    for a, b, _ in pipes:
        adj[a].append(b)
        adj[b].append(a)
    return adj


def bfs_depth_from_sources(
    n_nodes: int, adj: Dict[int, List[int]], sources: Tuple[int, int]
) -> List[int]:
    """多源 BFS，depth[v]=到任一水源的最短 hop（水源为 0）。"""
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
    depth: List[int],
    a: int,
    b: int,
    max_depth_observed: int,
) -> int:
    """按距水源较近端 hop 映射离散 DN；hop 小 → 大管径。"""
    da = depth[a] if a < len(depth) and depth[a] >= 0 else max_depth_observed
    db = depth[b] if b < len(depth) and depth[b] >= 0 else max_depth_observed
    md = min(da, db)
    if max_depth_observed <= 0:
        return DN_MM[len(DN_MM) // 2]
    # 靠近水源（md 小）→ 高索引（大 DN）
    t = 1.0 - min(md / max_depth_observed, 1.0)
    idx = int(t * (len(DN_MM) - 1) + 1e-9)
    idx = max(0, min(len(DN_MM) - 1, idx))
    return DN_MM[idx]


def pick_two_sources(nodes: List[Vec2]) -> Tuple[int, int]:
    best_sw = min(range(1, len(nodes) + 1), key=lambda k: nodes[k - 1][0] + nodes[k - 1][1])
    best_ne = max(range(1, len(nodes) + 1), key=lambda k: nodes[k - 1][0] + nodes[k - 1][1])
    if best_sw == best_ne and len(nodes) > 1:
        best_ne = 2 if best_sw == 1 else 1
    return best_sw, best_ne


def emit_inp(out_path: Path) -> None:
    # 不规则点数 + Delaunay → 三角网边；再按 target_m 剖分至 ~100 管段
    width, height = 1250.0, 920.0
    # 锚点数 + Delaunay 边数 + ceil 剖分共同决定管段条数；以下为 ~100 管段、管长约 100m 量级的标定
    n_pts = 13
    min_d = 128.0
    raw_pts = deterministic_irregular_points(n_pts, min_d, width, height)
    tris = bowyer_watson(raw_pts)
    edges = edges_from_triangles(tris)
    target_m = 138.0
    nodes, pipes = subdivide_long_edges(raw_pts, edges, target_m)

    n_j = len(nodes)
    src1, src2 = pick_two_sources(nodes)
    adj = build_adj(n_j, pipes)
    depth = bfs_depth_from_sources(n_j, adj, (src1, src2))
    valid_depths = [d for d in depth[1:] if d >= 0]
    max_dep = max(valid_depths) if valid_depths else 1

    demand_nodes = n_j - 2
    total_lps = 50.0
    d_each = total_lps / max(1, demand_nodes)

    lines: List[str] = []
    lines.append("[TITLE]")
    lines.append(
        "Amberfield — Delaunay street mesh, discrete DN, twin sources (EPANET 2.2, metric)."
    )
    lines.append("")
    lines.append("[JUNCTIONS]")
    lines.append(";ID               Elev        Demand      Pattern")
    w_src = max(3, len(str(n_j)))
    for k in range(1, n_j + 1):
        jid = f"J{k:0{w_src}d}"
        if k in (src1, src2):
            dem, pat = 0.0, ""
        else:
            dem, pat = d_each, "1"
        lines.append(f" {jid:<16} 0.0         {dem:<11g} {pat}")

    lines.append("")
    lines.append("[RESERVOIRS]")
    lines.append(";ID               Head            Pattern")
    lines.append(" R1               52.0")
    lines.append(" R2               52.0")
    lines.append("")

    lines.append("[TANKS]")
    lines.append("")

    lines.append("[PIPES]")
    lines.append(
        ";ID               Node1           Node2           Length  Diameter Roughness MinorLoss Status"
    )
    for k, (a, b, L) in enumerate(pipes, start=1):
        pid = f"P{k:03d}"
        a1 = f"J{a:0{w_src}d}"
        a2 = f"J{b:0{w_src}d}"
        dmm = dn_for_edge(depth, a, b, max_dep)
        lines.append(
            f" {pid:<16} {a1:<15} {a2:<15} {L:7.1f} {dmm:7d} 110       0         Open"
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
    lines.append(";ID               Multipliers")
    lines.append(" 1                1.0         1.0         1.0         1.0         1.0         1.0")
    lines.append(" 1                1.0         1.0         1.0         1.0         1.0         1.0")
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
    lines.append(f" R1               {sx1 - x0 - 180:15.1f} {sy1 - y0:15.1f}")
    lines.append(f" R2               {sx2 - x0 + 180:15.1f} {sy2 - y0:15.1f}")
    for k in range(1, n_j + 1):
        x, y = nodes[k - 1]
        lines.append(f" J{k:0{w_src}d}            {x - x0:15.1f} {y - y0:15.1f}")

    lines.append("")
    lines.append("[VERTICES]")
    lines.append("")
    lines.append("[END]")
    lines.append("")

    out_path.write_text("\n".join(lines), encoding="utf-8")
    dn_str = ", ".join(str(d) for d in DN_MM)
    j1 = f"J{src1:0{w_src}d}"
    j2 = f"J{src2:0{w_src}d}"
    print(
        f"Wrote {out_path}\n"
        f"  topology: Delaunay triangulation on irregular points (not rectilinear blocks)\n"
        f"  discrete DN (mm): {dn_str}\n"
        f"  junctions: {n_j}, pipes: {len(pipes)}, pumps: R1→{j1}, R2→{j2}\n"
        f"  BFS max depth: {max_dep}, target edge length ~{target_m:g} m\n"
        f"  demand total: {total_lps:g} LPS"
    )


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    out = root / "epanet  resource/example/可计算 算例管网 inp/amberfield.inp"
    emit_inp(out)


if __name__ == "__main__":
    main()
