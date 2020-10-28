## LoadGeneFromGeneFeature.pm
## $Id: LoadGeneFromGeneFeature.pm $
##

package NiagadsData::Load::Plugin::LoadGeneFromGeneFeature;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use GUS::PluginMgr::Plugin;
use Data::Dumper;

use GUS::Model::DoTS::Gene;
use GUS::Model::DoTS::GeneFeature;
use GUS::Model::DoTS::GeneInstance;

my $SQL= <<SQL;
SELECT na_feature_id, name AS symbol, source_id
FROM DoTS.GeneFeature
SQL


# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
  my $argumentDeclaration  =
    [
    ];
  return $argumentDeclaration;
}

# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
  my $purposeBrief = 'Populates DoTS.Gene from DoTS.GeneFeature';

  my $purpose = 'This plugin populates DoTS.Gene from DoTS.GeneFeature and links the two via DoTS.GeneInstance';

  my $tablesAffected = [['DoTS::Gene', 'Enters a row for each gene feature'], ['DoTS::GeneInstance', 'Enters a row for gene-feature link'], ];

  my $tablesDependedOn = [['DoTS::GeneFeature', 'for extracting gene info']];

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
		     cvsRevision => '$Revision: 19147 $',
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

  $self->loadGenes();


}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub loadGenes {
  my ($self) = @_;

  my $qh = $self->getQueryHandle()->prepare($SQL);
  $qh->execute();
  my $count = 0;
  while (my ($naFeatureId, $symbol, $sourceId) = $qh->fetchrow_array()) {
    $self->log("NA_FEATURE_ID: $naFeatureId; SYMBOL: $symbol, SOURCE_ID: $sourceId") if $self->getArg('veryVerbose');
    my $gene = GUS::Model::DoTS::Gene
      ->new({gene_symbol => $symbol,
	     source_id => $sourceId});

    my $geneInstance = GUS::Model::DoTS::GeneInstance
      ->new({na_feature_id => $naFeatureId});
    $geneInstance->setParent($gene);

    $gene->submit();

    unless (++$count % 5000) {
      $self->log("Inserted $count genes.");
      $self->undefPointerCache();
    }
  }


  $qh->finish();
}


# ----------------------------------------------------------------------
sub undoTables {
  my ($self) = @_;

  return ('DoTS.Gene');
}



1;
