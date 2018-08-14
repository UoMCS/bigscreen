# @file
# This file contains the implementation of the base Slide Source class
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
package BigScreen::SlideShow;

use strict;
use experimental 'smartmatch';
use parent qw(BigScreen);
use BigScreen::System::SlideSource;
use DateTime;
use v5.12;


# ============================================================================
#  Constructor

## @cmethod $ new(%args)
# Overloaded constructor for the SlideShow, loads the System::SlideShow model
# and other classes required to generate slideshow pages.
#
# @param args A hash of values to initialise the object with. See the Block docs
#             for more information.
# @return A reference to a new BigScreen::SlideShow object on success, undef on error.
sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = $class -> SUPER::new(@_)
        or return undef;

    $self -> {"sources"} = $self -> {"module"} -> load_module("BigScreen::System::SlideSource")
        or return Webperl::SystemModule::set_error("Slide show module object creation failed: ".$self -> {"module"} -> errstr());

    return $self;
}


# ============================================================================
#  Content generator

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


## @method private @ _handle_default()
# Generate the default page content. This will generate the slideshow page
# by loading each of the slide sources, collating the slide data they provide,
# and returning a HTML page containing the slideshow.
#
# @return An array containing the page title, content, extrahead, and extrajs
sub _handle_default {
    my $self   = shift;

    my $slides = $self -> {"sources"} -> get_slides();

    # Handle buttons
    my $buttons = "";
    my $slide = 0;
    my @outslides;
    foreach my $setslide (@{$slides}) {

        # This should not happen, but detect and avoid empty slides
        if(!$setslide) {
            print STDERR "Slide $slide is empty!!!\n";
            next;
        }

        push(@outslides, $self -> {"template"} -> process_template($setslide,
                                                                   { "%(active)s"   => $slide ? "" : "is-active",
                                                                     "%(style)s"    => $slide ? "display: none" : "",
                                                                     "%(slidenum)s" => $slide
                                                                   }));

        $buttons .= $self -> {"template"} -> load_template("slideshow/button.tem",
                                                           { "%(active)s"   => $slide ? "" : "is-active",
                                                             "%(slidenum)s" => $slide
                                                           });
             ++$slide;
    }

    my @options = ( "minDelay: ".(($self -> {"settings"} -> {"config"} -> {"Orbit:delay"} // 10) * 1000),
        );


    return ("{L_SLIDES_TITLE}",
            $self -> {"template"} -> load_template("slideshow/content.tem",
                                                   { "%(slides)s"        => join("", @outslides),
                                                     "%(buttons)s"       => $buttons,
                                                     "%(options)s"       => join(";", @options),
                                                     "%(orbit-delay)s"   => $self -> {"settings"} -> {"config"} -> {"Orbit:delay"} // 10,
                                                   }),
            $self -> {"template"} -> load_template("slideshow/extrahead.tem"),
            $self -> {"template"} -> load_template("slideshow/extrajs.tem",
                                                   {"%(orbit-maxdelay)s"   => $self -> {"settings"} -> {"config"} -> {"Orbit:maxDelay"} // 10,
                                                    "%(orbit-mindelayms)s" => ($self -> {"settings"} -> {"config"} -> {"Orbit:minDelay"} // 10) * 1000,
                                                    "%(orbit-maxdelayms)s" => ($self -> {"settings"} -> {"config"} -> {"Orbit:maxDelay"} // 10) * 1000,
                                                    "%(orbit-loops)s"      => $self -> {"settings"} -> {"config"} -> {"Orbit:loops"} // 3,
                                                   })
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

    given($pathinfo[0]) {
        default { ($title, $body, $extrahead, $extrajs) = $self -> _handle_default();    }
    }

    # Done generating the page content, return the filled in page template
    return $self -> generate_bigscreen_page(title     => $title,
                                            content   => $body,
                                            extrahead => $extrahead,
                                            extrajs   => $extrajs,
                                            nouserbar => 1);
}


# ============================================================================
#  Module interface functions

## @method $ page_display()
# Generate the page content for this module.
sub page_display {
    my $self = shift;

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
