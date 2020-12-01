package GenomicsDBData::Load::Plugin::LoadGeneAssociationResult;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use warnings;

use Data::Dumper;
use GUS::PluginMgr::Plugin;

use JSON::XS;

use Package::Alias Utils => 'GenomicsDBData::Load::Utils';
use Package::Alias PluginUtils => 'GenomicsDBData::Load::PluginUtils';

use GUS::Model::Results::GeneAssociation;

use GUS::Model::DoTS::Gene;

# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
  my $argumentDeclaration  =
    [
     stringArg({name => 'file',
	      descr => 'file name',
	      constraintFunc=> undef,
	      reqd  => 1,
	      isList => 0,
	     }),
     stringArg({name => 'fileDir',
		descr => 'directory containing input file & to which output of plugin will be written',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0
	       }),
     stringArg({ name  => 'sourceId',
                 descr => "unique source_id associated with the Study.ProtocolAppNode for this annotation",
                 constraintFunc => undef,
                 reqd           => 1,
                 isList         => 0 
	       }),

     booleanArg({ name  => 'standardizeResultOnly',
		  descr => 'only generate standardized files for storage in the data repository; one p-values only; one complete, can be done along w/--loadResult',
		  constraintFunc => undef,
		  isList         => 0,
		  reqd => 0
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
		     cvsRevision => '$Revision: 8 $',
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

  my $skipLoad = $self->getArg('standardizeResultOnly');
  my $protocolAppNodeId = PluginUtils::getProtocolAppNodeId($self, $self->getArg('sourceId'));

  my $fileName = $self->getArg('fileDir') . '/' . $self->getArg('file');
  $self->log("Loading $fileName");
  open(my $fh, $fileName) || $self->error("Unable to open $fileName");

  my $path = PluginUtils::createDirectory($self, $self->getArg('fileDir'), "standardized");
  my $standardizedFileName = $path . "/" . $self->getArg('sourceId') . ".txt";
  open(my $sfh, '>', $standardizedFileName) || $self->rror("Unable top open $standardizedFileName for writing.");
  $sfh->autoflush(1);

  my $header = <$fh>;
  chomp($header);
  my @fields = split /,/,  $header;
  my %columns = map { $fields[$_] => $_ } 0..$#fields;

  print $sfh join("\t", @fields) . "\n";

  my $count = 0;
  my $missingGeneCount = 0;
  while (my $line = <$fh>) {
    chomp($line);
    $self->log($line) if $self->getArg('veryVerbose');
    my @values = split /,/, $line;

    print $sfh join("\t", @values) . "\n";
 
    if (!$skipLoad) {
      my $geneId = $values[$columns{gene}];
      if (!$geneId) {
	$missingGeneCount++;
	$self->log("Missing gene on line ++$count");
	next;
      }
      my $fcMAC = $values[$columns{flag_cMAC}];
      my $fErr = $values[$columns{flag_seqMetaErrflag}];

      my $caveat = {
		    flag_cMAC => $fcMAC * 1.0, # so that it treats it as a num in the json
		    flag_seqMetaErr => $fErr * 1.0
		   };

      my $association = GUS::Model::Results::GeneAssociation
	->new({protocol_app_node_id => $protocolAppNodeId,
	       gene_id => $self->getGeneId($geneId),
	       p_value => $values[$columns{P}],
	       rho => $values[$columns{rho}],
	       cumulative_maf => $values[$columns{cmaf}],
	       cumulative_mac => $values[$columns{cMAC}],
	       num_snps => $values[$columns{nsnps}],
	       caveat => Utils::to_json($caveat)
	      });

      $association->submit(); # unless $association->retrieveFromDB();
    }

    if (++$count % 5000 == 0) {
      if (!$skipLoad) {
	$self->log("LOADED: $count records.");
	$self->undefPointerCache();
      }
      else {
	$self->log("Read: $count lines.");
      }
    }
  }

  $fh->close();
  $sfh->close();
  $self->log("DONE: Processed $count records.");
  $self->log("WARNING: Found $missingGeneCount missing genes");
}

sub getGeneId {
  my ($self, $sourceId) = @_;
  my $gene = GUS::Model::DoTS::Gene
    ->new({source_id => $sourceId});

  $self->error("Gene $sourceId not found in DB") 
    unless $gene->retrieveFromDB();
  return $gene->getGeneId();
}


# ----------------------------------------------------------------------
sub undoTables {
  my ($self) = @_;

  my @tables = qw(Results.GeneAssociation);
  return @tables;
}




1;
