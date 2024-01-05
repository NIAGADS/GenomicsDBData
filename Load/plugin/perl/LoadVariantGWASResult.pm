## no critic

## $Id: LoadVariantGWASResult.pm $
##

package GenomicsDBData::Load::Plugin::LoadVariantGWASResult;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use GUS::PluginMgr::Plugin;

use threads;
use Thread::Semaphore;
use threads::shared;

BEGIN { $Package::Alias::BRAVE = 1 }
use Package::Alias VariantAnnotator => 'GenomicsDBData::Load::VariantAnnotator';
use Package::Alias Utils            => 'GenomicsDBData::Load::Utils';
use Package::Alias PluginUtils      => 'GenomicsDBData::Load::PluginUtils';
use Package::Alias VariantLoadUtils => 'GenomicsDBData::Load::VariantLoadUtils';
use Package::Alias VariantRecord    => 'GenomicsDBData::Load::VariantRecord';

use JSON::XS;
use Data::Dumper;
use POSIX qw(strftime);
use Parallel::Loops;

use File::Basename;
use File::Path;

use LWP::UserAgent;
use LWP::Parallel::UserAgent;
use HTTP::Request::Common qw(GET);
use HTTP::Request;

use List::MoreUtils qw(natatime);

use GUS::Model::Results::VariantGWAS;
use GUS::Model::NIAGADS::Variant;
use GUS::Model::Study::ProtocolAppNode;

my $APPEND          = 1;
my $USE_MARKER      = 1;
my $INCLUDE_MARKERS = 1;
my $DROP_MARKERS    = 0;
my $NEW_FILE        = 0;
my $FINAL_CHECK     = 10;
my $UPDATE_CHECK    = 20;

my $RESTRICTED_STATS_FIELD_MAP = undef;

my $HOUSEKEEPING_FIELDS = PluginUtils::getHouseKeepingSql();

my @INPUT_FIELDS =
  qw(chr bp allele1 allele2 marker metaseq_id freq1 pvalue neg_log10_p display_p gwas_flags test_allele restricted_stats_json GRCh37 GRCh38);
my @RESULT_FIELDS =
  qw(chr bp allele1 allele2 freq1 pvalue neg_log10_p display_p gwas_flags test_allele restricted_stats_json db_variant_json);
my @RESTRICTED_STATS_ORDER =
  qw(num_observations coded_allele_frequency minor_allele_count call_rate test min_frequency max_frequency frequency_se effect beta t_statistic std_err odds_ratio beta_std_err beta_L95 beta_U95 odds_ratio_L95 odds_ratio_U95 hazard_ratio hazard_ratio_CI95 direction het_chi_sq het_i_sq het_df het_pvalue probe maf_case maf_control p_additive p_dominant p_recessive Z_additive Z_dominant Z_recessive );
my @VCF_FIELDS = qw(#CHROM POS ID REF ALT QUAL FILTER INFO);

my $COPY_SQL = <<COPYSQL;
COPY Results.VariantGWAS(
protocol_app_node_id,
variant_record_primary_key,
bin_index,
neg_log10_pvalue,
pvalue_display,
frequency,
allele,
restricted_stats,
$HOUSEKEEPING_FIELDS
)
FROM STDIN 
WITH (DELIMITER '|', 
NULL 'NULL')
COPYSQL

my $SHARED_VARIABLE_SEMAPHORE = Thread::Semaphore->new(1);
my $PROCESS_COUNT_SEMAPHORE   = undef;

# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
    my $argumentDeclaration = [
        stringArg(
            {
                name  => 'fileDir',
                descr =>
'directory containing input file & to which output of plugin will be written',
                constraintFunc => undef,
                reqd           => 1,
                isList         => 0
            }
        ),

        stringArg(
            {
                name  => 'sourceGenomeBuildGusConfig',
                descr =>
'gus config file for the lift over source version, should be GRCh37 gus.config',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0,
            }
        ),

        stringArg(
            {
                name           => 'updateGusConfig',
                descr          => 'gus config for update if not default',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0,
            }
        ),

        stringArg(
            {
                name           => 'caddDatabaseDir',
                descr          => 'full path to CADD database directory',
                constraintFunc => undef,
                reqd           => 1,
                isList         => 0,
            }
        ),

        fileArg(
            {
                name  => 'adspConsequenceRankingFile',
                descr => 'full path to ADSP VEP consequence ranking file',
                constraintFunc => undef,
                reqd           => 1,
                isList         => 0,
                mustExist      => 1,
                format         => 'new line delimited text'
            }
        ),

        booleanArg(
            {
                name  => 'liftOver',
                descr =>
'use UCSC liftOver to lift over to GRCh38 / TODO - generalize',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0,
            }
        ),

        stringArg(
            {
                name  => 'remapAssemblies',
                descr =>
'from|dest assembly accessions: e.g., GCF_000001405.25|GCF_000001405.39 (GRCh37.p13|GRCh38.p13)",',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0,
            }
        ),

        fileArg(
            {
                name           => 'liftOverChainFile',
                descr          => 'full path to liftOver chain file',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0,
                mustExist      => 1,
                format         => 'UCSC chain file'
            }
        ),

        stringArg(
            {
                name           => 'vepWebhook',
                descr          => "base url for vep webhook",
                constraintFunc => undef,
                isList         => 0,
                reqd           => 1
            }
        ),

        fileArg(
            {
                name           => 'file',
                descr          => 'input file (do not include full path)',
                constraintFunc => undef,
                reqd           => 1,
                mustExist      => 0,
                isList         => 0,
                format         => 'tab delim text'
            }
        ),

        stringArg(
            {
                name           => 'sourceId',
                descr          => 'protocol app node source id',
                constraintFunc => undef,
                reqd           => 1,
                isList         => 0
            }
        ),

        stringArg(
            {
                name           => 'frequency',
                descr          => '(optional) column containing freqency value',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        stringArg(
            {
                name           => 'marker',
                descr          => '(optional) column containing marker name',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        stringArg(
            {
                name           => 'testAllele',
                descr          => 'column containg test allele',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        stringArg(
            {
                name           => 'refAllele',
                descr          => 'column containg ref allele',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        stringArg(
            {
                name  => 'altAllele',
                descr =>
'(optional) only specify if input has 3 allele columns (e.g., major, minor, test)',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        stringArg(
            {
                name           => 'chromosome',
                descr          => 'column containg chromosome',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        stringArg(
            {
                name  => 'genomeWideSignificanceThreshold',
                descr =>
'threshold for flagging result has having genome wide signficiance; provide in scientific notation',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0,
                default        => '5e-8'
            }
        ),

        stringArg(
            {
                name           => 'position',
                descr          => 'column containing position',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        stringArg(
            {
                name           => 'pvalue',
                descr          => 'column containing pvalue',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        stringArg(
            {
                name  => 'genomeBuild',
                descr => 'genome build for the data (GRCh37 or GRCh38)',
                constraintFunc => undef,
                reqd           => 1,
                isList         => 0
            }
        ),

        stringArg(
            {
                name  => 'restrictedStats',
                descr =>
'json object of key value pairs for additional scores/annotations that have restricted access',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        booleanArg(
            {
                name           => 'zeroBased',
                descr          => 'flag if file is zero-based',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        booleanArg(
            {
                name           => 'lookupUnmappableMarkers',
                descr          => 'lookup unmappable markers',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        booleanArg(
            {
                name           => 'markerIsValidRefSnp',
                descr          => 'flag indicating if marker is valid refSNP (high confidence) and be concatenated to primary keys for novel variants',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),


        booleanArg(
            {
                name           => 'skipUnmappableMarkers',
                descr          => 'skip unmappable markers',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        booleanArg(
            {
                name           => 'mapPosition',
                descr          => 'flag if can map to all variants at position',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        booleanArg(
            {
                name           => 'isAdsp',
                descr          => 'flag if datasource is ADSP',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        booleanArg(
            {
                name           => 'mapThruMarker',
                descr          => 'flag if can only be mapped thru marker',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        booleanArg(
            {
                name  => 'allowAlleleMismatches',
                descr =>
                  'flag if map to marker even in alleles do not match exactly',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        booleanArg(
            {
                name  => 'markerIsMetaseqId',
                descr =>
'flag if marker is a metaseq_id; to be used with map thru marker',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        booleanArg(
            {
                name  => 'checkAltIndels',
                descr =>
'check for alternative variant combinations for indels, e.g.: ref:alt, alt:ref',
                constraintFunc => undef,
                isList         => 0,
                reqd           => 0
            }
        ),

        booleanArg(
            {
                name  => 'markerIndicatesIndel',
                descr =>
                  'marker indicates whether insertion or deletion (I or D)',
                constraintFunc => undef,
                isList         => 0,
                reqd           => 0
            }
        ),

        stringArg(
            {
                name  => 'customChrMap',
                descr =>
'json object defining custom mappings (e.g., {"25":"M", "Z": "5"}',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        stringArg(
            {
                name           => 'seqrepoProxyPath',
                descr          => 'for loading novel variants/ generating PKs',
                constraintFunc => undef,
                reqd           => 1,
                isList         => 0
            }
        ),

        booleanArg(
            {
                name  => 'updateFlags',
                descr =>
'update existing variant annotation: gwas_flags (part of load), lift over coords, typically part of load, but can run independently for debugging',
                constraintFunc => undef,
                isList         => 0,
                reqd           => 0
            }
        ),

        booleanArg(
            {
                name  => 'preprocess',
                descr =>
                  'preprocess / map to DB, find & annotate novel variants',
                constraintFunc => undef,
                isList         => 0,
                reqd           => 0
            }
        ),

        booleanArg(
            {
                name  => 'clean',
                descr => 'clean working directory (remove intermediary files)',
                constraintFunc => undef,
                isList         => 0,
                reqd           => 0
            }
        ),

        booleanArg(
            {
                name           => 'archive',
                descr          => 'archive working directory',
                constraintFunc => undef,
                isList         => 0,
                reqd           => 0
            }
        ),

        booleanArg(
            {
                name  => 'standardize',
                descr =>
'generate standardized files for storage in the data repository; one p-values only; one complete, can be done along w/--load, but assumes preprocessing complete and will fail if dbmapped file does not exist or is incomplete',
                constraintFunc => undef,
                isList         => 0,
                reqd           => 0
            }
        ),

        booleanArg(
            {
                name  => 'load',
                descr =>
'load variants; assumes preprocessing completed and will fail if dbmapped file does not exist or is incomplete',
                constraintFunc => undef,
                isList         => 0,
                reqd           => 0
            }
        ),

        booleanArg(
            {
                name  => 'skipMetaseqIdValidation',
                descr => 'for dataset with large numbers of non-standard ids',
                constraintFunc => undef,
                isList         => 0,
                reqd           => 0
            }
        ),

        booleanArg(
            {
                name           => 'overwrite',
                descr          => 'overwrite intermediary files',
                constraintFunc => undef,
                isList         => 0,
                reqd           => 0
            }
        ),

        booleanArg(
            {
                name           => 'probe',
                descr          => 'input includes a probe field',
                constraintFunc => undef,
                isList         => 0,
                reqd           => 0
            }
        ),

        booleanArg(
            {
                name  => 'resume',
                descr =>
'resume variant load; need to check against db for variants that were flagged  but not actually loaded',
                constraintFunc => undef,
                isList         => 0,
                reqd           => 0
            }
        ),

        booleanArg(
            {
                name  => 'test',
                descr => 'development flag / used to limit performance',
                constraintFunc => undef,
                isList         => 0,
                reqd           => 0
            }
        ),

        booleanArg(
            {
                name  => 'skipVep',
                descr =>
'skip VEP run; when novel variants contain INDELS takes a long time to run VEP + likelihood of running into a new consequence in the result is high; use this to use the existing JSON file to try and do the AnnotatedVDB update',
                constraintFunc => undef,
                isList         => 0,
                reqd           => 0
            }
        ),

        integerArg(
            {
                name  => 'commitAfter',
                descr => 'files matching the listed pattern (e.g., chrN)',
                constraintFunc => undef,
                isList         => 0,
                default        => 100000,
                reqd           => 0
            }
        ),

        integerArg(
            {
                name  => 'numWorkers',
                descr => 'num parallel workers',
                constraintFunc => undef,
                isList         => 0,
                default        => 10,
                reqd           => 0
            }
        ),
    ];
    return $argumentDeclaration;
}

# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
    my $purposeBrief = 'Loads Variant GWAS result';

    my $purpose =
'Loads Variant GWAS result in multiple passes: 1) lookup against AnnotatedVDB & flag novel variants; output updated input file w/mapped record PK & bin_index, 2) annotate novel variants and update new annotated input file, 3) sort annotated input file by position and update/insert into NIAGADS.Variant and annotatedVDB 4)load GWAS results, 5) output standardized files for NIAGADS repository';

    my $tablesAffected = [
        [ 'Results::VariantGWAS', 'Enters a row for each variant feature' ],
        [
            'NIAGAD::Variant',
'Enters a row for each variant when insertMissingVariants option is specified'
        ]
    ];

    my $tablesDependedOn =
      [ [ 'Study::ProtocolAppNode', 'lookup analysis source_id' ] ];

    my $howToRestart = '';

    my $failureCases = '';

    my $notes = <<NOTES;

Written by Emily Greenfest-Allen
Copyright Trustees of University of Pennsylvania 2019. 
NOTES

    my $documentation = {
        purpose          => $purpose,
        purposeBrief     => $purposeBrief,
        tablesAffected   => $tablesAffected,
        tablesDependedOn => $tablesDependedOn,
        howToRestart     => $howToRestart,
        failureCases     => $failureCases,
        notes            => $notes
    };

    return $documentation;
}

# ----------------------------------------------------------------------
# create and initalize new plugin instance.
# ----------------------------------------------------------------------

sub new {
    my ($class) = @_;
    my $self = {};
    bless( $self, $class );

    my $documentation       = &getDocumentation();
    my $argumentDeclaration = &getArgumentsDeclaration();

    $self->initialize(
        {
            requiredDbVersion => 4.0,
            cvsRevision       => '$Revision: 26$',
            name              => ref($self),
            revisionNotes     => '',
            argsDeclaration   => $argumentDeclaration,
            documentation     => $documentation
        }
    );
    return $self;
}

# ----------------------------------------------------------------------
# run method to do the work
# ----------------------------------------------------------------------

sub run {
    my ($self) = @_;

    $self->initializePlugin();

    my $numWorkers = $self->getArg('numWorkers');
    $self->log('Initializing PROCESS COUNT SEMAPHORE; num workers = $numWorkers');
    $PROCESS_COUNT_SEMAPHORE = Thread::Semaphore->new($numWorkers);

    my $liftedOverInputFile =
      ( $self->getArg('liftOver') )
      ? $self->liftOver( $self->getArg('updateFlags') )
      : undef;
    $self->preprocess() if ( $self->getArg('preprocess') );
    $self->loadResult() if ( $self->getArg('load') );
    $self->updateVariantFlags($liftedOverInputFile)
      if ( $self->getArg('updateFlags') );
    $self->standardize()       if ( $self->getArg('standardize') );
    $self->cleanWorkingDir()   if ( $self->getArg('clean') );
    $self->archiveWorkingDir() if ( $self->getArg('archive') );
}

# ----------------------------------------------------------------------
# helper methods
# ----------------------------------------------------------------------

sub initializePlugin {
    my ($self) = @_;

    $self->logAlgInvocationId();
    $self->logCommit();
    $self->logArgs();
    $self->getAlgInvocation()->setMaximumNumberOfObjects(100000);

    $self->verifyArgs();

    $self->{custom_chr_map} =
      ( $self->getArg('customChrMap') ) ? $self->generateCustomChrMap() : undef;

    if ( $self->getArg('liftOver') ) {
        $self->{gus_config} = {
            GRCh37 => $self->getArg('sourceGenomeBuildGusConfig'),
            GRCh38 => undef
        };    # will use plugin default
    }
    else {
        $self->{gus_config}->{ $self->getArg('genomeBuild') } = undef;
    }

    $self->{protocol_app_node_id} =
      $self->getProtocolAppNodeId();    # verify protocol app node

    $self->{annotator}    = VariantAnnotator->new( { plugin => $self } );
    $self->{housekeeping} = PluginUtils::buildHouseKeepingString($self);
    $self->{files}        = {};

    my $sourceId = $self->getArg('sourceId');
    if ( $self->getArg('liftOver') ) {
        $sourceId =~ s/_GRCh38//g;
    }
    if ( $self->getArg('genomeBuild') eq 'GRCh37' ) {

        # for postprocessing GRCh37 files that were lifted over
        if ( $sourceId =~ /GRCh38/ ) {
            $sourceId =~ s/_GRCh38//g;
        }
    }

    $self->{adj_source_id} = $sourceId;
    $self->{root_file_path} =
      $self->getArg('fileDir') . "/" . $self->getArg('genomeBuild') . "/";
    PluginUtils::createDirectory( $self, $self->{root_file_path} );
    my $workingDir = PluginUtils::createDirectory(
        $self,
        $self->{root_file_path},
        $self->{adj_source_id}
    );
    $self->{working_dir} = $workingDir;
}

sub verifyArgs {
    my ($self) = @_;

    if ( $self->getArg('preprocess') ) {
        $self->error("must specify testAllele")
          if (  !$self->getArg('testAllele')
            and !$self->getArg('marker')
            and !$self->getArg('markerIsMetaseqId') );
        $self->error("must specify refAllele")
          if ( !$self->getArg('refAllele') and !$self->getArg('marker') );
        $self->error("must specify pvalue") if ( !$self->getArg('pvalue') );
        $self->error("must specify marker if mapping through marker")
          if ( $self->getArg('mapThruMarker') and !$self->getArg('marker') );
    }

    if ( $self->getArg('liftOver') ) {
        $self->error("must specify liftOver chain file")
          if ( !$self->getArg('liftOverChainFile') );
        $self->error("must specify gus.config file for source genome build")
          if ( !$self->getArg('sourceGenomeBuildGusConfig') );
        if ( $self->getArg('updateFlags') ) {
            $self->error("must specify update gus.config file (annotatedvdb)")
              if ( !$self->getArg('updateGusConfig') );
        }
    }

}

sub getProtocolAppNodeId {
    my ($self) = @_;
    my $protocolAppNode = GUS::Model::Study::ProtocolAppNode->new(
        { source_id => $self->getArg('sourceId') } );
    $self->error(
        "No protocol app node found for " . $self->getArg('sourceId') )
      unless $protocolAppNode->retrieveFromDB();

    return $protocolAppNode->getProtocolAppNodeId();
}

sub generateCustomChrMap {
    my ($self) = @_;
    my $json   = JSON::XS->new;
    my $chrMap = $json->decode( $self->getArg('customChrMap') )
      || $self->error("Error parsing custom chromosome map");
    $self->log( "Found custom chromosome mapping: " . Dumper( \$chrMap ) );
    return $chrMap;
}

sub generateStandardizedHeader {
    my ( $self, $stats ) = @_;

    my @header = ();
    foreach my $label (@RESTRICTED_STATS_ORDER) {
        next                    if ( $label eq 'probe' );        # already added
        push( @header, $label ) if ( exists $stats->{$label} );
    }

    my $json    = JSON::XS->new;
    my $rsParam = $json->decode( $self->getArg('restrictedStats') )
      || $self->error("Error parsing restricted stats JSON");
    my @otherRSTATS =
      ( exists $rsParam->{other} ) ? @{ $rsParam->{other} } : undef;
    foreach my $label (@otherRSTATS) {
        push( @header, $label ) if ( exists $stats->{$label} );
    }

    return @header;
}

sub generateInsertStr {
    my ( $self, $recordPK, $binIndex, $data ) = @_;
    my @values = (
        $self->{protocol_app_node_id}, $recordPK,
        $binIndex,                     $data->{neg_log10_p},
        $data->{display_p},            $data->{freq1},
        $data->{test_allele},          $data->{restricted_stats_json}
    );

    push( @values, GenomicsDBData::Load::Utils::getCurrentTime() );
    push( @values, $self->{housekeeping} );
    my $str = join( "|", @values );
    return "$str\n";
}

sub getColumnIndex {
    my ( $self, $columnMap, $field ) = @_;

    $self->error("$field not in file header")
      if ( !exists $columnMap->{$field} );
    return $columnMap->{$field};
}

# ----------------------------------------------------------------------
# file manipulation methods
# ----------------------------------------------------------------------

sub cleanDirectory {
    my ( $self, $workingDir, $targetDir ) = @_;

    my $path = "$workingDir/$targetDir";
    if ( -e $path ) {
        $self->log("WARNING: $targetDir directory ($path) found/removing");

        # rmtree($path); # race condition
        my $cmd = `rm -rf $path`;
    }
    else {
        $self->log(
            "INFO: $targetDir directory ($path) does not exist/skipping");
    }
}

sub cleanWorkingDir {    # clean working directory
    my ($self)      = @_;
    my $genomeBuild = $self->getArg('genomeBuild');
    my $workingDir  = $self->{working_dir};
    $self->log(
        "INFO: Cleaning working directory for $genomeBuild: $workingDir");
    $self->log("INFO: Removing subdirectories");

    $self->cleanDirectory( $workingDir, "liftOver" );
    $self->cleanDirectory( $workingDir, "remap" );
    $self->cleanDirectory( $workingDir, "preprocess" );

    my $path = "$workingDir/standardized";
    if ( -e $path ) {
        if ( !$self->getArg('archive') )
        {    # keep standardization directory for achive
            $self->log("WARNING: standardized directory found/removing");

            # rmtree($path); # race condition
            my $cmd = `rm -rf $path`;
        }
    }
    else {
        $self->log(
            "INFO: standardized directory ($path) does not exist/skipping");
    }

    # delete files
    $self->log("WARNING: Removing logs and dbmapping files");

    my @patterns = map { qr/\Q$_/ } ('dbmapped');
    foreach my $file ( glob "$workingDir/*" ) {
        foreach my $pattern (@patterns) {
            if ( $file =~ $pattern ) {
                $self->log("INFO: Removing $file");
                unlink $file or $self->error("Cannot delete file $file: $!");
                next FILE;
            }
        }
    }
}

sub compressFiles {
    my ( $self, $workingDir, $pattern, $message ) = @_;

    my @patterns = map { qr/\Q$_/ } ($pattern);
    foreach my $file ( glob "$workingDir/*" ) {
        foreach my $pattern (@patterns) {
            if ( $file =~ $pattern ) {
                if ( $file !~ m/\.gz/ )
                {    # not already compressed in case of recovery/resume
                    $self->log("INFO: Compressing $message file: $file");
                    my $cmd = `gzip $file`;
                }
                else {
                    $self->log(
"WARNING: Skipping $message file $file; already compressed"
                    );
                }
            }
        }
    }
}

sub archiveWorkingDir {
    my ($self)      = @_;
    my $genomeBuild = $self->getArg('genomeBuild');
    my $workingDir  = $self->{working_dir};
    my $sourceId    = $self->{adj_source_id};
    my $rootPath    = $self->{root_file_path};

    $self->log(
        "INFO: Archiving working directory for $genomeBuild: $workingDir");
    $self->cleanWorkingDir();

    $self->compressFiles( $workingDir, "input", "cleaned input" );
    $self->compressFiles( $workingDir . "/standardized",
        "txt", "standardized output" );
    $self->log("INFO: Compressing working directory: $workingDir");
    my $cmd = `tar -zcf $workingDir.tar.gz --directory=$rootPath $sourceId`;
    $self->log("INFO: Removing working directory: $workingDir");

    # rmtree($workingDir); #race condition
    $cmd = `rm -rf $workingDir`;
}

sub removeFileDuplicates {
    my ( $self, $fileName ) = @_;
    my $cmd = `uniq $fileName > $fileName.uniq && mv $fileName.uniq $fileName`;
}

sub sortCleanedInput {
    my ( $self, $workingDir, $fileName ) = @_;
    my $sortedFileName = $fileName . "-sorted.tmp";
    $self->log(
        "Sorting cleaned input $fileName / working directory = $workingDir");
    my $cmd =
`(head -n 1 $fileName && tail -n +2 $fileName | sort -T $workingDir -V -k1,1 -k2,2 ) > $sortedFileName`;
    $cmd = `mv $sortedFileName $fileName`;
    $self->log("Created sorted file: $fileName");
}

sub writeCleanedInput {
    my ( $self, $fh, $resultVariant, $fields, @values ) = @_;

    my $frequencyC =
      ( $self->getArg('frequency') )
      ? $fields->{ $self->getArg('frequency') }
      : undef;
    my $frequency = ( defined $frequencyC ) ? $values[$frequencyC] : 'NULL';
    my $pvalueC   = $fields->{ $self->getArg('pvalue') };
    my ( $pvalue, $negLog10p, $displayP ) =
      $self->formatPvalue( $values[$pvalueC] );

    my $restrictedStats = 'NULL';
    if ( $self->getArg('restrictedStats') ) {
        $restrictedStats = $self->buildRestrictedStatsJson(@values);
    }

    my $gwasFlags =
      ( $pvalue <= 0.001 )
      ? $self->buildGWASFlags( $pvalue, $displayP )
      : undef;

# (chr bp allele1 allele2 marker metaseq_id freq1 pvalue neg_log10_p display_p gws_flags test_allele restricted_stats_json GRCh37 GRCh38);
    print $fh join(
        "\t",
        (
              $resultVariant->{chromosome}
            ? $resultVariant->{chromosome}
            : "NULL",
            $resultVariant->{position} ? $resultVariant->{position} : "NULL",
            $resultVariant->{altAllele},
            $resultVariant->{refAllele},
            ( $resultVariant->{marker} ) ? $resultVariant->{marker} : "NULL",
            (
                $resultVariant->{metaseq_id} =~ m/NA/g
                  || !$resultVariant->{metaseq_id}
            ) ? "NULL" : $resultVariant->{metaseq_id},
            $frequency,
            $pvalue,
            $negLog10p,
            $displayP,
            $gwasFlags ? $gwasFlags : "NULL",
            $resultVariant->{testAllele},
            $restrictedStats,
            "NULL", "NULL"
        )
    ) . "\n";
}

# ----------------------------------------------------------------------
# attribute formatting
# ----------------------------------------------------------------------

sub cleanAllele {
    my ( $self, $allele ) = @_;

    $allele =~ s/<|>//g;
    $allele =~ s/:/\//g;
    return $allele;
}

sub correctChromosome {
    my ( $self, $chrm ) = @_;
    my $customChrMap = $self->{custom_chr_map};

    return ($chrm) if ( !$customChrMap );

    while ( my ( $oc, $rc ) = each %$customChrMap ) {
        $chrm = $rc if ( $chrm =~ m/\Q$oc/ );
    }

    $chrm = 'M' if ( $chrm =~ m/25/ );
    $chrm = 'M' if ( $chrm =~ m/MT/ );
    $chrm = 'X' if ( $chrm =~ m/23/ );
    $chrm = 'Y' if ( $chrm =~ m/24/ );
    return $chrm;
}

sub generateAlleleStr {
    my ( $self, $ref, $alt, $marker, $chromosome, $position, $frequencyC,
        $frequency )
      = @_;

    my $alleleStr = "$ref:$alt";
    my $isIndel   = ( length($ref) > 1 || length($alt) > 1 );

    if ( $alleleStr =~ /\?/ ) {    # merged deletion or insertion
        if ( $self->getArg('markerIndicatesIndel') && $marker ne 'NULL' ) {
            if ( $marker =~ m/I$/ || $marker =~ m/ins/ ) {
                $alleleStr = ( $alt =~ /\?/ ) ? "$ref:$alt" : "$alt:$ref";
            }
            elsif ( $marker =~ m/D$/ || $marker =~ m/del/ ) {
                $alleleStr = ( $ref =~ /\?/ ) ? "$ref:$alt" : "$alt:$ref";
            }
            $self->log(
"WARNING: improper deletion: $chromosome:$position:$ref:$alt; UPDATED TO: $chromosome:$position:$alleleStr"
            );
        }
        else {    # take at face value
            $self->log(
                "WARNING: improper deletion: $chromosome:$position:$ref:$alt");
        }
    }    # end "-"
    elsif ($isIndel) {
        if ( $self->getArg('markerIndicatesIndel') && $marker ne 'NULL' ) {
            if ( $marker =~ m/I$/ || $marker =~ m/ins/ ) {    # A:AAT
                $alleleStr =
                  ( length($ref) < length($alt) )
                  ? $ref . ':' . $alt
                  : $alt . ':' . $ref;
            }
            elsif ( $marker =~ m/D$/ || $marker =~ m/del/ ) {    # AAT:A
                $alleleStr =
                  ( length($ref) > length($alt) )
                  ? $ref . ':' . $alt
                  : $alt . ':' . $ref;
            }
        }
    }
    else
    { # for SNVs if frequency > 0.5, then the test allele is the major allele; saves us some lookup times
        $alleleStr =
          ( $frequencyC and $frequency > 0.5 )
          ? $alt . ':' . $ref
          : $ref . ':' . $alt;
    }
    return $alleleStr;
}

sub formatPvalue {
    my ( $self, $pvalue ) = @_;
    my $negLog10p = 0;

    if ( $pvalue =~ m/NAN/i ) {
        return ( "NaN", "NaN", "NaN" );
    }

    if ( $pvalue =~ m/NA$/ ) {
        return ( "NULL", "NULL", "NULL" );
    }

    return ( $pvalue, "NaN", $pvalue ) if ( $pvalue == 0 );

    if ( !$pvalue ) {
        return ( "NULL", "NULL", "NULL" );
    }

    if ( $pvalue =~ m/e/i ) {
        my ( $mantissa, $exponent ) = split /-/, $pvalue;
        return ( $pvalue, $exponent, $pvalue ) if ( $exponent > 300 );
    }

    return ( 1, 0, $pvalue ) if ( $pvalue == 1 );

    eval {
        $negLog10p = -1.0 * ( log($pvalue) / log(10) );

    } or do {
        $self->log("WARNING: Cannot take log of p-value ($pvalue)");
        return ( $pvalue, $pvalue, $pvalue );
    };

    my $displayP = ( $pvalue < 0.0001 ) ? sprintf( "%.2e", $pvalue ) : $pvalue;

    return ( $pvalue, $negLog10p, $displayP );
}

sub generateRestrictedStatsFieldMapping {
    my ( $self, $columns ) = @_;
    my $json  = JSON::XS->new;
    my $stats = $json->decode( $self->getArg('restrictedStats') )
      || $self->error("Error parsing restricted stats JSON");

    $RESTRICTED_STATS_FIELD_MAP = {};
    while ( my ( $stat, $field ) = each %$stats ) {
        if ( $stat eq "other" ) {
            foreach my $fd (@$field) {
                $RESTRICTED_STATS_FIELD_MAP->{$fd} =
                  $self->getColumnIndex( $columns, $fd );
            }
        }
        else {
            $RESTRICTED_STATS_FIELD_MAP->{$stat} =
              $self->getColumnIndex( $columns, $field );
        }
    }
}

sub buildRestrictedStatsJson {
    my ( $self, @values ) = @_;
    my $stats = {};
    while ( my ( $stat, $index ) = each %$RESTRICTED_STATS_FIELD_MAP ) {
        my $tValue = lc( $values[$index] );
        if ( $tValue eq "infinity" or $tValue =~ m/^inf$/ ) {
            $stats->{$stat} = "Infinity";
        }
        else
        { # otherwise replaces Infinity w/inf which will cause problems w/load b/c inf s not a number in postgres
            $stats->{$stat} = Utils::toNumber( $values[$index] );
        }
    }
    return Utils::to_json($stats);
}

sub buildGWASFlags {
    my ( $self, $pvalue, $displayP ) = @_;
    my $flags = {
        $self->getArg('sourceId') => {
            p_value => Utils::toNumber($displayP),
            is_gws  => $pvalue <=
              $self->getArg('genomeWideSignificanceThreshold') ? 1 : 0
        }
    };

    return Utils::to_json($flags);
}

# ----------------------------------------------------------------------
# clean and sort
# ----------------------------------------------------------------------

sub cleanAndSortInput {
    my ( $self, $file ) = @_;
    my $lineCount = 0;

    $self->log("INFO: Cleaning $file");

    my $genomeBuild   = $self->getArg('genomeBuild');
    my $filePrefix    = $self->{adj_source_id};
    my $inputFileName = $self->{working_dir} . "/" . $filePrefix . '-input.txt';

    if ( -e $inputFileName && !$self->getArg('overwrite') ) {
        $self->log("INFO: Using existing cleaned input file: $inputFileName");
        return $inputFileName;
    }

    my $pfh = undef;
    open( $pfh, '>', $inputFileName )
      || $self->error(
        "Unable to create cleaned file $inputFileName for writing");
    print $pfh join( "\t", @INPUT_FIELDS ) . "\n";

    $pfh->autoflush(1);

    open( my $fh, $file ) || $self->error("Unable to open $file for reading");

    my $header = <$fh>;
    chomp($header);
    my @fields = split /\t/, $header;
    @fields = split /\s/, $header if ( scalar @fields == 1 );
    @fields = split /,/,  $header if ( scalar @fields == 1 );

    my %columns = map { $fields[$_] => $_ } 0 .. $#fields;
    if ( $self->getArg('restrictedStats') ) {
        $self->generateRestrictedStatsFieldMapping( \%columns )
          if ( !$RESTRICTED_STATS_FIELD_MAP );
    }

    my $testAlleleC =
      ( $self->getArg('testAllele') )
      ? $self->getColumnIndex( \%columns, $self->getArg('testAllele') )
      : undef;
    my $refAlleleC =
      ( $self->getArg('refAllele') )
      ? $self->getColumnIndex( \%columns, $self->getArg('refAllele') )
      : undef;
    my $altAlleleC =
      ( $self->getArg('altAllele') )
      ? $self->getColumnIndex( \%columns, $self->getArg('altAllele') )
      : undef;
    my $chrC =
      ( $self->getArg('chromosome') )
      ? $self->getColumnIndex( \%columns, $self->getArg('chromosome') )
      : undef;
    my $positionC =
      ( $self->getArg('position') )
      ? $self->getColumnIndex( \%columns, $self->getArg('position') )
      : undef;
    my $markerC =
      ( $self->getArg('marker') )
      ? $self->getColumnIndex( \%columns, $self->getArg('marker') )
      : undef;

    while ( my $line = <$fh> ) {
        chomp $line;
        my @values = split /\t/, $line;
        @values = split /\s/, $line if ( scalar @values == 1 );
        @values = split /,/,  $line if ( scalar @values == 1 );

        my $marker = ( defined $markerC ) ? $values[$markerC] : undef;
        $marker = 'NULL' if $marker eq 'NA';

        my $chromosome = undef;
        my $position   = undef;
        my $metaseqId  = undef;
        my $alleleStr  = undef;

        # N for uknown single allele; this will allow us to match chr:pos:N:test
        my $ref = ($refAlleleC) ? uc( $values[$refAlleleC] ) : 'N';
        my $alt =
            ($altAlleleC)  ? uc( $values[$altAlleleC] )
          : ($testAlleleC) ? uc( $values[$testAlleleC] )
          :                  'N';
        my $test = ($testAlleleC) ? uc( $values[$testAlleleC] ) : undef;

        # set ref/alt to N if unknown so can still map/annotate
        # set test to N if 0 but leave as ? if ?
        $ref = 'N'
          if ( $ref =~ m/^0$/ )
          ; # vep can still process the 'N' if there is a single unknown, so do the replacement here for consistency
        $ref = '?'
          if ( $ref =~ m/^\?$/ );    # assume ? matches unknown number of bases
        $ref = '?'
          if ( $ref =~ m/^-$/ );     # assume ? matches unknown number of bases
        $alt = 'N' if ( $alt =~ m/^0$/ );
        $alt = 'N' if ( $alt =~ m/^\?$/ );
        $alt = '?'
          if ( $alt =~ m/^-$/ );     # assume ? matches unknown number of bases
        $test = 'N' if ( $test =~ m/^0$/ );
        $test = '?' if ( $test =~ m/^\?$/ );
        $test = '?' if ( $test =~ m/^-$/ );

        my $frequencyC =
          ( $self->getArg('frequency') )
          ? $self->getColumnIndex( \%columns, $self->getArg('frequency') )
          : undef;
        my $frequency = ($frequencyC) ? $values[$frequencyC] : undef;

        if ( defined $chrC ) {
            $chromosome = $values[$chrC];

            if ( $chromosome eq "0" || !defined $chromosome ) {
                $chromosome = undef;
            }
            else {
                if ( $chromosome =~ m/:/ ) {
                    ( $chromosome, $position ) = split /:/, $chromosome;
                }
                elsif ( $chromosome =~ m/-/ ) {
                    ( $chromosome, $position ) = split /-/, $chromosome;
                }
                else {
                    $self->error("must specify position column")
                      if ( !$positionC );
                    $position = $values[$positionC];
                }

                $chromosome = $self->correctChromosome($chromosome);
            }
            if ( $position == 0 )
            {    # mapping issue/no confidence in rsId either so skip
                $position = undef;
            }
            $position = $position + 1
              if ( $position && $self->getArg('zeroBased') );

            $alleleStr =
              ( $self->getArg('mapPosition') )
              ? undef
              : $self->generateAlleleStr( $ref, $alt, $marker, $chromosome,
                $position, $frequencyC, $frequency );

            $metaseqId =
              ( $position && $chromosome )
              ? $chromosome . ':' . $position . ':' . $alleleStr
              : undef;
        }    # end definded chrC & !mapThruMarker

        else {    # chrC not defined / mapping thru marker
            $marker = undef if ( $chrC eq $markerC );
            if (
                $chromosome eq "NA"
                || (   $self->getArg('mapThruMarker')
                    && $self->getArg('markerIsMetaseqId') )
                || $marker =~ /:/
              )
            {
                $metaseqId = $marker
                  if ( $self->getArg('markerIsMetaseqId') )
                  ; # yes ignore all that processing just did; easy fix added later

                # some weird ones are like chr:ps:ref:<weird:alt:blah:blah>
                my ( $c, $p, $r, $a ) = split /\<[^><]*>(*SKIP)(*FAIL)|:/,
                  $metaseqId;
                $chromosome = $self->correctChromosome($c);
                $position   = $p;
                if ( $self->getArg('markerIsMetaseqId') ) {
                    $alt = $self->cleanAllele($a);
                    $ref = $self->cleanAllele($r);
                    $test =
                      ($test)
                      ? $self->cleanAllele($test)
                      : $alt;    # assume testAllele is alt if not specified
                }

                $metaseqId = ( $ref && $alt )
                  ? join( ':', $chromosome, $position, $ref,
                    $alt )       # in case chromosome/alleles were corrected
                  : join( ':', $chromosome, $position ) . ($alleleStr)
                  ? ':' . $alleleStr
                  : '';

            }
            $self->error(
"--testAllele not specified and unable to extract from marker.  Must specify 'testAllele'"
            ) if ( !$test );
        }    # end mapping thru marker

        my $rv = {
            chromosome => $chromosome,
            position   => $position,
            refAllele  => $ref,
            altAllele  => $alt,
            testAllele => $test,
            marker     => $marker,
            metaseq_id => $metaseqId
        };

        $self->writeCleanedInput( $pfh, $rv, \%columns, @values );

        if ( ++$lineCount % 500000 == 0 ) {
            $self->log("INFO: Cleaned $lineCount lines");
        }
    }

    $self->log("INFO: Cleaned $lineCount lines");
    $self->sortCleanedInput( $self->{working_dir}, $inputFileName );
    return $inputFileName;
}    # end cleanAndSortInput

# ----------------------------------------------------------------------
# query against DB to find GRCh38 mappings
# not done in clean and sort so can do it in bulk, instead of line by
# line
# ----------------------------------------------------------------------

# LOOKUP Result
# {
#   "rs9442372:A:G": [
#     {
#       "bin_index": "chr1.L1.B1.L2.B1.L3.B1.L4.B1.L5.B1.L6.B1.L7.B2.L8.B1.L9.B1.L10.B1.L11.B1.L12.B1.L13.B2",
#       "annotation": {
#         "GenomicsDB": [
#           "ADSP_WGS",
#           "NG00027_STAGE1"
#         ],
#         "mapped_coordinates": {
#           "assembly": "GRCh38",
#           "location": 1083324,
#           "chromosome": "1",
#           "matched_variants": [
#             "1:1083324:A:G:rs9442372"
#           ]
#         }
#       },
#       "metaseq_id": "1:1018704:A:G",
#       "ref_snp_id": "rs9442372",
#       "is_adsp_variant": true,
#       "record_primary_key": "1:1018704:A:G_rs9442372"
#     }
#   ]
# }

#{"bin_index":"chr1.L1.B1.L2.B1.L3.B1.L4.B1.L5.B1.L6.B1.L7.B1.L8.B2.L9.B2.L10.B1.L11.B1.L12.B1.L13.B1","location":752566,"chromosome":"1","matched_variants":[{"metaseq_id":"1:752566:G:A","ref_snp_id":"rs3094315","genomicsdb_id":"1:752566:G:A_rs3094315"}]}

# {"location":817186,"chromosome":"1","matched_variants":["1:817186:G:A:rs3094315"],"assembly":"GRCh38"}

# if firstValueOnly == false, then {"1:2071765:G:A": [{},{}]}

sub updateDBMappedInput {
    my ( $self, $lookup, $mapping, $genomeBuild, $updateCheck ) = @_;

    $updateCheck //= 0;
    $genomeBuild //= $self->getArg('genomeBuild');
    my $mappedBuild = ( $genomeBuild eq 'GRCh37' ) ? 'GRCh38' : 'GRCh37';

    my ( $chromosome, $position, @alleles ) = split /:/,
      $$mapping[0]->{metaseq_id};
    my $row = $lookup->{row};

    my @matchedVariants;
    my $alleleMismatch = 0;
    my $mappedRefSnp;
    foreach my $variant (@$mapping) {
        if ( $self->getArg('mapThruMarker') ) {

            # make sure alleles match
            if ( exists $variant->{annotation}->{allele_match} ) {
                if ( !( $variant->{annotation}->{allele_match} )
                    || $variant->{annotation}->{allele_match} eq "false" )
                {
                    $alleleMismatch = 1;
                    # in case original one in file was deprecated
                    $mappedRefSnp = $variant->{ref_snp_id};
                    last;
                }
            }
        }

        my $ids = {
            ref_snp_id    => $variant->{ref_snp_id},
            genomicsdb_id => $variant->{record_primary_key},
            metaseq_id    => $variant->{metaseq_id}
        };

        push( @matchedVariants, $ids );
    }

    if ( !$alleleMismatch ) {
        my $currentCoordinates = {
            chromosome       => $chromosome,
            location         => int($position),
            bin_index        => $$mapping[0]->{bin_index},
            matched_variants => \@matchedVariants
        };

        $row->{$genomeBuild} = Utils::to_json($currentCoordinates);

        my $mappedCoordinates = $$mapping[0]->{annotation}->{mapped_coordinates}
          ;    # should be the same even if multiple rsIds for the metaseq
        if ($mappedCoordinates) {
            my $assembly = $mappedCoordinates->{assembly};
            if ($updateCheck) {
                $row->{$mappedBuild} = 'NULL'
                  ; # set to NULL / updateCheck assumes not in DB so overwrite any liftOver inferred info in the file
            }
            if ( $assembly eq $mappedBuild ) {
                $row->{$mappedBuild} = Utils::to_json($mappedCoordinates);
            }
        }

        # handle marker only mappings
        if ( $row->{chr} =~ /NA/ || $row->{metaseq_id} eq 'NULL' ) {
            $row->{chr}        = $chromosome;
            $row->{bp}         = int($position);
            $row->{metaseq_id} = $$mapping[0]->{metaseq_id};
        }
    }
    else { # mismatched allele for existing refsnp
        # update the metaseq id to chr:pos:ref:allele_from_file (to be added later)
        # so it can be treated as a novel variant
        $row->{chr}        = $chromosome;
        $row->{bp}         = int($position);
        $row->{metaseq_id} = join( ':', $chromosome, $position, $alleles[0], $row->{test_allele});
        $row->{marker} = $mappedRefSnp; 
    }
    return join( "\t", @$row{@INPUT_FIELDS} );
}

sub submitDBLookupQuery {
    my ( $self, $genomeBuild, $lookups, $file, $updateCheck ) = @_;
    $updateCheck //= 0;

    # only scalars can be passed to threads, so need to rebless plugin
    bless $self, 'GenomicsDBData::Load::Plugin::LoadVariantGWASResult';
    eval {

        my $recordHandler = VariantRecord->new(
            {
                gus_config_file => $self->{gus_config}->{$genomeBuild},
                genome_build    => $genomeBuild,
                plugin          => $self
            }
        );

        $recordHandler->setFirstValueOnly(
            $self->getArg('mapThruMarker') ? 0 : 1 );

        # for rsIds map to all possible values
        # so if mapThruMarker is TRUE, firstValueOnly is FALSE (0)

# $recordHandler->setAllowAlleleMismatches($self->getArg('allowAlleleMismatches'));

        my $mappings = $recordHandler->lookup( keys %$lookups );
        $SHARED_VARIABLE_SEMAPHORE->down;
        foreach my $vid ( keys %$mappings ) {
            next if ( !defined $mappings->{$vid} );    # "null" returned
            foreach my $lvalue ( @{ $lookups->{$vid} } ) {
                my $index = $lvalue->{index};
                $$file[$index] =
                  $self->updateDBMappedInput( $lvalue, $mappings->{$vid},
                    $genomeBuild, $updateCheck );
            }
        }
        $SHARED_VARIABLE_SEMAPHORE->up;
        $PROCESS_COUNT_SEMAPHORE->up;
        undef $mappings;    # b/c threads don't free memory until exit
        undef $lookups;
        undef $recordHandler;

        return "SUCCESS";
    } or do {
        $SHARED_VARIABLE_SEMAPHORE->up;
        $PROCESS_COUNT_SEMAPHORE->down;
        return $@;
    }
}

sub monitorThreads {
    my ( $self, $fail, $errors, @threads ) = @_;
    foreach (@threads) {
        if ( $_->is_joinable() ) {
            my $result = $_->join;
            if ( $result ne "SUCCESS" ) {
                push( @$errors, $result );
                $fail = 1;
            }
        }
    }
    return $fail, @$errors;
}

sub DBLookup {    # check against DB
    my ( $self, $inputFileName, $genomeBuild, $useMarker, $checkType ) = @_;

    $checkType //= 0
      ; # FINAL_CHECK overwrites the dbmapped file even if it exists, UPDATE_CHECK creates new file with .fc extenstion

    $genomeBuild //= $self->getArg('genomeBuild');

    $self->log("INFO: Querying existing DB mappings");
    my $msg =
        ( $checkType == $UPDATE_CHECK ) ? 'UPDATE'
      : ( $checkType == $FINAL_CHECK )  ? 'FINAL'
      :                                   'NORMAL';
    $self->log("INFO: Check Type: $msg");
    my $gusConfig =
      ( $self->{gus_config}->{$genomeBuild} )
      ? $self->{gus_config}->{$genomeBuild}
      : "default";
    $self->log(
        "INFO: Source Genome Build: $genomeBuild / GUS Config File: $gusConfig"
    );

    my $outputFileName =
      ( $checkType == $UPDATE_CHECK )
      ? "$inputFileName.dbmapped.uc"
      : "$inputFileName.dbmapped";

    if ( -e $outputFileName && !$self->getArg('overwrite') ) {
        if ( $checkType == $FINAL_CHECK ) {
            $self->log(
"INFO: Final Check -- will overwrite existing DBLookup file $outputFileName"
            );
        }
        else {
            $self->log("INFO: Using existing DBLookup file $outputFileName");
            return $outputFileName;
        }
    }

    my $linePtr;
    share($linePtr);
    open( my $fh, $inputFileName )
      || $self->error("Unable to open input file $inputFileName for reading");

    # for some reason File::Slurp read_file was buggy with some files
    chomp( my @lines : shared = <$fh> );

    #my @lines :shared = read_file($fh, chomp => 1);
    $fh->close();
    $linePtr = \@lines;

    my $header = $lines[0];
    chomp($header);
    my @fields = split /\t/, $header;

    my $lookupCount = 0;
    my $json        = JSON::XS->new();
    my $lookups;
    my $lineCount = 0;

    my @threads;
    my $fail = 0;
    my @errors;
    while ( my ( $index, $line ) = each @lines ) {
        next if ( $index == 0 );

        # I know, should be at end, but this way can count correctly & skip loop
        # processing where necessary
        $self->log("INFO: Processed $lineCount lines")
          if ( ++$lineCount % 100000 == 0 );

     # $self->log("DEBUG: Processed $lineCount lines") if ($lineCount % 5 == 0);

        # chomp $line;
        my @values = split /\t/, $line;
        my %row;
        @row{@fields} = @values;

# DBLookup may be called several times, if the lookup has already been done, don't do it again
# unless update or row{genomeBuild} does not include bin_index (info is from liftOver)
        if ( $row{$genomeBuild} ne 'NULL' ) {
            my $currentCoordinates = $json->decode( $row{$genomeBuild} );
            next if ( exists $currentCoordinates->{bin_index} );
        }

        my $variantId = undef;
        my $marker    = $row{marker};
        my $metaseqId = $row{metaseq_id};
        my $markerIsMetaseqId =
          ( $self->getArg('markerIsMetaseqId') || $marker =~ /.+:.+:.+:.+/ );

        if ( $self->getArg('mapThruMarker') || $useMarker ) {
            if ($markerIsMetaseqId) {
                $variantId = $marker;
            }
            else {
                $variantId = join( ":", $marker, $row{allele1}, $row{allele2} );
            }
        }
        else {
            if ( $row{chr} =~ /NA/ || $row{metaseq_id} eq 'NULL' ) {
                $variantId = join( ":", $marker, $row{allele1}, $row{allele2} );
            }
            else {
                $variantId = $metaseqId;
            }
        }

        $variantId =~ s/:N:N//g
          ;    # if two unknowns, drop alleles and just match marker or position

        my @lvalue =
          ( exists $lookups->{$variantId} ) ? @{ $lookups->{$variantId} } : ();
        my $nlvalue = { index => $index, line => $line, row => \%row };
        push( @lvalue, $nlvalue );

        #$self->error(Dumper(\@lvalue)) if (exists $lookups->{$variantId});
        $lookups->{$variantId} = \@lvalue;

        # $self->error(Dumper($lookups->{$variantId}));

        if ( ++$lookupCount % 10 == 0 ) {
            my $debug_vars = join(',', keys %$lookups);
            $self->log("DEBUG: " . $lookupCount . " -> " . '"' . $debug_vars . '"');
        #if ( ++$lookupCount % 10000 == 0 ) {
            $PROCESS_COUNT_SEMAPHORE->down;
            my $thread =
              threads->create( \&submitDBLookupQuery, $self, $genomeBuild,
                $lookups, $linePtr, ( $checkType == $UPDATE_CHECK ) );
            undef $lookups;
            push( @threads, $thread );
            ( $fail, @errors ) =
              $self->monitorThreads( $fail, \@errors, @threads );
        }    # end do lookup
    }    # end iterate over file

    # residuals
    # $self->log("DEBUG: lookupCount = $lookupCount");
    if ($lookups) {
        $self->log("INFO: Processing Residuals");

# begin debug block
# my $it = natatime 100, keys %$lookups;
# my $sliceCount = 0;
# while (my @vals = $it->()) {
#     $self->log("DEBUG: Slice " . ++$sliceCount . " - variants = '" . join(',', @vals) ."'");
# }
# $self->error("DEBUG: DONE");
# end debug block

        $PROCESS_COUNT_SEMAPHORE->down;
        my $thread =
          threads->create( \&submitDBLookupQuery, $self, $genomeBuild,
            $lookups, $linePtr, ( $checkType == $UPDATE_CHECK ) );
        undef $lookups;
        push( @threads, $thread );
        ( $fail, @errors ) = $self->monitorThreads( $fail, \@errors, @threads );
    }

    # catch any still running
    while ( my @running = threads->list(threads::running) ) {
        ( $fail, @errors ) = $self->monitorThreads( $fail, \@errors, @threads );
    }

    # residuals after no more are running
    ( $fail, @errors ) = $self->monitorThreads( $fail, \@errors, @threads );

    $self->error( "Parallel DB Query failed: " . Dumper( \@errors ) )
      if ($fail);
    $self->log("DONE: Queried $lineCount variants");

    $lineCount = 0;
    $self->log(
        "INFO: Creating $outputFileName file with ${genomeBuild} database lookups");
    open( my $ofh, '>', $outputFileName )
      || $self->error(
        "Unable to open cleaned input file $outputFileName for updating");
    foreach my $line (@lines) {
        print $ofh "$line\n";
        $self->log("INFO: Wrote $lineCount lines")
          if ( ++$lineCount % 500000 == 0 );
    }
    $ofh->close();

    # just to cover bases on garbage collection
    undef @lines;
    undef @threads;

    $self->log("DONE: Wrote $lineCount lines");

    $self->sortCleanedInput( $self->{working_dir}, $outputFileName );
    return $outputFileName;
}

# ----------------------------------------------------------------------
# liftOver
# lift over
# 1) translate to bed file
#    1.1) lookup markerOnly variants in GRCh37 AnnotatedVDB and map when possible
# 2) liftOver
# 3) Remap anything not lifted over
# 4) reassembly liftedOver input file
# if just updating liftover flags in GRCh37, generate and return result
# file name only
# ----------------------------------------------------------------------

sub liftOver {
    my ( $self, $updateCoordsOnly ) = @_;

    my $file = $self->{root_file_path} . $self->getArg('file');
    $self->log("INFO: Beginning LiftOver process on $file");

    my $rootFilePath =
      PluginUtils::createDirectory( $self, $self->getArg('fileDir'), "GRCh38" );
    my $workingDir = PluginUtils::createDirectory( $self, $rootFilePath,
        $self->getArg('sourceId') );
    my $resultFileName =
      $workingDir . "/" . $self->getArg('sourceId') . "-input.txt";

    return $resultFileName if ($updateCoordsOnly);

    # do liftOver
    my $inputFileName    = $self->cleanAndSortInput($file);
    my $dbmappedFileName = $self->DBLookup($inputFileName);

    my ( $nUnliftedVariants, $sourceBedFileName ) =
      $self->input2bed($dbmappedFileName);
    $self->log("Number of unlifted variants found = $nUnliftedVariants");
    if ( $nUnliftedVariants > 0 ) {
        my $mappedBedFileName = $self->runUCSCLiftOver($sourceBedFileName);

        # find issues
        my ( $cleanedLiftOverFileName, $unmappedLiftOverFileName ) =
          $self->cleanMappedBedFile( $mappedBedFileName, $sourceBedFileName,
            "liftOver" );

        # handle unmapped & add in
        #   run against NCBI Remap
        my $remapFileName = $self->remapBedFile($unmappedLiftOverFileName);
        my ( $cleanedRemapFileName, $unmappedRemapFileName ) =
          $self->cleanMappedBedFile( $remapFileName, $unmappedLiftOverFileName,
            "remap" );

        # lookup remap-unmapped in GRCh38 database based on markers
        my $residualUnmappedFileName =
          $self->bed2input( $unmappedRemapFileName, undef, $INCLUDE_MARKERS,
            $NEW_FILE );
        my $residualDBMappedFile =
          $self->DBLookup( $residualUnmappedFileName, 'GRCh38', $USE_MARKER );
        my $markerOnlyDBMappedFile =
          $self->DBLookup( "$dbmappedFileName.unmapped.markerOnly",
            'GRCh38', $USE_MARKER );

        # dbmapping input, ucsc lift over, remap, remap-unmapped
        my ( $r, $fromDBLookup ) =
          $self->liftOverFromDBMappedFile( $dbmappedFileName, $resultFileName );
        $self->liftOverFromDBMappedFile( $residualDBMappedFile,
            $resultFileName, $APPEND );
        $self->liftOverFromDBMappedFile( $markerOnlyDBMappedFile,
            $resultFileName, $APPEND, 'GRCh38' );
        $self->bed2input( $cleanedRemapFileName, $resultFileName,
            $DROP_MARKERS, $APPEND );    # append
        $self->bed2input( $cleanedLiftOverFileName, $resultFileName,
            $DROP_MARKERS, $APPEND );

        # summarize counts
        my $inputCount = Utils::fileLineCount($dbmappedFileName) - 1;
        my $unmappedCount =
          Utils::countOccurrenceInFile( $residualDBMappedFile, 'genomicsdb_id',
            1 ) +
          Utils::countOccurrenceInFile( $markerOnlyDBMappedFile,
            'genomicsdb_id', 1 );        # find lines missing the pattern
        my $mappedCount     = Utils::fileLineCount($resultFileName) - 1;
        my $fromUSCliftOver = Utils::fileLineCount($cleanedLiftOverFileName);
        my $fromRemap       = Utils::fileLineCount($cleanedRemapFileName);
        my $fromMarker =
          Utils::countOccurrenceInFile( $residualDBMappedFile, 'genomicsdb_id' )
          - 1 + Utils::countOccurrenceInFile( $markerOnlyDBMappedFile,
            'genomicsdb_id' ) - 1;

        my $counts = {
            mapped                     => $mappedCount,
            unmapped                   => $unmappedCount,
            GRCh38_marker_AnnotatedVDB => $fromMarker,
            GRCh37_AnnotatedVDB        => $fromDBLookup,
            liftOver                   => $fromUSCliftOver,
            Remap                      => $fromRemap,
            original_input             => $inputCount,
            percent_mapped             => $mappedCount / $inputCount,
            percent_unmapped           => $unmappedCount / $inputCount
        };

        $self->log( "INFO: DONE with liftOver " . Dumper($counts) );
    }
    else {
        my $fromMarker =
          Utils::countOccurrenceInFile( "$dbmappedFileName.unmapped.markerOnly",
            'genomicsdb_id' ) - 1;
        my $mappedCount =
          Utils::countOccurrenceInFile( "$dbmappedFileName", 'genomicsdb_id' )
          - 1 - $fromMarker;
        $self->liftOverFromDBMappedFile( $dbmappedFileName, $resultFileName );

        if ( $fromMarker > 0 ) {
            my $markerOnlyDBMappedFile =
              $self->DBLookup( "$dbmappedFileName.unmapped.markerOnly",
                'GRCh38' );
            $self->liftOverFromDBMappedFile( $markerOnlyDBMappedFile,
                $resultFileName, $APPEND, 'GRCh38' );
            my $unmappedCount =
              Utils::countOccurrenceInFile( $markerOnlyDBMappedFile,
                'genomicsdb_id', 1 );    # find lines missing the pattern
            $self->log("Marker-only Unmapped: $unmappedCount");
        }
        $self->log(
"DONE: Done with liftOver / $mappedCount variants mapped via DB query / markerOnly = $fromMarker"
        );
    }

    $self->sortCleanedInput( $workingDir, $resultFileName );

    return $resultFileName;
}

sub runUCSCLiftOver {
    my ( $self, $sourceBedFile ) = @_;
    my $chainFile = $self->getArg('liftOverChainFile');
    $self->log(
"INFO: Performing UCSC liftOver on $sourceBedFile using chain: $chainFile"
    );

    # USAGE: liftOver oldFile map.chain newFile unMapped
    my $filePath          = $self->{working_dir} . "/liftOver/";
    my $filePrefix        = $self->{adj_source_id};
    my $errorFile         = $sourceBedFile . ".unmapped";
    my $mappedBedFileName = $filePath . $filePrefix . "-GRCh38.bed";

    if ( -e $mappedBedFileName && !$self->getArg('overwrite') ) {
        $self->log("INFO: Using existing liftOver file: $mappedBedFileName");
        return $mappedBedFileName;
    }

    my @cmd = (
        'liftOver',         $sourceBedFile, $chainFile,
        $mappedBedFileName, $errorFile
    );

    $self->log( "INFO: Running liftOver: " . join( ' ', @cmd ) );
    my $status = qx(@cmd);

    $self->log("INFO: Done with UCSC liftOver");
    my $nUnmapped = Utils::fileLineCount($errorFile);
    $self->log(
        "WARNING: Not all variants mapped, see: $errorFile (n = $nUnmapped)")
      if ( $nUnmapped > 0 );
    return $mappedBedFileName;
}

sub liftOverFromDBMappedFile {
    my ( $self, $inputFileName, $outputFileName, $append, $inputGenomeBuild ) =
      @_;
    $append           //= 0;
    $inputGenomeBuild //= 'GRCh37';

    $self->log("INFO: Finding DB Mapped variants in file $inputFileName");

    my $lineCount = 0;

    if ( -e $outputFileName && ($append) ) {
        $self->log(
"INFO: DB Mapping liftOver - Appending DB mappings to result file: $outputFileName"
        );
    }
    else {
        $self->log(
"INFO: DB Mapping liftOver - Creating result file: $outputFileName from DB mapped file $inputFileName"
        );
    }

    my $ofh;
    if ($append) {
        open( $ofh, '>>', $outputFileName )
          || $self->error("Unable to create $outputFileName for writing");
    }
    else {
        open( $ofh, '>', $outputFileName )
          || $self->error("Unable to create $outputFileName for writing");
        print $ofh join( "\t", @INPUT_FIELDS ) . "\n";
    }
    open( my $fh, '<', $inputFileName )
      || $self->error("Unable to create $outputFileName for writing");
    my $header = <$fh>;

    my $json = JSON::XS->new();
    while ( my $line = <$fh> ) {
        chomp $line;
        my @values = split /\t/, $line;
        my %row;
        @row{@INPUT_FIELDS} = @values;

        if ( $row{GRCh37} eq 'NULL' and $inputGenomeBuild eq 'GRCh37' ) {
            my $currentCoordinates = {
                chromosome => $row{chr},
                location   => int( $row{bp} ),
                metaseq_id => $row{metaseq_id}
            };
            $row{GRCh37} = Utils::to_json($currentCoordinates);
        }

        # otherwise leave NULL

        my $mappingStr = $row{GRCh38};
        next if ( $mappingStr eq 'NULL' );

# lookup could have one of two formats
# from GRCh37 DB
# {"location":817186,"chromosome":"1","matched_variants":["1:817186:G:A:rs3094315"],"assembly":"GRCh38"}
# based on marker from GRCh38 DB
# {"bin_index":"chr6.L1.B3.L2.B2.L3.B1.L4.B2.L5.B1.L6.B2.L7.B1.L8.B1.L9.B1.L10.B2.L11.B2.L12.B1.L13.B2","location":170213663,"chromosome":"6","matched_variants":[{"metaseq_id":"6:170213663:G:C","ref_snp_id":"rs6456179","genomicsdb_id":"6:170213663:G:C:rs6456179"}]}

        my $mapping    = $json->decode($mappingStr);
        my $chromosome = $mapping->{chromosome};
        $chromosome =~ s/chr//g;
        $row{chr} = $chromosome;
        $row{bp}  = int( $mapping->{location} );
        my @matchedVariants = @{ $mapping->{matched_variants} };
        foreach my $mv (@matchedVariants) {
            if ( ref $mv eq ref {} ) {    # check if hash
                $row{metaseq_id} = $mv->{metaseq_id};
                $row{marker} =
                  ( exists $mv->{ref_snp_id} ) ? $mv->{ref_snp_id} : 'NULL';
            }
            else {
                # can't infer metaseq_id from PK b/c some may be encoded
                # & don't want to do allele logic again so only regenerate
                # if easy to infer
                if ( $row{metaseq_id} ne 'NA' and $row{metaseq_id} ne 'NULL' ) {
                    my ( $oC, $oP, $ref, $alt ) = split /:/, $row{metaseq_id};
                    $row{metaseq_id} =
                      join( ':', $chromosome, $row{bp}, $ref, $alt );
                }
                my @idElements = split /:/, $mv;
                $row{marker} =
                  ( $idElements[-1] =~ m/^rs/ ) ? $idElements[-1] : 'NULL';
            }
        }

        print $ofh join( "\t", @row{@INPUT_FIELDS} ) . "\n";
        $self->log("INFO: Wrote $lineCount lines")
          if ( ++$lineCount % 500000 == 0 );
    }
    $ofh->close();
    $fh->close();
    $self->log("INFO: Wrote $lineCount lines");
    $self->log(
        "DONE: Adding $inputFileName to liftOver final output: $outputFileName"
    );

    return $outputFileName, $lineCount;
}

sub remapBedFile {
    my ( $self, $inputFileName ) = @_;

    my $filePrefix = $self->{adj_source_id};
    my $remapRootDir =
      PluginUtils::createDirectory( $self, $self->{working_dir}, "remap" );

    if ( -e $inputFileName ) {
        my $lineCount = Utils::fileLineCount($inputFileName);
        $self->log("WARNING: Remapping $inputFileName ($lineCount lines)");
        $self->error(
            "Too many unmapped variants in $inputFileName - $lineCount")
          if ( $lineCount > 50000 );

#output file - remap instead of liftOver dir, GRCh38 instead of GRCh37, remapped instead of unmapped
        ( my $outputFileName = $inputFileName ) =~ s/-GRCh37/-GRCh38/g;
        $outputFileName                         =~ s/liftOver/remap/g;
        $outputFileName                         =~ s/unmapped/remapped/g;

        if ( -e $outputFileName && !$self->getArg('overwrite') ) {
            $self->log("INFO: Remapped file $outputFileName already exists");
            return $outputFileName;
        }

        my ( $fromAssembly, $destAssembly ) = split /\|/,
          $self->getArg('remapAssemblies');

        my @cmd = (
            'remap_api.pl',  '--mode',
            'asm-asm',       '--in_format',
            'bed',           '--out_format',
            'bed',           '--from',
            $fromAssembly,   '--dest',
            $destAssembly,   '--annotation',
            $inputFileName,  '--annot_out',
            $outputFileName, '--report_out',
            $outputFileName . ".report"
        );

        $self->log( "INFO: Running NCBI Remap: " . join( ' ', @cmd ) );
        my $status = qx(@cmd);
        $self->log("INFO: Remap status: $status");
        if ( $status =~ m/Saving.+report/ ) {
            $self->log("INFO: Done with NCBI Remap");
            return $outputFileName;
        }
        else {
            $self->error("NCBI Remap of $inputFileName failed");
        }
    }
    else {
        $self->error(
            "Error running NCBI Remap: input file $inputFileName does not exist"
        );
    }
}

sub cleanMappedBedFile {
    my ( $self, $mappedBedFileName, $sourceBedFileName, $targetDir ) = @_;
    my $workingDir =
      PluginUtils::createDirectory( $self, $self->{working_dir}, $targetDir );

    $self->log("INFO: Cleaning mapped files");
    $self->log(
"INFO: Comparing $targetDir input $sourceBedFileName to mapped file $mappedBedFileName"
    );

    # generate two files - 1) .cleaned 2) .unmapped
    my $unmappedFileName = $mappedBedFileName . ".unmapped";
    $unmappedFileName =~ s/-GRCh38/-GRCh37/g;
    my $cleanedMappedFileName = $mappedBedFileName . ".cleaned";

    if ( -e $cleanedMappedFileName && !( $self->getArg('overwrite') ) ) {
        $self->log(
            "INFO: Using existing cleaned mapping file: $cleanedMappedFileName"
        );
        return $cleanedMappedFileName, $unmappedFileName;
    }

    # basically, want to identify the following problems:
    # 1) still unmapped
    # 2) duplicates
    # 3) mapped against contigs
    # 4) suprisingly enough, wrong chromosome

    # load $ofh into hash
    my $variants;
    open( my $ofh, $sourceBedFileName )
      || $self->error(
        "Unable to open source bed file: $sourceBedFileName for reading");
    while ( my $line = <$ofh> ) {
        chomp($line);
        my @values =
          ( $targetDir eq 'liftOver' )
          ? split / /, $line
          : split /\t/, $line;
        my $key = $values[3];
        $variants->{$key}->{original_line} = $line;
        $variants->{$key}->{status}        = 'none';
    }
    $ofh->close();

    my $altCount        = 0;
    my $wrongCount      = 0;
    my $mappedCount     = 0;
    my $duplicateCount  = 0;
    my $parsedLineCount = 0;

    # for some reason File::Slurp read_file was buggy with some liftOver output
    open( my $fh, $mappedBedFileName )
      || $self->error("Unable to open mapped bed file $mappedBedFileName: $!");
    chomp( my @mappedLines = <$fh> );
    $fh->close();

    while ( my ( $lineCount, $line ) = each @mappedLines ) {
        $parsedLineCount = $lineCount;

        my @values = split /\t/, $line;
        my $key    = $values[3];
        my ( $loc, $stats ) = split /\|/, $key;

        my $isAltChrm = ( $values[0] =~ m/_/g ) ? 1 : 0;
        if ($isAltChrm) {
            $altCount++;
            $self->log( "INFO: Location $loc mapped to contig - " . $values[0] )
              if $self->getArg('veryVerbose');
        }

        my ( $origChrm, @other ) = split /:/, $loc;
        my $isWrongChrm =
          ( $values[0] ne "chr$origChrm" && !$isAltChrm ) ? 1 : 0;
        $isWrongChrm =
          ( $loc =~ m/lookup/ )
          ? 0
          : $isWrongChrm;    # b/c we didn't have the original chrm info
        if ($isWrongChrm) {
            $wrongCount++;
            $self->log( "INFO: Location $loc mapped to wrong chromosome - "
                  . $values[0] )
              if $self->getArg('veryVerbose');
        }

        my $status =
          ( exists $variants->{$key} )
          ? $variants->{$key}->{status}
          : undef;

        $self->error(
            "Variant $key in $targetDir file but not in $targetDir input.")
          if ( !$status );

        if ( $status eq 'none' ) {
            $mappedCount++ if ( !$isAltChrm && !$isWrongChrm );
            $variants->{$key}->{status} =
                ($isAltChrm)   ? "alt|$lineCount"
              : ($isWrongChrm) ? "wrong_chrm|$lineCount"
              :                  "mapped|$lineCount";
        }
        else {
            if ( $status =~ m/mapped/ ) {
                if ($isAltChrm) {
                    $self->log(
"INFO: Location $loc already mapped to primary assembly - ignoring contig mapping"
                    ) if $self->getArg('veryVerbose');
                }
                elsif ($isWrongChrm) {
                    $self->log(
"INFO: Location $loc already mapped to primary assembly - ignoring wrong mapping"
                    ) if $self->getArg('veryVerbose');
                }
                else {
                    $duplicateCount += 2;    # original mapped + new
                    $mappedCount--;
                    my ( $dupStatus, $dupLine ) = split /\|/, $status;
                    $variants->{$key}->{status} = "dup|$dupLine,$lineCount";
                }
            }    # end already mapped
            if ( $status =~ m/alt/ ) {
                if ($isWrongChrm) {
                    $self->log(
"INFO: Location $loc already mapped to contig - ignoring wrong mapping"
                    ) if $self->getArg('veryVerbose');
                }
                elsif ($isAltChrm) {
                    $self->log(
"INFO: Location $loc already mapped to contig - ignoring contig mapping"
                    ) if $self->getArg('veryVerbose');
                }
                else {
                    $mappedCount++;
                    $self->log(
"INFO: Location $loc - replacing contig mapping with mapping to primary assembly"
                    ) if $self->getArg('veryVerbose');
                    $variants->{$key}->{status} = "mapped|$lineCount";
                }
            }
            if ( $status =~ m/wrong/ ) {
                if ($isWrongChrm) {
                    $variants->{$key}->{status} = $status . ",$lineCount";
                }
                elsif ($isAltChrm) {
                    $self->log(
"INFO: Location $loc mapped to contig - replacing wrong chromosome flag"
                    ) if $self->getArg('veryVerbose');
                    $variants->{$key}->{status} = "alt|$lineCount";
                }
                else {
                    $mappedCount++;
                    $self->log(
"INFO: Location $loc mapped to primary assembly - replacing wrong chromosome flag"
                    ) if $self->getArg('veryVerbose');
                    $variants->{$key}->{status} = "mapped|$lineCount";
                }
            }
            if ( $status =~ m/dup/ ) {
                if ($isAltChrm) {
                    $self->log(
"INFO: Location $loc already mapped to primary assembly - ignoring contig mapping"
                    ) if $self->getArg('veryVerbose');
                }
                elsif ($isWrongChrm) {
                    $self->log(
"INFO: Location $loc already mapped to primary assembly - ignoring wrong mapping"
                    ) if $self->getArg('veryVerbose');
                }
                else {
                    $duplicateCount++;
                    $variants->{$key}->{status} = $status . ",$lineCount";
                }
            }
        }
    }

    $parsedLineCount++;    # started at 0
    my $totalCount = $mappedCount + $duplicateCount + $altCount + $wrongCount;
    my $debugDiff  = $totalCount - $parsedLineCount;
    $self->log(
"INFO: Total = $totalCount (Mapped = $mappedCount | Duplicate = $duplicateCount | Contigs = $altCount | Wrong = $wrongCount)"
    );

    my $ufh;
    if ( -e $unmappedFileName )
    {    # file already exists append; e.g. add to liftOver unmapped
         # remove # lines in umapped file
        my @cmd = (
            'perl', '-n', '-i.bak', '-e', "'print unless m/^#/'",
            $unmappedFileName
        );
        qx(@cmd);

        #my $cmd = `grep -v "^#" $unmappedFileName > $unmappedFileName.tmp`;
        # $cmd = `mv $unmappedFileName.tmp $unmappedFileName`;
        open( $ufh, '>>', $unmappedFileName )
          || $self->error("Unable to open $unmappedFileName for appending");
    }
    else {
        open( $ufh, '>', $unmappedFileName )
          || $self->error("Unable to create $unmappedFileName for writing");
    }

    $self->log("INFO: Writing cleaned bed file $cleanedMappedFileName");
    open( my $cfh, '>', $cleanedMappedFileName )
      || $self->error("Unable to create $cleanedMappedFileName for writing");
    foreach my $key ( keys %$variants ) {
        my $statusStr = $variants->{$key}->{status};
        my ( $status, $lineNum ) = split /\|/, $statusStr;
        if ( $status eq 'mapped' ) {
            print $cfh $mappedLines[$lineNum] . "\n";
        }
        else {    # includes 'none's not in the remap file
            next if ( $status eq 'none' );    # already in unmapped file
            my $oLine = $variants->{$key}->{original_line};

            # $self->error($oLine);
            $oLine =~ s/ /\t/g;           # b/c original bed file is space delim
            $oLine =~ s/\|/:$status\|/;
            print $ufh $oLine . "\n";
        }
    }

    $cfh->close();
    $ufh->close();

    # some garbage collection
    undef @mappedLines;
    undef $variants;

    $self->log("INFO: Done checking $targetDir output");

    return $cleanedMappedFileName, $unmappedFileName;
}

sub bed2input {
    my ( $self, $bedFileName, $targetFileName, $inclMarkers, $append ) = @_;
    $append //= 0;
    if ( !$targetFileName ) {
        $targetFileName = "$bedFileName";
        $targetFileName =~ s/\.bed/-input\.txt/g;
    }

    if ( -e $targetFileName && !$self->getArg('overwrite') && !$append ) {
        $self->log("INFO: Using existing bed2input file: $targetFileName");
        return $targetFileName;
    }
    else {
        if ( -e $targetFileName && ($append) ) {
            $self->log(
"INFO: bed2input - Appending bed file $bedFileName to input file: $targetFileName"
            );
        }
        else {
            $self->log(
"INFO: bed2input - Creating input file: $targetFileName from bed file $bedFileName"
            );
        }

        my $ofh;
        if ($append) {
            open( $ofh, '>>', $targetFileName )
              || $self->error("Unable to open $targetFileName for appending");
        }
        else {
            open( $ofh, '>', $targetFileName )
              || $self->error("Unable to create $targetFileName for writing");
            print $ofh join( "\t", @INPUT_FIELDS ) . "\n";
        }

        my $json = JSON::XS->new;
        open( my $fh, $bedFileName )
          || $self->error("Unable to open $bedFileName for reading");
        my $lineCount = 0;
        while ( my $line = <$fh> ) {
            chomp $line;
            my @values  = split /\t/, $line;
            my $newChrm = $values[0];

            my ( $name, $statStr ) = split /\|/, $values[3];
            my $stats = $json->decode($statStr);

            my @printValues;
            foreach my $field (@INPUT_FIELDS) {
                if ( $field eq 'bp' ) {
                    push( @printValues, $values[2] );
                }
                elsif ( $field eq 'metaseq_id' ) {
                    my ( $oldChrm, $oldPos, $ref, $alt ) = split /:/,
                      $stats->{metaseq_id};
                    $self->error(
"Chromosome mismatch for $newChrm (new) != $oldChrm (old): $line"
                    ) if ( 'chr' . $oldChrm ne $newChrm );
                    my $metaseqId =
                      join( ":", $oldChrm, $values[2], $ref, $alt );
                    push( @printValues, $metaseqId );
                }
                elsif ( $field eq 'marker' )
                { # rs ids are no longer valid unless quirky metaseq or specified by params
                    if ($inclMarkers) {
                        push( @printValues, $stats->{$field} );
                    }
                    else {
                        push( @printValues, 'NULL' );
                    }
                }
                elsif (
                    (
                           $field eq 'gwas_flags'
                        || $field eq 'restricted_stats_json'
                        || $field eq 'GRCh37'
                        || $field eq 'GRCh38'
                    )
                    && $stats->{$field} ne 'NULL'
                  )
                {
                    push( @printValues, Utils::to_json( $stats->{$field} ) );
                }
                else {
                    push( @printValues, $stats->{$field} );
                }
            }

            print $ofh join( "\t", @printValues ) . "\n";

            $self->log("INFO: Wrote $lineCount lines from $bedFileName")
              if ( ++$lineCount % 500000 == 0 );
        }
        $fh->close();
        $ofh->close();
        $self->log("INFO: Wrote $lineCount lines from $bedFileName");
        return $targetFileName;
    }
}

sub input2bed {

    # extract fields not liftedOver by DB mapping and place in a bed file
    my ( $self, $inputFileName ) = @_;

    unless ( -e $inputFileName ) {
        $self->error("input2bed - Input file $inputFileName not found");
    }

    my $filePrefix = $self->{adj_source_id};
    my $filePath =
      PluginUtils::createDirectory( $self, $self->{working_dir}, "liftOver" );
    my $bedFileName = $filePath . "/" . $filePrefix . "-GRCh37.bed";
    my $markerOnlyFileName =
      $inputFileName . ".unmapped.markerOnly";    # b/c db look up

    $self->log(
"INFO: input2bed - Creating bed file $bedFileName from input file $inputFileName"
    );
    if ( -e $bedFileName && ( !$self->getArg('overwrite') ) ) {
        $self->log("INFO: Using existing input2bed file $bedFileName");
        my $lineCount = Utils::fileLineCount($bedFileName);
        return $lineCount, $bedFileName;
    }

    open( my $bedFh, '>', $bedFileName )
      || $self->error("Unable to create $bedFileName for writing");
    $bedFh->autoflush(1);

# any fields ID'd by marker only have to be put aside & tacked back on the liftOver result
    open( my $moFh, '>', $markerOnlyFileName )
      || $self->error(
        "Unable to create marker only $markerOnlyFileName for writing");
    $moFh->autoflush(1);

    open( my $fh, $inputFileName )
      || $self->error("Unable to open input file $inputFileName for reading");
    my $header = <$fh>;
    print $moFh $header;
    chomp($header);
    my @fields = split /\t/, $header;

    my $json = JSON::XS->new();

# INPUT fields: chr bp allele1 allele2 metaseq_id marker freq1 pvalue neg_log10_p display_p gwas_flags test_allele restricted_stats_json
# OUTPUT: chrom start end name {everything else in JSON} / no header
    my $lineCount           = 0;
    my $bedFileLineCount    = 0;
    my $markerOnlyLineCount = 0;
    my %row;
    while ( my $line = <$fh> ) {
        chomp $line;
        my @values = split /\t/, $line;
        @row{@fields} = @values;

        next if ( $row{GRCh38} ne 'NULL' );    # already lifted over

        my $chr      = "chr" . $row{chr};
        my $position = $row{bp};
        my $start    = $position - 1;          # shift to 0-based
        my $end      = $position;
        my $name = ( $chr =~ m/NA/g ) ? $row{marker} : $row{chr} . ":$position";

        $row{gwas_flags} = $json->decode( $row{gwas_flags} )
          if ( $row{gwas_flags} ne 'NULL' );
        $row{restricted_stats_json} =
          $json->decode( $row{restricted_stats_json} )
          if ( $row{restricted_stats_json} ne 'NULL' );
        $row{GRCh37} = $json->decode( $row{GRCh37} )
          if ( $row{GRCh37} ne 'NULL' );
        foreach my $f (qw(freq1 pvalue neg_log10_p display_p)) {
            $row{$f} = Utils::toNumber( $row{$f} );
        }

        my $infoStr = Utils::to_json( \%row );
        if ( $chr =~ m/NA/g || ( $row{metaseq_id} eq "NULL" ) ) {
            print $moFh "$line\n";
            $markerOnlyLineCount++;
        }
        else {
            print $bedFh join( " ", $chr, $start, $end, "$name|$infoStr" )
              . "\n";
            $bedFileLineCount++;
        }

        if ( ++$lineCount % 500000 == 0 ) {
            $self->log("INFO: Parsed $lineCount lines");
        }
    }
    $self->log("INFO: Parsed $lineCount lines");
    $fh->close();
    $bedFh->close();
    $moFh->close();

    my $tc = $markerOnlyLineCount + $bedFileLineCount;
    $self->log(
        "INFO: Found $tc unmapped variants / marker only = $markerOnlyLineCount"
    );
    return $bedFileLineCount, $bedFileName;
}

# ----------------------------------------------------------------------
# preprocess
# ----------------------------------------------------------------------

sub preprocess {
    my ($self)        = @_;
    my $file          = $self->{root_file_path} . $self->getArg('file');
    my $inputFileName = $self->cleanAndSortInput($file);

    my $filePrefix = $self->{adj_source_id};
    my $filePath =
      PluginUtils::createDirectory( $self, $self->{working_dir}, "preprocess" );
    PluginUtils::setDirectoryPermissions($self, $filePath, "g+w");

    my ( $novelVariantVcfFile, $novelVariantCount ) =
      $self->extractNovelVariants( $inputFileName, "$filePath/$filePrefix" );
    if ( !$self->getArg('test') ) {
        my $foundNovelVariants =
          $self->annotateNovelVariants($novelVariantVcfFile);
        if ($foundNovelVariants) {    # > 0
            $self->log(
"INFO: Executing final check that all novel variants were annotated and loaded"
            );
            ( $novelVariantVcfFile, $novelVariantCount ) =
              $self->extractNovelVariants( $inputFileName,
                "$filePath/$filePrefix", $FINAL_CHECK );
            $self->error(
"$novelVariantCount Novel Variants found after annotation & load completed. See $novelVariantVcfFile"
            ) if ( $novelVariantCount > 1 );
        }
    }
    else {
        $self->log(
"WARNING: --test flag provided; skipping novel variant annotation and load"
        );
    }
    $self->log("DONE: Preprocessing completed");
}

sub getValidVepVariants {
    my ( $self, $fileName ) = @_;
    ( my $validVcfFileName = $fileName ) =~ s/vcf/valid.vcf/g;
    open( my $fh, $fileName )
      || $self->error("Unable to open $fileName to extract valid variants");
    open( my $ofh, '>', $validVcfFileName )
      || $self->error(
        "Unable to create valid variant VCF $validVcfFileName for writing");

    # my @VCF_FIELDS = qw(#CHROM POS ID REF ALT QUAL FILTER INFO);

    while ( my $line = <$fh> ) {
        chomp($line);
        next if ( $line =~ m/\?/ );    # skip variants w/questions marks
        my ( $chrm, $pos, $id, $ref, $alt, @other ) = split /\t/, $line;
        next
          if ( length($ref) > 50 || length($alt) > 50 );  # skip long INDELS/SVs
        next if ( $chrm eq "NULL" );
        next if ( $line =~ /:N:N/ );    # completely unknown alleles
        print $ofh "$line\n";
    }

    $fh->close();
    $ofh->close();
    return $validVcfFileName;
}

sub annotateNovelVariants {
    my ( $self, $fileName ) = @_;

    my $lineCount = `wc -l < $fileName`;
    if ( $lineCount > 1 ) {
        $self->log("INFO: Annotating variants in: $fileName");
        my ( $accession, @other ) = split /_/, $self->{adj_source_id};
        my $preprocessDir =
            "$accession/"
          . $self->getArg('genomeBuild') . "/"
          . $self->{adj_source_id}
          . "/preprocess/";

        # remove invalid variants (i.e., w/?) before running thru VEP
        # and really long INDELs
        my $validVcfFileName = $self->getValidVepVariants($fileName);
        $lineCount = `wc -l < $validVcfFileName`;
        if ( $lineCount > 1 ) {
            if ( $self->getArg('skipVep') ) {
                $self->log(
                    "INFO: --skipVep flag provided, skipping VEP annotation");
            }
            else {
                # strip local path, make relative to accession folder
                my $vepInputFileName =
                  $preprocessDir . basename($validVcfFileName);
                $self->{annotator}->runVep("$vepInputFileName");
            }
            $self->{annotator}
              ->loadVepAnnotatedVariants("$validVcfFileName.vep.json.gz");
        }
        else {
            $self->log(
"WARNING: No 'VEP valid' variants found; skipping VEP annotation"
            );
        }

        $fileName = $validVcfFileName if $self->getArg('sourceId') =~ m/NHGRI/;
        $self->{annotator}->loadVariantsFromVCF("$fileName")
          ; # can just pass original VCF file as it will skip anything already loaded
        $self->{annotator}->loadCaddScores( $fileName, $preprocessDir );
    }
    else {
        $self->log("INFO: No novel variants found in: $fileName");
    }
    return ( $lineCount > 1 );
}

sub extractNovelVariants {
    my ( $self, $file, $filePrefix, $finalCheck ) = @_;

    $self->log("INFO: Extracting novel variants from DB Mapped file: $file");
    $finalCheck //= 0;    # final check remaps against db, overwriting existing dbmapping file

    my $genomeBuild = $self->getArg('genomeBuild');
    my $useMarker = ( $self->getArg('mapThruMarker') && !$self->getArg('markerIsMetaseqId') );

    my $dbmappedFileName =
      $self->DBLookup( $file, $genomeBuild, $useMarker, $finalCheck );

    open( my $fh, $dbmappedFileName )
      || $self->error(
        "Unable to open DB Mapped file $dbmappedFileName for reading");
    my $header = <$fh>;

    my $novelVariantVCF = ($finalCheck) ? "$filePrefix-novel-final-check.vcf" : "$filePrefix-novel.vcf";
    if ( -e $novelVariantVCF && !( $self->getArg('overwrite') ) ) {
        $self->log("INFO: Using existing novel variant VCF: $novelVariantVCF");
        return $novelVariantVCF;
    }

    $self->log("INFO: Writing novel variants to $novelVariantVCF");
    open( my $vfh, '>', $novelVariantVCF )
      || $self->error("Unable to create novel variant VCF file: $novelVariantVCF");
    $vfh->autoflush(1);

    print $vfh join( "\t", @VCF_FIELDS ) . "\n";

    my $lineCount           = 0;
    my $novelVariantCount   = 0;
    my $invalidVariantCount = 0;
    my $foundNovelVariants = {}; # to avoid writing duplicates to file / counts both invalid and novel
    while ( my $line = <$fh> ) {
        chomp $line;
        my @values = split /\t/, $line;

        my %row;
        @row{@INPUT_FIELDS} = @values;

        my $id = ($self->getArg('markerIsValidRefSnp')) ? $row{marker} : $row{metaseq_id};

        if ( $row{metaseq_id} ne "NULL" ) {
            my ( $chromosome, $position, $ref, $alt ) = split /:/,
              $row{metaseq_id};
            if ( $row{$genomeBuild} eq 'NULL' ) {    # not in DB
                next if (exists $foundNovelVariants->{$row{metaseq_id}});
                $foundNovelVariants->{$row{metaseq_id}} = 1;
                if ( $row{metaseq_id} =~ m/:\?/ )
                {    # can't annotate "?" b/c variable length allele str
                    $invalidVariantCount++;
                    $self->log(
                        "INFO: Found invalid variant " . $row{metaseq_id} );
                    next;
                }
                print $vfh join( "\t",
                    $chromosome, $position, $id, $ref, $alt, '.',
                    '.', '.' )
                  . "\n";
                ++$novelVariantCount;       
            }
        }
        else {
            next if (exists $foundNovelVariants->{$row{marker}});
            $foundNovelVariants->{$row{marker}} = 1;
            if ( $row{marker} =~ /^rs/ && $row{chr} ne "NULL" ) {
                ++$novelVariantCount;
            }
            else {
                $invalidVariantCount++;
                $self->log( "INFO: Found invalid variant " . $row{marker} );
                next;
            }
            print $vfh join( "\t",
                $row{chr}, $row{bp}, $row{marker}, "N", "N", '.', '.', '.' )
              . "\n";
        }

        $self->log("INFO: Checked $lineCount variants")
          if ( ++$lineCount % 500000 == 0 );
    }

    $fh->close();
    $vfh->close();
    $self->log("DONE: Checked $lineCount variants")
      if ( ++$lineCount % 500000 == 0 );
    $self->log("INFO: Found $novelVariantCount novel variants");
    if ($finalCheck) {
        $self->log("INFO: Found $invalidVariantCount invalid variants");
        $novelVariantCount -= $invalidVariantCount;
    }

    return $novelVariantVCF, $novelVariantCount;
}

# ----------------------------------------------------------------------
# load / update
# ----------------------------------------------------------------------

sub loadResult {
    my ($self) = @_;
    $self->log(
        "INFO: Loading GWAS summary statistics into Results.VariantGWAS");

    my $file       = $self->{root_file_path} . $self->getArg('file');
    my $filePrefix = $self->{adj_source_id};
    my $inputFileName =
      $self->{working_dir} . "/" . $filePrefix . '-input.txt.dbmapped';
    $self->log("INFO: Loading from file: $inputFileName");
    $self->error(
"DBMapped Input file $inputFileName does not exist.  Check preprocessing result."
    ) if ( !( -e $inputFileName ) );

    open( my $fh, $inputFileName )
      || $self->error("Unable to open $inputFileName for reading");
    my $header          = <$fh>;
    my $recordCount     = 0;
    my $json            = JSON::XS->new();
    my $insertStrBuffer = "";
    my $commitAfter     = $self->getArg('commitAfter');
    my $msgPrefix     = ( $self->getArg('commit') ) ? 'COMMITTED' : 'PROCESSED';
    my $genomeBuild   = $self->getArg('genomeBuild');
    my $nullSkipCount = 0;
    my %row;

    while ( my $line = <$fh> ) {
        chomp($line);
        @row{@INPUT_FIELDS} = split /\t/, $line;

        if ( $row{pvalue} eq 'NULL' )
        {    # don't load NULL (missing) pvalues as they are useless for project
            $nullSkipCount++;
            next;
        }

# {"bin_index":"blah","metaseq_id":"1:1205055:G:T","location":1205055,"chromosome":"1","matched_variants":[{"ref_snp_id":"rs1815606","genomicsdb_id":"1:1205055:G:T:rs1815606"}]}
        my $vrString = $row{$genomeBuild};
        if ( $vrString eq 'NULL' ) {
            if ( $self->getArg('sourceId') =~ /NHGRI/ ) {
                if ( $row{metaseq_id} eq "7:120812727:G:G" ) {
                    $self->log(
"WARNING: Found unmapped variant with missing allele(s):"
                          . $row{metaseq_id}
                          . " - SKIPPING Load" );
                    next;
                }
                if ( $row{metaseq_id} eq 'NULL' ) {
                    $self->log(
                        "WARNING: Found unmapped variant - NULL - SKIPPING Load"
                    );
                    next;
                }
            }

            if ( $row{metaseq_id} =~ m/:N/ ) {
                $self->log(
                    "WARNING: Found unmapped variant with missing allele(s):"
                      . $row{metaseq_id}
                      . " - SKIPPING Load" );
                next;
            }
            elsif ( $row{marker} =~ /rs/ ) {
                $self->log( "WARNING: Found unmapped variant with marker:"
                      . $row{marker}
                      . " - SKIPPING Load" );
                next;
            }
            else {
                $self->error(
                    "Variant " . $row{metaseq_id} . " not mapped to DB" );
            }
        }
        my $variantRecord  = $json->decode($vrString);
        my @mappedVariants = @{ $variantRecord->{matched_variants} };
        foreach my $mv (@mappedVariants) {
            $insertStrBuffer .= $self->generateInsertStr( $mv->{genomicsdb_id},
                $variantRecord->{bin_index}, \%row );
            if ( ++$recordCount % $commitAfter == 0 ) {
                PluginUtils::bulkCopy( $self, $insertStrBuffer, $COPY_SQL );
                $insertStrBuffer = "";
                $self->log("$msgPrefix: $recordCount Results");
            }
        }
    }

    # residuals
    if ( $insertStrBuffer ne "" ) {
        PluginUtils::bulkCopy( $self, $insertStrBuffer, $COPY_SQL );
        $self->log("$msgPrefix: $recordCount Results");
    }

    $self->log("DONE - $msgPrefix: $recordCount Results");
    $self->log("WARNING - SKIPPED: $nullSkipCount Results with NULL p-value");
}

# this is just for lift over, so assuming parameter is
# for the GRCh38 file & need to iterate over GRCh37 file
sub extractVariantsRequiringUpdate {
    my ( $self, $fileName, $genomeBuild, $ignoreGWASFlags ) = @_;
    my $mappedGenomeBuild = ( $genomeBuild eq 'GRCh37' ) ? 'GRCh38' : 'GRCh37';

    my $inputFileName = $fileName;

# read in dbmapped file and create variant array, flagging variants w/gwas_flags and/or mapped variants
    my %variants;
    open( my $fh, $inputFileName )
      || $self->error("Unable to open db lookup file $inputFileName");
    <$fh>;    #header
    my %row;
    my $json = JSON::XS->new;
    while ( my $line = <$fh> ) {
        chomp($line);
        @row{@INPUT_FIELDS} = split /\t/, $line;
        my $update = ( $row{$mappedGenomeBuild} ne 'NULL' ) ? 1 : 0;
        if ( !$ignoreGWASFlags ) {
            $update = ( $update || $row{gwas_flags} ne 'NULL' ) ? 1 : 0;
        }
        if ($update) {
            my $variantStr  = $row{$genomeBuild};
            my $variantJson = $json->decode($variantStr);
            foreach my $mv ( @{ $variantJson->{matched_variants} } ) {
                if ( ref $mv eq ref {} ) {    # is hash?
                    $variants{ $mv->{genomicsdb_id} } = 1;
                }
                else {
               # otherwise, what's in the altBuild field is an existing mapping,
               # so no need to do update unless GWAS flags are present
                    if ( !$ignoreGWASFlags && $row{gwas_flags} ne 'NULL' ) {
                        $variants{$mv} = 1;
                    }
                }
            }    # end foreach
        }
    }
    $fh->close();
    my $nuVars = keys %variants;
    $self->log("INFO: Found $nuVars potential updates");

    $inputFileName =~ s/\.dbmapped//g;
    $self->log(
"INFO: Doing DBLookup for $inputFileName to find variants that need to be updated"
    );
    my $useMarker =
      ( $self->getArg('mapThruMarker') && !$self->getArg('markerIsMetaseqId') );

# precheck was done on the GRCh38 file, but want to save new lookup file in GRCh37 directory
# against GRCh37 coordinates if this is a legacy update
    if ( $genomeBuild eq 'GRCh37' ) {
        $inputFileName =~ s/_GRCh38//g;
        $inputFileName =~ s/GRCh38/GRCh37/;
    }

    my $dbmappedFileName =
      $self->DBLookup( $inputFileName, $genomeBuild, $useMarker,
        $UPDATE_CHECK );

    open( $fh, $dbmappedFileName )
      || $self->error("Unable to open db lookup file $dbmappedFileName");
    <$fh>;    #header
    while ( my $line = <$fh> ) {
        chomp($line);
        @row{@INPUT_FIELDS} = split /\t/, $line;

        my $update = ( $row{$mappedGenomeBuild} eq 'NULL' ) ? 1 : 0; # not in DB
        if ( !$ignoreGWASFlags ) {
            $update =
              ( $update || $row{gwas_flags} ne 'NULL' )
              ? 1
              : 0;    # has a gwas flag
        }

# note not catching the possibility that variant mapping is NULL in DB and not in
# updateable variant hash as that may just be that there is no mapping for that variant
        my $variantStr = $row{$genomeBuild};
        if ( $variantStr eq 'NULL' ) {
            $self->log( "WARNING: Found unmapped variant: "
                  . $row{metaseq_id}
                  . " - SKIPPING" );
            next;
        }
        my $variantJson = $json->decode($variantStr);
        foreach my $mv ( @{ $variantJson->{matched_variants} } ) {
            my $cVariant = $mv->{genomicsdb_id};
            delete $variants{$cVariant}
              if ( exists $variants{$cVariant} and !$update );
        }
    }
    $fh->close();
    return \%variants;
}

sub updateVariantFlags {
    my ( $self, $file ) = @_;

    my $filePrefix = $self->{adj_source_id};
    my $inputFileName =
      ($file)
      ? $file . ".dbmapped"
      : $self->{working_dir} . "/" . $filePrefix . '-input.txt.dbmapped';

    my $liftedCoordinatesOnly = $self->getArg('liftOver');

    my $gusConfigFile = undef;

    if ($liftedCoordinatesOnly) {
        $self->log(
"INFO: LiftOver: updating alt build coordinates in GRCh37 database from $inputFileName"
        );
        if ( $self->getArg('updateGusConfig') ) {
            $gusConfigFile = $self->getArg('updateGusConfig');
            $self->log(
                "INFO: Verifying AnnotatedVDB gus.config file: $gusConfigFile");
            open( my $gfh, $gusConfigFile )
              || $self->error("Unable to open updateGusConfig $gusConfigFile");
            my $valid = 0;
            while ( my $line = <$gfh> ) {
                if ( $line =~ /dbname=annotated_vdb/ ) {
                    $valid = 1;
                    last;
                }
            }
            $gfh->close();
            if ( !$valid ) {
                $self->error(
"To update GRCh37 variants, must supply GRCh37 AnnotatedVDB gus.config file using the option --updateGusConfig. Connection must be to the annotated_vdb database, not to the genomicsdb.  Updates via the foreign data wrapper are too slow."
                );
            }
        }
        else {
            $self->error(
"To update GRCh37 variants, must supply GRCh37 AnnotatedVDB gus.config file using the option --updateGusConfig"
            );
        }
    }
    else {
        $self->log(
"INFO: Updating variant flags (other_annotation [alt build coords], gwas_flags) from $inputFileName"
        );
    }

    my $genomeBuild    = $self->getArg('genomeBuild');
    my $altGenomeBuild = $genomeBuild eq 'GRCh38' ? 'GRCh37' : 'GRCh38';

    my $outputFileName = $inputFileName . ".uc-update-variant-flags.txt";
    my $uVariants      = undef;
    if ($liftedCoordinatesOnly) {
        $outputFileName =~ s/_GRCh38//g;
        $outputFileName =~ s/GRCh38/GRCh37/;
    }
    $uVariants =
      $self->extractVariantsRequiringUpdate( $inputFileName, $genomeBuild );
    my $nuVars = keys %$uVariants;
    $self->log("INFO: Found $nuVars updateable variant records");
    if ( !$nuVars ) {
        $self->log("DONE Updating variant record flags");
        return;
    }

    $self->log("INFO: Creating update file: $outputFileName");
    open( my $fh, $inputFileName )
      || $self->error("Unable to open $inputFileName for reading");
    open( my $ofh, '>', $outputFileName )
      || $self->error(
        "Unable to create variant flag update output file $outputFileName");
    if ($liftedCoordinatesOnly) {
        print $ofh join( "\t", qw(variant other_annotation) ) . "\n";
    }
    else {
        print $ofh join( "\t", qw(variant other_annotation gwas_flags) ) . "\n";
    }

    my $header = <$fh>;

    my %row;
    my $json = JSON::XS->new;

    while ( my $line = <$fh> ) {
        chomp($line);
        @row{@INPUT_FIELDS} = split /\t/, $line;

        my $record = $row{$genomeBuild};
        if ( $record eq 'NULL' ) {
            if ($liftedCoordinatesOnly) {

                # this can occur if this is a liftOver update
                # variant may not have been in GRCh37 version
                next;
            }
            else {
# if it is a load based update there variant should have a record for the genome build
# unless no alleles and invalid marker
                $self->log(
                    "WARNING: Cannot update record b/c not mapped to DB: $line"
                );
                next;
            }
        }

# lookups (GRCh37 and GRCh38 fields) could have one of two formats
# mapped variant from liftOver
# {"location":817186,"chromosome":"1","matched_variants":["1:817186:G:A:rs3094315"],"assembly":"GRCh38"}
# variant in  current DB version
# {"bin_index":"chr6.L1.B3.L2.B2.L3.B1.L4.B2.L5.B1.L6.B2.L7.B1.L8.B1.L9.B1.L10.B2.L11.B2.L12.B1.L13.B2","location":170213663,"chromosome":"6","matched_variants":[{"metaseq_id":"6:170213663:G:C","ref_snp_id":"rs6456179","genomicsdb_id":"6:170213663:G:C:rs6456179"}]}

        my $liftOverRecord = $row{$altGenomeBuild};
        if ( $liftOverRecord ne 'NULL' )
        {    # remove bin_index & link to correct genome build
            $liftOverRecord = $json->decode($liftOverRecord);
            if ( exists $liftOverRecord->{bin_index} )
            { # extract matched variants, otherwise already in correct format, leave as is
                delete $liftOverRecord->{bin_index};
                my @mvs;
                foreach my $mv ( @{ $liftOverRecord->{matched_variants} } ) {
                    push( @mvs, $mv->{genomicsdb_id} );
                }
                $liftOverRecord->{matched_variants} = \@mvs;
            }
            $liftOverRecord = { $altGenomeBuild => $liftOverRecord };
            $liftOverRecord = Utils::to_json($liftOverRecord);
        }

        my @updateValues = ($liftOverRecord);

        if ( !$liftedCoordinatesOnly ) {
            my $gwasFlags = $row{gwas_flags};
            next
              if ( $gwasFlags eq 'NULL' && $liftOverRecord eq 'NULL' )
              ;    # no update needed;
            push( @updateValues, $gwasFlags );
        }

        $record = $json->decode($record);
        foreach my $mv ( @{ $record->{matched_variants} } ) {
            my $variantId = ( ref $mv eq ref {} )    # is hash?
              ? $mv->{genomicsdb_id}
              : $mv;                                 # scalar

            next if ( !( exists $uVariants->{$variantId} ) );  # already updated
            print $ofh join( "\t", $variantId, @updateValues ) . "\n";
        }
    }
    $fh->close();
    $ofh->close();
    undef $uVariants;

    my $annotator = $self->{annotator};
    $annotator->updateVariantRecords( $outputFileName, $gusConfigFile,
        $liftedCoordinatesOnly );
    $self->log("DONE Updating variant record flags");
}

sub extractMarkerFromDBMap {
    my ( $self, $mapping, $markerField ) = @_;

# {"bin_index":"chr1.L1.B1.L2.B1.L3.B1.L4.B1.L5.B1.L6.B1.L7.B2.L8.B1.L9.B1.L10.B1.L11.B2.L12.B1.L13.B2","location":1086035,"chromosome":"1","matched_variants":[{"metaseq_id":"1:1086035:A:G","ref_snp_id":"rs3737728","genomicsdb_id":"1:1086035:A:G:rs3737728"}]}

    my @mvs = @{ $mapping->{matched_variants} };
    foreach my $mv (@mvs) {
        my $marker = $mv->{$markerField};
        return $marker if ($marker);
    }
    return undef;
}

sub standardize {
    my ($self) = @_;

    $self->log("INFO: Generating Standardize Summary Statistics Files");

    my $hasFreqData = $self->getArg('frequency') ? 1 : 0;
    my $genomeBuild = $self->getArg('genomeBuild');

  # /project/wang4/GenomicsDB/NIAGADS_GWAS/NG00027/GRCh37/NG00027_GRCh38_STAGE12
    my $file       = $self->{root_file_path} . $self->getArg('file');
    my $filePrefix = $self->{adj_source_id};
    my $inputFileName =
      $self->{working_dir} . "/" . $filePrefix . '-input.txt.dbmapped';
    $self->error(
"DBMapped Input file $inputFileName does not exist.  Check preprocessing result."
    ) if ( !( -e $inputFileName ) );
    my $oFilePath = PluginUtils::createDirectory( $self, $self->{working_dir},
        "standardized" );
    my $pvaluesOnlyFileName = $oFilePath . "/" . $filePrefix . '-pvalues.txt';
    my $fullStatsFileName   = $oFilePath . "/" . $filePrefix . '.txt';

    my @sfields = qw(chr bp allele1 allele2 pvalue);
    my @rfields = undef;

    open( my $fh, $inputFileName )
      || $self->error(
        "Unable to open DBMapped input file $inputFileName for reading");
    open( my $pvFh, '>', $pvaluesOnlyFileName )
      || $self->error(
        "Unable to create p-value file $pvaluesOnlyFileName for writing");
    open( my $fsFh, '>', $fullStatsFileName )
      || $self->error(
        "Unable to create full stats file $fullStatsFileName for writing");
    $fsFh->autoflush(1);
    $pvFh->autoflush(1);
    my @sheader = qw(chr bp effect_allele non_effect_allele pvalue);

    my $header    = <$fh>;
    my $json      = JSON::XS->new();
    my $lineCount = 0;
    my %row;
    while ( my $line = <$fh> ) {
        chomp($line);
        @row{@INPUT_FIELDS} = split /\t/, $line;

        my $restrictedStats = $json->decode( $row{restricted_stats_json} )
          || $self->error(
            "Error parsing restricted stats json for line $lineCount: "
              . $row{restricted_stats_json} );

        if ( ++$lineCount == 1 ) {    # generate & print header
                                      # unshift @sheader, "variant";
            unshift @sheader, "marker";
            push( @sheader, "probe" ) if ( $self->getArg('probe') );
            print $pvFh join( "\t", @sheader ) . "\n";

            push( @sheader, "frequency" ) if ($hasFreqData);
            @rfields = $self->generateStandardizedHeader($restrictedStats);
            push( @sheader, @rfields );
            print $fsFh join( "\t", @sheader ) . "\n";
        }

        my $metaseqId = $row{metaseq_id};
        my $dbVariant = $row{$genomeBuild};
        if ( $dbVariant ne 'NULL' ) {
            $dbVariant = $json->decode($dbVariant)
              || $self->error( "Error parsing dbv json for line $lineCount: "
                  . $row{$genomeBuild} );
        }
        if ( $metaseqId eq 'NULL' ) {
            if ( $dbVariant eq 'NULL' ) {
                $self->log(
                    "INFO: SKIPPING Unmapped variant on $lineCount: $line");
                next;
            }
            $metaseqId =
              $self->extractMarkerFromDBMap( $dbVariant, "metaseq_id" );
            if ( !$metaseqId ) {
                $self->log(
                    "INFO: SKIPPING Unmapped variant on $lineCount: $line");
            }
        }

        my $refSnpId =
          ( $dbVariant ne 'NULL' )
          ? $self->extractMarkerFromDBMap( $dbVariant, "ref_snp_id" )
          : undef;
        my $marker =
          ($refSnpId) ? $refSnpId : Utils::truncateStr( $metaseqId, 50 );

        my @cvalues = @row{@sfields};

        # unshift @cvalues, $metaseqId;
        unshift @cvalues, $marker;
        push( @cvalues, $restrictedStats->{probe} )
          if ( $self->getArg('probe') );
        my $oStr = join( "\t", @cvalues );
        $oStr =~ s/NULL/NA/g;         # replace any DB nulls with NAs
        $oStr =~ s/Infinity/Inf/g;    # replace any DB Infinities with Inf
        print $pvFh "$oStr\n";

        push( @cvalues, $row{freq1} ) if ($hasFreqData);
        push( @cvalues, @$restrictedStats{@rfields} );
        $oStr = join( "\t", @cvalues );
        $oStr =~ s/NULL/NA/g;         # replace any DB nulls with NAs
        $oStr =~ s/Infinity/Inf/g;    # replace any DB Infinities with Inf
        print $fsFh "$oStr\n";

        if ( $lineCount % 10000 == 0 ) {
            $self->log("INFO: Processed $lineCount lines");
            $self->undefPointerCache();
        }
    }

    $fh->close();
    $pvFh->close();
    $fsFh->close();

    $self->log(
"INFO: Checking standardized output for duplicate values (from marker-based matches)"
    );
    $self->removeFileDuplicates($fullStatsFileName);
    $self->removeFileDuplicates($pvaluesOnlyFileName);
    $self->log("DONE: Wrote standardized output: $fullStatsFileName");
    $self->log(
        "DONE: Wrote standardized output pvalues only: $pvaluesOnlyFileName");
}

# ----------------------------------------------------------------------
sub undoTables {
    my ($self) = @_;
    return ('Results.VariantGWAS'); # 'Results.VariantGWAS', 'NIAGADS.Variant');
}

1;
