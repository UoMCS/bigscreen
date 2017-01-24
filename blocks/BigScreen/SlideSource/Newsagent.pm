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
use v5.12;


sub generate_slides {
    my $self = shift;

    my $xml = $self -> fetch_xml($self -> {"url"})
        or return undef;

    my @slides = ();

    foreach my $item ($xml -> findnodes('/rss/channel/item')) {
        # Pull out the bits of the item we're interesed in
        my ($title)  = $item -> findnodes('./title');
        my ($desc)   = $item -> findnodes('./description');
        my ($author) = $item -> findnodes('./author');
        my ($avatar) = $item -> findnodes('./newsagent:gravatar');
        my ($image)  = $item -> findnodes('(./newsagent:images/newsagent:image[@type=\'article\'])[1]');

        # Convert the avatar to an image tag
        my $slide_avatar = $self -> {"template"} -> load_template("slideshow/avatar.tem",
                                                                  {"%(url)s" => named_sprintf($self -> {"gravatar_url"},
                                                                                              { base => $avatar -> to_literal,
                                                                                                size => 64 }),
                                                                  });

        # And build the content
        my $image_mode = $image ? "slideshow/content-image.tem" : "slideshow/content-noimage.tem";
        my $slide_content = $self -> {"template"} -> load_template($image_mode,
                                                                   {"%(content)s" => $desc -> to_literal,
                                                                    "%(url)s" => $image ? $image -> getAttribute('src') : undef });

        my ($email, $name) = $author -> to_literal =~ /^(.*?)\s*\(([^)]+)\)$/;


        # And now create the slide
        push(@slides, $self -> {"template"} -> load_template("slideshow/slide.tem",
                                                             { "%(slide-title)s"  => $title -> to_literal,
                                                               "%(author)s"       => $name,
                                                               "%(email)s"        => $email,
                                                               "%(slide-avatar)s" => $slide_avatar,
                                                               "%(content)s"      => $slide_content,
                                                               "%(type)s"         => $self -> determine_type($slide_content),
                                                             }));
    }

    return \@slides;
}


1;