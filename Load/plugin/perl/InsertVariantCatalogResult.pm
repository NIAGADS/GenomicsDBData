## InsertVariantCatalogResult.pm.pm
## $Id: InsertVariantCatalogResult.pm.pm $
##

package NiagadsData::Load::Plugin::InsertVariantCatalogResult;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use GUS::PluginMgr::Plugin;
use POSIX qw(strftime);

use Data::Dumper;

use GUS::Model::Results::VariantCatalog;
use GUS::Model::Study::ProtocolAppNode;

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
COPY Results.VariantCatalog (
protocol_app_node_id,
variant_id,
ontology_term_id,
allele,
frequency,
neg_log10_pvalue,
pvalue_display,
evidence,
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
     fileArg({name => 'file',
	      descr => 'preprocessed file; expects output from generateVariantCatalogLoadFile',
	      constraintFunc=> undef,
	      reqd  => 1,
	      isList => 0,
	      mustExist =>1,
	      format => 'txt'
	     }),
     stringArg({name => 'sourceId',
		descr => 'protocol app node source id',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0
	       })

    ];
  return $argumentDeclaration;
}

# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
  my $purposeBrief = 'Loads Variant Catalog result';

  my $purpose = 'Loads Variant Catalog result';

  my $tablesAffected = [['Results::VariantCatalog', 'Enters a row for each variant feature']];

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
		     cvsRevision => '$Revision: 25 $',
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
 
  $self->{protocol_app_node_id} = $self->getProtocolAppNodeId();

  $self->copy();

}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub copy {
  my ($self) = @_;
  open(my $fh, $self->getArg('file')) || $self->error("Unable to read " . $self->getArg('file'));

  my $protocolAppNodeId = $self->{protocol_app_node_id};

  my $algInvId = $self->getAlgInvocation()->getId();
  my $rowUserId = $self->getAlgInvocation()->getRowUserId();
  my $rowGroupId = $self->getAlgInvocation()->getRowGroupId();
  my $rowProjectId = $self->getAlgInvocation()->getRowProjectId();
  my $housekeeping = join('|', 	  getCurrentTime(),
			  1, 1, 1, 1, 1, 0,
			  $rowUserId, $rowGroupId,
			  $rowProjectId, $algInvId);

  my $dbh = $self->getDbHandle();
  $dbh->do($COPY_SQL); # puts database in copy mode; no other trans until finished

  my $count = 0;

  while (my $fieldValues = <$fh>) {
    chomp($fieldValues);
    $fieldValues =~ s/\s+\|/\|/g; # sometimes there are extra spaces
    $fieldValues =~ s/\|\|/\|NULL\|/g;

    $dbh->pg_putcopydata($protocolAppNodeId . "|" . $fieldValues . "|" . $housekeeping . "\n");

    if ($self->getArg('veryVerbose')) {
      my @data = split /\|/, $protocolAppNodeId . "|" . $fieldValues . "|" . $housekeeping;
      my @logdata = ($count + 1, scalar @data, @data);
      $self->log(Dumper(\@logdata));
    }

    unless (++$count % 50000) {
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


sub getProtocolAppNodeId {
  my ($self) = @_;
  my $protocolAppNode = GUS::Model::Study::ProtocolAppNode
    ->new({source_id => $self->getArg('sourceId')});
  $self->error("No protocol app node found for " . $self->getArg('sourceId'))
    unless $protocolAppNode->retrieveFromDB();
  return $protocolAppNode->getProtocolAppNodeId();
}

sub getCurrentTime {
  return strftime '"%Y-%m-%d %H:%M:%S"', localtime;
}

# ----------------------------------------------------------------------
sub undoTables {
  my ($self) = @_;
  return ('Results.VariantCatalog');
}



1;
