# LoadOntologyTerms.pm
## $Id: LoadOntologyTerms.pm

package GenomicsDBData::Load::Plugin::LoadOntologyTerms;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use JSON::XS;
use IO::Zlib;
use Data::Dumper;

use GUS::PluginMgr::Plugin;

use GUS::Model::SRes::OntologyTerm;
use GUS::Model::SRes::OntologyRelationship;
use GUS::Model::SRes::OntologySynonym;

# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
  my $argumentDeclaration  = [];

  return $argumentDeclaration;
}


# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
  my $purposeBrief = 'Loads ontology terms, synonyms, and relationships from an OWL file';

  my $purpose = 'Loads ontology terms, synonyms, and relationships from an OWL file';

  my $tablesAffected = [['SRes::OntologyTerm', 'enter a row for or update each term'],
                        ['SRes::OntologySynonym', 'enter a row for each synonym'],
                        ['SRes::OntologyRelationship', 'enter a row for each relation']];

  my $tablesDependedOn = [];

  my $howToRestart = '';

  my $failureCases = '';

  my $notes = <<NOTES;
Written by Emily Greenfest-Allen
Copyright Trustees of University of Pennsylvania 2023.
NOTES

  my $documentation = {purpose=>$purpose, purposeBrief=>$purposeBrief, 
                       tablesAffected=>$tablesAffected, tablesDependedOn=>$tablesDependedOn, 
                       howToRestart=>$howToRestart, failureCases=>$failureCases, notes=>$notes};

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
                     cvsRevision => '$Revision: 1 $',
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

  $self->parseOwlFile();
  # my $extDbRlsId = $self->getExtDbRlsId($self->getArg('extDbRlsSpec'));
  my $ontologyTerms, $demotedTerms = $self->loadTerms();
  $self->loadSynonyms($ontologyTerms, $demotedTerms);
  # $self->loadRelationships($ontologyTerms);
}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub parseOwlFile {
    my ($self) = @_;

    # make call to niagads-pylib/owl_parser
}

sub loadTerms {
    my ($self) = @_;
    my $ontologyTerms = {};
    my $demotedTerms = {};

    # for each term in the term file

    # is it already in DB (term)
    # if yes; is the ID the same?
    # if no; is the new term in the preferred namespace?

    return $ontologyTerms, $demotedTerms
}

sub loadSynonyms  {
    my ($self, $ontologyTerms, $demotedTerms) = @_;
}
sub loadRelationships {
    my ($self, $ontologyTerms) = @_;
}

# ----------------------------------------------------------------------
sub undoTables {
  my ($self) = @_;

  return ('SRes.OntologyTerm', 'SRes.OntologySynonym', 'SRes.OntologyRelationship');
}
