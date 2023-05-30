# InsertSectionToSourceMapping.pm
## $Id: InsertSectionToSourceMapping.pm

package GenomicsDBData::Documentation::Plugin::InsertSectionToSourceMapping;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use JSON::XS;
use File::Slurp;
use Data::Dumper;

use GUS::PluginMgr::Plugin;
use GUS::Model::NIAGADS::WebsiteDatasources;
use GUS::Model::SRes::ExternalDatabaseRelease;
# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
  my $argumentDeclaration  =
    [
     fileArg({name => 'file',
          descr => 'full path to tab-delim input file',
          constraintFunc => undef,
          reqd => 1,
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
  my $purposeBrief = 'Loads section to data source mappings for the website documentation';

  my $purpose = 'Loads section to data source mappings for the website documentation';

  my $tablesAffected = [['NIAGADS::WebsiteDataSources', 'enter a row for each association']];

  my $tablesDependedOn = [];

  my $howToRestart = '';

  my $failureCases = '';

  my $notes = <<NOTES;

File Format: Assume following columns, in order:

record_class
category
accession
version

Written by Emily Greenfest-Allen
Copyright Trustees of University of Pennsylvania 2023.
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

  $self->load();
}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub load {
  my ($self) = @_;

  my $fileName = $self->getArg('file');
  open(my $fh, $fileName) || $self->error("Unable to open $fileName.  Reason $!");
  my $header = <$fh>;
  while (my $line = <$fh>) {
    chomp($line);
    my ($rclass, $category, $accession, $version) = split /\t/, $line;
    my $extDbRlsId = $self->lookupExtDbRls($accession, $version);

    my $dsObj = GUS::Model::NIAGADS::WebsiteDatasources->new({
      record_class => $rclass,
      website_category => $category,
      external_database_release_id => $extDbRlsId
    });

    $dsObj->submit() unless ($dsObj->retrieveFromDB());
  }

  $fh->close();

}

sub lookupExtDbRls {
  my ($self, $idType, $version) = @_;
  my $xdbr = GUS::Model::SRes::ExternalDatabaseRelease->new({
    id_type => $idType,
    version => $version
  });
  
  $self->error("Resource $idType | $version not found in database") 
    unless ($xdbr->retrieveFromDB());

  return $xdbr->getExternalDatabaseReleaseId();

}

# ----------------------------------------------------------------------
sub undoTables {
  my ($self) = @_;

  return ('NIAGADS.WebsiteDatasources');
}



1;
