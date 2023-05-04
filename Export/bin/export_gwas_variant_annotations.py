#!/usr/bin/env python3
""" export annotations for variants linked to summary statistics for AI/ML gold standard"""

import argparse
import os

from GenomicsDBData.Util.utils import warning, create_dir, print_dict, execute_cmd, die
from GenomicsDBData.Util.list_utils import qw
from GenomicsDBData.Util.postgres_dbi import Database

SQL = """WITH Variants AS (
SELECT DISTINCT variant_record_primary_key AS pk
FROM Results.VariantGWAS)
SELECT v.pk,
d.details->>'chromosome' AS "CHR",
CASE WHEN d.details->>'ref_snp_id' IS NOT NULL THEN d.details->>'ref_snp_id' ELSE d.details->>'metaseq_id' END AS "Variant_ID",
(d.details->>'position')::int AS "BP",
split_part(d.details->>'metaseq_id', ':', 3) AS "Ref_allele",
split_part(d.details->>'metaseq_id', ':', 4) AS "Alt_allele",
d.details->'most_severe_consequence'->>'impacted_gene_symbol' AS "Gene",
d.details->'most_severe_consequence'->>'conseq' AS "Most_damaging_consequence",
d.details->'most_severe_consequence'->>'impact' AS "Impact",
(d.details->'cadd'->>'CADD_phred')::numeric AS "CADD",
CASE WHEN (d.details->>'is_adsp_variant')::boolean THEN 'ADSP_17K_R3' ELSE NULL END AS "ADSP_Release"
FROM Variants v, get_variant_display_details(v.pk) d
WHERE d.details->'most_severe_consequence'->>'conseq' IS NOT NULL OR d.details->'cadd'->>'CADD_phred' IS NOT NULL
"""

FIELDS = qw('CHR Variant_ID BP Ref_allele Alt_allele Gene Most_damaging_consequence Impact CADD ADSP_Release')
    
if __name__ == "__main__":

    parser = argparse.ArgumentParser()
    parser.add_argument('-l', '--limit', help='limit number of rows to return for test')
    parser.add_argument('-o', '--outputPath', help='outputPath', required=True)
 
    args = parser.parse_args()
    
    database = Database(None)
    database.connect()
    
    fileName = os.path.join(args.outputPath, "variant_annotations.txt")
    rCount = 0
    with open(fileName, 'w') as fh, \
        database.named_cursor('annotation-select', cursorFactory="RealDictCursor") as cursor:
        cursor.itersize = 500000  
        print("\t".join(FIELDS), file=fh)
        
        warning("Fetching annotations for DISTINCT variants in Results.VariantGWAS and writing to", fileName)
        cursor.execute(SQL + " LIMIT " + args.limit if args.limit else SQL)
        for record in cursor:
            print("\t".join([record[field] for field in FIELDS]), file=fh)
            rCount = rCount + 1
            if (rCount % 50000 == 0):
                warning("Processed", rCount)

        warning("Sorting", fileName)      
        cmd = "(head -n 1 " + fileName + " && tail -n +2 " + fileName  \
            + " | sort -T " + outputPath + " -V -k1,1 -k2,2) > " + fileName + ".sorted"          
        execute_cmd([cmd], shell=True)

        warning("Compressing sorted", fileName)
        execute_cmd(["bgzip", fileName + ".sorted"])
        execute_cmd(["mv", fileName + ".sorted.gz", fileName + ".gz"])
        
        warning("Indexing", fileName)
        execute_cmd(["tabix", "-S", "1", "-s", "1", "-e", "3", "-b", "3", "-f", fileName + ".gz"])

        warning("Cleaning up (removing temp files)")
        execute_cmd(["rm", fileName])