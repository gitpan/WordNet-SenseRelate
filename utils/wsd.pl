#!/usr/local/bin/perl

# $Id: wsd.pl,v 1.14 2004/12/23 18:21:04 jmichelizzi Exp $

use strict;
use warnings;

use WordNet::SenseRelate;
use WordNet::QueryData;
use Getopt::Long;

our $measure = 'WordNet::Similarity::lesk';
our $mconfig;
our $contextf;
#our $tagged = 'auto';
our $compfile;
our $stoplist;
our $window = 3;
our $contextScore = 0;
our $pairScore = 0;
our $silent;
our $trace;
our $help;
our $version;
our $scheme = 'normal';
our $boundary;
our $outfile;

my $ok = GetOptions ('type|measure=s' => \$measure,
		   'config=s' => \$mconfig,
		   'context=s' => \$contextf,
#		   'tagged=i' => \$tagged,
		   'compounds=s' => \$compfile,
		   'stoplist=s' => \$stoplist,
		   'window=i' => \$window,
		   'pairScore=f' => \$pairScore,
		   'contextScore=f' => \$contextScore,
		   'scheme=s' => \$scheme,
		   'boundary!' => \$boundary,
		   silent => \$silent,
		   'trace=i' => \$trace,
		   help => \$help,
		   version => \$version,
		   'outfile=s' => \$outfile,
		   );
$ok or exit 1;

if ($help) {
    showUsage ("Long");
    exit;
}

if ($version) {
    print "wsd.pl version 0.01\n";
    print "Copyright (C) 2004, Jason Michelizzi and Ted Pedersen\n\n";
    print "This is free software, and you are welcome to redistribute it\n";
    print "under certain conditions.  This software comes with ABSOLUTELY\n";
    print "NO WARRANTY.  See the file COPYING or run 'perldoc perlgpl' for\n";
    print "more information.\n";
    exit;
}

unless (defined $contextf) {
    print STDERR "A context file is required.\n";
    showUsage ();
    exit 1;
}


my $istagged = isTagged ($contextf);

unless (defined $boundary) {
    $boundary = !$istagged;
}

unless ($silent) {
    print "Current configuration:\n";
    print "    context file  : $contextf\n";
    print "    scheme        : $scheme\n";
    print "    tagged text   : ", ($istagged ? "yes" : "no"), "\n";
    print "    measure       : $measure\n";
    print "    window        : ", $window, "\n";
    print "    contextScore  : ", $contextScore, "\n";
    print "    pairScore     : ", $pairScore, "\n";
    print "    measure config: ", ($mconfig ? $mconfig : '(none)'), "\n";
    print "    compound file : ", ($compfile ? $compfile : '(none)'), "\n";
    print "    stoplist      : ", ($stoplist ? $stoplist : '(none)') , "\n";
    print "    trace         : ", ($trace ? $trace : "no"), "\n";
    print "    boundary      : ", ($boundary ? "detect" : "assume"), "\n";
}

local $| = 1;
print "Loading WordNet... " unless $silent;
my $qd = WordNet::QueryData->new;
print "done.\n" unless $silent;

# options for the WordNet::SenseRelate constructor
my %options = (wordnet => $qd,
	       measure => $measure,
	       );
$options{config} = $mconfig if defined $mconfig;
$options{compfile} = $compfile if defined $compfile;
$options{stoplist} = $stoplist if defined $stoplist;
$options{trace} = $trace if defined $trace;
$options{pairScore} = $pairScore if defined $pairScore;
$options{contextScore} = $contextScore if defined $contextScore;
$options{outfile} = $outfile if defined $outfile;

my $sr = WordNet::SenseRelate->new (%options);


open (FH, '<', $contextf) or die "Cannot open '$contextf': $!";

my @sentences;
if ($boundary) {
    local $/ = undef;
    my $input = <FH>;
    $input =~ tr/\n/ /;


    @sentences = splitSentences ($input);
    undef $input;
}
else {
    @sentences = <FH>;
}

close FH;
my $i = 0;
foreach my $sentence (@sentences) {
    my @context = split /\s+/, $sentence;
    next unless scalar @context > 0;
    pop @context while !defined $context[$#context];
	
    my @res = $sr->disambiguate (window => $window,
				 tagged => $istagged,
				 scheme => $scheme,
				 context => [@context]);

    print STDOUT join (' ', @res), "\n";

    if ($trace) {
	my $tstr = $sr->getTrace ();
	print $tstr, "\n";
    }
}

exit;

sub isTagged
{
    my $file = shift;
    open FH, '<', $file or die "Cannot open context file '$file': $!";
    my @words;
    while (my $line = <FH>) {
	chomp $line;
	push @words, split (/\s+/, $line);
	last if $#words > 20;
    }
    close FH;

    my $tag_count = 0;
    foreach my $word (@words) {
	$tag_count++ if $word =~ m|/\S|;
    }
    my $ratio = $tag_count / scalar @words;

    # we consider the corpus to be tagged if we found that 70% or more
    # of the first 20 words were tagged (70% is somewhat of an arbitrary
    # value).
    return 1 if $ratio > 0.7;
    return 0;
}


# The sentence boundary algorithm used here is based on one described
# by C. Manning and H. Schutze. 2000. Foundations of Statistical Natural
# Language Processing. MIT Press: 134-135.
sub splitSentences
{
    my $string = shift;
    return unless $string;

    # abbreviations that (almost) never occur at the end of a sentence
    my @known_abbr = qw/prof Prof ph d Ph D dr Dr mr Mr mrs Mrs ms Ms vs/;

    # abbreviations that can occur at the end of sentence
    my @sometimes_abbr = qw/etc jr Jr/;


    my $pbm = '<pbound/>'; # putative boundary marker

    # put a putative sent. boundary marker after all .?!
    $string =~ s/([.?!])/$1$pbm/g;

    # move the boundary after quotation marks
    $string =~ s/$pbm"/"$pbm/g;
    $string =~ s/$pbm'/'$pbm/g;

    # remove boundaries after certain abbreviations
    foreach my $abbr (@known_abbr) {
	$string =~ s/\b$abbr(\W*)$pbm/$abbr$1 /g;
    }

    foreach my $abbr (@sometimes_abbr) {
	$string =~ s/$abbr(\W*)\Q$pbm\E\s*([a-z])/$abbr$1 $2/g;
    }

    # remove !? boundaries if not followed by uc letter
    $string =~ s/([!?])\s*$pbm\s*([a-z])/$1 $2/g;


    # all remaining boundaries are real boundaries
    my @sentences = map {s/^\s+|\s+$//g; $_} split /[.?!]\Q$pbm\E/, $string;
}

sub showUsage
{
    my $long = shift;
    print "Usage: wsd.pl --context FILE [--scheme SCHEME] [--type MEASURE]\n";
    print "              [--config FILE] [--compounds FILE] [--stoplist FILE]\n";
    print "              [--window INT] [--contextScore NUM] [--pairScore NUM] [--boundary]\n";
    print "              [--outfile FILE] [--trace INT] [--silent]\n";
    print "              | {--help | --version}\n";

    if ($long) {
	print "Options:\n";
	print "\t--context FILE       a file containing the text to be disambiguated\n";
	print "\t--scheme SCHEME      disambiguation scheme to use.  Valid values\n";
	print "\t                     are 'normal' and 'sense1'.\n";
	print "\t--type MEASURE       the relatedness measure to use\n";
	print "\t--config FILE        a config file for the relatedness measure\n";
	print "\t--compounds FILE     a file of compound words known to WordNet\n";
	print "\t--stoplist FILE      a file containing a list of regular expressions\n";
	print "\t--window INT         the window size to use (an integer)\n";
	print "\t--contextScore NUM   the overall minimum score required to project a\n";
	print "\t                     winner\n";
	print "\t--pairScore NUM      the minimum pairwise threshold used in the\n";
	print "\t                     algorithm\n";
	print "\t--outfile FILE       the name of an output file\n";
	print "\t--boundary           automatically detect sentence boundaries\n";
	print "\t--trace INT          turn tracing on; higher value results in more\n";
	print "\t                     traces\n";
	print "\t--silent             run silently; shows only final output\n";
	print "\t--help               show this help message\n";
	print "\t--version            show version information\n";
    }
}

__END__

=head1 NAME

wsd.pl - disambiguate words

=head1 SYNOPSIS

wsd.pl --context FILE [--scheme SCHEME] [--type MEASURE] [--config FILE] [--compounds FILE] [--stoplist FILE] [--window INT] [--contextScore NUM] [--pairScore NUM] [--outfile FILE] [--boundary] [--trace INT] [--silent] | --help | --version

=head1 DESCRIPTION

Disambiguates each word in the context file using the specified relatedness
measure (or WordNet::Similarity::lesk if none is specified).

=head1 OPTIONS

N.B., the I<=> sign between the option name and the option parameter is
optional.

=over

=item --context=B<FILE>

The input file containing the text to be disambiguated.  This
"option" is required.

=item --scheme=B<SCHEME>

The disambiguation scheme to use.  Valid values are "normal" and "sense1".
The default is "normal".  WordNet sense 1 disambiguation guesses that the
correct sense for each word is the first sense in WordNet because the
senses of words in WordNet are ranked according to frequency.  The first
sense is more likely than the second, the second is more likely than the
third, etc.

=item --measure=B<MEAURE>

The relatedness measure to be used.  The default is WordNet::Similarity::lesk.

=item --config=B<FILE>

The name of a configuration file for the specified relatedness measure.

=item --compounds=B<FILE>

A file containing compound words.

=item --stoplist=B<FILE>

A file containing regular expressions (as understood by Perl).  Any word
matching one of the regular expressions in the file is removed.  Each
regular expression must be on its own line, and any trailing whitespace
is ignored.

=item --window=B<INTEGER>

The window size used in the disambiguation algorithm.  The default is 3.

=item --contextScore=B<REAL>

If no sense of the target word achieves this minimum score, then
no winner will be projected (e.g., it is assumed that there is
no best sense or that none of the senses are sufficiently related
to the surrounding context).  The default is zero.

=item --pairScore=B<REAL>

The minimum pairwise score between a sense of the target word and
the best sense of a context word that will be used in computing
the overall score for that sense of the target word.  Setting this
to be greater than zero (but not too large) will reduce noise.
The default is zero.

=item --outfile=B<FILE>

The name of a file to which output should be sent.

=item --boundary

Automatically detect sentence boundaries.  By default, if the input text is
POS tagged, then it is assumed that the input file has once sentence per
line.  If the text is not POS tagged, then sentence boundary detection
is done.  This option can be used to override this default behavior.  To
force sentence boundary detection, use this option.  To prevent sentence
boundary detection, negate the option (I<--no-boundary>).

=item --trace=B<INT>

Turn tracing on/off.  A value of zero turns tracing off, a non-zero value
turns tracing on.  The different trace levels can be added together
to see the combined traces.  The trace levels are:

=over

=item 1

Show the context window for each pass through the algorithm.

=item 2

Display winning score for each pass.

=item 4

Display the scores for all senses for each pass (overrides 2).

=item 8

Display traces from the semantic relatedness module.

=back

=item --silent

Silent mode.  No information about progress, etc. is printed.  Just the
final output.

=back

=head1 AUTHORS

Jason Michelizzi, E<lt>jmichelizzi at users.sourceforge.netE<gt>

Ted Pedersen, E<lt>tpederse at d.umn.eduE<gt>

=head1 BUGS

None known.

=head1 COPYRIGHT

Copyright (C) 2004 Jason Michelizzi and Ted Pedersen

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

=cut
