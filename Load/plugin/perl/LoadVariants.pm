## LoadVariants Plugin
## $Id: LoadVariants.pm $
##

package NiagadsData::Load::Plugin::LoadVariants;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use GUS::PluginMgr::Plugin;
use Data::Dumper;

use JSON::XS;

use Package::Alias VariantAnnotator => 'NiagadsData::Load::VariantAnnotator';
use Package::Alias Utils => 'NiagadsData::Load::Utils';
use Package::Alias PluginUtils => 'NiagadsData::Load::PluginUtils';
use Package::Alias VariantLoadUtils => 'NiagadsData::Load::VariantLoadUtils';

use GUS::Model::NIAGADS::Variant;

# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
  my $argumentDeclaration  =
    [

     stringArg({name => 'fileDir',
		descr => 'The full path to the directory containing file; preprocess files will be saved here',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0,
	       }),

     stringArg({name => 'file',
		descr => 'the file containing the list of variants; just the name, not the full path',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0,
	       }),

     booleanArg({ name  => 'mapThruMarker',
		  descr => "map through ref snp id;  required by variant annotator",
		  constraintFunc => undef,
		  reqd           => 0,
		  isList         => 0 
		}),

     booleanArg({ name  => 'checkAltVariants',
                 descr => 'check for ref:alt, alt:ref, and reverse strand',
                 constraintFunc => undef,
                 isList         => 0,
		 reqd => 0
	       }),

     booleanArg({ name  => 'mapPosition',
		  descr => "map through ref snp id;  required by variant annotator",
		  constraintFunc => undef,
		  reqd           => 0,
		  isList         => 0 
		}),

     stringArg({ name  => 'adspFlag',
                 descr => 'one of ADSP, ADSP_WES, ADSP_WGS, used to set ADSP flags in database; ignore if not ADSP variants',
                 constraintFunc => undef,
                 isList         => 0,
		 reqd => 0
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

     stringArg({ name  => 'vepCacheDir',
                 descr => "full path to VEP Cache",
                 constraintFunc => undef,
                 isList         => 0,
		 reqd => 1
	       }),

     stringArg({name => 'adspConsequenceRankingFile',
		descr => 'full path to ADSP VEP consequence ranking file',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0,
	       }),

     booleanArg({ name  => 'loadVariants',
		  descr => 'load variants & identify novel variants; for first pass',
		  constraintFunc => undef,
		  isList         => 0,
		  reqd => 0
		}),

     booleanArg({ name  => 'loadNovelVariants',
		  descr => 'needs to be done in a third pass b/c of latency w/postgres FDW',
		  constraintFunc => undef,
		  isList         => 0,
		  reqd => 0
		}),

     booleanArg({ name  => 'annotateNovelVariants',
		  descr => 'can be done in first pass or in second pass, before running with --loadNovelVariants',
		  constraintFunc => undef,
		  isList         => 0,
		  reqd => 0
		}),


    ];
  return $argumentDeclaration;
}

# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
  my $purposeBrief = 'Loads variants from a listing file; expects metaseq_ids';

  my $purpose = 'This plugin reads variants from a list, and inserts them into NIAGADS.Variants; updates and loads novel variants into AnnotatedVDB.  Expects lists of metaseq ids.  This does not do a bulk update b/c the variants are not necessarily partitioned by chromosome; for short lists of variants';

  my $tablesAffected = [['NIAGADS::Variant', 'Enters a row for each variant feature']];

  my $tablesDependedOn = [ ];

  my $howToRestart = '';

  my $failureCases = '';

  my $notes = <<NOTES;

Written by Emily Greenfest-Allen
Copyright Trustees of University of Pennsylvania 2020. 
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
  my $argumentDeclaration    = &getArgumentsDeclaration();

  $self->initialize({requiredDbVersion => 4.0,
		     cvsRevision => '$Revision: 26 $',
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

  $self->{annotator} = VariantAnnotator->new({plugin => $self});
  $self->{annotator}->createQueryHandles();  
  $self->{housekeeping} = PluginUtils::buildHouseKeepingString($self);

  my $file = $self->getArg('file');
  if ($self->getArg('annotateNovelVariants')) {
    $self->annotateNovelVariants($file);
  }
  else {
    $file .= '-novel.txt' if $self->getArg('loadNovelVariants');
    $self->loadVariants($file);
  }

}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub annotateNovelVariants {
  my ($self, $file) = @_;

  my $fileName = $self->getArg('fileDir') . "/" . $file . "-novel.vcf";
  $self->log("Annotating $fileName");
  $fileName = $self->{annotator}->sortVcf($fileName);
  $self->{annotator}->runVep($fileName);
  $self->{annotator}->loadVepAnnotatedVariants($fileName);
  $self->{annotator}->loadNonVepAnnotatedVariants($fileName);
  $self->{annotator}->loadCaddScores($fileName);
}


sub loadVariants { # load or update
  my ($self, $file) = @_;

  my $va = $self->{annotator};

  my $insertedRecordCount = 0;
  my $updatedRecordCount = 0;
  my $totalVariantCount = 0;
  my $lineCount = 0;
  my $novelVariantCount = 0;
  
  my $insertRecordBuffer = "";
  my @updateRecordBuffer = ();
  my @updateAvDbBuffer = ();

  my $fileName = $self->getArg('fileDir') . "/" . $file;
  $self->log("Processing $fileName");

  my $selectAvDbh = $self->{annotator}->connect2AnnotatedVDB();
  my $updateAvDbh = $self->{annotator}->connect2AnnotatedVDB();

  my $vifh = undef;
  my $nvfh = undef;

  if ($file !~ m/novel/g) { # don't create files for writing if processing Novel files
    my $vcfFileName = $self->getArg('fileDir') . "/" . $file . "-novel.vcf";
    open($vifh, '>', $vcfFileName ) || $self->error("Unable to create $vcfFileName for writing");
    $vifh->autoflush(1);
    my @vcfFields = qw(#CHROM POS ID REF ALT QUAL FILTER INFO);
    print $vifh join("\t", @vcfFields) . "\n";

    my $novelFileName = $self->getArg('fileDir') . "/" . $file . "-novel.txt";
    open($nvfh, '>', $novelFileName ) || $self->error("Unable to create $novelFileName for writing");
    $nvfh->autoflush(1);
  }

  # --------------------
  # begin the work
  # --------------------

  open(my $fh, $fileName ) || $self->error("Unable to open $fileName for reading");

  while (my $metaseqId = <$fh>) {
    chomp $metaseqId;
    $self->log("Processing $metaseqId") if $self->getArg('veryVerbose');

    ++$lineCount;

    my ($chrNum, $position, $ref, $alt) = split /:/, $metaseqId;

    $chrNum = "M" if ($chrNum eq "MT");
    my $chr = "chr" . $chrNum;

    my $isAdspVariant = undef;
    my $annotation = undef;
    if ($self->getArg('adspFlag')) {
      $isAdspVariant = 1;
      $annotation = {$self->getArg('adspFlag') => {FILTER_STATUS => 'PASS'}};
    }

    # lookup variant in AnnotatedVDB.Variant
    my (@dbVariantIds) = $va->getAnnotatedVariants($metaseqId, undef);
    if (!@dbVariantIds) { # if variant not in AnnotatedVDB.Variant, write to file 
      if ($self->getArg('loadNovelVariants')) { # loading novel variants but still can't find it in the DB
	$self->log("$metaseqId from novel file missing after AnnotatedVDB update");
      }
      else {
	print $nvfh $metaseqId . "\n";
	print $vifh join("\t", $chrNum, $position, '.', $ref, $alt, '.', '.', '.') . "\n";
      }

      ++$novelVariantCount;
      ++$totalVariantCount;
      $self->log("Found novel variant: " . $metaseqId) if $self->getArg('veryVerbose');
    }

    # iterate over dbVariants
    # if variant in AnnotatedVDB.Variant, but not NIAGADS.Variant, insert
    # else update
    foreach my $dbv (@dbVariantIds) {
      ++$totalVariantCount;
      $self->log("Matched: " . Dumper($dbv)) if $self->getArg('veryVerbose');

      my $recordPK = $dbv->{record_primary_key};
      my $variant = GUS::Model::NIAGADS::Variant
	->new({record_primary_key => $recordPK});

      unless ($variant->retrieveFromDB()) { # if not in db; slow when not
	$self->log("Variant $recordPK not found in GenomicsDB.") 
	  if $self->getArg('veryVerbose');

	my $props = $va->inferVariantLocationDisplay($ref, $alt, $position, $position);
	my $jsonStr = ($annotation) ? Utils::to_json($annotation) : undef;
	$variant->setIsAdspVariant(1) if ($isAdspVariant);

	VariantLoadUtils::insertNiagadsVariant($variant, $dbv, $props, $jsonStr);

	$self->log("Submitted new record for $recordPK.") if $self->getArg('veryVerbose');
	++$insertedRecordCount;
      }
      else { # update existing variants
	$self->log("Variant $metaseqId mapped to annotated variant $recordPK")
	  if $self->getArg('veryVerbose');
	
	$annotation = PluginUtils::generateUpdatedJsonFromGusObj($self, $variant, 'annotation', $annotation);

	$variant->setAnnotation(Utils::to_json($annotation)) if ($annotation);
	$variant->setIsAdspVariant(1) if ($isAdspVariant);
	$variant->submit() if $self->getArg('commit'); # don't do the update in non-commit mode
	      $self->log("Updated $recordPK.") if $self->getArg('veryVerbose');
	++$updatedRecordCount;
      }

      # update AnnotatedVDB record
      my $selectSql = "SELECT other_annotation FROM Variant_chr$chrNum v WHERE v.record_primary_key = ?";
      my $updateSql = "UPDATE Variant_chr$chrNum v SET is_adsp_variant = ?::boolean, other_annotation = ?::jsonb";
      $updateSql .= " WHERE v.record_primary_key = ?";

      my $selectAvQh = $selectAvDbh->prepare($selectSql); # a little clunky but necessary
      my $updateAvQh = $updateAvDbh->prepare($updateSql);
      VariantLoadUtils::updateAnnotatedVariantRecord($self, $recordPK, undef, $annotation, $updateAvQh, $selectAvQh);
      $selectAvQh->finish();
      $updateAvQh->finish();

      $self->log("Updated annotated variant $recordPK")
	  if $self->getArg('veryVerbose');
    }
    unless ($lineCount % 1000) {
      $self->log("Read $lineCount lines; # variants: $totalVariantCount; updates: $updatedRecordCount; inserts: $insertedRecordCount; novel: $novelVariantCount");
      $self->undefPointerCache();
    }
  }

  $self->log("DONE: Read $lineCount lines; # variants: $totalVariantCount; updates: $updatedRecordCount; inserts: $insertedRecordCount; NOVEL: $novelVariantCount");

  $fh->close();

  if ($nvfh) {
    $vifh->close();
    $nvfh->close();
  }

  $selectAvDbh->disconnect();
  $updateAvDbh->disconnect();

  $self->log("Read $lineCount lines from file.");
  $self->log("Processed $totalVariantCount records from file.");
  $self->log("Updated $updatedRecordCount records.");
  $self->log("Inserted $insertedRecordCount records.");
  $self->log("Found $novelVariantCount novel variants.");
  return $novelVariantCount;

}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------


1;
