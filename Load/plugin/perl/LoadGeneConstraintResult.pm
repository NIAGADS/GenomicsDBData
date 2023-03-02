## LoadGeneConstraintResult Plugin
## $Id: LoadGeneConstraintResult.pm $

package GenomicsDBData::Load::Plugin::LoadGeneConstraintResult;
@ISA = qw(GUS::PluginMgr::Plugin);

use GUS::PluginMgr::Plugin;
use Data::Dumper;
use JSON::XS;
use Scalar::Util qw(looks_like_number);
use POSIX        qw(strftime);

use File::Slurp;

use Package::Alias Utils => 'GenomicsDBData::Load::Utils';

use GUS::Model::Results::GeneConstraint;
use GUS::Model::DoTS::Gene;
use GUS::Model::DoTS::Transcript;

# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
    my $argumentDeclaration = [

        stringArg(
            {
                name           => 'file',
                descr          => 'full path to input file',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0,
            }
        ),

    ];
    return $argumentDeclaration;
}

# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
    my $purposeBrief =
      'Loads gnomAD Gene Constraint results into Results.GeneConstraint';

    my $purpose =
      'Loads gnomAD Gene Constraint results into Results.GeneConstraint';

    my $tablesAffected =
      [ [ 'Results::GeneConstraint', 'Enters a row for gene-transcript pair' ]
      ];

    my $tablesDependedOn = [ [ 'DOTS::Gene', 'DOTS::Transcript' ] ];

    my $howToRestart = '';

    my $failureCases = '';

    my $notes = <<NOTES;
TODO: support characteristics

Written by Emily Greenfest-Allen
Copyright Trustees of University of Pennsylvania 2023. 
NOTES

    my $documentation = {
        purpose          => $purpose,
        purposeBrief     => $purposeBrief,
        tablesAffected   => $tablesAffected,
        tablesDependedOn => $tablesDependedOn,
        howToRestart     => $howToRestart,
        failureCases     => $failureCases,
        notes            => $notes
    };

    return $documentation;
}

# ----------------------------------------------------------------------
# create and initalize new plugin instance.
# ----------------------------------------------------------------------

sub new {
    my ($class) = @_;
    my $self = {};
    bless( $self, $class );

    my $documentation       = &getDocumentation();
    my $argumentDeclaration = &getArgumentsDeclaration();

    $self->initialize(
        {
            requiredDbVersion => 4.0,
            cvsRevision       => '$Revision$',
            name              => ref($self),
            revisionNotes     => '',
            argsDeclaration   => $argumentDeclaration,
            documentation     => $documentation
        }
    );
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

    $self->load();
}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

# expected fields
# gene    -- gene symbol -- DROP
# transcript -- ensembl transcript id; map & DROP
# ... many scores
# transcript_type -- DROP; in DoTS.Transcript
# gene_id -- ensembl gene id; map & DROP
# transcript_level -- could calculate but KEEP in scores
# cds_length -- could calculate but KEEP in scores
# num_coding_exons -- could calculate but KEEP in scores
# gene_type -- DROP; in DoTS.Gene
# gene_length -- DROP
# ... more scores
# chromosome -- DROP
# start_position  -- DROP
# end_position --DROP

sub load {
    my ($self) = @_;

    my $file = $self->getArg('file');
    open( my $fh, $file ) || $self->error("Unable to open $file");

    # get indexes of field names
    my $header = <$fh>;
    chomp($header);
    my @fields = split /\t/, $header;

    $self->log("Processing $file");
    my $lineCount = 0;
    my %row;
    while (<$fh>) {
        chomp;
        my @values = split /\t/;
        @row{@fields} = @values;

        # get the GENE_ID
        my $geneId = $self->getGeneId( $row{gene_id} );

        # get the TRANSCRIPT_ID (NA_FEATURE_ID)
        my $transcriptId = $self->getTranscriptId( $row{transcript} );

        # remove unnecessary fields
        my $scores = $self->buildJSON( \%row );

        my $geneConstraint = GUS::Model::Results::GeneConstraint->new(
            {
                gene_id       => $geneId,
                transcript_id => $transcriptId,
                scores        => $scores
            }
        );

        if ( ++$lineCount % 5000 == 0 ) {
            $self->log("INSERTED $lineCount records.");
            $self->undefPointerCache();
        }
    }
    $fh->close();
    $self->log("DONE. INSERTED $lineCount records.");
    $self->undefPointerCache();
}

sub buildScoreJSON {
    my ( $self, $row ) = @_;
    my @droppedFields =
      qw(gene transcript transcript_type gene_id gene_type gene_length chromosome start_position end_position);

    $self->log("DEBUG: raw row - ". Dumper($row));
    foreach my $f (@droppedFields) {
        delete $row->{$f};
    }

    foreach my $field ( keys %$row ) {
        if ( looks_like_number( $row{$field} ) ) {
            $row{$field} = 1.0 * $row{$field};
        }
    }

    $self->log( "DEBUG: processed row - " . Dumper($row) );
    $self->error("DEBUG: json row - " . Utils::to_json($row, 1));
    return Utils::to_json($row);

}

sub getGeneId {
    my ( $self, $ensemblId ) = @_;
    my $gene = GUS::Model::DoTS::Gene->new( { source_id => $ensemblId } );
    unless ( $gene->retrieveFromDB() ) {
        $self->error("Unable to map gene $ensemblId");
    }
    return $gene->getGeneId();
}

sub getTranscriptId {
    my ( $self, $ensemblId ) = @_;
    my $transcript =
      GUS::Model::DoTS::Transcript->new( { source_id => $ensemblId } );
    unless ( $transcript->retrieveFromDB() ) {
        $self->error("Unable to map transcript $ensemblId");
    }
    return $transcript->getNaFeatureId();
}

# ----------------------------------------------------------------------
sub undoTables {
    my ($self) = @_;
    my @tables = qw(Results.FeatureScore);
    return @tables;
}

1;
