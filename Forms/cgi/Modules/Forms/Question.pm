#!/usr/bin/perl
#-----------------------------------------------------------------------
#
#   Copyright 2015 Exware Solutions, Inc.  http://www.exware.com
#
#   This file is part of ExSite WebWare (ExSite, for short).
#
#   ExSite is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   ExSite is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with ExSite; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
#   Users requiring warranty coverage and/or support may arrange alternate
#   commercial licensing for ExSite, by contacting Exware Solutions 
#   via the website noted above.
#
#----------------------------------------------------------------------------

package Modules::Forms::Question;

use strict;
use ExSite::Config;
use ExSite::Content;
use ExSite::Form;
use ExSite::Misc;
use ExSite::Object;

use vars qw(@ISA);
@ISA = qw(ExSite::Content);

# loading: need data, metadata, flags

sub loaded {
    my $this = shift;
    if (! $this->{data} ||               # nothing loaded
	! exists $this->{data}{mtime} || # partial record only
	! exists $this->{metadata} ||    # no metadata
	! exists $this->{flags}) {       # no flags
	$this->load(@_); 
    }
    return ($this->{data} && exists $this->{metadata} && exists $this->{flags});
}

sub load {
    my ($this,$data) = @_;
    if ($this->SUPER::load()) {
	# preload metadata
	$this->{metadata} = $this->meta->get_all();
	$this->flags();
    }
}

sub form {
    my $this = shift;
    if (! exists $this->{form}) {
	$this->{form} = $this->parent();
    }
    return $this->{form};
}

sub is_freeform {
    my $this = shift;
    return ($this->format =~ /short text|long text|password/);
}

sub is_question {
    my $this = shift;
    return ($this->format !~ /label/);
}

# metadata

sub format {
    my $this = shift;
    if (! $this->{format}) {
	if ($this->loaded()) {
	    $this->{format} = $this->{metadata}{format} || "short text";
	}
    }
    return $this->{format};
}

sub datatype {
    my $this = shift;
    if (! $this->{datatype}) {
	if ($this->loaded()) {
	    $this->{datatype} = $this->{metadata}{datatype};
#	    if (! $this->{datatype}) {
#		$this->{datatype} = $this->format eq "long text" ?
#		    "text" : "string";
#	    }
	}
    }
    return $this->{datatype};
}

sub size {
    my $this = shift;
    if ($this->loaded()) {
	return $this->{metadata}{size};
    }
    return undef;
}

sub allowed_answers {
    my $this = shift;
    if ($this->loaded()) {
	my $fmt = $this->format();
	my $value;
	if ($fmt =~ /checkbox|hidden/) {
	    $value = $this->{metadata}{preset};
	}
	elsif ($fmt =~ /select|radio|checklist/) {
	    $value = $this->{metadata}{options};
	}
	return wantarray ? split(/\|/, $value) : $value;
    }
    return undef;
}

# question: returns the question itself

sub question {
    my $this = shift;
    my $out = $this->get_html();
    if (! $out) { $out = $this->title; }
    return $out;
}

# answer_regexp: answers to this question must match this regexp

sub answer_regexp {
    my $this = shift;
    if ($this->loaded()) {
	if ($this->is_freeform()) {
	    my $re = $this->DB->{map}->regexp($this->datatype);
	    return $re ? $re : ".*";
	}
	elsif ($this->format =~ /\+other$/) {
	    return ".*";
	}
	elsif ($this->format =~ /^checkbox$/) {
	    return $this->allowed_answers() || $config{Forms}{checkbox_default} || "ON";
	}
	else {
	    my $val = $this->allowed_answers();
	    if ($val) {
		$val =~ s/\s*\|\s*/\|/g;   # remove leading/trailing whitespace
		$val =~ s/==[\s\w]+==|//g; # remove help lines
		return &safe_regex($val);  # mask sensitive chars
	    }
	    else {
		return ".*";
	    }
	}
    }
    return undef;
}

sub answer {
    my ($this,$response_id) = @_;
    my $a = new Modules::Forms::Answer();
    my @data = $share{DB}->fetch_match("answer",{response_id=>$response_id,question_id=>$this->id});
    if (@data > 0) {
	$a->setup(data=>$data[0]);
    }
    return $a;
}

sub validate_answer {
    my ($this,$value) = @_;
    # is $value a valid answer to this question?
    if ($this->loaded()) {
	if (length $value) {
	    my $re;
	    my $fmt = $this->format();
	    my $baseval = $this->{metadata}{options};
	    if ($fmt =~ /multiselect|checklist/) {
		# multiselect fields have multiple values to validate
		my @val = split /; /, $value;
		$baseval =~ s/\s*\|\s*/\|/g;
		# allow certain regex-sensitive characters
		$baseval = &safe_regex($baseval);
		foreach my $v (@val) {
		    if ($v !~ /^$baseval$/) {
			return &substitute($msg{"Invalid input for \"[[label]]\""},
					   {label=>$this->label()});
		    }
		}
	    }
	    else {
		# single value
		my $re = $this->answer_regexp();
		if ($value !~ /^$re$/si) { 
		    return &substitute($msg{"Invalid input for \"[[label]]\""},
				       {label=>$this->label()});
		}
		else {
		    # any value is okay
		    return undef;
		}
	    }
	}
	elsif ($this->{flags}{required}) {
	    # no value provided
	    return &substitute($msg{"\"[[label]]\" is required."},{label=>$this->title()});
	}
    }
    return undef;
}

#=== DISPLAY

sub show {
    my ($this,%opt) = @_;
    my $stat = $this->run_handler("Forms_Question_show",\%opt);
    return $stat if (defined $stat);
    if ($this->loaded()) {
	return undef if ($this->access > $share{DB}->level); # perm denied
	if (! $opt{FormBuilder}) {
	    # probably an admin preview
	    $opt{FormBuilder} = new ExSite::FormBuilder();
	    #$opt{FormBuilder}->template($this->template);
	}
	my $prompt = $this->title;
	my $required = $this->{flags}{required};
	my $format = $opt{format} || $this->format();
	if ($required && $format eq "checklist") { $required = -1; } 
	my %in = (name=>$opt{name} || $this->name,
		  id=>$opt{id} || "question".$this->id,
		  prompt=>$prompt,
		  templated=>($opt{id} ? 0 : 1),
		  required=>defined $opt{required} ? $opt{required} : $required,
		  class=>"FormQuestion",
		  value=>exists $opt{value} ? $opt{value} : $this->{metadata}{preset},
		  placeholder=>$msg{$this->{metadata}{placeholder}},
#		  notranslate=>1,      # we do our own translations
		  size=>$opt{size} || $this->{metadata}{size},
	);
	if ($format eq "short text") {
	    $in{type} = "text";
	}
	elsif ($format eq "long text") {
	    $in{type} = "textarea";
	}
	elsif ($format eq "password") {
	    $in{type} = "password";
	}
	elsif ($format eq "file") {
	    $in{type} = "file";
	}
	elsif ($format eq "select") {
	    $in{type} = "select";
	    my $nullop = $msg{"choose one"};
	    $in{nullvalue} = "== $nullop ==";
	    my @answers = $this->allowed_answers;
	    $in{options} = \@answers;
	}
	elsif ($format eq "multiselect") {
	    $in{type} = "select";
	    $in{multiple} = 1;
	    my @answers = $this->allowed_answers;
	    $in{options} = \@answers;
	}
	elsif ($format =~ /^checklist/) {
	    my $ml = new ExSite::ML;
	    $in{type} = "formatted";
	    my @options = $this->allowed_answers();
	    my $out;
	    my @values = split /; /,$opt{value};
	    my $stack = $this->stack_options(@options); #(scalar @options >= $config{form}{stack_checkboxes});
	    my $ncheck = 0;
	    foreach my $opt (@options) {
		$ncheck++;
		my %in2 = ( name=>$in{name}, type=>"checkbox", subinput=>$ncheck, notranslate=>1 );
		my $val = (ref $opt eq "ARRAY") ? $opt->[0] : $opt;
		$in2{value} = $val;
		$val = quotemeta($val);
		$in2{checked} = (@values > 0 && grep(/^$val$/,@values) > 0);
		$in2{label} = (ref $opt eq "ARRAY") ? $opt->[1] : $opt;
		$out .=  $opt{FormBuilder}->inputtag(%in2);
		$out .= $stack ? $ml->br : "&nbsp;&nbsp;";
	    }
	    if ($format =~ /other/) {
		my %in2 = ( 
		    name=>$opt{name}, 
		    type=>"checkbox", 
		    label=>$msg{"Other:"}, 
		    value=>"Other:",
		    notranslate=>1,
		    subinput=>$ncheck+1,
		    );
		$in2{checked} = (@values > 0 && grep(/^Other:$/,@values) > 0);
		$out .= $opt{FormBuilder}->inputtag(%in2);
		my %in3 = ( 
		    name=>$opt{name}, 
		    type=>"text", 
		    notranslate=>1,
		    subinput=>$ncheck+1,
		    );
		for (my $ival = 0; $ival < $#values; $ival++) {
		    if ($values[$ival] eq "Other:") { 
			$in3{value} = $values[$ival+1];
			last;
		    }
		}
		$out .= $opt{FormBuilder}->inputtag(%in3);
		$out .= $stack ? $ml->br : "&nbsp;&nbsp;";
	    }
	    $in{input} = $out;
	    if ($opt{required}) { 
		$in{required} = -1; 
	    }
	}
	elsif ($format eq "radio+other") {
	    $in{type} = "radio";
	    my @options = $this->allowed_answers();
	    my ($value,$other) = split /; /,$opt{value};
	    push @options, [ $msg{"Other:"},
			     $msg{"Other:"}." ".
			     $opt{FormBuilder}->inputtag(
				 type=>"text",
				 name=>$in{name},
				 notranslate=>1,
				 value=>$other,
			     )
	    ];
	    $in{options} = \@options;
	    $in{stack} = $this->stack_options(@options);
	    $in{value} = $value;
	    $in{input} = $opt{FormBuilder}->select_radio(%in);
	    $in{type} = "formatted";
	    if ($opt{required}) { $in{required} = -1; }
	}
	elsif ($format eq "radio") {
	    $in{type} = "radio";
	    my @options = $this->allowed_answers();
	    $in{options} = \@options;
	    $in{stack} = $this->stack_options(@options);
	}
	elsif ($format eq "checkbox") {
	    $in{type} = "checkbox";
	    # optional value sets the return value of the checkbox
	    my @options = $this->allowed_answers();
	    if (scalar @options > 0) { 
		if (ref $options[0] eq "ARRAY") {
		    $in{value} = $options[0][0]; 
#		    $in{label} = $options[0][1];
		}
		else {
		    $in{value} = $options[0]; 
#		    $in{label} = $options[0];
		}
	    }
	    elsif ($config{Forms}{checkbox_default}) {
		$in{value} = $config{Forms}{checkbox_default};
		# no label
	    }
	    # else: use HTML default value="ON"
	    if ($opt{value} && $opt{value} eq $in{value}) {
		$in{checked} = 1;
	    }
	}
	elsif ($format eq "hidden") {
	    $in{type} = "hidden";
	    # use preset to set the value
	}
	# HTML5 input types
	elsif ($format eq "number") {
	    $in{type} = "number";
	    my %meta = $this->get_metadata();
	    $in{min} = $meta{min} if $meta{min};
	    $in{max} = $meta{max} if $meta{max};
	    $in{step} = $meta{step} if $meta{step};
	}
	elsif ($format eq "range") {
	    $in{type} = "range";
	    my %meta = $this->get_metadata();
	    my $ml = &get_obj("ML");
	    if ($meta{min}) {
		$in{min} = $meta{min};
		$in{head} = $ml->span($meta{min},{class=>"range_limit range_min"});
	    }
	    if ($meta{max}) {
		$in{max} = $meta{max};
		$in{tail} = $ml->span($meta{max},{class=>"range_limit range_max"});
	    }
	    $in{step} = $meta{step} if $meta{step};
	}
	elsif ($format eq "time") {
	    $in{type} = "time";
	}
	elsif ($format eq "date") {
	    $in{type} = "date";
	}
	elsif ($format eq "email") {
	    $in{type} = "email";
	}
	elsif ($format eq "url") {
	    $in{type} = "url";
	}
	elsif (! $this->is_question) {
	    my $fmt = $this->format;
	    $in{type} = $fmt eq "label" ? "formatted" : "preformatted";
	    # value is just an HTML blob
	    $in{input} = $this->allowed_values(); ######
	    if ($opt{required}) { $in{required} = -1; }
	}

	if ($format eq "multiselect") {
	    my $ml = new ExSite::ML;
	    $in{tail} = $ml->br.
		$ml->span("Use ctrl-click or shift-click to select multiple items.",{class=>"FormQuestionHelp"});
	}

	my $layout = $this->layout;
	if ($layout) {
	    my $qname = $this->name;
	    $opt{FormBuilder}->question_template($qname,$layout);
	}
=pod
	if ($layout) {
	    # custom layout for this question; reconfigure it as preformatted
	    my $qname = $this->name;
	    if ($layout =~ /\[\[$qname:prompt\]\]/) {
		my $masked;
		if ($layout =~ /\[\[$qname:input\]\]/) {
		    # mask the input tag temporarily
		    $layout =~ s/\[\[$qname:input\]\]/\{\{$qname:input\}\}/;
		    $masked = 1;
		}
		# insert the prompt
		$layout = &substitute($layout,{"$qname:prompt"=>$prompt});
		if ($masked) {
		    # unmask the input tag
		    $layout =~ s/\{\{$qname:input\}\}/\[\[$qname:input\]\]/;
		}
	    }
	    my ($prompt,$tail) = split /\[\[$qname:input\]\]/, $layout, 2;
	    $in{prompt} = $prompt;
	    $in{tail} = $in{tail} ? $tail . $in{tail} : $tail;
	    if (! $in{input}) {
		if ($format eq "radio") {
		    $in{input} = $opt{FormBuilder}->select_radio(%in);
		}
		elsif ($format eq "select") {
		    $in{input} = $opt{FormBuilder}->select(%in);
		}
		elsif ($format eq "long text") {
		    $in{input} = $opt{FormBuilder}->textarea(%in);
		}
		else {
		    $in{input} = $opt{FormBuilder}->inputtag(%in);
		}
	    }
	    $in{type} = "preformatted";
	}
=cut
	return $opt{FormBuilder}->input(%in);
    }
    return undef;
}

sub preview {
    my ($this,%opt) = @_;
    return $this->show(%opt);
}

# A question template specifies the layout of just this one question.
#
# You can specify the exact prommpt and input field placement, eg:
# <p>[[qname:prompt]]<br>[[qname:input]]</p>
#
# The question name is optional (since it can be inferred from this
# question), so you can leave it off, eg:
# <p>[[prompt]]<br>[[input]]</p>
#
# You can also leave off the prompt, in case you need to generate a long 
# or highly formatted version of the question, eg:
# <p>I, [[input]], being of sound mind and body...</p>

#sub template {  # overloads ExSite::Content::template, which is bad
sub layout {
    my $this = shift;
    my $ml = &get_obj("ML");
    my $qname = $this->name;
    my $template = $this->revision;
    if ($template && $template->defined) {
	my $html = $template->get_html();
	if ($html !~ /input\]\]/) {
	    # template only contains question text, no input placement
	    $html .= "[[input]]";
	}
	return $ml->div($html,{class=>"Forms_question [[rowclass]]"});
    }
    # use generic template
    my $fmt = $this->format();
    if ($fmt eq "checkbox") {
	# reverse prompt/input order for checkboxes
	return $config{Forms}{auto_template} ?
	    $ml->div(
		$ml->span("[[input]]",{class=>"Forms_input"})."&nbsp;".
		$ml->span("[[prompt]]",{class=>"Forms_prompt"}),
		{class=>"Forms_question [[rowclass]]"}
	    ) :
	    $ml->p("[[input]]&nbsp;[[prompt]]");
    }
    elsif ($config{Forms}{auto_template}) {
	return $ml->div(
		$ml->span("[[prompt]]",{class=>"Forms_prompt"}).$ml->br.
		$ml->span("[[input]]",{class=>"Forms_input"}),
		{class=>"Forms_question [[rowclass]]"}
	    );
    }
    return undef;  # use FormBuilder default
}

sub layout_old {
    my $this = shift;
    my $qname = $this->name;
    my $template = $this->revision;
    if ($template && $template->defined) {
	my $html = $template->get_html();
	$html =~ s/\[\[prompt\]\]/\[\[$qname:prompt\]\]/;
	$html =~ s/\[\[input\]\]/\[\[$qname:input\]\]/;
	if ($html !~ /\[\[$qname:input\]\]/) {
	    # template only contains question text, no input placement
	    $html .= "[[$qname:input]]";
	}
	return $html;
    }
    # use generic template
    # NB: checkboxes reverse the usual prompt-input convention
    my $ml = &get_obj("ML");
    my $fmt = $this->format();
    #return undef;
    if ($config{Forms}{auto_template}) {
	# use this setting when you have Forms-specific CSS in your design
	return $fmt eq "checkbox" ?
	    $ml->div(
		$ml->span("[[$qname:input]]",{class=>"Forms_input"})."&nbsp;".
		$ml->span("[[$qname:prompt]]",{class=>"Forms_prompt"}),
		{class=>"Forms_question [[rowclass]]"}
	    ) :
#	    undef;
	    $ml->div(
		$ml->div("[[$qname:prompt]]",{class=>"Forms_prompt"}).
		$ml->div("[[$qname:input]]",{class=>"Forms_input"}),
		{class=>"Forms_question [[rowclass]]"}
	    );
    }
    else {
	# otherwise, this will produce reasonable formatting:
	return $fmt eq "checkbox" ?
	    $ml->p("[[$qname:input]]&nbsp;[[$qname:prompt]]") :
#	    undef;
	    $ml->p("[[$qname:prompt]]".$ml->br."[[$qname:input]]");
    }
}

# stack_options: 
# if true, stack multiple-choice options vertically
# else, display horizontally

sub stack_options {
    my ($this,@opt) = @_;
    scalar @opt or @opt = $this->allowed_answers();

    # do we exceed the maximum # of checkboxes for horizontal layout?
    my $nopt = scalar @opt;
    return 1 if ($nopt > $config{form}{stack_checkboxes});

    # do any of the checkbox labels exceed the maximum label size?
    my $nchar;
    foreach my $opt (@opt) {
	my $len = length $opt;
	return 1 if ($len > $config{form}{stack_maxchar_per_button});
	$nchar += length $opt;
    }

    # does the total of all the labels exceed the maximum size?
    return 1 if ($nchar > $config{form}{stack_maxchar_total});

    # is this question explicitly flagged to stack vertically?
    return 1 if ($this->flag("stack"));

    # horizonal layout is recommended
    return 0;
}

sub editmeta_template { 
    my ($this) = @_;
    my $ml = &get_obj("ML");
    my $br = $ml->br;
    return $ml->table(
	$ml->tr($ml->td("Full question, as displayed to the user${br}[[title:input]]",{colspan=>3})).
	$ml->tr($ml->td("Brief form of question, used in reports${br}[[label:input]]",{colspan=>3})).
	$ml->tr($ml->td("Question name used for HTML encoding${br}[[name:input]]",{colspan=>3})).
	$ml->tr($ml->td("Minimum access level to see this question${br}[[access:input]]",{colspan=>3})).
	$ml->tr($ml->td("[[_meta_format:prompt]]${br}[[_meta_format:input]]").$ml->td("Datatype (extra server-side validation)${br}[[_meta_datatype:input]]")).
	$ml->tr($ml->td("Options (select, multiselect, radio, and checklists only)${br}[[_meta_options:input]]",{colspan=>3})).
	$ml->tr($ml->td("Default/preset answer${br}[[_meta_preset:input]]").$ml->td("Placeholder hint${br}[[_meta_placeholder:input]]")).
	$ml->tr($ml->td("Size of field${br}[[_meta_size:input]]").$ml->td("Maximum length of input data${br}[[_meta_maxlen:input]]")).
	$ml->tr($ml->td("For numeric inputs only (number, range):",{colspan=>3})).
	$ml->tr($ml->td("[[_meta_min:prompt]]: [[_meta_min:input]]").$ml->td("[[_meta_max:prompt]]: [[_meta_max:input]]").$ml->td("[[_meta_step:prompt]]: [[_meta_step:input]]")).
	$ml->tr($ml->td("[[_flag_required:input]] User must provide an answer to this question",{colspan=>3})).
	$ml->tr($ml->td("[[_flag_stack:input]] Stack buttons vertically (checklists and radios only)",{colspan=>3})).
	$ml->tr($ml->td("[[_flag_checked:input]] Pre-checked (checkboxes only)",{colspan=>3})),
	{class=>"Forms_question_config"}
	);
}

sub editmeta_fields {
    my $this = shift;
    return ["title","label","name","access","status"];
}

1;
