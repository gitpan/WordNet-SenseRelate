#!/usr/local/bin/perl

use strict;
use warnings;

my $infile = shift;
my $id = 0;

open FH, '<', $infile or die "Cannot open $infile: $!";
while (my $line = <FH>) {
    my @forms = split /\s+/, $line;
    foreach my $form (@forms) {
	my ($w, $p, $s) = split /\#/, $form;

	# inc the id number
	$id++;
	
	# check to see if there is a sense number assigned
	if ($s) {
	    print $w, '.', $p, ' ', $id, ' ', $s, "\n";
	}
	else {
	    # do nothing
	}
    }
}
close FH;

__END__

=head1 NAME

reformat-for-senseval.pl INPUT-FILE1 [INPUT-FILE2 ...]

=head1 SYNOPSIS

 wsd.pl --context words.txt --silent --format parsed > file.txt
 reformat-for-senseval.pl file.txt > answer.txt

=head1 DESCRIPTION

This script reads one or more files from the command line and reformats
them so that they can be scored using the Senseval scorer2 program.  The
input format is that of the wsd.pl program that is distributed with
WordNet-SenseRelate.  The output is printed to the standard output.

Note: be sure to run wsd.pl with the '--silent' option.  If this is not
done, wsd.pl will print configuration information that will cause this
script to fail.

=head1 AUTHORS

Jason Michelizzi, <jmichelizzi at users.sourceforge.net>

Ted Pedersen, <tpederse at d.umn.edu>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Jason Michelizzi and Ted Pedersen

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the
Free Software Foundation; either version 2 of the License, or (at your
option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.


