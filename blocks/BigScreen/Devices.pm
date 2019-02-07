# @file
# This file contains the implementation of the slide management class
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
package BigScreen::Devices;

use strict;
use experimental 'smartmatch';
use parent qw(BigScreen);
use Webperl::Utils qw(path_join);
use v5.12;


# ============================================================================
#  Constructor

## @cmethod $ new(%args)
# Overloaded constructor for the DEvices, loads the System::Devices model
# and other classes required to generate device management pages.
#
# @param args A hash of values to initialise the object with. See the Block docs
#             for more information.
# @return A reference to a new BigScreen::Devices object on success, undef on error.
sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = $class -> SUPER::new(@_)
        or return undef;

    $self -> {"devices"} = $self -> {"module"} -> load_module("BigScreen::System::Devices")
        or return Webperl::SystemModule::set_error("Slide show module object creation failed: ".$self -> {"module"} -> errstr());

    return $self;
}


# ============================================================================
#  Content generators

## @method private @ _fatal_error($error)
# Generate the tile and content for an error page.
#
# @param error A string containing the error message to display
# @return The title of the error page and an error message to place in the page.
sub _fatal_error {
    my $self  = shift;
    my $error = shift;

    return ("{L_MANAGE_ERR_FATAL}", $self -> {"template"} -> load_template("error/page_error.tem", { "%(message)s" => $error }));
}



## @method private $ _build_device_row($device)
# Generate a row to show in the devices list for the specified device. This will
# create a fragment of HTML representing the provided device, along with controls
# to manage its status and settings, and to delete it.
#
# @param source A reference to a hash containing the device information.
# @return A string containing the HTML fragment for this device.
sub _build_device_row {
    my $self   = shift;
    my $device = shift;

    return $self -> {"template"} -> load_template("devices/device.tem",
                                                  { "%(id)s"          => $device -> {"id"},
                                                    "%(name)s"        => $device -> {"name"},
                                                    "%(ipaddr)s"      => $device -> {"ipaddr"},
                                                    "%(port)s"        => $device -> {"port"},
                                                    "%(description)s" => $device -> {"description"},
                                                    "%(small-img)s"   => $device -> {"status"} -> {"screen"} -> {"thumb"},
                                                    "%(full-img)s"    => $device -> {"status"} -> {"screen"} -> {"full"},
                                                    "%(edit-url)s"    => $self -> build_url(block => "devmng",
                                                                                            pathinfo => [ "edit", $device -> {"id"} ],
                                                                                            params   => ""),
                                                    "%(delete-url)s"  => $self -> build_url(block    => "devmng",
                                                                                            pathinfo => [ "delete", $device -> {"id"} ],
                                                                                            params   => ""),
                                                    "%(alive-color)s"   => $device -> {"status"} -> {"alive"} ? "success" : "alert",
                                                    "%(running-color)s" => $device -> {"status"} -> {"running"} ? "success" : "alert",
                                                    "%(working-color)s" => $device -> {"status"} -> {"working"} ? "success" : "alert",
                                                    "%(alive-text)s"    => $device -> {"status"} -> {"alive"}   ? "{L_MANAGE_DEV_ALIVE_YES}"   : "{L_MANAGE_DEV_ALIVE_NO}",
                                                    "%(running-text)s"  => $device -> {"status"} -> {"running"} ? "{L_MANAGE_DEV_RUNNING_YES}" : "{L_MANAGE_DEV_RUNNING_NO}",
                                                    "%(working-text)s"  => $device -> {"status"} -> {"working"} ? "{L_MANAGE_DEV_WORKING_YES}" : "{L_MANAGE_DEV_WORKING_NO}",
                                                  });
}


# ============================================================================
#  Validators



# ============================================================================
#  Request handlers

## @method private @ _handle_default()
# Generate a page listing the currently defined slide sources, and presenting the
# controls to allow the sources to be managed.
#
# @return An array of values containing the page title, content, and extrahead.
sub _handle_default {
    my $self = shift;

    my $devices = $self -> {"devices"} -> get_devices()
        or return $self -> _fatal_error("Unable to obtain a list of devices");

    my $devlist = "";
    foreach my $device (@{$devices}) {
        my $status = $self -> {"devices"} -> get_device_status($device -> {"id"})
            or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"%(error)s" => $devices -> errstr()}));

        if($status -> {"screen"}) {
            $status -> {"screen"} = {
                "full"  => path_join($self -> {"settings"} -> {"config"} -> {"Devices:webdir"}, $device -> {"name"}, "full.png"),
                "thumb" => path_join($self -> {"settings"} -> {"config"} -> {"Devices:webdir"}, $device -> {"name"}, "small.jpg"),
            };
        } else {
            $status -> {"screen"} = {
                "full"  => path_join($self -> {"template"} -> {"templateurl"}, "images", "placeholder.png"),
                "thumb" => path_join($self -> {"template"} -> {"templateurl"}, "images", "placeholder.png"),
            };
        }

        $devlist .= $self -> _build_device_row({ "id"          => $device -> {"id"},
                                                 "name"        => $device -> {"name"},
                                                 "description" => $device -> {"description"},
                                                 "status"      => $status });
    }

    return ("{L_SIDE_DEVICES}",
            $self -> {"template"} -> load_template("devices/front.tem",
                                                   { "%(front-url)s" => $self -> build_url(block => "devmng",
                                                                                           pathinfo => [ ],
                                                                                           params   => ""),
                                                     "%(dev-list)s"  => $devlist || $self -> {"template"} -> load_template("devices/listempty.tem"),
                                                     "%(new-url)s"   => $self -> build_url(block => "devmng",
                                                                                           pathinfo => [ "new" ],
                                                                                           params   => ""),
                                                     }),
            $self -> {"template"} -> load_template("devices/extrahead.tem"),
            $self -> {"template"} -> load_template("devices/extrajs.tem",
                                                   { "%(device-url)s" => $self -> build_url(block => "rest",
                                                                                            pathinfo => [ "api", "devices" ],
                                                                                            params   => "")
                                                   }),
        );
}


## @method private $ _dispatch_ui()
# Implements the core behaviour dispatcher for non-api functions. This will
# inspect the state of the pathinfo and invoke the appropriate handler
# function to generate content for the user.
#
# @return A string containing the page HTML.
sub _dispatch_ui {
    my $self = shift;

    # We need to determine what the page title should be, and the content to shove in it...
    my ($title, $body, $extrahead, $extrajs) = ("", "", "", "");
    my @pathinfo = $self -> {"cgi"} -> multi_param("pathinfo");

    # All the _handle_* functions require manage permission, so check it once here.
    if($self -> check_permission("manage")) {
        given($pathinfo[0]) {
            default { ($title, $body, $extrahead, $extrajs) = $self -> _handle_default();    }
        }
    } else {
        ($title, $body) = $self -> _fatal_error("{L_MANAGE_ERR_PERMISSION}");
    }

    # Done generating the page content, return the filled in page template
    return $self -> generate_bigscreen_page(title     => $title,
                                            content   => $body,
                                            extrahead => $extrahead,
                                            extrajs   => $extrajs,
                                            nouserbar => 0);
}


# ============================================================================
#  Module interface functions

## @method $ page_display()
# Generate the page content for this module.
sub page_display {
    my $self = shift;

    my $error = $self -> check_login();
    return $error if($error);

    # Is this an API call, or a normal page operation?
    my $apiop = $self -> is_api_operation();
    if(defined($apiop)) {
        # API call - dispatch to appropriate handler.
        given($apiop) {
            default {
                return $self -> api_response($self -> api_errorhash('bad_op',
                                                                    $self -> {"template"} -> replace_langvar("API_BAD_OP")))
            }
        }
    } else {
        return $self -> _dispatch_ui();
    }
}

1;
