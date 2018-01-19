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

package Modules::Quiz::Response;

use strict;
use ExSite::Config;
use ExSite::Base;
use ExSite::Form;
use ExSite::Misc;
use ExSite::Content;
use ExSite::Object;
use ExSite::ObjectList;
use Modules::Quiz::Quiz;
use Modules::Quiz::Answer;

use vars qw(@ISA @rstatus %rstatus);
@ISA = qw(Modules::Forms::Response);
%rstatus = ( pass=>3, fail=>7 );
@rstatus = qw(completed archived queued passed submitted draft expired failed spam);

sub form {
    my $this = shift;
    if (! $this->{form}) {
	$this->{form} = new Modules::Quiz::Quiz();
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
	    my $ml = &get_obj("ML");
	    my %mark = $this->mark();

	    my $r = new ExSite::ReportBuilder(
		title=>$this->DB->is_executive ? $this->form->title : "Results",
		class=>"Report Forms_response",
		headers=>["#",$msg{Question},$msg{'Your answer'},$msg{Correct},$msg{Marks}],
		);
	    my $num = 0;
	    while (my $q = $this->{questions}->next()) {
		my $name = $q->name();
		my $answer = $q->correct_answer();
		if ($answer) {
		    my $score = $q->score();
		    next if ($q->format =~ /label|preformatted/);  # not really a question
		    next if ($q->access > $share{DB}->level);
		    $num++;
		    my @data = ($num,$q->label(),$q->answer($this->id)->show());
		    if ($mark{$name}) {
			push @data, $ml->img(undef,{src=>"$config{server}{HTMLpath}/_ExSite/images/icons/approve.png"}), $ml->div($mark{$name},{class=>"num"});
		    }
		    else {
			push @data, $ml->img(undef,{src=>"$config{server}{HTMLpath}/_ExSite/images/icons/reject.png"}), $ml->div($mark{$name}||0,{class=>"num"});
		    }
		    $r->push(@data);
		}
	    }
	    
#	    my $br = $ml->br;
#	    $foot = $this->getdata("note");
#	    $foot =~ s/\n/$br/g;
#	    if ($foot) { 
#		$foot =~ s/(https?:\/\/[^\s]+)/<a href='$1' target='_blank'>$1<\/a>/;
#		$foot .= $br; 
#	    }
#	    $foot .= &substitute($msg{"Response submitted at [[time]]."},{time=>$this->showdata("ctime")});

	    $r->foot($mark{_summary});
#	    $r->foot($foot);
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

sub mark {
    my $this = shift;
    my %marks;
    my $ml = &get_obj("ML");
    my $br = $ml->br;
    if ($this->loaded) {
	#my %key = $this->form->answer_key();
	my %rdata = $this->get_response_data();
	while (my $q = $this->{questions}->next()) {
	    my $qname = $q->name;
	    if ($q->is_markable) {
		# markable question format
		my $score = $q->score();
		my $answer = $q->correct_answer();
		if ($answer) {
		    $marks{_max} += $score;
		    if ($rdata{$qname} eq $answer) {
			$marks{$qname} = $score;
			$marks{_total} += $score;
		    }
		    else {
			$marks{$qname} = 0;
		    }
		}
	    }
	}
	if ($marks{_max}) {
	    $marks{_total} or $marks{_total} = 0;
	    $marks{_pct} = int(($marks{_total} / $marks{_max})*100);
	    $marks{_summary} = &substitute($msg{"You scored [[marks]] ([[percent]]\%)."},{marks=>$marks{_total}."/".$marks{_max},percent=>$marks{_pct}});
	    my $passing_score = $this->form->emeta("passing_score");
	    if ($passing_score) {
		$marks{_summary} .= $br.&substitute($msg{"[[percent]]\% is needed to pass."},{percent=>$passing_score});
		$marks{_pass} = ($marks{_pct} >= $passing_score);
		my $status = $this->getdata("status");
		if ($marks{_pass}) {
		    $marks{_summary} .= " ".$msg{"Well done!"};
		    if ($rstatus[$status] ne "pass") {
			$this->setdata("status",$rstatus{pass});
			$this->force_save();
		    }
		}
		else {
		    if ($rstatus[$status] ne "fail") {
			$this->setdata("status",$rstatus{fail});
			$this->force_save();
		    }
		}
	    }
	}
	else {
	    $marks{_summary} = $msg{"There were no gradable questions on this quiz."};
	}
	my $rstatus = $rstatus[$this->getdata("status")];
	$marks{_summary} .= $br."Status: ".$ml->span($rstatus,{class=>($rstatus eq "passed" ? "tone-good" : "tone-bad")});
    }
    return wantarray ? %marks : \%marks;
}

#=== DB

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
		my $q = new Modules::Quiz::Question(id=>$qid);
		if ($q->format() =~ /^checklist\+other$/) {
		    # remove blank other field
		    $answer_data->{$qid} =~ s/; ?$//;
		}
		if ($answer_data->{$qid} && ! $old_answer{$qid}) {
		    # new answer added to response
		    my $new_answer = new Modules::Quiz::Answer();
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
	    my $a = new Modules::Quiz::Answer(data=>{
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
