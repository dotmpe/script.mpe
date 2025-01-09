from __future__ import print_function
import os
import subprocess
import hashlib
import zlib

mhashlib = None # FIXME: malloc troubs
#import mhashlib # py-mhash 1.2

lt = None
try:
  import libtorrent as lt
except ImportError as e:
  pass

from .ck_unix import memcrc


# Alias zlib crc32 to hashlib
class crc32(object):
    name = 'crc32'
    digest_size = 4
    block_size = 1

    def __init__(self, arg=''):
        self.__digest = 0
        self.update(arg)

    def copy(self):
        copy = super(self.__class__, self).__new__(self.__class__)
        copy.__digest = self.__digest
        return copy

    def digest(self):
        return self.__digest

    def hexdigest(self):
        return '{:08x}'.format(self.__digest)

    def update(self, arg):
        self.__digest = zlib.crc32(arg, self.__digest) & 0xffffffff

hashlib.crc32 = crc32

# Python > 2.7: hashlib.algorithms += ('crc32',)
#hashlib.algorithms += ('crc32', )
# XXX: Python > 3.2:
hashlib.algorithms_available.add('crc32')


def rhash(path, name):
  cmd = [ 'rhash', '--simple', '--%s' % name, path ]
  line = subprocess.check_output(cmd)
  line = line.split('  ')
  return line[0]


def git_hash(path):
  cmd = [ 'git', 'hash-object', path ]
  return subprocess.check_output(cmd).split(' ')[0]


# Get checksums as int and pair with size

def unix_cksum(path):
  cmd = [ 'cksum', path ]
  return map(int, subprocess.check_output(cmd).split(' ')[:-1])

def py_unix_cksum(path):
  data = open(path, 'rb').read()
  cks = memcrc(data)
  return cks, len(data)

def rhash_cksum(f, algo='crc32b'):
  cks = rhash(f, 'crc32')
  return int(cks, 16), os.path.getsize(f)

def hashlib_cksum(f, algo='crc32'):
  data = open(f, 'rb').read()
  cks = getattr(hashlib, algo)(data).hexdigest()
  return int(cks, 16), len(data)

def php_crc32b_zip(f):
  cmd = [ 'php', '-r', '$f="%s";echo hexdec(hash_file("crc32b", $f))." ".filesize($f).PHP_EOL;' % ( f, ) ]
  line = subprocess.check_output(cmd)
  return map(int, line.split(' '))

def php_crc32_ethernet(f):
  cmd = [ 'php', '-r', '$f="%s";echo hexdec(hash_file("crc32", $f))." ".filesize($f).PHP_EOL;' % ( f, ) ]
  line = subprocess.check_output(cmd)
  return map(int, line.split(' '))


def tlit_cksum(f, format='plain', algo='crc32'):
  """
  TODO: work on checksum for literal texts, focussing on integrity of literal
  content, filtering out noise from formatting/encoding etc.

  XXX: Format:
  - plain for standard filters (unicode, universal lines and whitespace collapse)
  - fixed for unicode+universal lines only
  - sgml for standard+markup filter and allow per dialect fixed ranges
  - flowed for standard+soft-break-strip

  -F FMT, --format FMT
                 Set a filter list to preprocess data before hashing,

  --format-from MEDIATYPE
                 Determine the format from given MIME content-type header with
                 arguments. Set XML/SGML types

  TODO: add checksum attribute to Translit clinks/EDL files

  <url>?xuversion=1.0&locspec=charrange:11188/90
  <url>[?#;]scrow=1.0&locspec=charspan:89/7
  <url>[?#;]scrow=1.0&locspec=l1c0+76

  """
  cmd = [ ]
  return int(subprocess.check_output(cmd))


# resolvers reading data at local filename
file_resolvers = {

  'md5': lambda f: hashlib_cksum(f, 'md5')[0],
  'sha1': lambda f: hashlib_cksum(f, 'sha1')[0],
  'sha224': lambda f: hashlib_cksum(f, 'sha224')[0],
  'sha2': lambda f: hashlib_cksum(f, 'sha256')[0],
  'sha256': lambda f: hashlib_cksum(f, 'sha256')[0],
  'sha384': lambda f: hashlib_cksum(f, 'sha384')[0],
  'sha512': lambda f: hashlib_cksum(f, 'sha512')[0],

  'git': git_hash,

  # Crazy UNIX CRC32
  'ck': unix_cksum,
  'ckpy': py_unix_cksum,

  # Zip CRC32
  'zlib-crc32': hashlib_cksum,
  # Same as
  #python -c 'import binascii;print(binascii.crc32("asd\n") % (1<<32))'
  #python -c 'import zlib;print(zlib.crc32("asd\n") % (1<<32))'
  'rhash-crc32': lambda f: rhash_cksum(f, 'crc32'),
  'php-crc32b': php_crc32b_zip,

  # Ethernet CRC32
  'php-crc32': php_crc32_ethernet,


  # Other algos

  'rhash-tiger': lambda f: rhash(f, 'tiger'),
  'rhash-gost': lambda f: rhash(f, 'gost'),
  'rhash-aich': lambda f: rhash(f, 'aich'),
  'rhash-has160': lambda f: rhash(f, 'has160'),
  'rhash-snefru128': lambda f: rhash(f, 'snefru128'),
  'rhash-ripemd160': lambda f: rhash(f, 'ripemd160'),
  'rhash-ed2k': lambda f: rhash(f, 'ed2k'),
  'rhash-btih': lambda f: rhash(f, 'btih'),

  # Transliterature checksums (unicode, universal line-ends and collapsed whitespace)
  #'tlit-crc32': lambda f: tlit_cksum(f, 'crc32'),
  #'tlit-md5': lambda f: tlit_cksum(f, 'md5'),
  #'tlit-sha1': lambda f: tlit_cksum(f, 'sha1'),
  #'tlit-sha2': lambda f: tlit_cksum(f, 'sha256')
}

# CRC32 direct/lookup table B/... (ZIP)
algos_crc32b = "rhash-crc32 zlib-crc32 php-crc32b".split(' ')

# CRC32 crazy UNIX cksum compatible
algos_crc32_cksum_unix = "ck ckpy".split(' ')

# CRC32 lookup table (Ethernet)
algos_crc32_ethernet = ["php-crc32"]

# CRC32 output includes size and is single space separated, iso. double space
# as with other algos
cksums = algos_crc32b + algos_crc32_cksum_unix + algos_crc32_ethernet


class Table:

    @staticmethod
    def read(fl, algo=None):
        for line in fl.readlines():
            if line.strip().startswith('#'): continue
            if not algo or algo not in cksums:
                p = line.index('  ')
                ck = line[:p]
                fn = line[p+2:-1]
            else:
                p = line.index(' ', line.index(' ')+1)
                ck = tuple(map(int, line[:p].split(' ')))
                fn = line[p+1:-1]
            yield ck, fn
