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

### TODO:
###
### add a "key" flag, use for reporting purposes


package Modules::QA::Question;

use strict;
use ExSite::Config;
use ExSite::Base;
use ExSite::Form;
use ExSite::Misc;
use ExSite::Object;
use Modules::QA::Base;

use vars qw(@ISA);
@ISA = qw(ExSite::Object);

sub my_type { return "qa_question"; }

# name : human-friendly handle for the question

sub name {
    my $this = shift;
    return $this->loaded ? $this->{base}->name() : undef;
}

sub base {
    my $this = shift;
    return $this->{base};
}

sub form {
    my $this = shift;
    if (! $this->{form}) {
	$this->{form} = new Modules::QA::Form(id=>$this->getdata("qa_form_id"));
    }
    return $this->{form};
}

sub response {
    my $this = shift;
    if (! $this->{response}) {
	$this->{response} = new Modules::QA::Response(id=>$this->getdata("qa_response_id"));
    }
    return $this->{response};
}

# qname : computer-friendly handle for the question (used in forms)

sub qname {
    my $this = shift;
    my $name;
    if ($this->loaded()) {
	$name = 
	    $this->getdata("name") ||          # explicit name
	    $this->{base}->getdata("name") ||  # base has a default name
	    "qa".$this->id;                    # make up a name
    }
    return $name;
}

sub label {
    my $this = shift;
    return $this->loaded() ? $this->{base}->label() : undef;
}

sub format {
    my $this = shift;
    return $this->loaded() ? $this->{base}->getdata("format") : undef;
}

sub datatype {
    my $this = shift;
    return $this->loaded() ? $this->{base}->datatype() : undef;
}

sub is_required {
    my $this = shift;
    $this->getdata("flags") =~ /required/;
}

sub is_freeform {
    my $this = shift;
    return $this->loaded() ? $this->{base}->is_freeform() : undef;
}

sub is_question {
    my $this = shift;
    return ($this->format !~ /label|preformatted/);
}

sub answer_regexp {
    my $this = shift;
    return $this->loaded() ? $this->{base}->answer_regexp() : undef;
}

sub answer_values {
    my $this = shift;
    return $this->loaded() ? $this->{base}->answer_values() : undef;
}

sub flag {
    my ($this,$flag) = @_;
    my $flags = $this->getdata("flags");
    if ($flag) {
	return ($flags =~ /$flag/);
    }
    else {
	return $flags;
    }
}

sub answer {
    my ($this,$response_id) = @_;
    my $answer;
    my $qid = $this->id;
    if ($share{QA_cache}{"response:$response_id"}) {
	# answers have been preloaded
	foreach my $a (@{$share{QA_cache}{"response:$response_id"}}) {
	    if ($a->{qa_question_id} == $qid) {
		$answer = $a;
	    }
	}
    }
    else {
	my @a = $this->DB()->fetch_match("qa_answer",{qa_question_id=>$qid,
						      qa_response_id=>$response_id});
	$answer = $a[-1];
    }
    return $answer ? new Modules::QA::Answer(data=>$answer) : new Modules::QA::Answer();
}

sub validate_answer {
    my ($this,$value) = @_;
    # is $value a valid answer to this question?
    if ($this->loaded()) {
	if (length $value) {
	    return $this->{base}->validate_answer($value);
	}
	elsif ($this->is_required()) {
	    return &substitute($msg{"\"[[label]]\" is required."},{label=>$this->label()});
	}
    }
    return undef;
}

sub set_version {
    my ($this,$version) = @_;
    if ($this->defined()) {
	$this->{base}->set("version",$version);
	$this->{base}->load_translations();
    }
    $this->set("version",$version);
}

#=== DISPLAY

sub show {
    my ($this,%opt) = @_;
    my $stat = $this->run_handler("QA_Question_show",\%opt);
    return $stat if (defined $stat);
    if ($this->ok) {
	if ($opt{version}) { $this->set("version",$opt{version}); }
	if ($this->loaded()) {
	    if ($this->{base}->exists()) {
		my $flags = $this->getdata("flags");
		if ($flags =~ /show to admins only/ && ! $share{DB}->is_manager) {
		    # do not display this field to regular users
		    return undef;
		}
		if ($flags =~ /required/) {
		    # adds JS to validate that we have data in this field
		    $opt{required} = 1;
		}
		my $name = $this->getdata("name");
		my $preset = $this->getdata("value");
		if (! $opt{name} && $name) {
		    $opt{name} = $opt{id} = $name;
		}
		if (! $opt{value} && $preset) {
		    if ($flags =~ /placeholder/) {
			$opt{placeholder} = $preset;
		    }
		    else {
			$opt{value} = $preset;
		    }
		}
		return $this->{base}->show(%opt);
	    }
	    else {
		return $this->error($msg{"Question is undefined."});
	    }
	}
	else {
	    return $this->error($msg{"Question does not exist."});
	}
    }
    return $this->error($this->{status});
}

# load record : can pass an ID or a datahash

sub loaded {
    my $this = shift;
    if (! $this->{data} || ! $this->{base}) { $this->load(@_); }
    return ($this->{data} && $this->{base});
}

sub load {
    my ($this,$data) = @_;
    if ($this->{data} || $this->SUPER::load()) {
	# got the question; now load the base (ie. question content)
	$this->{base} = new Modules::QA::Base(id=>$this->{data}{qa_base_id});
	if ($this->{version}) {
	    $this->{base}->set("version",$this->{version});
	}
	$this->{base}->load();
    }
}

sub copy {
    my ($this,%data) = @_;
    # can't copy questions within a form
    if (! $data{qa_form_id}) {
	$this->error("cannot copy a question to the same form");
	return undef;
    }	
    return $this->SUPER::copy(%data);
}

#=== Answers...

1;


