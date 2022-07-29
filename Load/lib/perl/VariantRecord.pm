# utility functions for generating looking up variants against the database

package GenomicsDBData::Load::VariantRecord;

use strict;

use Data::Dumper;
use JSON::XS;
use DBD::Pg;

use GenomicsDBData::Load::Utils qw(truncateStr);
use GenomicsDBData::Load::VariantAnnotator qw(isNull);

my $LOOKUP_SQL="SELECT * from get_variant_primary_keys_and_annotations(?, ?)";


# metaseq_id, ref_snp_id, genomicsdbannotation, grch37, grch38

# my $POSITION_SQL = "SELECT * FROM find_variant_by_position(?,?)";

sub new {
  my ($class, $args) = @_;
  my $plugin = $args->{plugin};
  my $self = { plugin => $args->{plugin},
	       genome_build => $args->{genome_build},
	       gus_config_file => $args->{gus_config_file}
	     };

  bless $self, $class;
  $self->connect();
  $self->{lookup_qh} = $self->{dbh}->prepare($LOOKUP_SQL) || $self->{plugin}->error(DBI::errstr);
  $self->{first_value_only} = 0;
  $self->{allow_allele_mismatches} = 0;
  return $self;
}

sub DESTROY {
  my ($self) = @_;
  $self->{lookup_qh}->finish();
  $self->disconnect();
}

sub disconnect {
  my ($self) = @_;
  $self->{dbh}->disconnect();
}

sub setAllowAlleleMismatces {
  my ($self, $allow) = @_;
  $self->{allow_allele_mismatches} = $allow;
}

sub setFirstValueOnly {
  my ($self, $fvOnly) = @_;
  $self->{first_value_only} = $fvOnly;
}

sub connect {
  my ($self, $gusConfigFile) = @_;

  if ($gusConfigFile) {
    $self->{gus_config_file} = $gusConfigFile;
  }
  else {
    $gusConfigFile = $self->{gus_config_file};
  }

  my $gusConfig = GUS::Supported::GusConfig->new($gusConfigFile);

  my $dbh  = DBI->connect($gusConfig->getDbiDsn(),
			  $gusConfig->getDatabaseLogin(),
			  $gusConfig->getDatabasePassword(),
			  {AutoCommit => 0}) || $self->{plugin}->error(DBI::errstr);
  $self->{dbh} = $dbh;
}


sub getSnvDeletion {
  my ($self, $chromosome, $position) = @_;

  my $lookupField = ($self->{genome_build} eq 'GRCh37') ? 'source_id' : 'chromosome';

  my $sql = "SELECT SUBSTRING(sequence, ?, 2) FROM DOTs.ExternalNASequence WHERE $lookupField  = ?";
  my $qh = $self->{dbh}->prepare($sql) || $self->{plugin}->error(DBI::errstr);
  $qh->execute($position, $chromosome);
  my ($alleleStr) = $qh->fetchrow_array();
  $qh->finish();
  return ($alleleStr, substr $alleleStr, -1);
}



sub isValidMetaseqId {
  my ($self, $metaseqId) = @_;

  my ($chr, $pos, $ref, $alt) = split /:/, $metaseqId;

  return 0 if (($metaseqId =~ m/\?/) or !$ref or !$alt or (!($ref =~ m/A|T|C|G/)) or (!($alt =~ m/A|T|C|G/)));
  return 1;
}



sub lookup {
  my ($self, @variants) = @_;
  # $self->{plugin}->log(join(',', @variants));

  $self->{lookup_qh}->execute(join(',', @variants), $self->{first_value_only}) || $self->{plugin}->error(DBI::errstr . "/" . Dumper(\@variants));
  
  my ($result) = $self->{lookup_qh}->fetchrow_array();
  my $json = JSON::XS->new();
  return $json->decode($result);

  # "1:1510801:C:T": {
  #   "bin_index": "chr1.L1.B1.L2.B1.L3.B1.L4.B1.L5.B1.L6.B1.L7.B2.L8.B2.L9.B1.L10.B1.L11.B1.L12.B1.L13.B1",
  #   "annotation": {
  #     "GenomicsDB": [
  #       "ADSP_WGS",
  #       "NG00027_STAGE1"
  #     ],
  #     "mapped_coordinates": null
  #   },
  #   "match_rank": 1,
  #   "match_type": "exact",
  #   "metaseq_id": "1:1510801:C:T",
  #   "ref_snp_id": "rs7519837",
  #   "is_adsp_variant": true,
  #   "record_primary_key": "1:1510801:C:T_rs7519837"
  # },
}
