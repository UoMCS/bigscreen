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
use parent qw(BigScreen);
use JSON;
use Digest;
use List::Util qw(shuffle);
use DateTime;
use v5.12;

## @method $ create($moduleid, $args, $notes)
# Create a new slide source entry. This creates a new slide source with
# the specified settings.
#
# @param moduleid The ID of the source module to use for this slide source
# @param args     The arguments to pass to the slide source module
# @param notes    Human-readable notes ot include in the manage UI
# @return true on success, undef on error.
sub create {
    my $self     = shift;
    my $moduleid = shift;
    my $args     = shift;
    my $notes    = shift;

    $self -> clear_error();

    my $newh = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"slidesources"}."`
                                              (`module_id`, `args`, `notes`)
                                              VALUE(?, ?, ?)");
    my $result = $newh -> execute($moduleid, $args, $notes);
    return $self -> self_error("Insert of source failed: ".$self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("No rows added when inserting source.") if($result eq "0E0");

    return 1;
}


## @method $ delete($sourceid)
# Remove the specified slide source from the system.
#
# @param sourceid The ID of the slide source to remove.
# @return true on successful removal, undef on error.
sub delete {
    my $self     = shift;
    my $sourceid = shift;

    my $nukeh = $self -> {"dbh"} -> prepare("DELETE FROM `".$self -> {"settings"} -> {"database"} -> {"slidesources"}."`
                                             WHERE `id` = ?");
    my $result = $nukeh -> execute($sourceid);
    return $self -> self_error("Delete of source failed: ".$self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("No rows removed when deleting source.") if($result eq "0E0");

    return 1;
}


## @method $ update($sourceid, $moduleid, $args, $notes)
# Update a slide source entry. This updates the settings for the specified
# slide source with the provided values.
#
# @param sourceid The ID of the slide source to update
# @param moduleid The ID of the source module to use for this slide source
# @param args     The arguments to pass to the slide source module
# @param notes    Human-readable notes ot include in the manage UI
# @return true on success, undef on error.
sub update {
    my $self     = shift;
    my $sourceid = shift;
    my $moduleid = shift;
    my $args     = shift;
    my $notes    = shift;

    $self -> clear_error();

    my $edith = $self -> {"dbh"} -> prepare("UPDATE`".$self -> {"settings"} -> {"database"} -> {"slidesources"}."`
                                             SET `module_id` = ?, `args` = ?, `notes` = ?
                                             WHERE `id` = ?");
    my $result = $edith -> execute($moduleid, $args, $notes, $sourceid);
    return $self -> self_error("Update of source failed: ".$self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("No rows changed when updating source.") if($result eq "0E0");

    return 1;
}


## @method $ set_slide_status($sourceid, $enabled)
# Update the active status of the specified slide source.
#
# @param sourceid The ID of the slide source to update
# @param enabled  True if the slide source should be enabled, false if not.
# @return true on success, undef on error.
sub set_slide_status {
    my $self     = shift;
    my $sourceid = shift;
    my $enabled  = shift;

    $self -> clear_error();

    my $stateh = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"slidesources"}."`
                                              SET `enabled` = ?
                                              WHERE `id` = ?");
    $stateh -> execute($enabled, $sourceid)
        or return $self -> self_error("Unable to fetch slide sources list: ".$self -> {"dbh"} -> errstr());

    return 1;
}


## @method $ get_slide_source($sourceid)
# Fetch the data for the specified slide source.
#
# @note This does not process the arguments list in any way, or include module data.
#
# @param  sourceid The ID of the source to retrieve
# @return A reference to a hash containing the source data on success, undef
#         on error
sub get_slide_source {
    my $self     = shift;
    my $sourceid = shift;

    $self -> clear_error();

    my $source = $self -> {"dbh"} -> prepare("SELECT *
                                               FROM `".$self -> {"settings"} -> {"database"} -> {"slidesources"}."`
                                               WHERE `id` = ?");
    $source -> execute($sourceid)
        or return $self -> self_error("Unable to fetch slide source: ".$self -> {"dbh"} -> errstr());

    return $source -> fetchrow_hashref()
       || $self -> self_error("Request for unknown slide source $sourceid");
}


## @method $ get_slide_sources($all)
# Fetch the list of defined slide sources. This will obtain the list of slide
# sources defined in the database.
#
# @param all If set to true, all slide sources are returned, even if they
#            are disabled.
# @return A reference to an array of slide source hash definitions. Each hash
#         contains the name of the module implementating the slide source,
#         and a hash of arguments to initialise the module with.
sub get_slide_sources {
    my $self = shift;
    my $all  = shift;

    $self -> clear_error();

    my $only_enabled = $all ? "" : "AND `ss`.`enabled` = 1";
    my $sources = $self -> {"dbh"} -> prepare("SELECT `ss`.*, `sm`.`name`, `sm`.`module`
                                               FROM `".$self -> {"settings"} -> {"database"} -> {"slidesources"}."` AS `ss`,
                                                    `".$self -> {"settings"} -> {"database"} -> {"sourcemodules"}."` AS `sm`
                                               WHERE `sm`.`id` = `ss`.`module_id`
                                               $only_enabled
                                               ORDER BY `sm`.`name`, `ss`.`id`");
    $sources -> execute()
        or return $self -> self_error("Unable to fetch slide sources list: ".$self -> {"dbh"} -> errstr());

    my $sourcelist = $sources -> fetchall_arrayref({});
    foreach my $source (@{$sourcelist}) {
        my %args = $source -> {"args"} =~ /(\w+)\s*=\s*([^;]+)/g;

        $source -> {"args"} = \%args;
    }

    return $sourcelist;
}


# @method $ get_slide_modules()
# Fetch the list of defined slide modules.
#
# @return A reference to an array of slide module definitions.
sub get_slide_modules {
    my $self = shift;

    $self -> clear_error();

    my $sources = $self -> {"dbh"} -> prepare("SELECT *
                                               FROM `".$self -> {"settings"} -> {"database"} -> {"sourcemodules"}."`
                                               ORDER BY `name`, `id`");
    $sources -> execute()
        or return $self -> self_error("Unable to fetch slide module list: ".$self -> {"dbh"} -> errstr());

    return $sources -> fetchall_arrayref({});
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
    $mark -> execute($sourceid)
        or return $self -> self_error("Unable to fetch slide sources list: ".$self -> {"dbh"} -> errstr());

    return 1;
}


sub get_slides {
    my $self = shift;

    # Fetch the list of slide sources to it can be processed
    my $sources = $self -> get_slide_sources()
        or return $self -> _fatal_error("Unable to obtain a list of slide sources");

    my @slides = ();
    foreach my $source (@{$sources}) {
        my $slidemod = $self -> {"module"} -> load_module($source -> {"module"}, %{$source -> {"args"}})
            or return $self -> _fatal_error("Unable to load slide module ".$source -> {"module"});

        my $slides = $slidemod -> generate_slides()
            or return $self -> _fatal_error("Unable to process slides for ".$source -> {"module"}.": ".$slidemod -> errstr());

        # store the new slides if there are any
        push(@slides, @{$slides})
            if($slides && scalar(@{$slides}));

        $self -> set_slide_checked($source -> {"id"});
    }

    srand($self -> _sum_slides(\@slides));

    # Mix things up
    @slides = shuffle @slides;

    # process duplication
    return $self -> _process_duplicates(\@slides);
}


# ============================================================================
#  Support code

## @method private $ _calculate_total($slides)
# Work out how many slides there will be in total in the output, taking the
# creation of duplicate slides into account.
#
# @param slides A reference to an array containing the source slides
# @return The total number of slides that will be generated in the output.
sub _calculate_total {
    my $self   = shift;
    my $slides = shift;

    my $initial = scalar(@{$slides});
    my $total   = $initial;
    foreach my $slide (@{$slides}) {
        if($slide -> {"duplicate"} > 1) {
            $slide -> {"count"} = int($initial / $slide -> {"duplicate"});
            $total += ($slide -> {"count"} - 1);
        }
    }

    return $total;
}


## @method private $ _process_duplicates($slides)
# Given an array of slides, some of which may need to be duplicated, generate
# an array of slides with the duplicates placed within the list as needed.
#
# @param slides A reference to an array containing the source slides
# @return A reference to an array containing the generated slide list.
sub _process_duplicates {
    my $self   = shift;
    my $slides = shift;

    # Pass 1 - work out the total lenght of the output
    my $total = $self -> _calculate_total($slides);

    my @output;

    # Pass 2 - place duplicate candidates
    foreach my $slide (@{$slides}) {
        if($slide -> {"count"}) {
            # Work out how many slides per instance
            my $period = int($total / $slide -> {"count"});

            my $offset = 0;
            for(my $instance = 0; $instance < $slide -> {"count"}; ++$instance) {
                my $pos;

                # Look for an unoccupied slide in the allowed range
                do {
                    $pos = $offset + int(rand($period + 1));
                } while($output[$pos]);

                $output[$pos] = $slide -> {"slide"};
                $offset += ($period + 1);
            }

            $slide -> {"slide"} = undef;
        }
    }

    # Pass 3 - copy non-duplicated slides
    my $outpos = 0;
    foreach my $slide (@{$slides}) {
        # Ignore slides that've already been placed in pass 2
        next if(!$slide -> {"slide"});

        # Skip any filled-in slides in the output
        while($output[$outpos]) {
            ++$outpos;
        }

        $output[$outpos++] = $slide -> {"slide"};
    }

    return \@output;
}


## @method private $ _sum_slides($slides)
# Given an array of slides, generate a unique number representing those slides.
# This generates the md5 of the slides and returns the digest.
#
# @param slides The slides to generate the MD5 for.
# @return The digest generated from the slides.
sub _sum_slides {
    my $self   = shift;
    my $slides = shift;

    my $md5 = Digest -> new("MD5");
    $md5 -> add(@{$slides});

    return unpack('L', substr($md5 -> digest(), 0, 4));
}

1;