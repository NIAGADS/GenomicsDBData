
## $Id: LoadVariantGWASResult.pm.pm $
##

package GenomicsDBData::Load::Plugin::LoadVariantGWASResult;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use GUS::PluginMgr::Plugin;
use POSIX qw(strftime);
use Parallel::Loops;

use Package::Alias VariantAnnotator => 'GenomicsDBData::Load::VariantAnnotator';
use Package::Alias Utils => 'GenomicsDBData::Load::Utils';
use Package::Alias PluginUtils => 'GenomicsDBData::Load::PluginUtils';
use Package::Alias VariantLoadUtils => 'GenomicsDBData::Load::VariantLoadUtils';

use JSON::XS;
use Data::Dumper;
use File::Slurp qw(read_file);

use Scalar::Util qw(looks_like_number);

use GUS::Model::Results::VariantGWAS;
use GUS::Model::NIAGADS::Variant;
use GUS::Model::Study::ProtocolAppNode;

my $RESTRICTED_STATS_FIELD_MAP = undef;

my $HOUSEKEEPING_FIELDS = PluginUtils::getHouseKeepingSql();

my @INPUT_FIELDS = qw(chr bp allele1 allele2 marker metaseq_id freq1 pvalue neg_log10_p display_p gwas_flags test_allele restricted_stats_json);
my @RESULT_FIELDS = qw(chr bp allele1 allele2 freq1 pvalue neg_log10_p display_p gwas_flags test_allele restricted_stats_json db_variant_json);
my @RESTRICTED_STATS_ORDER = qw(num_observations coded_allele_frequency minor_allele_count call_rate test min_frequency max_frequency frequency_se effect beta t_statistic std_err odds_ratio beta_std_err beta_L95 beta_U95 odds_ratio_L95 odds_ratio_U95 hazard_ratio hazard_ratio_CI95 direction het_chi_sq het_i_sq het_df het_pvalue probe maf_case maf_control p_additive p_dominant p_recessive Z_additive Z_dominant Z_recessive );

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

     booleanArg({name => 'remap',
		 descr => 'use NCBI Remap API to lift over / TODO - generalize',
		 constraintFunc=> undef,
		 reqd  => 0,
		 isList => 0,
		}),


     integerArg({ name  => 'numRemapVariants',
		  descr => 'number of variants to submit to remap',
		  constraintFunc => undef,
		  isList         => 0,
		  default => 10000,
		  reqd => 0
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

     booleanArg({ name  => 'cleanAndSortInput',
		  descr => 'clean and sort input; this allows for faster lookups/has to do w/prepare statement',
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
		     cvsRevision       => '$Revision: 2$',
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

  $self->logAlgInvocationId();
  $self->logCommit();
  $self->logArgs();
  $self->getAlgInvocation()->setMaximumNumberOfObjects(100000);

  $self->verifyArgs();

  $self->{protocol_app_node_id} = $self->getProtocolAppNodeId(); # verify protocol app node

  $self->{annotator} = VariantAnnotator->new({plugin => $self});
  $self->{annotator}->createQueryHandles();
  $self->{housekeeping} = PluginUtils::buildHouseKeepingString($self);

  my $sourceId = $self->getArg('sourceId');
  if ($self->getArg('liftOver') || $self->getArg('remap'))  {
    $sourceId =~ s/_GRCh38//g;
  }
  $self->{adj_source_id} = $sourceId;
  $self->{root_file_path} = $self->getArg('fileDir') . "/" . $self->getArg('genomeBuild') . "/";
  my $workingDir =   PluginUtils::createDirectory($self, $self->{root_file_path}, $self->{adj_source_id});
  $self->{working_dir} = $workingDir;

  my $file = $self->{root_file_path} . $self->getArg('file');

  $self->cleanAndSortInput($file) if ($self->getArg('cleanAndSortInput'));
  $self->liftOver($file) if ($self->getArg('liftOver'));
  $self->remap($file) if ($self->getArg('remap'));

  $self->findNovelVariants($file, 0) if ($self->getArg('findNovelVariants')); # 0 => create new preprocess file
  $self->findNovelVariants($file, 1)
    if ($self->getArg('preprocessAnnotatedNovelVariants')); # needs to be done in a separate call b/c of FDW lag

  $self->annotateNovelVariants()  if ($self->getArg('annotateNovelVariants'));

  $self->loadVariants() if ($self->getArg('loadVariants'));

  $self->loadStandardizedResult() # so that we only have to iterate over the file once; do this simulatenously
    if ($self->getArg('loadResult') or $self->getArg('standardizeResult'));

}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------


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
  }
}

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

sub removeFileDuplicates {
  my ($self, $fileName) = @_;
  my $cmd = `uniq $fileName > $fileName.uniq && mv $fileName.uniq $fileName`;
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


sub cleanAndSortInput {
  my ($self, $file) = @_;
  my $lineCount = 0;

  $self->log("INFO: Cleaning $file");

  my $filePrefix = $self->{adj_source_id};
  my $preprocessFileName = $self->{working_dir} . "/" . $filePrefix . '-input.txt';
  my $pfh = undef;
  open($pfh, '>', $preprocessFileName) || $self->error("Unable to create cleaned file $preprocessFileName for writing");
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
  $self->sortCleanedInput($self->{working_dir}, $preprocessFileName);
}

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


sub runRemap {
  my ($self, $filePath, $filePrefix, $fileCount) = @_;
  my $inputFileName = $filePath . "/". $filePrefix . "-GRCh37_$fileCount" . ".vcf";
  if (-e $inputFileName) {
    my $outputFileName = $filePath . "/". $filePrefix . "-GRCh38_$fileCount" . ".vcf";
    my ($fromAssembly, $destAssembly) = split /\|/, $self->getArg('remapAssemblies');

    my @cmd = ('remap_api.pl',
	       '--mode', 'asm-asm',
	       '--in_format', 'vcf',
	       '--out_format', 'vcf',
	       '--from', $fromAssembly,
	       '--dest', $destAssembly,
	       '--annotation', $inputFileName,
	       '--annot_out', $outputFileName,
	       '--report_out', $inputFileName . ".report"
	      );

    $self->log("INFO: Running NCBI Remap (FC = $fileCount): " . join(' ', @cmd));
    my $status = qx(@cmd);
  }
  else {
    $self->error("Error running NCBI Remap: input file $inputFileName does not exist");
  }
}


sub remap {
  my ($self, $file) = @_;
  $self->log("INFO: Remapping $file (" . $self->{adj_source_id} . ")");
  my ($filePath, $filePrefix, $nFiles) = $self->writeRemapFiles($file);

  my $maxProcs = 4;
  my %errors;
  my $pl = Parallel::Loops->new($maxProcs);
  $pl->share(\%errors);
  my @fileCounts = (1 .. 4); # $nFiles);
  $pl->foreach(\@fileCounts, sub {
		 eval {
		   $self->runRemap($filePath, $filePrefix, $_) || die "Error executing Remap on file $_";
		 };
	       });

  my $hasErrors = keys %errors;
  if ($hasErrors) {
    $self->log(Dumper(\%errors));
  }
  # assemble results / sort & then tack on & marker only
}


sub writeRemapFiles {
  # batchs of at most 250,000 lines, up to 4 simultaneously
  # vcf probably best way to go
  my ($self, $file) = @_;

  my $filePrefix =  $self->{adj_source_id};
  my $inputFileName = $self->{working_dir} . '/' . $filePrefix . "-input.txt";

  if (-e $inputFileName && !$self->getArg('overwrite')) {
    $self->log("INFO: Using existing cleaned input file: $inputFileName");
  } else {
    $self->log("INFO: Creating cleaned and sorted input file: $inputFileName");
    $self->cleanAndSortInput($file);
  }

  my $vcfFh = undef;
  my $moFh = undef;
  my $filePath = PluginUtils::createDirectory($self, $self->{working_dir}, "remap");
  my $vcfFilePrefix = $filePath . "/". $filePrefix . "-GRCh37";

  if (-e $filePath && !$self->getArg('overwrite')) {
    opendir (my $dh, $filePath);
    my $numFiles =  grep {m/\.vcf$/} readdir($dh);
    $dh->close();
    if ($numFiles > 0) {
      $self->log("INFO: Remap directory already exists with $numFiles .vcf files; using existing files.");
      return ($filePath, $filePrefix, $numFiles);
    }
  }

  open($moFh, '>', $inputFileName . "-markerOnly" ) || $self->error("Unable to create marker only file $$inputFileName-markerOnly for writing");
  $moFh->autoflush(1);

  open(my $fh, $inputFileName ) || $self->error("Unable to open $inputFileName for reading");

  my $header = <$fh>;
  chomp($header);
  my @fields = split /\t/, $header;

  my $json = JSON::XS->new();
  # INPUT fields: chr bp allele1 allele2 metaseq_id marker freq1 pvalue neg_log10_p display_p gwas_flags test_allele restricted_stats_json
  # OUTPUT:
  my $limit = $self->getArg('numRemapVariants');
  my $lineCount = 0;
  my $fileCount = 0;
  my $vcfFileName = $vcfFilePrefix . "_$fileCount";
  while (my $line = <$fh>) {
    if ($lineCount % $limit == 0) {
      if ($lineCount != 0) {
	$vcfFh->close();
      }

      $fileCount++;
      $vcfFileName = $vcfFilePrefix . "_$fileCount" . ".vcf";
      $self->log("INFO: Writing remap VCF file: $vcfFileName");
      open($vcfFh, '>', $vcfFileName ) || $self->error("Unable to create $vcfFileName for writing");
      $vcfFh->autoflush(1);
      my @vcfFields = qw(#CHROM POS ID REF ALT QUAL FILTER INFO);
      print $vcfFh join("\t", @vcfFields) . "\n";
    }

    $lineCount++;

    chomp $line;
    my @values = split /\t/, $line;

    my %row;
    @row{@fields} = @values;

    my $metaseqId = $row{metaseq_id};
    my $chrm = $row{chr};
    if (!$metaseqId || $chrm eq "NA") {
      print $moFh $line . "\n";
    }
    else {
      my ($chr, $position, $ref, $alt) = split /:/, $metaseqId;
      my $name = $row{chr} . ":$position" ;
      $name .= ':' . $row{marker} if ($row{marker});

      $row{gwas_flags} = $json->decode($row{gwas_flags});
      $row{restricted_stats_json} = $json->decode($row{restricted_stats_json});
      my $infoStr = 'SS=' . Utils::to_json(\%row);

      print $vcfFh join("\t", ($chr, $position, $name, $ref, $alt, '.', '.', $infoStr)) . "\n";
    }
  }
  $fh->close();
  $vcfFh->close();
  $self->log("INFO: Done generating Remap files; processed $lineCount rows.");
  return ($filePath, $filePrefix, $fileCount);
}



sub liftOver {
  # lift over --> 1) translate 1-based to 0-based / output as bed file
  # lift over / handle errors
  # read back in and translate back to 1-based / output updated input file
  
  my ($self, $file) = @_;

  $self->log("INFO: Processing $file (" . $self->getArg('sourceId') . ")");

  # do liftOver
  my ($bedFileName, $markerOnlyFileName) = $self->writeBedFile($file);
  my $liftedBedFileName = $self->runLiftOver($bedFileName);

  # handle unmapped & add in
  #   run against NCBI Remap
  #   look up against GRCh37 dbSNP (using NCBI API?)
  my ($remapBedFileName, $unmappedRemapFileName) = $self->remapUnmapped($bedFileName . ".unmapped");
  my ($validRefSnpsFileName, $unmappedVariantsFileName) = $self->lookupValidGRCh37Variants($unmappedRemapFileName);
  
  my @bedFiles = ($liftedBedFileName, $remapBedFileName);
  my @markerOnlyFiles = ($markerOnlyFileName, $validRefSnpsFileName);
  # translate back to input file format
  $self->bed2input($liftedBedFileName, $markerOnlyFileName);
}


sub lookupValidGRCh37Variants {
  my ($self, $inputFileName) = @_;

  open(my $ofh, $inputFileName ) || $self->error("Unable to open NCBI Remap unmapped file: $inputFileName for reading");

  $ofh->close();


  return (1, 2);
}


sub remapBedFile {
  my ($self, $inputFileName) = @_;

  my $filePrefix =  $self->{adj_source_id};
  my $remapRootDir = PluginUtils::createDirectory($self, $self->{working_dir}, "remap");

  
  if (-e $inputFileName) {
    my $lineCount = `wc -l < $inputFileName`;
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
      $self->log("INFO: Done with remap");
      return $outputFileName;
    }
    else {
      $self->error("Remap of $inputFileName failed");
    }
  }
  else {
    $self->error("Error running NCBI Remap: input file $inputFileName does not exist");
  }

}


sub remapUnmapped {
  my ($self, $bedFile) = @_;
  $self->log("INFO: Running remap on variants not mapped by UCSC liftOver");

  # remove error codes
  #perl -n -i.bak -e 'print unless m/abc1[234567]/' filename
  my @cmd = ('perl', '-n', '-i.bak', '-e',
	     "'print unless m/^#/'",
	     $bedFile
	    );

  $self->log("INFO: Removing error codes from $bedFile - " . join(' ', @cmd));
  my $status = qx(@cmd);

  my $remappedBedFile = $self->remapBedFile($bedFile);
  # compare the two files and identify problems
  # return cleanedBedFile, unmappedBedFile
  return $self->checkRemappedResult($remappedBedFile, $bedFile);
}


sub checkRemappedResult {
  my ($self, $remapFile, $originalFile) = @_;
  my $workingDir = PluginUtils::createDirectory($self, $self->{working_dir}, "remap");

  # basically, want to identify the following problems:
  # 1) still unmapped
  # 2) duplicates
  # 3) mapped against contigs
  # 4) suprisingly enough, wrong chromosome
  
  # load $ofh into hash
  my $variants;
  open(my $ofh, $originalFile ) || $self->error("Unable to open liftOver unmapped file: $originalFile for reading");
  while (my $line = <$ofh>) {
    chomp($line);
    my @values = split /\t/, $line;
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
  my @remapLines = read_file($remapFile, chomp => 1);
  while (my ($lineCount, $line) = each @remapLines) {
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
    my $isWrongChrm = ($values[0] ne "chr$origChrm" && !$isAltChrm) ? 1 : 0;
    if ($isWrongChrm) {
      $wrongCount++;
      $self->log("INFO: Location $loc mapped to wrong chromosome - " . $values[0]) if $self->getArg('veryVerbose');
    }

    my $status = (exists $variants->{$key})
      ? $variants->{$key}->{status}
      : undef;

    $self->error("Variant $key in Remap file but not in remap input.") if (!$status);

    if ($status eq 'none') {
      $mappedCount++ if (!$isAltChrm && !$isWrongChrm);
      $variants->{$key}->{status} = ($isAltChrm) ? "alt|$lineCount" :
	($isWrongChrm) ? "wrong_chrm|$lineCount" : "mapped|$lineCount";
    }
    else {
      if ($status =~ m/mapped/) {
	if ($isAltChrm) {
	  $self->log("INFO: Location $loc already mapped to primary assembly - ignoring contig mapping") if $self->getArg('veryVerbose');
	}
	elsif ($isWrongChrm) {
	  $self->log("INFO: Location $loc already mapped to primary assembly - ignoring wrong mapping") if $self->getArg('veryVerbose');
	}
	else {
	  $duplicateCount += 2; # original mapped + new
	  $mappedCount--;
	  my ($dupStatus, $dupLine) = split /\|/, $status;
	  $variants->{$key}->{status} = "dup|$dupLine,$lineCount";
	}
      } # end already mapped
      if ($status =~ m/alt/) {
	if ($isWrongChrm) {
	  $self->log("INFO: Location $loc already mapped to contig - ignoring wrong mapping") if $self->getArg('veryVerbose');
	}
	else {
	  $mappedCount++;
	  $self->log("INFO: Location $loc - replacing contig mapping with mapping to primary assembly") if $self->getArg('veryVerbose');
	  $variants->{$key}->{status} = "mapped|$lineCount";
	}
      }
      if ($status =~ m/wrong/) {
	if ($isWrongChrm) {
	  $variants->{$key}->{status} = $status . ",$lineCount";
	}
	elsif ($isAltChrm) {
	  $self->log("INFO: Location $loc mapped to contig - replacing wrong chromosome flag") if $self->getArg('veryVerbose');
	  $variants->{$key}->{status} = "alt|$lineCount";
	}
	else {
	  $mappedCount++;
	  $self->log("INFO: Location $loc mapped to primary assembly - replacing wrong chromosome flag") if $self->getArg('veryVerbose');
	  $variants->{$key}->{status} = "mapped|$lineCount";
	}
      }
      if ($status =~ m/dup/) {
	if ($isAltChrm) {
	  $self->log("INFO: Location $loc already mapped to primary assembly - ignoring contig mapping") if $self->getArg('veryVerbose');
	}
	elsif ($isWrongChrm) {
	  $self->log("INFO: Location $loc already mapped to primary assembly - ignoring wrong mapping") if $self->getArg('veryVerbose');
	}
	else {
	  $duplicateCount++;
	  $variants->{$key}->{status} = $status . ",$lineCount";
	}
      }
    }
  }

  $parsedLineCount++; # started at 0
  #my $totalCount = $mappedCount + $duplicateCount + $altCount + $wrongCount;
  #my $debugDiff = $totalCount - $parsedLineCount;
  #$self->log("INFO: Total = $totalCount (Mapped = $mappedCount | Duplicate = $duplicateCount | Contigs = $altCount | Wrong = $wrongCount)");
  #$self->log("DEBUG: Why are counts off by " . $totalCount . '-' . $parsedLineCount . " ($debugDiff)?");

  # generate two files - 1) remapped.cleaned 2) remapped.unmapped
  my $cleanedRemapFileName = $remapFile . ".cleaned";
  my $unmappedRemapFileName = $remapFile. ".unmapped";
  $unmappedRemapFileName =~ s/-GRCh38/-GRCh37/g;

  open(my $cfh, '>', $cleanedRemapFileName ) || $self->error("Unable to create $cleanedRemapFileName for writing");
  open(my $ufh, '>', $unmappedRemapFileName ) || $self->error("Unable to create $unmappedRemapFileName for writing");

  foreach my $key (keys %$variants) {
    my $statusStr = $variants->{$key}->{status};
    my ($status, $lineNum) = split /\|/, $statusStr;

    if ($status eq 'mapped') {
      print $cfh $remapLines[$lineNum] . "\n";
    }
    else { # includes 'none's not in the remap file
      print $ufh $variants->{$key}->{original_line} . "\n";
    }
  }

  $cfh->close();
  $ufh->close();

  $self->log("INFO: Done checking remap");
  return ($cleanedRemapFileName, $unmappedRemapFileName);
}

sub isRemapAltChrm {
  my ($chrm) = @_;
  return ($chrm =~ m/_/g) ? 1: 0;
}


sub bed2input {
  my ($self, $bedFile, $markerOnlyFile) = @_;

  $self->log("INFO: Generating input file from $bedFile");

  my $rootFilePath =   PluginUtils::createDirectory($self, $self->getArg('fileDir'), "GRCh38");
  my $workingDir =   PluginUtils::createDirectory($self, $rootFilePath, $self->getArg('sourceId'));
  my $inputFileName = $workingDir . "/" . $self->getArg('sourceId') . "-input.txt";
  my $ofh = undef;

  if (-e $inputFileName && !$self->getArg('overwrite')) {
    $self->log("INFO: Using existing bed2input file: $inputFileName");
  }
  else {
    $self->log("INFO: Creating bed2input file: $inputFileName");
    my $json = JSON::XS->new;

    # INPUT fields: chr bp allele1 allele2 metaseq_id marker freq1 pvalue neg_log10_p display_p gwas_flags test_allele restricted_stats_json
    # OUTPUT: chrom start end name|{everything else in JSON} / no header

    open($ofh, '>', $inputFileName ) || $self->error("Unable to create $inputFileName for writing");
    open(my $fh, $bedFile ) || $self->error("Unable to open $bedFile for reading");

    print $ofh join("\t", @INPUT_FIELDS) . "\n";

    while (my $line = <$fh>) {
      chomp $line;
      my @values = split /\t/, $line;

      my ($name, $statStr) = split /\|/, $values[3];
      my $stats = $json->decode($statStr);

      my @printValues;
      foreach my $field (@INPUT_FIELDS) {
	if ($field eq 'bp') {
	  push(@printValues, $values[1])
	}
	elsif ($field eq 'metaseq_id') {
	  my ($chr, $oldPos, $ref, $alt) = split /:/, $stats->{metaseq_id};
	  my $metaseqId = "$chr:" . $values[1] . ":$ref:$alt";
	  push(@printValues, $metaseqId);
	}
	elsif ($field eq 'marker') { # rs ids are no longer valid
	  push(@printValues, undef);
	}
	elsif ($field eq 'gwas_flags' || $field eq 'restricted_stats_json') {
	  push(@printValues, Utils::to_json($stats->{$field}));
	}
	else {
	  push(@printValues, $stats->{$field});
	}
      }

      print $ofh join("\t", @printValues) . "\n";
    }
    $fh->close();

    open($fh, $markerOnlyFile) || $self->error("Unable to open marker only file $markerOnlyFile for reading");
    while (<$fh>) {
      print $ofh $_;
    }
    $fh->close();
    $ofh->close();
  }


  $self->sortCleanedInput($workingDir, $inputFileName);
}


sub runLiftOver {
  my ($self, $bedFile) = @_;
  my $chainFile = $self->getArg('liftOverChainFile');
  $self->log("INFO: Performing liftOver on $bedFile using chain: $chainFile");

  # USAGE: liftOver oldFile map.chain newFile unMapped
  my $filePath = $self->{working_dir} . "/liftOver/";
  my $filePrefix = $self->{adj_source_id};
  my $errorFile = $bedFile . ".unmapped";
  my $liftedBedFileName = $filePath . $filePrefix . "-GRCh38.bed";

  if (-e $liftedBedFileName && !$self->getArg('overwrite')) {
    $self->log("INFO: Using existing liftOver file: $liftedBedFileName");
    return $liftedBedFileName;
  }

  my @cmd = ('liftOver',
	     $bedFile,
	     $chainFile,
	     $liftedBedFileName,
	     $errorFile);

  $self->log("INFO: Running liftOver: " . join(' ', @cmd));
  my $status = qx(@cmd);

  $self->log("INFO: Done with liftOver");
  $self->log("WARNING: Not all variants mapped, see: $errorFile") if (-s $errorFile > 0);
  return $liftedBedFileName;
}


sub writeBedFile {
  my ($self, $file) = @_;

  my $filePrefix =  $self->{adj_source_id};
  my $inputFileName = $self->{working_dir} . '/' . $filePrefix . "-input.txt";

  if (-e $inputFileName && !$self->getArg('overwrite')) {
    $self->log("INFO: Using existing cleaned input file: $inputFileName");
  } else {
    $self->log("INFO: Creating cleaned and sorted input file: $inputFileName");
    $self->cleanAndSortInput($file);
  }

  my $filePath = PluginUtils::createDirectory($self, $self->{working_dir}, "liftOver");
  my $bedFh = undef;
  my $moFh = undef;
  my $bedFileName = $filePath . "/". $filePrefix . "-GRCh37.bed";
  my $markerOnlyFileName = $inputFileName . "-markerOnly";

  if (-e $bedFileName && !$self->getArg('overwrite')) {
    if (-e $markerOnlyFileName) {
      $self->log("INFO: Using existing bed file: $bedFileName");
      return ($bedFileName, $markerOnlyFileName);
    }
  }

  open($bedFh, '>', $bedFileName ) || $self->error("Unable to create $bedFileName for writing");
  $bedFh->autoflush(1);

  # any fields ID'd by marker only have to be put aside & tacked back on the liftOver result
  open($moFh, '>', $markerOnlyFileName) || $self->error("Unable to create marker only $bedFileName for writing");
  $moFh->autoflush(1);

  open(my $fh, $inputFileName ) || $self->error("Unable to open $inputFileName for reading");
  $self->log("INFO: Creating bed file: $bedFileName");
  my $header = <$fh>;
  chomp($header);
  my @fields = split /\t/, $header;

  my $json = JSON::XS->new();
  # INPUT fields: chr bp allele1 allele2 metaseq_id marker freq1 pvalue neg_log10_p display_p gwas_flags test_allele restricted_stats_json
  # OUTPUT: chrom start end name {everything else in JSON} / no header
  while (my $line = <$fh>) {
    chomp $line;
    my @values = split /\t/, $line;
    
    my %row;
    @row{@fields} = @values;

    my $chr = "chr" . $row{chr};
    my $position = $row{bp};
    my $start = $position - 1;	# shift to 0-based
    my $end = $position;
    my $name = ($chr eq "chrNA") ? $row{marker} : $row{chr} . ":$position" ;

    $row{gwas_flags} = $json->decode($row{gwas_flags});
    $row{restricted_stats_json} = $json->decode($row{restricted_stats_json});
    my $infoStr = Utils::to_json(\%row);
    if ($chr eq "chrNA" || !($row{metaseq_id})) {
      print $moFh $line . "\n";
    } else {
      print $bedFh join(" ", $chr, $start, $end, "$name|$infoStr") . "\n";
    }
  }
  $bedFh->close();
  $moFh->close();
  $fh->close();

  return ($bedFileName, $markerOnlyFileName);
}



sub findNovelVariants {
  my ($self, $file, $novel) = @_;

  $self->log("INFO: Processing $file (" . $self->getArg('sourceId') . ")");

  my $va = $self->{annotator};
  $va->validateMetaseqIds(0) if $self->getArg('skipMetaseqIdValidation');

  my $lineCount = 0;
  my $novelVariantCount = 0;
  my $totalVariantCount = 0;
  my $mappedVariantCount = 0;
  my $unmappedVariantCount = 0;

  my $filePrefix = $self->getArg('fileDir') . "/" . $self->getArg('genomeBuild') . "/" . $self->getArg('sourceId');
  my $inputFileName = ($novel) ? $filePrefix . "-novel.txt" : $filePrefix . "-input.txt";

  my $vifh = undef;
  my $nvfh = undef;

  if (!$novel) {
    if (-e $inputFileName && !$self->getArg('overwrite')) {
      $self->log("INFO: Using existing cleaned input file: $inputFileName");
    } else {
      $self->log("INFO: Creating cleaned and sorted input file: $inputFileName");
      $self->cleanAndSortInput($file);
    }

    my $vcfFileName = $filePrefix . "-novel.vcf";
    open($vifh, '>', $vcfFileName ) || $self->error("Unable to create $vcfFileName for writing");
    $vifh->autoflush(1);
    my @vcfFields = qw(#CHROM POS ID REF ALT QUAL FILTER INFO);
    print $vifh join("\t", @vcfFields) . "\n";
  
    my $novelFileName = $filePrefix . '-novel.txt';
    open($nvfh, '>', $novelFileName ) || $self->error("Unable to create $novelFileName for writing");
    $nvfh->autoflush(1);
    print $nvfh join("\t", @INPUT_FIELDS) . "\n";
  }

  my $preprocessFileName = $filePrefix . '-preprocess.txt';
  my $pfh = undef;
  if ($novel) {
    open($pfh, '>>', $preprocessFileName) || $self->error("Unable to create cleaned file $preprocessFileName for writing");
  } else {
    open($pfh, '>', $preprocessFileName) || $self->error("Unable to create cleaned file $preprocessFileName for writing");
    print $pfh join("\t", @RESULT_FIELDS) . "\n";
  }

  $pfh->autoflush(1);

  open(my $fh, $inputFileName ) || $self->error("Unable to open $inputFileName for reading"); 
  $self->log("INFO: Processing $inputFileName");
  my $header = <$fh>;
  chomp($header);
  my @fields = split /\t/, $header;

  while (my $line = <$fh>) {
    chomp $line;
    # (chr bp allele1 allele2 metaseq_id marker freq1 pvalue neg_log10_p display_p gwas_flags test_allele restricted_stats_json );
    my @values = split /\t/, $line;
    my %row = {};
    @row{@fields} = @values;

    my $metaseqId = $row{metaseq_id};
    my $marker = ($self->getArg('marker')) ? $row{marker} : undef;
    my ($chromosome, $position, $ref, $alt) = split /:/, $metaseqId;
    my $alleles = ($ref and $ref ne '') ? "$ref:$alt" : $row{test_allele}; 

    # my $startTime = Utils::getTime();

    my (@dbVariantIds) = $va->getAnnotatedVariants($metaseqId, $marker, $alleles, 1); # 1 -> firstHitOnly for metaseq_id matches 
    # my ($elapsedTime, $tmessage) = ::elapsed_time($startTime);
    # $self->log($tmessage) if $self->getArg('veryVerbose');
    if (!@dbVariantIds) { # if variant not in AnnotatedVDB.Variant, write to file 

      if ($self->getArg('skipUnmappableMarkers') and ($marker) and ($chromosome eq "NA")) {
	$self->log("WARNING: Unable to map $marker");
	++$unmappedVariantCount;
      } else {
	print $nvfh $line . "\n";
	print $vifh join("\t", $chromosome, $position, '.', $ref, $alt, '.', '.', '.') . "\n";
	++$novelVariantCount;
	$self->log("INFO: Found novel variant: " . $metaseqId) if ($self->getArg('veryVerbose') || $self->getArg('verbose'));
      }
    } else {			# format and write to preprocess file
      $self->log("INFO: Mapped to: " . Dumper(\@dbVariantIds)) if ($self->getArg('veryVerbose'));
      $self->log("INFO: Mapped to: " . $dbVariantIds[0]->{record_primary_key}) if ($self->getArg('verbose'));

      if (scalar @dbVariantIds > 1 and !$self->getArg('mapThruMarker') and !$self->getArg('markerIsMetaseqId')) { # mostly due to multiple refsnps mapped to same position; but sanity check
	$self->log("WARNING: Variant $metaseqId mapped to multiple annotated variants:");
	$self->log(Dumper(\@dbVariantIds));
      }

      foreach my $dbv (@dbVariantIds) {
	%$dbv = map { lc $_ => $dbv->{$_} } keys %$dbv; # plugin wrapper returns fields in uppercase/direct queries lowercase
	if ($chromosome eq "NA" || $self->getArg('mapThruMarker')) {
	  my ($c, $p, $r, $a) = split /:/, $dbv->{metaseq_id};
	  $chromosome = $c;
	  $position = $p;
	}
	$self->writePreprocessedResult($pfh, $dbv, \%row);
	++$mappedVariantCount;
      }
    }
    unless (++$totalVariantCount % 10000) {
      $self->log("INFO: Read $totalVariantCount lines; mapped: $mappedVariantCount; novel: $novelVariantCount; unmapped: $unmappedVariantCount");
      $self->undefPointerCache();
    }
  }
  if (!$novel) {
    $nvfh->close();
    $vifh->close();
  }
  $pfh->close();

  $self->log("INFO: Found $totalVariantCount total variants");
  $self->log("INFO: Mapped & preprocessed $mappedVariantCount variants");
  $self->log("INFO: Unable to map $unmappedVariantCount variants");
  $self->log("INFO: Found $novelVariantCount novel variants") if (!$novel);
}

sub getColumnIndex {
  my ($self, $columnMap, $field) = @_;

  $self->error("$field not in file header") if (!exists $columnMap->{$field});
  return $columnMap->{$field};
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


sub sortCleanedInput {
  my ($self, $workingDir, $fileName) = @_;
  my $sortedFileName = $fileName . "-sorted.tmp";
  $self->log("Sorting cleaned input $fileName / working directory = $workingDir");
  my $cmd = `(head -n 1 $fileName && tail -n +2 $fileName | sort -T $workingDir -V -k1,1 -k2,2 ) > $sortedFileName`;
  $cmd =  `mv $sortedFileName $fileName`;
  $self->log("Created sorted file: $fileName");
}


sub buildGWASFlags {
  my ($self, $pvalue, $displayP) = @_;
  my $flags = {$self->getArg('sourceId') => {p_value => $displayP,
					     is_gws => $pvalue <= $self->getArg('genomeWideSignificanceThreshold') ? 1: 0}};

  return Utils::to_json($flags);
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

  # (chr bp allele1 allele2 marker metaseq_id freq1 pvalue neg_log10_p display_p gws_flags test_allele restricted_stats_json );
  print $fh join("\t",
		 ($resultVariant->{chromosome},
		  $resultVariant->{position},
		  $resultVariant->{altAllele},
		  $resultVariant->{refAllele},
		  $resultVariant->{marker},
		  $resultVariant->{metaseq_id},
		  $frequency,
		  $pvalue,
		  $negLog10p,
		  $displayP,
		  $gwasFlags,
		  $resultVariant->{testAllele},
		  $restrictedStats
		 )
		) . "\n";
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
      $stats->{$stat} = (looks_like_number($values[$index])) ? $values[$index] * 1.0 : $values[$index];
    }
  }
  return Utils::to_json($stats);
}

sub formatPvalue {
  my ($self, $pvalue) = @_;
  my $negLog10p = 0;

  if ($pvalue =~ m/NA/i) {
    return ("NaN", "NaN", "NaN")
  }
  if (!$pvalue) {
    return ("NaN", "NaN", "NaN")
  }

  if ($pvalue =~ m/e/i) {
    my ($mantissa, $exponent) = split /-/, $pvalue;
    return ($pvalue, $exponent, $pvalue) if ($exponent > 300);
  }

  return (0, $pvalue) if ($pvalue == 1);

  eval {
    $negLog10p = -1.0 * (log($pvalue) / log(10));

  } or do {
    $self->log("WARNING: Cannot take log of p-value ($pvalue)");
    return ($pvalue, $pvalue, $pvalue);
  };

  my $displayP = ($pvalue < 0.0001) ? sprintf("%.2e", $pvalue) : $pvalue;

  return ($pvalue, $negLog10p, $displayP);
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

# ----------------------------------------------------------------------
sub undoTables {
  my ($self) = @_;
  return ();		  # 'Results.VariantGWAS', 'NIAGADS.Variant');
}



1;
