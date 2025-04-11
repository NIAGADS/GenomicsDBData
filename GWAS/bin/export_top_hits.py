#!/usr/bin/env python3 
#pylint: disable=invalid-name

""" 
Patch Results.VariantGWAS
* add values in new chromosome / pos fields
* delete variants not found in annotatedvdb.variants after its patch
"""

import argparse
import os.path as path
from concurrent.futures import ProcessPoolExecutor, as_completed

from niagads.utils.string import xstr
from niagads.utils.sys import warning, die
from niagads.db.postgres import Database

SQL="""
SELECT chromosome, position, metaseq_id as variant_id, ref_snp_id, 
split_part(metaseq_id,':', 3) AS ref, 
split_part(metaseq_id, ':', 4) AS alt, 
test_allele,
pvalue_display,
frequency AS test_allele_frequency,
restricted_stats->>'beta' AS beta,
COALESCE(restricted_stats->>'std_err', restricted_stats->>'beta_std_err') AS std_err,
restricted_stats->>'odds_ratio' AS odds_ratio,
restricted_stats->>'effect' AS effect,
restricted_stats->>'direction' AS direction,
s.source_id AS accession,
CASE WHEN s.source_id LIKE 'NG%' THEN 'NIAGADS DSS' ELSE 'NGHRI_GWAS_CATALOG' END AS track_data_source,
r.track AS track_id,
split_part(s.attribution, '|', 1) AS study,
split_part(s.attribution, '|', 2) AS publication,
c.characteristic AS phenotypes
FROM NIAGADS.VariantGWASTopHits r,
Study.ProtocolAppNode pan, Study.Study s, Study.StudyLink sl,
NIAGADS.ProtocolAppNodeCharacteristic c
WHERE r.track NOT IN ('NHGRI_GWAS_CATALOG', 'ADVP')
AND r.neg_log10_pvalue >=  (-1 * log(10, 5e-8))
AND pan.source_id = r.track
AND pan.protocol_app_node_id = sl.protocol_app_node_id
AND sl.study_id = s.study_id
AND c.track = r.track
AND c.characteristic_type = 'full_info_string'
ORDER BY bin_index, position, ref, alt
"""

db = Database() # will get gusConfigFile from environment
db.connect()

# FIXME: temporarily weed out lifted over long-indels in _GRCh8_ tracks 

count = 0
with db.cursor() as cursor:
    warning("Fetching Top Hits")
    cursor.execute(SQL)
    fields = [desc[0] for desc in cursor.description]
    
    print('\t'.join(fields))
    for row in cursor.fetchall():
        ref = row[4]
        alt = row[5]
        track = row[16]
        if (len(ref) >= 50 or len(alt) > 50 and '_GRCh38_' in track):
            next
        else:
            print('\t'.join([xstr(value, nullStr='NA') for value in row]))
        count = count + 1
        if count % 1000 == 0:
            warning(f'Retrieved {count} records.')

db.close()