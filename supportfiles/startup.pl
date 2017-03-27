use strict;

use lib "/path/to/bigscreen/blocks";
use lib "/path/to/bigscreen/modules";
use lib "/var/www/webperl";

# Make sure we are in a sane environment.
$ENV{MOD_PERL} or die "not running under mod_perl!";

# Preload core stuff
use Apache2::RequestRec;
use ModPerl::Util;

# Preload frequently used modules to speed up client spawning.
use CGI ();
CGI->compile(':cgi');
use CGI::Carp ();

use Apache::DBI;
use DBD::mysql ();
use MIME::Base64 ();
use List::BinarySearch ();
use List::Util ();

# And load the core modules
use BigScreen;
use BigScreen::API;
use BigScreen::AppUser;
use BigScreen::BlockSelector;
use BigScreen::Login;
use BigScreen::SlideShow;
use BigScreen::SlideSource::MondayMail;
use BigScreen::SlideSource::Newsagent;
use BigScreen::SlideSource::Twitter;
use BigScreen::SlideSource;
use BigScreen::SlideSource;
use BigScreen::System::Metadata;
use BigScreen::System::Roles;
use BigScreen::System::SlideSource;
use BigScreen::System::Tags;
use BigScreen::System::Devices;
use BigScreen::System;
use BigScreen::Userbar;
1;