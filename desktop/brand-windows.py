#!/usr/bin/env python3
"""Set a staged Windows executable's icon, on Windows, before signing."""
import ctypes
from ctypes import wintypes
from pathlib import Path
import struct
import sys


def apply(executable, icon):
    if sys.platform != 'win32':
        raise RuntimeError('Windows icon resources must be applied on the Windows packaging host before signing')
    data = Path(icon).read_bytes()
    reserved, kind, count = struct.unpack_from('<HHH', data)
    if reserved or kind != 1 or not 1 <= count <= 64:
        raise ValueError('Invalid ICO header')
    images, group = [], struct.pack('<HHH', 0, 1, count)
    for i in range(count):
        w, h, colors, r, planes, bits, size, offset = struct.unpack_from('<BBBBHHII', data, 6 + i*16)
        if offset < 6+count*16 or offset+size > len(data): raise ValueError('Invalid ICO image')
        images.append(data[offset:offset+size])
        group += struct.pack('<BBBBHHIH', w, h, colors, r, planes, bits, size, i+1)
    api = ctypes.WinDLL('kernel32', use_last_error=True)
    api.BeginUpdateResourceW.argtypes = [wintypes.LPCWSTR, wintypes.BOOL]
    api.BeginUpdateResourceW.restype = wintypes.HANDLE
    api.UpdateResourceW.argtypes = [wintypes.HANDLE, ctypes.c_void_p, ctypes.c_void_p, wintypes.WORD, ctypes.c_void_p, wintypes.DWORD]
    api.UpdateResourceW.restype = wintypes.BOOL
    api.EndUpdateResourceW.argtypes = [wintypes.HANDLE, wintypes.BOOL]
    api.EndUpdateResourceW.restype = wintypes.BOOL
    handle = api.BeginUpdateResourceW(str(Path(executable).resolve()), False)
    if not handle: raise ctypes.WinError(ctypes.get_last_error())
    try:
        for i, image in enumerate(images, 1):
            buffer = ctypes.create_string_buffer(image)
            if not api.UpdateResourceW(handle, 3, i, 1033, buffer, len(image)):
                raise ctypes.WinError(ctypes.get_last_error())
        buffer = ctypes.create_string_buffer(group)
        if not api.UpdateResourceW(handle, 14, 1, 1033, buffer, len(group)):
            raise ctypes.WinError(ctypes.get_last_error())
    except BaseException:
        api.EndUpdateResourceW(handle, True)
        raise
    if not api.EndUpdateResourceW(handle, False): raise ctypes.WinError(ctypes.get_last_error())


if __name__ == '__main__': apply(*sys.argv[1:])
