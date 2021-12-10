
CREATE EXTENSION IF NOT EXISTS plperl;

DROP TYPE IF EXISTS displayAlleleT CASCADE;
CREATE TYPE displayAlleleT AS (variant_class TEXT, variant_class_abbrev TEXT, location_start INTEGER, location_end INTEGER, display_allele TEXT, sequence_allele TEXT);

CREATE OR REPLACE FUNCTION variant_class(TEXT, TEXT, TEXT)
RETURNS TEXT AS $$
  my ($vcAbbrev, $ref, $alt) = @_;
  if ($vcAbbrev eq "SNV") {
    return "single-nucleotide variant";
  } 
  if ($vcAbbrev eq "MNV") {
    if ($ref eq reverse($alt)) {
    return "inversion";
    }
    return "substitution"
  } 
  if ($vcAbbrev eq "INDEL") {
    return "indel";
  }   
  if ($vcAbbrev eq "INS") {
    return "insertion";
  }   
  if ($vcAbbrev eq "DEL") {
    return "deletion";
  }   
$$ LANGUAGE plperl;

CREATE OR REPLACE FUNCTION display_allele_attributes (TEXT, TEXT, TEXT, TEXT, INTEGER) 
RETURNS displayAlleleT AS $$

  # infer MNV/DIV variant CLASS AND location FROM POSITION AND alleles
  my ($ref, $alt, $normRef, $normAlt, $position) = @_;

  my $refLength = length($ref);
  my $altLength = length($alt);

  my $truncRef = $refLength <= 5 ? $ref : substr($ref, 0, 5) . "...";
  my $truncAlt = $altLength <= 5 ? $alt : substr($alt, 0, 5) . "...";

  my $truncNRef = length($normRef) <= 5 ? $normRef : substr($normRef, 0, 5) . "...";
  my $truncNAlt = length($normAlt) <= 5 ? $normAlt : substr($normAlt, 0, 5) . "...";

  my $props = {};

  if ($refLength == 1 && $altLength == 1) {
    $props = { variant_class => "single-nucleotide variant",
	       variant_class_abbrev => "SNV",
	       location_start => $position,
	       location_end => $position,
	       display_allele => "$ref>$alt",
	       sequence_allele => "$ref/$alt"};
    # elog("WARNING", $props);	
    return $props; 
  }
  if ($refLength == $altLength) { # MNV
    # inversion
    if ($ref eq reverse($alt)) {
      $props = { variant_class => "inversion",
		 variant_class_abbrev => "MNV",
		 location_start => $position,
		 location_end => $position + $refLength - 1,
		 display_allele => "inv$ref",
		 sequence_allele => $truncRef . "/" . $truncAlt};
    }
    else {
      $props = { variant_class => "substitution",
		 variant_class_abbrev => "MNV",
		 location_start => $position,
		 location_end => $position + length($normRef) - 1,
		 display_allele => "$normRef>$normAlt",
		 sequence_allele => $truncNRef . "/" . $truncNormAlt};
    }
  } # END MNV

  if ($refLength > $altLength) { # deletions
    $props = { location_start => $position };

    if (length($normAlt) > 1) { # INDEL
      $props->{variant_class} = "indel";
      $props->{variant_class_abbrev} = "INDEL";
      if (length($normRef) == 0) {
	$ref =~ s/^.//s; # strip FIRST character
	$props->{location_end} = $position + length($ref) - 1;
	$props->{display_allele} = "del$ref" . "ins$normAlt";
	$props->{sequence_allele} = $truncRef . "/" . $truncAlt;
      }
      else {
	$props->{location_end} = $position + length($normRef) - 1;
	$props->{display_allele} = "del$normRef" . "ins$normAlt";
	$props->{sequence_allele} = $truncNRef . "/" . $truncNAlt;
      }
    }
    else { # deletion
      $props->{location_end} = $position + length($normRef) - 1;
      $props->{variant_class} = "deletion";
      $props->{variant_class_abbrev} = "DEL";
      $props->{display_allele} = "del$normRef";
      $props->{sequence_allele} = $truncNRef . "/-";
    }
  }

  if ($refLength < $altLength) { # insertion
    $props = {location_start => $position};

    if (length($ref) > 1) { # INDEL
      $props->{variant_class} = "indel";
      $props->{variant_class_abbrev} = "INDEL";

      if (length($normRef) == 0) {
	$ref =~ s/^.//s; # strip FIRST character
	$props->{location_end} = $position + length($ref) - 1;
	$props->{display_allele} = "del$ref" . "ins$normAlt";
	$props->{sequence_allele} = $truncRef . "/" . $truncNAlt;
      }
      else {
	$props->{location_end} = $position + length($normRef) - 1;
	$props->{display_allele} = "del$normRef" . "ins$normAlt";
	$props->{sequence_allele} = $truncNRef . "/" . $truncNAlt;
      }

    }
    else { # insertion
      $props->{location_end} = $position + 1;
      $props->{variant_class} = "insertion";
      $props->{variant_class_abbrev} = "INS";
      $props->{display_allele} = "ins$normAlt";
      $props->{sequence_allele} = "-/" . $truncNAlt;
    }
  }

  return $props;


$$ LANGUAGE plperl;
