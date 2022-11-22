## LoadADSPVariants Plugin
## $Id: LoadADSPVariants.pm $
##

package GenomicsDBData::Load::Plugin::LoadADSPVariants;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use GUS::PluginMgr::Plugin;
use Data::Dumper;

use JSON::XS;
use List::MoreUtils qw(first_index zip);

use GUS::Supported::GusConfig;
use DBD::Pg;

use Package::Alias VariantAnnotator => 'GenomicsDBData::Load::VariantAnnotator';
use Package::Alias Utils => 'GenomicsDBData::Load::Utils';
use Package::Alias PluginUtils => 'GenomicsDBData::Load::PluginUtils';
use Package::Alias VariantLoadUtils => 'GenomicsDBData::Load::VariantLoadUtils';

use GUS::Model::NIAGADS::Variant;
use GUS::Model::DoTS::ExternalNASequence;
use GUS::Model::SRes::OntologyTerm;

my $FILTER_STATUS = {DISTINCT_REF_ALT => 'FAIL',
		    BOTH_failed => 'FAIL',
		    BOTH_passed => 'PASS',
		    BAYLOR_failed_BROAD_uncalled => 'FAIL',
		    BAYLOR_passed_BROAD_uncalled => 'PASS',
		    BROAD_failed_BAYLOR_passed => 'PASS',
		    BROAD_passed_BAYLOR_failed => 'PASS',
		    BROAD_passed_BAYLOR_uncalled => 'PASS',
		    BROAD_failed_BAYLOR_uncalled => 'FAIL'};


  
# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
  my $argumentDeclaration  =
    [
     stringArg({name => 'fileDir',
	      descr => 'The full path to the directory containing file(s), if file is not specified, will use filePattern to find files',
	      constraintFunc=> undef,
	      reqd  => 1,
	      isList => 0,
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
   
     stringArg({ name  => 'filePattern',
                 descr => "file pattern to match",
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),

     stringArg({ name  => 'file',
                 descr => "single file or comma separated list of files instead of all files in dir; also use to ensure processing order",
                 constraintFunc => undef,
		 reqd => 0,
                 isList         => 0
	       }),

     stringArg({ name  => 'vepCacheDir',
                 descr => "full path to VEP Cache",
                 constraintFunc => undef,
                 isList         => 0,
		 reqd => 1
	       }),


     stringArg({ name  => 'annotationFields',
                 descr => 'json string of field:name for columns that will be included in the annotation (e.g., {"FILTER":"ADSP_WES_FILTER"})',
                 constraintFunc => undef,
                 isList         => 0,
		 reqd => 0
	       }),

     stringArg({ name  => 'altAllele',
		 descr => 'column containg ref allele',
                 constraintFunc => undef,
                 reqd           => 1,
                 isList         => 0 
	       }),


     stringArg({ name  => 'refAllele',
                 descr => 'column containg ref allele',
                 constraintFunc => undef,
                 reqd           => 1,
                 isList         => 0 
	       }),

     stringArg({ name  => 'chromosome',
                 descr => 'column containg chromosome',
                 constraintFunc => undef,
                 reqd           => 1,
                 isList         => 0 
	       }),

     stringArg({ name  => 'position',
                 descr => 'column containg position',
                 constraintFunc => undef,
                 reqd           => 1,
                 isList         => 0 
	       }),


     stringArg({ name  => 'adspFlag',
                 descr => 'one of ADSP, ADSP_WES, ADSP_WGS, used to set ADSP flags in database; ignore if not ADSP variants',
                 constraintFunc => undef,
                 isList         => 0,
		 reqd => 0
	       }),

     booleanArg({ name  => 'mapPosition',
                 descr => 'NOTE: should not be used for this plugin, but required for VariantAnnotator; maps to all variants at position when chr:pos:ref:alt not found in DB',
                 constraintFunc => undef,
                 isList         => 0,
		 reqd => 0
	       }),

     booleanArg({ name  => 'mapThruMarker',
                 descr => 'NOTE: should not be used for this plugin, but required for VariantAnnotator; maps variants by refSnp',
                 constraintFunc => undef,
                 isList         => 0,
		 reqd => 0
	       }),

     booleanArg({ name  => 'checkAltVariants',
                 descr => 'NOTE: should not be used for this plugin; want exact matches as should be done first',
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

     booleanArg({ name  => 'loadNovelVariants',
                 descr => 'needs to be done in a third pass b/c of latency w/postgres FDW',
                 constraintFunc => undef,
                 isList         => 0,
		 reqd => 0
	       }),
     
     booleanArg({ name  => 'bulkLoad',
                 descr => 'bulk load inserts',
                 constraintFunc => undef,
                 isList         => 0,
		 reqd => 0
	       }),

     booleanArg({ name  => 'checkForDuplicates',
                 descr => 'for bulk load inserts (on smaller files as will build a hash); use if you expect duplicate metaseqIds',
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

     booleanArg({ name  => 'findNovelVariantsOnly',
                 descr => 'only generate novel variant files, no inserts/updates',
                 constraintFunc => undef,
                 isList         => 0,
		 reqd => 0
	       }),


     stringArg({ name  => 'skipPattern',
                 descr => 'files matching the listed pattern (e.g., chrN)',
                 constraintFunc => undef,
                 isList         => 0,
		 reqd => 0
	       }),

     booleanArg({ name  => 'skipAnnotatedVDBUpdate',
                 descr => 'only insert/update NIAGADS.Variant, skip update of AnnotatedVDB',
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
  my $purposeBrief = 'Loads variants from a tab delimited filefile';

  my $purpose = 'This plugin reads variants from a tab-delimited file, and inserts them into NIAGADS.Variants';

  my $tablesAffected = [['NIAGADS::Variant', 'Enters a row for each variant feature'], ['AnnotatedVDB::Variant', 'updates annotation']];

  my $tablesDependedOn = [['AnnotatedVDB::Variant', 'lookups']];

  my $howToRestart = '';

  my $failureCases = '';

  my $notes = <<NOTES;

This plugin needs to run at least twice; the second (or third) time w/the flag --loadNovelVariants.  The first pass should specify the --loadVaraints flag and loads variants already present in the AnnotatedVDB and writes a vcf file (for each input file) containing any that are "novel" or missing from the AnnotatedVDB.  Then run the plugin again with the flag --annotateNovelVariants to run vep against the list of missing variants & load the results & then the CADD scores (ths flag can be used with the first pass).  A final pass with the --loadNovelVariants will load the newly annotated variants in the GenomicsDB.  This could not be done in a single pass becuase there is sometimes a network lag and/or some sort of caching issue w/the db handle and the FDW linking the GenomicsDB to the AnnotatedVDB returns NULL for variants just loaded, even though they are present in the AnnotatedVDB.

NOTE: If no QC info is available (e.g. INDELS), assumes QC passing status.

In this version of the plugin, updates are performed as encountered; inserts are written to file that is then
loaded in bulk w/PG COPY statement.

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
  my $argumentDeclaration    = &getArgumentsDeclaration();

  $self->initialize({requiredDbVersion => 4.0,
		     cvsRevision => '$Revision: 193 $',
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

  $self->setVariantIdFields();
  $self->{housekeeping} = PluginUtils::buildHouseKeepingString($self);

  my @files = $self->getFileList();

  if ($self->getArg('skipPattern')) {
    my @skipPattern = split /,/, $self->getArg('skipPattern');
    $self->{skip} = \@skipPattern;
    $self->log("\nSkipping files that match the following patterns: " . Dumper($self->{skip})) 
  }

  $self->{annotator} = VariantAnnotator->new({plugin => $self});
  $self->{annotator}->createQueryHandles();  

  for my $file (@files) {
    next if $file =~ m/novel/g; # just in case there are some -novel.txt/.vcf files in the path
    next if $self->skip($file); # file containes skipped chr

    $self->annotateNovelVariants($file) if ($self->getArg('annotateNovelVariants'));
    $self->loadVariants($file) if  ($self->getArg('findNovelVariantsOnly'));

    if ($self->getArg('loadVariants')) {
      $self->loadVariants($file);
    }

    if ($self->getArg('loadNovelVariants')) {
      $self->loadVariants($file . '-novel.txt');
    }
  }

}

# ----------------------------------------------------------------------
# methods 
# ----------------------------------------------------------------------

sub skip {
  my ($self, $fileName) = @_;
  return 0 if !($self->getArg('skipPattern'));
  my @skip = @{$self->{skip}};
  foreach my $pattern (@skip) {
    if ($fileName =~ m/\.$pattern\./g) {
      $self->log("SKIPPING: $fileName");
      return 1;
    }
  }
  return 0;
}


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


sub setVariantIdFields {
  my ($self) = @_;

  my $ref = $self->getArg('refAllele');
  my $alt = $self->getArg('altAllele');
  my $pos = $self->getArg('position');
  my $chr = $self->getArg('chromosome');

  $self->{variant_id_fields} = {};

  if ($pos eq $chr) { # likely id'd as chr:pos:ref:alt; throw errors later
    if ($ref eq $pos) {
      $self->{variant_id_fields}->{type} = 'METASEQ_ID';
      $self->{variant_id_fields}->{columns} = {};
      $self->{variant_id_fields}->{columns}->{marker} = $chr;
    }
    else { # chr:pos supplied in same field
      $self->{variant_id_fields}->{type} = 'LOCATION';
      $self->{variant_id_fields}->{columns} = {};
      $self->{variant_id_fields}->{columns}->{location} = $chr;
      $self->{variant_id_fields}->{columns}->{ref} = $ref;
      $self->{variant_id_fields}->{columns}->{alt} = $alt; 
   }
  }
  else {
    $self->{variant_id_fields}->{type} = 'NONE';
    $self->{variant_id_fields}->{columns} = {};
      $self->{variant_id_fields}->{columns}->{chr} = $chr;
      $self->{variant_id_fields}->{columns}->{pos} = $pos;
      $self->{variant_id_fields}->{columns}->{ref} = $ref;
      $self->{variant_id_fields}->{columns}->{alt} = $alt; 
  }
}

sub getFileList {
  my ($self) = @_;

  my $pattern = $self->getArg('filePattern');

  my @files = ();
  if ($self->getArg('file')) {
    @files = split /,/, $self->getArg('file')
  }
  else {
    $self->error('Must supply filePattern if no file list provided') if (!$pattern);
    $self->log("Finding files in " . $self->getArg('fileDir') . " that match $pattern");
    opendir(my $dh, $self->getArg('fileDir')) || $self->error("Path does not exists: " . $self->getArg('fileDir'));
    @files = grep(/${pattern}/, readdir($dh));
    closedir($dh);
    # remove 'novel' files
    for my $index (reverse 0..$#files) {
    if ( $files[$index] =~ /novel/ ) { 
        splice(@files, $index, 1, ());
    }
}
  }
  $self->log("Found the following files: @files");
  return @files;
}


sub loadVariants { # load or update
  my ($self, $file) = @_;

  my $findNovelVariantsOnly = $self->getArg('findNovelVariantsOnly');
  my $bulkLoad = $self->getArg('bulkLoad');
  my $commitAfter = $self->getArg('commitAfter');

  my $updateAnnotatedVDB = !($self->getArg('skipAnnotatedVDBUpdate'));
  $self->log("SKIPPING AnnotatedVDB UPDATE") if (!$updateAnnotatedVDB);

  my $checkForDuplicates = $self->getArg('checkForDuplicates');;
  my $duplicates = ($checkForDuplicates) ? {} : undef;

  my $fields = $self->{variant_id_fields}->{columns};

  my $va = $self->{annotator};

  my $insertedRecordCount = 0;
  my $updatedRecordCount = 0;
  my $totalVariantCount = 0;
  my $lineCount = 0;
  my $novelVariantCount = 0;
  
  my $insertRecordBuffer = ($bulkLoad) ? "" : undef;
  my @updateRecordBuffer = ($bulkLoad) ? () : undef;
  my @updateAvDbBuffer = ($bulkLoad) ? () : undef;

  my $fileName = $self->getArg('fileDir') . "/" . $file;
  $self->log("Processing $fileName");

  my ($partition) = $fileName =~ m/(chr\d+|chrM)/g;

  my $updateSql = "UPDATE Variant_$partition v SET is_adsp_variant = ?::boolean, other_annotation = ?::jsonb";
  $updateSql .= " WHERE v.record_primary_key = ?";
  my $updateAvDbh = $self->{annotator}->connect2AnnotatedVDB();
  my $updateAvQh = ($bulkLoad) ? undef : $updateAvDbh->prepare($updateSql);

  my $selectSql = "SELECT other_annotation FROM Variant_$partition v WHERE v.record_primary_key = ?";
  my $selectAvDbh = $self->{annotator}->connect2AnnotatedVDB();
  my $selectAvQh = $selectAvDbh->prepare($selectSql);

  my $vifh = undef;
  my $nvfh = undef;

  if ($file !~ m/novel/g) { # don't create files for writing if processing Novel files
    my $vcfFileName = $self->getArg('fileDir') . "/" . $file . "-novel.vcf";
    open($vifh, '>', $vcfFileName ) || $self->error("Unable to create $vcfFileName for writing");
    my @vcfFields = qw(#CHROM POS ID REF ALT QUAL FILTER INFO);
    print $vifh join("\t", @vcfFields) . "\n";

    my $novelFileName = $self->getArg('fileDir') . "/" . $file . "-novel.txt";
    open($nvfh, '>', $novelFileName ) || $self->error("Unable to create $novelFileName for writing");
  }

  # --------------------
  # begin the work
  # --------------------

  open(my $fh, $fileName ) || $self->error("Unable to open $fileName for reading");

  my $header = <$fh>;
  print $nvfh $header if ($nvfh);
  chomp($header);
  my @hFields = split /\t/, $header;
  my %columns = map { $hFields[$_] => $_ } 0..$#hFields;

  my $prevLine = undef;
  while (my $line = <$fh>) {
    chomp $line;
    my @record = split /\t/, $line;
    ++$lineCount;
  
    my $chrNum = $record[$columns{$fields->{chr}}];
    my $position = $record[$columns{$fields->{pos}}];
    my $ref = $record[$columns{$fields->{ref}}];
    my $altAlleleStr = $record[$columns{$fields->{alt}}];

    $chrNum = "M" if ($chrNum eq "MT");
    my $chr = "chr" . $chrNum;

    if ($ref =~ m/,/) {
      my @refs = split /,/, $ref;
      $self->log("Found variant at $lineCount with multiple ref alleles: @refs");
      $self->error("Alleles are different") 
	if !(keys %{{ map {$_, 1} @refs }} == 1); # test that all are the same
      $ref = $refs[0]; # usually they are the same
    }

    my $annotation = $self->getArg('annotationFields') ? $self->extractAnnotation(\@record, \%columns) : undef;
    my $isAdspVariant = $annotation->{$self->getArg('adspFlag')}->{FILTER_STATUS} eq 'PASS';

    my @altAlleles = split ',', $altAlleleStr;
    foreach my $alt (@altAlleles) {
      my $metaseqId = "$chrNum:$position:$ref:$alt";
      $self->log("Processing $metaseqId") if $self->getArg('veryVerbose');

      # lookup variant in AnnotatedVDB.Variant
      my (@dbVariantIds) = $va->getAnnotatedVariants($metaseqId, undef);

      if (!@dbVariantIds) { # if variant not in AnnotatedVDB.Variant, write to file 
	if ($self->getArg('loadNovelVariants')) { # loading novel variants but still can't find it in the DB
	  $self->log("$metaseqId from novel file missing after AnnotatedVDB update");
	}
	else {
	  print $nvfh $line . "\n" if $prevLine eq $line; # to prevent printing multiallelic variants more than once
	  print $vifh join("\t", $chrNum, $position, '.', $ref, $alt, '.', '.', '.') . "\n";
	  $prevLine = $line;
	}

	++$novelVariantCount;
	++$totalVariantCount;
	$self->log("Found novel variant: " . $metaseqId) if $self->getArg('veryVerbose');
      }

      if (!$findNovelVariantsOnly) {
	# iterate over dbVariants
	# if variant in AnnotatedVDB.Variant, but not NIAGADS.Variant, insert
	# else update
	foreach my $dbv (@dbVariantIds) {
	  ++$totalVariantCount;
	  $self->log("Matched: " . Dumper($dbv)) if $self->getArg('veryVerbose');

	  my $recordPK = $dbv->{record_primary_key};

	  if ($checkForDuplicates) { # avoid primary key violations
	    next if (exists $duplicates->{$recordPK});
	    $duplicates->{$recordPK} = 1;
	  }

	  my $variant = GUS::Model::NIAGADS::Variant
	    ->new({record_primary_key => $recordPK});

	  unless ($variant->retrieveFromDB()) { # if not in db; slow when not
	    $self->log("Variant $recordPK not found in GenomicsDB.") 
	      if $self->getArg('veryVerbose');

	    my $props = $va->inferVariantLocationDisplay($ref, $alt, $position, $position);

	    if ($self->getArg('bulkLoad')) {
	      $insertRecordBuffer .= VariantLoadUtils::generateCopyStr($self, $dbv, $props,
								       $annotation, $isAdspVariant);
	    }
	    else {
	      my $jsonStr = Utils::to_json($annotation);
	      $variant->setIsAdspVariant($isAdspVariant);
	      VariantLoadUtils::insertNiagadsVariant($variant, $dbv, $props, $jsonStr);
	      $self->log("Submitted new record for $recordPK.") if $self->getArg('veryVerbose');
	    }
	    ++$insertedRecordCount;
	  }

	  else { # update existing variants
	    $self->log("Variant $metaseqId mapped to annotated variant $recordPK")
	      if $self->getArg('veryVerbose');

	    $annotation =  PluginUtils::generateUpdatedJsonFromGusObj($self, $variant, 'annotation', $annotation);

	    if ($bulkLoad) {
	      push(@updateRecordBuffer,
		   VariantLoadUtils::niagadsVariantUpdateValuesStr($recordPK, $annotation, $isAdspVariant));
	    }
	    else {
	      $variant->setAnnotation(Utils::to_json($annotation)) if ($annotation);
	      $variant->setIsAdspVariant(1) if ($isAdspVariant);
	      $variant->submit() if $self->getArg('commit'); # don't do the update in non-commit mode
	      $self->log("Updated $recordPK.") if $self->getArg('veryVerbose');
	    }
	    ++$updatedRecordCount;
	  }

	  # update AnnotatedVDB.Variant -> ADSP Status/GenomicsDB annotation
	  if ($updateAnnotatedVDB) {
	    my %qcResult = zip @hFields, @record;
	    if ($bulkLoad) {
	      push(@updateAvDbBuffer, 
		   VariantLoadUtils::annotatedVariantUpdateValueStr($self, $recordPK, \%qcResult, $annotation, $selectAvQh));
	    }
	    else {
	      VariantLoadUtils::updateAnnotatedVariantRecord($self, $recordPK, \%qcResult, $annotation, $updateAvQh, $selectAvQh);
	    }
	  }
	}

	if ($bulkLoad) {
	  unless ($totalVariantCount % $commitAfter) {
	    $self->log("Found $totalVariantCount variants; Performing Bulk Inserts/Updates.");
	    PluginUtils::bulkCopy($self, $insertRecordBuffer, VariantLoadUtils::getCopySql());
	    VariantLoadUtils::bulkNiagadsVariantUpdate($self, @updateRecordBuffer);
	    VariantLoadUtils::bulkAnnotatedVariantUpdate($self, $updateAvDbh, $partition, @updateAvDbBuffer)
		if ($self->getArg('commit' ) and $updateAnnotatedVDB); # b/c table is not logged
	    @updateRecordBuffer = ();
	    @updateAvDbBuffer = ();
	    $insertRecordBuffer = "";
	  }
	}
      }

      unless ($lineCount % 10000) {
	$self->log("Read $lineCount lines; # variants: $totalVariantCount; updates: $updatedRecordCount; inserts: $insertedRecordCount; novel: $novelVariantCount");
	$self->undefPointerCache();
      }
    }
  }

  if ($bulkLoad and !$findNovelVariantsOnly) { # insert residual
    $self->log("Found $totalVariantCount variants; Performing Bulk Inserts/Updates.");
    PluginUtils::bulkCopy($self, $insertRecordBuffer, VariantLoadUtils::getCopySql());
    VariantLoadUtils::bulkNiagadsVariantUpdate($self, @updateRecordBuffer);
    VariantLoadUtils::bulkAnnotatedVariantUpdate($self, $updateAvDbh, $partition, @updateAvDbBuffer)
	if ($self->getArg('commit' ) and $updateAnnotatedVDB); # b/c table is not logged

    @updateRecordBuffer = ();
    @updateAvDbBuffer = ();
    $insertRecordBuffer = "";
  }

  $self->log("DONE: Read $lineCount lines; # variants: $totalVariantCount; updates: $updatedRecordCount; inserts: $insertedRecordCount; NOVEL: $novelVariantCount");

  $fh->close();

  if ($nvfh) {
    $vifh->close();
    $nvfh->close();
  }

  $updateAvQh->finish() if (!$bulkLoad);
  $updateAvDbh->disconnect();
  $selectAvQh->finish();
  $selectAvDbh->disconnect();

  $self->log("Read $lineCount lines from file.");
  $self->log("Processed $totalVariantCount records from file.");
  $self->log("Updated $updatedRecordCount records.");
  $self->log("Inserted $insertedRecordCount records.");
  $self->log("Found $novelVariantCount novel variants.");
  return $novelVariantCount;
}

sub extractAnnotation {
  my ($self, $record, $columns) = @_;

  my $json = JSON::XS->new;
  my $adspFlag = $self->getArg('adspFlag');
  my $annotation = {};
  $annotation->{$adspFlag} = {};
  my $fields = $json->decode($self->getArg('annotationFields')) || $self->error("Error parsing annotation field JSON");
  my $mterm = $adspFlag . "_";
  while (my ($cName, $label) = each (%$fields)) {
    $label =~ s/$mterm//g;
    $annotation->{$adspFlag}->{$label} = $$record[$columns->{$cName}];
  }

  $annotation->{$adspFlag}->{FILTER_STATUS} = $FILTER_STATUS->{$annotation->{$adspFlag}->{FILTER}};
  return (%$annotation) ? $annotation : undef;
}



# ----------------------------------------------------------------------
sub undoTables {
  my ($self) = @_;
  return (); # tallying number of inserts takes too long
}

1;
