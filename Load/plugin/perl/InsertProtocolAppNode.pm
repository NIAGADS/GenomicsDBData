## InsertPopulationProtocolAppNode.pm
## $Id: InsertProtocolAppNode.pm $
##

package GenomicsDBData::Load::Plugin::InsertProtocolAppNode;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use GUS::PluginMgr::Plugin;
use Data::Dumper;
use JSON::XS;

use GUS::Model::Study::ProtocolAppNode;
use GUS::Model::Study::Characteristic;
use GUS::Model::Study::Study;
use GUS::Model::Study::StudyLink;

use GUS::Model::SRes::OntologyTerm;


# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
  my $argumentDeclaration  =
    [
     stringArg({ name  => 'biomaterialCharacteristics',
                 descr => "json string specifing characterists as qualifier:value pairs",
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),

     stringArg({ name  => 'trackSummary',
                 descr => "json string specifing JSON for track_summary field",
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),

     stringArg({ name  => 'description',
                 descr => "description",
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),

      stringArg({ name  => 'uri',
                 descr => "uri",
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),

     stringArg({ name  => 'attribution',
                 descr => "attribution",
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),

     stringArg({ name  => 'name',
                 descr => "protocol app node name",
                 constraintFunc => undef,
		 reqd           => 1,
                 isList         => 0 
	       }),

     stringArg({ name  => 'type',
                 descr => "type of protocol app node; much match term in SRes.OntologyTerm",
                 constraintFunc => undef,
		 reqd           => 1,
                 isList         => 0 
	       }),

     stringArg({ name  => 'subtype',
                 descr => "subtype of protocol app node; much match term in SRes.OntologyTerm",
                 constraintFunc => undef,
		 reqd           => 0,
                 isList         => 0 
	       }),

     stringArg({ name  => 'sourceId',
                 descr => "unique source_id for the analysis",
                 constraintFunc => undef,
                 reqd           => 1,
                 isList         => 0 
	       }),

     stringArg({ name  => 'studyId',
                 descr => "study source id to which analysis should be linked",
                 constraintFunc => undef,
                 reqd           => 0,
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
  my $purposeBrief = 'Adds a protocol app node';

  my $purpose = 'Adds a protocol app node';

  my $tablesAffected = [['Study::ProtocolAppNode', 'Enters a row for the protocol app node'],
			['Study::Characteristic', 'Enters one row for each characteristic'],
			['Study::StudyLink', 'Enters one row for each study link']];

  my $tablesDependedOn = [['SRes::OntologyTerm', 'For setting mapping characteristics'], ['Study::Study', 'lookup study']];

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
		     cvsRevision => '$Revision: 27 $',
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

  $self->loadProtocolAppNode();  
}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub loadProtocolAppNode {
  my ($self) = @_;

  my $extDbRlsId = $self->getExtDbRlsId($self->getArg('extDbRlsSpec'));
  my $typeId = $self->getOntologyTermId($self->getArg('type'));
  my $subTypeId = $self->getOntologyTermId($self->getArg('subtype'));
  my $attribution = $self->getArg('attribution') ? $self->getArg('attribution') : undef;

  my $protocolAppNode = GUS::Model::Study::ProtocolAppNode
    ->new({source_id => $self->getArg('sourceId')});
  if ($protocolAppNode->retrieveFromDB()) {
    $self->log("Protocol App Node for " . $self->getArg('sourceId') . " already exists.  Checking/Updating Characteristics.");
  }
  else {
    $protocolAppNode = GUS::Model::Study::ProtocolAppNode
      ->new({name => $self->getArg('name'),
	     source_id => $self->getArg('sourceId'),
	     external_database_release_id => $extDbRlsId,
	     type_id => $typeId
	    });

    $protocolAppNode->setAttribution($attribution)
      if ($attribution);
    
    $protocolAppNode->setSubtypeId($subTypeId)
      if ($self->getArg('subtype'));

    $protocolAppNode->setDescription($self->getArg('description'))
      if ($self->getArg('description'));

    $protocolAppNode->setUri($self->getArg('uri'))
      if ($self->getArg('uri'));

    $protocolAppNode->setTrackSummary($self->getArg('trackSummary'))
      if ($self->getArg('trackSummary'));

    $protocolAppNode->submit() unless ($protocolAppNode->retrieveFromDB());

    $self->loadStudyLink($protocolAppNode->getProtocolAppNodeId())
      if ($self->getArg('studyId'));
  }

  $self->loadCharacteristics($protocolAppNode->getProtocolAppNodeId())
    if ($self->getArg('biomaterialCharacteristics'));
    

}


sub loadStudyLink {
  my ($self, $protocolAppNodeId) = @_;

  my $study = GUS::Model::Study::Study
    ->new({source_id => $self->getArg('studyId')});
  $self->error("No study for " . $self->getArg('studyId') . " found in DB.")
    unless $study->retrieveFromDB();

  my $studyLink = GUS::Model::Study::StudyLink
    ->new({study_id => $study->getStudyId()});

  $studyLink->setProtocolAppNodeId($protocolAppNodeId);
  $studyLink->submit() unless ($studyLink->retrieveFromDB());
}


sub loadCharacteristics {
  my ($self, $protocolAppNodeId) = @_;
  my $json = JSON::XS->new;
  my $chars = $json->decode($self->getArg('biomaterialCharacteristics')) || $self->error("Error parsing characteristic JSON");
  my @terms = undef;
  while (my ($qualifier, $term) = each %$chars) {
    # $term may be an array
    if (ref($term) eq 'ARRAY') {
      $self->log("Found list of characteristics with same qualifier:" . Dumper($term));
      @terms = @$term;
    }
    else {
      @terms = ($term);
    }

    foreach my $t (@terms) {
      my $characteristic = GUS::Model::Study::Characteristic
	->new({qualifier_id => $self->getOntologyTermId($qualifier)});
      
      if ($t =~ m/^value:/) {
	$t =~ s/value://;
	$characteristic->setValue($t);
      }
      else {
	$characteristic->setOntologyTermId($self->getOntologyTermId($t));
      }
      
      $characteristic->setProtocolAppNodeId($protocolAppNodeId);
      $characteristic->submit() unless ($characteristic->retrieveFromDB());
    }
  }
}

# ----------------------------------------------------------------------
# supporting methods
# ----------------------------------------------------------------------
sub getOntologyTermId {
  my ($self, $term) = @_;

  my $SQL="SELECT ontology_term_id FROM SRes.OntologyTerm WHERE name = ?";

  my $qh = $self->getQueryHandle()->prepare($SQL);
  $qh->execute($term);
  my ($ontologyTermId) = $qh->fetchrow_array();
  $qh->finish();
  $self->error("Term $term not found in SRes.OntologyTerm") if (!$ontologyTermId);

  return $ontologyTermId;
}

# ----------------------------------------------------------------------
sub undoTables {
  my ($self) = @_;

  return ('Study.StudyLink', 'Study.Characteristic', 'Study.ProtocolAppNode');
}



1;
