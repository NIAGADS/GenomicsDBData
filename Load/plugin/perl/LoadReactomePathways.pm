package GenomicsDBData::Load::Plugin::LoadReactomePathways;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use warnings;

use JSON::XS;

use File::Map qw(map_file);

use Data::Dumper;
use GUS::PluginMgr::Plugin;

use GUS::Model::SRes::Pathway;
use GUS::Model::SRes::PathwayNode;
use GUS::Model::DoTS::Gene;


my $PATHWAYS = {};

# ----------------------------------------------------------
# Load Arguments
# ----------------------------------------------------------

sub getArgsDeclaration {
  my $argsDeclaration  =
    [   
     stringArg({ name => 'file',
                 descr => 'file name',
                 constraintFunc=> undef,
                 reqd  => 1,
                 isList => 0,
                 mustExist => 1,
                }),

     stringArg({ name => 'species',
                 descr => 'species name',
                 constraintFunc=> undef,
                 reqd  => 1,
                 isList => 0
                }),

   
     stringArg({ name  => 'extDbRlsSpec',
                  descr => "The ExternalDBRelease specifier for the pathway database. Must be in the format 'name|version', where the name must match an name in SRes::ExternalDatabase and the version must match an associated version in SRes::ExternalDatabaseRelease.",
                  constraintFunc => undef,
                  reqd           => 1,
                  isList         => 0 })

    ];

  return $argsDeclaration;
}

# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
  my $purposeBrief = "Inserts pathway-gene relationships from Rectome.";

  my $purpose =  "Inserts pathway-gene relationships from Rectome.";

  my $tablesAffected = [['SRes.Pathway', 'One Row to identify each pathway'], ['SRes.PathwayNode', 'One row to store network and graphical inforamtion about a pathway node (genes only)'],];

  my $tablesDependedOn = [['Core.TableInfo',  'To store a reference to tables that have Node records (ex. EC Numbers, Coumpound IDs']];

  my $howToRestart = "No restart";

  my $failureCases = "";

  my $notes = <<NOTES;
Written by Emily Greenfest-Allen
Copyright Trustees of University of Pennsylvania 2019. 
NOTES

  my $documentation = {purpose=>$purpose, purposeBrief=>$purposeBrief, tablesAffected=>$tablesAffected, tablesDependedOn=>$tablesDependedOn, howToRestart=>$howToRestart, failureCases=>$failureCases,notes=>$notes};

  return $documentation;
}


# ----------------------------------------------------------------------
# create and initalize new plugin instance.
# ----------------------------------------------------------------------

sub new {
  my $class = shift;
  my $self = {};
  bless($self, $class);

  my $documentation = &getDocumentation();

  my $args = &getArgsDeclaration();

  my $configuration = { requiredDbVersion => 4.0,
                        cvsRevision => '$Revision: 3 $',
                        name => ref($self),
                        argsDeclaration => $args,
                        documentation => $documentation
                      };

  $self->initialize($configuration);

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

  $self->{ext_db_rls_id} = $self->getExtDbRlsId($self->getArg('extDbRlsSpec'));

  $self->loadPathways();

}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub loadPathways {
  my ($self) = @_;

  my $filename = $self->getArg('file');
  my $species = $self->getArg('species');

  my $geneTableId = $self->className2TableId("DoTS::Gene");
  my $nodeTypeId = $self->getOntologyTermId('Sequence Ontology', 'SO:0000704'); # gene; ideally should look this up or specify as param

  $self->log("Processing: $filename");

  map_file my $fileMap, $filename || $self->error("Unable to map file: $filename");
  open(my $fh, '<', \$fileMap) || $self->error("Unable to create filehandle from file map.");

  my $count = 0;
  my $lineCount = 0;
  while (<$fh>) {
    $self->log("Read $lineCount lines") if (++$lineCount % 25000 == 0);

    next if !(m/\Q$species/g); #\Q = quotemeta
    chomp;
    my ($ensemblId,  $pathwayId, $pathwayUrl, $pathwayName, $evidenceCode, $species) = split /\t/;

    if (!exists $PATHWAYS->{$pathwayId}) {
      # $self->log("Found new pathway: $pathwayId - $pathwayName");
      my $pathway = GUS::Model::SRes::Pathway
	->new({name => $pathwayName,
	       source_id => $pathwayId,
	       external_database_release_id => $self->{ext_db_rls_id}
	      });
      
      $pathway->submit() unless $pathway->retrieveFromDB();
      $PATHWAYS->{$pathwayId} = $pathway->getPathwayId();
    }
    
    my $gene = $self->getGene($ensemblId);
    if (!$gene) {
      $self->log("Gene $ensemblId not found in DB. Skipping.");
    }
    else {
      my $pathwayNode = GUS::Model::SRes::PathwayNode 
	->new({display_label => $gene->getGeneSymbol(),
	       pathway_node_type_id => $nodeTypeId,
	       table_id => $geneTableId,
	       row_id => $gene->getGeneId,
	       pathway_id => $PATHWAYS->{$pathwayId},
	       evidence_code => $evidenceCode
	      });

      $pathwayNode->submit() unless $pathwayNode->retrieveFromDB();
      
      if (++$count % 10000 == 0) {
	$self->log("Inserted $count PathwayNodes");
	$self->undefPointerCache();
      }
    }

  }

  $fh->close();

}


# ----------------------------------------------------------------------
# supporting methods
# ----------------------------------------------------------------------

sub getGene {
  my ($self, $ensemblId) = @_;

  my $gene = GUS::Model::DoTS::Gene
    ->new({source_id => $ensemblId});
  
  return undef 
    unless $gene->retrieveFromDB();

  return $gene;
}

sub undoTables {
  my ($self) = @_;

  return (

	  'SRes.PathwayNode',
	  'SRes.Pathway'
	 );
}



1;
