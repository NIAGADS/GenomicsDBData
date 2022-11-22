#!/usr/bin/env python3
#!pylint: disable=invalid-name

'''
functions for handling exceptions
'''
from __future__ import print_function

import traceback
from sys import stderr


def print_exception(numLeadingLines=2, fh=stderr, qualifier=None):
    ''' print line number & reduced stack trace for error messages for custom exceptions '''
    print("ERROR at: ", end='', file=fh)
    formattedLines = traceback.format_exc().splitlines()
    for n in range(1, numLeadingLines + 1):    
        print(formattedLines[n], file=fh)
    print(formattedLines[-1], file=fh) # actual error message

    if qualifier:
        print(qualifier, file=fh)
