## LoadGTFGeneTrackJson.pm
## $Id: LoadGTFGeneTrackJson.pm $
##

package GenomicsDBData::Load::Plugin::LoadGTFGeneTrackJson;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use GUS::PluginMgr::Plugin;
use Data::Dumper;
use File::Slurp;

use GUS::Model::NIAGADS::GTFGeneTrack;

use JSON::XS;
use Package::Alias Utils => 'GenomicsDBData::Load::Utils';


# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
  my $argumentDeclaration  =
    [
     stringArg({name => 'fileDir',
		descr => 'directory containing JSON files',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0,
	     }),

     fileArg({name => 'file',
		descr => 'only load the specified file',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0,
	      mustExist => 1,
	      format=>'JSON'
	     }),

     stringArg({name => 'filePattern',
		descr => 'parse files matching the specified pattern (regexp); otherwise will try and read all .json files in the directory',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0,
	     }),

      stringArg({name => 'skip',
		descr => 'comma separated list of files to skip',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0,
	     }),

    ];
  return $argumentDeclaration;
}

# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
  my $purposeBrief = 'Reads JSON files generated by IGV parsing of a GTEX/GFF3 and loads into database';

  my $purpose = 'This plugin populates NIAGADS.GTFGeneTrack by parsing JSON files generated by IGV parsing of GENCODE GTF/GFF3 files; stores chromosome and feature-level JSON for serving a Gene track webservice';

  my $tablesAffected = [];

  my $tablesDependedOn = [];

  my $howToRestart = '';

  my $failureCases = '';

  my $notes = <<NOTES;
  see http://github.com/igvteam/igv.js

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

  my @files = $self->getFileList();
  for my $file (@files) {
    my $fileName = $self->getArg('fileDir') . "/" . $file;
    $self->load($fileName);
  }


}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub load {
  my ($self, $fileName) = @_;

  $self->log("Processing $fileName");
  my $jsonStr = read_file($fileName) || $self->error("Unable to open $fileName for reading");

  $jsonStr =~ s/\.\d+//g; # remove .# from end of Ensembl IDS, eg. ENST00000387347.2 to ENST00000387342

  # extract chromosome
  $jsonStr =~ m/"(chr[X|Y|M|\d]+)"/;
  my $chromosome = $1;

  # insert jsonStr as full chromosome entry
  my $chrTrack = GUS::Model::NIAGADS::GTFGeneTrack
    ->new({feature_json => $jsonStr,
	   chromosome => $chromosome,
	   feature_source_id => $chromosome,
	   feature_type => "chromosome"
	  });

  $chrTrack->submit();
  $self->log("LOADED track for $chromosome; parsing features.");

  # convert to JSON, extract feature array and iterate over, submitting
  my $featureCount = 0;
  my $json = JSON::XS->new;
  my $jsonData = $json->decode($jsonStr) || $self->error("Error parsing JSON from  $fileName");

  my @features = $jsonData->{$chromosome};
  for my $feature (@{$features[0]}) {
    # $self->error(Dumper($feature));
    my $featureObj = GUS::Model::NIAGADS::GTFGeneTrack
      ->new({chromosome => $chromosome,
	     feature_source_id => $feature->{id},
	     feature_type => $feature->{type},
	     location_start => $feature->{start},
	     location_end => $feature->{end},
	     feature_json => Utils::to_json($feature)
	    });

    $featureObj->submit();

    if (++$featureCount % 1000 == 0) {
      $self->log("LOADED $featureCount features.");
      $self->undefPointerCache();
    }
  }
  $self->log("DONE processing $chromosome.");
  $self->log("LOADED $featureCount features.");

}

sub getFileList {
  my ($self) = @_;

  my $pattern = ($self->getArg('filePattern')) ? $self->getArg('filePattern') : ".json";

  my @files = ();
  if ($self->getArg('file')) {
    @files = ($self->getArg('file'));
  }
  else {
    $self->error('Must supply filePattern if no file list provided') if (!$pattern);
    $self->log("Finding files in " . $self->getArg('fileDir') . " that match $pattern");
    opendir(my $dh, $self->getArg('fileDir')) || $self->error("Path does not exists: " . $self->getArg('fileDir'));
    @files = grep(/${pattern}/, readdir($dh));
    closedir($dh);

    # remove skipped files
    if ($self->getArg('skip')) {
      my @skipFiles = split /,/, $self->getArg('skip');
      my %sFiles = map { $_ => 1 } @skipFiles;
      for my $index (reverse 0..$#files) {
	if (exists $sFiles{$files[$index]} ) {
	  splice(@files, $index, 1, ());
	}
      }
    }
  }
  $self->log("Found the following files: @files");
  return @files;
}


# ----------------------------------------------------------------------
sub undoTables {
  my ($self) = @_;

  return ('NIAGADS.GTFGeneTrack');
}



1;
