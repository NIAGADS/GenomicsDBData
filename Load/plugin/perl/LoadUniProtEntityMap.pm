## LoadUniProtEntityMap.pm
## $Id: LoadUniProtEntityMap.pm $
##

package GenomicsDBData::Load::Plugin::LoadUniProtEntityMap;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use GUS::PluginMgr::Plugin;
use Data::Dumper;

use GUS::Model::NIAGADS::UniProtEntityMap;


# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
  my $argumentDeclaration  =
    [
     fileArg({name => 'file',
	      descr => 'file containing entity mapping / downloaded from UniProt',
	      constraintFunc => undef,
	      reqd => 1,
	      isList => 0,
	      mustExist => 1,
	      format => '.dat (may be gzipped, but much slower load)'
             }),

     stringArg({ name  => 'extDbRlsSpec',
                 descr => "The ExternalDBRelease specifier for the go association file. Must be in the format 'name|version', where the name must match a name in SRes::ExternalDatabase and the version must match an associated version in SRes::ExternalDatabaseRelease.",
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
  my $purposeBrief = 'Loads UniProt Entity Mapping';

  my $purpose = 'This plugin loads the NIAGADS.UniProtEntityMap table';

  my $tablesAffected = [['NIAGADS::UniProtEntityMap', 'Enters a row for each id mapping']];

  my $tablesDependedOn = [];

  my $howToRestart = '';

  my $failureCases = '';

  my $notes = <<NOTES;
Written by Emily Greenfest-Allen
Copyright Trustees of University of Pennsylvania 2022. 
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

  my $xdbr = $self->getExtDbRlsId($self->getArg('extDbRlsSpec'));
  my $file = $self->getArg('file');
  my $fh = undef;
  if ($file =~ m/\.gz$/) {
    $self->log("Opening gzipped entity file.");
    open($fh, "zcat $file |")  || $self->error("Can't open gzipped $file.");
    $self->log("Done opening file.");
  }
  else {
    open ($fh, $file) || $self->error("Can't open $file.");
  }

  my $count = 0;
  $self->log("Processing");
  while(<$fh>) {
    chomp;
    my ($uniprotId, $database, $mappedId) = split /\t/;
    my $entity = GUS::Model::NIAGADS::UniProtEntityMap
      ->new({
	     uniprot_id => $uniprotId,
	     database => $database,
	     mapped_id => $mappedId,
	     external_database_release_id => $xdbr});

    $entity->submit(); # unless $entity->retrieveFromDB();
    if (++$count % 50000 == 0) {
      $self->log("Parsed $count entity mappings.");
      $self->undefPointerCache();
    }
  }
}

# ----------------------------------------------------------------------
sub undoTables {
  my ($self) = @_;

  return ('NIAGADS.UniProtEntityMap');
}



1;
