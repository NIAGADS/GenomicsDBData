## LoadClinvar.pm.pm
## $Id: LoadClinvar.pm.pm $
##

package GenomicsDBData::Load::Plugin::LoadClinvar;
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
use Vcf;

use Scalar::Util qw(looks_like_number);

use GUS::Model::Results::VariantPhenotype;
use GUS::Model::NIAGADS::Variant;
use GUS::Model::Study::ProtocolAppNode;

my @RESULT_FIELDS = qw(variant phenotype ontology_terms evidence db_variant_json);

my $HOUSEKEEPING_FIELDS = PluginUtils::getHouseKeepingSql();

my $COPY_SQL = <<COPYSQL;
COPY Results.VariantPhenotype(
protocol_app_node_id,
variant_record_primary_key,
bin_index,
phenotype,
ontology_terms,
evidence,
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

      stringArg({ name  => 'genomeBuild',
                 descr => 'genome build for dbsnp lookup',
                 constraintFunc => undef,
                 reqd           => 1,
                 isList         => 0 
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
	      format => 'bed file or vcf'
	     }),

     stringArg({name => 'sourceId',
		descr => 'protocol app node source id',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0
	       }),

     booleanArg({ name  => 'mapThruMarker',
		  descr => 'flag if can only be mapped thru marker',
		  constraintFunc => undef,
		  reqd           => 0,
		  isList         => 0 
		}),

       booleanArg({ name  => 'mapPosition',
		  descr => 'flag if can map to all variants at position; not used by this; required by VariantAnnotator',
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


     stringArg({ name  => 'customChrMap',
                 descr => 'json object defining custom mappings (e.g., {"25":"M", "Z": "5"}',
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),

     booleanArg({ name  => 'loadResult',
		  descr => 'load phenotype results, to be run after loading variants, & annotating and loading novel variants',
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
  my $purposeBrief = 'Loads Variant Phenotype result from Clinvar download';

  my $purpose = 'Loads Variant Phenotype result from ClinVar download in multiple passes: 1) lookup against AnnotatedVDB & flag novel variants; output updated input file w/mapped record PK & bin_index, 2) annotate novel variants and update new annotated input file, 3) sort annotated input file by position and update/insert into NIAGADS.Variant and annotatedVDB 4)load  results';

  my $tablesAffected = [['Results::VariantPhenotype', 'Enters a row for each variant feature'], ['NIAGAD::Variant', 'Enters a row for each novel variant']];

  my $tablesDependedOn = [['Study::ProtocolAppNode', 'lookup analysis source_id']];

  my $howToRestart = '';

  my $failureCases = '';

  my $notes = <<NOTES;

Written by Emily Greenfest-Allen
Copyright Trustees of University of Pennsylvania 2021. 
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
		     cvsRevision       => '$Revision: 6 $',
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

  $self->{protocol_app_node_id} = $self->getProtocolAppNodeId(); # verify protocol app node

  $self->{annotator} = VariantAnnotator->new({plugin => $self});
  $self->{annotator}->createQueryHandles();
  $self->{housekeeping} = PluginUtils::buildHouseKeepingString($self);

  my $file = $self->getArg('file');

  $self->findNovelVariants($file, 0) if ($self->getArg('findNovelVariants')); # 0 => create new preprocess file
  $self->findNovelVariants($file, 1)
    if ($self->getArg('preprocessAnnotatedNovelVariants')); # needs to be done in a separate call b/c of FDW lag

  $self->annotateNovelVariants()  if ($self->getArg('annotateNovelVariants'));

  $self->loadVariants() if ($self->getArg('loadVariants'));

  $self->loadResult() # so that we only have to iterate over the file once; do this simulatenously
    if ($self->getArg('loadResult'));

}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------


sub loadResult {
  my ($self) = @_;
  my $totalVariantCount = 0;
  my $insertStrBuffer = "";
  my $commitAfter = $self->getArg('commitAfter');

  my $fileDir = $self->getArg('fileDir');
  my $fileName = "$fileDir/" . $self->getArg('sourceId') . "-preprocess.txt"; 

  open(my $fh, $fileName ) || $self->error("Unable to open $fileName for reading");
  <$fh>; # throw away header
  
  my %row;   
  while (<$fh>) {
    chomp;
    @row{@RESULT_FIELDS} = split /\t/;

    my $json = JSON->new();
    my $dbv = $json->decode($row{db_variant_json}) || $self->error("Error parsing dbv json: " . $row{db_variant_json});

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

  $fh->close();

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
  my $inputFileName = ($novel) ? $filePrefix . "-novel.vcf" : $self->getArg('fileDir') . "/" . $self->getArg('file');

  my $vifh = undef;

  if (!$novel) {
    my $vcfFileName = $filePrefix . "-novel.vcf";
    open($vifh, '>', $vcfFileName ) || $self->error("Unable to create $vcfFileName for writing");
    $vifh->autoflush(1);
    my @vcfFields = qw(#CHROM POS ID REF ALT QUAL FILTER INFO);
    print $vifh join("\t", @vcfFields) . "\n"; 
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

  my $vcf = Vcf->new(file=>$inputFileName) || $self->error("Unable to parse VCF $inputFileName");
  $self->{vcfHandle} = $vcf;
  $vcf->parse_header();
  $self->log("Done Importing VCF File");
  while (my $record = $vcf->next_data_array()) {
    my $sourceId = $vcf->get_column($record, "ID");
    my $chrNum = $vcf->get_column($record, "CHROM");
    $chrNum = "M" if ($chrNum eq "MT");
    my $chromosome = "chr" . $chrNum;

    my $position = $vcf->get_column($record, "POS");
    my $ref = $vcf->get_column($record, "REF");
    my $alt = $vcf->get_column($record, "ALT");
    $self->error("multiple alleles: $chrNum:$position:$ref:$alt") if ($alt =~ m/,/);
    
    my $metaseqId = "$chrNum:$position:$ref:$alt";

    my $info = $vcf->get_column($record, "INFO");
    # $self->log("info: ", Dumper($info));
    my $rsId = $vcf->get_info_field($info, "RS");
    my $marker = ($rsId) ? "rs" . $rsId : undef;
    my $alleles = "$ref:$alt";

    # my $startTime = Utils::getTime();

    my (@dbVariantIds) = $va->getAnnotatedVariants($metaseqId, undef, undef, 1); # 1 -> firstHitOnly for metaseq_id matches 
    # my ($elapsedTime, $tmessage) = ::elapsed_time($startTime);
    # $self->log($tmessage) if $self->getArg('veryVerbose');
    if (!@dbVariantIds) { # if variant not in AnnotatedVDB.Variant, write to file
	print $vifh join("\t", @$record) . "\n";
	++$novelVariantCount;
	$self->log("Found novel variant: " . $metaseqId) if ($self->getArg('veryVerbose') || $self->getArg('verbose'));
    }
    else { # format and write to preprocess file
      $self->log("Mapped to: " . Dumper(\@dbVariantIds)) if ($self->getArg('veryVerbose'));
      $self->log("Mapped to: " . $dbVariantIds[0]->{record_primary_key}) if ($self->getArg('verbose'));

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
	my $phenotypes = $self->extractPhenotypes($info);
	my $evidence = $self->extractEvidence($info);
	$evidence->{clinvar_id} = $sourceId;
	# $self->log("evidence: " . Dumper($evidence));
	# $self->error("phenotypes: " . Dumper($phenotypes));
	$self->writePreprocessedResult($pfh, $dbv, $phenotypes, $evidence);
	++$mappedVariantCount;
      }
    }
    unless (++$totalVariantCount % 10000) {
      $self->log("Read $totalVariantCount lines; mapped: $mappedVariantCount; novel: $novelVariantCount; unmapped: $unmappedVariantCount");
      $self->undefPointerCache();
    }
  }
  if (!$novel) {
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

sub extractEvidence {
  my ($self, $vcfInfo) = @_;

  my $evidence = {};
  my @keyValues = split /;/, $vcfInfo;
  foreach my $pair (@keyValues) {
    my ($key, $value) = split /=/, $pair;
    next if $key eq "CLNDISDB"; # phenotypes
    next if $key eq "CLNDN";
    $evidence->{$key} = $value;
  }

  return $evidence;
}

sub extractPhenotypes {
  my ($self, $vcfInfo) = @_;

  my $termIds = $self->{vcfHandle}->get_info_field($vcfInfo, "CLNDISDB");
  my $terms = $self->{vcfHandle}->get_info_field($vcfInfo, "CLNDN");

  my @phenotypes = split /\|/, $terms;
  my @phenotypeIds = split /\|/, $termIds;

  my $phenotypeHash = {};

  for my $i (0 .. $#phenotypes) {
    my $phenotype = $phenotypes[$i];
    my $ids = $phenotypeIds[$i];
    $phenotypeHash->{$phenotype} = {};
    my @pids = split /,/, $ids;
    foreach my $pid (@pids) {
      my ($db, $sourceId) = split(/:/, $pid, 2);
      # $self->log("$phenotype -> $db: $sourceId");
      $phenotypeHash->{$phenotype}->{$db} = $sourceId;
    }
  }

  return $phenotypeHash;
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
	$previousPK = {}; # new chromosome so, erase old dups
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
	}
	else {
	  $self->log("Variant mapped to annotated variant $recordPK")
	    if $self->getArg('veryVerbose');
	  ++$existingRecordCount;
	}
      }
      else {
	$self->log("Duplicate variant found $recordPK") if $self->getArg('veryVerbose');
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
  my ($self, $fh, $dbVariant, $phenotypes, $vcfInfo) = @_;

  my $variant =  $dbVariant->{metaseq_id};
  
  # variant phenotype ontology_terms evidence db_variant_json
  foreach my $phenotype (keys %$phenotypes) {
    print $fh join("\t",
		   ($variant,
		    $phenotype,
		    Utils::to_json($phenotypes->{$phenotype}),
		    Utils::to_json($vcfInfo),
		    Utils::to_json($dbVariant)
		   )
		  ) . "\n";
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


sub generateInsertStr {
  my ($self, $dbv, $data) = @_;
  my @values = ($self->{protocol_app_node_id},
		$dbv->{record_primary_key},
		$dbv->{bin_index},
		$data->{phenotype},
		$data->{ontology_terms},
		$data->{evidence}
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
