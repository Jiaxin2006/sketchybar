#!/usr/bin/env python3
"""Categorized focus timer. Standard library only; SQLite serializes bar events."""
import datetime as dt
import json
import os
import re
from pathlib import Path
import sqlite3
import subprocess
import sys
import time

CATEGORIES = {'research': 'Research', 'course': 'Study', 'social': 'Service', 'uncategorized': 'Other'}
CLOSE_EVENTS = {'mouse.exited.global', 'space_change', 'display_change', 'front_app_switched'}
POMO = 25 * 60
CONFIG = Path(os.environ.get('CONFIG_DIR', Path.home() / '.config/sketchybar'))
DATA = Path(os.environ.get('SKETCHYBAR_DATA_DIR', CONFIG / 'data'))
CACHE = Path(os.environ.get('TMPDIR', '/tmp')) / 'sketchybar'


def fresh(category='research'):
    return dict(mode='idle', category=category, elapsed=0, anchor=0,
                last_tick=0, pending=[], notified=False)


def split_interval(start, end, category):
    """Split actual working intervals at local midnight, including DST days."""
    rows = []
    while start < end:
        date = dt.datetime.fromtimestamp(start).date()
        midnight = int(dt.datetime.combine(date + dt.timedelta(days=1), dt.time()).timestamp())
        stop = min(end, midnight)
        rows.append([date.isoformat(), category, stop - start])
        start = stop
    return rows


def migrate(now, cache):
    state = fresh()
    try:
        mode, accum, anchor, meta = (cache / 'timer_state').read_text().split()
        accum, anchor = int(accum), int(anchor)
        if mode == 'idle':
            return state
        if mode not in ('up', 'down', 'overtime', 'up_paused', 'down_paused', 'overtime_paused'):
            raise ValueError('unknown legacy timer mode')
        state.update(mode=mode, category='uncategorized', elapsed=accum, anchor=anchor)
        if mode.startswith('overtime'):
            state['elapsed'] += POMO
            state['notified'] = True
        # Old accumulated/paused time has no interval dates; retain on migration day.
        if state['elapsed']:
            state['pending'] = [[dt.datetime.fromtimestamp(now).date().isoformat(),
                                 'uncategorized', state['elapsed']]]
        try:
            state['last_tick'] = int((cache / 'timer_last_tick').read_text())
        except (FileNotFoundError, ValueError):
            state['last_tick'] = anchor
    except FileNotFoundError:
        pass
    return state


def connect(data=DATA):
    data.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(data / 'focus.sqlite3', timeout=15)
    db.execute('CREATE TABLE IF NOT EXISTS state (id INTEGER PRIMARY KEY, value TEXT NOT NULL)')
    db.execute('CREATE TABLE IF NOT EXISTS sessions (id INTEGER PRIMARY KEY, day TEXT NOT NULL, category TEXT NOT NULL, seconds INTEGER NOT NULL)')
    db.execute('CREATE TABLE IF NOT EXISTS discarded_sessions (id INTEGER PRIMARY KEY, discarded_at INTEGER NOT NULL, state_json TEXT NOT NULL, restored_at INTEGER)')
    return db


def load(db, now, cache=CACHE):
    row = db.execute('SELECT value FROM state WHERE id=1').fetchone()
    return json.loads(row[0]) if row else migrate(now, cache)


def running(state):
    return state['mode'] in ('up', 'down', 'overtime')


def settle(state, now):
    if running(state):
        end = max(state['anchor'], now)
        state['pending'].extend(split_interval(state['anchor'], end, state['category']))
        state['elapsed'] += end - state['anchor']
        state['anchor'] = end


def pause(state, now):
    if running(state):
        settle(state, now)
        state['mode'] += '_paused'
        state['anchor'] = 0


def total_elapsed(state, now):
    return state['elapsed'] + (max(0, now - state['anchor']) if running(state) else 0)


def write_session(db, state):
    """Commit the stored working intervals using the session's final category."""
    totals = {}
    for day, _, seconds in state['pending']:
        totals[day] = totals.get(day, 0) + seconds
    db.executemany('INSERT INTO sessions(day,category,seconds) VALUES(?,?,?)',
                   [(day, state['category'], sec) for day, sec in totals.items() if sec > 0])


def reset(state):
    category = state['category']
    state.clear()
    state.update(fresh(category))


def save_session(db, state, now):
    settle(state, now)
    write_session(db, state)
    reset(state)


def discard_session(db, state, now):
    if state['mode'] == 'idle':
        return False
    pause(state, now)
    db.execute('INSERT INTO discarded_sessions(discarded_at,state_json) VALUES(?,?)',
               (now, json.dumps(state)))
    reset(state)
    return True


def restore_last_discarded(db, now):
    row = db.execute('SELECT id,state_json FROM discarded_sessions WHERE restored_at IS NULL ORDER BY id DESC LIMIT 1').fetchone()
    if not row:
        return False
    write_session(db, json.loads(row[1]))
    db.execute('UPDATE discarded_sessions SET restored_at=? WHERE id=?', (now, row[0]))
    return True


def transition(db, state, now, name, sender, button='left', closed=False):
    """Return (refresh_focus, sound). State/history changes commit together."""
    saved = False
    # Wake must be processed before clicks/ticks so sleep cannot enter the ledger.
    if sender == 'system_woke' and running(state):
        pause(state, max(state['anchor'], state['last_tick']))
    elif sender == 'system_will_sleep' or closed:
        pause(state, now)

    if name == 'focus.discard' and sender == 'mouse.clicked':
        saved = discard_session(db, state, now)
    elif name == 'focus.restore' and sender == 'mouse.clicked':
        saved = restore_last_discarded(db, now)
    elif name.startswith('timer_category.') and sender == 'mouse.clicked':
        category = name.split('.', 1)[1]
        if category in CATEGORIES:
            # The selection applies to the whole open session, fixed on save.
            state['category'] = category
    elif name == 'timer' and sender == 'mouse.clicked':
        mode = state['mode']
        if mode == 'idle':
            category = state['category']
            state.clear()
            state.update(fresh(category))
            state.update(mode='down' if button == 'right' else 'up', anchor=now)
        elif mode.endswith('_paused'):
            if button == 'left':
                state.update(mode=mode.removesuffix('_paused'), anchor=now)
            elif button == 'right':
                save_session(db, state, now)
                saved = True
        elif button == 'right':
            pause(state, now)
        elif button == 'left' and (mode != 'down' or total_elapsed(state, now) >= POMO):
            save_session(db, state, now)
            saved = True

    sound = False
    if state['mode'].startswith('down') and total_elapsed(state, now) >= POMO:
        state['mode'] = state['mode'].replace('down', 'overtime')
        sound = not state['notified']
        state['notified'] = True
    if running(state):
        state['last_tick'] = now
    db.execute('INSERT OR REPLACE INTO state(id,value) VALUES(1,?)', (json.dumps(state),))
    return saved, sound


def legacy_rows(data, first, last):
    day = first
    while day <= last:
        path = data / f'focus_{day.isoformat()}.log'
        if path.exists():
            for line in path.read_text().splitlines():
                parts = line.split()
                if len(parts) >= 2 and parts[-1].isdigit() and int(parts[-1]) > 0:
                    category = parts[1] if len(parts) >= 3 and parts[1] in CATEGORIES else 'uncategorized'
                    yield day.isoformat(), category, int(parts[-1])
        day += dt.timedelta(days=1)


def rows(db, state, now, data=DATA, live=True):
    today = dt.datetime.fromtimestamp(now).date()
    monday = today - dt.timedelta(days=today.weekday())
    result = list(legacy_rows(data, monday, today))
    result.extend(db.execute('SELECT day,category,seconds FROM sessions WHERE day BETWEEN ? AND ?',
                             (monday.isoformat(), today.isoformat())))
    if live:
        result.extend((day, state['category'], sec) for day, _, sec in state['pending'])
        if running(state):
            result.extend(split_interval(state['anchor'], now, state['category']))
    return result


def stats(db, state, now, data=DATA):
    today = dt.datetime.fromtimestamp(now).date()
    monday = today - dt.timedelta(days=today.weekday())
    totals = {period: {cat: 0 for cat in CATEGORIES} for period in ('day', 'week')}
    for day, category, seconds in rows(db, state, now, data):
        cat = category if category in CATEGORIES else 'uncategorized'
        if monday.isoformat() <= day <= today.isoformat():
            totals['week'][cat] += seconds
        if day == today.isoformat():
            totals['day'][cat] += seconds
    return totals


def duration(seconds):
    h, rem = divmod(max(0, seconds), 3600)
    m, s = divmod(rem, 60)
    return f'{h}:{m:02}:{s:02}' if h else f'{m:02}:{s:02}'


def human(seconds):
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    return f'{h}小时 {m:02}分 {s:02}秒' if h else f'{m}分 {s:02}秒'


def bar(*args):
    subprocess.run(['sketchybar', *args], check=True, stdout=subprocess.DEVNULL)


def render_timer(state, now):
    mode = state['mode']
    elapsed = total_elapsed(state, now)
    if mode.startswith('down'):
        label, icon = duration(POMO - elapsed), '󰔛'
    elif mode.startswith('overtime'):
        label, icon = duration(elapsed - POMO), '󰔛'
    elif mode.startswith('up'):
        label, icon = duration(elapsed), '󰔟'
    else:
        label, icon = 'Timer', '󰄉'
    if mode.endswith('_paused'):
        icon = '󰏤'
    args = ['--set', 'timer', f'label={label}', f'icon={icon}',
            f'update_freq={1 if running(state) else 0}',
            '--set', 'timer_category', f'label={CATEGORIES[state["category"]]} ▾']
    for category in CATEGORIES:
        args += ['--set', f'timer_category.{category}',
                 'icon.drawing=off',
                 f'background.drawing={"on" if category == state["category"] else "off"}']
    bar(*args)


def render_stats(db, state, now, sender):
    totals = stats(db, state, now)
    today = dt.datetime.fromtimestamp(now).date()
    monday = today - dt.timedelta(days=today.weekday())
    args = []
    for period, title in [('day', f'今天 · {today:%m/%d}'),
                          ('week', f'本周 · {monday:%m/%d}–{monday + dt.timedelta(days=6):%m/%d}')]:
        args += ['--set', f'focus.{period}', f'label={title}  共 {human(sum(totals[period].values()))}']
        for cat, label in CATEGORIES.items():
            args += ['--set', f'focus.{period}.{cat}', f'label={label}    {human(totals[period][cat])}']
    note = '本次按当前分类预览；结束时固定' if state['mode'] != 'idle' else '已保存的专注时间 · 每周一开始'
    args += ['--set', 'focus.note', f'label={note}']
    last = db.execute('SELECT state_json FROM discarded_sessions WHERE restored_at IS NULL ORDER BY id DESC LIMIT 1').fetchone()
    restore_label = 'Restore last discarded'
    if last:
        discarded = json.loads(last[0])
        restore_label += f" · {CATEGORIES[discarded['category']]} {duration(discarded['elapsed'])}"
    args += ['--set', 'focus.restore', f'label={restore_label}',
             f'label.color={"0xff1e1e1e" if last else "0x661e1e1e"}',
             '--set', 'focus.discard',
             f'label.color={"0xffa33b32" if state['mode'] != 'idle' else "0x661e1e1e"}']
    if sender == 'mouse.clicked':
        bar('--set', 'timer_category', 'popup.drawing=off')
        current = json.loads(subprocess.check_output(['sketchybar', '--query', 'focus']))
        drawing = current.get('popup', {}).get('drawing', 'off')
        opened = drawing not in ('on', True)
        args += ['--set', 'focus', f'popup.drawing={"on" if opened else "off"}', f'update_freq={10 if opened else 0}']
    elif sender in CLOSE_EVENTS:
        args += ['--set', 'focus', 'popup.drawing=off', 'update_freq=0']
    bar(*args)


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else 'event'
    name, sender = os.environ.get('NAME', ''), os.environ.get('SENDER', '')
    saved = sound = False
    db = connect()
    with db:
        db.execute('BEGIN IMMEDIATE')
        now = int(time.time())
        state = load(db, now)
        if action == 'event':
            # Durable state can outlive a reboot; never credit the powered-off gap.
            if running(state) and state['last_tick'] and now - state['last_tick'] > 60:
                boot = subprocess.check_output(['sysctl', '-n', 'kern.boottime'], text=True)
                match = re.search(r'sec = (\d+)', boot)
                if match and state['last_tick'] < int(match[1]):
                    pause(state, max(state['anchor'], state['last_tick']))
            closed = False
            if running(state) and sender != 'system_woke':
                result = subprocess.run(['ioreg', '-r', '-k', 'AppleClamshellState', '-d', '1'], capture_output=True, text=True)
                closed = '"AppleClamshellState" = Yes' in result.stdout
            saved, sound = transition(db, state, now, name, sender, os.environ.get('BUTTON', 'left'), closed)
        if action == 'durations':
            today = dt.datetime.fromtimestamp(now).date().isoformat()
            for day, _, sec in rows(db, state, now, live=False):
                if day == today:
                    print(sec)
            return
    if action == 'stats':
        render_stats(db, state, now, sender)
    else:
        render_timer(state, now)
        if name == 'timer_category' and (sender == 'mouse.clicked' or sender in CLOSE_EVENTS):
            if sender == 'mouse.clicked':
                bar('--set', 'focus', 'popup.drawing=off', 'update_freq=0')
            bar('--set', 'timer_category', f'popup.drawing={"toggle" if sender == "mouse.clicked" else "off"}')
        elif name.startswith('timer_category.'):
            bar('--set', 'timer_category', 'popup.drawing=off')
        if name in ('focus.discard', 'focus.restore'):
            bar('--set', 'focus', 'popup.drawing=off', 'update_freq=0')
        if saved:
            env = dict(os.environ, NAME='focus', SENDER='timer_saved')
            subprocess.run([str(CONFIG / 'plugins/focus.sh')], env=env, check=True)
        if sound:
            subprocess.Popen(['afplay', '/System/Library/Sounds/Glass.aiff'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    db.close()


if __name__ == '__main__':
    main()
