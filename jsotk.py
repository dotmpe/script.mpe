#!/usr/bin/env python3
"""
jsotk
=====
Javascript Object toolkit
~~~~~~~~~~~~~~~~~~~~~~~~~
:Created: 2015-12-28
:Updated: 2017-12-08


Read, convert, query or combine YAML or JSON-type data.

"""
from __future__ import print_function

__version__ = '0.0.4-dev' # script-mpe
__usage__ = """
jsotk - Javascript Object toolkit

Usage:
    jsotk [options] path [--is-new] [--is-null] [--is-list] [--is-obj]
            [--is-int] [--is-str] [--is-bool] <srcfile> <pathexpr>
    jsotk [options] objectpath <srcfile> <expr>
    jsotk [options] ( keys | items ) <srcfile> <pathexpr>
    jsotk [options] ( dump | json2yaml | yaml2json ) [<srcfile> [<destfile>]]
    jsotk [options] (from-kv|to-kv) [<srcfile> [<destfile>]]
    jsotk [options] (from-flat-kv|to-flat-kv) [<srcfile> [<destfile>]]
    jsotk [options] from-args <kv_args>...
    jsotk [options] from-flat-args <fkv-args>...
    jsotk [options] merge-one <srcfile> <srcfile2> [<destfile>]
    jsotk [options] merge <destfile> <srcfiles>...
    jsotk [options] append <destfile> <pathexpr> [<srcfiles>...]
    jsotk [options] update <destfile> [<srcfiles>...] [--clear-paths=<path>...]
    jsotk [options] update-from-args <srcfiles> <kv-args> <destfile>
    jsotk [options] update-at <destfile> <expr> [<srcfiles>...]
    jsotk [options] serve <destfile>
    jsotk [options] encode <srcfile>
    jsotk (version|-V|--version)
    jsotk (help|-h|--help)
    jsotk [options] [dump] [<srcfile> [<destfile]]
    jsotk --background [options]


Options:
  -q, --quiet   Quiet operations
  -s, --strict  Strict(er) operations, step over less failure states.
  --no-strict-types
                Turn off type checking on updates, ie. overwrite value with
                different type.
  -p, --pretty  Pretty output formatting.
  -I <format>, --input-format <format>
                Override input format. See Formats_.
                TODO: default is to autodetect from filename
                if given, or set to [default: json].
  -O <format>, --output-format <format>
                Override output format. See Formats_.
                TODO: default is to autodetect from filename
                if given, or set to [default: json].
  --no-indices  [default: false]
  --serialize-datetime=FMT
                [default: %Y-%m-%dT%H:%M:%SZ]
  --serialize-date=FMT
                [default: %Y-%m-%dZ]
  --detect-format
  --no-detect-format
                Auto-detect input/output format based on file-name extension
                [default: true]
  --output-prefix PREFIX
                Path prefix for output [default: ]
  --list-update
  --list-update-nodict
  --list-union  .
  --ignore-aliases
                .
  --no-stdin    .
  -N, --empty-null
                Instead of null, print empty line.
  --line-input  Parse input lines separately.
                Only with merge JSON.
  --background  Turns script into socket server. This does not actually fork,
                detach or do anything else but enter an infinite server loop:
                use shell job control to background it.
  -S, --address ADDRESS
                The address that the socket server will be listening on for a
                backgrounded process. This defaults to JSOTK_SOCKET, and
                creates one if '--background' is requested. [default: /tmp/jsotk-serv.sock]
                .
                If the socket exists, any command invocation is relayed to the
                "server" instance, and the result output and return code
                returned to client. This python client process is less efficient
                as using a socket client from a shell script.
                .
                If no ADDRESS or JSOTK_SOCKET is found the invocation is
                executed normally
  --objects
                Mode for table writer.
  --columns C
                Select specific columns to output.
  --no-head     Do not print header/column line at start.
  --socket      Use socket server with 'serve'
  --fifo        Use FIFO IO with 'serve'
  --stacktrace  Dump entire stack-trace after catching exception.
  --info        Chat a bit more (but don't enable stacktraces).
  -V, --version
                Print version

Formats
-------
json (i/o)
    ..
yaml (i/o)
    ..
pkv (i/o)
    Parse syntax like::

        path/to[1]/item=value-for-object-path
        path/to[]=append-item-value

    To::

        {"path": {"to": [ {"item": "value-for-object-path"}, "append-item-value" ] } }

fkv (i/o)
    Like pkv, but this is even more restrictive in key characters, keys
    can only contain [A-Za-Z_][A-Za-z0-9_]+ and everything else is lost.
    Still the (example at pkv) above can be represented, for example::

        path_to__1_item=value-for-object-path
        path_to__2=append-item-value

    Double underscores are used to separate path elements.
py (o)
    Given one or more results, output as python value.
lines|list (o)
    Given a list result, simply output items line by line.
table (o)
    ..
xml (i/o)
    ..
properties (i)
    ..
ini (i)
    ..

Dev
----
- Functions seem to be behaving, but need a bit of refactoring to make the
  arguments more consistent and clear. Maybe need to ditch docopt.
- Background is a work in progress, file input buffering and parsed structure
  caching needs to be added. jsotk (Sh) frontend is not in use yet.
- Another improvement may be seeking out SHM filesystem support.

..

  TODO: simplify. Start with good use-case testing and update/merge.. can
  we not create one command of those. Or change the mode:

  | update src dest dest dest [ or update src src --- dest ]
  | merge dest src src src [ or merge src src src dest ]

  Ie. update = many dests from one or more src, merge = one or new dest from
  many src. But both have same behaviour and options to do merge/update/union
  etc.

"""
try:
    from io import StringIO
except:
    # ImportError or ModuleNotFoundError
    from StringIO import StringIO
import shlex
import traceback
import types

try:
    from objectpath import Tree
except: # XXX py3? ModuleNotFoundError:
    pass

import libcmd_docopt, confparse
from jsotk_lib import PathKVParser, FlatKVParser, \
        load_data, stdout_data, readers, open_file, \
        get_src_dest_defaults, set_format, get_format_for_fileext, \
        get_dest, get_src_dest, \
        json_writer, parse_json, \
        deep_union, deep_update, data_at_path, data_check_path, maptype



### Sub-command handlers

# Conversions, json is default format

def H_dump(ctx, write=True):
    "Read src and write destfile according to set i/o formats. "
    infile, outfile = get_src_dest_defaults(ctx)
    data = load_data( ctx.opts.flags.input_format, infile, ctx )
    if write:
        return stdout_data( data, ctx, outf=outfile )
    else:
        return data


def H_merge_one(ctx):
    "Docopt does not handle args for 'merge', so instead use this. "
    ctx.opts.args.srcfiles = [ ctx.opts.args.srcfile, ctx.opts.args.srcfile2 ]
    H_merge(ctx)


def H_merge(ctx, write=True):
    """
    Merge srcfiles into last file. All srcfiles must be same format.

    Defaults to src-to-dest noop, iow. '- -' functions identical to
    'dump'.  """

    if not ctx.opts.args.srcfiles and not ctx.opts.flags.line_input:
        ctx.opts.args.srcfile = '-'
        return H_dump(ctx, write=write)

    if ctx.opts.flags.line_input:
        ctx.opts.args.srcfile = ctx.opts.args.srcfiles.pop(0)
        set_format('input', 'src', ctx.opts)
        inp = open_file(ctx.opts.args.srcfile, 'in', ctx=ctx)
        ctx.opts.args.srcfiles += [ StringIO(line) for line in inp.readlines() ]
    else:
        ctx.opts.args.srcfile = ctx.opts.args.srcfiles[0]
        set_format('input', 'src', ctx.opts)

    if not (ctx.opts.flags.list_union or ctx.opts.flags.list_update):
        if ctx.opts.flags.list_update_nodict:
            ctx.opts.flags.list_update = True
        else:
            ctx.opts.flags.list_union = True

    data = None
    for srcfile in ctx.opts.args.srcfiles:
        mdata = None
        if hasattr(srcfile, 'read'):
            infile = srcfile
        elif isinstance(srcfile, (dict, list)):
            mdata = srcfile
            srcfile = '<inline>'
            infile = None
        else:
            infile = open_file(srcfile, defio='in', ctx=ctx)
        if infile and not mdata:
            mdata = load_data( ctx.opts.flags.input_format, infile, ctx )
        if not data:
            data = type(mdata)()
        elif not isinstance(mdata, type(data)):
            raise ValueError( "Srcsfiles must have same root type. "\
                    "Expected %s, but found %s (%s)" % (
                            type(data), type(mdata), srcfile ) )
        if isinstance(data, dict):
            deep_update([data, mdata], ctx)
        elif isinstance(data, list):
            data = deep_union([data, mdata], ctx)
        else:
            raise ValueError(data)

    if write:
        if not ctx.opts.flags.quiet:
            sys.stderr.write("Writing to %s\n" % ctx.opts.args.destfile)
        outfile = open_file(ctx.opts.args.destfile, mode='w+', ctx=ctx)
        return stdout_data( data, ctx, outf=outfile )
    else:
        return data


def H_append(ctx):
    "Add srcfiles as items to list. Optionally provide pathexpr to list. "
    if not ctx.opts.args.srcfiles:
        return
    appendfile = get_dest(ctx, 'r')
    data = l = load_data( ctx.opts.flags.output_format, appendfile, ctx )
    if ctx.opts.args.pathexpr:
        l = data_at_path(ctx, None, data)
    for src in ctx.opts.args.srcfiles:
        fmt = get_format_for_fileext(src) or ctx.opts.flags.input_format
        mdata = load_data( fmt, open_file( src, 'in', ctx=ctx ), ctx )
        l.append(mdata)
    updatefile = get_dest(ctx, 'w+')
    return stdout_data( data, ctx, outf=updatefile )


def H_update(ctx):
    "Update srcfile from stdin. Write to destfile or stdout. "

    if not ctx.opts.args.srcfiles:
        return

    updatefile = get_dest(ctx, 'r')
    data = load_data( ctx.opts.flags.output_format, updatefile, ctx )
    updatefile.close()

    for cp in ctx.opts.flags.clear_paths:
        if cp.startswith('['):
            es = parse_json(cp)
        else:
            es = cp.split('/')
        cl = es.pop()
        v = data
        while es:
            el = es.pop(0)
            v = v[el]
        del v[cl]

    for src in ctx.opts.args.srcfiles:
        fmt = get_format_for_fileext(src) or ctx.opts.flags.input_format
        mdata = load_data( fmt, open_file( src, 'in', ctx=ctx ), ctx )
        deep_update([data, mdata], ctx)

    updatefile = get_dest(ctx, 'w+')
    return stdout_data( data, ctx, outf=updatefile )


def H_update_from_args(ctx):
    print('TODO')
    pass
    # TODO jsotk update-from-args
    #reader = PathKVParser(rootkey=args[0])
    #reader.scan_kv_args(ctx.opts.args.kv_args)


def H_update_at(ctx):
    """Update object at path, using data read from srcfile(s)"""
    if not ctx.opts.args.srcfiles:
        return
    updatefile = get_dest(ctx, 'r')
    data = o = load_data( ctx.opts.flags.output_format, updatefile, ctx )
    #if ctx.opts.args.pathexpr:
        #o = data_at_path(ctx, None, data)
    if ctx.opts.args.expr:
        q = Tree(data)
        assert q.data
        o = q.execute( ctx.opts.args.expr )
    if isinstance(o, types.GeneratorType):
        r = list(o)
        assert len(r) == 1, r
        o = r[0]
        #r = [ stdout_data( s, ctx, outf=sys.stdout) for s in o ]
        #print(r)
    for src in ctx.opts.args.srcfiles:
        fmt = get_format_for_fileext(src) or ctx.opts.flags.input_format
        mdata = load_data( fmt, open_file( src, 'in', ctx=ctx ), ctx )
        deep_update([o, mdata], ctx)
    updatefile = get_dest(ctx, 'w+')
    return stdout_data( data, ctx, outf=updatefile )


def H_encode(ctx):
    srcfile = ctx.opts.args.srcfile
    if srcfile == '-':
        src = sys.stdin
    else:
        src = open(srcfile)
    data = src.read()
    json_writer(data, sys.stdout, ctx)
    #print(ctx.opts.args.srcfile)



# Ad-hoc designed path query

def H_path(ctx):

    """
    Return data at path. Return 1 if path is not found. Use with ``--is-*``
    opts to OR-test for type or exit 2. To check if a path could be inserted,
    use ``--is-new``. This overrules not-found errors, but only if the path
    could be inserted. When any existing
    element does not match a list or object type it also exits non-zero.
    """

    infile, outfile = get_src_dest_defaults(ctx)
    data = None
    try:
        data = data_at_path(ctx, infile)
        infile.close()
    except (Exception) as err:
        if not ctx.opts.flags.is_new:
            if not ctx.opts.flags.quiet:
                tb = traceback.format_exc()
                sys.stderr.write(tb)
                sys.stderr.write("Error: getting %r: %r\n" % (
                    ctx.opts.args.pathexpr, err ))
            return 1

    res = [ ]

    for tp in "new list obj int str bool".split(" "):
        if ctx.opts.flags["is_%s" % tp]:
            # FIXME: print(maptype(tp))
            if tp == "new":
                infile, outfile = get_src_dest_defaults(ctx)
                if not data and data_check_path(ctx, infile):
                    res += [ 0 ]
            elif isinstance(data, maptype(tp)):
                res += [ 0 ]
            else:
                res += [ 1 ]

    if res and min(res) == 0:
        res = [ 0 ]

    if not ctx.opts.flags.quiet:
        res += [ stdout_data( data, ctx, outf=outfile ) ]

    if res:
        return max(res)


def H_keys(ctx):
    "Output list of keys or indices"
    infile, outfile = get_src_dest_defaults(ctx)
    try:
        data = data_at_path(ctx, infile)
    except:
        return 1
    if not data:
        return 1
    if isinstance(data, dict):
        return stdout_data( list(data.keys()), ctx, outf=outfile )
    elif isinstance(data, list):
        return stdout_data( range(0, len(data)), ctx, outf=outfile )
    else:
        raise ValueError("Unhandled type %s" % type(data))

def H_items(ctx):
    "Output for every key or item in object at path"
    infile, outfile = get_src_dest_defaults(ctx)
    try:
        data = data_at_path(ctx, infile)
    except:
        return 1
    if not data:
        return 1
    if isinstance(data, list):
        for item in data:
            stdout_data( item, ctx, outf=outfile )
    elif isinstance(data, dict):
        for key, value in data.items():
            subdata = { key: value }
            stdout_data( subdata, ctx, outf=outfile )
    else:
        raise ValueError("Unhandled type %s" % type(data))



def H_objectpath(ctx):
    infile, outfile = get_src_dest_defaults(ctx)
    data = load_data( ctx.opts.flags.input_format, infile, ctx )
    assert data
    q = Tree(data)
    assert q.data
    # DEBUG:
    #print("Query:", ctx.opts.args.expr )
    o = q.compile( ctx.opts.args.expr )
    o = q.execute( ctx.opts.args.expr )
    if isinstance(o, types.GeneratorType):
        for s in o:
            v = stdout_data( s, ctx, outf=outfile )
            if v:
                return v
    else:
        return stdout_data( o, ctx, outf=outfile )



# TODO: helper for plain text (parser-less) updates to YAML/JSON

def H_offsets(ctx):
    """
    TODO: could print offsets from yaml.tokens.*.start/end_mark

    Print source offsets in line/column and absolute characters
    for
        --keys
        --list-items

    jsotk offsets --key redmine --list-items
    jsotk offsets --path redmine.image --value
    jsotk offsets --path redmine.image --value
    """


## Conversion shortcuts


def H_yaml2json(ctx):
    ctx.opts.flags.input_format = 'yaml'
    return H_dump(ctx)

def H_json2yaml(ctx):
    ctx.opts.flags.output_format = 'yaml'
    return H_dump(ctx)


# Flat key-value from/to nested list/dicts

def H_from_args(ctx):
    args = ctx.opts.args.kv_args
    reader = PathKVParser(rootkey=args[0])
    reader.scan_kv_args(args)
    return stdout_data( reader.data, ctx )

def H_from_kv(ctx):
    ctx.opts.flags.input_format = 'pkv'
    return H_dump(ctx)

def H_to_kv(ctx):
    ctx.opts.flags.output_format = 'pkv'
    return H_dump(ctx)


def H_from_flat_args(ctx):
    args = ctx.opts.args.fkv_args
    reader = FlatKVParser(rootkey=args[0])
    reader.scan_kv_args(args)
    return stdout_data( reader.data, ctx )

def H_from_flat_kv(ctx):
    ctx.opts.flags.input_format = 'fkv'
    return H_dump(ctx)

def H_to_flat_kv(ctx):
    ctx.opts.flags.output_format = 'fkv'
    return H_dump(ctx)


serve_handlers = {
      'update': lambda ctx, doc: True
    }

def H_serve(ctx):
    """
    jsotk serve FILE
Usage:
    update KEY VALUE

Options:
    """
    #print(ctx.todict())
    infile, outfile = get_src_dest_defaults(ctx)
    print(infile, outfile)
    destfile = get_dest(ctx, 'r')
    print(destfile, ctx.opts.flags.input_format)
    data = load_data( ctx.opts.flags.input_format, destfile, ctx )
    if ctx.opts.flag.fifo:
        jsotk_serve.fifo(ctx, data, __doc__, handlers)
    elif ctx.opts.flag.socket:
        # XXX: ops on in-mem document may be nice
        from script_mpe import jsotk_serve
        jsotk_serve.serve(ctx, data, __doc__, handlers)
    else: pass

    if not ctx.opts.flags.quiet:
        sys.stderr.write("Writing to %s\n" % ctx.opts.args.destfile)
    outfile = open_file(ctx.opts.args.destfile, mode='w+', ctx=ctx)
    stdout_data( data, ctx, outf=outfile )



def H_version(ctx):
    print('script-mpe/'+__version__)



### Main


handlers = {}
for k, h in list(locals().items()):
    if not k.startswith('H_'):
        continue
    handlers[k[2:].replace('_', '-')] = h


### Service global(s) and setup/teardown handlers

doc_cache = None
def prerun(ctx, cmdline):
    global doc_cache

    if cmdline in [ 'exit' ]:
      ctx.opts.cmds = [ cmdline ]
    else:
      argv = shlex.split(cmdline)
      ctx.opts = libcmd_docopt.get_opts(ctx.usage, argv=argv)

    #if not pdhdata:
    #    pdhdata = yaml_load(open(ctx.opts.flags.file))

    return doc_cache


def main(func, ctx):

    """
    Run command, or start socket server.

    Normally this returns after running a single subcommand.
    If backgrounded, There is at most one server per jsotk
    document. The 'server' remains in the working directory,
    and while running is used to resolve any calls instead.

    """

    if ctx.opts.flags.background:
        # Start background process
        localbg = __import__('local-bg')
        return localbg.serve(ctx, handlers, prerun=prerun)

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
    if not ctx.opts.cmds: ctx.opts.cmds = ['dump']
    if ctx.opts.flags.no_detect_format:
        ctx.opts.flags.detect_format = False
    else:
        ctx.opts.flags.detect_format = True
    # TODO: ctx.opts.flags.no_json_string
    try:
        sys.exit( main( ctx.opts.cmds[0], ctx ) )
    except Exception as err:
        print(err)
        if not ctx.opts.flags.quiet:
            if ctx.opts.flags.stacktrace:
                tbstr = traceback.format_exc()
                sys.stderr.write(tbstr)

            tb = traceback.extract_tb( sys.exc_info()[2] )
            jsotk_tb = list(filter(None, map(
                lambda t: t[2].startswith('H_') and "%s:%i" % (t[2], t[1]),
              tb)))
            if not len(jsotk_tb):
              jsotk_tb = filter(None, map(
                  lambda t: 'jsotk' in t[0] and "%s:%i" % (
                      t[2].replace('<module>', 'jsotk.py'), t[1]), tb))
              # Remove two main lines (__main__ entrypoint and main() handler)
              jsotk_tb = jsotk_tb[2:]

            if ctx.opts.flags.info:
                sys.stderr.write('jsotk %s: Unexpected Error: %s (%s)\n' % (
                    ' '.join(sys.argv[1:]), err, ', '.join(jsotk_tb)))
            else:
                sys.stderr.write('jsotk: Unexpected Error: %s (%s)\n' % (
                    err, ', '.join(jsotk_tb)))

        sys.exit(1)
