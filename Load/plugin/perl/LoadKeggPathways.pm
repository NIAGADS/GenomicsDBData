package NiagadsData::Load::Plugin::LoadKeggPathways;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use warnings;

use JSON::XS;

use File::Map qw(map_file);

use Data::Dumper;
use GUS::PluginMgr::Plugin;
use NiagadsData::Load::KEGGReader;
use GUS::Model::SRes::Pathway;
use GUS::Model::SRes::PathwayNode;
use GUS::Model::DoTS::Gene;
use GUS::Model::SRes::Disease;
use GUS::Model::SRes::PathwayDisease;

# ----------------------------------------------------------
# Load Arguments
# ----------------------------------------------------------

sub getArgsDeclaration {
  my $argsDeclaration  =
    [   
     stringArg({ name => 'pathwaysFileDir',
                 descr => 'full path to xml files',
                 constraintFunc=> undef,
                 reqd  => 1,
                 isList => 0,
                 mustExist => 1,
                }),

     stringArg({ name => 'diseaseMapFile',
                 descr => 'full path to KEGG disease json',
                 constraintFunc=> undef,
                 reqd  => 0,
                 isList => 0,
                 mustExist => 1,
                }),

     booleanArg({ name => 'loadDiseasesOnly',
                 descr => 'only load diseases',
                 constraintFunc=> undef,
                 reqd  => 0,
                 isList => 0,
                 mustExist => 1,
                }),

     enumArg({ name           => 'format',
               descr          => 'The file format for pathways (KEGG, MPMP, Biopax, Other); currently only handles KEGG',
               constraintFunc => undef,
               reqd           => 1,
               isList         => 0,
               enum           => 'KEGG, MPMP, Biopax, Other'
             }),
     stringArg({ name  => 'extDbRlsSpec',
                  descr => "The ExternalDBRelease specifier for the pathway database. Must be in the format 'name|version', where the name must match an name in SRes::ExternalDatabase and the version must match an associated version in SRes::ExternalDatabaseRelease.",
                  constraintFunc => undef,
                  reqd           => 1,
                  isList         => 0 }),

    ];

  return $argsDeclaration;
}

# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
  my $purposeBrief = "Inserts pathways from a set of KGML or XGMML (MPMP) files into Network schema.";

  my $purpose =  "Inserts pathways from a set of KGML or XGMML (MPMP) files into Network schema.";

  my $tablesAffected = [['SRes.Pathway', 'One Row to identify each pathway'], ['SRes.PathwayNode', 'One row to store network and graphical inforamtion about a pathway node (genes only)'],['SRes.Disease', 'one row per KEGG disease'], ['SRes.PathwayDisease', 'one row per pathway-disease link']];

  my $tablesDependedOn = [['Core.TableInfo',  'To store a reference to tables that have Node records (ex. EC Numbers, Coumpound IDs'], ['DoTS.Gene', 'To look up row_id for referenced genes']];

  my $howToRestart = "No restart";

  my $failureCases = "";

  my $notes = "";

  my $documentation = {purpose=>$purpose, purposeBrief=>$purposeBrief, tablesAffected=>$tablesAffected, tablesDependedOn=>$tablesDependedOn, howToRestart=>$howToRestart, failureCases=>$failureCases,notes=>$notes};

  return $documentation;
}

#--------------------------------------------------------------------------------

sub new {
  my $class = shift;
  my $self = {};
  bless($self, $class);

  my $documentation = &getDocumentation();

  my $args = &getArgsDeclaration();

  my $configuration = { requiredDbVersion => 4.0,
                        cvsRevision => '$Revision: 19434 $',
                        name => ref($self),
                        argsDeclaration => $args,
                        documentation => $documentation
                      };

  $self->initialize($configuration);

  return $self;
}


#######################################################################
# Main Routine
#######################################################################

sub run {
  my ($self) = shift;

  my $inputFileDir = $self->getArg('pathwaysFileDir');
  die "$inputFileDir directory does not exist\n" if !(-d $inputFileDir); 

  my $pathwayFormat = $self->getArg('format');
  my $extension = ($pathwayFormat eq 'KEGG') ? 'kgml' : 'xml';

  my @pathwayFiles = <$inputFileDir/*.$extension>;
  die "No $extension files found in the directory $inputFileDir\n" if not @pathwayFiles;

  $self->{extDbRlsId} = $self->getExtDbRlsId($self->getArg('extDbRlsSpec'));
  
  if (!$self->getArg('loadDiseasesOnly')) {
    my $count = 0;
    foreach my $p (@pathwayFiles) {
      $self->loadPathway($p);
      $count++;
    }
    $self->log("Processed $count pathway files");
  }

  $self->loadDiseasePathways()  if ($self->getArg('diseaseMapFile'));
}


sub loadDiseasePathways {
  my ($self) = @_;
  my $file = $self->getArg('diseaseMapFile');

  map_file my $fileMap, $file;

  my $json = JSON::XS->new;
  my $listing = $json->decode($fileMap) || $self->error("Error decoding JSON: $fileMap");

  my @categories = @{$listing->{children}};
  foreach my $cat (@categories) {
    my $categoryName = $cat->{name};
    my @subcategories = @{$cat->{children}};
    foreach my $subCat (@subcategories) {
      my $subCategoryName = $subCat->{name};
      my @diseases = @{$subCat->{children}};
      foreach my $ds (@diseases) {
	my $name = $ds->{name};
	$self->log("Parsing: $categoryName - $subCategoryName - $name");
	next unless ($name =~ m/PATH/); # skip if no pathways

	my ($sourceId, $lname) = split '  ', $name;
	my ($dsName, $pathways) = split ' \[', $lname;
	$pathways =~ s/PATH\://;
	$pathways =~ s/\]//;
	$self->log("Found disease with pathways: $dsName - $sourceId - $pathways");

	# load disease
	my $diseaseObj = GUS::Model::SRes::Disease
	  ->new({name =>  $dsName,
		 source_id => $sourceId,
		 external_database_release_id => $self->{extDbRlsId},
		 category => $categoryName,
		 subcategory => $subCategoryName});
	
	$diseaseObj->submit() unless ($diseaseObj->retrieveFromDB());

	# load pathway disease links

	my @pathwayIds = split ' ' , $pathways;
	foreach my $pId (@pathwayIds) {
	  $self->log("Linking $pId to $dsName");
	  my $pathwayObj = GUS::Model::SRes::Pathway
	    ->new({source_id => $pId});

	  
	    if ( $pathwayObj->retrieveFromDB()) {
	      my $pathwayDiseaseLink = GUS::Model::SRes::PathwayDisease
		->new({pathway_id => $pathwayObj->getPathwayId(),
		       disease_id => $diseaseObj->getDiseaseId()});
	      $pathwayDiseaseLink->submit() unless $pathwayDiseaseLink->retrieveFromDB();
	    }
	  else {
	    $self->log("Pathway: $pId not found in DB. SKIPPING.") ;
	  }   
	}
      }
    }
  }

}

sub loadPathway {
  my ($self, $pathwayFile) = @_;

  my $preader = NiagadsData::Load::KEGGReader->new($pathwayFile);
  my $pathwayObj = $preader->read();
  my $name = $pathwayObj->{NAME};
  my $sourceId = $pathwayObj->{SOURCE_ID};
  $self->log("Processing: $name ($sourceId)") if $self->getArg('veryVerbose');

  my $pathway = GUS::Model::SRes::Pathway->new({ name => $name,
						 external_database_release_id => $self->{extDbRlsId},
						 source_id => $sourceId,
						 url => $pathwayObj->{URL}
					       });
  
  my $nodes = $pathwayObj->{NODES};
  my $geneTableId = $self->className2TableId("DoTS::Gene");
  my $nodeTypeId = $self->getOntologyTermId('Sequence Ontology', 'SO:0000704'); # gene; ideally should look this up or specify as param

  foreach my $n (keys %$nodes) {
    my $nodeType = $nodes->{$n}->{TYPE};
    next if ($nodeType ne 'gene');
    
    my ($taxon, $entrezGeneId) = split /:/, $nodes->{$n}->{SOURCE_ID};
    my ($geneSymbol, $geneId) = $self->fetchGeneDetails($entrezGeneId);
    if (!$geneId) {
      $self->log("Unable to find GENE: $entrezGeneId in DB");
      next;
    }

    my $pathwayNode = GUS::Model::SRes::PathwayNode->new({display_label => $geneSymbol,
							  table_id => $geneTableId,
							  row_id => $geneId,
							  pathway_node_type_id => $nodeTypeId});

    $pathwayNode->setParent($pathway);
    #     $self->log(Dumper($nodes->{$n})) if ($nodes->{$n}->{TYPE} eq 'gene');    
  }

  $pathway->submit() if (!$pathway->retrieveFromDB());
  $self->undefPointerCache();

}#subroutine


# map entrez to ensembl
sub fetchGeneDetails {
  my ($self, $entrezGeneId) = @_;

  my $SQL=<<SQL;
SELECT gene_id, gene_symbol
FROM CBIL.GeneAttributes
WHERE annotation->>'entrez_id' = ?
SQL

  my $qh = $self->getQueryHandle()->prepare($SQL)
    or $self->error(DBI::errstr);

  $qh->execute($entrezGeneId) or $self->error(DBI::errstr);
  my ($geneId, $geneSymbol) = $qh->fetchrow_array();

  return $geneSymbol, $geneId
}


sub undoTables {
  my ($self) = @_;

  return (
	  'SRes.PathwayDisease',
	  'SRes.Disease',
	  'SRes.PathwayNode',
	  'SRes.Pathway'
	 );
}


1;
