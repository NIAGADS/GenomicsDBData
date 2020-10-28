package GenomicsDBData::Load::KEGGReader;
use base qw(GUS::Supported::MetabolicPathwayReader);

use strict;

use XML::LibXML;
use File::Basename;
use File::Map qw(map_file);

sub setPathwayHash {
  my ($self, $pathwayHash) = @_;

  $self->{_pathway_hash} = $pathwayHash;
}

sub getPathwayHash {
  my ($self) = @_;
  return $self->{_pathway_hash};
}

# -------------------------------------------------
# Subroutine: read
# Description: @override parses a kegg xml file

# Outputs: a hash data structure that stores
#          the kegg entries, relations and reactions
# -------------------------------------------------

sub read {
  my ($self) = @_;

  my ($pathway, $nodeEntryMapping);

  my $filename = $self->getFile();

  print STDERR "Reading file $filename...\n";

  if (!$filename) {
   die "Error: KGML file not found!";
  }

  # make some fixes: remove w/SYSTEM doctype
  map_file my $fileMap, $filename;
  my $correctedFileStr = $fileMap;
  $correctedFileStr =~ s/<!DOCTYPE pathway SYSTEM "http:\/\/www.kegg.jp\/kegg\/xml\/KGML_v0\.7\.2_\.dtd">//;

  #my $parser = new XML::LibXML;
  #my $doc = $parser->parse_string($correctedFileStr);
  my $doc = XML::LibXML->load_xml(string => $correctedFileStr);
  my $rid = 0;



  # get pathway name and id info
  # ===================================
  my @nodes = $doc->findnodes('/pathway');

  $pathway->{SOURCE_ID} = $nodes[0]->getAttribute('name');
  $pathway->{SOURCE_ID} =~ s/path://g;

  $pathway->{NAME} = $nodes[0]->getAttribute('title');
  $pathway->{URI} = $nodes[0]->getAttribute('link');
  $pathway->{IMAGE_FILE} = basename($nodes[0]->getAttribute('image'));
  $pathway->{NCOMPLEXES} = 0;
  

  # get "entries"
  # ===================================
  @nodes = $doc->findnodes('/pathway/entry');
  foreach my $entry (@nodes) {
    my $type = $entry->getAttribute('type');
    my $uniqId = $entry->getAttribute('id');
 
    my $enzymeNames = $entry->getAttribute('name');
    $enzymeNames =~ s/gl:|ec:|cpd:|dr:|path://g;
    $nodeEntryMapping->{$entry->getAttribute('id')} = $enzymeNames;

    my @nodeIds = split(/ /,$enzymeNames);

    foreach my $id (@nodeIds) {
      # Here $id needs to include X and Y positions (be unique)
      $pathway->{NODES}->{$id}->{TYPE} = $type;
      $pathway->{NODES}->{$id}->{SOURCE_ID} = $id;
      
      # my @graphicsNode = $entry->getChildrenByTagName('graphics');

      # foreach my $gn (@graphicsNode) {
      # 	my $gnName = $gn->getAttribute('name');
      # 	my ($xPosition, $yPosition) = ($gn->getAttribute('x'), $gn->getAttribute('y'));
      # 	my $verboseName = $id . "_X:" . $xPosition . "_Y:" . $yPosition;
	
      # 	$pathway->{NODES}->{$uniqId}->{SOURCE_ID} = $id;
      # 	$pathway->{NODES}->{$uniqId}->{UNIQ_ID} = $uniqId;
      # 	$pathway->{NODES}->{$uniqId}->{VERBOSE_NAME} = $verboseName;
      # 	$pathway->{NODES}->{$uniqId}->{TYPE} = $type;
      # 	$pathway->{NODES}->{$uniqId}->{ENTRY_ID} = $entry->getAttribute('id');
      # 	$pathway->{NODES}->{$uniqId}->{REACTION} = $entry->getAttribute('reaction');
      # 	$pathway->{NODES}->{$uniqId}->{LINK} = $entry->getAttribute('link');
	
      # 	$pathway->{NODES}->{$uniqId}->{GRAPHICS}->{NAME} = $gn->getAttribute('name');
      # 	$pathway->{NODES}->{$uniqId}->{GRAPHICS}->{FGCOLOR} = $gn->getAttribute('fgcolor');
      # 	$pathway->{NODES}->{$uniqId}->{GRAPHICS}->{BGCOLOR} = $gn->getAttribute('bgcolor');
      # 	$pathway->{NODES}->{$uniqId}->{GRAPHICS}->{TYPE} = $gn->getAttribute('type');
      # 	$pathway->{NODES}->{$uniqId}->{GRAPHICS}->{X} = $gn->getAttribute('x');
      # 	$pathway->{NODES}->{$uniqId}->{GRAPHICS}->{Y} = $gn->getAttribute('y');
      # 	$pathway->{NODES}->{$uniqId}->{GRAPHICS}->{WIDTH} = $gn->getAttribute('width');
      # 	$pathway->{NODES}->{$uniqId}->{GRAPHICS}->{HEIGHT} = $gn->getAttribute('height');
      # 	$pathway->{NODES}->{$uniqId}->{GRAPHICS}->{LINECOORDS} = $gn->getAttribute('coords');
      # }

    
    }  # end entries
  }
 
  # read in the relations
  # ===================================

  my @relations = $doc->findnodes('/pathway/relation');

  foreach my $relation (@relations) {
    my $type = $relation->getAttribute('type');
 
    my $rtype = "Protein-Protein"; # if type = PPrel
    $rtype = "Enzyme-Enzyme" if $type eq "ECrel";
    $rtype = "Gene Expression" if $type eq "GErel";
    $rtype = "Protein-Compound" if $type eq "PCrel";
    $rtype = "Maplink" if $type eq "maplink";

    my $entryId = $relation->getAttribute('entry1');
    my $associatedEntryId =  $relation->getAttribute('entry2');
    my $entry = $pathway->{ENTRY}->{$entryId};
    my $associatedEntry = $pathway->{ENTRY}->{$associatedEntryId};
    my @entries = ($entryId);
    my @associatedEntries = ($associatedEntryId);

    my @subtype = $relation->getChildrenByTagName('subtype');  
 
    foreach my $e (@entries) {
      foreach my $a (@associatedEntries) {
	if (!defined $subtype[0]) {
	  $pathway->{RELATIONS}->{$rtype}->{$rid}->{ENTRY} = $e;
	  $pathway->{RELATIONS}->{$rtype}->{$rid}->{ASSOCIATED_ENTRY} = $a;
	  $pathway->{RELATIONS}->{$rtype}->{$rid}->{INTERACTION_TYPE} = $rtype;
	  $rid++;
	}
	else {
	  foreach my $st (@subtype) {
	    $pathway->{RELATIONS}->{$rtype}->{$rid}->{ENTRY} = $e;
	    $pathway->{RELATIONS}->{$rtype}->{$rid}->{ASSOCIATED_ENTRY} = $a;
	    $pathway->{RELATIONS}->{$rtype}->{$rid}->{INTERACTION_TYPE} = $rtype;
	    $pathway->{RELATIONS}->{$rtype}->{$rid}->{INTERACTION_ENTITY} = $st->getAttribute('name');
	    $pathway->{RELATIONS}->{$rtype}->{$rid}->{INTERACTION_ENTITY_ENTRY} = $st->getAttribute('value');
	    $rid++;
	  }
	}
     }
    }
 
 
  } #end relations

  # read in the reactions
  # ===================================

 my @reactions = $doc->findnodes('/pathway/reaction');

  foreach my $reaction (@reactions) {

      #a complex reaction key to uniquely identify an 'Interaction'. To be noted that a single reaction can have multiple interactions
      #like substrateA <-> Enzyme1 <-> ProductA and SubstrateA <->EnzymeB <-> ProductA
      #which is a single reaction in KEGG but two separate network interactions

    my $reactionId = $reaction->getAttribute('id');
      my $verboseName = $reactionId."_".$reaction->getAttribute('name');
      my $rnName = $reaction->getAttribute('name');
      $rnName =~ s/rn://g;

      my @enzymes = split(/ /,$reaction->getAttribute('id'));

      my (@substrates, @products);

      my @substrate = $reaction->getChildrenByTagName('substrate');
      foreach my $sbstr (@substrate) {
        my $substrId = $sbstr->getAttribute('id');
        my $name = $sbstr->getAttribute('name');
        $name =~ s/gl:|ec:|cpd:|dr://g;
        push (@substrates,({ENTRY => $substrId, NAME => $name}));
      } 

      my @product = $reaction->getChildrenByTagName('product');
      foreach my $prd (@product) {
        my $prdId = $prd->getAttribute('id');
        my $name = $prd->getAttribute('name');
        $name =~ s/gl:|ec:|cpd:|dr://g;
        push (@products, ({ENTRY => $prdId, NAME => $name}));
      }

      $pathway->{REACTIONS}->{$reactionId} = {PRODUCTS => [@products],
                                                SUBSTRATES => [@substrates],
                                                ENZYMES => [@enzymes],
                                                SOURCE_ID => $rnName,
                                                VERBOSE_NAME => $verboseName,
                                                TYPE => $reaction->getAttribute('type')};
  }



  foreach my $relation (values %{$pathway->{RELATIONS}->{'Enzyme-Enzyme'}}) {

    unless($relation->{INTERACTION_ENTITY} eq 'compound') {
      print  "WARN:  Only know about Compound->Enzyme Relations Here. Found $relation->{INTERACTION_ENTITY}\n" ;
      next;
    }

    my $c = $relation->{INTERACTION_ENTITY_ENTRY};
    my $e1 = $relation->{ENTRY};
    my $e2 = $relation->{ASSOCIATED_ENTRY};

    push @{$pathway->{EDGES}->{$c}}, $e1 unless(&alreadyExistsInArray($e1, $pathway->{EDGES}->{$c}));
    push @{$pathway->{EDGES}->{$c}}, $e2 unless(&alreadyExistsInArray($e2, $pathway->{EDGES}->{$c}));
  }


  foreach my $relation (values %{$pathway->{RELATIONS}->{Maplink}}) {
    unless($relation->{INTERACTION_ENTITY} eq 'compound') {
      print "WARN: Only know about Compound->Map Relations Here.  Found $relation->{INTERACTION_ENTITY}\n" ;
      next;
    }
    my $c = $relation->{INTERACTION_ENTITY_ENTRY};
    my $e1 = $relation->{ENTRY};
    my $e2 = $relation->{ASSOCIATED_ENTRY};

    push @{$pathway->{EDGES}->{$c}}, $e1 unless(&alreadyExistsInArray($e1, $pathway->{EDGES}->{$c}));
    push @{$pathway->{EDGES}->{$c}}, $e2 unless(&alreadyExistsInArray($e2, $pathway->{EDGES}->{$c}));
  }

  foreach my $reaction (values %{$pathway->{REACTIONS}}) {
    foreach my $enzymeId (@{$reaction->{ENZYMES}}) {

      foreach my $substrateHash(@{$reaction->{SUBSTRATES}}) {
        my $substrateId = $substrateHash->{ENTRY};
        push @{$pathway->{EDGES}->{$substrateId}}, $enzymeId unless(&alreadyExistsInArray($enzymeId, $pathway->{EDGES}->{$substrateId}));
      }

      foreach my $productHash (@{$reaction->{PRODUCTS}}) {
        my $productId = $productHash->{ENTRY};
        push @{$pathway->{EDGES}->{$productId}}, $enzymeId unless(&alreadyExistsInArray($enzymeId, $pathway->{EDGES}->{$productId}));
      }
    }
  }

  $self->setPathwayHash($pathway);
}


sub alreadyExistsInArray {
  my ($e, $ar) = @_;

  return 0 unless($ar);
  foreach(@$ar) {
    return 1 if($e == $_);
  }

  return 0;
}


1; 
