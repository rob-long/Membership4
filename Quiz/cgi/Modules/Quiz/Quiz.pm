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
# A quiz is a form with some special qualities:
# - a quiz has an answer key - a set of correct answers
# - responses can be graded by compaing with the answer key
# - questions have a score - the value of a correct answer
# - the quiz has a total score - the total value of all answers
# - the response has a score - the total value of correct answers
# - the quiz has a pass value - the response score to pass the quiz
#----------------------------------------------------------------------------

package Modules::Quiz::Quiz;

use strict;
use ExSite::Config;
use ExSite::Base;
use ExSite::Form;
use ExSite::Captcha;
use ExSite::Misc;
use ExSite::Mail;
use ExSite::ObjectList;
use ExSite::Content;
use Modules::Quiz::Question;
use Modules::Quiz::Response;

use vars qw(@ISA);
@ISA = qw(Modules::Forms::Form);

sub load {
    my ($this,$data) = @_;
    $this->{list} = undef;
    if ($this->SUPER::load($data)) {
	# also load the questions
	$this->{list} = $this->get_contents_as_list("quiz_question");
	$this->{list}->set("class","Modules::Quiz::Question");
    }
}

# show: either display or process the form

sub show {
    my ($this,%opt) = @_;
    if ($this->loaded) {
	if (! $this->{list}) {
	    return $this->error(&substitute($msg{"[[form]] has no questions."},{form=>$this->title}));
	}

	my $out;
	my $input = new ExSite::Input;
	my $post = $input->post;
	if (keys %$post > 0 &&               # post data received
	    exists $post->{"_formkey"}) {    # targeted at a form
#	    exists $post->{"_formkey"} &&    # targeted at a form
#	    ! $this->{regen}{$this->id}) {   # not already processed
	    return $this->post();
	}
	else {
	    return $this->show_form(%opt);
	}
    }
    return $this->error($this->{status});
}

# quizzes have simplified layout

sub set_layout {
    my ($this,%opt) = @_;
    $this->{FormBuilder}->template(
	"<div class='Quiz'>",
	"<div class='QuizQuestion'><div class='QuizQuestionPrompt'>[[prompt]]</div><div class='QuizQuestionInput'>[[input]]</div></div>",
	"</div>"
	);
    return;
}

sub post {
    my ($this) = @_;
    my $out;
    my $in = new ExSite::Input;
    my $data = $in->post;
    if (! exists $data->{"_formkey"}) {
	# post not for us
	return undef;
    }
    elsif (scalar(keys %$data) == 0) {
	# nothing posted
	return $this->warn(&substitute($msg{"Nothing posted to form \"[[form]]\"."},{form=>$this->title}));
    }
    elsif ($this->loaded) {
	if ($this->allow_post) {
	    # user is allowed to post here

	    # but are they a robot?
	    my $robot_msg = $this->robot_check($data);
	    return $robot_msg if $robot_msg;

	    # formkey is id;confirmation_flag;reponse
	    my $c = new ExSite::Crypt();
	    my @key  = split /;/,$c->decrypt($data->{"_formkey"});
	    if (shift @key != $this->id) {
		# form mismatch
		$this->error($msg{"Form mismatch; submission not accepted."});
		return undef; # silent return, in case post is direct at another form on same page
	    }
	    $this->{confirmed} = shift @key;
	    $this->{do_form_response} = shift @key;

	    # check validity of answers

	    ### if %err was field => validation error, we could use those error
	    ### messages as "tails" on those questions when regenerating the form

	    my @err = $this->validate_form($data);
	    my $ml = new ExSite::ML;
	    if (@err > 0) {
		$out = $ml->div($this->error(@err),{class=>"formErrors"});
		# flag this form as being regenerated, or else it will attempt
		# to re-process the captcha
#		$this->{regen}{$this->id} = 1;
		$out .= $this->show_form(data=>$data);
	    }
	    elsif ($this->{confirmed}) {
		my $r = new Modules::Quiz::Response();
		my $uid = $share{DB}->my_uid || 0;
		my $rid;
		if ($this->{do_form_response}) {
		    $r->setup(id=>$this->{do_form_response});
		    $rid = $r->edit_response(
			$this->{response_data}
			);
		}
		else {
		    $rid = $r->make_response(
			{ 
			    form_id => $this->id ,
			    uid => $uid,
			    status => 4, # submitted
			    language => $share{Page} ?
				$share{Page}->getdata("language") : undef,
			},
			$this->{response_data}
			);
		}
		if ($rid) {
		    # response was logged successfully
		    if (! $r->errorcheck()) {
			# No errors were logged in post-processing...
			my %mark = $r->mark();
			my $notes = $r->getdata("notes");
			if ($notes) {
			    $r->setdata("notes",$notes."\n".$mark{_summary});
			}
			else {
			    $r->setdata("notes",$mark{_summary});
			}
			my $message = $this->run_handler("Quiz_reply",$r,\%mark);
			if (! defined $message) {
			    $out .= $this->assessment($r,\%mark);
			}
			$out .= $message;
		    }
		    $this->{response} = $r;
		    if ($r->defined() && ! $this->{do_form_response}) {
			# email notification for new responses only
			$out .= $this->notify($r);
			# receipt callback for custom post-processing
			$out .= $this->run_handler("Quiz_receipt",$r);
		    }
		}
		else {
		    $out .= $r->show_diagnostics("error","html");
		}
	    }
	    else {
		$out .= $this->confirmation_page($data);
	    }
	}
	else {
	    # post not allowed
	    $out = $this->error(&substitute($msg{"Form \"[[form]]\": you do not have sufficient permissions to submit this form."},{form=>$this->title}));
	}
    }
    else {
	$out = $this->error($msg{"No form to post to!"});
    }
    return $out;
}

sub assessment {
    my ($this,$response,$marks) = @_;
    my $reply_content;
    my %data;
    $data{_response} = $response->show();
    my $questions = $this->questions();
    $questions->reset();
    while (my $q = $questions->next) {
	if (! $q->emeta("score")) {
	    $data{$q->{qname}} = $response->answer($q->{qname});
	}
    }
    if (exists $marks->{_pass}) {
	$data{_result} = $marks->{_pass} ? "pass" : "fail";
	$data{_mark} = $marks->{_total}."/".$marks->{_max};
	$data{_pct} = $marks->{_pct};
	$reply_content = "_".$data{_result};
    }
    else {
	$data{_result} = "n/a";
	$data{_mark} = "n/a";
	$data{_percent} = "n/a";
	$data{_summary} = "No marks available";
    }

    my $message;
    if ($reply_content) {
	my $reply = $this->my_content($reply_content);
	if ($reply) {
	    $message = $reply->get_html();
	}
	else {
	    $reply = $this->my_content("_reply");
	    if ($reply) {
		$message = $reply->get_html();
	    }
	}
    }
    if (! $message) {
	$message = "[[_response]]";
    }
    return &substitute($message,\%data);
}

sub answer_key {
    my $this = shift;
    my %akey;
    my $questions = $this->questions();
    while (my $q = $questions->next()) {
	$akey{$q->name} = $q->correct_answer();
    }
    return wantarray ? %akey : \%akey;
}

sub notify {
    my $this = shift;
    my $response = shift;
    my $stat = $this->run_handler("Forms_notify",$response);
    return $stat if ($stat);

    my $notify = $this->meta->get("notify");
    return if (! $notify);

    my %opt;
    my $formtitle = $this->title;
    my $subject = "Response received from '$formtitle'";
    my $site = $this->my_section;
    my $site_name = $site->label;
    my $message = $subject . "\non $site_name website:\n\n";
    my $from = &preference("Forms.notification_from") ||
	$share{DB}->owner_email($site->get());
    
    my $ml = &get_obj("ML");
    $message = $ml->p($message);
    $message .= $response->show(admin=>1);

    my %mailopt = (
	to=>$notify,
	from=>$from,
	subject=>$subject,
	body=>$message
	);

    # attachments
    if (exists $share{Forms}{files}{$this->id}) {
	my @attach = values %{$share{Forms}{files}{$this->id}};
	$mailopt{attach} = \@attach;
    }

    &ExSite::Mail::send(%mailopt);
    return;
}

# add_question
# same options as Modules::Forms::Form::add_question, plus
# answer : the correct answer
# score : the number of marks for getting this answer right

sub add_question {
    my ($this,%opt) = @_;
    my $out;
    my $ml = &get_obj("ML");
    my $ui = &get_obj("UI");

    my $q = $this->setup_question(content_type=>"quiz_question",%opt);
    if ($q->defined) {
	# quiz_question metadata
	if ($opt{answer}) {
	    $q->set_metadata("answer",$opt{answer});
	}
	if ($opt{score}) {
	    $q->set_metadata("score",$opt{score});
	}
	$q->save();
	$out .= $ui->SuccessBox(size=>"m",title=>"Question Added",pane=>"Click preview to view the form, or add another question, below.");
    }
    else {
	$out .= $ui->ErrorBox(size=>"m",title=>"Error",pane=>&show_diagnostics());
    }
    return $out;
}

# get_all_answers : retrieves all answer data in a single query
# returns one row for each answer (use the response ID to aggregate
# these into a single response).

sub get_all_answers { 
    my $this = shift;
    if (! $share{querylib}{"all quiz answers"}) {
	$share{DB}->set_query("all quiz answers",
			      sql=>"select r.response_id,r.status,q.content_id,q.label,a.answer_id,a.value answer,r.ctime,r.uid,r.language,coalesce(m.value,'short text') format from response r,answer a,content_type t,content q left join metadata m on m.id=q.content_id and m.name='format' where t.name='quiz_question' and q.type=t.content_type_id and a.question_id=q.content_id and r.response_id=a.response_id and r.form_id=? order by response_id,q.sortkey",
			      nparam=>1,
			      mode=>"r",
			      keys=>["response","answer","content"]);
    }
    return $share{DB}->get_query("all quiz answers",$this->id);
}

1;

