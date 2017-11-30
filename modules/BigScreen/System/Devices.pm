# @file
# This file contains the implementation of the devices class
#
# @author  Chris Page &lt;chris@starforge.co.uk&gt;
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

## @class
package BigScreen::System::Devices;

use strict;
use experimental 'smartmatch';
use parent qw(BigScreen);
use v5.12;
use Webperl::Utils qw(path_join);
use Text::Sprintf::Named qw(named_sprintf);
use File::Path qw(make_path);
use Net::Ping::External qw(ping);


# ============================================================================
#  Constructor

## @cmethod $ new(%args)
# Overloaded constructor for the Devices.
#
# @param args A hash of values to initialise the object with.
# @return A reference to a new BigScreen::System::Devices object on success, undef on error.
sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = $class -> SUPER::new(working   => "/usr/bin/ssh %(user)s\@%(ipaddr)s 'echo Working'",
                                        running   => "/usr/bin/ssh %(user)s\@%(ipaddr)s 'ps -ef | grep /bigscreen/ | grep -v grep'",
                                        screencap => "/usr/bin/ssh %(user)s\@%(ipaddr)s '%(cmd)s' > %(outfile)s",
                                        thumb     => "/usr/bin/convert %(source)s -resize 240x180 %(dest)s",
                                        pishot    => "/usr/bin/raspi2png -c 8 -s",
                                        reboot    => "/usr/bin/ssh %(user)s\@%(ipaddr)s 'sudo reboot &' 2>&1",
                                        @_)
        or return undef;

    return $self;
}


# ============================================================================
#  Interface

## @method $ get_devices(void)
# Fetch a list of all defined display devices.
#
# @return A reference to an array of device hashes.
sub get_devices {
    my $self = shift;

    $self -> clear_error();

    my $devh = $self -> {"dbh"} -> prepare("SELECT *
                                            FROM `".$self -> {"settings"} -> {"database"} -> {"devices"}."`
                                            ORDER BY `name`");
    $devh -> execute()
        or return $self -> self_error("Unable to fetch device information: ".$self -> {"dbh"} -> errstr());

    return $devh -> fetchall_arrayref({});
}


## @method $ get_device($id)
# Given a device ID, fetch the stored information about that device.
#
# @param id The ID of the device to fetch.
# @return A reference to a hash containing the device data.
sub get_device {
    my $self = shift;
    my $id   = shift;

    $self -> clear_error();

    my $devh = $self -> {"dbh"} -> prepare("SELECT *
                                            FROM `".$self -> {"settings"} -> {"database"} -> {"devices"}."`
                                            WHERE `id` = ?");
    $devh -> execute($id)
        or return $self -> self_error("Unable to fetch device information: ".$self -> {"dbh"} -> errstr());

    return $devh -> fetchrow_hashref();
}


## @method $ get_device_byname($name)
# Given a device name, fetch the stored information about that device. Note
# that this will return the data for at most one device; if the name matches
# multiple devices (which should never happen), only the first one will be
# returned.
#
# @param name The name of the device to fetch.
# @return A reference to a hash containing the device data.
sub get_device_byname {
    my $self = shift;
    my $name = shift;

    $self -> clear_error();

    my $devh = $self -> {"dbh"} -> prepare("SELECT *
                                            FROM `".$self -> {"settings"} -> {"database"} -> {"devices"}."`
                                            WHERE `name` LIKE ?
                                            ORDER BY `id`
                                            LIMIT 1");
    $devh -> execute($name)
        or return $self -> self_error("Unable to fetch device information: ".$self -> {"dbh"} -> errstr());

    return $devh -> fetchrow_hashref();
}


## @method $ get_device_status(id)
# Obtain the status indicators for the specified device. This will attempt
# to determine whethet the device is powered up, responding, showing the
# big screen display, and grab a screenshot of its display.
#
# @param id The ID of the device to fetch the status data for.
# @return A reference to a hash containing the device status indicators.
sub get_device_status {
    my $self = shift;
    my $id   = shift;
    my $status;

    my $device = $self -> get_device($id)
        or return undef;

    $status -> {"alive"}   = $self -> _check_alive($device -> {"ipaddr"})
        or return {};

    $status -> {"working"} = $self -> _check_working($device -> {"ipaddr"}, $device -> {"username"})
        or return $status;

    $status -> {"running"} = $self -> _check_running($device -> {"ipaddr"}, $device -> {"username"})
        or return $status;

    $status -> {"screen"} = $self -> _fetch_screenshot($device);

    return $status;
}


## @method $ reboot_device($device)
# Reboot the device specified.
#
# @param device A reference ot a hash containing the device information
# @return true on successful reboot, undef on error.
sub reboot_device {
    my $self = shift;
    my $id   = shift;

    $self -> clear_error();

    my $device = $self -> get_device($id)
        or return undef;

    my $bootcmd = named_sprintf($self -> {"reboot"}, { "ipaddr"  => $device -> {"ipaddr"},
                                                       "user"    => $device -> {"username"} });
    my $result = `$bootcmd`;

    return 1 if($result =~ /^Connection to /);

    return $self -> self_error("Reboot failed. Response: '$result'");
}


# ============================================================================
#  Internals

## @method private $ _check_alive($ipaddr)
# Determine whether the device at the specified IP address is alive. This
# will try to ping the device and return true if it responds. Note that
# this does not necessarily mean the device is in a working state, just
# that enough of it is present to respond to ICMP messages.
#
# @param ipaddr The IP address (or hostname) of the device to check.
# @return true if the device responds to pings, false otherwise.
sub _check_alive {
    my $self   = shift;
    my $ipaddr = shift;

    my $alive = ping(host => $ipaddr);
    return $alive;
}


## @method private $ _check_working($ipaddr, $username)
# Check whether the device at the specified IP address is accepting SSH
# connections and responds. This is a heavier-duty ping that checks
# whether the device is in a state where it is running a SSH server and
# can run other programs.
#
# @param ipaddr The IP address (or hostname) of the device to check.
# @return true if the device seems to be working, false otherwise.
sub _check_working {
    my $self     = shift;
    my $ipaddr   = shift;
    my $username = shift;

    my $checkcmd = named_sprintf($self -> {"working"}, { "ipaddr" => $ipaddr,
                                                         "user"   => $username });
    my $result = `$checkcmd`;

    return $result =~ /^Working/;
}


## @method private $ _check_running($ipaddr, $username)
# Determine whether the device is running a web browser showing the
# big screen. This looks at the device's process list, and tries to
# work out whether a web browser is running on the device, and it is
# showing the display in kiosk mode.
#
# @param ipaddr The IP address (or hostname) of the device to check.
# @return true if the device seems to be showing the big screen
#         display, false otherwise.
sub _check_running {
    my $self     = shift;
    my $ipaddr   = shift;
    my $username = shift;

    my $checkcmd = named_sprintf($self -> {"running"}, { "ipaddr" => $ipaddr,
                                                         "user"   => $username });
    my $result = `$checkcmd`;

    my ($browser, $url) = $result =~ m|(chromium-browser).*?--kiosk (https://.*?bigscreen)|;

    return (defined($browser) && defined($url));
}


## @method private $ _fetch_screenshot($device)
# Invoke a command on the device to take a screenshot, and generate a
# scaled-down version to show on the status page.
#
# @param device A reference to a hash containing the device information
# @return true on successful screenshot retrieval and scaling, undef
#         on error.
sub _fetch_screenshot {
    my $self   = shift;
    my $device = shift;

    my $outpath   = path_join($self -> {"settings"} -> {"config"} -> {"Devices:basedir"}, $device -> {"name"});
    eval { make_path($outpath); };
    return $self -> self_error("Unable to create image store directory: $@")
        if($@);

    my $pngdest   = path_join($outpath, "full.png");
    my $thumbdest = path_join($outpath, "small.jpg");

    my $fetchcmd = named_sprintf($self -> {"screencap"}, { "ipaddr"  => $device -> {"ipaddr"},
                                                           "user"    => $device -> {"username"},
                                                           "cmd"     => $device -> {"shotcmd"} || $self -> {"pishot"},
                                                           "outfile" => $pngdest });

    my $result = `$fetchcmd`;
    return $self -> self_error("Image fetch failed: $result")
        if($result);

    my $thumbcmd = named_sprintf($self -> {"thumb"}, { "source" => $pngdest,
                                                       "dest"   => $thumbdest });
    $result = `$thumbcmd 2>&1`;
    return $self -> self_error("Thumb image conversion failed: $result")
        if($result);

    return 1;
}


1;