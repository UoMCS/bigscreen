# @file
# This file contains the implementation of the Newsagent class
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
package BigScreen::SlideSource::Newsagent;

use strict;
use experimental 'smartmatch';
use base qw(BigScreen::SlideSource);
use Text::Sprintf::Named qw(named_sprintf);
use DateTime::Format::CLDR;
use v5.12;


# ============================================================================
#  Utility functions

## @method private $ _strip_summary($body)
# Given the text of a newsagent article, attempt to determine whether
# the aut-inserted summary matches the first chunk of the body, and
# remove the summary if it does
#
# @param body The newsagent article text
# @return A string containing the possibly cleaned-up content
sub _strip_summary {
    my $self = shift;
    my $body = shift;

    my ($summary, $remainder) = $body =~ m|^\s*<h3>(.*?)</h3>\s*(.*?)$|s;

    # If there is a summary, we need to do more work
    if($summary) {
        my $nohtml = $self -> {"template"} -> html_strip($remainder);

        # Does the summary match the start of the html?
        if($nohtml =~ /^\s*$summary/s) {
            # Yes, we can strip the summary
            return $remainder;
        }
    }

    # No match/no summary.
    return $body;
}


## @method private $ _newsagent_to_datetime($datestr)
# Given a time string in rss time format, generate a DateTime object representing it.
#
# @param datestr A date string in the format, 'EEE MMM dd HH:mm:ss Z yyyy'
# @return A DateTime object representing the date string
sub _newsagent_to_datetime {
    my $self    = shift;
    my $datestr = shift;

    # CLDR parser requires TZ to offset from
    $datestr =~ s/([-+]\d+)/GMT$1/;

    my $parser = DateTime::Format::CLDR->new(pattern   => 'EEE, dd MMM yyyy HH:mm:ss ZZZZ',
                                             time_zone => $self -> {"settings"} -> {"config"} -> {"time_zone"});

    my $datetime = eval { $parser -> parse_datetime($datestr); };
    if($@ || !$datetime) {
        print STDERR "Failed to parse datetime from '$datestr': ".$parser -> errmsg();
        $self -> log("error", "Failed to parse datetime from '$datestr': ".$parser -> errmsg());
        return DateTime -> now(time_zone => $self -> {"settings"} -> {"config"} -> {"time_zone"});
    }

    $datetime -> set_time_zone($self -> {"settings"} -> {"config"} -> {"time_zone"});
    return $datetime;
}


## @method private $ _image_only($body, $item)
# Attempt to determine whether the specified slide is an 'image only' slide, and
# if so generate an appropriate body to show it full-screen.
#
# @param body The HTML for the slide body
# @param item The XML::LibXML::Node object representing the slide source data
# @return The body to use for the image-only slide if this is one, undef otherwise.
sub _image_only {
    my $self = shift;
    my $body = shift;
    my $item = shift;

    my $nohtml = $self -> {"template"} -> html_strip($body);
    if($nohtml =~ /^\s*image only$/im) {
        my ($image) = $item -> findnodes('(./newsagent:images/newsagent:image[@type=\'tactus\'])[1]');

        return $self -> {"template"} -> load_template("slideshow/content-imageonly.tem",
                                                      { "%(url)s" => $image -> getAttribute('src') })
            if($image);
    }

    return undef;
}


# ============================================================================
#  Interface methods

sub generate_slides {
    my $self = shift;

    my $xml = $self -> fetch_xml($self -> {"url"})
        or return undef;

    my @slides = ();

    foreach my $item ($xml -> findnodes('/rss/channel/item')) {
        # Do age checking
        my ($pubdate) = $item -> findnodes('./pubDate');
        my $timestamp = $self -> _newsagent_to_datetime($pubdate -> to_literal);
        last unless($self -> in_age_limit($timestamp));

        # Pull out the bits of the item we're interesed in
        my ($title)   = $item -> findnodes('./title');
        my ($desc)    = $item -> findnodes('./description');
        my ($author)  = $item -> findnodes('./author');
        my ($avatar)  = $item -> findnodes('./newsagent:gravatar');
        my ($image)   = $item -> findnodes('(./newsagent:images/newsagent:image[@type=\'article\'])[1]');

        # Convert the avatar to an image tag
        my $slide_avatar = $self -> {"template"} -> load_template("slideshow/avatar.tem",
                                                                  {"%(url)s" => named_sprintf($self -> {"gravatar_url"},
                                                                                              { base => $avatar -> to_literal,
                                                                                                size => 64 }),
                                                                  });

        my $slide_content;

        # Is this an image-only slide?
        my $imgbody = $self -> _image_only($desc -> to_literal, $item);
        if($imgbody) {
            $slide_content = $self -> {"template"} -> load_template("slideshow/content-noimage.tem",
                                                                    {"%(content)s" => $imgbody });
        } else {
            my $image_mode = $image ? "slideshow/content-image.tem" : "slideshow/content-noimage.tem";
            $slide_content = $self -> {"template"} -> load_template($image_mode,
                                                                    {"%(content)s" => $self -> _strip_summary($desc -> to_literal),
                                                                     "%(url)s"     => $image ? $image -> getAttribute('src') : undef });
        }

        my ($email, $name) = $author -> to_literal =~ /^(.*?)\s*\(([^)]+)\)$/;

        # And now create the slide
        my $slide = $self -> {"template"} -> load_template("slideshow/slide.tem",
                                                           { "%(slide-title)s"  => $title -> to_literal,
                                                             "%(byline)s"       => $self -> {"template"} -> load_template("slideshow/byline-oneauthor.tem"),
                                                             "%(author)s"       => $name,
                                                             "%(email)s"        => $email,
                                                             "%(posted)s"       => $timestamp -> strftime($self -> {"timefmt"}),
                                                             "%(slide-avatar)s" => $slide_avatar,
                                                             "%(content)s"      => $slide_content,
                                                             "%(type)s"         => $self -> determine_type($slide_content),
                                                           });
        push(@slides, { "slide"     => $slide,
                        "duplicate" => $self -> {"duplicate"} // 1,
                      }
            );
    }

    return \@slides;
}


1;