package GenomicsDBData::Load::VariantLoadUtils;
use Data::Dumper;
use GenomicsDBData::Load::Utils;
use GenomicsDBData::Load::PluginUtils;

my $HOUSEKEEPING_FIELDS = PluginUtils::getHouseKeepingSql();

my $COPY_SQL=<<SQL;
COPY NIAGADS.Variant (
record_primary_key,
bin_index,
ref_snp_id,
metaseq_id,
chromosome,
position,
ref_allele,
alt_allele,
location_start,
location_end,
display_allele,
variant_class_abbrev,
sequence_allele,
is_adsp_variant,
annotation,
$HOUSEKEEPING_FIELDS
)
FROM STDIN 
WITH (DELIMITER '|', 
NULL 'NULL')
SQL


sub getCopySql {
  return $COPY_SQL;
}

sub bulkNiagadsVariantUpdate {
  my ($plugin, @updateBuffer) = @_;
  if (scalar @updateBuffer != 0) {
    my $sql = "UPDATE NIAGADS.Variant v SET is_adsp_variant = buffer.is_adsp_variant::boolean,";
    $sql .= " annotation = buffer.annotation::jsonb";
    $sql .= " FROM (VALUES " . join(',', @updateBuffer) . ")";
    $sql .= " AS buffer(record_primary_key, annotation, is_adsp_variant)";
    $sql .= " WHERE v.record_primary_key = buffer.record_primary_key";

    my $dbh = $plugin->getQueryHandle();
    my $qh = $dbh->prepare($sql);
    $qh->execute() || $plugin->error($dbh->errstr);
    $qh->finish();
    $dbh->commit() if $plugin->getArg('commit');
  }
}

sub bulkAnnotatedVariantUpdate {
  my ($plugin, $dbh, $partition, @updateBuffer) = @_;

  if (scalar @updateBuffer != 0) {
    my $sql = "UPDATE Variant_$partition v SET is_adsp_variant = buffer.is_adsp_variant::boolean,";
    $sql .= " other_annotation = buffer.annotation::jsonb";
    $sql .= " FROM (VALUES " . join(',', @updateBuffer) . ")";
    $sql .= " AS buffer (record_primary_key, is_adsp_variant, annotation) WHERE v.record_primary_key = buffer.record_primary_key";
    
    $dbh->{pg_direct} = 0; # don't parse the string/hopefully resolves issues w/the JSON
    my $qh = $dbh->prepare($sql);
    $qh->execute() || $plugin->error(Dumper(\@updateBuffer) . $dbh->errstr);
    $qh->finish();
    # this dbh should be in autocommit mode; need to check
  }
}

sub bulkAnnotatedVariantUpdateOtherAnnotation {
  my ($plugin, $dbh, $partition, @updateBuffer) = @_;

  if (scalar @updateBuffer != 0) {
    my $sql = "UPDATE Variant_$partition v SET";
    $sql .= " other_annotation = buffer.annotation::jsonb";
    $sql .= " FROM (VALUES " . join(',', @updateBuffer) . ")";
    $sql .= " AS buffer (record_primary_key, annotation) WHERE v.record_primary_key = buffer.record_primary_key";

    $dbh->{pg_direct} = 0; # don't parse the string/hopefully resolves issues w/the JSON
    my $qh = $dbh->prepare($sql);
    $qh->execute() || $plugin->error(Dumper(\@updateBuffer) . $dbh->errstr);
    $qh->finish();
    # this dbh should be in autocommit mode; need to check
  }
}

sub insertNiagadsVariant {
  my ($variantObj, $dbv, $props, $annotation) =  @_;
  my ($chr, $position, $ref, $alt) = split /:/, $dbv->{metaseq_id};
  $variantObj->setBinIndex($dbv->{bin_index});
  $variantObj->setRefSnpId($dbv->{ref_snp_id});
  $variantObj->setMetaseqId($dbv->{metaseq_id});
  $variantObj->setChromosome('chr' . $chr);
  $variantObj->setPosition($position);
  $variantObj->setLocationStart($props->{locationStart});
  $variantObj->setLocationEnd($props->{locationEnd});
  $variantObj->setRefAllele($ref);
  $variantObj->setAltAllele($alt);
  $variantObj->setDisplayAllele($props->{displayAllele});
  $variantObj->setVariantClassAbbrev($props->{variantObjClassAbbrev});
  $variantObj->setSequenceAllele($props->{sequenceAllele});

  if ($annotation) {
    $variantObj->setAnnotation($annotation); # assume already converted using Utils::to_json
  }
  $variantObj->submit();
}


sub generateCopyStr {
  my ($plugin, $dbv, $props, $annotation, $isAdspVariant) = @_;
  my ($chr, $position, $ref, $alt) = split /:/, $dbv->{metaseq_id};
  
  my $refSnp = ($dbv->{ref_snp_id}) ? $dbv->{ref_snp_id} : 'NULL'; # chance it might be empty
  my @values = ($dbv->{record_primary_key},
		$dbv->{bin_index},
		$dbv->{ref_snp_id},
		$dbv->{metaseq_id},
		'chr' . $chr, $position, $ref, $alt,
		$props->{locationStart},
		$props->{locationEnd},
		$props->{displayAllele},
		$props->{variantClassAbbrev},
		$props->{sequenceAllele},
		$isAdspVariant ? 1 : 'NULL');

  if ($annotation) {
    push(@values, GenomicsDBData::Load::Utils::to_json($annotation));
  }
  else {
    push(@values, 'NULL');
  }
  push(@values, GenomicsDBData::Load::Utils::getCurrentTime());
  push(@values, $plugin->{housekeeping});

  my $str = join "|", @values;
  $plugin->log($str) if $plugin->getArg('veryVerbose');
  return "$str\n";
}


sub niagadsVariantUpdateValuesStr {
  my ($recordPK, $annotation, $isAdspVariant) = @_;
  my $aStr = GenomicsDBData::Load::Utils::to_json($annotation);
  my $vflag = ($isAdspVariant) ? "1::boolean" : "NULL";
  return "('$recordPK', '$aStr', $vflag )";
}


sub updateGenomicsDbFlags {
  my ($annotation, $newFlag) = @_;
  if (exists $annotation->{GenomicsDB}) {
    my @oldFlags = @{$annotation->{GenomicsDB}};
    if (not defined $oldFlags[0]) { # temp bug fix; remove later
      return ($newFlag);
    }

    if (!GenomicsDBData::Load::Utils::arrayContains($newFlag, @oldFlags)) {# already in list due to update/broken load
      push(@oldFlags, $newFlag);
    }
    return @oldFlags;
  }
  return ($newFlag);
}


sub annotatedVariantUpdateValueStr {
  my ($plugin, $recordPK, $qcResult, $qcStatus, $selectQh) = @_;

  my $adspFlag = $plugin->getArg('adspFlag');
  my $vflag = ($qcStatus->{$adspFlag}->{FILTER_STATUS} eq 'PASS') ? "1::boolean" : "NULL";
  my $updatedAnnotation = generateUpdatedAvAnnotationStr($plugin, $recordPK, $adspFlag, $qcResult, $qcStatus, $selectQh);
  return "('$recordPK', $vflag, '$updatedAnnotation')";
}

sub annotatedVariantUpdateGwsValueStr {
  my ($plugin, $recordPK, $gwsFlag, $selectQh) = @_;

  my $newAnnotation = {};

  my $oldAnnotation = GenomicsDBData::Load::PluginUtils::fetchValueById($recordPK, $selectQh);

  if ($oldAnnotation) {
    my $json = JSON::XS->new;
    $oldAnnotation = $json->decode($oldAnnotation) 
      || $plugin->error("Error parsing AnnotatedVDB 'other' annotation: $oldAnnotation");
    $newAnnotation = {%$oldAnnotation, %$newAnnotation};
  }

  my @genomicsDbFlags = updateGenomicsDbFlags($newAnnotation, $gwsFlag);
  $newAnnotation->{GenomicsDB} = \@genomicsDbFlags;

  # $plugin->log($recordPK . Dumper($newAnnotation));

  my $updatedAnnotation = GenomicsDBData::Load::Utils::to_json($newAnnotation);
  $updatedAnnotation =~ s/'/''/g; # escape single quotes in json string

  return "('$recordPK', '$updatedAnnotation')";
}


sub updateAnnotatedVariantRecord {
  my ($plugin, $recordPK, $qcResult, $qcStatus, $updateQh, $selectQh) = @_;

  my $adspFlag = $plugin->getArg('adspFlag');
  my $vflag = ($qcStatus->{$adspFlag}->{FILTER_STATUS} eq 'PASS') ? "1" : "NULL";
  my $updatedAnnotation = generateUpdatedAvAnnotationStr($plugin, $recordPK, $adspFlag, $qcResult, $qcStatus, $selectQh);

  $updateQh->execute($vflag, $updatedAnnotation, $recordPK) if $plugin->getArg('commit');
}


sub generateUpdatedAvAnnotationStr {
  my ($plugin, $recordPK, $adspFlag, $qcResult, $qcStatus, $selectQh) = @_;

  if ($qcResult) {
    $qcResult->{FILTER_STATUS} = $qcStatus->{$adspFlag}->{FILTER_STATUS};
  }

  my $newAnnotation = ($qcResult) ? {$adspFlag => $qcResult} : $qcStatus;
  my $oldAnnotation = GenomicsDBData::Load::PluginUtils::fetchValueById($recordPK, $selectQh);
  if ($oldAnnotation) {
    my $json = JSON::XS->new;
    $oldAnnotation = $json->decode($oldAnnotation) 
      || $plugin->error("Error parsing AnnotatedVDB 'other' annotation: $oldAnnotation");
    $newAnnotation = {%$oldAnnotation, %$newAnnotation};
  }

  my @genomicsDbFlags = updateGenomicsDbFlags($newAnnotation, $adspFlag);
  $newAnnotation->{GenomicsDB} = \@genomicsDbFlags;

  my $updatedAnnotation = GenomicsDBData::Load::Utils::to_json($newAnnotation);
  $updatedAnnotation =~ s/'/''/g; # escape single quotes in json string

  return $updatedAnnotation;
}








1;
