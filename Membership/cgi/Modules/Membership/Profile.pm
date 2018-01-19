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
# Notes:
# - show() handles all public display functions
# - commands via tools() are processed by show_cmd()
# - results of any posts are processed by post()
#
# - applications are a function of Membership::Type

package Modules::Membership::Profile;

use strict;
use ExSite::Config;
use ExSite::Content;
use ExSite::Misc;
use ExSite::Module qw(&get_module);
use Modules::ID::Contact;
use Modules::Finance::Cart;
use ExSite::Module qw(&read_conf);

use vars qw(@ISA $ml);
@ISA = qw(ExSite::Content);
$ml = &get_obj("ML");

sub my_subtype { return "profile"; }

# setup: can optionally pass a UID to find and setup a profile under that uid

sub setup {
    my ($this,%opt) = @_;
    $this->setup_querylib();
    if ($opt{uid}) {
    $this->setup_uid(%opt);
    }
    else {
    $this->SUPER::setup(%opt); # try generic setup
    if (! $this->ok) {
        # undefined object - setup current user's profile
        my $uid = $share{DB}->my_uid;
        if ($uid) {
        $opt{uid} = $uid;
        $this->setup_uid(%opt);
        }
    }
    }
    # dependencies
    $share{DB}->{map}->load_submaps("AddrBook");
    $share{DB}->{map}->load_submaps("Membership");
    if (! exists $config{Membership}{_loaded}) {
    &read_conf("Membership"); 
    }
    my $input = new ExSite::Input;
    my $in = $input->combine();
    $this->{in} = $input;
    $this->{input} = $in;
    $this->{post} = $input->post();
    return;
}

# setup_uid: setup first profile owned by a UID

sub setup_uid {
    my ($this,%opt) = @_;
    my @profile = $share{DB}->get_query("user profiles",$opt{uid});
    if (@profile > 0) {
    $this->{data} = $profile[0];
    $this->{id} = $this->{data}{content_id};
    $this->{uid} = $opt{uid};
    }
    $this->{Revision} = undef;
    $this->set_view($opt{view} || "normal");
    return;
}

# return the uid of the owner of this profile

sub uid {
    my $this = shift;
    if (! $this->{uid}) {
    my %role = $this->all_roles();
    if ($role{owner}) {
        my @uid = keys %{$role{owner}};
        $this->{uid} = $uid[0];
    }
    }
    return $this->{uid};
}

sub user {
    my $this = shift;
    return new ExSite::User(id=>$this->uid);
}

sub param_description_long {
    my $this = shift;
    return $this->show_formatted("profile_description");
}

sub param_membership_type {
    my $this = shift;
    my $t = $this->membership_type();
    return $t->label();
}

# sort dates so that we can pick out first, last log entries easier

sub get_dates {
    my ($this,$type) = @_;
    if (! $type && $this->{dates}) {
    return $this->{dates};
    }
    $this->load_children("content_date");
    my $dates = $this->SUPER::get_dates($type);
    if ($dates && $dates->count) {
    $dates->sort("start");
    $this->{dates} = $dates if (!$type);
    }
    return $dates;
}

sub expiry_date {
    my $this = shift;
    my $log = $this->get_dates();
    if ($log && $log->count) {
    $log->reset();
    my $logitem = $log->last();
    do {
        if ($logitem->getdata("description") eq "expire") {
        return new ExSite::Time($logitem->getdata("start"),"sql_datetime");
        }
        $logitem = $log->previous;
    } until (! $logitem);
    return new ExSite::Time($log->last->getdata("start"),"sql_datetime");
    }
    return undef;
}

sub member_since {
    my $this = shift;
    my $log = $this->get_dates();
    if ($log && $log->count) {
    $log->reset();
    while (my $logitem = $log->next) {
        if ($logitem->getdata("type") eq "log") {
        # this could be smarter;
        # I am returning the first date of a log entry on the assumption
        # that nothing is logged before then.
        return new ExSite::Time($logitem->getdata("start"),"sql_datetime");
        }
    }
    }
    return undef;
}

sub membership_type {
    my $this = shift;
    return $this->my_ancestor("membership_type");
}

# is_member: is the current user part of our family?

sub is_member {
    my ($this,$uid) = @_;
    $uid or $uid = $share{DB}->my_uid;
    return 1 if ($uid && $uid == $this->uid);
    return $this->SUPER::is_member($uid);
}

# replace [[contacts]] merge codes in templates

sub param_contacts {
    my $this = shift;
    my $out;
    $share{DB}->{map}->load_submaps();
    return undef if (!$this->contacts());
    foreach my $cdata (@{$this->contacts()}) {
    my $c = new Modules::ID::Contact(data=>$cdata);
    if ($c->allow) {
        # use lookup table from Membership::load_contacts if possible
        $out .= $c->show(info=>$share{contact_info}{$cdata->{contact_id}});
        last;
    }
    }
    return $out;
}

sub contact {
    my $this = shift;
    my $account_id = $this->account ? $this->{account_id} : 0;
    if ($account_id) {
    return $this->contacts->[-1];
    }
    return undef;
}

sub contacts {
    my $this = shift;
    return undef if (!$this->account());
    if (! defined $share{contact}) {
        my $allcontact = $share{DB}->fetch_match("contact",{account_id=>$this->account->{account_id}});
        foreach my $c (@$allcontact) {
        my $account_id = $c->{account_id};
        if (! exists $share{contact}{$account_id}) {
            $share{contact}{$account_id} = [];
        }
        push @{$share{contact}{$account_id}}, $c;
        }
    }
    return $share{contact}{$this->account->{account_id}};
}

sub account {
    my $this = shift;
    my @acct = $share{DB}->fetch_all("account");
    my %acct = &keywise("uid",\@acct);    
    # TODO: match section of account?
    if (defined $acct{$this->id}) {
    return $acct{$this->id};
    }
    return undef;
}

sub profile_header {
    my $this = shift;
    my $out;
    my $path = $ml->p(scalar $this->navpath(),{class=>"navpath"});
    $out .= $ml->div($path,{class=>"profilePath"});
    $out .= $ml->div($this->tools(),{class=>"profileTools"});
    return $out;
}

# user self-configure function

sub configure {
    my ($this) = @_;
    my $out;
    $out .= $this->profile_header();
    if (! $this->allow("edit")) {
    return $this->error($msg{"Sorry, you do not have permission to change this profile's settings."});
    }
    # display profile after post processed
    if (keys %{$this->{post}} > 0) {
        my $disptype = $this->displaytype;
        if ($disptype eq "none") {
            return undef;
        }
        elsif ($disptype eq "template") {
            return $this->expand();
        }
        elsif ($disptype eq "formatted") {
            my $fmt = $config{content}{format}{$this->subtype()} ||
            $config{content}{format}{content};
            $out = $this->show_formatted($fmt);
        }
        else {
            # raw content, show revision only
            $out = $this->show_revision();
        }

    }
    else {
    my $ml = &get_obj("ML");
    $out .= $ml->h1("Settings for ".$ml->em($this->title));
    my @hide = $this->{admin} ?
        qw(content_id type url parent template master sortkey content_role mtime ptime name language hide_from publish status) :
        qw(content_id type url parent template master sortkey content_role mtime ptime);

    # Note: this form can be templated using a custom editmeta_template

    $out .= $this->editmeta(
        hide=>\@hide,
        extra=>{cmd=>"conf"},
        );
    return $out;
    }
}

sub show_cmd {
    my ($this,$cmd) = @_;
    if ($cmd eq "pwd") {
    return $share{DB}->change_password_form();
    }
    elsif ($cmd eq "edit") {
    return "Redirected to configure".$this->configure();        
    return $this->update();
    }
    elsif ($cmd eq "conf") {
    return $this->configure();
    }
    elsif ($cmd eq "photo") {
    return $this->profile_photo();
    }
    elsif ($cmd eq "contact") {
    return $this->profile_contact();
    }
    elsif ($cmd eq "acct") {
    return $this->profile_account();
    }
    elsif ($cmd =~ /^renew/) {
    return $this->renew();
    }
    elsif ($cmd eq "login") {
    my $l = &get_module("Login");
    return $l->login($this->uid);
    }    
    return;
}

#--------------------------------------------------------------------------
# ExSite::Content

# show: main profile view

sub show {
    my ($this,%opt) = @_;
    my $out;
    # process any posts
    my $input = $this->{in};
    my $in = $this->{input};
    if ($input->is_post()  &&
    $this->url_is_me() &&
    $this->allow_post()) {
    $out .= $this->post();
    }
    # 
    if ($this->allow()) {
    if (! $opt{readonly} && $this->allow("edit")) {
        # check for tool use
        if ($in->{cmd}) {
        $out .= $this->show_cmd($in->{cmd});
        return $out;
        }
    }
    $out .= $this->SUPER::show();
    }
    else {
    $out = "Permission denied - Profile.pm.";
    }
    return $out;
}

# overload generic author metadata

sub author { 
    my $this = shift;
    my $author = $this->SUPER::author();
    if (! $author) {
    # return member name
    return $this->user->name();
    }
    return $author;
}

# 1-line description of profile

sub description { 
    my $this = shift; 
    my @info;
    my $fields = 
    $config{Profile}{description_fields} || 
    ["jobtitle","organization"];
    foreach my $fld (@$fields) {
    my $value = $this->dcmeta($fld);
    if ($value) { push @info, $value; } 
    }
    return join ", ",@info;
}

sub summary {
    my ($this,%opt) = @_;
    my $descr;
    my $fmt = 
    $config{content}{format}{$opt{format}} || 
    $this->find_format($this->subtype()."_summary") ||
    $config{content}{format}{summary};
    return $this->show_formatted($fmt,%opt);
}

sub revision {
    my ($this) = @_;
    $this->{Revision} = new ExSite::Revision();
    return $this->{Revision};
}

# preview - like show, but for admins

sub preview {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    my $ui = &get_obj("UI");
    $this->{admin} = 1;
    my $out .= $this->show(%opt);
    $out .= $ml->p($ui->Button(label=>"View on website",url=>$this->get_url,target=>"_blank"));
    $out .= $ml->p($ui->Button(label=>"Login",url=>$this->link(cmd=>"login",section_id=>),target=>"_blank"));
    return $out;
}

# tools - everything the profile owner can do on their own profile

sub tools {
    my ($this,%opt) = @_;
    return undef if (! $this->allow("edit") || 
             $this->{admin});  # admins get their own toolbars
    my $ui = &get_obj("UI");
    my $path1 = "$config{server}{HTMLpath}/_ExSite/images/icons";
#   my $path2 = "$config{server}{HTMLpath}/_Modules/Membership";
    my @tools = (
        {label=>$msg{"view&nbsp;profile"},img=>"$path1/user.png",url=>$this->get_url()},
        {label=>$msg{"edit&nbsp;profile"},img=>"$path1/edit.png",url=>$this->link(cmd=>"edit")},
        {label=>$msg{"settings"},img=>"$path1/conf.png",url=>$this->link(cmd=>"conf")},
        {label=>$msg{"photo/logo"},img=>"$path1/image.png",url=>$this->link(cmd=>"photo")},
        {label=>$msg{"contacts"},img=>"$path1/home.png",url=>$this->link(cmd=>"contact")},
        {label=>$msg{"account"},img=>"$path1/money.png",url=>$this->link(cmd=>"acct")},
        {label=>$msg{"password"},img=>"$path1/lock.png",url=>$this->link(cmd=>"pwd")},
    );
    if ($this->allow("renew")) {
    push @tools, {label=>$msg{"renew"},img=>"$path1/redo.png",url=>$this->link(cmd=>"renew")};
    }

    return $ui->IconBar(links=>\@tools);
}

# index - display an HTML listing of contents

sub index {
    my ($this,%opt) = @_;
    my $out;
    my $ml = &get_obj("ML");

    # link back to primary

    my $primary = $this->parent();
    if ($primary->subtype() eq "profile") {
    if (!$primary->hide_from("index")) {
        $out .= $ml->h3(&substitute($msg{"This member is affilated with ".$ml->a($ml->em("[[primary]]"))."."},
                    {primary=>$primary->label()}));
        $out .= $primary->summary();
    }
    }

    # index of secondaries

    my @secondary = $this->get_contents("profile");
    if (scalar @secondary > 0) {
    $out .= $ml->h3($msg{"Other Contacts"});
    foreach my $sec (@secondary) {
        next if ($sec->hide_from("index"));
        $out .= $sec->summary();
    }
    }

    return $out;
}

# process data posted to profile (from profile owner, usually)

sub post {
    my ($this,%opt) = @_;
    return $this->error("Posts not accepted here.") if (! $this->allow_post);
    my $ml = &get_obj("ML");

    # get post data
    my $input = new ExSite::Input;
    my $post = $this->{post};
    my $in = $input->combine();

    my $out;
    if ($in->{cmd} eq "pwd") {
    # update password
    my $stat = $share{DB}->change_password($in->{password0},$in->{password1},$in->{password2});
    if ($stat) {
        $out .= $ml->error($stat);
        $out .= $share{DB}->change_password_form();
    }
    else {
        $out .= $ml->p($msg{"Password changed."});
        $out .= $ml->p($ml->a("&lt; ".$msg{"Back to profile"},{href=>$this->link()}));
    }
    }
    elsif ($in->{cmd} eq "conf") {
    # configure profile
    return $this->do_editmeta();
    }
    elsif ($in->{cmd} eq "renew") {
    # membership renewal
    return $this->do_renew();
    }
    elsif ($in->{cmn} eq "photo") {
    # image uploads
    return "TODO: update photo";
    }
    elsif ($in->{cmd} eq "edit") {
    # bio/writeup
    return "TODO: update write-up";
    }
    elsif ($in->{cmd} eq "contact") {
    # contact info
    return "TODO: update contact info";
    }
    elsif ($in->{cmd} =~ /^renew/) {
    return $this->renew();
    }
    return $out;
}

# allow - test for permissions for various operations

sub allow_view {
    my ($this,$user) = @_;
    $user or $user = $share{DB}->my_user;    
    # user can always view their own profile
    return 1 if ($user && $user->id == $this->uid);
    # manager can always view profiles
    return 1 if ($share{DB}->is_manager);
    return $this->SUPER::allow_view($user);
}

sub allow {
    my ($this,$op,$user) = @_;
    $op or $op = "view";
    $user or $user = $share{DB}->my_user;
    if ($op eq "renew") {
    if ($this->SUPER::allow("edit",$user)) {
        # if user is allowed to update the profile, they are allowed 
        # to renew it; this should include both the profile owner
        # as well as admins
        my $date = $this->expiry_date;
        if ($date) {
        $date->add(-$config{Membership}{early_renewal_period},"days");
        if ($date->in_past) {
            return 1;
        }
        # else: renewals not allowed yet
        }
        else {
        # no expiry date!
        $this->warn("Profile ".$this->id." has no expiry date");
        }
    }
    # else: permission denied
    return 0;
    }
    else {
        if ($user && $user->id == $this->uid) {
            # allow user to view, update, edit their own profile
            if ($op eq "view" || $op eq "update" || $op eq "edit" || $op eq "conf") {
                return 1;
            }
        }
    return $this->SUPER::allow($op,$user);
    }
}

sub allow_post {
    my ($this) = @_;
    return ($this->{admin} ||
        ($share{Page} && $this->url_is_me() && $this->uid == $share{DB}->my_uid));
}

# search_index - minor mod to generic Content::search_index
# (ignore keywords, include description)

sub search_index {
    my ($this,$search) = @_;
    my $ml = &get_obj("ML");
    my $br = $ml->br;
    my $name = $this->subtype." ".$ml->em($this->name);
    my $stat = $this->can_index();
    return "$name already indexed - skipping...$br" if ($stat < 0);
    if (! $stat) {
    return "$name - permission denied$br" if (defined $stat);
    return undef;
    }

    my %content = (
    #name => $this->name, # usually just dupes the title
    title => $this->title,
    #keywords => $this->keywords(),
    description => $this->description(), # title, organization
    body => $this->get_html(), # bio
    );
    my %weight = (
    #name => 2,
    title => 10,
    #keywords => 2,
    description => 2,
    body => 1,
    );
    $search->index_url(
    content => \%content,
    weight => \%weight,
    language => $this->language(),
    url => $this->get_url_canonical(),
    access => $this->getdata("access"),
    section_id => $this->my_section->id,
    content_id => $this->id,
    type=>"Profile",
    );
    # $search->update() must be called by the caller
    return "indexed $name...$br\n";
}

#--------------------------------------------------------------------------
# Renewals

# note that applications are done via the Membership::Type class

sub renew {
    my ($this) = @_;
    my $ml = &get_obj("ML");
    my $out = $ml->h1($msg{"Renew Membership"});
    if ($this->allow("renew")) {
    # step 1: select membership type
    my $section = $this->my_section;
    my $tree = $this->get_content_tree();
    my @types = $tree->find({type=>$this->isubtype("membership_type")},$section->id);
    my @opt;
    foreach my $type (@types) {
        my $t = new Modules::Membership::Type(data=>$type);
        my $price = $t->price();
        my $cost = $price ? $share{DB}->show_data_noauth("price","cost",$price->{cost}) : $msg{"free"};
        if ($t->is_active) {
        push @opt, { 
            value=>$t->id, 
            text=>$t->label." ($cost)",
        };
        }
    }
    my $f = new ExSite::FormBuilder(method=>"get",action=>$this->link(__dynamic=>1));
    $f->input(type=>"hidden",name=>"cmd",value=>"renew");
    $f->input(type=>"select",name=>"type",prompt=>"Confirm membership type",options=>\@opt,value=>$this->membership_type->id,required=>1);
    $f->buttons(submit=>1);
    $out .= $f->make();
    }
    else {
    $out = $ml->p($msg{"Renewals are not being accepted at this time."});
    if ($this->is_active) {
        my $expdate = $this->expiry_date();
        if ($expdate) {
        $ml->p(&substitute($msg{"Your current membership is valid until [[date]]."},{date=>$expdate->write("date")}));
        }
    }
    }
    return $out;
}

sub do_renew {
    my ($this) = @_;
    my $out;
    my $ml = &get_obj("ML");
    my $ui = &get_obj("UI");
    if ($this->allow("renew")) {
    # add to cart
    my $type = new Modules::Membership::Type(id=>$this->{input}{type});
    if ($type->ok && 
        $type->subtype() eq "membership_type" && 
        $type->is_active) {
        if ($type->allow("apply")) {
        my $price = $type->price();
# should be done by the cart
#       &get_module("Finance"); # load maps, etc.
        my $cart = new Modules::Finance::Cart();
        $cart->add(
            item=>&substitute($msg{"Renew [[type]] membership"},{type=>$type->label}),
            description=>$this->title,
            cost=>$price->{cost},
            acctcode_id=>$config{Membership}{acctcode},
            acctcode2=>$type->id,
            acctcode3=>"2", # 1=application, 2=renewal
            uid=>$share{DB}->my_uid,
            objtype=>"content",
            objid=>$this->id,
            );
        $out .= $cart->show();
        }
        else {
        return "Sorry, renewals are not being accepted at this time.";
        }
    }
    else {
        return $this->error("invalid membership type");
    }
    }
    else {
    $out = $ml->p($msg{"Renewals are not being accepted at this time."});
    }
    return $out;
}

#--------------------------------------------------------------------------
# Profile UI

sub profile_contact {
    my $this = shift;
    my $out;
    my @contact = $this->contacts();
    foreach my $cdata (@{$this->contacts()}) {
    my $c = new Modules::ID::Contact(data=>$cdata);
    $out .= $c->show();
    }
    return $out;
}

sub edit_contact {    # process an edit contact form
    my $this = shift;
    my $stat = $this->run_handler("Membership_edit_contact");
    return $stat if ($stat);
    my $out;
    if (keys %{$this->{post}} > 0) {
        delete $this->{post}{form};
        delete $this->{post}{submit_action};
        my $c = new Modules::ID::Contact(id => $this->{post}{contact_id});
        my $errcnt = &AtError();
        $out .= $c->do_edit();
        if (!&AtError($errcnt)) {

            # no problems in update - redirect back to the edit_contacts page
            my $p = $share{Page} || $share{ML};
            if ($p) {
                $p->redirect($this->link(pro => "edit_contacts", __plaintext => 1));
            }
        } else {
            $out .= &ExSite::Config::show_diagnostics();
            my $ml = new ExSite::ML;
            $out .= $ml->p($ml->a("Try again", {href => $this->link(pro => "edit_contacts")}));
        }
    }
    return $out;
}

#sub delete {
#    my $this = shift;
#
#    ### TODO: does deletion imply any other data removal, eg. of the user?
#
#}

#--------------------------------------------------------------------------
# automated tasks

sub task {
    my $this = shift;
    $_ = shift; # this is the task command
    if (/expire/) {
    $this->wf_expire();
    }
    else {
    # publish, unpublish, archive
    $this->SUPER::task($_);
    }
}

#--------------------------------------------------------------------------
# Shopping cart callbacks

sub sale_delete {
    my ($this,$item) = @_;
    # purchase was deleted, 
    if ($this->wf_status() eq "draft") {
    # this was an application - throw it out
    $this->wf_reject(1);
    }
}

sub sale_activate {
    my ($this,$item) = @_;
    # invoice activated
    if ($this->wf_status() eq "draft") {
    # this is an application
    if ($config{Membership}{approval} ne "manual") {
        # applicants remain in draft until sale completed if manual approval is required
        $this->wf_submit(1);
    }
    }
}

sub sale_complete {
    my ($this,$item) = @_;
    # invoice paid
    if ($this->wf_status() =~ /^(draft|submitted)$/) {
    # application
    if ($config{Membership}{approval} eq "manual") {
        $this->wf_submit(1);
    }
    else {
        $this->wf_approve(1);
    }
    
    # attach account to user***
    my $acct = $item->receivable->account();
    $acct->setdata("uid",$this->uid);
    $acct->force_save();
    if (!$share{DB}->level) {
        $share{DB}->do_login($this->user->login);
    } else {
        delete $session{account};        
    }

    }
    else {
    # renewal
    $this->wf_approve(1);
    }
}

sub sale_note {
    my ($this,$item) = @_;
    my $inv = $item->receivable();
    if ($item->receivable->is_active() &&  # sale is closed
    $this->wf_istatus() < $this->wf_istatus("draft")) { # profile is submitted
    # include a link to what they bought
    my $ml = &get_obj("ML");
    return $ml->p($ml->a($msg{"View and manage your membership profile here."},{href=>$this->get_url_dynamic()}));
    }
    return undef;
}

#--------------------------------------------------------------------------
# workflow - update user privileges after profile status changes
#
# approve => raise to level 2
# expire, cancel => drop to level 1
# reject => drop to level 0

#active => published
#incomplete => draft
#pending => submitted
#expired => expired
#archived => canceled *

sub wf_approve {
    my ($this,$approve) = @_;
    $this->SUPER::wf_approve($approve);
    # activate user records
    foreach my $owner ($share{DB}->fetch_match("content_key",{content_id=>$this->id,role=>"owner",type=>"grant"})) {
    my $user = new ExSite::User(id=>$owner->{uid});
    if ($user->level < 2) {
        $user->setdata($config{auth}{user_access_column},2);
        $user->force_save();
    }
    }
}

sub wf_expire {
    my ($this,$approve) = @_;
    $this->SUPER::wf_expire($approve);
    # deactivate user records
    foreach my $owner ($share{DB}->fetch_match("content_key",{content_id=>$this->id,role=>"owner",type=>"grant"})) {
    if ($owner->{uid}) {
        my @profile = $share{DB}->get_query("user profiles",$owner->{uid});
        my %pstat = map { $_->{status} => $_ } @profile;
        if (! $pstat{0}) {
        # no active profiles left in the system
        my $user = new ExSite::User(id=>$owner->{uid});
        if ($user->level == 2) {
            $user->setdata($config{auth}{user_access_column},1);
            $user->force_save();
        }
        }
        # notify user?
    }
    }
}

sub wf_cancel {
    my ($this,$approve) = @_;
    $this->SUPER::wf_cancel($approve);
    # deactivate user records
    foreach my $owner ($share{DB}->fetch_match("content_key",{content_id=>$this->id,role=>"owner",type=>"grant"})) {
    if ($owner->{uid}) {
        my @profile = $share{DB}->get_query("user profiles",$owner->{uid});
        my %pstat = map { $_->{status} => $_ } @profile;
        if (! $pstat{0}) {
        # no active profiles left in the system
        my $user = new ExSite::User(id=>$owner->{uid});
        if ($user->level == 2) {
            $user->setdata($config{auth}{user_access_column},1);
            $user->force_save();
        }
        }
    }
    }
}

sub wf_reject {
    my ($this,$approve) = @_;
    $this->SUPER::wf_reject($approve);
    # deactivate user records
    foreach my $owner ($share{DB}->fetch_match("content_key",{content_id=>$this->id,role=>"owner",type=>"grant"})) {
    if ($owner->{uid}) {
        my @profile = $share{DB}->get_query("user profiles",$owner->{uid});
        my %pstat = map { $_->{status} => $_ } @profile;
        if (! $pstat{0}) {
        # no active profiles left in the system
        my $user = new ExSite::User(id=>$owner->{uid});
        if ($user->level) {
            $user->setdata($config{auth}{user_access_column},0);
            $user->force_save();
        }
        }
    }
    }
}

sub setup_querylib {
    my $this = shift;
    if (! exists $share{querylib}{"user profiles"}) {
    my $db = $share{DB};
    $db->set_query("user profiles",
               (
            sql => "select content.* from content,content_key,content_type where content.type=content_type.content_type_id and content_type.name='profile' and content.content_id=content_key.content_id and content_key.uid=? and content_key.type='grant' and content_key.role='owner'",
            nparam => 1,
            mode => "r",
            keys => ["content","content_key","content_type"],
               )
        );
    }
}

