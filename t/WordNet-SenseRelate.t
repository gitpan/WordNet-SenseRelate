# $Id: WordNet-SenseRelate.t,v 1.7 2004/12/17 21:13:01 jmichelizzi Exp $

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl WordNet-SenseRelate.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 13;
BEGIN {use_ok WordNet::SenseRelate}
BEGIN {use_ok WordNet::QueryData}

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $qd = WordNet::QueryData->new;
ok ($qd);

my @context = ('my/PRP$', 'cat/NN', 'is/VBZ', 'a/DT', 'wise/JJ', 'cat/NN');

my $obj = WordNet::SenseRelate->new (wordnet => $qd,
				     measure => 'WordNet::Similarity::lesk',
				     pairScore => 1,
				     contextScore => 1);
ok ($obj);

my @res = $obj->disambiguate (window => 2,
			      tagged => 1,
			      context => [@context]);

no warnings 'qw';
my @expected = qw/my cat#n#4 be#v#3 a#n#2 wise#a#4 cat#n#4/;

is ($#res, $#expected);

for my $i (0..$#expected) {
	is ($res[$i], $expected[$i]);
}

undef $obj;

# try it with tracing on
$obj = WordNet::SenseRelate->new (wordnet => $qd,
				  measure => 'WordNet::Similarity::lesk',
				  trace => 1,
				  );

ok ($obj);

undef @res;

@res = $obj->disambiguate (window => 2,
			   tagged => 1,
			   context => [@context]);

my $str = $obj->getTrace ();

ok ($str);



