# utility functions for generating variant annotations (e.g., allele strings, start/end locations)

package NiagadsData::Load::VariantAnnotator;

use strict;

use Scalar::Util qw(looks_like_number);

use LWP::UserAgent;
use Data::Dumper;
use JSON;
use DBD::Pg;
use Vcf;

use NiagadsData::Load::Utils qw(truncateStr);

my $METASEQ_SQL = "SELECT * FROM find_variant_by_metaseq_id(?::text, FALSE)";
my $SINGLE_METASEQ_SQL = "SELECT * FROM find_earliest_variant_by_metaseq_id(?::text, TRUE)";
my $REFSNP_SQL = "SELECT * FROM find_variant_by_refsnp(?)";
my $REFSNP_ALLELE_SQL = "SELECT * FROM find_variant_by_refsnp_and_alleles(?, ?, ?)";
my $POSITION_SQL = "SELECT * FROM find_variant_by_position(?,?)";
my $BIN_INDEX_SQL = "SELECT find_bin_index(?,?,?) AS global_bin_path";

my $VERIFY_VARIANT_SQL = "SELECT record_primary_key FROM NIAGADS.Variant WHERE record_primary_key = ?";

sub new {
  my ($class, $args) = @_;
  my $plugin = $args->{plugin};
  my $self = { plugin => $args->{plugin},
	       vcf => $args->{vcf},
	       external_database_release_id => $args->{external_database_release_id}
	     };
  return bless $self, $class;
}

sub DESTROY {
    my ($self) = @_;
    $self->{metaseqQh}->finish();
    $self->{singleMetaseqQh}->finish();
    $self->{verifyQh}->finish();
    $self->{refsnpQh}->finish();
    $self->{refsnpAlleleQh}->finish();
}


sub getSnvDeletion {
  my ($self, $chromosome, $position) = @_;

  my $sql = "SELECT SUBSTRING(sequence, ?, 2) FROM DOTs.ExternalNASequence WHERE source_id  = ?";
  my $qh = $self->{plugin}->getQueryHandle()->prepare($sql);
  $qh->execute($position, $chromosome);
  my ($alleleStr) = $qh->fetchrow_array();
  $qh->finish();
  return $alleleStr;
}


sub validateMetaseqIds {
  my ($self, $validateFlag) = @_;
  $self->{validate_metaseq_ids} = $validateFlag;
}

sub createQueryHandles {
  my ($self) = @_;
  $self->{metaseqQh} = $self->connect2AnnotatedVDB()->prepare($METASEQ_SQL);
  $self->{singleMetaseqQh} = $self->connect2AnnotatedVDB()->prepare($SINGLE_METASEQ_SQL);
  $self->{verifyQh} = $self->{plugin}->getQueryHandle()->prepare($VERIFY_VARIANT_SQL);
  $self->{refsnpQh} = $self->{plugin}->getQueryHandle()->prepare($REFSNP_SQL); # actually just as fast via fdw b/c can't use partitions
  $self->{refsnpAlleleQh} = $self->{plugin}->getQueryHandle()->prepare($REFSNP_ALLELE_SQL); # actually just as fast via fdw b/c can't use partitions
}


# ----------------------------------------------------------------------
# get flanking sequence for a variant
# ----------------------------------------------------------------------
sub getFlankingSequenceByPosition {
  my ($self, $chr, $start, $end, $length) = @_;
  $length //= 15;
  my $sql = <<SQL;
SELECT substring(sequence, $start - $length, $length) AS upstream_sequence,
substring(sequence, $end + 1, $length) AS downstream_sequence
FROM DoTS.ExternalNASequence na WHERE source_id = '$chr'
SQL

  my $qh = $self->{plugin}->getQueryHandle()->prepare($sql)
    or $self->{plugin}->error(DBI::errstr);
  
  $qh->execute();
  my ($upstream, $downstream) = $qh->fetchrow_array();
  $qh->finish();

  return ($upstream, $downstream);
}


sub getFlankingSequence {
  my ($self, $length, @variantIds) = @_;
  $length //= 15;
  my $sql = <<SQL;
SELECT variant_id, substring(sequence, v.location_start - $length, $length) AS upstream_sequence,
substring(sequence, v.location_end + 1, $length) AS downstream_sequence
FROM DoTS.ExternalNASequence na,
NIAGADs.Variant v
WHERE v.variant_id IN (@{[join',', ('?') x @variantIds]})
AND na.source_id = v.chromosome
SQL

  my $qh = $self->{plugin}->getQueryHandle()->prepare($sql)
    or $self->{plugin}->error(DBI::errstr);
  
  $qh->execute(@variantIds);
  my $result = {};
  while (my ($variantId, $upstream, $downstream) = $qh->fetchrow_array()) {
    $self->{plugin}->log($variantId);
    $result->{$variantId} = {};
    $result->{$variantId}->{UPSTREAM_SEQUENCE} = $upstream;
    $result->{$variantId}->{DOWNSTREAM_SEQUENCE} = $downstream;
    $self->{plugin}->log(Dumper($result));
  }
  $qh->finish();

  return $result;
}


sub queryDbSNP {
  my ($self, $marker) = @_;
  $marker =~ s/rs//g;
  my $url = "https://api.ncbi.nlm.nih.gov/variation/v0/beta/refsnp/$marker";

  my $ua = LWP::UserAgent->new;
  my $response = $ua->get($url);
  if ($response->is_success) {
    my $json = JSON->new;
    my $contentJson = $json->decode($response->content);
    my $annotation = $self->extractDbSnpVariant($contentJson->{primary_snapshot_data}->{placements_with_allele});
    $self->{plugin}->error(Dumper($annotation));
  }
  else {
    $self->{plugin}->error($response->status_line);
  }
}

sub extractDbSnpVariant {
  my ($self, $placements) = @_;

  my $assembly = $self->{plugin}->getArg('genomeBuild');
  foreach my $annotation (@$placements) {
    my @seqTraits = @{$annotation->{seq_id_traits_by_assembly}};
    if ($seqTraits[0]->{assemblyName} eq $assembly) {
      my @alleles = @{$annotation->{alleles}};
      my $position = $alleles[0]->{allele}->{spdi}->{position};
      last
    }
  }
}


# ----------------------------------------------------------------------
# test if a position is in a range
# ----------------------------------------------------------------------
sub inRange {
  my ($self, $position, @range) = @_;
  return 1 if ($position >= $range[0] and $position < $range[1]);
  return 0;
}


# ----------------------------------------------------------------------
# determine variant location & display alleles
# ----------------------------------------------------------------------
sub inferVariantLocationDisplay {
  # infer MNV/DIV variant class and location from position and alleles
  my ($self, $ref, $alt, $position, $rsPosition) = @_;

  my $refLength = length($ref);
  my $altLength = length($alt);

  my $props = {};

  my ($normRef, $normAlt) = normalize_alleles($self->{plugin}, $ref, $alt);
  if ($refLength == 1 and $altLength == 1) {
    $props = { variantClass => "SNV",
	       variantClassAbbrev => "SNV",
	       locationStart => $position,
	       locationEnd => $position,
	       displayAllele => "$ref>$alt",
	       sequenceAllele => "$ref/$alt"};
    return $props;
  }
  if ($refLength == $altLength) { # MNV
    # inversion
    if ($ref eq reverse $alt) {
      $props = { variantClass => "inversion",
		 variantClassAbbrev => "MNV",
		 locationStart => $position,
		 locationEnd => $position + $refLength - 1,
		 displayAllele => "inv$ref",
		 sequenceAllele => truncateStr($ref) . "/" . truncateStr($alt)};
    }
    else {
      $props = { variantClass => "substitution",
		 variantClassAbbrev => "MNV",
		 locationStart => $rsPosition,
		 locationEnd => $rsPosition + length($normRef) - 1,
		 displayAllele => "$normRef>$normAlt",
		 sequenceAllele => truncateStr($normRef) . "/" . truncateStr($normAlt)};
    }
  } # end MNV

  if ($refLength > $altLength) { # deletions
    $props = { locationStart => $rsPosition };

    if (length($alt) > 1) { # INDEL
      $props->{variantClass} = "indel";
      $props->{variantClassAbbrev} = "INDEL";
      if (length($normRef) == 0) {
	$ref =~ s/^.//s; # strip first character
	$props->{locationEnd} = $rsPosition + length($ref) - 1;
	$props->{displayAllele} = "del$ref" . "ins$normAlt";
	$props->{sequenceAllele} = truncateStr($ref) . "/" . truncateStr($normAlt);
      }
      else {
	$props->{locationEnd} = $rsPosition + length($normRef) - 1;
	$props->{displayAllele} = "del$normRef" . "ins$normAlt";
	$props->{sequenceAllele} = truncateStr($normRef) . "/" . truncateStr($normAlt);
      }
    }
    else { # deletion
      $props->{locationEnd} = $rsPosition + length($normRef) - 1;
      $props->{variantClass} = "deletion";
      $props->{variantClassAbbrev} = "DEL";
      $props->{displayAllele} = "del$normRef";
      $props->{sequenceAllele} = truncateStr($normRef) . "/-";
    }
  }

  if ($refLength < $altLength) { # insertion
    $props = {locationStart => $rsPosition};

    if (length($ref) > 1) { # INDEL
      $props->{variantClass} = "indel";
      $props->{variantClassAbbrev} = "INDEL";

      if (length($normRef) == 0) {
	$ref =~ s/^.//s; # strip first character
	$props->{locationEnd} = $rsPosition + length($ref) - 1;
	$props->{displayAllele} = "del$ref" . "ins$normAlt";
	$props->{sequenceAllele} = truncateStr($ref) . "/" . truncateStr($normAlt);
      }
      else {
	$props->{locationEnd} = $rsPosition + length($normRef) - 1;
	$props->{displayAllele} = "del$normRef" . "ins$normAlt";
	$props->{sequenceAllele} = truncateStr($normRef) . "/" . truncateStr($normAlt);
      }

    }
    else { # insertion
      $props->{locationEnd} = $rsPosition + 1;
      $props->{variantClass} = "insertion";
      $props->{variantClassAbbrev} = "INS";
      $props->{displayAllele} = "ins$normAlt";
      $props->{sequenceAllele} = "-/" . truncateStr($normAlt);
    }
  }

  return $props;
}


# ----------------------------------------------------------------------
#  normalize alleles (remove left most that are similar between ref & alt)
# ----------------------------------------------------------------------
sub normalize_alleles {
    my ($self, $ref, $alt) = @_;

    my $rLength = length($ref);
    my $aLength = length($alt);

    return ($ref, $alt)
      if ($rLength == 1 and $aLength == 1);

    my $lastMatchingIndex = -1;
    for my $i (0 .. $rLength - 1) {
      my $r = substr($ref, $i, 1);
      my $a = substr($alt, $i, 1);
      if ($r eq $a) {
	$lastMatchingIndex = $i;
      }
      else {
	last;
      }
    }

    return (substr($ref, $lastMatchingIndex + 1), substr($alt, $lastMatchingIndex + 1))
      if ($lastMatchingIndex >= 0);

    return ($ref, $alt);
}


# ----------------------------------------------------------------------
#  truncate and add ellipses
# ----------------------------------------------------------------------
sub truncateStr {
  my ($str, $length) = @_;
  $length //= 5; # set parameter value default (works in perl 5.10+)
  return $str if (length($str) <= $length);
  return substr($str, 0, $length) . "...";
}


# ----------------------------------------------------------------------
#  verify that variant is in GenomicsDB (NIAGADS.Variant)
# ----------------------------------------------------------------------

sub verifyVariant {
  my ($self, $recordPK) = @_;
  # my $sql = "SELECT record_primary_key FROM NIAGADS.Variant WHERE record_primary_key = ?";
  # my $dbh = $self->{plugin}->getQueryHandle();
  # my $qh = $dbh->prepare($sql);

  # $qh->execute($recordPK) || $self->{plugin}->error($dbh->errstr);
  $self->{verifyQh}->execute($recordPK);
  my ($result) = $self->{verifyQh}->fetchrow_array();
  # $qh->finish();
  return $result;
}

# ----------------------------------------------------------------------
#  get variant primary keys from database of annotated variants
# ----------------------------------------------------------------------

sub getAnnotatedVariants {
  my ($self, $metaseqId, $marker, $alleles, $firstHitOnly) = @_;

  if ($self->{plugin}->getArg('mapThruMarker')) { # bypasses metaseq check
    return $self->getVariantIdByRefSnp($marker, $alleles) if ($marker and $marker =~ /rs/);
    return ();
  }

  my @variants = ();
  if ($metaseqId) {
    if ($self->metaseqIdIsValid($metaseqId)) {
      @variants = $self->getVariantIdByMetaseqId($metaseqId, $firstHitOnly);
      
      if (!@variants) {
	$self->{plugin}->log("No match for $metaseqId, checking alt variants.")
	  if $self->{plugin}->getArg('veryVerbose');
	@variants = $self->checkAltVariants($metaseqId, $firstHitOnly);
      }
      else {
	$self->{plugin}->log("Matched $metaseqId.")
	    if $self->{plugin}->getArg('veryVerbose');
      }
    }
    else {
      $self->{plugin}->log("Unable to map invalid metaseq_id: $metaseqId.")
	    if $self->{plugin}->getArg('veryVerbose');
    }
  }

  if (!@variants) {
    if ($marker) { # if marker present and checking metaseq id failed, give it a go
      $self->{plugin}->log("Unable to map $metaseqId, checking $marker")
	    if $self->{plugin}->getArg('veryVerbose');
      @variants = $self->getVariantIdByRefSnp($marker, $alleles) if ($marker =~ /rs/);
      # @variants = $self->getVariantIdByMetaseqId($marker, $firstHitOnly) if ($marker =~ /:/);
    }
  }

  if (!@variants) {
    if ($self->{plugin}->getArg('mapPosition')) {
      my ($chr, $pos, $ref, $alt) = split /:/, $metaseqId;
      $self->{plugin}->log("Unable to map $metaseqId, mapping to all variants at position.")
	    if $self->{plugin}->getArg('veryVerbose');
      @variants = $self->getVariantIdByPosition($chr, $pos);
    }
  }

  return @variants;
}


# ----------------------------------------------------------------------
# get variant_id from db based on alt variant ids (e.g., switch 
# ref/alt, reverse strand
# ----------------------------------------------------------------------

sub checkAltVariants {
  my ($self, $metaseqId, $firstHitOnly) = @_;
  my ($chr, $pos, $ref, $alt) = split /:/, $metaseqId;
  
  my $isIndel = (length $ref > 1 || length $alt > 1); 

  if ($isIndel && !$self->{plugin}->getArg('checkAltIndels')) {
    return ();
  }

  my @altVariants = ("$chr:$pos:$alt:$ref");
  if (!$isIndel) { # don't check reverse complement for indels
    my $rRef = reverseComp($ref);
    my $rAlt = reverseComp($alt);
    push(@altVariants, "$chr:$pos:$rRef:$rAlt");
    push(@altVariants, "$chr:$pos:$rAlt:$rRef");
  }

  foreach my $v (@altVariants) {
    my @variants = $self->getVariantIdByMetaseqId($v, $firstHitOnly);
    return @variants if (@variants); # return first match
  }

  # $self->{plugin}->log("returning empty list");
  return ();
}

# ----------------------------------------------------------------------
# get variant_id from db based on metaseq id: chr:pos:ref:alt
# ----------------------------------------------------------------------

sub getVariantIdByMetaseqId {
  my ($self, $metaseqId, $firstHitOnly) = @_;

  $self->{metaseqQh}->execute($metaseqId);
  my $result = ($firstHitOnly) ? $self->{metaseqQh}->fetchall_arrayref({}, 2) : $self->{metaseqQh}->fetchall_arrayref({});
  # 2 is max_rows, limit the mem
  
  if ($firstHitOnly and scalar @$result > 1) { # these are so rare; it is faster to do two lookups than do the slower lookup on everything
    # $self->{plugin}->log(Dumper(\$result));
    $self->{plugin}->log("Multiple matches to $metaseqId; finding oldest refSNP") if $self->{plugin}->getArg('veryVerbose');
    $self->{singleMetaseqQh}->execute($metaseqId);
    $result = $self->{singleMetaseqQh}->fetchall_arrayref({}, 1); # 1 is max rows
  }
  
  return @$result if ($result);
  return ();
}


sub metaseqIdIsValid {
  my ($self, $metaseqId) = @_;

  return 1 if ($self->{validate_metaseq_ids} == 0);

  my ($chr, $pos, $ref, $alt) = split /:/, $metaseqId;

  return 0 if (($metaseqId =~ m/\?/) or !$ref or !$alt or (!($ref =~ m/A|T|C|G/)) or (!($alt =~ m/A|T|C|G/)));
  return 1;
}


# ----------------------------------------------------------------------
# get variant_id from db by position (chr:pos)
# ----------------------------------------------------------------------

sub getVariantIdByPosition {
  my ($self, $chr, $pos) = @_;

  $chr = 'chr' + $chr if (!($chr =~ 'chr'));
  
  my $qh = $self->{plugin}->getQueryHandle()->prepare($POSITION_SQL);
  $qh->execute($chr, $pos);
  my $result = $qh->fetchall_arrayref({record_primary_key => 1, has_genomicsdb_annotation => 2}); # ref({'record_primary_key'});
  $qh->finish();
  return @$result if ($result);
  return ();

}


# ----------------------------------------------------------------------
# get variant_id from db refsnp identifier (rsId)
# ----------------------------------------------------------------------

sub getVariantIdByRefSnp {
  my ($self, $marker, $alleles) = @_;
  my $result = undef;
  if (lc($marker) =~ m/rs/) {
    if ($alleles and $alleles !~ m/\?/g) { # if allele string contains a ?, then just match the rsId
      $self->{plugin}->log("Lookup by marker: $marker - $alleles");
      my ($ref, $alt) = split /:/, $alleles;
      $self->{refsnpAlleleQh}->execute($marker, $ref, $alt);
      $result = $self->{refsnpAlleleQh}->fetchall_arrayref({});
    }
    else {
      $self->{refsnpQh}->execute($marker);
      $result = $self->{refsnpQh}->fetchall_arrayref({});
    }
    return @$result if ($result);
  }
  else {
    $self->{plugin}->log("Cannot map variant by marker name $marker.  Not a refSNP id");
  }
  return ();
}


# ----------------------------------------------------------------------
# get the reverse complement of a dna string
# ----------------------------------------------------------------------

sub reverseComp {
  my ($allele) = @_;
  $allele =~ tr/ACGTacgt/TGCAtgca/;
  return $allele;
}


# ----------------------------------------------------------------------
# # check whether result from sql function is null
# ----------------------------------------------------------------------
sub isNull {
  my ($response) = @_;
  return 1 if (!$response or $response eq '');
  return 0;
}

# ----------------------------------------------------------------------
# # update variant annotation ($variant is a NIAGADS::Variant object)
# ----------------------------------------------------------------------
sub generateUpdatedAnnotation {
  my ($self, $variant, $annotation) = @_;
  my $json = JSON->new;
  my $variantAnnotation = $variant->getAnnotation();
  if ($variantAnnotation) {
    $variantAnnotation = $json->decode($variantAnnotation) || $self->{plugin}->error("Error parsing variant annotation: $variantAnnotation");
    $annotation = {%$variantAnnotation, %$annotation};
  }

  return $annotation;
}


# ----------------------------------------------------------------------
# # extract variant info from vcf record
# ----------------------------------------------------------------------

sub extractVariantsFromVcfRecord {
  my ($self, $record, $source) = @_;
  my $vcf = $self->{vcf};

  my $annotation = {};
  my $sourceId = $vcf->get_column($record, "ID");
  my $chrNum = $vcf->get_column($record, "CHROM");
  $chrNum = "M" if ($chrNum eq "MT");
  my $chr = "chr" . $chrNum;
  
  my $position = $vcf->get_column($record, "POS");
  my $ref = $vcf->get_column($record, "REF");
  my $altAlleleStr = $vcf->get_column($record, "ALT");
  
  my $info = $vcf->get_column($record, "INFO");
  my $vc = $vcf->get_info_field($info, "VC");
  my $isReversed = ($vcf->get_info_field($info, "RV")) ? 1 : "NULL";

  my $rsPosition = $vcf->get_info_field($info, "RSPOS");
  my $dbSnpBld = $vcf->get_info_field($info, "dbSNPBuildID");
  $annotation->{dbSNPBuildID} = $dbSnpBld if $dbSnpBld;
  
  my @altAlleles = split ',', $altAlleleStr;
  my $minorAlleleCount = scalar @altAlleles;
  my $isMultiallelic = ($minorAlleleCount > 1) ? 1 : "NULL";

  my @recordVariants = ();
  foreach my $alt (@altAlleles) {
      my $metaseqId = "$chrNum:$position:$ref:$alt";
      my $primaryKey = $metaseqId . "_" . $sourceId;
      my $annotation = to_json $annotation;

      my $props = $self->inferVariantLocationDisplay($ref, $alt, $position, $rsPosition, $vc);
      my $binIndex = $self->getBinIndexFromDB($chr, $props->{locationStart}, $props->{locationEnd});

      my @variant = ($binIndex, $self->{external_database_release_id}, $sourceId,
		    $source, $chr, $position, $props->{locationStart}, $props->{locationEnd},
		    $ref, $alt, $props->{displayAllele}, $props->{variantClass},
		    $props->{variantClassAbbrev}, $isMultiallelic, $minorAlleleCount, $isReversed, 
		    $metaseqId, 
		    $props->{sequenceAllele},
		    $primaryKey, $annotation);

      
      push(@recordVariants, join('|', @variant));

    }
  return @recordVariants;
}

sub loadCaddScores {
  my ($self, $file) = @_;
  $self->{plugin}->log("Loading CADD scores for variants in $file");
  my @cmd = ('load_cadd_scores.py', 
	     '--databaseDir', $self->{plugin}->getArg('caddDatabaseDir'),
	     '--gusConfigFile', $self->{plugin}->getArg('annotatedVdbGusConfigFile'),
	     '--logFile', $file . '-cadd.log',
	     '--vcfFile', $file);
  push(@cmd, '--commit') if $self->{plugin}->getArg('commit');
  $self->{plugin}->log("Running load_cadd_scores.py to add in CADD scores for novel variants: " . join(' ', @cmd));
  my $status = qx(@cmd);

  $self->{plugin}->error("Loading CADD scores failed -- see $file-cadd.log") if ($status !~ /SUCCESS/);
  $self->{plugin}->log("DONE loading CADD scores for novel variants.");
}


sub loadVepAnnotatedVariants {
  my ($self, $file) = @_;
  $self->{plugin}->log("Loading Variants into AnnotatedVDB from $file");

  my @cmd = ('load_vep_result.py', 
	     '--inputFile', $file . '.json',
	     '--logFile', $file . '.log',
	     '--rankingFile', $self->{plugin}->getArg('adspConsequenceRankingFile'),
	     '--gusConfigFile', $self->{plugin}->getArg('annotatedVdbGusConfigFile'));
  push(@cmd, '--commit') if $self->{plugin}->getArg('commit');

  $self->{plugin}->log("Running load_vep_result.py to load annotation of novel variants: " . join(' ', @cmd));

  my  $algInvocationId = qx(@cmd); # qx(join(' ', @cmd)); 

  $self->{plugin}->error("Loading novel variants failed; see $file.log") 
    if ($algInvocationId eq 'FAIL' || !(looks_like_number($algInvocationId)));
  $self->{plugin}->log("DONE Loading novel variants: AnnotatedVDB Algorithm Invocation ID = $algInvocationId");

}

sub loadNonVepAnnotatedVariants {
  my ($self, $file) = @_;
  $self->{plugin}->log("Loading placeholders in AnnotatedVDB for novel variants from $file not annotated by VEP");

  my @cmd = ('load_non_vep_annotated_variants_from_vcf.py',
	     '--vcfFile', $file,
	     '--logFileName', $file . '-missing-from-vep.log',
	     '--gusConfigFile', $self->{plugin}->getArg('annotatedVdbGusConfigFile'));
  push(@cmd, '--commit') if $self->{plugin}->getArg('commit');

  my $algInvocationId = qx(@cmd);

  $self->{plugin}->error("Loading unannotated novel variants failed; see $file-missing-from-vep.log") 
    if ($algInvocationId eq 'FAIL' || !(looks_like_number($algInvocationId)));
  $self->{plugin}->log("Done loading placeholders for non-VEP annotated novel variants: AnnotatedVDB Algorithm Invocation ID = $algInvocationId");
}



sub sortVcf {
  my ($self, $vcfFile) = @_;
  my $sortedFile = $vcfFile =~ s/vcf/sorted\.vcf/r; # /r substitute w/out replace

  $self->{plugin}->log("Sorting VCF file: $vcfFile");
  my $cmd = `vcf-sort -c $vcfFile > $sortedFile`;
  $self->{plugin}->log("Created sorted VCF file: $sortedFile");
  return $sortedFile;
}

sub runVep {
  my ($self, $inputFile) = @_;
  # "input_file": "foreach",
#		    "output_file": "foreach",
  my @cmd = ('vep',
	     '--input_file', $inputFile,
	     '--output_file', $inputFile . '.json',
	     '--format', 'vcf',
	     '--dir_cache', $self->{plugin}->getArg('vepCacheDir'),
	     '--offline', 
	     '--no_stats',
	     '--json',
	     '--fork', 10,
	     '--sift', 'b',
	     '--fork', 10,
	     '--sift', 'b',
	     '--polyphen', 'b',
	     '--ccds',
	     '--symbol',
	     '--numbers',
	     '--domains',
	     '--regulatory',
	     '--canonical',
	     '--protein',
	     '--biotype',
	     '--tsl',
	     '--pubmed',
	     '--uniprot',
	     '--variant_class',
	     '--af',
	     '--af_1kg',
	     '--af_esp',
	     '--af_gnomad',
	     '--clin_sig_allele', 1,
	     '--nearest', 'gene',
	     '--gene_phenotype',
	     '--force_overwrite');

  $self->{plugin}->log("Running VEP: " . join(' ', @cmd));
  system(@cmd);
  $self->{plugin}->log("Done Running VEP.");
}


sub connect2AnnotatedVDB {
  my ($self) = @_;
  my $gusConfig = GUS::Supported::GusConfig->new($self->{plugin}->getArg('annotatedVdbGusConfigFile'));

  my $dbh  = DBI->connect($gusConfig->getDbiDsn(),
			 $gusConfig->getDatabaseLogin(),
			 $gusConfig->getDatabasePassword(),
			 {AutoCommit => $self->{plugin}->getArg('commit')});
  return $dbh;
}

sub setAnnotatedVDBh {
  my ($self) = @_;
  $self->{annotatedVDB_handle} = $self->connect2AnnotatedVDB();
}


sub disconnectAnnotatedVDBh {
  my ($self) = @_;
  $self->{annotatedVDBh}->disconnect();
}

sub fetchFromAnnotatedVDB {
  my ($self, $recordPK, $chr, $field) = @_;
  my $sql = "SELECT $field FROM Variant_chr$chr v WHERE v.record_primary_key = ?";
  my $qh = $self->{annotatedVDBh}->prepare($sql);
  $qh->execute($recordPK);
  my ($result) = $qh->fetchrow_array();
  $qh->finish();
  return $result;
}


1;
