
"""
retrieve GWAS summary statistics from database and store
"""


import pandas as pd
from GenomicsDBData.Util.postgres_dbi import Database
from GenomicsDBData.Util.utils import warning
from psycopg2.errors import ConnectionDoesNotExist


DATA_SQL="""SELECT r.variant_record_primary_key, 
split_part(r.variant_record_primary_key, '_', 1) AS metaseq_id,
CASE WHEN split_part(r.variant_record_primary_key, '_', 2) = '' THEN NULL 
ELSE split_part(r.variant_record_primary_key, '_', 2) END AS ref_snp_id,
CASE WHEN split_part(r.variant_record_primary_key, '_', 2) != '' THEN split_part(r.variant_record_primary_key, '_', 2) 
ELSE truncate_str(split_part(r.variant_record_primary_key, '_', 1), 27) END AS "SNP",
r.neg_log10_pvalue,
r.pvalue_display AS "P",
CASE WHEN r.neg_log10_pvalue > -1 * log('5e-8') THEN 2 -- gws
WHEN r.neg_log10_pvalue > 5 THEN 1 -- relaxed
ELSE 0 END  -- nope
AS genome_wide_significance_level,
split_part(r.variant_record_primary_key, ':',1)::text AS "CHR",
split_part(r.variant_record_primary_key, ':',2)::bigint AS "BP"
FROM NIAGADS.TrackAttributes ta,
Results.VariantGWAS r
WHERE ta.track = %(track)s
AND ta.protocol_app_node_id = r.protocol_app_node_id"""

GENE_SQL='''SELECT ga.gene_symbol, ga.source_id, ga.chromosome, ga.location_start, ga.location_end, max(r.neg_log10_pvalue) AS peak_height,
count(DISTINCT variant_record_primary_key) AS num_variants,
sum(CASE WHEN r.neg_log10_pvalue > -1 * log('5e-8') THEN 1 ELSE 0 END) AS num_sig_variants,
string_agg(DISTINCT variant_record_primary_key, ',') AS variants
FROM NIAGADS.TrackAttributes ta, CBIL.GeneAttributes ga, Results.VariantGWAS r
WHERE ta.track = %(track)s
AND r.neg_log10_pvalue > 3 -- -1 * log('5e-8')
AND ga.bin_index_5kb_flank @> r.bin_index
AND int8range(ga.location_start - 5000, ga.location_end + 5000, '[]') @> split_part(r.variant_record_primary_key, ':', 2)::bigint
AND ta.protocol_app_node_id = r.protocol_app_node_id
GROUP BY ga.gene_symbol, ga.source_id, ga.chromosome, ga.location_start, ga.location_end
ORDER BY ga.chromosome, ga.location_start, ga.location_end'''

TITLE_SQL='''SELECT name, attribution FROM Study.ProtocolAppNode where source_id = %(track)s'''


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


    def connect(self, gusConfigFile=None):
        self._database = Database(gusConfigFile)
        self._database.connect()
        
    def set_cap(self, cap):
        self._cap = cap


    def get_cap(self):
        return self._cap
        

    def get_gene_annotation(self):
        return self._gene_annotation
    
        
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


    def get_restricted_stats(self):
        raise NotImplementedError;
    

    def get_database(self):
        return self._database
    
    
    def set_strack(self, track):
        self._track = track
        

    def set_data(self, data):
        self._data = data

    
    def set_restricted_stats(self):
        raise NotImplementedError


    def get_title(self):
        return self._track + ': ' + self._name + ' (' + self._attribution + ')'



    
    def fetch_title(self):
        if self._database is None:
            raise ConnectionDoesNotExist("gwas_track object database connection not initialized")

        if self._track is None:
            raise ValueError("Must set track value")

        with self._database.cursor() as cursor:
            cursor.execute(TITLE_SQL, {'track': self._track})
            self._name, self._attribution = cursor.fetchone()

            

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
                              "CASE WHEN r.neg_log10_pvalue > " + str(self._cap) + "THEN '1e-" + str(self._cap) +"' ELSE r.pvalue_display END AS" + '"P"')
        
        warning("Fetching track data")
        self._data = pd.read_sql_query(sql, self._database, params={'track': self._track}, index_col = 'variant_record_primary_key')
        warning("Done", "Fetched", len(self._data), "rows")
        

    def fetch_gene_data(self):
        if self._database is None:
            raise ConnectionDoesNotExist("gwas_track object database connection not initialized")

        if self._track is None:
            raise ValueError("Must set track value")

        warning("Fetching gene annotation")
        self._gene_annotation = pd.read_sql_query(GENE_SQL, self._database, params={'track':self._track}, index_col = 'source_id')
        warning("Done", "Fetched", len(self._gene_annotation), "rows")



    
 
