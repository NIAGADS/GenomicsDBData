package GenomicsDBData::Load::Utils;

use JSON::XS;
use POSIX qw(strftime);
use Time::HiRes;



sub to_json {
  my ($data) = @_;
  return JSON::XS->new->utf8->allow_blessed->convert_blessed->encode($data) if ($data);
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
