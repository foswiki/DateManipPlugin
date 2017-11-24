# ---+ Extensions
# ---++ DateManipPlugin
# This is the configuration used by the <b>DateManipPlugin</b>.

# **BOOLEAN**
# Shut down warning message when DateTimePlugin is installed as well.
$Foswiki::cfg{DateManipPlugin}{QuietDateTimePluginWarning} = $FALSE;

# **STRING CHECK="undefok emptyok"**
# Default date time format.
$Foswiki::cfg{DateManipPlugin}{DefaultDateTimeFormat} = '%d %b %Y - %H:%M';

# **NUMBER CHECK="undefok emptyok"**
# First day in week, a number between 1 and 7, 1=Monday, 7=Sunday.
$Foswiki::cfg{DateManipPlugin}{FirstDay} = 1;

# **NUMBER CHECK="undefok emptyok"**
# Day the working week begins (1-7), 1=Monday.
$Foswiki::cfg{DateManipPlugin}{WorkWeekBeg} = 1;

# **NUMBER CHECK="undefok emptyok"**
# Day the working week ends (1-7), 5=Friday.
$Foswiki::cfg{DateManipPlugin}{WorkWeekEnd} = 5;

# **STRING CHECK="undefok emptyok"**
# Time the working day begins.
$Foswiki::cfg{DateManipPlugin}{WorkDayBeg} = '08:00';

# **STRING CHECK="undefok emptyok"**
# Time the working day ends.
$Foswiki::cfg{DateManipPlugin}{WorkDayEnd} = '17:00';

1;
