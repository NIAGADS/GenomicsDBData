## LoadVariantsFromTabDelim Plugin
## $Id: LoadVariantsFromTabDelim.pm $
##

package GenomicsDBData::Load::Plugin::LoadVariantsFromTabDelim;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use GUS::PluginMgr::Plugin;
use Data::Dumper;

use JSON::XS;
use List::MoreUtils qw(first_index);


use Package::Alias VariantAnnotator => 'GenomicsDBData::Load::VariantAnnotator';

use GUS::Model::NIAGADS::Variant;
use GUS::Model::DoTS::ExternalNASequence;
use GUS::Model::SRes::OntologyTerm;

my $soTermIdHash = {};

my $filterStatus = {DISTINCT_REF_ALT => 0,
		    BOTH_failed => 0,
		    BOTH_passed => 1,
		    BAYLOR_failed_BROAD_uncalled => 0,
		    BAYLOR_passed_BROAD_uncalled => 1,
		    BROAD_failed_BAYLOR_passed => 1,
		    BROAD_passed_BAYLOR_failed => 1,
		    BROAD_passed_BAYLOR_uncalled => 1,
		    BROAD_failed_BAYLOR_uncalled => 0};



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

     stringArg({ name  => 'extDbRlsSpec',
                 descr => "The ExternalDBRelease specifier for dbSnp. Must be in the format 'name|version', where the name must match a name in SRes::ExternalDatabase and the version must match an associated version in SRes::ExternalDatabaseRelease.",
                 constraintFunc => undef,
                 reqd           => 1,
                 isList         => 0 
	       }),

     stringArg({ name  => 'soExtDbRlsSpec',
                 descr => "The ExternalDBRelease specifier for the sequence ontology. Must be in the format 'name|version', where the name must match a name in SRes::ExternalDatabase and the version must match an associated version in SRes::ExternalDatabaseRelease.",
                 constraintFunc => undef,
                 reqd           => 1,
                 isList         => 0 
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

     stringArg({ name  => 'variantSource',
                 descr => "web-friendly display for variant source",
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

     stringArg({ name  => 'genomeBuild',
                 descr => '(optional) genome build (e.g., b37) for concatenating to source_id',
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


    ];
  return $argumentDeclaration;
}

# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
  my $purposeBrief = 'Loads variants from a tab delimited filefile';

  my $purpose = 'This plugin reads variants from a tab-delimited file, and inserts them into NIAGADS.Variants';

  my $tablesAffected = [['NIAGADS::Variant', 'Enters a row for each variant feature']];

  my $tablesDependedOn = [['DoTS.ExternalNaSequence', 'looks up sequences'], ['SRes.OntologyTerm', 'looks up sequence ontology terms']];

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
  my $argumentDeclaration    = &getArgumentsDeclaration();

  $self->initialize({requiredDbVersion => 4.0,
		     cvsRevision => '$Revision: 50 $',
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

  $self->{external_database_release_id} = $self->getExtDbRlsId($self->getArg('extDbRlsSpec'));
  $self->{so_external_database_release_id} = $self->getExtDbRlsId($self->getArg('soExtDbRlsSpec'));
  $self->setVariantIdFields();

  my @files = $self->getFileList();
  for my $file (@files) {
    $self->loadVariants($file);
    $self->annotateNovelVariants($file);
    $self->loadVariants($file);
  }
}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

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
  }
  $self->log("Found the following files: @files");
  return @files;
}



sub loadVariants { # load or update
  my ($self, $file) = @_;

  my $fields = $self->{variant_id_fields}->{columns};
  my $variantIdType = $self->{variant_id_fields}->{type};
  my $variantSource = $self->getArg('variantSource');

  my $source = $self->getArg('variantSource');
  my $genomeBuild = ($self->getArg('genomeBuild')) ? '_' . $self->getArg('genomeBuild') : '';

  my $fileName = $self->getArg('fileDir') . "/" . $file;
  open(my $fh, $fileName ) || $self->error("Unable to open $fileName for reading");

  my $novelVariantsFileName = $self->getArg('fileDir') . "/" . $file . '-novel.txt';
  open(my $nvfh, '>', $novelVariantsFileName ) || $self->error("Unable to create $novelVariantsFileName for writing");

  my $vcfFileName = $self->getArg('fileDir') . "/" . $file . "-novel.vcf";
  open(my $vifh, '>', $vcfFileNae ) || $self->error("Unable to create $vcfFileName for writing");
  my @vcfFields = qw('#CHROM POS ID REF ALT QUAL FILTER INFO');
  print $vifh join('\t', @vcfFields) . "\n";

  $self->log("Processing $file");
  
  my $header = <$fh>;
  print $nvfh $header;

  chomp($header);
  my @hFields = split /\t/, $header;
  my %columns = map { $hFields[$_] => $_ } 0..$#hFields;

  my $insertedRecordCount = 0;
  my $updatedRecordCount = 0;
  my $variantCount = 0;
  my $lineCount = 0;
  my $novelVariantCount = 0;
  my ($chrNum, $ref, $position, $altAlleleStr);

  while (my $line = <$fh>) {
    chomp $line;
    my @record = split /\t/, $line;
    ++$lineCount;

    if ($variantIdType eq 'METASEQ_ID') {
      my  $index = $columns{$fields->{marker}};
      ($chrNum, $position, $ref, $altAlleleStr) = split /:/, $record[$index];
    }

    elsif ($variantIdType eq 'LOCATION') {
      my  $index = $columns{$fields->{location}};
      ($chrNum, $position) = split /:/, $record[$index];
      $ref = $record[$columns{$fields->{ref}}];
      $altAlleleStr = $record[$columns{$fields->{alt}}];
    }

    else {
      $chrNum = $record[$columns{$fields->{chr}}];
      $position = $record[$columns{$fields->{pos}}];
      $ref = $record[$columns{$fields->{ref}}];
      $altAlleleStr = $record[$columns{$fields->{alt}}];
    }

    $chrNum = "M" if ($chrNum eq "MT");
    my $chr = "chr" . $chrNum;

    if ($ref =~ m/,/) {
      my @refs = split /,/, $ref;
      $self->log("Found variant with multiple ref alleles: @refs");
      $self->error("Alleles are different") 
	if !(keys %{{ map {$_, 1} @refs }} == 1); # test that all are the same
      $ref = $refs[0]; # usually they are the same
    }

    my $annotation = $self->getArg('annotationFields') ? $self->fetchAnnotation(\@record, \%columns) : undef;

    my @altAlleles = split ',', $altAlleleStr;
    my $minorAlleleCount = scalar @altAlleles;
    my $isMultiallelic = ($minorAlleleCount > 1) ? 1 : undef;

    my $novelAlt = 0;

    foreach my $alt (@altAlleles) {
      my $metaseqId = "$chrNum:$position:$ref:$alt";

      # lookup variant in AnnotatedVDB.Variant
      my (@dbVariantIds) = VariantAnnotator::getVariants($self, $metaseqId, undef);

      if (!@dbVariantIds) { # if variant not in AnnotatedVDB.Variant, write to file for 2nd pass
	# TODO may be a weird case when multi-allelic and one variant is in db, but not other ---
	# not sure how to handle & if it actually occurs...
	print $nvfh $line;
	print $vifh join('\t', $chrNum, $position, '.', $refAllele, $alt, '.', '.', '.') . "\n";
	$novelVariantCount++;
      }

      # iterate over dbVariants
      # if variant in AnnotatedVDB.Variant, but not NIAGADS.Variant, insert
      # else update
      for each my ($dbvId @dbVariantIds) {
	if (!$dbvII->{has_genomicsdb_annotation}) {
	  $self->log("Variant $metaseqId annotated, but not found in GenomicsdB DB. Inserting.") 
	    if $self->getArg('veryVerbose');
	  
	  my $props = VariantAnnotator::inferVariantLocationDisplay($self, $ref, $alt, $position, $position);
	  my $binIndex = $self->getBinIndex($chr, $props->{locationStart});
	  
	  my $variant = GUS::Model::NIAGADS::Variant
	    ->new({external_database_release_id => $self->{external_database_release_id},
		   bin_index => $binIndex,
		   chromosome => $chr,
		   position => $position,
		   location_start => $props->{locationStart},
		   location_end => $props->{locationEnd},
		   ref_allele => $ref,
		   alt_allele => $alt,
		   display_allele => $props->{displayAllele},
		   variant_class_id => $self->getSequenceOntologyTermId($props->{variantClass}),
		   variant_class_abbrev => $props->{variantClassAbbrev},
		   is_multi_allelic => $isMultiallelic,
		   minor_allele_count => $minorAlleleCount,
		   metaseq_id => $metaseqId,
		   sequence_allele => $props->{sequenceAllele},
		   record_primary_key => $metaseqId
		  });
	  
	  $variant->setAnnotation(to_json $annotation) if ($annotation);
	  $variant = $self->setAdspFlags($variant, $annotation) if ($annotation);
	  $variant->submit();

	  ++$insertedRecordCount;
	}

	else { # update existing variants
	    my $variant = GUS::Model::NIAGADS::Variant->new({record_primary_key => $dbvId->{record_primary_key}});
	    $self->error("Could not retrieve variant with id: " . $dbvId->{record_primary_key} . " from database.") 
	      unless ($variant->retrieveFromDB());
	    $annotation = $self->generateUpdatedAnnotation($variant, $annotation) if ($annotation);
	    $variant->setAnnotation(to_json $annotation);
	    $variant = $self->setAdspFlags($variant, $annotation) if ($annotation);
	    $variant->submit();
	    
	    ++$updatedRecordCount;
	}
      }
      
      # update AnnotatedVDB.Variant -> ADSP Status/GenomicsDB annotation
      $self->updateAnnotatedVDB($metaseqId, $annotation);

      unless (++$variantCount  % 10000) {
	$self->log("Inserted/Updated annotations for $variantCount variants.");
	$self->undefPointerCache();
      }
    }
  }

  $fh->close();
  $vifh->close();
  $nvfh->close();
  $self->log("Read $lineCount lines from file.");
  $self->log("Processed $variantCount records from file.");
  $self->log("Updated $updatedRecordCount records.");
  $self->log("Inserted $insertedRecordCount records.");
  $self->log("Found $novelVariantCount novel variants.");

}

sub updateAnnotatedVDB {
  my ($self, $variantPK, $annotation) = @_;
}


# ----------------------------------------------------------------------
# supporting methods
# ----------------------------------------------------------------------


sub generateUpdatedAnnotation {
  my ($self, $variant, $annotation) = @_;
  my $json = JSON::XS->new;
  my $variantAnnotation = $variant->getAnnotation();
  if ($variantAnnotation) {
    $variantAnnotation = $json->decode($variantAnnotation) || $self->error("Error parsing variant annotation: $variantAnnotation");
    $annotation = {%$variantAnnotation, %$annotation};
  }

  return $annotation;
}

sub fetchAnnotation {
  my ($self, $record, $columns) = @_;

  my $annotation = {};
  my $json = JSON::XS->new;
  my $fields = $json->decode($self->getArg('annotationFields')) || $self->error("Error parsing annotation field JSON");
  while (my ($cName, $label) = each (%$fields)) {
    $annotation->{$label} = $$record[$columns->{$cName}];
  }
  return (%$annotation) ? $annotation : undef;
}

sub setAdspFlags {
  my ($self, $variant, $annotation) = @_;
  my $adspFlag = $self->getArg('adspFlag');
  my $pass = 0;

  if ($adspFlag eq 'ADSP_WES') {
    $pass = $filterStatus->{$annotation->{ADSP_WES_FILTER}};
  }
  if ($adspFlag eq 'ADSP_WGS') {
    $pass = $filterStatus->{$annotation->{ADSP_WGS_FILTER}};
  }

  if ($adspFlag) {
    if ($adspFlag =~ /ADSP/ and $pass) {
      $variant->setIsAdspVariant(1);
    }
    
    if ($adspFlag eq 'ADSP_WES' and $pass) {
      $variant->setIsAdspWes(1);
    }
    if ($adspFlag eq 'ADSP_WGS' and $pass) {
      $variant->setIsAdspWgs(1);
    }
  }
  
  return $variant;
}

sub getBinIndex {
  my ($self, $chr, $locStart) = @_;
  my $binIndex = VariantAnnotator::getBinIndexFromDB($self, $chr, $locStart, $locStart);
  $self->error("No bin found for $chr:$locStart") if (!$binIndex);
  return $binIndex;
}



sub getSequenceOntologyTermId {
  my ($self, $term) = @_;

  if (!exists $soTermIdHash->{$term}) {
    my $ontologyTerm = GUS::Model::SRes::OntologyTerm
      ->new({
	     name => $term,
	     external_database_release_id => $self->{so_external_database_release_id}
	    });

    $self->error("Sequence Ontology Term: $term not found in DB.")
      unless ($ontologyTerm->retrieveFromDB());

    $soTermIdHash->{$term} = $ontologyTerm->getOntologyTermId();
  }
  return $soTermIdHash->{$term};
}



# ----------------------------------------------------------------------
sub undoTables {
  my ($self) = @_;
  return ('NIAGADS.Variant');
}

1;
