package Modules::Quiz;

#----------------------------------------------------------------------------
#
#   Copyright (C) 2015 - Exware Solutions, Inc.  http://www.exware.com
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

use strict;

use ExSite::Config;
use ExSite::Misc;
use ExSite::ML;
use ExSite::URI;
use ExSite::Util;
use ExSite::Crypt;
use ExSite::Input;
use ExSite::Object;
use ExSite::ObjectList;
use ExSite::UI;
use Modules::Content;
use Modules::Forms;
use Modules::Quiz::Quiz;
use Modules::Quiz::Response;

use vars qw(@ISA $ml $ui $Forms $maxrec);
@ISA = qw(Modules::Forms);

sub write {
    my ($this,$options) = @_;
    $ml = &get_obj("ML");
    my %opt = &DecodeString($options);
    my $in = $this->{input};
    my $out;
    my $key_id;
    if ($in->{'_formkey'}) {
	my $c = new ExSite::Crypt;
	($key_id,undef) = split /;/, $c->decrypt($in->{'_formkey'});
    }
    my $form_id = $opt{form} || $key_id;
    my $action = $this->link();
    if ($form_id) {
	if ($in->{cmd} eq "edit_response" && $in->{response}) {
	    $out = $this->edit_response($form_id,$in->{response},$action);
	}
	else {
	    my $form = new Modules::Quiz::Quiz(id=>$form_id);
	    $out = $form->show(action=>$action);
	}
    }
    elsif ($in->{form}) {
	my $form = new Modules::Quiz::Quiz(id=>$in->{form});
	my $f_sid = $form->getdata("content_id");
	if (! $f_sid || $f_sid == $this->get_section_id()) {
	    $out = $form->show(action=>$action);
	}
	else {
	    $out = $this->error("Form $form_id: permission denied.");
	}
    }
    else {
	$out = $this->error("No form to display!");
    }
    return $ml->div($out,{class=>"Form"});
}

# ioctl method (used by ExSite to query the module for its functionality)

sub ioctl {
    my $this = shift;
    $_ = shift;           # $_ is the ioctl request

    if (/isRestricted/) {
	return 0;
    }
    elsif (/isService/) {
	return 1;
    }
    elsif (/ModuleName/) {
	return "Quiz";
    }
    elsif (/ModuleInfo/) {
	return "This module builds and processes quizzes and multiple-choice exams.";
    }
    elsif (/Dependencies/) {
	return ["Forms"];
    }
    elsif (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/DynContentParam/) {
	$ml = &get_obj("ML");
	my $forms = $this->my_forms();
	if ($forms->count) {
	    my $out .= $ml->strong("Quizzes:");
	    my $option;
	    while (my $f = $forms->next) {
		$option .= $ml->option($f->name,{value=>"quiz=".$f->id});
	    }
	    $out .= $ml->select($option,{name=>"param"});
	    return $out;
	}
	return undef;  # no forms; use blank parameter field
    }
    elsif (/ToDo/) {
	return \&todo;
    }
}

# Control Panel : browse and export responses

sub ctrl_panel {
    my $this = shift;
    $Forms = $this;

    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    # so inherited methods also use our package globals
    $Modules::Forms::ml or $Modules::Forms::ml = $ml;
    $Modules::Forms::ui or $Modules::Forms::ui = $ui;
    # datepicker stuff #### FIXME

    my $out;
    $out .= $this->show_location();

    my $cmd = $this->{query}{cmd};
    if ($this->{query}{response}) {
	if ($cmd eq "edit_response") {
	    $out .= $this->edit_response($this->{form}->id,$this->{query}{response});
	    $out .= $ml->p($ui->Button(label=>"back to response",url=>$this->link(cmd=>"responses"),faicon=>"back"));
	}
	elsif ($cmd eq "del") {
	    my $r = new Modules::Quiz::Response(id=>$this->{query}{response});
	    $r->delete();
	    $ml->location($this->link(cmd=>undef,response=>undef,__plaintext=>1));
	}
	else {
	    $out .= $this->show_form_toolbar();
	    $out .= $this->show_response($this->{query}{response});
	    $out .= $ml->p($ui->Button(label=>"All responses",url=>$this->link(response=>undef),faicon=>"back"));
	}
    }
    elsif ($this->{question}) {
	$out .= $this->show_question();
    }
    elsif ($this->{form}) {
	my $f = $this->{form};
	if ($this->{input}{copy}) {
	    return $this->copy_question()
	}
	$out .= $this->show_form_toolbar($f);
	if ($cmd eq "export") {
	    $out .= $this->export_responses($f);
	}
	elsif ($cmd eq "preview") {
	    my $preview = $ui->AlertBox(title=>"Warning",pane=>"Your website's stylesheet may impose a different look for your forms. This preview does not necessarily reflect how the form will be styled in its final published form.",state=>1,tone=>"warning");
	    $preview .= $f->preview();# revision=>"newest");
	    $out .= $ui->BasicBox(title=>"Preview",pane=>$preview);
	}
	elsif ($cmd eq "akey") {
	    $out .= $this->answer_key($f);
	}
	elsif ($cmd eq "responses") {
	    $out .= $this->show_responses($f);
	}
	elsif ($cmd eq "filter") {
	    $out .= $this->filter_responses($f);
	}
	elsif ($cmd eq "questions") {
	    $out .= $this->show_form_questions($f);
	}
	elsif ($cmd eq "summary") {
	    $out .= $this->show_summary($f);
	}
	elsif ($cmd eq "newq") {
	    $out .= $this->new_question_form();
	}
	elsif ($cmd eq "conf") {
	    $out .= $this->configure($f);
	}
	elsif ($cmd eq "copy") {
	    $out .= $this->copy_form($f);
	}
	elsif ($cmd eq "update") {
	    $out .= $this->update($f);
	}
	elsif ($cmd eq "reply") {
	    $out .= $this->reply($f);
	}
	elsif ($cmd eq "reorder") {
	    $out .= $this->reorder();
	}
	elsif ($cmd eq "del") {
	    $f->delete();
	    $ml->redirect($this->link(cmd=>undef,id=>undef,__plaintext=>1));
	    return;
	}
	else {
	    $out .= $this->show_form($f);
	}
    }
    else {
	if ($cmd eq "newform") {
#	    $out .= $this->new_form_wizard();
	    $out .= $this->new_form();
	}
	else {
	    $out .= $this->show_forms();
	}
    }
    return $out;
}

sub show_forms {
    my $this = shift;
    my $forms = $this->my_forms();
    my $r = new ExSite::ReportBuilder(title=>"Quizzes",width=>"100%");
    $r->headers(["ID","Quiz","Questions","Responses","Section","Reports"]);
    while (my $f = $forms->next) {
	my $n_response = $f->count_responses();
	my $opt;
	if ($n_response) {
	    $opt .= 
#		$ui->Button(type=>"link-button",label=>"grades",size=>"s",url=>$this->link(cmd=>"grades",id=>$f->id),faicon=>"graduation-cap").
		$ui->Button(type=>"link-button",label=>"stats",size=>"s",url=>$this->link(cmd=>"summary",id=>$f->id),faicon=>"chart").
		$ui->Button(type=>"link-button",label=>"responses",size=>"s",url=>$this->link(cmd=>"responses",id=>$f->id),faicon=>"list").
		$ui->Button(type=>"link-button",label=>"export",size=>"s",url=>$this->link(cmd=>"responses",export=>"xls",id=>$f->id),faicon=>"download");
	}
	$r->push($f->id,
		 $ml->a($f->label,{href=>$this->link(id=>$f->id())}),
		 $f->questions->count(),
		 $n_response,
		 $f->my_section->label,
		 $opt)
    }
    $r->tools($ui->Button(type=>"link-button",label=>"new form",size=>"s",url=>$this->link(cmd=>"newform",id=>undef),tone=>"good",faicon=>"new"));
    return $r->make();
}

sub show_location {
    my $this = shift;
    my $c = new ExSite::Content();
    my $obj = $c->get_content_obj($this->{input}{id});
    my @path;
    if ($obj->exists) {
	do {
	    if ($obj->subtype() eq "quiz") {
		$this->{form} = $obj;
		unshift @path, $ml->a($obj->label,{href=>$this->link(id=>$obj->id,cmd=>undef,response=>undef)});
	    }
	    elsif ($obj->subtype() eq "quiz_question") {
		$this->{question} = $obj;
		unshift @path, $ml->a($obj->label,{href=>$this->link(id=>$obj->id,cmd=>undef,response=>undef)});
	    }
	    else {
		unshift @path, $obj->label;
	    }
	    $obj = $obj->parent;
	} while ($obj->defined);
    }
    return (@path > 0) ? $ui->PathBar(links=>\@path) : undef;
}

sub my_forms {
    my $this = shift;
    my $s = $this->get_section();
    my $tree = $s->get_content_tree();
    my @form = $tree->find({type=>$s->isubtype("quiz")});
    my $forms = new ExSite::ObjectList(class=>"Modules::Quiz::Quiz",type=>"content",list=>\@form);
    $forms->sort("title");
    return $forms;
}

sub show_form {
    my ($this,$f) = @_;
    my $db = $share{DB};
    my $rpt = new ExSite::ReportBuilder(title=>$f->title());
    $rpt->headers(["Quiz #","Questions","Responses","Status","Last Modified"]);
    $rpt->data(
	       $f->id(),
	       $f->count_questions,
	       $f->count_responses,
	       $f->showdata("status"),
	       $f->showdata("mtime")
	       );
    return $rpt->make;
}

sub show_form_toolbar {
    my ($this,$f) = @_;
    $f or $f = $this->{form};
    my $n_response = $f->count_responses;
    my $fid = $f->id;

    return $ui->ToolBar(
	tools=>[
	    {label=>"stats",url=>$this->link(id=>$fid,response=>undef,cmd=>"summary"),faicon=>"chart"},
	    {label=>"responses",url=>$this->link(id=>$fid,response=>undef,cmd=>"responses"),faicon=>"list"},
	    {label=>"filter",url=>$this->link(id=>$fid,response=>undef,cmd=>"filter"),faicon=>"filter"},
	    undef,
	    {label=>"preview",url=>$this->link(id=>$fid,response=>undef,cmd=>"preview"),faicon=>"view"},
	    {label=>"configure",url=>$this->link(id=>$fid,response=>undef,cmd=>"conf"),faicon=>"conf"},
	    {label=>"questions",url=>$this->link(id=>$fid,response=>undef,cmd=>"questions"),faicon=>"help"},
	    {label=>"answer key",url=>$this->link(id=>$fid,response=>undef,cmd=>"akey"),faicon=>"check"},
#	    {label=>"layout",url=>$this->link(id=>$fid,response=>undef,cmd=>"update"),faicon=>"template"},
	    {label=>"reply",url=>$this->link(id=>$fid,response=>undef,cmd=>"reply"),faicon=>"comment"},
#	    {label=>"order",url=>$this->link(id=>$fid,response=>undef,cmd=>"reorder"),faicon=>"sort"},
#	    {label=>"add",url=>$this->link(id=>$fid,response=>undef,cmd=>"newq"),faicon=>"add"},
	    undef,
	    {label=>"copy quiz",url=>$this->link(id=>$fid,response=>undef,cmd=>"copy"),faicon=>"copy"},
	    {label=>"delete",url=>$this->link(id=>$fid,cmd=>"del"),faicon=>"delete",tone=>"bad",confirm=>($n_response > 0 ? "WARNING: deleting this form will also discard the $n_response responses\nthat have been received so far." :"Really delete this form and all of its questions?")},
	]
	);
}

sub show_question_toolbar {
    my ($this) = @_;
    return $ui->ToolBar(
	tools=>[
	    {label=>"back to form",url=>$this->link(id=>$this->{form}->id,cmd=>"questions"),faicon=>"back"},
	    undef,
	    {label=>"preview",url=>$this->link(cmd=>"preview"),faicon=>"view"},
	    {label=>"configure",url=>$this->link(cmd=>"conf"),faicon=>"conf"},
#	    {label=>"layout",url=>$this->link(cmd=>"update"),faicon=>"edit"},
	    {label=>"delete",url=>$this->link(cmd=>"del"),tone=>"bad",confirm=>"WARNING: deleting this question will also discard any answers that have been received for it.",faicon=>"delete"},
	]
	);
}

sub show_form_questions {
    my ($this,$f) = @_;
    my $db = $share{DB};
    my $out;

    # questions

    my $rpt2 = new ExSite::ReportBuilder(title=>"Questions",width=>"100%");
    $rpt2->nodata("No questions defined.");
    $rpt2->foot("Click on a question name to reconfigure that question.");
    $rpt2->headers(["Question ID","Question","Format","Answer","Last Modified"]);
    my $qlist = $f->questions();
    if ($qlist) {
	$qlist->reset();
	while (my $q = $qlist->next()) {
	    $rpt2->push(
		$q->id(),
		$ml->a($q->label(),{href=>$this->link(cmd=>undef,id=>$q->id())}),
		$q->format(),
		$q->correct_answer(),
		$q->showdata("mtime")
		);
	}
    }
    $rpt2->tools(
	$ui->Button(type=>"link-button",label=>"order",url=>$this->link(cmd=>"reorder"),size=>"s",faicon=>"sort").
	$ui->Button(type=>"link-button",label=>"add question",url=>$this->link(cmd=>"newq"),size=>"s",tone=>"good",faicon=>"add")
	);
    $out .= $rpt2->make;
    return $out;
}

sub answer_key {
    my ($this,$f) = @_;
    my $out;
    if ($f->allow("edit")) {
	my $in = new ExSite::Input;
	my $post = $in->post();
	if (scalar keys %$post > 0) {
	    # new answer key!
	    my $questions = $f->questions();
	    $questions->reset();
	    while (my $q = $questions->next) {
		my $name = $q->name();
		if ($post->{$name} && $q->is_markable) {
		    $q->meta->set("answer",$post->{$name});
		}
	    }
	    $out .= $ui->SuccessMsg("Answer key updated!");
	    $in->delete("_formkey"); # blocks re-processing in preview()
	}
	else {
	    $out .= $ui->HelpMsg("You can update the answer key by filling in the correct answers and submitting.");
	}
    }
    else {
	$out .= $ui->ErrorMsg("Note: you do not have permission to alter the answer key.");
    }
    my $akey = $f->answer_key();
    $out .= $f->preview(data=>$akey,action=>$this->link()); # real post!!!
    return $out;
}

sub new_question_form {
    my $this = shift;
    my $out = $ml->h1("Add a question");
    my $ml = &get_obj("ML");
    my $post = $this->{post};
    my $query = $this->{query};
    if (scalar keys %$post > 0) {
	$out .= $this->{form}->add_question(%$post);
    }

    my @qtype = split /\|/,$share{DB}{map}->regexp("list:quiz_input_format");
    my $br = $ml->br;
    my $arr = $ui->FAIcon("left"); # left arrow
    my $f = new ExSite::FormBuilder(method=>"post",action=>$this->link(cmd=>"newq",id=>$this->{input}{id}));
    $f->input(prompt=>"Question",name=>"prompt",type=>"text",size=>60,required=>1);
    $f->input(prompt=>"Type",name=>"format",type=>"select",options=>\@qtype,required=>1,tooltip=>"NOTE: only multiple-choice questions (radio, select) will be graded");
    $f->input(prompt=>"Answer choices (radio, select types only)",
	      name=>"options",
	      type=>"textarea",
	      rows=>6,cols=>60,
	      tooltip=>"List your multiple-choice answers separated with a bar, like this: yes|no");
    $f->input(prompt=>"Correct answer",name=>"answer",type=>"text",tooltip=>"One of the answer choices from the previous question");
    $f->input(prompt=>"Score",type=>"text",name=>"score",size=>10,tooltip=>"How many marks this question is worth");
    $f->input(prompt=>"Input name:",type=>"text",name=>"name",size=>20,tooltip=>"This is the name used by the computer to track this question. It should consist of alphanumeric chararacters plus underscores only");
    $f->input(prompt=>"Required",type=>"checkbox",name=>"required",tooltip=>"You cannot submit the quiz for grading without answering this question.");
    $f->buttons(submit=>"+ Add question");
    $f->question_template("required",$ml->p("[[input]] [[prompt]]"));
    $out .= $f->make();
    return $out;
}

# get_question_tree: display all questions in all forms;
# - uses jquery to compose AJAX calls to fetch question previews
# - see Forms.js, copy_question()
# - clicking on a questionfetches a preview and displays it in a css popup
# - preview has a confirm button, clicking that actually executes the copy
# - once copied, we mark the question as copied using strikethrough

sub get_question_tree {
    my $this = shift;
    my $f = $this->{form};
    my $tree = $f->get_content_tree();
    my @form = $tree->find({type=>$f->isubtype("form")},$f->my_section->id);
#    my $out = $ml->script("\nvar modpath = '$config{server}{CGIpath}/$config{prog}{admin}/Forms?';\n");
    my $nq;
    my $out;
    my (@head,@pane);
    foreach my $fdata (@form) {
	next if ($fdata->{content_id} == $f->id);
	my $form = new Modules::Quiz::Quiz(data=>$fdata);
	push @head, $form->title;
	my $questions = $form->questions();
	my $qlist;
	while (my $q = $questions->next) {
	    $nq++;
	    my $pane = $q->show();
	    $pane .= $ml->p($ui->Button(label=>"add this question",url=>"#",tone=>"good",class=>"copyQuestion",faicon=>"add",id=>"qf_".$q->id."_".$f->id));
	    $qlist .= $ml->div(
		$ui->Popup(label=>$q->label,id=>"addq_".$q->id,title=>"Add question",pane=>$ml->div($pane,{id=>"questionPopup".$q->id}))
		);
	}
	push @pane, $qlist;
    }
    if ($nq) {
	$out .= $ui->AccordionBox(titles=>\@head,panes=>\@pane);
	$out .= $ml->script("\nvar modpath = '$config{server}{CGIpath}/$config{prog}{admin}/Forms?';\n");
    }
    else {
	$out .= $ml->span("Sorry, there are no questions to copy.",{class=>"error"});
    }
    return $out;
}

sub show_response {
    my ($this,$response_id) = @_;
    my $r = new Modules::Quiz::Response(id=>$response_id);
    if ($this->{input}{cmd} eq "del") {
	$r->delete();
	$ml->redirect($this->link(cmd=>"responses",response=>undef,__plaintext=>1));
	return;
    }
    else {
	return $r->show(
	    admin=>1,
	    tools=>
	    $ui->fatool("edit",url=>$this->link(cmd=>"edit_response")).
	    $ui->fatool("delete",confirm=>'Really delete this response?',url=>$this->link(cmd=>"del"),tone=>"bad")
	    );
    }
}

sub edit_response {
    my ($this,$form_id,$response_id,$action) = @_;
    my $r = new Modules::Quiz::Response(id=>$response_id);
    if ($r->is_editable()) {
	my $f = $r->form;
	if ($f && $f->id == $form_id) {
	    return $f->show(response=>$response_id,action=>$action);
	}
	return $this->error("form - response mismatch");
    }
    return $this->error("Permission denied.");
}

# new form non-wizard

sub new_form {
    my ($this) = @_;
    my $out;
    my $c = new ExSite::Content();
    my $post = $this->{post};
    if (scalar keys %$post > 0) {
	if (! $post->{parent} && ! $post->{other_parent}) {
	    $out = $this->error("You must specify a location for the new form.");
	}
	else {
	    my $form_id = $c->new_content(
		type=>$c->isubtype("form"),
		title=>$post->{title},
		access=>$post->{access},
		parent=>$post->{parent} || $post->{other_parent});
	    if ($form_id) {
		$ml->location($this->link(__plaintext=>1,id=>$form_id,cmd=>"newq"));
		return;
	    }
	    else {
		$out .= &ExSite::Config::show_diagnostics();
	    }
	}
    }
    $out .= $ml->h1("New Form");
    my $f = new ExSite::FormBuilder();
    $f->input(type=>"text",name=>"title",prompt=>"Title",size=>40,required=>1,value=>$post->{title});
    $f->input(type=>"select",name=>"access",prompt=>"Access",options=>[[0,"public"],[1,"users"],[2,"members"],[5,"executives"]],nullvalue=>"== select ==",required=>1,value=>$post->{access});
    
    # select parent
    my $db = $share{DB};
    my @parent;
    foreach my $type ($db->fetch_match("content_rel",{type=>$c->isubtype("form")})) {
	push @parent, $db->fetch_match("content",{type=>$type->{under}});
    }
    my $np;
    my @opt;
    foreach my $pdata (reverse $db->sort_rows("content",\@parent,"ctime")) {
	# show newer locations first
	$np++;
	my $p = $c->get_content_obj($pdata);
	push @opt, { text=>$p->subtype().": ".$p->getdata("label"), value=>$p->id };
	last if ($np >= 50);
    }
    $f->input(type=>"select",name=>"parent",prompt=>"Location",options=>\@opt,nullvalue=>"== select ==");
    $f->input(type=>"text",name=>"other_parent",prompt=>"Or, enter content ID of form location:",size=>10);
    
    $out .= $f->make();
    return $out;
}

sub get_response_report {
    my ($this,$form,$options,$match) = @_;
    $match or $match = {};
    my %param; # match parameters that are actually set
    foreach my $key (keys %$match) { 
	if ($match->{$key}) { $param{$key} = $match->{$key}; }
    }
    
    # organize the response data
    my $answers = $form->get_all_answers();
    my %response;
    foreach my $a (@$answers) {
	$response{$a->{response_id}}{$a->{content_id}} = $a;
    }

    # generate the report
    my $rpt = new ExSite::ReportBuilder(title=>"Responses - ".$form->name);
    $rpt->set("dynamic",1);
    my @head = $options ? ('Options') : ();
    if ($config{QA}{report_form_name}) {
	push @head, 'Form';
    }
    push @head, qw(Response Date By Status);
    push @head, $this->question_labels($form);
    $rpt->headers(\@head);
    $rpt->tools("Export: ".
		$ml->a("excel",{href=>$this->link(export=>"xls",%param)})." ".
		$ml->a("csv",{href=>$this->link(export=>"csv",%param)})." ".
		$ml->a("html",{href=>$this->link(export=>"html",%param)})
		);
    my %member;
  RESPONSE:
    foreach my $rid (sort {$b <=> $a} keys %response) { # most recent first
	my @qid = keys %{$response{$rid}};
	my $r1 = $response{$rid}{$qid[0]}; # 1st answer in response

	# date filter
	my $date = new ExSite::Time($r1->{ctime},"sql_timestamp");
	if ($match->{filter_date_start}) {
	    # abort if start date is after this response
	    next if ($date->diff($match->{filter_date_start},"iso_date") > 0);
	}
	if ($match->{filter_date_end}) {
	    # abort if end date is before this response
	    next if ($date->diff($match->{filter_date_end},"iso_date") < 0);
	}

	my @data;
	if ($options) {
	    push @data, 
		 $ui->fatool("view",url=>$this->link(response=>$rid)).
		 $ui->fatool("edit",url=>$this->link(cmd=>"edit_response",response=>$rid)).
		 $ui->fatool("delete",confirm=>"Really delete response $rid?",url=>$this->link(cmd=>"del",response=>$rid),tone=>"bad");
	}
	if ($config{QA}{report_form_name}) {
	    push @data, $form->name;
	}
	my $user;
	my $uid = $r1->{uid};
	if ($uid) {
	    if ($member{$uid}) {
		$user = $member{$uid};
	    }
	    else {
		$user = $share{DB}->user_name($uid);
		$member{$uid} = $user;
	    }
	}
	push @data, $rid, $share{DB}->show_data_noauth("response","ctime",$r1->{ctime},$rid,"datetime"), $user, $Modules::Quiz::Response::rstatus[$r1->{status}];
	my $questions = $form->questions;
	$questions->reset;
	while (my $q = $questions->next) {
	    next if (! $q->is_question); # skip labels/section breaks
	    if (scalar keys %$match > 0) {
		my $qname = $q->name;
		if ($match->{$qname}) {
		    # abort row if no match
		    next RESPONSE if ($response{$rid}{$q->id}{answer} !~ /$match->{$qname}/i);
		}
	    }
	    my $datatype = $q->datatype();
	    my $answer;
	    if ($datatype) {
		# use show_data for its security 
		# (eg. masking tags)
		$answer = $share{DB}->show_data_noauth("answer",
						       "value",
						       $response{$rid}{$q->id}{answer},
						       $response{$rid}{$q->id}{qa_answer_id},
						       $datatype);
	    }
	    elsif ($q->format eq "file") {
		my $file = $response{$rid}{$q->id}{answer};
		if (-e $file) {
		    $file =~ s/^$config{server}{fileroot}//;
		    $answer = $ml->a($file,{href=>"$config{server}{CGIpath}/$config{prog}{file}$file",target=>"_blank"});
		}
		else {
		    $answer = "$file (not found)";
		}
	    }
	    else {
		$answer = &html_escape($response{$rid}{$q->id}{answer});
	    }
	    push @data, $answer;
	}
	$rpt->push(@data);
    }
    return $rpt;
}

sub show_summary {
    my ($this,$f) = @_;
    my $out;
    my $r = $this->get_summary_report($f);
    my $fmt = $this->{input}{export};
    if ($fmt =~ /csv/) {
	$ml->cancel();
	my $formid = $f->id;
	print "Content-type: text/comma-separated-values\ncontent-disposition: attachment; filename=responses-$formid.csv\n\n";
	print $r->export("csv");
    }
    elsif ($fmt =~ /html/) {
	$ml->cancel();
	$r->set("dynamic",0);
	$r->tools(undef);
	print "Content-type: text/html\n\n";
	print $r->make();
    }
    elsif ($fmt =~ /xls/) {
	$ml->cancel();
	my $formid = $f->id;
	print "Content-type: application/vnd.ms-excel\n";
	print "Content-disposition: attachment; filename=responses-$formid.xls\n\n";
	$r->export("excel");
    }
    else {
	# summarize grades
	my $answers = $f->get_all_answers();
	my (%done,%status,$total);
	foreach my $a (@$answers) {
	    if (! $done{$a->{response_id}}) {
		$done{$a->{response_id}} = 1;
		$total++;
		my $stat = $Modules::Quiz::Response::rstatus[$a->{status}];
		$status{$stat}++;
		if ($stat !~ /pass|fail/) { $status{other}++; }
	    }
	}
	$out .= $ui->Figure(img=>"//chart.googleapis.com/chart?cht=bvs&chd=t:$status{passed},$status{failed},$status{other}&chxl=0:|pass|fail|other&chxt=x,y&chs=200x150&chco=4D89F9&chbh=35,10&chds=0,$total",caption=>"% breakdown of results");
	# breakdown of answers
	$out .= $r->make();

    }
    return $out;
}

# simplified summary report: include checkmarks by correct answer, no averages

sub get_summary_report {
    my ($this,$form) = @_;

    my $answers = $form->get_all_answers();
    my $rpt = new ExSite::ReportBuilder(title=>"Response Summary - ".$form->name,
					width=>"100%",
					cwidth=>[undef,undef,undef,undef,"100"]
	);
    my @head;
    push @head, ("Question", "Answer", "Responses", "\%", "Chart");
    $rpt->headers(\@head);
    $rpt->tools("Export: ".
		$ml->a("excel",{href=>$this->link(export=>"xls")})." ".
		$ml->a("csv",{href=>$this->link(export=>"csv")})." ".
		$ml->a("html",{href=>$this->link(export=>"html")})
		);
    my %summary;
    my %response;
    my $n_response = 0;
    if (scalar @$answers > 0) {
	foreach my $a (@$answers) {
	    my $fmt = $a->{format};
	    $response{$a->{response_id}} = 1;
	    next if ($fmt eq "label" || $fmt eq "preformatted");
	    if ($fmt =~ /multiselect|checklist/) {
		# multiselect - may be several answers combined
		my @ans = split /$config{form}{multi_sep}/, $a->{answer};
		foreach my $ans (@ans) {
		    $summary{$a->{label}}{$ans}++;
		}
	    }
	    elsif ($fmt =~ /select|radio|checkbox/) {
		# fixed format - bin the answers
		$summary{$a->{label}}{$a->{answer}}++;
	    }
	    elsif ($fmt =~ /number|range/) {
		# numeric - bin the answers??
		$summary{$a->{label}}{$a->{answer}}++;
	    }
	    else {
		# freeform - simply count the answers
		$summary{$a->{label}}{answered}++;
	    }
	}
	$n_response = scalar keys %response;
	my $questions = $form->questions();
	while (my $q = $questions->next()) {
	    my @data;
	    push @data, $q->label;
	    my $fmt = $q->format();
	    next if ($fmt =~ /label|preformatted/);
	    if ($fmt =~ /select|checklist|radio|number|range|checkbox/) {
		# fixed format - display each bin separately
		my @val = $q->allowed_answers();
		my $first = 1;
		foreach my $v (@val) {
		    next if (!$v); # exclude blank answers
		    next if (!$summary{$q->label}{$v}); # exclude unused answers
		    my @data;
		    push @data, $first ? $q->label : "";
		    $first = 0;
		    my $n = $summary{$q->label}{$v} || 0;
		    my $pct = int(($n / $n_response) * 100);
		    my $nhash = $n ? int(($n / $n_response) * 10) + 1 : 0;
#--
		    my $opt = $q->emeta("answer") eq $v ? $ml->img(undef,{src=>"$config{server}{HTMLpath}/_ExSite/images/icons/approve.png"})." ".$v : $v;
#--
		    push @data, $opt, 
		    $ml->div($n,{class=>"num"}),
		    $ml->div("$pct\%",{class=>"num"});
		    push @data, $ml->div("#" x $nhash,{class=>"bar",style=>"height:10px;width:${pct}px"});
		    $rpt->push(@data);
		}
	    }
	    else { #if ($fmt =~ /^(string|textarea|password)$/) {
		# freeform
		my $n = $summary{$q->label}{answered} || 0;
		my $pct = int(($n / $n_response) * 100);
		my $nhash = int(($n / $n_response) * 10);
		push @data, 
		$ml->em("[all non-blank answers]"),
		$ml->div($n,{class=>"num"}),
		$ml->div("$pct\%",{class=>"num"});
		push @data, $ml->div("#" x $nhash,{class=>"bar",style=>"height:10px;width:${pct}px"});
		$rpt->push(@data);
	    }
	}
    }
    $rpt->foot("$n_response responses received.");
    return $rpt;
}

1;
