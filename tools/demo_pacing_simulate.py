"""Four-round economy estimate, separate from real engine/playtest evidence.

Reads production tables and the engine driver's buying policies. Models combo,
power strike, execute, crit, falling damage/rewards, contracts, discounts, heavy
volleys, scatter, chain, delayed aftershock and permanent skills. The grid model
approximates travel (0.7s), column fall motion and side-wall collisions; it does
not reproduce Godot broadphase, animation scheduling, hitstop or player mistakes.
"""
from pathlib import Path
import ast
import heapq
import json
import math
import random
import re
import statistics
import balance_simulate as base

ROOT = Path(__file__).resolve().parents[1]
UPGRADE = (ROOT / 'scripts/UpgradeManager.gd').read_text(encoding='utf-8')
REBIRTH = (ROOT / 'scripts/ReincarnationManager.gd').read_text(encoding='utf-8')
PROGRESS = (ROOT / 'scripts/DemoProgress.gd').read_text(encoding='utf-8')
DRIVER = (ROOT / 'tools/demo_pacing_run.gd').read_text(encoding='utf-8')


def table(source, name):
    return ast.literal_eval(re.search(r'const ' + name + r' := (\{.*?\n\})', source, re.S)[1])


def exported(source, name):
    return ast.literal_eval(re.search(r'@export var ' + name + r'(?:[^=\n]*)[=:]=? ([^\n]+)', source)[1])


DEMO = table(UPGRADE, 'DEMO_NODES')
DEFS = table(REBIRTH, 'NODE_DEFS')
META_PRE = table(REBIRTH, 'NODE_PRE_REQS')
PERCENT = table(REBIRTH, 'PERCENT_POINTS')
FLAT = table(REBIRTH, 'FLAT_POINTS')
PRE = table(UPGRADE, 'NODE_PRE_REQS')
ROUTES = table(DRIVER, 'ROUTES')
META = table(DRIVER, 'META')
TARGETS = exported(REBIRTH, 'run_gold_targets')
FINAL = exported(PROGRESS, 'finale_gold')
SCATTER_GOAL = exported(PROGRESS, 'required_scatter_volleys')
COSTS = base.COSTS | {key: item['costs'] for key, item in DEMO.items()} | {
    'crit_chance': base.array('CRIT_CHANCE_COSTS'), 'crit_mult': base.array('CRIT_MULT_COSTS'),
    'chain': base.array('CHAIN_COSTS'), 'scatter': base.array('SCATTER_COSTS'),
}
GATES = {'crit_chance': 1, 'crit_mult': 1, 'chain': 2, 'scatter': 3}
STEPS = ast.literal_eval(re.search(r'@export var specialization_steps := (\{.*?\n\})', REBIRTH, re.S)[1])


def simulate(route, seed):
    rng = random.Random(seed)
    permanent = dict.fromkeys(DEFS, 0)
    rp = 0
    phases = []
    milestones = {}
    total_seconds = 0.0
    mechanics = dict.fromkeys(['combo', 'power_strike', 'execute', 'crit', 'falling_damage', 'salvage',
                               'contract', 'discount', 'barrage', 'scatter', 'chain', 'aftershock'], 0)
    for phase in range(4):
        levels = dict.fromkeys(COSTS, 0)
        levels['bomb_launcher'] = [0, 1, 1, 2][phase]
        capital = [0, 20, 60, 140][permanent['initial_capital']]
        balance, earned, destroyed, volleys = capital, 0, 0, 0
        now, menu_until, hammer_next, shop_next = 0.0, 0.0, 0.0, 0.0
        paused_total = 0.0
        events, seq = [], 0
        combo, swings, last_hit = 0, 0, -99.0
        bomb_next = [0.8 if i < levels['bomb_launcher'] else math.inf for i in range(4)]
        rounds = [0]*4
        cells = []
        columns = [[] for _ in range(12)]

        def value(key):
            return DEMO[key]['values'][levels[key]]

        def meta(key):
            return permanent[key] * (PERCENT | FLAT | STEPS).get(key, 0.0)

        def new_cell(col, row, floor):
            tier = next(t for n, t in reversed(base.TIERS) if destroyed >= n)
            kind = 'floor' if floor else ('window' if 0 < col < 11 and rng.random() < .3 else 'wall')
            hp, gold = tier[kind]
            return {'x': col*40.0, 'y': row*40.0, 'hp': hp, 'max': hp, 'gold': gold,
                    'floor': floor, 'fall_until': 0.0, 'alive': True}

        for col in range(12):
            for row in range(30):
                cell = new_cell(col, row, row % 2 == 1)
                columns[col].append(cell)
                cells.append(cell)

        def hit(cell, amount):
            nonlocal balance, earned, destroyed
            if not cell['alive']:
                return False
            falling = now < cell['fall_until']
            amount *= 1 + value('falling_damage') if falling else 1
            if falling and levels['falling_damage']: mechanics['falling_damage'] += 1
            cell['hp'] -= amount
            if cell['hp'] > 0:
                return False
            cell['alive'] = False
            destroyed += 1
            salvage = int(value('salvage') + meta('salvage_license')) if falling and levels['salvage'] else 0
            reward = math.floor((cell['gold'] + base.VALUES['coin_base'][levels['coin_base']] +
                                 int(meta('coin_per_kill')) + salvage) * base.VALUES['coin_multiplier'][levels['coin_multiplier']] *
                                (1 + meta('coin_heart')) + .5)
            if salvage: mechanics['salvage'] += 1
            if destroyed % 50 == 0 and levels['contract']:
                reward += math.floor(value('contract') * (1 + meta('contract_license')) + .5)
                mechanics['contract'] += 1
            balance += reward
            earned += reward
            return True

        def area(x, y, damage, radius, kind):
            killed = []
            for cell in list(cells):
                if not cell['alive']:
                    continue
                dx, dy = abs(cell['x']-x), abs(cell['y']-y)
                if max(0, dx-20)**2 + max(0, dy-20)**2 > radius**2:
                    continue
                amount = damage
                if kind == 'hammer':
                    if cell['hp'] <= cell['max'] * (.5 + meta('execute_training')):
                        amount *= 1 + value('execute')
                        if levels['execute']: mechanics['execute'] += 1
                    if rng.random() < .1*levels['crit_chance']:
                        amount *= 2 + .5*levels['crit_mult']
                        mechanics['crit'] += 1
                else:
                    amount *= max(min(.8, value('blast_floor') + meta('blast_training')), 1-math.hypot(dx,dy)/radius)
                if hit(cell, amount): killed.append(cell)
            if kind == 'bomb' and levels['chain']:
                for dead in killed:
                    for cell in list(cells):
                        if cell['alive'] and math.hypot(cell['x']-dead['x'],cell['y']-dead['y']) <= 90:
                            hit(cell, damage * .15*levels['chain'])
                            mechanics['chain'] += 1

        def compact():
            nonlocal cells
            for col, column in enumerate(columns):
                alive = [c for c in column if c['alive']]
                missing = 30-len(alive)
                if not missing: continue
                for row, cell in enumerate(alive, missing):
                    destination = row*40.0
                    if destination != cell['y']:
                        drop = base.VALUES['building_drop_speed'][levels['building_drop_speed']] * (1+meta('gravity_accel'))
                        cell['fall_until'] = now + min(.8, max(.05,(destination-cell['y'])/(520*drop)))
                        cell['y'] = destination
                # Approximation: top refill immediately; falling state still affects hits/rewards.
                new = [new_cell(col,row,not alive[0]['floor'] if alive else bool(row%2)) for row in range(missing)]
                columns[col] = new + alive
            cells = [c for column in columns for c in column]

        def available(key):
            if levels[key] >= len(COSTS[key])-1 or phase < GATES.get(key,0): return False
            if key in DEMO:
                item = DEMO[key]
                return phase >= item['gate'] and levels[item['pre']] >= item['lv']
            return all(levels[item['node']] >= item['lvl'] for item in PRE.get(key,[]))

        while now < 3600:
            if now < menu_until:
                now = round(now+.1, 4)
                paused_total += .1
                continue
            active_now = now-paused_total
            while events and events[0][0] <= active_now:
                _, _, x, y, damage, radius, kind = heapq.heappop(events)
                area(x,y,damage,radius,kind)
                compact()
            auto = permanent['auto_hammer'] > 0
            if active_now >= hammer_next and (auto or levels['bomb_launcher'] == 0 or now % 18 < 6):
                target = min((c for c in cells if c['alive'] and c['y'] >= 360),key=lambda c:c['hp'])
                if active_now-last_hit > 1.5+meta('combo_memory'): combo = 0
                damage = (1+meta('base_damage'))*base.VALUES['hammer_damage'][levels['hammer_damage']]*(1+meta('destroy_power'))
                damage *= 1 + combo*value('combo')
                radius = base.VALUES['hammer_range'][levels['hammer_range']] + meta('giant_power')
                swings += 1
                if levels['power_strike'] and swings % 3 == 0:
                    damage *= value('power_strike')
                    radius += 40+meta('wave_training')
                    mechanics['power_strike'] += 1
                if levels['combo'] and combo: mechanics['combo'] += 1
                area(target['x'],target['y'],damage,radius,'hammer')
                compact()
                combo = min(5,combo+1)
                last_hit = active_now
                speed = base.VALUES['hammer_speed'][levels['hammer_speed']]*(1+meta('swift_wind'))
                hammer_next = active_now + (max(.3,.5/speed) if auto else max(.6,.5/speed))
            for index in range(levels['bomb_launcher']):
                if active_now < bomb_next[index]: continue
                rounds[index] += 1
                mult = 1+value('barrage') if rounds[index] % (4-int(meta('barrage_training'))) == 0 else 1
                if mult > 1: mechanics['barrage'] += 1
                projectiles = 1+levels['scatter']
                if projectiles > 1:
                    volleys += 1
                    mechanics['scatter'] += 1
                for _ in range(projectiles):
                    x = -15.0 if index % 2 == 0 else 455.0
                    y = rng.uniform(220,1000)
                    damage = (base.DAMAGES[levels['bomb_damage']]+meta('turret_base_damage'))*(1+meta('ammo_enhance'))*mult
                    radius = base.RADII[levels['bomb_radius']]*(1+meta('blast_range'))
                    seq += 1
                    heapq.heappush(events,(active_now+.7,seq,x,y,damage,radius,'bomb'))
                    if levels['aftershock']:
                        seq += 1
                        heapq.heappush(events,(active_now+1.15,seq,x,y,damage*value('aftershock'),radius*(1+meta('echo_mastery')),'echo'))
                        mechanics['aftershock'] += 1
                bomb_next[index] = active_now + 3.4*base.RATES[levels['bomb_rate']]
            if now >= shop_next:
                shop_next = now + 12
                bought = 0
                for _ in range(8):
                    discount = min(.25,value('discount')+meta('procurement'))
                    prices = {k: max(1,math.ceil(COSTS[k][levels[k]]*(1-discount))) for k in COSTS if available(k)}
                    tutorial = next((k for k in ['hammer_damage','hammer_speed','bomb_launcher'] if not levels[k]),None)
                    candidates = [k for k,p in prices.items() if p <= balance and (not tutorial or tutorial == k)]
                    if not candidates: break
                    key = min(candidates,key=lambda k: prices[k]*(.55 if k in ROUTES[route] else 1)*(.8 if levels[k] == 0 else 1)*(.1 if phase == 3 and k == 'scatter' and not levels[k] else 1))
                    balance -= prices[key]
                    levels[key] += 1
                    bought += 1
                    if discount: mechanics['discount'] += 1
                    if phase == 0:
                        milestones.setdefault('first_upgrade',now)
                        if key == 'bomb_launcher': milestones.setdefault('first_cannon',now)
                    if key == 'bomb_launcher': bomb_next[levels[key]-1] = active_now+.8
                if bought: menu_until = now+2+bought*.6
            target_gold = TARGETS[min(phase,len(TARGETS)-1)] if phase < 3 else FINAL
            if earned >= target_gold and (phase < 3 or volleys >= SCATTER_GOAL): break
            now = round(now+.1,4)
        phases.append({'phase':phase,'seconds':round(now,1),'gold':earned,'levels':levels.copy()})
        total_seconds += now
        if phase < 3:
            rp += min(8,math.floor(math.sqrt(earned/1000)))
            for _ in range(20):
                key = next((k for k in META[route] if permanent[k] < DEFS[k]['max_level'] and
                            rp >= DEFS[k]['costs'][permanent[k]] and phase+1 >= DEFS[k].get('rebirth',0) and
                            (permanent[k] > 0 or k not in META_PRE or permanent[META_PRE[k]['node']] >= META_PRE[k]['lvl'])),None)
                if key is None: break
                rp -= DEFS[key]['costs'][permanent[key]]
                permanent[key] += 1
            total_seconds += 15
    return {'route':route,'seed':seed,'seconds':round(total_seconds,1),'phases':phases,'milestones':milestones,
            'mechanics':mechanics,'completed':earned >= FINAL and volleys >= SCATTER_GOAL}


def main():
    results = []
    for route in ROUTES:
        for seed in [7,19,42]:
            result = simulate(route,seed)
            results.append(result)
            print(route,seed,round(result['seconds']/60,2),[p['seconds'] for p in result['phases']],flush=True)
    output = ROOT / 'artifacts/demo-pacing/model.json'
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps({'evidence':'estimate_not_playtest','assumptions':__doc__,'scenarios':results,
                                 'median_seconds':statistics.median(r['seconds'] for r in results)},ensure_ascii=False,indent=2),encoding='utf-8')


if __name__ == '__main__':
    main()
