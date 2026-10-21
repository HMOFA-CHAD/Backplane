#!/usr/bin/env python3
"""Focused framework directory-link resolution and package-root controls."""
import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('release_assets', Path(__file__).resolve().parents[2]/'scripts/release-assets.py')
COLLECTOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(COLLECTOR)


class FrameworkLinks(unittest.TestCase):
    def package(self, links, files=None):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        archive = Path(temp.name)/'framework.tar.gz'
        with tarfile.open(archive, 'w:gz') as out:
            for name in files or ['pkg/F/Versions/A/Foo', 'pkg/F/Versions/A/Resources/icon']:
                raw = b'payload'
                item = tarfile.TarInfo(name)
                item.size = len(raw)
                item.mode = 0o644
                out.addfile(item, io.BytesIO(raw))
            for name, target in links.items():
                item = tarfile.TarInfo(name)
                item.type = tarfile.SYMTYPE
                item.linkname = target
                out.addfile(item)
        return archive

    def accepted(self, links, destination, files=None):
        package = COLLECTOR.Package(self.package(links, files))
        self.addCleanup(package.close)
        for name, expected in destination.items():
            self.assertEqual(package.link_destination(name), expected)
        return package

    def refused(self, links, message, files=None):
        with self.assertRaisesRegex(ValueError, message):
            COLLECTOR.Package(self.package(links, files))

    def test_file_below_current_directory_link(self):
        self.accepted({'pkg/F/Versions/Current':'A', 'pkg/F/Foo':'Versions/Current/Foo'}, {'pkg/F/Foo':'pkg/F/Versions/A/Foo'})

    def test_directory_below_current_directory_link(self):
        self.accepted({'pkg/F/Versions/Current':'A', 'pkg/F/Resources':'Versions/Current/Resources'}, {'pkg/F/Resources':'pkg/F/Versions/A/Resources'})

    def test_multiple_directory_link_prefixes(self):
        self.accepted({'pkg/F/Versions/Current':'Stable', 'pkg/F/Versions/Stable':'A', 'pkg/F/Foo':'Versions/Current/Foo'}, {'pkg/F/Foo':'pkg/F/Versions/A/Foo'})

    def test_same_directory_link_reused_without_cycle(self):
        self.accepted({'pkg/alias':'.', 'pkg/link':'alias/alias/file'}, {'pkg/link':'pkg/file'}, ['pkg/file'])

    def test_dangling_file_after_directory_alias_refused(self):
        self.refused({'pkg/F/Versions/Current':'A', 'pkg/F/Foo':'Versions/Current/absent'}, 'target absent')

    def test_dangling_directory_alias_refused(self):
        self.refused({'pkg/F/Versions/Current':'missing'}, 'target absent')

    def test_direct_link_cycle_refused(self):
        self.refused({'pkg/a':'b', 'pkg/b':'a'}, 'cycle')

    def test_expanding_parent_link_cycle_refused(self):
        self.refused({'pkg/a':'a/child'}, 'cycle or depth')

    def test_parent_alias_escape_before_dotdot_refused(self):
        self.refused({'pkg/alias':'.', 'pkg/link':'alias/../outside'}, 'escapes package root', ['pkg/outside'])

    def test_cross_root_link_refused(self):
        self.refused({'pkg/link':'../other/file'}, 'escapes package root', ['other/file'])

    def test_member_below_symlink_parent_remains_refused(self):
        self.refused({'pkg/F/Versions/Current':'A'}, 'traverses a symlink parent', ['pkg/F/Versions/A/Foo','pkg/F/Versions/Current/injected'])

    def test_required_metadata_cannot_be_read_through_link(self):
        package = self.accepted({'pkg/F/Versions/Current':'A','pkg/F/Foo':'Versions/Current/Foo'}, {'pkg/F/Foo':'pkg/F/Versions/A/Foo'})
        with self.assertRaisesRegex(ValueError, 'absent or symlinked'):
            package.read('pkg/F/Foo')

    def test_absolute_link_remains_refused(self):
        self.refused({'pkg/link':'/outside'}, 'unsafe archive symlink')


if __name__ == '__main__':
    unittest.main()
