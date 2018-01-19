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

package Modules::Forms::Form;

use strict;
use ExSite::Config;
use ExSite::Base;
use ExSite::Form;
use ExSite::Captcha;
use ExSite::Misc;
use ExSite::Mail;
use ExSite::ObjectList;
use ExSite::Content;
use Modules::Forms::Question;
use Modules::Forms::Response;

use vars qw(@ISA);
@ISA = qw(ExSite::Content); # Modules::BaseDCD);  ########## BaseDCD ???

sub setup {
    my ($this,%opt) = @_;
    $this->SUPER::setup(%opt);
    # need some DB extensions
    $share{DB}{map}->load_submaps("Forms");
    return;
}

sub is_active {
    my $this = shift;
    return ! $this->getdata("status"); # only published forms are active
}

sub allow_post {
    my $this = shift;
    # who may post?
    if ($this->is_active ||          # if form is active
	$share{DB}->is_admin ||      # or user is an admin
	$this->has_role("owner")) {  # or user is the owner of the form
	return $share{DB}->level >= $this->access;
    }
    return 0;
}

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

sub can_index {
    my $this = shift;
    return undef; # do not include forms in search indexes
}

#=== DISPLAY

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


sub show_form {
    my ($this,%opt) = @_;
    my $access = $this->access;
    if ($access && $access > $share{DB}->level || ! $this->is_active) {
	return $this->warn($msg{"You do not have sufficient permissions to use this form."});
    }
    my $fb = $this->get_form(%opt);
    return $fb->make();
}

sub preview {
    my ($this,%opt) = @_;
    return $this->show();
}

sub has_content {
    my $this = shift;
    # this doesn't work because revision is form layout, not form content
    #return $this->revision->view->defined;
    my $questions = $this->questions();
    return $questions ? $questions->count() : undef;
}

# get_form() - return a FormBuilder object for this form

sub get_form {
    my ($this,%opt) = @_;
    if ($this->loaded) {
	if ($this->{FormBuilder}) { 
	    # already made it
	    return $this->{FormBuilder}; 
	}
	if (! exists $opt{action}) {
	    $opt{action} = $this->get_url_dynamic(); #"$config{server}{CGIpath}/$config{prog}{post}".$this->path();
	}

	my $fb = new ExSite::FormBuilder(%opt);
	$this->{FormBuilder} = $fb;

	$this->set_layout(%opt);

	my $buttons = $opt{buttons} || $config{Forms}{buttons};
	if ($buttons) {
	    # customize the form buttons
	    $fb->set("buttons",$buttons);
	}

	# any data to prepop the form with?
	$opt{data} or 
	    $opt{data} = $this->run_handler("Forms_Prepop_data");
	my $response_data;
	if ($opt{response} =~ /^\d+$/) {
	    my $r = new Modules::Forms::Response(id=>$opt{response});
	    $response_data = $r->get_response_data();
	}
	elsif (ref($opt{data}) eq "HASH" || $opt{data} eq "HASH") {
	    $response_data = $opt{data};
	}
	elsif ($this->flag('prepopulate with user data') && $share{DB}->level) {
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
	my $num = 0;
	my %names;
	while (my $q = $this->{list}->next()) {
	    $num++;
	    my $qname = $q->name;
	    $names{$qname} = 1;
	    my %qopt = (
		FormBuilder=>$fb,
#		id=>"q_".$q->id,
		name=>$qname,
		);
	    if (ref $response_data eq "HASH" && defined $response_data->{$qname}) {
		# use data from response
		$qopt{value} = $response_data->{$qname};
	    }
	    elsif (exists $query_data->{$qname}) {
		# query string has suggested value
		$qopt{value} = $query_data->{$qname};
	    }
	    $q->show(%qopt);
	}

	# add key to validate this form
	my $c = new ExSite::Crypt();
	my $confirm = $this->flag("confirmation screen") ? 0 : 1;
	$fb->input(type=>"hidden",
		   name=>"_formkey",
		   value=>$c->encrypt($this->id.";".$confirm.";".$opt{response}));

	if ($this->use_captcha()) {
	    my $input = new ExSite::Input;
	    my $in = $input->combine;
	    my $c = new ExSite::Captcha(mode=>$in->{captchamode});
	    $fb->input(name=>"captcha", prompt=>" ", type=>"preformatted", input=>$c->make());
	}
	elsif ($this->flag("robot counter-measures")) {
	    # add a honeypot field to try to catch comment spam
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
		$fb->input(name=>"captcha", prompt=>" ", type=>"preformatted", input=>$cinput);
	    }
	}
	if ($this->flag("simple buttons")) {
	    $fb->buttons(submit=>1);
	}
	return $fb;
    }
    return undef;
}

sub set_layout {
    my ($this,%opt) = @_;

    # allow alternate-row highlighting
    if ($config{Forms}{highlight_rows}) {
	$this->{FormBuilder}->set("highlight_rows",1);
    }

    my $layout;

    # check for custom layout
    if ($opt{layout} && $opt{layout} =~ /<\/?[a-zA-Z]+[ >]/) {
	# passed layout is already in html format
	$layout = $opt{layout};
    }
    elsif ($this->has_revisions) {
	$layout = $this->get_html;
    }

    if ($layout) {
	# expand question placeholders into FormBuilder placeholders
	my $l = $this->{list};
	$l->reset;
	while (my $q = $l->next()) {
	    my $qname = $q->name;
	    if ($layout =~ /\[\[$qname\]\]/) {
		# template has a simple question placeholder
		my $qtemplate = $q->layout();
		$layout =~ s/\[\[$qname\]\]/$qtemplate/;
	    }
	}
	$this->{FormBuilder}->template($layout);
	return;
    }

    # see if we can build a custom layout by grouping questions
    my @layout = $this->make_layout(%opt);
    if (scalar @layout > 1 || $layout[0]) {
	$this->{FormBuilder}->template(@layout);
    }
    return;
}

sub make_layout {
    my ($this,%opt) = @_;
    return if (! $this->loaded);
    return if (! $config{Forms}{auto_template}); # uses FormBuilder defaults

    my $ml = &get_obj("ML");
    my $layout;
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
	my $values = $q->allowed_answers;
	if ($last) {
	    if ($nq && ($format ne $lastformat || 
			$value ne $lastvalue ||
			$format !~ /^(radio|checkbox|checklist)$/)) {
		# do not group this question with the last one
		$ngrp++;
	    }
	    else {
		$use_groups = 1;
	    }
	}
	push @{$qgrp[$ngrp]},$q;
	$last = $q;
	$lastformat = $format;
	$lastvalue = $value;
    }
    # exit if no reason to make a custom layout
    return undef if (! $use_groups);# && ! $config{Forms}{auto_template});

    my $layout;
    # rescan questions, assembling an all-in-one layout as we go
    my @tgrp;
    my $ngrp = 0;
    # loop over each group
    foreach my $gr (@qgrp) {
	$ngrp++;
 
	my $format = $gr->[0]->format;
	# highlight alternating rows
	my $rowclass;
	$rowclass = $ngrp % 2 ? "A" : "B";
	# loop over each question in the group
	my $multi = (scalar @$gr > 1);
	my $rowout;
	if ($multi) {
	    if ($format eq "checkbox") {
		# questions
		my $nrow = 0;
		my @row;
		foreach my $q (@$gr) {
		    # highlight alternating group rows, too!
		    $nrow++;
		    my $grrowclass = $nrow % 2 ? "odd" : "even";
		    my $name = $q->name();
		    $rowout .= 
			$ml->tr(
			    $ml->td("[[$name:input]]",{class=>"Forms_input"}).
			    $ml->td($ml->div("[[$name:prompt]]",{class=>"Forms_prompt"})),
			    {class=>"Forms_question_group_$grrowclass"}
			);
		}
	    }
	    else {
		# header row
		my @row = ( $ml->td() );
		my @opt = $gr->[0]->allowed_answers();
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
		    my $name = $q->name();
		    @row = (
			$ml->td($ml->div("[[$name:prompt]]",{class=>"Forms_prompt"}))
			);
		    my $iopt = 0;
		    foreach my $opt (@opt) {
			$iopt++;
			push @row, $ml->td("[[$name:input:$iopt]]",{class=>"Forms_input"});
		    }
		    if ($format =~ /other/) {
			$iopt++;
			push @row, $ml->td("[[$name:input:$iopt]]",{class=>"Forms_input"});
		    }
		    $rowout .= $ml->tr(join("",@row),{class=>"Forms_question_group_$grrowclass"});
		}
	    }
	    $rowout = $ml->div(
		$ml->table($rowout,{class=>"Forms_question_group"}),
		{class=>"Forms_question $rowclass"}
		);
	}
	else {
	    my $q = $gr->[0];
	    my $name = $q->name();
#	    my $template = $q->layout();
#	    my $template = $q->has_revisions ? "[[$name]]" : $q->layout();
	    my $template = $q->has_revisions ? $q->layout() : "[[$name]]";
	    $template =~ s/\[\[rowclass\]\]/$rowclass/;
	    $rowout = $template;
	}
	$layout .= $rowout;
    }
    return ($layout);
}

sub response {
    my $this = shift;
    return $this->{response} if ($this->{response});
    return undef;
}

sub robot_check {
    my ($this,$data) = @_;
    
    if ($this->has_captcha() && 
	($this->{confirmed} || $this->flag("confirmation screen"))) {
	# interactive captcha -> user must solve a puzzle
	my $c = new ExSite::Captcha(mode=>$data->{captchamode});
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
	my %names = $this->{list}->hash("name");
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
    return undef;
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
		my $r = new Modules::Forms::Response();
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
			    language => $share{Page} ?
				$share{Page}->getdata("language") : undef,
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
			$out .= $this->run_handler("Forms_receipt",$r);
			my $price = $this->price();
			if ($price) {
			    # form has a price attached to it; 
			    # assume it's an order form
			    my $stat = eval "require Modules::Finance::Cart";
			    if ($stat) {
				my $details = $r->show_as_plaintext(skip_blank_answers=>1,id=>"Order #");
				$details =~ s/\n/\//g;   # nl -> /
				$details =~ s/\/\//\//g; # //
				$details =~ s/\/$//g;    # trailing /
				my $cart = new Modules::Finance::Cart();
				$out .= $cart->add(
				    item=>$price->{description}||$this->title,
				    description=>$details,
				    cost=>$price->{cost},
				    acctcode_id=>$price->{acctcode_id},
				    uid=>$share{DB}->my_uid,
				    objtype=>"response",
				    objid=>$rid,
				    acctcode2=>$this->id,
				    );
				$out .= $cart->show();
			    }
			    else {
				$out .= $this->error("Unable to setup shopping cart for this purchase: $@");
			    }
			}
		    }
		    if (! $r->errorcheck()) {
			# No errors were logged in post-processing...
			# we can show completion message
			my $message = $this->run_handler("Forms_receipt",$r);
			if (! defined $message) {
			    my $receipt = $this->my_content("_receipt");
			    $message = $receipt ?
				$receipt->get_html() :
				$ml->h1($msg{"Thank you"});
			    if ($message =~ /\[\[/) {
				# message contains merge fields
				my %data = $r->get_response_data();
				$data{_summary} = $r->show();
				$data{_date} = $r->showdata("ctime");
				$message = &substitute($message,\%data);
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

sub validate_form {
    my ($this,$data) = @_;
    my @err;

    # create a question index
    $this->{qobj} = {};  # index of question objects, by ID
    $this->{qname} = {}; # index of question IDs, by name
    while (my $q = $this->{list}->next()) {
	my $id = $q->id;
	$this->{qobj}{$id} = $q;
	my $name = $q->name();
	if (exists $this->{qname}{$name}) {
	    push @err, $msg{"Duplicate questions under name"}." '$name'";
	    # dupes will overwrite each other in the response data
	}
	else {
	    $this->{qname}{$name} = $id;
	}

	if ($q->format eq "file") {
	    # save file in share, convert file handle to file name
	    my $max_file_size = $config{Forms}{max_file_size} || 65536; # 64k
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
	    $share{Forms}{files}{$this->id}{$name} = {
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
    #$this->{do_form_response} = $response; #########################

    return @err;
}

sub confirmation_page { ######################## deprecate ???
    my ($this,$data) = @_;
    my $ml = new ExSite::ML;
    my $out = $ml->h1($msg{"Please Confirm"});
    my $report = new ExSite::ReportBuilder(
					   title=>$msg{"Your Response"},
					   headers=>[$msg{Question},$msg{Answer}],
					   );
    $report->class("Forms_confirmation");
    my $l = $this->{list};
    while (my $q = $l->next()) {
	next if ($q->format() =~ /^(hidden)$/);
        $q->set_version($this->{version}) if ($this->{version});
	# this is a dummy answer
	my $a = new Modules::Forms::Answer(data=>{answer_id=>-1, # kludge
						  question_id=>$q->id,
						  value=>$data->{$q->name()}});
	$report->push($q->label(),$a->show());
    }

    my $formdata;
    if ($config{Forms}{top_confirm}) {
	$formdata .= 
	    $ml->p(
		   $ml->input(undef,{type=>"button",value=>"&lt; $msg{Back}",onclick=>"javascript:history.back()"}).
		   "&nbsp;".
		   $ml->input(undef,{type=>"submit",value=>$msg{Confirm}})
		   );
    }
    $formdata .= $report->make();
    foreach my $key (keys %$data) {
	if ($key eq "_formkey") {
	    # rewrite with a confirmation flag
	    my $c = new ExSite::Crypt();
	    my ($fkey,$confirm,$response) = split /;/,$c->decrypt($data->{_formkey});
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

# list of fields or questions for this form

sub questions {
    my $this = shift;
    if ($this->loaded) {
	return $this->{list};
    }
    return undef;
}

sub question_names {
    my $this = shift;
    my @fname;
    if ($this->loaded) {
	$this->{list}->reset();
	while (my $q = $this->{list}->next()) {
	    push @fname, $q->name();
	}
    }
    return @fname;
}

sub question_labels {
    my $this = shift;
    my @label;
    if ($this->loaded) {
	$this->{list}->reset();
	while (my $q = $this->{list}->next()) {
	    push @label, $q->title();
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
	# also load the questions
	$this->{list} = $this->get_contents_as_list("question");
	$this->{list}->set("class","Modules::Forms::Question");
#	my $tree = $this->get_content_tree;
#	my $list = new ExSite::ObjectList(type=>"content",class=>"Modules::Forms::Question");
#	$list->setlist($tree->get_child_data($this->id));
#	$this->{list} = $list;
    }
}

sub loaded {
    my $this = shift;
    $this->load if (! $this->{data} || ! $this->{list});
    return ($this->{data} && $this->{list});
}

sub unload {
    my $this = shift;
    delete $this->{status};
    delete $this->{data};
    delete $this->{children};
    delete $this->{list};
}

sub count_questions {
    my $this = shift;
    if ($this->loaded) {
	return $this->{list}->count();
    }
    return undef;
}

sub copy {
    my ($this,%data) = @_;
    if ($this->defined()) {
	if (! $data{name} || $data{name} eq $this->getdata("name")) {
	    $data{name} = $this->getdata("name") . "_copy";
	}
#	if (! $data{title} || $data{title} eq $this->getdata("title")) {
#	    $data{title} = $this->getdata("title") . " (copy)";
#	}
	if (! $data{label} || $data{label} eq $this->getdata("label")) {
	    $data{label} = $this->getdata("label") . " (copy)";
	}
	my $newformid = $this->SUPER::copy(%data);
	if ($newformid) {
	    # also copy questions

	    ##### FIXME: alias the questions?? translations??

	    $this->questions->reset();
	    while (my $q = $this->questions->next()) {
		$q->copy(parent=>$newformid);
	    }
	}
	return $newformid;
    }
    return undef;
}

# add_question
#
# Options:
# prompt = the question text
# format = the question type
# name = the input name
# access = access level to view this question 
# min, max, step = for numeric inputs
# size, maxlen = limit the field/input size
# required = make the question required, if set
# datatype = server-side validation rule
# preset = default value
# placeholder = formatting hint
# checked = prechecked (checkbox format only)

sub add_question {
    my ($this,%opt) = @_;
    my $out;
    my $ml = &get_obj("ML");
    my $ui = &get_obj("UI");

    my $q = $this->new_content_obj(
	title=>$opt{prompt},
	parent=>$this->id,
	type=>$this->isubtype("question"),
	name=>$opt{name},
	access=>$opt{access},
	);
    if ($q->defined) {
	if ($opt{format} && $opt{format} ne "short text") {
	    $q->set_metadata("format",$opt{format});
	}
	if ($opt{min} =~ /^\d+$/) {
	    $q->set_metadata("min",$opt{min});
	}
	if ($opt{max} =~ /^\d+$/) {
	    $q->set_metadata("max",$opt{max});
	}
	if ($opt{step} =~ /^\d+$/) {
	    $q->set_metadata("step",$opt{step});
	}
	if ($opt{size} =~ /^\d+$/) {
	    $q->set_metadata("size",$opt{size});
	}
	if ($opt{maxlen} =~ /^\d+$/) {
	    $q->set_metadata("maxlen",$opt{maxlen});
	}
	if ($opt{required} eq "required") {
	    $q->set_flag("required");
	}
	if ($opt{datatype} && $opt{datatype} !~ /any answer/) {
	    $q->set_metadata("datatype",$opt{datatype});
	}
	if ($opt{preset}) {
	    $q->set_metadata("preset",$opt{preset});
	}
	if ($opt{placeholder}) {
	    $q->set_metadata("placeholder",$opt{placeholder});
	}
	if ($opt{checked}) {
	    $q->set_flag("checked");
	}
	if ($opt{options}) {
	    $q->set_metadata("options",$opt{options});
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
    if (! $share{querylib}{"all form answers"}) {
	$share{DB}->set_query("all form answers",
			      sql=>"select r.response_id,q.content_id,q.label,a.answer_id,a.value answer,r.ctime,r.uid,r.language,coalesce(m.value,'short text') format from response r,answer a,content_type t,content q left join metadata m on m.id=q.content_id and m.name='format' where t.name='question' and q.type=t.content_type_id and a.question_id=q.content_id and r.response_id=a.response_id and r.form_id=? order by response_id,q.sortkey",
			      nparam=>1,
			      mode=>"r",
			      keys=>["response","answer","content"]);
    }
    return $share{DB}->get_query("all form answers",$this->id);
}

sub count_responses {
    my $this = shift;
    if ($this->defined) {
	return $share{DB}->count("response",{form_id=>$this->id});
    }
    return undef;
}

sub editmeta_template_old { 
    my ($this) = @_;
    my $ml = &get_obj("ML");
    my $br = $ml->br;
    # note escape codes in template placeholders
    return 
	$ml->p("Title${br}[[title:input]]").
	$ml->p("Label${br}[[label:input]]").
	$ml->p("Name${br}[[name:input]]").
	$ml->p("[[access:prompt]]${br}[[access:input]]").
	$ml->p("[[status:prompt]]${br}[[status:input]]").
	$ml->p("[[_flag_captcha:input]] [[_flag_captcha:prompt]]$br
[[_flag_robot_20counter_2dmeasures:input]] [[_flag_robot_20counter_2dmeasures:prompt]]$br
[[_flag_prepopulate_20with_20user_20data:input]] [[_flag_prepopulate_20with_20user_20data:prompt]]$br
[[_flag_confirmation_20screen:input]] [[_flag_confirmation_20screen:prompt]]");
}

sub editmeta_fields {
    my $this = shift;
    return ["title","label","name","access","status"];
}

1;

