#!/usr/bin/env python
""":created: 2017-08-19
"""
from __future__ import print_function
__description__ = "txt - "
__version__ = '0.0.4-dev' # script-mpe
#__db__ = '~/.txt.sqlite'
__usage__ = """
Usage:
    txt.py [options] todolist LIST
    txt.py [options] urllist LIST
    txt.py -h|--help
    txt.py --version

Options:
  -O FMT, --output-format FMT
                json, json-stream, str, repr [default: str]
  --verbose     ..
  --quiet       ..
  -h --help     Show this usage description.
  --version     Show version (%s).

""" % ( __version__ )
import os

import libcmd_docopt
import res.txt
import res.todo
import res.js

import res.list2
#from taxus.init import SqlBase, get_session
#from taxus import Node, Topic

#models = [ Node, Topic, Journal ]


def cmd_urllist(LIST, g):
    prsr = res.list2.URLListParser()
    list(prsr.load_file(LIST))
    r = []
    for line, rawstr, text, it in prsr.items:
        if g.output_format == 'json-stream':
            res.js.dumps(it.todict())
        elif g.output_format == 'repr':
            print(repr(it))
        elif g.output_format == 'str':
            print(str(it))
        else:
            r.append(it.todict())
    if g.output_format == 'json':
        res.js.dumps(r)

def cmd_todolist(LIST, opts, settings):
    prsr = res.todo.TodoTxtParser()
    list(prsr.load(LIST))
    for k in prsr:
        print(prsr[k].todotxt())
        #print(res.js.dumps(prsr[k].attrs))


### Transform cmd_ function names to nested dict

commands = libcmd_docopt.get_cmd_handlers_2(globals(), 'cmd_')
commands['help'] = libcmd_docopt.cmd_help


### Util functions to run above functions from cmdline

def main(opts):

    """
    Execute command.
    """

    settings = opts.flags
    opts.default = 'meta-to-json'
    return libcmd_docopt.run_commands(commands, settings, opts)

def get_version():
    return 'txt.mpe/%s' % __version__


if __name__ == '__main__':
    import sys
    reload(sys)
    sys.setdefaultencoding('utf-8')
    opts = libcmd_docopt.get_opts(__description__ + '\n' + __usage__, version=get_version())
    sys.exit(main(opts))
