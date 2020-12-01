package GenomicsDBData::Load::Plugin::LoadGeneAssociationResult;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use warnings;

use Data::Dumper;
use GUS::PluginMgr::Plugin;

use JSON::XS;

use Package::Alias Utils => 'GenomicsDBData::Load::Utils';
use Package::Alias PluginUtils => 'GenomicsDBData::Load::PluginUtils';

use GUS::Model::NIAGADS::GeneAssociation;

use GUS::Model::DoTS::Gene;

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
     stringArg({ name  => 'sourceId',
                 descr => "unique source_id associated with the Study.ProtocolAppNode for this annotation",
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

  my $purpose = 'This plugin loads a gene-trait association from pipe-delimited data and links to  protocol application node result';

  my $tablesAffected = [  ['Results.GeneAssociation', 'enters one row per result characteristic']];

  my $tablesDependedOn = [ ['DoTS.Gene', 'look up genes'], ['Study::ProtocolAppNode', 'lookup protocol app node'],];

  my $howToRestart = '';

  my $failureCases = '';

  my $notes = <<NOTES;
--------------------------------
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

  $self->loadGeneAssociation();

}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------


sub loadGeneAssociation {
  my ($self) = @_;

  my $protocolAppNodeId = PluginUtils::getProtocolAppNodeId($self, $self->getArg('sourceId'));
  my $fileName = $self->getArg('file');
  $self->log("Loading $fileName");
  open(my $fh, $fileName) || $self->error("Unable to open $fileName");

  my $header = <$fh>;
  chomp($header);
  my @fields = split /,/,  $header;
  my %columns = map { $fields[$_] => $_ } 0..$#fields;


#gene,cmaf,cMAC,nsnps,P,rho,flag_cMAC,flag_seqMetaErrflag
#ENSG00000148584,0.0188477238890432,394,50,0.416115696635412,1,0,0

  my $count = 0;
  while (my $line = <$fh>) {
    chomp($line);
    my @values = split /\|/, $line;
    my $caveat = {
		  flag_cMAC => $values[$columns{flag_cMAC}],
		  flag_seqMetaErr => $values[$columns{flag_seqMetaErrflag}]
		 };

    my $association = GUS::Model::NIAGADS::GeneAssociation
      ->new({protocol_app_node_id => $protocolAppNodeId,
	     gene_id => $self->getGeneId($values[$columns{gene}]),
	     p_value => $values[$columns{P}],
	     rho => $values[$columns{rho}],
	     cumulative_maf => $values[$columns{cmaf}],
	     cumulative_mac => $values[$columns{cMAC}],
	     num_snps => $values[$columns{nsnps}],
	     caveat => Utils::to_json($caveat)
	    });

    $association->submit(); # unless $association->retrieveFromDB();
    if (++$count % 10000 == 0) {
      $self->log("LOADED: $count records.");
      $self->undefPointerCache();
    }
  }

  $fh->close();
  $self->log("DONE: Loaded $count records.");
}

sub getGeneId {
  my ($self, $sourceId) = @_;
  my $gene = GUS::Model::DoTS::Gene
    ->new({source_id => $sourceId});

  $self->error("Gene $sourceId not found in DB") 
    unless $gene->retrieveFromDB();
  return $gene->geneId();
}


# ----------------------------------------------------------------------
sub undoTables {
  my ($self) = @_;

  my @tables = qw(Results.GeneAssociation);
  return @tables;
}




1;
