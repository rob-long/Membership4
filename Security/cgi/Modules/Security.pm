package Modules::Security;

# Security : general-purpose security tool

# ops
# secdelkey
# secnewkey

use strict;
use ExSite::Config;
use ExSite::Util;
use ExSite::Misc;
use ExSite::Form;
use ExSite::Section;
use ExSite::User;
use ExSite::Group;
use ExSite::UI;
use ExSite::Module qw(&module_list);
use Modules::BaseDCD;

use vars qw(@ISA $ml $ui);
@ISA = qw(Modules::BaseDCD);

sub read {
    my ($this,$options) = @_;
    my $in = new ExSite::Input;
    $this->{input} = $in->combine;
    $this->{post} = $in->post;
    $this->{is_post} = scalar keys %{$this->{post}};
}

# write method provides a change password function for the logged-in user

sub write {
    my ($this,$options) = @_;
    return $share{DB}->change_password_form();
}

sub ioctl {
    my $this = shift;
    $_ = shift;   # $_ is the ioctl request
    if (/ModuleName/) {
	return "Security Manager";
    }
    elsif (/ModuleInfo/) {
	return "The Security Manager controls the various security features that 
define who can access websites, and which web applications those sites
are permitted to run.";
    }
    elsif (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/Category/) {
	return "System";
    }
    elsif (/Access/) {
	return 8;
    }
}

sub ctrl_panel {
    my $this = shift;
    $this->setup_querylib;
    my $db = $share{DB};
    return $this->error("Permission denied.") if (! $db->is_admin);

    $this->{name} = $config{Security}{user_name_field} || "name";

    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    my $in = $this->{input};

    my ($pane,$itab);
    if ($in->{seccmd} eq "adm") {
	$pane = $this->list_admins();
	$itab = 1;
    }
    elsif ($in->{seccmd}) {
	$pane = $this->do_action;
	if ($in->{seccmd} =~ /^sec/) { $itab = 0; }
	elsif ($in->{seccmd} =~ /^adm/) { $itab = 1; }
    }
    elsif ($in->{section_id}) {
	$pane = $this->show_site;
	$itab = 0;
    }
    else {
	$pane = $this->list_sites();
	$itab = 0;
    }
    return $ui->TabBox(
	tabs=>[
	    {label=>"Sections",url=>$this->link(seccmd=>undef,section_id=>undef,uid=>undef,key=>undef)},
	    {label=>"Administrators",url=>$this->link(seccmd=>"adm",section_id=>undef,uid=>undef,key=>undef)},
	],
	pane=>$pane,
	thistab=>$itab,
	);
}

sub do_action {
    my $this = shift;
    my $cmd = $this->{input}{seccmd};
    my $db = $share{DB};
    my $sid = $this->{input}{section_id};
    $this->{site} = $db->fetch("section",$sid);
    my $out;
    
    # site info

    if ($cmd eq "admnew") {
	return $this->new_admin();
    }
    elsif ($cmd eq "admpromote") {
	return $this->promote_admin();
    }
    elsif ($cmd eq "admown") {
	return $this->show_admin();
    }
    elsif ($cmd eq "admedit") {
	return $this->edit_admin();
    }
    elsif ($cmd eq "edserv" || $cmd eq "newserv") {
	$out .= $this->service;
    }
    elsif ($cmd eq "delserv") {
	$out .= $this->delserv;
    }
    elsif ($cmd eq "edkey") {
	$out .= $this->edkey;
    }
    elsif ($cmd =~ /delkey/) { #  admdelkey, secdelkey
	$out .= $this->delkey;
    }
    elsif ($cmd =~ /addkey/) { # admaddkey, secaddkey
	$out .= $this->addkey;
    }
    elsif ($cmd =~ /editkey/) { # admeditkey, seceditkey
	$out .= $this->editkey;
    }
    elsif ($cmd eq "newadmin") {
	$out .= $this->newadmin;
    }
    elsif ($cmd eq "proadmin") {
	$out .= $this->proadmin;
    }
    elsif ($cmd eq "demuser") {
	$out .= $this->demuser;
    }
    elsif ($cmd eq "archiveuser") {
	$out .= $this->archiveuser;
    }
    elsif ($cmd eq "deluser") {
	$out .= $this->deluser;
    }
    elsif ($cmd eq "delsite") {
	$out .= $this->delsite;
    }
    else {
	$out .= $this->error("Unknown option.");
    }
    return $out;
}

sub list_admins {
    my $this = shift;
    if ($this->{input}{uid}) {
	return $this->show_admin();
    }
    my $db = $share{DB};
    my $out;
    my $r = new ExSite::ReportBuilder(
	title=>"Administrators",
	headers=>["Name","Home","Level","Keys"],
	);
    my @adm = $db->get_query("all admins");
    foreach my $adm (@adm) {
	my $u = new ExSite::User(data=>$adm);
	my $home = $u->home();
	my $k = $u->keys();
	$r->push(
	    $ml->a($u->name,{href=>$this->link(uid=>$u->id)}),
	    $ml->a($home->name,{href=>$this->link(section_id=>$home->id,seccmd=>undef)}),
	    $u->level,
	    $k->count,
	    );
    }
    $r->tools(
	$ui->Button(label=>"new admin",url=>$this->link(seccmd=>"admnew"),size=>"s",faicon=>"user").
	$ui->Button(label=>"promote user",url=>$this->link(seccmd=>"admpromote"),size=>"s",faicon=>"star")
	);
    $out .= $r->make;
    return $out;
}

sub show_admin {
    my ($this,$uid) = @_;
    $uid or $uid = $this->{input}{uid};
    my $u = new ExSite::User(id=>$uid);
    my $out = $ml->p($ui->Button(label=>"all administrators",url=>$this->link(uid=>undef,seccmd=>"adm"),type=>"link-button",faicon=>"back")).$ml->h1($u->name);
    if (! $u->is_executive()) {
	$out .= $ui->ErrorBox(title=>"Warning",
			      pane=>"This user is not of a sufficient level to be an administrator. (Access level is ".$u->level.", where as level 5 is the minimum for admin duties.)");
    }

    my $r = new ExSite::ReportBuilder(
	title=>$u->name,
	headers=>["Name","Email","Home","Access Level"],
	data=>[$u->name,$u->email,$u->home->name,$u->level]
	);
    $r->tools(
	$ui->fatool("edit",url=>$this->link(seccmd=>"admedit",uid=>$uid)).
	$ui->fatool("delete",confirm=>"WARNING: deleting admins can also delete a lot of other records and history. Only do this if you REALLY know what you are doing.",url=>$this->link(seccmd=>"admdel",uid=>$uid),tone=>"bad"),
	);
    $out .= $r->make;

    # keys

    my $keys = $u->keys();
    $r->init(
	title=>"Keys",
	headers=>["Key to","Type","Role","Options"],
	nodata=>"No keys have been issued to this user.",
	);
    my $c = new ExSite::Content();
    my $nowner = 0;
    while (my $k = $keys->next) {
	if ($k->getdata("role") eq "owner") {
	    # not an admin privelege
	    $nowner++;
	    next if ($this->{input}{seccmd} ne "admown");
	}
	$c->setup(id=>$k->getdata("content_id"));
	my $ctitle = $c->defined ? $c->subtype().": ".$c->title : "n/a";
	if ($k->getdata("uid") == $u->id) {
	    $r->push(
		$ctitle,
		"private/".($k->showdata("type") || "grant"),
		$k->showdata("role"),
		$ui->fatool("cross",label=>"revoke",url=>$this->link(seccmd=>"admdelkey",key=>$k->id,uid=>$uid),tone=>"bad").
		$ui->fatool("edit",label=>"modify",url=>$this->link(seccmd=>"admeditkey",key=>$k->id,uid=>$uid))
		);
	}
	else {
	    # group key
	    $r->push(
		$ctitle,
		"group/".($k->showdata("type") || "grant"),
		$k->showdata("role"),
		$ui->fatool("cross",label=>"revoke",url=>$this->link(seccmd=>"admdelkey",key=>$k->id),tone=>"bad").
		$ui->fatool("edit",label=>"modify",url=>$this->link(seccmd=>"admeditkey",key=>$k->id))
		);
	}
    }
    $r->tools(
	$ui->fatool("key",label=>"new key",url=>$this->link(seccmd=>"admaddkey",uid=>$uid),tone=>"good")
	);
    if ($nowner) {
	if ($this->{input}{seccmd} eq "admown") {
	    $r->foot($ml->a("Show admin keys only",{href=>$this->link(seccmd=>"adm",uid=>$uid)}));
	}
	else {
	    $r->foot("Additionally, this admin has $nowner ownership keys. ".
		     $ml->a("[show]",{href=>$this->link(seccmd=>"admown",uid=>$uid)}));
	}
    }
    $out .= $r->make;

    return $out;
}

sub new_admin {
    my $this = shift;
    my $out;
    my @section = $share{DB}->get_query("all sites");
    if (scalar keys %{$this->{post}} > 0) {
	return $this->do_admin();
    }
    else {
	$out .= $ml->h1("New Administrator");
	my $fb = $share{DB}->form();
	$fb->template("<table>",
		      "<tr><td>[[prompt]]</td><td>[[input]]</td></tr>",
		      "</table>");
	my $table = $config{auth}{user_table};
	foreach my $col ($share{DB}{map}->get_columns($table)) {
	    my %col = $share{DB}{map}->get_column($table,$col);
	    next if ($col{datatype} eq "key#");
	    if ($col eq $config{auth}{user_access_column}) {
		$out .= &ExSite::Config::insert_js("HTML.js");
		$fb->input(name=>$config{auth}{user_access_column},type=>"select",prompt=>"Access level",options=>[5,6,7,8,9],value=>7,tail=>$ui->HelpPopup(label=>"hint",message=>"Level 7 is a website manager, who can update content and modify website data. Level 8 is a system administrator, who can also update system data and access restricted functions. Level 9 has no restrictions. (This could be dangerous!)"));
	    }
	    else {
		$share{DB}->input_column(
		    table=>$table,
		    column=>$col,
		    size=>40,
		    name=>$col{column}
		    );
	    }
	}
	$fb->input(type=>"preformatted",
		   name=>"key_help",
		   prompt=>"<tr><td colspan=2>".$ml->h2("Keys"),
		   input=>$ml->p("Select the roles for the sites/sections you want this administrator to have access to:")."</td></tr>
<tr><th>Site</th><th>Roles</th></tr>"
	    );
	my @role = split /\|/,$share{DB}{map}->regexp("set:role");
	my @row;
	foreach my $section (@section) {
	    my $input;
	    foreach my $role (@role) {
		$input .= $ml->input(undef,{type=>"checkbox",name=>"_s_".$section->{content_id}."_$role"})."$role ";
	    }
	    $fb->input(
		prompt=>$section->{title}, 
		input=>$input,
		name=>"_s_".$section->{content_id},
		);
	}

	$out .= $fb->make();
    }
    return $out;
}

sub promote_admin {
    my $this = shift;
    my $out;
    if (scalar keys %{$this->{post}} > 0) {
	return $this->do_admin();
    }
    else {
	$out .= $ml->h1("Promote User to Administrator");
	my $fb = $share{DB}->form();
	$fb->template("<table>",
		      "<tr><td>[[prompt]]</td><td>[[input]]</td></tr>",
		      "</table>");
	my $table = $config{auth}{user_table};
	my @opt;
	foreach my $udata ($share{DB}->get_query("all users")) {
	    my $user = new ExSite::User(data=>$udata);
	    push @opt, { value=>$user->id,
			 text=>$user->name." (UID:".$user->id.", level ".$user->level.")" };
	}
	$fb->input(name=>"uid",prompt=>"Select user to promote:",
		   type=>"select",options=>\@opt,required=>1,nullvalue=>"== select user ==");
	$fb->input(name=>$config{auth}{user_access_column},type=>"select",prompt=>"Promote to level",options=>[5,6,7,8,9],value=>7,tail=>$ui->HelpPopup(label=>"hint",message=>"Level 7 is a website manager, who can update content and modify website data. Level 8 is a system administrator, who can also update system data and access restricted functions. Level 9 has no restrictions. (This could be dangerous!)"));
	$fb->input(type=>"preformatted",
		   name=>"key_help",
		   prompt=>"<tr><td colspan=2>".$ml->h2("Keys"),
		   input=>$ml->p("Select the roles for the sites/sections you want this administrator to have access to:")."</td></tr>
<tr><th>Site</th><th>Roles</th></tr>"
	    );
	my @role = split /\|/,$share{DB}{map}->regexp("set:role");
	my @row;
	my @section = $share{DB}->get_query("all sites");
	foreach my $section (@section) {
	    my $input;
	    foreach my $role (@role) {
		$input .= $ml->input(undef,{type=>"checkbox",name=>"_s_".$section->{content_id}."_$role"})."$role ";
	    }
	    $fb->input(
		prompt=>$section->{title}, 
		input=>$input,
		name=>"_s_".$section->{content_id},
		);
	}

	$out .= $fb->make();
    }
    return $out;
}

sub edit_admin {
    my $this = shift;
    my $out;
    my $user = new ExSite::User(id=>$this->{input}{uid});
    if (scalar keys %{$this->{post}} > 0) {
	$out .= $user->do_edit();
    }
    else {
	$out .= $ml->h1("Edit Administrator");
	$out .= $user->edit(action=>$this->link(),hide=>[$config{auth}{user_pwd_column}]);
    }
    return $out;
}

sub delete_admin {
    my $this = shift;
    $share{DB}->trash_r($config{auth}{user_pwd_column},$this->{input}{uid});
    $ml->location($this->link(__plaintext=>1,seccmd=>"adm",uid=>undef));
    return;
}

sub do_admin {
    my $this = shift;
    my $out;
    my $data = $share{DB}->parse_parts(%{$this->{post}});
    my (%udata,%kdata);
    foreach my $key (keys %$data) {
	if ($key =~ /^_s_(\d+)_(\w+)$/) {
	    if (! exists $kdata{$1}) { $kdata{$1} = []; }
	    push @{$kdata{$1}}, $2;
	}
	else {
	    $udata{$key} = $data->{$key};
	}
    }
    my $user = new ExSite::User(data=>\%udata);
    $user->set("dirty",1);
    if ($user->save) {
	# save keys
	foreach my $content_id (keys %kdata) {
	    my $role = join "; ", @{$kdata{$content_id}};
	    $share{DB}->insert("content_key",{uid=>$user->id,content_id=>$content_id,role=>$role,type=>"grant"});
	}
    }
    if (&OnError()) {
	$out .= &ExSite::Config::show_diagnostics();
	$out .= $ml->p($ui->BackButton());
	return $out;
    }
    $ml->location($this->link(__plaintext=>1,seccmd=>"adm"));
    return $out;
}

sub addkey {
    my $this = shift;
    my $db = $share{DB};
    my $data = $share{DB}->parse_parts(%{$this->{post}});
    if ($data->{uid} && $data->{content_id}) {
	$db->insert("content_key",
		    {content_id=>$data->{content_id},
		     uid=>$data->{uid},
		     type=>$data->{type},
		     role=>$data->{role}});
	$ml->location($this->link(__plaintext=>1,seccmd=>undef,uid=>undef));
	return;
    }
    my $title = "New Administrator Key";
    my @hide;
    if ($this->{input}{section_id}) {
	my $s = new ExSite::Section(id=>$this->{input}{section_id});
	$title .= " for ".$s->title;
	push @hide, "content_id";
    }
    elsif ($this->{input}{uid}) {
	my $u = new ExSite::User(id=>$this->{input}{uid});
	$title .= " for ".$u->name;
	push @hide, "uid", "gid";
    }
    my $out = $ml->h1($title);
    $db->handler("select_foreign_key",\&CMS_select_admin_uid);
    $out .= $db->make(
	table=>"content_key",
	data=>{
	    content_id=>$this->{input}{section_id},
	    uid=>$this->{input}{uid},
	},
	hide=>\@hide,
	simplename=>1,
	action=>$this->link(),
	);
    return $out;
}

sub editkey {
    my $this = shift;
    my $db = $share{DB};
    if ($this->{is_post}) {
	my $data = $db->parse_parts(%{$this->{post}});
	$data->{content_key_id} = $this->{input}{key} if (! $data->{content_key_id});
	delete $data->{action};
	$db->update("content_key",$data);
	$ml->location($this->link(__plaintext=>1,seccmd=>undef,uid=>undef));
	return;
    }
    my $title = "Modify Administrator Key";
    my @hide;
    if ($this->{input}{section_id}) {
	my $s = new ExSite::Section(id=>$this->{input}{section_id});
	$title .= " for ".$s->title;
	push @hide, "content_id";
    }
    elsif ($this->{input}{uid}) {
	my $u = new ExSite::User(id=>$this->{input}{uid});
	$title .= " for ".$u->name;
	push @hide, "uid", "gid";
    }
    my $out = $ml->h1($title);
    $db->handler("select_foreign_key",\&CMS_select_admin_uid);
    $out .= $db->make(
	table=>"content_key",
	record=>$this->{input}{key},
	simplename=>1,
	action=>$this->link(),
	);
    return $out;
}

sub CMS_select_admin_uid {
    my ($this, $table, $rec, $col, $ftable) = @_;
    # ignore, if not using the CMS database
    if ($table eq "content_key" && $col eq "uid") {
	return $this->get_query("all admins");
    }
    if ($table eq "content_key" && $col eq "content_id") {
	return $this->get_query("all sites");
    }
}

# Fetch all section related data and place them under appropriate sections
sub fetch_sites{
    my ($this) = @_;
    my $db = $share{DB};
    my $c = new ExSite::Content;
    my $ctree = $c->get_content_tree();
    
    # Fetch data
    my @sites = $ctree->find({type=>$c->isubtype("section")});
    foreach my $site(@sites){
	my $sectionid = $site->{content_id};
	$site->{nkey} = $share{DB}->count("content_key",{content_id=>$sectionid});
	$site->{nuser} = $share{DB}->count("user",{section_id=>$sectionid});
	$site->{nserv} = $share{DB}->count("service",{section_id=>$sectionid});
    }
    return wantarray ? @sites : \@sites;
}

sub list_sites {
    my $this = shift;
    my $sites = shift;
    my $db = $share{DB};
    my $out;
    my %report = (
	title=>"Web sites / Sections",
	headers=>["Website","Keys","Users","Services"],
	data=>[],
	foot=>"Select a website/section to manage its security settings.",
	dynamic=>1,
	);
    my @sites = $sites ? @$sites : $this->fetch_sites();
    foreach my $site (@sites) {
	my $s = new ExSite::Section(data=>$site);
	my $nticket = $site->{nkey};
	my $nuser = $site->{nuser};
	my $nserv = $site->{nserv};
	push @{$report{data}},[$ml->a($s->title,{href=>$this->link(seccmd=>undef,section_id=>$s->id)}).$ml->br.$site->{description}, $nticket, $nuser, $nserv];
    }
    my $r = new ExSite::ReportBuilder(%report);
    $out .= $r->make;
    return $out;
}

sub show_site {
    my $this = shift;
    my $db = $share{DB};
    my $sid = $this->{input}{section_id};
    my $site = new ExSite::Section(id=>$sid);
    my $url = $this->link(serv=>undef,seccmd=>undef,section_id=>undef);
    my $out .= $ml->p($ui->Button(label=>"Back to site listing",url=>$url,type=>"link-button",faicon=>"back"));
    $out .= $ml->h1($site->title);

    my $root = ! $site->getdata("name");
    if ($root) {
	$out .= $ml->p("This is the root section of this system.");
    }
    
    # administrator keys

    my @keys = $site->keys;
    my $r = new ExSite::ReportBuilder();
    $r->title("Keys");
    $r->headers("Administrator","Login ID","Level","Roles","Options");
    foreach my $key (@keys) {
	my ($name, $login);
	my $user = $db->fetch($config{auth}{user_table},$key->{uid});
	if ($user) {
	    $name = $db->user_name($user);
	    $login = $user->{login};
	}
	else {
	    $name = "undefined member";
	    $login = "NO LOGIN";
	}
	my $del_url = $this->link(serv=>undef,seccmd=>"secdelkey",key=>$key->{content_key_id});
	$r->push(
	    $ml->a($name,{href=>$this->link(uid=>$key->{uid},seccmd=>"adm")}),
	    $login,
	    $user->{$config{auth}{user_access_column}},
	    $key->{role},
	    $ui->fatool("cross",label=>"revoke",url=>$this->link(serv=>undef,seccmd=>"secdelkey",key=>$key->{content_key_id}),tone=>"bad").
	    $ui->fatool("edit",label=>"modify",url=>$this->link(seccmd=>"seceditkey",key=>$key->{content_key_id}))
	    );
    }
    $r->tools($ui->fatool("key",label=>"new key",url=>$this->link(serv=>undef,seccmd=>"secaddkey"),tone=>"good"));
    $out .= $r->make();

    # add/remove services

    $r->init(title=>"Website Services",nodata=>"No services running on this site.");
    $r->headers("Service","Runs on page","Options");
    my @dcd = &module_list();
    my @services = $db->fetch_match("service",{section_id=>$sid});
    $url = $this->link();
    foreach my $serv (@services) {
	my $upd_url = $this->link(seccmd=>"edserv",serv=>$serv->{service_id});
	my $del_url = $this->link(seccmd=>"delserv",serv=>$serv->{service_id});
	my $page = new ExSite::Page(id=>$serv->{page_id});
	$r->push(
	    $serv->{name},
	    $page->title." (".$page->name.")",
	    $ui->fatool("delete",url=>$this->link(seccmd=>"delserv",serv=>$serv->{service_id}),tone=>"bad",confirm=>"Really delete this service?")
	    );
    }
    # new service
    $url = $this->link(serv=>undef,seccmd=>"newserv");
    $r->tools($ui->fatool("add",label=>"new service",url=>$this->link(seccmd=>"newserv",serv=>undef),tone=>"good"));
    $out .= $r->make();

    # groups

    my %data = (
	Groups => $share{DB}->count("usergroup",{section_id=>$this->{input}{section_id}}),
	Members => $share{DB}->count("user",{section_id=>$this->{input}{section_id}})
	);
    $r->init(
	title=>"Other",
	headers=>["Users","Groups"],
	data=>[
	    $share{DB}->count("user",{section_id=>$sid}),
	    $share{DB}->count("usergroup",{section_id=>$sid}),
	],
	);
    $out .= $r->make();

    $out .= $ui->ToolBar(links=>[
			     {label=>"Manage Users",url=>&ExSite::Module::launcher_link("Users","section_id=$sid")},
			     {label=>"Manage Groups",url=>&ExSite::Module::launcher_link("Users","section_id=$sid&cmd=group")}
			 ]);

    return $out;
}

sub service {
    my $this = shift;
    my $db = $share{DB};
    my $service_id = $this->{input}{serv};
    my $section_id = $this->{input}{section_id};
    if ($this->{input}{name}) {
	$db->insert("service",
		    {section_id=>$section_id,
		     name=>$this->{input}{name},
		     page_id=>$this->{input}{page_id}});
	$ml->location($this->link(__plaintext=>1,seccmd=>undef));
	return;
    }
    my $out = $ml->h1("Configure Website Services");
    my $br = $ml->br;
    my ($name,$page_id);
    if ($service_id) {
	my %serv = $db->fetch('service',$service_id);
	$name = $serv{name};
	$page_id = $serv{page_id};
    }
    my $f = new ExSite::FormBuilder();

    my @mod = &ExSite::Module::module_list;
    my $s = new ExSite::Section(id=>$this->{input}{section_id});
    my @p = $s->get_descendants("page");
    my @page_id = map { { value=>$_->{content_id}, text=>$_->{name} } } @p;
    
    $f->input(
	name=>"name",
	prompt=>"Application / Plug-in Module:",
	type=>"select",
	options=>\@mod,
	required=>1,
	nullvalue=>"== select application ==",
	);
    $f->input(
	name=>"page_id",
	prompt=>"Service Page",
	type=>"select",
	options=>\@page_id,
	nullvalue=>"== select page ==",
	);
    $out .= $f->make();
    return $out;
}

sub delkey {
    my $this = shift;
    my $db = $share{DB};
    my $key = $this->{input}{key};
    my $adminkey = $db->fetch("content_key",$key);
    my $nkey = $db->count("content_key",{uid=>$adminkey->{uid}});	
    my $out;
    $db->trash_key("content_key",$key);
    if ($nkey == 1) {
	# this was the only key for this administrator
	my $user = new ExSite::User(id=>$adminkey->{uid});
	if ($user->exists) {
	    my $site = $user->home;
	    my $name = $user->name;
	    my $level = $user->level;
	    $out .= $ml->h1("No Keys Left");
	    $out .= $ui->ErrorBox(title=>"WARNING",
					    pane=>"You removed the only 
administrator key for ".$ml->em($name).".  This user no longer has any
keys on this system. However, they still have level $level access. 
This may be an appropriate time to downgrade their access level, or
delete them entirely.");
	    $out .= $this->show_admin($user->id);
	    return $out;
	}
    }
    $ml->location($this->link(__plaintext=>1,seccmd=>undef,key=>undef));
    return $out;
}

sub delserv {
    my $this = shift;
    my $db = $share{DB};
    my $serv = $this->{input}{serv};
    $db->trash_key("service",$serv);
    return $this->show_site;
}

sub deluser {
    my $this = shift;
    my $db = $share{DB};
    my $user = $this->{input}{uid};
    $db->trash_key($config{auth}{user_table},$user);
    return $this->show_site;
}

sub setup_querylib {
    my $this = shift;
    my $db = $share{DB};
    $db->set_query("all admins",
		   sql => "select * from user where access>=5",
		   nparam => 0,
		   mode => "r",
		   keys => ["user"],
	);
    $db->set_query("all users",
		   sql => "select * from user where access<5",
		   nparam => 0,
		   mode => "r",
		   keys => ["user"],
	);


}

1;
