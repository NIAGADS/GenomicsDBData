## LoadSeqVariationResult.pm
## $Id: LoadSeqVariationResult.pm $
##

package NiagadsData::Load::Plugin::LoadSeqVariationResult;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use GUS::PluginMgr::Plugin;
use Data::Dumper;
use Scalar::Util qw(looks_like_number);
use POSIX qw(strftime);
use JSON;

use GUS::Model::DoTS::SnpFeature;
use GUS::Model::DoTS::GeneFeature;
use GUS::Model::DoTS::ExternalNASequence;

use GUS::Model::Results::SeqVariation;

use GUS::Model::SRes::OntologyTerm;

use GUS::Model::Study::ProtocolAppNode;
use GUS::Model::Study::Study;
use GUS::Model::Study::StudyLink;
use GUS::Model::Study::Characteristic;

my %seqHash;
my %seqIdHash;
my ($currentSequenceId, $currentSequence);

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

my $SEQUENCE_SQL= <<SEQUENCE_SQL;
SELECT substring(sequence from ? - 25 for 25) AS upstream_seq
, substring(sequence from ? + 1 for 25) AS downstream_seq
FROM DoTS.ExternalNASequence
WHERE na_sequence_id = ?
SEQUENCE_SQL

my $CHR_SEQUENCE_SQL= <<CHR_SEQUENCE_SQL;
SELECT sequence FROM DoTS.ExternalNASequence
WHERE na_sequence_id = ?
CHR_SEQUENCE_SQL


my $NA_FEATURE_SQL= <<NA_SQL;
SELECT na_feature_id, primary_key FROM DoTS.SnpFeature
WHERE variant_id IN (?)
NA_SQL

my $NA_FEATURE_POSITION_SQL= <<NA_POS_SQL;
SELECT na_feature_id, primary_key FROM DoTS.SnpFeature
WHERE chromosome = ? 
AND ((position_start = vcf_position AND position_start = ?)
OR
((position_start != vcf_position OR vcf_position IS NULL) AND vcf_position = ?))
NA_POS_SQL

my $NA_FEATURE_POSITION_REF_SQL = $NA_FEATURE_POSITION_SQL; # further modified in run


my $NA_FEATURE_REFSNP_SQL= <<NA_RS_SQL;
SELECT na_feature_id, primary_key
FROM dots.snpfeature WHERE source_id = ?
AND name != 'dbSNP_merge'
UNION
SELECT p.na_feature_id, p.primary_key
FROM DoTS.SnpFeature c, DoTS.SnpFeature p
WHERE c.source_id = ?
AND c.parent_id = p.na_feature_id
NA_RS_SQL


my $varInsertCount = 0;

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

     stringArg({ name  => 'characteristics',
                 descr => "json string of qualifier:value pairs for characteristics",
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),

     stringArg({ name  => 'extDbRlsSpec',
                 descr => "The ExternalDBRelease specifier for the VEP analysis. Must be in the format 'name|version', where the name must match a name in SRes::ExternalDatabase and the version must match an associated version in SRes::ExternalDatabaseRelease.",
                 constraintFunc => undef,
                 reqd           => 1,
                 isList         => 0 
	       }),

     stringArg({ name  => 'soExtDbRlsSpec',
                 descr => "The ExternalDBRelease specifier for the sequence ontology; required if sequence_ontology_id fields is to be populationed. Must be in the format 'name|version', where the name must match a name in SRes::ExternalDatabase and the version must match an associated version in SRes::ExternalDatabaseRelease.",
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

     stringArg({ name  => 'variantSource',
                 descr => "in case new variant needs to be created; one of dbSNP, ADSP_WES, ADSP_WGS, ADSP_INDEL, NIAGADS",
                 constraintFunc => undef,
                 reqd           => 1,
                 isList         => 0 
	       }),

     stringArg({ name  => 'description',
                 descr => "description for the study.protocolappnode",
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

     booleanArg({ name  => 'checkAltVariantIds',
                 descr => "in case variant id does not map; check flipped alleles and reverse",
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),
     booleanArg({ name  => 'matchPosition',
                 descr => "in case variant id does not map; map to all variants at the position; only works for SNVs",
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),
     booleanArg({ name  => 'nonStandardAllelesMatchPosition',
		  descr => "in case variant id contains non-standard alleles (e.g., D, R, I) or is missing an allele, map to all variants at the position",
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),
     booleanArg({ name  => 'matchPositionAndRef',
                 descr => "in case variant id does not map; map to all variants at the position, with same ref allele; only works for SNVs",
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),
     booleanArg({ name  => 'useRefSnpId',
                 descr => "use ref snp id (dbSNP rs) instead of variant id to find dots.snpfeatures",
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),
     booleanArg({ name  => 'useNaFeatureId',
                 descr => "use na_feature_id if preprocessing involved mapping against db",
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),
     booleanArg({ name  => 'skipMissingVariants',
                 descr => "skips missing variants (if not specified, will create new SnpFeature entries)",
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),
     booleanArg({ name  => 'ignoreMergedSnps',
                 descr => "ignore merged snps when checking for prexisting variants",
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
  my $purposeBrief = 'Loads Results.SeqVariation';

  my $purpose = 'This plugin reads a csv load file with column names = fields in Results.SeqVariation and and inserts the contents into Results.SeqVariation';

  my $tablesAffected = [['Study::ProtocolAppNode', 'Enters a row for the analysis'], ['Results::SeqVariation', 'Enters one row for each annotation result'], ['DoTS::SnpFeature', 'Enters one row per new variant']];

  my $tablesDependedOn = [['DoTS::GeneFeature', 'looks up genes'], ['DoTS::SnpFeature', 'looks up SNP feature'], ['SRes::OntologyTerm', 'looks up ontology terms'], ['DoTS.ExternalNASequence', 'look up sequences']];

  my $howToRestart = '';

  my $failureCases = '';

  my $notes = <<NOTES;

Written by Emily Greenfest-Allen
Copyright Trustees of University of Pennsylvania 2016. 
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
		     cvsRevision => '$Revision: 19863 $',
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

  $self->{validate_id} = $self->getArg('nonStandardAllelesMatchPosition');

  $NA_FEATURE_SQL .= " AND name != 'dbSNP_merge'" if ($self->getArg('ignoreMergedSnps'));
  $NA_FEATURE_POSITION_SQL .= " AND name != 'dbSNP_merge'" if ($self->getArg('ignoreMergedSnps'));
  $NA_FEATURE_POSITION_REF_SQL .= " AND name != 'dbSNP_merge'" if ($self->getArg('ignoreMergedSnps'));

  if ($self->getArg('checkAltVariantIds')) {
    $NA_FEATURE_POSITION_REF_SQL .= " AND (ref_allele = ? OR alt_allele = ?)";
  }
  else {
    $NA_FEATURE_POSITION_REF_SQL .= " AND ref_allele = ?";
  }

  $self->{file} = 'results_seqvariation_' . $self->getArg('sourceId') . 'csv';

  $self->{extDbRlsId} = $self->getExtDbRlsId($self->getArg('extDbRlsSpec'));
  $self->{soExtDbRlsId} = $self->getExtDbRlsId($self->getArg('soExtDbRlsSpec'))
    if ($self->getArg('soExtDbRlsSpec'));
  $self->insertProtocolAppNode();
  $self->loadCharacteristics() if ($self->getArg('characteristics'));
  $self->insertStudyLink() if ($self->getArg('studySourceId'));
  $self->insertRecords('Results');

}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------


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


sub buildCopySQL {
  my ($self, $fields) = @_;

  $fields =~ s/variant_id/variant_primary_key/;


  my $prefix= <<PREFIX;
COPY Results.SeqVariation (
snp_na_feature_id,
protocol_app_node_id,
PREFIX

  if ($self->getArg('useNaFeatureId')) {
    $fields =~ s/na_feature_id/snp_na_feature_id/;
    $prefix = "COPY Results.SeqVariation (protocol_app_node_id,";
  }

  my $suffix = <<SUFFIX;
) FROM STDIN
WITH (DELIMITER '|', 
NULL 'NULL')
SUFFIX

  my $sql = $prefix . $fields . "," . $HOUSEKEEPING_FIELDS . $suffix;
  $self->log("COPY SQL: $sql");
  return $sql;
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
  $studyLink->submit();
}


sub buildHousekeeping {
  my ($self) = @_;

  my $algInvId = $self->getAlgInvocation()->getId();
  my $rowUserId = $self->getAlgInvocation()->getRowUserId();
  my $rowGroupId = $self->getAlgInvocation()->getRowGroupId();
  my $rowProjectId = $self->getAlgInvocation()->getRowProjectId();

  my $currentTime = getCurrentTime();

  my $housekeeping = join("|",
			  $currentTime,
			  1, 1, 1, 1, 1, 0, 
			  $rowUserId, $rowGroupId,
			  $rowProjectId, $algInvId);
  return $housekeeping;
}

sub insertProtocolAppNode() {
  my ($self) = @_;

  my $protocolAppNode = GUS::Model::Study::ProtocolAppNode
    ->new( {
	    name => $self->getArg('name'),
	    description => $self->getArg('description'),
	    external_database_release_id => $self->{extDbRlsId},
	    source_id => $self->getArg('sourceId'),
	    subtype_id => $self->getOntologyTermId($self->getArg('subtypeSourceRef')),
	    type_id => $self->getOntologyTermId($self->getArg('typeSourceRef'))
	   });
  $protocolAppNode->submit() unless ($protocolAppNode->retrieveFromDB());
  $self->{protocol_app_node_id} =  $protocolAppNode->getId();
}

sub insertRecords {
  my ($self, $recordType) = @_;

  my $fileName = $self->getArg('file');
  open(my $fh, $fileName) || $self->error("Unable to open $fileName");

  my $fields = <$fh>;
  chomp($fields);
  $fields =~ s/\|/,/g;

  my $sql = $self->buildCopySQL($fields);

  # return if (!$self->getArg('commit'));

  my $housekeeping = $self->buildHousekeeping();

  $self->log("Beginning COPY");

  my $dbh = $self->getDbHandle();
  $dbh->do($sql); # puts database in copy mode; no other trans until finished

  my $count = 0;

  while (my $fieldValues = <$fh>) {
    chomp($fieldValues);
    if ($self->getArg('useNaFeatureId')) {
	$fieldValues = join("|", $self->{protocol_app_node_id}, $fieldValues, $housekeeping) . "\n"; 
	$self->log($fieldValues) if ($self->getArg('veryVerbose'));
	
	$dbh->pg_putcopydata($fieldValues);
	unless (++$count % 50000) {
	  $self->log("Inserted $count $recordType records.");
	  $dbh->pg_putcopyend(); # end copy trans can no do other things
	  $self->getDbHandle()->commit(); # commit
	  $dbh->do($sql); # puts database in copy mode; no other trans until finished
	}
    }
    else {
      my ($variantId, @values) = split /\|/, $fieldValues;
      my ($standardId, $features, $pks) = $self->getVariantFeatures($variantId);
      
      # $self->log($fieldValues) if $self->getArg('veryVerbose');
      $self->log("Num features = " . @$features) if ($self->getArg('veryVerbose'));
      if (@$features == 0) {

	if ($self->getArg('skipMissingVariants')) {
	  $self->log("No entry in DoTS.SnpFeature found for $variantId.  Skipping");
	  next;
	}

	# don't insert variants missing alleles or with non-standard alleles
	if (!$standardId) {
	  $self->log("No positional matches in DoTS.SnpFeature found for $variantId.  Skipping");
	  next;
	}

	$self->log("Inserting new feature for variant $variantId.");
	if ($count > 0) {
	  $dbh->pg_putcopyend(); # end copy trans can no do other things
	  $self->getDbHandle()->commit(); # commit
	  $self->log("Pausing copy at $count commits");
	}
	# insert new feature
	my ($naFeatureId) = $self->insertSnpFeature($variantId);
	push(@$features, $naFeatureId);
	push(@$pks, $variantId);
	
	$dbh->do($sql) if ($count > 0);      # puts database in back into copy mode
      }
      
      foreach my $i (0 .. $#$features) {
	# 91648664|28|10:60494:A:G_rs568182971|3.499|CADD_phred|"2017-04-07 07:57:34"|1|1|1|1|1|0|2|2|2|392916\n
	$fieldValues = join("|", @$features[$i], $self->{protocol_app_node_id}, @$pks[$i], @values, $housekeeping) . "\n"; # drop variant_id
	$self->log($fieldValues) if ($self->getArg('veryVerbose'));
	
	$dbh->pg_putcopydata($fieldValues);
	unless (++$count % 50000) {
	  $self->log("Inserted $count $recordType records.");
	  $dbh->pg_putcopyend(); # end copy trans can no do other things
	  $self->getDbHandle()->commit(); # commit
	  $dbh->do($sql); # puts database in copy mode; no other trans until finished
	}
      }
      $self->undefPointerCache();
    }
  }

  $self->log("DONE: Inserted $varInsertCount new variant records");
  $self->log("DONE: Inserted $count $recordType records.");
  $dbh->pg_putcopyend(); # end copy trans can now do other things
  $self->getDbHandle()->commit(); # commit
  $fh->close();
}


sub reverseAllele {
  my ($a) = @_;
  return 'T' if ($a eq 'A');
  return 'A' if ($a eq 'T');
  return 'G' if ($a eq 'C');
  return 'C' if ($a eq 'G');
}


sub getVariantFeatureById {
  my ($self, @variants) = @_;

  my @features;
  my @pks;

  my $qh = $self->getQueryHandle()->prepare($NA_FEATURE_SQL);

  my $found = 0;
  foreach my $v (@variants) {
    $qh->execute($v);
    while (my ($naFeatureId, $primaryKey) = $qh->fetchrow_array()) {
      push(@features, $naFeatureId);
      push(@pks, $primaryKey);
      $found = 1;
    }
    last if ($found); # alt ids are prioritized
  }
  $qh->finish();

  return \@features, \@pks;
}


sub getVariantFeatureByRefSnp {
  my ($self, $refSnpId) = @_;

  my @features;
  my @pks;

  my $qh = $self->getQueryHandle()->prepare($NA_FEATURE_REFSNP_SQL);
  $qh->execute($refSnpId, $refSnpId);
  while (my ($naFeatureId, $primaryKey) = $qh->fetchrow_array()) {
    push(@features, $naFeatureId);
    push(@pks, $primaryKey);

  }

  $qh->finish();

  return \@features, \@pks;
}


sub getVariantFeaturesByPosition {
  my ($self, $chr, $pos) = @_;

  my @features;
  my @pks;

  my $qh = $self->getQueryHandle()->prepare($NA_FEATURE_POSITION_SQL);

  $qh->execute($chr, $pos, $pos);
  while (my ($naFeatureId, $primaryKey) = $qh->fetchrow_array()) {
    push(@features, $naFeatureId);
    push(@pks, $primaryKey);
  }

  $qh->finish();

  return \@features, \@pks;
}

sub getVariantFeaturesByPositionAndReference {
  my ($self, $chr, $pos, $ref) = @_;

  my @features;
  my @pks;

  my $qh = $self->getQueryHandle()->prepare($NA_FEATURE_POSITION_REF_SQL);

  if ($self->getArg('checkAltVariantIds')) {
    $qh->execute($chr, $pos, $pos, $ref, $ref);
  }
  else {
    $qh->execute($chr, $pos, $pos, $ref);
  }
  while (my ($naFeatureId, $primaryKey) = $qh->fetchrow_array()) {
    push(@features, $naFeatureId);
    push(@pks, $primaryKey);
  }

  $qh->finish();

  return \@features, \@pks;
}

sub hasStandardVariantId {
  my ($variantId) = @_;
  my ($chr, $pos, $ref, $alt) = split /:/, $variantId;

  # tr/ACGT//c counts number of characters that are not ACGT
  my $validRefAllele = (defined $ref and !($ref =~ tr/ACGT//c) and $ref ne '') ? 1 : 0;
  my $validAltAllele = (defined $alt and !($alt =~ tr/ACGT//c) and $alt ne '') ? 1 : 0;
  my $isStandard = ($validRefAllele and $validAltAllele) ? 1 : 0;

  return ($isStandard, $validRefAllele);
}


sub getVariantFeatures {
  my ($self, $variantId) = @_;
  $self->log("Processing $variantId") if $self->getArg('veryVerbose');
  my $features = undef;
  my $pks = undef;
  my $hasStandardId = 1;
  my $hasValidRefAllele = 1;

  if ($self->getArg('useRefSnpId')) {
    ($features, $pks) = $self->getVariantFeatureByRefSnp($variantId);
  }
  else {
    if ($self->{validate_id}) {
      my ($chr, $pos, $ref, $alt) = split /:/, $variantId;
      ($hasStandardId, $hasValidRefAllele)  = hasStandardVariantId($variantId);
      if (!$hasStandardId) {
	if ($hasValidRefAllele) {
	  $self->log("Non standard variant ID found: $variantId; mapping to all variants at location, conditioned on reference allele");
	  ($features, $pks) = $self->getVariantFeaturesByPositionAndReference('chr' . $chr, $pos, $ref);
	}
	else {
	  $self->log("Non standard variant ID found: $variantId; mapping to all variants at location");
	  ($features, $pks) = $self->getVariantFeaturesByPosition('chr' . $chr, $pos);
	}
      }
    }

    if ($hasStandardId) {
      ($features, $pks) = $self->getVariantFeatureById(($variantId)); 

      if (!@$features and $self->getArg('checkAltVariantIds')) {
	my @altVariantIds;
	my ($chr, $pos, $ref, $alt) = split /:/, $variantId;
	$self->log("Variant $variantId not found in DB; matching alternatives") if $self->getArg('veryVerbose');
	push(@altVariantIds, "$chr:$pos:$alt:$ref"); # flip allele
	if (length($ref) == 1 and length($alt) == 1) { # only look on reverse if SNV
	  push(@altVariantIds, "$chr:$pos:" . reverseAllele($ref) . ":" . reverseAllele($alt));
	  push(@altVariantIds, "$chr:$pos:" . reverseAllele($alt) . ":" . reverseAllele($ref));
	}
	($features, $pks) = $self->getVariantFeatureById((@altVariantIds));
      }
      
      if (!@$features and $self->getArg('matchPosition')) {
	my ($chr, $pos, $ref, $alt) = split /:/, $variantId;
	($features, $pks) = $self->getVariantFeaturesByPosition('chr' . $chr, $pos);
      }

      if (!@$features and $self->getArg('matchPositionAndRef')) {
	my ($chr, $pos, $ref, $alt) = split /:/, $variantId;
	($features, $pks) = $self->getVariantFeaturesByPositionAndReference('chr' . $chr, $pos, $ref);
      }
    }
  }
  return $hasStandardId, $features, $pks;
}

 
  sub flagNiagadsVariant {
    my ($self, $features) = @_;
    foreach my $naFeatureId (@$features) {
      my $snpFeature = GUS::Model::DoTS::SnpFeature
	->new({na_feature_id => $naFeatureId});
      $snpFeature->setIsNiagadsVariant(1);
      $snpFeature->submit();
    }
  }

  sub setVariantSource {
    my ($self) = @_;
    return 'ADSP' if ($self->getArg('variantSource') =~ /ADSP/);
    return $self->getArg('variantSource');
  }


  sub inferPositionEnd {
    my ($self, $pos, $ref, $alt) = @_;

    # $ref = substr $ref, 1; # remove first char
    my $rLength = length($ref);
    my $aLength = length($alt);
    
    my $positionEnd = $pos; # snv
    if ($rLength == $aLength) {
      return $pos + $rLength if ($rLength > 1); # mnv
      return $pos + 1; # snv
    }
  
    if ($rLength > $aLength) {
      return $pos + $rLength - 1; # deletion
    }

    return $pos+1 if ($rLength < $aLength);  # inesrtion/indel

    return $positionEnd;
  }

  sub inferVariantType {
    my ($self, $pos, $ref, $alt) = @_;

    # $ref = substr $ref, 1; # remove first char
    my $rLength = length($ref);
    my $aLength = length($alt);
    
    if ($rLength == $aLength) {
      return ('SNV', 'single-nucleotide variant') if ($rLength) == 1;
      return ('MNV', 'multi-nucleotide variant');
    }

    if ($rLength > $aLength) {
      return ('DEL', 'deletion');
    }
    else {
      return ('INS', 'insertion');
    }
  }

  sub insertSnpFeature {
    my ($self, $variantId, $infoMap) = @_;

    my ($chr, $pos, $ref, $alt) = split /:/, $variantId;
    my $naSequenceId = $self->getNaSequenceId("chr" . $chr);
    my $positionEnd = $self->inferPositionEnd($pos, $ref, $alt);
    my $snpFeature = GUS::Model::DoTS::SnpFeature
      ->new({primary_key => $variantId,
	     variant_id => $variantId,
	     ref_allele => $ref,
	     alt_allele => $alt,
	     na_sequence_id => $naSequenceId,
	     position_start => $pos,
	     position_end => $positionEnd,
	     chromosome => "chr" . $chr,
	     external_database_release_id => $self->{extDbRlsId},
	    });

    my $name = $self->setVariantSource();
    $snpFeature->setName($name);
    $snpFeature->setIsAdspVariant(1) if $name eq "ADSP";
    $snpFeature->setIsNiagadsVariant(1) if $name eq "NIAGADS";

    my ($vc, $variantClass) = $self->inferVariantType($pos, $ref, $alt);
    my $annotation = {SEQUENCE => $self->buildSequence($naSequenceId, $pos, $positionEnd),
		      UNIVARIATION => $self->buildUnivariation($ref, $alt), # TODO: modify for indels
		      VARIANT_CLASS => $variantClass,
		      VC => $vc
		     };
    $annotation->{ADSP_WGS} = 1 if ($self->getArg('variantSource') eq 'ADSP_WGS');
    $annotation->{ADSP_WES} = 1 if ($self->getArg('variantSource') eq 'ADSP_WES');
    $annotation->{ADSP_INDEL} = 1 if ($self->getArg('variantSource') eq 'ADSP_INDEL');

    my $annotation = to_json $annotation;
    $snpFeature->setAnnotation($annotation);

    $snpFeature->submit();

    $varInsertCount++;

    return $snpFeature->getNaFeatureId();
  }


  sub buildSequence {
    my ($self, $naSequenceId, $pos, $positionEnd) = @_;
    my $sequence = undef;

    my ($upstreamSeq, $downstreamSeq) = $self->getSequence($naSequenceId, $pos, $positionEnd);

    $sequence->{UPSTREAM} = $upstreamSeq;
    $sequence->{DOWNSTREAM} = $downstreamSeq;
    return $sequence;
  }

  sub getChrSequence {
    my ($self, $naSequenceId) = @_;
    unless ($seqHash{$naSequenceId}) {
      $self->log("Fetching Sequence for na_sequence_id = $naSequenceId");
      my $qh = $self->getQueryHandle()->prepare($CHR_SEQUENCE_SQL);
      $qh->execute($naSequenceId);
      $seqHash{$naSequenceId} = $qh->fetchrow_array();
      $qh->finish();
      $self->log("Done, fetched sequence of length:" . length($currentSequence));
    }
    # $currentSequenceId = $naSequenceId;
  }

  sub getSequence {
    my ($self, $naSequenceId, $pos, $positionEnd) = @_;

    $self->getChrSequence($naSequenceId); # if ($naSequenceId != $currentSequenceId);

    # VCF is one-based & sequence in database is one-based
    # perl array is zero-based
    # need to adjust variant position accordingly
    $pos = $pos - 1;

    my $downstreamSeq = substr($seqHash{$naSequenceId}, $positionEnd + 1, 25); # string, offset, #chars
    # catch anything too close to start of chr (not likely, but just in case)
    my $offset = $pos - 25;
    my $end = 25;
    if ($offset < 0) {
      $end = 25 - abs($offset);
      $offset = 0;
    }
    my $upstreamSeq = substr($seqHash{$naSequenceId}, $offset, $end);

    return $upstreamSeq, $downstreamSeq;
  }


  # getSequenceId
  #
  # find the na_sequence_id for the given chromosome name
  # save to hash to limit lookups
  sub getNaSequenceId {
    my ($self, $chromosome) = @_;

    unless ($seqIdHash{$chromosome}) {
      my $externalNASequence = GUS::Model::DoTS::ExternalNASequence
	->new( {"chromosome" => $chromosome} );

      $self->error("WARNING: Could not find ExternalNASequence for chromosome: " . $chromosome)
	if (!$externalNASequence->retrieveFromDB());

      $seqIdHash{$chromosome} = $externalNASequence->getId();
    }
    return $seqIdHash{$chromosome}
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


  sub getCurrentTime {
    return strftime '"%Y-%m-%d %H:%M:%S"', localtime;
  }

  sub buildUnivariation {
    my ($self, $ref, $alt) = @_;
  
    my @alleles = sort ($ref, $alt);
    return join('/', @alleles);
  }


  # ----------------------------------------------------------------------
  sub undoTables {
    my ($self) = @_;

    return ('Results.SeqVariation', 'Dots.SnpFeature', 'Study.StudyLink', 'Study.Characteristic', 'Study.ProtocolAppNode', 'Study.Study'); 
  }



  1;
