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
package BigScreen::Manage;

use strict;
use experimental 'smartmatch';
use base qw(BigScreen);
use BigScreen::System::SlideSource;
use HTML::Entities;
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


## @method private $ _build_arg_row($arg, $value)
# Given an feed argument and the value set for it, produce a HTML fragment to
# include in the feed row.
#
# @param arg   The name of the argument.
# @param value The value set for the argument.
# @return A string containing the HTML to show for this argument.
sub _build_arg_row {
    my $self  = shift;
    my $arg   = shift;
    my $value = shift;

    return $self -> {"template"} -> load_template("manage/feedarg.tem",
                                                  { "%(argument)s" => $arg,
                                                    "%(value)s"    => encode_entities($value) });
}


## @method private $ _build_source_row($source)
# Generate a row to show in the sources list for the specified source. This will
# create a fragment of HTML representing the provided source, along with controls
# to manage its status and settings, and to delete it.
#
# @param source A reference to a hash containing the slide source information.
# @return A string containing the HTML fragment for this source.
sub _build_source_row {
    my $self   = shift;
    my $source = shift;

    my @args = ();
    foreach my $arg (sort keys %{$source -> {"args"}}) {
        push(@args, $self -> _build_arg_row($arg, $source -> {"args"} -> {$arg}));
    }

    my $arglist = join("", @args)  ||
        $self -> {"template"} -> load_template("manage/argsempty.tem");

    return $self -> {"template"} -> load_template("manage/feed.tem",
                                                  { "%(id)s"         => $source -> {"id"},
                                                    "%(enabled)s"    => $source -> {"enabled"} ? "on" : "off",
                                                    "%(toggle)s"     => $source -> {"enabled"} ? "on" : "off",
                                                    "%(mode-title)s" => $source -> {"enabled"} ? "{L_MANAGE_DISABLE}" : "{L_MANAGE_ENABLE}",
                                                    "%(module)s"     => $source -> {"name"},
                                                    "%(notes)s"      => $source -> {"notes"},
                                                    "%(arguments)s"  => $arglist,
                                                    "%(edit-url)s"   => $self -> build_url(block => "manage",
                                                                                           pathinfo => [ "edit", $source -> {"id"} ],
                                                                                           params   => ""),
                                                    "%(delete-url)s" => $self -> build_url(block    => "manage",
                                                                                           pathinfo => [ "delete", $source -> {"id"} ],
                                                                                           params   => ""),
                                                    "%(mode-url)s"   => $self -> build_url(block    => "manage",
                                                                                           pathinfo => [ $source -> {"enabled"} ? "disable" : "enable" , $source -> {"id"} ],
                                                                                           params   => ""),
                                                  });
}


# ============================================================================
#  validators

sub _validate_source {
    my $self    = shift;
    my $modlist = shift;
    my ($args, $error, $errors) = ( {}, "", "" );

    ($args -> {"module_id"}, $error) = $self -> validate_options("module", { required   => 1,
                                                                             default    => "",
                                                                             source     => $modlist,
                                                                             nicename   => "{L_MANAGE_MODULE}" });
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", { "%(error)s" => $error })
        if($error);

    ($args -> {"args"}, $error) = $self -> validate_string("args", { required   => 1,
                                                                     default    => "",
                                                                     nicename   => "{L_MANAGE_ARGS}" });
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", { "%(error)s" => $error })
        if($error);

    ($args -> {"notes"}, $error) = $self -> validate_string("notes", { required   => 0,
                                                                       default    => "",
                                                                       nicename   => "{L_MANAGE_NOTES}" });
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", { "%(error)s" => $error })
        if($error);

    return ($args, $errors);
}


sub _validate_new {
    my $self    = shift;
    my $modlist = shift;

    my ($args, $errors) = $self -> _validate_source($modlist);
    return ($args, $errors)
        if($errors);

    $self -> log("manage.new", "User added slide source ".$args -> {"module"}." with note ".$args -> {"notes"} // "not set");
    $self -> {"sources"} -> create($args -> {"module_id"},
                                   decode_entities($args -> {"args"}),
                                   $args -> {"notes"})
        or return ($args, $self -> {"template"} -> load_template("error/error_item.tem", { "%(error)s" => $self -> {"sources"} -> errstr() }));

    return (undef, undef);
}


sub _validate_edit {
    my $self     = shift;
    my $sourceid = shift;
    my $modlist  = shift;

    my ($args, $errors) = $self -> _validate_source($modlist);
    return ($args, $errors)
        if($errors);

    $self -> log("manage.edit", "User updated slide source $sourceid, module ".$args -> {"module"}." with note ".$args -> {"notes"} // "not set");
    $self -> {"sources"} -> update($sourceid,
                                   $args -> {"module_id"},
                                   decode_entities($args -> {"args"}),
                                   $args -> {"notes"})
        or return ($args, $self -> {"template"} -> load_template("error/error_item.tem", { "%(error)s" => $self -> {"sources"} -> errstr() }));

    return (undef, undef);
}


# ============================================================================
#  Request handlers

sub _handle_state_change {
    my $self     = shift;
    my $sourceid = shift;
    my $status   = shift;

    # NOTE: This does no permissions checks here - it relies on the manage permission
    # being checked by the caller.

    # Check that the source ID seems valid
    return $self -> _fatal_error("{L_MANAGE_ERR_NOSID}")
        unless($sourceid);

    return $self -> _fatal_error("{L_MANAGE_ERR_BADSID}")
        unless($sourceid =~ /^\d+$/);

    # Make sure the state is valid
    return $self -> _fatal_error("{L_MANAGE_ERR_BADSTATE}")
        unless($status =~ /^[01]$/);

    $self -> log("manage.state", "User has changed slide source $sourceid to status $status");

    # And away we go
    $self -> {"sources"} -> set_slide_status($sourceid, $status);

    return $self -> _handle_default();
}


sub _handle_new {
    my $self   = shift;
    my $args   = {};
    my $errors = "";

    my $modules = $self -> {"sources"} -> get_slide_modules()
        or return $self -> _fatal_error("Unable to obtain a list of slide modules");

    # process the module list into something usable
    my @modlist = ();
    my @moddesc = ();
    foreach my $module (@{$modules}) {
        push(@modlist, { "name"  => $module -> {"name"},
                         "value" => $module -> {"id"} });

        push(@moddesc, $self -> {"template"} -> load_template("manage/moddesc.tem",
                                                              { "%(name)s"        => $module -> {"name"},
                                                                "%(description)s" => $module -> {"description"},
                                                                "%(arginfo)s"     => $module -> {"arginfo"}
                                                              }));
    }

    # Now pick up and handle validation
    if($self -> {"cgi"} -> param("new")) {
        $self -> log("manage.new", "User has submitted data for new source");

        # Validate the submission - passing the module list so it can be used for validation
        ($args, $errors) = $self -> _validate_new(\@modlist);

        return $self -> redirect($self -> build_url(block    => "manage",
                                                    pathinfo => [ ],
                                                    params   => "",
                                                    api      => [] ))
            if(!$errors);
    }

    if($errors) {
        $self -> log("manage.new", "Errors detected in addition: $errors");

        my $errorlist = $self -> {"template"} -> load_template("error/error_list.tem", {"%(message)s" => "{L_MANAGE_ERR_NEWERR}",
                                                                                        "%(errors)s"  => $errors });
        $errors = $self -> {"template"} -> load_template("error/page_error.tem", { "%(message)s" => $errorlist });
    }

    return ("{L_SIDE_MANAGE}",
            $self -> {"template"} -> load_template("manage/new.tem",
                                                   { "%(front-url)s" => $self -> build_url(block => "manage",
                                                                                           pathinfo => [ ],
                                                                                           params   => ""),
                                                     "%(modopts)s" => $self -> {"template"} -> build_optionlist(\@modlist, $args -> {"module_id"}),
                                                     "%(errors)s"  => $errors,
                                                     "%(args)s"    => encode_entities($args -> {"args"}),
                                                     "%(notes)s"   => $args -> {"notes"},
                                                     "%(moddesc)s" => join("", @moddesc),
                                                   }),
            $self -> {"template"} -> load_template("manage/extrahead.tem"),
        );
}


sub _handle_edit {
    my $self     = shift;
    my $sourceid = shift;

    # Check that the source ID seems valid
    return $self -> _fatal_error("{L_MANAGE_ERR_NOSID}")
        unless($sourceid);

    return $self -> _fatal_error("{L_MANAGE_ERR_BADSID}")
        unless($sourceid =~ /^\d+$/);

    my $args   = $self -> {"sources"} -> get_slide_source($sourceid)
        or return $self -> _fatal_error($self -> {"sources"} -> errstr());

    my $errors = "";

    my $modules = $self -> {"sources"} -> get_slide_modules()
        or return $self -> _fatal_error("Unable to obtain a list of slide modules");

    # process the module list into something usable
    my @modlist = ();
    my @moddesc = ();
    foreach my $module (@{$modules}) {
        push(@modlist, { "name"  => $module -> {"name"},
                         "value" => $module -> {"id"} });

        push(@moddesc, $self -> {"template"} -> load_template("manage/moddesc.tem",
                                                              { "%(name)s"        => $module -> {"name"},
                                                                "%(description)s" => $module -> {"description"},
                                                                "%(arginfo)s"     => $module -> {"arginfo"}
                                                              }));
    }

    # Now pick up and handle validation
    if($self -> {"cgi"} -> param("edit")) {
        $self -> log("manage.edit", "User has submitted data for source edit");

        # Validate the submission - passing the module list so it can be used for validation
        ($args, $errors) = $self -> _validate_edit($sourceid, \@modlist);

        return $self -> redirect($self -> build_url(block    => "manage",
                                                    pathinfo => [ ],
                                                    params   => "",
                                                    api      => [] ))
            if(!$errors);
    }

    if($errors) {
        $self -> log("manage.edit", "Errors detected in edit: $errors");

        my $errorlist = $self -> {"template"} -> load_template("error/error_list.tem", {"%(message)s" => "{L_MANAGE_ERR_EDITERR}",
                                                                                        "%(errors)s"  => $errors });
        $errors = $self -> {"template"} -> load_template("error/page_error.tem", { "%(message)s" => $errorlist });
    }

    return ("{L_SIDE_MANAGE}",
            $self -> {"template"} -> load_template("manage/edit.tem",
                                                   { "%(front-url)s" => $self -> build_url(block => "manage",
                                                                                           pathinfo => [ ],
                                                                                           params   => ""),
                                                     "%(modopts)s" => $self -> {"template"} -> build_optionlist(\@modlist, $args -> {"module_id"}),
                                                     "%(errors)s"  => $errors,
                                                     "%(args)s"    => encode_entities($args -> {"args"}),
                                                     "%(notes)s"   => $args -> {"notes"},
                                                     "%(moddesc)s" => join("", @moddesc),
                                                   }),
            $self -> {"template"} -> load_template("manage/extrahead.tem"),
        );
}


sub _handle_delete {
    my $self     = shift;
    my $sourceid = shift;

    # NOTE: This does no permissions checks here - it relies on the manage permission
    # being checked by the caller.

    # Check that the source ID seems valid
    return $self -> _fatal_error("{L_MANAGE_ERR_NOSID}")
        unless($sourceid);

    return $self -> _fatal_error("{L_MANAGE_ERR_BADSID}")
        unless($sourceid =~ /^\d+$/);

    $self -> log("manage.delete", "User has deleted slide source $sourceid");

    # And away we go
    $self -> {"sources"} -> delete($sourceid)
        or return $self -> _fatal_error($self -> {"sources"} -> errstr());

    return $self -> _handle_default();
}


sub _handle_default {
    my $self = shift;

    my $sources = $self -> {"sources"} -> get_slide_sources(1) # Set all argument to get disabled sources
        or return $self -> _fatal_error("Unable to obtain a list of slide sources");

    my $feedlist = join("", map { $self -> _build_source_row($_) } @{$sources}) ||
                     $self -> {"template"} -> load_template("manage/listempty.tem");

    return ("{L_SIDE_MANAGE}",
            $self -> {"template"} -> load_template("manage/front.tem",
                                                   { "%(front-url)s" => $self -> build_url(block => "manage",
                                                                                           pathinfo => [ ],
                                                                                           params   => ""),
                                                     "%(feed-list)s" => $feedlist,
                                                     "%(new-url)s"   => $self -> build_url(block => "manage",
                                                                                           pathinfo => [ "new" ],
                                                                                           params   => ""),
                                                   }),
            $self -> {"template"} -> load_template("manage/extrahead.tem"),
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

    if($self -> check_permission("manage")) {
        given($pathinfo[0]) {
            when("enable")  { ($title, $body, $extrahead, $extrajs) = $self -> _handle_state_change($pathinfo[1], 1); }
            when("disable") { ($title, $body, $extrahead, $extrajs) = $self -> _handle_state_change($pathinfo[1], 0); }
            when("new")     { ($title, $body, $extrahead, $extrajs) = $self -> _handle_new(); }
            when("edit")    { ($title, $body, $extrahead, $extrajs) = $self -> _handle_edit($pathinfo[1]); }
            when("delete")  { ($title, $body, $extrahead, $extrajs) = $self -> _handle_delete($pathinfo[1]); }
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
