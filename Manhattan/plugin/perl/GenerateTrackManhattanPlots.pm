## GenerateTrackManhattanPlots.pm
## $Id: GenerateTrackManhattanPlots.pm $
##

package GenomicsDBData::Manhattan::Plugin::GenerateTrackManhattanPlots;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use GUS::PluginMgr::Plugin;
use Data::Dumper;

use Package::Alias PluginUtils => 'GenomicsDBData::Load::PluginUtils';

my @PLOT_TYPES = qw(circular standard);
my @PLOT_FORMATS = qw(png pdf);

my $ANNOTATION_SQL= <<ANNOTATION_SQL;
SELECT hit, hit_type, 
CASE WHEN hit_type = 'gene' THEN gene_type ELSE 'variant' END AS hit_subtype,
hit_display_value,
chromosome, location_start, location_end,
neg_log10_pvalue AS peak_height, 
CASE WHEN neg_log10_pvalue >= -1 * log('5e-8') THEN 1
WHEN neg_log10_pvalue >= 3 THEN 2 ELSE 0 END AS is_significant,
ld_reference_variant AS variant, rank
FROM NIAGADS.DatasetTopFeatures 
WHERE track = ?
--AND CASE WHEN hit_type = 'gene' AND gene_type = 'protein coding' 
--THEN TRUE WHEN hit_type = 'variant' THEN TRUE ELSE FALSE END
ORDER BY rank
ANNOTATION_SQL
  
my $TRACK_ID_SQL = <<TRACK_ID_SQL;
SELECT pan.protocol_app_node_id, pan.source_id
FROM Study.StudyLink sl, Study.ProtocolAppNode pan
WHERE study_id = ?
AND sl.protocol_app_node_id = pan.protocol_app_node_id
TRACK_ID_SQL

my $SERIES_SQL= <<SERIES_SQL;
SELECT r.variant_record_primary_key, 
split_part(r.variant_record_primary_key, '_', 1) AS metaseq_id,
CASE WHEN split_part(r.variant_record_primary_key, '_', 2) = '' THEN NULL 
ELSE split_part(r.variant_record_primary_key, '_', 2) END AS ref_snp_id,
CASE WHEN split_part(r.variant_record_primary_key, '_', 2) != '' THEN split_part(r.variant_record_primary_key, '_', 2) 
ELSE truncate_str(split_part(r.variant_record_primary_key, '_', 1), 27) END AS "SNP",
r.neg_log10_pvalue,
CASE WHEN r.neg_log10_pvalue > ? THEN '1e-' || ?::text ELSE r.pvalue_display END AS "P",
CASE WHEN r.neg_log10_pvalue > -1 * log('5e-8') THEN 2 -- gws
WHEN r.neg_log10_pvalue > 5 THEN 1 -- relaxed
ELSE 0 END  -- nope
AS genome_wide_significance_level,
split_part(r.variant_record_primary_key, ':',1)::text AS "CHR",
split_part(r.variant_record_primary_key, ':',2)::bigint AS "BP"
FROM Results.VariantGWAS r
WHERE r.protocol_app_node_id = ?
AND neg_log10_pvalue > -1 * log(0.5)
AND bin_index <@ ('chr' || ?::text)::ltree
SERIES_SQL


my @CHR = (1..22);
push(@CHR, ("X", "Y", "M"));


# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
  my $argumentDeclaration  =
    [
    stringArg({ name  => 'studyId',
                 descr => 'source id for the study',
                 constraintFunc => undef,
                 reqd           => 1,
                 isList         => 0 
	      }),

     integerArg({ name  => 'cap',
                 descr => 'cap -log10 pvalue',
                 constraintFunc => undef,
                 reqd           => 0,
		  isList         => 0,
		  default => 40,
	      }),

     stringArg({ name  => 'preprocessDir',
                 descr => "preprocess directory; must exist",
                 constraintFunc => undef,
                 reqd           => 1,
                 isList         => 0 
	       }),

    

     booleanArg({ name  => 'extractData',
                 descr => "extract data",
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
		}),

      booleanArg({ name  => 'generatePlots',
                 descr => "generates plot; expects data in preprocessDir",
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
		 }),

      booleanArg({ name  => 'overwrite',
                 descr => "overwrite existing files; otherwise will work with what is present",
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
  my $purposeBrief = 'generates  track manhattan plots';

  my $purpose = 'generates track manhattan plots';

  my $tablesAffected = [];

  my $tablesDependedOn = [];

  my $howToRestart = '';

  my $failureCases = '';

  my $notes = <<NOTES;
DEPENDS ON MATERIALIZED VIEW: NIAGADS.DatasetTopFeatures. Must be refreshed if study is recently loaded before generating plots.

Written by Emily Greenfest-Allen
Copyright Trustees of University of Pennsylvania 2021. 
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
		     cvsRevision => '$Revision: 7 $',
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

  $self->{study_id} = PluginUtils::getStudyId($self, $self->getArg('studyId'));
  $self->createPreprocessDir();

  my $tracks = $self->getTrackIds();

  foreach my $track (keys %$tracks) {
    my $protocolAppNodeId = $tracks->{$track};
    $self->log("Processing Track: $track");
    $self->extractData($protocolAppNodeId, $track) if ($self->getArg('extractData'));
    $self->generatePlots($track) if ($self->getArg('generatePlots'));
  }

}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub generatePlots {
  my ($self, $track) = @_;
  $self->log("Generating plots for $track");
  
  my $targetDir = $self->{preprocess_directory};
  PluginUtils::createDirectory($self, $targetDir, "png");
  PluginUtils::createDirectory($self, $targetDir, "pdf");
  my @cmd = ('generateManhattanPlots.R',
	     $track,
	     $targetDir);

  $self->log("CMD: " . join(' ', @cmd));

  qx(@cmd);
  my $fail = $?;
  $self->error("Generating plots failed") if ($fail > 0);
}

sub getTrackIds {
  my ($self) = @_;
  my $qh = $self->getQueryHandle()->prepare($TRACK_ID_SQL);
  $qh->execute($self->{study_id});
  my $tracks = {};
  while (my ($protocolAppNodeId, $sourceId) = $qh->fetchrow_array()) {
    $tracks->{$sourceId} = $protocolAppNodeId;
  }
  $qh->finish();
  return $tracks;
}

sub createPreprocessDir {
  my ($self) = @_;
  $self->error("Preprocess directory: ". $self->getArg('preprocessDir') . " does not exist.")
    if (!PluginUtils::fileExists($self, $self->getArg('preprocessDir')));

  $self->{preprocess_directory} = PluginUtils::createDirectory($self, $self->getArg('preprocessDir'), $self->getArg('studyId'));
}

sub extractData {
  my ($self, $protocolAppNodeId, $track) = @_;

  $self->getTrackData($protocolAppNodeId, $track);
  $self->getAnnotationData($track);
}

sub getTrackData {
  my ($self, $protocolAppNodeId, $track) = @_;

  my $trackFile = $self->{preprocess_directory} . '/' . $track . '-track.txt';
  my $overwrite = $self->getArg('overwrite');
  my $fileExists = PluginUtils::fileExists($self, $trackFile);

  $self->log("$trackFile already exists") if $fileExists;
  $self->log("Overwriting") if ($fileExists and $overwrite);
  
  if ($overwrite or !$fileExists) {  
    $self->log("Extracting track data and writing to $trackFile");
    open (my $ofh, '>', $trackFile) || die "Can't create $trackFile.  Reason: $!\n";

    my @header = qw(variant_record_primary_key metaseq_id ref_snp_id SNP neg_log10_pvalue P genome_wide_significance_level CHR BP);
    print $ofh join("\t", @header) . "\n";
    my $cap = $self->getArg('cap');
    my $qh = $self->getQueryHandle()->prepare($SERIES_SQL);
    foreach my $chr (@CHR) {
      $self->log("Extracting $track / chr$chr");
      $qh->execute($cap, $cap, $protocolAppNodeId, $chr);
      while (my @result = $qh->fetchrow_array()) {
	print $ofh join("\t", @result) . "\n";
      }
    }
    $qh->finish();
  }
}


sub getAnnotationData {
  my ($self, $track) = @_;

  my $annotationFile = $self->{preprocess_directory} . '/' . $track . '-annotation.txt';
  my $overwrite = $self->getArg('overwrite');
  my $fileExists = PluginUtils::fileExists($self, $annotationFile);

  $self->log("$annotationFile already exists") if $fileExists;
  $self->log("Overwriting") if ($fileExists and $overwrite);
  
  if ($overwrite or !$fileExists) {
    $self->log("Extracting track data and writing to $annotationFile");
    open (my $ofh, '>', $annotationFile) || die "Can't create $annotationFile.  Reason: $!\n";

    my @header = qw(hit hit_type hit_subtype hit_display_value chromosome location_start location_end peak_height is_significant variant rank);
    print $ofh join("\t", @header) . "\n";

    my $qh = $self->getQueryHandle()->prepare($ANNOTATION_SQL);
    $self->log("Extracting $track annotation");
    $qh->execute($track);
    my $annotationCount = 0;
    while (my @result = $qh->fetchrow_array()) {
      print $ofh join("\t", @result) . "\n";
    }
    $qh->finish();
  }
}






# ----------------------------------------------------------------------




1;
