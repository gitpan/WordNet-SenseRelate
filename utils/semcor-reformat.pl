#!/usr/local/bin/perl

use strict;
use warnings;

use Getopt::Long;
use File::Spec;

our $key = 0;
our $semcor_dir;
our $file;
my $res = GetOptions (key => \$key, "semcor=s" => \$semcor_dir,
		      "file=s" => \$file);

unless ($res) {
    exit 1;
}

unless (defined $semcor_dir or defined $file) {
    print STDERR "No location for semcor was given\n";
    exit 2;
}

if ($semcor_dir) {
    unless (-e $semcor_dir) {
	print STDERR "Invalid directory '$semcor_dir'\n";
	exit 3;
    }
}
else {
    unless (-e $file) {
	print STDERR "Invalid input file '$file'\n";
	exit 4;
    }
}

sub wf_handler;
sub punc_handler;
sub p_handler;
sub s_handler;
sub context_handler;

my %posMap = (JJ =>   'a',
	      OD =>   'a',
	      JJR =>  'a',
	      JJT =>  'a',
	      CD =>   'a',
	      RB =>   'r',
	      RBR =>  'r',
	      RBT =>  'r',
	      RP =>   'r',
	      WRB =>  'r',
	      WQL=>   'r',
	      QL =>   'r',
	      QLP =>  'r',
	      RN =>   'r',
	      NN =>   'n',
	      NNS =>  'n',
	      NNP =>  'n',
	      NP =>   'n',
	      NPS =>  'n',
	      NR =>   'n',
	      NRS =>  'n',
	      VB  =>  'v',
	      VBD =>  'v',
	      VBG =>  'v',
	      VBN =>  'v',
	      VBZ =>  'v',
	      VBS =>  'v',
	      VBP =>  'v',
	      DO =>   'v',
	      DOD=>   'v',
	      DOZ=>   'v',
	      HV =>   'v',
	      HVD =>  'v',
	      HVG =>  'v',
	      HVN =>  'v',
	      HVZ =>  'v',
	      BE  =>  'v',
	      BED =>  'v',
	      BEDZ => 'v',
	      BEG =>  'v',
	      BEN =>  'v',
	      BEZ =>  'v',
	      BEM =>  'v',
	      BER =>  'v',
	      MD =>   'v');

my $flag = 1;

my %handlers = (contextfile => sub {}, # ignore this tag
		p => \&p_handler,
                s => \&s_handler,
                context => \&context_handler,
                wf => \&wf_handler,
                punc => \&punc_handler,
                );

# some global variables modified by the handler functions
my $paragraph_number = 0;
my $sentence_number = 0;
my $context_filename = File::Spec->devnull; #'/dev/null';
my $wordnum = 0;
# input file

my @files;
if ($semcor_dir) {
    # get the files we are going to process
    my $gpattern = File::Spec->catdir ($semcor_dir, 'brown1', 'tagfiles');
    $gpattern = File::Spec->catdir ($gpattern, 'br-*');
    @files = glob ($gpattern);
    $gpattern = File::Spec->catdir ($semcor_dir, 'brown2', 'tagfiles');
    $gpattern = File::Spec->catdir ($gpattern, 'br-*');
    push @files, glob ($gpattern);
}
else {
    @files = $file;
}


foreach my $f (@files) {
    processFile ($f)
}

exit;

sub processFile
{
    my $infile = shift;
    open (FH, '<', $infile) or die "Cannot open $infile: $!";

    local $/ = undef;

    my $file = <FH>;

    # silly hack
    $file =~ s/<punc>([^<>]+)<\/punc>/<punc type=\"$1\" \/>/g;

    while ($file =~ /<((?:\"[^\"]*\"|\'[^\']*\'|[^\'\">])*)>/g) {
	processTag ($1);
    }

    close FH;
}


sub processTag
{
    my $tag = shift;
    my $close_tag = 0;

    $tag =~ m|^(/)?(\w+)(.*)|;

    if ($1) {
	$close_tag = 1;
    }

    my $name = $2;
    unless (defined $name) {
	print STDERR "Nameless tag: '$tag'\n";
	return;
    }

    my $attrs_string = $3;

    my %attrs;

    while ($attrs_string =~ /(\w+)=(\S+|\"[^\"]+\")/g) {
	my $a = $1;
	my $val = $2;

	if (substr ($val, 0, 1) eq '"') {
	    $val = substr ($val, 1, length ($val) - 2);
	}

	$attrs{$a} = $val;
    }

    $handlers{$name} ($close_tag, %attrs);
}


sub punc_handler
{
    my $close_tag = shift;
    return if $close_tag;
    return if $key;

    my %attrs = @_;
    if ($attrs{type}) {
	if ($attrs{type} eq '.') {
	    print "\n";
	}
	elsif ($attrs{type} eq ';') {
	    print "\n";
	}
	elsif ($attrs{type} eq '!') {
	    print "\n";
	}
	elsif ($attrs{type} eq '?') {
	    print "\n";
	}
	else {
	    # do nothing
	}
    }
}

sub wf_handler
{
    my $close_tag = shift;
    return if $close_tag;

    my %attrs = @_;
    return unless $attrs{cmd} eq 'done';
    return unless defined $attrs{lemma};
    return if $attrs{wnsn} eq '0'; # drop words that wordnet doesn't have
    $flag = 0;

    if ($key) {
	#print $context_filename, '.', $paragraph_number, '.', $sentence_number;
	#print ' ';
	print $attrs{lemma}, '.', $posMap{$attrs{pos}}, ' ';
	print ++$wordnum, ' ';

	# When we generate a key, we want to show the sense number.  When
	# we generate input to WordNet-SenseRelate, then we don't want a
	# sense number.
	print $attrs{wnsn} if defined $attrs{wnsn};

	print "\n";
    }
    else {
	print $attrs{lemma};

	if (defined $attrs{pos}) {
	    my $pos = $posMap{$attrs{pos}};
	    if (defined $pos) {
		print '#', $pos;
	    }
	    else {
		print '#', $attrs{pos};
	    }
	}
	print ' ';
    }
}

sub p_handler
{
    my $close_tag = shift;
    return if $close_tag;

    my %attrs = @_;

    return unless defined $attrs{pnum};

    $paragraph_number = $attrs{pnum} + 0;
}

sub s_handler
{
    my $close_tag = shift;
    return if $close_tag;

    my %attrs = @_;

    return unless defined $attrs{snum};

    $sentence_number = $attrs{snum} + 0;
}

sub context_handler
{
    my $close_tag = shift;
    return if $close_tag;

    my %attrs = @_;

    return unless defined $attrs{filename};

    $context_filename = $attrs{filename};  
}

__END__

=head1 NAME

semcor-reformat {--semcor-dir DIR | --file FILE} [--key] 

=head1 SYNOPSIS

semcor-reformat --semcor-dir ~/semcor2.0

=head1 DESCRIPTION

This scripts reads a semcor-formatted file and produces formatted
text that can be used as input to wsd.pl.  Alternatively, if the
--key option is specified, the output will also include the sense
number for each work, and this output can be used as a key file.

=head1 AUTHORS

Jason Michelizzi, <jmichelizzi at users.sourceforge.net>

Ted Pedersen, <tpederse at users.sourceforge.net>

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
