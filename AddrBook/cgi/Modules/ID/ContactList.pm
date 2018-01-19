#!/usr/bin/perl
#-----------------------------------------------------------------------
#
#   Copyright 2001-2010 Exware Solutions, Inc.  http://www.exware.com
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

package Modules::ID::ContactList;

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::ObjectList;

use vars qw(@ISA @column);
@ISA = qw(ExSite::ObjectList);
@column = qw(address city provstate country pcode phone cell fax email web);

sub my_type { "contact"; }

sub section_id {
    my $this = shift;
    my $s = $share{DB}->this_site();
    return $s ? $s->{section_id} : 0;
}

### TODO:
#
# select customers who bought a particular item
# select customers who bought from a particular account code
# select customers who made purchases in a time window
# select customers - accounts receivable
#
# merge dupe emails
# merge dupe addresses

sub remove_unsubscribed {
    my $this = shift;
    my @newlist;
    $this->reset();
    while (my $c = $this->next()) {
	if ($c->getdata("member_subscribe") =~ /n/i) {
	    # member-level unsubscribe - affects all contact records
	    next;
	}
	if ($c->getdata("subscribe") =~ /n/i) {
	    # contact-level unsubscribe
	    next;
	}
	push @newlist, $c->get();
    }
    $this->{list} = \@newlist;
}

sub remove_dupe_emails {
    my $this = shift;
    $this->reset();
    my %email;
    while (my $c = $this->next()) {
	my $em = $c->getdata("email");
	if ($em) {
	    if (exists $email{$em}) {
		push @{$email{$em}},$c->get();
	    }
	    else {
		$email{$em} = [$c->get()];
	    }
	}
    }
    my @newlist;
    foreach my $email (keys %email) {
	push @newlist, $this->best_of($email{$email});
    }
    $this->{list} = \@newlist;
}

sub remove_dupe_addresses {
    my $this = shift;
    $this->reset();
    my %addr;
    while (my $c = $this->next()) {
	my $data = $c->get();
	# convert addresses to simple text form to eliminate variances in
	# spacing, punctuation, capitalization
	my $addr = uc "$data->{address} $data->{city} $data->{provstate} $data->{pcode} $data->{country}";
	$addr =~ s/[^\w]//g;
	# would also be nice to detect minor spelling differences, 
	# abbreviations, etc...
	if (exists $addr{$addr}) {
	    push @{$addr{$addr}},$data;
	}
	else {
	    $addr{$addr} = [$data];
	}
    }
    my @newlist;
    foreach my $addr (keys %addr) {
	push @newlist, $this->best_of($addr{$addr});
    }
    $this->{list} = \@newlist;
}

sub best_of_account {
    my $this = shift;
    $this->reset();
    my %acct;
    my @newlist;
    while (my $c = $this->next()) {
	my $data = $c->get();
	if ($data->{account_id}) {
	    if (exists $acct{$data->{account_id}}) {
		push @{$acct{$data->{account_id}}},$data;
	    }
	    else {
		$acct{$data->{account_id}} = [$data];
	    }
	}
	else {
	    push @newlist, $data;
	}
    }
    foreach my $acct (keys %acct) {
	push @newlist, $this->best_of($acct{$acct});
    }
    $this->{list} = \@newlist;
}

sub best_of_content {
    my $this = shift;
    $this->reset();
    my %loc;
    my @newlist;
    while (my $c = $this->next()) {
	my $data = $c->get();
	if ($data->{content_id}) {
	    if (exists $loc{$data->{content_id}}) {
		push @{$loc{$data->{content_id}}},$data;
	    }
	    else {
		$loc{$data->{content_id}} = [$data];
	    }
	}
	else {
	    push @newlist, $data;
	}
    }
    foreach my $loc (keys %loc) {
	push @newlist, $this->best_of($loc{$loc});
    }
    $this->{list} = \@newlist;
}

# deprecated; use best_of_content instead
sub best_of_location {
    my $this = shift;
    $this->reset();
    my %loc;
    my @newlist;
    while (my $c = $this->next()) {
	my $data = $c->get();
	if ($data->{content_id}) {
	    if (exists $loc{$data->{content_id}}) {
		push @{$loc{$data->{content_id}}},$data;
	    }
	    else {
		$loc{$data->{content_id}} = [$data];
	    }
	}
	else {
	    push @newlist, $data;
	}
    }
    foreach my $loc (keys %loc) {
	push @newlist, $this->best_of($loc{$loc});
    }
    $this->{list} = \@newlist;
}

sub best_of {
    my ($this,$list,%opt) = @_;
    if (scalar @$list == 1) {
	return $list->[0];
    }

    # find the subset of the preferred type(s)
    my @plist;
    my $pref_type = $opt{type} || $config{contact}{preferred_type};
    if ($pref_type) {
	my @pref_type = (ref $pref_type eq "LIST") ?
	    @$pref_type : split /,/,$pref_type;

	my @type;
	if (scalar @pref_type > 0) {
	    for (my $i=0; $i < scalar @$list; $i++) {
		$type[$i] = $list->[$i]{type};
	    }
	    foreach my $ptype (@pref_type) {
		my $i = 0;
		foreach my $type (@type) {
		    if ($ptype eq $type) {
			push @plist, $list->[$i];
		    }
		    $i++;
		}
		last if (scalar @plist > 0);
	    }
	}
    }
    if (scalar @plist == 0) {
	@plist = ( @$list );
    }

    # find the card with the maximum number of defined fields
    my $nmax = 0;
    my $imax = 0;
    for (my $i=0; $i < scalar @plist; $i++) {
	my $count = 0;
	foreach my $key (keys %{$plist[$i]}) {
	    if ($plist[$i]{$key}) { 
		$count++; 
		if ($count > $nmax) { $nmax = $count; $imax = $i; }
	    }
	}
    }

    return $plist[$imax];
}

sub where {
    my ($this, $match) = @_;
    my (@wlist,@plist,$value);
    while (my ($key, $val) = each(%$match)) {
	# sanity check on keys
	if ($key !~ /^[\w\.]+$/) {
	    $this->error("invalid match column: $key");
	    return undef;
	}
	my $op = "=";
	if (ref $val) {
	    # values passed by reference are SQL literals
	    if ($$val =~ /^null$/i) { 
		$op = "IS"; 
	    }
	    $value = $$val;
	}
	elsif (! $val) {
	    next;
	}
	else {
	    # normal values are user data
	    if ($val =~ /%/) {
		if ($val =~ /(?<!\\)%/) {  # any occurence of % not preceeded by \
		    $op = "LIKE";
		}
		$val =~ s/\\%/%/g;
	    }
	    $value = "?";
	    push @plist, $val;
	}
	push @wlist, "$key $op $value";
    }
    return \@wlist,\@plist;
}

# fetch a contact_list record, and load its contacts

# You can daisy-chain contact lists together - they are simply concatenated.
# However, the list-trimming functions are a little more complicated in this
# case. Basically the rules for any sublist are inherited by the whole list.
# 
# For example, if you chain two lists, one that excludes unsubscribed records
# and one that doesn't, the joined list inherits the unsubscribe rule.

sub load_db {
    my ($this,$id) = @_;
    $this->{list} = [];
    $this->{unsubscribe} = undef;
    $this->{dupe} = undef;
    $this->{ctype} = undef;
    $this->add_db($id);
    if ($this->{unsubscribe} =~ /exclude/) {
	$this->remove_unsubscribed();
    }
    if ($this->{dupe} =~ /best/) {
	if ($this->{ctype} =~ /member|customer|registrant/) {
	    $this->best_of_account();
	}
	elsif ($this->{ctype} =~ /content/) {
	    $this->best_of_content();
	}
	elsif ($this->{ctype} =~ /location/) {
	    $this->best_of_location();
	}
	else {
	#if ($this->{ctype} =~ /other/) {
	    $this->remove_dupe_emails();
	    $this->remove_dupe_addresses();
	}
    }
}

sub add_db {
    my ($this,$id) = @_;
    my $out;

    # load the list parameters
    my $clist = new ExSite::Object("contact_list",$id);
    if (! $this->{clist_name}) { 
	$this->{clist_name} = $clist->name();
    }
    return if (! $clist->exists);
    my %in = &DecodeString($clist->getdata("parameters"));
    my $ctype = $clist->getdata("type");
    my $unsubscribe = $clist->getdata("unsubscribe");
    my $dupe = $clist->getdata("dupe");
    $this->{ctype} .= $ctype . " ";
    $this->{unsubscribe} .= $unsubscribe . " ";
    $this->{dupe} .= $dupe . " ";
    # load the contact data
    my %match = $this->match_hash($ctype,%in);
    my $method = $this->load_method("add",$ctype,\%match);
    eval { $this->$method(\%match); };
    if ($@) { $this->error("Cannot load contact list: $@"); }
    my $include = $clist->getdata("include");
    if ($include) {
	# daisy-chain another contact list to this one
	$this->add_db($include);
    }
}

sub match_hash {
    my ($this,$ctype,%in) = @_;
    my %match;
    if ($in{provstate} && $in{provstate} !~ /==/) {
	$match{provstate} = $in{provstate};
    }
    if ($in{country}) {
	$match{country} = $in{country};
    }
    if ($in{type}) {
	$match{"c.type"} = $in{type};
    }
    if ($ctype =~ /member/) {  # member, membership, membership_meta
	if ($in{usertype} || $in{status}) {
	    if ($in{usertype}) {
		$match{'member_type'} = $in{usertype};
	    }
	    if ($in{status}) {
		$match{status} = $in{status};
	    }
	}
    }
    elsif ($ctype eq "registrant") {
	my ($evt,$fee) = split /-/,$in{evtfee};
	$match{evt_id} = $evt;
	if ($fee) { $match{evt_fee_id} = $fee; }
	if ($in{status}) {
	    $match{'r.status'} = $in{status};
	}
    }
    elsif ($ctype eq "other") {
	if ($in{group}) {
	    $match{category} = $in{group};
	}
    }
    elsif ($ctype eq "custom") {
	$this->run_handler("custom_contact_list_match_hash",\%in,\%match);
    }
    return %match;
}

sub load_method {
    my ($this,$method,$ctype,$match) = @_;
    if ($ctype eq "membership") {
	$method .= "_membership";
    }
    elsif ($ctype eq "member") {
	if ($match->{member_type} || $match->{status}) {
	    $method .= "_membership";
	}
	elsif ($match->{group}) {
	    $method .= "_member_group";
	}
	else {
	    $method .= "_members";
	}
    }
    elsif ($ctype eq "customer") {
	$method .= "_customers";
    }
    elsif ($ctype eq "registrant") {
	$method .= "_registrants";
    }
    elsif ($ctype eq "content") {
	$method .= "_content";
    }
    elsif ($ctype eq "location") {
	$method .= "_locations";
    }
    elsif ($ctype eq "custom") {
	$method .= "_custom";
    }
    elsif ($ctype eq "other") {
	$method .= "_other";
    }
    return $method;
}

# add_meta : add some metadata to the contact records to help in managing 
# and displaying them
# _type = the contact type (member,memberhip,membership_meta,registrant,
#         customer,content,location,other)
# _alpha = an alphasort key for ordering contacts
# _name = best guess as to the contact's name

sub add_meta {
    my ($this,$type,$clist);
    foreach my $c (@$clist) {
	$c->{_type} = $type;
	if ($type =~ /member/) { 
	    my @membersort = (ref $config{auth}{user_sort_column} eq "ARRAY") ?
		@{$config{auth}{user_sort_column}} : ($config{auth}{user_sort_column});
	    my @membername = (ref $config{auth}{user_name_column} eq "ARRAY") ?
		@{$config{auth}{user_name_column}} : ($config{auth}{user_name_column});
	    foreach my $s (@membersort) {
		$c->{_alpha} .= uc $c->{$s} . " ";
	    }
	    foreach my $n (@membername) {
		$c->{_name} .= $c->{$n} . " ";
	    }
	}
	elsif ($type =~ /registrant/) {
	    $c->{_alpha} = uc($c->{last_name} . " " . $c->{first_name});
	    $c->{_name} .= $c->{first_name} . " " . $c->{last_name};
	}
	elsif ($type =~ /customer/) {
	    $c->{_alpha} = uc $c->{name};
	    $c->{_name} = $c->{name};
	}
	elsif ($type =~ /content/) {
	    $c->{_alpha} = uc $c->{title};
	    $c->{_name} = $c->{title};
	}
	elsif ($type =~ /location/) {
	    $c->{_alpha} = uc $c->{title};
	    $c->{_name} = $c->{title};
	}
	elsif ($type =~ /^custom$/) {
	    $this->run_handler("custom_contact_list_add_meta",$c);
	}
	elsif ($type =~ /other/) {
	    $c->{_alpha} = uc $c->{info};
	    $c->{_name} = $c->{info};
	}
    }
}

sub user_name_columns {
    my ($this,$prefix) = @_;
    my @name;
    my $user_name_col = $config{auth}{user_name_column};
    push @name, (ref $user_name_col eq "ARRAY") ? @$user_name_col : $user_name_col;
    my @sort = (ref $config{auth}{user_sort_column} eq "ARRAY") ?
	@{$config{auth}{user_sort_column}} : $config{auth}{user_sort_column};
    foreach my $col (@sort) {
	if (scalar (grep /^$col$/, @name) > 0) {
	    push @name, $col;
	}
    }
    return scalar @name > 0 ? "," . join(",", map { $prefix.$_ } @name) : "";
}

# members : simple attachment of members to their contact records

sub load_members {
    my ($this,$match) = @_;
    $this->{list} = $this->get_members($match);
    $this->add_meta("member",$this->{list});
}

sub add_members {
    my ($this,$match) = @_;
    my $list = $this->get_members($match);
    $this->add_meta("member",$list);
    push @{$this->{list}}, @$list;
}

sub get_members {
    my ($this,$match) = @_;
    my $namecols = $this->user_name_columns("m.");
    my $sql = "select a.name,m.login,m.password$namecols,c.* from contact c,account a,member m where ";
    my @wlist = ("c.account_id=a.account_id", 
		 "m.member_id=a.member_id",
		 "m.section_id=?");
    my @param = ($this->section_id);
    my ($xtra_w,$xtra_p) = $this->where($match);
    if (ref $xtra_w eq "ARRAY") {
	push @wlist, @$xtra_w;
    }
    $sql .= join(" and ",@wlist);
    if (ref $xtra_p eq "ARRAY") {
	push @param, @$xtra_p;
    }
    my @c = $share{DB}->custom_query($sql,@param);
    return wantarray ? @c : \@c;
}

# membership : also includes member_status, if that is installed

sub load_membership {
    my ($this,$match) = @_;
    $this->{list} = $this->get_membership($match);
    $this->add_meta("membership",$this->{list});
}

sub add_membership {
    my ($this,$match) = @_;
    my $list = $this->get_membership($match);
    $this->add_meta("membership",$list);
    push @{$this->{list}}, @$list;
}

sub get_membership {
    my ($this,$match) = @_;
    my $sql = "select a.name,m.type,m.first_name,m.last_name,m.login,m.password,m.subscribe member_subscribe,m.type member_type,c.*,(select status from member_status where member_status.member_id=m.member_id order by member_status_id desc limit 1) status from contact c,account a,member m where ";
    my @wlist = ("c.account_id=a.account_id", 
		 "m.member_id=a.member_id",
		 "m.section_id=?");
    my @param = ($this->section_id);
    my %having;
    if (exists $match->{status}) {
	$having{status} = $match->{status};
	delete $match->{status};
    }
    if (exists $match->{member_type}) {
	$having{member_type} = $match->{member_type};
	delete $match->{member_type};
    }
    my ($xtra_w,$xtra_p) = $this->where($match);
    if (ref $xtra_w eq "ARRAY") {
	push @wlist, @$xtra_w;
    }
    $sql .= join(" and ",@wlist);
    if (ref $xtra_p eq "ARRAY") {
	push @param, @$xtra_p;
    }
    if (scalar keys %having > 0) {
	my ($xtra_w,$xtra_p) = $this->where(\%having);
	if (ref $xtra_w eq "ARRAY") {
	    $sql .= " having ".join(" and ",@$xtra_w);
	    push @param, @$xtra_p;
	}
    }
    my @c = $share{DB}->custom_query($sql,@param);
    return wantarray ? @c : \@c;
}

# membership_meta : same as above, but also allows filtering on one 
# meta data column

sub load_membership_meta {
    my ($this,$match) = @_;
    $this->{list} = $this->get_membership_meta($match);
    $this->add_meta("membership_meta",$this->{list});
}

sub add_membership_meta {
    my ($this,$match) = @_;
    my $list = $this->get_membership_meta($match);
    $this->add_meta("membership_meta",$list);
    push @{$this->{list}}, @$list;
}

sub get_membership_meta {
    my ($this,$match) = @_;
    my $sql = "select a.name,m.type,m.first_name,m.last_name,m.login,m.password,att.value meta,c.*,(select status from member_status where member_status.member_id=m.member_id order by member_status_id desc limit 1) status from contact c,account a,member m,member_attribute att where ";
    my @wlist = ("c.account_id=a.account_id", 
		 "m.member_id=a.member_id",
		 "a.member_id=m.member_id",
		 "m.section_id=?");
    my @param = ($this->section_id);
    my $status;
    if (exists $match->{status}) {
	$status = $match->{status};
	delete $match->{status};
    }
    foreach my $key (keys %$match) {
	if ($key =~ /^meta_/) {
	    my $metaname = $key;
	    $metaname =~ s/^meta_//;
	    push @wlist, "att.name=?";
	    push @param, $metaname;
	    last;  # only one meta column
	}
    }
    my ($xtra_w,$xtra_p) = $this->where($match);
    if (ref $xtra_w eq "ARRAY") {
	push @wlist, @$xtra_w;
    }
    $sql .= join(" and ",@wlist);
    if (ref $xtra_p eq "ARRAY") {
	push @param, @$xtra_p;
    }
    if ($status) {
	$sql .= " having status ?";
	push @param, $status;
    }
    my @c = $share{DB}->custom_query($sql,@param);
    return wantarray ? @c : \@c;
}

# member_groups : members joined into groups and committees

sub load_member_group {
    my ($this,$match) = @_;
    $this->{list} = $this->get_member_group($match);
    $this->add_meta("member_group",$this->{list});
}

sub add_member_group {
    my ($this,$match) = @_;
    my $list = $this->get_member_group($match);
    $this->add_meta("member_group",$list);
    push @{$this->{list}}, @$list;
}

sub get_member_group {
    my ($this,$match) = @_;
    my $group_id;
    if ($match->{member_group_id}) {
	$group_id = $match->{member_group_id};
	delete $match->{evt_id};
    }
    else {
	$this->error("Cannot build a member group contact list without a group ID.");
	return ();
    }
    my $namecols = $this->user_name_columns("m.");
    my $sql = "select a.name,m.login,m.password$namecols,c.*,g.name groupname from contact c,account a,member m,member_group g where ";
    my @wlist = ("c.account_id=a.account_id",
		 "m.member_id=a.member_id",
		 "g.member_id=m.member_id",
		 "g.member_group_id=?",
		 "m.section_id=?");
    my @param = ($group_id, $this->section_id);
    my ($xtra_w,$xtra_p) = $this->where($match);
    if (ref $xtra_w eq "ARRAY") {
	push @wlist, @$xtra_w;
    }
    $sql .= join(" and ",@wlist);
    if (ref $xtra_p eq "ARRAY") {
	push @param, @$xtra_p;
    }
    my @c = $share{DB}->custom_query($sql,@param);
    return wantarray ? @c : \@c;
}

# registrants : contact records that can be tied to an evt_reg record

sub load_registrants {
    my ($this,$match) = @_;
    $this->{list} = $this->get_registrants($match);
    $this->add_meta("registrant",$this->{list});
}

sub add_registrants {
    my ($this,$match) = @_;
    my $list = $this->get_registrants($match);
    $this->add_meta("registrant",$list);
    push @{$this->{list}}, @$list;
}

sub get_registrants {
    my ($this,$match) = @_;
    my ($evt_id,$fee_id);
    if ($match->{evt_id}) {
	$evt_id = $match->{evt_id};
	delete $match->{evt_id};
    }
    else {
	$this->error("Cannot build a registrant contact list without an event ID.");
	return ();
    }
    if ($match->{evt_fee_id}) {
	$fee_id = $match->{evt_fee_id};
	delete $match->{evt_fee_id};
    }

    # add main registrant

    my $sql = "select r.first_name,r.last_name,a.name name, c.* from contact c, account a, evt_reg r, evt_fee f where ";
    my @wlist = ("c.account_id=a.account_id",
		 "r.account_id=a.account_id",
		 "r.evt_fee_id=f.evt_fee_id",
		 "f.evt_id=?");
    my @param = ($evt_id);
    if ($fee_id) {
	push @wlist, "(f.evt_fee_id=? or f.treat_as=?)";
	push @param, $fee_id, $fee_id;
    }
    my ($xtra_w,$xtra_p) = $this->where($match);
    if (ref $xtra_w eq "ARRAY") {
	push @wlist, @$xtra_w;
    }
    $sql .= join(" and ",@wlist);
    if (ref $xtra_p eq "ARRAY") {
	push @param, @$xtra_p;
    }
    my @c = $share{DB}->custom_query($sql,@param);

    # add guest registrants

    $sql = "select r.first_name,r.last_name,a.name name, c.* from contact c, account a, evt_reg r, evt_fee f where ";
    @wlist = ("c.account_id=a.account_id",
	      "r.guest_account_id=a.account_id",
	      "r.evt_fee_id=f.evt_fee_id",
	      "f.evt_id=?");
    @param = ($evt_id);
    if ($fee_id) {
	push @wlist, "(f.evt_fee_id=? or f.treat_as=?)";
	push @param, $fee_id, $fee_id;
    }
    ($xtra_w,$xtra_p) = $this->where($match);
    if (ref $xtra_w eq "ARRAY") {
	push @wlist, @$xtra_w;
    }
    $sql .= join(" and ",@wlist);
    if (ref $xtra_p eq "ARRAY") {
	push @param, @$xtra_p;
    }
    push @c, $share{DB}->custom_query($sql,@param);

    return wantarray ? @c : \@c;
}

# customers : have accounts, but no member record

sub load_customers {
    my ($this,$match) = @_;
    $this->{list} = $this->get_customers($match);
    $this->add_meta("customer",$this->{list});
}

sub add_customers {
    my ($this,$match) = @_;
    my $list = $this->get_customers($match);
    $this->add_meta("customer",$list);
    push @{$this->{list}}, @$list;
}

sub get_customers {
    my ($this,$match) = @_;
    my $sql = "select distinct a.name,c.* from contact c,receivable r,account a left join member m on m.member_id=a.member_id where ";
    my @wlist = ("c.account_id=a.account_id",
		 "r.account_id=a.account_id",
		 "r.status='active'",
		 "(a.section_id=? or m.section_id=?)");
    my $sid = $this->section_id;
    my @param = ($sid,$sid);
    my ($xtra_w,$xtra_p) = $this->where($match);
    if (ref $xtra_w eq "ARRAY") {
	push @wlist, @$xtra_w;
    }
    $sql .= join(" and ",@wlist);
    if (ref $xtra_p eq "ARRAY") {
	push @param, @$xtra_p;
    }
    my @c = $share{DB}->custom_query($sql,@param);
    return wantarray ? @c : \@c;
}

# content : contact records tied directly to a content record

sub load_content {
    my ($this,$match) = @_;
    $this->{list} = $this->get_content($match);
    $this->add_meta("content",$this->{list});
}

sub add_content {
    my ($this,$match) = @_;
    my $list = $this->get_content($match);
    $this->add_meta("location",$list);
    push @{$this->{list}}, @$list;
}

#### use content tree search instead??

sub get_content {
    my ($this,$match) = @_;
    my $sql = "select l.content_id,l.title,c.* from contact c,content l where ";
    my @wlist = ("c.content_id=l.content_id");
    my @param = ();
    my ($xtra_w,$xtra_p) = $this->where($match);
    if (ref $xtra_w eq "ARRAY") {
	push @wlist, @$xtra_w;
    }
    $sql .= join(" and ",@wlist);
    if (ref $xtra_p eq "ARRAY") {
	push @param, @$xtra_p;
    }
    my @c = $share{DB}->custom_query($sql,@param);
    # query will find all locations in DB - now must filter them
    my @allowed;
    foreach my $c (@c) {
	# accept content if we have a key/role in managing it
	my $l = new ExSite::Content(data=>$c);
	push @allowed, $c if ($l->has_role());
    }
    return wantarray ? @allowed : \@allowed;
}

# locations : contact records tied directly to a location record

sub load_locations {
    my ($this,$match) = @_;
    $this->{list} = $this->get_locations($match);
    $this->add_meta("location",$this->{list});
}

sub add_locations {
    my ($this,$match) = @_;
    my $list = $this->get_locations($match);
    $this->add_meta("location",$list);
    push @{$this->{list}}, @$list;
}

sub get_locations {
    my ($this,$match) = @_;
    my $sql = "select l.content_id,l.title,c.* from contact c,content l,content_type t where ";
    my @wlist = ("c.content_id=l.content_id",
		 "l.type=t.content_type_id",
		 "t.name='location'");
    my @param = ();
    my ($xtra_w,$xtra_p) = $this->where($match);
    if (ref $xtra_w eq "ARRAY") {
	push @wlist, @$xtra_w;
    }
    $sql .= join(" and ",@wlist);
    if (ref $xtra_p eq "ARRAY") {
	push @param, @$xtra_p;
    }
    my @c = $share{DB}->custom_query($sql,@param);
    # query will find all locations in DB - now must filter them
    my @allowed;
    foreach my $c (@c) {
	# accept location if we have a key/role in managing it
	my $l = new Modules::Location::Location(data=>$c);
	push @allowed, $c if ($l->has_role());
    }
    return wantarray ? @allowed : \@allowed;
}

# custom : custom rules - must be installed via handlers

sub load_custom {
    my ($this,$match) = @_;
    $this->{list} = $this->get_custom($match);
    $this->add_meta("custom",$this->{list});
}

sub add_custom {
    my ($this,$match) = @_;
    my $list = $this->get_custom($match);
    $this->add_meta("custom",$list);
    push @{$this->{list}}, @$list;
}

sub get_custom {
    my ($this,$match) = @_;
    my $list = $this->run_handler("get_custom_contact_list",$match);
    if (defined $list) {
	return wantarray ?  @$list : $list;
    }
    return undef;
}

# other : contact records not matching any of the above

sub load_other {
    my ($this,$match) = @_;
    $this->{list} = $this->get_other($match);
    $this->add_meta("other",$this->{list});
}

sub add_other {
    my ($this,$match) = @_;
    my $list = $this->get_other($match);
    $this->add_meta("other",$list);
    push @{$this->{list}}, @$list;
}

sub get_other {
    my ($this,$match) = @_;
    my $sql = "select c.* from contact c where ";
    my @wlist = ("account_id=0", "content_id=0");
    my @param = ($this->section_id);
    my ($xtra_w,$xtra_p) = $this->where($match);
    if (ref $xtra_w eq "ARRAY") {
	push @wlist, @$xtra_w;
    }
    $sql .= join(" and ",@wlist);
    if (ref $xtra_p eq "ARRAY") {
	push @param, @$xtra_p;
    }
    my @c = $share{DB}->custom_query($sql,@param);
    return wantarray ? @c : \@c;
}

# display/export the contact list

sub show {
    my ($this,%opt) = @_;
    my $out;
    my $ml = &get_obj("ML");
    $this->sort("_alpha");
    if ($opt{style} =~ /card/) {
	
	$this->reset;
	my $ncard = 0;
	while (my $card = $this->next()) {
	    my $cardout = $ml->strong($card->contact_name).$ml->br.$card->show;
	    $out .= $ml->div($cardout,{class=>"AddrCard"});
	    $ncard++;
	    if ($opt{limit} && $ncard > $opt{limit}) {
		### pagination
		last;
	    }
	}
    }
    else {
	$out .= $this->report(%opt);
    }
    return $out;
}

sub report {
    my ($this,%opt) = @_;
    my $out;
    my $ml = &get_obj("ML");
    my $url = $opt{url};
    my $r = new ExSite::ReportBuilder(
				      title=>$opt{title} || $this->{clist_name},
				      nodata=>"No contacts found.",
				      dynamic=>1,
				      );
    $r->headers("Name","Address","City","Prov/State","Country","Postal Code","Phone","Cell","Fax","E-mail","Web");
    $this->reset;
    if ($opt{tools}) {
	$r->tools($opt{tools});
    }
    while (my $contact = $this->next()) {
	my $data = $contact->meta->get_all();
	my $phone = $contact->showdata("phone1") . " " . $contact->showdata("phone2");
	my $cname = $contact->showdata("name") || $contact->contact_name || "(NO NAME)";
	if ($url && ! $opt{export}) {
	    $url->query(contact_id=>$contact->id);
	    $cname = $ml->a($cname,{href=>$url->write()});
	}
	$r->push($cname,
		 $data->{address},
		 $data->{city},
		 $data->{provstate},
		 $data->{country},
		 $data->{pcode},
		 $data->{phone},
		 $data->{cell},
		 $data->{fax},
		 $data->{email},
		 $data->{web},
	    );
    }
    if ($opt{export} eq "csv") {
	$ml->cancel;
	print "Content-type: text/comma-separated-values\n\n";
	print $r->export("csv");
	return undef;
    }
    elsif ($opt{export} eq "xls") {
	$ml->cancel;
	print "Content-type: application/vnd.ms-excel\ncontent-disposition: attachment; filename=contacts.xls\n\n";
	$r->export("excel");
	return undef;
    }
    else {
	if ($opt{url}) {
	    $opt{url}->query(contact_id=>undef,export=>"csv");
	    my $csvlink = $opt{url}->write;
	    $opt{url}->query(export=>"xls");
	    my $xlslink = $opt{url}->write;
	    my $foot = "Export: ".
		$ml->a("CSV",{href=>$csvlink}) . " &bull; " .
		$ml->a("Excel",{href=>$xlslink});
	    $r->foot($foot);
	}
	return $r->make();
    }
}

1;

