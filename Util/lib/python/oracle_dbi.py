#!/usr/bin/python
from __future__ import print_function
import sys
import cx_Oracle

from CBILDataCommon.Util.utils import warning

def createDbh(connectionString):
    # user@password/dsn

    tstr = connectionString.split("/")
    user, password = tstr[0].split("@")
    dsn = tstr[1]

    # warning((user, password, dsn))

    connection = cx_Oracle.connect(user, password, dsn)
   
    # test connection
    cursor = connection.cursor()
    cursor.execute("select 'OK' from dual")
    for result in cursor:
        warning("CONNECTION: ", result[0])
    cursor.close()

    return connection
