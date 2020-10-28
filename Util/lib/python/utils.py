from __future__ import print_function
from __future__ import with_statement

import sys
import os
import gzip
import datetime

from subprocess import check_output, CalledProcessError


def get_opener(fileName=None, compressed=True):
    ''' check if compressed files are expected and return
    appropriate opener '''
    opener = open
    if compressed or (fileName is not None and '.gz' in fileName):
        opener = gzip.open
    return opener


def is_integer(value):
    if isinstance(value, (float, bool)):
        return False
    try:
        int(value)
        return True
    except ValueError:
        return False


def is_float(value):
    try:
        float(value)
        return True
    except ValueError:
        return False



def to_numeric(value):
    ''' convert string to appropriate numeric '''
    try:
        return int(value)
    except ValueError:
        return float(value) # raises ValueError again that will be thrown



def convert_str2numeric_values(cdict):
    '''
    converts numeric values in dictionary stored as strings 
    to numeric
    '''

    for key, value in cdict.items():
        if is_float(value): # must check float first b/c integers are a subset
            cdict[key] = float(value)
        if is_integer(value):
            cdict[key] = int(value)

    return cdict


def execute_cmd(cmd, cwd=None, printCmdOnly=False, verbose=True, shell=False):
    '''
    execute a command
    '''
    if verbose or printCmdOnly:
        warning("EXECUTING: ", ' '.join(cmd))
        if printCmdOnly: return
    try:
        if shell:
            output = check_output(cmd, cwd=cwd, shell=True)
        else:
            output = check_output(cmd, cwd=cwd)
        warning(output)
    except CalledProcessError as e:
        die(e)



def gzip_file(filename, removeOriginal):
    '''
    gzip a file
    '''
    with open(filename) as f_in, gzip.open(filename + '.gz', 'wb') as f_out:
        f_out.writelines(f_in)
    if removeOriginal:
        os.remove(filename)


def truncate(s, length):
    '''
    if string s is > length, return truncated string
    with ... added to end
    '''
    return (s[:(length - 3)] + '...') if len(s) > length else s


def xstrN(s):
    '''
    wrapper for str() that handles Nones -> 'NULL'
    '''
    if s is None:
        return 'NULL'
    else:
        return str(s)

def xstr(s):
    '''
    wrapper for str() that handles Nones
    '''
    if s is None:
        return ""
    else:
        return str(s)


def ascii_safe_str(obj):
    try: return str(obj)
    except UnicodeEncodeError:
        return obj.encode('ascii', 'ignore').decode('ascii')
    return ""


def warning(*objs, **kwargs):
    '''
    print messages to stderr
    '''
    fh = sys.stderr
    flush = False
    if kwargs:
        if 'file' in kwargs: fh = kwargs['file']
        if 'flush' in kwargs: flush = kwargs['flush']

    print('[' + str(datetime.datetime.now()) + ']\t', *objs, file=fh)
    if flush:
        fh.flush()


def qw(s, returnTuple=False):
    '''
    mimics perl's qw function
    usage: qw('a b c') will yield ['a','b','c']
    returnTuple: return a tuple if true, otherwise return list
    '''
    if returnTuple:
        return tuple(s.split())
    else:
        return s.split()


def create_dir(dirName):
    '''
    check if directory exists in the path, if not create
    '''
    try:
        os.stat(dirName)
    except OSError:
        os.mkdir(dirName)

    return dirName


def verify_path(fileName, isDir=False):
    '''
    verify that a file exists
    if isDir is True, just verifies that the path
    exists
    '''
    if isDir:
        return os.path.exists(fileName)
    else:
        return os.path.isfile(fileName)
        

def die(message):
    '''
    mimics Perl's die function
    '''
    warning(message)
    sys.exit(1)

