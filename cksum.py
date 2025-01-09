#!/usr/bin/env python
"""Process file checksum, one algorithm at a time.

CRC checks include size, and are separated by spaces. All other tables
are split at the double space.

Three algorithms for CRC32 are tested in test/ck-spec.bats: the common
UNIX cksum, and ZIP and Ethernet variants. A working but slow pure python
UNIX cksum 'ckpy' is provided. Other algorithms are taken from hashlib, or
wrapped invocations of rhash or php. See script_mpe.res.ck.
"""
from __future__ import print_function
__description__ = "cksum.py - "
__version__ = '0.0.4-dev' # script-mpe

from script_mpe.libhtd import *
from script_mpe.res.ck import *

__algos__ = file_resolvers.keys()
__default_algo__ = "ck"
__usage__ = """
Usage:
  cksum.py [-v... options] (-c|check) TABLE...
  cksum.py [-v... options] -l|list
  cksum.py [-v... options] [ FILES... | calc FILES... ]
  cksum.py -h|--help
  cksum.py help [CMD]
  cksum.py --version

Options:
  -c, --check
                 Check all entries from file
  -l, --list
                 List algos
  -a ALGO, --algorithm ALGO
                 Calculate one of available checkum algorithms:
                 %s [default: %s]
  -F FMT, --format FMT
                 TODO: see tlit cksum
  --format-from MEDIATYPE
                 TODO: see tlit cksum
  --verbose, -v  ..
  --quiet        ..
  -h --help      Show this usage description
  --version      Show version (%s)
""" % ( ",".join(__algos__), __default_algo__, __version__, )
import os
from itertools import chain


def cmd_list(opts):
    for algo in file_resolvers:
        print(algo)

def cmd_calc(FILES, opts):
    num = len(FILES)
    algo = opts.flags.algorithm
    for fname in FILES:
        if algo in cksums:
            try:
                cksum, size = file_resolvers[algo](fname)
            except Exception as e:
                print("Error for %s of %s: %s" % (algo, fname, e), file=sys.stderr)
                #traceback.print_exc()
                continue
            print( "%d %d %s" % (cksum, size, fname))
        else:
            try:
                cksum = file_resolvers[algo](fname)
            except Exception as e:
                print("Error for %s of %s: %s" % (algo, fname, e), file=sys.stderr)
                #traceback.print_exc()
                continue
            if num > 1:
                print( "%s  %s" % (cksum, fname))
            else:
                print(cksum)

def cmd_check(TABLE):
    v = True
    algo = opts.flags.algorithm
    for tabfn in TABLE:
        if tabfn == '-': tab = sys.stdin
        else: tab = open(tabfn)
        for ck, fname in res.ck.Table.read(tab):
            try:
                cksum = file_resolvers[algo](fname)
            except Exception as e:
                print("Error for %s of %s: %s" % (ck, fname, e), file=sys.stderr)
                #traceback.print_exc()
                continue
            if ck != cksum:
                print("%s: Failed" % fname)
                v = False
            else:
                print("%s: OK" % fname)
    return v


### Transform cmd_ function names to nested dict

commands = libcmd_docopt.get_cmd_handlers_2(globals(), 'cmd_')
commands.update(dict(
        help = libcmd_docopt.cmd_help,
        memdebug = libcmd_docopt.cmd_memdebug
    ))

### Util functions to run above functions from cmdline

def defaults(opts, init={}):
    libcmd_docopt.defaults(opts)
    return init

def main(opts):
    opts.default = 'calc'
    settings = opts.flags
    if settings.list: opts.cmds = ['list']
    if settings.check: opts.cmds = ['check']
    return libcmd_docopt.run_commands(commands, settings, opts)

def get_version():
    global __version__
    return 'script-mpe:cksum.py/%s' % __version__


if __name__ == '__main__':
    import sys
    reload(sys)
    sys.setdefaultencoding('utf-8')
    usage = __description__ +'\n\n'+ __usage__
    opts = libcmd_docopt.get_opts(
            usage, version=get_version(), defaults=defaults)
    sys.exit(main(opts))
