package Modules::Forms;

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
#
#  This modules processes user-configurable forms.
#
#----------------------------------------------------------------------------

use strict;

use ExSite::Config;
use ExSite::Misc;
use ExSite::ML;
use ExSite::URI;
use ExSite::Util;
use ExSite::Crypt;
use ExSite::Object;
use ExSite::ObjectList;
use ExSite::Wizard;
use ExSite::UI;
use Modules::Content;
use Modules::Forms::Form;

use vars qw(@ISA $ml $ui $Forms $maxrec);
@ISA = qw(Modules::Content);

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
	    my $form = new Modules::Forms::Form(id=>$form_id);
	    $out = $form->show(action=>$action);
	}
    }
    elsif ($in->{form}) {
	my $form = new Modules::Forms::Form(id=>$in->{form});
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
	return "Forms";
    }
    elsif (/ModuleInfo/) {
	return "This module builds and processes user-configurable forms.";
    }
    elsif (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/DynContentParam/) {
	$ml = &get_obj("ML");
	my $forms = $this->my_forms();
	if ($forms->count) {
	    my $out .= $ml->strong("Forms:");
	    my $option;
	    while (my $f = $forms->next) {
		$option .= $ml->option($f->name,{value=>"form=".$f->id});
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
#    $this->{section_id} = $this->get_section_id();
#    if (! $this->{section_id} && $config{Forms}{admin_scope} ne "global") {
#	return $this->set_section_id();
#    }

    $ml = &get_obj("ML");
    $ui = &get_obj("UI");

    # datepicker stuff #### FIXME
    my $out = $ui->js;
    $out .= &insert_js("httprequest.js");
    $out .= &insert_js("jquery.treeview.js");
    $out .= &insert_js("jquery.magnific-popup.min.js");

    #$out .= $ml->script("\$(function() {\n  \$( '.accordion' ).accordion();\n});\n");
    $out .= &insert_css("magnific-popup.css");
    $out .= $this->show_location();

    my $cmd = $this->{query}{cmd};
    if ($this->{query}{response}) {
	if ($cmd eq "edit_response") {
	    $out .= $this->edit_response($this->{form}->id,$this->{query}{response});
	    $out .= $ml->p($ui->Button(label=>"back to response",url=>$this->link(cmd=>"responses"),faicon=>"back"));
	}
	elsif ($cmd eq "del") {
	    my $r = new Modules::Forms::Response(id=>$this->{query}{response});
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
    my $r = new ExSite::ReportBuilder(title=>"Forms",width=>"100%");
    $r->headers(["Form","Title","Questions","Responses","Section","Reports"]);
    while (my $f = $forms->next) {
	my $n_response = $f->count_responses();
	my $opt;
	if ($n_response) {
	    $opt .= 
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
	    if ($obj->subtype() eq "form") {
		$this->{form} = $obj;
		unshift @path, $ml->a($obj->label,{href=>$this->link(id=>$obj->id,cmd=>undef,response=>undef)});
	    }
	    elsif ($obj->subtype() eq "question") {
		$this->{question} = $obj;
		unshift @path, $ml->a($obj->label,{href=>$this->link(id=>$obj->id,cmd=>undef,response=>undef)});
	    }
	    elsif ($obj->subtype() eq "section") {
		unshift @path, $ml->a($obj->label,{href=>$this->link(id=>undef,cmd=>undef,response=>undef)});
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
    my @form = $tree->find({type=>$s->isubtype("form")});
    my $forms = new ExSite::ObjectList(class=>"Modules::Forms::Form",type=>"content",list=>\@form);
    $forms->sort("title");
    return $forms;
}

sub show_form {
    my ($this,$f) = @_;
    my $db = $share{DB};
    my $rpt = new ExSite::ReportBuilder(title=>$f->title());
    $rpt->headers(["Form #","Questions","Responses","Status","Last Modified"]);
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
	    {label=>"export",url=>$this->link(id=>$fid,response=>undef,cmd=>"responses",export=>"xls"),faicon=>"export"},
	    undef,
	    {label=>"preview",url=>$this->link(id=>$fid,response=>undef,cmd=>"preview"),faicon=>"view"},
	    {label=>"configure",url=>$this->link(id=>$fid,response=>undef,cmd=>"conf"),faicon=>"conf"},
	    {label=>"layout",url=>$this->link(id=>$fid,response=>undef,cmd=>"update"),faicon=>"template"},
#	    {label=>"layout",url=>$this->link(id=>$fid,response=>undef,cmd=>"template"),faicon=>"template"},
	    {label=>"reply",url=>$this->link(id=>$fid,response=>undef,cmd=>"reply"),faicon=>"comment"},
	    {label=>"questions",url=>$this->link(id=>$fid,response=>undef,cmd=>"questions"),faicon=>"help"},
	    {label=>"order",url=>$this->link(id=>$fid,response=>undef,cmd=>"reorder"),faicon=>"sort"},
	    {label=>"add",url=>$this->link(id=>$fid,response=>undef,cmd=>"newq"),faicon=>"add"},
	    undef,
	    {label=>"copy form",url=>$this->link(id=>$fid,response=>undef,cmd=>"copy"),faicon=>"copy"},
	    {label=>"delete",url=>$this->link(id=>$fid,cmd=>"del"),faicon=>"delete",tone=>"bad",confirm=>($n_response > 0 ? "WARNING: deleting this form will also discard the $n_response responses\nthat have been received so far." :"Really delete this form and all of its questions?")},
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
    $rpt2->headers(["Question ID","Question","Format","Last Modified"]);
    my $qlist = $f->questions();
    if ($qlist) {
	$qlist->reset();
	while (my $q = $qlist->next()) {
	    $rpt2->push(
		$q->id(),
		$ml->a($q->label(),{href=>$this->link(cmd=>undef,id=>$q->id())}),
		$q->format(),
		$q->showdata("mtime")
		);
	}
    }
    $rpt2->tools($ui->Button(type=>"link-button",label=>"add question",url=>$this->link(cmd=>"newq"),size=>"s",tone=>"good",faicon=>"add"));
    $out .= $rpt2->make;
    return $out;
}

# update: update the revision, which is understood to be a layout

sub update {
    my ($this,$c,%opt) = @_;
    if (! $c->allow("update")) {
	return $this->error("Sorry, you do not have permission to update this ".$c->subtype().".");
    }
    my $out;
    my $name = "layout";
    if (scalar keys %{$this->{post}} > 0) {
	my %post = $share{DB}->parse_parts(%{$this->{post}});
	my %rev = (data=>$post{$name},format=>"text");
	if ($this->{post}{_save} =~ /draft/i) {
	    $rev{status} = $ExSite::Workflow::status{draft};
	}
	elsif ($this->{post}{_save} =~ /reset/i) {
	    if ($rev{data}) {
		$rev{data} = "";
		$rev{force} = 1;
	    }
	    $out .= $ui->SuccessMsg("Layout reset back to default.");
	}
	if ($rev{data} || $c->has_revisions()) {
	    if ($c->revise(%rev)) {
		$out .= $ui->SuccessBox(pane=>$c->title." layout updated.");
		#$ml->location($this->link(__plaintext=>1,cmd=>"preview"));
	    }
	    else {
		$out .= $ui->ErrorBox(pane=>$c->show_diagnostics("error","html"));
	    }
	}
    }
    $out .= $ml->h1("Layout for ".$c->subtype." ".$ml->em($c->title));
    $c->load_revision("newest");
    my $db = $share{DB};
    $db->input_htmleditor(
	prompt=>"Layout",
	name=>$name,
	value=>$c->get_html(),
	editor_height=>350,
	editor_width=>550
	);
    $db->form->set("buttons",
		   $ml->input(undef,{type=>"submit",value=>"Save"}).
		   $ml->input(undef,{type=>"submit",name=>"_save",value=>"Save as draft"}).
		   $ml->input(undef,{type=>"submit",class=>"delete",name=>"_save",value=>"Reset layout"}).
		   $ml->input(undef,{type=>"button",value=>"Cancel",class=>"formButton cancel",onclick=>"javascript:history.back()"}).
		   $ml->input(undef,{type=>"reset"}));
    $out .= $db->form->make();

    if ($c->subtype eq "form") {
	my $br = $ml->br;
	my ($simple_template,$table_template,$enhanced_template);
	my $nq;
	while (my $q = $c->questions->next()) {
	    $nq++;
	    my $rowclass = $nq % 2 ? "A" : "B";
	    my $qname = $q->name();
	    my $qtemplate = $q->layout();
	    $qtemplate =~ s/\[\[prompt\]\]/\[\[$qname:prompt\]\]/;
	    $qtemplate =~ s/\[\[input\]\]/\[\[$qname:input\]\]/;
	    $qtemplate =~ s/\[\[rowclass\]\]/$rowclass/;
	    $simple_template .= $qtemplate;
	    
#$ml->p("[[$qname:prompt]]${br}[[$qname:input]]");
	    $table_template .= $ml->tr(
		$ml->td("[[$qname:prompt]]",{class=>"prompt"}).
		$ml->td("[[$qname:input]]",{class=>"input"})
		);
	    $enhanced_template .= $ml->div(
		$ml->div("[[$qname:prompt]]",{class=>"Forms_prompt"}).
		$ml->div("[[$qname:input]]",{class=>"Forms_input"}),
		{class=>"Forms_question $rowclass"});
	}
	$table_template = $ml->table($table_template,{class=>"Form"});
	$enhanced_template = $ml->div($enhanced_template,{class=>"Form"});
	my @titles = ("Basic Layout","Two-column Table");
	my @panes = ($simple_template,$table_template);
	my @states = (0,0);
	my @matrix_template = $c->make_layout();
	if (scalar @matrix_template == 1 && $matrix_template[0] && $matrix_template[0] ne $simple_template) {
	    push @titles, "Enhanced Layout with Grouping/Matrixes";
	    push @panes, $matrix_template[0];
	    push @states, 0;
	}
	
	my $br = $ml->br;
	$out .= $ml->h2("Instructions");
	$out .= $ml->p("Use merge codes to place the prompt and input fields for each of your form inputs. To place the input field, use ".$ml->code("[[name:input]]").". To place the prompt/label string, use ".$ml->code("[[name:prompt]]")." - replace \"name\" with the short name of the input field.");
	$out .= $ml->p("Example layouts are shown below (click to open). You can copy these using copy-paste, and then modify to suit.");

	$out .= $ui->AccordionBox(titles=>\@titles,
				  panes=>\@panes,
				  states=>\@states,);
    }
    else {
	$out .= $ui->HelpBox(title=>"Instructions",
			     size=>"m",
			     pane=>"Use ".$ml->code("[[prompt]]")." and ".$ml->code("[[input]]")." merge codes to place the prompt and input fields for this question. To replace the question with longer or more formatted text, enter that text and formatting directly, in place of the ".$ml->code("[[prompt]]")." code.");
    }

    return $out;
}

# reply - the response screen after a form is submitted

sub reply {
    my ($this,$f,%opt) = @_;
    my $rcpt = $f->my_content("_reply");
    if (! ($rcpt||$f)->allow("update")) {
	return $this->error("Sorry, you do not have permission to update the form reply message.");
    }
    my $out;
    my $deleted;
    my $name = "replymsg";
    if (scalar keys %{$this->{post}} > 0) {
	my %post = $share{DB}->parse_parts(%{$this->{post}});
	my %rev = (data=>$post{$name},format=>"text");
	if ($this->{post}{_save} =~ /draft/i) {
	    $rev{status} = $ExSite::Workflow::status{draft};
	}
	elsif ($this->{post}{_save} =~ /delete/i) {
	    if ($rcpt) {
		$rcpt->delete;
		$rcpt = undef;
		$out .= $ui->SuccessMsg("Reply message deleted. Now using default reply message.");
		$deleted = 1;
	    }
	}

	if (! $deleted) {
	    # make message if not exists
	    if (! $rcpt) {
		$rcpt = $f->new_content_obj(name=>"_reply",publish=>"dynamic");
	    }
	    if ($rcpt->exists && $rcpt->revise(%rev)) {
		$out .= $ui->SuccessBox(pane=>"Form reply updated.");
		$ml->location($this->link(__plaintext=>1,cmd=>"preview"));
	    }
	    else {
		$out .= $ui->ErrorBox(pane=>$rcpt->show_diagnostics("error","html"));
	    }
	}
    }

    my @qname;
    my $qlist = $f->questions();
    while (my $q = $qlist->next) { push @qname, $q->name; }

    $out .= $ml->h1("Reply text for ".$ml->em($f->title));
    $out .= $ui->HelpBox(title=>"Form Replies",
			 float=>"right",
			 pane=>$ml->p("The reply message is displayed to the user after they have submitted the form. You do not have to define any special reply; a simple 'Thank you' will be used by default.").
			 $ml->p("You can include the following merge codes in the reply:").
			 $ml->ul([
			     join(", ",map {$ml->code("[[".$_."]]")} @qname)." - the answer they provided for that question",
			     $ml->code("[[_summary]]")." - a summary of all answers provided on the registration form",
			     $ml->code("[[_date]]")." - the date and time the response was received",
			     ])
	);

    $rcpt->load_revision("newest") if $rcpt;
    my $db = $share{DB};
    $db->input_htmleditor(
	prompt=>"Reply message",
	name=>$name,
	value=>$rcpt ? $rcpt->get_html() : $ml->h1("Thank You"),
	editor_height=>350,
	editor_width=>550
	);
    $db->form->set("buttons",
		   $ml->input(undef,{type=>"submit",value=>"Save"}).
		   $ml->input(undef,{type=>"submit",name=>"_save",value=>"Save as draft"}).
		   $ml->input(undef,{type=>"submit",class=>"delete",name=>"_save",value=>"Delete reply"}).
		   $ml->input(undef,{type=>"button",value=>"Cancel",class=>"formButton cancel",onclick=>"javascript:history.back()"}).
		   $ml->input(undef,{type=>"reset"}));
    $out .= $db->form->make();

    return $out;
}

sub form_template {  ### deprecated
    my ($this,$f) = @_;
    my $out = $ml->h1("Form Layout");
    my $db = $share{DB};

    my $post = $this->{post};
    if (scalar keys %$post) {
	my %post = $db->parse_parts(%{$this->{post}});
	if ($f->revise(data=>$post->{template},format=>"text")) {
	    $out .= $ui->SuccessBox(pane=>$f->title." updated.");
	    $ml->location($this->link(__plaintext=>1,cmd=>undef));
	}
	else {
	    $out .= $ui->ErrorBox(pane=>$f->show_diagnostics("error","html"));
	    return $out;
	}
    }

    $f->load_revision("newest");
    my $template = $f->get_html();
    my $form = $db->form(method=>"POST",
			 formid=>"exsiteform",
			 formname=>"FormLayout",
			 action=>$this->link);
    my %opt = ( name=>"template",
		editor=>{
		    op_image=>1,
		    op_link=>1,
		    op_table=>1,
		    op_dyncontent=>0,
		},
		value=>$template,
		required=>1,
		prompt=>"Layout",
	);
    $db->input_htmleditor(%opt);
    $out .= $form->make;

    my $br = $ml->br;
    my ($simple_template,$table_template,$enhanced_template);
    my $nq;
    while (my $q = $f->questions->next()) {
	$nq++;
        my $rowclass = $nq % 2 ? "A" : "B";
	my $qname = $q->name();
	my $qtemplate = $q->layout();
	$qtemplate =~ s/\[\[rowclass\]\]/$rowclass/;
	$simple_template .= $qtemplate;
	
#$ml->p("[[$qname:prompt]]${br}[[$qname:input]]");
	$table_template .= $ml->tr(
	    $ml->td("[[$qname:prompt]]",{class=>"prompt"}).
	    $ml->td("[[$qname:input]]",{class=>"input"})
	    );
        $enhanced_template .= $ml->div(
	    $ml->div("[[$qname:prompt]]",{class=>"Forms_prompt"}).
	    $ml->div("[[$qname:input]]",{class=>"Forms_input"}),
	    {class=>"Forms_question $rowclass"});
    }
    $table_template = $ml->table($table_template,{class=>"Form"});
    $enhanced_template = $ml->div($enhanced_template,{class=>"Form"});
    my @titles = ("Basic Layout","Two-column Table");
    my @panes = ($simple_template,$table_template);
    my @states = (0,0);
    my @matrix_template = $f->make_layout();
    if (scalar @matrix_template == 1 && $matrix_template[0] ne $simple_template) {
        push @titles, "Enhanced Layout with Grouping/Matrixes";
        push @panes, $matrix_template[0];
        push @states, 0;
    }

    my $br = $ml->br;
    $out .= $ml->h2("Instructions");
    $out .= $ml->p("Use merge codes to place the prompt and input fields for each of your form inputs. To place the input field, use ".$ml->code("[[name:input]]").". To place the prompt/label string, use ".$ml->code("[[name:prompt]]")." - replace \"name\" with the short name of the input field.");
    $out .= $ml->p("Example layouts are shown below (click to open). You can copy these using copy-paste, and then modify to suit.");

    $out .= $ui->AccordionBox(titles=>\@titles,
			      panes=>\@panes,
			      states=>\@states,);
    return $out;
}

sub copy_form {
    my ($this,$f) = @_;
    if ($f->defined) {
	my $newformid = $f->copy;
	if ($newformid) {
	    my $url = $this->link(cmd=>undef,id=>$newformid,__plaintext=>1);
	    $ml->location($url);
	    return $ml->p("Form copied. ".$ml->a("Click here to continue.",{href=>$url}));
	}
	else {
	    return &ExSite::Config::show_diagnostics();
	}
    }
    return $this->error("cannot copy a non-existent form");
}

sub reorder {
    my ($this,$cnode) = @_;
    my $out;
    my $f = $this->{form};
    my $qlist = $f->questions();
    if (scalar keys %{$this->{post}} > 0) {
	# oid=144&oid=143&oid=142&oid=141
	my @sort;
	my @input = split /&/,$share{input}{post}{raw};
	foreach my $input (@input) {
	    if ($input =~ /^form_reorder_id=(\d+)$/) {
		push @sort, $1;
	    }
	}
	my $order = 0;
	my %q = $qlist ? $qlist->hash("content_id") : ();
	foreach my $qid (@sort) {
	    $order++;
	    my $q = $q{$qid};
	    if ($q) {
		$q->setdata("sortkey",$order);
		$q->save;
	    }
	}
	$out .= $this->info("Re-ordered $order items.");
	$f->unload();
	$f->load();
    }
    my @order;
    if ($qlist) {
	$qlist->reset;
	while (my $q = $qlist->next()) {
	    push @order, $q->show().$ml->input(undef,{type=>"hidden",name=>"form_reorder_id",value=>$q->id});
	}
    }
    if (scalar @order > 1) {
	$out .= $ml->h1("Re-order questions");
	$out .= $ml->p("Drag questions into their new order, then click the save button.");
	$out .= $ui->js();
	$out .= $ml->script('
$(function() {
  $( "#sortable" ).sortable();
  $( "#sortable" ).disableSelection();
});
');
	if ($f->has_revisions) {
	    $out .= $ui->HelpMsg("This form has a custom layout, which will override the ordering you specify here.".$ml->br."The ordering here will still control the ordering in reports.");
	}
	$out .= $ml->form(
	    $ml->input(undef,{type=>"submit",value=>"Save order"}).
	    $ml->ul(\@order,{id=>"sortable"}).
	    $ml->input(undef,{type=>"submit",value=>"Save order"}),
	    {action=>$this->link(),method=>"post",id=>"sortableContent"}
	    );
    }
    else {
	$out .= $this->warn("There are not enough questions to order.");
    }
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

    my @qtype = split /\|/,$share{DB}{map}->regexp("list:form_input_format");
    my $br = $ml->br;
    my $arr = $ui->FAIcon("left"); # left arrow
    my $newout = $ml->div(
	$ml->form(
	    $ml->h2("Create a new question").
	    $ml->div($ml->strong("Question:")." ".$ml->span("[required]",{class=>"warn"}).$br.$ml->input(undef,{type=>"text",name=>"prompt",id=>"prompt",size=>60}),{id=>"question_prompt"}).
	    $ml->div($ml->strong("Type:")." ".$ml->span("[required]",{class=>"warn"}).$br.$ml->select(\@qtype,{name=>"format",id=>"format"}),{style=>"display:inline-block;",id=>"question_type"}).
	    $ml->p(
		$ml->span($arr."a single-line text input that accepts any input",{id=>"help_short_text"}).
		$ml->span($arr."a multi-line text input that accepts any input",{id=>"help_long_text",style=>"display:none;"}).
		$ml->span($arr."a drop-down selector to choose one of several options",{id=>"help_select",style=>"display:none;"}).
		$ml->span($arr."a box containing a list of options, from which you can choose one or more using ctrl-click and shift-click",{id=>"help_multiselect",style=>"display:none;"}).
		$ml->span($arr."a multiple-choice list of options, allowing you to check one of them",{id=>"help_radio",style=>"display:none;"}).
		$ml->span($arr."a radio button multiple choice selector, with an optoin to select 'other' and enter free-form text",{id=>"help_radio_other",style=>"display:none;"}).
		$ml->span($arr."a simple checkbox",{id=>"help_checkbox",style=>"display:none;"}).
		$ml->span($arr."a list of checkboxes, any number of which can be chosen",{id=>"help_checklist",style=>"display:none;"}).
		$ml->span($arr."a checklist that includes an 'other' option, in which you can enter free-form text",{id=>"help_checklist_other",style=>"display:none;"}).
		$ml->span($arr."input text will be masked so that it is not readable to bystanders",{id=>"help_password",style=>"display:none;"}).
		$ml->span($arr."hidden inputs are not displayed, but will be included in the submitted response",{id=>"help_hidden",style=>"display:none;"}).
		$ml->span($arr."uploads a file selected from the user's computer",{id=>"help_file",style=>"display:none;"}).
		$ml->span($arr."a block of text with no actual question, but which you can place and move around as if it were a question",{id=>"help_label",style=>"display:none;"}).
		$ml->span($arr."a block of text with no actual question, but which you can place and move around as if it were a question",{id=>"help_preformatted",style=>"display:none;"}).
		$ml->span($arr."accepts numeric inputs within a range (works on modern browsers only)",{id=>"help_number",style=>"display:none;"}).
		$ml->span($arr."a slider to set numeric values within a range (works on modern browsers only)",{id=>"help_range",style=>"display:none;"}).
		$ml->span($arr."sets a date (works on modern browsers only)",{id=>"help_date",style=>"display:none;"}).
		$ml->span($arr."sets a time (works on modern browsers only)",{id=>"help_time",style=>"display:none;"}).
		$ml->span($arr."accepts an input formatted like an email address (works on modern browsers only)",{id=>"help_email",style=>"display:none;"}).
		$ml->span($arr."accepts an input formatted like a URL (works on modern browsers only)",{id=>"help_url",style=>"display:none;"}),
		{class=>"format_help"}
	    ).
	    $ml->p("Min: ".$ml->input(undef,{type=>"text",name=>"min",id=>"min",size=>4,title=>"The minimum numeric value that will be accepted."}).
		   " Max: ".$ml->input(undef,{type=>"text",name=>"max",id=>"max",size=>4,title=>"The maximum numeric value that will be accepted."}).
		   " Step: ".$ml->input(undef,{type=>"text",name=>"step",id=>"step",size=>4,title=>"The amount by which numeric options should increment."}),
	    {style=>"display:none;"}).
	    $ml->p($ml->input(undef,{type=>"checkbox",name=>"checked",id=>"checked",title=>"Pre-check the checkbox.",disabled=>undef})." Checked",{style=>"display:none;"}).
	    $ml->div(
	    $ml->p("Input field size:$br".$ml->input(undef,{type=>"text",name=>"size",id=>"size",size=>8,title=>"This sets the size of the input field. For most inputs, it is the number of characters that are visible at once. For multiselects, this is the number of lines that are shown."}),{style=>"display:inline-block;"}).
	    $ml->p("Max. value length:$br".$ml->input(undef,{type=>"text",name=>"maxlen",id=>"maxlen",size=>8,title=>"This is the maximum number of characters you can type into the field."}),{style=>"display:inline-block;"})
	    ).
	    #$ml->p("Answer is:".$ml->br.$ml->select(["optional","required"],{name=>"required",id=>"required"})).
	    $ml->p("Validate:$br".$ml->select(["any answer is okay","email","url","date (YYYY-MM-DD)","time (HH:MM)","integer","decimal","price"],{name=>"datatype",id=>"datatype",title=>"This will reject any answers that do not match the selected pattern."})).
	    $ml->p($ml->strong("Allowed answers")." (separate with | character): ".$ml->span("[required]",{class=>"warn"}).$br.$ml->textarea(undef,{name=>"options",rows=>6,cols=>60,id=>"options",disabled=>undef,title=>"List your multiple-choice answers separated with a bar, like this: yes|no"}),{style=>"display:none;"}).
	    $ml->p("Preset answer:$br".$ml->input(undef,{type=>"text",name=>"preset",id=>"preset",size=>30,title=>"This presets a default answer for the question."})).
	    $ml->p("Placeholder:$br".$ml->input(undef,{type=>"text",name=>"placeholder",id=>"placeholder",size=>30,title=>"This shows a formatting hint in the input field."})).
	    $ml->p("Access:$br".
		   $ml->select(
		       $ml->option("everyone",{value=>0}).
		       $ml->option("registered users",{value=>1}).
		       $ml->option("members",{value=>2}).
		       $ml->option("administrators",{value=>5}),
		       {name=>"access",id=>"access",title=>"You must have at least this level of access to see this question."})
	    ).
	    $ml->p($ml->input(undef,{type=>"checkbox",name=>"required",id=>"required",title=>"The response will not be accepted if a required question is not answered."})." Required").
	    $ml->p("Input name:$br".$ml->input(undef,{type=>"text",name=>"name",id=>"name",size=>20,title=>"This is the name used by the computer to track this question. It should consist of alphanumeric chararacters plus underscores only"})).
	    $ml->p($ml->input(undef,{type=>"submit",value=>"+ Add question",id=>"make_question"})),
	    {method=>"post",action=>$this->link(cmd=>"newq",id=>$this->{input}{id}),id=>"new_question_form"}),
	{id=>"new_question"});

    my $copyout = 
	$ml->h2("Copy an existing question").
	$ml->p("Copying similar questions is faster, reduces mistakes and typos, and makes use of existing translations.").
	$this->get_question_tree();
#	&ExSite::HTML::ErrorBox(title=>"TODO",pane=>"this feature not developed yet");

    # list all forms by age, with # of responses
    # click to expand to a list of questions
    # click a question to add it

#    $out .= &ExSite::HTML::DynTabBox(tabs=>["Copy","Create"],
#				     panes=>[$copyout,$newout]);
    $out .= $ui->DynTabBox(tabs=>["Create","Copy"],
			   panes=>[$newout,$copyout]);
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
	my $form = new Modules::Forms::Form(data=>$fdata);
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

sub get_question_tree_old {
    my $this = shift;
    my $f = $this->{form};
    my $tree = $f->get_content_tree();
    my @form = $tree->find({type=>$f->isubtype("form")},$f->my_section->id);
    my $out;
    my $nq;
    my (@title,@pane);
    foreach my $fdata (@form) {
	next if ($fdata->{content_id} == $f->id);
	my $form = new Modules::Forms::Form(data=>$fdata);
	push @title, $form->title;
	my $questions = $form->questions();
	my $qlist;
	while (my $q = $questions->next) {
	    $nq++;
	    $qlist .= $ml->div(
		$ml->a($q->label(),{class=>"copyQuestion popupLink",href=>"#questionPopup",id=>"q".$q->id."_f".$f->id})
		);
	}
	push @pane, $qlist;
    }

    return $nq ? 
	$ml->script("\nvar modpath = '$config{server}{CGIpath}/$config{prog}{admin}/Forms?';\n").
	$ui->AccordionBox(titles=>\@title, panes=>\@pane).
	$ml->div(undef,{id=>"questionPopup",class=>"contentPopup mfp-hide"}) : 
	$ml->span("Sorry, there are no questions to copy.",{class=>"error"});
}

sub copy_question {
    my $this = shift;
    my $out;
    my $q = new Modules::Forms::Question(id=>$this->{input}{copy});
    my $f = $this->{form};
    if ($this->{input}{confirm}) {
	if ($q->copy(parent=>$f->id)) {
	    $out = $ui->SuccessMsg("Question copied").
		$ml->p("You can edit the question particulars via the 'questions' button in the toolbar");
	}
	else {
	    $out = $ui->ErrorMsg("Question not copied").
		&ExSite::Config::show_diagnostics();
	}
    }
    else {
	# jquery copy question skips this part
	$out = $ui->FrameBox(title=>"Preview",pane=>$q->show());
	$out .= $ml->button("copy this question",{class=>"copyQuestionConfirm",id=>"copyq".$q->id."_f".$f->id});
    }
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
    push @head, qw(Response Received From Language);
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
		 $ui->fatool("delete",confirm=>'Really delete response $rid?',url=>$this->link(cmd=>"del",response=>$rid),tone=>"bad");
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
	push @data, $rid, $share{DB}->show_data_noauth("response","ctime",$r1->{ctime},$rid,"datetime"), $user, $r1->{language};
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

sub question_labels {
    my ($this,$form) = @_;
    my @label;
    if ($form->loaded) {
	$form->{list}->reset();
	while (my $q = $form->{list}->next()) {
	    next if (! $q->is_question);  # skip labels/section breaks
	    push @label, $q->label();
	}
    }
    return @label;
}

sub show_question_toolbar {
    my ($this) = @_;
    return $ui->ToolBar(
	tools=>[
	    {label=>"back to form",url=>$this->link(id=>$this->{form}->id,cmd=>"questions"),faicon=>"back"},
	    undef,
	    {label=>"preview",url=>$this->link(cmd=>"preview"),faicon=>"view"},
	    {label=>"configure",url=>$this->link(cmd=>"conf"),faicon=>"conf"},
	    {label=>"layout",url=>$this->link(cmd=>"update"),faicon=>"edit"},
	    {label=>"delete",url=>$this->link(cmd=>"del"),tone=>"bad",confirm=>"WARNING: deleting this question will also discard any answers that have been received for it.",faicon=>"delete"},
	]
	);
}

sub show_question {
    my $this = shift;
    my $out;
    my $q = $this->{question};
    if ($this->{input}{cmd} eq "preview") {
	$out .= $this->show_question_toolbar();
	$out .= $ui->FrameBox(title=>"Preview",pane=>$q->show());
    }
    elsif ($this->{input}{cmd} eq "update") {
	$out .= $this->update($q);
    }
    elsif ($this->{input}{cmd} eq "del") {
	if ($q->allow("delete")) {
	    $q->delete();
	    $ml->redirect($this->link(cmd=>"questions",id=>$this->{form}->id,__plaintext=>1));
	    return;
	}
	else {
	    $out .= $this->error("delete question: permission denied");
	}
    }
    else {
	$out .= $this->show_question_toolbar();
	$out .= $this->configure($this->{question});
    }
    return $out;
}

sub get_summary_report {
    my ($this,$form) = @_;

    # look for any questions requiring averages
    my ($use_avg, %avg);
    my $questions = $form->questions();
    while (my $q = $questions->next) {
	if ($q->format =~ /number|range/) {
	    $avg{$q->id} = 1; 
	    $use_avg = 1;
	}
	elsif ($q->format eq "radio") {
	    my $isnum = 1;
	    foreach my $v ($q->answer_values()) {
		# allow trailing whitespace in case of extra spaces or CRs
		if ($v !~ /^\d+\s*$/) { $isnum = 0; last; }
	    }
	    if ($isnum) {
		$avg{$q->id} = 1; 
		$use_avg = 1;
	    }
	}
    }

    my $answers = $form->get_all_answers();
    my $rpt = new ExSite::ReportBuilder(title=>"Response Summary - ".$form->name,
					width=>"100%",
					cwidth=>[undef,undef,undef,undef,"100"]
	);
    my @head;
    push @head, ("Question", "Answer", "Responses", "\%", "Chart");
    if ($use_avg) {
	push @head, "Average";
    }
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
		    push @data, $v, 
		    $ml->div($n,{class=>"num"}),
		    $ml->div("$pct\%",{class=>"num"});
		    push @data, $ml->div("#" x $nhash,{class=>"bar",style=>"height:10px;width:${pct}px"});
		    if ($use_avg) {
			if ($first && $avg{$q->id}) { 
			    # report average
			    my ($n,$total);
			    foreach my $key (keys %{$summary{$q->label}}) {
				$n += $summary{$q->label}{$key};
				$total += $key * $summary{$q->label}{$key};
			    }
			    if ($n) {
				push @data, $ml->div(int($total/$n*100)/100,{class=>"num"}); 
			    }
			    else {
				push @data, undef; # no answers!
			    }
			}
			else {
			    push @data, undef; # filler
			}
		    }
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
		if ($use_avg) { push @data, undef; } # no avgs on freeform data
		$rpt->push(@data);
	    }
	}
    }
    $rpt->foot("$n_response responses received.");
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
	$out = $r->make();
    }
    return $out;
}

sub show_responses {
    my ($this,$f) = @_;
    my $out;
    my $fmt = $this->{input}{export};
    my $r = $this->get_response_report($f,!$fmt);  ##### doesn't match params
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
	$out .= $r->make();
#	$out .= $ml->p(
#	    &ExSite::HTML::Button(
#		 label=>"Delete all responses",
#		 url=>$this->link(cmd=>"delall"),
#		 confirm=>"Really delete all responses?",
#	    ));
	return $out;
    }
}

sub show_response {
    my ($this,$response_id) = @_;
    my $r = new Modules::Forms::Response(id=>$response_id);
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

sub filter_responses {
    my ($this,$form) = @_;
    my $out;
    my $post = $this->{input}; # normally post, but get on exports

    my $f = new ExSite::FormBuilder();
    $f->template(
	$ml->h3("Select only responses received within this date range:").
	$ml->table(
	    $ml->tr(
		$ml->td("[[filter_date_start:prompt]]".$ml->br."[[filter_date_start:input]]").
		$ml->td("[[filter_date_end:prompt]]".$ml->br."[[filter_date_end:input]]")
	    ),
	    {class=>'filterdates'}
	)
	);
    $f->input(name=>"_filter",type=>"hidden",value=>1);
    $f->input(name=>"filter_date_start",prompt=>"Start Date",value=>$post->{filter_date_start},size=>12,type=>"date",placeholder=>"YYYY-MM-DD");
    $f->input(name=>"filter_date_end",prompt=>"End Date",value=>$post->{filter_date_end},size=>12,type=>"date",placeholder=>"YYYY-MM-DD");

    $f->input(name=>"filters",input=>$ml->h3("Select only responses matching the following answers:"),type=>"preformatted");

    my $qlist = $form->questions();
    while (my $q = $qlist->next) {
	if ($q->is_question()) {
	    my $fmt = $q->format;
	    next if ($fmt eq "file");
	    if ($fmt =~ /number|range/) {
		$q->show(FormBuilder=>$f,required=>0,value=>$post->{$q->name},format=>"short text",size=>8);
	    }
	    else {
		$q->show(FormBuilder=>$f,required=>0,value=>$post->{$q->name});
	    }
	}
    }

    $out .= $ui->BlindBox(
	title=>"Report Filters",
	pane=>$f->make(),
	open=>! exists $post->{filter_date_start}
	);

    if (exists $post->{_filter}) {
	my $fmt = $this->{input}{export};
	my $r = $this->get_response_report($form,!$fmt,$post);
	if ($fmt =~ /csv/) {
	    $ml->cancel();
	    my $formid = $form->id;
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
	    my $formid = $form->id;
	    print "Content-type: application/vnd.ms-excel\n";
	    print "Content-disposition: attachment; filename=responses-$formid.xls\n\n";
	    $r->export("excel");
	}
	else {
	    $out .= $r->make();
	}
    }
    return $out;
}

sub edit_response {
    my ($this,$form_id,$response_id,$action) = @_;
    my $r = new Modules::Forms::Response(id=>$response_id);
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

1;
