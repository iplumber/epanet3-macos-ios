#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从 OpenStreetMap（Overpass API）拉取道路折线，生成 EPANET 3 风格 .inp（沿路管段）。

选用 OSM 的原因：同一 bbox 内可批量导出路网几何；高德/百度路径 API 面向起终点算路，
要铺 500～5000+ 条管段需海量请求且不覆盖「全路网」。

依赖：仅 Python 3 标准库（urllib / json / math / argparse）。

示例（厦门本岛示意范围，约 primary～tertiary，管段数随 OSM 数据变化）：
  python3 scripts/osm_roads_to_inp.py \\
    --bbox 24.42,118.04,24.53,118.18 \\
    --out "epanet  resource/example/可计算 算例管网 inp/xiamen_island_osm.inp"

更多管段：加 --include-residential 或略放大 --bbox；默认不限制管段数（--max-edges 0）。
小谷围扩大 bbox 预设：--preset xiaoguwei（可与 --from-json 联用）。

EPANET 2.2 输出：加 --epanet22（[OPTIONS] 无 EPANET3 扩展项；需水量 Pattern 为数字 ID 1）。

Overpass 易 504：可先 curl 保存 JSON，再 --from-json 离线生成，例如：
  curl -sS --max-time 180 -X POST -d @query.txt \\
    https://lz4.overpass-api.de/api/interpreter -o scripts/xiaoguwei_overpass_osm.json
  python3 scripts/osm_roads_to_inp.py --from-json scripts/xiaoguwei_overpass_osm.json \\
    --preset xiaoguwei --epanet22 \\
    --out \"epanet  resource/example/可计算 算例管网 inp/guangzhou_xiaoguwei_osm_epanet22.inp\"

默认：不限制 --max-edges；保留全部连通分量（每分量 Rk+PUMP）；平行边去重可关 --no-dedupe；
仅最大块：--largest-component-only。
"""

from __future__ import annotations

import argparse
import json
import math
import sys
import urllib.error
import urllib.request
from collections import defaultdict
from typing import Dict, List, Optional, Set, Tuple

# 小谷围岛：略扩大 bbox（矩形会含岛外道路；完整岛内裁剪可后续做多边形）
XIAOGUWEI_BBOX = "23.015,113.338,23.105,113.438"
DEFAULT_INP_TITLE = "OSM roads -> pipes (Xiamen bbox demo). Not survey-grade."
XIAOGUWEI_INP_TITLE = "Guangzhou Xiaoguwei Island OSM roads (EPANET). Not survey-grade."

# --- 地球坐标近似：管长（米） ---
def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlmb = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlmb / 2) ** 2
    return 2 * r * math.asin(min(1.0, math.sqrt(a)))


def latlon_to_xy_m(
    lat: float, lon: float, lat0: float, lon0: float
) -> Tuple[float, float]:
    """本地切平面近似：原点在 (lat0,lon0)，X 东向、Y 北向，单位米。"""
    cos_lat = math.cos(math.radians(lat0))
    x = (lon - lon0) * cos_lat * 111_320.0
    y = (lat - lat0) * 110_540.0
    return x, y


def overpass_query(bbox: Tuple[float, float, float, float], highway_regex: str) -> str:
    south, west, north, east = bbox
    # out geom：折线顶点；道路类由正则筛选（可调）
    return f"""[out:json][timeout:300];
(
  way["highway"~"{highway_regex}"]({south},{west},{north},{east});
);
out geom;
"""


def fetch_overpass(query: str, endpoint: str) -> dict:
    data = query.encode("utf-8")
    req = urllib.request.Request(
        endpoint,
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded; charset=UTF-8"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=300) as resp:
        return json.loads(resp.read().decode("utf-8"))


def snap_key(lat: float, lon: float, decimals: int = 6) -> Tuple[float, float]:
    """合并交叉口附近重复点：约 0.1m 量级可再调 decimals。"""
    return (round(lat, decimals), round(lon, decimals))


def build_graph(
    osm_json: dict,
    max_edges: int,
) -> Tuple[Dict[Tuple[float, float], int], List[Tuple[int, int, float]]]:
    """
    返回：
      junc_index: (lat,lon)键 -> 连续整数节点号 0..N-1
      edges: 列表 (i, j, length_m)，无向去重只存 i<j
    """
    elements = osm_json.get("elements", [])
    edge_set: Set[Tuple[int, int]] = set()
    edges: List[Tuple[int, int, float]] = []

    key_to_idx: Dict[Tuple[float, float], int] = {}
    next_idx = 0

    def idx_for_key(k: Tuple[float, float]) -> int:
        nonlocal next_idx
        if k not in key_to_idx:
            key_to_idx[k] = next_idx
            next_idx += 1
        return key_to_idx[k]

    for el in elements:
        if el.get("type") != "way":
            continue
        geom = el.get("geometry")
        if not geom or len(geom) < 2:
            continue
        for i in range(len(geom) - 1):
            if max_edges > 0 and len(edges) >= max_edges:
                return invert_junction_map(key_to_idx), edges
            la1, lo1 = geom[i]["lat"], geom[i]["lon"]
            la2, lo2 = geom[i + 1]["lat"], geom[i + 1]["lon"]
            k1 = snap_key(la1, lo1)
            k2 = snap_key(la2, lo2)
            if k1 == k2:
                continue
            i1 = idx_for_key(k1)
            i2 = idx_for_key(k2)
            a, b = (i1, i2) if i1 < i2 else (i2, i1)
            if (a, b) in edge_set:
                continue
            edge_set.add((a, b))
            d = haversine_m(k1[0], k1[1], k2[0], k2[1])
            if d < 0.05:  # 极短边跳过
                continue
            edges.append((a, b, d))

    return invert_junction_map(key_to_idx), edges


def invert_junction_map(key_to_idx: Dict[Tuple[float, float], int]) -> Dict[int, Tuple[float, float]]:
    idx_to_latlon: Dict[int, Tuple[float, float]] = {}
    for k, v in key_to_idx.items():
        idx_to_latlon[v] = k
    return idx_to_latlon


def largest_connected_component(
    idx_to_latlon: Dict[int, Tuple[float, float]],
    edges: List[Tuple[int, int, float]],
) -> Tuple[Dict[int, Tuple[float, float]], List[Tuple[int, int, float]]]:
    """只保留边集的最大连通分量，节点重编号为 0..n-1，便于单水源求解。"""
    if not edges:
        return idx_to_latlon, edges
    adj: Dict[int, List[int]] = defaultdict(list)
    nodes: Set[int] = set()
    for a, b, _ in edges:
        nodes.add(a)
        nodes.add(b)
        adj[a].append(b)
        adj[b].append(a)

    best: Set[int] = set()
    unseen = set(nodes)
    while unseen:
        start = next(iter(unseen))
        comp = {start}
        stack = [start]
        unseen.discard(start)
        while stack:
            u = stack.pop()
            for v in adj[u]:
                if v not in comp:
                    comp.add(v)
                    unseen.discard(v)
                    stack.append(v)
        if len(comp) > len(best):
            best = comp

    remap = {old: i for i, old in enumerate(sorted(best))}
    new_idx: Dict[int, Tuple[float, float]] = {
        remap[i]: idx_to_latlon[i] for i in best if i in idx_to_latlon
    }
    new_edges: List[Tuple[int, int, float]] = []
    for a, b, d in edges:
        if a in remap and b in remap:
            na, nb = remap[a], remap[b]
            if na > nb:
                na, nb = nb, na
            new_edges.append((na, nb, d))
    # 去重（不同 way 可能重复同边）
    seen_e: Set[Tuple[int, int]] = set()
    deduped: List[Tuple[int, int, float]] = []
    for a, b, d in new_edges:
        if (a, b) in seen_e:
            continue
        seen_e.add((a, b))
        deduped.append((a, b, d))
    return new_idx, deduped


def find_connected_components(
    edges: List[Tuple[int, int, float]],
) -> List[Set[int]]:
    """按无向边划分连通分量（节点为边中出现的下标）。"""
    if not edges:
        return []
    adj: Dict[int, List[int]] = defaultdict(list)
    nodes: Set[int] = set()
    for a, b, _ in edges:
        nodes.add(a)
        nodes.add(b)
        adj[a].append(b)
        adj[b].append(a)
    unseen = set(nodes)
    comps: List[Set[int]] = []
    while unseen:
        start = next(iter(unseen))
        comp: Set[int] = {start}
        stack = [start]
        unseen.discard(start)
        while stack:
            u = stack.pop()
            for v in adj[u]:
                if v not in comp:
                    comp.add(v)
                    unseen.discard(v)
                    stack.append(v)
        comps.append(comp)
    comps.sort(key=lambda c: min(c))
    return comps


def pick_source_junctions_all_components(
    idx_to_latlon: Dict[int, Tuple[float, float]],
    edges: List[Tuple[int, int, float]],
) -> List[int]:
    """每个连通分量选最西节点（min 经度）作为泵接入点。"""
    out: List[int] = []
    for comp in find_connected_components(edges):
        out.append(min(comp, key=lambda i: idx_to_latlon[i][1]))
    return out


def pick_source_junction(
    idx_to_latlon: Dict[int, Tuple[float, float]], edges: List[Tuple[int, int, float]]
) -> int:
    """选「最西」节点作为泵房接入点（示意：靠近大陆一侧）。"""
    involved = set()
    for a, b, _ in edges:
        involved.add(a)
        involved.add(b)
    best = min(involved, key=lambda i: idx_to_latlon[i][1])  # min lon
    return best


def dedupe_parallel_edges(
    edges: List[Tuple[int, int, float]],
    idx_to_latlon: Dict[int, Tuple[float, float]],
    mid_dist_m: float = 35.0,
    cos_parallel: float = 0.88,
    min_len_ratio: float = 0.45,
    cell_m: float = 50.0,
) -> List[Tuple[int, int, float]]:
    """
    对上下行/平行重复的道路边做几何去重：中点接近、方向平行（同向或反向）、长度相近时保留较长边。
    """
    if not edges:
        return edges
    lats = [idx_to_latlon[i][0] for i in idx_to_latlon]
    lons = [idx_to_latlon[i][1] for i in idx_to_latlon]
    lat0, lon0 = min(lats), min(lons)

    def edge_geom(a: int, b: int, d: float) -> Tuple[float, float, float, float, float]:
        la1, lo1 = idx_to_latlon[a]
        la2, lo2 = idx_to_latlon[b]
        x1, y1 = latlon_to_xy_m(la1, lo1, lat0, lon0)
        x2, y2 = latlon_to_xy_m(la2, lo2, lat0, lon0)
        dx, dy = x2 - x1, y2 - y1
        L = math.hypot(dx, dy)
        if L < 1e-9:
            return 0.0, 0.0, 1.0, 0.0, d
        vx, vy = dx / L, dy / L
        mx, my = (x1 + x2) * 0.5, (y1 + y2) * 0.5
        return mx, my, vx, vy, d

    enriched: List[Tuple[float, float, float, float, float, int, int]] = []
    for a, b, d in edges:
        mx, my, vx, vy, dd = edge_geom(a, b, d)
        enriched.append((mx, my, vx, vy, dd, a, b))

    enriched.sort(key=lambda t: -t[4])

    grid: Dict[Tuple[int, int], List[Tuple[float, float, float, float, float]]] = defaultdict(list)
    kept: List[Tuple[int, int, float]] = []

    for mx, my, vx, vy, d, a, b in enriched:
        cx, cy = int(mx / cell_m), int(my / cell_m)
        duplicate = False
        for dcx in (-1, 0, 1):
            for dcy in (-1, 0, 1):
                for kmx, kmy, kvx, kvy, kd in grid.get((cx + dcx, cy + dcy), []):
                    if math.hypot(mx - kmx, my - kmy) > mid_dist_m:
                        continue
                    dot = vx * kvx + vy * kvy
                    if abs(dot) < cos_parallel:
                        continue
                    md, Mg = min(d, kd), max(d, kd)
                    lr = md / Mg if Mg > 0 else 0.0
                    if lr < min_len_ratio:
                        continue
                    duplicate = True
                    break
                if duplicate:
                    break
            if duplicate:
                break
        if not duplicate:
            kept.append((a, b, d))
            grid[(cx, cy)].append((mx, my, vx, vy, d))

    kept.sort(key=lambda e: (e[0], e[1]))
    return kept


def emit_inp(
    idx_to_latlon: Dict[int, Tuple[float, float]],
    edges: List[Tuple[int, int, float]],
    out_path: str,
    title: str,
    reservoir_head_m: float,
    demand_total_cmh: float,
    pipe_diameter_mm: float,
    roughness: float,
    source_indices: Optional[List[int]] = None,
) -> None:
    n_j = len(idx_to_latlon)
    if n_j < 2 or not edges:
        raise SystemExit("无足够节点或管段，请扩大 bbox 或放宽 highway 正则。")

    lats = [idx_to_latlon[i][0] for i in range(n_j)]
    lons = [idx_to_latlon[i][1] for i in range(n_j)]
    lat0, lon0 = min(lats), min(lons)

    if source_indices is None:
        source_indices = [pick_source_junction(idx_to_latlon, edges)]
    source_set = set(source_indices)
    # 需求按节点均分（可改为按管长加权）；每个水源节点需求为 0
    d_each = demand_total_cmh / max(1, n_j - len(source_set))

    lines: List[str] = []
    lines.append("[TITLE]")
    lines.append(title)
    lines.append("")

    lines.append("[JUNCTIONS]")
    lines.append(";ID               Elev        Demand      Pattern")
    for i in range(n_j):
        jid = f"J{i+1:05d}"
        dem = 0.0 if i in source_set else d_each
        pat = "" if i in source_set else "PAT1"
        lines.append(f" {jid:<16} 12.0        {dem:<11g} {pat}")

    lines.append("")
    lines.append("[RESERVOIRS]")
    for ri in range(len(source_indices)):
        rid = f"R{ri}"
        lines.append(f" {rid:<16} {reservoir_head_m:.1f}")
    lines.append("")

    lines.append("[TANKS]")
    lines.append("")

    lines.append("[PIPES]")
    lines.append(
        ";ID               Node1           Node2           Length  Diameter Roughness MinorLoss Status"
    )
    for k, (a, b, length_m) in enumerate(edges, start=1):
        n1 = f"J{a+1:05d}"
        n2 = f"J{b+1:05d}"
        pid = f"P{k:05d}"
        lines.append(
            f" {pid:<16} {n1:<15} {n2:<15} {length_m:7.1f} {pipe_diameter_mm:7.0f} {roughness:7.0f} 0         Open"
        )

    lines.append("")
    lines.append("[PUMPS]")
    for k, src_idx in enumerate(source_indices, start=1):
        pid = f"PUMP{k:03d}"
        rid = f"R{k-1}"
        lines.append(
            f" {pid:<16} {rid:<15} J{src_idx+1:05d}           HEAD 1"
        )
    lines.append("")

    lines.append("[VALVES]")
    lines.append("")

    lines.append("[TAGS]")
    lines.append("")

    lines.append("[DEMANDS]")
    lines.append("")

    lines.append("[LEAKAGES]")
    lines.append("")

    lines.append("[STATUS]")
    lines.append("")

    lines.append("[PATTERNS]")
    lines.append(" PAT1             0.78        0.72        0.68        0.66        0.70        0.88")
    lines.append(" PAT1             1.02        1.18        1.22        1.20        1.14        1.10")
    lines.append(" PAT1             1.06        1.05        1.02        1.02        1.06        1.12")
    lines.append(" PAT1             1.18        1.16        1.05        0.95        0.85        0.80")
    lines.append("")

    lines.append("[CURVES]")
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
    lines.append(" Order Bulk             1")
    lines.append(" Order Tank             1")
    lines.append(" Order Wall             1")
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
    lines.append("")

    lines.append("[OPTIONS]")
    lines.append(" Units                  CMH")
    lines.append(" Headloss               H-W")
    lines.append(" Specific Gravity       1")
    lines.append(" Viscosity              1")
    lines.append(" Trials                 40")
    lines.append(" Accuracy               0.001")
    lines.append(" Unbalanced             Continue")
    lines.append("")
    lines.append(" DEMAND_MODEL           FIXED")
    lines.append(" Pattern")
    lines.append(" Demand Multiplier      1")
    lines.append(" MINIMUM_PRESSURE       0")
    lines.append(" SERVICE_PRESSURE       0")
    lines.append(" PRESSURE_EXPONENT      0.5")
    lines.append("")
    lines.append(" LEAKAGE_MODEL          NONE")
    lines.append(" LEAKAGE_COEFF1         0")
    lines.append(" LEAKAGE_COEFF2         0")
    lines.append(" Emitter Exponent       0.5")
    lines.append("")
    lines.append(" Quality                None mg/L")
    lines.append(" Diffusivity            1")
    lines.append(" Tolerance              0.01")
    lines.append("")

    lines.append("[COORDINATES]")
    lines.append(";Node             X-Coord         Y-Coord")
    for ri in range(len(source_indices)):
        rid = f"R{ri}"
        rx = -80.0 * ri
        ry = 0.0
        lines.append(f" {rid:<16} {rx:15.2f} {ry:15.2f}")
    for i in range(n_j):
        la, lo = idx_to_latlon[i]
        x, y = latlon_to_xy_m(la, lo, lat0, lon0)
        jid = f"J{i+1:05d}"
        lines.append(f" {jid:<16} {x:15.2f} {y:15.2f}")

    lines.append("")
    lines.append("[VERTICES]")
    lines.append("")
    lines.append("[END]")
    lines.append("")

    text = "\n".join(lines)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(text)

    adj: Dict[int, List[int]] = defaultdict(list)
    for a, b, _ in edges:
        adj[a].append(b)
        adj[b].append(a)
    if len(source_indices) == 1:
        src_idx = source_indices[0]
        seen = {src_idx}
        stack = [src_idx]
        while stack:
            u = stack.pop()
            for v in adj[u]:
                if v not in seen:
                    seen.add(v)
                    stack.append(v)
        if len(seen) < n_j:
            print(
                f"警告: 道路子图不连通，{n_j - len(seen)} 个节点从泵接入点不可达，"
                f"EPANET 可能报错；可缩小 bbox 或只选相连道路等级。",
                file=sys.stderr,
            )

    n_src = len(source_indices)
    if n_src <= 10:
        pump_desc = ", ".join(
            f"R{k-1}→J{s+1:05d}" for k, s in enumerate(source_indices, start=1)
        )
    else:
        head = ", ".join(
            f"R{k-1}→J{s+1:05d}"
            for k, s in enumerate(source_indices[:5], start=1)
        )
        pump_desc = f"{n_src} 个（{head}, …）"

    print(
        f"已写入: {out_path}\n"
        f"  节点数(含需求 junction): {n_j}\n"
        f"  管段数: {len(edges)}\n"
        f"  水库/泵: {pump_desc}\n"
        f"  总需求约 {demand_total_cmh:g} CMH 均分到非源节点。"
    )


def emit_inp_epanet22(
    idx_to_latlon: Dict[int, Tuple[float, float]],
    edges: List[Tuple[int, int, float]],
    out_path: str,
    title: str,
    reservoir_head_m: float,
    demand_total_cmh: float,
    pipe_diameter_mm: float,
    roughness: float,
    source_indices: Optional[List[int]] = None,
) -> None:
    """
    EPANET 2.2 兼容输入：不含 EPANET 3 的 DEMAND_MODEL / LEAKAGE 等扩展选项；
    需水量 Pattern 使用数字 ID「1」（与 [OPTIONS] Pattern 一致）。
    """
    n_j = len(idx_to_latlon)
    if n_j < 2 or not edges:
        raise SystemExit("无足够节点或管段，请扩大 bbox 或放宽 highway 正则。")

    lats = [idx_to_latlon[i][0] for i in range(n_j)]
    lons = [idx_to_latlon[i][1] for i in range(n_j)]
    lat0, lon0 = min(lats), min(lons)

    if source_indices is None:
        source_indices = [pick_source_junction(idx_to_latlon, edges)]
    source_set = set(source_indices)
    d_each = demand_total_cmh / max(1, n_j - len(source_set))

    lines: List[str] = []
    lines.append("[TITLE]")
    lines.append(title)
    lines.append("")

    lines.append("[JUNCTIONS]")
    lines.append(";ID               Elev        Demand      Pattern")
    for i in range(n_j):
        jid = f"J{i+1:05d}"
        dem = 0.0 if i in source_set else d_each
        pat = "" if i in source_set else "1"
        lines.append(f" {jid:<16} 12.0        {dem:<11g} {pat}")

    lines.append("")
    lines.append("[RESERVOIRS]")
    lines.append(";ID               Head            Pattern")
    for ri in range(len(source_indices)):
        rid = f"R{ri}"
        lines.append(f" {rid:<16} {reservoir_head_m:.1f}")
    lines.append("")

    lines.append("[TANKS]")
    lines.append("")

    lines.append("[PIPES]")
    lines.append(
        ";ID               Node1           Node2           Length  Diameter Roughness MinorLoss Status"
    )
    for k, (a, b, length_m) in enumerate(edges, start=1):
        n1 = f"J{a+1:05d}"
        n2 = f"J{b+1:05d}"
        pid = f"P{k:05d}"
        lines.append(
            f" {pid:<16} {n1:<15} {n2:<15} {length_m:7.1f} {pipe_diameter_mm:7.0f} {roughness:7.0f} 0         Open"
        )

    lines.append("")
    lines.append("[PUMPS]")
    lines.append(";ID               Node1           Node2           Parameters")
    for k, src_idx in enumerate(source_indices, start=1):
        pid = f"PUMP{k:03d}"
        rid = f"R{k-1}"
        lines.append(
            f" {pid:<16} {rid:<15} J{src_idx+1:05d}           HEAD 1"
        )
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
    lines.append(" 1                0.78        0.72        0.68        0.66        0.70        0.88")
    lines.append(" 1                1.02        1.18        1.22        1.20        1.14        1.10")
    lines.append(" 1                1.06        1.05        1.02        1.02        1.06        1.12")
    lines.append(" 1                1.18        1.16        1.05        0.95        0.85        0.80")
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
    lines.append(" Units                  CMH")
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

    lines.append("[COORDINATES]")
    lines.append(";Node             X-Coord         Y-Coord")
    for ri in range(len(source_indices)):
        rid = f"R{ri}"
        rx = -80.0 * ri
        ry = 0.0
        lines.append(f" {rid:<16} {rx:15.2f} {ry:15.2f}")
    for i in range(n_j):
        la, lo = idx_to_latlon[i]
        x, y = latlon_to_xy_m(la, lo, lat0, lon0)
        jid = f"J{i+1:05d}"
        lines.append(f" {jid:<16} {x:15.2f} {y:15.2f}")

    lines.append("")
    lines.append("[VERTICES]")
    lines.append("")
    lines.append("[END]")
    lines.append("")

    text = "\n".join(lines)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(text)

    adj: Dict[int, List[int]] = defaultdict(list)
    for a, b, _ in edges:
        adj[a].append(b)
        adj[b].append(a)
    if len(source_indices) == 1:
        src_idx = source_indices[0]
        seen = {src_idx}
        stack = [src_idx]
        while stack:
            u = stack.pop()
            for v in adj[u]:
                if v not in seen:
                    seen.add(v)
                    stack.append(v)
        if len(seen) < n_j:
            print(
                f"警告: 道路子图不连通，{n_j - len(seen)} 个节点从泵接入点不可达。",
                file=sys.stderr,
            )

    n_src = len(source_indices)
    if n_src <= 10:
        pump_desc = ", ".join(
            f"R{k-1}→J{s+1:05d}" for k, s in enumerate(source_indices, start=1)
        )
    else:
        head = ", ".join(
            f"R{k-1}→J{s+1:05d}"
            for k, s in enumerate(source_indices[:5], start=1)
        )
        pump_desc = f"{n_src} 个（{head}, …）"

    print(
        f"已写入 (EPANET 2.2 风格): {out_path}\n"
        f"  节点数: {n_j}\n"
        f"  管段数: {len(edges)}\n"
        f"  水库/泵: {pump_desc}\n"
        f"  总需求约 {demand_total_cmh:g} CMH（均分至非源节点），Pattern ID=1。"
    )


def main() -> None:
    ap = argparse.ArgumentParser(description="OSM 道路 → EPANET .inp（Overpass）")
    ap.add_argument(
        "--bbox",
        default="",
        help="south,west,north,east 十进制度；与 --from-json 二选一（离线时可省略）",
    )
    ap.add_argument("--out", required=True, help="输出 .inp 路径")
    ap.add_argument(
        "--overpass",
        default="https://lz4.overpass-api.de/api/interpreter",
        help="Overpass API URL（主站易 504，可换 overpass-api.de 或 kumi 等镜像）",
    )
    ap.add_argument(
        "--highway-regex",
        default="^(primary|secondary|tertiary)$",
        help='道路 class 正则（OSM highway），默认主干～三级路',
    )
    ap.add_argument(
        "--include-residential",
        action="store_true",
        help="在正则中纳入 residential、unclassified，管段数通常显著增加",
    )
    ap.add_argument(
        "--max-edges",
        type=int,
        default=0,
        help="最多保留的管段数；0 表示不限制",
    )
    ap.add_argument(
        "--largest-component-only",
        action="store_true",
        help="仅保留最大连通子图（默认保留全部分量，每分量一个水库+泵）",
    )
    ap.add_argument(
        "--no-dedupe",
        action="store_true",
        help="关闭上下行/平行管段几何去重",
    )
    ap.add_argument(
        "--dedupe-mid-m",
        type=float,
        default=35.0,
        help="平行边去重：中点距离阈值（米）",
    )
    ap.add_argument(
        "--dedupe-cos",
        type=float,
        default=0.88,
        help="平行边去重：方向余弦阈值（同向或反向）",
    )
    ap.add_argument(
        "--dedupe-cell-m",
        type=float,
        default=50.0,
        help="平行边去重：网格单元边长（米）",
    )
    ap.add_argument(
        "--preset",
        default="",
        choices=["", "xiaoguwei"],
        help="预设 bbox/标题：xiaoguwei=小谷围扩大矩形",
    )
    ap.add_argument("--reservoir-head", type=float, default=45.0)
    ap.add_argument(
        "--demand-total-cmh",
        type=float,
        default=400.0,
        help="全网总需水量目标（CMH），均分到各节点（源点除外）",
    )
    ap.add_argument("--diameter-mm", type=float, default=300.0)
    ap.add_argument("--roughness", type=float, default=110.0)
    ap.add_argument(
        "--title",
        default=DEFAULT_INP_TITLE,
    )
    ap.add_argument(
        "--epanet22",
        action="store_true",
        help="输出 EPANET 2.2 兼容 [OPTIONS]（无 EPANET3 扩展项；Pattern 使用数字 ID 1）",
    )
    ap.add_argument(
        "--from-json",
        metavar="PATH",
        default="",
        help="跳过 Overpass，直接读取已保存的 Overpass JSON（用于离线或规避 504）",
    )
    args = ap.parse_args()

    if args.preset == "xiaoguwei":
        if not args.from_json and not args.bbox.strip():
            args.bbox = XIAOGUWEI_BBOX
        if args.title == DEFAULT_INP_TITLE:
            args.title = XIAOGUWEI_INP_TITLE

    if args.from_json:
        try:
            with open(args.from_json, "r", encoding="utf-8") as f:
                data = json.load(f)
        except OSError as e:
            sys.exit(f"无法读取 JSON: {e}")
    else:
        if not args.bbox.strip():
            sys.exit("请提供 --bbox，或使用 --from-json 指定已下载的 Overpass JSON。")
        parts = [float(x.strip()) for x in args.bbox.split(",")]
        if len(parts) != 4:
            sys.exit("bbox 需要 4 个数: south,west,north,east")
        bbox = (parts[0], parts[1], parts[2], parts[3])

        hwy = args.highway_regex
        if args.include_residential:
            hwy = "^(primary|secondary|tertiary|residential|unclassified)$"

        q = overpass_query(bbox, hwy)
        print("请求 Overpass …（可能需数十秒）")
        try:
            data = fetch_overpass(q, args.overpass)
        except urllib.error.HTTPError as e:
            sys.exit(f"Overpass HTTP 错误: {e}")
        except urllib.error.URLError as e:
            sys.exit(f"网络错误: {e}")

    idx_to_latlon, edges = build_graph(data, max_edges=args.max_edges)
    n_edges_raw = len(edges)
    if not args.no_dedupe and edges:
        edges = dedupe_parallel_edges(
            edges,
            idx_to_latlon,
            mid_dist_m=args.dedupe_mid_m,
            cos_parallel=args.dedupe_cos,
            cell_m=args.dedupe_cell_m,
        )
        print(
            f"平行边去重: {n_edges_raw} → {len(edges)} 条管段。",
            file=sys.stderr,
        )

    if args.largest_component_only:
        idx_to_latlon, edges = largest_connected_component(idx_to_latlon, edges)
        print(
            f"最大连通子图: {len(idx_to_latlon)} 个节点, {len(edges)} 条管段。",
            file=sys.stderr,
        )
        source_indices = [pick_source_junction(idx_to_latlon, edges)]
    else:
        comps = find_connected_components(edges)
        print(
            f"全路网: {len(idx_to_latlon)} 个节点, {len(edges)} 条管段, "
            f"{len(comps)} 个连通分量。",
            file=sys.stderr,
        )
        source_indices = pick_source_junctions_all_components(idx_to_latlon, edges)

    if args.epanet22:
        emit_inp_epanet22(
            idx_to_latlon,
            edges,
            out_path=args.out,
            title=args.title,
            reservoir_head_m=args.reservoir_head,
            demand_total_cmh=args.demand_total_cmh,
            pipe_diameter_mm=args.diameter_mm,
            roughness=args.roughness,
            source_indices=source_indices,
        )
    else:
        emit_inp(
            idx_to_latlon,
            edges,
            out_path=args.out,
            title=args.title,
            reservoir_head_m=args.reservoir_head,
            demand_total_cmh=args.demand_total_cmh,
            pipe_diameter_mm=args.diameter_mm,
            roughness=args.roughness,
            source_indices=source_indices,
        )


if __name__ == "__main__":
    main()
