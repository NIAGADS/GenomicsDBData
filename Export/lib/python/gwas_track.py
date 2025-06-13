"""
retrieve GWAS summary statistics from database and store
"""

from os import path
from GenomicsDBData.Util.postgres_dbi import Database
from GenomicsDBData.Util.utils import warning, die, xstr
from psycopg2.errors import ConnectionDoesNotExist
import json
import pysam


TRACK_METADATA_SQL = """
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


ANNOTATED_SUM_STATS_SQL = """
SELECT details->>'chromosome' AS chromosome,
(details->>'position')::int AS position,
details->>'metaseq_id'AS variant_id,
details->>'ref_snp_id' AS ref_snp_id,
r.pvalue_display as pvalue,
r.allele AS test_allele,
round(r.neg_log10_pvalue::numeric, 6) AS neg_log10_pvalue,
details - 'cadd' - 'location' - 'position' - 'bin_index' - 'chromosome' - 'metaseq_id' - 'ref_snp_id' - 'display_id' AS annotation,
--(details - 'bin_index' - 'location' - 'position' - 'chromosome')::text AS annotations,
(r.restricted_stats || jsonb_build_object('test_allele_freq', r.frequency))::text AS restricted_stats
FROM Results.VariantGWAS r,  get_variant_display_details(variant_record_primary_key) d,
NIAGADS.TrackAttributes ta
WHERE ta.track = %(track)s
AND ta.protocol_app_node_id = r.protocol_app_node_id
"""

TITLE_SQL = """SELECT name, attribution FROM Study.ProtocolAppNode where source_id = %(track)s"""

LIST_TRACKS_SQL = """SELECT track, name from NIAGADS.TrackAttributes WHERE subcategory = 'GWAS summary statistics"""

ITERATION_SIZE = 50000  # too big and connection gets closed between iterations

class GWASTrack(object):
    """
    accessor for database connection info
    + database handler
    """

    def __init__(self, track, fastaDir=None):
        self._database = None  # database handler (connection)
        self._track = track
        self._data = None
        self._restricted_stats = []  # restricted stats to be retrieved
        self._limit = None
        self._name = None
        self._attribution = None
        self._metadata_json = None
        self._referencePath = fastaDir
        self._fastaFh = None
        self._currentChrm = 1

    def connect(self, gusConfigFile=None):
        self._database = Database(gusConfigFile)
        self._database.connect()

    def get_metadata(self):
        return self._metadata_json

    def get_limit(self):
        return self._limit

    def set_limit(self, limit):
        self._limit = limit

    def get_track(self):
        """return track"""
        return self._track

    def get_data(self):
        """return data"""
        return self._data

    def get_database(self):
        return self._database

    def set_track(self, track):
        self._track = track

    def set_data(self, data):
        self._data = data

    def get_title(self):
        return self._track + ": " + self._name + " (" + self._attribution + ")"

    def list_available_tracks(self):
        if self._database is None:
            raise ConnectionDoesNotExist(
                "gwas_track object database connection not initialized"
            )

        with self._database.cursor(cursorFactory="RealDictCursor") as cursor:
            cursor.execute(LIST_TRACKS_SQL)
            return cursor.fetchall()

    def fetch_title(self):
        if self._database is None:
            raise ConnectionDoesNotExist(
                "gwas_track object database connection not initialized"
            )

        if self._track is None:
            raise ValueError("Must set track value")

        with self._database.cursor() as cursor:
            cursor.execute(TITLE_SQL, {"track": self._track})
            self._name, self._attribution = cursor.fetchone()

        with self._database.cursor() as cursor:
            cursor.execute(TRACK_METADATA_SQL, {"accession": self._track})
            self._metadata_json = cursor.fetchone()[0]

    def fetch_metadata(self):
        if self._database is None:
            raise ConnectionDoesNotExist(
                "gwas_track object database connection not initialized"
            )

        if self._track is None:
            raise ValueError("Must set track value")

        with self._database.cursor() as cursor:
            cursor.execute(TRACK_METADATA_SQL, {"accession": self._track})
            self._metadata_json = cursor.fetchone()[0]

    def __info_qualifier(self, field: str, type: str, description: str):
        return f"## <ID={field},Number=.Type={type},Description={description}>"
        # INFO=<ID=UCSC.conservation,Number=.,Type=Integer,Description="Score from 0-1000 (conservation scores based on a phylo-HMM)">

    def __vcf_header(self, inclRestricted=False):
        #    ['chromosome', 'position', 'variant_id', 'ref_snp_id', 'pvalue', 'test_allele', 'neg_log10_pvalue', 'annotation', 'restricted_stats']

        fields = ["CHROM", "POS", "ID", "REF", "ALT", "QUAL", "FILTER", "INFO"]
        fieldStr = "#" + "\t".join(fields)

        # fmt:off
        header = ["##fileformat=VCFv4.1",
             self.__info_qualifier("TEST_ALLELE", "String","the specific allele at the genomic location that is being examined" ),
             self.__info_qualifier("PVALUE", "Float", "p-value"),
             self.__info_qualifier("NEG_LOG10_PVALUE", "Float", "-log10 p-value"),
             self.__info_qualifier("ANNOTATION", "String", "(JSON) summary functional annotation for the tested allelic variant"),
             self.__info_qualifier("ADJUSTED", 'Boolean', "if `True`, alleles were swapped so test allele is the alterative; frequency, beta, effect adjusted accordingly"),
             self.__info_qualifier("RS_ID", "String", "refSNP id")]
        
        if inclRestricted:
            header.append(self.__info_qualifier("RESTRICTED_STATS", "String", "(JSON) restricted summary statistics"))
        # fmt:on

        header.append(fieldStr)

        return "\n".join(header)

    def __dict_to_string(self, obj, nullStr=".", delimiter=";"):
        """translate dict to attr=value; string list
        in string utils to avoid circular imports
        """
        pairs = [
            k + "=" + xstr(v, nullStr=nullStr) for k, v in obj.items() if v != None
        ]
        # pairs.sort()
        return delimiter.join(pairs)

    def __build_info_str(self, record, inclRestrictedStats=False):
        info = {
            "TEST_ALLELE": record["test_allele"],
            "PVALUE": record["pvalue"],
            "NEG_LOG10_PVALUE": record["neg_log10_pvalue"],
            "ANNOTATION": record["annotation"],
        }
        if record["ref_snp_id"] is not None:
            info["RS_ID"] = record["ref_snp_id"]

        if 'adjusted' in record is not None:
            info["ADJUSTED"] = True

        if inclRestrictedStats:
            info["RESTRICTED_STATS"] = record["restricted_stats"]

        return self.__dict_to_string(info)

    def __adjust_stats(self, record):
        restrictedStats = json.loads(record["restricted_stats"])
        if "beta" in restrictedStats:
            restrictedStats["beta"] = -1 * restrictedStats["beta"]
        if "effect" in restrictedStats:
            restrictedStats["effect"] = -1 * restrictedStats["effect"]
        if restrictedStats["test_allele_freq"] is not None:
            restrictedStats["test_allele_freq"] = (
                1 - restrictedStats["test_allele_freq"]
            )
        record["restricted_stats"] = json.dumps(restrictedStats)

    def __matches_reference_sequence(self, chrom, position, sequence):
        if self._referencePath is None:
            raise ValueError("Must set FASTA directory to export GWAS data")

        if self._fastaFh is None or chrom != self._currentChrm:
            if self._fastaFh is not None:
                self._fastaFh.close()
            file = path.join(self._referencePath, f"chr{chrom}.fa.gz")
            self._currentChrm = chrom
            self._fastaFh = pysam.FastaFile(file)

        refSequence = self._fastaFh.fetch(
            reference=f"chr{chrom}",
            start=int(position) - 1,
            end=int(position) + len(sequence) - 1,
        ).upper()
        return sequence == refSequence

    def __adjust_test_allele(self, record):
        # check test allele
        if record["alt"] != record["test_allele"]:
            # set test allele to alt and then swap the stats
            # warning(f"{record['ref_snp_id']} - {record['variant_id']} - test = {record['test_allele']}; ADJUSTING")
            record["test_allele"] = record["alt"]
            self.__adjust_stats(record)

            record["adjusted"] = True

    def __adjust_alleles(self, record):
        """record updated by reference ?"""
        chrom, pos, ref, alt = record["variant_id"].split(":")

        if record["ref_snp_id"] is not None:
            # trust dbSNP mapping to reference assembly
            record["alt"] = alt
            record["ref"] = ref

            self.__adjust_test_allele(record)

        else:  # check to see if reference matches sequence
            if self.__matches_reference_sequence(chrom, pos, ref):
                # variant ID is correct
                record["alt"] = alt
                record["ref"] = ref
                self.__adjust_test_allele(record)

            elif self.__matches_reference_sequence(chrom, pos, alt):
                # swap and adjust variant id
                record["alt"] = ref
                record["ref"] = alt
                record["variant_id"] = ":".join((xstr(chrom), xstr(pos), alt, ref))

                self.__adjust_test_allele(record)

            else:  # if neither matches, keep original orientation
                record["alt"] = alt
                record["ref"] = ref
                record["no_sequence_match"] = True
                
                self.__adjust_test_allele(record)

    def export_annotated_sum_stats_as_vcf(self, dir: str = None):
        """fetch sum stats w/annotations & restricted stats in JSON objects only"""
        if self._database is None:
            raise ConnectionDoesNotExist(
                "gwas_track object database connection not initialized"
            )

        if self._track is None:
            raise ValueError("Must set track value")

        sql = ANNOTATED_SUM_STATS_SQL
        if self._limit is not None:
            sql = sql + " LIMIT " + self._limit
            # sql = sql.replace("Results.VariantGWAS r", "Results.VariantGWAS r TABLESAMPLE SYSTEM (0.01)")

        fullStatsFile = (
            f"{self._track}_full.vcf"
            if dir is None
            else path.join(dir, f"{self._track}_full.vcf")
        )

        pvalueStatsFile = (
            f"{self._track}_pvalue_only.vcf"
            if dir is None
            else path.join(dir, f"{self._track}_pvalue_only.vcf")
        )

        warning(f"Fetching track data -- {self._track}")
        count = 0
        with open(fullStatsFile, "w") as fsFh, open(
            pvalueStatsFile, "w"
        ) as pvFh, self._database.named_cursor(
            f"export-gwas-{self._track}", cursorFactory="RealDictCursor"
        ) as selectCursor:

            print(self.__vcf_header(inclRestricted=True), file=fsFh)
            print(self.__vcf_header(), file=pvFh)

            selectCursor.itersize = ITERATION_SIZE
            selectCursor.execute(sql, {"track": self._track})

            for record in selectCursor:
                count += 1
                if count % 50000 == 0:
                    warning(f"{self._track} - PARSED {count}")
                self.__adjust_alleles(record)

                if 'no_sequence_match' in record and '_GRCh38_' in self._track:
                    warning(f"DROPPED {record["variant_id"]}: unable to match reference sequence")
                    continue

                # fields = ["CHROM", "POS", "ID", "REF", "ALT", "QUAL", "FILTER", "INFO"]
                infoStr = self.__build_info_str(record, inclRestrictedStats=True)
                print(
                    "\t".join(
                        (
                            xstr(record["chromosome"]),
                            xstr(record["position"]),
                            record["variant_id"],
                            record["ref"],
                            record["alt"],
                            ".",
                            ".",
                            infoStr,
                        )
                    ),
                    file=fsFh,
                )

                infoStr = self.__build_info_str(record)
                print(
                    "\t".join(
                        (
                            xstr(record["chromosome"]),
                            xstr(record["position"]),
                            record["variant_id"],
                            record["ref"],
                            record["alt"],
                            ".",
                            ".",
                            infoStr,
                        )
                    ),
                    file=pvFh,
                )

        warning(f"DONE: Retrieved {count} records.")

        if self._fastaFh is not None:
            self._fastaFh.close()

        return [fullStatsFile, pvalueStatsFile]
