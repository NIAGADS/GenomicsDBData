package GenomicsDBData::Load::Plugin::LoadGeneTraitAssociationResult;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use warnings;

use Data::Dumper;
use GUS::PluginMgr::Plugin;

use JSON;
use POSIX qw(strftime);

use GUS::Model::SRes::OntologyTerm;
use GUS::Model::Study::Study;
use GUS::Model::Study::StudyLink;

use GUS::Model::Study::Characteristic;
use GUS::Model::Study::ProtocolAppNode;
use GUS::Model::NIAGADS::GeneTraitAssociation;

use GUS::Model::DoTS::Gene;


my $HOUSEKEEPING_FIELDS = <<HOUSEKEEPING;
modification_date,
user_read,
user_write,
group_read,
group_write,
other_read,
other_write,
row_user_id,
row_group_id,
row_project_id,
row_alg_invocation_id
HOUSEKEEPING

# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
  my $argumentDeclaration  =
    [
     fileArg({name => 'file',
	      descr => 'full path to tab-delimited annotation file',
	      constraintFunc=> undef,
	      reqd  => 1,
	      isList => 0,
	      mustExist => 1,
	      format => 'txt'
	     }),
     booleanArg({ name  => 'useGeneSymbol',
                 descr => "use gene symbols instead of ensembl ids",
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),
     stringArg({ name  => 'name',
                 descr => "name associated with the Study.ProtocolAppNode for this annotation",
                 constraintFunc => undef,
                 reqd           => 1,
                 isList         => 0 
	       }),

     stringArg({ name  => 'sourceId',
                 descr => "unique source_id associated with the Study.ProtocolAppNode for this annotation",
                 constraintFunc => undef,
                 reqd           => 1,
                 isList         => 0 
	       }),

     stringArg({ name  => 'studySourceId',
                 descr => "unique source_id associated with the Study.Study for this annotation",
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),
  stringArg({ name  => 'description',
                 descr => "description for the study.protocolappnode",
                 constraintFunc => undef,
                 reqd           => 1,
                 isList         => 0 
	       }),


     stringArg({ name  => 'characteristics',
                 descr => "json string of qualifier:value pairs for characteristics",
                 constraintFunc => undef,
                 reqd           => 1,
                 isList         => 0 
	       }),

     stringArg({ name  => 'subtypeSourceRef',
                 descr => "protocolappnode subtype ontology term source ref",
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0,
		 default => 'operation_3225'
	       }),

     stringArg({ name  => 'typeSourceRef',
                 descr => "protocolappnode type ontology term source ref",
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0,
		 default => 'operation_3661'
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
  my $purposeBrief = 'Loads a gene-trait association result';

  my $purpose = 'This plugin loads a gene-trait association from pipe-delimited data and links to  protocol application node result ';

  my $tablesAffected = [ ['Study::ProtocolAppNode', 'enters a row for the data source(if needed) and the result'], ['Study::Characteristic', 'enters one row per result characteristic']];

  my $tablesDependedOn = [['SRes::OntologyTerms', 'for looking up ontology terms'], ['Study::Protocol', 'lookup protocol'],  ['DoTS.Gene', 'look up genes']];

  my $howToRestart = '';

  my $failureCases = '';

  my $notes = <<NOTES;
Example JSON config:



--------------------------------
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
		     cvsRevision => '$Revision: 19627 $',
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

  $self->insertProtocolAppNode();
  $self->insertStudyLink() if ($self->getArg('studySourceId'));
  $self->loadCharacteristics();
  $self->loadGeneTraitAssociation();

}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------


sub insertProtocolAppNode() {
  my ($self) = @_;

  my $protocolAppNode = GUS::Model::Study::ProtocolAppNode
    ->new( {
	    name => $self->getArg('name'),
	    description => $self->getArg('description'),
	    external_database_release_id => $self->{extDbRlsId},
	    source_id => $self->getArg('sourceId'),
	    subtype_id => $self->getOntologyTermId('genome-wide association study'),
	    type_id => $self->getOntologyTermId('gene annotation')
	   });
  $protocolAppNode->submit() unless ($protocolAppNode->retrieveFromDB());
  $self->{protocol_app_node_id} =  $protocolAppNode->getId();
}


sub insertStudyLink () {
  my ($self) = @_;

  my $study = GUS::Model::Study::Study
    ->new({source_id => $self->getArg('studySourceId')});
  unless ($study->retrieveFromDB()) {
    $self->error("Study " . $self->getArg('studySourceId') . " not found in database");
  }

  my $studyLink = GUS::Model::Study::StudyLink
    ->new({protocol_app_node_id => $self->{protocol_app_node_id},
	   study_id => $study->getStudyId()
	  });
  $studyLink->submit() unless ($studyLink->retrieveFromDB());
}



sub loadCharacteristics {
  my ($self) = @_;

  my $c = $self->getArg('characteristics');
  $c =~ s/\'//g; # have to strip enclosing single quotes or else decoder fails
  my $chars = decode_json $c;
  $self->log(Dumper $chars);
  foreach my $qualifier (keys %$chars) {
    $self->log($qualifier);
    my $value = $chars->{$qualifier};
    my $qualifierTermId = $self->getOntologyTermId($qualifier);
    my $characteristic = GUS::Model::Study::Characteristic
      ->new({value => $value,
	     qualifier_id => $qualifierTermId,
	     protocol_app_node_id => $self->{protocol_app_node_id}
	    });

    $characteristic->submit();
  }
}




sub loadGeneTraitAssociation {
  my ($self) = @_;
  my $fileName = $self->getArg('file');
  $self->log("Loading $fileName");
  open(my $fh, $fileName) || $self->error("Unable to open $fileName");

  my $header = <$fh>;
  chomp($header);
  my @fields = split /\|/,  $header;
  my %columns = map { $fields[$_] => $_ } 0..$#fields;

  my $count = 0;
  while (my $line = <$fh>) {
    chomp($line);

    my @values = split /\|/, $line;
    my $geneId = $self->getGeneId($values[0]); 
    my $association = GUS::Model::NIAGADS::GeneTraitAssociation
      ->new({protocol_app_node_id => $self->{protocol_app_node_id},
	     gene_id => $geneId,
	     p_value => $values[$columns{p_value}],
	     rho => $values[$columns{rho}],
	     cumulative_maf => $values[$columns{cumulative_maf}],
	     cumulative_mac => $values[$columns{cumulative_mac}],
	     num_snps => $values[$columns{num_snps}],
	     caveat => $values[$columns{caveat}]
	    });

    $association->submit(); # unless $association->retrieveFromDB();
    if (++$count % 10000 == 0) {
      $self->log("Loaded $count records")
    }
  }
  $self->undefPointerCache();
  $fh->close();
  $self->log("Loaded $count rows for this result.");


}

sub getGeneId {
  my ($self, $geneIdentifier) = @_;
  return $self->getGeneIdFromSymbol($geneIdentifier) 
    if $self->getArg('useGeneSymbol');
  my $gene = GUS::Model::DoTS::Gene
    ->new({source_id => $geneIdentifier});
  unless ($gene->retrieveFromDB()) {
    $self->log("Gene $geneIdentifier not found in DB");
  }
  return $gene->getGeneId();
}

sub getGeneIdFromSymbol {
  my ($self, $geneIdentifier) = @_;

  $self->log("Looking up $geneIdentifier") if $self->getArg('veryVerbose');

  my $ALIAS_LOOKUP = <<ALIAS_LOOKUP;
SELECT gene_id FROM NIAGADS.GeneAnnotation
WHERE annotation->>'prev_symbol' = '$geneIdentifier'
OR annotation->>'alias_symbol' ~ '^$geneIdentifier$|^$geneIdentifier\||\|$geneIdentifier$|\|$geneIdentifier\|';
ALIAS_LOOKUP

  my  $SYMBOL_LOOKUP = <<SYMBOL_LOOKUP;
SELECT gene_id FROM NIAGADS.GeneAnnotation
WHERE annotation->>'symbol' = '$geneIdentifier'
SYMBOL_LOOKUP

  my $qh = $self->getQueryHandle()->prepare($SYMBOL_LOOKUP);
  $qh->execute();
  my ($geneId) = $qh->fetchrow_array();
  if (!$geneId) {
    $qh = $self->getQueryHandle()->prepare($ALIAS_LOOKUP);
    $qh->execute();
    ($geneId) = $qh->fetchrow_array();
  }
  if (!$geneId) {
    $self->error("No symbol or alias for Gene: $geneIdentifier found in DB");
  }

  $qh->finish();
  return $geneId;
}


sub getOntologyTermId {
  my ($self, $value) = @_;

  my $ontologyTerm = GUS::Model::SRes::OntologyTerm
    ->new({source_id => $value});

  unless ($ontologyTerm->retrieveFromDB()) {
    $ontologyTerm = GUS::Model::SRes::OntologyTerm
      ->new({name => $value});
  }

  unless ($ontologyTerm->retrieveFromDB()) {
    $ontologyTerm = GUS::Model::SRes::OntologyTerm
      ->new({uri => $value});
  }

  $self->error("Term $value not found in SRes.OntologyTerm")
    unless ($ontologyTerm->retrieveFromDB());

  return $ontologyTerm->getOntologyTermId();

}


# ----------------------------------------------------------------------
sub undoTables {
  my ($self) = @_;

  my @tables = qw(Study.Characteristic Niagads.GeneTraitAssociation Study.StudyLink Study.ProtocolAppNode );
  return @tables;
}




1;
