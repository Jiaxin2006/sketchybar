import datetime as dt
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('timer', Path(__file__).parents[1] / 'plugins/timer.py')
t = importlib.util.module_from_spec(spec)
spec.loader.exec_module(t)


def stamp(date):
    return int(dt.datetime.fromisoformat(date).timestamp())


class TimerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name)
        self.db = t.connect(self.path)
        self.s = t.fresh()
        self.now = stamp('2026-09-15T10:00:00')

    def tearDown(self):
        self.db.close()
        self.tmp.cleanup()

    def event(self, offset, name='timer', sender='mouse.clicked', button='left'):
        with self.db:
            return t.transition(self.db, self.s, self.now + offset, name, sender, button)

    def totals(self, offset):
        return t.stats(self.db, self.s, self.now + offset, self.path)

    def test_switch_pause_resume_save(self):
        self.event(0)
        self.event(60, 'timer_category.course')
        self.event(120, button='right')
        self.assertEqual(self.totals(500)['day']['research'], 60)
        self.assertEqual(self.totals(500)['day']['course'], 60)
        self.event(600)
        self.event(660)
        self.assertEqual(self.totals(1000)['day']['course'], 120)
        self.assertEqual(self.s['mode'], 'idle')
        self.assertEqual(sum(self.totals(1000)['day'].values()), 180)
        self.event(1001, sender='routine')
        self.assertEqual(sum(self.totals(1001)['day'].values()), 180)

    def test_discard_removes_all_pending_categories(self):
        self.event(0)
        self.event(60, 'timer_category.social')
        self.event(120, button='right')
        self.event(121, button='right')
        self.assertEqual(sum(self.totals(121)['week'].values()), 0)

    def test_midnight_and_monday_live_then_saved(self):
        self.now = stamp('2026-09-13T23:59:00')
        self.event(0)
        self.assertEqual(self.totals(120)['day']['research'], 60)
        self.assertEqual(self.totals(120)['week']['research'], 60)
        self.event(120)
        self.assertEqual(self.totals(120)['week']['research'], 60)
        self.assertEqual(list(self.db.execute('SELECT day,seconds FROM sessions')),
                         [('2026-09-13', 60), ('2026-09-14', 60)])

    def test_pause_across_midnight_excludes_gap(self):
        self.now = stamp('2026-09-14T23:58:00')
        self.event(0)
        self.event(60, button='right')
        self.event(3600)
        self.event(3660)
        self.assertEqual(self.totals(3660)['day']['research'], 60)
        self.assertEqual(self.totals(3660)['week']['research'], 120)

    def test_pomodoro_pause_overtime_and_sound_once(self):
        self.event(0, button='right')
        self.event(60)  # countdown left click does not stop
        self.assertEqual(self.s['mode'], 'down')
        self.event(100, button='right')
        self.event(200)
        self.assertEqual(self.event(1605, sender='routine'), (False, True))
        self.assertEqual(self.s['mode'], 'overtime')
        self.assertEqual(self.event(1606, sender='routine'), (False, False))
        self.event(1610)
        self.assertEqual(self.totals(1610)['day']['research'], 1510)

    def test_sleep_wake_freezes_at_last_tick(self):
        self.event(0)
        self.event(30, sender='routine')
        self.event(3600, sender='system_woke')
        self.assertEqual(self.s['mode'], 'up_paused')
        self.assertEqual(self.totals(3600)['day']['research'], 30)
        self.event(3601)
        self.event(3611, sender='system_will_sleep')
        self.event(7000, sender='system_woke')
        self.assertEqual(self.totals(7000)['day']['research'], 40)

    def test_lid_close(self):
        self.event(0)
        t.transition(self.db, self.s, self.now + 20, 'timer', 'routine', closed=True)
        self.assertEqual(self.s['mode'], 'up_paused')
        self.assertEqual(self.s['elapsed'], 20)

    def test_legacy_history_and_week_boundaries(self):
        (self.path / 'focus_2026-09-15.log').write_text('14:24:04 4575\ninvalid\n12:00:00 xyz\n')
        (self.path / 'focus_2026-09-14.log').write_text('14:00:00 60\n')
        (self.path / 'focus_2026-09-13.log').write_text('14:00:00 900\n')
        totals = self.totals(0)
        self.assertEqual(totals['day']['uncategorized'], 4575)
        self.assertEqual(totals['week']['uncategorized'], 4635)
        self.assertEqual(totals['week']['research'], 0)

    def test_running_legacy_migration_and_reopen(self):
        (self.path / 'timer_state').write_text(f'up 60 {self.now - 30} 0')
        (self.path / 'timer_last_tick').write_text(str(self.now - 1))
        self.s = t.load(self.db, self.now, self.path)
        self.assertEqual(self.totals(0)['day']['uncategorized'], 90)
        self.event(0, sender='routine')
        again = t.load(self.db, self.now, self.path)
        self.assertEqual(again, self.s)
        self.event(10)
        self.assertEqual(self.totals(10)['day']['uncategorized'], 100)

    def test_legacy_paused_overtime(self):
        (self.path / 'timer_state').write_text('overtime_paused 100 0 1')
        self.s = t.load(self.db, self.now, self.path)
        self.assertEqual(self.totals(0)['day']['uncategorized'], 1600)
        self.event(10)
        self.event(20)
        self.assertEqual(self.totals(20)['day']['uncategorized'], 1610)

    def test_transaction_rolls_back_save_and_state_together(self):
        self.event(0)
        with self.assertRaises(RuntimeError):
            with self.db:
                t.transition(self.db, self.s, self.now + 60, 'timer', 'mouse.clicked')
                raise RuntimeError('simulated failure')
        reloaded = t.load(self.db, self.now)
        self.assertEqual(reloaded['mode'], 'up')
        self.assertEqual(self.db.execute('SELECT count(*) FROM sessions').fetchone()[0], 0)


if __name__ == '__main__':
    unittest.main()
