## InsertPopulationStudy.pm
## $Id: InsertStudy.pm $
##

package NiagadsData::Load::Plugin::InsertStudy;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use GUS::PluginMgr::Plugin;
use Data::Dumper;
use JSON;

use GUS::Model::Study::Study;
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
     stringArg({ name  => 'approaches',
                 descr => "approaches field",
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),

     stringArg({ name  => 'description',
                 descr => "description",
                 constraintFunc => undef,
                 reqd           => 1,
                 isList         => 0 
	       }),

     stringArg({ name  => 'attribution',
                 descr => "attribution",
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),

     stringArg({ name  => 'name',
                 descr => "study name",
                 constraintFunc => undef,
		 reqd           => 1,
                 isList         => 0 
	       }),

     stringArg({ name  => 'sourceId',
                 descr => "unique source_id for the study",
                 constraintFunc => undef,
                 reqd           => 1,
                 isList         => 0 
	       }),

     stringArg({ name  => 'extDbRlsSpec',
                 descr => "The ExternalDBRelease specifier for the study. Must be in the format 'name|version', where the name must match a name in SRes::ExternalDatabase and the version must match an associated version in SRes::ExternalDatabaseRelease.",
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
  my $purposeBrief = 'Adds a study';

  my $purpose = 'Adds a study';

  my $tablesAffected = [['Study::Study', 'Enters a row for the study']];

  my $tablesDependedOn = [['SRes::OntologyTerm', 'For setting mapping type/subtype']];

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
		     cvsRevision => '$Revision: 9 $',
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

  $self->loadStudy();  
}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub loadStudy {
  my ($self) = @_;

  my $extDbRlsId = $self->getExtDbRlsId($self->getArg('extDbRlsSpec'));
  my $attribution = $self->getArg('attribution') ? $self->getArg('attribution') : undef;

  my $study = GUS::Model::Study::Study
    ->new({name => $self->getArg('name'),
	   description => $self->getArg('description'),
	   source_id => $self->getArg('sourceId'),
	   external_database_release_id => $extDbRlsId
	  });

  $study->setAttribution($self->getArg('attribution')) 
    if ($attribution);

  $study->setApproaches($self->getArg('approaches')) 
    if ($self->getArg('approaches'));

  $study->submit() unless ($study->retrieveFromDB());
}



# ----------------------------------------------------------------------
# supporting methods
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

  return ('Study.Study');
}



1;
