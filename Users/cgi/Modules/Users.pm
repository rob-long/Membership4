package Modules::Users;

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
#
#  Setup users and groups.
#
#----------------------------------------------------------------------------

use strict;

use ExSite::Config;          # required
use ExSite::Input;           # optional input manager
use ExSite::Misc;            # optional utils
use ExSite::Util;            # optional utils
use ExSite::ML;              # optional markup-language generation
use ExSite::FormBuilder;     # optional form generation
use ExSite::ReportBuilder;   # optional report generation
use ExSite::Form;            # optional database manager
use ExSite::User;
use ExSite::Group;
use ExSite::UI;

use Modules::BaseDCD;
use vars qw(@ISA $ml $ui);
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
    return undef;
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
    elsif (/ModuleName/) {
	return "Users";
    }
    elsif (/ModuleInfo/) {
	return "Setup users and groups.";
    }
    elsif (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/Category/) {
	return "System";
    }
}

sub ctrl_panel {
    my $this = shift;
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    if ($this->{input}{cmd} eq "me") {
	return $this->show_me();
    }
    elsif ($this->{input}{cmd} eq "pwd") {
	return $this->my_password();
    }
    my $out = $this->set_section_id();
    my $sid = $this->get_section_id();
    $this->{section_id} = $sid;

    my ($upane,$gpane);

    if (! $sid) {
	$upane .= $ui->ErrorBox(
	    title=>"Universal Users",
	    pane=>"No site has been selected, so users created here will be universal users - they can log into any section on the system.",
	    );
    }	    
    $upane .= $this->show_users();

    if (! $sid) {
	$gpane .= $ui->ErrorBox(
	    title=>"Universal Groups",
	    pane=>"No site has been selected, so groups created here will be universal groups, which will be available to any section on the system.",
	    );
    }	    
    $gpane .= $this->show_groups();

    my $thistab = ($this->{input}{cmd} =~ /group/) ? 1 : 0;
    $out .= $ui->DynTabBox(
	tabs=>["Users","Groups"],
	panes=>[$upane, $gpane],
	thistab=>$thistab,
	);
    return $out;
}

sub get_users {
    my $this = shift;
    my $sid = $this->{section_id} || "0";
    my @u = $share{DB}->fetch_match("user",{section_id=>$sid});
    return \@u;
}

sub get_groups {
    my $this = shift;
    my $sid = $this->{section_id} || "0";
    my @g = $share{DB}->fetch_match("usergroup",{section_id=>$sid});
    return \@g;
}

sub show_users {
    my ($this,$ulist) = @_;
    if ($this->{input}{cmd}) {
	my $cmd = $this->{input}{cmd};
	if ($cmd eq "edituser") {
	    return $this->edit_user();
	}
#	elsif ($cmd eq "showuser") {
#	    return $this->show_user();
#	}
	elsif ($cmd eq "newuser") {
	    return $this->new_user();
	}
	elsif ($cmd eq "deluser") {
	    $share{DB}->trash_r("user",$this->{input}{uid});
	    $ml->location($this->link(__plaintext=>1,cmd=>undef,uid=>undef));
	}
    }
    my $s = new ExSite::Section(id=>$this->{section_id});
    my $sname = $s->id ? $s->label : "all sections";
    $ulist or $ulist = $this->get_users();
    my $r = new ExSite::ReportBuilder(title=>"Users for $sname",nodata=>"This site has no users.");
    $r->headers("Name","Login","Level","Options");
    foreach my $u (@$ulist) {
	my $user = new ExSite::User(data=>$u);
	my $uid = $user->id;
	$r->push(
	    #$ml->a($user->name,{href=>$this->link(cmd=>"showuser",uid=>$uid)}),
	    $user->name,
	    $user->login,
	    $ml->div($user->level,{class=>"num"}),
	    $ui->fatool("configure",url=>$this->link(cmd=>"edituser",uid=>$uid)).
	    $ui->fatool("delete",confirm=>'WARNING: Deleting users is risky, as it also deletes MANY other pieces of data that are associated with them. Only do this if you REALLY know what you are doing.',url=>$this->link(cmd=>"deluser",uid=>$uid),tone=>"bad")
	    );
    }
    $r->tools(
	$ui->fatool("add",label=>"new user",url=>$this->link(cmd=>"newuser"),tone=>"good")
	);

    return $r->make();
}

sub show_groups {
    my ($this,$glist) = @_;
    if ($this->{input}{cmd}) {
	my $cmd = $this->{input}{cmd};
	if ($cmd eq "showgroup") {
	    return $this->show_group();
	}
	elsif ($cmd eq "addgroup") {
	    return $this->add_to_group();
	}
	elsif ($cmd eq "editgroup") {
	    return $this->edit_group();
	}
	elsif ($cmd eq "newgroup") {
	    return $this->new_group();
	}
	elsif ($cmd eq "rmgroup") {
	    $share{DB}->trash_r("groupkey",$this->{input}{gkey});
	    $ml->location($this->link(__plaintext=>1,cmd=>"showgroup"));
	}
	elsif ($cmd eq "delgroup") {
	    $share{DB}->trash_r("usergroup",$this->{input}{gid});
	    $ml->location($this->link(__plaintext=>1,cmd=>"group",gid=>undef));
	}
    }
    $glist or $glist = $this->get_groups();
    my $r = new ExSite::ReportBuilder(title=>"Groups",nodata=>"This site has no groups.");
    $r->headers("Name","Members","Options");
    foreach my $g (@$glist) {
	my $group = new ExSite::Group(data=>$g);
	my $gid = $group->id;
	$r->push(
	    $ml->a($group->name,{href=>$this->link(cmd=>"showgroup",gid=>$gid)}),
	    $ml->div($group->count_users,{class=>"num"}),
	    $ui->fatool("configure",url=>$this->link(cmd=>"editgroup",gid=>$gid)).
	    $ui->fatool("delete",url=>$this->link(cmd=>"delgroup",gid=>$gid),tone=>"bad",confirm=>"Really delete this group?")
	    );
    }
    $r->tools(
	$ui->fatool("add",label=>"new group",url=>$this->link(cmd=>"newgroup"),tone=>"good")
	);

    return $r->make();
}

sub new_group {
    my $this = shift;
    my $gr = new ExSite::Group;
    if (scalar keys %{$this->{post}}) {
	$gr->do_make();
	$ml->location($this->link(__plaintext=>1,cmd=>"group"));
	return;
    }
    return $ml->h1("New Group").
	$gr->make(
	    data=>{section_id=>$this->{section_id}},
	    hide=>["section_id"],
	    action=>$this->link(),
	);
}

sub edit_group {
    my $this = shift;
    my $gr = new ExSite::Group(id=>$this->{input}{gid});
    if (scalar keys %{$this->{post}}) {
	$gr->do_edit();
	$ml->location($this->link(__plaintext=>1,cmd=>"group"));
	return;
    }
    return $ml->h1("Configure Group").
	$gr->edit(
	    action=>$this->link(),
	);
}

sub new_user {
    my $this = shift;
    my $out = $ml->h1("New User");
    my $user = new ExSite::User;
    if (scalar keys %{$this->{post}}) {
	$user->do_make();
	if (&OnError) {
	    $out .= &ExSite::Config::show_diagnostics();
	}
	else {
	    $ml->location($this->link(__plaintext=>1,cmd=>undef));
	    return $out;
	}
    }
    $out .= $user->make(
	data=>{section_id=>$this->{section_id},access=>1},
	hide=>["section_id"],
	);
    return $out;
}

sub edit_user {
    my $this = shift;
    my $out;
    my $gr = new ExSite::User(id=>$this->{input}{uid});
    if (scalar keys %{$this->{post}}) {
	my %u = $share{DB}->parse_parts(%{$this->{post}});
	delete $u{action};
	delete $u{$config{auth}{user_pwd_column}};
	$gr->setup(data=>\%u);
	$gr->set("dirty",1);
	if ($gr->save()) {
	    $ml->location($this->link(__plaintext=>1,cmd=>undef));
	}
	else {
	    $out .= $share{DB}->show_diagnostics("error","html");
	}
    }
    $out .= $ml->h1("Edit User").
	$gr->edit(
	    hide=>[$config{auth}{user_pwd_column}],
	    action=>$this->link(),
	    simplename=>1,
	);
    return $out;
}

sub show_group {
    my $this = shift;
    my $gr = new ExSite::Group(id=>$this->{input}{gid});
    my $klist = $gr->group_keys();
    my $r = new ExSite::ReportBuilder(title=>"Members of ".$gr->name,nodata=>"This group has no members.");
    $r->headers("Name","Login","Level","Options");
    while (my $key = $klist->next) {
	my $u = new ExSite::User(id=>$key->getdata("uid"));
	$r->push(
	    $u->name,
	    $u->login,
	    $ml->div($u->level,{class=>"num"}),
	    $ui->fatool("delete",label=>"remove",url=>$this->link(cmd=>"rmgroup",gkey=>$key->getdata("groupkey_id")),tone=>"bad"),
	    );

    }
    $r->tools(
	$ui->fatool("add",label=>"add to group",url=>$this->link(cmd=>"addgroup"),tone=>"good")
	);
    return 
	$r->make().
	$ml->p($ui->Button(label=>"done with ".$ml->em($gr->name),url=>$this->link(gid=>undef,cmd=>undef),faicon=>"back"));
}

sub add_to_group {
    my $this = shift;
    my $out;
    my $gr = new ExSite::Group(id=>$this->{input}{gid});
    if (scalar keys %{$this->{post}}) {
	my @uid = split /; /,$this->{post}{uid};
	my $nadd;
	foreach my $uid (@uid) {
	    $nadd++ if $share{DB}->insert("groupkey",{gid=>$this->{input}{gid},uid=>$uid});
	}
	$out .= $ml->p("Added $nadd user(s).");
	if ($nadd) {
	    $out .= $this->show_group();
	    return $out;
	}
	$out .= $share{DB}->show_diagnostics("error","html");
    }
    $out .= $ml->h1("Add Users to ".$ml->em($gr->name));
    $out .= $ml->p("Select as many users as you need to add to this group. Shift-click selects a range of names. Ctrl-click toggles a selection.");
    my $f = new ExSite::FormBuilder(action=>$this->link());
    #$f->input(prompt=>"UID",name=>"uid",type=>"text");
    my @u = $share{DB}->fetch_match($config{auth}{user_table},{section_id=>$this->{section_id}});
    my @opt;
    foreach my $u (@u) {
	my $user = new ExSite::User(data=>$u);
	push @opt, {text=>$user->name." (UID:".$user->id.")",value=>$user->id};
    }
    $f->input(prompt=>"Choose user:",name=>"uid",options=>\@opt,type=>"select",multiple=>1,size=>25,required=>1);
    $out .= $f->make();
    return $out;
}

sub show_me {
    my $this = shift;
    my $out;
    my $gr = new ExSite::User();  # currently logged-in user
    if (scalar keys %{$this->{post}}) {
	my %u = $share{DB}->parse_parts(%{$this->{post}});
	delete $u{action};
	delete $u{$config{auth}{user_pwd_column}};
	$gr->setup(data=>\%u);
	$gr->set("dirty",1);
	if ($gr->save()) {
	    $ml->location($this->link(__plaintext=>1,cmd=>undef));
	}
	else {
	    $out .= $share{DB}->show_diagnostics("error","html");
	}
    }
    $out .= $ml->h1($gr->name).
	$gr->edit(
	    hide=>[$config{auth}{user_pwd_column}],
	    action=>$this->link(),
	    simplename=>1,
	);
    return $out;
}

sub my_password {
    my $this = shift;
    return $share{DB}->change_password_form();
}

1;

