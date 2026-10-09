"""Deterministic grid economy model. Estimates only, not a player playtest.

Reads the production upgrade/tier tables; reproduces HP thresholds, block gold,
circle/AABB coverage and bomb falloff. Omits travel, falling, menu time and miss
clicks. Runs both interior hits and conservative edge hits, with/without clicking
after the first cannon. Output belongs in artifacts/balance.
"""
from pathlib import Path
import ast
import json
import math
import random
import re
import statistics

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'scripts/UpgradeManager.gd').read_text(encoding='utf-8')

def dictionary(name):
    return ast.literal_eval(re.search(r'const ' + name + r' := (\{.*?\n\})', SOURCE, re.S)[1])

def array(name):
    return ast.literal_eval(re.search(r'const ' + name + r':[^=\n]*= (\[[^\n]*\])', SOURCE)[1])

VALUES = dictionary('RUN_VALUES')
COSTS = dictionary('RUN_COSTS') | {
    'bomb_launcher': array('LAUNCHER_COSTS'),
    'bomb_rate': array('LAUNCHER_RATE_COSTS'),
    'bomb_damage': array('BOMB_DAMAGE_COSTS'),
    'bomb_radius': array('BOMB_RADIUS_COSTS'),
}
DAMAGES = array('BOMB_DAMAGES')
RADII = array('BOMB_RADII')
RATES = array('LAUNCHER_RATE_MULTIPLIERS')
COOLDOWNS = array('LAUNCHER_COOLDOWNS')
TIERS_SOURCE = (ROOT / 'scripts/BuildingSetup.gd').read_text(encoding='utf-8')
TIERS = []
for chunk in re.findall(r'"threshold":.*?(?=\n\t\},)', TIERS_SOURCE, re.S):
    threshold = int(re.search(r'"threshold": (\d+)', chunk)[1])
    types = {name: (float(hp), int(gold)) for name, hp, gold in re.findall(r'"(wall|window|floor)":.*?"hp": ([\d.]+),.*?"gold": (\d+)', chunk)}
    TIERS.append((threshold, types))

def simulate(seed, edge, active, meta=False):
    rng = random.Random(seed)
    level = dict.fromkeys(COSTS, 0)
    level['bomb_launcher'] = int(meta)
    percent_gold = 1.25 if meta else 1.0  # first rebirth: 1 RP coin + 1 RP base damage
    base_damage = 1.5 if meta else 1.0
    balance = earned = destroyed = 0
    time = 0.0
    milestones = {'first_cannon_seconds': 0.0} if meta else {}
    cells = []
    for row in range(30):
        for col in range(12):
            kind = 'floor' if row % 2 else ('window' if rng.random() < .25 else 'wall')
            hp, gold = TIERS[0][1][kind]
            cells.append([col*40.0, row*40.0, hp, gold, kind])

    def damage_at(x, y, damage, radius, bomb=False):
        nonlocal balance, earned, destroyed
        for cell in cells:
            dx, dy = abs(cell[0]-x), abs(cell[1]-y)
            if max(dx-20, 0)**2 + max(dy-20, 0)**2 > radius*radius:
                continue
            hit = damage * max(.3, 1-math.hypot(dx, dy)/radius) if bomb else damage
            cell[2] -= hit
            if cell[2] > 0:
                continue
            destroyed += 1
            amount = math.floor((cell[3]+VALUES['coin_base'][level['coin_base']])*VALUES['coin_multiplier'][level['coin_multiplier']]*percent_gold + .5)
            earned += amount
            balance += amount
            tier = next(t for n, t in reversed(TIERS) if destroyed >= n)
            kind = cell[4] if cell[4] == 'floor' else ('window' if rng.random() < .25 else 'wall')
            hp, gold = tier[kind]
            cell[2:] = [hp, gold, kind]

    hammer_next = 0.0
    bomb_next = [1.6 if meta else math.inf] + [math.inf]*3
    while time < 1800:
        if time >= hammer_next and (active or not level['bomb_launcher']):
            target = min(cells, key=lambda c: (c[2], -c[1]))
            damage_at(target[0], target[1], base_damage*VALUES['hammer_damage'][level['hammer_damage']], VALUES['hammer_range'][level['hammer_range']])
            hammer_next = time + max(.30, .5/VALUES['hammer_speed'][level['hammer_speed']])
        for i in range(level['bomb_launcher']):
            if time >= bomb_next[i]:
                x = (0.0 if i % 2 == 0 else 440.0) if edge else rng.uniform(40,400)
                damage_at(x, rng.uniform(220, 1080), DAMAGES[level['bomb_damage']], RADII[level['bomb_radius']], True)
                bomb_next[i] = time + COOLDOWNS[level['bomb_launcher']]*RATES[level['bomb_rate']]
        # Buy one upgrade per second: tutorial damage, range, first cannon,
        # then cheapest available branch. No inaccessible mechanics in run one.
        if abs(time-round(time)) < .001:
            priority = None
            for nid in ['hammer_damage', 'hammer_range', 'bomb_launcher']:
                if level[nid] == 0:
                    priority = nid
                    break
            candidates = []
            for nid, costs in COSTS.items():
                cost = costs[level[nid]]
                if cost < 0 or cost > balance:
                    continue
                if nid in ['bomb_rate','bomb_damage','bomb_radius'] and not level['bomb_launcher']:
                    continue
                if priority and nid != priority:
                    continue
                candidates.append((cost, nid))
            if candidates:
                cost, nid = min(candidates)
                balance -= cost
                level[nid] += 1
                if nid == 'bomb_launcher':
                    bomb_next[level[nid]-1] = time+1.6
                    milestones.setdefault('first_cannon_seconds', time)
                if nid == 'hammer_damage':
                    milestones.setdefault('first_upgrade_seconds', time)
        for key, threshold in [('first_rebirth_seconds',4000), ('three_rp_seconds',9000), ('four_rp_seconds',16000)]:
            if earned >= threshold:
                milestones.setdefault(key, round(time, 2))
        time = round(time+.1, 2)
    return milestones | {'gold_at_30_minutes': earned, 'blocks_at_30_minutes': destroyed}

def main():
    report = {'assumptions': __doc__, 'scenarios': []}
    for edge in [True, False]:
        for active in [True, False]:
            for meta in [False, True]:
                runs = [simulate(n, edge, active, meta) for n in [7, 19, 42]]
                data = {'edge_hits': edge, 'manual_after_cannon': active, 'second_run': meta}
                for key in set().union(*(r.keys() for r in runs)):
                    values = [r[key] for r in runs if key in r]
                    data[key] = {'median':round(statistics.median(values),2), 'min':min(values), 'max':max(values), 'reached':len(values)}
                report['scenarios'].append(data)
                print(json.dumps(data, ensure_ascii=False))
    target = ROOT / 'artifacts/balance/simulation.json'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')

if __name__ == '__main__':
    main()
