package Modules::Content;

#----------------------------------------------------------------------------
#
#   Copyright (C) 2012 - Exware Solutions, Inc.  http://www.exware.com
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
#  Provides a common suite of re-usable functions for handling content as
#  or in a plugin module.
#
#  Features/functions:
#  - insert content into non-standard areas of the page or site. For example:
#    - display a blog index other than on the blog page itself, such as on the
#      section homepage, or in a sidebar
#  - select view or index
#  - includes standard admin functions that can be inherited:
#    - configure content
#    - update content
#    - rollback
#    - delete
#    - pricing
#    - sort/order subcontent
#    - multiple image management
#    - contact/address book management
#    - workflow status changes
#
# Module conventions:
# - the content object is referenced using parameter "id"
# - the action paramter is "cmd"
# - the default action (a blank cmd) previews the object
#
# Reconfigurations of a content object will set the lcc (last content change)
# cookie to the current time. Front-end code can use this to detect whether 
# content indexes may need to be refreshed.
#----------------------------------------------------------------------------


######## TODO:
# do_make, do_edit on images, contacts


use strict;

use ExSite::Config;
use ExSite::Input;
use ExSite::Misc;
use ExSite::Util;
use ExSite::ML;
use ExSite::UI;
use ExSite::Date;
use ExSite::Content;
use Modules::BaseDCD;

# declare package globals

use vars qw(@ISA $ml $ui);

@ISA = qw(Modules::BaseDCD);

sub read {
    my ($this,$options) = @_;
    my $in = new ExSite::Input;
    $this->{input} = $in->combine;
    $this->{post} = $in->post;
    $this->{query} = $in->query;
    $this->{is_post} = scalar keys %{$this->{post}};
}

sub write {
    my ($this,$options) = @_;
    my $out;
    my $c = new ExSite::Content();
    my $content;
    my %opt = &DecodeString($options);
    if ($opt{id}) {
	$content = $c->get_content_obj($opt{id});
	delete $opt{id};
    }
    elsif ($opt{name}) {
	# context-dependent
	$content = $share{Page}->find($opt{name});
	delete $opt{name};
    }
    elsif ($opt{path}) {
	if ($opt{path} =~ /^\//) {
	    # full path
	    $content = $c->path_to_obj($opt{path});
	}
	else {
	    # find under this page
	    $content = $c->path_to_obj($opt{path},$share{Page}->id);
	}
	delete $opt{path};
    }
    if (! $content || ! $content->defined) {
	return $this->error("Content($options): not found");
    }
    if ($opt{view}) {
	$content->set_view($opt{view});
	delete $opt{view};
    }
    # any remaining options are passed to the object
    if ($opt{method} =~ /index/) {
	$out = $content->index(%opt);
    }
    else {
	$out = $content->show(%opt);
    }
    return $out;
}

sub ioctl {
    my $this = shift;
    $_ = shift;           # $_ is the ioctl request

    if (/isRestricted/) {
	return 0;
    }
    elsif (/isService/) {
	return 0;
    }
    elsif (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/ModuleName/) {
	return "Content";
    }
    elsif (/ModuleInfo/) {
	return "Insert content into non-standard areas of the page or site.";
    }
}

#----------------------------------------------------------------------------
# generic control panel - provides a simplified but general-purpose
# CMS interface. Should be overloaded for more specific content classes.

sub ctrl_panel {
    my $this = shift;
    my $db = $share{DB};
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    my $out;
    my $cmd = $this->{input}{cmd};
    my $id = $this->{input}{id};
    if ($id) {
	my $c = new ExSite::Content();
	$c = $this->{content} = $c->get_content_obj($id);
	$out = $this->pathbar($c);
	$out .= $ui->ToolBar(
	    tools=>[
		$ml->a("preview",{href=>$this->link(cmd=>undef)}),
		$ml->a("configure",{href=>$this->link(cmd=>"conf")}).
		$ml->a("edit",{href=>$this->link(cmd=>"edit")}).
		$ml->a("rollback",{href=>$this->link(cmd=>"rollback")}).
		$ml->a("todo",{href=>$this->link(cmd=>"todo")}),
		$ml->a("images",{href=>$this->link(cmd=>"image")}).
		$ml->a("pricing",{href=>$this->link(cmd=>"price")}).
		$ml->a("contacts",{href=>$this->link(cmd=>"contact")}).
		$ml->a("translate",{href=>$this->link(cmd=>"translate")}),
		$ml->a("publish",{href=>$this->link(cmd=>"publish")}).
		$ml->a("unpublish",{href=>$this->link(cmd=>"unpublish")}).
		$ml->a("schedule",{href=>$this->link(cmd=>"schedule")}),
		$ml->a("copy",{href=>$this->link(cmd=>"copy")}).
		$ml->a("delete",{href=>"javascript:confirm_custom('Really unpublish and delete this item?','".$this->link(cmd=>"del")."')",style=>"color:red"})
	    ]
	    );
	if ($cmd) {
	    if ($cmd eq "conf") {
		$out .= $this->configure($c);
	    }
	    elsif ($cmd eq "edit") {
		$out .= $this->update($c);
	    }
	    elsif ($cmd eq "rollback") {
		$out .= $this->rollback($c);
	    }
	    elsif ($cmd eq "del") {
		$out .= $this->delete($c);
	    }
	    elsif ($cmd eq "copy") {
		$out .= $this->copy($c);
	    }
	    elsif ($cmd =~ /price/) {
		$out .= $this->pricing($c);
	    }
	    elsif ($cmd eq "sort") {
		$out .= $this->order($c);
	    }
	    elsif ($cmd eq "todo") {
		$out .= $this->todo($c);
	    }
	    elsif ($cmd =~ /schedule/) {
		$out .= $this->schedule($c);
	    }
	    elsif ($cmd eq "translate") {
		$out .= $this->translations($c);
	    }
	    elsif ($cmd =~ /image/) {
		$out .= $this->images($c);
	    }
	    elsif ($cmd =~ /contact/) {
		$out .= $this->contacts($c);
	    }
	    elsif ($cmd =~ /^((un)?publish|archive|approve|(un)?queue|expire|reject)$/) {
		$out .= $this->$1($c);
	    }
	    else {
		$out .= $this->warn("$cmd: unrecognized command");
	    }
	}
	$out .= $ui->ScrollBox(title=>$c->title,pane=>$c->preview(),height=>"300px");
	my $r = new ExSite::ReportBuilder(title=>"Contents of ".$c->title);
	$r->nodata("No contents.");
	$r->headers("Content","Content Type", "MIME Type");
	foreach my $subc ($c->get_contents()) {
	    $r->push($ml->a($subc->title,{href=>$this->link(id=>$subc->id,cmd=>undef)}),$subc->subtype(),$subc->revision->mime_type());
	}
	$out .= $r->make();
    }
    else {
	# list sections that we have keys for
	my @s = $db->my_sites();
	my $r = new ExSite::ReportBuilder(title=>"Sections");
	$r->nodata("You do not have keys to any sections.");
	$r->headers("Title", "Public URL");
	foreach my $sdata ($db->my_sites) {
	    my $s = new ExSite::Section(data=>$sdata);
	    $r->push($ml->a($s->title,{href=>$this->link(id=>$s->id,cmd=>undef)}),
		     $ml->a($s->get_url(),{href=>$s->get_url()}));
	}
	$out .= $r->make();
    }
    return $out;
}


# pathbar: show path to current object
# options:
# linktypes = regex of content types that should be linked from the pathbar
# section_id = use the section_id parameter to build/limit the pathbar

sub pathbar {
    my ($this,$c,%opt) = @_;
    my @path = ( { label=>"Top", url=>$this->link(__clear=>1) } );
    if ($opt{section_id}) {
	my $section = new ExSite::Section(id=>$opt{section_id});
	push @path, { label=>$section->label, url=>$this->link(__clear=>1,section_id=>$opt{section_id}) };
    }
    my $cpath = $c->content_path;
    $cpath->reset;
    while (my $pathnode = $cpath->next) {
	my $type = $pathnode->subtype;
	if ($opt{section_id}) {
	    # do not display items up to the section
	    delete $opt{section_id} if ($pathnode->id == $opt{section_id});
	    next;
	}
	if (! $opt{linktypes} || $type =~ /$opt{linktypes}/) {
	    push @path, { label=>$pathnode->label, url=>$this->link(id=>$pathnode->id,__clear=>1), class=>"path".ucfirst($type) };
	}
	else {
	    push @path, $pathnode->name;
	}
    }
    my $ui = &get_obj("UI");
    return $ui->PathBar(links=>\@path);
}

# configure: basic form to reconfigure the content object
# You can pass show/hide arrayrefs to control which columns are displayed
# in the form. Hide defaults to a typical set.

sub configure {
    my ($this,$c,%opt) = @_;
    if (! $c->allow("edit")) {
	return $this->error("Sorry, you do not have permission to configure this ".$c->subtype().".");
    }
    if (scalar keys %{$this->{post}} > 0) {
	$cookie{lcc} = time;
	return $c->do_editmeta();
    }
    else {
	my $type = $c->subtype();
	$ml = &get_obj("ML");
	my $out .= $ml->h1("Configure $type ".$ml->em($c->title));
#	my $hide = $opt{hide} || [qw(content_id type url parent template master sortkey content_role mtime ptime)];

	# Note: this form can be templated using a custom editmeta_template
	# in the content object

	$out .= $c->editmeta(
	    hide=>$opt{hide},
	    show=>$opt{show},
	    extra=>{reply=>$this->link(__plaintext=>1,cmd=>undef)}
	    );
	return $out;
    }
}

# update: basic form to edit/add a revision - ASSUMES HTML CONTENT!
# options:
# prompt: set the content prompt
# name: set the input name
# format="html" - use HTML editor (otherwise use textarea)

sub update {
    my ($this,$c,%opt) = @_;
    if (! $c->allow("update")) {
	return $this->error("Sorry, you do not have permission to update this ".$c->subtype().".");
    }
    my $out;
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    my $name = $opt{name} || "content";
    if (scalar keys %{$this->{post}} > 0) {
	my %post = $share{DB}->parse_parts(%{$this->{post}});
	my %rev = (data=>$post{$name},format=>"text");
	if ($this->{post}{_save} =~ /draft/i) {
	    $rev{status} = $ExSite::Workflow::status{draft};
	}
	if ($c->revise(%rev)) {
	    $out .= $ui->SuccessBox(pane=>$c->title." updated.");
	    $ml->location($this->link(__plaintext=>1,cmd=>undef));
	}
	else {
	    $out .= $ui->ErrorBox(pane=>$c->show_diagnostics("error","html"));
	}
    }
    my $title = $opt{title} || "Edit ".$c->subtype." ".$ml->em($c->title);
    $out .= $ml->h1($title);
    $c->load_revision("newest");
    my $db = $share{DB};
    my $prompt = $opt{prompt} || ucfirst($c->subtype);
    if ($opt{format} =~ /html/i) {
	$db->input_htmleditor(
	    prompt=>$prompt,
	    name=>$name,
	    value=>$c->get_html(),
	    editor_height=>350,
	    editor_width=>550
	    );
    }
    else {
	$db->form->input(
	    type=>"textarea",
	    prompt=>$prompt,
	    name=>$name,
	    value=>$c->revision->get_raw(),
	    rows=>15,
	    cols=>70,
	    );
    }
    $db->form->set("buttons",
		   $ml->input(undef,{type=>"submit",value=>"Save"}).
		   $ml->input(undef,{type=>"submit",name=>"_save",value=>"Save as draft"}).
		   $ml->input(undef,{type=>"button",value=>"Cancel",class=>"formButton cancel",onclick=>"javascript:history.back()"}).
		   $ml->input(undef,{type=>"reset"}));

    $out .= $db->form->make();
    return $out;
}

# rollback: unpublish and delete a revision

sub rollback {
    my ($this,$c) = @_;
    my $type = $c->subtype();
    if (! $c->allow("delete")) {
	return $this->error("Sorry, you do not have permission to delete this $type.");
    }
    $c->unpublish();
    $c->rollback();
    return ucfirst $type . " rolled back.";
}

# delete: unpublish and delete a content object

sub delete {
    my ($this,$c) = @_;
    my $type = $c->subtype();
    if (! $c->allow("delete")) {
	return $this->error("Sorry, you do not have permission to delete this $type.");
    }
    $ml = &get_obj("ML");
    $ml->redirect($this->link(__plaintext=>1,__clear=>1,id=>$c->parent->id));
    $c->unpublish();
    $c->delete();
    $cookie{lcc} = time;
    return ucfirst $type . " deleted.";
}

# copy: clone a content object

sub copy {
    my ($this,$c) = @_;
    my $newid = $c->copy();
    $cookie{lcc} = time;
    if ($newid) {
	# done, now let them reconfigure it
	my $ml = &get_obj("ML");
	$ml->location($this->link(__plaintext=>1,cmd=>"conf",id=>$newid));
	return;
    }
    else {
	return $this->error("Failed to copy ".$c->subtype()." ".$c->id.".");
    }
}

# search for content under an object
# options:
# term => search string
# max => max # of results to show
# type => search url type (eg. content type) to display

sub search {
    my ($this,$c,%opt) = @_;
    my $out;
    $ml or $ml = &get_obj("ML");
    if ($this->{input}{search}) {
	my $section_id = $c->my_section->id || $c->id;
	require ExSite::Search;
	my $search = new ExSite::Search($section_id);
	my %results = $search->search($this->{input}{search},$opt{type});
	my @url_id = sort { $results{$b} <=> $results{$a}; } keys %results;
	my $db = $share{DB};
	my $nresult = 0;
	my $max_result = $opt{max} || 20;
	foreach my $url_id (@url_id) {
	    my $url = $search->{search_results}{$url_id} || 
		$db->fetch("searchurl",$url_id);
	    next if (! $url->{content_id});
	    next if ($opt{type} && $url->{type} ne $opt{type});
	    next if (!$c->is_ancestor_of($url->{content_id})); # not in this branch
	    $nresult++;
	    my $score = int($results{$url_id}*10)/10;
	    if ($url->{url} =~ /^$config{server}{CGIpath}/) {
		# show complete URLs
		$url->{url} = $config{server}{server}.$url->{url};
	    }
	    my $link = $this->link(id=>$url->{content_id},cmd=>undef);
	    $out .= $ml->dt( $ml->a($url->{title},{href=>$link}) );
	    my $descr = $url->{description} . 
		($url->{description} ? $ml->br : "") .
		$ml->span("[$url->{url}, $msg{score}: $score]",{class=>"searchdetails"});
	    $out .= $ml->dd($descr);
	    last if ($nresult >= $max_result);
	}
	if ($nresult == 0) {
	    $out .= $ml->p("No results found.");
	}
	else {
	    $out = $ml->dl($out);
	}
    }
    my $term = &html_escape($this->{input}{search});
    return $ml->h1("Search ".$ml->em($c->title)).
	$ml->form(
	$ml->input(undef,{type=>"text",name=>"search",value=>$term}).
	$ml->input(undef,{type=>"submit",value=>"Search"}),
	{action=>$this->link(),method=>"post",class=>"Search"}
	).
	    $out;
}

# pricing - optional; do not link to these methods if you module does not
# support pricing

sub pricing {
    my ($this,$c) = @_;
    $c or $c = $this->{content};
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    my $out = &insert_js("misc");
    if ($this->{input}{cmd} eq "price_add") {
	$out .= $this->price_add($c);
    }
    elsif ($this->{input}{cmd} eq "price_edit") {
	$out .= $this->price_edit($c);
    }
    elsif ($this->{input}{cmd} eq "price_del") {
	$share{DB}->trash_key("price",$this->{input}{pid});
	$ml->location($this->link(cmd=>"price",__plaintext=>1));
	return undef;
    }
    my @prices = $c->get_prices();
    my $r = new ExSite::ReportBuilder(title=>"Pricing for ".$ml->em($c->title));
    $r->headers("Price","Description","Access","Start","End","Status","Options");
    $r->nodata("No prices defined.");
    foreach my $p (@prices) {
	my $obj = new ExSite::Object(type=>"price",data=>$p);
	$r->push(
	    $ml->div($obj->showdata("cost"),{class=>"num"}),
	    $obj->showdata("description"),
	    $obj->showdata("access"),
	    $obj->showdata("start"),
	    $obj->showdata("end"),
	    $obj->showdata("status"),
	    $ui->fatool("edit",url=>$this->link(cmd=>"price_edit",pid=>$obj->id)).
	    $ui->fatool("delete",url=>$this->link(cmd=>"price_del",pid=>$obj->id),confirm=>"Really delete this price?",tone=>"bad"),
	    );
    }
    $r->tools($ui->fatool("add",label=>"add price",url=>$this->link(cmd=>"price_add")));
    $out .= $r->make();
    if ($r->nrow > 1) {
	$out .= $ui->HelpBox(title=>"Multiple Prices",
			     pane=>"When there are multiple prices, the system will select the ".$ml->em("lowest")." active price that is valid for the current date/time and access level of the user.");
    }
    return $out;
}

sub price_add {
    my ($this,$c) = @_;
    $c or $c = $this->{content};
    my $out;
    my $db = $share{DB};
    if (scalar keys %{$this->{post}} > 0) {
	my %post = $db->parse_parts(%{$this->{post}});
	delete $post{action};
	if ($post{cost}) {
	    $post{content_id} = $c->id;
	    $post{status} = "active";
	    my $pid = $db->insert("price",\%post);
	    if (! $pid) {
		$out .= $db->show_diagnostics("error","html");
	    }
	}
	else {
	    $out .= $this->error("You must specify a price.");
	}
    }
    else {
	$db->{map}->load_submaps("Finance");
	$ml = &get_obj("ML");
	$out .= $ml->h1("Add Price");
	$out .= $db->make(table=>"price",show=>["description","cost","acctcode_id","access","start","end"],simplename=>1,action=>$this->link());
    }
    return $out;
}

sub price_edit {
    my ($this,$c) = @_;
    $c or $c = $this->{content};
    my $out;
    my $db = $share{DB};
    if (scalar keys %{$this->{post}} > 0) {
	my %post = $db->parse_parts(%{$this->{post}});
	delete $post{action};
	if ($post{cost} && $post{price_id}) {
	    my $stat = $db->update("price",\%post);
	    if (! $stat) {
		$out .= $db->show_diagnostics("error","html");
	    }
	}
	else {
	    $out .= $this->error("You must specify a price.");
	}
    }
    else {
	$ml = &get_obj("ML");
	$out .= $ml->h1("Edit Price");
	my $price = $db->fetch("price",$this->{input}{pid});
	$out .= $db->make(table=>"price",show=>["description","cost","acctcode_id","access","start","end"],data=>$price,simplename=>1,action=>$this->link());
    }
    return $out;
}

# order : manually re-sort sub-content

sub order {
    my ($this,$c) = @_;
    my $out;
    $ml = &get_obj("ML");
    if (scalar keys %{$this->{post}} > 0) {
	# oid=144&oid=143&oid=142&oid=141
	my @sort = split /&?oid=/,$share{input}{post}{raw};
	shift @sort; # first one is a dummy
	my $order = 0;
	foreach my $cid (@sort) {
	    $order++;
	    my $c = $c->get_content_obj($cid);
	    my $sortkey = sprintf("%04d",$order);
	    $c->setdata("sortkey",$sortkey);
	    $c->save;
	}
	$out .= $this->info("Re-ordered $order items.");
    }
    my $tree = $c->get_content_tree;
    my @child = $tree->get_child_data($c->id);
    my @order;
    foreach my $ch (@child) {
	my $c = $c->get_content_obj($ch);
	next if ($c->subtype eq "content" && $c->name eq "body");
	my $subtype = $c->subtype;
	if ($subtype eq "content") {
	    $subtype .= ": ".$c->revision->mime_type;
	}
	push @order, $c->name." ($subtype)".$ml->input(undef,{type=>"hidden",name=>"oid",value=>$c->id});
    }
    if (scalar @order > 1) {
	$out .= $ml->h1("Re-order contents");
	my $sortrule = $config{content}{$c->subtype}{sort};
	if ($sortrule) {
	    $out .= &ExSite::HTML::ErrorBox(
		title=>"Sort Warning",
		pane=>ucfirst($c->subtype)." objects have their own special rules for sorting their contents. Re-ordering here may not affect the display order."
		);
	}
	$out .= $ml->p("Drag items into their new order, then click the save button.");
	$out .= &ExSite::HTML::js();
	$out .= $ml->script('
$(function() {
  $( "#sortable" ).sortable();
  $( "#sortable" ).disableSelection();
});
');
	$out .= $ml->form(
	    $ml->ul(\@order,{id=>"sortable"}).
	    $ml->input(undef,{type=>"submit",value=>"Save order"}),
	    {action=>$this->link(),method=>"post",id=>"sortableContent"}
	    );
    }
    else {
	$out .= $this->warn("There are not enough contents to order.");
    }
    return $out;
}

# todo - add a "to-do" item on this content

sub todo {
    my ($this,$c) = @_;
    $ml = &get_obj("ML");
    my $out .= $ml->h1("Add a to-do reminder for ".$c->subtype()." ".$ml->em($c->label));
    if ($this->{post}{description} && $this->{post}{date}) {
	if ($c->todo($this->{post}{description},$this->{post}{date})) {
	    my $ui = &get_obj("UI");
	    $out .= $ui->SuccessMsg("reminder saved");
	}
    }
    my $f = new ExSite::FormBuilder(action=>$this->link());
    $f->input(name=>"description",prompt=>"To-do / Reminder",type=>"text",size=>60,required=>1);
    $f->input(name=>"date",prompt=>"Remind me on:",type=>"date",required=>1);
    $out .= $f->make();
    $out .= $ml->p("To-do reminders, along with other dates and tasks, can be viewed in the ".$ml->a("schedule",{href=>$this->link(cmd=>"schedule")})." for this content.");
    return $out;
}

sub translations {
    my ($this,$c) = @_;
    my $out;
    my @lang = &get_languages(1);
    if (scalar @lang < 2) {
	$out = $ml->h1("Multilingual content management not enabled");
	$out .= $ml->p("Your system only recognizes one language:");
	$out .= $ml->ul(\@lang);
	$out .= $ml->p("Consult the help documentation to define additional languages.");
	return $out;
    }
    $out .= $ml->h1("Translations");
    my $language = $c->getdata("language");
    my $master = $c->master();
    if (! $master->defined) { $master = $c; }
    if ($language) {
	$out .= $ml->p($ml->strong($c->name) . " is the " . 
		       $ml->em($language) . " version of " . 
		       $c->subtype() . " " .
		       $ml->a($master->name,{href=>$this->link(id=>$master->id)}) . "."
	    );
    }
    my @c = $share{DB}->fetch_match("content",{master=>$master->id});
    my %tr = &keywise("language",\@c);
    if ($this->{input}{v}) {
	if ($tr{$lang[$this->{input}{v}]}) {
	    $out .= $this->warn("$lang[$this->{input}{v}] already exists.");
	}
	else {
	    $out .= $this->make_translation($c,$lang[$this->{input}{v}]);
	}
    }
    my $r = new ExSite::ReportBuilder(title=>"Translations of ".$master->name);
    $r->headers("Language","Content","URL","Last Update*");
    $r->foot("* green translation dates are fresher than the master content; red indicates translations that may be stale");
    my $t = new ExSite::Time($master->timestamp,"sql_timestamp");
    my $url = $master->get_url;
    $r->push($lang[0],
	     $ml->a($master->name,{href=>$this->link(cmd=>"info",id=>$master->id)}),
	     $ml->a($url,{href=>$url}),
	     $t->write("datetime"));
    shift @lang;
    my $iv = 0;
    foreach my $v (@lang) {
	$iv++;
	my @data = ( $v );
	if ($tr{$v}) {
	    my $tr_content = $c->get_content_obj($tr{$v});
	    my $url = $tr_content->get_url;
	    my $ctime = $tr_content->timestamp();
	    my ($date,$tclass);
	    if ($ctime) {
		my $t2 = new ExSite::Time($tr_content->timestamp,"sql_timestamp");
		$date = $t2->write("datetime");
		$tclass = $t2->diff($t) > 0 ? "stale" : "fresh";
	    }
	    else {
		$date = "no update yet";
		$tclass = "stale";
	    }
	    push @data, $ml->a($tr_content->name(),{href=>$this->link(cmd=>"info",id=>$tr_content->id)});
	    push @data, $ml->a($url,{href=>$url});
	    push @data, $ml->span($date,{class=>$tclass});
	}
	else {
	    push @data, $ml->a("create $v version",{href=>$this->link(v=>$iv),class=>"button_sm"}), "", "";
	}
	$r->push(\@data);
    }
    $out .= $r->make();
    return $out;
}

sub make_translation {
    my ($this,$c,$language) = @_;
    my $master = $c->master();
    if (! $master->defined) { $master = $c; }
    if (! $c->allow("update")) {
	# translations are an editorial function
	return $this->error("Sorry, your keys do not allow you to update translations.");
    }
    my $suffix = $config{language_suffix}{$language} || substr($language,0,2);
    my $name = $master->getdata("name") . "_$suffix";
    my $title = $master->getdata("title") . " ($language)";
    my $label = $master->getdata("label") . " ($language)";
    my $new_id = $master->copy(language=>$language,
			       name=>$name,
			       title=>$title,
			       label=>$label,
			       master=>$master->id);
    if ($new_id) {
	$ml->location($this->link(v=>undef,__plaintext=>1));
	return $ml->p("Created $language translation ".
		      $ml->a($ml->em($name),{href=>$this->link(cmd=>"info",id=>$new_id,v=>undef)}).".");
    }
    else {
	return $this->error("Failed to create $language translation.");
    }
}

# multi image management

sub images {
    my ($this,$c) = @_;
    my $out;
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    if ($this->{input}{cmd} eq "image_add") {
	return $this->image_add($c);
    }
    elsif ($this->{input}{cmd} eq "image_edit") {
	$out .= $this->image_edit($c);
    }
    elsif ($this->{input}{cmd} eq "image_sort") {
	$out .= $this->image_sort($c);
    }
    elsif ($this->{input}{cmd} eq "image_del") {
	my $photo = new ExSite::Content(id=>$this->{input}{img});
	$photo->delete();
	$ml->location($this->link(cmd=>"image",__plaintext=>1));
	return undef;
    }
    $out .= $ml->h1("Photos for ".$ml->em($c->title));
    $out .= $ml->script('
$(function() {
  $( "#sortable" ).sortable();
  $( "#sortable" ).disableSelection();
});
$(document).ready(function(){
  $(".popupLink").magnificPopup({type:"inline"});
})
');
    my $lout;
    my $capout;
    my $nimg;
    my @photo = $c->get_contents();
    if (scalar @photo) {
	foreach my $p (@photo) {
	    next if (! $p->revision->is_image);
	    $p->set_view("thumbnail");
#	    $p->revision->view("thumbnail");
	    my $pout = $ml->div($p->show(),{class=>"imageThumb"});
#	    my $caption = $p->caption();
	    my $caption = $p->dcmeta("caption");
	    my $popupid = "editCaption".$p->id;
	    $capout = $ml->div(
		$ml->form("Caption: ".
		$ml->input(undef,{type=>"text",name=>"caption",size=>40,value=>$caption}).
		$ml->input(undef,{type=>"submit",value=>"update caption"}),
		{action=>$this->link(cmd=>"image_edit",img=>$p->id),method=>"post"}),
		{id=>$popupid,class=>"editCaption"}
#		{id=>$popupid,class=>"editCaption white-popup mfp-hide"}
		);
	    $pout .= $ml->div(
		$ml->p("Caption: ".$ml->em($caption || $ml->span("(no caption set)",{class=>"noCaption"})).$ui->Button(type=>"button",label=>"edit",faicon=>"edit",size=>"s",title=>"Edit Caption",pane=>$capout)).
#$ml->a("edit",{href=>"#$popupid",class=>"popupLink button_sm"})).
		$ml->p($ui->Button(type=>"link-button",label=>"delete image",confirm=>"Really delete this image?",url=>$this->link(cmd=>"image_del",img=>$p->id),class=>"imageDelete",faicon=>"delete",size=>"s",tone=>"bad")),
		{class=>"imageEditDetails"});
	    $pout .= $ml->input(undef,{type=>"hidden",name=>"order",value=>$p->id});
	    $lout .= $ml->li($pout, {class=>"contentImage"});
	    $nimg++;
	}
	$out .= $ml->form(
	    $ml->ul($lout,{id=>"sortable"}).
	    ($nimg>1?$ml->input(undef,{type=>"submit",value=>"save order"}):""),
	    {action=>$this->link(cmd=>"image_sort"),method=>"post"}
	    );
#	$out .= $capout;
    }
    else {
	$out .= $ml->p("No photos have been uploaded.");
    }
    $out .= $ml->p(
	&ExSite::HTML::Button(label=>"upload new photo",url=>$this->link(cmd=>"image_add"))
	);
    return $ml->div($out,{class=>"contentImageList"});
}

sub image_add {
    my ($this,$c) = @_;
    my $out;
    $ml = &get_obj("ML");
    my $db = $share{DB};
    if (scalar keys %{$this->{post}} > 0) {
	my $in = new ExSite::Input;
	my $fdata = $in->fetch_file("photo");
	if ($fdata) {
	    my $fname = $in->fetch_file("photo","name");
	    my $img = $c->new_content_obj(name=>$fname,type=>"content",parent=>$c->id);
	    if ($img->id) {
		$img->revise(data=>$fdata,format=>"file",view=>{normal=>1,small=>1,thumbnail=>1});
		if ($this->{post}{caption}) {
		    $img->set_metadata("caption",$this->{post}{caption});
		    $img->save();
		    $out .= $db->show_diagnostics("error","html");
		}
		$ml->location($this->link(__plaintext=>1,cmd=>"image"));
	    }
	    else {
		$out .= $db->show_diagnostics("error","html");
	    }
	}
    }
    else {
	$out .= $ml->h1("Add Image");
	my $f = new ExSite::FormBuilder();
	$f->input(type=>"file",name=>"photo",prompt=>"Image",required=>1);
	$f->input(type=>"text",name=>"caption",prompt=>"Caption",size=>40);	
	$out .= $f->make();
    }
    return $out;
}

sub image_edit {
    my ($this,$c) = @_;
    $ml = &get_obj("ML");
    if (scalar keys %{$this->{post}} > 0) {
	if ($this->{post}{caption}) {
	    my $photo = $this->{content}->get_content_obj($this->{input}{img});
	    $photo->set_metadata("caption",$this->{post}{caption});
	    $photo->save();
	}
    }
    #return $db->show_diagnostics("error","html");
    $ml->location($this->link(__plaintext=>1,cmd=>"image",img=>undef));
}

sub image_sort {
    my ($this,$c) = @_;
    $ml = &get_obj("ML");
    if (scalar keys %{$this->{post}} > 0) {
	my @order = split /; /,$this->{post}{order};
	my $isort = 1;
	foreach my $photo_id (@order) {
	    my $p = new ExSite::Content(id=>$photo_id);
	    $p->setdata("sortkey",$isort);
	    $p->save;
	    $isort++;
	}
    }
    $ml->location($this->link(__plaintext=>1,cmd=>undef,img=>undef));
}

sub image_del {
    my ($this,$c) = @_;
    $ml = &get_obj("ML");
    my $photo = new ExSite::Content(id=>$this->{input}{img});
    $photo->delete();
    $ml->location($this->link(cmd=>"image",img=>undef,__plaintext=>1));
}

# contact management

sub contacts {
    my ($this,$c) = @_;
    my $out;
    $ml = &get_obj("ML");
    my $cmd = $this->{input}{cmd};
    require Modules::ID::Contact;
    if ($cmd eq "edit_contact") {
	return $this->edit_contact($c);
    }
    elsif ($cmd eq "del_contact") {
	return $this->delete_contact($c);
    }
    elsif ($cmd eq "add_contact") {
	return $this->add_contact($c);
    }
    my $out = $ml->h1("Contacts for ".$ml->em($c->title));
    my @contact = $share{DB}->fetch_child("contact","content",$this->{content}->id);
    if (scalar @contact == 0) {
	$out .= "No contact information.";
    }
    foreach my $cdata (@contact) {
	my $c = new Modules::ID::Contact(data=>$cdata);
	my $tools = 
	    $ml->a("edit",{href=>$this->link(cmd=>"edit_contact",contact_id=>$c->id),class=>"contact_edit"}).
	    $ml->a("delete",{href=>"javascript:confirm_custom('Really delete this contact?','".$this->link(cmd=>"del_contact",contact_id=>$c->id)."')",class=>"contact_delete"});
	$out .= $c->show(foot=>$ml->div($tools,{class=>"contact_tools"}))
    }
    $out .= $ml->div($ml->a("new contact",{href=>$this->link(cmd=>"add_contact"),class=>"contact_add"}),{class=>"contact_tools"});
    return $out;
}

sub edit_contact {
    my ($this,$c) = @_;
    $ml = &get_obj("ML");
    my $out = $ml->h1("Edit Contact");
    my $contact = new Modules::ID::Contact(id=>$this->{input}{contact_id});
    $out .= $contact->edit(
	hide=>["account_id"],
	action=>$this->link(__plaintext=>1),
	);
    return $out;
}

sub add_contact {
    my ($this,$c) = @_;
    my $ui = new ExSite::UI;
    $ml = &get_obj("ML");
    my $contact = new Modules::ID::Contact();
    return $ui->BasicBox(
	title=>"Add new contact information for ".$ml->em($this->{content}->title),
	pane=>$contact->make(
	    data=>{content_id=>$c->id},
	    hide=>["content_id","account_id"],
	    action=>$this->link(__plaintext=>1),
	)
	);
}

sub del_contact {
    my ($this,$c) = @_;
    $ml = &get_obj("ML");
    my $c = new Modules::ID::Contact(id=>$this->{input}{contact_id});
    if ($c->approve("delete")) {
	$c->delete();
	$ml->location($this->link(cmd=>"contact",contact_id=>undef,__plaintext=>1));
	return;
    }
    else {
	return $this->error("Delete contact: permission denied.");
    }
}

sub about {
    my ($this,$c) = @_;
    if ($c->defined()) {
	$ml = &get_obj("ML");
	$c->load();
	my $out = $share{DB}->report({ table=>$c->{type},
				       data=>[$c->{data}], 
				       columns=>"full|brief",
				       type=>"full", 
				       title=>$c->name,
				     });

	# metadata

	my %meta;
	my @meta = sort $c->meta->get_allowed();
	my $nmeta = 0;
	my @metahead;
	foreach my $m (@meta) {
	    my $val = $c->meta->get($m);
	    if ($val) {
		push @metahead, $m;
		$meta{$m} = $val; 
		$nmeta++;
	    }
	}
	my $metareport = new ExSite::ReportBuilder(title=>"Metadata");
	$metareport->headers(@metahead);
	$metareport->data( map { $meta{$_} } @metahead );
	$out .= $metareport->make() if ($metareport->nrow > 0);

	# other info

	my %other;
	if ($c->revision->is_file) {
	    my %fileinfo = $c->revision->get_fileinfo;
	    $other{'Original filename'} = $c->revision->view->original_filename;
	    $other{'File location'} = $fileinfo{diskpath};
	    $other{'File size'} = $fileinfo{size};
	}
	$other{"MIME type"} = $c->revision->view->mime_type;
	$other{"Path (logical)"} = scalar $c->path();
	$other{"Path (disk)"} = $c->diskpath();
	$other{"Path (url)"} = $c->httppath();
	$other{"Filename"} = $c->filename || "n/a";
	$other{Published} = $c->revision->is_published ? $c->revision->showdata("ptime") : "not yet";
	$other{"Publish Heuristic"} = $c->publish_rule_heuristic();

	my $otherreport = new ExSite::ReportBuilder(title=>"Other Information");
	$otherreport->headers(sort keys %other);
	$otherreport->data( map { $other{$_} } sort keys %other );
	$out .= $otherreport->make() if ($otherreport->nrow > 0);

	# views

	my $viewreport = new ExSite::ReportBuilder(title=>"Views of revision ".$c->revision->id);
	$viewreport->headers("View","Format","MIME Type","Attributes");
	foreach my $vtype (qw(large normal small thumbnail icon)) {
	    if ($c->revision->has_view($vtype)) {
		my $v = $c->revision->select_view($vtype);
		$viewreport->push($vtype,
				  $v->showdata("format"),
				  $v->showdata("mime_type"),
				  $v->showdata("attributes"));
	    }
	}
	$out .= $viewreport->make() if ($viewreport->nrow > 0);
	
	# keys

	my @keys = $c->keys();
	if (scalar @keys > 0) {
	    my $keyreport = new ExSite::ReportBuilder(title=>"Administrator Keys");
	    $keyreport->headers("User","Role");
	    foreach my $key (@keys) {
		my $user = $share{DB}->fetch("user",$key->{uid});
		$keyreport->push($share{DB}->user_name($user),$key->{role});
	    }
	    $out .= $keyreport->make() if ($keyreport->nrow > 0);
	}

	# revisions

	my %rev;
	my @rev = $c->get_revisions();
	my $revreport = new ExSite::ReportBuilder(title=>"Revisions");
	$revreport->headers("Revision","Note","Updated on","Published on");
	foreach my $rev (reverse @rev) {
	    next if ($rev->{content_id} != $c->id);
	    my @rdata;
	    my $r = new ExSite::Revision(data=>$rev);
	    my $id = $r->id;
	    if ($id == $c->revision->id) { $id .= "*"; }
	    push @rdata,$id;
	    push @rdata,$r->showdata("note");
	    push @rdata,$r->showdata("ctime");
	    my $ptime = $r->getdata("ptime");
	    push @rdata, $ptime =~ /^0/ ? "n/a" : $r->showdata("ptime");
	    $revreport->push(@rdata);
	}
	$revreport->foot("* The revision currently being shown.");
	$out .= $revreport->make() if ($revreport->nrow > 0);
	
	# contents

	my $contentreport = new ExSite::ReportBuilder(title=>"Contents");
	$contentreport->set("dynamic",1);
	$contentreport->headers("Name","Type","Language","MIME-Type");
	my $tree = $c->get_content_tree();
	my @child = $tree->get_child_data($c->id);
	if (scalar @child > 0) {
	    foreach my $n (@child) {
		my $cnode = new ExSite::Content(id=>$n->{content_id});
		$contentreport->push(
		    $ml->a($cnode->name,{href=>$this->link(id=>$cnode->id)}),
		    $c->subtype($cnode->getdata("type")),
		    $cnode->getdata("language"),
		    $cnode->revision->mime_type);
	    }
	}
	$out .= $contentreport->make() if ($contentreport->nrow > 0);

	return $ml->div($out,{class=>"contentReport"});
    }
    return undef;
}

sub tags {
    my ($this,$c) = @_;
    require ExSite::Index;
    my $ml = &get_obj("ML");
    my $out;

    # tags on this content
    my (%tag,%tagid);
    my $tags = $c->tags();
    while (my $tag = $tags->next()) {
	$tag{$tag->label} = $tag;
	$tagid{$tag->id} = $tag;
    }

    # complete list of keywords
    my %index;
    my $tree = $c->get_content_tree;
    my @index = $tree->find({type=>$c->isubtype("index")},$c->my_section->id);
    foreach my $indata (@index) {
	my $in = new ExSite::Index(data=>$indata);
	my $indid = $in->id;
	$index{$indid}{_} = $in;
	my $kws = $in->get_keywords();
	while (my $kw = $kws->next()) {
	    $index{$indid}{$kw->label} = $kw;
	}
    }

    # update tags
    if ($this->{is_post}) {
	my %selected_tags;
	foreach my $key (keys %{$this->{post}}) {
	    $key =~ /^keyword(\d+)$/;
	    $selected_tags{$1} = 1;
	}

	# 1) remove tags
	foreach my $kwid (keys %tagid) {
	    if (! exists $selected_tags{$kwid}) {
		foreach my $tag ($share{DB}->fetch_match("content",{parent=>$kwid,master=>$c->id,type=>$c->isubtype("alias")})) {
		    $share{DB}->trash_key("content",$tag->{content_id});
		}
		$out .= $ml->p("Removed tag ".$ml->em($tagid{$kwid}->label).".",{class=>"help"});
		delete $tag{$tagid{$kwid}->label};
		delete $tagid{$kwid};
	    }
	}

	# 2) add tags

	my $c = new ExSite::Content();
	foreach my $kwid (keys %selected_tags) {
	    if (! exists $tagid{$kwid}) {
		my $kw = $c->get_content_obj($kwid);
		my $content = $c->get_content_obj($this->{input}{id});
		if ($content->allow("edit")) {
		    my %newtag = (
			type=>$content->isubtype("alias"),
			title=>$content->title,
			label=>$content->label,
			name=>$content->name,
			parent=>$kw->id,
			master=>$content->id,
			access=>0,
			content_role=>"editorial",
			publish=>"static",
			status=>"active",
			);
		    my $tagid = $share{DB}->insert("content",\%newtag);
		    if ($tagid) {
			# success
			$out .= $ml->p("Tagged ".$ml->em($content->label)." as ".$ml->em($kw->label).".",{class=>"help"});
			$tag{$kw->label} = $kw;
			$tagid{$kwid} = $kw;
			#$cookie{lcc} = time;
		    }
		    else {
			$out .= $share{DB}->show_diagnostics();
		    }
		}
		else {
		    $out .= $this->error("You do not have permission to tag this content.");
		}
	    }
	}
    }

    # build tags table

    my $tagout;
    foreach my $indid (keys %index) {
	my $nkw = scalar(keys(%{$index{$indid}})) - 1;
	my (@col,@percol);
	foreach my $icol (0 .. 3) {
	    $percol[$icol] = int($nkw / 4);
	    $percol[$icol]++ if ($nkw % 4 && $icol < $nkw % 4);
	}
	my $icol = 0;
	my $incol = 0;

	foreach my $kw (sort keys %{$index{$indid}}) {
	    next if ($kw eq "_");
	    $incol++;
	    my %opt = (name=>"keyword".$index{$indid}{$kw}->id,type=>"checkbox");
	    if ($tag{$kw}) {
		$opt{checked} = undef;
	    }
	    $col[$icol] .= $ml->input(undef,\%opt)." $kw".$ml->br;
	    if ($nkw > 20 && $incol >= $percol[$icol]) {
		$icol++;
		$incol = 0;
	    }
	}
	my $head = (scalar keys %index) > 1 ? $index{$indid}{_}->title() : undef;
	$tagout .= $nkw > 20 ? # break large keyword lists into columns
	    $ml->table(($head ? $ml->caption($head) : undef).
		       $ml->tr(
			   $ml->td($col[0],{valign=>"top"}).
			   $ml->td($col[1],{valign=>"top"}).
			   $ml->td($col[2],{valign=>"top"}).
			   $ml->td($col[3],{valign=>"top"})
		       ),{width=>"100%"}) :
	    ($head ? $ml->h3($head) : undef).$ml->p($col[0]); # single column view
    }

    $out .= $ml->h1($c->title);
    $out .= $ml->p("This ".$c->subtype." is tagged as:");
    $out .= $ml->form(
	$tagout.
	$ml->input(undef,{type=>"submit",value=>"Add/remove tags"}).
	$ml->input(undef,{type=>"reset",value=>"Reset"}),
	{method=>"post"}
	);
    return $out;
}

#--------------------- Workflow ----------------------

# simplified schedule management: add

sub schedule {
    my ($this,$cnode) = @_;
    my $ml = &get_obj("ML");
    my $ui = &get_obj("UI");
    my $out;
    my $cmd = $this->{input}{cmd};
    return $this->error("Permission denied.") if (! $cnode->allow("edit"));

    if ($this->{input}{description} && $this->{input}{start}) {
	# new task
	my %task = ( type=>"task", 
		     content_id=>$cnode->id,
		     description=>$this->{input}{description},
		     start=>$this->{input}{start},
		     status=>"active" );
	$share{DB}->insert("content_date",\%task) or 
	    $out = &ExSite::Config::show_diagnostics();
    }
    elsif ($cmd eq "schedule_del") {
	my $dateid = $this->{input}{date};
	my $date = new ExSite::Object(type=>"content_date",id=>$dateid);
	if ($date->getdata("content_id") != $cnode->id) {
	    $this->error("Cannot delete date ".$dateid);
	}
	elsif ($date->delete()) {
	    $ml->location($this->link(__plaintext=>1,key=>undef,cmd=>"schedule"));
	    return;
	}
	else {
	    $out .= &ExSite::Config::show_diagnostics();
	}
    }

    my @date = $share{DB}->fetch_child("content_date","content",$cnode->id);
    my $r = new ExSite::ReportBuilder(title=>"Schedule for ".$cnode->name);
    $r->headers("Task","Done?","");
    $r->nodata("Nothing scheduled.");
    foreach my $d (@date) {
	next if ($d->{type} ne "task");
	my $e = new ExSite::Object(type=>"content_date",data=>$d);
	my $t = new ExSite::Time($e->getdata("start"),"sql_datetime");
	$r->push(
	    $e->showdata("description") . " on " . $t->write("datetime"),
	    $e->getdata("status") eq "completed" ? $ui->faicon("check")."yes" : $ui->faicon("cross")."no",
	    $ui->fatool("delete",url=>$this->link(cmd=>"schedule_del",date=>$e->id),confirm=>"Really delete this task?",tone=>"bad")
	    );
    }
    $out .= $r->make();

    # add a new task
    my @tasks = $cnode->allowed_tasks();
    $out .= $ml->h2("Add a task");
    my $f = new ExSite::FormBuilder();
    $f->input(prompt=>"Task",name=>"description",type=>"select",options=>\@tasks,nullvalue=>"== choose ==");
    $f->input(prompt=>"Date &amp time",name=>"start",type=>"date",placeholder=>"YYYY-MM-DD HH:MM");
    $f->buttons(submit=>"add to task schedule");
    $out .= $f->make();

    return $out;
}

# wf_tools - returns an array of UI::navitem descriptors to perform 
# workflow operations on the current content. These can be used to make 
# links, buttons, toolbar or menu items.

sub wf_tools {
    my ($this,$c) = @_;
    my @tool; # all tools
    foreach (0..8) {
	if ($c->wf_allow($_)) { # workflow operation make sense 
	    if ($c->allow($ExSite::Workflow::wf_priv[$_])) { # user is allowed
		my $action = $ExSite::Workflow::wf_action[$_];
		push @tool, { label=>$action,
			      url=>$this->link(cmd=>$action,id=>$c->id),
			      faicon=>$action, };
	    }
	}
    }
    my @wftool; # actual presented tools
    my $status = $c->wf_status();
    if ($tool[0]{label} eq "publish") {
	push @wftool, shift @tool;
	if ($status eq "published") {
	    $wftool[0]{label} = "re-publish";
	}
	# use draft instead
	#push @pubtools, { label=>"Un-publish",url=>$this->link(cmd=>"unpublish"),faicon=>"draft"};
    }
    elsif ($status eq "published") {
	unshift @tool, { label=>"re-publish", faicon=>"publish", url=>$this->link(cmd=>"publish",id=>$c->id) };
    }
    if (scalar @tool > 0) {
	push @wftool, { label=>$status, faicon=>$ExSite::Workflow::wf_action[$c->wf_istatus()], links=>\@tool };
#	push @wftool, { label=>"workflow", faicon=>"workflow", links=>\@tool };
    }
    return @wftool;
}

# schedule tool generates a navlink that links to the schedule function;
# it also includes a Bootstrap badge to indicate whether anything has been 
# scheduled

sub schedule_tool {
    my ($this,$c) = @_;
    my $ntask;
    my $dates = $c->get_dates();
    if ($dates && $dates->count) {
	while (my $date = $dates->next) {
	    $ntask++ if ($date->getdata("type") eq "task");
	}
    }
    my $label = "Schedule";
    if ($ntask) { 
	my $ml = &get_obj("ML");
	$label .= " ".$ml->span($ntask,{class=>"badge"}); 
    }
    return {label=>$label,url=>$this->link(cmd=>"schedule"),faicon=>"calendar"};
}

# status changes - higher-level modules can overload these to do more

sub publish { 
    my ($this,$c) = @_;
    if ($c->is_published) {
	# no status change; republish
	$c->publish();
    }
    else {
	$c->wf_publish();
	$cookie{lcc} = time;
    }
    return;
}

sub unpublish {
    my ($this,$c) = @_;
    $c->wf_draft();
    $cookie{lcc} = time;
    return;
}

sub archive {
    my ($this,$c) = @_;
    $c->wf_archive();
    $cookie{lcc} = time;
    return;
}

sub approve {
    my ($this,$c) = @_;
    $c->wf_approve();
    $cookie{lcc} = time;
    return;
}

sub submit {
    my ($this,$c) = @_;
    $c->wf_submit();
    $cookie{lcc} = time;
    return;
}

sub queue {
    my ($this,$c) = @_;
    $c->wf_queue();
    $cookie{lcc} = time;
    return;
}

sub unqueue {
    my ($this,$c) = @_;
    $c->wf_draft();
    $cookie{lcc} = time;
    return;
}

sub draft {
    my ($this,$c) = @_;
    $c->wf_draft();
    $cookie{lcc} = time;
    return;
}

sub expire {
    my ($this,$c) = @_;
    $c->wf_expire();
    $cookie{lcc} = time;
    return;
}

sub cancel {
    my ($this,$c) = @_;
    $c->wf_cancel();
    $cookie{lcc} = time;
    return;
}

sub reject {
    my ($this,$c) = @_;
    $c->wf_reject();
    $cookie{lcc} = time;
    return;
}

1;
