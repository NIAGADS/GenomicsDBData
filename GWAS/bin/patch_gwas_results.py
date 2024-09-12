#!/usr/bin/env python3 
#pylint: disable=invalid-name

""" 
Patch Results.VariantGWAS
* add values in new chromosome / pos fields
* delete variants not found in annotatedvdb.variants after its patch
"""

import argparse
import os.path as path
from random import shuffle

from concurrent.futures import ProcessPoolExecutor, as_completed

from niagads.utils.string import xstr
from niagads.utils.sys import warning, die
from niagads.db.postgres import Database


PAN_SELECT_SQL = "SELECT DISTINCT protocol_app_node_id::int FROM Results.VariantGWAS"
RESULT_SELECT_SQL = "SELECT variant_record_primary_key, chromosome, position FROM Results.VariantGWAS WHERE protocol_app_node_id = %s"
VALID_PK_SQL = "SELECT chromosome, position FROM AnnotatedVDB.Variant WHERE record_primary_key = %s"

# including pan_id here so can do parallel
DELETE_SQL = "DELETE FROM Results.VariantGWAS WHERE variant_record_primary_key = %s"
UPDATE_SQL = "UPDATE Results.VariantGWAS SET chromosome = %s, position = %s WHERE variant_record_primary_key = %s"

ITERATION_SIZE = 500000

def commit(count: int, db: Database, lfh):
    if args.commit:
        db.commit()
        warning("COMMIT: " + xstr(count), file=lfh, flush=True)
    else:
        db.rollback()
        warning("ROLLBACK: " + xstr(count), file=lfh, flush=True)
            
def patch_table(panId: int):
    # get variant ids for the protocol app node
    # fetch chr, pos
        # update chr, pos if found, 
        # else remove add to list of invalid variant ids (deleting while selecting will cause a lock)
    # delete invalid variants
    logFileName = path.join(args.logFilePath, xstr(panId) + ".log")
    cname = 'variants_' + xstr(panId)
    modificationCount = 0
    recordCount = 0
    updates = []
    
    warning("Processing " + xstr(panId) + "; logging to: " + logFileName)

    try:
        dbSelect = Database(args.gusConfigFile) # otherwise named cursor is lost on commit
        dbSelect.connect()
        db = Database(args.gusConfigFile)
        db.connect()
        with open(logFileName, 'w') as lfh, \
            dbSelect.named_cursor(cname, cursorFactory="RealDictCursor") as selectCursor, \
            db.cursor(cursorFactory="RealDictCursor") as validCursor, \
            db.cursor() as deleteCursor:
                
            warning("Reviewing variants from: " + xstr(panId), file=lfh, flush=True)
            selectCursor.itersize = ITERATION_SIZE 
            selectCursor.execute(RESULT_SELECT_SQL, [panId])
            for record in selectCursor:
                recordCount = recordCount + 1
                vpk = record['variant_record_primary_key']
                if 'I' in vpk or 'R' in vpk or 'D' in vpk or 'N' in vpk or '?' in vpk:
                    validCursor.execute(VALID_PK_SQL, [vpk])
                    lookup = validCursor.fetchone()
                    if lookup is None:
                        updates.append([vpk])             
                if recordCount % 100000 == 0:
                    warning("PROCESSED: " + xstr(recordCount) + " variants.", file=lfh, flush=True)

            nUpdates = len(updates)
            if nUpdates > 0:
                deleteCursor.executemany(DELETE_SQL, updates)
                warning("DELETED: " + xstr(nUpdates), file=lfh, flush=True)  
                commit(nUpdates, db, lfh)
                
            warning("PROCESSED: " + xstr(recordCount) + " variants.", file=lfh, flush=True)
            warning("DONE", file=lfh, flush=True)
            
    finally:
        db.close()
        dbSelect.close()

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="one-off-patch of Results.VariantGWAS to remove problematic varians removed from AnnotatedVDB.Variant", allow_abbrev=False)
    parser.add_argument('--maxWorkers', type=int, default=5)
    parser.add_argument('--debug', action='store_true')
    parser.add_argument('--verbose', action='store_true')
    parser.add_argument('--commit', action='store_true')
    parser.add_argument('--commitAfter', type=int, default=500)
    parser.add_argument('--test', action='store_true')
    parser.add_argument('--veryVerbose', action='store_true')
    parser.add_argument('--logFilePath', required=True)
    parser.add_argument('--panId')
    parser.add_argument('--gusConfigFile',
                        help="GUS config file. If not provided, assumes default: $GUS_HOME/conf/gus.config")
    args = parser.parse_args()
    
    panIds = None
    if args.panId:
        panIds = args.panId.split(',')
    else:
        try:
            database = Database(args.gusConfigFile)
            panIds = None
            database.connect()
            with database.cursor() as cursor:
                warning("Fetching Dataset Protocol App Node IDs")
                cursor.execute(PAN_SELECT_SQL)
                panIds = [r[0] for r in cursor.fetchall()]

            database.close()

            
        finally:
            database.close()
    
    warning("Processing " + xstr(len(panIds)) + " distinct datasets")
    panIds.sort()
    warning(panIds)  
    
    shuffle(panIds)
    
    for pid in panIds:
        patch_table(pid)

    """
    with ProcessPoolExecutor(args.maxWorkers) as executor:
        futureUpdate = {executor.submit(patch_table, panId=pid) : pid for pid in panIds}
        for future in as_completed(futureUpdate): # this should allow catching errors 
            try:
                future.result()
            except Exception as err:
                raise(err)       
    """


