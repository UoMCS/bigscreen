# @file
# This file contains the implementation of the Twitter class
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
package BigScreen::SlideSource::Twitter;

use strict;
use experimental 'smartmatch';
use base qw(BigScreen::SlideSource);
use Net::Twitter::Lite::WithAPIv1_1;
use DateTime::Format::CLDR;
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
    my $self     = $class -> SUPER::new(maxage => 1,
                                        @_)
        or return undef;

    return $self;
}


# ============================================================================
#  Utility functions

## @method private $ _twitter_to_datetime($datestr)
# Given a time string in twitter's [CENSORED] [CENSORED] and generally [CENSORED]
# time format, generate a DateTime object representing it.
#
# @param datestr A date string in twitter's inimitable format, 'EEE MMM dd HH:mm:ss Z yyyy'
# @return A DateTime object representing the date string
sub _twitter_to_datetime {
    my $self    = shift;
    my $datestr = shift;

    # CLDR requires base TZ for offset
    $datestr =~ s/([-+]\d+)/GMT$1/;

    my $parser = DateTime::Format::CLDR->new(pattern => 'EEE MMM dd HH:mm:ss ZZZZ yyyy');

    my $datetime = eval { $parser -> parse_datetime($datestr); };
    if($@) {
        $self -> log("error", "Failed to parse datetime from '$datestr'");
        return DateTime -> now(time_zone => $self -> {"settings"} -> {"config"} -> {"time_zone"});
    }

    # Set the TZ forcibly, overriding the bovine excrement in the twitter feed
    $datetime -> set_time_zone($self -> {"settings"} -> {"config"} -> {"time_zone"});
    return $datetime;
}


# ============================================================================
#  Interface methods

sub generate_slides {
    my $self = shift;

    my $twitter = Net::Twitter::Lite::WithAPIv1_1 -> new(consumer_key        => $self -> {"consumer_key"},
                                                         consumer_secret     => $self -> {"consumer_secret"},
                                                         access_token        => $self -> {"access_token"},
                                                         access_token_secret => $self -> {"token_secret"},
                                                         ssl                 => 1,
                                                         wrap_result         => 1);

    my $results = eval { $twitter -> user_timeline({ tweet_mode => "extended", # extended mode includes media in the results
                                                     count => 10 }); };

    my @slides = ();
    foreach my $status (@{$results -> {"result"}}) {
        # Stop when we exceed the age limit
        my $timestamp = $self -> _twitter_to_datetime($status -> {"created_at"});
        last unless($self -> in_age_limit($timestamp));

        my $text = "<p>".( $status -> {"retweeted_status"} -> {"full_text"} || $status -> {"full_text"} )."</p>";

        # Expand URLs...
        my $urls = $status-> {"retweeted_status"} -> {"entities"} -> {"urls"} || $status -> {"entities"} -> {"urls"};
        foreach my $url (@{$urls}) {
            $text =~ s|$url->{url}|<strong>$url->{url}</strong> \($url->{expanded_url}\)|g;
        }

        my $profileimg = $self -> {"template"} -> load_template("slideshow/avatar.tem",
                                                                { "%(url)s" => ( $status -> {"retweeted_status"} -> {"user"} -> {"profile_image_url_https"} ||
                                                                                 $status -> {"user"} -> {"profile_image_url_https"} )
                                                                });

        my $byline = $self -> {"template"} -> load_template("slideshow/byline-oneauthor.tem",
                                                            { "%(slide-avatar)s" => $profileimg,
                                                              "%(author)s"       => ( $status -> {"retweeted_status"} -> {"user"} -> {"name"} ||
                                                                                      $status -> {"user"} -> {"name"} ),
                                                              "%(email)s"        => '@'.( $status -> {"retweeted_status"} -> {"user"} -> {"screen_name"} ||
                                                                                          $status -> {"user"} -> {"screen_name"} ),
                                                            });


        my $image      = $status -> {"entities"} -> {"media"} -> [0] -> {"media_url_https"};
        my $image_mode = $image ? "slideshow/content-image.tem" : "slideshow/content-noimage.tem";
        my $content = $self -> {"template"} -> load_template($image_mode,
                                                             {"%(content)s" => $text,
                                                              "%(url)s"     => $image });

        my $slide = $self -> {"template"} -> load_template("slideshow/slide.tem",
                                                            { "%(id)s"           => $status -> {"id"},
                                                               "%(slide-title)s"  => "{L_SLIDE_TWITTER_TITLE}",
                                                               "%(account)s"      => $self -> {"account"},
                                                               "%(posted)s"       => $timestamp -> strftime($self -> {"timefmt"}),
                                                               "%(byline)s"       => $byline,
                                                               "%(content)s"      => $content,
                                                               "%(type)s"         => $self -> determine_type($text),
                                                             });
        push(@slides, { "slide"     => $slide,
                        "duplicate" => $self -> {"duplicate"} // 1,
                      }
            );
    }

    return \@slides;
}


1;