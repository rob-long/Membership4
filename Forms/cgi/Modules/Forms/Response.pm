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

package Modules::Forms::Response;

use strict;
use ExSite::Config;
use ExSite::Base;
use ExSite::Form;
use ExSite::Misc;
use ExSite::Content;
use ExSite::Object;
use ExSite::ObjectList;
use Modules::Forms::Form;
use Modules::Forms::Answer;

use vars qw(@ISA);
@ISA = qw(ExSite::Object);

sub my_type { return "response"; }

sub name {
    my $this = shift;
    $this->load() if (!defined $this->{data});
    return "Response ".$this->id;
}

sub form {
    my $this = shift;
    if (! $this->{form}) {
	$this->{form} = new Modules::Forms::Form();
	if ($this->exists) {
	    $this->{form}->setup(id=>$this->getdata("form_id"));
	}
    }
    return $this->{form};
}

sub is_editable {
    my $this = shift;
    if ($this->loaded) {
	my $db = $share{DB};
	return 1 if $db->is_executive;  ######### ?
	my $uid = $db->my_uid;
	return 1 if ($uid && $uid == $this->getdata("uid"));
    }
    return 0;
}

sub get_response_data {
    my $this = shift;
    my %data;
    if ($this->loaded) {
	my $ans = $this->{answers};
	$ans->reset();
	while (my $answer = $ans->next()) {
	    my $question = $answer->question();
	    $data{$question->name} = $answer->value();
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
	    return $answer if ($qname eq $answer->question->name);
	}
    }
    # no answer - see if the question actually exists
    my $qs = $this->form->questions;
    $qs->reset();
    while (my $question = $qs->next()) {
	if ($question->name eq $qname) {
	    # looks like we have an unanswered question; return a dummy object
	    my $answer = new Modules::Forms::Answer(data=>{
		response_id=>$this->id,
		question_id=>$question->id,
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
	    return $question if ($qname eq $question->name);
	}
    }
    return undef;
}

# show:
# options: admin=>1 to disply admin-only info about the response
# tools: optional links/buttons

sub show {
    my ($this,%opt) = @_;
    if ($this->loaded()) {
	my $name = ucfirst $this->name;
	if (! $this->{data}) {
	    return $this->error($msg{"Sorry, the requested response does not exist."});
	}
	elsif (! $this->{answers}) {
	    return $this->error(&substitute($msg{"[[response]] has no answers.",{response=>$name}}));
	}
	else {
	    my $r = new ExSite::ReportBuilder(
		title=>$this->DB->is_executive ? $this->form->title : "Response",
		class=>"Report Forms_response",
		headers=>["#",$msg{Question},$msg{Answer}],
		);
	    my $num = 0;
	    while (my $q = $this->{questions}->next()) {
##########
#		if ($opt{version}) {
#		    $q->set("version",$opt{version});
#		}
		next if ($q->format =~ /label|preformatted/);  # not really a question
		next if ($q->access > $share{DB}->level);
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
    return $this->error($this->{status});
}

sub show_as_plaintext {
    my ($this,%opt) = @_;
    my $out;
    if ($this->loaded()) {
	while (my $q = $this->{questions}->next()) {
	    next if ($q->format() =~ /^(hidden|label)$/);
	    next if ($q->access > $share{DB}->level);
####	    $q->set("version",$this->{version});
	    my $question = $q->label();
	    my $answer = $q->answer($this->id)->value();
	    next if (! $answer && $opt{skip_blank_answers});
	    if ($answer =~ /<\w/) {
		# got some funky embedded markup in our answers :-/
		$answer = &make_plaintext($answer,1);
	    }
	    $out .= ($question=~/:\s*?/) ? "$question $answer\n" : "$question: $answer\n";
	}
	$out .= "\n";
	my $response_id = $opt{id} || "Response ID";
	$out .= $response_id.": ".$this->id()."\n";
	if ($opt{admin}) {
	    $out .= $this->getdata("note")."\n";
	}
    }
    return $out;
}

#=== DB

# load record : can pass an ID or a datahash

#sub defined {
#    my $this = shift;
#    if (! $this->{data} || ! $this->{questions}) { $this->load(@_); }
#    return ($this->{data} && $this->{questions});
#}

sub get_answers {
    my $this = shift;
    if ($this->exists) {
	my $response_id = $this->id;
	my @answer;
	if ($share{Forms_cache}{"response:$response_id"}) {
	    # answers have been preloaded
	    @answer = @{$share{Forms_cache}{"response:$response_id"}};
	}
	else {
	    @answer = $this->DB()->fetch_match("answer",{response_id=>$response_id});
	}
	return wantarray ? @answer : \@answer;
    }
    return undef;
}

sub load {
    my ($this,$data) = @_;
    $this->{list} = undef;
    if ($this->{data} || $this->SUPER::load($data)) {
	# load questions (copy from form)
	my $f = $this->form();
	$f->load();
	my $q = $f->get("list"); # question list
	$this->{questions} = $q;

	# load answers, but first sort them into the question order
	my %qkey = keywise("question_id",scalar $q->getlist());
	my @ans = sort { $qkey{$a->{question_id}}{sortkey} <=> $qkey{$b->{question_id}}{sortkey} } $this->get_answers();
	my $a = new ExSite::ObjectList(type=>"answer");
	$a->push(@ans);
	$this->{answers} = $a;
    }
}

sub loaded {
    my $this = shift;
    if (! $this->{data} || 
	! $this->{questions} || 
	! $this->{answers}) { $this->load(@_); }
    return ($this->{data} && $this->{questions} && $this->{answers});
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
	    my $q = new Modules::Forms::Question(id=>$qid);
	    # trim leading/trailing whitespace from answer
	    my $value = $answer_data->{$qid};
	    $value =~ s/\s+$//;
	    $value =~ s/^\s+//;
	    if ($q->format() =~ /^checklist\+other$/) {
		# remove blank other field
		$value =~ s/;$//;
	    }
	    my $a = new Modules::Forms::Answer(data=>{
		response_id=>$this->id,
		question_id=>$qid,
		value=>$value
	    });
	    ### FIXME:
	    # validation is done in form, but we should also validate in case
	    # a response is inserted indirectly
	    my $aid = $a->insert();
	    if ($aid) {
		if ($q->format eq "file") {
		    # successfully saved answer, should also install the file
		    my $file = $share{Forms}{files}{$this->form->id}{$q->name};
		    my $df = new ExSite::Diskfile();
		    my $installed_file = $df->install(
			filename => $file->{filename},
			contents => $file->{data},
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
    my $stat = $this->run_handler("Forms_edit_response",$answer_data);
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
	my $questions = $this->form->questions;
	$questions->reset;
	while (my $question = $questions->next) {
	    my $qid = $question->id;
	    if ($answer_data->{$qid} || $old_answer{$qid}) {
		my $q = new Modules::Forms::Question(id=>$qid);
		if ($q->format() =~ /^checklist\+other$/) {
		    # remove blank other field
		    $answer_data->{$qid} =~ s/; ?$//;
		}
		if ($answer_data->{$qid} && ! $old_answer{$qid}) {
		    # new answer added to response
		    my $new_answer = new Modules::Forms::Answer();
		    $new_answer->setdata("response_id",$this->id);
		    $new_answer->setdata("question_id",$qid);
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
	    my $a = new Modules::Forms::Answer(data=>{
		response_id=>$this->id,
		question_id=>$qid,
		value=>$value
	    });
	    my $aid = $a->insert();
	    if (! $aid) {
		$this->warn("Failed to insert answer to question $qid: $answer_data->{$qid}");
	    }
	}

	my $note = $this->getdata("note");
	my $newnote = "Edited by ".$share{DB}->my_name." on ".localtime;
	$this->setdata("note", $note ? $note."\n$newnote" : $newnote);
	$this->save or $this->warn("Failed to save updated reponse note.");
    }
    else {
	$this->error("Failed to load response.");
    }
    # return our id if no errors (same behaviour as make_response)
    return &AtError($errcnt) ? 0 : $this->id;
}

1;
