## LoadMergedVariants.pm
## $Id: LoadMergedVariants.pm $
##

package GenomicsDBData::Load::Plugin::LoadMergedVariants;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use GUS::PluginMgr::Plugin;
use POSIX qw(strftime);

use Data::Dumper;
use JSON;

use GUS::Model::NIAGADS::Variant;
use GUS::Model::NIAGADS::MergedVariant;

my %variants = {};

my $HOUSEKEEPING_FIELDS =<<HOUSEKEEPING;
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

my $COPY_SQL=<<SQL;
COPY NIAGADS.MergedVariant (
ref_snp_id,
merge_ref_snp_id,
merge_variant_id,
merge_build,
merge_date,
$HOUSEKEEPING_FIELDS
)
FROM STDIN 
WITH (DELIMITER '|', 
NULL 'NULL')
SQL

# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
  my $argumentDeclaration  =
    [
     stringArg({name => 'file',
		descr => 'full path to file; expects output from generateMergedVariantLoadFile',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0
	       }),

    ];
  return $argumentDeclaration;
}

# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
  my $purposeBrief = 'Loads dbSNP merged ref SNP ids from a JSON file';

  my $purpose = 'This plugin reads merged refSNPs from a JSON file, and inserts them into NIAGADS.MergedVariant & NIAGADS.Variant';

  my $tablesAffected = [['NIAGADS::Variant', 'Enters a row for each variant feature'], ['NIAGADS::MergedVariant', 'Enters one row for each merge relationship']];

  my $tablesDependedOn = [];

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
		     cvsRevision => '$Revision: 12 $',
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
 
  $self->copy();

}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub copy {
  my ($self) = @_;
  my $file = $self->getArg('file');
  open(my $fh, $file ) || $self->error("Unable to read $file");

  my $dbh = $self->getDbHandle();
  $dbh->do($COPY_SQL); # puts database in copy mode; no other trans until finished
  my $algInvId = $self->getAlgInvocation()->getId();
  my $count = 0;

  my $rowUserId = $self->getAlgInvocation()->getRowUserId();
  my $rowGroupId = $self->getAlgInvocation()->getRowGroupId();
  my $rowProjectId = $self->getAlgInvocation()->getRowProjectId();
  my $housekeeping = join('|', 	  getCurrentTime(),
		  1, 1, 1, 1, 1, 0,
		  $rowUserId, $rowGroupId,
		  $rowProjectId, $algInvId);

  while (my $fieldValues = <$fh>) {
    chomp($fieldValues);
    $dbh->pg_putcopydata($fieldValues . "|" . $housekeeping . "\n");
    unless (++$count % 500000) {
      $dbh->pg_putcopyend();   # end copy trans can no do other things
      $self->getDbHandle()->commit() if $self->getArg('commit'); # commit
      $self->log("Inserted $count records.");
      $dbh->do($COPY_SQL); # puts database in copy mode; no other trans until finished
    }
  }
  $dbh->pg_putcopyend();       # end copy trans can no do other things
  $self->getDbHandle()->commit() if $self->getArg('commit'); # commit
  $self->log("Inserted $count records.");
  $fh->close();
}


# ----------------------------------------------------------------------
# supporting methods
# ----------------------------------------------------------------------


sub getCurrentTime {
  return strftime '"%Y-%m-%d %H:%M:%S"', localtime;
}

# ----------------------------------------------------------------------
sub undoTables {
  my ($self) = @_;
  return ('NIAGADS.MergedVariant');
}



1;
