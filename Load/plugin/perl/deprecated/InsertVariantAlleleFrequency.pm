## InsertVariantAlleleFrequency.pm
## $Id: InsertVariantAlleleFrequency.pm $
##

package GenomicsDBData::Load::Plugin::InsertVariantAlleleFrequency;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use GUS::PluginMgr::Plugin;
use Data::Dumper;
use Scalar::Util qw(looks_like_number);
use POSIX qw(strftime);
use JSON::XS;

use GUS::Model::Results::VariantFrequency;


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

my $NA_FEATURE_SQL= <<NA_SQL;
SELECT na_feature_id, primary_key FROM DoTS.SnpFeature
WHERE variant_id = ? AND name != 'dbSNP_merge'
NA_SQL

my $NA_FEATURE_POSITION_SQL= <<NA_POS_SQL;
SELECT na_feature_id, primary_key FROM DoTS.SnpFeature
WHERE chromosome = ? and ref_allele = ? and alt_allele = ? and vcf_position = ?
NA_POS_SQL


my $varInsertCount = 0;

# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
  my $argumentDeclaration  =
    [
     fileArg({name => 'file',
	      descr => 'full path to preprocessed result',
	      constraintFunc=> undef,
	      reqd  => 1,
	      isList => 0,
	      mustExist => 1,
	      format => 'txt'
	     }),   
     stringArg({name => 'protocolAppNode',
	      descr => '
	      constraintFunc=> undef,
	      reqd  => 1,
	      isList => 0,
	      mustExist => 1,
	      format => 'txt'
	     }),


    ];
  return $argumentDeclaration;
}

# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
  my $purposeBrief = 'Loads Niagads.VariantAlleleFrequency';

  my $purpose = 'This plugin reads a csv load file into NIAGADS.VariantAlleleFrequency';

  my $tablesAffected = [['NIAGADS::VariantAlleleFrequency', 'one row per allele frequency']];

  my $tablesDependedOn = [['DoTS::SnpFeature', 'looks up SNP feature'],['Study::ProtocolAppNode', 'looks up populations']];

  my $howToRestart = '';

  my $failureCases = '';

  my $notes = <<NOTES;

Written by Emily Greenfest-Allen
Copyright Trustees of University of Pennsylvania 2016. 
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
		     cvsRevision => '$Revision: 19208 $',
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

  $self->{file} = 'results_seqvariation_' . $self->getArg('population') . 'csv';

  $self->{extDbRlsId} = $self->getExtDbRlsId($self->getArg('extDbRlsSpec'));
  $self->{popExtDbRlsId} = $self->getExtDbRlsId($self->getArg('popExtDbRlsSpec'))
    if ($self->getArg('popExtDbRlsSpec'));
  $self->getPopulationProtocolAppNode();
  $self->insertRecords('Variant Allele Frequencies');

}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub buildCopySQL {
  my ($self, $fields) = @_;

  $fields =~ s/variant_id/variant_primary_key/;

  my $prefix= <<PREFIX;
COPY Niagads.VariantAlleleFrequency (
na_feature_id,
protocol_app_node_id,
PREFIX

  my $suffix = <<SUFFIX;
) FROM STDIN
WITH (DELIMITER '|', 
NULL 'NULL')
SUFFIX

  my $sql = $prefix . $fields . "," . $HOUSEKEEPING_FIELDS . $suffix;
  $self->log("COPY SQL: $sql");
  return $sql;
}



sub buildHousekeeping {
  my ($self) = @_;

  my $algInvId = $self->getAlgInvocation()->getId();
  my $rowUserId = $self->getAlgInvocation()->getRowUserId();
  my $rowGroupId = $self->getAlgInvocation()->getRowGroupId();
  my $rowProjectId = $self->getAlgInvocation()->getRowProjectId();

  my $currentTime = getCurrentTime();

  my $housekeeping = join("|",
			  $currentTime,
			  1, 1, 1, 1, 1, 0, 
			  $rowUserId, $rowGroupId,
			  $rowProjectId, $algInvId);
  return $housekeeping;
}

sub getPopulationProtocolAppNode() {
  my ($self) = @_;

  my $protocolAppNode = GUS::Model::Study::ProtocolAppNode
    ->new( {
	    name => $self->getArg('population'),
	    external_database_release_id => $self->{popExtDbRlsId},
	   });
  unless ($protocolAppNode->retrieveFromDB()) {
    $self->error("No entry in Study.ProtocolAppNode found for " 
		 . $self->getArg('population') . "; "
		 . $self->getArg('popExtDbRlsSpec'));
  }
  $self->{pop_protocol_app_node_id} =  $protocolAppNode->getId();
}

sub insertRecords {
  my ($self, $recordType) = @_;

  my $fileName = $self->getArg('file');
  open(my $fh, $fileName) || $self->error("Unable to open $fileName");

  my $fields = <$fh>;
  chomp($fields);
  $fields =~ s/\|/,/g;

  my $sql = $self->buildCopySQL($fields);

  # return if (!$self->getArg('commit'));

  my $housekeeping = $self->buildHousekeeping();

  $self->log("Beginning COPY");

  my $dbh = $self->getDbHandle();
  $dbh->do($sql); # puts database in copy mode; no other trans until finished

  my $count = 0;
  while (my $fieldValues = <$fh>) {
    chomp($fieldValues);
    my ($variantId, @values) = split /\|/, $fieldValues;
    my ($features, $pks) = $self->getVariantFeatures($variantId);

    $self->log($fieldValues) if $self->getArg('veryVerbose');
    $self->log("Length features = " . @$features . ": @$features[0] - @$pks[0]") if ($self->getArg('veryVerbose'));

    if (@$features == 0) {
      $self->log("No feature found for variant $variantId.");
      next;
    }

    foreach my $i (0 .. $#$features) {

      $fieldValues = join("|", @$features[$i], $self->{pop_protocol_app_node_id}, @$pks[$i], @values, $housekeeping) . "\n"; # drop variant_id
      $self->log($fieldValues) if ($self->getArg('veryVerbose'));

      $dbh->pg_putcopydata($fieldValues);
      unless (++$count % 50000) {
	$self->log("Inserted $count $recordType records.");
	$dbh->pg_putcopyend(); # end copy trans can no do other things
	$self->getDbHandle()->commit(); # commit
	$dbh->do($sql); # puts database in copy mode; no other trans until finished
      }
    }
    $self->undefPointerCache();
  }

  $self->log("DONE: Inserted $count $recordType records.");
  $dbh->pg_putcopyend(); # end copy trans can now do other things
  $self->getDbHandle()->commit(); # commit
  $fh->close();
}


sub reverseAllele {
  my ($a) = @_;
  return 'T' if ($a eq 'A');
  return 'A' if ($a eq 'T');
  return 'G' if ($a eq 'C');
  return 'C' if ($a eq 'G');
}


sub getVariantFeatureById {
  my ($self, @variants) = @_;

  my @features;
  my @pks;

  my $qh = $self->getQueryHandle()->prepare($NA_FEATURE_SQL);

  my $found = 0;
  foreach my $v (@variants) {
    $qh->execute($v);
    while (my ($naFeatureId, $primaryKey) = $qh->fetchrow_array()) {
      push(@features, $naFeatureId);
      push(@pks, $primaryKey);
      $found = 1;
    }
    last if ($found); # alt ids are prioritized
  }
  $qh->finish();

  return \@features, \@pks;
}


sub getVariantFeaturesByVcfPosition {
  my ($self, $variantId) = @_;
  my @features;
  my @pks;
  my ($chr, $pos, $ref, $alt) = split /:/, $variantId;

  my $qh = $self->getQueryHandle()->prepare($NA_FEATURE_POSITION_SQL);

  $qh->execute('chr' . $chr, $ref, $alt, $pos);

  while (my ($naFeatureId, $primaryKey) = $qh->fetchrow_array()) {
    $self->log($primaryKey);
    push(@features, $naFeatureId);
    push(@pks, $primaryKey);
  }

  $qh->finish();

  return \@features, \@pks;
}


sub getVariantFeatures {
  my ($self, $variantId) = @_;

  my $features = undef;
  my $pks = undef;

  ($features, $pks) = $self->getVariantFeatureById(($variantId));
  if (!@$features and $self->getArg('checkAltVariantIds')) {
    my @altVariantIds;
    my ($chr, $pos, $ref, $alt) = split /:/, $variantId;
    $self->log("Variant $variantId not found in DB; matching alteratives");
    push(@altVariantIds, "$chr:$pos:$alt:$ref"); # flip allele
    push(@altVariantIds, "$chr:$pos:" . reverseAllele($ref) . ":" . reverseAllele($alt));
    push(@altVariantIds, "$chr:$pos:" . reverseAllele($alt) . ":" . reverseAllele($ref));
    ($features, $pks) = $self->getVariantFeatureById((@altVariantIds));
  }

 

  if (!@$features and $self->getArg('matchVcfPosition')) {
    $self->log("Variant $variantId not found in DB; matching VCF position");
   ($features, $pks) = $self->getVariantFeaturesByVcfPosition($variantId);
  }

  return $features, $pks;
}



sub getCurrentTime {
  return strftime '"%Y-%m-%d %H:%M:%S"', localtime;
}




# ----------------------------------------------------------------------
# sub undoTables {
#   my ($self) = @_;

#   return ('Study.ProtocolAppNode'); # results.seqvariation, dots.snpfeature take too long
# }




1;
