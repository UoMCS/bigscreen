## @file
# This file contains the implementation of the signin/signout facility.
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
# along with this program.  If not, see http://www.gnu.org/licenses/.

## @class
# A 'stand alone' login implementation. This presents the user with a
# login form, checks the credentials they enter, and then redirects
# them back to the task they were performing that required a login.
package BigScreen::Login;

use strict;
use parent qw(BigScreen); # This class extends the BigScreen block class
use experimental qw(smartmatch);
use Webperl::Utils qw(path_join is_defined_numeric);
use LWP::UserAgent;
use JSON;
use v5.14;

# ============================================================================
#  Utility/support functions

## @method private $ _build_password_policy()
# Build a string describing the password policy for the current user. This
# interrogates the user's AuthMethod to determine the password policy in place
# for the user (if any), and generates a string describing it in a format
# suitable to present to users.
#
# @return A string containing the password policy enforced for the logged-in
#         user.
sub _build_password_policy {
    my $self     = shift;

    # Anonymous user can have no policy
    return '{L_LOGIN_PASSCHANGE_ERRNOUSER}'
        if($self -> {"session"} -> anonymous_session());

    my $user = $self -> {"session"} -> get_user_byid()
        or return '{L_LOGIN_PASSCHANGE_ERRNOUSER}';

    # Fetch the policy, and give up if there isn't one.
    my $policy = $self -> {"session"} -> {"auth"} -> get_policy($user -> {"username"})
        or return '{L_LOGIN_POLICY_NONE}';

    my $policystr = "";
    foreach my $name (@{$policy -> {"policy_order"}}) {
        next if(!$policy -> {$name});

        $policystr .= $self -> {"template"} -> load_template("login/policy.tem",
                                                             { "%(policy)s" => "{L_LOGIN_".uc($name)."}",
                                                               "%(value)s"  => $policy -> {$name} });
    }

    return $policystr;
}


# ============================================================================
#  Emailer functions

## @method private $ _signup_email($user, $password)
# Send a registration welcome message to the specified user. This send an email
# to the user including their username, password, and a link to the activation
# page for their account.
#
# @param user     A reference to a user record hash.
# @param password The unencrypted version of the password set for the user.
# @return undef on success, otherwise an error message.
sub _signup_email {
    my $self     = shift;
    my $user     = shift;
    my $password = shift;

    # Build URLs to place in the email.
    my $acturl  = $self -> build_url("fullurl"  => 1,
                                     "block"    => "login",
                                     "pathinfo" => [ "activate" ],
                                     "params"   => "actcode=".$user -> {"act_code"});
    my $actform = $self -> build_url("fullurl"  => 1,
                                     "block"    => "login",
                                     "pathinfo" => [ "activate" ]);

    my $status =  $self -> {"messages"} -> queue_message(subject => $self -> {"template"} -> replace_langvar("LOGIN_SIGNUP_SUBJECT"),
                                                         message => $self -> {"template"} -> load_template("login/email_signedup.tem",
                                                                                                           {"%(username)s" => $user -> {"username"},
                                                                                                            "%(password)s" => $password,
                                                                                                            "%(act_code)s" => $user -> {"act_code"},
                                                                                                            "%(act_url)s"  => $acturl,
                                                                                                            "%(act_form)s" => $actform,
                                                                                                           }),
                                                         recipients       => [ $user -> {"user_id"} ],
                                                         send_immediately => 1);
    return ($status ? undef : $self -> {"messages"} -> errstr());
}


## @method private $ _lockout_email($user, $password, $actcode, $faillimit)
# Send a message to a user informing them that their account has been locked, and
# they need to reactivate it.
#
# @param user      A reference to a user record hash.
# @param password  The unencrypted version of the password set for the user.
# @param actcode   The activation code set for the account.
# @param faillimit The number of login failures the user can have.
# @return undef on success, otherwise an error message.
sub _lockout_email {
    my $self      = shift;
    my $user      = shift;
    my $password  = shift;
    my $actcode   = shift;
    my $faillimit = shift;

    # Build URLs to place in the email.
    my $acturl  = $self -> build_url("fullurl"  => 1,
                                     "block"    => "login",
                                     "pathinfo" => [ "activate" ],
                                     "params"   => "actcode=".$actcode);
    my $actform = $self -> build_url("fullurl"  => 1,
                                     "block"    => "login",
                                     "pathinfo" => [ "activate" ]);

    my $status =  $self -> {"messages"} -> queue_message(subject => $self -> {"template"} -> replace_langvar("LOGIN_LOCKOUT_SUBJECT"),
                                                         message => $self -> {"template"} -> load_template("login/email_lockout.tem",
                                                                                                           {"%(username)s"  => $user -> {"username"},
                                                                                                            "%(password)s"  => $password,
                                                                                                            "%(act_code)s"  => $actcode,
                                                                                                            "%(act_url)s"   => $acturl,
                                                                                                            "%(act_form)s"  => $actform,
                                                                                                            "%(faillimit)s" => $faillimit,
                                                                                                           }),
                                                         recipients       => [ $user -> {"user_id"} ],
                                                         send_immediately => 1);
    return ($status ? undef : $self -> {"messages"} -> errstr());
}


## @method private $ _resend_act_email($user, $password)
# Send another copy of the user's activation code to their email address.
#
# @param user     A reference to a user record hash.
# @param password The unencrypted version of the password set for the user.
# @return undef on success, otherwise an error message.
sub _resend_act_email {
    my $self     = shift;
    my $user     = shift;
    my $password = shift;

    # Build URLs to place in the email.
    my $acturl  = $self -> build_url("fullurl"  => 1,
                                     "block"    => "login",
                                     "pathinfo" => [ "activate" ],
                                     "params"   => "actcode=".$user -> {"act_code"});
    my $actform = $self -> build_url("fullurl"  => 1,
                                     "block"    => "login",
                                     "pathinfo" => [ "activate" ]);

    my $status = $self -> {"messages"} -> queue_message(subject => $self -> {"template"} -> replace_langvar("LOGIN_RESEND_SUBJECT"),
                                                        message => $self -> {"template"} -> load_template("login/email_actcode.tem",
                                                                                                          {"%(username)s" => $user -> {"username"},
                                                                                                           "%(password)s" => $password,
                                                                                                           "%(act_code)s" => $user -> {"act_code"},
                                                                                                           "%(act_url)s"  => $acturl,
                                                                                                           "%(act_form)s" => $actform,
                                                                                                          }),
                                                         recipients       => [ $user -> {"user_id"} ],
                                                         send_immediately => 1);
    return ($status ? undef : $self -> {"messages"} -> errstr());
}


## @method private $ _recover_email$user, $actcode)
# Send a copy of the user's username and new actcode to their email address.
#
# @param user     A reference to a user record hash.
# @param actcode The unencrypted version of the actcode set for the user.
# @return undef on success, otherwise an error message.
sub _recover_email {
    my $self    = shift;
    my $user    = shift;
    my $actcode = shift;

    # Build URLs to place in the email.
    my $reseturl = $self -> build_url("fullurl"  => 1,
                                      "block"    => "login",
                                      "params"   => { "uid"       => $user -> {"user_id"},
                                                      "resetcode" => $actcode},
                                      "joinstr"  => "&",
                                      "pathinfo" => [ "reset" ]);

    my $status = $self -> {"messages"} -> queue_message(subject => $self -> {"template"} -> replace_langvar("LOGIN_RECOVER_SUBJECT"),
                                                        message => $self -> {"template"} -> load_template("login/email_recover.tem",
                                                                                                          {"%(username)s"  => $user -> {"username"},
                                                                                                           "%(reset_url)s" => $reseturl,
                                                                                                          }),
                                                        recipients       => [ $user -> {"user_id"} ],
                                                        send_immediately => 1);
    return ($status ? undef : $self -> {"messages"} -> errstr());
}


## @method private $ _reset_email($user, $password)
# Send the user's username and random reset password to them
#
# @param user     A reference to a user record hash.
# @param password The unencrypted version of the password set for the user.
# @return undef on success, otherwise an error message.
sub _reset_email {
    my $self     = shift;
    my $user     = shift;
    my $password = shift;

    # Build URLs to place in the email.
    my $loginform = $self -> build_url("fullurl"  => 1,
                                       "block"    => "login",
                                       "pathinfo" => [ ]);

    my $status = $self -> {"messages"} -> queue_message(subject => $self -> {"template"} -> replace_langvar("LOGIN_RESET_SUBJECT"),
                                                        message => $self -> {"template"} -> load_template("login/email_reset.tem",
                                                                                                           {"%(username)s"  => $user -> {"username"},
                                                                                                            "%(password)s"  => $password,
                                                                                                            "%(login_url)s" => $loginform,
                                                                                                           }),
                                                        recipients       => [ $user -> {"user_id"} ],
                                                        send_immediately => 1);
    return ($status ? undef : $self -> {"messages"} -> errstr());
}


# ============================================================================
#  Validation functions

## @method private @ _validate_signin()
# Determine whether the username and password provided by the user are valid. If
# they are, return the user's data.
#
# @note This does not check for password force change status, as the call mechanics
#       do not support the behaviour needed to prompt the user for a change here.
#       The caller must check whether a change is needed after fixing the user's session.
#
# @return An array of two values: A reference to the user's data on success,
#         or an error string if the login failed, and a reference to a hash of
#         arguments that passed validation.
sub _validate_signin {
    my $self   = shift;
    my $error  = "";
    my $args   = {};

    # Check that the username is provided and valid
    ($args -> {"username"}, $error) = $self -> validate_string("username", {"required"   => 1,
                                                                            "nicename"   => "{L_LOGIN_USERNAME}",
                                                                            "minlen"     => 2,
                                                                            "maxlen"     => 32,
                                                                            "formattest" => '^[-\w ]+$',
                                                                            "formatdesc" => "{L_LOGIN_ERR_BADUSERCHAR}",
                                                               });
    # Bomb out at this point if the username is not valid.
    return ($self -> {"template"} -> load_template("error/error.tem", {"%(message)s" => "{L_LOGIN_ERR_MESSAGE}",
                                                                       "%(reason)s"  => $error}), $args)
        if($error);

    # Do the same with the password...
    ($args -> {"password"}, $error) = $self -> validate_string("password", {"required"   => 1,
                                                                            "nicename"   => "{L_LOGIN_PASSWORD}",
                                                                            "minlen"     => 2,
                                                                            "maxlen"     => 255});
    return ($self -> {"template"} -> load_template("error/error.tem", {"%(message)s" => "{L_LOGIN_ERR_MESSAGE}",
                                                                       "%(reason)s"  => $error}), $args)
        if($error);

    # Username and password appear to be present and contain sane characters. Try to log the user in...
    my $user = $self -> {"session"} -> {"auth"} -> valid_user($args -> {"username"}, $args -> {"password"});

    # If the user is valid, is the account active?
    if($user) {
        # If the account is active, the user is good to go (AuthMethods that don't support activation
        # will return true here always, so there's no need to explicitly check activation support)
        if($self -> {"session"} -> {"auth"} -> activated($args -> {"username"})) {
            return ($user, $args);

        } else {
            # Otherwise, send back the 'account needs activating' error
            return ($self -> {"template"} -> load_template("error/error.tem", {"%(message)s" => "{L_LOGIN_ERR_MESSAGE}",
                                                                               "%(reason)s"  => $self -> {"template"} -> replace_langvar("LOGIN_ERR_INACTIVE",
                                                                                                                                         { "%(url-resend)s" => $self -> build_url("block" => "login", "pathinfo" => [ "resend" ]) })
                                                           }), $args);
        }
    }

    # Work out why the login failed (this may be an internal error, or a fallback)
    my $failmsg = $self -> {"session"} -> auth_error() || "{L_LOGIN_ERR_INVALID}";

    # Try marking the login failure. If username is not valid, this will return undefs
    my ($failcount, $limit) = $self -> {"session"} -> {"auth"} -> mark_loginfail($args -> {"username"});

    # Is login failure limiting even supported?
    if(defined($failcount) && defined($limit) && ($limit > 0)) {
        # Is the user within the login limit?
        if($failcount <= $limit) {
            # Yes, return a fail message, potentially with a failure limit warning
            return ($self -> {"template"} -> load_template("login/failed.tem",
                                                           {"%(reason)s"      => $failmsg,
                                                            "%(failcount)s"   => $failcount,
                                                            "%(faillimit)s"   => $limit,
                                                            "%(failremain)s"  => $limit - $failcount,
                                                            "%(url-recover)s" => $self -> build_url("block" => "login", "pathinfo" => [ "recover" ])
                                                           }), $args);

        # User has exceeded failure limit but their account is still active, deactivate
        # their account, send an email, and return an appropriate error
        } elsif($self -> {"session"} -> {"auth"} -> activated($args -> {"username"})) {

            # Get the user data - the user must exist to get past the defined() guards above, but check anyway
            my $user = $self -> {"session"} -> {"auth"} -> get_user($args -> {"username"});
            if($user) {
                my ($newpass, $actcode) = $self -> {"session"} -> {"auth"} -> reset_password_actcode($args -> {"username"});

                $self -> lockout_email($user, $newpass, $actcode, $limit);

                return ($self -> {"template"} -> load_template("login/lockedout.tem",
                                                               {"%(reason)s"     => $failmsg,
                                                                "%(failcount)s"  => $failcount,
                                                                "%(faillimit)s"  => $limit,
                                                                "%(failremain)s" => $limit - $failcount
                                                               }), $args);
            }
        }
    }

    # limiting not supported, or username is bunk - return the failure message as-is
    return ($self -> {"template"} -> load_template("error/error.tem", { "%(reason)" => $failmsg }), $args);
}


## @method private $ _validate_recaptcha()
# Pull the reCAPTCHA response string from the posted data, and ask the
# google reCAPTCHA validation service to check whether the response is valid.
#
# @return true if the code is valid, undef if not - examine $self -> errstr()
#         for the reason why in this case
sub _validate_recaptcha {
    my $self     = shift;

    $self -> clear_error();

    # Pull the reCAPTCHA response code
    my ($response, $error) = $self -> validate_string("g-recaptcha-response", {"required"   => 1,
                                                                               "nicename"   => "{L_LOGIN_RECAPTCHA}",
                                                                               "minlen"     => 2,
                                                                               "formattest" => '^[-\w]+$',
                                                                               "formatdesc" => "{L_LOGIN_ERR_BADRECAPTCHA}"
                                                                });
    return $self -> self_error($error)
        if($error);

    my $ua = LWP::UserAgent -> new();

    my $data = {
        "secret"   => $self -> {"settings"} -> {"config"} -> {"Login:recaptcha_secret"},
        "response" => $response,
        "remoteip" => $self -> {"cgi"} -> remote_addr()
    };

    # Ask the recaptcha server to verify the response
    my $resp = $ua -> post($self -> {"settings"} -> {"config"} -> {"Login:recaptcha_verify"}, $data);
    if($resp -> is_success()) {

        # Convert the validator response
        my $json = eval { decode_json($resp -> decoded_content()) };
        return $self -> self_error("JSON decoding failed: $@") if($@);

        $self -> log("recaptcha:status", "Validation response: ".($json -> {"success"} ? "successful" : "failed")." JSON: ".$resp -> decoded_content());

        return 1 if($json -> {"success"});
    } else {
        return $self -> self_error("HTTP problem: ".$resp -> status_line());
    }

    return $self -> self_error("{L_LOGIN_ERR_RECAPTCHA}");
}


## @method private @ _validate_signup()
# Determine whether the username, email, and security question provided by the user
# are valid. If they are, return true.
#
# @return The new user's record on success, an error string if the signup failed.
sub _validate_signup {
    my $self   = shift;
    my $error  = "";
    my $errors = "";
    my $args   = {};

    # User attempted self-register when it is disabled? Naughty user, no cookie!
    return ($self -> {"template"} -> load_template("error/error.tem", {"%(message)s" => "{L_LOGIN_ERR_REGFAILED}",
                                                                       "%(reason)s"  => "{L_LOGIN_ERR_NOSELFREG}"}), $args)
        unless($self -> {"settings"} -> {"config"} -> {"Login:allow_self_register"});

    # Check that the username is provided and valid
    ($args -> {"username"}, $error) = $self -> validate_string("username", {"required"   => 1,
                                                                          "nicename"   => "{L_LOGIN_USERNAME}",
                                                                          "minlen"     => 2,
                                                                          "maxlen"     => 32,
                                                                          "formattest" => '^[-\w ]+$',
                                                                          "formatdesc" => "{L_LOGIN_ERR_BADUSERCHAR}"
                                                              });
    # Is the username valid?
    if($error) {
        $errors .= $self -> {"template"} -> load_template("error/error_item.tem", {"%(reason)s" => $error});
    } else {
        # Is the username in use?
        my $user = $self -> {"session"} -> get_user($args -> {"username"});
        $errors .= $self -> {"template"} -> load_template("error/error.tem",
                                                          { "%(message)s" => "{L_LOGIN_ERR_REGFAILED}",
                                                            "%(reason)s"  => $self -> {"template"} -> replace_langvar("LOGIN_ERR_USERINUSE",
                                                                                                                      { "%(url-recover)s" => $self -> build_url("block" => "login", "pathinfo" => [ "recover" ]) })
                                                          })
            if($user);
    }

    # And the email
    ($args -> {"email"}, $error) = $self -> validate_string("email", {"required"   => 1,
                                                                      "nicename"   => "{L_LOGIN_EMAIL}",
                                                                      "minlen"     => 2,
                                                                      "maxlen"     => 256
                                                            });
    if($error) {
        $errors .= $self -> {"template"} -> load_template("error/error_item.tem", {"%(reason)s" => $error});
    } else {

        # Check that the address is structured in a vaguely valid way
        # Yes, this is not fully RFC compliant, but frankly going down that road invites a
        # level of utter madness that would make Azathoth himself utter "I say, steady on now..."
        $errors .= $self -> {"template"} -> load_template("error/error_item.tem", {"%(reason)s" => "{L_LOGIN_ERR_BADEMAIL}"})
            if($args -> {"email"} !~ /^[\w.+-]+\@([\w-]+\.)+\w+$/);

        # Is the email address in use?
        my $user = $self -> {"session"} -> {"auth"} -> {"app"} -> get_user_byemail($args -> {"email"});
        $errors .= $self -> {"template"} -> load_template("error/error_item.tem", {"%(reason)s" => $self -> {"template"} -> replace_langvar("LOGIN_ERR_EMAILINUSE",
                                                                                                                                            { "%(url-recover)s" => $self -> build_url("block" => "login", "pathinfo" => [ "recover" ]) })
                                                          })
            if($user);
    }

    # Is the reCAPTCHA response valid?
    return ($self -> {"template"} -> load_template("error/error_list.tem", { "%(message)s" => "{L_LOGIN_ERR_REGFAILED}",
                                                                             "%(errors)s"  => $self -> errstr() }), $args)
        unless($self -> _validate_recaptcha());


    # Get here an the user's details are okay, register the new user.
    my $methodimpl = $self -> {"session"} -> {"auth"} -> get_authmethod_module($self -> {"settings"} -> {"config"} -> {"default_authmethod"})
        or return ($self -> {"template"} -> load_template("error/error.tem", {"%(message)s" => "{L_LOGIN_ERR_REGFAILED}",
                                                                              "%(reason)s"  => $self -> {"session"} -> {"auth"} -> errstr() }),
                   $args);

    my ($user, $password) = $methodimpl -> create_user($args -> {"username"}, $self -> {"settings"} -> {"config"} -> {"default_authmethod"}, $args -> {"email"});
    return ($self -> {"template"} -> load_template("error/error.tem", {"%(message)s" => "{L_LOGIN_ERR_REGFAILED}",
                                                                       "%(reason)s"  => $methodimpl -> errstr() }),
            $args)
        if(!$user);

    # Send registration email
    my $err = $self -> _signup_email($user, $password);
    return ($err, $args) if($err);

    # User is registered...
    return ($user, $args);
}


## @method private @ validate_actcode()
# Determine whether the activation code provided by the user is valid
#
# @return An array of two values: the first is a reference to the activated
#         user's data hash on success, an error message otherwise; the
#         second is the args parsed from the activation data.
sub _validate_actcode {
    my $self = shift;
    my $args = {};
    my $error;

    # Check that the code has been provided and contains allowed characters
    ($args -> {"actcode"}, $error) = $self -> validate_string("actcode", {"required"   => 1,
                                                                          "nicename"   => "{L_LOGIN_ACTIVATE_CODE}",
                                                                          "minlen"     => 64,
                                                                          "maxlen"     => 64,
                                                                          "formattest" => '^[a-zA-Z0-9]+$',
                                                                          "formatdesc" => "{L_LOGIN_ERR_BADACTCHAR}"});
    # Bomb out at this point if the code is not valid.
    return $self -> {"template"} -> load_template("error/error.tem", { "%(message)s" => "{L_LOGIN_ACTIVATE_FAILED}",
                                                                       "%(reason)s"  => $error})
        if($error);

    # Act code is valid, can a user be activated?
    # Note that this can not determine whether the user's auth method supports activation ahead of time, as
    # we don't actually know which user is being activated until the actcode lookup is done. And generally, if
    # an act code has been set, the authmethod supports activation anyway!
    my $user = $self -> {"session"} -> {"auth"} -> activate_user($args -> {"actcode"});
    return ($self -> {"template"} -> load_template("error/error.tem", { "%(message)s" => "{L_LOGIN_ACTIVATE_FAILED}",
                                                                        "%(reason)s"  => "{L_LOGIN_ERR_BADCODE}"}), $args)
        unless($user);

    # User is active
    return ($user, $args);
}


## @method private @ validate_resend()
# Determine whether the email address the user entered is valid, and whether the
# the account needs to be (or can be) activated. If it is, generate a new password
# and activation code to send to the user.
#
# @return Two values: a reference to the user whose activation code has been send
#         on success, or an error message, and a reference to a hash containing
#         the data entered by the user.
sub _validate_resend {
    my $self   = shift;
    my $args   = {};
    my $error;

    # Get the recaptcha check out of the way first
    return ($self -> {"template"} -> load_template("error/error_list.tem", { "%(message)s" => "{L_LOGIN_RESEND_FAILED}",
                                                                             "%(errors)s"  => $self -> errstr() }), $args)
        unless($self -> _validate_recaptcha());


    # Get the email address entered by the user
    ($args -> {"email"}, $error) = $self -> validate_string("email", {"required"   => 1,
                                                                      "nicename"   => "{L_LOGIN_RESENDEMAIL}",
                                                                      "minlen"     => 2,
                                                                      "maxlen"     => 256
                                                            });
    return ($self -> {"template"} -> load_template("error/error.tem", { "%(message)s" => "{L_LOGIN_RESEND_FAILED}",
                                                                        "%(reason)s"  => $error}), $args)
        if($error);

    # Does the email look remotely valid?
    return ($self -> {"template"} -> load_template("error/error.tem", { "%(message)s" => "{L_LOGIN_RESEND_FAILED}",
                                                                        "%(reason)s"  => "{L_LOGIN_ERR_BADEMAIL}"}), $args)
        if($args -> {"email"} !~ /^[\w.+-]+\@([\w-]+\.)+\w+$/);

    # Does the address correspond to an actual user?
    my $user = $self -> {"session"} -> {"auth"} -> {"app"} -> get_user_byemail($args -> {"email"});
    return ($self -> {"template"} -> load_template("error/error.tem", { "%(message)s" => "{L_LOGIN_RESEND_FAILED}",
                                                                        "%(reason)s"  => "{L_LOGIN_ERR_BADUSER}"}), $args)
        if(!$user);

    # Does the user's authmethod support activation anyway?
    return ($self -> {"template"} -> load_template("error/error.tem", { "%(message)s" => "{L_LOGIN_RESEND_FAILED}",
                                                                        "%(reason)s"  => $self -> {"session"} -> {"auth"} -> capabilities($user -> {"username"}, "activate_message")}), $args)
        if(!$self -> {"session"} -> {"auth"} -> capabilities($user -> {"username"}, "activate"));

    # no point in resending an activation code to an active account
    return ($self -> {"template"} -> load_template("error/error.tem", { "%(message)s" => "{L_LOGIN_RESEND_FAILED}",
                                                                        "%(reason)s"  => "{L_LOGIN_ERR_ALREADYACT}"}), $args)
        if($self -> {"session"} -> {"auth"} -> activated($user -> {"username"}));

    $self -> log("login:resend", "Generating new password and act code for ".$user -> {"username"});

    my $newpass;
    ($newpass, $user -> {"act_code"}) = $self -> {"session"} -> {"auth"} -> reset_password_actcode($user -> {"username"});
    return ($self -> {"template"} -> load_template("error/error.tem", { "%(message)s" => "{L_LOGIN_RESEND_FAILED}",
                                                                        "%(reason)s"  => $self -> {"session"} -> {"auth"} -> {"app"} -> errstr()}), $args)
        if(!$newpass);

    # Get here and the user's account isn't active, needs to be activated, and can be emailed a code...
    $self -> _resend_act_email($user, $newpass);

    return($user, $args);
}


## @method private @ validate_recover()
# Determine whether the email address the user entered is valid, and if so generate
# an act code to start the reset process.
#
# @return Two values: a reference to the user whose reset code has been send
#         on success, or an error message, and a reference to a hash containing
#         the data entered by the user.
sub _validate_recover {
    my $self   = shift;
    my $args   = {};
    my $error;

    # Get the recaptcha check out of the way first
    return ($self -> {"template"} -> load_template("error/error_list.tem", { "%(message)s" => "{L_LOGIN_RECOVER_FAILED}",
                                                                             "%(errors)s"  => $self -> errstr() }), $args)
        unless($self -> _validate_recaptcha());

    # Get the email address entered by the user
    ($args -> {"email"}, $error) = $self -> validate_string("email", {"required"   => 1,
                                                                      "nicename"   => "{L_LOGIN_RECOVER_EMAIL}",
                                                                      "minlen"     => 2,
                                                                      "maxlen"     => 256
                                                            });
    return ($self -> {"template"} -> load_template("error/error.tem", { "%(message)s" => "{L_LOGIN_RECOVER_FAILED}",
                                                                        "%(reason)s"  => $error}), $args)
        if($error);

    # Does the email look remotely valid?
    return ($self -> {"template"} -> load_template("error/error.tem", { "%(message)s" => "{L_LOGIN_RECOVER_FAILED}",
                                                                        "%(reason)s"  => "{L_LOGIN_ERR_BADEMAIL}"}), $args)
        if($args -> {"email"} !~ /^[\w.+-]+\@([\w-]+\.)+\w+$/);

    # Does the address correspond to an actual user?
    my $user = $self -> {"session"} -> {"auth"} -> {"app"} -> get_user_byemail($args -> {"email"});
    return ($self -> {"template"} -> load_template("error/error.tem", { "%(message)s" => "{L_LOGIN_RECOVER_FAILED}",
                                                                        "%(reason)s"  => "{L_LOGIN_ERR_BADUSER}"}), $args)
        if(!$user);

    # Users can not recover an inactive account - they need to get a new act code
    return ($self -> {"template"} -> load_template("error/error.tem", { "%(message)s" => "{L_LOGIN_RECOVER_FAILED}",
                                                                        "%(reason)s"  => "{L_LOGIN_ERR_NORECINACT}"}), $args)
        if($self -> {"session"} -> {"auth"} -> capabilities($user -> {"username"}, "activate") &&
           !$self -> {"session"} -> {"auth"} -> activated($user -> {"username"}));

    # Does the user's authmethod support activation anyway?
    return ($self -> {"template"} -> load_template("error/error.tem", { "%(message)s" => "{L_LOGIN_RECOVER_FAILED}",
                                                                        "%(reason)s"  => $self -> {"session"} -> {"auth"} -> capabilities($user -> {"username"}, "recover_message")}), $args)
        if(!$self -> {"session"} -> {"auth"} -> capabilities($user -> {"username"}, "recover"));

    my $newcode = $self -> {"session"} -> {"auth"} -> generate_actcode($user -> {"username"});
    return ($self -> {"template"} -> load_template("error/error.tem", { "%(message)s" => "{L_LOGIN_RECOVER_FAILED}",
                                                                        "%(reason)s"  => $self -> {"session"} -> {"auth"} -> {"app"} -> errstr()}), $args)
        if(!$newcode);

    # Get here and the user's account has been reset
    $self -> _recover_email($user, $newcode);

    return($user, $args);
}


## @method private @ validate_reset()
# Pull the userid and activation code out of the submitted data, and determine
# whether they are valid (and that the user's authmethod allows for resets). If
# so, reset the user's password and send and email to them with the new details.
#
# @return Two values: a reference to the user whose password has been reset
#         on success, or an error message, and a reference to a hash containing
#         the data entered by the user.
sub _validate_reset {
    my $self = shift;
    my $args   = {};
    my $error;

    # Obtain the userid from the query string, if possible.
    ($args -> {"uid"}, $error) = $self -> validate_numeric("uid", { "required" => 1,
                                                                    "nidename" => "{L_LOGIN_UID}",
                                                                    "intonly"  => 1,
                                                                    "min"      => 2});
    return ("{L_LOGIN_ERR_NOUID}", $args)
        if($error);

    my $user = $self -> {"session"} -> {"auth"} -> {"app"} -> get_user_byid($args -> {"uid"})
        or return ("{L_LOGIN_ERR_BADUID}", $args);

    # Get the reset code, should be a 64 character alphanumeric string
    ($args -> {"resetcode"}, $error) = $self -> validate_string("resetcode", {"required"   => 1,
                                                                              "nicename"   => "{L_LOGIN_RESET_CODE}",
                                                                              "minlen"     => 64,
                                                                              "maxlen"     => 64,
                                                                              "formattest" => '^[a-zA-Z0-9]+$',
                                                                              "formatdesc" => "{L_LOGIN_ERR_BADRECCHAR}"});
    return ($error, $args) if($error);

    # Does the reset code match the one set for the user?
    return ("{L_LOGIN_ERR_BADRECCODE}", $args)
        unless($user -> {"act_code"} && $user -> {"act_code"} eq $args -> {"resetcode"});

    # Users can not recover an inactive account - they need to get a new act code
    return ("{L_LOGIN_ERR_NORECINACT}", $args)
        if($self -> {"session"} -> {"auth"} -> capabilities($user -> {"username"}, "activate") &&
           !$self -> {"session"} -> {"auth"} -> activated($user -> {"username"}));

    # double-check the authmethod supports resets, just to be on the safe side (the code should never
    # get here if it does not, but better safe than sorry)
    return ($self -> {"session"} -> {"auth"} -> capabilities($user -> {"username"}, "recover_message"), $args)
        if(!$self -> {"session"} -> {"auth"} -> capabilities($user -> {"username"}, "recover"));

    # Okay, user is valid, authcode checks out, auth module supports resets, generate a new
    # password and send it
    my $newpass  = $self -> {"session"} -> {"auth"} -> reset_password($user -> {"username"});
    return ($self -> {"template"} -> load_template("error/error.tem", { "%(message)s" => "{L_LOGIN_RECOVER_FAILED}",
                                                                        "%(reason)s"  => $self -> {"session"} -> {"auth"} -> errstr()}), $args)
        if(!$newpass);

    # Get here and the user's account has been reset
    $self -> _reset_email($user, $newpass);

    return($user, $args);
}


## @method private @ validate_passchange()
# Determine whether the password change request made by the user is valid. If the
# password change is valid (passwords match, pass policy, and the old password is
# valid), this will change the password for the user before returning.
#
# @return An array of two values: A reference to the user's data on success,
#         or an error string if the change failed, and a reference to a hash of
#         arguments that passed validation.
sub _validate_passchange {
    my $self   = shift;
    my $error  = "";
    my $errors = "";
    my $args   = {};

    # Get the recaptcha check out of the way first
    return ($self -> {"template"} -> load_template("error/error_list.tem", { "%(message)s" => "{L_LOGIN_PASSCHANGE_FAILED}",
                                                                             "%(errors)s"  => $self -> errstr() }), $args)
        unless($self -> _validate_recaptcha());

    # Need to get a logged-in user before anything else is done
    my $user = $self -> {"session"} -> get_user_byid();
    return ($self -> {"template"} -> load_template("error/error_list.tem",
                                                   { "%(message)s" => "{L_LOGIN_PASSCHANGE_FAILED}",
                                                     "%(errors)s"  => $self -> {"template"} -> load_template("error/error_item.tem",
                                                                                                             { "%(error)s" => "{L_LOGIN_PASSCHANGE_ERRNOUSER}" })
                                                   }), $args)
        if($self -> {"session"} -> anonymous_session() || !$user);

    # Double-check that the user's authmethod actually /allows/ password changes
    my $auth_passchange = $self -> {"session"} -> {"auth"} -> capabilities($user -> {"username"}, "passchange");
    return ($self -> {"template"} -> load_template("error/error_list.tem",
                                                   { "%(message)s" => "{L_LOGIN_PASSCHANGE_FAILED}",
                                                     "%(errors)s"  => $self -> {"template"} -> load_template("error/error_item.tem",
                                                                                                             {"%(error)s" => $self -> {"session"} -> {"auth"} -> capabilities($user -> {"username"}, "passchange_message")})
                                                   }), $args)
        if(!$auth_passchange);

    # Got a user, so pull in the passwords - new, confirm, and old.
    ($args -> {"newpass"}, $error) = $self -> validate_string("newpass", {"required"   => 1,
                                                                          "nicename"   => "{L_LOGIN_NEWPASSWORD}",
                                                                          "minlen"     => 2,
                                                                          "maxlen"     => 255});
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", {"%(error)s" => $error})
        if($error);

    ($args -> {"confirm"}, $error) = $self -> validate_string("confirm", {"required"   => 1,
                                                                          "nicename"   => "{L_LOGIN_CONFPASS}",
                                                                          "minlen"     => 2,
                                                                          "maxlen"     => 255});
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", {"%(error)s" => $error})
        if($error);

    # New and confirm must match
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", {"%(error)s" => "{L_LOGIN_PASSCHANGE_ERRMATCH}"})
        unless($args -> {"newpass"} eq $args -> {"confirm"});

    ($args -> {"oldpass"}, $error) = $self -> validate_string("oldpass", {"required"   => 1,
                                                                          "nicename"   => "{L_LOGIN_OLDPASS}",
                                                                          "minlen"     => 2,
                                                                          "maxlen"     => 255});
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", {"%(error)s" => $error})
        if($error);

    # New and old must not match
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", {"%(error)s" => "{L_LOGIN_PASSCHANGE_ERRSAME}"})
        if($args -> {"newpass"} eq $args -> {"oldpass"});

    # Check that the old password is actually valid
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", {"%(error)s" => "{L_LOGIN_PASSCHANGE_ERRVALID}"})
        unless($self -> {"session"} -> {"auth"} -> valid_user($user -> {"username"}, $args -> {"oldpass"}));

    # Now apply policy if needed
    my $policy_fails = $self -> {"session"} -> {"auth"} -> apply_policy($user -> {"username"}, $args -> {"newpass"});

    if($policy_fails) {
        foreach my $name (@{$policy_fails -> {"policy_order"}}) {
            next if(!$policy_fails -> {$name});
            $errors .= $self -> {"template"} -> load_template("error/error_item.tem", {"%(error)s"   => "{L_LOGIN_".uc($name)."ERR}",
                                                                                       "%(set)s"     => $policy_fails -> {$name} -> [1],
                                                                                       "%(require)s" => $policy_fails -> {$name} -> [0] });
        }
    }

    # Any errors accumulated up to this point mean that changes don't happen...
    return ($self -> {"template"} -> load_template("error/error_list.tem",
                                                   { "%(message)s" => "{L_LOGIN_PASSCHANGE_FAILED}",
                                                     "%(errors)s"  => $errors}), $args)
        if($errors);

    # Password is good, change it
    $self -> {"session"} -> {"auth"} -> set_password($user -> {"username"}, $args -> {"newpass"})
        or return ($self -> {"template"} -> load_template("error/error_list.tem",
                                                          { "%(message)s" => "{L_LOGIN_PASSCHANGE_FAILED}",
                                                            "%(errors)s"  => $self -> {"template"} -> load_template("error/error_item.tem",
                                                                                                                    {"%(error)s" => $self -> {"session"} -> {"auth"} -> errstr()})
                                                          }), $args);

    # No need to keep the passchange variable now
    $self -> {"session"} -> set_variable("passchange_reason", undef);

    return ($user, $args);
}


# ============================================================================
#  Form generators

## @method private $ generate_signin_form($error, $args)
# Generate the content of the login form.
#
# @param error A string containing errors related to logging in, or undef.
# @param args  A reference to a hash of intiial values.
# @return An array containing the page title, content, extra header data, and
#         extra javascript content.
sub _generate_signin_form {
    my $self  = shift;
    my $error = shift;
    my $args  = shift;

    # Wrap the error message in a message box if we have one.
    $error = $self -> {"template"} -> load_template("error/error_box.tem", {"%(message)s" => $error})
        if($error);

    my $persist = $self -> {"settings"} -> {"config"} -> {"Auth:allow_autologin"} ?
        $self -> {"template"} -> load_template("login/persist_enabled.tem") :
        $self -> {"template"} -> load_template("login/persist_disabled.tem");

    return ("{L_LOGIN_TITLE}",
            $self -> {"template"} -> load_template("login/form_signin.tem", {"%(error)s"      => $error,
                                                                             "%(persist)s"    => $persist,
                                                                             "%(url-forgot)s" => $self -> build_url("block" => "login", "pathinfo" => [ "recover" ]),
                                                                             "%(url-target)s" => $self -> build_url("block" => "login"),
                                                                             "%(username)s"   => $args -> {"username"}}),
            $self -> {"template"} -> load_template("login/extrahead.tem"),
            $self -> {"template"} -> load_template("login/extrajs.tem"));
}


## @method private $ generate_signup_form($error, $args)
# Generate the content of the registration form.
#
# @param error A string containing errors related to signing up, or undef.
# @param args  A reference to a hash of intiial values.
# @return An array containing the page title, content, extra header data, and
#         extra javascript content.
sub _generate_signup_form {
    my $self  = shift;
    my $error = shift;
    my $args  = shift;

    # Wrap the error message in a message box if we have one.
    $error = $self -> {"template"} -> load_template("error/error_box.tem", {"%(message)s" => $error})
        if($error);

    return ("{L_LOGIN_SIGNUP_TITLE}",
            $self -> {"template"} -> load_template("login/form_signup.tem", {"%(error)s"        => $error,
                                                                             "%(sitekey)s"      => $self -> {"settings"} -> {"config"} -> {"Login:recaptcha_sitekey"},
                                                                             "%(url-activate)s" => $self -> build_url("block" => "login", "pathinfo" => [ "activate" ]),
                                                                             "%(url-target)s"   => $self -> build_url("block" => "login", "pathinfo" => [ "signup" ]),
                                                                             "%(username)s"     => $args -> {"username"},
                                                                             "%(email)s"        => $args -> {"email"}}),
            $self -> {"template"} -> load_template("login/signup_extrahead.tem"),
            $self -> {"template"} -> load_template("login/extrajs.tem"));
}


## @method private @ generate_actcode_form($error)
# Generate a form through which the user may specify an activation code.
#
# @param error A string containing errors related to activating, or undef.
# @return An array containing the page title, content, extra header data, and
#         extra javascript content.
sub _generate_actcode_form {
    my $self  = shift;
    my $error = shift;

    # Wrap the error message in a message box if we have one.
    $error = $self -> {"template"} -> load_template("error/error_box.tem", {"%(message)s" => $error})
        if($error);

    return ("{L_LOGIN_TITLE}",
            $self -> {"template"} -> load_template("login/form_activate.tem", {"%(error)s"      => $error,
                                                                               "%(url-target)s" => $self -> build_url("block" => "login", "pathinfo" => [ "activate" ]),
                                                                               "%(url-resend)s" => $self -> build_url("block" => "login", "pathinfo" => [ "resend"   ]),}),
            $self -> {"template"} -> load_template("login/extrahead.tem"),
            $self -> {"template"} -> load_template("login/extrajs.tem"));
}


## @method private @ generate_resend_form($error)
# Generate a form through which the user may resend their account activation code.
#
# @param error A string containing errors related to resending, or undef.
# @return An array containing the page title, content, extra header data, and
#         extra javascript content.
sub _generate_resend_form {
    my $self  = shift;
    my $error = shift;

    # Wrap the error message in a message box if we have one.
    $error = $self -> {"template"} -> load_template("error/error_box.tem", {"%(message)s" => $error})
        if($error);

    return ("{L_LOGIN_RESEND_TITLE}",
            $self -> {"template"} -> load_template("login/form_resend.tem", {"%(error)s"      => $error,
                                                                             "%(sitekey)s"    => $self -> {"settings"} -> {"config"} -> {"Login:recaptcha_sitekey"},
                                                                             "%(url-target)s" => $self -> build_url("block" => "login", "pathinfo" => [ "resend" ])
                                                   }),
            $self -> {"template"} -> load_template("login/signup_extrahead.tem"),
            $self -> {"template"} -> load_template("login/extrajs.tem"));
}


## @method private @ generate_recover_form($error)
# Generate a form through which the user may recover their account details.
#
# @param error A string containing errors related to recovery, or undef.
# @return An array containing the page title, content, extra header data, and
#         extra javascript content.
sub _generate_recover_form {
    my $self  = shift;
    my $error = shift;

    # Wrap the error message in a message box if we have one.
    $error = $self -> {"template"} -> load_template("error/error_box.tem", {"%(message)s" => $error})
        if($error);

    return ("{L_LOGIN_RECOVER_TITLE}",
            $self -> {"template"} -> load_template("login/form_recover.tem", {"%(error)s"      => $error,
                                                                              "%(sitekey)s"    => $self -> {"settings"} -> {"config"} -> {"Login:recaptcha_sitekey"},
                                                                              "%(url-target)s" => $self -> build_url("block" => "login", "pathinfo" => [ "recover" ])
                                                   }),
            $self -> {"template"} -> load_template("login/signup_extrahead.tem"),
            $self -> {"template"} -> load_template("login/extrajs.tem"));
}


## @method private @ generate_passchange_form($error)
# Generate a form through which the user can change their password, used to
# support forced password changes.
#
# @param error  A string containing errors related to password changes, or undef.
# @return An array containing the page title, content, extra header data, and
#         extra javascript content.
sub _generate_passchange_form {
    my $self    = shift;
    my $error   = shift;
    my $reasons = {
        'temporary' => "{L_LOGIN_PASSCHANGE_TEMP}",
        'expired'   => "{L_LOGIN_PASSCHANGE_OLD}",
        'manual'    => "{L_LOGIN_PASSCHANGE_MANUAL}"
    };

    # convert the password policy to a string
    my $policy = $self -> _build_password_policy();

    # Reason should be in the 'passchange_reason' session variable.
    my $reason = $self -> {"session"} -> get_variable("passchange_reason", "manual");

    # Force a sane reason
    $reason = 'manual' unless($reason && $reasons -> {$reason});

    # Wrap the error message in a message box if we have one.
    $error = $self -> {"template"} -> load_template("error/error_box.tem", {"%(message)s" => $error})
        if($error);

    return ("{L_LOGIN_PASSCHANGE_TITLE}",
            $self -> {"template"} -> load_template("login/form_passchange.tem",
                                                   { "%(error)s"      => $error,
                                                     "%(sitekey)s"    => $self -> {"settings"} -> {"config"} -> {"Login:recaptcha_sitekey"},
                                                     "%(url-target)s" => $self -> build_url(block => "login", pathinfo => [ "passchange" ]),
                                                     "%(policy)s"     => $policy,
                                                     "%(reason)s"     => $reasons -> {$reason},
                                                     "%(rid)s"        => $reason } ),
            $self -> {"template"} -> load_template("login/signup_extrahead.tem"),
            $self -> {"template"} -> load_template("login/extrajs.tem"));
}


# ============================================================================
#  Response generators

## @method private @ _generate_loggedin()
# Generate the contents of a page telling the user that they have successfully logged in.
#
# @return An array of two values: the page title string, and the 'logged in' message.
sub _generate_loggedin {
    my $self = shift;
    my $content;

    # determine where the user was trying to get to before the login process
    my $url = $self -> build_return_url();

    # The user validation might have thrown up warning, so check that.
    my $warning = $self -> {"template"} -> load_template("login/warning_box.tem", {"%(message)s" => $self -> {"session"} -> auth_error()})
        if($self -> {"session"} -> auth_error());

    # If any warnings were encountered, send back a different logged-in page to avoid
    # confusing users.
    if(!$warning) {
        $self -> redirect($url);

    # Users who have encountered warnings during login always get a login confirmation page, as it has
    # to show them the warning message box.
    } else {
        my $message = $self -> message_box("{L_LOGIN_DONETITLE}",
                                                           "security",
                                                           "{L_LOGIN_SUMMARY}",
                                                           $self -> {"template"} -> replace_langvar("LOGIN_NOREDIRECT", {"%(url)s" => $url,
                                                                                                                         "%(supportaddr)s" => ""}),
                                                           undef,
                                                           "logincore",
                                                           [ {"message" => "{L_SITE_CONTINUE}",
                                                              "colour"  => "blue",
                                                              "action"  => "location.href='$url'"} ]);
        $content = $self -> {"template"} -> load_template("login/login_warn.tem", {"%(message)s" => $message,
                                                                                   "%(warning)s" => $warning});
    }

    # return the title, content, and extraheader. If the warning is set, do not include an autoredirect.
    return ("{L_LOGIN_DONETITLE}", $content);
}


## @method private @ _generate_signedout()
# Generate the contents of a page telling the user that they have successfully logged out.
#
# @return An array of two values: the page title string, and the 'logged out' message
sub _generate_signedout {
    my $self = shift;

    # NOTE: This is called **after** the session is deleted, so savestate will be undef. This
    # means that the user will be returned to a default (the login form, usually).
    my $url = $self -> build_return_url();

    # return the title, content, and extraheader
    return ("{L_LOGOUT_TITLE}",
            $self -> message_box(title   => "{L_LOGOUT_TITLE}",
                                 type    => "account",
                                 summary => "{L_LOGOUT_SUMMARY}",
                                 message => $self -> {"template"} -> replace_langvar("LOGOUT_MESSAGE", {"%(url)s" => $url}),
                                 buttons => [ {"message" => "{L_SITE_CONTINUE}",
                                               "colour"  => "standard",
                                               "href"    => $url } ]));
}


## @method private @ _generate_activated($user)
# Generate the contents of a page telling the user that they have successfully activated
# their account.
#
# @return An array of two values: the page title string, the 'activated' message.
sub _generate_activated {
    my $self = shift;

    my $url = $self -> build_url(block    => "login",
                                 pathinfo => []);

    return ("{L_LOGIN_ACTIVATE_DONETITLE}",
            $self -> message_box(title   => "{L_LOGIN_ACTIVATE_DONETITLE}",
                                 type    => "account",
                                 summary => "{L_LOGIN_ACTIVATE_SUMMARY}",
                                 message => $self -> {"template"} -> replace_langvar("LOGIN_ACTIVATE_MESSAGE",
                                                                                     {"%(url-login)s" => $self -> build_url("block" => "login")}),
                                 buttons => [ {"message" => "{L_LOGIN_LOGIN}",
                                               "colour"  => "standard",
                                               "href"    => "$url"} ]));
}


## @method private @ _generate_signedup()
# Generate the contents of a page telling the user that they have successfully created an
# inactive account.
#
# @return An array of two values: the page title string, the 'registered' message.
sub _generate_signedup {
    my $self = shift;

    my $url = $self -> build_url(block    => "login",
                                 pathinfo => [ "activate" ]);

    return ("{L_LOGIN_SIGNUP_DONETITLE}",
            $self -> message_box(title   => "{L_LOGIN_SIGNUP_DONETITLE}",
                                 type    => "account",
                                 summary => "{L_LOGIN_SIGNUP_SUMMARY}",
                                 message => "{L_LOGIN_SIGNUP_MESSAGE}",
                                 buttons => [ {"message" => "{L_LOGIN_ACTIVATE}",
                                               "colour"  => "standard",
                                               "href"    => $url} ]));
}


## @method private @ _generate_resent()
# Generate the contents of a page telling the user that a new activation code has been
# sent to their email address.
#
# @return An array of two values: the page title string, the 'resent' message.
sub _generate_resent {
    my $self = shift;

    my $url = $self -> build_url(block    => "login",
                                 pathinfo => [ "activate" ]);

    return ("{L_LOGIN_RESEND_DONETITLE}",
            $self -> message_box(title => "{L_LOGIN_RESEND_DONETITLE}",
                                 type  => "account",
                                 summary => "{L_LOGIN_RESEND_SUMMARY}",
                                 message => "{L_LOGIN_RESEND_MESSAGE}",
                                 buttons => [ {"message" => "{L_LOGIN_ACTIVATE}",
                                               "colour"  => "standard",
                                               "href"    => $url} ]));
}


## @method private @ _generate_recover()
# Generate the contents of a page telling the user that a new password has been
# sent to their email address.
#
# @return An array of two values: the page title string, the 'recover sent' message.
sub _generate_recover {
    my $self = shift;

    my $url = $self -> build_url("block" => "login", "pathinfo" => []);

    return ("{L_LOGIN_RECOVER_DONETITLE}",
            $self -> message_box(title   => "{L_LOGIN_RECOVER_DONETITLE}",
                                 type    => "account",
                                 summary => "{L_LOGIN_RECOVER_SUMMARY}",
                                 message => "{L_LOGIN_RECOVER_MESSAGE}",
                                 buttons => [ {"message" => "{L_LOGIN_LOGIN}",
                                               "colour"  => "standard",
                                               "href"    => $url } ]));
}


## @method private @ _generate_reset()
# Generate the contents of a page telling the user that a new password has been
# sent to their email address.
#
# @param  error If set, display an error message rather than a 'completed' message.
# @return An array of two values: the page title string, the 'resent' message.
sub _generate_reset {
    my $self  = shift;
    my $error = shift;

    my $url = $self -> build_url("block" => "login", "pathinfo" => []);

    if(!$error) {
        return ("{L_LOGIN_RESET_DONETITLE}",
                $self -> message_box(title   => "{L_LOGIN_RESET_DONETITLE}",
                                     type    => "account",
                                     summary => "{L_LOGIN_RESET_SUMMARY}",
                                     message => "{L_LOGIN_RESET_MESSAGE}",
                                     buttons => [ {"message" => "{L_LOGIN_LOGIN}",
                                                   "colour"  => "standard",
                                                   "href"    => $url } ]));
    } else {
        return ("{L_LOGIN_RESET_ERRTITLE}",
                $self -> message_box(title   => "{L_LOGIN_RESET_ERRTITLE}",
                                     type    => "error",
                                     summary => "{L_LOGIN_RESET_ERRSUMMARY}",
                                     message => $self -> {"template"} -> replace_langvar("LOGIN_RESET_ERRDESC", {"%(reason)s" => $error}),
                                     button  => [ { "message" => "{L_LOGIN_LOGIN}",
                                                    "colour"  => "blue",
                                                    "href"    => $url } ]));
    }
}


## @method private @ _generate_passchanged()
# Generate the contents of a page telling the user that they have successfully created an
# inactive account.
#
# @return An array of two values: the page title string, the 'registered' message.
sub _generate_passchanged {
    my $self = shift;

    my $url = $self -> build_url(block    => "login",
                                 pathinfo => [ ]);

    return ("{L_LOGIN_PASSCHANGE_DONETITLE}",
            $self -> message_box(title   => "{L_LOGIN_PASSCHANGE_DONETITLE}",
                                 type    => "account",
                                 summary => "{L_LOGIN_PASSCHANGE_SUMMARY}",
                                 message => "{L_LOGIN_PASSCHANGE_MESSAGE}",
                                 buttons => [ {"message" => "{L_SITE_CONTINUE}",
                                               "colour"  => "standard",
                                               "href"    => $url} ]));
}


# ============================================================================
#  API handling


## @method private $ _build_login_check_response(void)
# Determine whether the user's session is still login
#
# @return The data to send back to the user in an API response.
sub _build_login_check_response {
    my $self = shift;

    return { "login" => { "loggedin" => $self -> {"session"} -> anonymous_session() ? "false" : "true" }};
}


## @method private $ _build_login_response(void)
# Genereate a hash containing the API response to a login request.
#
# @return The data to send back to the user in an API reponse.
sub _build_login_response {
    my $self = shift;

    my ($user, $args) = $self -> _validate_signin();
    if(ref($user) eq "HASH") {
        $self -> {"session"} -> create_session($user -> {"user_id"});
        $self -> log("login", $user -> {"username"});

        my $cookies = $self -> {"session"} -> session_cookies();

        return { "login" => { "loggedin" => "true",
                              "user"     => $user -> {"user_id"},
                              "sid"      => $self -> {"session"} -> {"sessid"},
                              "cookies"  => $cookies}};
    } else {
        return { "login" => { "loggedin" => "false",
                              "content"  => $user}};
    }
}


# ============================================================================
#  UI handler/dispatcher functions

## @method private @ _handle_signup()
# Handle the process of showing the user the signup form, and processing any
# submission from the form. Note that this will abort immediately if self-registration
# has not been enabled.
#
# @return An array containing the page title, content, extra header data, and
#         extra javascript content.
sub _handle_signup {
    my $self = shift;

    # Signup not permitted?
    return $self -> generate_errorbox(message => "{L_LOGIN_ERR_NOSELFREG}")
        unless($self -> {"settings"} -> {"config"} -> {"Login:allow_self_register"});

    # Logged in user can't sign up again
    return $self -> _handle_default()
        unless($self -> {"session"} -> anonymous_session());

    # Has the user submitted the signup form?
    if(defined($self -> {"cgi"} -> param("signup"))) {
        # Validate/perform the registration
        my ($user, $args) = $self -> _validate_signup();

        # Do we have any errors? If so, send back the signup form with them
        if(!ref($user)) {
            $self -> log("registration error", $user);
            return $self -> _generate_signup_form($user, $args);

        # No errors, user is registered
        } else {
            # Do not create a new session - the user needs to confirm the account.
            $self -> log("registered inactive", $user -> {"username"});
            return $self -> _generate_signedup();
        }
    }

    # No submission, send back the signup form
    return $self -> _generate_signup_form();
}


## @method private @ _handle_activate()
# Handle the process of showing the form they can enter an activation code
# through, and processing submission from the form.
#
# @return An array containing the page title, content, extra header data, and
#         extra javascript content.
sub _handle_activate {
    my $self = shift;

    # Does the get/post data include an activation code? If so, check it
    # note that we don't care about post v get as the user is given a get
    # URL in the signup email
    if(defined($self -> {"cgi"} -> param("actcode"))) {
        my ($user, $args) = $self -> _validate_actcode();
        if(!ref($user)) {
            $self -> log("activation error", $user);
            return $self -> _generate_actcode_form($user);
        } else {
            $self -> log("activation success", $user -> {"username"});
            return $self -> _generate_activated($user);
        }
    }

    # Otherwise, just return the activation form
    return $self -> _generate_actcode_form();
}


## @method private @ _handle_resend()
# Handle the process of showing the form they can request a new activation code
# through, and processing submission from the form.
#
# @return An array containing the page title, content, extra header data, and
#         extra javascript content.
sub _handle_resend {
    my $self = shift;

    if(defined($self -> {"cgi"} -> param("doresend"))) {
        my ($user, $args) = $self -> _validate_resend();

        if(!ref($user)) {
            $self -> log("Resend error", $user);
            return $self -> _generate_resend_form($user);
        } else {
            $self -> log("Resend success", $user -> {"username"});
            return $self -> _generate_resent($user);
        }
    }

    return $self -> _generate_resend_form();
}


## @method private @ _handle_resend()
# Handle the process of showing the form they can request a password reset code
# through, and processing submission from the form.
#
# @return An array containing the page title, content, extra header data, and
#         extra javascript content.
sub _handle_recover {
    my $self = shift;

    if(defined($self -> {"cgi"} -> param("dorecover"))) {
        my ($user, $args) = $self -> _validate_recover();
        if(!ref($user)) {
            $self -> log("Recover error", $user);
            return $self -> _generate_recover_form($user);
        } else {
            $self -> log("Recover success", $user -> {"username"});
            return $self -> _generate_recover($user);
        }
    }

    return $self -> _generate_recover_form();
}


## @method private @ _handle_reset()
# Handle the process of resetting the user's password.
#
# @return An array containing the page title, content, extra header data, and
#         extra javascript content.
sub _handle_reset {
    my $self = shift;

    my ($user, $args) = $self -> _validate_reset();
    if(!ref($user)) {
        $self -> log("Reset error", $user);
        return $self -> _generate_reset($user);
    } else {
        $self -> log("Reset success", $user -> {"username"});
        return $self -> _generate_reset();
    }
}


## @method private @ _handle_passchange()
# Handle the process of showing the form they can change their password
# through, and processing submission from the form.
#
# @return An array containing the page title, content, extra header data, and
#         extra javascript content.
sub _handle_passchange {
    my $self = shift;

    if(defined($self -> {"cgi"} -> param("changepass"))) {
        # Check the password form is valid
        my ($user, $args) = $self -> _validate_passchange();

        # Change failed, send back the change form
        if(!ref($user)) {
            $self -> log("passchange error", $user);
            return $self -> _generate_passchange_form($user);

        # Change done, send back the loggedin page
        } else {
            $self -> log("password updated", $user);
            return $self -> _generate_passchanged();
        }
    }

    return $self -> _generate_passchange_form();
}


## @method private @ _handle_signin()
# Handle the process of showing the form they can enter their credentials into,
# and processing submission from the form.
#
# @return An array containing the page title, content, extra header data, and
#         extra javascript content.
sub _handle_signin {
    my $self = shift;

    # Has the signin form been submitted?
    if(defined($self -> {"cgi"} -> param("signin"))) {
        # Check the login
        my ($user, $args) = $self -> _validate_signin();

        # Do we have any errors? If so, send back the login form with them
        if(!ref($user)) {
            $self -> log("login error", $user);
            return $self -> _generate_signin_form($user, $args);

        # No errors, user is valid...
        } else {
            # should the login be made persistent?
            my $persist = defined($self -> {"cgi"} -> param("persist")) &&
                          $self -> {"cgi"} -> param("persist") &&
                          $self -> {"settings"} -> {"config"} -> {"Auth:allow_autologin"};

            # Get the session variables so they can be copied to the new session.
            my ($block, $pathinfo, $api, $qstring) = $self -> get_saved_state();

            # create the new logged-in session, copying over the savestate session variable
            $self -> {"session"} -> create_session($user -> {"user_id"},
                                                   $persist,
                                                   {"saved_block"    => $block,
                                                    "saved_pathinfo" => $pathinfo,
                                                    "saved_api"      => $api,
                                                    "saved_qstring"  => $qstring});

            $self -> log("login", $user -> {"username"});

            # Does the user need to change their password?
            my $passchange = $self -> {"session"} -> {"auth"} -> force_passchange($args -> {"username"});
            if(!$passchange) {
                # No passchange needed, user is good
                return $self -> _generate_loggedin();
            } else {
                $self -> {"session"} -> set_variable("passchange_reason", $passchange);
                return $self -> _generate_passchange_form();
            }
        }
    }

    return $self -> _generate_signin_form();
}


## @method private @ _handle_default()
# Handle the situation where no specific login function has been selected
# by the user. This will pick up signed-in users and either redirect them
# or make them change their password, and if there's no logged in user
# this delegates to _handle_signin() to show the signin form.
#
# @return An array containing the page title, content, extra header data, and
#         extra javascript content.
sub _handle_default {
    my $self = shift;

    # Is there already a logged-in session?
    my $user = $self -> {"session"} -> get_user_byid();

    # Pick up logged-in sessions, and either generate the password change form,
    # or to the logged-in page
    if($user && !$self -> {"session"} -> anonymous_session()) {

        # Does the user need to change their password?
        my $passchange = $self -> {"session"} -> {"auth"} -> force_passchange($user -> {"username"});

        if(!$passchange) {
            $self -> log("login", "Revisit to login form by logged in user ".$user -> {"username"});

            # No passchange needed, user is good
            return $self -> _generate_loggedin();
        } else {
            $self -> {"session"} -> set_variable("passchange_reason", $passchange);
            return $self -> _generate_passchange_form();
        }
    }

    # Get here and its an anon session; delegate to the signin handler
    return $self -> _handle_signin();
}


## @method private @ _handle_signout()
# Handle signing the user out of the system.
#
# @return An array containing the page title, content, extra header data, and
#         extra javascript content.
sub _handle_signout {
    my $self = shift;

    # User must be logged in to log out
    return $self -> generate_errorbox(message => "{L_LOGIN_NOTSIGNEDIN}")
        if($self -> {"session"} -> anonymous_session());

    # User is logged in, do the signout
    $self -> log("signout", $self -> {"session"} -> get_session_userid());
    if($self -> {"session"} -> delete_session()) {
        return $self -> _generate_signedout();
    } else {
        return $self -> generate_errorbox(message => $SessionHandler::errstr);
    }
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
        # `signup` creates the accoung, and sends an activation code. The user then goes to
        # `activate` to activate their account, or `resend` to request a new code
        when("signup")     { ($title, $body, $extrahead, $extrajs) = $self -> _handle_signup();     }
        when("activate")   { ($title, $body, $extrahead, $extrajs) = $self -> _handle_activate();   }
        when("resend")     { ($title, $body, $extrahead, $extrajs) = $self -> _handle_resend();     }

        # Account recovery is two stages - first user goes to `recover` and enters the email
        # to send a recovery code to, then the user goes to `reset` to enter the code and
        # reset their password
        when("recover")    { ($title, $body, $extrahead, $extrajs) = $self -> _handle_recover();    }
        when("reset")      { ($title, $body, $extrahead, $extrajs) = $self -> _handle_reset();      }

        # Passchange can be a forced redirect after reset or signup
        when("passchange") { ($title, $body, $extrahead, $extrajs) = $self -> _handle_passchange(); }

        # default handles signin and redirect, paired with signout to log the user out
        when("signout")    { ($title, $body, $extrahead, $extrajs) = $self -> _handle_signout();    }
        default            { ($title, $body, $extrahead, $extrajs) = $self -> _handle_default();    }
    }

    # Done generating the page content, return the filled in page template
    return $self -> generate_cadence_page(title     => $title,
                                          content   => $body,
                                          extrahead => $extrahead,
                                          extrajs   => $extrajs,
                                          doclink   => 'login');
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
            when("check")     { return $self -> api_response($self -> _build_login_check_response()); }
            when("login")     { return $self -> api_response($self -> _build_login_response()); }

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
