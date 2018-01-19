package Modules::Locations;
#----------------------------------------------------------------------------
#
#   Copyright (C) 2014 - Exware Solutions, Inc.  http://www.exware.com
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

# useful kernel libs; you can/should remove any of these that are not needed

use ExSite::Config;          # required
use ExSite::Input;           # optional input manager
use ExSite::Misc;            # optional utils
use ExSite::Util;            # optional utils
use ExSite::ML;              # optional markup-language generation
use ExSite::FormBuilder;     # optional form generation
use ExSite::ReportBuilder;   # optional report generation
use ExSite::Form;            # optional database manager
use ExSite::UI;

use Modules::ID::Contact;
use Modules::Location::Location;
use Modules::Location::Directory;

# recommended base class for plug-in modules

use Modules::Content;

# declare package globals

use vars qw(@ISA $ml $ui);
@ISA = qw(Modules::Content);

sub read {
    my ($this,$options) = @_;
    my $in = new ExSite::Input;
    $this->{input} = $in->combine;
    $this->{post} = $in->post;
    $this->{query} = $in->query;
}

sub write {
    my ($this,$options) = @_;
    return undef;
}

# ioctl method (used by ExSite to query the module for its functionality)

sub ioctl {
    my $this = shift;
    $_ = shift;           # $_ is the ioctl request

    if (/ModuleName/) {
	return "Locations";
    }
    elsif (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/Dependencies/) {
	return ["AddrBook"];
    }
    elsif (/PublishRule/) {
	return "static";
    }
}

#----------------------------------------------------------------------------
# Everything after this point consists of private methods.

# ctrl_panel() generates the contents of the administrator control panel

sub ctrl_panel {
    my $this = shift;

    # declare a markup generator
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");

    my $out;  # our output buffer
    $this->{section_id} = $this->get_section_id();
    if (! $this->{section_id}) {
	$out .= $this->set_section_id();
	return $out;
    } 
    #$this->setup_querylib();
    my $cmd = $this->{input}{cmd};
    if ($this->{input}{id}) {
	my $c = new ExSite::Content(id=>$this->{input}{id});
	$this->{content} = $c->get_content_obj();
	$out .= $this->pathbar();
    }

    if ($cmd eq "search") {
	$out .= $this->search();
    }
    elsif ($cmd eq "newloc") {
	$out .= $this->new_location();
    }
    elsif ($cmd eq "newdir") {
	$out .= $this->new_directory();
    }
    elsif ($this->{content}) {
	if ($cmd eq "publish") {
	    $out .= $this->publish();
	}
	if ($this->{content}->subtype eq 'location') {
	    $out .= $this->show_location();
	}
	else {
	    $out .= $this->show_directory();
	}
    }
    else {
	$out .= $this->show_directories();
    }

    return $out;
}

sub pathbar {
    my ($this) = @_;
    my @path = ( { label=>"Top", url=>$this->link(section_id=>undef,id=>undef,cmd=>undef,contact_id=>undef) } );
    my $cpath = $this->{content}->content_path;
    $cpath->reset;
    while (my $pathnode = $cpath->next) {
	my $url = $pathnode->id == $this->{section_id} ?
	    $this->link(section_id=>$this->{section_id},id=>undef,cmd=>undef) : 
	    $this->link(id=>$pathnode->id,cmd=>undef);
	push @path, { label=>$pathnode->label, url=>$url };
    }
    return $ui->PathBar(links=>\@path);
}

sub get_locations {
    my ($this,$root_id) = @_;
    $root_id or $root_id = $this->{section_id};
    my $c = new ExSite::Content(id=>$root_id);  # type doesn't matter
    my @loc = $c->get_descendants("location");
    return wantarray ? @loc : \@loc;
}

sub get_directories {
    my ($this,$root_id,$locdir_only) = @_;
    $root_id or $root_id = $this->{section_id};
    my $c = new ExSite::Content(id=>$root_id);  # type doesn't matter
    # first, get actual location directories
    my $c = new ExSite::Content(id=>$root_id);  # type doesn't matter
    my @loc = $c->get_descendants("location_directory");
    my %dir = &keywise("content_id",\@loc);
    # next, add any container object holding locations
    my $locs = $this->get_locations($root_id);
    my %locs = &keywise("parent",$locs);
    my $tree = $c->get_content_tree();
    foreach my $id (keys %locs) {
	next if ($dir{$locs{$id}{parent}});  # already got it
	push @loc, $tree->getnode_data($id);
    }
    return wantarray ? @loc : \@loc;
}

sub show_directories {
    my $this = shift;
    my $section = new ExSite::Section(id=>$this->{section_id});
    my @path = ( 
	{ label=>"Top", url=>$this->link(section_id=>undef,id=>undef,cmd=>undef) },
	{ label=>$section->label, url=>$this->link(section_id=>$section->id,id=>undef,cmd=>undef) },
	);
    my $out = $ui->PathBar(links=>\@path);

    my @dir = $this->get_directories();
    my $r = new ExSite::ReportBuilder(title=>"Location Directories");
    $r->headers("Title","Type","Locations");
    $r->nodata("No locations defined");
    my $c = new ExSite::Content();
    my $tree = $c->get_content_tree;
    foreach my $dir (@dir) {
	my $d = $c->get_content_obj($dir);
	$r->push(
	    $ml->a($d->title,{href=>$this->link(id=>$d->id)}),
	    $d->subtype,
	    $ml->div($tree->count({type=>$c->isubtype("location")},$d->id),{class=>"num"})
	    );
    }
    $r->tools($ml->a("new directory",{href=>$this->link(cmd=>"newdir")}));
    $out .= $r->make;
    return $out;
}

sub show_directory {
    my ($this,$dir) = @_;
    $dir or $dir = $this->{content};
    my $out;
    my @loc = $dir->get_contents("location");
    if ($dir->subtype eq "location_directory" || @loc > 0) {
	my $imgdir = "$config{server}{HTMLpath}/_ExSite/images/icons";
	$out = $ui->MenuBar(
	    links=>[
		{label=>"locations", url=>$this->link(cmd=>undef), img=>"$imgdir/home.png"},
		{label=>"configure", url=>$this->link(cmd=>"conf"), img=>"$imgdir/conf.png"},
		{label=>"new location", url=>$this->link(cmd=>"add"), img=>"$imgdir/add.png"},
		{label=>"publish", url=>$this->link(cmd=>"publish"), img=>"$imgdir/publish.png"},
		{label=>"DELETE", url=>$this->link(cmd=>"del"), img=>"$imgdir/delete.png"},
	    ],
	    padding=>0
	    );
    }
    my $cmd = $this->{input}{cmd};
    if ($cmd eq "conf") {
	$out .= $this->configure($dir);
    }
    elsif ($cmd eq "add") {
	$out .= $this->new_location();
    }
    elsif ($cmd eq "del") {
	$out .= $this->delete();
    }
    else {
	my $r = new ExSite::ReportBuilder(title=>"Locations in ".$ml->em($dir->title));
	$r->headers("Name","Location");
	$r->nodata("No locations defined");
	foreach my $loc (@loc) {
	    my @cdata = $share{DB}->fetch_child("contact","content",$loc->id);
	    my @contact;
	    foreach my $cdata (@cdata) {
		my $c = new Modules::ID::Contact(data=>$cdata);
		push @contact, $c->show_address_abbr();
	    }
	    $r->push(
		$ml->a($loc->title,{href=>$this->link(id=>$loc->id)}),
		join($ml->br,@contact)
		);
	}
	$out .= $r->make;
    }
    return $out;
}

sub new_directory {
    my $this = shift;
    my $out = $ml->h1("New Directory");
    my $content = $this->{content} || new ExSite::Content();
    my $input = new ExSite::Input();
    my $post = $input->post();
    if ($post->{title}) {
	my $dir = $content->new_content_obj(
	    title=>$post->{title},
	    type=>$content->isubtype("location_directory"),
	    parent=>$content->defined ? $content->id : $this->{section_id},
	    );
	if ($dir->id) {
	    $ml->location($this->link(__plaintext=>1,cmd=>undef,id=>$dir->id));
	    return;
	}
	else {
	    $out .= &ExSite::Config::show_diagnostics();
	}
    }
    my $f = new ExSite::FormBuilder(action=>$this->link());
    $f->input(name=>"title",prompt=>"Directory Name",type=>"text",size=>80,required=>1);
    $out .= $f->make();
    return $out;
}

sub show_location {
    my ($this,$loc) = @_;
    $loc or $loc = $this->{content};
    my $out;
    my $imgdir = "$config{server}{HTMLpath}/_ExSite/images/icons";
    $out .= $ui->IconBar(
	links=>[
	    {label=>"preview", url=>$this->link(cmd=>undef), img=>"$imgdir/view.png"},
	    {label=>"description", url=>$this->link(cmd=>"edit"), img=>"$imgdir/edit.png"},
	    {label=>"configure", url=>$this->link(cmd=>"conf"), img=>"$imgdir/conf.png"},
	    {label=>"contacts", url=>$this->link(cmd=>"contact"), img=>"$imgdir/email.png"},
	    undef,
	    {label=>"publish", url=>$this->link(cmd=>"publish"), img=>"$imgdir/publish.png"},
	    {label=>"DELETE", url=>$this->link(cmd=>"del"), img=>"$imgdir/delete.png"},

	],
	padding=>0
	);
    my $cmd = $this->{input}{cmd};
    if ($cmd eq "conf") {
	$out .= $this->configure($loc);
    }
    elsif ($cmd eq "edit") {
	$out .= $this->update($loc,prompt=>"Location Description",name=>"description",format=>"html");
    }
    elsif ($cmd eq "del") {
	$out .= $this->delete();
    }
    elsif ($cmd =~ /contact/) {
	$out .= $this->show_contacts();
    }
    else {
	$out .= $ui->BasicBox(title=>"preview",pane=>$loc->preview());
    }
}

sub new_location {
    my $this = shift;
    my $out = $ml->h1("New Location");
    my $input = new ExSite::Input();
    my $post = $input->post();
    if (keys %$post > 0) {
	my $data = $share{DB}->parse_parts(%$post);
	my $loc = $this->{content}->new_content_obj(
	    title=>$data->{title},
	    type=>$this->{content}->isubtype("location"),
	    parent=>$this->{content}->id,
	    );
	if ($loc->id) {
	    if ($data->{description}) {
		$loc->revise(data=>$data->{description},format=>"text") or 
		    $this->error("Failed to save description.");
	    }
	    delete $data->{title};
	    delete $data->{description};
	    # lat, lon
	    my $lat = $this->{content}->meta_get("latitude");
	    my $lon = $this->{content}->meta_get("longitude");
	    if ($data->{lat} != $lat || $data->{lon} != $lon) {
		$this->{content}->meta_set("latitude",$data->{lat});
		$this->{content}->meta_set("longitude",$data->{lon});
		$this->{content}->save();
	    }
	    delete $data->{lat};
	    delete $data->{lon};
	    # remaining data is a contact record
	    if (scalar values %$data > 0) {
		$data->{content_id} = $loc->id;
		if (! $share{DB}->insert("contact",$data)) {
		    $this->error("Failed to save description.");
		}
	    }
	}
	if (&OnError) {
	    $out .= $share{DB}->show_diagnostics("error","html");
	    return $out;
	}
	else {
	    $ml->redirect($this->link(__plaintext=>1,id=>$loc->id,cmd=>undef));
	}
    }
    my $db = $share{DB};
    $db->set_action("insert");
    my $f = $db->form(action=>$this->link());
    $f->input(name=>"title",prompt=>"Location Name",type=>"text",size=>80,required=>1);
    $db->input_htmleditor(
	prompt=>"Description (optional)",
	name=>"description",
	value=>"",
	editor_height=>250,
	editor_width=>550,
	);
    $f->input(name=>"lat",prompt=>"Latitude",type=>"text",size=>10);
    $f->input(name=>"lon",prompt=>"Longitude",type=>"text",size=>10);
    $db->form()->input(type=>"preformatted",name=>"contact_hdg",input=>$ml->h2("Contact Information"));
    $db->input_record({
	table=>"contact",
	data=>{location_id=>"_1",type=>"main"},
	show=>["type","address","city","provstate","country","pcode","phone1","fax","email","web"],
	simplename=>1,
    });
    my $out = $ml->h1("New Location");
    $out .= $db->form()->make();
    return $out;
}

sub show_contacts {
    my $this = shift;
    my $out;
    my $cmd = $this->{input}{cmd};
    if ($cmd eq "edit_contact") {
	return $this->edit_contact();
    }
    elsif ($cmd eq "del_contact") {
	return $this->delete_contact();
    }
    elsif ($cmd eq "add_contact") {
	return $this->add_contact();
    }
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
    return $ui->BasicBox(title=>"Contacts for ".$ml->em($this->{content}->title),pane=>$out);
}

sub edit_contact {
    my $this = shift;
    my $out = $ml->h1("Edit Contact");
    my $contact = new Modules::ID::Contact(id=>$this->{input}{contact_id});
    $out .= $contact->edit(
	hide=>["account_id"],
	action=>$this->link(__plaintext=>1),
	);
    return $out;
}

sub add_contact {
    my $this = shift;
    my $ui = new ExSite::UI;
    my $contact = new Modules::ID::Contact();
    return $ui->BasicBox(
	title=>"Add new contact information for ".$ml->em($this->{content}->title),
	pane=>$contact->make(
	    data=>{content_id=>$this->{input}{id}},
	    hide=>["content_id","account_id"],
	    action=>$this->link(__plaintext=>1),
	)
	);
}

sub del_contact {
    my $this = shift;
    my $c = new Modules::ID::Contact(id=>$this->{input}{contact_id});
    if ($c->approve("delete")) {
	$c->delete();
    }
    else {
	return $this->error("Delete contact: permission denied.");
    }
}

sub edit_contact_old {
    my $this = shift;
    my $out = $ml->h1("Edit Contact");
    my $contact = new Modules::ID::Contact(id=>$this->{input}{contact_id});
    if (scalar keys %{$this->{post}}) {
	delete $this->{post}{action};
	$contact->setup(data=>$this->{post},dirty=>1);
	if ($contact->save) {
	    $ml->location($this->link(__plaintext=>1,cmd=>"contact"));
	}
	else {
	    $out .= $share{DB}->show_diagnostics("error","html");
	}
    }
    else {
	$out .= $contact->edit(
	    hide=>["account_id"],
	    action=>$this->link(__plaintext=>1),
	    );
    }
    return $out;
}

sub add_contact_old {
    my $this = shift;
    my $out = $ml->h1("Add new contact information for ".$ml->em($this->{content}->title));
    my $contact = new Modules::ID::Contact();
    if (scalar keys %{$this->{post}}) {
	delete $this->{post}{action};
	$contact->setup(data=>$this->{post},dirty=>1);
	if ($contact->save) {
	    $ml->location($this->link(__plaintext=>1,cmd=>"contact"));
	}
	else {
	    $out .= $share{DB}->show_diagnostics("error","html");
	}
    }
    else {
	$out .= $contact->make(
	    data=>{content_id=>$this->{input}{id}},
	    hide=>["content_id","account_id"],
	    action=>$this->link(__plaintext=>1),
	    );
    }
    return $out;
}

sub delete {
    my ($this) = @_;
    my $p = $this->{content}->parent();
    $this->SUPER::delete($this->{content});
    if (&OnError()) {
	return $ui->ErrorBox(pane=>&ExSite::Config::show_diagnostics());
    }
    $ml->redirect($this->link(__plaintext=>1,cmd=>undef,id=>$p->id));
}

1;
