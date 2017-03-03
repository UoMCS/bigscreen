# @file
# This file contains the implementation of the BigScreen class
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
package BigScreen::SlideSource::BigScreen;

use strict;
use experimental 'smartmatch';
use base qw(BigScreen::SlideSource);
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
#  Interface methods

sub generate_slides {
    my $self = shift;

    return [ { "slide"     => $self -> {"template"} -> load_template("slideshow/bigscreen-slide.tem"),
               "duplicate" => 1
             }
           ];
}


1;