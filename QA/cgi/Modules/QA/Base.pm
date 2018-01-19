#!/usr/bin/perl
#-----------------------------------------------------------------------
#
#   Copyright 2001-2009 Exware Solutions, Inc.  http://www.exware.com
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

package Modules::QA::Base;

use strict;
use ExSite::Config;
use ExSite::Base;
use ExSite::Form;
use ExSite::Misc;
use ExSite::Object;

use vars qw(@ISA);
@ISA = qw(ExSite::Object);

sub my_type { return "qa_base"; }

sub name {
    my $this = shift;
    if ($this->loaded()) {
	my $name = $this->{data}{label};
	if ($this->getdata("format") eq "preformatted") {
	    $name =~ s/<.+?>//g;
	}
	return $name;
    }
    return undef;
}

sub is_freeform {
    my $this = shift;
    if ($this->loaded()) {
	my $fmt = $this->getdata("format");
	return $fmt =~ /short text|long text|password/;
    }
    return undef;
}

sub datatype {
    my $this = shift;
    if ($this->loaded()) {
	if ($this->getdata("format") eq "password") {
	    return "password";
	}
	my $val = $this->getdata("value");
	if ($val && $this->is_freeform()) {
	    return $val;
	}
	else {
	    my $fmt = $this->getdata("format");
	    return ($fmt =~ /long text/) ? "text" : "string";
	}
    }
    return undef;
}

sub answer_regexp {
    my $this = shift;
    if ($this->loaded()) {
	my $val = $this->getdata("value");
	if ($this->is_freeform()) {
	    my $re = $this->DB->{map}->regexp($val);
	    return $re ? $re : ".*";
	}
	else {
	    if ($val) {
		$val =~ s/\s*\|\s*/\|/g;
		return $val;
	    }
	    else {
		return ".*";
	    }
	}
    }
    return undef;
}

sub answer_values {
    my $this = shift;
    my $re = $this->answer_regexp();
    return $re =~ /^\.\*$/ ? undef : split(/\|/, $re);
}

sub validate_answer {
    my ($this,$value) = @_;
    # is $value a valid answer to this question?
    if ($this->loaded()) {
	if ($value) {
	    my $re;
	    my $fmt = $this->getdata("format");
	    my $baseval = $this->getdata("value");
	    if ($this->is_freeform()) {
		if ($baseval) {
		    # baseval is a datatype
		    my $msg = $share{DB}->validate_datatype($baseval,$value);
		    $msg = $this->label . ": $msg" if $msg;
		    return $msg;
		}
		$re = ".*";
	    }
	    elsif ($fmt =~ /\+other$/) {
		# other fields can hold any value
		$re = ".*";
	    }
	    elsif ($fmt =~ /multiselect|checklist/) {
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
		return undef;
	    }
	    elsif ($fmt eq "checkbox") {
		my $val = $this->getdata("value");
		if ($val) { 
		    $re = $val;
		}
		elsif ($config{QA}{checkbox_default}) {
		    $re = $config{QA}{checkbox_default};
		}
		else {
		    $re = "ON";
		}
	    }
	    elsif ($baseval) {
		# simple regex validation - strip formatting whitespace
		$baseval =~ s/\s*\|\s*/\|/g;
		# mask any regex-sensitive characters
		$baseval = &safe_regex($baseval);
		# remove ==*== items, which are formatting lines, not valid answers
		$baseval =~ s/==[\s\w]+==|//g;
		$re = $baseval;
	    }
	    else {
		$re = ".*";
	    }

	    if ($value !~ /^$re$/si) { 
		return &substitute($msg{"Invalid input for \"[[label]]\""},
				   {label=>$this->label()});
	    }
	}
    }
    return undef;
}

# label : return the (translated) label of the question

sub label {
    my $this = shift;
    my $label;
    if ($this->loaded()) {
	if ($this->{version}) {
	    $label = $this->{translation}{$this->{version}}{label};
	}
	if (! $label) {
	    $label = $this->getdata("label");
	}
    }
    return $label;
}

# value : return the (translated) value (answers) of the question

sub value {
    my $this = shift;
    my $value;
    if ($this->loaded()) {
	if ($this->{version}) {
	    $value = $this->{translation}{$this->{version}}{value};
	}
	if (! $value) {
	    $value = $this->getdata("value");
	}
    }
    return $value;
}

# options : return an array of options (in translation, if required)

sub options {
    my $this = shift;
    my @options = split /\s*\|\s*/, $this->getdata("value");
    if ($this->{version} && $this->{translation}{$this->{version}}{value}) {
	my @troptions = split /\s*\|\s*/, $this->{translation}{$this->{version}}{value};
	my @combo_opt;
	while (my $e_opt = shift @options) {
	    my $tr_opt = shift @troptions;
	    if (! $e_opt || $tr_opt) {
		$this->warn("Base question ".$this->id.": unmatched options in $this->{version} version");
	    }
	    elsif (! $tr_opt) {
		# option does not exist in translation; skip it
		next;
	    }
	    push @combo_opt, [ $e_opt, $tr_opt ];
	}
	return \@combo_opt;
    }
    else {
	return \@options;
    }
}

sub translation {
    my ($this,$version) = @_;
    $this->load_translations();
    return $this->{translation}{$version};
}

#=== DISPLAY

sub show {
    my ($this,%opt) = @_;
    my $stat = $this->run_handler("QA_Base_show",\%opt);
    return $stat if (defined $stat);
    if ($opt{version}) { $this->set("version",$opt{version}); }
    if ($this->ok) {
	if ($this->loaded()) {

	    ### FIXME: optional question numbers
	    ### FIXME: grid view

	    if (! $opt{FormBuilder}) {
		# probably an admin preview
		$opt{FormBuilder} = new ExSite::FormBuilder();
	    }
	    my $qid = $opt{id} || &randtext(8,'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789');
	    
	    my $name = 
		$opt{name} ||              # explicit name given to us
		$this->getdata("name") ||  # use our own name
		$opt{id} ||                # no name; use our ID
		"qa_$qid";                 # no ID; make something up
	    (tied %msg)->nohighlight();
	    my %in = (name=>$name,
		      id=>$opt{id} || "qa_$qid",
		      prompt=>$this->label(),
		      templated=>$opt{id} ? 0 : 1,
		      required=>$opt{required},
		      class=>"qaQuestion",
		      value=>$opt{value},
		      placeholder=>$msg{$opt{placeholder}},
		      notranslate=>1,      # we do our own translations
		      size=>$opt{size}||$this->getdata("size"));
	    (tied %msg)->restore();

	    my $format = $this->getdata("format");
	    
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
		$in{options} = $this->options();
	    }
	    elsif ($format eq "multiselect") {
		$in{type} = "select";
		$in{multiple} = 1;
		$in{options} = $this->options();
	    }
	    elsif ($format =~ /^checklist/) {
		my $ml = new ExSite::ML;
		$in{type} = "formatted";
		my $options = $this->options();
		my $out;
		my @values = split /; /,$opt{value};
		my $stack = (scalar @$options >= $config{form}{stack_checkboxes});
		my $ncheck = 0;
		foreach my $opt (@$options) {
		    $ncheck++;
		    my %in2 = ( name=>$name, type=>"checkbox", subinput=>$ncheck, notranslate=>1 );
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
				name=>$name, 
				type=>"checkbox", 
				label=>$msg{"Other:"}, 
				value=>"Other:",
			        notranslate=>1,
			        subinput=>$ncheck+1,
				);
		    $in2{checked} = (@values > 0 && grep(/^Other:$/,@values) > 0);
		    $out .= $opt{FormBuilder}->inputtag(%in2);
		    my %in3 = ( 
				name=>$name, 
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
		if ($opt{required}) { $in{required} = -1; }
	    }
	    elsif ($format eq "radio+other") {
		$in{type} = "radio";
		my $options = $this->options();
		my ($value,$other) = split /; /,$opt{value};
		push @$options, [ $msg{"Other:"},
				  $msg{"Other:"}." ".
				  $opt{FormBuilder}->inputtag(
							      type=>"text",
							      name=>$in{name},
				                              notranslate=>1,
							      value=>$other,
							      )
				  ];
		$in{options} = $options;
		$in{value} = $value;
		$in{input} = $opt{FormBuilder}->select_radio(%in);
		$in{type} = "formatted";
		if ($opt{required}) { $in{required} = -1; }
	    }
	    elsif ($format eq "radio") {
		$in{type} = "radio";
		$in{options} = $this->options();
	    }
	    elsif ($format eq "checkbox") {
		$in{type} = "checkbox";
		# optional value sets the return value of the checkbox
		my $options = $this->options();
		if (scalar @$options > 0) { 
		    if (ref $options->[0] eq "ARRAY") {
			$in{value} = $options->[0][0]; 
			$in{label} = $options->[0][1];
		    }
		    else {
			$in{value} = $options->[0]; 
			$in{label} = $options->[0];
		    }
		}
		elsif ($config{QA}{checkbox_default}) {
		    $in{value} = $config{QA}{checkbox_default};
		    # no label
		}
		# else: use HTML default value="ON"
		if ($opt{value} && $opt{value} eq $in{value}) {
		    $in{checked} = 1;
		}
	    }
	    elsif ($format eq "hidden") {
		$in{type} = "hidden";
		# optional value sets the return value of the hidden field
		if (! $in{value}) {
		    $in{value} = $this->getdata("value");
		}
	    }
	    elsif ($format eq "label") {
		$in{type} = "formatted";
		# value is just an HTML blob
		$in{input} = $this->getdata("value");
		if ($opt{required}) { $in{required} = -1; }
	    }
	    elsif ($format eq "preformatted") {
		$in{type} = "preformatted";
		# value is just an HTML blob
		$in{input} = $this->getdata("value");
		if ($opt{required}) { $in{required} = -1; }
	    }

	    if ($format eq "multiselect") {
		my $ml = new ExSite::ML;
		$in{tail} = $ml->br.
		    $ml->span("Use ctrl-click or shift-click to select multiple items.",{class=>"qaQuestionHelp"});
	    }
	    return $opt{FormBuilder}->input(%in);
	}
	else {
	    my $name = ucfirst $this->name;
	    return $this->error($msg{"Question does not exist."});
	}
    }
    return $this->error($this->{status});
}

#=== DB

sub validate {
    my $this = shift;
    return ($msg{"no data"}) if (ref $this->{data} ne "HASH");
    my $action = $this->action;
    if ($action eq "update") {
	return $this->DB->validate_record_update($this->{type},$this->{data});
    }
    else {
	return $this->DB->validate_record_insert($this->{type},$this->{data});
    }
}

# load record : can pass an ID or a datahash

sub loaded {
    my $this = shift;
    if (! $this->{data} || ! $this->{translation}) { $this->load(@_); }
    return ($this->{data} && $this->{translation});
}

sub load {
    my ($this,$data) = @_;
    if ($this->SUPER::load()) {
	if ($this->get("version")) {
	    $this->load_translations();
	}
	else {
	    # don't bother loading translations if no special version req'd
	    $this->{translation} = {};
	}
    }
}

sub load_translations {
    my ($this) = @_;
    if (scalar keys %{$this->{translation}} == 0) {
	if ($this->ok) {
	    my @tq = $this->DB->fetch_child("qa_translation","qa_base",$this->id);
	    $this->{translation} = &keywise("version",\@tq);
	}
    }
}

sub copy {
    my $this = shift;
    if ($this->SUPER::copy()) {
	# also copy versions

    }
}

sub insert {
    my $this = shift;
    my $data = scalar @_ > 0 ? {@_} : $this->{data};
    my $null = "NULL";
    $data->{ctime} = \$null;
    return $this->SUPER::insert(%$data);
}

1;


