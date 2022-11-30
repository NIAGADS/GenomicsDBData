# InsertCBILGoAssociation.pm
## $Id: InsertCBILGoAssociation.pm

package GenomicsDBData::Load::Plugin::InsertCBILGoAssociation;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use JSON::XS;
use IO::Zlib;
use Data::Dumper;

use GUS::PluginMgr::Plugin;

use GUS::Model::CBIL::GoAssociation;
use GUS::Model::SRes::OntologyTerm;


my %ECO_2_GO = (
              "ECO:0000203" =>    "IEA",
              "ECO:0000323" =>  "IEA",
              "ECO:0000323" =>  "IEA",
              "ECO:0000322" =>  "IEA",
              "ECO:0000322" =>  "IEA",
              "ECO:0000265" =>  "IEA",
              "ECO:0000256" =>  "IEA",
              "ECO:0000265" =>  "IEA",
              "ECO:0000203" =>  "IEA",
              "ECO:0000203" =>  "IEA",
              "ECO:0000265" =>  "IEA",
              "ECO:0000265" =>  "IEA",
              "ECO:0000203" =>  "IEA",
              "ECO:0000307" =>  "ND",
              "ECO:0000269" =>  "EXP",
              "ECO:0000314" =>  "IDA",
              "ECO:0000315" =>  "IMP",
              "ECO:0000316" =>  "IGI",
              "ECO:0000270" =>  "IEP",
              "ECO:0000021" =>  "IPI",
              "ECO:0000304" =>  "TAS",
              "ECO:0000303" =>  "NAS",
              "ECO:0000305" =>  "IC",
              "ECO:0000031" =>  "ISS",
              "ECO:0000255" =>  "ISS",
              "ECO:0000031" =>  "ISS",
              "ECO:0000031" =>  "ISS",
              "ECO:0000250" =>  "ISS",
              "ECO:0000266" =>  "ISO",
              "ECO:0000247" =>  "ISA",
              "ECO:0000255" =>  "ISM",
              "ECO:0000084" =>  "IGC",
              "ECO:0000317" =>  "IGC",
              "ECO:0000318" =>  "IBA",
              "ECO:0000319" =>  "IBD",
              "ECO:0000320" =>  "IKR",
              "ECO:0000321" =>  "IRD",
              "ECO:0000245" =>  "RCA",
              "ECO:0000320" =>  "IMR",
              "ECO:0000501" =>  "IEA",
              "ECO:0000353" =>  "IPI",
               "ECO:0007005" => "HDA",
              "ECO:0007007" => "HEP",
                "ECO:0007001" => "HMP"
);

# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
  my $argumentDeclaration  =
    [
     fileArg({name => 'annotationFile',
          descr => 'pathname for the annotation file',
          constraintFunc => undef,
          reqd => 1,
          isList => 0,
          mustExist => 1,
          format => 'gpa (may be gzipped)'
             }),

     fileArg({name => 'entityMetadataFile',
          descr => 'pathname for the entity metadata file (containing uniprot -> hgnc mapping)',
          constraintFunc => undef,
          reqd => 1,
          isList => 0,
          mustExist => 1,
          format => 'gpi (may be gzipped)'
             }),

     stringArg({ name  => 'extDbRlsSpec',
                 descr => "The ExternalDBRelease specifier for the go association file. Must be in the format 'name|version', where the name must match a name in SRes::ExternalDatabase and the version must match an associated version in SRes::ExternalDatabaseRelease.",
                 constraintFunc => undef,
                 reqd           => 1,
                 isList         => 0
               }),

     stringArg({ name  => 'goExtDbRlsSpec',
                 descr => "The ExternalDBRelease specifier for the Gene Ontology. Must be in the format 'name|version', where the name must match a name in SRes::ExternalDatabase and the version must match an associated version in SRes::ExternalDatabaseRelease.",
                 constraintFunc => undef,
                 reqd           => 1,
                 isList         => 0
               }),

     booleanArg({ name  => 'failOnMissingHgncId',
                  descr => "fail if mapped HgncId is not in DB; otherwise just warns",
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
  my $purposeBrief = 'Loads GO Gene Annotation from UniProt-GOA GPAD (gpa extension) file';

  my $purpose = 'Loads GO Gene Annotation from UniProt-GOA GPAD (gpa extension) file';

  my $tablesAffected = [['CBIL::GOAssociation', 'enter a row for each annotation']];

  my $tablesDependedOn = [['SRes::DBRef', 'uniprot -> hgnc -> gene_id mapping']];

  my $howToRestart = '';

  my $failureCases = '';

  my $notes = <<NOTES;
Written by Emily Greenfest-Allen
Copyright Trustees of University of Pennsylvania 2019.
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
                     cvsRevision => '$Revision: 20 $',
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

  $self->{external_database_release_id} = $self->getExtDbRlsId($self->getArg('extDbRlsSpec'));
  $self->{go_external_database_release_id} = $self->getExtDbRlsId($self->getArg('goExtDbRlsSpec'));
  $self->parseEntitites();
  $self->parseAnnotations();
  $self->loadAnnotation();
}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub loadAnnotation {
  my ($self) = @_;

  $self->log("Loading Annotations");
  my $count = 0;
  my $skipCount = 0;
  foreach my $key (keys %{$self->{annotations}}) {
    my ($uniProtId, $goTerm) = split /_/, $key;
    if (!exists $self->{entities}->{$uniProtId}) { # did not map to hgnc
      $skipCount++;
      next;
    }
    $goTerm =~ s/:/_/;
    my $goTermId = $self->getGoOntologyTermId($goTerm);
    my @genes = @{$self->{entities}->{$uniProtId}};
    my $evidence = $self->{annotations}->{$key};

    foreach my $geneId (@genes) {
      my $association = GUS::Model::CBIL::GoAssociation
        ->new({external_database_release_id => $self->{external_database_release_id},
               gene_id => $geneId,
               go_term_id => $goTermId,
               evidence => to_json $evidence
              });
      $association->submit() unless $association->retrieveFromDB();
      $self->log("Loaded $count annotations.") if (++$count % 50000 == 0);
    }

    $self->undefPointerCache();
  }
  $self->log("Done. Skipped $skipCount rows.");
}

sub parseEntitites {
  my ($self) = @_;

  my $file = $self->getArg('entityMetadataFile');

  my $fh = undef;
  if ($file =~ m/\.gz$/) {
    $self->log("Opening gzipped entity file.");
    open($fh, "zcat $file |")  || $self->error("Can't open gzipped $file.");
    $self->log("Done opening file.");
  }
  else {
    open ($fh, $file) || $self->error("Can't open $file.");
  }

  $self->{entities} = {};
  my $numMapped = 0;
  while(<$fh>) {
    chomp;
    next if /^!/;

    my @values = split /\t/;
    my $uniProtId = $values[1]; # entityDb, entity
    my @hgncIds = split /\|/, $values[8];
    my @genes = ();
    foreach my $id (@hgncIds) {
      my $geneId = $self->hgnc2geneLookup($id);

      if ($geneId) {
        push(@genes, $geneId);
        ++$numMapped;
      }
      else {
        $self->error("HGNC ID: $id for UniProtKB: $uniProtId not found in DB") if $self->getArg('failOnMissingHgncId');
        # $self->log("HGNC ID: $id for UniProtKB: $uniProtId not found in DB") if $self->getArg('veryVerbose');
      }
    }

    $self->{entities}->{$uniProtId} =  \@genes if (scalar @genes >= 1);

  }

  $fh->close();
  $self->log("Found $numMapped UniProtKB -> HGNC -> DB mappings");
}


sub parseAnnotations {
  my ($self) = @_;

  my $file = $self->getArg('annotationFile');

  my $fh = undef;
  if ($file =~ m/\.gz$/) {
    $self->log("Opening gzipped annotation file.");
    open($fh, "zcat $file |")  || $self->error("Can't open gzipped $file.");
    $self->log("Done opening file.");
  }
  else {
    open ($fh, $file) || $self->error("Can't open $file.");
  }

  $self->{annotations} = {};

  $self->log("Parsing Annotations");
  my $count = 0;
  while (<$fh>) {
    chomp;
    next if /^!/;

    my ($entityDb, $uniProtId, $qualifier, $goId, $citation, $evidenceCode, $evidenceCodeQualifier, $iteractingTaxon, $lastUpdate, $annotationSource, $crossReferenceAxioms, $internalProps)  =  split /\t/;

    my $key = $uniProtId . "_" . $goId;
    my @evidence = (exists $self->{annotations}->{$key}) ? @{$self->{annotations}->{$key}} : ();
    my $newEvidence = {citation => $citation,
                       evidence_code => $evidenceCode,
                       qualifier => $qualifier,
                       evidence_code_qualifier => $evidenceCodeQualifier,
                       annotation_source => $annotationSource,
                       axioms => $crossReferenceAxioms,
                       go_evidence_code => $self->mapGoEvidenceCodes($evidenceCode)
                      };

    # remove empty elements
    foreach (keys %$newEvidence) {
      delete $newEvidence->{$_} unless (defined $newEvidence->{$_} and length($newEvidence->{$_}) > 1);
    }
    push (@evidence, $newEvidence);
    $self->{annotations}->{$key} = \@evidence;
    $count++;
  }
  $fh->close();
  $self->log("Parsed annotations for $count gene-go associations.");
  $self->log(Dumper($self->{annotations})) if $self->getArg('veryVerbose');
}


# ----------------------------------------------------------------------
# supporting methods
# ----------------------------------------------------------------------


sub mapGoEvidenceCodes {
  my ($self, $ecoCode) = @_;

  $self->error("$ecoCode not found in mapping to GO ECs")
    if (!exists $ECO_2_GO{$ecoCode});

  return $ECO_2_GO{$ecoCode};

}

sub hgnc2geneLookup {
  my ($self, $hgncId) = @_;

  my $sql = <<SQL;
SELECT primary_identifier FROM SRes.DBRef WHERE remark @> '{"hgnc_id" : "$hgncId"}'
SQL

  my $qh = $self->getQueryHandle()->prepare($sql);
  $qh->execute();
  my ($geneId) = $qh->fetchrow_array();
  $qh->finish();

  return $geneId;
}

sub getGoOntologyTermId {
  my ($self, $value) = @_;

  my $ontologyTerm = GUS::Model::SRes::OntologyTerm
    ->new({source_id => $value,
           external_database_release_id => $self->{go_external_database_release_id}});

  $self->error("GO Term $value not found in SRes.OntologyTerm")
    unless ($ontologyTerm->retrieveFromDB());

  return $ontologyTerm->getOntologyTermId();
}

# ----------------------------------------------------------------------
sub undoTables {
  my ($self) = @_;

  return ('CBIL.GoAssociation');
}



1;
