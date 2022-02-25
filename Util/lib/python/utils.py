from __future__ import print_function
from __future__ import with_statement

import sys
import os
import gzip
import datetime
import json

from types import SimpleNamespace
from collections import abc
from subprocess import check_output, CalledProcessError

def deep_update(d, u):
    """! deep update a dict
    based on https://stackoverflow.com/questions/3232943/update-value-of-a-nested-dictionary-of-varying-depth/60321833
    answer: https://stackoverflow.com/a/3233356 
    but may not handle all variations

        @param d             source dict to be updated
        @param u             overrides
        @returns             the deep updated source dict
    """
    for k, v in u.items():
        if isinstance(v, abc.Mapping):
            d[k] = deep_update(d.get(k, {}), v)
        else:
            d[k] = v
    return d


def print_args(args, pretty=True):
    ''' print argparser args '''
    return print_dict(vars(args), pretty)


def print_dict(dictObj, pretty=True):
    ''' pretty print a dict / JSON object '''
    if isinstance(dictObj, SimpleNamespace):
        return dictObj.__repr__()
    return json.dumps(dictObj, indent=4, sort_keys=True) if pretty else json.dumps(dictObj)


def get_opener(fileName=None, compressed=True, binary=True):
    ''' check if compressed files are expected and return
    appropriate opener '''

    if compressed or (fileName is not None and '.gz' in fileName):
        if binary:
            return gzip.GzipFile
        return gzip.open
    return open


def is_number(value):
    return is_integer(value) or is_float(value)


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



def convert_str2numeric_values(cdict, nanAsStr=True):
    """!  converts numeric values in dictionary stored as strings 
    to numeric

        @param cdict             dictionary to conver
        @param nanAsStr          treat NaN/nan/NAN as string?
        @returns                 the converted dictionary
    """
    for key, value in cdict.items():
        if str(value).upper() == 'NAN' and nanAsStr:
            # is_float test will be true for NaN/NAN/nan/Nan etc
            continue
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
        asciiSafeCmd = [ascii_safe_str(c) for c in cmd]
        warning("EXECUTING: ", ' '.join(asciiSafeCmd), flush=True)
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


def reverse(s):
    ''' reverse a string 
    see https://www.w3schools.com/python/python_howto_reverse_string.asp '''
    return s[::-1]
        

def truncate(s, length):
    '''
    if string s is > length, return truncated string
    with ... added to end
    '''
    return (s[:(length - 3)] + '...') if len(s) > length else s


def xstr(value, nullStr="", falseAsNull=False):
    '''
    wrapper for str() that handles Nones
    '''
    if value is None:
        return nullStr
    elif falseAsNull and isinstance(value, bool):
        if value is False:
            return nullStr
        else:
            return str(value)
    elif isinstance(value, dict):
        if bool(value):
            return print_dict(value, pretty=False)
        else:
            return nullStr
    else:
        return str(value)


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


def int_to_alpha(value, lower=False):
    ''' Convert an input integer to alphabetic representation, 
    starting with 1=A. or 1=a if lower=True'''

    if lower:
        return chr(96 + value)
    else:
        return chr(64 + value)
