#!/usr/bin/env python3
''' patch old schema/data to match new schema and standards:
    1. replace record primary keys
    2. generate gwas_flags and update annotatedvdb.variant accordingly
'''

from __future__ import print_function
from __future__ import with_statement
import argparse # parse command line args
import json
from sys import stdout, exit
from os import environ, path

from GenomicsDBData.Util.postgres_dbi import Database
from GenomicsDBData.Util.utils import warning, die

VARIANT_MAP = {}

UPDATE_FLAGS_SQL = """
    UPDATE AnnotatedVDB.Variant
    SET gwas_flags = COALESCE(gwas_flags || %s::jsonb, %s::jsonb)
    WHERE record_primary_key = %s)
"""

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

UPDATE_PK_SQL = """
    UPDATE Results.VariantGWAS
    SET variant_primary_key = %s
    WHERE variant_primary_key = %s
"""

VALIDATE_PK_SQL = """
    SELECT variant_primary_key FROM AnnotatedVDB.Variant 
    WHERE variant_primary_key = %s
"""

FIND_PK_BY_METASEQ_SQL = """
    SELECT variant_primary_key FROM AnnotatedVDB.Variant
    WHERE left(metaseq_id, 50) = left(%s, 50)
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
    with database.cursor() as cursor:
        cursor.execute(VALIDATE_PK_SQL, (primaryKey))
        result = cursor.fetchone()
        return result is not None


def find_indel_pk(primaryKey):
    ''' lookup via metaseq'''
    with database.cursor() as cursor:
        cursor.execute(FIND_PK_BY_METASEQ_SQL, (primaryKey))
        if cursor.rowcount > 1:
            warning("WARNING: Multple matches for long indel:", primaryKey, "-", cursor.fetchall())
            return None
        else: 
            return cursor.fetchone()[0] 


def submit_pk_update(newPk, oldPk):
    ''' do the update '''
    with database.cursor() as cursor:
        cursor.execute(UPDATE_PK_SQL, (newPk, oldPk))
        warning("Updated", cursor.rowcount, "rows with PK = ", newPk)


def update_pk(oldPk):
    ''' update the primary key '''
   
    if oldPk in VARIANT_MAP:
        return VARIANT_MAP[oldPk] 

    newPk = oldPk.replace('_', ':')   # naive approache, substitute '_' for ':'
    if is_valid_pk(newPk):
        VARIANT_MAP[oldPk] = newPk  
        if newPk != oldPk: 
            submit_pk_update(newPk, oldPk)
        return newPk
    else: # long indel
        newPk = find_indel_pk(oldPk)
        if newPk is not None:
            submit_pk_update(newPk, oldPk)
        return newPk


def estimate_patch_size(datasetId):
    ''' estimate patch size '''

    sql = SELECT_SQL + "''" + datasetId + "''"
    sql = "SELECT estimate_result_size('" + sql + "')"
    with database.cursor() as cursor:
        cursor.execute(sql)
        return cursor.fetchone()[0]

def update_gwas_flags(datasetId, primaryKey, row):
    ''' update the gwas flags '''
    gwasFlags = build_gwas_flags(datasetId, row)
    if gwasFlags is not None:
        with database.cursor() as cursor:
            cursor.execute(UPDATE_FLAGS_SQL, (gwasFlags, gwasFlags, primaryKey))


def build_gwas_flags(datasetId, row):
    ''' build the flag '''
    flags = {}
    if row['pvalue_display'] > 0.001:
        return None
    else:
        return json.dumps({datasetId: {
                            'p_value': row['pvalue_display'],
                            'is_gwas': True if row['neg_log10_pvalue'] >= 7.301029996 else False
                            }
                })



def run_patch(datasetId):
    ''' run the patch '''
    warning("Patching", datasetId, "-", estimate_patch_size(datasetId), "rows.")
    rowCount = 0
    with database.cursor("RealDictCursor") as cursor:
        cursor.execute(PROTOCOL_SQL + "'" + datasetId + "'")
        for row in cursor:
            newPk = update_pk(row['variant_record_primary_key']) 
            if newPk is not None:
                update_gwas_flags(datasetId, newPk, row)

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
    parser.add_argument('--dataset')

    args =  parser.parse_args()
    
    database = Database(args.gusConfigFile)
    database.connect()

    protocols = get_protocol_listing()
    for pId in protocols:
        if pId == dataset or dataset == 'all':
            run_patch(pId)

    database.close()