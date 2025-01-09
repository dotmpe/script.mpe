#!/usr/bin/env python3
"""
user-tools
==========
:Created: 2025-01-09
"""
from __future__ import print_function

import traceback

from script_mpe.res.ck import *
from script_mpe import libcmd_docopt, confparse

__algos__ = file_resolvers.keys()
__default_algo__ = "ck"
__version__ = '0.0.4-dev' # script-mpe
__usage__ = """
user-tools -

Usage:
    user-tools [options] hash [<Algo>]
    user-tools [options] hash-file <Path> [<Algo>]
    user-tools [options] hash-files <Paths>...
    user-tools [options] list-hash
    user-tools (version|-V|--version)
    user-tools (help|-h|--help)
    user-tools --background [options]

Options:
  -A, --algorithm ALGORITHM
                [default: %s]
  --background  Turns script into socket server. This does not actually fork,
                detach or do anything else but enter an infinite server loop:
                use shell job control to background it.
  --backtrace   Turn on trace output on exceptions.
  -q, --quiet   Quiet operations
  -s, --strict  Strict(er) operations, step over less failure states.
  -S, --address ADDRESS
                The address that the socket server will be listening on for a
                backgrounded process. This defaults to USER_SOCKET, and
                creates one if '--background' is requested.
                [default: /tmp/usertools-serv.sock]
                .
                If the socket exists, any command invocation is relayed to the
                "server" instance, and the result output and return code
                returned to client. This python client process is less efficient
                as using a socket client from a shell script.
                .
                If no ADDRESS or USER_SOCKET is found the invocation is
                executed normally
  --skipdirs    Check for and skip directory paths.
""" % __default_algo__


def H_hash(ctx):
    return 1

def H_hash_files(ctx):
    for fname in ctx.opts.args.Paths:
      if ctx.opts.flags.strict:
        if not ctx.opts.flags.skipdirs:
          if os.path.isdir(fname):
            return 2
      if ctx.opts.flags.skipdirs:
        if os.path.isdir(fname):
          if not ctx.opts.flags.quiet:
            print("Warning: skipping directory '%s'" % fname, file=sys.stderr)
          continue
      stat = hash_file( ctx.opts.flags.algorithm, fname, ctx)
      if stat: return stat

def H_hash_file(ctx):
    if ctx.opts.flags.strict:
      if os.path.isdir(ctx.opts.args.Path):
        return 2
    return hash_file( ctx.opts.flags.algorithm, ctx.opts.args.Path, ctx)

def H_list_hash(ctx):
    global file_resolvers
    for algo in file_resolvers:
        print(algo, file=ctx.out)

def H_version(ctx):
    global __version__
    print('script-mpe/'+__version__)


### Tools

# FIXME: for proper zero-padding going to need to know length of checksum
checksum_len = {
    'md5': 32,
    'sha1': 40,
    'sha2': 64,
    'sha256': 64,
    'git': 40
}

def hash_file(algo, fname, ctx):
    padding = checksum_len[algo]
    try:
        checksum = file_resolvers[algo](fname)
        cksum = "{0:0{1}X}".format(checksum, padding)
    except Exception as e:
        print("Error for %s of %s: %s" % (algo, fname, e), file=ctx.err)
        if ctx.opts.flags.backtrace:
          traceback.print_exc()
        return 1

    if ctx.opts.flags.strict:
      print( "%s  %s" % (cksum.lower(), fname), file=ctx.out)
    else:
      size = os.path.getsize(fname)
      print( "%s %d %s" % (cksum, size, fname), file=ctx.out)



### Main


handlers = {}
for k, h in list(locals().items()):
    if not k.startswith('H_'):
        continue
    handlers[k[2:].replace('_', '-')] = h


def main(func, ctx):

    """
    Run command, or start socket server.
    """

    if ctx.opts.flags.background:
        # Start background process
        localbg = __import__('local-bg')
        return localbg.serve(ctx, handlers) # , prerun=prerun)

    elif ctx.path_exists(ctx.opts.flags.address):
        # Query background process
        localbg = __import__('local-bg')
        return localbg.query(ctx)

    elif 'exit' == ctx.opts.cmds[0]:
        # Exit background process
        ctx.err.write("No background process at %s\n" % ctx.opts.flags.address)
        return 1

    else:
        # Normal execution
        return handlers[func](ctx)



if __name__ == '__main__':
    import sys, os
    if sys.argv[-1] == 'help':
        sys.argv[-1] = '--help'
    ctx = confparse.Values(dict(
        usage=__usage__,
        path_exists=os.path.exists,
        sep=confparse.Values(dict(
            line=os.linesep
        )),
        out=sys.stdout,
        inp=sys.stdin,
        err=sys.stderr,
        opts=libcmd_docopt.get_opts(__usage__)
    ))
    ctx['in'] = ctx['inp']
    if ctx.opts.flags.version: ctx.opts.cmds = ['version']
    if ctx.opts.args.Algo: ctx.opts.flags.algorithm = ctx.opts.args.Algo
    if not ctx.opts.cmds: ctx.opts.cmds = [None]
    try:
        sys.exit( main( ctx.opts.cmds[0], ctx ) )
    except Exception as err:
        print(err)
        if not ctx.opts.flags.quiet:
            if ctx.opts.flags.stacktrace:
                tbstr = traceback.format_exc()
                sys.stderr.write(tbstr)

            tb = traceback.extract_tb( sys.exc_info()[2] )
            usertools_tb = list(filter(None, map(
                lambda t: t[2].startswith('H_') and "%s:%i" % (t[2], t[1]),
              tb)))
            if not len(usertools_tb):
              usertools_tb = filter(None, map(
                  lambda t: 'usertools' in t[0] and "%s:%i" % (
                      t[2].replace('<module>', 'user-tools.py'), t[1]), tb))
              # Remove two main lines (__main__ entrypoint and main() handler)
              usertools_tb = usertools_tb[2:]

            if ctx.opts.flags.info:
                sys.stderr.write('usertools %s: Unexpected Error: %s (%s)\n' % (
                    ' '.join(sys.argv[1:]), err, ', '.join(usertools_tb)))
            else:
                sys.stderr.write('usertools: Unexpected Error: %s (%s)\n' % (
                    err, ', '.join(usertools_tb)))

        sys.exit(1)
