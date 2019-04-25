# @file
# This file contains the implementation of the API class
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
package BigScreen::API;

use strict;
use experimental 'smartmatch';
use parent qw(BigScreen);
use Webperl::Utils qw(path_join);
use JSON;
use DateTime;
use v5.12;
use Data::Dumper;

# ============================================================================
#  Constructor

## @cmethod $ new(%args)
# Overloaded constructor for the API, loads the System::Agreement model
# and other classes required to generate article pages.
#
# @param args A hash of values to initialise the object with. See the Block docs
#             for more information.
# @return A reference to a new BigScreen::API object on success, undef on error.
sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = $class -> SUPER::new(@_)
        or return undef;

    return $self;
}


# ============================================================================
#  Support functions

## @method private $ _show_api_docs()
# Redirect the user to a Swagger-generated API documentation page.
# Note that this function will never return.
sub _show_api_docs {
    my $self = shift;

    $self -> log("api:docs", "Sending user to API docs");

    my ($host) = $self -> {"settings"} -> {"config"} -> {"httphost"} =~ m|^https?://([^/]+)|;
    return $self -> {"template"} -> load_template("api/docs.tem", { "%(host)s" => $host });
}


# ============================================================================
#  API functions

## @method private $ _build_slides_response()
# Return the slides to show on the big screen
#
# @api GET /slides
#
# @return A reference to a hash containing the API response data.
sub _build_slides_response {
    my $self = shift;

    my $sources = $self -> {"module"} -> load_module("BigScreen::System::SlideSource")
        or return $self -> api_errorhash('internal_error', "Slide show module object creation failed: ".$self -> {"module"} -> errstr());

    return { "slides" => $sources -> get_slides() };

}


## @method private $ _build_token_response()
# Generate an API token for the currently logged-in user.
#
# @api GET /token
#
# @return A reference to a hash containing the API response data.
sub _build_token_response {
    my $self = shift;

    my $token = $self -> api_token_generate($self -> {"session"} -> get_session_userid())
        or return $self -> api_errorhash('internal_error', $self -> errstr());

    return { "token" => $token };
}


## @method private $ _build_devices_response()
# Generate the information about the status of devices currently
# defined within the system.
#
# @api GET /devices
#
# @return A reference to a hash containing the API response data.
sub _build_get_devices_response {
    my $self    = shift;
    my $devname = shift;

    return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"%(error)s" => "Illegal characters in device name"}))
        unless(!$devname || $devname =~ /^\w+$/);

    my $devices = $self -> {"module"} -> load_module("BigScreen::System::Devices")
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"%(error)s" => $self -> {"module"} -> errstr()}));

    my $devlist = $devices -> get_devices()
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"%(error)s" => $devices -> errstr()}));

    my @response;
    foreach my $device (@{$devlist}) {
        next if($devname && $device -> {"name"} ne $devname);

        $self -> log("api.devices", "Looking up status for ".$device -> {"name"});

        my $status = $devices -> get_device_status($device -> {"id"})
            or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"%(error)s" => $devices -> errstr()}));

        # Convert status booleans
        $status -> {"alive"}   = $status -> {"alive"} ? JSON::true : JSON::false;
        $status -> {"running"} = $status -> {"running"} ? JSON::true : JSON::false;
        $status -> {"working"} = $status -> {"working"} ? JSON::true : JSON::false;

        # Work out the screenshot URLs
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

        push(@response, { "id"          => $device -> {"id"},
                          "name"        => $device -> {"name"},
                          "description" => $device -> {"description"},
                          "status"      => $status,
                          "statusstr"   => {
                              "alive"   => $self -> {"template"} -> replace_langvar($status -> {"alive"}   ? "MANAGE_DEV_ALIVE_YES"   : "MANAGE_DEV_ALIVE_NO"),
                              "running" => $self -> {"template"} -> replace_langvar($status -> {"running"} ? "MANAGE_DEV_RUNNING_YES" : "MANAGE_DEV_RUNNING_NO"),
                              "working" => $self -> {"template"} -> replace_langvar($status -> {"working"} ? "MANAGE_DEV_WORKING_YES" : "MANAGE_DEV_WORKING_NO"),
                          }
             });
    }

    return \@response;
}


sub _build_post_device_reboot_response {
    my $self    = shift;
    my $devname = shift;

    return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"%(error)s" => "Illegal characters in device name"}))
        unless($devname =~ /^\w+$/);

    my $devices = $self -> {"module"} -> load_module("BigScreen::System::Devices")
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"%(error)s" => $self -> {"module"} -> errstr()}));

    my $device = $devices -> get_device_byname($devname)
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"%(error)s" => $devices -> errstr()}));

    $devices -> reboot_device($device -> {"id"})
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"%(error)s" => $devices -> errstr()}));

    return $self -> _build_get_devices_response($devname);
}


sub _build_post_device_setip_response {
    my $self    = shift;
    my $devname = shift;

    return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"%(error)s" => "Illegal characters in device name"}))
        unless($devname =~ /^\w+$/);

    my $devices = $self -> {"module"} -> load_module("BigScreen::System::Devices")
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"%(error)s" => $self -> {"module"} -> errstr()}));

    my $device = $devices -> get_device_byname($devname)
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"%(error)s" => $devices -> errstr()}));

    $self -> log("api:update", "Setting IP address for device '$devname' (".$device -> {"id"}.") to '".$self -> {"cgi"} -> remote_addr()."'");

    $devices -> set_device_ip($device -> {"id"}, $self -> {"cgi"} -> remote_addr())
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"%(error)s" => $devices -> errstr()}));

    return $self -> _build_get_devices_response($devname);
}


sub _build_devices_response {
    my $self     = shift;
    my $pathinfo = shift;

    if($self -> {"cgi"} -> request_method() eq "GET") {
        return $self -> _build_get_devices_response($pathinfo -> [2]);

    } elsif($self -> {"cgi"} -> request_method() eq "POST") {
        my $reboot = $self -> api_param("reboot", 0, $pathinfo);
        my $setip  = $self -> api_param("setip" , 0, $pathinfo);

        if($reboot) {
            return $self -> _build_post_device_reboot_response($pathinfo -> [2]);
        } elsif($setip) {
            return $self -> _build_post_device_setip_response($pathinfo -> [2]);
        }
    }

    return $self -> api_errorhash("bad_request", $self -> {"template"} -> replace_langvar("API_BAD_REQUEST"));
}


# ============================================================================
#  Interface functions

## @method $ page_display()
# Produce the string containing this block's full page content. This generates
# the compose page, including any errors or user feedback.
#
# @capabilities api.grade
#
# @return The string containing this block's page content.
sub page_display {
    my $self = shift;

    $self -> api_token_login();

    # Is this an API call, or a normal page operation?
    my $apiop = $self -> is_api_operation();
    if(defined($apiop)) {
        # API operations that are callable by anonymous users first
        given($apiop) {
            when("slides")  { $self -> api_response($self -> _build_slides_response()); }
        }

        # General API permission check - will block anonymous users at a minimum
        return $self -> api_response($self -> api_errorhash('permission',
                                                            "You do not have permission to use the API"))
            unless($self -> check_permission('api.use'));

        my @pathinfo = $self -> {"cgi"} -> multi_param('api');

        # API call - dispatch to appropriate handler.
        given($apiop) {
            when("token")   { $self -> api_response($self -> _build_token_response());  }
            when("devices") { $self -> api_response($self -> _build_devices_response(\@pathinfo)); }

            when("") { return $self -> _show_api_docs(); }

            default {
                return $self -> api_response($self -> api_errorhash('bad_op',
                                                                    $self -> {"template"} -> replace_langvar("API_BAD_OP")))
            }
        }
    } else {
        return $self -> _show_api_docs();
    }
}

1;
