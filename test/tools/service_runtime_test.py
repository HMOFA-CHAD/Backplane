#!/usr/bin/env python3
"""Offline parser/closure failures; no configured artifact or runtime acceptance."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('runtime', ROOT/'scripts/service-runtime.py')
R = importlib.util.module_from_spec(spec)
spec.loader.exec_module(R)


class RuntimeTests(unittest.TestCase):
    def test_native_host_tuple_is_exact(self):
        for system, machine, target in [('Linux', 'x86_64', 'linux-x64'), ('Linux', 'aarch64', 'linux-arm64'),
                                        ('Darwin', 'arm64', 'darwin-arm64'), ('Linux', 'armv7l', None)]:
            with patch.object(R.platform, 'system', return_value=system), patch.object(R.platform, 'machine', return_value=machine):
                self.assertEqual(R.target_host(), target)

    def test_elf_uses_actual_needed_not_symbol_guess(self):
        self.assertEqual(R.elf_needed(' 0x1 (NEEDED) Shared library: [libc.so.6]\n'), ['libc.so.6'])
        for tag in ['RPATH', 'RUNPATH', 'AUDIT', 'DEPAUDIT', 'FILTER', 'AUXILIARY']:
            with self.assertRaises(ValueError):
                R.elf_needed(' ('+tag+') [/unapproved]')

    def test_loader_reports_actual_resolution_and_interpreter(self):
        value = R.elf_resolved(' linux-vdso.so.1 (0x123)\n libc.so.6 => /lib/aarch64-linux-gnu/libc.so.6 (0x456)\n /lib/ld-linux-aarch64.so.1 (0x789)\n')
        self.assertEqual(value, {'libc.so.6': '/lib/aarch64-linux-gnu/libc.so.6', 'ld-linux-aarch64.so.1': '/lib/ld-linux-aarch64.so.1'})

    def test_unresolved_and_unrecognized_loader_output_refused(self):
        for text in ['libc.so.6 => not found', 'unrecognized output', 'libc.so.6 => /lib/libc.so.6 (0x1)\nlibc.so.6 => /tmp/libc.so.6 (0x2)']:
            with self.assertRaises(ValueError):
                R.elf_resolved(text)

    def test_runtime_loader_api_refused_on_both_formats(self):
        for symbol in ['dlopen@GLIBC_2.34', '_dlopen', 'dlmopen', 'dlsym@GLIBC_2.2', '_dlsym', 'dlvsym', '__libc_dlopen_mode']:
            with self.assertRaises(ValueError):
                R.no_loader_imports(' UND '+symbol)
        R.no_loader_imports(' UND socket@GLIBC_2.2.5\n UND pthread_create@GLIBC_2.34')

    def test_macho_system_umbrella_version_measured(self):
        value = R.macho_dependencies('/service:\n\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1345.120.2)\n')
        self.assertEqual(value[0]['currentVersion'], '1345.120.2')

    def test_macho_foreign_framework_rpath_and_empty_not_approved(self):
        for name in ['/opt/homebrew/lib/libSystem.B.dylib', '@rpath/libSystem.B.dylib', '/tmp/libx.dylib', '/usr/lib/libforeign.dylib']:
            with self.assertRaises(ValueError):
                R.macho_dependencies('/service:\n\t'+name+' (compatibility version 1.0.0, current version 1.0.0)\n')
        with self.assertRaises(ValueError):
            R.macho_dependencies('/service:\n')

    def test_capture_retains_real_tool_log_and_exit(self):
        with tempfile.TemporaryDirectory(prefix='bp-runtime-parser-') as d:
            c = R.Capture(Path(d))
            self.assertEqual(c(['/usr/bin/true']), '')
            self.assertEqual(c.calls[0]['exit'], 0)
            self.assertTrue((Path(d)/c.calls[0]['log']).is_file())
            with self.assertRaises(ValueError):
                c(['/usr/bin/false'])
            self.assertEqual(c.calls[1]['exit'], 1)


if __name__ == '__main__':
    unittest.main(verbosity=2)
