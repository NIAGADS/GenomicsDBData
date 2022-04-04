## $Id: LoadVariantGWASResult.pm $
##

package GenomicsDBData::Load::Plugin::LoadVariantGWASResult;
@ISA = qw(GUS::PluginMgr::Plugin);


use strict;
use GUS::PluginMgr::Plugin;

use threads;
use Thread::Semaphore;
use threads::shared;

use Package::Alias VariantAnnotator => 'GenomicsDBData::Load::VariantAnnotator';
use Package::Alias Utils => 'GenomicsDBData::Load::Utils';
use Package::Alias PluginUtils => 'GenomicsDBData::Load::PluginUtils';
use Package::Alias VariantLoadUtils => 'GenomicsDBData::Load::VariantLoadUtils';
use Package::Alias VariantRecord => 'GenomicsDBData::Load::VariantRecord';

use JSON::XS;
use Data::Dumper;
use File::Slurp qw(read_file);
use POSIX qw(strftime);
use Parallel::Loops;


use LWP::UserAgent;
use LWP::Parallel::UserAgent;
use HTTP::Request::Common qw(GET);
use HTTP::Request;

use GUS::Model::Results::VariantGWAS;
use GUS::Model::NIAGADS::Variant;
use GUS::Model::Study::ProtocolAppNode;

my $APPEND = 1;
my $USE_MARKER = 1;
my $INCLUDE_MARKERS = 1;
my $DROP_MARKERS = 0;
my $NEW_FILE = 0;

my $RESTRICTED_STATS_FIELD_MAP = undef;

my $HOUSEKEEPING_FIELDS = PluginUtils::getHouseKeepingSql();

my @INPUT_FIELDS = qw(chr bp allele1 allele2 marker metaseq_id freq1 pvalue neg_log10_p display_p gwas_flags test_allele restricted_stats_json GRCh37 GRCh38);
my @RESULT_FIELDS = qw(chr bp allele1 allele2 freq1 pvalue neg_log10_p display_p gwas_flags test_allele restricted_stats_json db_variant_json);
my @RESTRICTED_STATS_ORDER = qw(num_observations coded_allele_frequency minor_allele_count call_rate test min_frequency max_frequency frequency_se effect beta t_statistic std_err odds_ratio beta_std_err beta_L95 beta_U95 odds_ratio_L95 odds_ratio_U95 hazard_ratio hazard_ratio_CI95 direction het_chi_sq het_i_sq het_df het_pvalue probe maf_case maf_control p_additive p_dominant p_recessive Z_additive Z_dominant Z_recessive );
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

my $SHARED_VARIABLE_SEMAPHORE = Thread::Semaphore->new();
my $PROCESS_COUNT_SEMAPHORE = Thread::Semaphore->new(20);


# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
  my $argumentDeclaration  =
    [
     stringArg({name => 'fileDir',
		descr => 'directory containing input file & to which output of plugin will be written',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0
	       }),

     stringArg({name => 'sourceGenomeBuildGusConfig',
		descr => 'gus config file for the lift over source version, should be GRCh37 gus.config',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0,
	       }),


     stringArg({name => 'variantLookupServiceUrl',
		descr => 'lookup service url and endpoint',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0,
		default => "https://www.niagads.org/genomics/service/variant"
	       }),

     stringArg({name => 'caddDatabaseDir',
		descr => 'full path to CADD database directory',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0,
	       }),

     fileArg({name => 'adspConsequenceRankingFile',
	      descr => 'full path to ADSP VEP consequence ranking file',
	      constraintFunc=> undef,
	      reqd  => 1,
	      isList => 0,
	      mustExist => 1,
	      format => 'new line delimited text'
	     }),

     booleanArg({name => 'liftOver',
		 descr => 'use UCSC liftOver to lift over to GRCh38 / TODO - generalize',
		 constraintFunc=> undef,
		 reqd  => 0,
		 isList => 0,
		}),

     stringArg({name => 'remapAssemblies',
		descr => 'from|dest assembly accessions: e.g., GCF_000001405.25|GCF_000001405.39 (GRCh37.p13|GRCh38.p13)",',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0,
	       }),

     fileArg({ name => 'liftOverChainFile',
	       descr => 'full path to liftOver chain file',
	       constraintFunc=> undef,
	       reqd => 0,
	       isList => 0,
	       mustExist => 1,
	       format => 'UCSC chain file'
	     }),


     
     stringArg({ name  => 'vepWebhook',
                 descr => "vep webhook / TODO",
                 constraintFunc => undef,
                 isList         => 0,
		 reqd => 1
	       }),

     fileArg({name => 'file',
	      descr => 'input file (do not include full path)',
	      constraintFunc=> undef,
	      reqd  => 1,
	      mustExist => 0,
	      isList => 0,
	      format => 'tab delim text'
	     }),

     stringArg({name => 'sourceId',
		descr => 'protocol app node source id',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0
	       }),

     stringArg({name => 'frequency',
		descr => '(optional) column containing freqency value',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0
	       }),

     stringArg({ name  => 'marker',
                 descr => '(optional) column containing marker name',
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),

     stringArg({ name  => 'testAllele',
                 descr => 'column containg test allele',
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),

     stringArg({ name  => 'refAllele',
                 descr => 'column containg ref allele',
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),

     stringArg({ name  => 'altAllele',
                 descr => '(optional) only specify if input has 3 allele columns (e.g., major, minor, test)',
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),

     stringArg({ name  => 'chromosome',
                 descr => 'column containg chromosome',
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),

     stringArg({ name  => 'genomeWideSignificanceThreshold',
                 descr => 'threshold for flagging result has having genome wide signficiance; provide in scientific notation',
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0,
		 default => '5e-8'
	       }),

     stringArg({ name  => 'position',
                 descr => 'column containing position',
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),

     stringArg({ name  => 'pvalue',
                 descr => 'column containing pvalue',
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),

     stringArg({ name  => 'genomeBuild',
                 descr => 'genome build for the data (GRCh37 or GRCh38)',
                 constraintFunc => undef,
                 reqd           => 1,
                 isList         => 0 
	       }),

     stringArg({ name  => 'restrictedStats',
                 descr => 'json object of key value pairs for additional scores/annotations that have restricted access',
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),

     booleanArg({ name  => 'zeroBased',
		  descr => 'flag if file is zero-based',
		  constraintFunc => undef,
		  reqd           => 0,
		  isList         => 0 
		}),


     booleanArg({ name  => 'lookupUnmappableMarkers',
		  descr => 'lookup unmappable markers',
		  constraintFunc => undef,
		  reqd           => 0,
		  isList         => 0 
		}),

     booleanArg({ name  => 'skipUnmappableMarkers',
		  descr => 'skip unmappable markers',
		  constraintFunc => undef,
		  reqd           => 0,
		  isList         => 0 
		}),

     booleanArg({ name  => 'mapPosition',
		  descr => 'flag if can map to all variants at position',
		  constraintFunc => undef,
		  reqd           => 0,
		  isList         => 0 
		}),

     booleanArg({ name  => 'isAdsp',
		  descr => 'flag if datasource is ADSP',
		  constraintFunc => undef,
		  reqd           => 0,
		  isList         => 0
		}),

     booleanArg({ name  => 'mapThruMarker',
		  descr => 'flag if can only be mapped thru marker',
		  constraintFunc => undef,
		  reqd           => 0,
		  isList         => 0 
		}),


     booleanArg({ name  => 'allowAlleleMismatches',
		  descr => 'flag if map to marker even in alleles do not match exactly',
		  constraintFunc => undef,
		  reqd           => 0,
		  isList         => 0 
		}),

     booleanArg({ name  => 'markerIsMetaseqId',
		  descr => 'flag if marker is a metaseq_id; to be used with map thru marker',
		  constraintFunc => undef,
		  reqd           => 0,
		  isList         => 0 
		}),


     booleanArg({ name  => 'checkAltIndels',
		  descr => 'check for alternative variant combinations for indels, e.g.: ref:alt, alt:ref',
		  constraintFunc => undef,
		  isList         => 0,
		  reqd => 0
		}),

     booleanArg({ name  => 'markerIndicatesIndel',
		  descr => 'marker indicates whether insertion or deletion (I or D)',
		  constraintFunc => undef,
		  isList         => 0,
		  reqd => 0
		}),

     stringArg({ name  => 'customChrMap',
                 descr => 'json object defining custom mappings (e.g., {"25":"M", "Z": "5"}',
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),

     booleanArg({ name  => 'loadResult',
		  descr => 'load GWAS results, to be run after loading variants, & annotating and loading novel variants',
		  constraintFunc => undef,
		  isList         => 0,
		  reqd => 0
		}),

     booleanArg({ name  => 'preprocess',
		  descr => 'preprocess / map to DB, find & annotate novel variants',
		  constraintFunc => undef,
		  isList         => 0,
		  reqd => 0
		}),

     booleanArg({ name  => 'standardizeResult',
		  descr => 'generate standardized files for storage in the data repository; one p-values only; one complete, can be done along w/--loadResult',
		  constraintFunc => undef,
		  isList         => 0,
		  reqd => 0
		}),


     booleanArg({ name  => 'loadVariants',
		  descr => 'load variants & identify novel variants; for first pass',
		  constraintFunc => undef,
		  isList         => 0,
		  reqd => 0
		}),

  
     booleanArg({ name  => 'findNovelVariants',
		  descr => 'find novel variants, no inserts/updates',
		  constraintFunc => undef,
		  isList         => 0,
		  reqd => 0
		}),

     booleanArg({ name  => 'preprocessAnnotatedNovelVariants',
		  descr => 'append annotated novel variants to preprocess file',
		  constraintFunc => undef,
		  isList         => 0,
		  reqd => 0
		}),

     booleanArg({ name  => 'annotateNovelVariants',
		  descr => 'annotate novel variants found after load',
		  constraintFunc => undef,
		  isList         => 0,
		  reqd => 0
		}),

     booleanArg({ name  => 'skipMetaseqIdValidation',
		  descr => 'for dataset with large numbers of non-standard ids',
		  constraintFunc => undef,
		  isList         => 0,
		  reqd => 0
		}),

     booleanArg({ name  => 'overwrite',
		  descr => 'overwrite intermediary files',
		  constraintFunc => undef,
		  isList         => 0,
		  reqd => 0
		}),

     booleanArg({ name  => 'probe',
		  descr => 'input includes a probe field',
		  constraintFunc => undef,
		  isList         => 0,
		  reqd => 0
		}),

     booleanArg({ name  => 'resume',
		  descr => 'resume variant load; need to check against db for variants that were flagged  but not actually loaded',
		  constraintFunc => undef,
		  isList         => 0,
		  reqd => 0
		}),


     booleanArg({ name  => 'skipVep',
		  descr => 'skip VEP run; when novel variants contain INDELS takes a long time to run VEP + likelihood of running into a new consequence in the result is high; use this to use the existing JSON file to try and do the AnnotatedVDB update',
		  constraintFunc => undef,
		  isList         => 0,
		  reqd => 0
		}),

     integerArg({ name  => 'commitAfter',
		  descr => 'files matching the listed pattern (e.g., chrN)',
		  constraintFunc => undef,
		  isList         => 0,
		  default => 10000,
		  reqd => 0
		}),
    ];
  return $argumentDeclaration;
}

# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
  my $purposeBrief = 'Loads Variant GWAS result';

  my $purpose = 'Loads Variant GWAS result in multiple passes: 1) lookup against AnnotatedVDB & flag novel variants; output updated input file w/mapped record PK & bin_index, 2) annotate novel variants and update new annotated input file, 3) sort annotated input file by position and update/insert into NIAGADS.Variant and annotatedVDB 4)load GWAS results, 5) output standardized files for NIAGADS repository';

  my $tablesAffected = [['Results::VariantGWAS', 'Enters a row for each variant feature'], ['NIAGAD::Variant', 'Enters a row for each variant when insertMissingVariants option is specified']];

  my $tablesDependedOn = [['Study::ProtocolAppNode', 'lookup analysis source_id']];

  my $howToRestart = '';

  my $failureCases = '';

  my $notes = <<NOTES;

Written by Emily Greenfest-Allen
Copyright Trustees of University of Pennsylvania 2019. 
NOTES

  my $documentation = {purpose=>$purpose, purposeBrief=>$purposeBrief, tablesAffected=>$tablesAffected, tablesDependedOn=>$tablesDependedOn, howToRestart=>$howToRestart, failureCases=>$failureCases, notes=>$notes};

  return $documentation;
}

# ----------------------------------------------------------------------
# create and initalize new plugin instance.
# ----------------------------------------------------------------------

sub new {
  my ($class) = @_;
  my $self = {};
  bless($self,$class);

  my $documentation = &getDocumentation();
  my $argumentDeclaration = &getArgumentsDeclaration();

  $self->initialize({requiredDbVersion => 4.0,
		     cvsRevision       => '$Revision: 9$',
		     name => ref($self),
		     revisionNotes => '',
		     argsDeclaration => $argumentDeclaration,
		     documentation => $documentation
		    });
  return $self;
}

# ----------------------------------------------------------------------
# run method to do the work
# ----------------------------------------------------------------------

sub run {
  my ($self) = @_;

  $self->initializePlugin();

  $self->liftOver() if ($self->getArg('liftOver'));
  $self->preprocess() if ($self->getArg('preprocess'));

  # $self->findNovelVariants($file, 0) if ($self->getArg('findNovelVariants')); # 0 => create new preprocess file
  #$self->findNovelVariants($file, 1)
  #  if ($self->getArg('preprocessAnnotatedNovelVariants')); # needs to be done in a separate call b/c of FDW lag
  $self->annotateNovelVariants()  if ($self->getArg('annotateNovelVariants'));
  $self->loadVariants() if ($self->getArg('loadVariants'));
  $self->loadStandardizedResult() # so that we only have to iterate over the file once; do this simulatenously
    if ($self->getArg('loadResult') or $self->getArg('standardizeResult'));
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

  if ($self->getArg('liftOver')) {
    $self->{gus_config} = {GRCh37 => $self->getArg('sourceGenomeBuildGusConfig'),
			   GRCh38 => undef}; # will use plugin default
  }
  else {
    $self->{gus_config}->{$self->getArg('genomeBuild')} = undef;
  }

  $self->{protocol_app_node_id} = $self->getProtocolAppNodeId(); # verify protocol app node

  $self->{annotator} = VariantAnnotator->new({plugin => $self});
  $self->{annotator}->createQueryHandles();
  $self->{housekeeping} = PluginUtils::buildHouseKeepingString($self);
  $self->{files} = {};

  my $sourceId = $self->getArg('sourceId');
  if ($self->getArg('liftOver')) {
    $sourceId =~ s/_GRCh38//g;
  }

  $self->{adj_source_id} = $sourceId;
  $self->{root_file_path} = $self->getArg('fileDir') . "/" . $self->getArg('genomeBuild') . "/";
  my $workingDir =   PluginUtils::createDirectory($self, $self->{root_file_path}, $self->{adj_source_id});
  $self->{working_dir} = $workingDir;
  
}


sub verifyArgs {
  my ($self) = @_;

  if ($self->getArg('findNovelVariants')) {
    $self->error("must specify testAllele") if (!$self->getArg('testAllele') and !$self->getArg('marker') and !$self->getArg('markerIsMetaseqId'));
    $self->error("must specify refAllele") if (!$self->getArg('refAllele') and !$self->getArg('marker'));
    $self->error("must specify pvalue") if (!$self->getArg('pvalue'));
    $self->error("must specify marker if mapping through marker") 
      if ($self->getArg('mapThruMarker') and !$self->getArg('marker'));
  }

  if ($self->getArg('liftOver')) {
    $self->error("must specify liftOver chain file") if (!$self->getArg('liftOverChainFile'));
    $self->error("must specify gus.config file for source genome build") if (!$self->getArg('sourceGenomeBuildGusConfig'));
  }
}


sub getProtocolAppNodeId {
  my ($self) = @_;
  my $protocolAppNode = GUS::Model::Study::ProtocolAppNode
    ->new({source_id => $self->getArg('sourceId')});
  $self->error("No protocol app node found for " . $self->getArg('sourceId'))
    unless $protocolAppNode->retrieveFromDB();

  return $protocolAppNode->getProtocolAppNodeId();
}


sub generateCustomChrMap {
  my ($self) = @_;
  my $json = JSON->new;
  my $chrMap = $json->decode($self->getArg('customChrMap')) || $self->error("Error parsing custom chromosome map");
  $self->log("Found custom chromosome mapping: " . Dumper(\$chrMap));
  return $chrMap;
}


sub generateStandardizedHeader {
  my ($self, $stats) = @_;
  # qw(min_frequency max_frequency frequency_se effect beta odds_ratio std_err direction het_chi_sq het_i_sq het_df het_pvalue);

  my @header = ();
  foreach my $label (@RESTRICTED_STATS_ORDER) {
    push(@header, $label) if (exists $stats->{$label});
  }

  my $json = JSON->new;
  my $rsParam = $json->decode($self->getArg('restrictedStats')) || $self->error("Error parsing restricted stats JSON");
  my @otherRSTATS = (exists $rsParam->{other}) ? @{$rsParam->{other}} : undef;
  foreach my $label (@otherRSTATS) {
    push(@header, $label) if (exists $stats->{$label});
  }

  return @header;
}


sub generateInsertStr {
  my ($self, $dbv, $data) = @_;
  my @values = ($self->{protocol_app_node_id},
		$dbv->{record_primary_key},
		$dbv->{bin_index},
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

  $self->error("$field not in file header") if (!exists $columnMap->{$field});
  return $columnMap->{$field};
}



# ----------------------------------------------------------------------
# file manipulation methods
# ----------------------------------------------------------------------

sub removeFileDuplicates {
  my ($self, $fileName) = @_;
  my $cmd = `uniq $fileName > $fileName.uniq && mv $fileName.uniq $fileName`;
}


sub sortCleanedInput {
  my ($self, $workingDir, $fileName) = @_;
  my $sortedFileName = $fileName . "-sorted.tmp";
  $self->log("Sorting cleaned input $fileName / working directory = $workingDir");
  my $cmd = `(head -n 1 $fileName && tail -n +2 $fileName | sort -T $workingDir -V -k1,1 -k2,2 ) > $sortedFileName`;
  $cmd =  `mv $sortedFileName $fileName`;
  $self->log("Created sorted file: $fileName");
}


sub writeCleanedInput {
  my ($self, $fh, $resultVariant, $fields, @values) = @_;

  my $frequencyC = ($self->getArg('frequency')) ? $fields->{$self->getArg('frequency')} : undef;
  my $frequency = (defined $frequencyC) ? $values[$frequencyC] : 'NULL';
  my $pvalueC = $fields->{$self->getArg('pvalue')};
  my ($pvalue, $negLog10p, $displayP) = $self->formatPvalue($values[$pvalueC]);

  my $restrictedStats = 'NULL';
  if ($self->getArg('restrictedStats')) {
    $restrictedStats = $self->buildRestrictedStatsJson(@values);
  }

  my $gwasFlags = $self->buildGWASFlags($pvalue, $displayP);

  # (chr bp allele1 allele2 marker metaseq_id freq1 pvalue neg_log10_p display_p gws_flags test_allele restricted_stats_json GRCh37 GRCh38);
  print $fh join("\t",
		 ($resultVariant->{chromosome},
		  $resultVariant->{position},
		  $resultVariant->{altAllele},
		  $resultVariant->{refAllele},
		  $resultVariant->{marker},
		  ($resultVariant->{metaseq_id} =~ m/NA/g) ? "NULL" : $resultVariant->{metaseq_id},
		  $frequency,
		  $pvalue,
		  $negLog10p,
		  $displayP,
		  $gwasFlags,
		  $resultVariant->{testAllele},
		  $restrictedStats,
		  "NULL",
		  "NULL"
		 )
		) . "\n";
}


sub sortPreprocessedResult {
  my ($self, $file) = @_;
  my $fileDir = $self->getArg('fileDir');
  my $filePrefix = "$fileDir/" . $self->getArg('sourceId');
  my $sortedFileName = $filePrefix . "-sorted.txt";
  if (-e $sortedFileName && !$self->getArg('overwrite')) {
    $self->log("Skipping sort; $sortedFileName already exists");
  } else {
    my $fileName = $filePrefix . "-preprocess.txt";
    $self->log("Sorting preprocessed $fileName");
    my $cmd = `(head -n 1 $fileName && tail -n +2 $fileName | sort -T $fileDir -V -k1,1 -k2,2 ) > $sortedFileName`;
    $self->log("Created sorted  file: $sortedFileName");
  }

  return $sortedFileName;
}


sub writePreprocessedResult {
  my ($self, $fh, $dbVariant, $input) = @_;

  my ($dchr, $dpos, $dref, $dalt) = split /:/, $dbVariant->{metaseq_id};
  my $chr = ($input->{chr}) ? $input->{chr} : $dchr;
  my $pos = ($input->{bp}) ? $input->{bp} : $dpos;

  # (chr bp allele1 allele2 freq1 pvalue neg_log10_p display_p gwas_flags test_allele restricted_stats_json db_variant_json);
  print $fh join("\t",
		 ($chr,
		  $pos,
		  $input->{allele1},
		  $input->{allele2},
		  $input->{freq1},
		  $input->{pvalue},
		  $input->{neg_log10_p},
		  $input->{display_p},
		  ($input->{pvalue} <= $self->getArg('genomeWideSignificanceThreshold')) ? 1 : 'NULL',
		  $input->{test_allele},
		  $input->{restricted_stats_json},
		  Utils::to_json($dbVariant)
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
  my $customChrMap = ($self->getArg('customChrMap')) ? $self->generateCustomChrMap() : undef;

  while (my ($oc, $rc) = each %$customChrMap) {
    $chrm = $rc if ($chrm =~ m/\Q$oc/);
  }

  $chrm = 'M' if ($chrm =~ m/25/);
  $chrm = 'M' if ($chrm =~ m/MT/);
  $chrm = 'X' if ($chrm =~ m/23/);
  $chrm = 'Y' if ($chrm =~ m/24/);
  return $chrm;
}


sub formatPvalue {
  my ($self, $pvalue) = @_;
  my $negLog10p = 0;

  if ($pvalue =~ m/NA/i) {
    return ("NaN", "NaN", "NaN")
  }

  return ($pvalue, "NaN", $pvalue) if ($pvalue == 0);

  if (!$pvalue) {
    return ("NaN", "NaN", "NaN")
  }

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
  my $json = JSON->new;
  my $stats = $json->decode($self->getArg('restrictedStats')) || $self->error("Error parsing restricted stats JSON");

  $RESTRICTED_STATS_FIELD_MAP = {};
  while (my ($stat, $field) = each %$stats) {
    if ($stat eq "other") {
      foreach my $fd (@$field) {
	$RESTRICTED_STATS_FIELD_MAP->{$fd} = $self->getColumnIndex($columns, $fd);
      }
    } else {
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
    } else { # otherwise replaces Infinity w/inf which will cause problems w/load b/c inf s not a number in postgres
      $stats->{$stat} = Utils::toNumber($values[$index]);
    }
  }
  return Utils::to_json($stats);
}


sub buildGWASFlags {
  my ($self, $pvalue, $displayP) = @_;
  my $flags = {$self->getArg('sourceId') => {p_value => Utils::toNumber($displayP),
					     is_gws => $pvalue <= $self->getArg('genomeWideSignificanceThreshold') ? 1: 0}};

  return Utils::to_json($flags);
}


# ----------------------------------------------------------------------
# clean and sort
# ----------------------------------------------------------------------

sub cleanAndSortInput {
  my ($self, $file) = @_;
  my $lineCount = 0;

  $self->log("INFO: Cleaning $file");

  my $filePrefix = $self->{adj_source_id};
  my $inputFileName = $self->{working_dir} . "/" . $filePrefix . '-input.txt';

  if (-e $inputFileName && !$self->getArg('overwrite')) {
    $self->log("INFO: Using existing cleaned input file: $inputFileName");
    return $inputFileName;
  }

  my $pfh = undef;
  open($pfh, '>', $inputFileName) || $self->error("Unable to create cleaned file $inputFileName for writing");
  print $pfh join("\t", @INPUT_FIELDS) . "\n";

  $pfh->autoflush(1);

  open(my $fh, $file ) || $self->error("Unable to open $file for reading");

  my $header= <$fh>;
  chomp($header);
  my @fields = split /\t/, $header;
  @fields = split /\s/, $header if (scalar @fields == 1);
  @fields = split /,/, $header  if (scalar @fields == 1);

  my %columns = map { $fields[$_] => $_ } 0..$#fields;
  if ($self->getArg('restrictedStats')) {
    $self->generateRestrictedStatsFieldMapping(\%columns) if (!$RESTRICTED_STATS_FIELD_MAP);
  }

  my $testAlleleC = ($self->getArg('testAllele')) ? $self->getColumnIndex(\%columns, $self->getArg('testAllele')) : undef;
  my $refAlleleC = ($self->getArg('refAllele')) ? $self->getColumnIndex(\%columns, $self->getArg('refAllele')) : undef;
  my $altAlleleC = ($self->getArg('altAllele')) ? $self->getColumnIndex(\%columns, $self->getArg('altAllele')) : undef;
  my $chrC = ($self->getArg('chromosome')) ? $self->getColumnIndex(\%columns, $self->getArg('chromosome')) : undef;
  my $positionC = ($self->getArg('position')) ? $self->getColumnIndex(\%columns, $self->getArg('position')) : undef;
  my $markerC = ($self->getArg('marker')) ? $self->getColumnIndex(\%columns, $self->getArg('marker')) : undef;

  while (my $line = <$fh>) {
    chomp $line;
    my @values = split /\t/, $line;
    @values = split /\s/, $line if (scalar @values == 1);
    @values = split /,/, $line if (scalar @values == 1);

    my $marker = (defined $markerC) ? $values[$markerC] : undef;
    my $chromosome = undef;
    my $position = undef;
    my $metaseqId = undef;

    my $ref = ($refAlleleC)? uc($values[$refAlleleC]) : undef;
    my $alt = ($altAlleleC) ? uc($values[$altAlleleC]) : ($testAlleleC) ? uc($values[$testAlleleC]) : undef;
    my $test = ($testAlleleC) ? uc($values[$testAlleleC]) : undef;

    $ref = '?' if ($ref =~ m/^0$/); # vep can still process the '?', so do the replacement here for consistency 
    $alt = '?' if ($alt =~ m/^0$/);
    $test = '?' if ($test =~ m/^0$/);

    my $frequencyC = ($self->getArg('frequency')) 
      ? $self->getColumnIndex(\%columns, $self->getArg('frequency')) : undef;
    my $frequency = ($frequencyC) ? $values[$frequencyC] : undef;

    if (defined $chrC) {
      $chromosome = $values[$chrC];
      if ($chromosome =~ m/:/) {
	($chromosome, $position) = split /:/, $chromosome;
      } elsif ($chromosome =~ m/-/) {
	($chromosome, $position) = split /-/, $chromosome;
      } else { 
	$self->error("must specify position column") if (!$positionC);
	$position = $values[$positionC];
      }
      $position = $position + 1 if $self->getArg('zeroBased');
      if ($position == 0) { # mapping issue/no confidence in rsId either so skip
	$self->log("INFO: Skipping variant $metaseqId -- BP = 0");
	next;
      }

      $chromosome = $self->correctChromosome($chromosome);

      if ($alt =~ /-/) { # deletion -- note: zeros may be deletions, but unsure so treating as unknown,  see above
	# in a VCF deletions must provide the anchor nucleotide preceeding the change, with position being 1 base before the change
	# in files where alt is '-', the $ref allele is actually the alt (what is deleted)
	# updates -- extract sequence from pos-1 to pos + 1 and assign to ref, set pos = pos - 1

	# for now assuming that this is for SNVs only
	# throw error to handle MNVs if occassion arises
	$self->error("NOT YET IMPLEMENTED: MNV deletion represented as '-' for test allele: $chromosome:$position$ref:$alt")
	  if (length $ref > 1);

	$position = $position - 1;
	$alt = $ref;
	$ref = $self->{annotator}->getSnvDeletion('chr' . $chromosome, $position);
	$test = ($test =~ /-/) ? $alt : ref;
	$self->log("WARNING: improper deletion: $chromosome:" . ($position + 1) . ":$alt:-; UPDATED TO: $chromosome:$position:$ref:$alt");
      }

      if ($self->getArg('mapPosition')) {
	$metaseqId = $chromosome . ':' . $position;
      } else {
	$metaseqId = $chromosome . ':' . $position . ':';

	my $isIndel = (length($ref) > 1 || length($alt) > 1);

	if ($isIndel && $self->getArg('markerIndicatesIndel')) {
	  if ($marker =~ m/I$/) {
	    $metaseqId .= (length($ref) > length($alt)) ? $alt . ':' . $ref : $ref . ':' . $alt;
	  } elsif ($marker =~ m/D$/) {
	    $metaseqId .= (length($ref) > length($alt)) ? $ref . ':' . $alt : $alt . ':' . $ref;
	  } else {		# incl merged_del (true indels)
	    $metaseqId .= $ref . ':' . $alt;
	  }
	} else { # for SNVs if frequency > 0.5, then the test allele is the major allele; saves us some lookup time
	  $metaseqId .= ($frequencyC and $frequency > 0.5) ? $alt . ':' . $ref : $ref . ':' . $alt;
	}
      }
    }

    $marker = undef if ($chrC eq $markerC);

    if ($chromosome eq "NA" || $self->getArg('mapThruMarker')) {
      $metaseqId = $marker if ($self->getArg('markerIsMetaseqId')); # yes ignore all that processing just did; easy fix added later

      # some weird ones are like chr:ps:ref:<weird:alt:blah:blah>
      my ($c, $p, $r, $a) = split /\<[^><]*>(*SKIP)(*FAIL)|:/, $metaseqId; 
      $chromosome = $self->correctChromosome($c);
      $position = $p;

      if ($self->getArg('markerIsMetaseqId')) {
	$alt = $self->cleanAllele($a);
      	$ref = $self->cleanAllele($r);
	$test = ($test) ? $self->cleanAllele($test) : $alt; # assume testAllele is alt if not specified
      }

      $metaseqId = join(':', $chromosome, $position, $ref, $alt); # in case chromosome/alleles were corrected
    }

    $self->error("--testAllele not specified and unable to extract from marker.  Must specify 'testAllele'") if (!$test);

    my $rv = {chromosome => $chromosome, position => $position, refAllele => $ref, altAllele => $alt, testAllele => $test, marker => $marker, metaseq_id => $metaseqId};
    $self->writeCleanedInput($pfh, $rv, \%columns, @values);

    if (++$lineCount % 500000 == 0) {
      $self->log("INFO: Cleaned $lineCount lines");
    }
  }

  $self->log("INFO: Cleaned $lineCount lines");
  $self->sortCleanedInput($self->{working_dir}, $inputFileName);
  return $inputFileName;
}				# end cleanAndSortInput

# ----------------------------------------------------------------------
# query against DB to find GRCh38 mappings
# not done in clean and sort so can do it in bulk, instead of line by
# line
# ----------------------------------------------------------------------

# LOOKUP Result
# "1:2071765:G:A": {
#   "bin_index": "chr1.L1.B1.L2.B1.L3.B1.L4.B1.L5.B1.L6.B2.L7.B1.L8.B1.L9.B1.L10.B1.L11.B2.L12.B1.L13.B1",
#   "annotation": {
#     "GenomicsDB": [
#       "ADSP_WGS",
#       "NG00027_STAGE1"
#     ],
#     "mapped_coordinates": null
#   },
#   "match_rank": 2,
#   "match_type": "switch",
#   "metaseq_id": "1:2071765:A:G",
#   "ref_snp_id": "rs364677",
#   "is_adsp_variant": true,
#   "record_primary_key": "1:2071765:A:G_rs364677"
# },

# if firstValueOnly == false, then {"1:2071765:G:A": [{},{}]}

sub updateDBMappedInput {
  my ($self, $lookup, $mapping, $genomeBuild) = @_;

  $genomeBuild //= $self->getArg('genomeBuild');
  my $mappedBuild = ($genomeBuild eq 'GRCh37') ? 'GRCh38' : 'GRCh37';


  my ($chromosome, $position, @alleles) = split /:/, $$mapping[0]->{metaseq_id};
  my @matchedVariants;
  foreach my $variant (@$mapping) {
    my $ids = {ref_snp_id => $variant->{ref_snp_id},
	       genomicsdb_id => $variant->{record_primary_key}};
    push(@matchedVariants, $ids);
  }

  my $currentCoordinates = { chromosome => $chromosome,
			     location => int($position),
			     metaseq_id => $$mapping[0]->{metaseq_id},
			     matched_variants => \@matchedVariants};

  my $row = $lookup->{row};
  $row->{$genomeBuild} = Utils::to_json($currentCoordinates);

  my $mappedCoordinates = $$mapping[0]->{mapped_coordinates}; # should be the same even if multiple rsIds for the metaseq

  $row->{$mappedBuild} = (defined $mappedCoordinates && exists $mappedCoordinates->{$mappedBuild})
    ? Utils::to_json($mapping->{$mappedBuild})
    : $row->{$mappedBuild} ne 'NULL' ? $row->{$mappedBuild} : 'NULL';

  # handle marker only mappings
  if ($row->{chr} =~ /NA/ || $row->{metaseq_id} eq 'NULL') {
    $row->{chr} = $chromosome;
    $row->{bp} = int($position);
    $row->{metaseq_id} = $$mapping[0]->{metaseq_id};
  }

  return join("\t", @$row{@INPUT_FIELDS});
}


sub submitDBLookupQuery {
  my ($self, $genomeBuild, $lookups, $file) = @_;

  # only scalars can be passed to threads, so need to rebless plugin
  bless $self, 'GenomicsDBData::Load::Plugin::LoadVariantGWASResult';

  eval {
    my $recordHandler = VariantRecord->new({gus_config_file => $self->{gus_config}->{$genomeBuild},
					    genome_build => $genomeBuild,
					    plugin => $self});

    $recordHandler->setFirstValueOnly(0);

    my $mappings = $recordHandler->lookup(keys %$lookups);

    $SHARED_VARIABLE_SEMAPHORE->up;
    foreach my $vid (keys %$mappings) {
      next if (!defined $mappings->{$vid}); # "null" returned
      $$file[$lookups->{$vid}->{index}] = $self->updateDBMappedInput($lookups->{$vid}, $mappings->{$vid}, $genomeBuild);
    }
    undef $mappings; # b/c threads don't free memory until exit
    undef $lookups;
    undef $recordHandler;
    $SHARED_VARIABLE_SEMAPHORE->up;
    $PROCESS_COUNT_SEMAPHORE->up;
    return "SUCCESS";
  } or do {
    $PROCESS_COUNT_SEMAPHORE->up;
    return $@;
  }
}


sub monitorThreads {
  my ($self, $fail, $errors, @threads) = @_;

  foreach (@threads) {
    if ($_->is_joinable()) {
      my $result = $_->join;
      if ($result ne "SUCCESS") {
	push(@$errors, $result);
	$fail = 1;
      }
    }
  }
  return $fail, @$errors;
}


sub DBLookup {	# check against DB
  # note: this is a simplistic approach / does not handle outlying cases such as chr:pos:test_allele
  # these will have to be handled by liftOver & findNovelVariant combined / too many checks
  my ($self, $inputFileName, $genomeBuild, $useMarker) = @_;

  $self->error("DB Mapping to position / alternative alleles not yet implemented")
    if ($self->getArg('mapPosition') || $self->getArg('allowAlleleMismatches'));

  $genomeBuild //= $self->getArg('genomeBuild');

  $self->log("INFO: Querying existing DB mappings / refsnp:alleleStr and metaseq id matches only");
  my $gusConfig = ($self->{gus_config}->{$genomeBuild}) ? $self->{gus_config}->{$genomeBuild} : "default";
  $self->log("INFO: Source Genome Build: $genomeBuild / GUS Config File: $gusConfig");

  my $outputFileName = "$inputFileName.dbmapped";

  if (-e $outputFileName && !$self->getArg('overwrite')) {
    $self->log("INFO: Using existing DBLookup file $outputFileName");
    return $outputFileName;
  }

  my $linePtr;
  share($linePtr);
  open(my $fh, $inputFileName) || $self->error("Unable to open input file $inputFileName for reading");
  my @lines :shared = read_file($fh, chomp => 1);
  # my @lines = read_file($fh, chomp => 1);
  $fh->close();
  $linePtr = \@lines;

  my $header = $lines[0];
  chomp($header);
  my @fields = split /\t/, $header;

  my $lookupCount = 0;
  my $json = JSON::XS->new();
  my $lookups;
  my $lineCount = 0;

  my @threads;
  my $fail = 0;
  my @errors;
  while (my ($index, $line) = each @lines) {
    next if ($index == 0);

    # I know, should be at end, but this way can count correctly & skip loop
    # processing where necessary
    $self->log("INFO: Processed $lineCount lines") if (++$lineCount % 100000 == 0);

    # chomp $line;
    my @values = split /\t/, $line;
    my %row;
    @row{@fields} = @values;

    # DBLookup may be called several times, if the lookup has already been done, don't do it again
    next if ($row{$genomeBuild} ne 'NULL');

    my $variantId = $row{metaseq_id};

    if (($self->getArg('mapThruMarker') && !$self->getArg('markerIsMetaseqId'))
	|| $useMarker
	|| ($row{chr} =~ /NA/ || $row{metaseq_id} eq 'NULL')) {
      $variantId = join(":", $row{marker}, $row{allele1}, $row{allele2});
    }

    $lookups->{$variantId}->{index} = $index;
    $lookups->{$variantId}->{line} = $line;
    $lookups->{$variantId}->{row} = \%row;

    # LOOKUP Result
    # "1:2071765:G:A": {
    #   "bin_index": "chr1.L1.B1.L2.B1.L3.B1.L4.B1.L5.B1.L6.B2.L7.B1.L8.B1.L9.B1.L10.B1.L11.B2.L12.B1.L13.B1",
    #   "annotation": {
    #     "GenomicsDB": [
    #       "ADSP_WGS",
    #       "NG00027_STAGE1"
    #     ],
    #     "mapped_coordinates": null
    #   },
    #   "match_rank": 2,
    #   "match_type": "switch",
    #   "metaseq_id": "1:2071765:A:G",
    #   "ref_snp_id": "rs364677",
    #   "is_adsp_variant": true,
    #   "record_primary_key": "1:2071765:A:G_rs364677"
    # },

    if (++$lookupCount % 10000 == 0) {
      $PROCESS_COUNT_SEMAPHORE->down;
      my $thread = threads->create(\&submitDBLookupQuery, $self, $genomeBuild, $lookups, $linePtr);
      undef $lookups;
      push(@threads, $thread);
      $self->monitorThreads($fail, \@errors, @threads);
    } # end do lookup
  }				# end iterate over file

  # residuals
  if ($lookups) {
    $PROCESS_COUNT_SEMAPHORE->down;
    my $thread = threads->create(\&submitDBLookupQuery, $self, $genomeBuild, $lookups, $linePtr);
    undef $lookups;
    push(@threads, $thread);
  }

  while (my @running = threads->list(threads::running)) {
    $self->monitorThreads($fail, \@errors, @threads);
  }
  $self->monitorThreads($fail, \@errors, @threads); # residuals after no more are running

  $self->error("Parallel DB Query failed: " . Dumper(\@errors)) if ($fail);
  $self->log("DONE: Queried $lineCount variants");

  $lineCount = 0;
  $self->log("INFO: Creating $outputFileName file with GRCh37 database lookups");
  open(my $ofh, '>', $outputFileName) || $self->error("Unable to open cleaned input file $outputFileName for updating");
  foreach my $line (@lines) {
    print $ofh "$line\n";
    $self->log("INFO: Wrote $lineCount lines") if (++$lineCount % 500000 == 0);
  }
  $ofh->close();

  $self->log("DONE: Wrote $lineCount lines");

  $self->sortCleanedInput($self->{working_dir}, $outputFileName);
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
# ----------------------------------------------------------------------


sub liftOver {
  my ($self) = @_;

  my $file = $self->{root_file_path} . $self->getArg('file');
  $self->log("INFO: Beginning LiftOver process on $file");

  my $rootFilePath =   PluginUtils::createDirectory($self, $self->getArg('fileDir'), "GRCh38");
  my $workingDir =   PluginUtils::createDirectory($self, $rootFilePath, $self->getArg('sourceId'));
  my $resultFileName = $workingDir . "/" . $self->getArg('sourceId') . "-input.txt";

  # do liftOver
  my $inputFileName = $self->cleanAndSortInput($file);
  my $dbmappedFileName = $self->DBLookup($inputFileName);
  
  my ($nUnliftedVariants, $sourceBedFileName) = $self->input2bed($dbmappedFileName);
  $self->log("Number of unlifted variants found = $nUnliftedVariants");
  if ($nUnliftedVariants > 0) {
    my $mappedBedFileName = $self->runUCSCLiftOver($sourceBedFileName);
    # find issues
    my ($cleanedLiftOverFileName, $unmappedLiftOverFileName) =
      $self->cleanMappedBedFile($mappedBedFileName, $sourceBedFileName, "liftOver");

    # handle unmapped & add in
    #   run against NCBI Remap
    my $remapFileName = $self->remapBedFile($unmappedLiftOverFileName);
    my ($cleanedRemapFileName, $unmappedRemapFileName) =
      $self->cleanMappedBedFile($remapFileName, $unmappedLiftOverFileName, "remap");

    # lookup remap-unmapped in GRCh38 database
    # lookup marker only in GRCh38 database
    my $residualUnmappedFileName = $self->bed2input($unmappedRemapFileName, undef, $INCLUDE_MARKERS, $NEW_FILE);
    my $residualDBMappedFile = $self->DBLookup($residualUnmappedFileName, 'GRCh38', $USE_MARKER);
    my $markerOnlyDBMappedFile = $self->DBLookup("$dbmappedFileName.unmapped.markerOnly", 'GRCh38', $USE_MARKER);

    # dbmapping input, ucsc lift over, remap, remap-unmapped
    my ($r, $fromDBLookup) = $self->liftOverFromDBMappedFile($dbmappedFileName, $resultFileName);
    $self->liftOverFromDBMappedFile($residualDBMappedFile, $resultFileName, $APPEND);
    $self->liftOverFromDBMappedFile($markerOnlyDBMappedFile, $resultFileName, $APPEND);
    $self->bed2input($cleanedRemapFileName, $resultFileName, $DROP_MARKERS, $APPEND); # append
    $self->bed2input($cleanedLiftOverFileName,  $resultFileName, $DROP_MARKERS, $APPEND);

    # summarize counts
    my $inputCount = Utils::fileLineCount($dbmappedFileName) - 1;
    my $unmappedCount = Utils::countOccurrenceInFile($residualDBMappedFile, 'genomicsdb_id', 1) +
      Utils::countOccurrenceInFile($markerOnlyDBMappedFile, 'genomicsdb_id', 1); # find lines missing the pattern
    my $mappedCount = Utils::fileLineCount($resultFileName) - 1;
    my $fromUSCliftOver = Utils::fileLineCount($cleanedLiftOverFileName);
    my $fromRemap = Utils::fileLineCount($cleanedRemapFileName);
    my $fromMarker = Utils::countOccurrenceInFile($residualDBMappedFile, 'genomicsdb_id') - 1  +
      Utils::countOccurrenceInFile($markerOnlyDBMappedFile, 'genomicsdb_id') - 1;
    
    my $counts = {mapped => $mappedCount, unmapped => $unmappedCount, GRCh38_marker_AnnotatedVDB => $fromMarker,
		  GRCh37_AnnotatedVDB => $fromDBLookup, liftOver => $fromUSCliftOver, Remap => $fromRemap,
		  original_input => $inputCount, percent_mapped => $mappedCount / $inputCount,
		  percent_unmapped => $unmappedCount / $inputCount };
    
    $self->log("INFO: DONE with liftOver " . Dumper($counts));
  }
  else {
    my $fromMarker = Utils::countOccurrenceInFile("$dbmappedFileName.unmapped.markerOnly", 'genomicsdb_id') - 1;
    my $mappedCount = Utils::countOccurrenceInFile("$dbmappedFileName", 'genomicsdb_id') - 1 - $fromMarker;
    $self->liftOverFromDBMappedFile($dbmappedFileName, $resultFileName);
    
    if ($fromMarker > 0) {
      my $markerOnlyDBMappedFile = $self->DBLookup("$dbmappedFileName.unmapped.markerOnly", 'GRCh38');
      $self->liftOverFromDBMappedFile($markerOnlyDBMappedFile, $resultFileName);
      my $unmappedCount = Utils::countOccurrenceInFile($markerOnlyDBMappedFile, 'genomicsdb_id', 1); # find lines missing the pattern
      $self->log("Marker-only Unmapped: $unmappedCount");
    }
    $self->log("DONE: Done with liftOver / $mappedCount variants mapped via DB query / markerOnly = $fromMarker");
  }

  $self->sortCleanedInput($workingDir, $resultFileName);

  return $resultFileName;
}


sub runUCSCLiftOver {
  my ($self, $sourceBedFile) = @_;
  my $chainFile = $self->getArg('liftOverChainFile');
  $self->log("INFO: Performing UCSC liftOver on $sourceBedFile using chain: $chainFile");

  # USAGE: liftOver oldFile map.chain newFile unMapped
  my $filePath = $self->{working_dir} . "/liftOver/";
  my $filePrefix = $self->{adj_source_id};
  my $errorFile = $sourceBedFile . ".unmapped";
  my $mappedBedFileName = $filePath . $filePrefix . "-GRCh38.bed";
  
  if (-e $mappedBedFileName && !$self->getArg('overwrite')) {
    $self->log("INFO: Using existing liftOver file: $mappedBedFileName");
    return $mappedBedFileName;
  }

  my @cmd = ('liftOver',
	     $sourceBedFile,
	     $chainFile,
	     $mappedBedFileName,
	     $errorFile);

  $self->log("INFO: Running liftOver: " . join(' ', @cmd));
  my $status = qx(@cmd);

  $self->log("INFO: Done with UCSC liftOver");
  my $nUnmapped = Utils::fileLineCount($errorFile);
  $self->log("WARNING: Not all variants mapped, see: $errorFile (n = $nUnmapped") if ($nUnmapped > 0);
  return $mappedBedFileName;
}

sub liftOverFromDBMappedFile {
  my ($self, $inputFileName, $outputFileName, $append) = @_;
  $append //= 0;
  my $lineCount = 0;
  if (-e $outputFileName && !$self->getArg('overwrite') && !$append) {
    $self->log("INFO: Using existing DB-based liftOver file: $outputFileName");
    return $outputFileName;
  } else {
    if (-e $outputFileName && ($append)) {
      $self->log("INFO: DB Mapping liftOver - Appending DB mappings to input file: $outputFileName");
    }
    else {
      $self->log("INFO: DB Mapping liftOver - Creating input file: $outputFileName from bed file $inputFileName");
    }

    my $ofh;
    if ($append) {
      open($ofh, '>>', $outputFileName) || $self->error("Unable to create $outputFileName for writing");
    }
    else {
      open($ofh, '>', $outputFileName) || $self->error("Unable to create $outputFileName for writing");
      print $ofh join("\t", @INPUT_FIELDS) . "\n";
    }
    open(my $fh, '<', $inputFileName) || $self->error("Unable to create $outputFileName for writing");
    my $header = <$fh>;
    
    my $json = JSON::XS->new();
    while (my $line = <$fh>) {
      chomp $line;
      my @values = split /\t/, $line;
      my %row;
      @row{@INPUT_FIELDS} = @values;

      my $mappingStr = $row{GRCh38};
      next if ($mappingStr eq 'NULL');

      my $mapping = $json->decode($mappingStr);
      my $chromosome = $mapping->{chromosome};
      $chromosome =~ s/chr//g;
      $row{chr} = $chromosome;
      $row{bp} = int($mapping->{location});
      $row{metaseq_id} = $mapping->{metaseq_id};
      my $newMarker= ${$mapping->{matched_variants}}[0]->{ref_snp_id};
      $row{marker} = ($newMarker) ? $newMarker : 'NULL';

      if ($row{GRCh37} eq 'NULL') {
	my $currentCoordinates = { chromosome => $row{chr},
				   location => int($row{bp}),
				   metaseq_id => $row{metaseq_id}};
	$row{GRCh37} = Utils::to_json($currentCoordinates);
      }

      print $ofh join("\t", @row{@INPUT_FIELDS}) . "\n";
      $self->log("INFO: Wrote $lineCount lines") if (++$lineCount % 500000 == 0);
    }
    $ofh->close();
    $fh->close();
    $self->log("INFO: Wrote $lineCount lines");
    $self->log("DONE: Adding $inputFileName to liftOver final output: $outputFileName");
  }
  return $outputFileName, $lineCount;
}



# ----------------------------------------------------------------------
# find novel
# ----------------------------------------------------------------------


# ----------------------------------------------------------------------
# load
# ----------------------------------------------------------------------

sub loadStandardizedResult {
  my ($self) = @_;
  my $totalVariantCount = 0;
  my $insertStrBuffer = "";
  my $commitAfter = $self->getArg('commitAfter');
  my $hasFreqData = $self->getArg('frequency') ? 1: 0;

  my @sfields = qw(chr bp allele1 allele2 pvalue);
  my @rfields = undef;

  my $fileName = $self->sortPreprocessedResult(); # should already exist, so should just return filename
  open(my $fh, $fileName ) || $self->error("Unable to open $fileName for reading");
  <$fh>;			# throw away header

  my $path = PluginUtils::createDirectory($self, $self->getArg('fileDir'), "standardized");
  my $standardizedFileName = $path . "/" . $self->getArg('sourceId') . ".txt";
  open(my $sfh, '>', $standardizedFileName) || $self->rror("Unable top open $standardizedFileName for writing.");
  $sfh->autoflush(1);

  my $pvalueFileName = $path . "/" . $self->getArg('sourceId') . "-pvalues-only.txt";
  open(my $pfh, '>', $pvalueFileName) || $self->rror("Unable top open $pvalueFileName for writing.");
  $pfh->autoflush(1);

  my @sheader = qw(chr bp effect_allele non_effect_allele pvalue);
  my %row; # (chr bp allele1 allele2 freq1 pvalue neg_log10_p display_p gwas_flags test_allele restricted_stats_json db_variant_json);
  while (<$fh>) {
    chomp;
    @row{@RESULT_FIELDS} = split /\t/;

    my $json = JSON->new();
    my $restrictedStats = $json->decode($row{restricted_stats_json}) || $self->error("Error parsing restricted stats json: " . $row{restricted_stats_json});

    if ($totalVariantCount == 0) {
      unshift @sheader, "variant";
      unshift @sheader, "marker";
      push(@sheader, "probe") if ($self->getArg('probe'));
      print $pfh join("\t", @sheader) . "\n";

      push(@sheader, "frequency") if ($hasFreqData);
      @rfields = $self->generateStandardizedHeader($restrictedStats);
      push(@sheader, @rfields);
      print $sfh join("\t", @sheader) . "\n";
    }

    my $dbv = $json->decode($row{db_variant_json}) || $self->error("Error parsing dbv json: " . $row{db_variant_json});
    my $marker = ($dbv->{ref_snp_id}) ? $dbv->{ref_snp_id} : Utils::truncateStr($dbv->{metaseq_id}, 20);

    my @cvalues = @row{@sfields};
    unshift @cvalues, $dbv->{metaseq_id};
    unshift @cvalues, $marker;
    push(@cvalues, $restrictedStats->{probe}) if ($self->getArg('probe'));
    my $oStr = join("\t", @cvalues);
    $oStr =~ s/NaN/NA/g;	# replace any DB nulls with NAs
    $oStr =~ s/Infinity/Inf/g;	# replace any DB Infinities with Inf
    print $pfh "$oStr\n";

    push(@cvalues, $row{freq1}) if ($hasFreqData);
    push(@cvalues, @$restrictedStats{@rfields});
    $oStr = join("\t", @cvalues);
    $oStr =~ s/NaN/NA/g;	# replace any DB nulls with NAs
    $oStr =~ s/Infinity/Inf/g;	# replace any DB Infinities with Inf
    print $sfh "$oStr\n";

    ++$totalVariantCount;
    if ($self->getArg('loadResult')) {
      $insertStrBuffer .= $self->generateInsertStr($dbv, \%row);
      unless ($totalVariantCount % $commitAfter) {
	$self->log("INFO: Found $totalVariantCount result records; Performing Bulk Inserts");
	PluginUtils::bulkCopy($self, $insertStrBuffer, $COPY_SQL);
	$insertStrBuffer = "";
      }
    }
    unless ($totalVariantCount % 10000) {
      $self->log("INFO: Read $totalVariantCount lines");
      $self->undefPointerCache();
    }
  }

  # residuals
  if ($self->getArg('loadResult')) {
    $self->log("INFO: Found $totalVariantCount result records; Performing Bulk Inserts");
    PluginUtils::bulkCopy($self, $insertStrBuffer, $COPY_SQL);
    $insertStrBuffer = "";
    $self->log("DONE: Inserted $totalVariantCount result records.");
  }

  $self->log("INFO: Checking standardized output for duplicate values (from marker-based matches)");
  $self->removeFileDuplicates($standardizedFileName);
  $self->removeFileDuplicates($pvalueFileName);
  $self->log("DONE: Wrote standardized output: $standardizedFileName");
  $self->log("DONE: Wrote standardized output pvalues only: $pvalueFileName");

  $fh->close();
  $sfh->close();
}


sub annotateNovelVariants {
  my ($self) = @_;

  my $fileName = $self->getArg('fileDir') . "/" . $self->getArg('sourceId') . "-novel.vcf";
  my $lineCount = `wc -l < $fileName`;
  if ($lineCount > 1) {
    $self->log("INFO: Annotating variants in: $fileName");
    $fileName = $self->{annotator}->sortVcf($fileName);
    $self->{annotator}->runVep($fileName) if (!$self->getArg('skipVep'));
    $self->{annotator}->loadVepAnnotatedVariants($fileName);
    $self->{annotator}->loadNonVepAnnotatedVariants($fileName);
    $self->{annotator}->loadCaddScores($fileName);
  } else {
    $self->log("INFO: No novel variants found in: $fileName");
  }
}


sub queryGenomicsDBVariantLookupService {
  my ($self, $lookupHash) = @_;

  my $pua = LWP::Parallel::UserAgent->new();
  $pua->in_order  (1);	    # handle requests in order of registration
  $pua->duplicates(0);	    # ignore duplicates
  $pua->timeout   (10);	    # in seconds
  $pua->redirect  (1);	    # follow redirects

  my @variants = keys %$lookupHash;
  $self->log("INFO: Beginning bulk lookup against GRCh37 AnnotatedVDB / n = " . scalar(@variants));

  my @lookups;
  my @requests;
  while (my ($index, $variantId) = each @variants) {
    if ($index == 0 || $index % 200 != 0) {
      push(@lookups, $variantId);
    } else {
      my $requestUrl = $self->getArg('variantLookupServiceUrl') . "?mscOnly&id=" . join(",", @lookups);
      push(@requests, HTTP::Request->new('GET', $requestUrl));
      @lookups = ($variantId);
    }
  }

  # residuals
  my $requestUrl = $self->getArg('variantLookupServiceUrl') . "?mscOnly&id=" . join(",", @lookups);
  push(@requests, HTTP::Request->new('GET', $requestUrl));

  foreach my $req (@requests) {
    if (my $res = $pua->register($req)) {
      print STDERR $res->error_as_HTML;
    }
  }

  my $entries = $pua->wait();

  foreach (keys %$entries) {
    my $response = $entries->{$_}->response;
    if ($response->is_success) {
      my $json = JSON::XS->new;
      my $result = $json->decode($response->content);

      $self->error("Submitted too many variants; response paged")
	if ($result->{paging}->{total_pages} > 1);

      foreach my $key (keys %{$result->{result}}) {
	$lookupHash->{$key}->{mapping} = $result->{result}->{$key};
      }
      if (defined $result->{unmapped_variants}) {
	foreach my $value (@{$result->{unmapped_variants}}) {
	  $lookupHash->{$value}->{mapping} = undef;
	}
      }
    } else {
      $self->error("Problem looking up variants ($_): ". $response->status_line);
    }
  }

  return $lookupHash;
}


sub remapBedFile {
  my ($self, $inputFileName) = @_;

  my $filePrefix =  $self->{adj_source_id};
  my $remapRootDir = PluginUtils::createDirectory($self, $self->{working_dir}, "remap");

  if (-e $inputFileName) {
    my $lineCount = Utils::fileLineCount($inputFileName);
    $self->log("WARNING: Remapping $inputFileName ($lineCount lines)");
    $self->error("Too many unmapped variants in $inputFileName - $lineCount") if ($lineCount > 50000);

    #output file - remap instead of liftOver dir, GRCh38 instead of GRCh37, remapped instead of unmapped
    (my $outputFileName = $inputFileName) =~ s/-GRCh37/-GRCh38/g;
    $outputFileName =~ s/liftOver/remap/g;
    $outputFileName =~ s/unmapped/remapped/g;

    if (-e $outputFileName && !$self->getArg('overwrite')) {
      $self->log("INFO: Remapped file $outputFileName already exists");
      return $outputFileName;
    }
    
    my ($fromAssembly, $destAssembly) = split /\|/, $self->getArg('remapAssemblies');

    my @cmd = ('remap_api.pl',
	       '--mode', 'asm-asm',
	       '--in_format', 'bed',
	       '--out_format', 'bed',
	       '--from', $fromAssembly,
	       '--dest', $destAssembly,
	       '--annotation', $inputFileName,
	       '--annot_out', $outputFileName,
	       '--report_out', $outputFileName . ".report"
	      );

    $self->log("INFO: Running NCBI Remap: " . join(' ', @cmd));
    my $status = qx(@cmd);
    $self->log("INFO: Remap status: $status");
    if ($status =~ m/Saving.+report/) {
      $self->log("INFO: Done with NCBI Remap");
      return $outputFileName;
    } else {
      $self->error("NCBI Remap of $inputFileName failed");
    }
  } else {
    $self->error("Error running NCBI Remap: input file $inputFileName does not exist");
  }
}



sub cleanMappedBedFile {
  my ($self, $mappedBedFileName, $sourceBedFileName, $targetDir) = @_;
  my $workingDir = PluginUtils::createDirectory($self, $self->{working_dir}, $targetDir);

  $self->log("INFO: Cleaning mapped files");
  $self->log("INFO: Comparing $targetDir input $sourceBedFileName to mapped file $mappedBedFileName");

  # generate two files - 1) .cleaned 2) .unmapped
  my $unmappedFileName = $mappedBedFileName. ".unmapped";
  $unmappedFileName =~ s/-GRCh38/-GRCh37/g;
  my $cleanedMappedFileName = $mappedBedFileName . ".cleaned";

  if (-e $cleanedMappedFileName && !($self->getArg('overwrite'))) {
    $self->log("INFO: Using existing cleaned mapping file: $cleanedMappedFileName");
    return $cleanedMappedFileName, $unmappedFileName;
  }

  # basically, want to identify the following problems:
  # 1) still unmapped
  # 2) duplicates
  # 3) mapped against contigs
  # 4) suprisingly enough, wrong chromosome
  
  # load $ofh into hash
  my $variants;
  open(my $ofh, $sourceBedFileName ) || $self->error("Unable to open source bed file: $sourceBedFileName for reading");
  while (my $line = <$ofh>) {
    chomp($line);
    my @values = ($targetDir eq 'liftOver') ? split / /, $line : split /\t/, $line;
    my $key = $values[3];
    $variants->{$key}->{original_line} = $line;
    $variants->{$key}->{status} = 'none';
  }
  $ofh->close();

  my $altCount = 0;
  my $wrongCount = 0;
  my $mappedCount = 0;
  my $duplicateCount = 0;
  my $parsedLineCount = 0;
  my @mappedLines = read_file($mappedBedFileName, chomp => 1);
  while (my ($lineCount, $line) = each @mappedLines) {
    $parsedLineCount = $lineCount;
    my @values = split /\t/, $line;
    my $key = $values[3];
    my ($loc, $stats) = split /\|/, $key;

    my $isAltChrm = ($values[0] =~ m/_/g) ? 1 : 0;
    if ($isAltChrm) {
      $altCount++;
      $self->log("INFO: Location $loc mapped to contig - " . $values[0]) if $self->getArg('veryVerbose');
    }

    my ($origChrm, @other) = split /:/, $loc;
    my $isWrongChrm = ($values[0] ne "chr$origChrm" && !$isAltChrm) ? 1 : 0 ;
    $isWrongChrm = ($loc =~ m/lookup/) ? 0 : $isWrongChrm; # b/c we didn't have the original chrm info
    if ($isWrongChrm) {
      $wrongCount++;
      $self->log("INFO: Location $loc mapped to wrong chromosome - " . $values[0]) if $self->getArg('veryVerbose');
    }

    my $status = (exists $variants->{$key})
      ? $variants->{$key}->{status}
      : undef;

    $self->error("Variant $key in $targetDir file but not in $targetDir input.") if (!$status);

    if ($status eq 'none') {
      $mappedCount++ if (!$isAltChrm && !$isWrongChrm);
      $variants->{$key}->{status} = ($isAltChrm) ? "alt|$lineCount" :
	($isWrongChrm) ? "wrong_chrm|$lineCount" : "mapped|$lineCount";
    } else {
      if ($status =~ m/mapped/) {
	if ($isAltChrm) {
	  $self->log("INFO: Location $loc already mapped to primary assembly - ignoring contig mapping") if $self->getArg('veryVerbose');
	} elsif ($isWrongChrm) {
	  $self->log("INFO: Location $loc already mapped to primary assembly - ignoring wrong mapping") if $self->getArg('veryVerbose');
	} else {
	  $duplicateCount += 2; # original mapped + new
	  $mappedCount--;
	  my ($dupStatus, $dupLine) = split /\|/, $status;
	  $variants->{$key}->{status} = "dup|$dupLine,$lineCount";
	}
      }				# end already mapped
      if ($status =~ m/alt/) {
	if ($isWrongChrm) {
	  $self->log("INFO: Location $loc already mapped to contig - ignoring wrong mapping") if $self->getArg('veryVerbose');
	} elsif ($isAltChrm) {
	  $self->log("INFO: Location $loc already mapped to contig - ignoring contig mapping") if $self->getArg('veryVerbose');
	} else {
	  $mappedCount++;
	  $self->log("INFO: Location $loc - replacing contig mapping with mapping to primary assembly") if $self->getArg('veryVerbose');
	  $variants->{$key}->{status} = "mapped|$lineCount";
	}
      }
      if ($status =~ m/wrong/) {
	if ($isWrongChrm) {
	  $variants->{$key}->{status} = $status . ",$lineCount";
	} elsif ($isAltChrm) {
	  $self->log("INFO: Location $loc mapped to contig - replacing wrong chromosome flag") if $self->getArg('veryVerbose');
	  $variants->{$key}->{status} = "alt|$lineCount";
	} else {
	  $mappedCount++;
	  $self->log("INFO: Location $loc mapped to primary assembly - replacing wrong chromosome flag") if $self->getArg('veryVerbose');
	  $variants->{$key}->{status} = "mapped|$lineCount";
	}
      }
      if ($status =~ m/dup/) {
	if ($isAltChrm) {
	  $self->log("INFO: Location $loc already mapped to primary assembly - ignoring contig mapping") if $self->getArg('veryVerbose');
	} elsif ($isWrongChrm) {
	  $self->log("INFO: Location $loc already mapped to primary assembly - ignoring wrong mapping") if $self->getArg('veryVerbose');
	} else {
	  $duplicateCount++;
	  $variants->{$key}->{status} = $status . ",$lineCount";
	}
      }
    }
  }

  $parsedLineCount++;		# started at 0
  my $totalCount = $mappedCount + $duplicateCount + $altCount + $wrongCount;
  my $debugDiff = $totalCount - $parsedLineCount;
  $self->log("DEBUG: Total = $totalCount (Mapped = $mappedCount | Duplicate = $duplicateCount | Contigs = $altCount | Wrong = $wrongCount)");

  my $ufh;
  if (-e $unmappedFileName) { # file already exists append; e.g. add to liftOver unmapped
    # remove # lines in umapped file
    my @cmd = ('perl', '-n', '-i.bak', '-e',
	       "'print unless m/^#/'",
	       $unmappedFileName);
    qx(@cmd);

    #my $cmd = `grep -v "^#" $unmappedFileName > $unmappedFileName.tmp`;
    # $cmd = `mv $unmappedFileName.tmp $unmappedFileName`;
    open($ufh, '>>', $unmappedFileName ) || $self->error("Unable to open $unmappedFileName for appending");
  } else {
    open($ufh, '>', $unmappedFileName ) || $self->error("Unable to create $unmappedFileName for writing");
  }

  open(my $cfh, '>', $cleanedMappedFileName ) || $self->error("Unable to create $cleanedMappedFileName for writing");
  foreach my $key (keys %$variants) {
    my $statusStr = $variants->{$key}->{status};
    my ($status, $lineNum) = split /\|/, $statusStr;

    if ($status eq 'mapped') {
      print $cfh $mappedLines[$lineNum] . "\n";
    } else {		      # includes 'none's not in the remap file
      next if ($status eq 'none'); # already in unmapped file
      my $oLine = $variants->{$key}->{original_line};
      # $self->error($oLine);
      $oLine =~ s/ /\t/g;	# b/c original bed file is space delim
      $oLine =~ s/\|/:$status\|/;
      print $ufh $oLine . "\n";
    }
  }

  $cfh->close();
  $ufh->close();

  $self->log("INFO: Done checking $targetDir output");

  return $cleanedMappedFileName, $unmappedFileName;
}


sub bed2input {
  my ($self, $bedFileName, $targetFileName, $inclMarkers, $append) = @_;
  $append //= 0;
  if (!$targetFileName) {
    $targetFileName = "$bedFileName";
    $targetFileName =~ s/\.bed/-input\.txt/g;
  }

  if (-e $targetFileName && !$self->getArg('overwrite') && !$append) {
    $self->log("INFO: Using existing bed2input file: $targetFileName");
    return $targetFileName;
  } else {
    if (-e $targetFileName && ($append)) {
      $self->log("INFO: bed2input - Appending bed file $bedFileName to input file: $targetFileName");
    }
    else {
      $self->log("INFO: bed2input - Creating input file: $targetFileName from bed file $bedFileName");
    }
    
    my $ofh;
    if ($append) {
      open($ofh, '>>', $targetFileName) || $self->error("Unable to open $targetFileName for appending");
    }
    else {
      open($ofh, '>', $targetFileName) || $self->error("Unable to create $targetFileName for writing");
      print $ofh join("\t", @INPUT_FIELDS) . "\n";
    }
    
    my $json = JSON::XS->new;
    open(my $fh, $bedFileName) || $self->error("Unable to open $bedFileName for reading");
    my $lineCount = 0;
    while (my $line = <$fh>) {
      chomp $line;
      my @values = split /\t/, $line;
      my $newChrm = $values[0];

      my ($name, $statStr) = split /\|/, $values[3];
      my $stats = $json->decode($statStr);

      my @printValues;
      foreach my $field (@INPUT_FIELDS) {
	if ($field eq 'bp') {
	  push(@printValues, $values[2])
	} elsif ($field eq 'metaseq_id') {
	  my ($oldChrm, $oldPos, $ref, $alt) = split /:/, $stats->{metaseq_id};
	  $self->error("Chromosome mismatch for $newChrm (new) != $oldChrm (old): $line")
	    if ('chr' . $oldChrm ne $newChrm);
	  my $metaseqId = join(":", $oldChrm, $values[2], $ref, $alt);
	  push(@printValues, $metaseqId);
	} elsif ($field eq 'marker') { # rs ids are no longer valid
	  if ($inclMarkers) {
	    push(@printValues, $stats->{$field});
	  }
	  else {
	    push(@printValues, 'NULL');
	  }
	}
	elsif (($field eq 'gwas_flags'
		|| $field eq 'restricted_stats_json'
		|| $field eq 'GRCh37'
		|| $field eq 'GRCh38') && $stats->{$field} ne 'NULL') {
	  push(@printValues, Utils::to_json($stats->{$field}));
	} else {
	  push(@printValues, $stats->{$field});
	}
      }

      print $ofh join("\t", @printValues) . "\n";

      $self->log("INFO: Wrote $lineCount lines from $bedFileName")
	if (++$lineCount % 500000 == 0);
    }
    $fh->close();
    $ofh->close();
    $self->log("INFO: Wrote $lineCount lines from $bedFileName");
    return $targetFileName;
  }
}


sub input2bed {
  # extract fields not liftedOver by DB mapping and place in a bed file
  my ($self, $inputFileName) = @_;

  unless (-e $inputFileName) {
    $self->error("input2bed - Input file $inputFileName not found");
  }

  my $filePrefix =  $self->{adj_source_id};
  my $filePath = PluginUtils::createDirectory($self, $self->{working_dir}, "liftOver");
  my $bedFileName = $filePath . "/". $filePrefix . "-GRCh37.bed";
  my $markerOnlyFileName = $inputFileName . ".unmapped.markerOnly"; # b/c db look up

  $self->log("INFO: input2bed - Creating bed file $bedFileName from input file $inputFileName");
  if (-e $bedFileName && (!$self->getArg('overwrite'))) {
    $self->log("INFO: Using existing input2bed file $bedFileName");
    my $lineCount = Utils::fileLineCount($bedFileName); 
    return $lineCount, $bedFileName;
  }

  open(my $bedFh, '>', $bedFileName ) || $self->error("Unable to create $bedFileName for writing");
  $bedFh->autoflush(1);

  # any fields ID'd by marker only have to be put aside & tacked back on the liftOver result
  open(my $moFh, '>', $markerOnlyFileName) || $self->error("Unable to create marker only $markerOnlyFileName for writing");
  $moFh->autoflush(1);

  open(my $fh, $inputFileName) || $self->error("Unable to open input file $inputFileName for reading");
  my $header = <$fh>;
  print $moFh $header;
  chomp($header);
  my @fields = split /\t/, $header;

  my $json = JSON::XS->new();
  # INPUT fields: chr bp allele1 allele2 metaseq_id marker freq1 pvalue neg_log10_p display_p gwas_flags test_allele restricted_stats_json
  # OUTPUT: chrom start end name {everything else in JSON} / no header
  my $lineCount = 0;
  my $bedFileLineCount = 0;
  my $markerOnlyLineCount = 0;
  while (my $line = <$fh>) {
    chomp $line;
    my @values = split /\t/, $line;

    my %row;
    @row{@fields} = @values;

    next if ($row{GRCh38} ne 'NULL'); # already lifted over

    my $chr = "chr" . $row{chr};
    my $position = $row{bp};
    my $start = $position - 1;	# shift to 0-based
    my $end = $position;
    my $name = ($chr =~ m/NA/g) ? $row{marker} : $row{chr} . ":$position" ;

    $row{gwas_flags} = $json->decode($row{gwas_flags});
    $row{restricted_stats_json} = $json->decode($row{restricted_stats_json});
    $row{GRCh37} = $json->decode($row{GRCh37}) if ($row{GRCh37} ne 'NULL');
    foreach my $f (qw(freq1 pvalue neg_log10_p display_p)) {
      $row{$f} = Utils::toNumber($row{$f});
    }

    my $infoStr = Utils::to_json(\%row);
    if ($chr =~ m/NA/g || ($row{metaseq_id} eq "NULL")) {
      print $moFh "$line\n";
      $markerOnlyLineCount++;
    } else {
      print $bedFh join(" ", $chr, $start, $end, "$name|$infoStr") . "\n";
      $bedFileLineCount++;
    }

    if (++$lineCount % 500000 == 0) {
      $self->log("INFO: Parsed $lineCount lines");
    }
  }
  $self->log("INFO: Parsed $lineCount lines");
  $fh->close();
  $bedFh->close();
  $moFh->close();

  my $tc = $markerOnlyLineCount + $bedFileLineCount;
  $self->log("INFO: Found $tc unmapped variants / marker only = $markerOnlyLineCount");
  return $bedFileLineCount, $bedFileName;
}

sub preprocess {
  my ($self) = @_;
  my $file = $self->{root_file_path} . $self->getArg('file');
  my $inputFileName = $self->cleanAndSortInput($file);

  my $filePrefix =  $self->{source_id};
  my $filePath = PluginUtils::createDirectory($self, $self->{working_dir}, "preprocess");
  my $novelVariantVcfFile = $self->extractNovelVariants($inputFileName, "$filePath/$filePrefix");
  # $self->annotateNovelVariants($novelVariantVCF); 
}


sub extractNovelVariants {
  my ($self, $file, $filePrefix) = @_;
  $self->log("INFO: Extracting novel variants from DB Mapped file: $file");
  my $genomeBuild = $self->getArg('genomeBuild');
  my $useMarker = ($self->getArg('mapThruMarker') && !$self->getArg('markerIsMetaseqId'));

  my $dbmappedFileName = $self->DBLookup($file, $genomeBuild, $useMarker);

  open(my $fh, $dbmappedFileName) || $self->error("Unable to open DB Mapped file $dbmappedFileName for reading");
  my $header = <$fh>;

  my $novelVariantVCF = $filePrefix . "-novel.vcf";
  open(my $vfh, '>', $novelVariantVCF) || $self->error("Unable to open create  novel variant VCF file: $novelVariantVCF");
  $vfh->autoflush(1);

  print $vfh join("\t", @VCF_FIELDS) . "\n";

  my $lineCount = 0;
  my $novelVariantCount = 0;
  while (my $line = <$fh>) {
    chomp $line;
    my @values = split /\t/, $line;

    my %row;
    @row{@INPUT_FIELDS} = @values;

    my ($chromosome, $position, $ref, $alt) = split /:/, $row{metaseq_id};
    if ($row{$genomeBuild} eq 'NULL') { # not in DB
      print $vfh join("\t", $chromosome, $position, '.', $ref, $alt, '.', '.', '.') . "\n";
      ++$novelVariantCount;
    }

    $self->log("INFO: Checked $lineCount variants") if (++$lineCount % 500000 == 0);
  }

  $fh->close();
  $vfh->close();
  $self->log("DONE: Checked $lineCount variants") if (++$lineCount % 500000 == 0);
  $self->log("INFO: Found $novelVariantCount novel variants");

  return $novelVariantVCF;
}


sub loadVariants {
  my ($self) = @_;

  my $commitAfter = $self->getArg('commitAfter');
  my $resume = $self->getArg('resume');

  my $insertedRecordCount = 0;
  my $existingRecordCount = 0;
  my $updatedRecordCount = 0;
  my $duplicateRecordCount = 0;
  my $totalVariantCount = 0;

  my $insertRecordBuffer = "";
  my @updateRecordBuffer = ();
  my @updateAvDbBuffer = ();

  my $currentPartition = "";

  my $updateAvDbh = $self->{annotator}->connect2AnnotatedVDB();
  my $selectAvDbh = $self->{annotator}->connect2AnnotatedVDB();
  my $updateSql = undef;
  my $selectSql = undef;
  my $updateAvQh = undef;
  my $selectAvQh = undef;
  
  my $previousPK = {}; # for checking duplicates loaded in same batch (some files have multiple p-values for single variants)
  
  my $fileName = $self->sortPreprocessedResult();
  open(my $fh, $fileName ) || $self->error("Unable to open $fileName for reading");
  # (chr bp allele1 allele2 freq1 pvalue neg_log10_p display_p gwas_flags test_allele restricted_stats_json db_variant_json);
  <$fh>;			# throw away header
  my %row;
  while (<$fh>) {
    chomp;
    ++$totalVariantCount;
    @row{@RESULT_FIELDS} = split /\t/;
    my $chrNum = $row{chr};

    my $partition = 'chr' . $chrNum;
    if ($currentPartition ne $partition) { # changing chromosome
      $self->log("INFO: New Partition: $currentPartition -> $partition.");
      if ($currentPartition) {	# has been initialized
	# commit anything in buffers
	$self->log("INFO: Found $totalVariantCount variants; Performing Bulk Inserts/Updates.");
	PluginUtils::bulkCopy($self, $insertRecordBuffer, VariantLoadUtils::getCopySql());
	VariantLoadUtils::bulkAnnotatedVariantUpdateOtherAnnotation($self, $updateAvDbh, $currentPartition, @updateAvDbBuffer)
	    if ($self->getArg('commit' )); # b/c table is not logged
	@updateAvDbBuffer = ();
	$insertRecordBuffer = "";
	$previousPK = {};	# new chromosome so, erase old dups
      }

      $selectAvQh->finish() if $selectAvQh;
      $selectSql = "SELECT other_annotation FROM Variant_$partition v WHERE v.record_primary_key = ?";
      $selectAvQh = $selectAvDbh->prepare($selectSql);
      $currentPartition = $partition;
    }

    my $json = JSON::XS->new;
    my $dbv = $json->decode($row{db_variant_json}) || $self->error("Error parsing dbv json: " . $row{db_variant_json});
    my $recordPK = $dbv->{record_primary_key};

    my ($chr, $position, $ref, $alt) = split /:/, $dbv->{metaseq_id};

    if ($resume || !($dbv->{has_genomicsdb_annotation})) {
      # after a while this will be true for most
      # but double check in case of resume or check all if resume flag is specified
      if (not exists $previousPK->{$recordPK}) {
	my $variant = GUS::Model::NIAGADS::Variant->new({record_primary_key => $recordPK});
	unless ($variant->retrieveFromDB()) {
	  $self->log("Variant $recordPK not found in GenomicsDB.") 
	    if $self->getArg('veryVerbose');
	  my $props = $self->{annotator}->inferVariantLocationDisplay($ref, $alt, $position, $position);

	  $insertRecordBuffer .= VariantLoadUtils::generateCopyStr($self, $dbv, $props,
								   undef, $dbv->{is_adsp_variant});
	  ++$insertedRecordCount;
	  $previousPK->{$recordPK} = 1;
	} else {
	  $self->log("Variant mapped to annotated variant $recordPK")
	    if $self->getArg('veryVerbose');
	  ++$existingRecordCount;
	}
      } else {
	$self->log("Duplicate variant found $recordPK") if $self->getArg('veryVerbose');
	$duplicateRecordCount++;
      }
    } else {
      $self->log("Variant mapped to annotated variant $recordPK")
	if $self->getArg('veryVerbose');
      ++$existingRecordCount;
    }

    # update AnnotatedVDB variant
    my $gwsFlag = ($row{gwas_flags} ne "NULL") ? $self->getArg('sourceId') : undef;
    if ($gwsFlag) {
      push(@updateAvDbBuffer,
	   VariantLoadUtils::annotatedVariantUpdateGwsValueStr($self, $recordPK, $gwsFlag, $selectAvQh));
      ++$updatedRecordCount;
    }

    unless ($totalVariantCount % $commitAfter) {
      $self->log("Found $totalVariantCount variants; Performing Bulk Inserts/Updates.");
      PluginUtils::bulkCopy($self, $insertRecordBuffer, VariantLoadUtils::getCopySql());
      VariantLoadUtils::bulkAnnotatedVariantUpdateOtherAnnotation($self, $updateAvDbh, $currentPartition, @updateAvDbBuffer)
	  if ($self->getArg('commit' )); # b/c table is not logged
      @updateAvDbBuffer = ();
      $insertRecordBuffer = "";
    }

    unless ($totalVariantCount % 10000) {
      $self->log("Read $totalVariantCount lines; updates: $existingRecordCount; inserts: $insertedRecordCount; duplicates: $duplicateRecordCount; AVDB updates: $updatedRecordCount");
      $self->undefPointerCache();
    }
    $previousPK->{$recordPK} = 1;
  }

  # insert residuals
  $self->log("Found $totalVariantCount variants; Performing Bulk Inserts/Updates.");
  PluginUtils::bulkCopy($self, $insertRecordBuffer, VariantLoadUtils::getCopySql());
  VariantLoadUtils::bulkAnnotatedVariantUpdateOtherAnnotation($self, $updateAvDbh, $currentPartition, @updateAvDbBuffer)
      if ($self->getArg('commit' )); # b/c table is not logged
  @updateAvDbBuffer = ();
  $insertRecordBuffer = "";

  $self->log("DONE: Read $totalVariantCount lines; existing: $existingRecordCount; inserts: $insertedRecordCount; duplicates: $duplicateRecordCount; AVDB updates: $updatedRecordCount");

  $fh->close();
  $selectAvQh->finish();
}



# ----------------------------------------------------------------------
# supporting methods
# ----------------------------------------------------------------------





# ----------------------------------------------------------------------
sub undoTables {
  my ($self) = @_;
  return ();		  # 'Results.VariantGWAS', 'NIAGADS.Variant');
}



1;
