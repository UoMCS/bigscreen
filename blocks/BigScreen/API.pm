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
use base qw(BigScreen);
use JSON;
use DateTime;
use v5.12;

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

sub _build_token_response {
    my $self = shift;

    my $token = $self -> api_token_generate($self -> {"session"} -> get_session_userid())
        or return $self -> api_errorhash('internal_error', $self -> errstr());

    return { "token" => $token };
}


# ============================================================================
#  Interface functions

## @method $ page_display()
# Produce the string containing this block's full page content. This generates
# the compose page, including any errors or user feedback.
#
# @return The string containing this block's page content.
sub page_display {
    my $self = shift;

    $self -> api_token_login();

    # Is this an API call, or a normal page operation?
    my $apiop = $self -> is_api_operation();
    if(defined($apiop)) {
        # General API permission check - will block anonymous users at a minimum
        return $self -> api_response($self -> api_errorhash('permission',
                                                            "You do not have permission to use the API"))
            unless($self -> check_permission('api.use'));

        # API call - dispatch to appropriate handler.
        given($apiop) {

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
