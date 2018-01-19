package Modules::QA;

#----------------------------------------------------------------------------
#
#   Copyright (C) 2009 - Exware Solutions, Inc.  http://www.exware.com
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
use Modules::BaseDCD;
use Modules::QA::Form;
use Modules::QA::Library;

use vars qw(@ISA $ml $QA $maxrec);
@ISA = qw(Modules::BaseDCD);

sub read {
    my ($this,$options) = @_;
    my $in = new ExSite::Input;
    $this->{input} = $in->combine;
    $this->{post} = $in->post;
    $this->{query} = $in->query;
}

sub write {
    my ($this,$options) = @_;
    $ml = &get_obj("ML");
    my %opt = &DecodeString($options);
    my $in = $this->{input};
    my $out;
    my $key_id;
    if ($in->{'_qakey'}) {
	my $c = new ExSite::Crypt;
	($key_id,undef) = split /;/, $c->decrypt($in->{'_qakey'});
    }
    my $form_id = $opt{form} || $key_id;
    my $action = $this->link();
    if ($form_id) {
	if ($in->{qacmd} eq "edit_response" && $in->{response}) {
	    $out = $this->edit_response($form_id,$in->{response},$action);
	}
	else {
	    my $form = new Modules::QA::Form(id=>$form_id);
	    $out = $form->show(action=>$action);
	}
    }
    elsif ($in->{form}) {
	my $form = new Modules::QA::Form(id=>$in->{form});
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
    return $ml->div($out,{class=>"QA"});
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
	return "Web Forms";
    }
    elsif (/ModuleInfo/) {
	return "This modules processes user-configurable forms.";
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

# ToDo : find all untranslated questions

sub todo {
    my $this = shift;
    my @version = split /\|/, $share{DB}{map}->regexp("list:version");
    my @task;
    if (@version > 0) {
	$this->setup_querylib();
	my $section_id = $this->{input}{section_id} || 0;

	### FIXME: this only finds questions with NO translations
	### not questions with some translations, but not others

	my @q = $share{DB}->get_query("untranslated questions",$section_id);
	foreach my $q (@q) {
	    push @task, { title=>"Question not translated: $q->{label}",
			  description=>$q->{format},
			  link=>"$config{server}{CGIpath}/$config{prog}{ctrlpanel}/QA?section_id=$section_id&amp;lib=$q->{qa_lib_id}&amp;qb=$q->{qa_base_id}" };
	}
    }
    return @task;
}

# Control Panel : browse and export responses

sub ctrl_panel {
    my $this = shift;
    $QA = $this;
    $this->{section_id} = $this->get_section_id();
    if (! $this->{section_id} && $config{QA}{admin_scope} ne "global") {
	return $this->set_section_id();
    }
    $this->setup_querylib();

    $ml = &get_obj("ML");

    # datepicker stuff
    my $out = &ExSite::HTML::js;
    $out .= $ml->script(undef,{type=>"text/javascript",src=>"$config{server}{HTMLpath}/_ExSite/js/date.js"});
    $out .= $ml->script(undef,{type=>"text/javascript",src=>"$config{server}{HTMLpath}/_ExSite/js/jquery.datePicker.js"});
    $out .= $ml->link(undef,{rel=>"stylesheet",type=>"text/css",media=>"screen",href=>"$config{server}{HTMLpath}/_ExSite/css/datePicker.css"});
    $out .= $ml->script("Date.firstDayOfWeek = 0;\nDate.format = 'yyyy-mm-dd';\n\$(function() {\n\$('.date-pick').datePicker({startDate:'$config{form}{date_picker_start_date}'});\n});\n",
			{type=>"text/javascript",charset=>"utf-8"});

    $out .= $this->show_location();
    my $db = $share{DB};
    $db->handler("show_foreign_key",\&show_foreign_key);

    my $cmd = $this->{query}{qacmd};
    if ($this->{query}{response}) {
	if ($cmd eq "edit_response") {
	    $out .= $this->edit_response($this->{query}{form},$this->{query}{response});
	    $out .= $ml->p($ml->a("&lt; back to response",{href=>$this->link(qacmd=>"responses")}));
	}
	else {
	    my $f = new Modules::QA::Form(id=>$this->{query}{form});
	    $out .= $this->show_form_toolbar($f);
	    $out .= $this->show_response($this->{query}{response});
	    $out .= $ml->p($ml->a("&lt; All responses",{href=>$this->link(response=>undef),class=>"button"}));
	}
    }
    elsif ($this->{query}{lib}) {
	if ($cmd eq "newq") {
	    $out .= $this->new_base_question();
	}
	elsif ($cmd eq "newlab") {
	    $out .= $this->new_base_label();
	}
	elsif ($cmd eq "editlib") {
	    $out .= $this->edit_lib();
	}
	elsif ($this->{query}{qb}) {
	    if ($cmd eq "trans") {
		$out .= $this->translate();
	    }
	    else {
		$out .= $this->base_question();
	    }
	}
	else {
	    $out .= $this->show_library();
	}
    }
    elsif ($this->{query}{form}) {
	my $f = new Modules::QA::Form(id=>$this->{query}{form});
	$out .= $this->show_form_toolbar($f);
	if ($cmd eq "export") {
	    $out .= $this->export_responses($f);
	}
	elsif ($cmd eq "preview") {
	    my $preview = &ExSite::HTML::ErrorBox(title=>"Warning",pane=>"Your website's stylesheet may mandate a different look for your forms. This preview does not necessarily reflect how the form will look in its final published form.");
	    $preview .= $f->show(revision=>"newest");
	    $out .= &ExSite::HTML::BasicBox(title=>"Preview",pane=>$preview);
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
	    $out .= $this->add_question();
	}
	elsif ($cmd eq "conf") {
	    $out .= $this->configure_form($f);
	}
	elsif ($cmd eq "copy") {
	    $out .= $this->copy_form($f);
	}
	elsif ($cmd =~ /^template/) {
	    $out .= $this->form_template($f);
	}
#	elsif ($cmd =~ /^up|down$/) {
#	    $out .= $this->reorder();
#	}
	elsif ($cmd eq "reorder") {
	    $out .= $this->reorder();
	}
	elsif ($this->{query}{q}) {
	    $out .= $this->question();
	}
	elsif ($cmd eq "del") {
	    $f->delete();
	    $ml->redirect($this->link(qacmd=>undef,form=>undef,__plaintext=>1));
	    return;
	}
	elsif ($cmd =~ /^publish/) {
	    $out .= $this->publish_form($f);
	}
	else {
	    $out .= $this->show_form($f);
	}
    }
    else {
	if ($cmd eq "newform") {
	    $out .= $this->new_form_wizard();
	}
	elsif ($cmd eq "newlib") {
	    $out .= $this->new_lib();
	}
	else {
	    my $formout = $this->show_forms();
	    my $libout = $this->show_libraries();
	    $out .= &ExSite::HTML::DynTabBox(
		tabs=>["Forms","Libraries"],
		panes=>[$formout,$libout]
		);
	}
    }
    return $out;
}

sub show_forms {
    my $this = shift;
    my $forms = $this->my_forms();
    my $r = new ExSite::ReportBuilder(title=>"Forms",width=>"100%");
    $r->headers(["Form","Title","Responses","Section","Reports"]);
    while (my $f = $forms->next) {
	my $n_response = $f->count_responses();
	my $opt;
	if ($n_response) {
	    $opt .= 
		$ml->a("stats",{class=>"button_sm",href=>$this->link(qacmd=>"summary",form=>$f->id)}).
		$ml->a("responses",{class=>"button_sm",href=>$this->link(qacmd=>"responses",form=>$f->id)}).
		$ml->a("export",{class=>"button_sm",href=>$this->link(qacmd=>"responses",export=>"xls",form=>$f->id)});
	}
	$r->push($f->id,
		 $ml->a($f->name,{href=>$this->link(form=>$f->id())}),
		 $n_response,
		 $f->showdata("content_id"),
		 $opt)
    }
    $r->tools($ml->a("+ new form",{href=>$this->link(form=>undef,qacmd=>"newform"),class=>"button_sm"}));
    return $r->make();
}

sub show_libraries {
    my $this = shift;
    my $libs = $this->my_libs();
    my $r = new ExSite::ReportBuilder(title=>"Question Libraries",width=>"100%");
    $r->headers(["Library","Title","Questions","Section"]);
    while (my $lib = $libs->next) {
	next if (! $this->owns_lib($lib->get()));
	$r->push($lib->id,
		 $ml->a($lib->name,{href=>$this->link(lib=>$lib->id())}),
		 $lib->count_questions(),
		 $lib->showdata("content_id"));
    }
    $r->tools($ml->a("+ new library",{href=>$this->link(form=>undef,qacmd=>"newlib"),class=>"button_sm"}));
    return $r->make();
}

sub show_location {
    my $this = shift;
    my @path = $ml->a("Top",{href=>$this->link(section_id=>undef,lib=>undef,form=>undef,qacmd=>undef,qb=>undef,tr=>undef,response=>undef)});
    if ($this->{section_id}) {
	my $s = new ExSite::Section(id=>$this->{section_id});
	push @path, $ml->a($s->get_my("title"),{href=>$this->link(form=>undef,lib=>undef,qacmd=>undef,q=>undef,qb=>undef,tr=>undef,response=>undef)});
    }
    if ($this->{query}{form}) {
	$this->{form} = new Modules::QA::Form(id=>$this->{query}{form});
	push @path, $ml->a("Form: ".$this->{form}->name,{href=>$this->link(lib=>undef,qacmd=>undef,q=>undef,qb=>undef,tr=>undef,response=>undef)});
	if ($this->{query}{q}) {
	    $this->{question} = new Modules::QA::Question(id=>$this->{query}{q});
	    push @path, $ml->a($this->{question}->name,{href=>$this->link(qacmd=>undef,lib=>undef,qb=>undef,tr=>undef,response=>undef)});
	}
    }
    if ($this->{query}{lib}) {
	$this->{lib} = new Modules::QA::Library(id=>$this->{query}{lib});
	push @path, $ml->a("Library: ".$this->{lib}->name,{href=>$this->link(form=>undef,qacmd=>undef,q=>undef,qb=>undef,tr=>undef,response=>undef)});
    }
    if ($this->{query}{qb}) {
	$this->{qb} = new Modules::QA::Base(id=>$this->{query}{qb});
	push @path, $ml->a($this->{qb}->name,{href=>$this->link(qacmd=>undef,q=>undef,tr=>undef,response=>undef)});
	if ($this->{query}{tr}) {
	    $this->{tr} = new ExSite::Object(type=>"qa_translation",id=>$this->{query}{tr});
	    push @path, $ml->a($this->{tr}->showdata("version"),{href=>$this->link(qacmd=>undef,response=>undef)});
	}
    }
    #return $ml->p(join("&nbsp;&gt;&nbsp;",@path));
    return &ExSite::HTML::PathBar(links=>\@path);
}

sub my_forms {
    my $this = shift;
    my $db = $share{DB};
    my @form;
    if ($config{QA}{admin_scope} eq "global") {
	# show all forms
	push @form, $db->fetch_all("qa_form");
    }
    else {
	# local scope; show only forms for selected section
	if ($db->level >= 8) { 
	    push @form, $db->fetch_match("qa_form",{content_id=>0});
	}
	my $site = $db->this_site();
	if ($site) { 
	    push @form, $db->fetch_match("qa_form",{content_id=>$site->{content_id}});
	}
    }
    my $forms = new ExSite::ObjectList(type=>"qa_form",list=>\@form);
    $forms->sort("name");
    return $forms;   # ObjectList
}

sub my_libs {
    my $this = shift;
    my $db = $share{DB};
    my $sid = $this->get_section_id();
    my @lib;
    if ($config{QA}{admin_scope} eq "global") {
	# show all libs
	push @lib, $db->fetch_all("qa_lib");
    }
    else {
	# local scope
	push @lib, $db->fetch_match("qa_lib",{section_id=>0});
	if ($sid) {
	    push @lib, $db->fetch_match("qa_lib",{section_id=>$sid});
	}
    }
    my $libs = new ExSite::ObjectList(type=>"qa_lib",list=>\@lib);
    $libs->sort("name");
    return $libs;   # ObjectList
}

sub owns_lib {
    my ($this,$lib) = @_;
    my $db = $share{DB};
    my $l = (ref $lib) ? $lib : $db->fetch("qa_lib",$lib);
    my $sid = $l->{section_id};
    if ($sid) {
	return $db->owns($sid);
    }
    else {
	return ($db->level > 2);
    }
}

sub show_library {
    my $this = shift;
    my $out;
    my $lib = new Modules::QA::Library(id=>$this->{query}{lib});
    if ($this->owns_lib($this->{query}{lib})) {
	if ($this->{query}{qacmd} eq "del") {
	    $lib->delete();
	    $ml->redirect($this->link(qacmd=>undef,lib=>undef,__plaintext=>1));
	    return;
	}
	my $url = new ExSite::URI;
	my $newurl = new ExSite::URI;
	$newurl->parameter(qacmd=>"newq");
	my $newlaburl = new ExSite::URI;
	$newlaburl->parameter(qacmd=>"newlab");
	$out .= $lib->show(url=>$url,newurl=>$newurl,newlaburl=>$newlaburl);
	$out .= 
	    $ml->a("+ create new question",{href=>$this->link(qacmd=>"newq"),class=>"button"}).
	    $ml->a("+ create new label/section break",{href=>$this->link(qacmd=>"newlab"),class=>"button"}).
	    $ml->a("configure library",{href=>$this->link(qacmd=>"editlib"),class=>"button"});
	if ($lib->count_questions() == 0) {
	    $out .= &ExSite::HTML::Button(label=>"DELETE library",url=>$this->link(qacmd=>"del"),type=>"button");
	}
    }
    else {
	$out .= $lib->show();
    }
    return $out;
}

sub show_form {
    my ($this,$f) = @_;
    my $db = $share{DB};
    my $rpt = new ExSite::ReportBuilder(title=>$f->name());
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
    my $n_response = $f->count_responses;
    my $fid = $f->id;

    my $delete_link = $n_response > 0 ?
	&ExSite::HTML::Confirm(message=>"WARNING: deleting this form will also discard the $n_response responses\nthat have been received so far.",
			       label=>$ml->span("- delete",{style=>"color:red"}),
			       url=>$this->link(form=>$fid,qacmd=>"del")) :
	$ml->a($ml->span("- delete",{style=>"color:red"}),{href=>$this->link(form=>$fid,response=>undef,qacmd=>"del")});
			       
    return &ExSite::HTML::ToolBar(
	tools=>[
	    $ml->a("stats",{href=>$this->link(form=>$fid,response=>undef,qacmd=>"summary")}).
	    $ml->a("responses",{href=>$this->link(form=>$fid,response=>undef,qacmd=>"responses")}).
	    $ml->a("filter",{href=>$this->link(form=>$fid,response=>undef,qacmd=>"filter")}).
	    $ml->a("export",{href=>$this->link(form=>$fid,response=>undef,qacmd=>"responses",export=>"xls")}),

	    $ml->a("preview",{href=>$this->link(form=>$fid,response=>undef,qacmd=>"preview")}).
	    $ml->a("configure",{href=>$this->link(form=>$fid,response=>undef,qacmd=>"conf")}).
	    $ml->a("layout",{href=>$this->link(form=>$fid,response=>undef,qacmd=>"template")}).
	    $ml->a("questions",{href=>$this->link(form=>$fid,response=>undef,qacmd=>"questions")}).
	    $ml->a("order",{href=>$this->link(form=>$fid,response=>undef,qacmd=>"reorder")}).
	    $ml->a("+ add",{href=>$this->link(form=>$fid,response=>undef,qacmd=>"newq")}),

	    $ml->a("publish",{href=>$this->link(form=>$fid,response=>undef,qacmd=>"publish")}).
	    $ml->a("+ copy form",{href=>$this->link(form=>$fid,response=>undef,qacmd=>"copy")}).
	    $delete_link
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
    $rpt2->headers(["Question ID","Question","Format","Options","Last Modified"]);
    my $qlist = $f->questions();
    if ($qlist) {
	$qlist->reset();
	while (my $q = $qlist->next()) {
	    $rpt2->push(
		$q->id(),
		$ml->a($q->name(),{href=>$this->link(qacmd=>undef,'q'=>$q->id())}),
		$q->format(),
		$q->showdata("flags"),
#		&ExSite::HTML::Arrow(dir=>"up",url=>$this->link(q=>$q->id,qacmd=>"up")).&ExSite::HTML::Arrow(dir=>"down",url=>$this->link(q=>$q->id,qacmd=>"down")),
#		$ml->a("&#9650",{href=>$this->link(q=>$q->id,qacmd=>"up")})." ".$ml->a("&#9660",{href=>$this->link(q=>$q->id,qacmd=>"down")}),
		$q->showdata("mtime")
		);
	}
    }
    $rpt2->tools($ml->a("+ add question",{class=>"button_sm",href=>$this->link(qacmd=>"newq")}));
    $out .= $rpt2->make;
    return $out;
}

sub form_template {
    my ($this,$f) = @_;
    my $out = $ml->h1("Form Layout");
    my $db = $share{DB};

    if ($this->{query}{qacmd} eq "template_reset") {
	if ($this->{query}{template_id}) {
	    ### don't delete the content object - it might be used by 
	    ### multiple forms
	    #my $content = new ExSite::Content(id=>$this->{input}{template_id});
	    #$content->delete();
	    $f->setdata("template","");
	    if ($f->save()) {
		$ml->location($this->link(__plaintext=>1,qacmd=>"template",template_id=>undef));
		return;
	    }
	}
	$out = $this->error("failed to remove template from form");
	return $out;
    }

    my $post = $this->{post};
    if (scalar keys %$post) {
	# template was submitted
	if ($post->{template_id}) {
	    my $content = new ExSite::Content(id=>$post->{template_id});
	    if ($content->update({data=>$post->{'template#html'},mime_type=>"text/html",note=>"form template created using QA"})) {
		$ml->location($this->link(__plaintext=>1,qacmd=>undef));
	    }
	    else {
		$out .= $content->show_diagnostics("error","html");
		return $out;
	    }
	}
	elsif ($post->{template_lib}) {
	    my $content = new ExSite::Content();
	    my $template = $content->new_content_obj(name=>$post->{template_name},parent=>$post->{template_lib});
	    if ($template->defined) {
		if ($template->revise(data=>$post->{'template#html'},format=>"text",mime_type=>"text/html",note=>"form template created using QA")) {
		    $f->setdata("template",$post->{template_name});
		    if ($f->save()) {
			$ml->location($this->link(__plaintext=>1,qacmd=>undef));
		    }
		    else {
			$out = $this->error("failed to reconfigure form to use new template");
			return $out;
		    }
		}
		else {
		    $out .= $template->show_diagnostics("error","html");
		    return $out;
		}
	    }
	    else {
		$out .= $content->show_diagnostics("error","html");
		return $out;
	    }
	}
	else {
	    $out .= $this->error("Invalid input - cannot make template.");
	}
    }

    my $template = $f->template();
    # reset to get newest revision
    if ($template) {
	$template->load_revision("newest");
#	$template->reset_context();
    }
    my ($template_html,$template_name,$template_lib,$template_id);
    if ($template) {
	$template_html = $template->get_html();
	$template_id = $template->id();
    }
    my $template_name = $f->getdata("template");
	
    my $form = $db->form(method=>"POST",
			 formid=>"exsiteform",
			 formname=>"QAlayout",
			 action=>$this->link);

    if ($template_name) {
	$out .= $ml->p("This form has a custom layout, shown below. Use the preview button to see what the form looks like when this template is applied.");
	$form->input(type=>"hidden",name=>"template_name",value=>$template_name);
	$form->input(type=>"hidden",name=>"template_id",value=>$template_id);
	$out .= $ml->p($ml->a("Reset to default layout",{href=>"javascript:confirm_custom('Discard this template?','".$this->link(qacmd=>"template_reset",template_id=>$template_id)."')",class=>"button"}));
    }
    else {
	$out .= $ml->p("This form has no special layout defined. Use the preview button to see what the default layout will look like. Use the form below to create a custom layout.");
	$form->input(type=>"text",name=>"template_name",required=>1,prompt=>"Template ID",value=>"QA_template_".$f->id);
	my $s = $db->this_site();
	if (! $s) { return $this->error("This form must belong to a particular website ini order to define a layout template for it."); }
	my $section = new ExSite::Section(section=>$s);
	my @opt = map { [ $_->{content_id}, $_->{name} ] } $section->fetch_libraries;
	$form->input(type=>"select",name=>"template_lib",required=>1,prompt=>"Put template in library",nullvalue=>"== select ==",options=>\@opt);
    }

    my %opt = ( name=>"template",
		editor_height=>350,
		editor_width=>550,
		editor=>{
		    op_image=>0,
		    op_link=>0,
		    op_table=>1,
		    op_dyncontent=>0,
		},
		value=>$template_html,
		required=>1,
		prompt=>"Layout",
	);
    $db->input_htmleditor(%opt);
    $out .= $form->make;

    my $br = $ml->br;
    my $simple_template;
    my $table_template;
    while (my $q = $f->questions->next()) {
	my $qname = $q->qname();
	$simple_template .= $ml->p("[[$qname:prompt]]${br}[[$qname:input]]");
	$table_template .= $ml->tr(
	    $ml->td("[[$qname:prompt]]",{class=>"prompt"}).
	    $ml->td("[[$qname:input]]",{class=>"input"})
	    );
    }
    $table_template = $ml->table($table_template,{class=>"Form"});
    my $br = $ml->br;
    $out .= $ml->h2("Instructions");
    $out .= $ml->p("Use merge codes to place the prompt and input fields for each of your form inputs. To place the input field, use ".$ml->code("[[name:input]]").". To place the prompt/label string, use ".$ml->code("[[name:prompt]]")." - replace \"name\" with the short name of the input field.");
    $out .= $ml->p("Example layouts are shown below (click to open). You can copy these using cut-and-paste, and then modify to suit.");
    $out .= &ExSite::HTML::AccordionBox(titles=>["Simple Layout","Two-column Table"],
					panes=>[$simple_template,$table_template],
					states=>[0,0],);
    return $out;
}

sub configure_form {
    my ($this,$f) = @_;
    my $db = $share{DB};
    my $out;

    # configuration
    
    my $post = $this->{post};
    if (scalar keys %$post > 0) {
	if (! $post->{_qakey}) {
	    # config form was submitted
	    $out .= $f->do_edit();
	    $ml->location($this->link(qacmd=>undef,__plaintext=>1));
	}
    }
    $out .= $f->edit(action=>$this->link());
    return $ml->h1("Configure Form") . $out;
}

sub edit_form {
    my $this = shift;
    my $post = $this->{post};
    my $query = $this->{query};
    my $out;
    if (scalar keys %$post > 0) {
	if ($post->{submit_action} eq "Cancel") {
	    $ml->location($this->link(qb=>undef,__plaintext=>1));
	    return undef;
	}
	my $db = $share{DB};
	$db->get_data();
	$db->get_action();
	my @err = $db->validate();
	if (@err > 0) {
	    $out = $ml->h3("Problem:");
	    $out .= $this->error(@err);
	    $out .= $ml->p($ml->a("&lt; Back",{href=>"javascript:history.back()"}));
	}
	else {
	    my $fid = $this->{form}->id();
	    my $stat = $db->update("qa_form",$db->{form}{qa_form}{$fid});
	    if ($stat) {
		$out = $ml->h3("Problem:");
		$out .= $this->show_diagnostics("error","html");
		$out .= $ml->p($ml->a("&lt; Back",{href=>"javascript:history.back()"}));
	    }
	    else {
		$ml->location($this->link(qacmd=>undef,q=>undef,qb=>undef,__plaintext=>1));
	    }
	}
    }
    else {
	my $f = $this->{form};
	$out .= $ml->h1("Configure Form");
	$out .= $f->edit( action=>$this->link() );
    }

    return $out;
}

sub copy_form {
    my ($this,$f) = @_;
    if ($f->defined) {
	my $newformid = $f->copy;
	if ($newformid) {
	    my $url = $this->link(qacmd=>undef,form=>$newformid,__plaintext=>1);
	    $ml->location($url);
	    return $ml->p("Form copied. ".$ml->a("Click here to continue.",{href=>$url}));
	}
	else {
	    return &ExSite::Config::show_diagnostics();
	}
    }
    return $this->error("cannot copy a non-existent form");
}

sub publish_form {
    my ($this,$f) = @_;
    my $out = $ml->h1("Publish Form");
    if (! $this->{input}{section_id}) {
	$out .= $this->error("No section selected; cannot publish.");
	return $out;
    }
    my $spage = &ExSite::Module::service_page("QA",$this->{input}{section_id});
    if ($spage) {
	my $link = $spage->link(form=>$f->id);
	$out .= $ml->p("This form is automatically available at the following URL:".$ml->br.
		       $ml->a($spage->link(form=>$f->id),{href=>$spage->link(form=>$f->id),target=>"_blank"}));
    }
    my $post = $this->{post};
    if (scalar keys %$post > 0) {
	# publish the form
	my $formid = $f->id;
	my $page = new ExSite::Page();
	my $body = "<!--&QA(form=$formid)-->";
	if (! $f->getdata("template")) {
	    # no custom formatting; jazz it up with a title 
	    $body = $ml->h1($f->name) . $body;
	}
	my $pdata = $f->flag("members-only") ?
	{ access=>"members", publish_method=>"dynamic", label=>$post->{name} } : $post->{name};
	my $pid = $page->quick_make_page($pdata,$body);
	if ($pid) {
	    $page->setup(id=>$pid);
	    $out .= $ml->p("Created page ".$ml->a($page->filename,{href=>$page->get_url(),target=>"_blank"}));
	    $out .= $ml->p($ml->a("edit page",{href=>$page->link(_cms=>1),target=>"_blank",class=>"button"}));
	}
	else {
	    $out .= $page->show_diagnostics("error","html");
	    $out .= $ml->p(&ExSite::HTML::BackButton(label=>"retry"));
	}
    }
    else {
	if ($spage) {
	    $out .= $ml->p("In addition to this URL, you can optionally create a dedicated page for this form:");
	}
	my $fb = new ExSite::FormBuilder();
	my $name = $f->name;
	if (length $name > 40) {
	    $name = substr($name,0,40);
	}
	$fb->input(prompt=>"Page title",name=>"name",value=>$name,type=>"text",required=>1,maxlen=>40,size=>40);
	$fb->set("buttons",$ml->input(undef,{type=>"submit",value=>"create page"}));
	$out .= $fb->make();
    }
    return $out;
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
	    if ($input =~ /^qa_reorder_id=(\d+)$/) {
		push @sort, $1;
	    }
	}
	my $order = 0;
	my %q = $qlist ? $qlist->hash("qa_question_id") : ();
	foreach my $qid (@sort) {
	    $order++;
	    my $q = $q{$qid};
	    if ($q) {
		$q->setdata("sortkey",$order);
		$q->save;
#		$out .= $ml->p("Changed ".$q->id." from ".$q->getdata("sortkey")." to $order");
	    }
	}
	$out .= $this->info("Re-ordered $order items.");
	$f->unload();
	$qlist = $f->questions();
    }
    my @order;
    if ($qlist) {
	$qlist->reset;
	while (my $q = $qlist->next()) {
	    push @order, $q->show().$ml->input(undef,{type=>"hidden",name=>"qa_reorder_id",value=>$q->id});
	}
    }
    if (scalar @order > 1) {
	$out .= $ml->h1("Re-order questions");
	$out .= $ml->p("Drag questions into their new order, then click the save button.");
	$out .= &ExSite::HTML::js();
	$out .= $ml->script('
$(function() {
  $( "#sortable" ).sortable();
  $( "#sortable" ).disableSelection();
});
');
	if ($f->getdata("template")) {
	    $out .= &ExSite::HTML::ErrorBox(title=>"Warning",
					    pane=>"This form has a custom layout, which will override the ordering you specify here.".$ml->br."The ordering here will still control the ordering in reports.");
	}
	$out .= $ml->form(
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

sub reorder_old {
    my $this = shift;
    my $f = $this->{form};
    my $qid = $this->{question}->id;
    my $dir = $this->{input}{qacmd};

    # get the current sort order
    my @qsort;
    my $questions = $f->questions();
    $questions->reset();
    my $qpos;
    while (my $q = $questions->next()) {
	push @qsort, $q;
	if ($q->id == $qid) { $qpos = $#qsort; }
    }

    # reorder
    if ($dir eq "down") {
	if ($qpos < $#qsort) {
	    my $qtmp = $qsort[$qpos + 1];
	    $qsort[$qpos + 1] = $qsort[$qpos];
	    $qsort[$qpos] = $qtmp;
	}
    }
    else { #if ($dir eq "up") {
	if ($qpos > 0) {
	    my $qtmp = $qsort[$qpos - 1];
	    $qsort[$qpos - 1] = $qsort[$qpos];
	    $qsort[$qpos] = $qtmp;
	}
    }

    # adjust sortkeys to preserve new order
    
    my $qprev;
    foreach my $q (@qsort) {
	if ($qprev) {
	    my $sort = $q->getdata("sortkey");
	    my $prevsort = $qprev->getdata("sortkey");
	    my $qid = $q->id;
	    my $qprevid = $qprev->id;
	    if ($sort lt $prevsort || 
		($sort eq $prevsort && $qid < $qprevid)) {
		# incorrect sort order
		my $newsortkey = ($qid > $qprevid) ? $prevsort : $prevsort + 1;
		$q->setdata("sortkey", $newsortkey);
		$q->save();
	    }
	}
	$qprev = $q;
    }

    # refresh form view
    $ml->location($this->link(qacmd=>"questions",q=>undef,__plaintext=>1));
}

sub new_lib {
    my ($this) = @_;
    my $post = $this->{post};
    my $out;
    my $f = new Modules::QA::Library();
    if (scalar keys %$post > 0) {
	if ($post->{submit_action} eq "Cancel") {
	    $ml->location($this->link(qacmd=>undef,__plaintext=>1));
	    return undef;
	}
	my $db = $share{DB};
	$db->get_data();
	$db->get_action();
	my @err = $db->validate();
	if (@err > 0) {
	    $out = $ml->h3("Problem:");
	    $out .= $this->error(@err);
	    $out .= $ml->p($ml->a("Go back to form.",{href=>"javascript:history.back()"}));
	}
	else {
	    my $qalibid = $db->insert("qa_lib",$db->{form}{qa_lib}{_});
	    if ($qalibid) {
		$ml->location($this->link(lib=>$qalibid,form=>undef,qacmd=>undef,__plaintext=>1));
	    }
	    else {
		$out = $ml->h3("Problem:");
		$out .= $this->show_diagnostics("error","html");
		$out .= $ml->p($ml->a("&lt; Back",{href=>"javascript:history.back()"}));
	    }
	}
    }
    else {
	$out .= $ml->h1("New Question Library");
	my $f = new Modules::QA::Library();
	$out .= $f->make(action=>$this->link(),data=>{section_id=>$this->{section_id}},hide=>["section_id"]);
    }
}

sub edit_lib {
    my ($this) = @_;
    my $post = $this->{post};
    my $out;
    my $f = new Modules::QA::Library();
    if (scalar keys %$post > 0) {
	if ($post->{submit_action} eq "Cancel") {
	    $ml->location($this->link(qacmd=>undef,__plaintext=>1));
	    return undef;
	}
	my $db = $share{DB};
	$db->get_data();
	$db->get_action();
	my @err = $db->validate();
	if (@err > 0) {
	    $out = $ml->h3("Problem:");
	    $out .= $this->error(@err);
	    $out .= $ml->p($ml->a("Go back to form.",{href=>"javascript:history.back()"}));
	}
	else {
	    my $status = $db->update("qa_lib",$db->{form}{qa_lib}{$this->{input}{lib}});
	    if ($status) {
		$out = $ml->h3("Problem:");
		$out .= &ExSite::Config::show_diagnostics();
		$out .= $ml->p($ml->a("&lt; Back",{href=>"javascript:history.back()"}));
	    }
	    else {
		# success
 		$ml->location($this->link(lib=>$this->{input}{lib},form=>undef,qacmd=>undef,__plaintext=>1));
	    }
	}
    }
    else {
	$out .= $ml->h1("Reconfigure Question Library");
	my $f = new Modules::QA::Library(id=>$this->{input}{lib});
	$out .= $f->edit(action=>$this->link(),hide=>["section_id"]);
    }
}

sub new_base_question {
    my $this = shift;
    my $post = $this->{post};
    my $out;
    if (scalar keys %$post > 0) {
	if ($post->{submit_action} eq "Cancel") {
	    $ml->location($this->link(qacmd=>undef,__plaintext=>1));
	    return undef;
	}
	my $db = $share{DB};
	$db->get_data();
	$db->get_action();
	my @err = $db->validate();
	if (@err > 0) {
	    $out = $ml->h3("Problem:");
	    $out .= $this->error(@err);
	    $out .= $ml->p($ml->a("&lt; Back",{href=>"javascript:history.back()"}));
	}
	else {
	    my $qbid = $db->insert("qa_base",$db->{form}{qa_base}{_});
	    if ($qbid) {
		if ($this->{input}{form}) {
		    # hopefully this sends the user back to form mgmt
		    $ml->location($this->link(lib=>undef,__plaintext=>1));
		}
		else {
		    $ml->location($this->link(qacmd=>undef,__plaintext=>1));
		}
	    }
	    else {
		$out = $ml->h3("Problem:");
		$out .= $this->show_diagnostics("error","html");
		$out .= $ml->p($ml->a("&lt; Back",{href=>"javascript:history.back()"}));
	    }
	}
    }
    else {
	$out = $ml->h1("Create new question");
	my $lib = new Modules::QA::Base();
	$out .= $lib->make(action=>$this->link(),data=>{qa_lib_id=>$this->{input}{lib}});
    }
    return $out;
}

sub new_base_label {
    my $this = shift;
    my $post = $this->{post};
    my $out;
    if (scalar keys %$post > 0) {
	if ($post->{submit_action} eq "Cancel") {
	    $ml->location($this->link(qacmd=>undef,__plaintext=>1));
	    return undef;
	}
	my $db = $share{DB};
	$db->get_data();
	$db->get_action();
	my @err = $db->validate();
	if (@err > 0) {
	    $out = $ml->h3("Problem:");
	    $out .= $this->error(@err);
	    $out .= $ml->p($ml->a("&lt; Back",{href=>"javascript:history.back()"}));
	}
	else {
	    my $qbid = $db->insert("qa_base",$db->{form}{qa_base}{_});
	    if ($qbid) {
		if ($this->{input}{form}) {
		    # hopefully this sends the user back to form mgmt
		    $ml->location($this->link(lib=>undef,__plaintext=>1));
		}
		else {
		    $ml->location($this->link(qacmd=>undef,__plaintext=>1));
		}
	    }
	    else {
		$out = $ml->h3("Problem:");
		$out .= $this->show_diagnostics("error","html");
		$out .= $ml->p($ml->a("&lt; Back",{href=>"javascript:history.back()"}));
	    }
	}
    }
    else {
	$out = $ml->h1("Create new label/section break");
	$out .= &ExSite::HTML::HelpBox(
	    title=>"What is a label or section break?",
	    pane=>$ml->p("A label or section break is a pseudo-question: it can be managed and placed in your forms like any other question, but it is not actually a question and doesn't ask for any input. You can use this to add instructions, headings, or other text into the middle of your forms.").
	    $ml->p("There are two ways to format your text:").
	    $ml->ol(["Like a regular question: simply provide text in the question and answer fields below, and those will be placed exactly where the question prompt and input field would go in a normal question.",
		     "Preformatted: include HTML formatting codes in your text below, and those will be used instead of the usual question formatting."])
	    );
	my $fb = new ExSite::FormBuilder(action=>$this->link(),method=>"post");
	$fb->input(type=>"hidden",name=>"qa_base##qa_lib_id",value=>$this->{input}{lib});
	$fb->input(type=>"radio",name=>"qa_base##format",options=>[["label","use regular question formatting"],["preformatted","formatting is already included below"]],prompt=>"Formatting",required=>1);
	$fb->input(type=>"text",name=>"qa_base##label",prompt=>"Prompt",size=>40);
	$fb->input(type=>"textarea",name=>"qa_base##value",prompt=>"Question");
	$out .= $fb->make();
    }
    return $out;
}

sub base_question {
    my $this = shift;
    my $db = $share{DB};
    my $post = $this->{post};
    my $out;
    if ($this->{input}{qacmd} eq "del") {
	$this->{qb}->delete();
	$ml->location($this->link(qb=>undef,qacmd=>undef,__plaintext=>1));
    }
    if (scalar keys %$post > 0) {
	if ($post->{submit_action} eq "Cancel") {
	    $ml->location($this->link(qacmd=>undef,__plaintext=>1));
	    return undef;
	}
	$db->get_data();
	$db->get_action();
	my @err = $db->validate();
	if (@err > 0) {
	    $out = $ml->h3("Problem:");
	    $out .= $this->error(@err);
	    $out .= $ml->p($ml->a("&lt; Back",{href=>"javascript:history.back()"}));
	}
	else {
	    my $qbid = $this->{qb}->id;
	    my $stat = $db->update("qa_base",$db->{form}{qa_base}{$qbid});
	    if ($stat) {
		$out = $ml->h3("Problem:");
		$out .= $this->show_diagnostics("error","html");
		$out .= $ml->p($ml->a("&lt; Back",{href=>"javascript:history.back()"}));
	    }
	    else {
		$ml->location($this->link(qacmd=>undef,__plaintext=>1));
	    }
	}
    }
    else {
	my $qb = $this->{qb};
	my $del;
	my @f = $db->get_query("forms using base question",$qb->id);
	if (@f > 0) {
	    $del .= $ml->p("This question is currently being used by the following forms:");
	    my $forms;
	    foreach my $f (@f) {
		my $f = new Modules::QA::Form(data=>$f);
		$forms .= $ml->li(
				  $ml->a($f->name,{href=>$this->link(qacmd=>undef,lib=>undef,qb=>undef,form=>$f->id)})
				  );
	    }
	    $del .= $ml->ul($forms);
	    $del .= $ml->p("Deleting this question may damage those forms and/or the responses they have already collected.");
	}
	else {
	    $del .= $ml->p("This question is not in use at this time, and is safe to delete.");
	}
	$del .= &ExSite::HTML::Button(label=>"DELETE this question",
					url=>$this->link(qacmd=>"del"),
					type=>"button");
	$out .= &ExSite::HTML::AccordionBox(
					    titles=>["Preview","Details","Translations","Edit","Delete"],
					    panes=>[
						    $qb->show(),
						    $qb->report(),
						    $this->show_translations(),
						    $qb->edit(action=>$this->link()),
						    $del
						    ],
					    states=>[1,1,0,0,0]
					    );
    }
    return $out;
}

sub show_translations {
    my $this = shift;
    my $r = new ExSite::ReportBuilder(title=>"Translations");
    $r->headers(["Version","Translated Question","Translated Answers"]);
    my @version = split(/\|/,$share{DB}{map}->regexp("list:version"));
    my $qb = $this->{qb};
    foreach my $v (@version) {
	my $tr = $qb->translation($v);
	my $label = $tr->{label} || "[missing]";
	my $value = $tr->{value} || ($qb->getdata("value") ? "[missing]" : "[n/a]");
	my $url = $this->link(qacmd=>"trans",tr=>$qb->{translation}{$v}{qa_translation_id});
	$r->push(
		 $v,
		 $ml->a($label,{href=>$url}),
		 $ml->a($value,{href=>$url}),
		 );
    }
    $r->foot("Click on the question or answer to update the translation.");
    return $r->make();
}

sub translate {
    my $this = shift;
    my $db = $share{DB};
    my $post = $this->{post};
    my $out;
    if (scalar keys %$post > 0) {
	if ($post->{version}) {
	    my $old_tr = $this->{qb}->translation($post->{version});
	    if ($old_tr) {
		$old_tr->{label} = $post->{label};
		$old_tr->{value} = $post->{value};
		my $stat = $db->update("qa_translation",$old_tr);
	    }
	    else {
		my $qbid = $this->{qb}->id;
		my %tr = (
			  label=>$post->{label},
			  value=>$post->{value},
			  version=>$post->{version},
			  qa_base_id=>$qbid,
			  );
		my $trid = $db->insert("qa_translation",\%tr);
	    }
	    $ml->location($this->link(qacmd=>undef,__plaintext=>1));
	}
    }
    else {
	# no translation - make one
	$out .= $ml->h1("$config{default_version} Version");
	my $qdata = $ml->tr(
			    $ml->th("Question:").
			    $ml->td(
				    $ml->textarea($this->{qb}->label,{cols=>80,rows=>4,readonly=>undef})
				    )
			    );
	my $ans = $this->{qb}->showdata("value");
	if ($ans) {
	    $qdata .= $ml->tr(
			      $ml->th("Answers:").
			      $ml->td(
				      $ml->textarea($ans,{cols=>80,rows=>4,readonly=>undef})
				      )
			      );
	}
	$out .= $ml->table($qdata);
    }
    my @version = split /\|/, $share{DB}{map}->regexp("list:version");
    foreach my $version (@version) {
	$out .= $this->translate_version($version);
    }
    
    return $out;
}

sub translate_version {
    my ($this,$version) = @_;
    my $out .= $ml->h1($ml->em($version)." Version");
    $this->{qb}->set("version",$version);
    $this->{qb}->load_translations();
    my $qdata = $ml->tr(
			$ml->th("Question:").
			$ml->td(
				$ml->textarea($this->{qb}->label,{name=>"label",cols=>80,rows=>4})
				)
			);
    my $ans = $this->{qb}->value();
    if ($ans) {
	$qdata .= $ml->tr(
			  $ml->th("Answers:").
			  $ml->td(
				  $ml->textarea($ans,{name=>"value",cols=>80,rows=>4})
				  )
			  );
    }
    $qdata .= $ml->tr(
		      $ml->td().
		      $ml->td(
			      $ml->input(undef,{type=>"submit",value=>"Update $version version"})
			      )
		      );
    $out .= $ml->form(
		      $ml->table($qdata).
		      $ml->input(undef,{type=>"hidden",name=>"version",value=>$version}),
		      {method=>"post",action=>$this->link()}
		      );
    return $out;
}

sub add_question {
    my $this = shift;
    my $post = $this->{post};
    my $query = $this->{query};
    my $out;
    if (scalar keys %$post > 0) {
	if ($post->{submit_action} eq "Cancel") {
	    $ml->location($this->link(qb=>undef,q=>undef,__plaintext=>1));
	    return undef;
	}
	my $db = $share{DB};
	$db->get_data();
	$db->get_action();
	my @err = $db->validate();
	if (@err > 0) {
	    $out = $ml->h3("Problem:");
	    $out .= $this->error(@err);
	    $out .= $ml->p($ml->a("&lt; Back",{href=>"javascript:history.back()"}));
	}
	else {
	    my $stat = $db->insert("qa_question",$db->{form}{qa_question}{_});
	    if ($stat) {
		#$ml->location($this->link(qacmd=>"questions",qb=>undef,q=>undef,__plaintext=>1));
		$ml->location($this->link(qb=>undef,q=>undef,__plaintext=>1));
	    }
	    else {
		$out = $ml->h3("Problem:");
		$out .= $this->show_diagnostics("error","html");
		$out .= $ml->p($ml->a("&lt; Back",{href=>"javascript:history.back()"}));
	    }
	}
    }
    elsif ($query->{qb} && $query->{form}) {
	my $q = new Modules::QA::Question();
	$out .= $ml->h1("New Question");
	$out .= $ml->p("Adding ".
		       $ml->em($this->{qb}->label).
		       " to ".
		       $ml->em($this->{form}->name));
	$out .= $ml->h2("Advanced Options");
	$out .= $q->make(
			 data=>{
			     qa_base_id=>$this->{qb}->id,
			     qa_form_id=>$this->{form}->id,
			 },
			 hide=>[
				"qa_form_id", "qa_base_id",
				],
			 action=>$this->link(),
			 );
    }
    else {
	# flag all base questions that have been used
	my $fquestions = $this->{form}->questions();
	my %fbq;
	while (my $fq = $fquestions->next) {
	    $fbq{$fq->getdata("qa_base_id")} = $fq;
	}

	$out .= $ml->h1("Select question");
	$out .= $ml->p("Click on a question to add it to your form. Checked questions have already been added, but can be added again if you need more than one instance of the question.");
	my $warnout;
	my $libs = $this->my_libs();
	while (my $lib = $libs->next()) {
	    my $owns_lib = $this->owns_lib($lib);
	    my $libtype = $lib->getdata("type");
	    if ($libtype && $libtype ne "other" && 
		$libtype ne $this->{form}->getdata("type")) {
		$warnout .= $ml->p($ml->em($lib->name)." questions are not availble to this type of form.");
		next;
	    }
	    my $questions = $lib->questions();
	    my $qlist;
	    if ($questions) {
		while (my $q = $questions->next()) {
		    my $icon;
		    if ($fbq{$q->id}) {
			$icon = " ".&ExSite::HTML::ToolIcon(name=>"approve",label=>"added");
		    }
		    $qlist .= $ml->li(
			$ml->a($q->name(),{href=>$this->link(qb=>$q->id)})." ".
			&ExSite::HTML::ResponsivePopup(label=>"[preview]",pane=>$q->show()).
			$icon.
			$ml->br
			);
		}
		if ($owns_lib) {
		    $qlist .= $ml->li($ml->a("+ add a new question to ".$ml->em($lib->name),{href=>$this->link(lib=>$lib->id),class=>"liblink"}));
		    $qlist .= $ml->li($ml->a("+ add a label/section break to ".$ml->em($lib->name),{href=>$this->link(qacmd=>"newlab",lib=>$lib->id),class=>"liblink"}));
		}
	    }
	    if ($qlist) {
		$out .= 
		    $ml->h2($lib->name).
		    $ml->ul($qlist);
	    }
	    if ($warnout) {
		$out .= $warnout;
	    }
	}
    }

    return $out;
}

sub question {
    my $this = shift;
    my $post = $this->{post};
    my $query = $this->{query};
    my $out;
    if ($this->{input}{qacmd} eq "del") {
	$this->{question}->delete();
	$ml->location($this->link(qb=>undef,tr=>undef,q=>undef,qacmd=>undef,__plaintext=>1));
    }
    if (scalar keys %$post > 0) {
	if ($post->{submit_action} eq "Cancel") {
	    $ml->location($this->link(qb=>undef,__plaintext=>1));
	    return undef;
	}
	my $db = $share{DB};
	$db->get_data();
	$db->get_action();
	my @err = $db->validate();
	if (@err > 0) {
	    $out = $ml->h3("Problem:");
	    $out .= $this->error(@err);
	    $out .= $ml->p($ml->a("&lt; Back",{href=>"javascript:history.back()"}));
	}
	else {
	    my $qid = $this->{question}->id();
	    my $stat = $db->update("qa_question",$db->{form}{qa_question}{$qid});
	    if ($stat) {
		$out = $ml->h3("Problem:");
		$out .= $this->show_diagnostics("error","html");
		$out .= $ml->p($ml->a("&lt; Back",{href=>"javascript:history.back()"}));
	    }
	    else {
		$ml->location($this->link(qacmd=>undef,q=>undef,qb=>undef,__plaintext=>1));
	    }
	}
    }
    else {
	my $q = $this->{question};
	$out .= &ExSite::HTML::FrameBox(title=>"Preview",pane=>$q->show(),bgcolor=>"#eee",color=>"#999");
	$out .= $ml->p(
		       &ExSite::HTML::Button(label=>"REMOVE this question from this form",
					     url=>$this->link(qacmd=>"del"),
					     type=>"button")
		       );
	$out .= $ml->h1("Configure Question");
	$out .= $q->edit(hide=>["qa_form_id"],
			 action=>$this->link() );
	$out .= $ml->p("These settings affect the question in this form only.".
		       $ml->br."To reconfigure the generic question, ".
		       $ml->a("go here",{href=>$this->link(qb=>$this->{question}->base->id,lib=>$this->{question}->base->getdata("qa_lib_id"))}).
		       ".");
    }

    return $out;
}

sub get_responses {
    my ($this,$form) = @_;
    my $responses = new ExSite::ObjectList(type=>"qa_response");
    $responses->load({qa_form_id=>$form->id},"ctime desc");
    # preload all answers for faster lookups
    my @answers = $share{DB}->get_query("answers to form",$form->id);
    # group the answers by response
    $share{QA_cache} = {};
    foreach my $a (@answers) {
	my $rid = $a->{qa_response_id};
	if (! exists $share{QA_cache}{"response:$rid"}) {
	    $share{QA_cache}{"response:$rid"} = [ $a ];
	}
	else {
	    push @{$share{QA_cache}{"response:$rid"}}, $a;
	}
    }
    return $responses;
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
	$response{$a->{qa_response_id}}{$a->{qa_question_id}} = $a;
    }

    # generate the report
    my $rpt = new ExSite::ReportBuilder(title=>"Responses - ".$form->name);
    $rpt->set("dynamic",1);
    my @head = $options ? ('Options') : ();
    if ($config{QA}{report_form_name}) {
	push @head, 'Form';
    }
    push @head, qw(Response Date Member Language);
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
	        $ml->a("view",{href=>$this->link(response=>$rid),class=>"button_sm"}).
		$ml->a("edit",{href=>$this->link(qacmd=>"edit_response",response=>$rid),class=>"button_sm"}).
		$ml->a("delete",{href=>"javascript:confirm_custom('Really delete response $rid?','".$this->link(qacmd=>"del",response=>$rid)."')",class=>"button_sm"});
	}
	if ($config{QA}{report_form_name}) {
	    push @data, $form->name;
	}
	my $user;
	my $uid = $r1->{member_id};
	if ($uid) {
	    if ($member{$uid}) {
		$user = $member{$uid};
	    }
	    else {
		$user = $share{DB}->user_name($uid);
		$member{$uid} = $user;
	    }
	}
	push @data, $rid, $r1->{ctime}, $user, $r1->{version};
	my $questions = $form->questions;
	$questions->reset;
	while (my $q = $questions->next) {
	    next if (! $q->is_question); # skip labels/section breaks
	    if (scalar keys %$match > 0) {
		my $qname = $q->qname;
		if ($match->{$qname}) {
		    # abort row if no match
		    next RESPONSE if ($response{$rid}{$q->id}{answer} !~ /$match->{$qname}/);
		}
	    }
	    my $datatype = $response{$rid}{$q->id}{value};
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

# this version doesn't do matching/filtering

sub get_response_report_2 {
    my ($this,$form,$options) = @_;

    # organize the response data
    my $answers = $form->get_all_answers();
    my %response;
    foreach my $a (@$answers) {
	$response{$a->{qa_response_id}}{$a->{qa_question_id}} = $a;
    }

    # generate the report
    my $rpt = new ExSite::ReportBuilder(title=>"Responses - ".$form->name);
    $rpt->set("dynamic",1);
    my @head = $options ? ('Options') : ();
    if ($config{QA}{report_form_name}) {
	push @head, 'Form';
    }
    push @head, qw(Response Date Member Language);
    push @head, $this->question_labels($form);
    $rpt->headers(\@head);
    $rpt->tools("Export: ".
		$ml->a("excel",{href=>$this->link(qacmd=>"export")})." ".
		$ml->a("csv",{href=>$this->link(qacmd=>"export",format=>"csv")})." ".
		$ml->a("html",{href=>$this->link(qacmd=>"export",format=>"html")})
		);
    my %member;
    foreach my $rid (sort {$b <=> $a} keys %response) { # most recent first
	my @data;
	if ($options) {
	    push @data, 
	        $ml->a("view",{href=>$this->link(response=>$rid),class=>"button_sm"}).
		$ml->a("edit",{href=>$this->link(qacmd=>"edit_response",response=>$rid),class=>"button_sm"}).
		$ml->a("delete",{href=>"javascript:confirm_custom('Really delete response $rid?','".$this->link(qacmd=>"del",response=>$rid)."')",class=>"button_sm"});
	}
	if ($config{QA}{report_form_name}) {
	    push @data, $form->name;
	}
	my @qid = keys %{$response{$rid}};
	my $r1 = $response{$rid}{$qid[0]}; # 1st answer in response
	my $user;
	my $uid = $r1->{member_id};
	if ($uid) {
	    if ($member{$uid}) {
		$user = $member{$uid};
	    }
	    else {
		$user = $share{DB}->user_name($uid);
		$member{$uid} = $user;
	    }
	}
	push @data, $rid, $r1->{ctime}, $user, $r1->{version};
	my $questions = $form->questions;
	$questions->reset;
	while (my $q = $questions->next) {
	    next if (! $q->is_question); # skip labels/section breaks
	    my $datatype = $response{$rid}{$q->id}{value};
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
    if ($form->defined) {
	$form->{list}->reset();
	while (my $q = $form->{list}->next()) {
	    next if (! $q->is_question);  # skip labels/section breaks
	    #push @label, $q->label();
	    push @label, $q->name();
	}
    }
    return @label;
}

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
	    $response{$a->{qa_response_id}} = 1;
	    next if ($fmt eq "label");
	    if ($fmt =~ /^(string|textarea|password)$/) {
		# freeform - simply count the answers
		$summary{$a->{label}}{answered}++;
	    }
	    elsif ($fmt =~ /^(multiselect|checklist)/) {
		# multiselect - may be several answers combined
		my @ans = split /$config{form}{multi_sep}/, $a->{answer};
		foreach my $ans (@ans) {
		    $summary{$a->{label}}{$ans}++;
		}
	    }
	    else {
		# fixed format - bin the answers
		$summary{$a->{label}}{$a->{answer}}++;
	    }
	}
	$n_response = scalar keys %response;
	my $questions = $form->questions();
	while (my $q = $questions->next()) {
	    my @data;
	    push @data, $q->label;
	    my $fmt = $q->format();
	    next if ($fmt eq "label");
	    if ($fmt =~ /^(string|textarea|password)$/) {
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
	    else {
		# fixed format - display each bin separately
		my @val = $q->answer_values();
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
		    $rpt->push(@data);
		}
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
    my $r = $this->get_response_report($f,!$fmt);
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
#		 url=>$this->link(qacmd=>"delall"),
#		 confirm=>"Really delete all responses?",
#	    ));
	return $out;
    }
}

sub show_response {
    my ($this,$response_id) = @_;
    my $r = new Modules::QA::Response(id=>$response_id);
    if ($this->{input}{qacmd} eq "del") {
	$r->delete();
	$ml->redirect($this->link(qacmd=>"responses",response=>undef,__plaintext=>1));
	return;
    }
    else {
	return $r->show(
	    admin=>1,
	    tools=>
	    $ml->a("edit",{href=>$this->link(qacmd=>"edit_response"),class=>"button_sm"}).
	    $ml->a("delete",{href=>"javascript:confirm_custom('Really delete this response?','".$this->link(qacmd=>"del")."')",class=>"button_sm"})
	    );
    }
}

#### deprecated
sub export_responses_old {
    my ($this,$f) = @_;
    my $formid = $f->id;
    my $fmt = $this->{input}{format};
    my $r = $this->get_response_report($f,0); # no options
    $ml->cancel();
    if ($fmt =~ /csv/) {
	print "Content-type: text/comma-separated-values\ncontent-disposition: attachment; filename=responses-$formid.csv\n\n";
	print $r->export("csv");
    }
    elsif ($fmt =~ /html/) {
	$r->set("dynamic",0);
	$r->tools(undef);
	print "Content-type: text/html\n\n";
	print $r->make();
    }
    else {
	print "Content-type: application/vnd.ms-excel\n";
	print "Content-disposition: attachment; filename=responses-$formid.xls\n\n";
	$r->export("excel");
    }
    return undef;
}

sub filter_responses {
    my ($this,$form) = @_;
    my $out;
    my $post = $this->{input}; # normally post, but get on exports

    my $f = new ExSite::FormBuilder();
    $f->template(
	$ml->p($ml->strong("Select only responses received within this date range:")).
	$ml->table(
	    $ml->tr(
		$ml->td("[[filter_date_start:prompt]]".$ml->br."[[filter_date_start:input]]").
		$ml->td("[[filter_date_end:prompt]]".$ml->br."[[filter_date_end:input]]")
	    ),
	    {class=>'filterdates'}
	)
	);
    $f->input(name=>"filter_date_start",prompt=>"Start Date",value=>$post->{filter_date_start},size=>12,class=>"date-pick");
    $f->input(name=>"filter_date_end",prompt=>"End Date",value=>$post->{filter_date_end},size=>12,class=>"date-pick");

    $f->input(name=>"filters",input=>$ml->p($ml->strong("Select only responses matching the following answers:")),type=>"preformatted");
    my $qlist = $form->questions();
    while (my $q = $qlist->next) {
	if ($q->is_question()) {
	    $q->base->show(FormBuilder=>$f,required=>0,value=>$post->{$q->qname});
	}
    }

    $out .= &ExSite::HTML::AccordionBox(
	titles=>["Report Filters"],
	panes=>[$f->make()],
	states=>[! exists $post->{filter_date_start}]
	);

    if (exists $post->{filter_date_start}) {
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
    my $r = new Modules::QA::Response(id=>$response_id);
    if ($r->is_editable()) {
	my $f = $r->form;
	if ($f && $f->id == $form_id) {
	    return $f->show(response=>$response_id,action=>$action);
	}
	return $this->error("form - response mismatch");
    }
    return $this->error("Permission denied.");
}

sub doform {
    my ($this,$data,$goto) = @_;
    if ($data->{submit_action} eq "Cancel") {
	$ml->location($goto);
	return undef;
    }
    my $db = $share{DB};
    my $out;
    $db->get_data();
    $db->{action} = $db->get_action();
    
    my $errcnt = &AtError();
    $db->do_db($db->{action});

    # report results
    if (! &AtError($errcnt)) {
	# no errors
	$ml->location($goto) if $goto;
	$out .= "Done!";
    }
    else {
	# uh-oh!
	$out = $ml->h3("Problem:");
	$out .= $this->show_diagnostics("error","html");
	$out .= $ml->p($ml->a("Go back to form.",{href=>"javascript:history.back()"}));
    }
    return $out;
}

sub setup_querylib {
    my $this = shift;
    my $db = $share{DB};
    $db->set_query("forms using base question",
		   (sql=>"select distinct f.* from qa_form f,qa_question q,qa_base b where b.qa_base_id=q.qa_base_id and f.qa_form_id=q.qa_form_id and b.qa_base_id=?",
		    nparam=>1,
		    mode=>"r",
		    keys=>["qa_form","qa_question","qa_base"]
		    ));
    $db->set_query("answers to form",
		   (sql=>"select a.* from qa_answer a,qa_response r where a.qa_response_id=r.qa_response_id and r.qa_form_id=?",
		    nparam=>1,
		    mode=>"r",
		    keys=>["qa_question","qa_response"]
		    ));
    $db->set_query("untranslated questions",
		   (sql=>"select qa_base.* from qa_lib,qa_base left join qa_translation on qa_translation.qa_base_id=qa_base.qa_base_id where qa_base.qa_lib_id=qa_lib.qa_lib_id and qa_translation.qa_base_id is null and qa_lib.section_id=?",
		    nparam=>1,
		    mode=>"r",
		    keys=>["qa_lib","qa_base","qa_translation"]
		    ));
}

# scoped into Report class
sub show_foreign_key {
    my ($this,$table,$column,$data,$id,$datatype) = @_;
    return undef if ($table !~ /qa_form|qa_response/);
    # dereference foreign keys
    my (undef,$ftable) = split /[:=]/,$datatype;
    # look up foreign row
    my %fdata = $this->fetch($ftable,$data);
    my $fkey = $this->get_key($ftable);
    my $label = $this->record_label($ftable,$fdata{$fkey},\%fdata);
    return $label;
}

# new form wizard

sub new_form_wizard {
    my ($this) = @_;
    #$QA = $this;
    if ($this->{post}{qa_lib_id} && 
	$this->{post}{label} && 
	$this->{post}{format}) {
	# meta wizard step - add question
	return $this->newform_add_question();
    }
    my $wiz = new ExSite::Wizard(title=>"New Form",action=>$this->link());
    $wiz->add_step("Setup Form",\&newform1,\&do_newform1);
    $wiz->add_step("Select Questions",\&newform2,\&do_newform2);
    $wiz->add_step("Submission",\&newform3,\&do_newform3);
    $wiz->add_step("Preview",\&newform4);
    return $wiz->go;
}

# newform_add_question: receives jquery post from wizard step 2

sub newform_add_question {
    my $this = shift;
    my $out;
    if (scalar keys %{$this->{post}} > 0) {
	my $qabase = new Modules::QA::Base(data=>$this->{post});
	my $name = lc $this->{post}{label};
	$name =~ s/ /_/g;
	$name =~ s/_+/_/g;
	$name =~ s/_$//;
	if (length $name < 20) {
	    $qabase->setdata("name",$name);
	}
	my @err = $qabase->validate();
	if (@err > 0) {
	    $out = &ExSite::HTML::ErrorBox(title=>"Error",pane=>join($ml->br,@err));
	}
	else {
	    my $qbid = $qabase->save();
	    if ($qbid) {
		$out .= $ml->input(undef,{type=>"hidden",name=>"new_question_label",value=>$this->{post}{label}});
		$out .= $ml->input(undef,{type=>"hidden",name=>"new_question_id",value=>$qbid});
		$out .= $ml->input(undef,{type=>"hidden",name=>"new_qa_lib_id",value=>$this->{post}{qa_lib_id}});
		$out .= $ml->div("Question added!",{class=>"success"});
	    }
	    else {
		$out .= $share{DB}->show_diagnostics("error","html");
	    }
	}
    }
    $out .= $this->newform_new_question();
}

# newform_new_question: creates wizard new question subform

sub newform_new_question {
    my $this = shift;
    my $ml = &get_obj("ML");
    my @qlib = $share{DB}->fetch_match("qa_lib",{section_id=>$QA->{section_id}});
    my @libopt = map { $ml->option($_->{title},{value=>$_->{qa_lib_id}}) } @qlib;
    my @qtype = split /\|/,$share{DB}{map}->regexp("list:qa_format");
    my $out = 
	$ml->h1("Create a new question:").
	$ml->p("Type:".$ml->br.$ml->select(\@qtype,{name=>"new_format",id=>"new_format"})).
	$ml->p($ml->strong("Question:").$ml->br.$ml->input(undef,{type=>"text",name=>"new_prompt",size=>60})).
#	$ml->p("Placeholder text:".$ml->br.$ml->input(undef,{type=>"text",name=>"new_placeholder",id=>"new_placeholder",size=>60})).
	$ml->p("Input length:".$ml->br.$ml->input(undef,{type=>"text",name=>"new_size",id=>"new_size",size=>8})).
	$ml->p("Validate:".$ml->br.$ml->select(["any answer is okay","email","url","date (YYYY-MM-DD)","time (HH:MM)","integer","decimal","price"],{name=>"new_validate",id=>"new_validate"})).
	$ml->p("Allowed answers (separate with | character):".$ml->br.$ml->textarea(undef,{name=>"new_value",rows=>6,cols=>60,id=>"new_value",disabled=>undef}),{style=>"display:none;"}).
	$ml->p("Answer:".$ml->br.$ml->input(undef,{name=>"new_answer",id=>"new_answer",size=>60,disabled=>undef}),{style=>"display:none;"}).
	$ml->p("Organize this question under:".$ml->br.$ml->select(join("",@libopt),{name=>"new_lib"})).
	$ml->p($ml->button("+ Add question",{type=>"button",id=>"make_question"}));
    return $ml->div($out,{id=>"new_question"})
}

# wizards steps - scoped into Wizard class

sub newform1 {
    my ($this,$input) = @_;
    my $out .= &ExSite::HTML::HelpBox(pane=>"This wizard creates a new form from scratch.".$ml->br."Note that in some cases it may be faster to copy an existing form and modify it.");
#$ml->p("This wizard creates a new form from scratch.".$ml->br."Note that in some cases it may be faster to copy an existing form and modify it.");
    $share{DB}->input_exsite(prompt=>"Form type",name=>"type",datatype=>"list:qa_form_type",value=>"other",tail=>&ExSite::HTML::HelpPopup(label=>"help",message=>"Different questions may be available to different form types."));
    $share{DB}->input_exsite(prompt=>"Form title",name=>"title",datatype=>"string",size=>60,required=>1,tail=>&ExSite::HTML::HelpPopup(label=>"help",message=>"The title identifies this form in reports and control panels. It is not displayed on the form itself."));
    $share{DB}->input_exsite(prompt=>"Options",name=>"flags",datatype=>"set:qa_form_flags",tail=>&ExSite::HTML::HelpPopup(label=>"help",message=>"These options control form security. Members-only forms can only be used by logged-in users. Captchas and robot counter-measures try to prevent automated bots from using the forms. Confirmation screens show the answers to the user and require them to confirm before submitting. Single-submission forms only work with logged-in users; they will overwrite previous responses, rather than create a new response. Prepopulate with member data will try to prefill the form with information about the user."));
    $share{DB}->form->set("buttons"," ");  # skip default buttons
    $out .= $share{DB}->form->make_form_html();
}
sub do_newform1 {
    my ($this,$input) = @_;
    my @err;
    if (! $input->{title}) {
	push @err, "You did not title your form!";
    }
    return @err;
}

sub newform2 {
    my ($this,$input) = @_;
    my $out;
    if (! $share{js}{httprequest}) {
	$out .= $ml->script(undef,{src=>"$config{server}{HTMLpath}/_ExSite/js/httprequest.js"});
	$share{js}{httprequest} = 1;
    }
    my $warnout;
    my $libs = $QA->my_libs();
    my $oldout;
    my $newout;
    while (my $lib = $libs->next()) {
	my $libtype = $lib->getdata("type");
	if ($libtype && $libtype ne "other" && $libtype ne $input->{type}) {
	    $warnout .= $ml->p($ml->em($lib->name)." questions are not available to this type of form.");
	    next;
	}
	my $questions = $lib->questions();
	my $qlist;
	if ($questions) {
	    while (my $q = $questions->next()) {
		$qlist .= $ml->li(
		    $ml->span($q->name(),{class=>"select_question",id=>"qa_base_".$q->id})." ".
#		    &ExSite::HTML::Popup(label=>"[preview]",pane=>$q->show()).
		    $ml->br
		    );
	    }
	}
	if ($qlist) {
	    $oldout .= $ml->h2($lib->name).$ml->ul($qlist,{id=>"qa_lib_".$lib->id});
	}
	if ($warnout) {
	    $oldout .= $warnout;
	}
    }
    $out .= &ExSite::HTML::DynTabBox(tabs=>["Questions","New Question"],
				     panes=>[
					 &ExSite::HTML::ScrollBox(title=>"Click on a question to add it to the form.",pane=>$oldout,height=>"250px"),
					 $QA->newform_new_question()
				     ]);

    $out .= &ExSite::HTML::BlindBox(title=>"Selected Questions",
				    pane=>$ml->p("Check any questions that should be required.").$ml->ol(undef,{id=>"selected_questions"}));
    return $out;
}

sub do_newform2 {
    my ($this,$input) = @_;
    my @err = $QA->do_newform1($input);
    if (! $input->{question}) {
	push @err, "You did not add any questions to the form!";
    }
    return @err;
}

sub newform3 {
    my ($this,$input) = @_;
    my $out; # .= &ShowHash($input);
    $share{DB}->input_exsite(prompt=>"Message to respondents upon completion:",name=>"message",datatype=>"text",size=>400,tail=>&ExSite::HTML::HelpPopup(label=>"help",message=>"This message is displayed to the user after they submit the form. You can embed HTML codes here."));
    $share{DB}->input_exsite(prompt=>"Send notification e-mail to:",name=>"notify",datatype=>"string",size=>60,tail=>&ExSite::HTML::HelpPopup(label=>"help",message=>"Include one or more comma-separated email addresses here to receive a copy of each form response."));
    $share{DB}->form->set("buttons"," ");  # skip default buttons
    $out .= $share{DB}->form->make_form_html();
    return $out;
}
sub do_newform3 {
    my ($this,$input) = @_;
    my @err;
    # make the form
    my $f = new Modules::QA::Form(data=>{
	content_id=>$QA->{section_id},
	title=>$input->{title},
	type=>$input->{type},
	message=>$input->{message},
	notify=>$input->{notify},
	status=>"active"
				  });
    # flags
    my @flags;
    foreach my $key (keys %$input) {
	if ($key =~ /^flags#_set_\d/) {
	    push @flags, $input->{$key} if $input->{$key};
	}
    }
    $f->setdata("flags",join("; ",@flags)) if (scalar @flags > 0);
    if ($f->save()) {
	# add questions
	my $form_id = $f->id;
	my %r = map { $_ => 1 } split(/; /,$input->{required});
	foreach my $qid (split(/; /,$input->{question})) {
	    my $q = new Modules::QA::Question(data=>{
		qa_form_id=>$form_id,
		qa_base_id=>$qid,
					      });
	    if ($r{$qid}) {
		$q->setdata("flags","required");
	    }
	    $q->save() or push @err, "failed to add question ".$qid;
	}
	$f->load(); # load new questions
	$share{QA_newform} = $f;
    }
    else {
	push @err, "failed to save form";
    }
    return @err;
}

sub newform4 {
    my ($this,$input) = @_;
    
#    return &ShowHash($input);
    my $out;
    if ($share{QA_newform}) {
	my $f = $share{QA_newform}; #new Modules::QA::Form(id=>$share{QA_newform});
	$out .= $QA->show_form_toolbar($f);
	$out .= $ml->p("Your form is done. Here is a preview:",{class=>"success"});
	$out .= &ExSite::HTML::BasicBox(title=>"Preview",pane=>$f->show());
    }
    else {
	$this->error("New form not found.");
	$out .= &ExSite::Config::show_diagnostics();
    }
    return $out;
}

1;
