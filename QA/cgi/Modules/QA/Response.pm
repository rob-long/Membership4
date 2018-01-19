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

package Modules::QA::Response;

use strict;
use ExSite::Config;
use ExSite::Base;
use ExSite::Form;
use ExSite::Misc;
use ExSite::Object;
use ExSite::ObjectList;
use Modules::QA::Answer;
use Modules::QA::Form;

use vars qw(@ISA);
@ISA = qw(ExSite::Object);

sub my_type { return "qa_response"; }

sub name {
    my $this = shift;
    $this->load() if (!defined $this->{data});
    return "Response ".$this->id;
}

sub form {
    my $this = shift;
    $this->load() if (!defined $this->{data});
    return new Modules::QA::Form(id=>$this->getdata("qa_form_id"));
}

sub is_editable {
    my $this = shift;
    if ($this->loaded) {
	my $db = $share{DB};
	return 1 if $db->is_manager;
	my $uid = $db->my_uid;
	return 1 if ($uid && $uid == $this->getdata("uid"));
    }
    return 0;
}

sub get_response_data {
    my $this = shift;
    my %data;
    if ($this->loaded()) {
	my $ans = $this->{answers};
	$ans->reset();
	while (my $answer = $ans->next()) {
	    my $question = $answer->question();
	    $data{$question->qname()} = $answer->value();
	}
    }
    return wantarray ? %data : \%data;
}

sub answer {
    my ($this,$qname) = @_;
    if ($this->loaded()) {
	my $ans = $this->{answers};
	$ans->reset();
	while (my $answer = $ans->next()) {
	    return $answer if ($qname eq $answer->question->qname);
	}
    }
    # no answer - see if the question actually exists
    my $qs = $this->form->questions;
    $qs->reset();
    while (my $question = $qs->next()) {
	if ($question->qname eq $qname) {
	    # looks like we have an unanswered question; return a dummy object
	    my $answer = new Modules::QA::Answer(data=>{
		qa_response_id=>$this->id,
		qa_question_id=>$question->id,
						 });	    
	    return $answer;
	}
    }
    # no such question
    return undef;
}

sub question {
    my ($this,$qname) = @_;
    if ($this->loaded()) {
	my $q = $this->{questions};
	$q->reset();
	while (my $question = $q->next()) {
	    return $question if ($qname eq $question->qname);
	}
    }
    return undef;
}

# show:
# options: admin=>1 to disply admin-only info about the response
# tools: optional links/buttons

sub show {
    my ($this,%opt) = @_;
    if ($this->ok) {
	if ($this->loaded()) {
	    my $name = ucfirst $this->name;
	    if (! $this->{data}) {
		return $this->error($msg{"Sorry, the requested response does not exist."});
	    }
	    elsif (! $this->{answers}) {
		return $this->error(&substitute($msg{"[[response]] has no answers.",{response=>$name}}));
	    }
	    else {
		my $title = $this->form->name;
		$title .= " (".$this->name.")" if ($this->DB->is_manager());
		my $r = new ExSite::ReportBuilder(
		    title=>$title,
		    class=>"Report QA_response",
		    headers=>["#",$msg{Question},$msg{Answer}],
		    );
		my $num = 0;
		while (my $q = $this->{questions}->next()) {
		    if ($opt{version}) {
			$q->set("version",$opt{version});
		    }
		    next if ($q->format =~ /label|preformatted/);  # not really a question
		    next if ($q->flag("show to admins only") && ! $share{DB}->is_manager);
		    $num++;
		    $r->push($num,$q->label(),$q->answer($this->id)->show());
		}
		my $foot;
		if ($opt{admin}) {
		    my $ml = &get_obj("ML");
		    my $br = $ml->br;
		    $foot = $this->getdata("note");
		    $foot =~ s/\n/$br/g;
		    if ($foot) { 
			$foot =~ s/(https?:\/\/[^\s]+)/<a href='$1' target='_blank'>$1<\/a>/;
			$foot .= $br; 
		    }
		}
		$foot .= &substitute($msg{"Response submitted at [[time]]."},{time=>$this->showdata("ctime")});
		$r->foot($foot);
		$r->tools($opt{tools}) if $opt{tools};
		return $r->make();
	    }
	}
    }
    return $this->error($this->{status});
}

sub show_as_plaintext {
    my ($this,%opt) = @_;
    my $out;
    if ($this->ok) {
	if ($this->loaded()) {
	    while (my $q = $this->{questions}->next()) {
		next if ($q->format() =~ /^(hidden|label)$/);
		next if ($q->flag("show to admins only") && ! $share{DB}->is_manager);
		$q->set("version",$this->{version});
		my $question = $q->label();
		my $answer = $q->answer($this->id)->value();
		$out .= "$question: $answer\n";
	    }
	    $out .= "\n";
	    $out .= "Response ID: ".$this->id()."\n";
	    if ($opt{admin}) {
		$out .= $this->getdata("note")."\n";
	    }
	}
    }
    return &html_to_plaintext($out,(nohtml=>1));
}

#=== DB

# load record : can pass an ID or a datahash

sub defined {
    my $this = shift;
    if (! $this->{data} || ! $this->{questions}) { $this->load(@_); }
    return ($this->{data} && $this->{questions});
}

sub get_answers {
    my $this = shift;
    if ($this->exists) {
	my $response_id = $this->id;
	my @answer;
	if ($share{QA_cache}{"response:$response_id"}) {
	    # answers have been preloaded
	    @answer = @{$share{QA_cache}{"response:$response_id"}};
	}
	else {
	    @answer = $this->DB()->fetch_match("qa_answer",{qa_response_id=>$response_id});
	}
	return wantarray ? @answer : \@answer;
    }
    return undef;
}

sub load {
    my ($this,$data) = @_;
    $this->{list} = undef;
    if ($this->{data} || $this->SUPER::load($data)) {
	# load questions
	my $q =  new ExSite::ObjectList(type=>"qa_question");
	$q->load({qa_form_id=>$this->{data}{qa_form_id}});
	$q->sort("sortkey","qa_question_id");
	$this->{questions} = $q;

	# load answers, but first sort them into the question order
	my %qkey = keywise("qa_question_id",scalar $q->getlist());
	my @ans = sort { $qkey{$a->{qa_question_id}}{sortkey} <=> $qkey{$b->{qa_question_id}}{sortkey} } $this->get_answers();
	my $a = new ExSite::ObjectList(type=>"qa_answer");
	$a->push(@ans);
	$this->{answers} = $a;
    }
}

sub make_response {
    my ($this,$response_data,$answer_data) = @_;
    # data is question_id => answer value
    
    if (! $response_data->{note}) {
	# if no note, record the referer in the notes
	my $ref = &html_escape($ENV{HTTP_REFERER});
	$response_data->{note} = "Submitted from $ref";
    }
    $this->{data} = $response_data;
    my $rid = $this->insert();
    if ($rid) {
	foreach my $qid (keys %$answer_data) {
	    next if (! $answer_data->{$qid});   # no answer given
	    my $q = new Modules::QA::Question(id=>$qid);
	    # trim leading/trailing whitespace from answer
	    my $value = $answer_data->{$qid};
	    $value =~ s/\s+$//;
	    $value =~ s/^\s+//;
	    if ($q->format() =~ /^checklist\+other$/) {
		# remove blank other field
		$value =~ s/;$//;
	    }
	    my $a = new Modules::QA::Answer(data=>{
		qa_response_id=>$this->id,
		qa_question_id=>$qid,
		value=>$value
	    });
	    ### FIXME:
	    # validation is done in form, but we should also validate in case
	    # a response is inserted indirectly
	    my $aid = $a->insert();
	    if ($aid) {
		if ($q->format eq "file") {
		    # successfully saved answer, should also install the file
		    my $file = $share{QA}{files}{$this->form->id}{$q->qname};
		    my $df = new ExSite::Diskfile();
		    my $installed_file = $df->install(
			filename => $file->{filename},
			data => $file->{data},
			key=>"ans$aid",
			auth=>1,
			);
		    my $path = $installed_file->location();
		    $a->setdata("value",$path);
		    $a->save();
		}
	    }
	    else {
		$this->warn("Failed to insert answer to question $qid: $answer_data->{$qid}");
	    }
	}
	$this->reload();
    }
    else {
	$this->error("Failed to insert response.");
    }
    return $rid;
}

sub edit_response {
    my ($this,$answer_data) = @_;
    my $stat = $this->run_handler("QA_edit_response",$answer_data);
    return $stat if (defined $stat);
    my $errcnt = &AtError();
    if ($this->loaded) {
	my %old_answer;
	if ($this->{answers}) {
	    while (my $ans = $this->{answers}->next) {
		my $qid = $ans->question->id;
		$old_answer{$qid} = $ans;
	    }
	}
	# change existing answers
#	foreach my $qid (keys %$answer_data) { # might not have all questions
	my $questions = $this->form->questions;
	$questions->reset;
	while (my $question = $questions->next) {
	    my $qid = $question->id;
	    if ($answer_data->{$qid} || $old_answer{$qid}) {
		my $q = new Modules::QA::Question(id=>$qid);
		if ($q->format() =~ /^checklist\+other$/) {
		    # remove blank other field
		    $answer_data->{$qid} =~ s/; ?$//;
		}
		if ($answer_data->{$qid} && ! $old_answer{$qid}) {
		    # new answer added to response
		    my $new_answer = new Modules::QA::Answer();
		    $new_answer->setdata("qa_response_id",$this->id);
		    $new_answer->setdata("qa_question_id",$qid);
		    $new_answer->setdata("value",$answer_data->{$qid});
		    $new_answer->save or $this->warn("Failed to update answer to question $qid: $answer_data->{$qid}");
		}
		elsif ($answer_data->{$qid} ne $old_answer{$qid}->value) {
		    # this answer has changed
		    if ($q->format ne "file" || $answer_data->{$qid}) {
			# (do not delete old file uploads)
			$old_answer{$qid}->setdata("value",$answer_data->{$qid});
			$old_answer{$qid}->save or $this->warn("Failed to update answer to question $qid: $answer_data->{$qid}");
		    }
		}
	    }
	    delete $answer_data->{$qid};
	}
	# add new answers
	foreach my $qid (keys %$answer_data) {
	    next if (! $answer_data->{$qid});   # no answer given
	    # trim leading/trailing whitespace from answer
	    my $value = $answer_data->{$qid};
	    $value =~ s/\s+$//;
	    $value =~ s/^\s+//;
	    my $a = new Modules::QA::Answer(data=>{
		qa_response_id=>$this->id,
		qa_question_id=>$qid,
		value=>$value
	    });
	    my $aid = $a->insert();
	    if (! $aid) {
		$this->warn("Failed to insert answer to question $qid: $answer_data->{$qid}");
	    }
	}

	my $note = $this->getdata("note");
	my $newnote = "Edited by ".$share{DB}->my_name." on ".localtime;
	$this->setdata("note", $note ? $note . "\n$newnote" : $newnote);
	$this->save or $this->warn("Failed to save updated reponse note.");
    }
    else {
	$this->error("Failed to load response.");
    }
    # return our id if no errors (same behaviour as make_response)
    return &AtError($errcnt) ? 0 : $this->id;
}

1;
