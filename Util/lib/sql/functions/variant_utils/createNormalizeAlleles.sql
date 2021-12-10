
CREATE EXTENSION IF NOT EXISTS plperl;

DROP TYPE IF EXISTS allelesT CASCADE;
CREATE TYPE allelesT AS (ref TEXT, alt TEXT);

CREATE OR REPLACE FUNCTION normalize_alleles (TEXT, TEXT) 
RETURNS allelesT AS $$
    my ($refAllele, $altAllele) = @_;
    my $rLength = length($refAllele);
    my $aLength = length($altAllele);

    if ($rLength == 1 && $aLength == 1) {	# comment
        return {ref => $refAllele, alt => $altAllele}
    }  

    my $lastMatchingIndex = -1;
    for my $i (0 .. $rLength - 1) {
      my $r = substr($refAllele, $i, 1);
      my $a = substr($altAllele, $i, 1);
      if ($r eq $a) {
	$lastMatchingIndex = $i;
      }
      else {
	last;
      }
    }

    return {ref => substr($refAllele, $lastMatchingIndex + 1), alt => substr($altAllele, $lastMatchingIndex + 1)}
      if ($lastMatchingIndex >= 0);

    return {ref => $refAllele, alt => $altAllele};


$$ LANGUAGE plperl;
