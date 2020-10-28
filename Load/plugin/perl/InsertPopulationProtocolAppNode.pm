## InsertPopulationProtocolAppNode.pm
## $Id: InsertPopulationProtocolAppNode.pm $
##

package NiagadsData::Load::Plugin::InsertPopulationProtocolAppNode;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use GUS::PluginMgr::Plugin;
use Data::Dumper;

use GUS::Model::Study::ProtocolAppNode;
use GUS::Model::SRes::OntologyTerm;

my $SQL= <<SQL;
SELECT ontology_term_id 
FROM SRes.OntologyTerm WHERE lower(name) = ?
SQL


# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
  my $argumentDeclaration  =
    [
     stringArg({ name  => 'population',
                 descr => "population full name; to be mapped against SRes.Ontology Term",
                 constraintFunc => undef,
                 reqd           => 1,
                 isList         => 0 
	       }),


     stringArg({ name  => 'abbrev',
                 descr => "population abbreviation",
                 constraintFunc => undef,
                 reqd           => 1,
                 isList         => 0 
	       }),

     stringArg({ name  => 'description',
                 descr => "description",
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),

     stringArg({ name  => 'source',
                 descr => "source of the population frequency, i.e., 1000 Genome, ExAC; for display",
                 constraintFunc => undef,
                 reqd           => 1,
                 isList         => 0 
	       }),

     stringArg({ name  => 'extDbRlsSpec',
                 descr => "The ExternalDBRelease specifier for the analysis. Must be in the format 'name|version', where the name must match a name in SRes::ExternalDatabase and the version must match an associated version in SRes::ExternalDatabaseRelease.",
                 constraintFunc => undef,
                 reqd           => 1,
                 isList         => 0 
	       }),
    ];
  return $argumentDeclaration;
}

# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
  my $purposeBrief = 'Adds a protocol app node for a population underlying an allele frequency analysis.';

  my $purpose = 'Adds a protocol app node for a population underlying an allele frequency analysis.';

  my $tablesAffected = [['Study::ProtocolAppNode', 'Enters a row for each population']];

  my $tablesDependedOn = [['SRes::OntologyTerm', 'For setting the type ("population") and subtype (ethnicity) of the node']];

  my $howToRestart = '';

  my $failureCases = '';

  my $notes = <<NOTES;

Written by Emily Greenfest-Allen
Copyright Trustees of University of Pennsylvania 2017. 
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
		     cvsRevision => '$Revision: 19186 $',
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

  my $extDbRlsId = $self->getExtDbRlsId($self->getArg('extDbRlsSpec'));
  my $typeId = $self->getOntologyTermId('population');
  my $subTypeId = $self->getOntologyTermId($self->getArg('population'));

  my $protocolAppNode = GUS::Model::Study::ProtocolAppNode
    ->new({name => $self->getArg('abbrev'),
	   description => $self->getArg('description'),
	   source_id => $self->getArg('source'),
	   external_database_release_id => $extDbRlsId,
	   type_id => $typeId,
	   subtype_id => $subTypeId
	  });

  $protocolAppNode->submit() unless ($protocolAppNode->retrieveFromDB());

}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub getOntologyTermId {
  my ($self, $sourceId) = @_;

  my $qh = $self->getQueryHandle()->prepare($SQL);
  $qh->execute(lc($sourceId));
  my ($ontologyTermId) = $qh->fetchrow_array();
  $qh->finish();
  $self->error("Term $sourceId not found in SRes.OntologyTerm") if (!$ontologyTermId);

  return $ontologyTermId;
}

# ----------------------------------------------------------------------
sub undoTables {
  my ($self) = @_;

  return ('Study.ProtocolAppNode');
}



1;
