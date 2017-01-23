# @file
# This file contains the implementation of the base Slide Source module class
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
package BigScreen::System::SlideSource;

use strict;
use experimental 'smartmatch';
use base qw(BigScreen);
use JSON;
use DateTime;
use v5.12;


## @method $ get_slide_sources()
# Fetch the list of defined slide sources. This will obtain the list of slide
# sources defined in the database.
#
# @return A reference to an array of slide source hash definitions. Each hash
#         contains the name of the module implementating the slide source,
#         and a hash of arguments to initialise the module with.
sub get_slide_sources {
    my $self = shift;

    $self -> clear_error();

    my $sources = $self -> {"dbh"} -> prepare("SELECT *
                                               FROM `".$self -> {"settings"} -> {"database"} -> {"slidesources"}."`
                                               ORDER BY `last_checked`, `id`");
    $sources -> execute()
        or return $self -> self_error("Unable to fetch slide sources list: ".$self -> {"dbh"} -> errstr());

    my $sourcelist = $sources -> fetchall_arrayref({});
    foreach my $source (@{$sourcelist}) {
        my %args = $source -> {"args"} =~ /(\w+)\s*=\s*([^;]+)/g;

        $source -> {"args"} = \%args;
    }

    return $sourcelist;
}


## @method $ set_slide_checked($sourceid)
# Mark the slide source as checked.
#
# @param sourceid The ID of the slide source to mark as checked.
# @return true on success, undef on error
sub set_slide_checked {
    my $self     = shift;
    my $sourceid = shift;

    $self -> clear_error();

    my $mark = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"slidesources"}."`
                                            SET `last_checked` = UNIX_TIMESTAMP()
                                            WHERE `id` = ?");
    $sources -> execute($sourceid)
        or return $self -> self_error("Unable to fetch slide sources list: ".$self -> {"dbh"} -> errstr());

    return 1;
}

1;