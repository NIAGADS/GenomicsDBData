## LoadVariantsFromVcf Plugin
## $Id: LoadVariantsFromVcf.pm $
##

package NiagadsData::Load::Plugin::LoadVariantsFromVcf;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use GUS::PluginMgr::Plugin;
use Data::Dumper;
use Vcf;
use JSON;
use Scalar::Util qw(looks_like_number);
use POSIX qw(strftime);

use Package::Alias VariantAnnotator => 'NiagadsData::Load::VariantAnnotator';

use GUS::Model::NIAGADS::Variant;
use GUS::Model::DoTS::ExternalNASequence;
use GUS::Model::SRes::OntologyTerm;

my $SOURCE = 'dbSNP';

my $soTermIdHash = {};
my $currentChr = "none";
my @indexBin;
my @indexStart;
my @indexEnd;
my $currentIndexBin;

my $HOUSEKEEPING_FIELDS = <<HOUSEKEEPING;
modification_date,
user_read,
user_write,
group_read,
group_write,
other_read,
other_write,
row_user_id,
row_group_id,
row_project_id,
row_alg_invocation_id
HOUSEKEEPING

my $COPY_VARIANT_SQL = <<COPY_VARIANT_SQL;
COPY NIAGADS.Variant (
variant_id,
bin_index,
external_database_release_id,
source_id,
source,
chromosome,
position,
location_start,
location_end,
ref_allele,
alt_allele,
display_allele,
variant_class_id,
variant_class_abbrev,
is_multi_allelic,
minor_allele_count,
is_reversed,
metaseq_id,
-- upstream_sequence,
-- downstream_sequence,
sequence_allele,
record_pk,
annotation,
$HOUSEKEEPING_FIELDS
)
FROM STDIN 
WITH (DELIMITER '|', 
NULL 'NULL')
COPY_VARIANT_SQL

# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
  my $argumentDeclaration  =
    [
     stringArg({name => 'vcfFileDir',
	      descr => 'The full path to the directory containing VCF files.',
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

     stringArg({ name  => 'vcfFile',
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

     booleanArg({ name  => 'loadSequences',
                 descr => "populate flanking sequences",
                 constraintFunc => undef,
                 isList         => 0,
		 reqd => 0
	       }),

     booleanArg({ name  => 'preprocess',
                 descr => "preprocess?",
                 constraintFunc => undef,
                 isList         => 0,
		 reqd => 0
	       }),

     booleanArg({ name  => 'bulkLoad',
                 descr => "load from preprocess files",
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
  my $purposeBrief = 'Loads variants from a VCF file';

  my $purpose = 'This plugin reads variants from a VCF file, and inserts them into NIAGADS.Variants';

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
		     cvsRevision => '$Revision: 39 $',
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

  my @files = $self->getVcfFileList();
  for my $file (@files) {
    $self->preprocess($file) if $self->getArg('preprocess');
    $self->copy($file) if $self->getArg('bulkLoad');
    # $self->loadVariants($file) if (!$self->getArg('preprocess') and !$self->getArg('bulkLoad'));
  }
}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub getVcfFileList {
  my ($self) = @_;

  my @files = ();
  if ($self->getArg('vcfFile')) {
    @files = split /,/, $self->getArg('vcfFile')
  }
  else {
    opendir(my $dh, $self->getArg('vcfFileDir')) || $self->error("Path does not exists: " . $self->getArg('vcfFileDir'));
    @files = grep(/\.vcf$/, readdir($dh));
    closedir($dh);
  }
  $self->log("Found the following files: @files") if $self->getArg('verbose');
  return @files;
}


sub copy {
  my ($self, $file) = @_;
  my $outputFileName = 'preprocess_' . $file . '.txt';
  $self->log("Loading $outputFileName") if $self->getArg('verbose');
  open(my $fh, '<', $self->getArg('vcfFileDir') . "/" . $outputFileName ) || $self->error("Unable to read $outputFileName");

  my $dbh = $self->getDbHandle();
  $dbh->do($COPY_VARIANT_SQL); # puts database in copy mode; no other trans until finished

  my $algInvId = $self->getAlgInvocation()->getId();
  my $count = 0;
  while (my $fieldValues = <$fh>) {
    chomp($fieldValues);
    $dbh->pg_putcopydata($fieldValues . "|" . $algInvId . "\n");
    unless (++$count % 500000) {
      $dbh->pg_putcopyend(); # end copy trans can no do other things
      $self->getDbHandle()->commit() if $self->getArg('commit');# commit
      $self->log("Inserted $count records.");
      $dbh->do($COPY_VARIANT_SQL); # puts database in copy mode; no other trans until finished
    }
  }
  $dbh->pg_putcopyend(); # end copy trans can no do other things
  $self->getDbHandle()->commit() if $self->getArg('commit');# commit
  $self->log("Inserted $count records.");
  $fh->close();
}

sub preprocess {
  my ($self, $file) = @_;

  my $outputFileName = 'preprocess_' . $file . '.txt';
  open(my $fh, '>', $self->getArg('vcfFileDir') . "/" . $outputFileName ) || $self->error("Unable to create $outputFileName");

  my $rowUserId = $self->getAlgInvocation()->getRowUserId();
  my $rowGroupId = $self->getAlgInvocation()->getRowGroupId();
  my $rowProjectId = $self->getAlgInvocation()->getRowProjectId();

  my $source = $self->getArg('variantSource');

  my $variantId = $self->getNextVariantId();

  $self->log("Preprocessing $file");
  my $vcf = Vcf->new(file=>$self->getArg('vcfFileDir') . '/' . $file);
  $self->{vcf_handler} = $vcf;
  $vcf->parse_header();
  my $recordCount = 0;
  while (my $record = $vcf->next_data_array()) {
    my $annotation = {};
    my $sourceId = $vcf->get_column($record, "ID");
    my $chrNum = $vcf->get_column($record, "CHROM");
    $chrNum = "M" if ($chrNum eq "MT");
    my $chr = "chr" . $chrNum;

    my $position = $vcf->get_column($record, "POS");
    my $ref = $vcf->get_column($record, "REF");
    my $altAlleleStr = $vcf->get_column($record, "ALT");

    my $info = $vcf->get_column($record, "INFO");
    my $vc = $vcf->get_info_field($info, "VC");
    my $isReversed = ($vcf->get_info_field($info, "RV")) ? 1 : "NULL";

    my $rsPosition = $vcf->get_info_field($info, "RSPOS");
    my $dbSnpBld = $vcf->get_info_field($info, "dbSNPBuildID");
    $annotation->{dbSNPBuildID} = $dbSnpBld if $dbSnpBld;

    my @altAlleles = split ',', $altAlleleStr;
    my $minorAlleleCount = scalar @altAlleles;
    my $isMultiallelic = ($minorAlleleCount > 1) ? 1 : "NULL";

    foreach my $alt (@altAlleles) {
      my $metaseqId = "$chrNum:$position:$ref:$alt";
      my $primaryKey = $metaseqId . "_" . $sourceId;
      my $annotation = to_json $annotation;

      my $props = VariantAnnotator::inferVariantLocationDisplay($self, $ref, $alt, $position, $rsPosition, $vc);
      my $binIndex = $self->getBinIndex($chr, $props->{locationStart});

      $self->log(Dumper($props)) if $self->getArg('veryVerbose');

      my @record = (++$variantId, $binIndex, $self->{external_database_release_id}, $sourceId,
		    $source, $chr, $position, $props->{locationStart}, $props->{locationEnd},
		    $ref, $alt, $props->{displayAllele}, $self->getSequenceOntologyTermId($props->{variantClass}),
		    $props->{variantClassAbbrev}, $isMultiallelic, $minorAlleleCount, $isReversed, 
		    $metaseqId, # $upstream, $downstream,
		    $props->{sequenceAllele},
		    $primaryKey, $annotation,
		    getCurrentTime(),
		    1, 1, 1, 1, 1, 0,
		    $rowUserId, $rowGroupId,
		    $rowProjectId);
      print $fh join('|', @record) . "\n";
    
      unless (++$recordCount % 500000) {
	$self->log("Wrote $recordCount Variant records.") if $self->getArg('verbose');
      }
    }
  }
  $fh->close();
  $self->log("Wrote $recordCount Variant records.");
  $vcf->close();
  $self->restartPKSequence($variantId);
}


# ----------------------------------------------------------------------
# supporting methods
# ----------------------------------------------------------------------

sub getBinIndex {
  my ($self, $chr, $locStart) = @_;
  $self->fetchBinsFromDB($chr) if ($currentChr ne $chr);
  # since vcf is sequential next variant will be in the same as last 
  # or the next, so start from there
  for my $i ($currentIndexBin .. $#indexBin) {
    if (VariantAnnotator::inRange($self, $locStart, ($indexStart[$i], $indexEnd[$i]))) {
      $currentIndexBin = $i; 
      return $indexBin[$i];
    }
  }
  # possible that moved to next bin due to indel, 
  # so check one bin back before throwing error
  return $indexStart[--$currentIndexBin]
    if (VariantAnnotator::inRange($self, $locStart, ($indexStart[$currentIndexBin - 1], $indexEnd[$currentIndexBin - 1])));

  $self->error("No bin found for $chr:$locStart - " . $indexBin[$currentIndexBin]);
}



sub fetchBinsFromDB {
  my ($self, $chr) = @_;
  $self->log("Fetching Bins for $chr") if $self->getArg("verbose");
  $currentChr = $chr;
  my $sql = <<SQL;
SELECT global_bin_path,
location_start, location_end
FROM CBIL.BinIndexRef
WHERE global_bin_path::text ~ 'L4'
and chromosome = '$chr'
SQL
  my $qh = $self->getQueryHandle()->prepare($sql)
    or $self->error(DBI::errstr);
  $qh->execute();
  @indexBin = ();
  @indexStart = ();
  @indexEnd = ();
  $currentIndexBin = 0;
  while (my ($bin, $locStart, $locEnd) = $qh->fetchrow_array()) {
    push(@indexBin, $bin);
    push(@indexStart, $locStart);
    push(@indexEnd, $locEnd);
  }
  $qh->finish();
}

sub restartPKSequence {
  my ($self, $value) = @_;
  my $sql = "ALTER SEQUENCE NIAGADS.Variant_SQ RESTART WITH $value";

  my $qh = $self->getQueryHandle()->prepare($sql)
    or $self->error(DBI::errstr);
  $qh->execute();
  $qh->finish();
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

sub getNextVariantId {
  my ($self) = @_;

  my $SQL = "SELECT nextval('NIAGADS.Variant_SQ')";

  my $qh = $self->getQueryHandle()->prepare($SQL);
  $qh->execute();
  my ($pk) = $qh->fetchrow_array();
  $qh->finish();

  return $pk;
}

sub getCurrentTime {
  return strftime '"%Y-%m-%d %H:%M:%S"', localtime;
}



# ----------------------------------------------------------------------
# sub undoTables {
#   my ($self) = @_;

#   # return ('NIAGADS.Variant');
# }



1;
