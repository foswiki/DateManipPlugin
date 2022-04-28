# Plugin for Foswiki - The Free and Open Source Wiki, https://foswiki.org/
#
# DateManipPlugin is Copyright (C) 2017-2022 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package Foswiki::Plugins::DateManipPlugin::Core;

use strict;
use warnings;
use utf8;

use Foswiki::Func ();
use Foswiki::Plugins ();
use Date::Manip ();
use Error qw(:try);
use POSIX;

use constant TRACE => 0; # toggle me

sub new {
  my $class = shift;
  my $session = shift;

  $session ||= $Foswiki::Plugins::SESSION;

  my $this = bless({
    firstDay => $Foswiki::cfg{DateManipPlugin}{FirstDay} || 1,
    workWeekBeg => $Foswiki::cfg{DateManipPlugin}{WorkWeekBeg} || 1,
    workWeekEnd => $Foswiki::cfg{DateManipPlugin}{WorkWeekEnd} || 5,
    workDayBeg => $Foswiki::cfg{DateManipPlugin}{WorkDayBeg} || '08:00',
    workDayEnd => $Foswiki::cfg{DateManipPlugin}{WorkDayEnd} || '17:00',
    @_
  }, $class);

  $this->{_numCallsToParseTime} = 0;
  $this->{_session} = $session;

  return $this;
}

sub finish {
  my $this = shift;

  _writeDebug("numCallsToParseTime=$this->{_numCallsToParseTime}");

  undef $this->{_session};
  undef $this->{_secondsOfUnit};
  undef $this->{_defaultLang};
  undef $this->{_cache};
}

sub DATETIME {
  my ($this, $params, $topic, $web) = @_;

  _writeDebug("called DATETIME()");
  my $result = "";

  try {
    my $date = $this->getDate($params);

    my $dateStr = $params->{_DEFAULT} || $params->{date} || "epoch ".time;
    my $err = $date->parse(_fixDateTimeString($dateStr));
    throw Error::Simple($date->err) if $err;

    if (defined $params->{delta}) {
      my $delta = $this->getDelta($params);
      my $isBusiness = Foswiki::Func::isTrue($params->{business}, 0);
      my $err = $delta->parse($params->{delta}, $isBusiness);
      throw Error::Simple($delta->err) if $err;

      my $isSubtract = Foswiki::Func::isTrue($params->{subtract}, 0);
      $date = $date->calc($delta, $isSubtract);
    }

    $result = $this->formatDate($date, $params);
  } catch Error::Simple with {
    $result = _inlineError(shift);
  };

  return Foswiki::Func::decodeFormatTokens($result);
}

sub DURATION {
  my ($this, $params, $topic, $web) = @_;

  # ... to please gettext
  #
  # %MAKETEXT{"year"}%
  # %MAKETEXT{"years"}%
  # %MAKETEXT{"month"}%
  # %MAKETEXT{"months"}%
  # %MAKETEXT{"months"}%
  # %MAKETEXT{"day"}%
  # %MAKETEXT{"days"}%
  # %MAKETEXT{"week"}%
  # %MAKETEXT{"weeks"}%
  # %MAKETEXT{"hour"}%
  # %MAKETEXT{"hours"}%
  # %MAKETEXT{"minute"}%
  # %MAKETEXT{"minutes"}%
  # %MAKETEXT{"second"}%
  # %MAKETEXT{"seconds"}%


  _writeDebug("called DURATION()");
  my $result = "";

  try {
    my $isSubtract = Foswiki::Func::isTrue($params->{subtract}, 0);
    my $isBusiness = Foswiki::Func::isTrue($params->{business}, 0);

    my $delta;
    my $fromStr = $params->{from};
    my $toStr = $params->{to};

    if(defined $fromStr || defined $toStr) {
      # date mode
      $fromStr = "epoch ".time if !defined($fromStr) || $fromStr eq '';
      $toStr = "epoch ".time if !defined($toStr) || $toStr eq '';

      my $fromDate = $this->getDate($params);
      my $err = $fromDate->parse(_fixDateTimeString($fromStr));
      throw Error::Simple($fromDate->err) if $err;

      my $toDate = $this->getDate($params);
      $err = $toDate->parse(_fixDateTimeString($toStr));
      throw Error::Simple($toDate->err) if $err;

      $delta = $fromDate->calc($toDate, $isSubtract, $isBusiness?"business":"exact");

    } else {
      # duration mode
      my $durStr = $params->{_DEFAULT} || $params->{delta} || '0:0:0:0:0:0:0';
      $delta = $this->getDelta($params);
      my $err = $delta->parse($durStr, $isBusiness);
      throw Error::Simple($delta->err) if $err;
    }

    _writeDebug("delta=".$delta->printf('%Dt')) if TRACE;

    my $format = $params->{format};

    if (defined $format) {
      $result = $delta->printf($format);
      $result =~ s/\$epoch\b/$this->delta2sec($delta, $isBusiness)/ge;
    } else {
      $result = $this->formatDelta($delta, $params);
    }

  } catch Error::Simple with {
    $result = _inlineError(shift);
  };

  $result =~ s/Jän\b/Jan/g; # SMELL: strange german traslation
  return Foswiki::Func::decodeFormatTokens($result);
}

sub RECURRENCE {
  my ($this, $params, $topic, $web) = @_;

  _writeDebug("called RECURRENCE()");
  my $result = '';
  try {
    my $rec = $this->getRecurrence($params);

    my $recStr = $params->{_DEFAULT};

    if (defined $recStr) {
      my $err = $rec->parse($recStr);
      throw Error::Simple($rec->err) if $err;
    } else {
      my $freq = $params->{freq} || $params->{frequency};
      my $start = $params->{start} || 'epoch '.time;
      my $end = $params->{end};
      my $base = $params->{base};
      my $modifiers = $params->{modifiers};
      my $limit = $params->{limit} || 1000;

      throw Error::Simple("no frequency") unless defined $freq;

      my $err;
      $err = $rec->frequency($freq);
      throw Error::Simple($rec->err) if $err;

      $err = $rec->start($start);
      throw Error::Simple($rec->err) if $err;

      if (defined $end) {
        $err = $rec->end($end);
        throw Error::Simple($rec->err) if $err;
      }
      if (defined $base) {
        $err = $rec->basedate($base);
        throw Error::Simple($rec->err) if $err;
      }
      if (defined $modifiers) {
        $err = $rec->modifiers($modifiers);
        throw Error::Simple($rec->err) if $err;
      }
    }

    my @result = ();
    my @dates = $rec->dates();
    my $index = 0;
    foreach my $date (@dates) {
      my $line = $this->formatDate($date, $params);
      push @result, $line if defined $line && $line ne '';
      $index++;
      last if $index >= $params->{limit};
    }
    $result = ($params->{header} || '').join($params->{separator}||', ', @result).($params->{footer}||'')
      if @result;

  } catch Error::Simple with {
    $result = _inlineError(shift);
  };

  return Foswiki::Func::decodeFormatTokens($result);
}

# implements Foswiki::Time::formatTime
sub compatFormatTime {
  my ($this, $string, $format, $tz, $params) = @_;

  $params ||= {};
  $params->{format} //= $format;
  $params->{format} //= $Foswiki::cfg{DefaultDateFormat};
  $params->{tz} //= $tz;
  $params->{tz} //= $Foswiki::cfg{DisplayTimeValues};
  $params->{lang} = $this->getLang($params);

  $string //= '';

  my $date = $this->getDate($params);
  my $err;

  if ($string =~ /^\-?\d+$/) {
    $err = $date->parse("epoch $string");
  } else {
    $err = $date->parse($string);
  }

  if ($err) {
    # silently ignore
    print STDERR "ERROR: ".$date->err." in compatFormatTime($string)\n" if TRACE;
    return "";
  }

  return $this->formatDate($date, $params);
}

# implements Foswiki::Time::formatDelta
# sub compatFormatDelta {
#   my ($this, $epoch, $dummy, $params) = @_;
#
#   $params ||= {};
#
#   my $delta = $this->getDelta($params);
#   my $err = $delta->parse($epoch);
#
#   if ($err) {
#     Foswiki::Func::writeWarning($delta->err);
#     return "";
#   }
#
#   my $result = $this->formatDelta($delta, $params);
#
#   return;
# }

# implements Foswiki::Time::parseTime
sub compatParseTime {
  my ($this, $string, $defaultLocal, $params) = @_;

  $this->{_numCallsToParseTime}++;

  # SMELL: some jobs are really slowed down by Date::Manip -> lets use the old time parser
  if (Foswiki::Func::getContext()->{statistics}) {
    return Foswiki::Time::origParseTime($string, $defaultLocal);
  }

  $params ||= {};
  $params->{lang} = $this->getLang($params);
  $params->{tz} = 'GMT' unless $defaultLocal;
  my $date = $this->getDate($params);

  $string = _fixDateTimeString($string);
  my $err = $date->parse($string);

  if ($err) {
    # silently ignore
    print STDERR "ERROR: ".$date->err." in compatParseTime($string)\n" if TRACE;
    return;
  }

  return $date->printf("%s");
}

sub formatDate {
  my ($this, $date, $params) = @_;

  my $format = $params->{format} || $Foswiki::cfg{DateManipPlugin}{DefaultDateTimeFormat} || '%d %b %Y - %H:%M';

  my $tz = _getTimezone($params);
  $format = '$year-$mo-$dayT$hours:$minutes:$secondsZ' if $format =~ /^\$?iso$/ && $tz eq "GMT";

  _translateFormat($format); # for compatibility with DateTimeFormat and other Foswiki formats

  my $result = $date->printf($format);
  $result =~ s/Jän\b/Jan/g; # SMELL: strange german traslation

  # rewrite iso tz string
  $result =~ s/\0\+0000\0/Z/;
  $result =~ s/\0([+-]\d\d)(\d\d)\0/$1:$2/;

  return $result;
}

sub getSecondsOfUnit {
  my ($this, $isBusiness, $unit) = @_;

  unless (exists $this->{_secondsOfUnit}) {
    #print STDERR "computing seondsOfUnit\n";

    $this->{_secondsOfUnit}{standard} = {
      years   => 60*60*24*365.2425,
      months  => 60*60*2*365.2425,
      weeks   => 60*60*24*7,
      days    => 60*60*24,
      hours   => 60*60,
      minutes => 60,
      seconds => 1,
    };

    my $start;
    my $end;
    my $delta;
    my @fields;

    $start = $this->getDate();
    $start->parse($this->{workDayBeg});
    $end = $this->getDate();
    $end->parse($this->{workDayEnd});
    $delta = $start->calc($end);
    @fields = $delta->value();
    my $daySecs = ($fields[6]||0) + ($fields[5]||0) * 60 + ($fields[4]||0) * 60 * 60;
    #print STDERR "daySecs=$daySecs\n";

    my $weekDays = $this->{workWeekEnd} - $this->{workWeekBeg} + 1;
    #print STDERR "weekDays=$weekDays\n";

    $this->{_secondsOfUnit}{business} = {
      years   => $daySecs * $weekDays * 52.143,
      months  => $daySecs * $weekDays * 52.143 / 12,
      weeks   => $daySecs * $weekDays,
      days    => $daySecs,
      hours   => 60*60,
      minutes => 60,
      seconds => 1,
    };
  }

  return $this->{_secondsOfUnit}{$isBusiness?"business":"standard"}{$unit};
}

sub delta2sec {
  my ($this, $delta, $isBusiness) = @_;

  my $index = 0;
  my $sec = 0;
  my @fields = $delta->value();

  #print STDERR "input=".$delta->input."\n";
  #print STDERR "fields=".join(":",@fields)."\n";

  foreach my $unit (qw(years months weeks days hours minutes seconds)) {
    my $val = $fields[$index++];
    $sec += $val * $this->getSecondsOfUnit($isBusiness, $unit);
  }
  $sec = abs($sec);

  return $sec;
}

sub formatDelta {
  my ($this, $delta, $params) = @_;

  my $isBusiness = Foswiki::Func::isTrue($params->{business}, 0);
  my $duration = $this->delta2sec($delta, $isBusiness);

  #print STDERR "total seconds=$duration\n";

  return ($params->{null} // '%MAKETEXT{"null"}%') if $duration == 0;

  my @result = ();
  my $numUnits = $params->{units};
  my $index = 0;
  my $all = Foswiki::Func::isTrue($params->{all}, 1);
  my $useLabels = Foswiki::Func::isTrue($params->{labels}, 1);
  foreach my $unit (qw(years months weeks days hours minutes seconds)) {
    next unless Foswiki::Func::isTrue($params->{$unit}, $all);

    my $factor = $this->getSecondsOfUnit($isBusiness, $unit);
    my $count = floor($duration / $factor);
    _writeDebug("duration=$duration, unit=$unit, seconds in $unit=$factor, count=$count");

    if ($count) {

      if ($useLabels) {
        my $label = $unit;
        $label =~ s/s$//g if $count == 1; # TODO use maketext
        push @result, "$count %MAKETEXT{\"$label\"}%";
      } else {
        push @result, $count;
      }

      $index++;
      $duration -= $count * $factor;

      last if defined $numUnits && $index >= $numUnits;
    }
  }

  my $result = '';
  if (@result) {

    if ($useLabels) {
      my $last = pop @result;

      $result = join(", ", @result) . ' %MAKETEXT{"and"}% ' if @result;
      $result .= $last;
    } else {
      $result = join(", ", @result);
    }
  }

  return $params->{null} if defined $params->{null} && $result eq '';
  return $result;
}

sub getLang {
  my ($this, $params) = @_;

  unless (defined $this->{_defaultLang}) {
    $this->{_defaultLang} =
      Foswiki::Func::getPreferencesValue("LANGUAGE")
      || $this->{_session}->i18n->language()
      || 'en';
  }

  return $params->{lang}
    || $params->{language}
    || $this->{_defaultLang};
}

sub getRecurrence {
  my ($this, $params) = @_;

  return $this->_getObject("recur", $params);
}

sub getDate {
  my ($this, $params) = @_;

  return $this->_getObject("date", $params);
}

sub getDelta {
  my ($this, $params) = @_;

  return $this->_getObject("delta", $params);
}

sub _getObject {
  my ($this, $type, $params) = @_;

  my $lang = $this->getLang($params);
  my $tz = _getTimezone($params);
  my $key = $type."::".$tz."::".$lang;
  my $obj = $this->{_cache}{$key};

  unless ($obj) {

    if ($type eq 'date') {
      $obj = new Date::Manip::Date();
    } elsif ($type eq 'delta') {
      $obj = new Date::Manip::Delta();
    } elsif ($type eq 'recur') {
      $obj = new Date::Manip::Recur() if $type eq 'recur';
    } else {
      die "unknown object type '$type'";
    }

    $obj->config(
      "Language", $lang,
      "DateFormat", $lang eq "en" ? "US" : "non-US",
      "FirstDay", $this->{firstDay},
      "WorkWeekBeg", $this->{workWeekBeg},
      "WorkWeekEnd", $this->{workWeekEnd},
      "WorkDayBeg", $this->{workDayBeg},
      "WorkDayEnd", $this->{workDayEnd},
    );

    $obj->config("setdate", "zone,$tz") if $tz;
    $this->{_cache}{$key} = $obj;
  }

  return $obj->new();
}

sub _getTimezone {
  my ($params) = @_;

  my $tz = $params->{tz} // $Foswiki::cfg{DisplayTimeValues};
  my $format = $params->{format} || $Foswiki::cfg{DateManipPlugin}{DefaultDateTimeFormat} || '%d %b %Y - %H:%M';

  $tz = 'GMT' if $format =~ m/http/i;
  $tz = 'GMT' if $tz eq 'gmtime';
  $tz = '' if $tz eq 'servertime';

  return $tz;
}


sub _translateFormat {

  # predefined formats
  my $iso  = '$year-$mo-$dayT$hours:$minutes:$seconds$isotz';
  my $rcs  = '$year/$mo/$day $hours:$minutes:$seconds';
  my $http = '$wday, $day $mon $year $hours:$minutes:$seconds $tz';
  my $longdate = '$day $mon $year - $hours:$minutes';

  $_[0] =~ s/\$(http|email)/\$wday, \$day \$month \$year \$hour:\$min:\$sec \$tz/gi;
  $_[0] =~ s/[\b\$]?iso\b/$iso/g;
  $_[0] =~ s/[\b\$]?rcs\b/$rcs/g;
  $_[0] =~ s/[\b\$]?http\b/$http/g;
  $_[0] =~ s/[\b\$]?email\b/$http/g;
  $_[0] =~ s/[\b\$]?longdate\b/$longdate/g;

  $_[0] =~ s/\$year?s?/%Y/g;
  $_[0] =~ s/\$ye/%y/g;

  $_[0] =~ s/\$month/%B/g;
  $_[0] =~ s/\$mon/%b/g;
  $_[0] =~ s/\$mo/%m/g;

  $_[0] =~ s/\$weekday/%A/g;
  $_[0] =~ s/\$wday/%a/g;
  $_[0] =~ s/\$day/%d/g;
  $_[0] =~ s/\$dow/%w/g;
  $_[0] =~ s/\$doy/%j/g;
  $_[0] =~ s/\$dom/%E/g;

  $_[0] =~ s/\$hours12/%I %p/g;
  $_[0] =~ s/\$h12/%i %p/g;
  $_[0] =~ s/\$hour?s?/%H/g;
  $_[0] =~ s/\$h/%k/g;

  $_[0] =~ s/\$minu?t?e?s?/%M/g;
  $_[0] =~ s/\$seco?n?d?s?/%S/g;

  $_[0] =~ s/\$week/%W/g;
  $_[0] =~ s/\$tz/%Z/g;
  $_[0] =~ s/\$isotz/\0%z\0/g; # rewrite it later
  $_[0] =~ s/\$offset/%N/g;
  $_[0] =~ s/\$epoch/%s/g;

  return $_[0];
}


sub _writeDebug {
  return unless TRACE;
  #Foswiki::Func::writeDebug("DateManipPlugin::Core - $_[0]");
  print STDERR "DateManipPlugin::Core - $_[0]\n";
}

sub _inlineError {
  my $msg = shift;

  #_writeDebug("error: $msg");
  $msg =~ s/:? at .*$//g;
  $msg =~ s/^\s+|\s+$//g;
  return "<span class='foswikiAlert'>$msg</span>";
}

# work around bug in Date::Manip not being able to separate date and time by a dash
# replaces dash by T (05 May 2018 - 12:00 -> 05 May 2018 T 12:00)
sub _fixDateTimeString {
  my $str = shift;

  return "epoch $str" if $str =~ /^-?\d+$/;

  $str =~ s/\s+\-\s+(\d\d?:\d\d?(?:\d\d?\d)?)/ T $1/g;

  return $str;
}

1;
