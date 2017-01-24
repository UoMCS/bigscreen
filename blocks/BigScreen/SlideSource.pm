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
package BigScreen::SlideSource;

use strict;
use experimental 'smartmatch';
use base qw(BigScreen);
use XML::LibXML;
use LWP::UserAgent;
use Digest;
use Encode;
use v5.12;


# ============================================================================
#  Constructor

## @cmethod $ new(%args)
# Overloaded constructor for the SlideSource.
#
# @param args A hash of values to initialise the object with. See the Block docs
#             for more information.
# @return A reference to a new BigScreen::SlideSource object on success, undef on error.
sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = $class -> SUPER::new(gravatar_url => "%(base)s?s=%(size)s&r=g&d=mm",
                                        @_)
        or return undef;

    return $self;
}


# ============================================================================
#  Support functions

## @method $ fetch_xml($url)
# Request the XML at the specified URL, and parse it into a usable
# form.
#
# @param URL The URL of the XML to retrieve.
# @return A reference to an XML::LibXML::DOM object on success,
#         undef on error.
sub fetch_xml {
    my $self = shift;
    my $url  = shift;

    $self -> clear_error();

    # Fetch the specifed URL.
    my $ua  = LWP::UserAgent -> new();
    my $resp = $ua -> get($url);

    # If the request for the content was successful, parse the XML into a usable form
    if($resp -> is_success) {
        my $xml = eval { XML::LibXML -> load_xml(string => $resp -> decoded_content() ); };
        return $self -> self_error("XML Parsing failed: $@")
            if($@);

        return $xml;
    }

    return $self -> self_error("XML retrieval failed: ".$resp -> status_line);
}


## @method $ determine_type($data)
# Given some data, work out what the corresponding slide type should be.
#
# @param data Some data to use to determine the type
# @return a string containing the slide type
sub determine_type {
    my $self = shift;
    my $data = shift;

    my $digest = Digest -> new("MD5");
    $digest -> add(Encode::encode_utf8($data));

    my $hex = uc(substr($digest -> hexdigest, -1, 1));
    return "type$hex";
}

1;