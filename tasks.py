#!/usr/bin/env python
""":created: 2016-09-10

Read and sync between tasks.ttxt and todo.list.
tasks.ttxt is formatted as todo.txt. todo.list is compatible with
``grep -Hn`` output, or with Radical full-sh format.

    <file> ':' <line> ': ' <matched>

    <file> [ ':' [ <line_nr> ]
        [ ':' [ <line_range> ]
            [ ':' [ <outer_char_range> ]
                [ ':' [ <inner_char_range> ] ]
            ]
        ]
        ': ' <inner_text>
    ]

Objects
    Issue
        - strid
        - priority|prio
        - project
        - projects
        - contexts
    Comment
        - srcfile
        - line|line_range|outer_range|inner_range
"""
__description__ = "tasks - time ordered, grouped tasks"
__version__ = '0.0.0'
__tasks_file__ = 'tasks.ttxt'
__grep_file__ = 'todo.list'
__usage__ = """
Usage:
  tasks.py [options] info
  tasks.py [options] read-issues
  tasks.py help
  tasks.py -h|--help
  tasks.py --version

Options:
    -t FILE --tasks-file=FILE
                  Document with ``todo.txt`` formatted tickets [default: %s].
    -g FILE --grep-file=FILE
                  Result file with line references and single line descriptions
                  parsed from source [default: %s].

    -s SLUG --project-slug=SLUG
                  Project name Id slug, used to match existing issues with
                  comments. Defaults to current directory reformatted in all
                  capitals and with non alphanumeric characters removed.
    -k TYPE --key-type=TYPE
                  Mode to create new issue tags, 'number': append count+1 or
                  'hex': append random hex ID, to project slug.
                  [default: hex]
    -K LEN --key-arg=LEN
                  Argument to create new issue tags: length of hex or offset
                  for number.
                  [default: 5]
    -S SEP --key-sep=SEP
                  Separator [default: -]

Other flags:
    -h --help     Show this usage description.
                  For a command and argument description use the command 'help'.
    --version     Show version (%s).

""" % ( __tasks_file__, __grep_file__, __version__ )
from datetime import datetime
import os
import re
import hashlib
from pprint import pformat

import log
import util


grep_nH_rs = re.compile('^([^:\ ]+):([0-9]+):\ (.*)$')

rad_cmnt_rs = re.compile('''^ ([^:\ ]+)
    (:
        (?:[0-9]+)?
        (:
            (?:[0-9]+-[0-9]+)?
            (:
                (?:[0-9]+-[0-9]+)?
                (:
                    (?:[0-9]+-[0-9]+)?
                )
            )
        )
    ): \ (.*) $''', re.VERBOSE)

class Issue:

    def __init__(self, project_slug, description):
        self.strid = None
        self.project_slug = project_slug
        self.description = description
        self.set_strid()

    def set_strid(self):
        if self.project_slug in self.description:
            pass

    @classmethod
    def from_comment(cls, comment, settings):
        pass

    @classmethod
    def parse_doc(cls, file, proj_tag):
        issues = {}
        if os.path.exists(file):
            for line in open(file).readlines():
                i = Issue(proj_tag, line.strip())
                issues[i.strid] = i
        return issues

class Comment:

    def __init__(self, srcfile, **values):
        self.srcfile = srcfile
        attr = dict(
                line_nr=None,
                line_range=None,
                inner_range=None,
                outer_range=None,
                issue_id=None
            )
        attr.update(values)
        for k, v in attr.items():
            setattr(self, k, v)

        if self.line_nr and not self.line_range:
            self.line_range = self.line_nr, self.line_nr
        elif self.line_range and not self.line_nr:
            self.line_nr = self.line_range[0]

    def __str__(self):
        return "%s %r" % ( self.strid or '(blank)', self.text )

    @classmethod
    def parse_tag_grep(cls, file, settings):

        for line in open(file).readlines():

            grep_nH_rs_match = grep_nH_rs.match(line)
            if grep_nH_rs_match:
                srcfile, linenr, comment = grep_nH_rs_match.groups()
                yield Comment(srcfile, linenr=linenr, text=comment)
                continue

            rad_cmnt_rs_match = rad_cmnt_rs.match(line)
            if rad_cmnt_rs_match:
                groups = list(rad_cmnt_rs_match.groups())
                srcfile, comment = groups.pop(0), groups.pop()
                fa = groups[0].count(':')
                fr = map(int, groups[0].strip(':').split('-'))
                if fa == 4:
                    inner_char_range = fr
                yield Comment(srcfile, inner_range=inner_char_range, text=comment)
                continue

            log.warn('No match for %r', line)

def get_project_slug(name_id):
    return re.sub('[^A-Z_-]+', '-', name_id.upper())


### Commands

def cmd_info(opts):
    """
        Dump settings dict.
    """
    for l, v in (
            ( "Tasks Document", opts.flags.tasks_file ),
            ( "Comment File", opts.flags.grep_file ),
            ( "Project Name Id Slug", opts.flags.project_slug ),
            ( "Key Type", opts.flags.key_type ),
            ( "Key Argument", opts.flags.key_arg ),
            ( "Key Separator", opts.flags.key_sep ),
    ):
        log.std('{green}%s{default}: {bwhite}%s{default}', l, v)

def cmd_read_issues(settings, opts, tasks_file, grep_file):
    """
        Read new issues from grep-list and write to tasks-doc.
    """
    issues = Issue.parse_doc(tasks_file, settings.project_slug)
    for comment in Comment.parse_tag_grep(grep_file, settings):
        if not comment.issue_id:
            log.warn("No %r ID for %s:%s: %s", settings.project_slug,
                    comment.srcfile, comment.line_nr, comment.text )
            continue
        # TODO: scan for project slug, and match with taskdoc.
        if comment.strid not in issues:
            issues[comment.issue_id] = Issue.from_comment(comment, settings)
        else:
            pass # TODO: check, update from changed comment


### Transform cmd_ function names to nested dict

commands = util.get_cmd_handlers_2(globals(), 'cmd_')
commands['help'] = util.cmd_help


### Util functions to run above functions from cmdline

def main(opts):

    """
    Execute command.
    """

    settings = opts.flags
    values = opts.args

    return util.run_commands(commands, settings, opts)

def get_version():
    return 'tasks.mpe/%s' % __version__

if __name__ == '__main__':
    import sys
    opts = util.get_opts(__description__ + '\n' + __usage__, version=get_version())
    if not opts.flags.project_slug:
        opts.flags.project_slug = get_project_slug(os.path.basename(os.getcwd()))
    sys.exit(main(opts))

