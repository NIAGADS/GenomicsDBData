## InsertTrackManhattan.pm
## $Id: InsertTrackManhattan.pm $
##

package NiagadsData::Load::Plugin::InsertTrackManhattan;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use GUS::PluginMgr::Plugin;
use Data::Dumper;

use GUS::Model::Study::ProtocolAppNode;
use GUS::Model::NIAGADS::TrackManhattan;

my $TRACK_SQL= <<TRACK_SQL;
SELECT protocol_app_node_id, source_id
FROM Study.ProtocolAppNode
WHERE source_id LIKE 'NG0%'
ORDER BY protocol_app_node_id DESC
TRACK_SQL

my $VERIFY_BIN_SQL= <<VERIFY_SQL;
SELECT bin_index IS NOT NULL AS has_bin_index From results.variantgwas where protocol_app_node_id = ? LIMIT 1
VERIFY_SQL

my $SERIES_SQL= <<SERIES_SQL;
SELECT json_agg(
jsonb_build_object(
'x', (? || '.' || split_part(metaseq_id, ':', 2))::numeric, 
'y', CASE WHEN r.neg_log10_pvalue > 50 THEN 50 ELSE r.neg_log10_pvalue END,
'pvalue', r.pvalue_display,
'chr', split_part(metaseq_id, ':', 1),
'position', split_part(metaseq_id, ':', 2), 
'variant', r.metaseq_id) ||
CASE WHEN source_id LIKE 'rs%' THEN jsonb_build_object('refsnp', source_id) ELSE '{}' END)::text AS series
FROM
Results.VariantGWAS r
WHERE protocol_app_node_id = ?
AND r.neg_log10_pvalue >= -1 * log(10, 0.01)
AND r.bin_index <@ ('chr' || ?)::ltree
SERIES_SQL


my @CHR = (1..22);
push(@CHR, ("X", "Y", "M"));

my @CHR_XAXIS = (1..25);


# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
  my $argumentDeclaration  =
    [
    stringArg({ name  => 'track',
                 descr => "track source_id; if not specified will iterate over all tracks",
                 constraintFunc => undef,
                 reqd           => 0,
                 isList         => 0 
	       }),
 stringArg({ name  => 'skip',
                 descr => "skip the following tracks",
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
  my $purposeBrief = 'Populates track manhattan series';

  my $purpose = 'Populates track manhattan series';

  my $tablesAffected = [];

  my $tablesDependedOn = [];

  my $howToRestart = '';

  my $failureCases = '';

  my $notes = <<NOTES;

Written by Emily Greenfest-Allen
Copyright Trustees of University of Pennsylvania 2020. 
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
		     cvsRevision => '$Revision: 11 $',
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

  if ($self->getArg('track')) {
    my $track = $self->getArg('track');
    my $protocolAppNodeId = $self->getProtocolAppNodeId($track);
    $self->insertTrackManhattan($protocolAppNodeId, $track);
  }
  else {
    my  %skipHash = undef;

    if ($self->getArg('skip')) {
      my @skip = split /,/, $self->getArg('skip');
      %skipHash = map { $_ => 1 } @skip;
      $self->log("Skipping the following tracks: @skip");
    }
    $self->loadTracks(\%skipHash);
  }

}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub loadTracks {
  my ($self, $skip) = @_;
  my $qh = $self->getQueryHandle()->prepare($TRACK_SQL);

  $qh->execute();
  while (my ($protocolAppNodeId, $track) = $qh->fetchrow_array()) {
    $self->log("Processing $track");
    if ($skip and exists $skip->{$track}) {
      $self->log("Skipping $track");
    }
    else {
      $self->insertTrackManhattan($protocolAppNodeId, $track);
    }
  }
  $qh->finish();
}


sub verifyBinnedData {
  my ($self, $protocolAppNodeId) = @_;
  my $qh = $self->getQueryHandle()->prepare($VERIFY_BIN_SQL);
  $qh->execute($protocolAppNodeId);
  my ($isBinned) = $qh->fetchrow_array();
  $qh->finish();
  return $isBinned;
}

sub insertTrackManhattan {
  my ($self, $protocolAppNodeId, $track) = @_;

  my $isBinned = $self->verifyBinnedData($protocolAppNodeId);

  if ($isBinned)  {
    my $qh = $self->getQueryHandle()->prepare($SERIES_SQL);
    foreach my $c (@CHR_XAXIS) {
      $self->log("Chr $c");
      $qh->execute($c, $protocolAppNodeId, $CHR[$c - 1]);
      while (my ($series) = $qh->fetchrow_array()) {
	if ($series) {
	  my $trackManhattan = GUS::Model::NIAGADS::TrackManhattan
	    ->new({track => $track,
		   chromosome => $CHR[$c - 1],
		   series => $series});
	  $trackManhattan->submit();
	}
	$self->undefPointerCache();
      }

      $qh->finish();
    }
  } 
  else {
    $self->log("Track $track is has not assigned bin_index. SKIPPING");
  }
}


# ----------------------------------------------------------------------
sub undoTables {
  my ($self) = @_;

  return ('NIAGADS.TrackManhattan');
}



1;
