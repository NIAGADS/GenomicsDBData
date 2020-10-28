## InsertRecordGWASCounts.pm
## $Id: InsertRecordGWASCounts.pm $
##

package NiagadsData::Load::Plugin::InsertRecordGWASCounts;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use GUS::PluginMgr::Plugin;
use Data::Dumper;

use GUS::Model::NIAGADS::RecordGWASCounts;

my $CHARACTERISTIC_SQL= <<SQL;
SELECT string_agg(ot.name) AS phenotypes
FROM Study.Characteristic c,
SRes.OntologyTerm ot,
SRes.OntologyTerm qot
WHERE c.protocol_app_node_id = ?
AND qot.ontology_term_id = c.qualifier_id
AND c.ontology_term_id = ot.ontology_term_id
SQL


# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
  my $argumentDeclaration  =
    [
     stringArg({ name => 'record_type',
                 descr => 'gene or variant',
                 constraintFunc=> undef,
                 reqd  => 1,
                 isList => 0,
	       }),
     stringArg({ name => 'dataset',
                 descr => 'GWAS dataset id (not resource accession)',
                 constraintFunc=> undef,
                 reqd  => 1,
                 isList => 0,

	       }),
    ];
  return $argumentDeclaration;
}

# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
  my $purposeBrief = 'Populates NIAGADS.RecordGWASCounts for a specified dataset';

  my $purpose = 'Populates NIAGADS.RecordGWASCounts for a specified dataset';

  my $tablesAffected = [['NIAGADS::RecordGWASCounts', 'inserts one row per feature']];

  my $tablesDependedOn = [];

  my $howToRestart = '';

  my $failureCases = '';

  my $notes = <<NOTES;

Written by Emily Greenfest-Allen
Copyright Trustees of University of Pennsylvania 2020. 
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

  $self->{protocol_app_node_id} = $self->getProtocolAppNodeId();
  $self->{diagnosis} = $self->getCharacteristics('diagnosis');
  $self->{neuropathology} = $self->getCharacteristics('neuropathology');

  if (lc($self->getArg('recordType')) eq 'gene') {
    $self->insertVariantsPerGeneCounts('diagnosis');
    $self->insertVariantsPerGeneCounts('neuropathology');
  $self->insertVariantCounts() if lc($self->getArg('recordType')) eq 'variant';
}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub getCharacteristics {
  my ($self, $category) = @_;

  my $sql = $CHARACTERISTIC_SQL;
  if ($category eq 'diagnosis') {
    $sql += " AND (qot.name = 'diagnosis' AND ot.name != 'autopsy-based diagnosis')";
  }
  else {
    $sql += " AND qot.name = 'neuropathology'";
  }

  my $qh = $self->getQueryHandle()->prepare($sql);
  $qh->execute($self->{protocol_app_node_id});
  my ($phenotypes) = $qh->fetch;
  $qh->finish();
  return $phenotypes;
}


sub summarizeCharacterisitics {
  my ($self, $category) = @_;

  my @phenotypes = split /,/, $self->{$category};
  for my $i (0 .. $#phenotypes) {
    my $p = $phenotypes[$i];

    if ($category eq "diagnosis") {
      $phenotypes[$i] = "PSP" if $p =~ /Progressive/;
      $phenotypes[$i] = "FTD" if $p =~ /Frontotemporal/;
      $phenotypes[$i] = "AD" if $p =~ /Alzheimer/;
      $phenotypes[$i] = "LBD" if $p =~ /Lewy/;
      $phenotypes[$i] = "DEM" if $p =~ /dementia/;
    }
    else {
      $phenotypes[$i] = "Braak" if $p =~ /Braak/;
      $phenotypes[$i] = "CERAD" if $p =~ /CERAD/;
      $phenotypes[$i] = "CAA" if $p =~ /angiopathy/;
      $phenotypes[$i] = "HS-Aging" if $p =~ /hippocampal/;
      $phenotypes[$i] = "LB" if $p =~ /Lewy/;
      $phenotypes[$i] = "NP" if $p =~ /plaques/;
      $phenotypes[$i] = "NT" if $p =~ /tangles/;
      $phenotypes[$i] = "VBI" if $p =~ /vascular/;
    }
  }

  return \@phenotypes;
}


sub insertVariantsPerGeneCounts {
  my ($self, $category) = @_;

  my $phenotypes = $self->summaryCharacteristics($category);



}


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

sub getProtocolAppNodeId {
  my ($self) = @_;
  my $protocolAppNode = GUS::Model::Study::ProtocolAppNode
    ->new({source_id => $self->getArg('dataset')});
  $self->error("No protocol app node found for " . $self->getArg('dataset'))
    unless $protocolAppNode->retrieveFromDB();
  return $protocolAppNode->getProtocolAppNodeId();
}



# ----------------------------------------------------------------------
sub undoTables {
  my ($self) = @_;

  return ('DoTS.Gene');
}



1;
