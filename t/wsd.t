# $Id: wsd.t,v 1.2 2005/03/12 20:47:03 jmichelizzi Exp $
#
# simple test script for wsd.pl

# specify number of tests below
use Test::More tests => 7;

use File::Spec;
my $tmp = File::Spec->tmpdir;

my $wsd_pl = File::Spec->catfile ('utils', 'wsd.pl');
ok (-e $wsd_pl);

# test the parsed mode
my $t1in = File::Spec->catfile ($tmp, "$$.1in");
ok (open (IN, '>', $t1in));
print IN "parking_tickets are expensive";
close IN;
END {unlink $t1in}
my $inc = "-Iblib/lib";
my $output = `$^X $inc $wsd_pl --context $t1in --format parsed --type WordNet::Similarity::lesk --silent 2>&1`;

chomp $output;

my $expected = 'parking_ticket#n#1 be#v#1 expensive#a#1';

is ($output, $expected);

# test the tagged mode
my $t2in = File::Spec->catfile ($tmp, "$$.2in");
ok (open (IN, '>', $t2in));
print IN "parking_tickets/NNS are/VBP expensive/JJ";
close IN;
END {unlink $t2in}
$output = `$^X $inc $wsd_pl --context $t2in --format tagged --type WordNet::Similarity::lesk --silent 2>&1`;
chomp $output;
is ($output, $expected);

# test raw mode
my $t3in = File::Spec->catfile ($tmp, "$$.3in");
ok (open (IN, '>', $t3in));

# bad grammar, but it does test the script nicely
print IN "parking_tickets, are expensive.";

close IN;
END {unlink $t3in}
$output = `$^X $inc $wsd_pl --context $t3in --format raw --type WordNet::Similarity::lesk --silent 2>&1`;
chomp $output;
is ($output, $expected);
