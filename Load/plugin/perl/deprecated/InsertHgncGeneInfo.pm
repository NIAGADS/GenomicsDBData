## InsertHgncGeneInfo.pm
## $Id: InsertHgncGeneInfo.pm $
## 

package GenomicsDBData::Load::Plugin::InsertHgncGeneInfo;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;

use JSON;

use GUS::PluginMgr::Plugin;
use GUS::Model::NIAGADS::GeneAnnotation;
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
	  format => 'output of generateHgncAnnotationLoadFile (ensembl_gene_id\tjson)'
        }),
     stringArg({ name  => 'extDbRlsSpec',
                 descr => "The ExternalDBRelease specifier for the VEP analysis. Must be in the format 'name|version', where the name must match a name in SRes::ExternalDatabase and the version must match an associated version in SRes::ExternalDatabaseRelease.",
                 constraintFunc => undef,
                 reqd           => 1,
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
  my $purposeBrief = 'Loads HGNC Gene Annotation as a mapping from Ensembl ID -> json';

  my $purpose = 'Loads HGNC Gene Annotation as a mapping from Ensembl ID -> json';

  my $tablesAffected = [['NIAGADS::GeneAnnotation', 'Enters a row for each gene']];

  my $tablesDependedOn = [['DoTS::Gene', 'for extracting gene ids']];

  my $howToRestart = '';

  my $failureCases = '';

  my $notes = <<NOTES;

Written by Emily Greenfest-Allen
Copyright Trustees of University of Pennsylvania 2013. 
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
		     cvsRevision => '$Revision: 19167 $',
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
  $self->{extDbRlsId} = $self->getExtDbRlsId($self->getArg('extDbRlsSpec'));
  $self->loadAnnotation();

}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub loadAnnotation {
  my ($self) = @_;

  my $skip = 0;

  my $file = $self->getArg('file');
  open (my $fh, $file) || die "Can't open $file.  Reason: $!\n";

  while (<$fh>) {
    chomp;
    my ($ensemblId, $json) = split /\t/;

    my $gene = GUS::Model::DoTS::Gene->new({source_id => $ensemblId});

    if (!$gene->retrieveFromDB()) {
      $self->log("Gene $ensemblId not found in DoTS.Gene");
      if ($self->getArg('mapThruSymbol')) {
	my $annotations = from_json $json;
	$gene = GUS::Model::DoTS::Gene->new({gene_symbol => $annotations->{symbol}});
	unless ($gene->retrieveFromDB()) {
	  $self->log("Gene " . $annotations->{symbol} . " not found in DoTS.Gene");
	  $skip++;
	  next;
	}
      }
      else {
	$skip++;
	next;
      }
    }

    my $geneId = $gene->getGeneId();
    my $geneAnnotation = GUS::Model::NIAGADS::GeneAnnotation
      ->new({
	     gene_id => $geneId,
	     source_id => $ensemblId,
	     annotation => $json,
	     external_database_release_id => $self->{extDbRlsId}
	    });    
    $geneAnnotation->submit();
  }
  $fh->close();
  $self->log("Skipped $skip genes");
}


# ----------------------------------------------------------------------
sub undoTables {
  my ($self) = @_;

  return ('NIAGADS.GeneAnnotation');
}



1;
