## LoadDataDictionary.pm
## $Id: LoadDataDictionary.pm $
##

package GenomicsDBData::Load::Plugin::LoadDataDictionary;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use GUS::PluginMgr::Plugin;
use Data::Dumper;
use JSON::XS;
use GenomicsDBData::Load::Utils;

use GUS::Model::NIAGADS::DataDictionary;
use GUS::Model::SRes::OntologyTerm;

# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
    my $argumentDeclaration = [

        stringArg(
            {
                name           => 'file',
                descr          => "full path to data dictionary file",
                constraintFunc => undef,
                reqd           => 1,
                isList         => 0
            }
        ),
        booleanArg(
            {
                name  => 'checkSpaces',
                descr =>
'for DEBUGING invlaid ontology terms, logs presence of extra white space',
                constraintFunc => undef,
                reqd           => 0
            }
        ),
        booleanArg(
            {
                name  => 'initialLoad',
                descr => 'will die on duplicates instead of trying to update',
                constraintFunc => undef,
                reqd           => 0
            }
        )

    ];
    return $argumentDeclaration;
}

# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
    my $purposeBrief = 'Loads data dictionary';

    my $purpose = 'Insert or update terms';

    my $tablesAffected =
      [ [ 'NIAGADS::DataDictionary', 'Enters a row for each term' ] ];

    my $tablesDependedOn =
      [ [ 'SRes::OntologyTerm', 'For setting mapping type/subtype' ] ];

    my $howToRestart = '';

    my $failureCases = '';

    my $notes = <<NOTES;
Expected input: tab delimited w/fields:
term    ontology_term_id        is_a    display_value   synonyms        units   PHC_Code

Written by Emily Greenfest-Allen
Copyright Trustees of University of Pennsylvania 2019.
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
            cvsRevision       => '$Revision: 2$',
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

sub load {
    my ($self) = @_;

    my $file = $self->getArg('file');

    open( my $fh, $file )
      || $self->error("Unable to open $file for reading");

    my $header = <$fh>;
    chomp($header);
    my @fields = split '\t', $header;
    $_ = lc for @fields;    # convert to lowercase

    my %row;
    my $termCount = 0;
    while ( my $line = <$fh> ) {
        chomp($line);
        @row{@fields} = split /\t/, $line;

        $self->log("DEBUG: $line") if ( $self->getArg('veryVerbose') );

        my $ontologyTermId =
          $self->validateOntologyTerm( $row{term}, $row{ontology_term_id} );

        my $isaOntologyTermId =
          $row{is_a} ? $self->getOntologyTermId( $row{is_a} ) : undef;

        my $ddObj = GUS::Model::NIAGADS::DataDictionary->new(
            {
                ontology_term_id => $ontologyTermId
            }
        );

        if ( $ddObj->retrieveFromDB() ) {    # if exists -> update or warn
            if ( $self->getArg('initialLoad') ) {
                $self->error("ERROR: Found duplicate term: $line");
            }
            else {
                $self->log("INFO: Found existing term; updating");
                $self->updateEntry( $ddObj, \%row, $ontologyTermId, $isaOntologyTermId );
            }
        }
        else {                               # otherwise insert
            $ddObj->setIsaOntologyTermId($isaOntologyTermId)
              if ($isaOntologyTermId);
            $ddObj->setAnnotation( GenomicsDBData::Load::Utils::to_json({units => $row{units}} )) if ( $row{units} );
            $ddObj->setDisplayValue( $row{display_value} )
              if ( $row{display_value} );
            $ddObj->setSynonyms( $row{synonyms} ) if ( $row{synonyms} );
            $ddObj->setPhcCode( $row{phc_code} )  if ( $row{phc_code} );
            $ddObj->submit();
        }

        if ( ++$termCount % 50 == 0 ) {
            $self->log("INFO: processed $termCount dictionary terms");
            $self->undefPointerCache();
        }

    }

    $fh->close();

}

# ----------------------------------------------------------------------
# supporting methods
# ----------------------------------------------------------------------

sub updateEntry {
    my ( $self, $entry, $row, $ontologyTermId, $isaOntologyTermId ) = @_;

    my @refFields = qw('units display_value synonyms phc_code');

    my @updates;

    if ($isaOntologyTermId) {
        push( @updates, "isa_ontology_term_id = $isaOntologyTermId" );
    }

    foreach my $rf (@refFields) {
        if ( $row->{$rf} ) {
          if ($rf eq "units") {
            $self->error("ERROR: Units update not yet implemented; involves JSONB update");
          }
          push( @updates, "$rf = '" . $row->{$rf} . "'" );
        }
    }

    my $sql =
        "UPDATE NIAGADS.DataDictionary SET "
      . join( " ", @updates )
      . " WHERE dd_term_id = ?";

    $self->error("DEBUG (first time): update SQL = $sql");

    my $qh = $self->getQueryHandle()->prepare($sql);
    $qh->execute( $entry->getDdTermId() ) || die $self->error(DBI::errstr);
    $qh->finish();
}

sub validateOntologyTerm {
    my ( $self, $term, $termId ) = @_;

    $termId =~ s/:/_/g;

    $self->log("DEBUG-spaces - term----$term----$termId-----")
      if ( $self->getArg('checkSpaces') );

    my $sql =
"SELECT ontology_term_id FROM SRes.OntologyTerm WHERE lower(name) = ? and source_id = ?";

    my $qh = $self->getQueryHandle()->prepare($sql);
    $qh->execute( lc($term), $termId );
    my ($ontologyTermId) = $qh->fetchrow_array();
    $qh->finish();

    if ( !$ontologyTermId && $term =~ m/^APOE/ )
    {    # quick fix for unicode character issue
        $self->log(
            "WARNING: APOE allele term not found ($term), looking up term_id");
        $qh =
          $self->getQueryHandle()
          ->prepare(
"SELECT name, ontology_term_id FROM Sres.OntologyTerm WHERE source_id = ?"
          );
        $qh->execute($termId) || $self->error(DBI::errstr);
        my $dbTerm;
        ( $dbTerm, $ontologyTermId ) = $qh->fetchrow_array();
        $qh->finish();

        $self->log(
"INFO: Matching APOE term found $term / $termId => $dbTerm / $ontologyTermId"
        ) if ($ontologyTermId);
    }

    $self->error("Ontology Term $term / $termId not found in DB.")
      if ( !$ontologyTermId );
    return $ontologyTermId;
}

sub getOntologyTermId {
    my ( $self, $term ) = @_;

    # returning name and source_id for debugging purposes
    my $sql =
"SELECT ontology_term_id, name, source_id FROM SRes.OntologyTerm WHERE lower(name) = ?";

    my $qh = $self->getQueryHandle()->prepare($sql);
    $qh->execute( lc($term) ) || $self->error(DBI::errstr);
    my ( $ontologyTermId, $name, $sourceId ) = $qh->fetchrow_array();
    $qh->finish();
    $self->error("Term $term not found in SRes.OntologyTerm")
      if ( !$ontologyTermId );

    return $ontologyTermId;
}

# ----------------------------------------------------------------------
sub undoTables {
    my ($self) = @_;

    return ('NIAGADS.DataDictionary');
}

1;
