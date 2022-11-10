#!/usr/bin/env python3
''' patch old schema/data to match new schema and standards:
    1. replace record primary keys
    2. generate gwas_flags and update annotatedvdb.variant accordingly
'''

from __future__ import print_function
from __future__ import with_statement
import argparse # parse command line args
import json
from sys import stdout, exit, exc_info
from os import environ, path
from math import isnan

from GenomicsDBData.Util.postgres_dbi import Database
from GenomicsDBData.Util.utils import warning, die

VARIANT_MAP = {}

UPDATE_FLAGS_SQL = """
    UPDATE AnnotatedVDB.Variant
    SET gwas_flags = COALESCE(gwas_flags || %s::jsonb, %s::jsonb)
    WHERE record_primary_key = %s
"""

PROTOCOL_SQL = """
    SELECT protocol_app_node_id, source_id FROM Study.ProtocolAppNode WHERE source_id LIKE 'NG0%'
"""

ESTIMATE_UPDATES_SQL= "SELECT * FROM Results.VariantGwas WHERE protocol_app_node_id ="

SELECT_SQL = """
    SELECT variant_record_primary_key, neg_log10_pvalue, pvalue_display
    FROM Results.VariantGWAS 
    WHERE protocol_app_node_id = %s
"""

UPDATE_PK_SQL = """
    UPDATE Results.VariantGWAS
    SET variant_record_primary_key = %s
    WHERE variant_record_primary_key = %s
"""

VALIDATE_PK_SQL = """
    SELECT record_primary_key FROM AnnotatedVDB.Variant 
    WHERE record_primary_key = %s
"""

FIND_PK_BY_METASEQ_SQL = """
    SELECT record_primary_key FROM AnnotatedVDB.Variant
    WHERE left(metaseq_id, 50) = left(%s, 50)
"""

FIND_PK_SQL = "SELECT find_variant_primary_key(%s)"

def get_protocol_listing():
    protocols = {}
    with database.cursor("RealDictCursor") as cursor:
        cursor.execute(PROTOCOL_SQL)
        for row in cursor:
            protocols[row['source_id']] = row['protocol_app_node_id']
    return protocols


def is_valid_pk(primaryKey):
    ''' validate primary key off the database '''
    with database.cursor() as cursor:
        cursor.execute(VALIDATE_PK_SQL, (primaryKey, ))
        result = cursor.fetchone()
        if args.debug: 
            warning("DEBUG:", "is_valid", result[0], "-", result is not None)
        return result is not None


def find_indel_pk(primaryKey):
    ''' lookup via metaseq'''
    with database.cursor() as cursor:
        cursor.execute(FIND_PK_BY_METASEQ_SQL, (primaryKey, ))
        if cursor.rowcount > 1:
            warning("WARNING: Multple matches for long INDEL:", primaryKey, "-", cursor.fetchall())
            return None
        else: 
            result = cursor.fetchone()[0] 
            warning("INFO:", "Found long INDEL -", primaryKey, "->", result)
            return result


def submit_pk_update(newPk, oldPk):
    ''' do the update '''
    global variantCountStepwise
    global variantCountTotal
    global skipCount

    with database.cursor() as cursor:
        cursor.execute(UPDATE_PK_SQL, (newPk, oldPk))

        variantCountStepwise = variantCountStepwise + cursor.rowcount
        variantCountTotal = variantCountTotal + cursor.rowcount

        if variantCountStepwise >= args.commitAfter:
            if args.commit:
                database.commit()
                warning("COMMITED:", variantCountTotal, "variant updates")
                variantCountStepwise = 0
            else:
                database.rollback()
                warning("ROLLING BACK:", variantCountTotal, "variant updates")
                variantCountStepwise = 0
            warning("SKIPPED:", skipCount, "variants")

        if args.verbose:
           warning("INFO:", "Updated", cursor.rowcount, "rows with PK = ", newPk)


def update_pk(oldPk):
    ''' update the primary key '''
    global skipCount
    # already updated
    if oldPk in VARIANT_MAP:
        skipCount = skipCount + 1
        return VARIANT_MAP[oldPk] 

    if oldPk.count(':') == 4: # chr:pos:ref:alt:rsId
        VARIANT_MAP[oldPk] = oldPk 
        skipCount = skipCount + 1
        return oldPk

    if '_' not in oldPk and len(oldPk) < 20: # no rsId, but not a long indel
        VARIANT_MAP[oldPk] = oldPk
        skipCount = skipCount + 1
        return oldPk

    newPk = oldPk.replace('_', ':')   # naive approach, substitute '_' for ':'
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


def estimate_patch_size(protocolAppNodeId):
    ''' estimate patch size '''

    sql = ESTIMATE_UPDATES_SQL + str(protocolAppNodeId)
    sql = "SELECT estimate_result_size('" + sql + "')"
    with database.cursor() as cursor:
        cursor.execute(sql)
        return cursor.fetchone()[0]


def update_gwas_flags(datasetId, primaryKey, row):
    ''' update the gwas flags '''
    global flagCount
    gwasFlags = build_gwas_flags(datasetId, row)
    if args.debug:
        warning("DEBUG:", "Flags = ", gwasFlags, "- pvalue =", row['pvalue_display'])
    if gwasFlags is not None:
        with database.cursor() as cursor:
            cursor.execute(UPDATE_FLAGS_SQL, (gwasFlags, gwasFlags, primaryKey))
        flagCount = flagCount + 1


def build_gwas_flags(datasetId, row):
    ''' build the flag '''

    try:
        if datasetId == 'NHGRI_GWAS_CATALOG':
            return None
        if float(row['neg_log10_pvalue']) == 0.0:
            return None
        if float(row['neg_log10_pvalue']) == 1.0:
            return None
        if isnan(float(row['pvalue_display'])):
            return None
        if isnan(float(row['neg_log10_pvalue'])):
            return None
        if float(row['pvalue_display']) > 0.001:
            return None
        if float(row['neg_log10_pvalue']) == 0.0:
            return None
        else:
            return json.dumps({datasetId: {
                                'p_value': row['pvalue_display'],
                                'is_gws': True if float(row['neg_log10_pvalue']) >= 7.301029996 else False
                                }
                    })
    except ValueError:
         warning("ERROR :" "Failed to extract gwas_flags from row:", row)
         warning("ERROR", exc_info()[0])
         database.rollback()
         raise


def run_patch(datasetId, protocolAppNodeId):
    ''' run the patch '''
    global skipCount
    global flagCount
    global variantCountStepwise
    global variantCountTotal

    warning("Patching", datasetId, "(" + str(protocolAppNodeId) + ")", "-", estimate_patch_size(protocolAppNodeId), "rows.")
    rowCount = 0
    with database.named_cursor('select_' + datasetId, cursorFactory="RealDictCursor") as cursor:
        cursor.itersize = 50000
        cursor.execute(SELECT_SQL, (protocolAppNodeId, ))
        warning("INFO: Starting Update")
        rowCount = 0
        for row in cursor:
            newPk = update_pk(row['variant_record_primary_key']) 
            if args.debug:
                warning("DEBUG:", "mapped", row['variant_record_primary_key'], "->", newPk)
            if newPk is not None:
                update_gwas_flags(datasetId, newPk, row)
                if flagCount % args.commitAfter == 0 and flagCount != 0:
                    if args.commit:
                        database.commit()
                        warning("COMMITED:", flagCount, "gwas_flag updates")
                    else:
                        database.rollback()
                        warning("ROLLING BACK:", flagCount, "gwas_flag updates")
            rowCount = rowCount + 1
            if rowCount % 500000 == 0:
                warning("INFO:", "Parsed", rowCount, "rows")

        # residuals
        if args.commit:
            database.commit()
            warning("COMMITED:", flagCount, "gwas_flag updates")
            warning("COMMITED:", variantCountTotal, "variant updates")
        else:
            database.rollback()
            warning("ROLLING BACK:", flagCount, "gwas_flag updates")   
            warning("ROLLING BACK:", variantCountTotal, "variant updates") 

    warning("SKIPPED:", skipCount, "variants")
    warning("INFO:", "Parsed", rowCount, "rows")
    warning("DONE", datasetId)

    skipCount = 0
    variantCountStepwise = 0
    variantCountTotal = 0
    flagCount = 0
    

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="patch old GRCh37 Results.VariantGWAS", allow_abbrev=False)
    parser.add_argument('--gusConfigFile',
                        help="GUS config file. If not provided, assumes default: $GUS_HOME/conf/gus.config")
    parser.add_argument('--commit', action='store_true')
    parser.add_argument('--dataset')
    parser.add_argument('--debug', action='store_true')
    parser.add_argument('--verbose', action='store_true')
    parser.add_argument('--commitAfter', default=5000, type=int)
    parser.add_argument('--skip')

    args =  parser.parse_args()
    
    database = Database(args.gusConfigFile)
    database.connect()

    skip = args.skip.split(',') if args.skip else ['none']

    protocols = get_protocol_listing()
    skipCount = 0
    variantCountStepwise = 0
    variantCountTotal = 0
    flagCount = 0
    for pId in protocols:
        if pId == args.dataset or args.dataset == 'all':
            if pId not in skip:
                run_patch(pId, protocols[pId])
            else:
                warning("INFO:", "Skipping Dataset", pId)

    database.close()