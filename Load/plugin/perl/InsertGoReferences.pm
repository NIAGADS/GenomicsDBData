# InsertGOReferences.pm
## $Id: InsertGOReferences.pm

package GenomicsDBData::Load::Plugin::InsertGoReferences;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use JSON::XS;
use File::Slurp;
use Data::Dumper;

use GUS::PluginMgr::Plugin;

use GUS::Model::SRes::BibliographicReference;
use GUS::Model::SRes::OntologyTerm;

# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
  my $argumentDeclaration  =
    [
     fileArg({name => 'file',
          descr => 'pathname for the file',
          constraintFunc => undef,
          reqd => 1,
          isList => 0,
          mustExist => 1,
          format => 'json'
             }),

     stringArg({ name  => 'extDbRlsSpec',
                 descr => "The Gene Ontology ExternalDBRelease specifier for the file. Must be in the format 'name|version', where the name must match a name in SRes::ExternalDatabase and the version must match an associated version in SRes::ExternalDatabaseRelease.",
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
  my $purposeBrief = 'Loads GO Reference File';

  my $purpose = 'Loads GO Gene References from go-ref.json';

  my $tablesAffected = [['SRes::BibliographicReference', 'enter a row for each reference']];

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
  my $argumentDeclaration    = &getArgumentsDeclaration();

  $self->initialize({requiredDbVersion => 4.0,
                     cvsRevision => '$Revision$',
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

  $self->loadReferences();
}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub loadReferences {
  my ($self) = @_;

  my $extDbRlsId = $self->getExtDbRlsId($self->getArg('extDbRlsSpec'));
  my $bibRefTypeId = $self->getOntologyTermId("Data reference");
  my $firstRecord = 1;
  my $json = JSON::XS->new();

  my $file = $self->getArg('file');
  my $content = read_file($file)
    || $self->error("Can't open $file.  Reason: $!\n");

  my $contentJson = $json->decode($content) || $self->error("Error decoding file JSON");  

  foreach my $record (@$contentJson) {
    next if exists $record->{is_obsolete};

    my @ids = ($record->{id});
    push (@ids, @{$record->{alt_id}}) if (exists $record->{alt_id});

    foreach my $id (@ids) {
       my $bibRef = GUS::Model::SRes::BibliographicReference
	 ->new({source_id => $id});

       $bibRef->setTitle($record->{title}) if (exists $record->{title});
       
       my $useComments = 0;
       my $abstract = "No abstract available.";
       if (exists $record->{abstract}) {
	 if ($record->{abstract} eq "No abstract available.") {
	   $useComments = 1;
	 }
	 else {
	   $abstract = $record->{abstract};
	 }
       }
       else {
	 $useComments = 1;
       }
       if (exists $record->{comments} and $useComments) {
	 $abstract = $record->{comments} if ($record->{comments} ne "n/a");
       }
       $bibRef->setAbstract($abstract);
       $bibRef->setAuthors($record->{authors}) if (exists $record->{authors});
       $bibRef->setYear($record->{year}) if (exists $record->{year});
       $bibRef->setPublication($record->{citation}) if (exists $record->{citation});
       $bibRef->setBibRefTypeId($bibRefTypeId);
      
       $bibRef->submit();
    }
    $self->undefPointerCache();
  }

}


# ----------------------------------------------------------------------
# supporting methods
# ----------------------------------------------------------------------


sub getOntologyTermId {
  my ($self, $value) = @_;

  my $ontologyTerm = GUS::Model::SRes::OntologyTerm
    ->new({name => $value});

  $self->error("Term $value not found in SRes.OntologyTerm")
    unless ($ontologyTerm->retrieveFromDB());

  return $ontologyTerm->getOntologyTermId();

}

# ----------------------------------------------------------------------
sub undoTables {
  my ($self) = @_;

  return ('SRes.BibliographicReference');
}



1;
