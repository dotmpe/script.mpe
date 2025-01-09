#!/usr/bin/env python
"""
:created: 2015-11-30
:updated: 2016-06-06

Python helper to query/update Projectdir metadatadocument

Usage:
    projectdir-meta [options] get-repo <prefix>
    projectdir-meta [options] put-repo <prefix> [<kwdargs>...]
    projectdir-meta [options] update-repo <prefix> [<kwdargs>...]
    projectdir-meta [options] drop-repo <prefix>
    projectdir-meta [options] (enabled|disabled) <prefix>
    projectdir-meta [options] (enable|disable) <prefix>
    projectdir-meta [options] clean-mode <prefix> [<mode>]
    projectdir-meta [options] list-basedirs [<root>]
    projectdir-meta [options] list-prefixes [<root>]
    projectdir-meta [options] list-enabled [<root>]
    projectdir-meta [options] list-disabled [<root>]
    projectdir-meta [options] get-uri <prefix> [<remote>]
    projectdir-meta [options] list-remotes <prefix>
    projectdir-meta [options] list-upstream <prefix> [<branches>...]
    projectdir-meta [options] status [<prefix>]
    projectdir-meta [options] package [<prefix>]
    projectdir-meta [options] sort
    projectdir-meta [options] exit
    projectdir-meta [options] x-conv
    projectdir-meta [options] x-check
    projectdir-meta [options] (dump|x-dump) [<prefix>]
    projectdir-meta --filesystem PATH
    projectdir-meta --background [options]
    projectdir-meta (-h | --help)

Options:
  -S, --address ADDRESS
                The address that the socket server will be listening on. If
                the socket exists, any command invocation is relayed to the
                server intance, and the result output and return code
                returned to client. [default: /var/run/pd-serv.sock]
  --background  Turns script into socket server. This does not fork, detach
                or do anything else but enter an infinite server loop. Commands
                are invoked the same way as with regular command-line arguments,
                but written to the socket.
  -f PD, --file PD
                Give custom path to projectdir document file
                [default: ~/.conf/etc/projects.yaml]
  --filesystem PATH
                Run filesystem server and mount at path. A background process
                must be running. TODO: no vfs impl. yet.
  -q, --quiet   Quiet operations
  -s, --strict  Strict operations
  -g, --glob    Change from root prefix matching to glob matching.
  -G, --global  Use global enabled status, instead of per host.
  -a, --all     List all prefixes
  -l, --local   List local prefixes
  -H NAME, --host NAME
                Hostname to use for current entries.

Schema:
    repositories:
        - Root key, contains a map of all local path prefixes leading to SCM
          checkouts. Below each prefix key
    disabled:
        - Boolean indicator requests checkout to be available if false, or if
          available and true, to be cleaned up and removed.
    enabled:
        - Vice versa to disabled.
    remotes:
        - A map of local names for remote GIT urls, updated from the GIT remotes
          config, and configured for fresh checkouts upon enabling prefixes.

    clean:
        - enum: tracked|untracked|excluded
        - Mode of cleanliness to employ to check for changed or new files in
          project, before removing the checkout upon disable.

          The modes are in order of strictness: tracked only checks versioned
          files, untracked also considers the presence of unversioned, unignored
          files. Excluded also considers files ignored (ie. by .gitignore).

          Verifying wether a checkout has staged or unstaged changes (is dirty)
          or has cruft is one, preferably the first step in syncing or cleaning.
          The other is syncing.

    sync:
        - Complex variant value to indicate up and downstream remote references
          for local references. Upstream references are synced from, dowstream
          references are synced to, and full sync is done normally.

          A boolean 'true' value indicates all remotes are synced from and to,
          ie. no up- or down- but full-sync is assumed if no pull or push
          qualifiers are given. Alternatively either a single or list of remote
          names can restrict full-sync with selected remotes.

          TODO: there needs to be a way to deal with specific references (tags/branches)
          and also push and pull only.
          XXX: something like this::

            sync:
            - origin: true
            - seed:
                pull:
                - master
            - joe:
                - master
                - dev
            - pub:
                push:
                - master
                - v*

          with remotes origin, seed, joe and pub.

          Upon syncing, the .git/FETCH_HEAD has to have a minimum modification
          age, or the remotes are fetched first. Then the references are
          compared, using simple name matching, with the local references.
          Any delta is noted in the number of commits.

          Sync exits with an error code if any remote or local reference is
          behind.

          XXX: if a project is to be deleted, it may forego the actual pull, if ffwd.

    submodule:
        - Boolean indicator wether this checkout is not a standalone,
          but part of a parent project.

          XXX: Pd currently holds no submodule prefixes. But is does need to
          deal with clean/sync of embedded submodules before rm -rf'ing a prefix!

    TODO: valid attributes include those from package
        (script:) init, check, test

    status:
        XXX: contains at least result attr,
        and totals for each named IO.
        Also keys with per-target result & IO.

        Status object appears at root, and at each prefix.

    targets:
        named, virtual targets defined in DSL

"""
from __future__ import print_function
import os
from fnmatch import fnmatch
from pprint import pformat
from socket import gethostname

import uuid
from deep_eq import deep_eq
from ruamel.yaml import comments

from script_mpe import libcmd_docopt, confparse
from script_mpe.res import js
from script_mpe.confparse import yaml_load, yaml_safe_dumps

#try:
#    import fuse
#except ImportError:
#    projectdir_vfs = None
#finally:
#    import projectdir_vfs


def meta_from_projectdir_doc(data):
    newdata = {}

    for prefix in list(data['repositories'].keys()):

        remotes = dict( data['repositories'][prefix]['remotes'] )
        repoid = "repo:_:%s" % uuid.uuid4()
        newdata[repoid] = dict(
            prefix=prefix,
            remotes=remotes
        )
    return newdata


toggle_states = 'disabled', 'enabled'

def toggle(state):
    if state == toggle_states[0]:
        return toggle_states[1]
    else:
        return toggle_states[0]

def toggle_active(state):
    return state == toggle_states[1]

def toggle_inactive(state):
    return state == toggle_states[0]

def get_toggle_state(data):
    for state in toggle_states:
        if state in data:
            if data[state]:
                return state
            else:
                return toggle(state)

def set_toggle_state(data, state):
    assert state in toggle_states

    if toggle(state) in data:
        del data[toggle(state)]

    enabled = state == toggle_states[1]

    data[state] = True



repo_modes = ['tracked', 'untracked', 'excluded']

def get_clean_mode(repo):
    """Clean mode is 'tracked' to only consider changes to tracked files,
    untracked to include those as well, or excluded to consider all files in
    the checkout directory including GIT ignored files.
    """
    if 'clean' in repo:
        repo_mode = repo['clean']
    else:
        repo_mode = True
    if isinstance(repo_mode, bool):
        if repo_mode == True:
            repo_mode = 'untracked'
        else:
            repo_mode = 'tracked'
    if not repo_mode:
        repo_mode = 'untracked'
    return repo_mode


def get_one_prefix(pdhdata, ctx):
    "TODO: setup try catch and only stacktrace for debug/unexpected errors"
    prefix = ctx.opts.args.prefix
    if prefix not in pdhdata['repositories']:
        ctx.out.write("No such repo prefix %r\n" %prefix)
        return 3
    record = pdhdata['repositories'][prefix]
    return record

def prefix_match(prefix, match, opts):
    """Match path <prefix> with root-path or pattern <match> """
    if match:
        # Match glob or prefix
        if opts.flags.glob:
            return fnmatch( prefix, match )
        else:
            return prefix.startswith( match )

        return False
    else:
        # No prefix is match all
        return True


def check_state(target, pdhdata, ctx):
    "Project repo Enabled/Disabled function"
    prefix = ctx.opts.args.prefix
    if prefix not in pdhdata['repositories']:
        ctx.out.write("No such repo prefix %r\n" % prefix)
        return 3
    state = get_toggle_state(pdhdata['repositories'][prefix])
    if not ctx.opts.flags.quiet:
        ctx.out.write("%s\t%s\n" % ( prefix, state ))
    if ctx.opts.flags.strict and state is None:
        return
    if target != state:
        return 1

def toggle_state(newstate, pdhdata, ctx):
    prefix = ctx.opts.args.prefix
    if prefix not in pdhdata['repositories']:
        ctx.out.write("No such repo prefix %r\n" % prefix)
        return False
    state = get_toggle_state(pdhdata['repositories'][prefix])
    if newstate+'d' != state:
        set_toggle_state( pdhdata['repositories'][prefix], newstate+'d' )
        yaml_safe_dumps(pdhdata,
                open(os.path.expanduser(ctx.opts.flags.file), 'w+'), default_flow_style=False)
    return True

def toggle_host(newstate, pdhdata, ctx):
    #record = get_one_prefix(pdhdata, ctx)
    prefix = ctx.opts.args.prefix
    if prefix not in pdhdata['repositories']:
        ctx.out.write("No such repo prefix %r\n" % prefix)
        return 3
    record = pdhdata['repositories'][prefix]
    if 'hosts' not in record:
        record['hosts'] = []
    if 'enable' in newstate:
        if ctx.opts.flags.host not in record['hosts']:
            record['hosts'] += [ ctx.opts.flags.host ]
    elif 'disable' in newstate:
        if ctx.opts.flags.host in record['hosts']:
            record['hosts'].remove( ctx.opts.flags.host )

def check_host(record, ctx):
    if 'hosts' in record:
        if ctx.opts.flags.host in record['hosts']:
            return True
    return False

def yaml_commit(pdhdata, ctx):
    yaml_safe_dumps(pdhdata, os.path.expanduser(open(ctx.opts.flags.file),
        'w+'), default_flow_style=False)

def yaml_sort(doc, key, recurse=True):
    o = dict(doc[key])
    new_o = comments.CommentedMap()
    for k in sorted(o):
        v = o[k]
        if isinstance(v, dict):
            v = yaml_sort(o, k)
        new_o[k] = v
    doc[key] = new_o

def repo_kv_to_dict( kwdargs ):
    new = dict(remotes={})
    new.update(dict([ k.split('=') for k in kwdargs if k ]))
    for k,v in list(new.items()):
        if isinstance(v, str):
            if v.lower() == 'true':
                v = True
            elif v.lower() == 'false':
                v = False
            #elif v.isdigit():
            #    v = int(v)
        if k in "disabled enabled clean sync remotes annex description todo":
            new[k] = v
        else:
            del new[k]
            if k.startswith('remote_'):
                k = k[7:]
            new['remotes'][k] = v
    return new

def update_repo(pdhdata, ctx):
    # add/update/drop repo metadata
    new = repo_kv_to_dict( ctx.opts.args.kwdargs )

    p = ctx.opts.args.prefix
    if ctx.opts.cmds[0] == 'update-repo':
        if p not in pdhdata['repositories']:
            ctx.out.write("No such repo prefix %r\n" % p)
            return 2
        updated = dict(pdhdata['repositories'][p])
        updated.update(new)
        if deep_eq( pdhdata['repositories'][p], updated ):
            return 42
        pdhdata['repositories'][p] = updated
    else:
        if p in pdhdata['repositories']:
            ctx.out.write("Repo prefix exists %r\n" % p)
            return 3
        pdhdata['repositories'][p] = new

    yaml_commit(pdhdata, ctx)

def list_state(target, pdhdata, ctx):
    for k in list(pdhdata['repositories'].keys()):
        if not prefix_match( k, ctx.opts.args.root, ctx.opts ):
            continue
        state = get_toggle_state(pdhdata['repositories'][k])
        if state is None:
            continue
        bstate = toggle_active(state)
        if bstate:
            if 'enable' in target:
                yield k #print >>ctx.out, k
        elif 'disable' in target:
            yield k #print >>ctx.out, k

def list_host_state(target, pdhdata, ctx):
    for k in list(pdhdata['repositories'].keys()):
        if not prefix_match( k, ctx.opts.args.root, ctx.opts ):
            continue
        record = pdhdata['repositories'][k]
        if check_host(record, ctx):
            if 'enable' in target:
                yield k #print >>ctx.out, k
        elif 'disable' in target:
            yield k #print >>ctx.out, k

def init_hostname(ctx):
    if not ctx.opts.flags.host:
        ctx.opts.flags.host = gethostname().split('.')[0]
        print("# Set host to %s" % ( ctx.opts.flags.host ))


#

def H_list_upstream(pdhdata, ctx):
    repos = pdhdata['repositories']
    assert ctx.opts.args.prefix in repos, "No key %s" %ctx.opts.args.prefix

    branches = 'branches' in ctx.opts.args and ctx.opts.args.branches
    if not branches: branches = '*'
    sync = None
    if 'sync' in repos[ctx.opts.args.prefix]:
        sync = repos[ctx.opts.args.prefix]['sync']

    if not sync:
        if sync == None and ctx.opts.flags.strict:
            return 1
        return

    p = ctx.opts.args.prefix
    if isinstance(sync, list):
        for remote in sync:
            for branch in branches:
                ctx.out.write("%s %s\n" % (remote, branch))
    elif isinstance(sync, str):
        assert sync in repos[p]['remotes'], sync
        for branch in branches:
            ctx.out.write("%s %s\n" % (sync, branch))
    elif isinstance(sync, bool):
        for remote in repos[p]['remotes']:
            for branch in branches:
                ctx.out.write("%s %s\n" % (remote, branch))

def H_list_remotes(pdhdata, ctx):
    repos = pdhdata['repositories']
    assert ctx.opts.args.prefix in repos, "No key %s" %ctx.opts.args.prefix
    for remote in repos[ctx.opts.args.prefix]['remotes']:
        ctx.out.write(remote + "\n")

def H_get_uri(pdhdata, ctx):
    repos = pdhdata['repositories']
    assert ctx.opts.args.prefix in repos, "No key %s" %ctx.opts.args.prefix
    remote = 'origin'
    if 'remote' in ctx.opts.args:
        remote = ctx.opts.args.remote or 'origin'
    remotes = repos[ctx.opts.args.prefix]['remotes']
    assert remote in remotes, remote
    ctx.out.write(remotes[remote] + "\n")

def H_disabled(pdhdata, ctx):
    return check_state(ctx.opts.cmds[0], pdhdata, ctx)
def H_enabled(pdhdata, ctx):
    return check_state(ctx.opts.cmds[0], pdhdata, ctx)

def H_enable(pdhdata, ctx):
    if ctx.opts.flags['global']:
        return toggle_state(ctx.opts.cmds[0], pdhdata, ctx)
    else:
        return H_enable_host(pdhdata, ctx)

def H_disable(pdhdata, ctx):
    if ctx.opts.flags['global']:
        return toggle_state(ctx.opts.cmds[0], pdhdata, ctx)
    else:
        return H_disable_host(pdhdata, ctx)

def H_enable_host(pdhdata, ctx):
    if not check_state(ctx.opts.cmds[0], pdhdata, ctx):
        assert toggle_state(ctx.opts.cmds[0], pdhdata, ctx)
    return toggle_host(ctx.opts.cmds[0], pdhdata, ctx)

def H_disable_host(pdhdata, ctx):
    if check_state(ctx.opts.cmds[0], pdhdata, ctx):
        assert toggle_state(ctx.opts.cmds[0], pdhdata, ctx), (
                ctx.opts.cmds[0],
                pdhdata['repositories'].keys(),
                ctx.opts.args.prefix
            )
    return toggle_host(ctx.opts.cmds[0], pdhdata, ctx)


# Return or check for clean-mode. Giving a mode argument implies quiet/exit.
# With -q, be quiet and exit non-zero if required-mode >= given-mode
# With -s, be strict, and exit non-zero if required-mode != given-mode
# With no argument print whatever value repo-mode is, and with -s exit on None
def H_clean_mode(pdhdata, ctx):
    mode = ctx.opts.args.mode
    if mode:
        ctx.opts.flags.quiet = True
    if ctx.opts.args.prefix in pdhdata['repositories']:

        repo = pdhdata['repositories'][ctx.opts.args.prefix]
        repo_mode = get_clean_mode(repo)
        if not mode:
            assert not ctx.opts.flags.quiet, "illegal quiet flag"
            #assert not ctx.opts.flags.strict, "illegal strict flag"
            if ctx.opts.flags.strict:
                if not repo_mode:
                    return 1
            else:
                ctx.out.write(repo_mode)
        elif ctx.opts.flags.strict:
            if repo_mode != mode:
                return 1
        else:
            #print repo_modes.index(repo_mode), repo_modes.index(mode)
            if repo_modes.index(repo_mode) < repo_modes.index(mode):
                #if ctx.opts.flags.quiet:
                return 1

        #if not (opts.flags.strict or opts.flags.quiet):
        #    mode = 'untracked'
        #else:
        #    if ctx.opts.flags.strict:
        #        if repo_mode != mode:
        #            return 1
        #    else:
        #        if repo_modes.index(repo_mode) < repo_modes.index(mode):
        #            return 1
    else:
        for k in list(pdhdata['repositories'].keys()):
            if not prefix_match( k, ctx.opts.args.prefix, ctx.opts ):
                continue
            repo = pdhdata['repositories'][k]
            repo_mode = get_clean_mode(repo)
            if ctx.opts.flags.strict:
                if repo_mode != mode:
                    return 1
            else:
                if repo_modes.index(repo_mode) < repo_modes.index(mode):
                    return 1

def H_get_repo(pdhdata, ctx):
    p = ctx.opts.args.prefix
    repos = pdhdata['repositories']
    if not ctx.opts.flags.quiet:
        if p in repos:
            print(js.dumps(repos[p]))
    if p not in repos:
        return 1

def H_put_repo(pdhdata, ctx):
    if ctx.opts.args.prefix in pdhdata['repositories']:
        raise Exception("Prefix already in use")
    return update_repo(pdhdata, ctx)
def H_update_repo(pdhdata, ctx):
    return update_repo(pdhdata, ctx)

def H_drop_repo(pdhdata, ctx):
    p = ctx.opts.args.prefix
    del pdhdata['repositories'][p]
    yaml_commit(pdhdata, ctx)

def H_sort(pdhdata, ctx):
    """
    Sort repositories and sub-objects.
    """
    p = ctx.opts.args.prefix
    yaml_sort(pdhdata, 'repositories')
    yaml_commit(pdhdata, ctx)

def H_list_basedirs(pdhdata, ctx):
    for k in list(pdhdata['repositories'].keys()):
        if prefix_match( k, ctx.opts.args.root, ctx.opts ):
            ctx.out.write(k + "\n")

def list_prefixes_recurse(data, ctx):
    for k in list(data.keys()):
        if k in ( 'symlinks', 'description', 'status' ): continue
        if not isinstance(data[k], dict):
            ctx.err.write("Not a mapping object: %r\n" % data[k])
            continue
        if 'enabled' in data[k] or 'disabled' in data[k] \
                or 'remotes' in data[k] \
                or 'src' in data[k]:
            yield k
        else:
            for k2 in list_prefixes_recurse(data[k], ctx):
                yield "%s/%s" % ( k, k2 )

def H_list_prefixes(pdhdata, ctx):
    """Recurse into base-dirs to each checkout and print path.
    """
    # List all project repo prefixes
    for k in list_prefixes_recurse(pdhdata['repositories'], ctx):
        if prefix_match( k, ctx.opts.args.root, ctx.opts ):
            ctx.out.write(k + "\n")

def H_list_enabled(pdhdata, ctx):
    prefixes = []

    if ctx.opts.flags['all'] or not (
                ctx.opts.flags['all'] or ctx.opts.flags['local'] or
                ctx.opts.flags['global']
            ):
        ctx.opts.flags['local'] = ctx.opts.flags['global'] = True

    if ctx.opts.flags['local']:
        init_hostname(ctx)
        local_prefixes = list_host_state(ctx.opts.cmds[0], pdhdata, ctx)
        if local_prefixes:
            prefixes += local_prefixes

    if ctx.opts.flags['global']:
        global_prefixes = list_state(ctx.opts.cmds[0], pdhdata, ctx)
        if global_prefixes:
            prefixes += global_prefixes

    if prefixes:
        ctx.out.write('\n'.join(prefixes) + "\n")

def H_list_disabled(pdhdata, ctx):
    return H_list_enabled(pdhdata, ctx)

def H_dump(pdhdata, ctx):
    if 'prefix' not in ctx.opts.args:
        ctx.out.write(yaml_safe_dumps(pdhdata, default_flow_style=False), "\n")
    else:
        ctx.out.write("repositories:\n")
        for k in list(pdhdata['repositories'].keys()):
            if not prefix_match( k, ctx.opts.args.prefix, ctx.opts ):
                continue
            ctx.out.write("  %s:\n" % k)
            v = pdhdata['repositories'][k]
            ctx.out.write("    "+ yaml_safe_dumps(v
                ).replace( '\n', '\n    ')+"\n")

def H_x_dump(pdhdata, ctx):
    meta = meta_from_projectdir_doc(pdhdata)
    ctx.out.write(yaml_safe_dumps(meta, default_flow_style=False)+"\n")

def H_x_check(pdhdata, ctx):
    for h in handlers:
        if h not in ctx.usage:
            ctx.err.write("Missing %s docs\n" % h)
    print(ctx.usage)

def H_x_conv(pdhdata, ctx):
    """
    Convert old yaml format
    """
    newd = dict(repositories={})
    for k, v in list(pdhdata['repositories'].items()):
        sd = {}
        r = {}
        for sk, sv in list(pdhdata['repositories'][k].items()):
            if sk in ('enabled', 'disabled', 'title', 'description', 'clean'):
                sd[sk] = sv
            else:
                assert sk != 'enable', 'FIXME'
                assert sk != 'disable', 'FIXME'
                r[sk] = sv
        sd['remotes'] = r
        newd['repositories'][k] = sd
    yaml_commit(newd, ctx)



def update_status(data):
    v = True
    for s in list(data.keys()):
        if s == 'result': continue
        if isinstance(data[s], dict):
            update_status(data[s])
            v = v and data[s]['result'] == 0
        else:
            assert isinstance(data[s], int), type(data[s])
            v = v and data[s] == 0
    data['result'] = [1, 0][v]


def H_status(pdhdata, ctx):
    ok = True

    if 'prefix' in ctx.opts.args:
        ctx.out.write("status:\n")
        prefixes = []
        for k in list(pdhdata['repositories'].keys()):
            if not prefix_match( k, ctx.opts.args.prefix, ctx.opts ):
                continue
            ctx.out.write("  %s:\n" % k)
            v = pdhdata['repositories'][k]
            if 'status' not in v:
                return 1
            prefixes += [ k ]
            update_status(v['status'])
            ctx.out.write("    " + yaml_safe_dumps(v['status'], default_flow_style=False).replace( '\n', '\n    ').strip() + "\n")

    for k in prefixes:
        ok = ok and v['status']['result'] == 0

    ctx.out.write("  result: %s\n" % ( [1, 0][ok] ))

    return [1, 0][ok]

def H_update_states(pdhdata, ctx):
    if 'prefix' not in ctx.opts.args:
        """FIXME: find deepest states, update to all paths above
        """
    else:
        for k in list(pdhdata['repositories'].keys()):
            if not prefix_match( k, ctx.opts.args.prefix, ctx.opts ):
                continue
            v = pdhdata['repositories'][k]
    return 0


# FIXME: parser is in jsotk, also fkv cannot always be parsed back to dict
#from jsotk_lib import FlatKVParser

def read_sh_pack(fn):
    #prsr = FlatKVParser()
    #prsr.scan(open(fn))
    #return prsr.data

    lines = open(fn).readlines()
    lpackd = {}
    for line in lines:
        if not line.strip() or line.strip().startswith('#'): continue
        spos = line.index('=')
        k = line[:spos]
        assert k.startswith('package_')
        k = k[8:]
        if k.startswith('environment_'):
            pass #print k[12:]
        elif '__' in k:
            continue
        elif k.startswith('pd_meta_'):
            k = k[8:]
# TODO: set scripts in their own schema
            if 'pd-meta' not in lpackd:
                lpackd['pd-meta'] = {}
            if k in 'test init check':
                #lpackd['script'][k] = line[spos+1:].strip()
                lpackd['pd-meta'][k] = line[spos+1:].strip()
        else:
            lpackd[k] = line[spos+1:].strip()

    lpackd = set_sh_pack_types(lpackd)

    return lpackd


def set_sh_pack_types(lpackd):
    for k in list(lpackd.keys()):
        if isinstance(lpackd[k], dict):
            lpackd[k] = set_sh_pack_types(lpackd[k])
            continue
        elif not isinstance(lpackd[k], str):
            continue
        if lpackd[k].lower() in "true false":
            lpackd[k] = bool(lpackd[k])
        elif lpackd[k].isdigit() :
            lpackd[k] = int(lpackd[k], 10)
        else:
            lpackd[k] = lpackd[k].strip('"\'')
    return lpackd


def H_package(pdhdata, ctx):
    """
    Show current package metadata at prefix. Loads and merges .package.sh
    """
    pref = ctx.opts.args.prefix
    if not pref: return 1

    m = pdhdata['repositories'][pref]

    lpack = os.path.join(pref, '.package.sh')
    lpackd = {}
    if os.path.exists(lpack):
        lpackd = read_sh_pack(lpack)
        pack_id = lpackd['id']
    else:
        pack_id = pref

    pack = [ dict(
          type='application/vnd.org.wtwta.project',
          main=pack_id,
          id=pack_id
      ) ]

    pack[0].update( lpackd )
    pack[0].update( pdhdata['repositories'][pref] )

    for k in 'status', 'benchmarks', 'enabled':
        if k in pack[0]:
            del pack[0][k]

    ctx.out.write(yaml_safe_dumps(pack, default_flow_style=False) + "\n")



handlers = {}
for k, h in list(locals().items()):
    if not k.startswith('H_'):
        continue
    handlers[k[2:].replace('_', '-')] = h

# XXX: no sessions
pdhdata = None
def prerun(ctx, cmdline):
    global pdhdata

    argv = cmdline.split(' ')
    ctx.opts = libcmd_docopt.get_opts(ctx.usage, argv=argv)

    if not pdhdata:
        pdhdata = yaml_load(open(os.path.expanduser(ctx.opts.flags.file)))

    return [ pdhdata ]


def main(ctx):

    """
    Run command, or start socket server.

    Normally this returns after running a single subcommand.
    If backgrounded, There is at most one server per projectdir
    document. The server remains in the working directory,
    and while running is used to resolve any calls. Iow. subsequent executions
    turn into UNIX domain socket clients in a transparent way, and the user
    command invocation is relayed via line-based protocol to the background
    server isntance.

    For projectdir document, which currently is 15-20kb, this setup has a
    minimal performance boost, while the Pd does not need
    to be loaded from and committed back to disk on each execution.

    """

    if ctx.opts.flags.background:
        # Start background process
        localbg = __import__('local-bg')
        if not ctx.opts.flags.quiet:
            print("Starting background server at", ctx.opts.flags.address)
        return localbg.serve(ctx, handlers, prerun=prerun)

    elif ctx.opts.flags.filesystem:
        assert projectdir_vfs, "Fuse import error"
        addr = ctx.opts.flags.address
        assert os.path.exists(addr), \
            "Expected socket to background process at %s" % serveraddr
        localbg = __import__('local-bg')
        fs = projectdir_vfs.ProjectDirFS(server=addr)
        FUSE(fs, ctx.opts.flags.filesystem, nothreads=True, foreground=True)

    elif os.path.exists(ctx.opts.flags.address):
        # Query background process
        localbg = __import__('local-bg')
        return localbg.query(ctx)

    elif 'exit' == ctx.opts.cmds[0]:
        # Exit background process
        ctx.err.write("No background process at %s\n" % ctx.opts.flags.address)
        return 1

    else:
        # Normal execution
        pdhdata = yaml_load(open(os.path.expanduser(ctx.opts.flags.file)))
        func = ctx.opts.cmds[0]
        assert func in handlers
        return handlers[func](pdhdata, ctx)


if __name__ == '__main__':
    import sys
    ctx = confparse.Values(dict(
        usage=__doc__,
        out=sys.stdout,
        err=sys.stderr,
        inp=sys.stdin,
        opts=libcmd_docopt.get_opts(__doc__)
    ))
    if ctx.opts.args.prefix:
        ctx.opts.args.prefix = ctx.opts.args.prefix.strip(os.sep)
    if ctx.opts.args.prefix == '.':
        ctx.opts.args.prefix = None
    sys.exit( main( ctx ) )
