
CREATE EXTENSION IF NOT EXISTS plperl;


CREATE OR REPLACE FUNCTION reverse_complement (TEXT) 
RETURNS TEXT AS $$
    my ($alleleStr) = @_;
    my ($refAllele, $altAllele) = split /:/, $alleleStr;
    $refAllele =~ tr/ACGTacgt/TGCAtgca/;
    $altAllele =~ tr/ACGTacgt/TGCAtgca/;

    $refAllele = reverse $refAllele;
    $altAllele = reverse $altAllele;

    return join(':', $refAllele, $altAllele)
$$ LANGUAGE plperl;
