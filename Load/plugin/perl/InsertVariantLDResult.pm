## InsertVariantLDResult.pm.pm
## $Id: InsertVariantLDResult.pm.pm $
##

package GenomicsDBData::Load::Plugin::InsertVariantLDResult;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use GUS::PluginMgr::Plugin;
use POSIX qw(strftime);

use Data::Dumper;

use GUS::Model::Results::VariantLD;
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
COPY Results.VariantLD (
population_protocol_app_node_id,
chromosome,
variants,
locations,
minor_allele_frequency,
distance,
r_squared,
d_prime,
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
     stringArg({name => 'dir',
		descr => 'directory containing LD output',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0
	       }),
     stringArg({name => 'sourceId',
		descr => 'protocol app node source id',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0
	       }),
     stringArg({name => 'skipChr',
		descr => 'skip the specified chromosome',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0
	   }),

     stringArg({name => 'onlyChr',
		descr => 'only do the specified chromosome',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0
	   }),

    ];
  return $argumentDeclaration;
}

# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
  my $purposeBrief = 'Loads Variant LD result';

  my $purpose = 'Loads Variant LD result';

  my $tablesAffected = [['Results::VariantLD', 'Enters a row for each variant feature']];

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
		     cvsRevision => '$Revision: 19 $',
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
  my $skipChr = ($self->getArg('skipChr')) ? 'chr' . $self->getArg('skipChr') . '.' : undef;
  my $onlyChr = ($self->getArg('onlyChr')) ? 'chr'. $self->getArg('onlyChr') . '.' : undef;

  $self->{protocol_app_node_id} = $self->getProtocolAppNodeId();

  my @files = $self->getFiles();
  foreach my $f (@files) {
    if ($skipChr) {
      if ($f =~ /\Q$skipChr/) {
	$self->log("Skipping: $f");
	next;
      }
    }
    if ($onlyChr) {
      unless ($f =~ /\Q$onlyChr/) {
	$self->log("Skipping $f");
	next;
      }
    }
    $self->log("Processing $f");
    $self->copy($f);
  }

}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub getFiles {
  my ($self) = @_;

  my $dir = $self->getArg('dir');
  opendir(DIR, $dir);
  my @files = grep(/preprocess_chr.*\.txt$/,readdir(DIR));
  closedir(DIR);
  return @files;
}

sub copy {
  my ($self, $file) = @_;
  open(my $fh, $self->getArg('dir') . "/" . $file ) || $self->error("Unable to read $file");

  $file =~ m/(chrX|chrY|chrMT|chr\d+)/;
  my $chromosome = $1;
  $chromosome = 'chrM' if $chromosome =~ m/MT/;

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
    $dbh->pg_putcopydata($protocolAppNodeId . "|" . $fieldValues . "|" . $housekeeping . "\n");
    unless (++$count % 5000000) {
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
#sub undoTables {
#  my ($self) = @_;
#  return ('Results.VariantLD');
#}



1;
