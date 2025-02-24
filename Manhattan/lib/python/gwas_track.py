
"""
retrieve GWAS summary statistics from database and store
"""


import pandas as pd
from GenomicsDBData.Util.postgres_dbi import Database
from GenomicsDBData.Util.utils import warning
from psycopg2.errors import ConnectionDoesNotExist

TRACK_METADATA_SQL="""
WITH phenotypes AS (
SELECT track, protocol_app_node_id, characteristic_type, jsonb_agg(replace(replace(characteristic, 'late onset ', ''), 'adjusted for ', '')) as characteristic
FROM NIAGADS.ProtocolAppNodeCharacteristic
WHERE characteristic_type NOT IN ('covariate_list', 'full_list', 'phenotype_list')
GROUP BY track, protocol_app_node_id, characteristic_type),
PhenotypeJson AS (
SELECT track, protocol_app_node_id, jsonb_object_agg(characteristic_type, characteristic) AS p_json
FROM Phenotypes
GROUP BY track, protocol_app_node_id),
dataset AS (
SELECT da.accession, 
da.name, da.description, 
split_part(da.attribution, '|', 1) AS attribution, 
split_part(da.attribution, '|', 2) AS primary_publication
FROM NIAGADS.DatasetAttributes da),
TrackDetails AS (
SELECT ta.dataset_accession AS niagads_accn,
ta.track, 
ta.name, 
ta.description
FROM NIAGADS.TrackAttributes ta)
SELECT 
row_to_json(da)::jsonb 
|| jsonb_build_object('tracks', jsonb_object_agg(td.track, row_to_json(td)::jsonb 
|| COALESCE(pan.track_summary, '{}'::jsonb) 
|| p.p_json)) AS track_metadata
FROM TrackDetails td, Study.ProtocolAppNode pan, PhenotypeJson p, dataset da
WHERE pan.protocol_app_node_id = p.protocol_app_node_id
AND td.track = p.track
AND da.accession = td.niagads_accn
AND da.accession = %(accession)s
GROUP BY da.*;
"""

PUBLIC_SUM_STATS_SQL="""
SELECT details->>'chromosome' AS chromosome,
split_part(variant_record_primary_key, ':', 2)::int AS position,
split_part(details->>'metaseq_id', ':', 3) AS ref_allele,
split_part(details->>'metaseq_id', ':', 4) AS alt_allele,
CASE WHEN details->>'ref_snp_id' IS NOT NULL 
THEN details->>'ref_snp_id' 
ELSE details->>'metaseq_id' END AS variant_id,
r.allele AS test_allele, 
r.pvalue_display AS pvalue
FROM Results.VariantGWAS r,  get_variant_display_details(variant_record_primary_key) d,
NIAGADS.TrackAttributes ta
WHERE ta.track = %(track)s
AND ta.protocol_app_node_id = r.protocol_app_node_id
"""
# was loaded sorted, so should be OK
# ORDER BY idx(ARRAY['chr1', 'chr2', 'chr3', 'chr4', 'chr5', 'chr6', 'chr7', 'chr8',
# 'chr9', 'chr10', 'chr11', 'chr12', 'chr13', 'chr14', 'chr15', 'chr16', 'chr17', 'chr18', 'chr19',
# 'chr20', 'chr21', 'chr22', 'chrX', 'chrY', 'chrM'], details->>'chromosome')
# , position
# """

BED_FULL_SUM_STATS_SQL="""
SELECT details->>'chromosome' AS "#chrom",
(details->>'position')::int - 1 AS "chromStart",
(details->>'position')::int AS "chromEnd",
CASE WHEN details->>'ref_snp_id' IS NOT NULL 
THEN details->>'ref_snp_id' 
ELSE details->>'metaseq_id' END AS name,
r.neg_log10_pvalue AS score,
jsonb_build_object('test_allele', r.allele, 'display_p', r.pvalue_display, 'genomicsdb_id', variant_record_primary_key)::text AS info,
--(details - 'bin_index' - 'location' - 'position' - 'chromosome')::text AS annotations,
(r.restricted_stats || jsonb_build_object('test_allele_freq', r.frequency))::text AS restricted_stats
FROM Results.VariantGWAS r,  get_variant_display_details(variant_record_primary_key) d,
NIAGADS.TrackAttributes ta
WHERE ta.track = %(track)s
AND ta.protocol_app_node_id = r.protocol_app_node_id
"""

BED_PUBLIC_SUM_STATS_SQL="""
SELECT details->>'chromosome' AS "#chrom",
(details->>'position')::int - 1 AS "chromStart",
(details->>'position')::int AS "chromEnd",
CASE WHEN details->>'ref_snp_id' IS NOT NULL 
THEN details->>'ref_snp_id' 
ELSE details->>'metaseq_id' END AS name,
r.neg_log10_pvalue AS score,
jsonb_build_object('test_allele', r.allele, 
'display_p', r.pvalue_display, 'genomicsdb_id', variant_record_primary_key)::text AS info
FROM Results.VariantGWAS r,  get_variant_display_details(variant_record_primary_key) d,
NIAGADS.TrackAttributes ta
WHERE ta.track = %(track)s
AND ta.protocol_app_node_id = r.protocol_app_node_id
"""


DATA_SQL="""
SELECT variant_record_primary_key, 
details->>'metaseq_id' AS metaseq_id,
details->'most_severe_consequence'->>'impacted_gene_symbol' AS "GENE",
replace(details->>'chromosome', 'chr', '') AS "CHR",
(details->'position')::int AS "BP",
CASE WHEN details->>'ref_snp_id' IS NOT NULL THEN details->>'ref_snp_id' ELSE details->>'display_id' END AS "SNP",
to_char(r.neg_log10_pvalue, '999D999')::float AS neg_log10_pvalue,
r.pvalue_display AS "P",
CASE WHEN r.neg_log10_pvalue > -1 * log('5e-8') THEN 2 -- gws
WHEN r.neg_log10_pvalue > 5 THEN 1 -- relaxed
ELSE 0 END  -- nope
AS genome_wide_significance_level
FROM Results.VariantGWAS r,  
get_variant_display_details(variant_record_primary_key) details,
NIAGADS.TrackAttributes ta
WHERE ta.track = %(track)s
AND ta.protocol_app_node_id = r.protocol_app_node_id
AND neg_log10_pvalue > -1 * log(0.5)
AND details.record_primary_key = r.variant_record_primary_key
"""

GENE_SQL='''
SELECT hit, hit_type, hit_display_value,
replace(chromosome, 'chr', '') as chromosome, 
location_start, location_end,
neg_log10_pvalue AS peak_height, 
CASE WHEN neg_log10_pvalue >= -1 * log('5e-8') THEN 1 ELSE 0 END AS is_significant,
ld_reference_variant AS variant, rank
FROM NIAGADS.DatasetTopFeatures 
WHERE track = %(track)s
AND hit_type = 'gene'
AND CASE WHEN hit_type = 'gene' AND gene_type = 'protein coding' 
THEN TRUE WHEN hit_type = 'variant' THEN TRUE ELSE FALSE END
ORDER BY rank
'''

TITLE_SQL='''SELECT name, attribution FROM Study.ProtocolAppNode where source_id = %(track)s'''

LIST_TRACKS_SQL="""SELECT track, name from NIAGADS.TrackAttributes WHERE subcategory = 'GWAS summary statistics"""


class GWASTrack(object):
    '''
    accessor for database connection info
    + database handler
    '''
    def __init__(self, track):
        self._database = None # database handler (connection)
        self._track = track
        self._data = None
        self._gene_annotation = None
        self._restricted_stats = [] # restricted stats to be retrieved
        self._limit = None
        self._name = None
        self._attribution = None
        self._cap = None
        self._metadata_json = None


    def connect(self, gusConfigFile=None):
        self._database = Database(gusConfigFile)
        self._database.connect()
        
    def set_cap(self, cap):
        self._cap = cap


    def get_cap(self):
        return self._cap
        

    def get_gene_annotation(self):
        return self._gene_annotation
    
    
    def get_metadata(self):
        return self._metadata_json
    
        
    def get_limit(self):
        return self._limit


    def set_limit(self, limit):
        self._limit = limit
        
    def get_track(self):
        ''' return track'''
        return self._track
    

    def get_data(self):
        '''return data'''
        return self._data


    def get_database(self):
        return self._database
    
    
    def set_track(self, track):
        self._track = track
        

    def set_data(self, data):
        self._data = data


    def get_title(self):
        return self._track + ': ' + self._name + ' (' + self._attribution + ')'


    def list_available_tracks(self):
        if self._database is None:
            raise ConnectionDoesNotExist("gwas_track object database connection not initialized")
        
        with self._database.cursor(cursorFactory='RealDictCursor') as cursor:
            cursor.execute(LIST_TRACKS_SQL)
            return cursor.fetchall()
            


    def fetch_title(self):
        if self._database is None:
            raise ConnectionDoesNotExist("gwas_track object database connection not initialized")

        if self._track is None:
            raise ValueError("Must set track value")

        with self._database.cursor() as cursor:
            cursor.execute(TITLE_SQL, {'track': self._track})
            self._name, self._attribution = cursor.fetchone()

        with self._database.cursor() as cursor:
            cursor.execute(TRACK_METADATA_SQL, {'accession': self._track})
            self._metadata_json = cursor.fetchone()[0]
            

    def fetch_metadata(self):
        if self._database is None:
            raise ConnectionDoesNotExist("gwas_track object database connection not initialized")

        if self._track is None:
            raise ValueError("Must set track value")

        with self._database.cursor() as cursor:
            cursor.execute(TRACK_METADATA_SQL, {'accession': self._track})
            self._metadata_json = cursor.fetchone()[0]


    def fetch_bed_sum_stats(self, inclRestricted=False):
        ''' fetch sum stats w/annotations & restricted stats in JSON objects only '''
        if self._database is None:
            raise ConnectionDoesNotExist("gwas_track object database connection not initialized")

        if self._track is None:
            raise ValueError("Must set track value")

        sql = BED_FULL_SUM_STATS_SQL if inclRestricted else BED_PUBLIC_SUM_STATS_SQL
        if self._limit is not None:
            sql = sql + " LIMIT " + self._limit
            # sql = sql.replace("Results.VariantGWAS r", "Results.VariantGWAS r TABLESAMPLE SYSTEM (0.01)")
                    
        warning("Fetching track data -- full stats only")
        self._data = pd.read_sql_query(sql, self._database, params={'track': self._track}, index_col = None)
        warning("Done", "Fetched", len(self._data), "rows")
        

    def fetch_public_sum_stats(self):
        ''' fetch pvalues only '''
        if self._database is None:
            raise ConnectionDoesNotExist("gwas_track object database connection not initialized")

        if self._track is None:
            raise ValueError("Must set track value")

        sql = PUBLIC_SUM_STATS_SQL
        if self._limit is not None:
            sql = PUBLIC_SUM_STATS_SQL + " LIMIT " + self._limit
            sql = sql.replace("Results.VariantGWAS r", "Results.VariantGWAS r TABLESAMPLE SYSTEM (0.01)")
                    
        warning("Fetching track data -- pvalues only")
        self._data = pd.read_sql_query(sql, self._database, params={'track': self._track}, index_col = None)
        warning("Done", "Fetched", len(self._data), "rows")

            
    def fetch_track_data(self):
        if self._database is None:
            raise ConnectionDoesNotExist("gwas_track object database connection not initialized")

        if self._track is None:
            raise ValueError("Must set track value")

        sql = DATA_SQL
        if self._limit is not None:
            sql = DATA_SQL + " LIMIT " + self._limit
            sql = sql.replace("Results.VariantGWAS r", "Results.VariantGWAS r TABLESAMPLE SYSTEM (0.01)")
            
        if self._cap is not None:
            sql = sql.replace('r.pvalue_display AS "P"',
                "CASE WHEN r.neg_log10_pvalue > " + str(self._cap) 
                + "THEN '1e-" + str(self._cap) 
                + "' ELSE r.pvalue_display END AS" + '"P"')
        
        warning("Fetching track data")
        self._data = pd.read_sql_query(sql, self._database, params={'track': self._track}, index_col = 'variant_record_primary_key')
        warning("Done", "Fetched", len(self._data), "rows")
        

    def fetch_gene_data(self):
        if self._database is None:
            raise ConnectionDoesNotExist("gwas_track object database connection not initialized")

        if self._track is None:
            raise ValueError("Must set track value")

        warning("Fetching gene annotation")
        self._gene_annotation = pd.read_sql_query(GENE_SQL, self._database, params={'track':self._track}, index_col = 'hit')
        warning("Done", "Fetched", len(self._gene_annotation), "rows")




