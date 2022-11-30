
## InsertJsonGeneInfo.pm
## $Id: InsertJsonGeneInfo.pm $
##

package GenomicsDBData::Load::Plugin::InsertJsonGeneInfo;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use JSON::XS;
use GUS::PluginMgr::Plugin;

use GUS::Model::SRes::DbRef;
use GUS::Model::DoTS::Gene;


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
          format => 'output of generate<>AnnotationLoadFile (ensembl_gene_id\tjson)'
             }),
      stringArg({ name  => 'extDbRlsSpec',
                  descr => "The ExternalDBRelease specifier for the gene info file. Must be in the format 'name|version', where the name must match a name in SRes::ExternalDatabase and the version must match an associated version in SRes::ExternalDatabaseRelease.",
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0
                }),
          booleanArg({ name  => 'mapThruSymbol',
                 descr => "map through gene symbol when fail to map through ensembl id",
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0
               }),
    ];
  return $argumentDeclaration;
}

# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
  my $purposeBrief = 'Loads Gene Annotation as a mapping from Ensembl ID -> json';

  my $purpose = 'Loads Gene Annotation as a mapping from Ensembl ID -> json';

  my $tablesAffected = [['SRes::DbRef', 'enter a row for each annotation']];

  my $tablesDependedOn = [['DoTS::Gene', 'for extracting gene ids']];

  my $howToRestart = '';

  my $failureCases = '';

  my $notes = <<NOTES;

Written by Emily Greenfest-Allen
Copyright Trustees of University of Pennsylvania 2018.
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

  $self->loadAnnotation();
}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub loadAnnotation {
  my ($self) = @_;

  my $extDbRlsId = $self->getExtDbRlsId($self->getArg('extDbRlsSpec'));
  my $skip = 0;

  my $file = $self->getArg('file');
  open (my $fh, $file) || die "Can't open $file.  Reason: $!\n";

  while (<$fh>) {
    chomp;
    my ($ensemblId, $json) = split /\t/;
    my $gene = GUS::Model::DoTS::Gene->new({source_id => $ensemblId});

    my $primaryId = ($gene->retrieveFromDB()) ? $gene->getGeneId() : undef;

    if (!$primaryId) {
      $self->log("Gene $ensemblId not found in DoTS.Gene");
    }

    if (!$primaryId and $self->getArg('mapThruSymbol')) {
      my $annotations = from_json $json;
      $gene = GUS::Model::DoTS::Gene->new({gene_symbol => $annotations->{symbol}});
      $primaryId = ($gene->retrieveFromDB()) ? $gene->getGeneId() : undef;
      $self->log("Gene " . $annotations->{symbol} . " not found in DB") if (!$primaryId);
    }

    if (!$primaryId) {
      $self->undefPointerCache();
      $skip++;
      next;
    }

    my $dbRef = GUS::Model::SRes::DbRef
      ->new({external_database_release_id => $extDbRlsId,
             primary_identifier => $gene->getGeneId(),
             remark => $json
            });

    $dbRef->submit();
    $self->undefPointerCache();
  }
  $fh->close();
  $self->log("Skipped $skip genes");
}


# ----------------------------------------------------------------------
sub undoTables {
  my ($self) = @_;

  return ('SRes.DbRef');
}



1;
