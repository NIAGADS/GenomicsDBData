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

BEGIN {$Package::Alias::BRAVE = 1}
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
  qw(chr bp allele1 allele2 marker metaseq_id freq1 pvalue neg_log10_p display_p gwas_flags test_allele restricted_stats_json mapped_variant bin_index);
my @RESULT_FIELDS =
  qw(chr bp allele1 allele2 freq1 pvalue neg_log10_p display_p gwas_flags test_allele restricted_stats_json db_variant_json);
my @RESTRICTED_STATS_ORDER =
  qw(num_observations coded_allele_frequency minor_allele_count call_rate test min_frequency max_frequency frequency_se effect beta t_statistic std_err odds_ratio beta_std_err beta_L95 beta_U95 odds_ratio_L95 odds_ratio_U95 hazard_ratio hazard_ratio_CI95 direction het_chi_sq het_i_sq het_df het_pvalue probe maf_case maf_control p_additive p_dominant p_recessive Z_additive Z_dominant Z_recessive);
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
                descr => 'directory containing input file & to which output of plugin will be written',
                constraintFunc => undef,
                reqd           => 1,
                isList         => 0
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
                descr => '(optional) only specify if input has 3 allele columns (e.g., major, minor, test)',
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
                descr => 'threshold for flagging result has having genome wide signficiance; provide in scientific notation',
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
                descr => 'json object of key value pairs for additional scores/annotations that have restricted access',
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
                descr => 'flag if map to marker even in alleles do not match exactly',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
           }
       ),

        booleanArg(
            {
                name  => 'markerIsMetaseqId',
                descr => 'flag if marker is a metaseq_id; to be used with map thru marker',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
           }
       ),

        booleanArg(
            {
                name  => 'checkAltIndels',
                descr => 'check for alternative variant combinations for indels, e.g.: ref:alt, alt:ref',
                constraintFunc => undef,
                isList         => 0,
                reqd           => 0
           }
       ),

        booleanArg(
            {
                name  => 'markerIndicatesIndel',
                descr => 'marker indicates whether insertion or deletion (I or D)',
                constraintFunc => undef,
                isList         => 0,
                reqd           => 0
           }
       ),

        stringArg(
            {
                name  => 'customChrMap',
                descr => 'json object defining custom mappings (e.g., {"25":"M", "Z": "5"}',
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
                descr => 'update existing variant annotation: gwas_flags (part of load)',
                isList         => 0,
                reqd           => 0
           }
       ),

        booleanArg(
            {
                name  => 'preprocess',
                descr => 'preprocess / map to DB, find & annotate novel variants',
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
                descr => 'generate standardized files for storage in the data repository; one p-values only; one complete, can be done along w/--load, but assumes preprocessing complete and will fail if dbmapped file does not exist or is incomplete',
                constraintFunc => undef,
                isList         => 0,
                reqd           => 0
           }
       ),

        booleanArg(
            {
                name  => 'load',
                descr => 'load variants; assumes preprocessing completed and will fail if dbmapped file does not exist or is incomplete',
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
                descr => 'resume variant load; need to check against db for variants that were flagged  but not actually loaded',
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
                descr => 'skip VEP run; when novel variants contain INDELS takes a long time to run VEP + likelihood of running into a new consequence in the result is high; use this to use the existing JSON file to try and do the AnnotatedVDB update',
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

    my $purpose = 'Loads Variant GWAS result in multiple passes: 1) lookup against AnnotatedVDB & flag novel variants; output updated input file w/mapped record PK & bin_index, 2) annotate novel variants and update new annotated input file, 3) sort annotated input file by position and update/insert into NIAGADS.Variant and annotatedVDB 4)load GWAS results, 5) output standardized files for NIAGADS repository';

    my $tablesAffected = [
        [ 'Results::VariantGWAS', 'Enters a row for each variant feature' ],
        ['NIAGAD::Variant', 'Enters a row for each variant when insertMissingVariants option is specified']
    ];

    my $tablesDependedOn =
      [ [ 'Study::ProtocolAppNode', 'lookup analysis source_id' ] ];

    my $howToRestart = '';

    my $failureCases = '';

    my $notes = <<NOTES;

Written by Emily Greenfest-Allen
modified from ../Load/plugin/perl/deprecated/LoadVariantGWASResult
Copyright Trustees of University of Pennsylvania 2024. 
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
    bless($self, $class);

    my $documentation       = &getDocumentation();
    my $argumentDeclaration = &getArgumentsDeclaration();

    $self->initialize(
        {
            requiredDbVersion => 4.0,
            cvsRevision       => '$Revision: 1$',
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
    $self->log("Initializing PROCESS COUNT SEMAPHORE; num workers = $numWorkers");
    $PROCESS_COUNT_SEMAPHORE = Thread::Semaphore->new($numWorkers);

    my $liftedOverInputFile = ($self->getArg('liftOver'))
      ? $self->liftOver($self->getArg('updateFlags'))
      : undef;
    $self->preprocess() if ($self->getArg('preprocess'));
    $self->loadResult() if ($self->getArg('load'));
    $self->updateVariantFlags($liftedOverInputFile)
      if ($self->getArg('updateFlags'));
    $self->standardize()       if ($self->getArg('standardize'));
    $self->cleanWorkingDir()   if ($self->getArg('clean'));
    $self->archiveWorkingDir() if ($self->getArg('archive'));
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

    $self->{custom_chr_map} = ($self->getArg('customChrMap')) 
        ? $self->generateCustomChrMap() 
        : undef;

    $self->{protocol_app_node_id} = $self->getProtocolAppNodeId();    # verify protocol app node

    $self->{annotator} = VariantAnnotator->new({plugin => $self});
    $self->{housekeeping} = PluginUtils::buildHouseKeepingString($self);
    $self->{files} = {};

    my $sourceId = $self->getArg('sourceId');

    $self->{source_id} = $sourceId;
    $self->{root_file_path} = $self->getArg('fileDir') . "/" . $self->getArg('genomeBuild') . "/";
    
    PluginUtils::createDirectory($self, $self->{root_file_path});
    my $workingDir = PluginUtils::createDirectory(
        $self,
        $self->{root_file_path},
        $self->{source_id}
    );
    $self->{working_dir} = $workingDir;
}

sub verifyArgs {
    my ($self) = @_;

    if ($self->getArg('preprocess')) {
        $self->error("must specify testAllele")
            if ( !$self->getArg('testAllele')
                && !$self->getArg('marker')
                && !$self->getArg('markerIsMetaseqId'));
        $self->error("must specify refAllele")
            if (!$self->getArg('refAllele') && !$self->getArg('marker'));
        $self->error("must specify pvalue") if (!$self->getArg('pvalue'));
        $self->error("must specify marker if mapping through marker")
            if ($self->getArg('mapThruMarker') && !$self->getArg('marker'));
    }
}


sub getProtocolAppNodeId {
    my ($self) = @_;

    my $protocolAppNode = GUS::Model::Study::ProtocolAppNode->new(
        {source_id => $self->getArg('sourceId')});
        
    $self->error("No protocol app node found for " . $self->getArg('sourceId'))
        unless $protocolAppNode->retrieveFromDB();

    return $protocolAppNode->getProtocolAppNodeId();
}

sub generateCustomChrMap {
    my ($self) = @_;
    my $json   = JSON::XS->new;
    my $chrMap = $json->decode($self->getArg('customChrMap'))
        || $self->error("Error parsing custom chromosome map");
    $self->log("Found custom chromosome mapping: " . Dumper(\$chrMap));
    return $chrMap;
}

sub generateStandardizedHeader {
    my ($self, $stats) = @_;

    my @header = ();
    foreach my $label (@RESTRICTED_STATS_ORDER) {
        next if ($label eq 'probe');        # already added
        push(@header, $label) if (exists $stats->{$label});
    }

    my $json    = JSON::XS->new;
    my $rsParam = $json->decode($self->getArg('restrictedStats'))
        || $self->error("Error parsing restricted stats JSON");

    my @otherRSTATS = (exists $rsParam->{other}) 
        ? @{$rsParam->{other}} 
        : undef;

    foreach my $label (@otherRSTATS) {
        push(@header, $label) if (exists $stats->{$label});
    }

    return @header;
}

sub generateInsertStr {
    my ($self, $recordPK, $binIndex, $data) = @_;
    my @values = (
        $self->{protocol_app_node_id}, 
        $recordPK,
        $binIndex,
        $data->{neg_log10_p},
        $data->{display_p},
        $data->{freq1},
        $data->{test_allele},
        $data->{restricted_stats_json}
    );

    push(@values, GenomicsDBData::Load::Utils::getCurrentTime());
    push(@values, $self->{housekeeping});
    my $str = join("|", @values);
    return "$str\n";
}

sub getColumnIndex {
    my ($self, $columnMap, $field) = @_;

    $self->error("$field not in file header")
        if (!exists $columnMap->{$field});

    return $columnMap->{$field};
}

# ----------------------------------------------------------------------
# file manipulation methods
# ----------------------------------------------------------------------

sub cleanDirectory {
    my ($self, $workingDir, $targetDir) = @_;

    my $path = "$workingDir/$targetDir";
    if (-e $path) {
        $self->log("WARNING: $targetDir directory ($path) found/removing");

        # rmtree($path); # race condition
        my $cmd = `rm -rf $path`;
    }
    else {
        $self->log("INFO: $targetDir directory ($path) does not exist/skipping");
    }
}


sub cleanWorkingDir {   # clean working directory
    my ($self)      = @_;
    my $genomeBuild = $self->getArg('genomeBuild');
    my $workingDir  = $self->{working_dir};
    $self->log("INFO: Cleaning working directory for $genomeBuild: $workingDir");
    $self->log("INFO: Removing subdirectories");

    $self->cleanDirectory($workingDir, "liftOver");
    $self->cleanDirectory($workingDir, "remap");
    $self->cleanDirectory($workingDir, "preprocess");

    my $path = "$workingDir/standardized";
    if (-e $path) {
        if (!$self->getArg('archive'))
        {   # keep standardization directory for achive
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

    my @patterns = map {qr/\Q$_/} ('dbmapped');
    foreach my $file (glob "$workingDir/*") {
        foreach my $pattern (@patterns) {
            if ($file =~ $pattern) {
                $self->log("INFO: Removing $file");
                unlink $file or $self->error("Cannot delete file $file: $!");
                next FILE;
            }
        }
    }
}


sub compressFiles {
    my ($self, $workingDir, $pattern, $message) = @_;

    my @patterns = map {qr/\Q$_/} ($pattern);
    foreach my $file (glob "$workingDir/*") {
        foreach my $pattern (@patterns) {
            if ($file =~ $pattern) {
                if ($file !~ m/\.gz/)
                {   # not already compressed in case of recovery/resume
                    $self->log("INFO: Compressing $message file: $file");
                    my $cmd = `gzip $file`;
                }
                else {
                    $self->log("WARNING: Skipping $message file $file; already compressed");
                }
            }
        }
    }
}


sub archiveWorkingDir {
    my ($self)      = @_;
    my $genomeBuild = $self->getArg('genomeBuild');
    my $workingDir  = $self->{working_dir};
    my $sourceId    = $self->{source_id};
    my $rootPath    = $self->{root_file_path};

    $self->log(
        "INFO: Archiving working directory for $genomeBuild: $workingDir");
    $self->cleanWorkingDir();

    $self->compressFiles($workingDir, "input", "cleaned input");
    $self->compressFiles($workingDir . "/standardized",
        "txt", "standardized output");
    $self->log("INFO: Compressing working directory: $workingDir");
    my $cmd = `tar -zcf $workingDir.tar.gz --directory=$rootPath $sourceId`;
    $self->log("INFO: Removing working directory: $workingDir");

    # rmtree($workingDir); #race condition
    $cmd = `rm -rf $workingDir`;
}


sub removeFileDuplicates {
    my ($self, $fileName) = @_;
    my $cmd = `uniq $fileName > $fileName.uniq && mv $fileName.uniq $fileName`;
}


sub sortCleanedInput {
    my ($self, $workingDir, $fileName) = @_;
    
    $self->log("Sorting cleaned input $fileName / working directory = $workingDir");
    
    my $sortedFileName = $fileName . "-sorted.tmp";
    my $cmd = `(head -n 1 $fileName && tail -n +2 $fileName | sort -T $workingDir -V -k1,1 -k2,2) > $sortedFileName`;
    $cmd = `mv $sortedFileName $fileName`;
    $self->log("Created sorted file: $fileName");
}

sub writeCleanedInput {
    my ($self, $fh, $resultVariant, $fields, @values) = @_;

    my $frequencyC = ($self->getArg('frequency'))
        ? $fields->{$self->getArg('frequency')}
        : undef;
    my $frequency = (defined $frequencyC) ? $values[$frequencyC] : 'NULL';
    my $pvalueC   = $fields->{$self->getArg('pvalue')};
    my ($pvalue, $negLog10p, $displayP) = $self->formatPvalue($values[$pvalueC]);

    my $restrictedStats = 'NULL';
    if ($self->getArg('restrictedStats')) {
        $restrictedStats = $self->buildRestrictedStatsJson(@values);
    }

    my $gwasFlags = ($pvalue <= 0.001)
        ? $self->buildGWASFlags($pvalue, $displayP)
        : undef;

    # (chr bp allele1 allele2 marker metaseq_id freq1 pvalue neg_log10_p display_p gws_flags test_allele restricted_stats_json mapped_variant bin_index)
    print $fh join(
        "\t",
        (
            $resultVariant->{chromosome}
            ? $resultVariant->{chromosome}
            : "NULL",
            $resultVariant->{position} ? $resultVariant->{position} : "NULL",
            $resultVariant->{altAllele},
            $resultVariant->{refAllele},
            ($resultVariant->{marker}) 
                ? $resultVariant->{marker}
                : "NULL",
            ($resultVariant->{metaseq_id} =~ m/NA/g || !$resultVariant->{metaseq_id}) 
                ? "NULL" 
                : $resultVariant->{metaseq_id},
            $frequency,
            $pvalue,
            $negLog10p,
            $displayP,
            $gwasFlags ? $gwasFlags : "NULL",
            $resultVariant->{testAllele},
            $restrictedStats,
            "NULL", "NULL" # mapped variant, bin_index
        )
    ) . "\n";
}

# ----------------------------------------------------------------------
# attribute formatting
# ----------------------------------------------------------------------

sub cleanAllele {
    my ($self, $allele) = @_;

    $allele =~ s/<|>//g;
    $allele =~ s/:/\//g;
    return $allele;
}


sub correctChromosome {
    my ($self, $chrm) = @_;
    my $customChrMap = $self->{custom_chr_map};

    return ($chrm) if (!$customChrMap);

    while (my ($oc, $rc) = each %$customChrMap) {
        $chrm = $rc if ($chrm =~ m/\Q$oc/);
    }

    $chrm = 'M' if ($chrm =~ m/25/);
    $chrm = 'M' if ($chrm =~ m/MT/);
    $chrm = 'X' if ($chrm =~ m/23/);
    $chrm = 'Y' if ($chrm =~ m/24/);
    return $chrm;
}


sub generateAlleleStr {
    my ($self, $ref, $alt, $marker, $chromosome, $position, $frequencyC, $frequency) = @_;

    my $alleleStr = "$ref:$alt";
    my $isIndel   = (length($ref) > 1 || length($alt) > 1);

    if ($alleleStr =~ /\?/) {   # merged deletion or insertion
        if ($self->getArg('markerIndicatesIndel') && $marker ne 'NULL') {
            if ($marker =~ m/I$/ || $marker =~ m/ins/) {
                $alleleStr = ($alt =~ /\?/) ? "$ref:$alt" : "$alt:$ref";
            }
            elsif ($marker =~ m/D$/ || $marker =~ m/del/) {
                $alleleStr = ($ref =~ /\?/) ? "$ref:$alt" : "$alt:$ref";
            }
            $self->log( "WARNING: improper deletion: $chromosome:$position:$ref:$alt; UPDATED TO: $chromosome:$position:$alleleStr");
        }
        else {   # take at face value
            $self->log(
                "WARNING: improper deletion: $chromosome:$position:$ref:$alt");
        }
    }    # end "-"
    elsif ($isIndel) {
        if ($self->getArg('markerIndicatesIndel') && $marker ne 'NULL') {
            if ($marker =~ m/I$/ || $marker =~ m/ins/) {   # A:AAT
                $alleleStr = (length($ref) < length($alt))
                    ? $ref . ':' . $alt
                    : $alt . ':' . $ref;
            }
            elsif ($marker =~ m/D$/ || $marker =~ m/del/) {   # AAT:A
                $alleleStr = (length($ref) > length($alt))
                    ? $ref . ':' . $alt
                    : $alt . ':' . $ref;
            }
        }
    }
    else
    {# for SNVs if frequency > 0.5, then the test allele is the major allele; saves us some lookup times
        $alleleStr = ($frequencyC and $frequency > 0.5)
            ? $alt . ':' . $ref
            : $ref . ':' . $alt;
    }
    return $alleleStr;
}


sub formatPvalue {
    my ($self, $pvalue) = @_;
    my $negLog10p = 0;

    return ("NaN", "NaN", "NaN") if ($pvalue =~ m/NAN/i);
    return ("NULL", "NULL", "NULL") if ($pvalue =~ m/NA$/);
    return ($pvalue, "NaN", $pvalue) if ($pvalue == 0);
    return ("NULL", "NULL", "NULL") if (!$pvalue)
        
    if ($pvalue =~ m/e/i) {
        my ($mantissa, $exponent) = split /-/, $pvalue;
        return ($pvalue, $exponent, $pvalue) if ($exponent > 300);
    }

    return (1, 0, $pvalue) if ($pvalue == 1);

    eval {
        $negLog10p = -1.0 * (log($pvalue) / log(10));
    } or do {
        $self->log("WARNING: Cannot take log of p-value ($pvalue)");
        return ($pvalue, $pvalue, $pvalue);
    };

    my $displayP = ($pvalue < 0.0001) ? sprintf("%.2e", $pvalue) : $pvalue;

    return ($pvalue, $negLog10p, $displayP);
}


sub generateRestrictedStatsFieldMapping {
    my ($self, $columns) = @_;
    my $json  = JSON::XS->new;
    my $stats = $json->decode($self->getArg('restrictedStats')) || $self->error("Error parsing restricted stats JSON");

    $RESTRICTED_STATS_FIELD_MAP = {};
    while (my ($stat, $field) = each %$stats) {
        if ($stat eq "other") {
            foreach my $fd (@$field) {
                $RESTRICTED_STATS_FIELD_MAP->{$fd} = $self->getColumnIndex($columns, $fd);
            }
        }
        else {
            $RESTRICTED_STATS_FIELD_MAP->{$stat} = $self->getColumnIndex($columns, $field);
        }
    }
}


sub buildRestrictedStatsJson {
    my ($self, @values) = @_;
    my $stats = {};
    while (my ($stat, $index) = each %$RESTRICTED_STATS_FIELD_MAP) {
        my $tValue = lc($values[$index]);
        if ($tValue eq "infinity" or $tValue =~ m/^inf$/) {
            $stats->{$stat} = "Infinity";
        }
        else { # otherwise replaces Infinity w/inf which will cause problems w/load b/c inf s not a number in postgres
            $stats->{$stat} = Utils::toNumber($values[$index]);
        }
    }
    return Utils::to_json($stats);
}


sub buildGWASFlags {
    my ($self, $pvalue, $displayP) = @_;
    my $flags = {
        $self->getArg('sourceId') => {
            p_value => Utils::toNumber($displayP),
            is_gws  => $pvalue <= $self->getArg('genomeWideSignificanceThreshold') ? 1 : 0
        }
    };

    return Utils::to_json($flags);
}

# ----------------------------------------------------------------------
# clean and sort
# ----------------------------------------------------------------------

sub cleanAndSortInput {
    my ($self, $file) = @_;
    my $lineCount = 0;

    $self->log("INFO: Cleaning $file");

    my $genomeBuild   = $self->getArg('genomeBuild');
    my $filePrefix    = $self->{source_id};
    my $inputFileName = $self->{working_dir} . "/" . $filePrefix . '-input.txt';

    if (-e $inputFileName && !$self->getArg('overwrite')) {
        $self->log("INFO: Using existing cleaned input file: $inputFileName");
        return $inputFileName;
    }

    my $pfh = undef;
    open($pfh, '>', $inputFileName) || $self->error("Unable to create cleaned file $inputFileName for writing");
    print $pfh join("\t", @INPUT_FIELDS) . "\n";

    $pfh->autoflush(1);

    open(my $fh, $file) || $self->error("Unable to open $file for reading");

    my $header = <$fh>;
    chomp($header);
    my @fields = split /\t/, $header;
    @fields = split /\s/, $header if (scalar @fields == 1);
    @fields = split /,/,  $header if (scalar @fields == 1);

    my %columns = map {$fields[$_] => $_} 0 .. $#fields;
    if ($self->getArg('restrictedStats')) {
        $self->generateRestrictedStatsFieldMapping(\%columns) if (!$RESTRICTED_STATS_FIELD_MAP);
    }

    my $testAlleleC = ($self->getArg('testAllele'))
        ? $self->getColumnIndex(\%columns, $self->getArg('testAllele'))
        : undef;
    my $refAlleleC = ($self->getArg('refAllele'))
        ? $self->getColumnIndex(\%columns, $self->getArg('refAllele'))
        : undef;
    my $altAlleleC = ($self->getArg('altAllele'))
        ? $self->getColumnIndex(\%columns, $self->getArg('altAllele'))
        : undef;
    my $chrC = ($self->getArg('chromosome'))
        ? $self->getColumnIndex(\%columns, $self->getArg('chromosome'))
        : undef;
    my $positionC = ($self->getArg('position'))
        ? $self->getColumnIndex(\%columns, $self->getArg('position'))
        : undef;
    my $markerC = ($self->getArg('marker'))
        ? $self->getColumnIndex(\%columns, $self->getArg('marker'))
        : undef;

    while (my $line = <$fh>) {
        chomp $line;
        my @values = split /\t/, $line;
        @values = split /\s/, $line if (scalar @values == 1);
        @values = split /,/,  $line if (scalar @values == 1);

        my $marker = (defined $markerC) ? $values[$markerC] : undef;
        $marker = 'NULL' if $marker eq 'NA';

        my $chromosome = undef;
        my $position   = undef;
        my $metaseqId  = undef;
        my $alleleStr  = undef;

        # N for uknown single allele; this will allow us to match chr:pos:N:test
        my $ref = ($refAlleleC) ? uc($values[$refAlleleC]) : 'N';
        my $alt = ($altAlleleC)  
            ? uc($values[$altAlleleC])
            : (($testAlleleC) ? uc($values[$testAlleleC]) : 'N');
        my $test = ($testAlleleC) ? uc($values[$testAlleleC]) : undef;

        # set ref/alt to N if unknown so can still map/annotate
        # set test to N if 0 but leave as ? if ?
        $ref = 'N' if ($ref =~ m/^0$/); # vep can still process the 'N' if there is a single unknown, so do the replacement here for consistency
        $ref = '?' if ($ref =~ m/^\?$/);    # assume ? matches unknown number of bases
        $ref = '?' if ($ref =~ m/^-$/);     # assume ? matches unknown number of bases
        $alt = 'N' if ($alt =~ m/^0$/);
        $alt = 'N' if ($alt =~ m/^\?$/);
        $alt = '?' if ($alt =~ m/^-$/);     # assume ? matches unknown number of bases
        $test = 'N' if ($test =~ m/^0$/);
        $test = '?' if ($test =~ m/^\?$/);
        $test = '?' if ($test =~ m/^-$/);

        my $frequencyC = ($self->getArg('frequency'))
            ? $self->getColumnIndex(\%columns, $self->getArg('frequency'))
            : undef;

        my $frequency = ($frequencyC) ? $values[$frequencyC] : undef;

        if (defined $chrC) {
            $chromosome = $values[$chrC];

            if ($chromosome eq "0" || !defined $chromosome) {
                $chromosome = undef;
            }
            else {
                if ($chromosome =~ m/:/) {
                    ($chromosome, $position) = split /:/, $chromosome;
                }
                elsif ($chromosome =~ m/-/) {
                    ($chromosome, $position) = split /-/, $chromosome;
                }
                else {
                    $self->error("must specify position column")
                        if (!$positionC);
                    $position = $values[$positionC];
                }

                $chromosome = $self->correctChromosome($chromosome);
            }

            if ($position == 0) {   # mapping issue/no confidence in rsId either so skip
                $position = undef;
            }
            
            $position = $position + 1
                if ($position && $self->getArg('zeroBased'));

            $alleleStr = ($self->getArg('mapPosition'))
                ? undef
                : $self->generateAlleleStr($ref, $alt, $marker, $chromosome,
                    $position, $frequencyC, $frequency);

            $metaseqId = ($position && $chromosome)
                ? $chromosome . ':' . $position . ':' . $alleleStr
                : undef;
        }    # end definded chrC & !mapThruMarker

        else {   # chrC not defined / mapping thru marker
            $marker = undef if ($chrC eq $markerC);
            if ($chromosome eq "NA" || ($self->getArg('mapThruMarker') && $self->getArg('markerIsMetaseqId'))
                    || $marker =~ /:/) {
                $metaseqId = $marker if ($self->getArg('markerIsMetaseqId')); # yes ignore all that processing just did; easy fix added later

                # some weird ones are like chr:ps:ref:<weird:alt:blah:blah>
                my ($c, $p, $r, $a) = split /\<[^><]*>(*SKIP)(*FAIL)|:/, $metaseqId;
                $chromosome = $self->correctChromosome($c);
                $position   = $p;
                if ($self->getArg('markerIsMetaseqId')) {
                    $alt = $self->cleanAllele($a);
                    $ref = $self->cleanAllele($r);
                    $test = ($test)
                        ? $self->cleanAllele($test)
                        : $alt;    # assume testAllele is alt if not specified
                }

                $metaseqId = ($ref && $alt) 
                    ? join(':', $chromosome, $position, $ref, $alt) # in case chromosome/alleles were corrected
                    : join(':', $chromosome, $position) 
                        . ($alleleStr) ? ':' . $alleleStr : '';
            } # end if

            $self->error("--testAllele not specified and unable to extract from marker.  Must specify 'testAllele'") 
                if (!$test);
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

        $self->writeCleanedInput($pfh, $rv, \%columns, @values);

        if (++$lineCount % 500000 == 0) {
            $self->log("INFO: Cleaned $lineCount lines");
        }
    }

    $self->log("INFO: Cleaned $lineCount lines");
    $self->sortCleanedInput($self->{working_dir}, $inputFileName);
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
#        }
#      },
#       "metaseq_id": "1:1018704:A:G",
#       "ref_snp_id": "rs9442372",
#       "is_adsp_variant": true,
#       "record_primary_key": "1:1018704:A:G_rs9442372"
#    }
#   ]
#}

#{"bin_index":"chr1.L1.B1.L2.B1.L3.B1.L4.B1.L5.B1.L6.B1.L7.B1.L8.B2.L9.B2.L10.B1.L11.B1.L12.B1.L13.B1","location":752566,"chromosome":"1","matched_variants":[{"metaseq_id":"1:752566:G:A","ref_snp_id":"rs3094315","genomicsdb_id":"1:752566:G:A_rs3094315"}]}

# {"location":817186,"chromosome":"1","matched_variants":["1:817186:G:A:rs3094315"],"assembly":"GRCh38"}

# if firstValueOnly == false, then {"1:2071765:G:A": [{},{}]}

sub updateDBMappedInput {
    my ($self, $lookup, $mapping, $genomeBuild, $updateCheck) = @_;

    $updateCheck //= 0;
    $genomeBuild //= $self->getArg('genomeBuild');
    my $mappedBuild = ($genomeBuild eq 'GRCh37') ? 'GRCh38' : 'GRCh37';

    my ($chromosome, $position, @alleles) = split /:/,
      $$mapping[0]->{metaseq_id};
    my $row = $lookup->{row};

    my @matchedVariants;
    my $alleleMismatch = 0;
    my $mappedRefSnp;
    foreach my $variant (@$mapping) {
        if ($self->getArg('mapThruMarker')) {

            # make sure alleles match
            if (exists $variant->{annotation}->{allele_match}) {
                if (!($variant->{annotation}->{allele_match})
                    || $variant->{annotation}->{allele_match} eq "false")
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

        push(@matchedVariants, $ids);
   }

    if (!$alleleMismatch) {
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
            if ($assembly eq $mappedBuild) {
                $row->{$mappedBuild} = Utils::to_json($mappedCoordinates);
           }
       }

        # handle marker only mappings
        if ($row->{chr} =~ /NA/ || $row->{metaseq_id} eq 'NULL') {
            $row->{chr}        = $chromosome;
            $row->{bp}         = int($position);
            $row->{metaseq_id} = $$mapping[0]->{metaseq_id};
       }
   }
    else {# mismatched allele for existing refsnp
        # update the metaseq id to chr:pos:ref:allele_from_file (to be added later)
        # so it can be treated as a novel variant
        $row->{chr}        = $chromosome;
        $row->{bp}         = int($position);
        $row->{metaseq_id} = join(':', $chromosome, $position, $alleles[0], $row->{test_allele});
        $row->{marker} = $mappedRefSnp; 
   }
    return join("\t", @$row{@INPUT_FIELDS});
}

sub submitDBLookupQuery {
    my ($self, $genomeBuild, $lookups, $file, $updateCheck) = @_;
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
            $self->getArg('mapThruMarker') ? 0 : 1);

        # for rsIds map to all possible values
        # so if mapThruMarker is TRUE, firstValueOnly is FALSE (0)

# $recordHandler->setAllowAlleleMismatches($self->getArg('allowAlleleMismatches'));

        my $mappings = $recordHandler->lookup(keys %$lookups);

        $self->error("DEBUG - done mapping: ". Dumper($mappings));
        $SHARED_VARIABLE_SEMAPHORE->down;
        foreach my $vid (keys %$mappings) {
            next if (!defined $mappings->{$vid});    # "null" returned
            foreach my $lvalue (@{$lookups->{$vid}}) {
                my $index = $lvalue->{index};
                $$file[$index] =
                  $self->updateDBMappedInput($lvalue, $mappings->{$vid},
                    $genomeBuild, $updateCheck);
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


sub DBLookup {   # check against DB
    my ($self, $inputFileName, $genomeBuild, $useMarker, $checkType) = @_;

    $checkType //= 0
      ; # FINAL_CHECK overwrites the dbmapped file even if it exists, UPDATE_CHECK creates new file with .fc extenstion

    $genomeBuild //= $self->getArg('genomeBuild');

    $self->log("INFO: Querying existing DB mappings");
    my $msg =
        ($checkType == $UPDATE_CHECK) ? 'UPDATE'
      : ($checkType == $FINAL_CHECK)  ? 'FINAL'
      :                                   'NORMAL';
    $self->log("INFO: Check Type: $msg");
    my $gusConfig =
      ($self->{gus_config}->{$genomeBuild})
      ? $self->{gus_config}->{$genomeBuild}
      : "default";
    $self->log(
        "INFO: Source Genome Build: $genomeBuild / GUS Config File: $gusConfig"
   );

    my $outputFileName =
      ($checkType == $UPDATE_CHECK)
      ? "$inputFileName.dbmapped.uc"
      : "$inputFileName.dbmapped";

    if (-e $outputFileName && !$self->getArg('overwrite')) {
        if ($checkType == $FINAL_CHECK) {
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
    open(my $fh, $inputFileName)
      || $self->error("Unable to open input file $inputFileName for reading");

    # for some reason File::Slurp read_file was buggy with some files
    chomp(my @lines : shared = <$fh>);

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
    while (my ($index, $line) = each @lines) {
        next if ($index == 0);

        # I know, should be at end, but this way can count correctly & skip loop
        # processing where necessary
        $self->log("INFO: Processed $lineCount lines")
          if (++$lineCount % 100000 == 0);

     # $self->log("DEBUG: Processed $lineCount lines") if ($lineCount % 5 == 0);

        # chomp $line;
        my @values = split /\t/, $line;
        my %row;
        @row{@fields} = @values;

# DBLookup may be called several times, if the lookup has already been done, don't do it again
# unless update or row{genomeBuild} does not include bin_index (info is from liftOver)
        if ($row{$genomeBuild} ne 'NULL') {
            my $currentCoordinates = $json->decode($row{$genomeBuild});
            next if (exists $currentCoordinates->{bin_index});
       }

        my $variantId = undef;
        my $marker    = $row{marker};
        my $metaseqId = $row{metaseq_id};
        my $markerIsMetaseqId =
          ($self->getArg('markerIsMetaseqId') || $marker =~ /.+:.+:.+:.+/);

        if ($self->getArg('mapThruMarker') || $useMarker) {
            if ($markerIsMetaseqId) {
                $variantId = $marker;
           }
            else {
                $variantId = join(":", $marker, $row{allele1}, $row{allele2});
           }
       }
        else {
            if ($row{chr} =~ /NA/ || $row{metaseq_id} eq 'NULL') {
                $variantId = join(":", $marker, $row{allele1}, $row{allele2});
           }
            else {
                $variantId = $metaseqId;
           }
       }

        $variantId =~ s/:N:N//g; # if two unknowns, drop alleles and just match marker or position

        my @lvalue =
          (exists $lookups->{$variantId}) ? @{$lookups->{$variantId}} : ();
        my $nlvalue = {index => $index, line => $line, row => \%row};
        push(@lvalue, $nlvalue);

        #$self->error(Dumper(\@lvalue)) if (exists $lookups->{$variantId});
        $lookups->{$variantId} = \@lvalue;

        # $self->error(Dumper($lookups->{$variantId}));

        if (++$lookupCount % 10 == 0) {
            my $debug_vars = join(',', keys %$lookups);
            $self->log("DEBUG: " . $lookupCount . " -> " . '"' . $debug_vars . '"');
        #if (++$lookupCount % 10000 == 0) {
            $PROCESS_COUNT_SEMAPHORE->down;
            my $thread =
              threads->create(\&submitDBLookupQuery, $self, $genomeBuild,
                $lookups, $linePtr, ($checkType == $UPDATE_CHECK));
            undef $lookups;
            push(@threads, $thread);
            ($fail, @errors) =
              $self->monitorThreads($fail, \@errors, @threads);
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
#}
# $self->error("DEBUG: DONE");
# end debug block

        $PROCESS_COUNT_SEMAPHORE->down;
        my $thread =
          threads->create(\&submitDBLookupQuery, $self, $genomeBuild,
            $lookups, $linePtr, ($checkType == $UPDATE_CHECK));
        undef $lookups;
        push(@threads, $thread);
        ($fail, @errors) = $self->monitorThreads($fail, \@errors, @threads);
   }

    # catch any still running
    while (my @running = threads->list(threads::running)) {
        ($fail, @errors) = $self->monitorThreads($fail, \@errors, @threads);
   }

    # residuals after no more are running
    ($fail, @errors) = $self->monitorThreads($fail, \@errors, @threads);

    $self->error("Parallel DB Query failed: " . Dumper(\@errors))
      if ($fail);
    $self->log("DONE: Queried $lineCount variants");

    $lineCount = 0;
    $self->log(
        "INFO: Creating $outputFileName file with ${genomeBuild} database lookups");
    open(my $ofh, '>', $outputFileName)
      || $self->error(
        "Unable to open cleaned input file $outputFileName for updating");
    foreach my $line (@lines) {
        print $ofh "$line\n";
        $self->log("INFO: Wrote $lineCount lines")
          if (++$lineCount % 500000 == 0);
   }
    $ofh->close();

    # just to cover bases on garbage collection
    undef @lines;
    undef @threads;

    $self->log("DONE: Wrote $lineCount lines");

    $self->sortCleanedInput($self->{working_dir}, $outputFileName);
    return $outputFileName;
}


# ----------------------------------------------------------------------
# preprocess
# ----------------------------------------------------------------------

sub preprocess {
    my ($self)        = @_;
    my $file          = $self->{root_file_path} . $self->getArg('file');
    my $inputFileName = $self->cleanAndSortInput($file);

    my $filePrefix = $self->{source_id};
    my $filePath = PluginUtils::createDirectory($self, $self->{working_dir}, "preprocess");
    PluginUtils::setDirectoryPermissions($self, $filePath, "g+w");

    my ($novelVariantVcfFile, $novelVariantCount) = $self->extractNovelVariants($inputFileName, "$filePath/$filePrefix");
    if (!$self->getArg('test')) {
        my $foundNovelVariants = $self->annotateNovelVariants($novelVariantVcfFile);
        if ($foundNovelVariants) {   # > 0
            $self->log("INFO: Executing final check that all novel variants were annotated and loaded");
            ($novelVariantVcfFile, $novelVariantCount) = $self->extractNovelVariants(
                $inputFileName,
                "$filePath/$filePrefix", 
                $FINAL_CHECK);
            $self->error("$novelVariantCount Novel Variants found after annotation & load completed. See $novelVariantVcfFile") 
                if ($novelVariantCount > 1);
       }
    }
    else {
        $self->log("WARNING: --test flag provided; skipping novel variant annotation and load");
    }
    $self->log("DONE: Preprocessing completed");
}


sub getValidVepVariants {
    my ($self, $fileName) = @_;
    (my $validVcfFileName = $fileName) =~ s/vcf/valid.vcf/g;
    open(my $fh, $fileName) || $self->error("Unable to open $fileName to extract valid variants");
    open(my $ofh, '>', $validVcfFileName) || $self->error("Unable to create valid variant VCF $validVcfFileName for writing");

    # my @VCF_FIELDS = qw(#CHROM POS ID REF ALT QUAL FILTER INFO);

    while (my $line = <$fh>) {
        chomp($line);
        next if ($line =~ m/\?/);    # skip variants w/questions marks
        my ($chrm, $pos, $id, $ref, $alt, @other) = split /\t/, $line;
        next if (length($ref) > 50 || length($alt) > 50);  # skip long INDELS/SVs
        next if ($chrm eq "NULL");
        next if ($line =~ /:N:N/);    # completely unknown alleles
        print $ofh "$line\n";
    }

    $fh->close();
    $ofh->close();
    return $validVcfFileName;
}


sub annotateNovelVariants {
    my ($self, $fileName) = @_;

    my $lineCount = `wc -l < $fileName`;
    if ($lineCount > 1) {
        $self->log("INFO: Annotating variants in: $fileName");
        my ($accession, @other) = split /_/, $self->{source_id};
        my $preprocessDir = join("/", $accesssion, $self->getArg('genomeBuild'), $self->{source_id}, "preprocess");

        # remove invalid variants (i.e., w/?) before running thru VEP
        # and really long INDELs
        my $validVcfFileName = $self->getValidVepVariants($fileName);
        $lineCount = `wc -l < $validVcfFileName`;
        if ($lineCount > 1) {
            if ($self->getArg('skipVep')) {
                $self->log("INFO: --skipVep flag provided, skipping VEP annotation");
            }
            else {
                # strip local path, make relative to accession folder
                my $vepInputFileName = $preprocessDir . basename($validVcfFileName);
                $self->{annotator}->runVep("$vepInputFileName");
            }
            $self->{annotator}->loadVepAnnotatedVariants("$validVcfFileName.vep.json.gz");
        }
        else {
            $self->log("WARNING: No 'VEP valid' variants found; skipping VEP annotation");
        }

        $fileName = $validVcfFileName if $self->getArg('sourceId') =~ m/NHGRI/;
        $self->{annotator}->loadVariantsFromVCF("$fileName"); # can just pass original VCF file as it will skip anything already loaded
        $self->{annotator}->loadCaddScores($fileName, $preprocessDir);
    }
    else {
        $self->log("INFO: No novel variants found in: $fileName");
    }
    return ($lineCount > 1);
}


sub extractNovelVariants {
    my ($self, $file, $filePrefix, $finalCheck) = @_;

    $self->log("INFO: Extracting novel variants from DB Mapped file: $file");
    $finalCheck //= 0;    # final check remaps against db, overwriting existing dbmapping file

    my $genomeBuild = $self->getArg('genomeBuild');
    my $useMarker = ($self->getArg('mapThruMarker') && !$self->getArg('markerIsMetaseqId'));

    my $dbmappedFileName = $self->DBLookup($file, $genomeBuild, $useMarker, $finalCheck);

    open(my $fh, $dbmappedFileName) || $self->error("Unable to open DB Mapped file $dbmappedFileName for reading");
    my $header = <$fh>;

    my $novelVariantVCF = ($finalCheck) ? "$filePrefix-novel-final-check.vcf" : "$filePrefix-novel.vcf";
    if (-e $novelVariantVCF && !($self->getArg('overwrite'))) {
        $self->log("INFO: Using existing novel variant VCF: $novelVariantVCF");
        return $novelVariantVCF;
    }

    $self->log("INFO: Writing novel variants to $novelVariantVCF");
    open(my $vfh, '>', $novelVariantVCF) || $self->error("Unable to create novel variant VCF file: $novelVariantVCF");
    $vfh->autoflush(1);

    print $vfh join("\t", @VCF_FIELDS) . "\n";

    my $lineCount           = 0;
    my $novelVariantCount   = 0;
    my $invalidVariantCount = 0;
    my $foundNovelVariants = {}; # to avoid writing duplicates to file / counts both invalid and novel
    while (my $line = <$fh>) {
        chomp $line;
        my @values = split /\t/, $line;

        my %row;
        @row{@INPUT_FIELDS} = @values;

        my $id = ($self->getArg('markerIsValidRefSnp')) ? $row{marker} : $row{metaseq_id};

        if ($row{metaseq_id} ne "NULL") {
            my ($chromosome, $position, $ref, $alt) = split /:/, $row{metaseq_id};
            if ($row{$genomeBuild} eq 'NULL') {   # not in DB
                next if (exists $foundNovelVariants->{$row{metaseq_id}});
                $foundNovelVariants->{$row{metaseq_id}} = 1;
                if ($row{metaseq_id} =~ m/:\?/)
                {   # can't annotate "?" b/c variable length allele str
                    $invalidVariantCount++;
                    $self->log("INFO: Found invalid variant " . $row{metaseq_id});
                    next;
                }
                print $vfh join("\t", $chromosome, $position, $id, $ref, $alt, '.', '.', '.') . "\n";
                ++$novelVariantCount;       
            }
        }
        else {
            next if (exists $foundNovelVariants->{$row{marker}});
            $foundNovelVariants->{$row{marker}} = 1;
            if ($row{marker} =~ /^rs/ && $row{chr} ne "NULL") {
                ++$novelVariantCount;
            }
            else {
                $invalidVariantCount++;
                $self->log("INFO: Found invalid variant " . $row{marker});
                next;
            }
            print $vfh join("\t", $row{chr}, $row{bp}, $row{marker}, "N", "N", '.', '.', '.') . "\n";
        }

        $self->log("INFO: Checked $lineCount variants")
            if (++$lineCount % 500000 == 0);
    }

    $fh->close();
    $vfh->close();
    $self->log("DONE: Checked $lineCount variants")
        if (++$lineCount % 500000 == 0);
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
    my $filePrefix = $self->{source_id};
    my $inputFileName =
      $self->{working_dir} . "/" . $filePrefix . '-input.txt.dbmapped';
    $self->log("INFO: Loading from file: $inputFileName");
    $self->error(
"DBMapped Input file $inputFileName does not exist.  Check preprocessing result."
   ) if (!(-e $inputFileName));

    open(my $fh, $inputFileName)
      || $self->error("Unable to open $inputFileName for reading");
    my $header          = <$fh>;
    my $recordCount     = 0;
    my $json            = JSON::XS->new();
    my $insertStrBuffer = "";
    my $commitAfter     = $self->getArg('commitAfter');
    my $msgPrefix     = ($self->getArg('commit')) ? 'COMMITTED' : 'PROCESSED';
    my $genomeBuild   = $self->getArg('genomeBuild');
    my $nullSkipCount = 0;
    my %row;

    while (my $line = <$fh>) {
        chomp($line);
        @row{@INPUT_FIELDS} = split /\t/, $line;

        if ($row{pvalue} eq 'NULL')
        {   # don't load NULL (missing) pvalues as they are useless for project
            $nullSkipCount++;
            next;
       }

# {"bin_index":"blah","metaseq_id":"1:1205055:G:T","location":1205055,"chromosome":"1","matched_variants":[{"ref_snp_id":"rs1815606","genomicsdb_id":"1:1205055:G:T:rs1815606"}]}
        my $vrString = $row{$genomeBuild};
        if ($vrString eq 'NULL') {
            if ($self->getArg('sourceId') =~ /NHGRI/) {
                if ($row{metaseq_id} eq "7:120812727:G:G") {
                    $self->log(
"WARNING: Found unmapped variant with missing allele(s):"
                          . $row{metaseq_id}
                          . " - SKIPPING Load");
                    next;
               }
                if ($row{metaseq_id} eq 'NULL') {
                    $self->log(
                        "WARNING: Found unmapped variant - NULL - SKIPPING Load"
                   );
                    next;
               }
           }

            if ($row{metaseq_id} =~ m/:N/) {
                $self->log(
                    "WARNING: Found unmapped variant with missing allele(s):"
                      . $row{metaseq_id}
                      . " - SKIPPING Load");
                next;
           }
            elsif ($row{marker} =~ /rs/) {
                $self->log("WARNING: Found unmapped variant with marker:"
                      . $row{marker}
                      . " - SKIPPING Load");
                next;
           }
            else {
                $self->error(
                    "Variant " . $row{metaseq_id} . " not mapped to DB");
           }
       }
        my $variantRecord  = $json->decode($vrString);
        my @mappedVariants = @{$variantRecord->{matched_variants}};
        foreach my $mv (@mappedVariants) {
            $insertStrBuffer .= $self->generateInsertStr($mv->{genomicsdb_id},
                $variantRecord->{bin_index}, \%row);
            if (++$recordCount % $commitAfter == 0) {
                PluginUtils::bulkCopy($self, $insertStrBuffer, $COPY_SQL);
                $insertStrBuffer = "";
                $self->log("$msgPrefix: $recordCount Results");
           }
       }
   }

    # residuals
    if ($insertStrBuffer ne "") {
        PluginUtils::bulkCopy($self, $insertStrBuffer, $COPY_SQL);
        $self->log("$msgPrefix: $recordCount Results");
   }

    $self->log("DONE - $msgPrefix: $recordCount Results");
    $self->log("WARNING - SKIPPED: $nullSkipCount Results with NULL p-value");
}

# this is just for lift over, so assuming parameter is
# for the GRCh38 file & need to iterate over GRCh37 file
sub extractVariantsRequiringUpdate {
    my ($self, $fileName, $genomeBuild, $ignoreGWASFlags) = @_;
    my $mappedGenomeBuild = ($genomeBuild eq 'GRCh37') ? 'GRCh38' : 'GRCh37';

    my $inputFileName = $fileName;

# read in dbmapped file and create variant array, flagging variants w/gwas_flags and/or mapped variants
    my %variants;
    open(my $fh, $inputFileName)
      || $self->error("Unable to open db lookup file $inputFileName");
    <$fh>;    #header
    my %row;
    my $json = JSON::XS->new;
    while (my $line = <$fh>) {
        chomp($line);
        @row{@INPUT_FIELDS} = split /\t/, $line;
        my $update = ($row{$mappedGenomeBuild} ne 'NULL') ? 1 : 0;
        if (!$ignoreGWASFlags) {
            $update = ($update || $row{gwas_flags} ne 'NULL') ? 1 : 0;
       }
        if ($update) {
            my $variantStr  = $row{$genomeBuild};
            my $variantJson = $json->decode($variantStr);
            foreach my $mv (@{$variantJson->{matched_variants}}) {
                if (ref $mv eq ref {}) {   # is hash?
                    $variants{$mv->{genomicsdb_id}} = 1;
               }
                else {
               # otherwise, what's in the altBuild field is an existing mapping,
               # so no need to do update unless GWAS flags are present
                    if (!$ignoreGWASFlags && $row{gwas_flags} ne 'NULL') {
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
      ($self->getArg('mapThruMarker') && !$self->getArg('markerIsMetaseqId'));

# precheck was done on the GRCh38 file, but want to save new lookup file in GRCh37 directory
# against GRCh37 coordinates if this is a legacy update
    if ($genomeBuild eq 'GRCh37') {
        $inputFileName =~ s/_GRCh38//g;
        $inputFileName =~ s/GRCh38/GRCh37/;
   }

    my $dbmappedFileName =
      $self->DBLookup($inputFileName, $genomeBuild, $useMarker,
        $UPDATE_CHECK);

    open($fh, $dbmappedFileName)
      || $self->error("Unable to open db lookup file $dbmappedFileName");
    <$fh>;    #header
    while (my $line = <$fh>) {
        chomp($line);
        @row{@INPUT_FIELDS} = split /\t/, $line;

        my $update = ($row{$mappedGenomeBuild} eq 'NULL') ? 1 : 0; # not in DB
        if (!$ignoreGWASFlags) {
            $update =
              ($update || $row{gwas_flags} ne 'NULL')
              ? 1
              : 0;    # has a gwas flag
       }

# note not catching the possibility that variant mapping is NULL in DB and not in
# updateable variant hash as that may just be that there is no mapping for that variant
        my $variantStr = $row{$genomeBuild};
        if ($variantStr eq 'NULL') {
            $self->log("WARNING: Found unmapped variant: "
                  . $row{metaseq_id}
                  . " - SKIPPING");
            next;
       }
        my $variantJson = $json->decode($variantStr);
        foreach my $mv (@{$variantJson->{matched_variants}}) {
            my $cVariant = $mv->{genomicsdb_id};
            delete $variants{$cVariant}
              if (exists $variants{$cVariant} and !$update);
       }
   }
    $fh->close();
    return \%variants;
}

sub updateVariantFlags {
    my ($self, $file) = @_;

    my $filePrefix = $self->{source_id};
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
        if ($self->getArg('updateGusConfig')) {
            $gusConfigFile = $self->getArg('updateGusConfig');
            $self->log(
                "INFO: Verifying AnnotatedVDB gus.config file: $gusConfigFile");
            open(my $gfh, $gusConfigFile)
              || $self->error("Unable to open updateGusConfig $gusConfigFile");
            my $valid = 0;
            while (my $line = <$gfh>) {
                if ($line =~ /dbname=annotated_vdb/) {
                    $valid = 1;
                    last;
               }
           }
            $gfh->close();
            if (!$valid) {
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
      $self->extractVariantsRequiringUpdate($inputFileName, $genomeBuild);
    my $nuVars = keys %$uVariants;
    $self->log("INFO: Found $nuVars updateable variant records");
    if (!$nuVars) {
        $self->log("DONE Updating variant record flags");
        return;
   }

    $self->log("INFO: Creating update file: $outputFileName");
    open(my $fh, $inputFileName)
      || $self->error("Unable to open $inputFileName for reading");
    open(my $ofh, '>', $outputFileName)
      || $self->error(
        "Unable to create variant flag update output file $outputFileName");
    if ($liftedCoordinatesOnly) {
        print $ofh join("\t", qw(variant other_annotation)) . "\n";
   }
    else {
        print $ofh join("\t", qw(variant other_annotation gwas_flags)) . "\n";
   }

    my $header = <$fh>;

    my %row;
    my $json = JSON::XS->new;

    while (my $line = <$fh>) {
        chomp($line);
        @row{@INPUT_FIELDS} = split /\t/, $line;

        my $record = $row{$genomeBuild};
        if ($record eq 'NULL') {
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
        if ($liftOverRecord ne 'NULL')
        {   # remove bin_index & link to correct genome build
            $liftOverRecord = $json->decode($liftOverRecord);
            if (exists $liftOverRecord->{bin_index})
            {# extract matched variants, otherwise already in correct format, leave as is
                delete $liftOverRecord->{bin_index};
                my @mvs;
                foreach my $mv (@{$liftOverRecord->{matched_variants}}) {
                    push(@mvs, $mv->{genomicsdb_id});
               }
                $liftOverRecord->{matched_variants} = \@mvs;
           }
            $liftOverRecord = {$altGenomeBuild => $liftOverRecord};
            $liftOverRecord = Utils::to_json($liftOverRecord);
       }

        my @updateValues = ($liftOverRecord);

        if (!$liftedCoordinatesOnly) {
            my $gwasFlags = $row{gwas_flags};
            next
              if ($gwasFlags eq 'NULL' && $liftOverRecord eq 'NULL')
              ;    # no update needed;
            push(@updateValues, $gwasFlags);
       }

        $record = $json->decode($record);
        foreach my $mv (@{$record->{matched_variants}}) {
            my $variantId = (ref $mv eq ref {})    # is hash?
              ? $mv->{genomicsdb_id}
              : $mv;                                 # scalar

            next if (!(exists $uVariants->{$variantId}));  # already updated
            print $ofh join("\t", $variantId, @updateValues) . "\n";
       }
   }
    $fh->close();
    $ofh->close();
    undef $uVariants;

    my $annotator = $self->{annotator};
    $annotator->updateVariantRecords($outputFileName, $gusConfigFile,
        $liftedCoordinatesOnly);
    $self->log("DONE Updating variant record flags");
}

sub extractMarkerFromDBMap {
    my ($self, $mapping, $markerField) = @_;

# {"bin_index":"chr1.L1.B1.L2.B1.L3.B1.L4.B1.L5.B1.L6.B1.L7.B2.L8.B1.L9.B1.L10.B1.L11.B2.L12.B1.L13.B2","location":1086035,"chromosome":"1","matched_variants":[{"metaseq_id":"1:1086035:A:G","ref_snp_id":"rs3737728","genomicsdb_id":"1:1086035:A:G:rs3737728"}]}

    my @mvs = @{$mapping->{matched_variants}};
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
    my $filePrefix = $self->{source_id};
    my $inputFileName =
      $self->{working_dir} . "/" . $filePrefix . '-input.txt.dbmapped';
    $self->error(
"DBMapped Input file $inputFileName does not exist.  Check preprocessing result."
   ) if (!(-e $inputFileName));
    my $oFilePath = PluginUtils::createDirectory($self, $self->{working_dir},
        "standardized");
    my $pvaluesOnlyFileName = $oFilePath . "/" . $filePrefix . '-pvalues.txt';
    my $fullStatsFileName   = $oFilePath . "/" . $filePrefix . '.txt';

    my @sfields = qw(chr bp allele1 allele2 pvalue);
    my @rfields = undef;

    open(my $fh, $inputFileName)
      || $self->error(
        "Unable to open DBMapped input file $inputFileName for reading");
    open(my $pvFh, '>', $pvaluesOnlyFileName)
      || $self->error(
        "Unable to create p-value file $pvaluesOnlyFileName for writing");
    open(my $fsFh, '>', $fullStatsFileName)
      || $self->error(
        "Unable to create full stats file $fullStatsFileName for writing");
    $fsFh->autoflush(1);
    $pvFh->autoflush(1);
    my @sheader = qw(chr bp effect_allele non_effect_allele pvalue);

    my $header    = <$fh>;
    my $json      = JSON::XS->new();
    my $lineCount = 0;
    my %row;
    while (my $line = <$fh>) {
        chomp($line);
        @row{@INPUT_FIELDS} = split /\t/, $line;

        my $restrictedStats = $json->decode($row{restricted_stats_json})
          || $self->error(
            "Error parsing restricted stats json for line $lineCount: "
              . $row{restricted_stats_json});

        if (++$lineCount == 1) {   # generate & print header
                                      # unshift @sheader, "variant";
            unshift @sheader, "marker";
            push(@sheader, "probe") if ($self->getArg('probe'));
            print $pvFh join("\t", @sheader) . "\n";

            push(@sheader, "frequency") if ($hasFreqData);
            @rfields = $self->generateStandardizedHeader($restrictedStats);
            push(@sheader, @rfields);
            print $fsFh join("\t", @sheader) . "\n";
       }

        my $metaseqId = $row{metaseq_id};
        my $dbVariant = $row{$genomeBuild};
        if ($dbVariant ne 'NULL') {
            $dbVariant = $json->decode($dbVariant)
              || $self->error("Error parsing dbv json for line $lineCount: "
                  . $row{$genomeBuild});
       }
        if ($metaseqId eq 'NULL') {
            if ($dbVariant eq 'NULL') {
                $self->log(
                    "INFO: SKIPPING Unmapped variant on $lineCount: $line");
                next;
           }
            $metaseqId =
              $self->extractMarkerFromDBMap($dbVariant, "metaseq_id");
            if (!$metaseqId) {
                $self->log(
                    "INFO: SKIPPING Unmapped variant on $lineCount: $line");
           }
       }

        my $refSnpId =
          ($dbVariant ne 'NULL')
          ? $self->extractMarkerFromDBMap($dbVariant, "ref_snp_id")
          : undef;
        my $marker =
          ($refSnpId) ? $refSnpId : Utils::truncateStr($metaseqId, 50);

        my @cvalues = @row{@sfields};

        # unshift @cvalues, $metaseqId;
        unshift @cvalues, $marker;
        push(@cvalues, $restrictedStats->{probe})
          if ($self->getArg('probe'));
        my $oStr = join("\t", @cvalues);
        $oStr =~ s/NULL/NA/g;         # replace any DB nulls with NAs
        $oStr =~ s/Infinity/Inf/g;    # replace any DB Infinities with Inf
        print $pvFh "$oStr\n";

        push(@cvalues, $row{freq1}) if ($hasFreqData);
        push(@cvalues, @$restrictedStats{@rfields});
        $oStr = join("\t", @cvalues);
        $oStr =~ s/NULL/NA/g;         # replace any DB nulls with NAs
        $oStr =~ s/Infinity/Inf/g;    # replace any DB Infinities with Inf
        print $fsFh "$oStr\n";

        if ($lineCount % 10000 == 0) {
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
