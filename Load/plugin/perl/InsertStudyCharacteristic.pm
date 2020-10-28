## InsertStudyCharacteristic.pm
## $Id: InsertStudyCharacteristic.pm $
##

package GenomicsDBData::Load::Plugin::InsertStudyCharacteristic;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use GUS::PluginMgr::Plugin;
use Data::Dumper;

use GUS::Model::SRes::OntologyTerm;
use GUS::Model::Study::ProtocolAppNode;
use GUS::Model::Study::Characteristic;


# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
  my $argumentDeclaration  =
    [
     fileArg({name => 'file',
	      descr => 'full path to tab-delimited input file; see notes',
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
  my $purposeBrief = 'Populates Study.Characteristic';

  my $purpose = 'This plugin populates Study.Characteristics';

  my $tablesAffected = [['Study.Characteristic', 'Enters a row for each characteristic']];

  my $tablesDependedOn = [['SRes.OntologyTerm', 'look up ontology term ids']];

  my $howToRestart = '';

  my $failureCases = '';

  my $notes = <<NOTES;
Input file should be tab-delim and contain the following labeled columns: protocol_app_node_source_id ontology_term_source_id qualifier_ontology_term_source_id display_value.  The file may contain additional columns; they will be ignored

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
		     cvsRevision => '$Revision: 19494 $',
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

  $self->loadTerms();


}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub loadTerms {
  my ($self) = @_;


  open (my $fh, $self->getArg('file')) || $self->error("Unable to open " . $self->getArg('file'));
  my $header = <$fh>;
  chomp($header);
  my @fields = split /\t/, $header;
  my %fieldIndexes = map {uc($fields[$_]) => $_} 0..$#fields;

  while (<$fh>) {
    chomp;
    my @values = split /\t/;
    
    my $panSourceId = $values[$fieldIndexes{PROTOCOL_APP_NODE_SOURCE_ID}];
    my $ontologyTermRef = $values[$fieldIndexes{ONTOLOGY_TERM_SOURCE_ID}];
    my $qualifierTermRef = $values[$fieldIndexes{QUALIFIER_SOURCE_ID}];
    my $displayValue = $values[$fieldIndexes{DISPLAY_VALUE}];

    my $protocolAppNodeId = $self->getProtocolAppNodeId($panSourceId);
    my $ontologyTermId = $self->getOntologyTermId($ontologyTermRef);
    my $qualifierTermId = $self->getOntologyTermId($qualifierTermRef);

    my $characteristic = GUS::Model::Study::Characteristic->new({
								 protocol_app_node_id => $protocolAppNodeId,
								 ontology_term_id => $ontologyTermId,
								 qualifier_id => $qualifierTermId
								});

    if ($displayValue or $displayValue ne '') {
      $characteristic->setValue($displayValue);
    }

    $characteristic->submit();

  }
  $fh->close();

}


sub getProtocolAppNodeId {
  my ($self, $sourceId) = @_;

  my $protocolAppNode= GUS::Model::Study::ProtocolAppNode
	  ->new({source_id => $sourceId});

  $self->error("Node for $sourceId not found in Study.ProtocolAppNode") if (!$protocolAppNode->retrieveFromDB());

  return $protocolAppNode->getProtocolAppNodeId();
}

sub getOntologyTermId {
  my ($self, $sourceId) = @_;

  my $ontologyTerm = GUS::Model::SRes::OntologyTerm
	  ->new({source_id => $sourceId});

  $self->error("Term $sourceId not found in SRes.OntologyTerm") if (!$ontologyTerm->retrieveFromDB());

  return $ontologyTerm->getOntologyTermId();
}

# ----------------------------------------------------------------------
sub undoTables {
  my ($self) = @_;

  return ('Study.Characteristic');
}
