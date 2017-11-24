# Plugin for Foswiki - The Free and Open Source Wiki, https://foswiki.org/
#
# DateManipPlugin is Copyright (C) 2017 Michael Daum http://michaeldaumconsulting.com
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

our $VERSION = '1.00';
our $RELEASE = '24 Nov 2017';
our $SHORTDESCRIPTION = 'Date times, durations and recurrences';
our $NO_PREFS_IN_TOPIC = 1;
our $core;

sub initPlugin {

  if (exists $Foswiki::cfg{Plugins}{DateTimePlugin}{Enabled} && $Foswiki::cfg{Plugins}{DateTimePlugin}{Enabled}) {
    Foswiki::Func::writeWarning("Please disable DateTimePlugin. Temporarily renaming DATETIME macro to DATEMANIP.")
      unless $Foswiki::cfg{DateManipPlugin}{QuietDateTimePluginWarning};

    Foswiki::Func::registerTagHandler('DATEMANIP', sub { return getCore(shift)->DATETIME(@_); });
  } else {
    Foswiki::Func::registerTagHandler('DATETIME', sub { return getCore(shift)->DATETIME(@_); });
  }

  Foswiki::Func::registerTagHandler('DURATION', sub { return getCore(shift)->DURATION(@_); });
  Foswiki::Func::registerTagHandler('RECURRENCE', sub { return getCore(shift)->RECURRENCE(@_); });

  return 1;
}

sub getCore {
  unless (defined $core) {
    require Foswiki::Plugins::DateManipPlugin::Core;
    $core = Foswiki::Plugins::DateManipPlugin::Core->new(shift);
  }
  return $core;
}


sub finishPlugin {
  return unless $core;

  $core->finish;
  undef $core;
}

1;