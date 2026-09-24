#!/usr/bin/env python3
"""Move one local directory with macOS's atomic no-overwrite rename."""
import ctypes
import json
import os
import sys


def move(source, destination):
    if sys.platform != 'darwin':
        raise OSError('This helper requires macOS renamex_np.')
    libc = ctypes.CDLL(None, use_errno=True)
    rename = libc.renamex_np
    rename.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    # Darwin SDK sys/stdio.h: RENAME_EXCL = 0x00000004.
    if rename(os.fsencode(source), os.fsencode(destination), 0x00000004):
        code = ctypes.get_errno()
        raise OSError(code, os.strerror(code), destination)


if __name__ == '__main__':
    try:
        if len(sys.argv) != 3:
            raise ValueError('Expected exactly a source and destination directory.')
        move(sys.argv[1], sys.argv[2])
    except (OSError, ValueError) as error:
        print(json.dumps({'ok': False, 'error': str(error)}, ensure_ascii=False))
        sys.exit(1)
    print(json.dumps({'ok': True}))
