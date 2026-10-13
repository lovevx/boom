"""Summarize automated engine evidence; never label it a human playtest."""
from pathlib import Path
import json
import statistics

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'artifacts/demo-pacing'
ROUTES = {'hammer':'主动拆除','bomb':'自动轰炸','economy':'工程经营'}


def main():
    results = []
    missing = []
    for route in ROUTES:
        for seed in (7,19,42):
            path = OUTPUT / f'engine-{route}-{seed}.json'
            if not path.exists():
                missing.append(path.name)
                continue
            result = json.loads(path.read_text(encoding='utf-8'))
            # Legacy driver reports include exactly 3 x 15s of main-menu overhead.
            result.setdefault('eligible_seconds', round(result['seconds']-45,1))
            result['checks'] = {
                'completed':result['completed'],
                'journey_20_30_min':1200 <= result['seconds'] <= 1800,
                'first_upgrade_within_20s':result['milestones'].get('first_upgrade',999) <= 20,
                'first_cannon_45_90s':45 <= result['milestones'].get('first_cannon',0) <= 90,
                'progress_gaps_within_90s':result['longest_progress_gap'] <= 90,
                'four_rounds':len(result['phases']) == 4,
                'new_mechanic_available_in_first_half':all(
                    result['milestones'].get(f"phase_{p['phase']}_mechanic_available",99999) <= p['seconds']/2
                    for p in result['phases']),
            }
            results.append(result)
    report = {'evidence':'automated_engine_not_human_playtest','missing':missing,'scenarios':results,
              'human_playtest':{'required_new_players':3,'completed':0,'status':'pending'},
              'limitations':['Reduced motion / low effects enabled: default hitstop and full-effects performance not certified.',
                             'Menu reading time is a synthetic policy; real player choices and mistakes are not simulated.',
                             'Exit logs retain pre-existing CanvasItem / ObjectDB / resource cleanup warnings.']}
    regression_files = {'pacing':OUTPUT/'verification.json',
                        'balance':ROOT/'artifacts/demo-growth/balance-regression/verification.json',
                        'growth':ROOT/'artifacts/demo-growth/verification.json',
                        'collapse':ROOT/'artifacts/demo-growth/collapse-regression/verification.json'}
    report['regressions'] = {}
    for suite,path in regression_files.items():
        if path.exists():
            checks = json.loads(path.read_text(encoding='utf-8'))['checks']
            report['regressions'][suite] = {'checks':len(checks),'failed':sum(not c['passed'] for c in checks)}
    if results:
        report['journey_median_seconds'] = statistics.median(r['seconds'] for r in results)
        report['eligible_median_seconds'] = statistics.median(r['eligible_seconds'] for r in results)
        report['automated_acceptance_passed'] = not missing and all(all(r['checks'].values()) for r in results)
        report['eligible_median_24_26_min'] = 1440 <= report['eligible_median_seconds'] <= 1560
        report['automated_acceptance_passed'] &= report['eligible_median_24_26_min']
        report['mechanic_availability'] = [
            {'route':r['route'],'seed':r['seed'],'phase':p['phase'],
             'seconds':r['milestones'].get(f"phase_{p['phase']}_mechanic_available"),
             'halfway_seconds':p['seconds']/2}
            for r in results for p in r['phases']
        ]
    lines = ['# Demo 自动引擎节奏报告','',
             '这些数据来自真实 Godot 场景和物理的脚本驱动流程，**不是真人试玩**。',
             '全部使用减少动态效果、低特效；攻击/补层/弹道按 60 Hz 游戏时间运行，购买停顿和每次转生后的菜单停留由脚本模拟。',
             '“流程用时”包含三次主菜单各 15 秒；“试玩计时”排除这 45 秒，与游戏内计时口径一致。','',
             '| 路线 | 种子 | 流程分钟 | 试玩计时分钟 | 四轮秒数 | 首升级 / 首炮秒 | 最长进展间隔秒 |',
             '| --- | --- | --- | --- | --- | --- | --- |']
    for result in results:
        phases = ' / '.join(str(p['seconds']) for p in result['phases'])
        milestones = result['milestones']
        lines.append(f"| {ROUTES[result['route']]} | {result['seed']} | {result['seconds']/60:.2f} | {result['eligible_seconds']/60:.2f} | {phases} | {milestones.get('first_upgrade',0):.1f} / {milestones.get('first_cannon',0):.1f} | {result['longest_progress_gap']:.1f} |")
    if results:
        lines += ['',f"流程中位数 {report['journey_median_seconds']/60:.2f} 分钟；试玩计时中位数 {report['eligible_median_seconds']/60:.2f} 分钟。",
                  f"自动检查：{'通过' if report['automated_acceptance_passed'] else '未全部通过'}。"]
    lines += ['','真人验收：0 / 3，待进行。默认动态反馈下的时长、陌生玩家理解与自主路线选择尚未验收。',
              '各阶段表中的 5–7 / 5–6 / 5–7 / 5–6 分钟仍是设计目标；以表中实际结果报告偏差，不能声称每阶段均已满足。',
              '退出时仍有资源生命周期告警，详见同目录日志。']
    lines += ['','功能回归：'+ '；'.join(f"{suite} {data['checks']-data['failed']}/{data['checks']}" for suite,data in report['regressions'].items())+'。']
    availability = report.get('mechanic_availability',[])
    if availability and all(a['seconds'] is not None for a in availability):
        early = sum(a['seconds'] <= a['halfway_seconds'] for a in availability)
        lines += ['',f'各轮至少一种新机制在前半段可购买：{early}/{len(availability)} 个阶段。逐项时点保留在 JSON 中；真人是否自主购买仍需试玩。']
    if missing: lines += ['', '缺少：'+', '.join(missing)]
    (OUTPUT/'engine-summary.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    (OUTPUT/'engine-report.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print('scenarios=',len(results),'missing=',len(missing),'passed=',report.get('automated_acceptance_passed',False))
    raise SystemExit(0 if report.get('automated_acceptance_passed',False) else 1)


if __name__ == '__main__':
    main()
