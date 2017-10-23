# @file
# This file contains the implementation of the Newsagent Newsletter reader class
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
package BigScreen::SlideSource::Newsletter;

use strict;
use experimental 'smartmatch';
use base qw(BigScreen::SlideSource);
use HTML::TreeBuilder;
use Text::Sprintf::Named qw(named_sprintf);
use DateTime::Format::CLDR;
use v5.12;
use Data::Dumper;

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
        my ($desc)    = $item -> findnodes('./description');

        my $parser = HTML::TreeBuilder -> new();
        $parser -> parse_content($desc -> to_literal);
        $parser -> elementify();

        my @elements = $parser -> look_down(_tag => "td",
                                            class => qr/na-testnews-articleitem/);

        foreach my $element (@elements) {
            my $title   = $element -> look_down(_tag  => "h3");
            my $content = $element -> look_down(_tag  => "div");
            my $byline  = $element -> look_down(_tag  => "div",
                                                class => "na-testnews-author");

            my $img  = $byline -> look_down(_tag => "img");
            my $name = $byline -> as_text();

            my $src = $img -> attr("src");
            $src =~ s/s=16/s=64/;
            my $slide_avatar = $self -> {"template"} -> load_template("slideshow/avatar.tem",
                                                                      {"%(url)s" => $src });

            # And now create the slide
            my $slide = $self -> {"template"} -> load_template("slideshow/slide.tem",
                                                               { "%(slide-title)s"  => $title -> as_text(),
                                                                     "%(byline)s"       => $self -> {"template"} -> load_template("slideshow/byline-oneauthor.tem"),
                                                                     "%(author)s"       => $name,
                                                                     "%(email)s"        => "",
                                                                     "%(posted)s"       => $timestamp -> strftime($self -> {"timefmt"}),
                                                                     "%(slide-avatar)s" => $slide_avatar,
                                                                     "%(content)s"      => $content -> as_HTML(),
                                                                     "%(type)s"         => $self -> determine_type("1234"),
                                                               });
            push(@slides, { "slide"     => $slide,
                                "duplicate" => $self -> {"duplicate"} // 1,
                 }
                );
        }
    }

    return \@slides;
}


1;