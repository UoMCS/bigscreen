## @file
# This file contains the implementation of the BigScreen user toolbar.
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

## @class BigScreen::Userbar
# The Userbar class encapsulates the code required to generate and
# manage the user toolbar.
package BigScreen::Userbar;

use strict;
use base qw(BigScreen);
use experimental qw(smartmatch);
use v5.12;


# ==============================================================================
#  Bar generation

## @method $ block_display($title, $current, $doclink)
# Generate a user toolbar, populating it as needed to reflect the user's options
# at the current time.
#
# @param title   A string to show as the page title.
# @param current The current page name.
# @param doclink The name of a document link to include in the userbar. If not
#                supplied, no link is shown.
# @return A string containing the user toolbar html on success, undef on error.
sub block_display {
    my $self    = shift;
    my $title   = shift;
    my $current = shift;
    my $doclink = shift;

    $self -> clear_error();

    my $urls = { "%(url-signin)s"  => $self -> build_url(block => "login",
                                                         fullurl  => 1,
                                                         pathinfo => [],
                                                         params   => {},
                                                         forcessl => 1),
                 "%(url-signout)s" => $self -> build_url(block => "login",
                                                         fullurl  => 1,
                                                         pathinfo => [ "signout" ],
                                                         params   => {},
                                                         forcessl => 1),
                 "%(url-signup)s"  => $self -> build_url(block => "login",
                                                         fullurl  => 1,
                                                         pathinfo => [ "signup" ],
                                                         params   => {},
                                                         forcessl => 1),
                 "%(url-front)s"   => $self -> build_url(block    => $self -> {"settings"} -> {"config"} -> {"default_block"},
                                                         fullurl  => 1,
                                                         pathinfo => [],
                                                         params   => {}),
                 "%(url-manage)s"  => $self -> build_url(block    => "manage",
                                                         fullurl  => 1,
                                                         pathinfo => [],
                                                         params   => {}),
                 "%(url-devices)s" => $self -> build_url(block    => "devices",
                                                         fullurl  => 1,
                                                         pathinfo => [],
                                                         params   => {}),
    };

    my ($userprofile, $sidemenu);

    # Is the user logged in?
    if(!$self -> {"session"} -> anonymous_session()) {
        my $user = $self -> {"session"} -> get_user_byid()
            or return $self -> self_error("Unable to obtain user data for logged in user. This should not happen!");

        my $controls = "";

        # User is logged in, so actually reflect their current options and state
        $userprofile = $self -> {"template"} -> load_template("userbar/profile_signedin.tem",
                                                              { "%(realname)s" => $user -> {"fullname"},
                                                                "%(username)s" => $user -> {"username"},
                                                                "%(gravhash)s" => $user -> {"gravatar_hash"},
                                                              });

        # If the user has permission to manage, enable the option
        $controls = $self -> {"template"} -> load_template("sidemenu/controls.tem")
            if($self -> check_permission("manage"));

        $sidemenu = $self -> {"template"} -> load_template("sidemenu/signedin.tem",
                                                           { "%(realname)s" => $user -> {"fullname"},
                                                             "%(username)s" => $user -> {"username"},
                                                             "%(gravhash)s" => $user -> {"gravatar_hash"},
                                                             "%(controls)s" => $controls,
                                                           });

    } else {
        my ($topsignup, $sidesignup) = ("", "");

        if($self -> {"settings"} -> {"config"} -> {"Login:allow_self_register"}) {
            $topsignup  = $self -> {"template"} -> load_template("userbar/profile_signup.tem");
            $sidesignup = $self -> {"template"} -> load_template("sidemenu/signup.tem");
        }

        $userprofile = $self -> {"template"} -> load_template("userbar/profile_signedout.tem",
                                                              { "%(signup)s" => $topsignup });

        $sidemenu = $self -> {"template"} -> load_template("sidemenu/signedout.tem",
                                                           { "%(signup)s" => $sidesignup });
    }

    return ( $self -> {"template"} -> load_template("userbar/userbar.tem",
                                                    { "%(pagename)s"  => $title,
                                                      "%(profile)s"   => $userprofile,
                                                      %{ $urls }
                                                    }),
             $self -> {"template"} -> process_template($sidemenu, $urls)
        );
}


## @method $ page_display()
# Produce the string containing this block's full page content. This is primarily provided for
# API operations that allow the user to change their profile and settings.
#
# @return The string containing this block's page content.
sub page_display {
    my $self = shift;
    my ($content, $extrahead, $title);

    if(!$self -> {"session"} -> anonymous_session()) {
        my $user = $self -> {"session"} -> get_user_byid()
            or return '';

        my $apiop = $self -> is_api_operation();
        if(defined($apiop)) {
            given($apiop) {
                default {
                    return $self -> api_html_response($self -> api_errorhash('bad_op',
                                                                             $self -> {"template"} -> replace_langvar("API_BAD_OP")))
                }
            }
        }
    }

    return "<p class=\"error\">".$self -> {"template"} -> replace_langvar("BLOCK_PAGE_DISPLAY")."</p>";
}

1;
