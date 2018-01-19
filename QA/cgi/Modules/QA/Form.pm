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

package Modules::QA::Form;

use strict;
use ExSite::Config;
use ExSite::Base;
use ExSite::Form;
use ExSite::Captcha;
use ExSite::Misc;
use ExSite::Mail;
use ExSite::Object;
use ExSite::ObjectList;
use Modules::QA::Question;
use Modules::QA::Response;

use vars qw(@ISA);
@ISA = qw(ExSite::Object Modules::BaseDCD);

sub my_type { return "qa_form"; }

sub name {
    my $this = shift;
    $this->load() if (!defined $this->{data});
    return $this->getdata("title");
}

sub flag {
    my ($this,$flag) = @_;
    my $flags = $this->getdata("flags");
    if ($flag) {
	return $flags =~ /$flag/;
    }
    else {
	my @flag = split /; /, $flags;
	return wantarray ? @flag : \@flag;
    }
}

# captcha - should captchas be conditional on login status?

sub use_captcha {
    my $this = shift;
    return $this->flag("captcha") || $this->{robot_countermeasures_failed};
}

sub has_captcha {
    my $this = shift;
    my $in = new ExSite::Input;
    my $indata = $in->post_or_query();
    if ($this->flag("robot counter-measures") &&
	exists $indata->{captcha} && 
	exists $indata->{captcha_solution}) {
	# real captcha overrides robot counter-measures
	return 1;
    }
    return $this->flag("captcha");
}

# template : return content object that contains the template

sub template {
    my ($this,%opt) = @_;
    my $template = $opt{template} || $this->getdata("template");
    if ($template =~ /^\w+$/) {
	# single-word template = content object; search in context of current
	# page if possible, our section if not
	my $obj = $share{Page} ? 
	    $share{Page} : 
	    new ExSite::Section(id=>$this->getdata("section_id"));
	if ($opt{revision}) {
	    #$obj->set_revision($opt{revision});
	    $obj->load_revision($opt{revision});
	}
	return $obj->find($template);
    }
    return undef;
}

#=== DISPLAY

# show: either display or process the form

sub show {
    my ($this,%opt) = @_;
    if ($this->ok) {
	if (! $this->{data}) { $this->load(); }
	my $name = ucfirst $this->name;
	if ($opt{version}) {
	    $this->set("version",$opt{version});
	}
	elsif ($share{Page} && $share{Page}->get_my("version")) {
	    $this->set("version",$share{Page}->get_my("version"));
	}
	if (! $this->{data}) {
	    return $this->error("$name ".$msg{"does not exist."});
	}
	elsif (! $this->{list}) {
	    return $this->error("$name ".$msg{"has no questions."});
	}
	else {
	    my $in = new ExSite::Input;
	    my $indata = $in->post_or_query();
	    if ($indata->{_qakey}) {
		# looks like we have form inputs
		return $this->do_form($indata);
	    }
	    else {
		# display ordered list of questions
		$opt{formname} or $opt{formname} = $this->getdata("name");
		return $this->show_form(%opt);
	    }
	}
    }
    return $this->error($this->{status});
}

# show_form : display the form

sub show_form {
    my ($this,%opt) = @_;
    if (! $this->{data}) { $this->load(); }
    if ($this->flag("members-only") && ! $share{DB}->level) {
	return $this->warn("You must be logged in to view this form.");
    }
    my $fb = $this->get_form(%opt);
    return $fb->make();
}

# get_form() - return a FormBuilder object for this form

sub get_form {
    my ($this,%opt) = @_;
    if (! $this->{data}) { $this->load(); }
    if ($this->{FormBuilder}) { 
	# already made it
	return $this->{FormBuilder}; 
    }

    my $l = $this->{list};
    my $v = $this->get("version");
    my $num = 0;

    my $fb = new ExSite::FormBuilder(%opt);
    $this->{FormBuilder} = $fb;
    if ($config{QA}{highlight_rows}) {
	$fb->set("highlight_rows",1);
    }

    $this->set_template(%opt);

    my $buttons = $opt{buttons} || $config{QA}{buttons};
    if ($buttons) {
	# customize the form buttons
	$fb->set("buttons",$buttons);
    }

    $opt{data} or 
	$opt{data} = $this->run_handler("QA_Prepop_data", $this->name);
 
    # any data to prepop the form with?
    my $response_data;
    if ($opt{response} =~ /^\d+$/) {
	my $r = new Modules::QA::Response(id=>$opt{response});
	$response_data = $r->get_response_data();
    }
    elsif (ref($opt{data}) eq "HASH" || $opt{data} eq "HASH") {
	$response_data = $opt{data};
    }
    elsif ($this->flag('prepopulate with member data') && $share{DB}->level) {
	$response_data = $share{DB}->my_user_record;
    }
    if ($response_data) {
	# this is redundant, since we add the response data manually below.
	# But it allows FormBuilder to detect missing data and restyle
	# accordingly.
	$fb->values($response_data);
    }
    my $in = new ExSite::Input();
    my $query_data = $in->query();

    # generate form inputs
    my %names;
    while (my $q = $l->next()) {
	$num++;
	if ($v) { $q->set("version",$v); }
	my $qid = $q->qname;
	$names{$qid} = 1;
	my %qopt = (
		    FormBuilder=>$fb,
		    id=>$qid,
		    name=>$q->getdata("name"),
		    );
	if (ref $response_data eq "HASH" && defined $response_data->{$qid}) {
	    # use data from response
	    $qopt{value} = $response_data->{$qid};
	}
	elsif (exists $query_data->{$qid}) {
	    # query string has suggested value
	    $qopt{value} = $query_data->{$qid};
	}
	$q->show(%qopt);
    }

    # add QA key to validate this form
    my $c = new ExSite::Crypt();
    my $confirm = $this->flag("confirmation screen") ? 0 : 1;
    $fb->input(type=>"hidden",
	       name=>"_qakey",
	       value=>$c->encrypt($this->id.";".$confirm.";".$opt{response}));

    if ($this->use_captcha()) {
	my $input = new ExSite::Input;
	my $in = $input->combine;
	my $c = new ExSite::Captcha(mode=>$in->{captchamode});
	$fb->input(name=>"captcha", prompt=>" ", input=>$c->make());
    }
    elsif ($this->flag("robot counter-measures")) {

	# 1) add a honeypot field to try to catch comment spam
	my $name = $config{captcha}{honeypot_name};
	if ($names{$name}) {
	    # default honeypot field collides with our form
	    my $n = 0;
	    do { $name = $config{captcha}{honeypot_name}.$n; $n++ } 
	    until (! $names{$name});
	}
	my $c = new ExSite::Captcha(mode=>"passive",name=>$name);
	my $cinput = $c->make($this->id);
	if ($cinput) {
	    $fb->input(name=>"captcha", prompt=>" ", input=>$cinput);
	}
#	# 2) add a honeypot field to try to catch comment spam
#	my $name = $config{captcha}{jsmod_name} || "_pc";
#	$fb->input(name=>$name, type=>"hidden", value=>"_pc");
    }
    return $fb;
}

sub do_form {
    my ($this,$data) = @_;
    my @err = $this->validate_form($data);
    my $ml = new ExSite::ML;
    my $out;
    if (@err > 0) {
	$out = $this->error(@err);
	# flag this form as being regenerated, or else it will attempt
	# to re-process the captcha
	$this->{regen}{$this->id} = 1;
	$out .= $this->show_form(data=>$data);
#	$out .= $ml->p(&ExSite::HTML::Button(url=>"javascript:history.back()",
#					     label=>"&lt; ".$msg{"Back to form"}));
    }
    elsif ($this->{confirmed}) {
	my $r = new Modules::QA::Response();
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
					 qa_form_id => $this->id ,
					 uid => $uid,
					 version => $this->get("version"),
				     },
				     $this->{response_data}
				     );
	}
	if ($rid) {
	    # response was logged successfully
	    $this->{response} = $r;
	    if ($r->defined() && ! $this->{do_form_response}) {
		# email notification for new responses only
		$out .= $this->notify($r);
		# receipt callback for custom post-processing
		$out .= $this->run_handler("qa_receipt",$r);
	    }
	    if (! $r->errorcheck()) {
		# No errors were logged in post-processing...
		# we can show completion message
		my $message = $this->run_handler("QA_acceptance_message",$r);
		if (! defined $message) {
		    $message = 
			$msg{$this->getdata("message")} || 
			$ml->h1($msg{"Thank you"});
		    if ($message =~ /\[\[/) {
			# message contains merge fields
			my %data = $r->get_response_data();
			$data{_summary} = $r->show();
			$data{_date} = $r->showdata("ctime");
			$message = &substitute($message,\%data);
		    }
		    if ($message !~ /<[A-Za-z!]/) {
			my $br = $ml->br;
			$message =~ s/\n/$br\n/g;
		    }
		}
		return $message . $out;
	    }
	}
	else {
	    $out .= $r->show_diagnostics("error","html");
	}
    }
    else {
	return $this->confirmation_page($data);
    }
    return $out;
}

# set_template: 
# 3 possibilities:
# 1) user has installed their own custom template
# 2) we dynamically create our own 'custom' template that tries to group
#    similar questions
# 3) we fall back on a generic row-by-row template

sub set_template {
    my ($this,%opt) = @_;

    # 1) check for custom template
    if ($opt{template} && $opt{template} =~ /<\/?[a-zA-Z]+[ >]/) {
	# passed template is already in html format
	$this->{FormBuilder}->template($opt{template});
	return;
    }
    # check for custom template in CMS
    my $template = $this->template(%opt);
    my $template_html = $template->get_html() if $template;
    if ($template_html) {
	$this->{FormBuilder}->template($template_html);
	return;
    }

    # 2) see if we can build a custom template by grouping questions
    my $ml = &get_obj("ML");
    my @qgrp;
    my $last;
    my ($format,$lastformat,$value,$lastvalue);
    my $nq;
    my $ngrp = 0;
    $qgrp[0] = [];
    my $use_groups;
    # scan questions, looking for questions that can be grouped
    my $l = $this->{list};
    while (my $q = $l->next()) {
	$nq++;
	my $format = $q->format;
	my $value = $q->{base}->value;
	if ($last) {
	    if ($nq && ($format ne $lastformat || 
			$value ne $lastvalue ||
			$format !~ /^(radio|checkbox|checklist)$/)) {
		# do not group this question with the last one
		$ngrp++;
	    }
	    else {
		# try to do question grouping
		$use_groups = 1;
	    }
	}
	push @{$qgrp[$ngrp]},$q;
	$last = $q;
	$lastformat = $format;
	$lastvalue = $value;
    }
    if ($use_groups) {
	# looks like we have some questions that could benefit from grouping
	my $template;
	# rescan questions, assembling an all-in-one template as we go
	my @tgrp;
	my $ngrp = 0;
	# loop over each group
	foreach my $gr (@qgrp) {
	    $ngrp++;
	    my $format = $gr->[0]->format;
	    my $rowclass;
	    if ($config{QA}{highlight_rows}) {
		$rowclass = $ngrp % 2 ? " A" : " B";
	    }
	    # loop over each question in the group
	    my $multi = (scalar @$gr > 1);
	    my $rowout;
	    if ($multi) {
		if ($format eq "checkbox") {
		    # questions
		    my $nrow = 0;
		    my @row;
		    foreach my $q (@$gr) {
			$nrow++;
			my $grrowclass = $nrow % 2 ? "odd" : "even";
			my $name = $q->qname();
			$rowout .= 
			    $ml->tr(
				$ml->td("[[$name:input]]",{class=>"QA_input"}).
				$ml->td($ml->div("[[$name:prompt]]",{class=>"QA_prompt"})),
				{class=>"QA_question_group_$grrowclass"}
			    );
		    }
		}
		else {
		    # header row
		    my @row = ( $ml->td() );
		    my @opt = $gr->[0]->answer_values();
		    foreach my $opt (@opt) {
			push @row, $ml->th($opt);
		    }
		    if ($format =~ /other/) {
			push @row, $ml->th($msg{Other});
		    }
		    $rowout = $ml->tr(join("",@row));
		    
		    # questions
		    my $nrow = 0;
		    foreach my $q (@$gr) {
			$nrow++;
			my $grrowclass = $nrow % 2 ? "odd" : "even";
			my $name = $q->qname();
			@row = (
			    $ml->td($ml->div("[[$name:prompt]]",{class=>"QA_prompt"}))
			    );
			my $iopt = 0;
			foreach my $opt (@opt) {
			    $iopt++;
			    push @row, $ml->td("[[$name:input:$iopt]]",{class=>"QA_input"});
			}
			if ($format =~ /other/) {
			    $iopt++;
			    push @row, $ml->td("[[$name:input:$iopt]]",{class=>"QA_input"});
			}
			$rowout .= $ml->tr(join("",@row),{class=>"QA_question_group_$grrowclass"});
		    }
		}
		$rowout = $ml->div(
		    $ml->table($rowout,{class=>"QA_question_group"}),
		    {class=>"QA_question$rowclass"}
		    );
	    }
	    else {
		my $q = $gr->[0];
		my $name = $q->qname();
		$rowout = $ml->div(
		    $ml->div("[[$name:prompt]]",{class=>"QA_prompt"}).
		    $ml->div("[[$name:input]]",{class=>"QA_input"}),
		    {class=>"QA_question$rowclass"}
		    );
	    }
	    $template .= $rowout;
	}
	$this->{FormBuilder}->template($template);
	return;
    }

    # 3) install an improved row-by-row template

    if ($config{QA}{template}) {
	# use a slightly fancier row-by-row template to allow for more CSS
	$this->{FormBuilder}->template("<div class='QA_form'>",
		      $ml->div(
			  $ml->div("[[prompt]]",{class=>"QA_prompt"}).
			  $ml->div("[[input]]",{class=>"QA_input"}),
			  {class=>"QA_question [[rowclass]]"}
		      ),
		      "</div>");
	return;
    }

    # else: use the generic row-by-row template
}

sub response {
    my $this = shift;
    return $this->{response} if ($this->{response});
    return undef;
}

sub validate_form {
    my ($this,$data) = @_;
    my @err;
    if ($this->getdata("status") eq "inactive" && ! $share{DB}->is_admin()) {
	push @err, $msg{"Sorry, this form has been disabled and is not accepting input at this time."};
    }
    else {
	my $c = new ExSite::Crypt();
	my ($fkey,$confirm,$response) = split /;/,$c->decrypt($data->{_qakey});
	$this->{confirmed} = $confirm;
	if ($fkey !~ /^\d+$/ || $fkey != $this->id) {
	    push @err, $msg{"Invalid form ID."};
	}
	else {
	    # looks like valid input

	    if (my $deny = $this->deny) {
		# failed to pass security check
		return ($deny);
		# don't bother with other validation
	    }

	    # create a question index
	    $this->{qobj} = {};  # index of question objects, by ID
	    $this->{qname} = {}; # index of question IDs, by name
	    while (my $q = $this->{list}->next()) {
		$q->set("form",$this);
		my $id = $q->id;
		$this->{qobj}{$id} = $q;
		my $name = $q->qname();
		if (exists $this->{qname}{$name}) {
		    push @err, $msg{"Duplicate questions under name"}." '$name'";
		    # dupes will overwrite each other in the response data
		}
		else {
		    $this->{qname}{$name} = $id;
		}

		if ($q->format eq "file") {
		    # save file in share, convert file handle to file name
		    my $max_file_size = $config{QA}{max_file_size} || 65536; # 64k
		    my $fdata = ExSite::Input->new()->fetch_file($name,"raw");
		    my $filename = sprintf("%s",$data->{$name});

		    if (length $fdata > $max_file_size &&
			&MimeType($filename) =~ /^image/) {
			# try shrinking the image
			my $img = new ExSite::Image($filename,$fdata);
			if ($img->shrink(size=>$max_file_size/1024)) {
			    $fdata = $img->get("filedata");
			}
		    }
		    $share{QA}{files}{$this->id}{$name} = {
			filename=>$filename,
			size=>length $fdata,
			data=>$fdata,
		    };
		    if (length $fdata > $max_file_size) {
			
			my $size_k = int ($max_file_size/102.4) / 10;
			push @err, &substitute($msg{"[[name]] is too large; [[size]] kB max"},{name=>$name,size=>$size_k});
		    }
		    $data->{$name} = $filename;
		}
	    }

	    # get our list of questions and input names
	    $this->{response_data} = {};
	    my %legal_questions = &keywise($this->{list}->key,
					   scalar $this->{list}->getlist());

	    # map the response as qid => answer value
	    # spurious inputs (eg. captcha solutions) should be ignored
	    foreach my $key (%$data) {
		if (exists $this->{qname}{$key}) {
		    $this->{response_data}{$this->{qname}{$key}} = $data->{$key};
		}
	    }

	    # are all required answers present?
	    # do selected answers conform to allowed values?
	    foreach my $qid (keys %legal_questions) {
		my $q = $this->{qobj}{$qid};
		my $valerr = $q->validate_answer($this->{response_data}{$qid});
		if ($valerr) { push @err, $valerr; }
	    }

	    # note the response ID so we know what to update
	    $this->{do_form_response} = $response;
	}
    }
    return @err;
}

# deny : test if the form input should be rejected

sub deny {
    my $this = shift;
    if ($this->has_captcha() && 
	($this->{confirmed} || $this->flag("confirmation screen"))) {
	# interactive captcha -> user must solve a puzzle
	my $input = new ExSite::Input;
	my $in = $input->combine;
	my $c = new ExSite::Captcha(mode=>$in->{captchamode});
	if ($c->pass()) {
	    # real captcha overrides robot counter-measures
	    $this->{robot_countermeasures_failed} = 0;
	}
	else {
	    if ($this->flag("robot counter-measures")) {
		$this->{robot_countermeasures_failed} = 1;
	    }
	    return $msg{"Incorrect answer to the anti-spam question."};
	}
    }
    if ($this->flag("robot counter-measures") &&  # passive captcha requested
	! $this->flag("captcha") &&           # regular captcha not requested
	! exists $this->{robot_countermeasures_failed}) { # no reversion to active captcha
	my $l = $this->{list};	
	my $v = $this->get("version");
	my $num = 0;
	my %names;
	while (my $q = $l->next()) {
	    $num++;
	    if ($v) { $q->set("version",$v); }
	    my $qid = $q->qname;
	    $names{$qid} = 1;
	}

	my $name = $config{captcha}{honeypot_name};
	if ($names{$name}) {
	    # default honeypot field collides with our form
	    my $n = 0;
	    do { $name = $config{captcha}{honeypot_name}.$n; $n++ }
	    until (! $names{$name});
	}
	# passive captcha, not overridden by regular captcha
	my $c = new ExSite::Captcha(mode=>"passive",name=>$name);
	if (!$c->pass($this->id)) {
	    $this->{robot_countermeasures_failed} = 1;
	    return $msg{"Unable to confirm that you are a real person. Please complete the anti-spam question."};
	}
    }
    if ($this->flag("members-only")) {
	if ($share{DB}->level < 1) {
	    return $msg{"Sorry, you must be logged in to use this form."};
	}
	if ($this->flag("single submission only")) {
	    my @r = $share{DB}->fetch_match("qa_response",{qa_form_id=>$this->id,uid=>$share{DB}->my_uid});
	    if (scalar @r > 0) {
		return $msg{"Sorry, a response to this form has already been received from you. Thank you again for your input."};
	    }
	}
    }
    return undef;
}

sub confirmation_page {
    my ($this,$data) = @_;
    my $ml = new ExSite::ML;
    my $out = $ml->h1($msg{"Please Confirm"});
    my $report = new ExSite::ReportBuilder(
					   title=>$msg{"Your Response"},
					   headers=>[$msg{Question},$msg{Answer}],
					   );
    $report->class("QA_confirmation");
    my $l = $this->{list};
    while (my $q = $l->next()) {
	next if ($q->format() =~ /^(hidden)$/);
        $q->set_version($this->{version}) if ($this->{version});
	# this is a dummy answer
	my $a = new Modules::QA::Answer(data=>{qa_answer_id=>-1, # kludge
					       qa_question_id=>$q->id,
					       value=>$data->{$q->qname()}});
	$report->push($q->label(),$a->show());
    }

    my $formdata;
    if ($config{QA}{top_confirm}) {
	$formdata .= 
	    $ml->p(
		   $ml->input(undef,{type=>"button",value=>"&lt; $msg{Back}",onclick=>"javascript:history.back()"}).
		   "&nbsp;".
		   $ml->input(undef,{type=>"submit",value=>$msg{Confirm}})
		   );
    }
    $formdata .= $report->make();
    foreach my $key (keys %$data) {
	if ($key eq "_qakey") {
	    # rewrite with a confirmation flag
	    my $c = new ExSite::Crypt();
	    my ($fkey,$confirm,$response) = split /;/,$c->decrypt($data->{_qakey});
	    $data->{$key} = $c->encrypt("$fkey;1;$response");
	}
	my $val = $data->{$key};
	$val =~ s/\"/&quot;/g;
	$formdata .= $ml->input(undef,{type=>"hidden",name=>$key,value=>$val});
	$formdata .= "\n";
    }
    $formdata .= $ml->p(
			$ml->input(undef,{type=>"button",value=>"&lt; $msg{Back}",onclick=>"javascript:history.back()"}).
			"&nbsp;".
			$ml->input(undef,{type=>"submit",value=>$msg{Confirm}})
			);

    $out .= $ml->p( $ml->form($formdata,{method=>"post"}) );
    return $out;
}

sub notify {
    my $this = shift;
    my $response = shift;
    my $stat = $this->run_handler("qa_notify",$response);
    return $stat if ($stat);

    my $notify = $this->getdata("notify");
    return if (! $notify);

    my %opt;
    my $formtitle = $this->getdata("title");
    my $subject = "Response received from '$formtitle'";
    my $site = $share{DB}->this_site();
    my $site_name = $site ? ($site->{label} || $site->{title}) : $config{site}{name};
    my $message = $subject . "\non $site_name website:\n\n";
    my $from = &preference("QA.notification_from") ||
	$share{DB}->owner_email($site);
    
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
    if (exists $share{QA}{files}{$this->id}) {
	my @attach = values %{$share{QA}{files}{$this->id}};
	$mailopt{attach} = \@attach;
    }

    &ExSite::Mail::send(%mailopt);
    return;
}

# list of fields or questions for this form

sub questions {
    my $this = shift;
    if ($this->defined) {
	return $this->{list};
    }
    return undef;
}

sub question_names {
    my $this = shift;
    my @fname;
    if ($this->defined) {
	$this->{list}->reset();
	while (my $q = $this->{list}->next()) {
	    push @fname, $q->qname();
	}
    }
    return @fname;
}

sub question_labels {
    my $this = shift;
    my @label;
    if ($this->defined) {
	$this->{list}->reset();
	while (my $q = $this->{list}->next()) {
	    push @label, $q->label();
	}
    }
    return @label;
}

#=== DB

# load record : can pass an ID or a datahash

sub load {
    my ($this,$data) = @_;
    $this->{list} = undef;
    if ($this->SUPER::load($data)) {
	my $list =  new ExSite::ObjectList(type=>"qa_question");
	$list->load({qa_form_id=>$this->id});
	$list->sort("sortkey","qa_question_id");
	$this->{list} = $list;
    }
}

sub loaded {
    my $this = shift;
    $this->load if (! $this->{data} || ! $this->{list});
    return ($this->{data} && $this->{list});
}

# get_all_answers : retrieves all answer data in a single query
# returns one row for each answer (use the response ID to aggregate
# these into a single response).
# * qa_response.qa_response_id
# * qa_question.qa_question_id
# * qa_base.label (base question text)
# * qa_answer.qa_answer_id
# * qa_answer.value as answer (answer value)
# * qa_base.format
# * qa_base.value (answer regexp)

sub get_all_answers {
    my $this = shift;
    if (! $share{querylib}{"all form answers"}) {
	$share{DB}->set_query("all form answers",
			      sql=>"select r.qa_response_id,q.qa_question_id,b.label,a.qa_answer_id,a.value answer,b.format,b.value,r.ctime,r.uid,r.version from qa_response r,qa_answer a,qa_question q, qa_base b where q.qa_base_id=b.qa_base_id and a.qa_question_id=q.qa_question_id and r.qa_response_id=a.qa_response_id and r.qa_form_id=? order by qa_response_id,q.sortkey",
			      nparam=>1,
			      mode=>"r",
			      keys=>["qa_response","qa_answer","qa_question","qa_base"]);
    }
    return $share{DB}->get_query("all form answers",$this->id);
}

sub count_responses {
    my $this = shift;
    if ($this->defined) {
	return $share{DB}->count("qa_response",{qa_form_id=>$this->id});
    }
    return undef;
}

sub count_questions {
    my $this = shift;
    if ($this->defined) {
	return $this->{list}->count();
    }
    return undef;
}

sub copy {
    my $this = shift;
    if ($this->defined()) {
	my $name = $this->name();
	my $newformid = $this->SUPER::copy(title=>"$name (copy)");
	if ($newformid) {
	    # also copy questions
	    $this->questions->reset();
	    while (my $q = $this->questions->next()) {
		$q->copy(qa_form_id=>$newformid);
	    }
	}
	return $newformid;
    }
    return undef;
}

1;

