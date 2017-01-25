# @file
# This file contains the implementation of the Monday Mail class
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
package BigScreen::SlideSource::MondayMail;

use strict;
use experimental 'smartmatch';
use base qw(BigScreen::SlideSource);
use Text::Sprintf::Named qw(named_sprintf);
use DateTime::Format::CLDR;
use v5.12;


sub _split_monday_mail {
    my $self = shift;
    my $body = shift;

    my @parts = $body =~ m{<p>((?:<img[^>]+>)?\*.*?)</p>}gm;
    s/\*// for @parts;

    return \@parts;
}

## @method private $ _newsagent_to_datetime($datestr)
# Given a time string in rss time format, generate a DateTime object representing it.
#
# @param datestr A date string in the format, 'EEE MMM dd HH:mm:ss Z yyyy'
# @return A DateTime object representing the date string
sub _newsagent_to_datetime {
    my $self    = shift;
    my $datestr = shift;

    my $parser = DateTime::Format::CLDR->new(pattern   => 'EEE, dd MMM yyyy HH:mm:ss Z',
                                             time_zone => 'Europe/London');

    my $datetime = eval { $parser -> parse_datetime($datestr); };
    if($@) {
        print STDERR "Failed to parse datetime from '$datestr'";
        $self -> log("error", "Failed to parse datetime from '$datestr'");
        return DateTime -> now();
    }

    return $datetime;
}


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

        my ($title)   = $item -> findnodes('./title');
        my ($desc)    = $item -> findnodes('./description');
        my ($author)  = $item -> findnodes('./author');
        my ($avatar)  = $item -> findnodes('./newsagent:gravatar');

        # Convert the avatar to an image tag
        my $slide_avatar = $self -> {"template"} -> load_template("slideshow/avatar.tem",
                                                                  {"%(url)s" => named_sprintf($self -> {"gravatar_url"},
                                                                                              { base => $avatar -> to_literal,
                                                                                                size => 64 }),
                                                                  });

        # And build the content
        my ($email, $name) = $author -> to_literal =~ /^(.*?)\s*\(([^)]+)\)$/;

        my $bodyparts = $self -> _split_monday_mail($desc -> to_literal);

        foreach my $part (@{$bodyparts}) {
            # And now create the slide
            push(@slides, $self -> {"template"} -> load_template("slideshow/slide.tem",
                                                                 { "%(slide-title)s"  => $title -> to_literal,
                                                                   "%(byline)s"       => $self -> {"template"} -> load_template("slideshow/byline-oneauthor.tem"),
                                                                   "%(author)s"       => $name,
                                                                   "%(email)s"        => $email,
                                                                   "%(posted)s"       => $self -> {"template"} -> format_time($timestamp -> epoch(), '%a, %d %b %Y %H:%M:%S'),
                                                                   "%(slide-avatar)s" => $slide_avatar,
                                                                   "%(content)s"      => "<p>".$part."</p>",
                                                                   "%(type)s"         => $self -> determine_type($part),
                                                                 }));
        }
    }

    return \@slides;
}


1;