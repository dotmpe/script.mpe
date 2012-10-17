#!/usr/bin/env python
"""Resource -  A simple volume manager for media carriers.

Perhaps distributed metadata later.

A Volume is a resource identifying a physical storage medium,
as discrete media carrier that can be present at different places.

The object is still in taxus.module and need review, integration.

See Resourcer.rst

- Builds upon cmd.
"""
import os
import shelve
from pprint import pformat

import lib
import log
import confparse
from libname import Namespace, Name
from libcmd import Targets, Arguments, Keywords, Options,\
    Target 
from res import PersistedMetaObject, Metafile, Volume, Repo, Dir

from taxus import Node


NS = Namespace.register(
        prefix='rsr',
        uriref='http://project.dotmpe.com/script/#/.Resourcer'
    )

Options.register(NS, 

        (('-F', '--output-file'), { 'metavar':'NAME', 
            'default': None, 
            'dest': 'outputfile',
            }),

        (('-R', '--recurse', '--recursive'),{ 
            'dest': "recurse",
            'default': False,
            'action': 'store_true',
            'help': "For directory listings, do not descend into "
            "subdirectories by default. "
            }),

        (('-L', '--max-depth', '--maxdepth'),{ 
            'dest': "max_depth",
            'default': -1,
            'help': "Recurse in as many sublevels as given. This may be "
            " set in addition to 'recurse'. 0 is not recursing and -1 "
            "means no maximum level. "
            })

    )


@Target.register(NS, 'lib', 'cmd:userdir')
def rsr_lib_init(prog=None, lib=None, settings=None):
    """
    Initialize Workspace, 
    """
    assert prog.pwd, prog.copy().keys()
    # Normally /var/lib/cllct
    sysdir = conf.cmd.lib.paths.systemdir
    #sysdbpath = os.path.join(sysdir, conf.cmd.lib.name)
    # Normally ~/.cllct
    #usrdbpath = os.path.join(prog.userdir, conf.cmd.lib.name)
    # Initialize shelves
    #sysdb = PersistedMetaObject.get_store('system', sysdbpath)
    #usrdb = PersistedMetaObject.get_store('user', usrdbpath)
    voldbpath = os.path.expanduser(conf.cmd.lib.sessions.user_volumes)
    voldb = PersistedMetaObject.get_store('volumes', voldbpath)
    # XXX: 'default' is set to user-database
    #assert usrdb == PersistedMetaObject.get_store('default', usrdbpath)
    # XXX: 
    #    The objects lazy initialize static indices when needed,
    #    only provide path?
    yield Keywords(
            lib=confparse.Values(dict(
                stores=confparse.Values(dict(
    #                system=sysdb,
    #                user=usrdb,
                    volumes=voldb
                )),
                indices=confparse.Values(dict(
                )),
            )),
        )


@Target.register(NS, 'init-volume', 'cmd:pwd', 'cmd:lib')
def rsr_volume_init(prog=None, lib=None, conf=None):
    assert prog.pwd, prog.copy().keys()
    Volume.new(prog.pwd, lib, conf)


@Target.register(NS, 'volume', 'cmd:pwd', 'cmd:lib')
def rsr_volume(prog=None, opts=None, conf=None):
    """
    Return the current volume. In --init mode, a volume is created
    in the current directory.

    Arguments
     - prog.pwd
     - opts.init
    """
    assert prog.pwd, prog.copy().keys()
    Volume.init(conf)
    volumepath = Volume.find_root(prog.pwd, opts, conf)
    print 'volumepath=',volumepath
    volume = Volume.find(Volume.stores.objects, 'vpath', volumepath)
    assert volume, 'XXX'
    print 'volume=',volume
    #volume = Volume.find('volumes', 'pwd', prog.pwd)
    if not volume:
        if opts.init:
            log.info("New volume")
            name = Name.fetch('rsr:init-volume')
            assert name, name
            yield Targets('rsr:init-volume',)
        else:
            log.err("Not in a volume")
            yield 1
    else:
        log.note("rsr:volume %r for %s", volume.db, volume.full_path)
        yield Keywords(volume=volume)
        volumedb = PersistedMetaObject.get_store('volume', volume.db)
        log.info("rsr:volume index length: %i", len(volumedb))
        yield Keywords(volumedb=volumedb)
    #Metafile.default_extension = '.meta'
    #Metafile.basedir = 'media/application/metalink/'


@Target.register(NS, 'ls', 'rsr:volume')
def rsr_ls(volume=None):
    """

    """
    assert volume, volume
    cwd = os.getcwd();
    lnames = os.listdir(cwd)
    for name in lnames:
        path = os.path.join(cwd, name)
        metafile = Metafile(path)
        if not metafile.non_zero():
            print "------", path.replace(cwd, '.')
            continue
        #print metafile.data['Digest'], path.replace(cwd, '.')
    print
    print os.getcwd(), volume.path, len(lnames)


#@Target.register(NS, 'clean', 'cmd:options')
#def rsr_clean(volumedb=None):
#    log.debug("{bblack}rsr{bwhite}:clean{default}")
#    vlen = len(volumedb)
#    log.err("Rsr: Closing volumedb")
#    volumedb.close()
#    log.err("Rsr: Closed, %i keys", vlen)


@Target.register(NS, 'list-volume', 'rsr:volume', 'txs:session')
def rsr_list_volume(prog=None, volume=None, opts=None):
    for r in sa.query(Node).all():
        print r


@Target.register(NS, 'scan', 'rsr:volume')
def rsr_scan(prog=None, volume=None, opts=None):
    """
    Walk all files, gather metadata into metafile.
    """ 
    log.debug("{bblack}rsr{bwhite}:update-volume{default}")
    i = 0
    log.info("Walking %s", prog.pwd)
    for path in Metafile.walk(prog.pwd):
        log.debug("Found %s", path)
        i += 1
        metafile, metacache = Metafile(path), None
        #if opts.persist_meta 
            #if metafile.exists:
            #metafile.rebase(basedir)
        #metafile.basedir = 'media/application/metalink/'
        if metafile.has_metafile():
            log.err("Re-read persisted metafile for %s", metafile.path)
        metacache, metaupdate = None, None
        if metafile.key in volumedb:
            metacache = volumedb[metafile.key]
            log.info("Found cached metafile for %s", metafile.key)
            #metacmp = metafile.compare(metacache)
        if metacache and metafile.has_metafile():
            assert metacache == metafile, \
                    "Corrupted cache, or metafile was updated externally. "
        else:
            metafile = metacache
        if metafile.needs_update():
            log.note("Needs update %s", metafile.path)
            #log.note("Updating metafile for %s", metafile.path)
            #metaupdate = metafile.update()
        #if metafile.key not in volumedb:
        #    log.note("Writing %s to volumedb", metafile.key)
        #    volumedb[metafile.key] = metafile
        if not metafile.has_metafile() or metafile.updated:
            #if options.persist_meta:
            #    if metafile.non_zero:
            #        log.warn("Overwriting previous metafile at %s", metafile.path)
            #    metafile.write()
            for k in metafile.data:
                print '\t'+k+':', metafile.data[k]
            print '\tSize: ', lib.human_readable_bytesize(
                metafile.data['Content-Length'], suffix_as_separator=True)
        else:
            print '\tOK'
        yield metafile
    #volumedb.sync()


#@Target.register(NS, 'volume', 'rsr:shared-lib')
#def rsr_update_content(opts=None, sharedlib=None):
#    sharedlib.contents = PersistedMetaObject.get_store('default', 
#            opts.contentdbref)


#def rsr_count_volume_files(volumedb):
#    print len(volumedb.keys())

@Target.register(NS, 'repo-update', 'cmd:lib', 'cmd:pwd')
def rsr_repo_update(prog=None, objects=None, opts=None):
    i = 0
    for repo in Repo.walk(prog.pwd, max_depth=2):
        i += 1
        assert repo.rtype
        assert repo.path
        print repo.rtype, repo.path, 
        if repo.uri:
            print repo.uri
        else:
            print 


#@Target.register(NS, 'list-checksums', 'rsr:volume')
#def rsr_list_checksums(volume=None, volumedb=None):
#    i = 0
#    for i, p in enumerate(volumedb):
#        print p
#    print i, 'total', volume.path
#
#def rsr_content_20(opts=None):
#    pass # load index
#
#def rsr_content_sha1(opts=None):
#    pass # load index
#
#def rsr_list_nodes(self, **kwds):
#    print self.session.query(Node).all()
#
#def rsr_import_bookmarks(self):
#    """
#    Import from
#      - HTML
#      - Legacy delicious XML
#    """
#    print self.session
#
#def rsr_dump_bookmarks(self):
#    pass


@Target.register(NS, 'status', 'rsr:volume')#'cmd:lib', 'cmd:pwd')
def rsr_status(prog=None, objects=None, opts=None, conf=None):
    print PersistedMetaObject.sessions['default']
    print PersistedMetaObject.sessions['system']
    print PersistedMetaObject.sessions['user']
    Dir.find_newer(prog.pwd, )
    yield 0


# XXX: Illustration of the kwd types by rsr
import zope.interface
from zope.interface import Attribute, implements
# rsr:volume<IVolume>
class IVolume(zope.interface.Interface):
    pass
    # rsr:volume


if __name__ == '__main__':
    from libcmd import TargetResolver
    import cmd
    import txs
    import lind
    #import rsr
    import volume

    TargetResolver().main(['rsr:status'])


