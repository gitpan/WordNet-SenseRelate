package WordNet::SenseRelate;

# $Id: SenseRelate.pm,v 1.19 2005/03/11 22:15:09 jmichelizzi Exp $

=head1 NAME

WordNet::SenseRelate - perform Word Sense Disambiguation

=head1 SYNOPSIS

  use WordNet::SenseRelate;
  use WordNet::QueryData;
  my $qd = WordNet::QueryData->new;
  my $wsd = WordNet::SenseRelate->new (wordnet => $qd,
                                       measure => 'WordNet::Similarity::lesk');
  my @results = $wsd->disambiguate ();

=head1 DESCRIPTION

WordNet::SenseRelate implements an algorithm for Word Sense Disambiguation
that uses measures of semantic relatedness.  The algorithm is an extension
of an algorithm described by Pedersen, Banerjee, and Patwardhan[1].  This
implementation is similar to the original SenseRelate package but
disambiguates every word in the given context rather than just a single
word.

=head2 Methods

Note: the methods below will die() on certain errors (actually, they will
Carp::croak()).  Wrap calls to the methods in an eval BLOCK to catch the
exceptions.  See 'perldoc -f eval' for more information.

Example:

  my @res;
  eval {@res = $wsd->disambiguate (args...)}

  if ($@){
      print STDERR "An exception occurred ($@)\n";
  }

=over

=cut

use 5.006;
use strict;
use warnings;
use Carp;

our @ISA = ();

our $VERSION = '0.03';

my %wordnet;
my %compounds;
my %simMeasure; # the similarity/relatedness measure
my %stoplist;
my %pairScore;
my %contextScore;
my %trace;
my %outfile;
my %forcepos;

# signifies closed class words
use constant {CLOSED => 'c',
	      NOINFO => 'f'};

# Penn tagset
my %wnTag = (
    JJ => 'a',
    JJR => 'a',
    JJS => 'a',
    CD => 'a',
    RB => 'r',
    RBR => 'r',
    RBS => 'r',
    RP => 'r',
    WRB => CLOSED,
    CC => CLOSED,
    IN => CLOSED,
    DT => CLOSED,
    PDT => CLOSED,
    CC => CLOSED,
    'PRP$' => CLOSED,
    PRP => CLOSED,
    WDT => CLOSED,
    'WP$' => CLOSED,
    NN => 'n',
    NNS => 'n',
    NNP => 'n',
    NNPS => 'n',
    PRP => CLOSED,
    WP => CLOSED,
    EX => CLOSED,
    VBP => 'v',
    VB => 'v',
    VBD => 'v',
    VBG => 'v',
    VBN => 'v',
    VBZ => 'v',
    VBP => 'v',
    MD => 'v',
    TO => CLOSED,
    POS => undef,
    UH => CLOSED,
    '.' => undef,
    ':' => undef,
    ',' => undef,
    _ => undef,
    '$' => undef,
    '(' => undef,
    ')' => undef,
    '"' => undef,
    FW => NOINFO,
    SYM => undef,
    LS => undef,
    );



=item B<new>Z<>

Z<>The constructor for this class.  It will create a new instance and
return a reference to the constructed object.

Parameters:

  wordnet      => REFERENCE : WordNet::QueryData object
  measure      => STRING    : name of a WordNet::Similarity measure
  config       => FILENAME  : config file for above measure
  outfile      => FILENAME  : name of a file for output (optional)
  compfile     => FILENAME  : file containing compound words
  stoplist     => FILENAME  : file containing list of stop words
  pairScore    => INTEGER   : minimum pairwise score (default: 0)
  contextScore => INTEGER   : minimum overall score (default: 0)
  trace        => INTEGER   : generate traces (default: 0)
  forcepos     => INTEGER   : do part-of-speech coercion (default: 0)

Returns:

  A reference to the constructed object.

Example:

  WordNet::SenseRelate->new (wordnet => $query_data_obj,
                             measure => 'WordNet::Similarity::lesk',
                             trace   => 1);

The trace levels are:

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

These trace levels can be added together.  For example, by specifying
a trace level of 3, the context window will be displayed along with
the winning score for each pass.

=cut

sub new
{
    my $class = shift;
    my %args = @_;
    $class = ref $class || $class;

    my $qd;
    my $measure;
    my $measure_config;
    my $compfile;
    my $stoplist;
    my $pairScore = 0;
    my $contextScore = 0;
    my $trace;
    my $outfile;
    my $forcepos;

    while (my ($key, $val) = each %args) {
	if ($key eq 'wordnet') {
	    $qd = $val; 
	}
	elsif ($key eq 'measure') {
	    $measure = $val;
	}
	elsif ($key eq 'config') {
	    $measure_config = $val;
	}
	elsif ($key eq 'compfile') {
	    $compfile = $val;
	}
	elsif ($key eq 'stoplist') {
	    $stoplist = $val;
	}
	elsif ($key eq 'pairScore') {
	    $pairScore = $val;
	}
	elsif ($key eq 'contextScore') {
	    $contextScore = $val;
	}
	elsif ($key eq 'trace') {
	    $trace = $val;
	    $trace = defined $trace ? $trace : 0;
	}
	elsif ($key eq 'outfile') {
	    $outfile = $val;
	}
	elsif ($key eq 'forcepos') {
	    $forcepos = $val;
	}
	else {
	    croak "Unknown parameter type '$key'";
	}
    }

    unless (ref $qd) {
	croak "No WordNet::QueryData object supplied";
    }

    unless ($measure) {
	croak "No relatedness measure supplied";
    }

    my $self = bless [], $class;

    # initialize tracing;
    if (defined $trace) {
	$trace{$self} = {level => $trace, string => ''};
    }
    else {
	$trace{$self} = {level => 0, string => ''};
    }

    # require the relatedness modules
    my $file = $measure;
    $file =~ s/::/\//g;
    require "${file}.pm";

    # construct the relatedness object
    if (defined $measure_config) {
	$simMeasure{$self} = $measure->new ($qd, $measure_config);
    }
    else {
	$simMeasure{$self} = $measure->new ($qd);
    }

    # check for errors
    my ($errCode, $errStr) = $simMeasure{$self}->getError;
    if ($errCode) {
	croak $errStr;
    }

    # turn on traces in the relatedness measure if required
    if ($trace{$self}->{level} & 8) {
	$simMeasure{$self}->{trace} = 1;
    }
    else {
	$simMeasure{$self}->{trace} = 0;
    }


    # save ref to WordNet::QueryData obj
    $wordnet{$self} = $qd;

    $self->_loadCompfile ($compfile) if defined $compfile;
    $self->_loadStoplist ($stoplist) if defined $stoplist;

    # store threshold values
    $pairScore{$self} = $pairScore;
    $contextScore{$self} = $contextScore;

    # save output file name
    $outfile{$self} = $outfile;
    if ($outfile and -e $outfile) {
	unlink $outfile;
    }

    if (defined $forcepos) {
	$forcepos{$self} = $forcepos;
    }
    else {
	$forcepos{$self} = 0;
    }

    return $self;
}

# the destructor for this class.  You shouldn't need to call this
# explicitly (but if you really want to, you can see what happens)
sub DESTROY
{
    my $self = shift;
    delete $wordnet{$self};
    delete $simMeasure{$self};
    delete $compounds{$self};
    delete $stoplist{$self};
    delete $pairScore{$self};
    delete $contextScore{$self};
    delete $trace{$self};
    delete $outfile{$self};
    delete $forcepos{$self};
    1;
}

sub wordnet : lvalue
{
    my $self = shift;
    $wordnet{$self};
}

=item B<disambiguate>

Disambiguates all the words in the specified context and returns them
as a list.  If a word cannot be disambiguated, then it is returned "as is".
A word cannot be disambiguated if it is not in WordNet or if no value
exceeds the specified threshold.

The context parameter specifies the
words to be disambiguated.  It treats the value as one sentence.  To
disambiguate a document with multiple sentences, make one call to
disambiguate() for each sentence.

Parameters:

  window => INTEGER    : the window size to use
  tagged => BOOLEAN    : true if the text is tagged, false otherwise
  scheme => normal|sense1 : the disambiguation scheme to use
  context => ARRAY_REF : reference to an array of words to disambiguate

Returns:  An array of disambiguated words.

Example:

  my @results =
    $wsd->disambiguate (window => 3, tagged => 0, context => [@words]);

=cut

sub disambiguate
{
    my $self = shift;
    my %options = @_;
    my $contextScore;
    my $pairScore;
    my $window;
    my $tagged;
    my @context;
    my $scheme = 'normal';

    while (my ($key, $value) = each %options) {
	if ($key eq 'window') {
	    $window = $value;
	}
	elsif ($key eq 'tagged') {
	    $tagged = $value;
	}
	elsif ($key eq 'context') {
	    @context = @$value;
	}
	elsif ($key eq 'scheme') {
	    $scheme = $value;
	}
	else {
	    croak "Unknown option '$key'";
	}
    }

    my @newcontext = $self->_initializeContext ($tagged, @context);

    my @results;
    if ($scheme eq 'sense1') {
	@results = $self->doSense1 (@newcontext);
    }
    elsif ($scheme eq 'random') {
	@results = $self->doRandom (@newcontext);
    }
    elsif ($scheme eq 'normal') {
	@results = $self->doNormal ($pairScore, $contextScore, $window, @newcontext);
    }

    my @rval = map {s/\#o//; $_} @results;
    
    if ($outfile{$self}) {
	open OFH, '>>', $outfile{$self} or croak "Cannot open outfile: $!";

	for my $i (0..$#context) {
	    my $orig_word = $context[$i];
	    my $new_word = $rval[$i];
	    my ($w, $p, $s) = $new_word =~ /([^\#]+)(?:\#([^\#]+)(?:\#([^\#]+))?)?/;
	    printf OFH "%25s", $orig_word;
	    printf OFH " %24s", $w;
	    printf OFH "%3s", $p if defined $p;
	    printf OFH "%3s", $s if defined $s;
	    print OFH "\n";
	}

	close OFH;
    }

    return @rval;
}

sub _initializeContext
{
    my $self = shift;
    my $tagged = shift;
    my @context = @_;

    # compoundify the words (if we loaded a compounds file)
    if ($self->compounds ('#do#')) {
	@context = $self->_compoundify ($tagged, @context);
    }

    my @newcontext;
    # do stoplisting
    if ($stoplist{$self}) {
	foreach my $word (@context) {
	    if ($self->isStop ($word)) {
		push @newcontext, $word."#o";
	    }
	    else {
		push @newcontext, $word;
	    }
	}
    }
    else {
	@newcontext = @context;
    }

    # convert POS tags, if we have tagged text
    if ($tagged) {
	foreach my $wpos (@newcontext) {
	    $wpos = $self->convertTag ($wpos);
	}
    }

    return @newcontext;
}

sub doNormal {
    my $self = shift;
    my $pairScore = shift;
    my $contextScore = shift;
    my $window = shift;
    my @context = @_;

    # get all the senses for each word
    my @senses = $self->_getSenses (@context);


    # disambiguate
    my @results;

    local $| = 1;

    # for each word in the context, disambiguate the (target) word
    for my $targetIdx (0..$#context) {
	my @target_scores;
	
	unless (ref $senses[$targetIdx]) {
	    $results[$targetIdx] = $context[$targetIdx];
	    next;
	}


	# figure out which words are in the window
	my $lower = $targetIdx - $window;
	$lower = 0 if $lower < 0;
	my $upper = $targetIdx + $window;
	$upper = $#context if $upper > $#context;

	# expand context window to the left, if necessary
	my $i = $targetIdx - 1;
	while ($i >= $lower) {
	    last if $lower == 0;
	    unless (defined $senses[$i]) {
		$lower--;
	    }
	    $i--;
	}

	# expand context window to the right, if necessary
	my $j = $targetIdx + 1;
	while ($j <= $upper) {
	    last if $upper >= scalar $#context;
	    unless (defined $senses[$j]) {
		$upper++;
	    }
	    $j++;
	}

	# do some tracing
	if ($trace{$self} and ($trace{$self}->{level} & 1)) {
	    $trace{$self}->{string} .= "Context: ";
	    if ($lower < $targetIdx) {
		$trace{$self}->{string} .=
		    join (' ', @context[$lower..$targetIdx-1]) . ' ';
		
	    }

	    $trace{$self}->{string} .=
		"<target>$context[$targetIdx]</target>";
	    
	    if ($targetIdx < $upper) {
		$trace{$self}->{string} .= ' ' .
		    join (' ', @context[($targetIdx+1)..$upper]);
	    }

	    $trace{$self}->{string} .= "\n";
	}


	my $result;
	if ($forcepos{$self}) {
	    $result = $self->_forcedPosDisambig ($lower, $targetIdx, $upper,
						 \@senses, \@context);
	}
	else {
	    $result = $self->_normalDisambig ($lower, $targetIdx, $upper,
					       \@senses, \@context);
	}
	push @results, $result;

    }

    return @results;
}
    
=item B<getTrace>

Gets the current trace string and resets it to "".

Parameters:
  None

Returns:
  The current trace string (before resetting it).  If the returned string
  is not empty, it will end with a newline.

Example:
  my $str = $wsd->getTrace ();
  print $str;

=cut

sub getTrace
{
    my $self = shift;
    my $str = $trace{$self}->{string};
    $trace{$self}->{string} = '';
    return $str;
}

# does sense 1 disambiguation
sub doSense1
{
    my $self = shift;
    my @words = @_;
    my $wn = $wordnet{$self};

    my $datapath = $wn->dataPath;

    my @disambiguated;

    foreach my $word (@words) {
	my %senses;
	my @forms = $wn->validForms ($word);

	foreach my $form (@forms) {
	    my @t = $wn->querySense ($form);
	    if (scalar @t > 0) {
		$senses{$form} = $t[0];
	    }
	}

	my @best_senses;

	foreach my $key (keys %senses) {
	    my $sense = $senses{$key};

	    my $freq = $wn->frequency ($sense);

	    if ($#best_senses < 0) {
		push @best_senses, [$sense, $freq];
	    }
	    elsif ($best_senses[$#best_senses]->[1] < $freq) {
		@best_senses = ([$sense, $freq]);
	    }
	    elsif ($best_senses[$#best_senses]->[1] == $freq) {
		push @best_senses, [$sense, $freq];
	    }
	    else {
		# do nothing
	    }
	}

	if (scalar @best_senses) {
	    my $i = int (rand (scalar @best_senses));

	    push @disambiguated, $best_senses[$i]->[0];
	}
	else {
	    push @disambiguated, $word;
	}


    }
    return @disambiguated;
}

# does random guessing.  This could be considered a baseline approach
# of sorts.  Also try running normal disambiguation using the
# WordNet::Similarity::random measure
sub doRandom
{
    my $self = shift;
    my @words = @_;
    my $wn = $wordnet{$self};

    my $datapath = $wn->dataPath;

    my @disambiguated;

    foreach my $word (@words) {
	my @forms = $wn->validForms ($word);

	my @senses;

	foreach my $form (@forms) {
	    my @t = $wn->querySense ($form);
	    if (scalar @t > 0) {
		push @senses, @t;
	    }
	}


	if (scalar @senses) {
	    my $i = int (rand (scalar @senses));
	    push @disambiguated, $senses[$i];
	}
	else {
	    push @disambiguated, $word;
	}


    }
    return @disambiguated;
}

sub _forcedPosDisambig
{
    my $self = shift;
    my $lower = shift;
    my $targetIdx = shift;
    my $upper = shift;
    my $senses_ref = shift;
    my $context_ref = shift;
    my $measure = $simMeasure{$self};
    my $result;
    my @traces;
    my @target_scores;


    # for each sense of the target word ...
    for my $i (0..$#{$senses_ref->[$targetIdx]}) {
	unless (ref $senses_ref->[$targetIdx]
		and  defined $senses_ref->[$targetIdx][$i]) {
	    $target_scores[$i] = -1;
	    next;
	}
	my @tempScores;


	my $target_pos = getPos ($senses_ref->[$targetIdx][$i]);

	# for each (context) word in the window around the target word
	for my $contextIdx ($lower..$upper) {
	    next if $contextIdx == $targetIdx;
	    next unless ref $senses_ref->[$contextIdx];

	    my @goodsenses;
	    # * check if senses for context word work with target word *
	    if (needCoercePos ($target_pos, $senses_ref->[$contextIdx])) {
		@goodsenses = $self->coercePos ($context_ref->[$contextIdx],
						$target_pos);
	    }
	    else {
		@goodsenses = @{$senses_ref->[$contextIdx]};
	    }

	    # for each sense of the context word in the window
	    for my $k (0..$#{$senses_ref->[$i]}) {
		unless (defined $senses_ref->[$contextIdx][$k]) {
		    $tempScores[$k] = -1;
		    next;
		}
		    
		$tempScores[$k] =
		    $measure->getRelatedness ($senses_ref->[$targetIdx][$i],
					      $senses_ref->[$contextIdx][$k]);
		    
		if ($trace{$self}->{level} & 8) {
		    push @traces, $measure->getTraceString ();
		}
		# clear errors in Similarity object
		$measure->getError () unless defined $tempScores[$k];
	    }
	    my $best = -2;
	    foreach my $temp (@tempScores) {
		next unless defined $temp;
		$best = $temp if $temp > $best;
	    }

	    if ($best > $pairScore{$self}) {
		$target_scores[$i] += $best;
	    }
	}
    }

    # find the best score for this sense of the target word

    # first, do a bit of tracing
    if (ref $trace{$self} and ($trace{$self}->{level} & 4)) {
	$trace{$self}->{string} .= "  Scores for $context_ref->[$targetIdx]\n";
    }

    # now find the best sense
    my $best_tscore = -1;
    foreach my $i (0..$#target_scores) {
	my $tscore = $target_scores[$i];
	next unless defined $tscore;
	
	    if (ref $trace{$self} and $trace{$self}->{level} & 4) {
		$trace{$self}->{string} .= "    $senses_ref->[$targetIdx][$i]: $tscore\n";
	    }
	
	# ignore scores less than the threshold
	next unless $tscore >= $contextScore{$self};
	
	if ($tscore > $best_tscore) {
	    $result = $senses_ref->[$targetIdx][$i];
	    $best_tscore = $tscore;
	}
    }

    if ($best_tscore < 0) {
	$result = $context_ref->[$targetIdx];
    }
    
    if (ref $trace{$self} and $trace{$self}->{level} & 2) {
	$trace{$self}->{string} .= "  Winning score: $best_tscore\n";
    }

    if ($trace{$self}->{level} & 8) {
	foreach my $str (@traces) {
	    $trace{$self}->{string} .= "$str\n";
	}
	@traces = ();
    }

    return $result;

    croak __PACKAGE__, "::_forcedPosDisambig(): Not implemented";
}

sub _normalDisambig
{
    my $self = shift;
    my $lower = shift;
    my $targetIdx = shift;
    my $upper = shift;
    my $senses_ref = shift;
    my $context_ref = shift;
    my $measure = $simMeasure{$self};
    my $result;

    my @traces;
    my @target_scores;

    # for each sense of the target word ...
    for my $i (0..$#{$senses_ref->[$targetIdx]}) {
	unless (ref $senses_ref->[$targetIdx]
		and  defined $senses_ref->[$targetIdx][$i]) {
	    $target_scores[$i] = -1;
	    next;
	}
	my @tempScores;
	    

	# for each (context) word in the window around the target word
	for my $contextIdx ($lower..$upper) {
	    next if $contextIdx == $targetIdx;
	    next unless ref $senses_ref->[$i];

	    # for each sense of the context word in the window
	    for my $k (0..$#{$senses_ref->[$i]}) {
		unless (defined $senses_ref->[$contextIdx][$k]) {
		    $tempScores[$k] = -1;
		    next;
		}
		    
		$tempScores[$k] =
		    $measure->getRelatedness ($senses_ref->[$targetIdx][$i],
					      $senses_ref->[$contextIdx][$k]);
		    
		if ($trace{$self}->{level} & 8) {
		    push @traces, $measure->getTraceString ();
		}
		# clear errors in Similarity object
		$measure->getError () unless defined $tempScores[$k];
	    }
	    my $best = -2;
	    foreach my $temp (@tempScores) {
		next unless defined $temp;
		$best = $temp if $temp > $best;
	    }

	    if ($best > $pairScore{$self}) {
		$target_scores[$i] += $best;
	    }
	}
    }

    # find the best score for this sense of the target word

    # first, do a bit of tracing
    if (ref $trace{$self} and ($trace{$self}->{level} & 4)) {
	$trace{$self}->{string} .= "  Scores for $context_ref->[$targetIdx]\n";
    }

    # now find the best sense
    my $best_tscore = -1;
    foreach my $i (0..$#target_scores) {
	my $tscore = $target_scores[$i];
	next unless defined $tscore;
	
	    if (ref $trace{$self} and $trace{$self}->{level} & 4) {
		$trace{$self}->{string} .= "    $senses_ref->[$targetIdx][$i]: $tscore\n";
	    }
	
	# ignore scores less than the threshold
	next unless $tscore >= $contextScore{$self};
	
	if ($tscore > $best_tscore) {
	    $result = $senses_ref->[$targetIdx][$i];
	    $best_tscore = $tscore;
	}
    }

    if ($best_tscore < 0) {
	$result = $context_ref->[$targetIdx];
    }
    
    if (ref $trace{$self} and $trace{$self}->{level} & 2) {
	$trace{$self}->{string} .= "  Winning score: $best_tscore\n";
    }

    if ($trace{$self}->{level} & 8) {
	foreach my $str (@traces) {
	    $trace{$self}->{string} .= "$str\n";
	}
	@traces = ();
    }

    return $result;
}

sub compounds : lvalue
{
    my $self = shift;
    my $comp = shift;
    if (defined $comp) {
	return $compounds{$self}->{$comp};
    }
    else {
	return $compounds{$self};
    }
}

sub isStop
{
    my $self = shift;
    my $word = shift;

    foreach my $re (@{$stoplist{$self}}) {
	if ($word =~ /$re/) {
	    return 1;
	}
    }
    return 0;
}

# checks to see if the POS of at least one word#pos#sense string in $aref 
# is $pos
sub needCoercePos
{
    my $pos = shift;

    # Only coerce if target POS is noun or verb.
    # The measures that take advantage of POS coercion only work with
    # nouns and verbs.
    unless ($pos eq 'n' or $pos eq 'v') {
	return 0;
    }

    my $aref = shift;
    foreach my $wps (@$aref) {
	if ($pos eq getPos ($wps)) {
	    return 0;
	}
    }
    return 1;
}

sub convertTag
{
    my $self = shift;
    my $wordpos = shift;
    my $index = index $wordpos, "/";

    if ($index <  0) {
	return $wordpos;
    }
    elsif ($index == 0) {
	return undef;
    }
    elsif (index ($wordpos, "'") == 0) {
        # we have a contraction
        my $word = substr $wordpos, 0, $index;
        my $tag = substr $wordpos, $index + 1;

        return $self->convertContraction ($word, $tag);
    }
    else {
	my $word = substr $wordpos, 0, $index;
	my $old_pos_tag = substr $wordpos, $index + 1;
	my $new_pos_tag = $wnTag{$old_pos_tag};

	if ((defined $new_pos_tag) and ($new_pos_tag =~ /[nvar]/)) {
	    return $word . '#' . $new_pos_tag;
	}
	else {
	    return $word;
	}
    }
}


sub convertContraction
{
    my ($self, $word, $tag) = @_;
    if ($word eq "'s") {
	if ($tag =~ /^V/) {
	    return "is#v";
	}
	else {
	    return "";
	}
    }
    elsif ($word eq "'re") {
	return "are#v";
    }
    elsif ($word eq "'d") {
	return "had#v"; # actually this could be would as well
    }
    elsif ($word eq "'ll") {
	return "will#v";
    }
    elsif ($word eq "'em") {
	return "";
    }
    elsif ($word eq "'ve") {
	return "have#v";
    }
    elsif ($word eq "'m") {
	return "am#v";
    }
    elsif ($word eq "'t") { # HELP should be n't
	return "not";
    }
    else {
	return "$word#$tag";
    }

}

# noun to non-noun ptr symbols, with frequencies
# -u 329 (dmnu)  - cf. domn (all domains)
# -r 80  (dmnr)
# = 648  (attr)
# -c 2372 (dmnc)
# + 21390 (deri) lexical

# verb to non-verb ptr symbols, with frequencies
# ;u 16   (dmtu) - cf. domt (all domains)
# ;c 1213 (dmtc)
# ;r 2    (dmtr)
# + 21095 (deri) lexical

# adj to non-adj
# \ 4672   (pert) pertains to noun ; lexical
# ;u 233  
# ;c 1125
# = 648    (attr)
# < 124    (part) particple of verb ; lexical
# ;r 76

# adv to non-adv
# \ 3208    (derived from adj)
# ;u 74
# ;c 37
# ;r 2

sub coercePos
{
    my $self = shift;
    my $word = shift;
    my $pos = shift;
    my $wn = $wordnet{$self};

    # remove pos tag, if present
    $word =~ s/\#.*//;

    my @forms = $wn->validForms ($word);

    if (0 >= scalar @forms) {
	return undef;
    }

    # pre-compile the pattern
    my $cpattern = qr/\#$pos/;

    foreach my $form (@forms) {
	if ($form =~ /$cpattern/) {
	    return $form;
	}
    }

    # didn't find a surface match, look along cross-pos relations

    my @goodforms;
    foreach my $form (@forms) {
	my @cands = $wn->queryWord ($form, "deri");
	foreach my $candidate (@cands) {
	    if ($candidate =~ /$cpattern/) {
		push @goodforms, $candidate;
	    }
	}
    }

    return @goodforms;
}

# get all senses for each context word
sub _getSenses
{
    my $self = shift;
    my @context = @_;
    my @senses;

    for my $i (0..$#context) {
	# first get all forms for each POS
	if ($context[$i] =~ /\#o/) {
	    $senses[$i] = undef;
	}
	else {
	    my @forms = $self->wordnet->validForms ($context[$i]);

	    if (scalar @forms == 0) {
		$senses[$i] = undef;
	    }
	    else {
		# now get all the senses for each form
		foreach my $form (@forms) {
		    my @temps = $self->wordnet->querySense ($form);
		    push @{$senses[$i]}, @temps;
		}
	    }
	}
    }
    return @senses;
}

sub _loadStoplist
{
    my $self = shift;
    my $file = shift;
    open SFH, '<', $file or die "Cannot open stoplist $file: $!";
    $stoplist{$self} = [];
    while (my $line = <SFH>) {
        chomp $line;
	$line =~ m|/(.*)/|;
        push @{$stoplist{$self}}, qr/$1/;
    }
    close SFH;
}

sub _loadCompfile
{
    my $self = shift;
    my $compfile = shift;
    $compounds{$self} = {};

    open CFH, '<', $compfile or die "Cannot open '$compfile': $!";
    while (<CFH>) {
	chomp;
	next unless defined;
	$self->compounds->{$_} = 1;
    }
    close CFH;

    # a special sentinal.  Later, we can check if this exists to see
    # if we should do compoundification
    $self->compounds->{'#do#'} = 1;
}

sub _compoundify
{
    my $self = shift;
    my $tagged = shift; # tags would be in Penn Treebank form
    my @wordpos = @_;
    my @words;

    foreach my $wpos (@wordpos) {
	my $index = index $wpos, '/';
	if ($index < 0) {
	    push @words, lc $wpos;
	}
	else {
	    push @words, lc substr $wpos, 0, $index;
	}
    }

    my @rvalues;

    my $i = 0;
    my $j = $#words;
    while ($i < $#words) {
	my $candidate = join '_', @words[$i..$j];
	if (defined $self->compounds ($candidate)) {
	    # do something with $candidate
	    push @rvalues, $candidate;
	    $i = $j + 1;
	    $j = $#words;
	}
	elsif (--$j > $i) {
	    # nothing to do
	}
	else {
	    push @rvalues, $wordpos[$i];
	    $i++;
	    $j = $#words;
	}
    }

    my $lastword = $words[$#words];
    unless ($lastword =~ /\Q$rvalues[$#rvalues]\E/) {
	push @rvalues, $wordpos[$#wordpos];
    }

    return @rvalues;
}

sub getPos
{
    my $string = shift;
    my $p = index $string, "#";
    return undef if $p < 0;
    my $pos = substr $string, $p+1, 1;
    return $pos;
}

1;

__END__

=pod

=back

=head1 SEE ALSO

WordNet::Similarity

The main web page for SenseRelate is

http://senserelate.sourceforge.net/

There are several mailing lists for SenseRelate:

http://lists.sourceforge.net/lists/list-info/senserelate-users

http://lists.sourceforge.net/lists/list-info/senserelate-news

http://lists.sourceforge.net/lists/list-info/senserelate-developers

=head1 REFERENCES

=over

=item [1]

Ted Pedersen, Satanjeev Banerjee, and Siddharth Patwardhan. 2003.  Maximizing
Semantic Relatedness to Perform Word Sense Disambiguation. (submitted)

=back

=head1 AUTHORS

Jason Michelizzi, E<lt>jmichelizzi at users.sourceforge.netE<gt>

Ted Pedersen, E<lt>tpederse at d.umn.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2004-2005 by Jason Michelizzi and Ted Pedersen

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

=cut
