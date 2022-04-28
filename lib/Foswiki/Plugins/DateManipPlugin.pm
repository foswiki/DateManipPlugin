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

package Foswiki::Plugins::DateManipPlugin;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Time ();
use Error qw(:try);

our $VERSION = '4.00';
our $RELEASE = '28 Apr 2022';
our $SHORTDESCRIPTION = 'Date times, durations and recurrences';
our $NO_PREFS_IN_TOPIC = 1;
our $core;

BEGIN {
  no warnings 'redefine';

  if (1) {

    # patch Foswiki::Time
    *Foswiki::Time::origFormatTime = \&Foswiki::Time::formatTime;
    #*Foswiki::Time::origFormatDelta = \&Foswiki::Time::formatDelta;
    *Foswiki::Time::origParseTime = \&Foswiki::Time::parseTime;
    *Foswiki::Time::formatTime = sub { return getCore()->compatFormatTime(@_); };
    #*Foswiki::Time::formatDelta = sub { return getCore()->compatFormatDelta(@_); };
    *Foswiki::Time::parseTime = sub { return getCore()->compatParseTime(@_); };

    # patch Foswiki::Func
    *Foswiki::Func::origFormatTime = \&Foswiki::Func::formatTime;
    *Foswiki::Func::formatTime = sub { return getCore()->compatFormatTime(@_); };
  }

  use warnings 'redefine';
}

sub initPlugin {

  if (exists $Foswiki::cfg{Plugins}{DateTimePlugin} && $Foswiki::cfg{Plugins}{DateTimePlugin}{Enabled}) {
    Foswiki::Func::writeWarning("Please disable DateTimePlugin. Temporarily renaming DATETIME macro to DATEMANIP.")
      unless $Foswiki::cfg{DateManipPlugin}{QuietDateTimePluginWarning};

    Foswiki::Func::registerTagHandler('DATEMANIP', sub { return getCore(shift)->DATETIME(@_); });
  } else {
    Foswiki::Func::registerTagHandler('DATETIME', sub { return getCore(shift)->DATETIME(@_); });
  }

  Foswiki::Func::registerTagHandler('NOW', sub { return time(); });
  Foswiki::Func::registerTagHandler('TODAY', sub { return getCore(shift)->DATETIME({
    "_DEFAULT" => "today",
    lang => "en",
    format => '$epoch',
  }); });

  Foswiki::Func::registerTagHandler('DURATION', sub { return getCore(shift)->DURATION(@_); });
  Foswiki::Func::registerTagHandler('RECURRENCE', sub { return getCore(shift)->RECURRENCE(@_); });

  return 1;
}

sub getCore {
  my ($session) = @_;

  unless (defined $core) {
    require Foswiki::Plugins::DateManipPlugin::Core;
    $core = Foswiki::Plugins::DateManipPlugin::Core->new($session);
  }

  return $core;
}

sub finishPlugin {
  return unless $core;

  $core->finish;
  undef $core;
}

1;
