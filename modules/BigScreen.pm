## @file
# This file contains the implementation of the BigScreen block base class.
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
#
package BigScreen;

use strict;
use experimental qw(smartmatch);
use v5.14;

use base qw(Webperl::Block); # Features are just a specific form of Block
use Digest;
use CGI::Util qw(escape);
use HTML::Entities;
use Webperl::Utils qw(join_complex path_join hash_or_hashref);
use XML::Simple;
use DateTime;
use JSON;

# Hack the DateTime object to include the TO_JSON function needed to support
# JSON output of datetime objects. Outputs as ISO8601
sub DateTime::TO_JSON {
    my $dt = shift;

    return $dt -> format_cldr('yyyy-MM-ddTHH:mm:ssZZZZZ');
}

# ============================================================================
#  Constructor

## @cmethod $ new(%args)
# Overloaded constructor for BigScreen block modules. This will ensure that a valid
# item id has been stored in the block object data.
#
# @param args A hash of values to initialise the object with. See the Block docs
#             for more information.
# @return A reference to a new BigScreen object on success, undef on error.
sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = $class -> SUPER::new(entitymap => { '&ndash;'  => '-',
                                                       '&mdash;'  => '-',
                                                       '&rsquo;'  => "'",
                                                       '&lsquo;'  => "'",
                                                       '&ldquo;'  => '"',
                                                       '&rdquo;'  => '"',
                                                       '&hellip;' => '...',
                                                       '&gt;'     => '>',
                                                       '&lt;'     => '<',
                                                       '&amp;'    => '&',
                                                       '&nbsp;'   => ' ',
                                        },
                                        api_auth_header => 'Private-Token',
                                        api_auth_keylen => 24,
                                        @_)
        or return undef;

    return $self;
}


# ============================================================================
#  HTML generation support

## @method void redirect($url)
# Redirect the user to the specified url.
#
# @param url The URL to send the user to.
sub redirect {
    my $self = shift;
    my $url  = shift;

    # There is ambiguity about whether 302/303 responses should contain cookies,
    # but all major browsers support doing this as of at least 2012 - see
    #  http://blog.dubbelboer.com/2012/11/25/302-cookie.html
    print $self -> {"cgi"} -> redirect( -url     => $url,
                                        -charset => 'utf-8',
                                        -cookie  => $self -> {"session"} -> session_cookies());

    # Prevent circular references from messing up shutdown
    $self -> {"template"} -> set_module_obj(undef) if($self -> {"template"});
    $self -> {"messages"} -> set_module_obj(undef) if($self -> {"messages"});
    $self -> {"system"} -> clear() if($self -> {"system"});
    $self -> {"appuser"} -> set_system(undef) if($self -> {"appuser"});

    $self -> {"dbh"} -> disconnect() if($self -> {"dbh"});
    $self -> {"logger"} -> end_log() if($self -> {"logger"});
    exit;
}


## @method $ generate_bigscreen_page(%args)
# A convenience function to wrap page content in the standard page template. This
# function allows blocks to embed their content in a page without having to build
# the whole page including "common" items themselves. It should be called to wrap
# the content when the block's page_display is returning. Supported arguments are:
#
# - `title`:     The page title.
# - `content`:   The content to show in the page.
# - `leftmenu`:  Optional content to show in a left popup menu.
# - `extrahead`: Any extra directives to place in the header.
# - `extrajs`:   Any extra javascript to place in the footer.
# - `doclink`:   The name of a document link to include in the userbar. If not
#                supplied, no link is shown.
# @return A string containing the page.
sub generate_bigscreen_page {
    my $self = shift;
    my $args = hash_or_hashref(@_);

    my $userbar = $self -> {"module"} -> load_module("BigScreen::Userbar");

    my ($topbar, $leftbar) = $userbar -> block_display($args -> {"title"}, $self -> {"block"}, $args -> {"doclink"});
    return $self -> {"template"} -> load_template("page.tem", {"%(extrahead)s" => $args -> {"extrahead"} // "",
                                                               "%(extrajs)s"   => $args -> {"extrajs"} // "",
                                                               "%(title)s"     => $args -> {"title"} // "",
                                                               "%(leftmenu)s"  => $leftbar,
                                                               "%(userbar)s"   => $topbar,
                                                               "%(content)s"   => $args -> {"content"}});
}


## @method $ generate_errorbox(%args)
# Generate the HTML to show in the page when a fatal error has been encountered.
# The following options can be specified in the arguments:
#
# - `message`: The message to show in the page.
# - `title`:   The title to use for the error. If not set "{L_FATAL_ERROR}" is used.
#
# @param args A hash, or reference to a hash, of options.
# @return A string containing the page
sub generate_errorbox {
    my $self = shift;
    my $args = hash_or_hashref(@_);

    $self -> log("error:fatal", $args -> {"message"});

    return ($args -> {"title"},
            $self -> message_box(title   => $args -> {"title"} // "{L_FATAL_ERROR}",
                                 type    => "error",
                                 class   => "alert",
                                 summary => "{L_FATAL_ERROR_SUMMARY}",
                                 message => $args -> {"message"},
                                 buttons => [ { "message" => "{L_SITE_CONTINUE}",
                                                "colour"  => "standard",
                                                "href"    => "{V_[scriptpath]}"
                                              }
                                 ])
        );
}


## @method $ message_box(%args)
# Create a message box block to include in a page. This generates a templated
# message box to include in a page. It assumes the presence of messagebox.tem
# in the template directory, containing markers for a title, type, summary,
# long description and additional data. The type argument should correspond
# to an image in the {template}/images/messages/ directory without an extension.
# Supported arguments are:
#
#  - `title`:      The title of the message box.
#  - `type`:       The message type.
#  - `class`:      Optional additional classes to set on the box.
#  - `summary`:    A summary version of the message.
#  - `message`:    The full message body
#  - `additional`: Any additional content to include in the message box.
#  - `buttons`:    Optional reference to an array of hashes containing button
#                  data. Each hash in the array should contain three keys:
#                  - `colour`: specifies the button colour
#                  - `href`: the href to set in the button
#                  - `message`: the message to show in the button.
#
# @param args A hash, or reference to a hash, of arguments.
# @return A string containing the message box.
sub message_box {
    my $self = shift;
    my $args = hash_or_hashref(@_);

    my $buttonbar = "";

    # Has the caller specified any buttons?
    if($args -> {"buttons"}) {

        # Build the list of buttons...
        my $buttonlist = "";
        foreach my $button (@{$args -> {"buttons"}}) {
            $buttonlist .= $self -> {"template"} -> load_template("messagebox/button.tem",
                                                                  { "%(colour)s"  => $button -> {"colour"},
                                                                    "%(href)s"    => $button -> {"href"},
                                                                    "%(message)s" => $button -> {"message"}
                                                                  });
        }

        # Shove into the bar
        $buttonbar = $self -> {"template"} -> load_template("messagebox/buttonbar.tem",
                                                            { "%(buttons)s" => $buttonlist });
    }

    return $self -> {"template"} -> load_template("messagebox/box.tem",
                                                  { "%(title)s"      => $args -> {"title"},
                                                    "%(icon)s"       => $args -> {"type"} // "important",
                                                    "%(summary)s"    => $args -> {"summary"},
                                                    "%(message)s"    => $args -> {"message"},
                                                    "%(additional)s" => $args -> {"additional"},
                                                    "%(class)s"      => $args -> {"class"} // "secondary",
                                                    "%(buttons)s"    => $buttonbar,
                                                  });
}


# ============================================================================
#  Permissions/Roles related.

## @method $ check_permission($action, $contextid, $userid)
# Determine whether the user has permission to peform the requested action. This
# should be overridden in subclasses to provide actual checks.
#
# @param action    The action the user is attempting to perform.
# @param contextid The ID of the metadata context the user is trying to perform
#                  an action in. If this is not given, the root context is used.
# @param userid    The ID of the user to check the permissions for. If not
#                  specified, the current session user is used.
# @return true if the user has permission, false if they do not, undef on error.
sub check_permission {
    my $self      = shift;
    my $action    = shift;
    my $contextid = shift || $self -> {"system"} -> {"roles"} -> {"root_context"};
    my $userid    = shift || $self -> {"session"} -> get_session_userid();

    return $self -> {"system"} -> {"roles"} -> user_has_capability($contextid, $userid, $action);
}


## @method $ check_login()
# Determine whether the current user is logged in, and if not force them to
# the login form.
#
# @return undef if the user is logged in and has access, otherwise a page to
#         send back with a permission error. If the user is not logged in, this
#         will 'silently' redirect the user to the login form.
sub check_login {
    my $self = shift;

    # Anonymous users need to get punted over to the login form
    if($self -> {"session"} -> anonymous_session()) {
        $self -> log("error:anonymous", "Redirecting anonymous user to login form");

        print $self -> {"cgi"} -> redirect($self -> build_login_url());
        exit;

    # Otherwise, permissions need to be checked
    } elsif(!$self -> check_permission("view")) {
        $self -> log("error:permission", "User does not have perission 'view'");

        # Logged in, but permission failed
        my $message = $self -> message_box(title   => "{L_PERMISSION_FAILED_TITLE}",
                                           type    => "error",
                                           class   => "alert",
                                           summary => "{L_PERMISSION_FAILED_SUMMARY}",
                                           message => "{L_PERMISSION_VIEW_DESC}",
                                           buttons => [ {"message" => $self -> {"template"} -> replace_langvar("SITE_CONTINUE"),
                                                         "colour"  => "blue",
                                                         "href"    => "{V_[scriptpath]}"} ]);

        return $self -> generate_bigscreen_page(title   => "{L_PERMISSION_FAILED_TITLE}",
                                                content => $message);
    }

    return undef;
}


# ============================================================================
#  API support

## @method $ is_api_operation()
# Determine whether the feature is being called in API mode, and if so what operation
# is being requested.
#
# @return A string containing the API operation name if the script is being invoked
#         in API mode, undef otherwise. Note that, if the script is invoked in API mode,
#         but no operation has been specified, this returns an empty string.
sub is_api_operation {
    my $self = shift;

    my @api = $self -> {"cgi"} -> multi_param('api');

    # No api means no API mode.
    return undef unless(scalar(@api));

    # API mode is set by placing 'api' in the first api entry. The second api
    # entry is the operation.
    return $api[1] || "" if($api[0] eq 'api');

    return undef;
}


## @method $ api_param($param, $hasval, $params)
# Determine whether an API parameter has been set, and optionally return
# its value. This checks through the list of API parameters specified and,
# if the named parameter is present, this will either return the value
# that follows it in the parameter list if $hasval is true, or it will
# simply return true to indicate the parameter is present.
#
# @param param  The name of the API parameter to search for.
# @param hasval If true, expect the value following the parameter in the
#               list of parameters to be the value thereof, and return it.
#               If false, this will return true if the parameter is present.
# @param params An optional reference to a list of parameters. If making
#               multiple calls to api_param, grabbing the api parameter
#               list beforehand and passing a reference to that into each
#               api_param call will help speed the process up a bit.
# @return The value for the parameter if it is set and hasval is true,
#         otherwise true if the paramter is present. If the parameter is
#         not present, this will return undef.
sub api_param {
    my $self   = shift;
    my $param  = shift;
    my $hasval = shift;
    my $params = shift;

    if(!$params) {
        my @api = $self -> {"cgi"} -> multi_param('api');
        return undef unless(scalar(@api));

        $params = \@api;
    }

    for(my $pos = 2; $pos < scalar(@{$params}); ++$pos) {
        if($params -> [$pos] eq $param) {
            return $hasval ? $params -> [$pos + 1] : 1;
        }
    }

    return undef;
}


## @method $ api_errorhash($code, $message)
# Generate a hash that can be passed to api_response() to indicate that an error was encountered.
#
# @param code    A 'code' to identify the error. Does not need to be numeric, but it
#                should be short, and as unique as possible to the error.
# @param message The human-readable error message.
# @return A reference to a hash to pass to api_response()
sub api_errorhash {
    my $self    = shift;
    my $code    = shift;
    my $message = shift;

    return { 'error' => {
                          'info' => $message,
                          'code' => $code
                        }
           };
}


## @method $ api_html_response($data)
# Generate a HTML response containing the specified data.
#
# @param data The data to send back to the client. If this is a hash, it is
#             assumed to be the result of a call to api_errorhash() and it is
#             converted to an appropriate error box. Otherwise, the data is
#             wrapped in a minimal html wrapper for return to the client.
# @return The html response to send back to the client.
sub api_html_response {
    my $self = shift;
    my $data = shift;

    # Fix up error hash returns
    $data = $self -> {"template"} -> load_template("api/html_error.tem", {"%(code)s" => $data -> {"error"} -> {"code"},
                                                                          "%(info)s" => $data -> {"error"} -> {"info"}})
        if(ref($data) eq "HASH" && $data -> {"error"});

    return $self -> {"template"} -> load_template("api/html_wrapper.tem", {"%(data)s" => $data});
}


## @method private $ _api_status($data)
# Based on the specified data hash, determine which HTTP status code
# to use in the response.
#
# @param data A reference to a hash containing the data that will be sent to
#             the client.
# @return A HTTP status string, including code and message.
sub _api_status {
    my $self = shift;
    my $data = shift;

    return "200 OK"
        unless(ref($data) eq "HASH" && $data -> {"error"} && $data -> {"error"} -> {"code"});

    given($data -> {"error"} -> {"code"}) {
        when("bad_request")      { return "400 Bad Request"; }
        when("not_found")        { return "404 Not Found"; }
        when("permission_error") { return "403 Forbidden"; }
        when("general_error")    { return "532 Lilliputian snotweasel foxtrot omegaforce"; }
        default { return "500 Internal Server Error"; }
    }
}


## @method private void _xml_api_response($data, %xmlopts)
# Print out the specified data as a XML response.
#
# @param data    The data to send back to the client as XML.
# @param xmlopts Additional options passed to XML::Simple::XMLout. See the
#                documentation for api_response() regarding this argument.
sub _xml_api_response {
    my $self    = shift;
    my $data    = shift;
    my %xmlopts = @_;
    my $xmldata;

    $xmlopts{"XMLDecl"} = '<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>'
        unless(defined($xmlopts{"XMLDecl"}));

    $xmlopts{"KeepRoot"} = 0
        unless(defined($xmlopts{"KeepRoot"}));

    $xmlopts{"RootName"} = 'api'
        unless(defined($xmlopts{"RootName"}));

    eval { $xmldata = XMLout($data, %xmlopts); };
    $xmldata = $self -> {"template"} -> load_template("xml/error_response.tem", { "%(code)s"  => "encoding_failed",
                                                                                  "%(error)s" => "Error encoding XML response: $@"})
        if($@);

    my $status = $self -> _api_status($data);
    print $self -> {"cgi"} -> header(-type => 'application/xml',
                                     -status  => $status
                                     -charset => 'utf-8');
    if($ENV{MOD_PERL} && $status ne "200 OK") {
        $self -> {"cgi"} -> r -> rflush();
        $self -> {"cgi"} -> r -> status(200);
    }
    print Encode::encode_utf8($xmldata);
}


## @method private void _json_api_response($data)
# Print out the specified data as a JSON response.
#
# @param data The data to send back to the client as JSON.
sub _json_api_response {
    my $self = shift;
    my $data = shift;

    my $json = JSON -> new();
    my $status = $self -> _api_status($data);
    print $self -> {"cgi"} -> header(-type => 'application/json',
                                     -status  => $status,
                                     -charset => 'utf-8');
    if($ENV{MOD_PERL} && $status ne "200 OK") {
        $self -> {"cgi"} -> r -> rflush();
        $self -> {"cgi"} -> r -> status(200);
    }
    print Encode::encode_utf8($json -> pretty -> convert_blessed(1) -> encode($data));
}


## @method $ api_response($data, %xmlopts)
# Generate an API response containing the specified data. This function will not return
# if it is successful - it will return an response and exit. The content generated by
# this function will be either JSON or XML depending on whether the user has specified
# an appropriate 'format=' argument, whether a system default default is set, falling back
# on JSON otherwise.
#
# @param data    A reference to a hash containing the data to send back to the client as an
#                API response.
# @param xmlopts Options passed to XML::Simple::XMLout if the respons is in XML. Note that
#                the following defaults are set for you:
#                - XMLDecl is set to '<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>'
#                - KeepRoot is set to 0
#                - RootName is set to 'api'
# @return Does not return if successful, otherwise returns undef.
sub api_response {
    my $self    = shift;
    my $data    = shift;
    my @xmlopts = @_;

    # What manner of result should be resulting?
    my $format = $self -> {"settings"} -> {"API:format"} || "json";
    $format = "json" if($self -> {"cgi"} -> param("format") && $self -> {"cgi"} -> param("format") =~ /^json$/i);
    $format = "xml"  if($self -> {"cgi"} -> param("format") && $self -> {"cgi"} -> param("format") =~ /^xml$/i);

    given($format) {
        when("xml") { $self -> _xml_api_response($data, @xmlopts); }
        default { $self -> _json_api_response($data); }
    }

    $self -> {"template"} -> set_module_obj(undef);
    $self -> {"messages"} -> set_module_obj(undef);
    $self -> {"system"} -> clear() if($self -> {"system"});
    $self -> {"session"} -> {"auth"} -> {"app"} -> set_system(undef) if($self -> {"session"} -> {"auth"} -> {"app"});

    $self -> {"dbh"} -> disconnect();
    $self -> {"logger"} -> end_log();

    exit;
}


## @method $ api_token_login()
# Determine whether the client has sent an API token as part of the http request, and
# if so establish whether the key is valid and corresponds to a user in the system.
# This will set up the global session object to be 'logged in' as the key owner,
# if they key is valid. Note that methods that rely on or generate session cookies
# are not going to operate correctly when this is used: use only for API code!
#
# @note If using token auth, https *must* be used, or you may as well remove the
# auth code entirely.
#
# @return The ID of the user the token corresponds to on success, undef if the user
#         has not provided a token header, or the token is not valid.
sub api_token_login {
    my $self = shift;

    $self -> clear_error();

    my $key = $self -> {"cgi"} -> http($self -> {"api_auth_header"});
    return undef unless($key);

    my ($checkkey) = $key =~ /^(\w+)$/;
    return undef unless($checkkey);

    my $sha256 = Digest -> new('SHA-256');
    $sha256 -> add($checkkey);
    my $crypt = $sha256 -> hexdigest();

    my $keyrec = $self -> {"dbh"} -> prepare("SELECT `user_id`
                                              FROM `".$self -> {"settings"} -> {"database"} -> {"apikeys"}."`
                                              WHERE `token` = ?
                                              AND `active` = 1
                                              ORDER BY `created` DESC
                                              LIMIT 1");
    $keyrec -> execute($crypt)
        or return $self -> self_error("Unable to look up api key: ".$self -> {"dbh"} -> errstr());

    my $keydata = $keyrec -> fetchrow_hashref()
        or return $self -> self_error("No matching api key record when looking for key '$checkkey'");

    # This is a bit of a hack, but as long as it is called before any other session
    # code in the API module, it'll fake a logged-in session.
    $self -> {"session"} -> {"sessuser"} = $keydata -> {"user_id"};

    return $keydata -> {"user_id"};
}


## @method $ api_token_generate($userid)
# Generate a guaranteed-unique API token/key for the specified user. This will record the
# new token in the database for later use, deactivating any previously-issued tokens for
# the user, and return a copy of the new token.
#
# @param userid The ID of the user to generate a token for
# @return The new token string on success, undef on error.
sub api_token_generate {
    my $self   = shift;
    my $userid = shift;
    my ($token, $crypt) = ('', '');

    $self -> clear_error();

    my $checkh = $self -> {"dbh"} -> prepare("SELECT `user_id`
                                              FROM `".$self -> {"settings"} -> {"database"} -> {"apikeys"}."`
                                              WHERE `token` = ?");

    # Generate tokens until we hit one that isn't already defined.
    do {
        $token = join("", map { ("a".."z", "A".."Z", 0..9)[rand 62] } 1..$self -> {"api_auth_keylen"});

        my $sha256 = Digest -> new('SHA-256');
        $sha256 -> add($token);
        $crypt = $sha256 -> hexdigest();

        $checkh -> execute($crypt)
            or return $self -> self_error("Unable to look up api token: ".$self -> {"dbh"} -> errstr());

    } while($checkh -> fetchrow_hashref());

    # Deactivate the user's old tokens
    my $blockh = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"apikeys"}."`
                                              SET `active` = 0
                                              WHERE `active` = 1 AND `user_id` = ?");
    $blockh -> execute($userid)
        or return $self -> self_error("Unable to deactivate old api tokens: ".$self -> {"dbh"} -> errstr());

    # And add the new token
    my $newh = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"apikeys"}."`
                                            (`user_id`, `token`, `created`)
                                            VALUES(?, ?, UNIX_TIMESTAMP())");

    my $row = $newh -> execute($userid, $crypt);
    return $self -> self_error("Unable to store token for user '$userid': ".$self -> {"dbh"} -> errstr) if(!$row);
    return $self -> self_error("Insert failed for token for user '$userid': no rows inserted") if($row eq "0E0");

    return $token;
}


# ============================================================================
#  General utility

## @method void log($type, $message)
# Log the current user's actions in the system. This is a convenience wrapper around the
# Logger::log function.
#
# @param type     The type of log entry to make, may be up to 64 characters long.
# @param message  The message to attach to the log entry, avoid messages over 128 characters.
sub log {
    my $self     = shift;
    my $type     = shift;
    my $message  = shift;

    $message = "[Item:".($self -> {"itemid"} ? $self -> {"itemid"} : "none")."] $message";
    $self -> {"logger"} -> log($type, $self -> {"session"} -> get_session_userid(), $self -> {"cgi"} -> remote_host(), $message);
}


## @method $ set_saved_state()
# Store the current status of the script, including block, api, pathinfo, and querystring
# to session variables for later restoration.
#
# @return true on success, undef on error.
sub set_saved_state {
    my $self = shift;

    $self -> clear_error();

    my $block = $self -> {"cgi"} -> param("block");
    my $res = $self -> {"session"} -> set_variable("saved_block", $block);
    return undef unless(defined($res));

    my @pathinfo = $self -> {"cgi"} -> multi_param("pathinfo");
    $res = $self -> {"session"} -> set_variable("saved_pathinfo", join("/", @pathinfo));
    return undef unless(defined($res));

    my @api = $self -> {"cgi"} -> multi_param("api");
    $res = $self -> {"session"} -> set_variable("saved_api", join("/", @api));
    return undef unless(defined($res));

    # Convert the query parameters to a string, skipping the block, pathinfo, and api
    my @names = $self -> {"cgi"} -> param;
    my @qstring = ();
    foreach my $name (@names) {
        next if($name eq "block" || $name eq "pathinfo" || $name eq "api");

        my @vals = $self -> {"cgi"} -> param($name);
        foreach my $val (@vals) {
            push(@qstring, escape($name)."=".escape($val));
        }
    }
    $res = $self -> {"session"} -> set_variable("saved_qstring", join("&amp;", @qstring));
    return undef unless(defined($res));

    return 1;
}


## @method @ get_saved_state()
# A convenience wrapper around Session::get_variable() for fetching the state saved in
# build_login_url().
#
# @return An array of strings, containing the block, pathinfo, api, and query string.
sub get_saved_state {
    my $self = shift;

    # Yes, these use set_variable. set_variable will return the value in the
    # variable, like get_variable, except that this will also delete the variable
    return ($self -> {"session"} -> set_variable("saved_block"),
            $self -> {"session"} -> set_variable("saved_pathinfo"),
            $self -> {"session"} -> set_variable("saved_api"),
            $self -> {"session"} -> set_variable("saved_qstring"));
}


## @method $ cleanup_entities($html)
# Wrangle the specified HTML into something that won't produce an unholy mess when
# passed to something that doesn't handle UTF-8 properly.
#
# @param html The HTML to process
# @return A somewhat cleaned-up string of HTML
sub cleanup_entities {
    my $self = shift;
    my $html = shift;

    $html =~ s/\r//g;
    return encode_entities($html, '^\n\x20-\x7e');
}


# ============================================================================
#  URL building

## @method $ build_login_url()
# Attempt to generate a URL that can be used to redirect the user to a login form.
# The user's current query state (course, block, etc) is stored in a session variable
# that can later be used to bring them back to the location this was called from.
#
# @return A relative login form redirection URL.
sub build_login_url {
    my $self = shift;

    # Store as much state as possible to restore after login (does not store POST
    # data!)
    $self -> set_saved_state();

    return $self -> build_url(block    => "login",
                              fullurl  => 1,
                              pathinfo => [],
                              params   => {},
                              forcessl => 1);
}


## @method $ build_return_url($fullurl)
# Pulls the data out of the session saved state, checks it for safety,
# and returns the URL the user should be redirected/linked to to return to the
# location they were attempting to access before login.
#
# @param fullurl If set to true, the generated url will contain the protocol and
#                host. Otherwise the URL will be absolute from the server root.
# @return A relative return URL.
sub build_return_url {
    my $self    = shift;
    my $fullurl = shift;
    my ($block, $pathinfo, $api, $qstring) = $self -> get_saved_state();

    # Return url block should never be "login"
    $block = $self -> {"settings"} -> {"config"} -> {"default_block"} if($block eq "login" || !$block);

    # Build the URL from them
    return $self -> build_url("block"    => $block,
                              "pathinfo" => $pathinfo,
                              "api"      => $api,
                              "params"   => $qstring,
                              "fullurl"  => $fullurl);
}


## @method $ build_url(%args)
# Build a url suitable for use at any point in the system. This takes the args
# and attempts to build a url from them. Supported arguments are:
#
# * fullurl  - if set, the resulting URL will include the protocol and host. Defaults to
#              false (URL is absolute from the host root).
# * block    - the name of the block to include in the url. If not set, the current block
#              is used if possible, otherwise the system-wide default block is used.
# * pathinfo - Either a string containing the pathinfo, or a reference to an array
#              containing pathinfo fragments. If not set, the current pathinfo is used.
# * api      - api fragments. If the first element is not "api", it is added.
# * params   - Either a string containing additional query string parameters to add to
#              the URL, or a reference to a hash of additional query string arguments.
#              Values in the hash may be references to arrays, in which case multiple
#              copies of the parameter are added to the query string, one for each
#              value in the array.
# * forcessl - If true, the URL is forced to https: rather than http:
#
# @param args A hash of arguments to use when building the URL.
# @return A string containing the URL.
sub build_url {
    my $self = shift;
    my %args = @_;
    my $base = "";

    # Default the block, item, and API fragments if needed and possible
    $args{"block"} = ($self -> {"cgi"} -> param("block") || $self -> {"settings"} -> {"config"} -> {"default_block"})
        if(!defined($args{"block"}));

    if(!defined($args{"pathinfo"})) {
        my @cgipath = $self -> {"cgi"} -> multi_param("pathinfo");
        $args{"pathinfo"} = \@cgipath if(scalar(@cgipath));
    }

    if(!defined($args{"api"})) {
        my @cgiapi = $self -> {"cgi"} -> multi_param("api");
        $args{"api"} = \@cgiapi if(scalar(@cgiapi));
    }

    # Convert the pathinfo and api to slash-delimited strings
    my $pathinfo = join_complex($args{"pathinfo"}, joinstr => "/");
    my $api      = join_complex($args{"api"}, joinstr => "/");

    # Force the API call to start 'api' if it doesn't
    $api = "api/$api" if($api && $api !~ m|^/?api|);

    # build the query string parameters.
    my $querystring = join_complex($args{"params"}, joinstr => ($args{"joinstr"} || "&amp;"), pairstr => "=", escape => 1);

    # building the URL involves shoving the bits together. path_join is intelligent enough to ignore
    # anything that is undef or "" here, so explicit checks beforehand should not be needed.
    my $url = path_join($self -> {"settings"} -> {"config"} -> {"scriptpath"}, $args{"block"}, $pathinfo, $api);
    $url = path_join($self -> {"cgi"} -> url(-base => 1), $url)
        if($args{"fullurl"});

    # Strip block, pathinfo, and api from the query string if they've somehow made it in there.
    # Note this can't simply be made 'eg' as the progressive match can leave a trailing &
    if($querystring) {
        while($querystring =~ s{((?:&(?:amp;))?)(?:api|block|pathinfo)=[^&]+(&?)}{$1 && $2 ? "&" : ""}e) {}
        $url .= "?$querystring";
    }

    $url =~ s/^http:/https:/
        if($args{"forcessl"} && $url =~ /^http:/);

    return $url;
}


# ============================================================================
#  Documentation support

## @method $ get_documentation_url($doclink)
# Given a documentation link name, obtain the URL associated with that name.
#
# @param doclink The name of the documentation link to fetch.
# @return The documentation URL if the doclink is valid, undef otherwise.
sub get_documentation_url {
    my $self    = shift;
    my $doclink = shift;

    $self -> clear_error();

    # No point trying anything if there is no link name set.
    return undef if(!$doclink);

    my $urlh = $self -> {"dbh"} -> prepare("SELECT `url`
                                            FROM `".$self -> {"settings"} -> {"database"} -> {"docs"}."`
                                            WHERE `name` LIKE ?");
    $urlh -> execute($doclink)
        or return $self -> self_error("Unable to look up documentation link: ".$self -> {"dbh"} -> errstr);

    # Fetch the url row, and if one has been found return it.
    my $url = $urlh -> fetchrow_arrayref();
    return $url ? $url -> [0] : undef;
}

1;
