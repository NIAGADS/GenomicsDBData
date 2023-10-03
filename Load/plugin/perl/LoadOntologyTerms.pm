# LoadOntologyTerms.pm
## $Id: LoadOntologyTerms.pm

package GenomicsDBData::Load::Plugin::LoadOntologyTerms;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use JSON::XS;
use IO::Zlib;
use Data::Dumper;

use GUS::PluginMgr::Plugin;

use GUS::Model::SRes::OntologyTerm;
use GUS::Model::SRes::OntologyRelationship;
use GUS::Model::SRes::OntologySynonym;

BEGIN { $Package::Alias::BRAVE = 1 }
use Package::Alias Utils            => 'GenomicsDBData::Load::Utils';
use Package::Alias PluginUtils      => 'GenomicsDBData::Load::PluginUtils';

# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
    my $argumentDeclaration  = [
    stringArg({ descr => 'Ontology external database release specification',
            name  => 'extDbRlsSpec',
            isList    => 0,
            reqd  => 1,
            constraintFunc => undef,
        }),

    stringArg({ descr => 'url of the OWL file',
            name  => 'owlFileUrl',
            isList    => 0,
            reqd  => 1,
            constraintFunc => undef,
        }),

    stringArg({ descr => 'path for saving parsed OWL file excerpts; must exist',
        name  => 'outputPath',
        isList    => 0,
        reqd  => 1,
        constraintFunc => undef,
    }),

    stringArg({ descr => 'preferred namespace; will synonymize same term if already in DB from other namespace',
        name  => 'namespace',
        isList    => 0,
        reqd  => 0,
        constraintFunc => undef,
    }),

    integerArg({ name  => 'numWorkers',
                descr => 'number of workers for parallel processing; defaults to number of processors',
                constraintFunc => undef,
                isList         => 0,
                reqd => 0
    }),

    booleanArg({ name  => 'skipParsing',
            descr => 'skip parsing (e.g., for resume)',
            constraintFunc => undef,
            isList         => 0,
            reqd => 0
    }),

    ];

    return $argumentDeclaration;
}


# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
    my $purposeBrief = 'Loads ontology terms, synonyms, and relationships from an OWL file';

    my $purpose = 'Loads ontology terms, synonyms, and relationships from an OWL file';

    my $tablesAffected = [['SRes::OntologyTerm', 'enter a row for or update each term'],
                            ['SRes::OntologySynonym', 'enter a row for each synonym'],
                            ['SRes::OntologyRelationship', 'enter a row for each relation']];

    my $tablesDependedOn = [];

    my $howToRestart = '';

    my $failureCases = '';

    my $notes = <<NOTES;
    Written by Emily Greenfest-Allen
    Copyright Trustees of University of Pennsylvania 2023.
NOTES

    my $documentation = {purpose=>$purpose, purposeBrief=>$purposeBrief, 
        tablesAffected=>$tablesAffected, tablesDependedOn=>$tablesDependedOn, 
        howToRestart=>$howToRestart, failureCases=>$failureCases, notes=>$notes};

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
        cvsRevision => '$Revision: 2 $',
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

    # my $extDbRlsId = $self->getExtDbRlsId($self->getArg('extDbRlsSpec'));
    my $outputDir = $self->parseOwlFile() if (!$self->getArg('skipParsing'));
    # my $ontologyTerms, $demotedTerms = $self->loadTerms($targetDir);
    # self->loadSynonyms($ontologyTerms, $demotedTerms);
    # $self->loadRelationships($ontologyTerms);
}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub parseOwlFile {
    my ($self) = @_;

    my $owlFileUrl = $self->getArg('owlFileUrl');
    my $namespace = ($self->getArg('namespace')) ? $self->getArg('namespace') : 'full';
    my $outputPath = $self->getArg('outputPath');

    $self->error("Output path $outputPath does not exist") unless (-d $outputPath);
    my $targetDir = ($namespace ne 'full') 
        ? PluginUtils::createDirectory($self, $outputPath, $namespace)
        : $outputPath;

    PluginUtils::setDirectoryPermissions($self, $outputPath, "g+w");

    $self->log("INFO: Parsing OWL File $owlFileUrl using niagads-pylib owl_parser");

    my (@cmd) = ('owl_parser', '--reportSuccess', '--verbose', '--url', $owlFileUrl, '--outputDir', $targetDir );
    if ($namespace ne 'full') {
        push(@cmd, '--namespace');
        push(@cmd, $namespace);
    }

    if ($self->getArg('numWorkers')) {
        push(@cmd, '--numWorkers');
        push(@cmd, $self->getArg('numWorkers'));
    }
    
    if ($self->getArg('debug')) {
        push(@cmd, '--debug')
    }

    $self->log("INFO: Executing command: " . join(' ', @cmd));
    my $message = qx(@cmd);

    $self->error("ERROR parsing OWL file $owlFileUrl: see $targetDir/owl_parser.log")
        if ($message !~ /SUCCESS/);
    $self->{plugin}->log("DONE: Parsing OWL File $owlFileUrl");

    return $targetDir;
}

sub loadTerms {
    my ($self) = @_;
    my $ontologyTerms = {};
    my $demotedTerms = {}; # terms moved from ontology term to ontology synonym

    # for each term in the term file

    # is it already in DB (term)
    # if yes; is the ID the same?
    # if no; is the new term in the preferred namespace?

    return $ontologyTerms, $demotedTerms
}

sub loadSynonyms  {
    my ($self, $ontologyTerms, $demotedTerms) = @_;
}
sub loadRelationships {
    my ($self, $ontologyTerms) = @_;
}

# ----------------------------------------------------------------------
# supporting
# ----------------------------------------------------------------------

sub getOntologyTerm {
    my ($self, $termId, $term) = @_;
    # pull by name first
    my $otObj = GUS::Model::SRes::OntologyTerm->new({
        name => $term
    })

}

# ----------------------------------------------------------------------
sub undoTables {
    my ($self) = @_;

    return ('SRes.OntologyTerm', 'SRes.OntologySynonym', 'SRes.OntologyRelationship');
}
