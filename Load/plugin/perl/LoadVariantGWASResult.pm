## LoadVariantGWASResult.pm.pm
## $Id: LoadVariantGWASResult.pm.pm $
##

package GenomicsDBData::Load::Plugin::LoadVariantGWASResult;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use GUS::PluginMgr::Plugin;
use POSIX qw(strftime);

use Package::Alias VariantAnnotator => 'GenomicsDBData::Load::VariantAnnotator';
use Package::Alias Utils => 'GenomicsDBData::Load::Utils';
use Package::Alias PluginUtils => 'GenomicsDBData::Load::PluginUtils';
use Package::Alias VariantLoadUtils => 'GenomicsDBData::Load::VariantLoadUtils';

use JSON::XS;
use Data::Dumper;

use Scalar::Util qw(looks_like_number);

use GUS::Model::Results::VariantGWAS;
use GUS::Model::NIAGADS::Variant;
use GUS::Model::Study::ProtocolAppNode;

my $RESTRICTED_STATS_FIELD_MAP = undef;

my $HOUSEKEEPING_FIELDS = PluginUtils::getHouseKeepingSql();

my @INPUT_FIELDS = qw(chr bp allele1 allele2 marker metaseq_id freq1 pvalue neg_log10_p display_p has_gws test_allele restricted_stats_json);
my @RESULT_FIELDS = qw(chr bp allele1 allele2 freq1 pvalue neg_log10_p display_p has_gws test_allele restricted_stats_json db_variant_json);
my @RESTRICTED_STATS_ORDER = qw(num_observations test min_frequency max_frequency frequency_se effect beta t_statistic std_err odds_ratio beta_std_err beta_L95 beta_U95 odds_ratio_L95 odds_ratio_U95 hazard_ratio hazard_ratio_CI95 direction het_chi_sq het_i_sq het_df het_pvalue probe maf_case maf_control p_additive p_dominant p_recessive Z_additive Z_dominant Z_recessive );

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

     stringArg({name => 'annotatedVdbGusConfigFile',
		descr => 'full path to AnnotatedVDB gusConfigFile',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0,
	       }),

     stringArg({name => 'caddDatabaseDir',
		descr => 'full path to CADD database directory',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0,
	       }),

     stringArg({name => 'adspConsequenceRankingFile',
		descr => 'full path to ADSP VEP consequence ranking file',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0,
	       }),

     stringArg({ name  => 'vepCacheDir',
                 descr => "full path to VEP Cache",
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
                 descr => 'genome build for dbsnp lookup',
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
		  descr => 'skip unmappable markers',
		  constraintFunc => undef,
		  reqd           => 0,
		  isList         => 0 
		}),

     booleanArg({ name  => 'skipUnmappableMarkers',
		  descr => 'lookup unmappable markers in dbsnp',
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
		     cvsRevision       => '$Revision$',
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

  my $file = $self->getArg('file');

  $self->cleanAndSortInput($file) if ($self->getArg('cleanAndSortInput'));
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
    $self->error("must specify testAllele") if (!$self->getArg('testAllele'));
    $self->error("must specify refAllele") if (!$self->getArg('refAllele') and !$self->getArg('marker'));
    $self->error("must specify pvalue") if (!$self->getArg('pvalue'));
    $self->error("must specify marker if mapping through marker") 
      if ($self->getArg('mapThruMarker') and !$self->getArg('marker'));
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
  <$fh>; # throw away header

  my $path = PluginUtils::createDirectory($self, $self->getArg('fileDir'), "standardized");
  my $standardizedFileName = $path . "/" . $self->getArg('sourceId') . "-COMPLETE.txt";
  open(my $sfh, '>', $standardizedFileName) || $self->rror("Unable top open $standardizedFileName for writing.");
  $sfh->autoflush(1);

  my $pvalueFileName = $path . "/" . $self->getArg('sourceId') . "-PVALUES.txt";
  open(my $pfh, '>', $pvalueFileName) || $self->rror("Unable top open $pvalueFileName for writing.");
  $pfh->autoflush(1);

  my @sheader = (@sfields);
  my %row;   # (chr bp allele1 allele2 freq1 pvalue neg_log10_p display_p has_gws test_allele restricted_stats_json db_variant_json);
  while (<$fh>) {
    chomp;
    @row{@RESULT_FIELDS} = split /\t/;

    my $json = JSON->new();
    my $restrictedStats = $json->decode($row{restricted_stats_json}) || $self->error("Error parsing restricted stats json: " . $row{restricted_stats_json});

    if ($totalVariantCount == 0) {
      unshift @sheader, "marker";
      print $pfh join("\t", @sheader) . "\n";

      push(@sheader, "freq1") if ($hasFreqData);
      @rfields = $self->generateStandardizedHeader($restrictedStats);
      push(@sheader, @rfields);
      print $sfh join("\t", @sheader) . "\n";
    }

    my $dbv = $json->decode($row{db_variant_json}) || $self->error("Error parsing dbv json: " . $row{db_variant_json});
    my $marker = ($dbv->{ref_snp_id}) ? $dbv->{ref_snp_id} : Utils::truncateStr($dbv->{metaseq_id}, 20);

    my @cvalues = @row{@sfields};
    unshift @cvalues, $marker;
    my $oStr = join("\t", @cvalues);
    $oStr =~ s/NaN/NA/g; # replace any DB nulls with NAs
    print $pfh "$oStr\n";

    push(@cvalues, $row{freq1}) if ($hasFreqData);
    push(@cvalues, @$restrictedStats{@rfields});
    $oStr = join("\t", @cvalues);
    $oStr =~ s/NaN/NA/g; # replace any DB nulls with NAs
    print $sfh "$oStr\n";

    ++$totalVariantCount;
    if ($self->getArg('loadResult')) {
      $insertStrBuffer .= $self->generateInsertStr($dbv, \%row);
      unless ($totalVariantCount % $commitAfter) {
	$self->log("Found $totalVariantCount result records; Performing Bulk Inserts");
	PluginUtils::bulkCopy($self, $insertStrBuffer, $COPY_SQL);
	$insertStrBuffer = "";
      }
    }
    unless ($totalVariantCount % 10000) {
      $self->log("Read $totalVariantCount lines");
      $self->undefPointerCache();
    }
  }

  # residuals
  if ($self->getArg('loadResult')) {
    $self->log("Found $totalVariantCount result records; Performing Bulk Inserts");
    PluginUtils::bulkCopy($self, $insertStrBuffer, $COPY_SQL);
    $insertStrBuffer = "";
    $self->log("DONE: Inserted $totalVariantCount result records.");
  }

  $self->log("Checking standardized output for duplicate values (from marker-based matches)");
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
    $self->log("Annotating variants in: $fileName");
    $fileName = $self->{annotator}->sortVcf($fileName);
    $self->{annotator}->runVep($fileName) if (!$self->getArg('skipVep'));
    $self->{annotator}->loadVepAnnotatedVariants($fileName);
    $self->{annotator}->loadNonVepAnnotatedVariants($fileName);
    $self->{annotator}->loadCaddScores($fileName);
  }
  else {
    $self->log("No novel variants found in: $fileName");
  }
}


sub cleanAndSortInput {
  my ($self, $file) = @_;
  my $lineCount = 0;
  my $fileName = $self->getArg('fileDir') . "/" . $file;
  $self->log("Cleaning $fileName");

  my $preprocessFileName = $self->getArg('fileDir') . "/" . $self->getArg('sourceId') . '-input.txt';
  my $pfh = undef;
  open($pfh, '>', $preprocessFileName) || $self->error("Unable to create cleaned file $preprocessFileName for writing");
  print $pfh join("\t", @INPUT_FIELDS) . "\n";

  $pfh->autoflush(1);

  open(my $fh, $fileName ) || $self->error("Unable to open $fileName for reading");

  my $header= <$fh>;
  chomp($header);
  my @fields = split /\t/, $header;
  @fields = split /\s/, $header if (scalar @fields == 1);
  @fields = split /,/, $header  if (scalar @fields == 1);

  my %columns = map { $fields[$_] => $_ } 0..$#fields;
  if ($self->getArg('restrictedStats')) {
    $self->generateRestrictedStatsFieldMapping(\%columns) if (!$RESTRICTED_STATS_FIELD_MAP);
  }

  my $testAlleleC = $self->getColumnIndex(\%columns, $self->getArg('testAllele'));
  my $refAlleleC = ($self->getArg('refAllele')) ? $self->getColumnIndex(\%columns, $self->getArg('refAllele')) : undef;
  my $altAlleleC = ($self->getArg('altAllele')) ? $self->getColumnIndex(\%columns, $self->getArg('altAllele')) : undef;
  my $chrC = ($self->getArg('chromosome')) ? $self->getColumnIndex(\%columns, $self->getArg('chromosome')) : undef;
  my $positionC = ($self->getArg('position')) ? $self->getColumnIndex(\%columns, $self->getArg('position')) : undef;
  my $markerC = ($self->getArg('marker')) ? $self->getColumnIndex(\%columns, $self->getArg('marker')) : undef;

  my $customChrMap = ($self->getArg('customChrMap')) ? $self->generateCustomChrMap() : undef;

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
    my $alt = ($altAlleleC) ? uc($values[$altAlleleC]) : uc($values[$testAlleleC]);
    my $test = uc($values[$testAlleleC]);
   
    $ref = '?' if ($ref =~ m/0/); # vep can still process the '?', so do the replacement here for consistency 
    $alt = '?' if ($alt =~ m/0/);
    $test = '?' if ($test =~ m/0/);

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
	  $self->log("Skipping variant $metaseqId -- BP = 0");
	  next;
      }

      while (my ($oc, $rc) = each %$customChrMap) {
	$chromosome = $rc if ($chromosome =~ m/\Q$oc/);
      }

      $chromosome = 'M' if ($chromosome =~ m/MT/);
      $chromosome = 'X' if ($chromosome =~ m/23/);
      $chromosome = 'Y' if ($chromosome =~ m/24/);

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
      }
      else {
	$metaseqId = $chromosome . ':' . $position . ':';

	my $isIndel = (length($ref) > 1 || length($alt) > 1);

	if ($isIndel && $self->getArg('markerIndicatesIndel')) {
	  if ($marker =~ m/I$/) {
	    $metaseqId .= (length($ref) > length($alt)) ? $alt . ':' . $ref : $ref . ':' . $alt;
	  }
	  elsif ($marker =~ m/D$/) {
	    $metaseqId .= (length($ref) > length($alt)) ? $ref . ':' . $alt : $alt . ':' . $ref;
	  }
	  else { # incl merged_del (true indels)
	    $metaseqId .= $ref . ':' . $alt;
	  }
	}
	else { 	# for SNVs if frequency > 0.5, then the test allele is the major allele; saves us some lookup time
	  $metaseqId .= ($frequencyC and $frequency > 0.5) ? $alt . ':' . $ref : $ref . ':' . $alt;
	}
      }
    }

    $marker = undef if ($chrC eq $markerC);
    
    if ($chromosome eq "NA" || $self->getArg('mapThruMarker')) {
      $metaseqId = $marker if ($self->getArg('markerIsMetaseqId')); # yes ignore all that processing just did; easy fix added later

      my ($c, $p, $r, $a) = split /:/, $metaseqId;
      $chromosome = $c;
      $position = $p;

      if ($self->getArg('markerIsMetaseqId')) {
	$ref = $r;
	$alt = $a;
      }
    }

    my $rv = {chromosome => $chromosome, position => $position, refAllele => $ref, altAllele => $alt, testAllele => $test, marker => $marker, metaseq_id => $metaseqId};
    $self->writeCleanedInput($pfh,$rv, \%columns, @values);

    if (++$lineCount % 500000 == 0) {
      $self->log("Cleaned $lineCount lines");
    }
  }
  $self->sortCleanedInput($preprocessFileName);
}


sub findNovelVariants {
  my ($self, $file, $novel) = @_;

  $self->log("Processing $file (" . $self->getArg('sourceId') . ")");

  my $va = $self->{annotator};
  $va->validateMetaseqIds(0) if $self->getArg('skipMetaseqIdValidation');

  my $lineCount = 0;
  my $novelVariantCount = 0;
  my $totalVariantCount = 0;
  my $mappedVariantCount = 0;
  my $unmappedVariantCount = 0;

  my $filePrefix = $self->getArg('fileDir') . "/" . $self->getArg('sourceId');
  my $inputFileName = ($novel) ? $filePrefix . "-novel.txt" : $filePrefix . "-input.txt";

  my $vifh = undef;
  my $nvfh = undef;

  if (!$novel) {
    if (-e $inputFileName && !$self->getArg('overwrite')) {
      $self->log("Using cleaned input file: $inputFileName");
    }
    else {
      $self->log("Cleaned input file does not exist; cleaning and sorting...");
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
  }
  else {
    open($pfh, '>', $preprocessFileName) || $self->error("Unable to create cleaned file $preprocessFileName for writing");
    print $pfh join("\t", @RESULT_FIELDS) . "\n";
  }

  $pfh->autoflush(1);

  open(my $fh, $inputFileName ) || $self->error("Unable to open $inputFileName for reading"); 
  $self->log("Processing $inputFileName");
  my $header = <$fh>;
  chomp($header);
  my @fields = split /\t/, $header;

  while (my $line = <$fh>) {
    chomp $line;
    # (chr bp allele1 allele2 metaseq_id marker freq1 pvalue neg_log10_p display_p has_gws test_allele restricted_stats_json );
    my @values = split /\t/, $line;
    my %row = {};
    @row{@fields} = @values;

    my $metaseqId = $row{metaseq_id};
    my $marker = ($self->getArg('marker')) ? $row{marker} : undef;
    my ($chromosome, $position, $ref, $alt) = split /:/, $metaseqId;

    # my $startTime = Utils::getTime();
    my (@dbVariantIds) = $va->getAnnotatedVariants($metaseqId, $marker, "$ref:$alt", 1); # 1 -> firstHitOnly for metaseq_id matches 
    # my ($elapsedTime, $tmessage) = ::elapsed_time($startTime);
    # $self->log($tmessage) if $self->getArg('veryVerbose');
    if (!@dbVariantIds) { # if variant not in AnnotatedVDB.Variant, write to file 

      if ($self->getArg('skipUnmappableMarkers') and ($marker) and ($chromosome eq "NA"))  {
	$self->log("WARNING: Unable to map $marker");
	++$unmappedVariantCount;
      }
      else {
	print $nvfh $line . "\n";
	print $vifh join("\t", $chromosome, $position, '.', $ref, $alt, '.', '.', '.') . "\n";
	++$novelVariantCount;
	$self->log("Found novel variant: " . $metaseqId) if ($self->getArg('veryVerbose') || $self->getArg('verbose'));
      }
    }
    else { # format and write to preprocess file
      $self->log("Mapped to: " . Dumper(\@dbVariantIds)) if ($self->getArg('veryVerbose'));
      $self->log("Mapped to: " . $dbVariantIds[0]->{record_primary_key}) if ($self->getArg('verbose'));

      if (scalar @dbVariantIds > 1) { # mostly due to multiple refsnps mapped to same position; but sanity check
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
      $self->log("Read $totalVariantCount lines; mapped: $mappedVariantCount; novel: $novelVariantCount; unmapped: $unmappedVariantCount");
      $self->undefPointerCache();
    }
  }
  if (!$novel) {
    $nvfh->close();
    $vifh->close();
  }
  $pfh->close();

  $self->log("Found $totalVariantCount total variants");
  $self->log("Mapped & preprocessed $mappedVariantCount variants");
  $self->log("Unable to map $unmappedVariantCount variants");
  $self->log("Found $novelVariantCount novel variants") if (!$novel);
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
  
  my $previousPK = undef; # for checking duplicates loaded in same batch (some files have multiple p-values for single variants
  
  my $fileName = $self->sortPreprocessedResult();
  open(my $fh, $fileName ) || $self->error("Unable to open $fileName for reading");
  # (chr bp allele1 allele2 freq1 pvalue neg_log10_p display_p has_gws test_allele restricted_stats_json db_variant_json);
  <$fh>; # throw away header
  my %row;
  while (<$fh>) {
    chomp;
    ++$totalVariantCount;
    @row{@RESULT_FIELDS} = split /\t/;
    my $chrNum = $row{chr};

    my $partition = 'chr' . $chrNum;
    if ($currentPartition ne $partition) { # changing chromosome
      $self->log("New Partition: $currentPartition -> $partition.");
      if ($currentPartition) { # has been initialized
	# commit anything in buffers
	$self->log("Found $totalVariantCount variants; Performing Bulk Inserts/Updates.");
	PluginUtils::bulkCopy($self, $insertRecordBuffer, VariantLoadUtils::getCopySql());
	VariantLoadUtils::bulkAnnotatedVariantUpdateOtherAnnotation($self, $updateAvDbh, $currentPartition, @updateAvDbBuffer)
	    if ($self->getArg('commit' )); # b/c table is not logged
	@updateAvDbBuffer = ();
	$insertRecordBuffer = "";
      }

      $selectAvQh->finish() if $selectAvQh;
      $selectSql = "SELECT other_annotation FROM Variant_$partition v WHERE v.record_primary_key = ?";
      $selectAvQh = $selectAvDbh->prepare($selectSql);
      $currentPartition = $partition;
    }

    my $json = JSON->new;
    my $dbv = $json->decode($row{db_variant_json}) || $self->error("Error parsing dbv json: " . $row{db_variant_json});
    my $recordPK = $dbv->{record_primary_key};

    my ($chr, $position, $ref, $alt) = split /:/, $dbv->{metaseq_id};

    if ($resume || !($dbv->{has_genomicsdb_annotation})) {
      # after a while this will be true for most
      # but double check in case of resume or check all if resume flag is specified
      if (!$previousPK || $previousPK ne $recordPK) {
	my $variant = GUS::Model::NIAGADS::Variant->new({record_primary_key => $recordPK});
	unless ($variant->retrieveFromDB()) {
	  $self->log("Variant $recordPK not found in GenomicsDB.") 
	    if $self->getArg('veryVerbose');
	  my $props = $self->{annotator}->inferVariantLocationDisplay($ref, $alt, $position, $position);
	  $insertRecordBuffer .= VariantLoadUtils::generateCopyStr($self, $dbv, $props,
								   undef, $dbv->{is_adsp_variant});
	  ++$insertedRecordCount;
	}
	else {
	  $self->log("Variant mapped to annotated variant $recordPK")
	    if $self->getArg('veryVerbose');
	  ++$existingRecordCount;
	}
      }
      else {
	$self->log("Duplicate variant found $recordPK - $previousPK");
	$duplicateRecordCount++;
      }
    }
    else {
      $self->log("Variant mapped to annotated variant $recordPK")
	if $self->getArg('veryVerbose');
      ++$existingRecordCount;
    }

    # update AnnotatedVDB variant
    my $gwsFlag = ($row{has_gws} ne "NULL") ? $self->getArg('sourceId') : undef;
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
    $previousPK = $recordPK;
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
  }
  else {
    my $fileName = $filePrefix . "-preprocess.txt";
    $self->log("Sorting preprocessed $fileName");
    my $cmd = `(head -n 1 $fileName && tail -n +2 $fileName | sort -T $fileDir -V -k1,1 -k2,2 ) > $sortedFileName`;
    $self->log("Created sorted  file: $sortedFileName");
  }

  return $sortedFileName;
}

sub sortCleanedInput {
  my ($self, $file) = @_;
  my $fileDir = $self->getArg('fileDir');
  my $filePrefix = "$fileDir/" . $self->getArg('sourceId');
  my $sortedFileName = $filePrefix . "-input-sorted.tmp";
  my $fileName = $filePrefix . "-input.txt";
  $self->log("Sorting cleaned input $fileName");
  my $cmd = `(head -n 1 $fileName && tail -n +2 $fileName | sort -T $fileDir -V -k1,1 -k2,2 ) > $sortedFileName`;
  $cmd =  `mv $sortedFileName $fileName`;
  $self->log("Created sorted  file: $fileName");
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

  # (chr bp allele1 allele2 marker metaseq_id freq1 pvalue neg_log10_p display_p has_gws test_allele restricted_stats_json );
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
	      ($pvalue <= $self->getArg('genomeWideSignificanceThreshold')) ? 1 : 'NULL',
	      $resultVariant->{testAllele},
	      $restrictedStats
	     )
	    ) . "\n";
}

sub writePreprocessedResult {
  my ($self, $fh, $dbVariant, $input) = @_;

  # (chr bp allele1 allele2 freq1 pvalue neg_log10_p display_p has_gws test_allele restricted_stats_json db_variant_json);
  print $fh join("\t",
	     ($input->{chr},
	      $input->{bp},
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
    $stats->{$stat} = (looks_like_number($values[$index])) ? $values[$index] * 1.0 : $values[$index];
  }
  return Utils::to_json($stats);
}

sub formatPvalue {
  my ($self, $pvalue) = @_;
  my $negLog10p = 0;

  if ($pvalue =~ m/NA/i) {
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
  return (); # 'Results.VariantGWAS', 'NIAGADS.Variant');
}



1;
