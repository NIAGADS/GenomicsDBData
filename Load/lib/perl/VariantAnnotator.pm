# utility functions for generating variant annotations (e.g., allele strings, start/end locations)

package GenomicsDBData::Load::VariantAnnotator;

use strict;

use Scalar::Util qw(looks_like_number);

use LWP::UserAgent;
use Data::Dumper;
use JSON::XS;
use DBD::Pg;
use Vcf;

use GenomicsDBData::Load::Utils qw(truncateStr);


sub new {
  my ($class, $args) = @_;
  my $plugin = $args->{plugin};
  my $self = { plugin => $args->{plugin},
	       vcf => $args->{vcf},
	       genome_build => $args->{genome_build},
	       external_database_release_id => $args->{external_database_release_id}
	     };
  return bless $self, $class;
}

sub DESTROY {
    my ($self) = @_;
}


sub getSnvDeletion {
  my ($self, $genomeBuild, $chromosome, $position) = @_;

  my $lookupField = ($genomeBuild eq 'GRCh37') ? 'source_id' : 'chromosome';

  my $sql = "SELECT SUBSTRING(sequence, ?, 2) FROM DOTs.ExternalNASequence WHERE $lookupField  = ?";
  my $qh = $self->{plugin}->getQueryHandle()->prepare($sql);
  $qh->execute($position, $chromosome);
  my ($alleleStr) = $qh->fetchrow_array();
  $qh->finish();
  return ($alleleStr, substr $alleleStr, -1);
}


sub initializeUpdateBuffer {
  my ($self) =@_;
  $self->{update_buffer_size} = 0;
  $self->{update_buffer} = "";
}


sub bufferVariantUpdate {
  my ($self, $gwasFlags, $recordPK, $chromosome, $isAdspVariant) = @_;

  my $chr = ($chromosome =~ m/chr/g) ? $chromosome : "chr$chromosome";
  my $sql = "UPDATE AnnotatedVDB. Variant v SET"
    . " gwas_flags = gwas_flags || " . Utils::to_json($gwasFlags)
    . ($isAdspVariant) ? ", is_adsp_variant = True" : ""
    . " WHERE v.record_primary_key = $recordPK"
    . " AND v.chromosome = $chromosome;";

  $self->{update_buffer} .= $sql;
  $self->{update_buffer_size} += 1; 
}


sub bulkUpdateVariants {
  my ($self) = @_;
  my $qh = $self->{plugin}->getQueryHandle()->prepare($self->{update_buffer})
    or $self->{plugin}->error(DBI::errstr);
  $qh->execute();
  $qh->finish();
  $self->initializeUpdateBuffer();
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
    my $json = JSON::XS->new;
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
# get the complement of a dna string
# ----------------------------------------------------------------------

sub complement {
  my ($allele) = @_;
  $allele =~ tr/ACGTacgt/TGCAtgca/;
  return $allele;
}

sub reverseComplement {
  my  ($allele) = @_;
  my  $comp = complement($allele);
  $comp = reverse $comp;
  return $comp;
}


# ----------------------------------------------------------------------
# # update variant annotation ($variant is a NIAGADS::Variant object)
# ----------------------------------------------------------------------
sub generateUpdatedAnnotation {
  my ($self, $variant, $annotation) = @_;
  my $json = JSON::XS->new;
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
  my ($self, $file, $logFilePath) = @_;
  $self->{plugin}->log("Loading CADD scores for variants in $file");
  my @cmd = ('load_cadd_scores.py', 
	     '--databaseDir', $self->{plugin}->getArg('caddDatabaseDir'),
	     '--logFilePath', $logFilePath,
	     '--seqrepoProxyPath', $self->{plugin}->getArg('seqrepoProxyPath'),
	     '--vcfFile', $file);
  push(@cmd, '--commit') if $self->{plugin}->getArg('commit');
  $self->{plugin}->log("Running load_cadd_scores.py to add in CADD scores for novel variants: " . join(' ', @cmd));
  my $status = qx(@cmd);

  $self->{plugin}->error("Loading CADD scores failed -- see logs in $logFilePath") if ($status !~ /SUCCESS/);
  $self->{plugin}->log("DONE loading CADD scores for novel variants.");
}


sub updateVariantRecords {
  my ($self, $fileName, $gusConfigFile, $legacyDB) = @_;

  $self->{plugin}->log("Updating variants from $fileName");
  my @cmd = ('update_variant_annotation.py',
	     '--variantIdType', 'PRIMARY_KEY',
	     '--commitAfter', 5000,
	     '--fileName', $fileName
	    );

  push(@cmd, '--gusConfigFile', $gusConfigFile) if ($gusConfigFile);
  push(@cmd, '--useDynamicPkSql') if ($legacyDB);
  push(@cmd, '--commit') if( $self->{plugin}->getArg('commit'));

  $self->{plugin}->log("Running variant annotation update: " . join(' ', @cmd));
  my $status = qx(@cmd);

  $self->{plugin}->error("Updating Variants failed -- see logs in $fileName.log") if ($status !~ /SUCCESS/);
  $self->{plugin}->log("DONE updating variants.");
}



sub loadVepAnnotatedVariants {
  my ($self, $file) = @_;
  $self->{plugin}->log("INFO: Loading Variants into AnnotatedVDB from $file");

  my @cmd = ('load_vep_result.py', 
	     '--fileName', $file,
	     '--rankingFile', $self->{plugin}->getArg('adspConsequenceRankingFile'),
	     '--genomeBuild', $self->{plugin}->getArg('genomeBuild'),
	     '--seqrepoProxyPath', $self->{plugin}->getArg('seqrepoProxyPath'),
	     '--datasource', $self->{plugin}->getArg('isAdsp') ? 'ADSP' : 'NIAGADS',
	     '--skipExisting',
	     '--logSkips'
	    );
  push(@cmd, '--commit') if $self->{plugin}->getArg('commit');

  $self->{plugin}->log("INFO: Executing command: " . join(' ', @cmd));
  my  $algInvocationId = qx(@cmd);
  $self->{plugin}->error("Loading variants from VEP result failed. See $file.log")
    if ($algInvocationId eq 'FAIL' || !(looks_like_number($algInvocationId)));
  $self->{plugin}->log("DONE: Loading variants from VEP result: AnnotatedVDB Algorithm Invocation ID = $algInvocationId");

}

sub loadVariantsFromVCF {
  my ($self, $file) = @_;
  $self->{plugin}->log("INFO: Loading variants in AnnotatedVDB from VCF $file");

  my @cmd = ('load_vcf_file.py',
	     '--fileName', $file,
	     '--genomeBuild', $self->{plugin}->getArg('genomeBuild'),
	     '--seqrepoProxyPath', $self->{plugin}->getArg('seqrepoProxyPath'),
	     '--datasource', $self->{plugin}->getArg('isAdsp') ? 'ADSP' : 'NIAGADS',
	     '--skipExisting'
	   );
  push(@cmd, '--commit') if $self->{plugin}->getArg('commit');

  $self->{plugin}->log("INFO: Executing command: " . join(' ', @cmd));
  my $algInvocationId = qx(@cmd);
  $self->{plugin}->error("Loading variants from VCF failed; see $file.log")
    if ($algInvocationId eq 'FAIL' || !(looks_like_number($algInvocationId)));
  $self->{plugin}->log("DONE: loading variants from VCF: AnnotatedVDB Algorithm Invocation ID = $algInvocationId");
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

  # e.g. file name NG00027/GRCh38/NG00027_GRCh38_STAGE12/preprocess/NG00027_GRCh38_STAGE12-novel.vcf
  $self->{plugin}->log("Info: Running VEP on $inputFile");
  my $webhook = $self->{plugin}->getArg('vepWebhook');
  my (@cmd) = ('curl', '-d',
	       '"' . "file=$inputFile" . '"',
	       '"' . $webhook . '"'
	      );
  
  $self->{plugin}->log("INFO: Executing command: " . join(' ', @cmd));
  my $message = qx(@cmd);

  $self->{plugin}->error("Running VEP on variants from $inputFile failed: $message")
    if ($message !~ /SUCCESS/);
  $self->{plugin}->log("DONE: Running VEP on $inputFile");
}


sub connect2AnnotatedVDB {
  my ($self) = @_;
  my $gusConfig = GUS::Supported::GusConfig->new(); 

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
