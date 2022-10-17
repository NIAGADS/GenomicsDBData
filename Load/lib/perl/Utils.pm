package GenomicsDBData::Load::Utils;

use JSON::XS;
use POSIX qw(strftime);
use Time::HiRes;
use Scalar::Util qw(looks_like_number);

sub toNumber {
  my ($value) = @_;
  return $value if ($value =~ m/nan/i);
  return $value if ($value =~ m/inf/i);
  return (looks_like_number($value)) ? $value * 1.0 : $value;
}

sub fileLineCount {
  my ($file) = @_;
  my $lineCount = `wc -l < $file`;
  return $lineCount;
}

sub countOccurrenceInFile {
  my ($file, $pattern, $missing) = @_;
  
  my  $lineCount = ($missing) ? `grep -v -P $pattern $file | wc -l`
    : `grep -P $pattern $file | wc -l`;
  return $lineCount;
}


sub to_json {
  my ($data, $pretty) = @_;
  $pretty //= 0;
  if ($data) {
    if ($pretty) {
      return JSON::XS->new->allow_blessed->convert_blessed->pretty->encode($data);
    }
    else {
      return JSON::XS->new->utf8->allow_blessed->convert_blessed->encode($data);
    }
  }
  return undef;
}


sub arrayContains {
  my ($value, @array) = @_;

  my %arrayHash = map { $_ => 1 } @array;

  return 1 if (exists $arrayHash{$value});
  return 0;
}

sub getCurrentTime {
  return strftime '"%Y-%m-%d %H:%M:%S"', localtime;
}

sub getTime {
  return [Time::HiRes::gettimeofday()];
}

sub elapsed_time {
  my ($startTime) = @_;
  my ($user, $system, $child_user, $child_system) = times;
  my $elapsedTime = Time::HiRes::tv_interval($startTime);
  return ($elapsedTime, "real $elapsedTime // user $user // sys $system");
}

# ----------------------------------------------------------------------
#  truncate and add ellipses
# ----------------------------------------------------------------------
sub truncateStr {
  my ($str, $length) = @_;
  $length //= 5; # set parameter value default (works in perl 5.10+)
  return $str if (length($str) <= $length);
  return substr($str, 0, $length) . "...";
}

1;
