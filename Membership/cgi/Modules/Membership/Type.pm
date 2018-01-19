#!/usr/bin/perl
#-----------------------------------------------------------------------
#
#   Copyright 2011 Exware Solutions, Inc.  http://www.exware.com
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

package Modules::Membership::Type;

use strict;
use ExSite::Config;
use ExSite::Content;
use ExSite::Misc;
use ExSite::Module qw(&get_module &read_conf);
use Modules::Membership::Profile;
use Modules::Membership::Directory;

use vars qw(@ISA);
@ISA = qw(Modules::Membership::Directory);

sub my_subtype { return "membership_type"; }

sub setup {
    my ($this,%opt) = @_;
    $this->setup_querylib();
    $this->SUPER::setup(%opt); # try generic setup
    # dependencies
    if (! exists $config{Membership}{_loaded}) {
	&read_conf("Membership"); 
    }
    return;
}

sub is_active {
    my $this = shift;
    return ! $this->wf_istatus(); # active if published
}

# i_am: test whether user has a profile of this type
# user - user object to test against; defaults to current user
# max_status - set this to ignore invalid profiles
#    0 - only active profiles
#    1 - active or archived profiles
#    6 - include all valid or prospective profiles, but not rejected/cancelled
# if max_status is not passed, any profile status will pass

sub i_am {
    my ($this,$user,$max_status) = @_;
    $user or $user = $share{DB}->my_user;
    if ($user && $user->id) {
	my %profile = map { $_->{parent} => $_ } $share{DB}->get_query("my profiles",$user->id);
	my $pro = $profile{$this->id};
	if ($pro) {
	    defined $max_status or $max_status=10;
	    return $pro->{status} <= $max_status ? $pro : 0;
	}
    }
    return undef;
}

# profile metadata definitions are of two types:
# content.metadata.profile.META... - general defs, applicable to all types
# content.metadata.TYPEID.profile.META... - defs applicable to one type
# metadefs returns the appropriate combination of the two

sub metadefs {
    my $this = shift;
    my %meta;
    foreach my $key (keys %{$config{content}{metadata}{profile}}) {
	$meta{$key} = $config{content}{metadata}{profile}{$key};
    }
    my $id = $this->id;
    if (exists $config{content}{metadata}{$id}) {
	foreach my $key (keys %{$config{content}{metadata}{$id}{profile}}) {
	    if ($config{content}{metadata}{$id}{profile}{$key}) {
		$meta{$key} = $config{content}{metadata}{$id}{profile}{$key};
	    }
	    else {
		# this subtype does not use this generic meta 
		delete $meta{$key};
	    }
	}
    }
    return \%meta;
}

# in this version, type-specific defs completely override generic defs
sub metadefs_old {
    my $this = shift;
    my $id = $this->id;
    if ($id && exists $config{content}{metadata}{$id}{profile}) {
	return $config{content}{metadata}{$id}{profile};
    }
    return $config{content}{metadata}{profile};
}

#=== DATES

# possible uses of dates
# - annual expiry date?
# - notification dates?

sub show {
    my ($this,%opt) = @_;
    my $out;
    my $ml = &get_obj("ML");
    # process any posts
    my $input = new ExSite::Input;
    my $in = $input->combine();
    if ($input->is_post()  &&
	$this->url_is_me() &&
	$this->allow_post()) {
	$out .= $this->post();
    }
    if ($this->allow()) {
	if (! $opt{readonly} && $this->allow("edit")) {
	    # check for tool use
	    $this->{input} = $in;
	    if ($in->{cmd} =~ /apply/) {
		return $this->apply();
	    }
	}
	$out .= $this->SUPER::show();
    }
    else {
	$out = "Permission denied.";
    }
    return $ml->div($out,{class=>"MembershipType"});
}

sub tools {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    my $apply_label = $config{Membership}{apply_label} || "Apply now";
    return $ml->div(
	$ml->a($msg{$apply_label},{href=>$this->link(cmd=>"apply"),class=>"MembershipApplyButton"}),
	{class=>"MembershipApply"}
	);
}

# index: membership directory for this type

sub index {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    my $out = $ml->h2("Directory");
    foreach my $p ($this->get_contents("profile")) {
	next if (! $p->is_viewable);
	$out .= $p->summary();
    }
    return $out;
}

# preview - like show, but for admins

sub preview {
    my ($this,%opt) = @_;
    $this->{admin} = 1;
    return $this->show(%opt);
}

sub post {
    my ($this,%opt) = @_;
    return $this->error($msg{"Sorry, membership applications are not being accepted at this time."}) if (! $this->allow_post);

    # get post data
    my $input = new ExSite::Input;
    my $post = $this->{post_data} = $input->post();
    my $in = $input->combine();

    my $out;
    if ($in->{cmd} =~ /apply/) {
	$out .= $this->do_application();
    }
    return $out;
}

sub report {
    my ($this,%opt) = @_;
    if ($this->defined()) {

	### report membership stats???

    }
    return undef;
}

sub apply {
    my ($this) = @_;
    my $out;
    my $ml = &get_obj("ML");
    my $ui = &get_obj("UI");
    &get_module("Membership"); # load configs
    if ($this->allow("apply")) {
	my $input = new ExSite::Input;
	my $post = $input->post();
	if (scalar keys %$post > 0) {
	    my $nfld;
	    my %application;
	    my $meta = $this->metadefs;
	    foreach my $fld ($this->application_fields) {
		$nfld;
		if ($this->{input}{$fld}) {
		    $nfld;
		    $application{$fld} = $this->{input}{$fld};
		}
		elsif ($meta->{$fld}{validate} eq "soft") {
		    # missing req'd field
		    my $label = $meta->{$fld}{label} || $fld;
		    return $this->error($msg{"You must provide a value for '$label'."});
		}
	    }
	    
	    if (scalar keys %application > 0) {
		my $title_template = $this->meta()->get("profile_title_template") ||
		    "[[first_name]] [[last_name]]";
		my $title = &substitute($title_template,\%application);

		my $profile = $this->new_content_obj(
		    title=>$title,
		    type=>$this->isubtype("profile"),
		    parent=>$this->id,
		    status=>$ExSite::Workflow::status{draft},
		    );

		if ($profile && $profile->id) {

		    ### add user & key
		    my $user = new ExSite::User;

		    my $price = $this->price();
		    &get_module("Finance"); # load maps, etc.
		    my $cart = new Modules::Finance::Cart();
		    $cart->add(
			item=>$msg{"Membership application"}." (".$this->label.")",
			description=>"for $title",
			cost=>$price->{cost},
			acctcode_id=>$config{Membership}{acctcode},
			acctcode2=>$this->id,
			acctcode3=>"1", # 1=application, 2=renewal
			uid=>$user->id,
			objtype=>"content",
			objid=>$profile->id,
			);
		    $out .= $cart->show();
		    return $out;
		}
		else {
		    return $this->error("Failed to initialize profile for $title.");
		}
	    }
	    # else: post is probably not for us
	}
	$out .= $this->application_form();
    }
    else {
	if ($this->{deny}) {
	    $out = $ml->p($msg{$this->{deny}});
	}
	else {
	    $out = $ml->p($msg{"Applications are not being accepted at this time."});
	}
	if ($this->is_active) {
	    my $expdate = $this->expiry_date();
	    if ($expdate) {
		$ml->p(&substitute($msg{"Your current membership is valid until [[date]]."},{date=>$expdate->write("date")}));
	    }
	}
    }
    return $out;
}

sub application_form {
    my ($this,%opt) = @_;
    my $out;
    my $ml = &get_obj("ML");
    $out .= $ml->h1("Membership Application").$ml->h2($this->title);
    my $price = $this->price();
    if ($price) {
	$out .= $this->show_price($price);
	my $f = $share{DB}->form(method=>"post");
	my $meta = $this->metadefs;
	foreach my $fld ($this->application_fields) {
	    my $prompt = $meta->{$fld}{label};
	    if (! $prompt) {
		$prompt = ucfirst $fld;
		$prompt =~ s/_/ /g;
	    }		    
	    $share{DB}->input_exsite(
		name=>$fld,
		prompt=>$prompt,
		datatype=>$meta->{$fld}{datatype} || "string",
		size=>$meta->{$fld}{size},
		required=>$meta->{$fld}{validate} eq "soft",  ## use required instead of validate??
		);
	}
	$f->buttons(submit=>$msg{"Submit application"});
	$out .= $f->make();
    }
    else {
	$out .= $ml->p($msg{"Applications are not being accepted at this time."});
    }
    return $out;
}

sub application_fields {
    my $this = shift;
    my $flds = $this->meta()->get("apply_fields");
    if ($flds) {
	return split /,\s*/, $flds;
    }
    else {
	return ("first_name", "last_name", "email");
    }
}

sub do_application {
    my ($this) = @_;
    my $out;
    my $ml = &get_obj("ML");
    my $ui = &get_obj("UI");
    if ($this->allow("apply")) {
	my $nfld;
	my %application;
	my $meta = $this->metadefs;
	foreach my $fld ($this->application_fields) {
	    $nfld;
	    if ($this->{input}{$fld}) {
		$nfld;
		$application{$fld} = $this->{input}{$fld};
	    }
	    elsif ($meta->{$fld}{validate} eq "soft") {
		# missing req'd field
		my $label = $meta->{$fld}{label} || $fld;
		return $this->error($msg{"You must provide a value for '$label'."});
	    }
	}
	    
	if (scalar keys %application > 0) {
	    my $title_template = $this->meta()->get("profile_title_template") ||
		"[[first_name]] [[last_name]]";
	    my $title = &substitute($title_template,\%application);
	    my $sortkey_template = $this->meta()->get("profile_sortkey_template") ||
		"[[last_name]] [[first_name]]";
	    my $sortkey = uc &substitute($title_template,\%application);
	    
	    my $profile = $this->new_content_obj(
		title=>$title,
		type=>$this->isubtype("profile"),
		parent=>$this->id,
		status=>$ExSite::Workflow::status{draft},
		sortkey=>$sortkey,
		);
	    
	    if ($profile && $profile->id) {
		
		### add user & key
		my $uid = $this->make_user($profile,\%application);

		my $price = $this->price();
		&get_module("Finance"); # load maps, etc.
		my $cart = new Modules::Finance::Cart();
		$cart->add(
		    item=>$msg{"Membership application"}." (".$this->label.")",
		    description=>"for $title",
		    cost=>$price->{cost},
		    acctcode_id=>$config{Membership}{acctcode},
		    acctcode2=>$this->id,
		    acctcode3=>"1", # 1=application, 2=renewal
		    uid=>$uid,
		    objtype=>"content",
		    objid=>$profile->id,
		    );
		$out .= $cart->show();
	    }
	    else {
		$out .= $this->error("Failed to initialize profile for $title.");
	    }
	}
    }
    return $out;
}

sub make_user {
    my ($this,$profile,$application) = @_;
    my $uid = $share{DB}->my_uid();
    if (! $uid) {
	my $user = {
	    login=>$application->{email}||$profile->label,
	    password=>&randtext(7,"ABCDEFGHJKLMNPQRSTUVWXYZ23456789!#-.?=\$"),
	    name=>$profile->title,
	    email=>$application->{email},
	    access=>0, ### increment on activation
	    section_id=>$profile->my_section()->id
	};
	do {
	    $uid = $share{DB}->adduser($user, {content_id=>$profile->id, type=>"grant", role=>"owner"});
	    if (! $uid) {
		my $errs = $share{DB}->{diagnostics}{error};
		if (ref $errs eq "ARRAY") {
		    my $err = $errs->[-1];
		    if ($err eq $msg{"Password is too weak.  Strengthen it with more text, numbers, upper-case, or punctuation characters."}) {
			$user->{password} .= &randtext(2,"ABCDEFGHJKLMNPQRSTUVWXYZ23456789!#-.?=\$");
		    }
		    elsif ($err eq "That $config{auth}{login_prompt} is already in use - please try another") {
			# dupe account !!!

			# FIXME: connect to existing user? or change login ID
			# and create account anyway?

			$this->error("Cannot make user for $application->{email}, as one already exists.");
			return 0;
		    }
		    else {
			# all other errors - just bail
			return 0;
		    }
		}
	    }
	} until $uid;

	# Q: when do we notify member of their login/password?

    }
    return $uid;
}

sub allow_post {
    my ($this) = @_;
    if ($this->url_is_me()) {
	# applications are allowed from anyone at the appropriate URL
	if ($this->has_prices) {
	    if ($this->price) {
		# there is a current active price
		return 1;
	    }
	    else {
		# there are prices, but none are valid
		$this->{deny} = "Applications are not being accepted at this time.";
	    }
	}
	else {
	    # no prices defined
	    $this->{deny} = "Applications are not being accepted in this category.";
	}
	return 0;
    }
    return undef;
}

sub allow {
    my ($this,$op,$user) = @_;
    $user or $user = $share{DB}->my_user;
    if ($op eq "apply") {
	if ($this->is_active) {
	    if ($user) {
		if ($this->i_am($user,6)) {
		    # user is already a member of this type
		    if ($config{Membership}{allow_dupe_types}{$this->name}) {
			return 1;
		    }
		    else {
			$this->{deny} = "You already have a membership of this type.";
		    }
		}
		else {
		    my @pro = $share{DB}->get_query("my profiles",$user->id);
		    if (scalar @pro > 0) {
			# user has membership in another type
			if ($config{Membership}{allow_multiple_memberships}) {
			    return 1;
			}
			else {
			    $this->{deny} = "You already have a membership of another type.";
			}
		    }
		    else {
			# user has no memberships
			return 1;
		    }
		}
	    }
	    else {
		return 1;  # public is allowed to apply
	    }
	}
	else {
	    # type is not accepting applications
	    $this->{deny} = "This membership type is not accepting applications.";
	    return 0;
	}
    }
    return $this->SUPER::allow($op,$user);
}

sub setup_querylib {
    my $this = shift;
    my $db = $share{DB};

    $db->set_query("my profiles",
		   sql=>"select c.* from content_key k,content c,content_type t where k.uid=? and c.type=t.content_type_id and t.name='profile' and c.content_id=k.content_id and k.role='owner'",
		   nparam=>1,
		   keys=>["content_key","content_type","content"]);

}

1;
