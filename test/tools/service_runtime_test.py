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
    PROGRAM = ('Entry point 0x18b22c0\nThere are 9 program headers, starting at offset 64\n'
        ' PHDR 0x000040 0x0000000000000040 0x40\n'
        ' LOAD 0x000000 0x0000000000000000 0x0\n'
        ' DYNAMIC 0x587fda0 0x000000000587fda0 0x587fda0\n')
    ARM_LIST = ('\t (0x0000ff9b5c8e0000)\n'
        '\tlinux-vdso.so.1 (0x0000ff9b622ac000)\n'
        '\tlibm.so.6 => /lib/aarch64-linux-gnu/libm.so.6 (0x0000ff9b5c830000)\n'
        '\tlibc.so.6 => /lib/aarch64-linux-gnu/libc.so.6 (0x0000ff9b5c670000)\n'
        '\t/lib/ld-linux-aarch64.so.1 (0x0000ff9b62270000)\n')

    def debug(self, binary):
        # Synthetic glibc diagnostic with preserved ARM program-header offsets.
        base = 0xff9b5c8e0000
        return (f' 42: file={binary} [0];  generating link map\n'
            f' 42:   dynamic: 0x{base+0x587fda0:016x}  base: 0x{base:016x}   size: 0x0000000005980000\n'
            f' 42:     entry: 0x{base+0x18b22c0:016x}  phdr: 0x{base+0x40:016x}  phnum:   9\n\n')

    def test_actual_arm_row_requires_same_invocation_main_binding(self):
        with self.assertRaises(ValueError):
            R.elf_resolved(self.ARM_LIST)
        with tempfile.TemporaryDirectory() as d:
            binary = Path(d)/'backplane-serve'
            binary.write_bytes(b'parser-model-only')
            bound = R.elf_main_mapping(self.debug(binary), binary, self.PROGRAM)
            got = R.elf_resolved(self.ARM_LIST, bound)
            self.assertEqual(set(got), {'libm.so.6', 'libc.so.6', 'ld-linux-aarch64.so.1'})
            self.assertEqual(bound['sha256'], R.sha(binary))

    def test_main_binding_requires_exact_file_and_all_headers(self):
        with tempfile.TemporaryDirectory() as d:
            binary = Path(d)/'backplane-serve'
            binary.write_bytes(b'parser-model-only')
            debug = self.debug(binary)
            cases = [debug.replace(str(binary), '/foreign'), debug+debug,
                debug.replace('phnum:   9', 'phnum:   8'),
                debug.replace('0x0000ff9b6215fda0', '0x0000ff9b6215fda1'),
                debug.replace('0x0000ff9b5e1922c0', '0x0000ff9b5e1922c1'),
                debug.replace('0x0000ff9b5c8e0040', '0x0000ff9b5c8e0041'),
                debug.replace(' 42:     entry:', ' 43:     entry:'), '']
            for text in cases:
                with self.subTest(text=text), self.assertRaises(ValueError):
                    R.elf_main_mapping(text, binary, self.PROGRAM)

    def test_bound_main_does_not_allow_other_anonymous_or_bad_dependencies(self):
        bound = {'mapStart': '0xff9b5c8e0000'}
        for text in [self.ARM_LIST.replace('5c8e0000', '5c8e0001'),
            self.ARM_LIST+self.ARM_LIST.splitlines()[0]+'\n',
            'linux-vdso.so.1 (0x1)\n'+self.ARM_LIST,
            self.ARM_LIST+'libx.so => not found\n', self.ARM_LIST+'unexpected\n',
            self.ARM_LIST+' /foreign/ld-linux-aarch64.so.1 (0x2)\n']:
            with self.subTest(text=text), self.assertRaises(ValueError):
                R.elf_resolved(text, bound)

    def test_loader_diagnostic_is_fixed_and_retains_separate_streams(self):
        with tempfile.TemporaryDirectory() as d:
            c = R.Capture(Path(d))
            result = R.subprocess.CompletedProcess([], 0, b'list', b'diagnostic')
            with patch.object(R.subprocess, 'run', return_value=result) as run:
                self.assertEqual(c.elf_list(Path('/usr/bin/true'), Path('/exact/binary')), ('list', 'diagnostic'))
                self.assertEqual(run.call_args.args[0], ['/usr/bin/true', '--list', '/exact/binary'])
                self.assertEqual({k:v for k,v in run.call_args.kwargs['env'].items() if k.startswith('LD_')}, {'LD_DEBUG':'files'})
            self.assertEqual((Path(d)/c.calls[0]['stderrLog']).read_text(), 'diagnostic')

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
