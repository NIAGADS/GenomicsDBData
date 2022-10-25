#!/usr/bin/env python3
''' patch old schema/data to match new schema and standards:
    1. replace record primary keys
    2. generate gwas_flags and update annotatedvdb.variant accordingly
'''

from __future__ import print_function
from __future__ import with_statement
import argparse # parse command line args

from sys import stdout, exit
from os import environ, path

from GenomicsDBData.Util.postgres_dbi import Database
from GenomicsDBData.Util.utils import warning, die

VARIANT_MAP = {}

PROTOCOL_SQL = """
    SELECT protocol_app_node_id, source_id FROM Study.ProtocolAppNode WHERE source_id LIKE 'NG0%'
"""

SELECT_SQL = """
    SELECT pan.source_id, variant_record_primary_key, neg_log10_pvalue, pvalue_display
    FROM Results.VariantGWAS r,
    Study.ProtocolAppNode pan
    WHERE pan.protocol_app_node_id = r.protocol_app_node_id
    AND pan.source_id = 
"""

VALIDATE_PK_SQL = """SELECT variant_primary_key FROM AnnotatedVDB.Variant 
    WHERE variant_primary_key = %s
"""

FIND_PK_SQL = "SELECT find_variant_primary_key(%s)"

def get_protocol_listing():
    protocols = []
    with database.cursor("RealDictCursor") as cursor:
        cursor.execute(PROTOCOL_SQL)
        for row in cursor:
            protocols.append(row['source_id'])
    return protocols


def is_valid_pk(primaryKey):
    ''' validate primary key off the database '''
    with database.cursor() as cursor():
        cursor.execute(VALIDATE_PK_SQL, (primaryKey))
        result = cursor.fetchone()
        return result is not None

def update_pk(oldPk):
    ''' update the primary key '''
    # naive approache, substitute '_' for ':'
    newPk = oldPk.replace('_', ':')
    if not is_valid_pk(newPk):
        1

    # update

def estimate_patch_size(sourceId):
    ''' estimate patch size '''

    sql = SELECT_SQL + "''" + sourceId + "''"
    sql = "SELECT estimate_result_size('" + sql + "')"
    with database.cursor() as cursor:
        cursor.execute(sql)
        return cursor.fetchone()[0]


def run_patch(sourceId):
    ''' run the patch '''
    warning("Patching", sourceId, "-", estimate_patch_size(sourceId), "rows.")
    rowCount = 0
    with database.cursor("RealDictCursor") as cursor:
        cursor.execute(PROTOCOL_SQL + "'" + sourceId + "'")
        for row in cursor:
            update_pk(row['variant_record_primary_key']) 
            update_gwas_flags(sourceId, row)
            rowCount += 1
            if rowCount % 50000 == 0:
                if args.commit:
                    database.commit()
                    warning("COMMITED:", rowCount)
                else:
                    database.rollback()
                    warning("ROLLING BACK:", rowCount)
        # residuals
        if args.commit:
            database.commit()
            warning("COMMITED:", rowCount)
        else:
            database.rollback()
            warning("ROLLING BACK:", rowCount)    


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="patch old GRCh37 Results.VariantGWAS")
    parser.add_argument('--gusConfigFile',
                        help="GUS config file. If not provided, assumes default: $GUS_HOME/conf/gus.config")
    parser.add_argument('--commit', action='store_true')
    args =  parser.parse_args()
    
    database = Database(args.gusConfigFile)
    database.connect()

    protocols = get_protocol_listing()
    for pId in protocols:
        run_patch(pId)

    database.close()