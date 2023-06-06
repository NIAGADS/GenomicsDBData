#!/usr/bin/env python3
""" export annotations for variants linked to summary statistics for AI/ML gold standard"""

import argparse
import os
import json

from GenomicsDBData.Util.utils import warning, create_dir, print_dict, execute_cmd, die, xstr
from GenomicsDBData.Util.list_utils import qw
from GenomicsDBData.Util.postgres_dbi import Database

FIELDS = qw('chromosome position ref_allele alt_allele variant_id gene_symbol gene_id most_damaging_consequence impact CADD_score ADSP_release GWAS_hits')

TOP_HITS_SQL = """SELECT  variant_record_primary_key,
json_agg(jsonb_build_object(track, jsonb_build_object('pvalue', pvalue_display, 'test_allele', test_allele))) AS hits
FROM NIAGADS.VariantGWASTopHits 
WHERE track != 'NHGRI_GWAS_CATALOG'
GROUP BY variant_record_primary_key
"""

ALL_VARIANTS_SQL = """WITH Variants AS (
SELECT DISTINCT variant_record_primary_key AS pk
FROM Results.VariantGWAS)
SELECT v.pk,
d.details->>'chromosome' AS chromosome,
CASE WHEN d.details->>'ref_snp_id' IS NOT NULL THEN d.details->>'ref_snp_id' ELSE d.details->>'metaseq_id' END AS variant_id,
(d.details->>'position')::int AS position,
split_part(d.details->>'metaseq_id', ':', 3) AS ref_allele,
split_part(d.details->>'metaseq_id', ':', 4) AS alt_allele,
d.details->'most_severe_consequence'->>'impacted_gene_symbol' AS gene_symbol,
d.details->'most_severe_consequence'->>'impacted_gene' AS gene_id,
d.details->'most_severe_consequence'->>'conseq' most_damaging_consequence,
d.details->'most_severe_consequence'->>'impact' AS impact,
(d.details->'cadd'->>'CADD_phred')::numeric AS cadd_score,
CASE WHEN (d.details->>'is_adsp_variant')::boolean THEN 'ADSP_17K_R3' ELSE NULL END AS adsp_release
FROM Variants v, get_variant_display_details(v.pk) d
WHERE d.details->'most_severe_consequence'->>'conseq' IS NOT NULL OR d.details->'cadd'->>'CADD_phred' IS NOT NULL
"""

def get_top_hits():
    ''' fetch top hits and return dict '''
    warning("Fetching top hits in Results.VariantGWAS from materialized view")
    hits = {}
    with database.cursor(cursorFactory="RealDictCursor") as cursor:
        cursor.execute(TOP_HITS_SQL)
        for record in cursor:
            hits[record['variant_record_primary_key']] = json.dumps(record['hits'])
            
    return hits

        
if __name__ == "__main__":

    parser = argparse.ArgumentParser()
    parser.add_argument('-l', '--limit', help='limit number of rows to return for test')
    parser.add_argument('-o', '--outputPath', help='outputPath', required=True)
    parser.add_argument('--compressOnly', action='store_true')
 
    args = parser.parse_args()
        
    fileName = os.path.join(args.outputPath, "variant_annotations.txt")
    if not args.compressOnly:
        database = Database(None)
        database.connect()
        
        gwasHits = get_top_hits()

        rCount = 0
        with open(fileName, 'w') as fh, \
            database.named_cursor('annotation-select', cursorFactory="RealDictCursor") as cursor:
            cursor.itersize = 1000 
            print("\t".join(FIELDS), file=fh, flush=True)
            
            warning("Fetching annotations for DISTINCT variants in Results.VariantGWAS and writing to", fileName)
            cursor.execute(ALL_VARIANTS_SQL + " LIMIT " + args.limit if args.limit else ALL_VARIANTS_SQL)
            for record in cursor:
                buffer = [xstr(record[field.lower()], nullStr="NA") for field in FIELDS if field != 'GWAS_hits']
                variantPK = record['pk']
                if variantPK in gwasHits:
                    buffer.append(gwasHits[variantPK])
                else:
                    buffer.append('NA')
                    
                print("\t".join(buffer), file=fh)
                rCount = rCount + 1
                if (rCount % 10000 == 0):
                    warning("Processed", rCount)
                    
        database.close()

    warning("Sorting", fileName)      
    cmd = "(head -n 1 " + fileName + " && tail -n +2 " + fileName  \
        + " | sort -T " + args.outputPath + " -V -k1,1 -k2,2) > " + fileName + ".sorted"          
    execute_cmd([cmd], shell=True)

    warning("Compressing sorted", fileName)
    execute_cmd(["bgzip", fileName + ".sorted"])
    execute_cmd(["mv", fileName + ".sorted.gz", fileName + ".gz"])
    
    warning("Indexing", fileName)
    execute_cmd(["tabix", "-S", "1", "-s", "1", "-e", "3", "-b", "3", "-f", fileName + ".gz"])

    warning("Cleaning up (removing temp files)")
    execute_cmd(["rm", fileName])