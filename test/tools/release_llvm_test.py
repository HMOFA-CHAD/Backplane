#!/usr/bin/env python3
"""Offline official-tool extraction tests; no LLVM download or compilation."""
import importlib.util
import io
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('release_llvm',ROOT/'scripts/release-llvm.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)


class LLVMTest(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)

    def archive(self,extra=()):
        path=self.root/'llvm.tar.xz'
        items=[('bin/clang-21',b'compiler',tarfile.REGTYPE,''),
               ('bin/clang',b'',tarfile.SYMTYPE,'clang-21'),
               ('lib/clang/21/include/stddef.h',b'header',tarfile.REGTYPE,''),
               ('lib/x86_64-unknown-linux-gnu/libc++.so.1',b'cxxruntime',tarfile.REGTYPE,''),
               ('lib/libLLVM.so.21',b'llvmruntime',tarfile.REGTYPE,''),
               ('bin/lldb',b'unneeded debugger',tarfile.REGTYPE,''),
               ('lib/libclangStatic.a',b'unneeded static archive',tarfile.REGTYPE,'')]+list(extra)
        with tarfile.open(path,'w:xz') as t:
            for name,data,kind,link in items:
                info=tarfile.TarInfo('LLVM-21.1.8-Linux-X64/'+name);info.type=kind;info.linkname=link
                info.mode=0o755 if name.startswith('bin/') else 0o644
                if kind==tarfile.REGTYPE:info.size=len(data)
                t.addfile(info,io.BytesIO(data) if info.isfile() else None)
        return path

    def test_extracts_real_compiler_and_nested_shared_runtime_without_tool_bloat(self):
        out=self.root/'prefix';m.unpack(self.archive(),out)
        self.assertEqual((out/'bin/clang').resolve(),out/'bin/clang-21')
        self.assertTrue((out/'bin/clang').stat().st_mode & 0o111)
        self.assertTrue((out/'lib/x86_64-unknown-linux-gnu/libc++.so.1').exists())
        self.assertTrue((out/'lib/clang/21/include/stddef.h').exists())
        self.assertFalse((out/'bin/lldb').exists());self.assertFalse((out/'lib/libclangStatic.a').exists())

    def test_fresh_prefix_required(self):
        out=self.root/'exists';out.mkdir()
        with self.assertRaises(ValueError):m.unpack(self.archive(),out)

    def test_escaping_link_refused(self):
        with self.assertRaises(ValueError):m.unpack(self.archive([('lib/libbad.so',b'',tarfile.SYMTYPE,'../../escape')]),self.root/'prefix')

    def test_absolute_member_refused(self):
        with self.assertRaises(ValueError):m.safe('/absolute')
        with self.assertRaises(ValueError):m.safe('../escape')

    def test_wrong_actual_host_refused_before_network(self):
        with patch.object(m.platform,'system',return_value='Linux'), patch.object(m.platform,'machine',return_value='aarch64'), patch.object(m.urllib.request,'urlopen') as fetch:
            with self.assertRaises(ValueError):m.install('linux-x64',self.root/'prefix')
            fetch.assert_not_called()

    def test_wrong_published_digest_refused_before_extract(self):
        class Response(io.BytesIO):pass
        with patch.object(m.platform,'system',return_value='Linux'),patch.object(m.platform,'machine',return_value='x86_64'),patch.object(m.urllib.request,'urlopen',return_value=Response(b'wrong archive')),patch.object(m,'unpack') as unpack:
            with self.assertRaises(ValueError):m.install('linux-x64',self.root/'prefix')
            unpack.assert_not_called()


if __name__=='__main__':unittest.main()
