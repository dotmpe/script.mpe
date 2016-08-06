import re

from fnmatch import fnmatch
from res import js
from confparse import yaml_load, yaml_safe_dump


re_non_escaped = re.compile('[\[\]\$%:<>;|\ ]')
re_alphanum = re.compile('[^a-z0-9A-Z]')

class AbstractKVParser(object):

    """
    Parse dict or list from arguments::

        a/b/c=1 a/d=2  ->  { a: { b: { c: 1 }, d: 2 } }

    """

    def __init__(self, seed=None, rootkey=None):
        super(AbstractKVParser, self).__init__()
        self.data = seed
        if rootkey:
            self.scan_root_type(rootkey)

    def scan_root_type(self, key):
        "Initialize root (self.data) to correct data type: dict or list"
        if '/' in key:
            key = key.split('/')[0]
        self.data = FlatKVParser.get_data_instance(key)

    def scan(self, fh):
        " Parse from file, listing one kv each line. "

        self.scan_init(fh)

        for line in fh.readlines():
            self.set_kv(line)

    def scan_init(self, fh):
        # XXX: need bufered read.. See also H_update reader.scan
        #pos = fh.tell()
        #if self.data is None:
        #    rootkey = fh.read(1)
        #    while rootkey[-1] != '=':
        #        rootkey += fh.read(1)
        #    self.scan_root_type(rootkey)
        #    fh.seek(pos)
        if self.data is None:
            firstline = fh.readline()
            self.scan_root_type(firstline.split('=')[0])
            self.set_kv(firstline)

    def scan_kv_args(self, args):
        " Parse from list of kv's. "
        for arg in args:
            self.set_kv(arg)

    def set_kv(self, kv):
        " Split kv to key and value, the the first '=' occurence. "
        if '=' not in kv: return
        pos = kv.index('=')
        key, value = kv[:pos].strip(), kv[pos+1:].strip()
        self.set( key, value )


    def set( self, key, value, d=None, default=None, values_as_json=True ):
        """ Parse key to path within dict/list struct and insert value.
        kv syntax::

            list[] = value
            key = value
            key/sub = value

        Append value to a list::

            key/list[5]/subkey/mylist[] = value

        """

        # Maybe want to allow other parsers too, ie YAML values
        if isinstance(value, basestring):
            if values_as_json:
                value = parse_json(value)
            else:
                value = parse_primitive(value)

        if d is None:
            d = self.data
        if '/' in key:
            self.set_path(key.split('/'), value)
        else:
            di = self.__class__.get_data_instance(key)
            if isinstance(di, list):
                pos = key.index('[')

                if key[:pos] not in d:
                    d[key[:pos]] = di

                if len(key) > pos+2:
                    idx = int(key[pos+1:-1])

                    while len(d[key[:pos]]) <= idx:
                        d[key[:pos]].append(None)

                    d[key[:pos]][idx] = value

                else:
                    d[key[:pos]].append( value )

                return key[:pos]
            else:
                if value is None and default is not None:
                    if key not in d:
                        d[key] = default
                else:
                    d[key] = value
                return key

    def set_path( self, path, value ):
        assert isinstance(path, list), "Path must be a list"
        d = self.data
        while path:
            k = path.pop(0)
            di = self.__class__.get_data_instance(k)
            if path:
                k = self.set( k, None, d, di )
            else:
                k = self.set( k, value, d )
            if path:
                d = d[k]

    @staticmethod
    def get_data_instance(key):
        "Get data container instance based on key pattern"
        raise NotImplementedError
        return None


class PathKVParser(AbstractKVParser):

    @staticmethod
    def get_data_instance(key):
        if fnmatch(key, '*[[0-9]]') or fnmatch(key, '*[]'):
            return []
        else:
            return {}

class FlatKVParser(AbstractKVParser):

    @staticmethod
    def get_data_instance(key):
        if fnmatch(key, '*__[0-9]*') or fnmatch(key, '*__*'):
            return []
        else:
            return {}



class AbstractKVSerializer(object):

    linesep = '\n'
    itemfmt, dirfmt = None, None

    write_indices = True

    def serialize(self, data, prefix=''):
        if prefix is None:
            prefix = ''
        return self.linesep.join(self.ser(data, prefix)) + self.linesep
    def ser(self, data, prefix=''):
        r = []
        if isinstance(data, list):
            r.extend(self.ser_list(data, prefix))
        elif isinstance(data, dict):
            r.extend(self.ser_dict(data, prefix))
        else:
            if isinstance(data, basestring) and re_non_escaped.search(data):
                r.append( "%s=\"%s\"" % ( prefix, data ))
            else:
                r.append( "%s=%s" % ( prefix, data ))
        return r
    def ser_list(self, data, prefix=''):
        r = []
        for i, item in enumerate(data):
            if not self.write_indices:
                i = ''
            r.extend(self.ser(item, prefix + self.itemfmt % i))
        return r
    def ser_dict(self, data, prefix=''):
        r = []
        for key, item in data.items():
            r.extend(self.ser(item, self.dir_prefix(prefix, key)))
        return r
    def dir_prefix(self, prefix, key):
        raise NotImplementedError

class PathKVSerializer(AbstractKVSerializer):
    dirfmt = '/%s'
    itemfmt = '[%s]'

    def dir_prefix(self, prefix, key):
        sp = prefix and prefix + self.dirfmt or '%s'
        return sp % key


class FlatKVSerializer(AbstractKVSerializer):
    dirfmt = '_%s'
    itemfmt = '__%s'

    def dir_prefix(self, prefix, key):
        sp = prefix and prefix + self.dirfmt or '%s'
        return sp % re_alphanum.sub('_', key)

def load_data(infmt, infile, ctx):
    data = readers[ infmt ]( infile, ctx )
    if isinstance(data, type(None)):
        raise Exception("No data from file %s (%s)" % ( infile, infmt ))
    return data

def stdout_data(outfmt, data, outfile, ctx):
    return writers[ outfmt ]( data, outfile, ctx )


def parse_json(value):
    if value.strip().startswith('{') or value.strip().startswith('['):
        return js.loads(value)
    else:
        return parse_primitive(value)


# TODO: use the propery serializer asked for, or add datatype lib option
re_float  = re.compile('\d+.\d+')
def parse_primitive(value):
    # TODO: other numbers
    if value.isdigit():
        return int(value)
    elif re_float.match(value):
        return float(value)
    elif value.lower() in ["true", "false"]:
        return value is 'true'
    else:
        return value


### Readers/Writers

def json_reader(file, ctx):
    return js.load(file)

def yaml_reader(file, ctx):
    return yaml_load(file)

def pkv_reader(file, ctx):
    reader = PathKVParser()
    reader.scan(file)
    return reader.data

def fkv_reader(file, ctx):
    reader = FlatKVParser()
    reader.scan(file)
    return reader.data

# FIXME: lazy loading readers, do something better to have optional imports
def xml_reader(file, ctx):
    from jsotk_xml_dom import reader
    return reader( file, ctx )

def properties_reader(file, ctx):
    from jsotk_properties import reader
    return reader( file, ctx )

def ini_reader(file, ctx):
    from jsotk_ini import reader
    return reader( file, ctx )


readers = dict(
        json=json_reader,
        yaml=yaml_reader,
        pkv=pkv_reader,
        fkv=fkv_reader,
        xml=xml_reader,
        properties=properties_reader,
        ini=ini_reader
    )


def write(writer, data, file, ctx):
    if ctx.opts.flags.no_indices:
        writer.write_indices = False
    file.write(writer.serialize(data, ctx.opts.flags.output_prefix))

def output_prefix(data, opts):
    if opts.flags.output_prefix:
        path = opts.flags.output_prefix
        parser = PathKVParser(rootkey=path)
        parser.set(path, data)
        data = parser.data
    return data


def pkv_writer(data, file, ctx):
    writer = PathKVSerializer()
    writer.linesep = ctx.sep.line
    write(writer, data, file, ctx)

def fkv_writer(data, file, ctx):
    writer = FlatKVSerializer()
    writer.linesep = ctx.sep.line
    write(writer, data, file, ctx)

def json_writer(data, file, ctx):
    kwds = {}
    if ctx.opts.flags.pretty:
        kwds.update(dict(indent=2))
    data = output_prefix(data, ctx.opts)
    if not data and ctx.opts.flags.empty_null:
        print >>file
    else:
        file.write(js.dumps(data, **kwds))
    print >>file

def yaml_writer(data, file, ctx):
    kwds = {}
    if ctx.opts.flags.pretty:
        kwds.update(dict(default_flow_style=False))
    data = output_prefix(data, ctx.opts)
    if not data and ctx.opts.flags.empty_null:
        print >>file
    else:
        yaml_safe_dump(data, file, **kwds)

def py_writer(data, file, ctx):
    if not data and ctx.opts.flags.empty_null:
        print >>file
    else:
        print >>file, str(data)

def lines_writer(data, file, ctx):
    if not data:
        return
    if not isinstance(data, (tuple, list)):
        data = [ data ]
    # XXX: seems object returns objects sometimes? assert isinstance(data, (tuple, list)), data
    for item in data:
        print >>file, item

# FIXME: lazy loading writers, do something better to have optional imports
def xml_writer(data, file, ctx):
    from jsotk_xml_dom import writer
    return writer( data, file, ctx )


writers = dict(
        json=json_writer,
        yaml=yaml_writer,
        pkv=pkv_writer,
        fkv=fkv_writer,
        py=py_writer,
        lines=lines_writer,
        xml=xml_writer
    )


fmt_ext_aliases = dict(
    yaml=[ 'yml' ],
    json=[ 'jso' ],
    kv=[ 'pkv' ],
    lines=[ 'list' ]
        )


### Misc. argument/option handling

def open_file(fpathname, defio='out', mode='r', ctx=None):
    if hasattr(fpathname, 'read'):
        return fpathname
    if not fpathname:
        fpathname = '-'
    if fpathname == '-':
        assert defio in ( 'in', 'out' ), defio
        if ctx:
            return ctx[defio]
        else:
            import sys
            return getattr(sys, 'std%s' % defio)
    else:
        try:
            return open(fpathname, mode)
        except IOError, e:
            raise Exception, "Unable to open %s for %s" % (fpathname, mode)

def get_src_dest(ctx):
    infile, outfile = None, None
    if 'srcfile' in ctx.opts.args and ctx.opts.args.srcfile:
        infile = open_file(ctx.opts.args.srcfile, defio='in', ctx=ctx)
    if 'destfile' in ctx.opts.args and ctx.opts.args.destfile:
        outfile = open_file(ctx.opts.args.destfile, mode='w+', ctx=ctx)
    return infile, outfile

def set_format(tokey, fromkey, opts):
    file = getattr(opts.args, "%sfile" % fromkey)
    if file and isinstance(file, basestring):
        fmt = get_format_for_fileext(file, fromkey)
        if fmt:
            setattr(opts.flags, "%s_format" % tokey, fmt)

def get_format_for_fileext(fn, io='out'):
    if io == 'out':
        fmts = writers.keys()
    else:
        fmts = readers.keys()

    for fmt in fmts:
        if fmt in fmt_ext_aliases:
            for alias in fmt_ext_aliases[fmt]:
                ext = ".%s" % alias
                if fn.endswith( ext ):
                    return fmt
        ext = ".%s" % fmt
        if fn.endswith( ext ):
            return fmt

def get_dest(ctx, mode):
    if ctx.opts.flags.detect_format:
        set_format('output', 'dest', ctx.opts)
    updatefile = None
    if 'destfile' in ctx.opts.args and ctx.opts.args.destfile:
        assert ctx.opts.args.destfile != '-'
        updatefile = open_file(
                ctx.opts.args.destfile, defio=None, mode=mode, ctx=ctx)
    return updatefile

def get_src_dest_defaults(ctx):
    if ctx.opts.flags.detect_format:
        set_format('input', 'src', ctx.opts)
        set_format('output', 'dest', ctx.opts)

    infile, outfile = get_src_dest(ctx)
    if not outfile:
        outfile = ctx.out
        if not infile:
            infile = ctx['in']
    return infile, outfile


def deep_update(dicts, ctx):
    """Merge dicts by overwriting first given dict, with keys/paths-value
    mappings found in subsequent dicts. Update embedded lists according to
    --list-update or --list-union, see deep_union.
    """
    assert len(dicts) > 1
    assert not isinstance( dicts[0], type(None) )
    assert not isinstance( dicts[1], type(None) )
    data = dicts[0]
    while len(dicts) > 1:
        mdata = dicts.pop(1)
        if not isinstance(mdata, dict):
            raise ValueError, "Expected %s but got %s" % (
                    type(data), type(mdata))
        for k, v in mdata.iteritems():
            if k in data:
                if isinstance(data[k], dict):
                    try:
                        deep_update( [ data[k], v ], ctx )
                    except ValueError, e:
                        raise Exception("Error updating %s (%r) with %r" % (
                                k, data[k], v
                            ), e)
                elif isinstance(data[k], list):
                    data[k] = deep_union( [ data[k], v ], ctx )
                else:
                    if not isinstance(data[k], type(v)):
                        raise ValueError, "Expected %s but got %s" % (
                                type(data[k]), type(v))
                    data[k] = v
            else:
                data[k] = v
    return data


def deep_union(lists, ctx):
    """List merger with different modes.

    Mode is 'update' to preserve indices (and assume equal length lists),
    while recursing into objects with deep_update. Mode 'union' does
    instead what the name implies, and adds unique items only, using
    deep_cmp on lists and dicts.

    --list-update          Update items at index, merging lists and dicts.
    --list-union           Gather unique values, ignore indices and never merge
                           items.
    --list-update-nodicts  Skip deep object updates, only merge lists.

    FIXME: update jsotk-merge to enable overrides --list-update-on=path/to/list
    --list-union-on=path/to/list

    Having  an index in any overridden path marks that list container for
    'update' mode, and raises an error on conflicting rules.
    More advanced feature not needed now. Also, may want set customized
    merge routines based on object type match, or value expressions of
    specific types, or path-expressions.
    """

    data = lists[0]
    while len(lists) > 1:
        mdata = lists.pop(1)
        if not isinstance(mdata, list):
            raise ValueError, "Expected %s but got %s" % (
                    type(data), type(mdata))
        for i, v in enumerate(mdata):
            if ctx.opts.flags.list_update:
                while len(data)-1 < i:
                    data.append(None)
                # cmp index-by-index
                if not ctx.opts.flags.list_update_nodict:
                    if isinstance(data[i], dict):
                        try:
                            v = deep_update([data[i], v], ctx )
                        except ValueError, e:
                            raise Exception("Error updating %s (%r) with %r" % (
                                    i, data[i], v
                                ), e)
                elif isinstance(data[i], list):
                    v = deep_union([data[i], v], ctx )
                data[i] = v

            elif ctx.opts.flags.list_union:
                # TODO: deep-compare objects
                if v not in data:
                    data.append(v)

    return data


def data_at_path(ctx, infile):
    if not infile:
        infile, outfile = get_src_dest_defaults(ctx)
    l = load_data( ctx.opts.flags.input_format, infile, ctx )
    path_el = ctx.opts.args.pathexpr.split('/')
    if not ctx.opts.args.pathexpr or path_el[0] == '':
        return l
    while len(path_el):
        b = path_el.pop(0)
        if b not in l:
            raise KeyError, b
        l = l[b]
    return l

