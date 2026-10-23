"""Focused no-wait/fallback receipt checks; never starts a heavy gate."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,ROOT/path)
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
ci=module('local_ci','scripts/local-ci.py')
phase=module('local_phase','scripts/local-phase.py')


class Resources(unittest.TestCase):
    def test_unavailable_phase_moves_once_to_boat(self):
        with tempfile.TemporaryDirectory() as d, patch.object(ci,'CACHE',Path(d)), \
             patch.object(ci,'local_phase',return_value=(75,{})) as local, \
             patch.object(ci,'boat_phase',return_value=(0,{'backend':'boat'},None)) as remote:
            rc,data=ci.execute_phase('proof',['PROOF.bend'],[],['scripts/check.sh','proof'],Path(d))
            self.assertEqual(rc,0);self.assertEqual(data['backend'],'boat')
            self.assertEqual(local.call_count,1);self.assertEqual(remote.call_count,1)

    def test_real_phase_failure_does_not_start_duplicate(self):
        with tempfile.TemporaryDirectory() as d, patch.object(ci,'CACHE',Path(d)), \
             patch.object(ci,'local_phase',return_value=(1,{'seconds':1.0})), \
             patch.object(ci,'boat_phase') as remote:
            self.assertEqual(ci.execute_phase('proof',[],[],[],Path(d))[0],1)
            remote.assert_not_called()

    def test_killed_scope_without_result_moves_unfinished_phase(self):
        with tempfile.TemporaryDirectory() as d, patch.object(ci,'CACHE',Path(d)), \
             patch.object(ci,'local_phase',return_value=(-15,{})), \
             patch.object(ci,'boat_phase',return_value=(0,{'backend':'boat'},None)) as remote:
            self.assertEqual(ci.execute_phase('tests',[],[],[],Path(d))[0],0)
            self.assertEqual(remote.call_count,1)

    def test_boat_exit_zero_without_matching_receipt_is_incomplete(self):
        with tempfile.TemporaryDirectory() as d, patch.object(ci,'base_key',return_value='expected'), \
             patch.object(ci.subprocess,'run') as run:
            run.return_value.returncode=0
            rc,_,_=ci.boat_phase('proof','proof',[],[],Path(d))
            self.assertEqual(rc,3)

    def test_measurement_labels_process_peak_and_exits(self):
        with tempfile.TemporaryDirectory() as d:
            receipt=Path(d)/'phase.json'
            self.assertEqual(phase.measure(['/bin/true'],receipt),0)
            data=json.loads(receipt.read_text())
            self.assertGreater(data['peak_rss_kib'],0)
            self.assertNotIn('aggregate_peak_bytes',data)
            self.assertIn('not aggregate',data['rss_measurement'])


if __name__=='__main__':unittest.main()
