# $Id: Makefile.PL,v 1.3 2004/12/03 20:12:52 jmichelizzi Exp $

use strict;
use warnings;
use 5.006;
use ExtUtils::MakeMaker;

#

WriteMakefile(
    NAME              => 'WordNet::SenseRelate',
    VERSION_FROM      => 'lib/WordNet/SenseRelate.pm', # finds $VERSION
    PREREQ_PM         => {'WordNet::QueryData' => 1.37,
			  'WordNet::Similarity' => 0.08},
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/WordNet/SenseRelate.pm', # retrieve abstract from module
       AUTHOR         => 'Jason Michelizzi <jmichelizzi at users.sourceforge.net>') : ()),
    EXE_FILES         => ['utils/wsd.pl'],
);
