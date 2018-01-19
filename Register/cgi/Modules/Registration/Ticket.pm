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

package Modules::Registration::Ticket;

### TODO: get receivable_item tied to this claim

use strict;
use ExSite::Config;
use ExSite::Base;
use ExSite::Form;
use ExSite::Misc;
use ExSite::Object;
use ExSite::Base;
use Modules::Registration::Fee;

use vars qw(@ISA %status_msg);
@ISA = qw(ExSite::Object);

%status_msg = (
    confirmed => "sold",
    reserved => "reserved",
    waitlist => "on waitlist",
    held => "temporary hold",
    canceled => "available",
    active => "available",
    inactive => "not available yet"
    );

sub my_type { return "ticket"; }

sub name {
    my $this = shift;
    my $fee = $this->fee;
    my $type = "Registration";
    if ($fee) {
	if ($fee && $fee->is_ticketed) {
	    $type = "Ticket";
	}
    }
    return $msg{$type}." ".$this->id;
}

sub load {
    my $this = shift;
    if ($this->SUPER::load()) {
	$this->load_children();
    }
    return $this->{data};
}

# relations

sub fee {
    my ($this,%opt) = @_;
    if (! $this->{fee}) {
	if ($this->exists()) {
	    my $c = new ExSite::Content;
	    $this->{fee} = $c->get_content_obj($this->getdata("content_id"));
	    #### is this needed still?
	    $this->{fee}->set("url", $opt{url});
	}
    }
    return $this->{fee};
}

sub event {
    my $this = shift;
    if (! $this->{event}) {
	if ($this->defined()) {
	    my $fee = $this->fee();
	    if ($fee) {
		$this->{event} = $fee->event();
	    }
	}
    }
    return $this->{event};
}

# claim: who is holding this ticket?

sub get_claim {
    my $this = shift;
    if (! $this->{claim}) {
	if ($this->loaded) {
	    my $claims = $this->get_child("ticket_claim");
	    if ($claims->count > 0) {
		$claims->sort("ticket_claim_id");
		$this->{claim} = $claims->last;
	    }
	}
    }
    return $this->{claim};
}

sub claim_name {
    my ($this,$claim) = @_;
    $claim or $claim = $this->get_claim;
    if ($claim && $claim->defined) {
	my $fname = $claim->showdata("first_name");
	my $lname = $claim->showdata("last_name");
	return wantarray ?
	    ($fname, $lname) :
	    ($fname ? "$fname $lname" : $lname);
    }
    return undef;
}

# the unique claim name includes a dupekey in case of duplicate registrant names
sub unique_claim_name {
    my ($this,$claim) = @_;
    $claim or $claim = $this->get_claim;
    my $name = $this->claim_name($claim);
    if ($name) {
	my $dupekey = $claim->getdata("dupekey");
	return $dupekey ? "$name #$dupekey" : $name;
    }
    return undef;
}

sub parent {
    my $this = shift;
    my $pticket;
    if ($this->loaded) {
	my $claim = $this->get_claim();
	if ($claim) {
	    my $claim_parent = $claim->getdata("parent");
	    if ($claim_parent) {
		my $pclaim = $share{DB}->fetch("ticket_claim",$claim_parent);
		if ($pclaim) {
		    $pticket = $pclaim->{ticket_id};
		}
	    }
	}
    }
    return new Modules::Registration::Ticket(id=>$pticket);
}

sub response {
    my $this = shift;
    my $response_id;
    if ($this->loaded) {
	my $claim = $this->get_claim();
	if ($claim) {
	    $response_id = $claim->getdata("reponse_id");
	}
    }
    return new Modules::Forms::Response(id=>$response_id);
}

# status: combined status of claim then ticket
# if claim exists and has a status, return that status; otherwise 
# return ticket status

sub status {
    my $this = shift;
    if ($this->exists) {
	my $claim = $this->get_claim;
	return $claim ?
	    $claim->getdata("status") :  # confirmed, reserved, waitlist, held, canceled
	    $this->getdata("status");    # active, inactive
    }
}

sub status_message {
    my $this = shift;
    return $status_msg{$this->status} || "n/a";
}

sub is_available {
    my $this = shift;
    return $this->status_message() eq "available";
}


# is_mine: check if ticket belongs to current user
sub is_mine {
    my $this = shift;
    my $claim = $this->get_claim();
    my $acctid = $claim->getdata("account_id");
    # does it match currently active account?
    return 1 if ($acctid == $session{account});
    # is it in the current registration session?
    if ($session{registrations}) {
	foreach my $tic (@{$session{registrations}}) {
	    return 1 if ($tic->{ticket_id} == $this->id);
	}
    }
    # does it match user's account?
    my $acct = $share{DB}->fetch("account",$acctid);
    if ($acct) {
	return ($acct->{uid} == $share{DB}->my_uid);
    }
    # no match
    return 0;
}

# claim status change

sub set_claim_status {
    my ($this,$status) = @_;
    my $claim = $this->get_claim();
    if ($claim && $claim->defined) {
	$claim->setdata("status",$status);
	return $claim->save();
    }
    return undef;
}

# account - returns the account that best represents the registrant
# NB: this may not be the same as the account of the buyer, if a guest
# account was set up to hold the registrant's contact info.

sub account {
    my $this = shift;
    my $account_id;
    if ($this->defined) {
	my $claim = $this->get_claim();
	if ($claim) {

### do we need to look at parent ticket ??

	    $account_id = $claim->{guest_account_id} || $claim->{account_id};
	}
    }
    return new Modules::Finance::Account(id=>$account_id);
}

# invoice: return the invoice ID that was used to purchase this ticket
# 0 => no invoice, perhaps an instant registration
# undef => no account or registration defined

sub invoice {
    my $this = shift;
    if ($this->defined) {
	my $acct = $this->getdata("account_id");
	if ($acct) {
	    my @reg = $share{DB}->get_query("registration invoice",$acct,$this->id);
	    if (@reg > 0) {
		return $reg[0]{receivable_id};
	    }
	    return 0;
	}
    }
    return undef;
}

sub email {
    my $this = shift;
    my $email;
    # check account first
    my $acct = $this->account;
    if ($acct) {
	$email = $acct->email;
    }
    if (! $email) {
	# nothing; check the response
	my $r = $this->response;
	if ($r) {
	    $email = $r->get_response_data()->{email};
	}
    }
    return $email;
}

#=== RELATIONS

# batch : all tickets of the batch, as an ObjectList
# A ticket batch is a collection of tickets related through the claim parent.
# This is typically a ticket bundle for one person to attend multiple
# activities in one event.

sub batch {
    my $this = shift;
    my $batch = new ExSite::ObjectList(type=>"ticket");
    my $maintic = $this->main_ticket;
    if ($maintic->defined) {
	$this->batch_add($batch,$maintic);
    }
    elsif ($this->defined) {
	$batch->push($this->get());
    }
    return $batch;
}

sub batch_add {
    my ($this,$batch,$tic) = @_;
    if ($tic && $tic->defined) {
	$batch->push($tic->get());
	# get all subtix
	my $claim = $tic->get_claim();
	my @subclaim = $share{DB}->fetch_match("ticket_claim",{parent_id=>$claim->{ticket_claim_id}},"ticket_claim_id");
	foreach my $claim (@subclaim) {
	    my $subtic = new Modules::Registration::Ticket(data=>$claim);
	    $this->batch_add($batch,$subtic);
	}
    }
}

# main_ticket : root ticket of batch

sub main_ticket {
    my $this = shift;
    my $main = $this;
    while ($this->parent->defined) {
	$main = $this->parent;
    }
    return $main;
}

#=== DISPLAY

sub show {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");

    # Ticket format is:
    # +--------------+--------------+
    # | ticket info  | fee info     |
    # +--------------+--------------+
    # | registrant   | QR code      |
    # +--------------+--------------+
    # | event info   | venue info   |
    # +--------------+--------------+

    my $id = $this->id;
    my $ticketno = $id < 10000 ? sprintf("%04d",$id) : $id;
    my $ticketinfo = $this->getdata("info");

    my $feeinfo = $this->fee->title;
    
    my $registrant = $this->claim_name;

    my $evt = $this->event;
    my $eventinfo =
	$ml->div($evt->title,{class=>"eventTitle"}).
	$ml->div($evt->show_date_range,{class=>"eventDate"});
    my $venue = $this->event->venue();
    my $venueinfo;
    if ($venue && $venue->defined) { 
	$venueinfo = $venue->summary();
#	$venueinfo = $ml->div($venue->title,{class=>"venueTitle"});
#	my $contacts = $venue->contacts();
#	if ($contacts->count) {
#	    $venueinfo .= $ml->div($contacts->first->show_address(),{class=>"venueAddress"});
#	}
    }
    my $claim = $this->get_claim;
    my $status = $this->status_message();
    if ($status eq "sold") { 
	$status = undef;
    }
    elsif ($status eq "available") {
	$status = $claim->getdata("status") eq "canceled" ? "canceled" : "unsold";
    }
    my $statusinfo;
    if ($status) {
	$statusinfo = $ml->div($status,{class=>"ticketStatus"});
    }

    my $out = 
	$ml->div(
	    $ml->div(
		"Ticket #".$ml->span($ticketno,{class=>"ticketNumber"}).
		$ticketinfo,
		{class=>"ticketInfo"}
	    ).
	    $ml->div($feeinfo,{class=>"feeInfo"}),
	    {class=>"ticketHead"}
	).
	    $ml->div(
		$ml->div(undef,{id=>"qrcode"}).
		$ml->div($registrant,{class=>"ticketName"}).
		$ml->div($eventinfo,{class=>"ticketEvent"}).
		$ml->div($venueinfo,{id=>"ticketVenue"}).
		$statusinfo,
	    {class=>"ticketBody"}
	    );

    # ticket bar code
    my @qrdata = $id, $registrant;
    if ($ticketinfo) { push @qrdata, $ticketinfo; }
    my $qrdata = join ",",@qrdata;
    $out .= &ExSite::Config::insert_js("jquery");
    $out .= &ExSite::Config::insert_js("jquery.qrcode.min.js");
    ## need some css
    $out .= $ml->script("\njQuery('#qrcode').qrcode('$qrdata');\n");
    return $ml->div($out,{class=>"Ticket"});
}

sub make_claim {
    my ($this,$claim) = @_;  # claim is an object or datahash
    my $errcnt = &AtError();
    if ($this->status_message eq "available") {
	my $claimdata;
	if (ref $claim =~ /Object/) {
	    $claimdata = $claim->get();
	}
	else {
	    $claimdata = $claim;
	    $claim = new ExSite::Object(type=>"ticket_claim",data=>$claimdata);
	}
	$claim->setdata("ticket_id", $this->id);
	$claimdata->{status} or $claim->setdata("status", "held");
	$claim->setdata("ticket_claim_id",undef);
	my @err = $claim->validate();
	if (@err == 0) {
	    if ($claim->insert()) {
		$this->{claim} = $claim;
	    }
	}
	else {
	    $claim->error(@err);
	}
    }
    return &AtError($errcnt) ? 0 : 1; # 1 is success
}

sub cancel {
    my $this = shift;
    my $claim = $this->get_claim();
    if ($claim && $claim->defined) {
	$claim->setdata("status","canceled");
	return $claim->save();

	### delete from cart?
	
    }
    return undef;
}

sub confirm {
    my $this = shift;
    my $claim = $this->get_claim();
    if ($claim && $claim->defined) {
	$claim->setdata("status","confirmed");
	return $claim->save();
    }
    return undef;
}

# release cancels a held ticket

sub release {
    my $this = shift;
    my $claim = $this->get_claim();
    if ($claim->getdata("status") eq "held") {
	$claim->setdata("status","canceled");
	if ($claim->force_save()) {
	    
	    ### delete from cart?
	
	    return 1; # ticket released
	}
    }
    return 0; # nothign done
}

# make_guest_account - create an account and contact records for a guest
# registrant.
#
# This is not for billing purposes, but for contact management purposes.
# For instance if Joe registers himself and Mary for an event, Joe's contact
# info will by stored in his own account, because he made the purchase. Mary's
# contact info will not be stored in a contact record, unless we create a
# guest account for her. This account holds no financial data, only her contact
# data.

sub make_guest_account {
    my ($this,$section_id) = @_;
    my $status = $this->run_handler("Registration_make_guest_account",$section_id);
    return $status if (defined $status);
    return $this->make_account($section_id,"guest_account_id");
}

sub make_account {
    my ($this,$section_id,$acctcol) = @_;
    my $status = $this->run_handler("Registration_make_account",$section_id,$acctcol);
    return $status if (defined $status);

    # can setup regular or guest accounts
    $acctcol or $acctcol = "account_id";
    
    # make a contact record from the response data
    my %contact = $this->get_contact_info_from_response();

    # check to see if this is the purchaser
    my $acct = new Modules::Finance::Account(id=>$this->getdata("account_id"));
    my ($name,$first_name,$last_name);
    my $threshold = $config{EvtReg}{compare_threshold} || 0.5;
    if ($acct->loaded()) {
	$name = $acct->name();
	my $user = $share{DB}->my_user_record();
	$first_name = $user->{first_name};
	$last_name = $user->{last_name};
	my $contacts = $acct->get_contacts();
	my $ndiff = 0;
	while (my $c = $contacts->next) {
	    my %cdata = %{$c->get()};
	    # add name fields
	    $cdata{name} = $name;
	    $cdata{first_name} = $first_name;
	    $cdata{last_name} = $last_name;
	    # abort if this is a close match to the current account
	    return undef if (&ExSite::Misc::compare(\%cdata,\%contact) > $threshold);
	}
    }

    # %contact does not match any of the contact records on this account

    my $new_name = $contact{last_name} ? "$contact{last_name}, $contact{first_name}" : $contact{name};
    my $old_name = $last_name ? "$last_name, $first_name" : $last_name;
    if (&ExSite::Misc::compare($new_name,$old_name) < $threshold) {
	# names are very different - create a separate account
	$acct = new Modules::Finance::Account();
    }
    my $name = $contact{last_name} ? 
	"$contact{last_name}, $contact{first_name}" : 
	$contact{name};
    if (! $name) {
	# urk - no account name; make something up
	$name = $contact{email} || $contact{web} || "Registrant";
    }

    my $acct_id;
    if ($share{guest_account}{$name}) {
	$acct_id = $share{guest_account}{$name};
    }
    else {
	if (! $acct->getdata("name")) {
	    $acct->setdata("name",$name);
	}
	if (! $acct->getdata("section_id") && ! $acct->getdata("member_id")) {
	    $acct->setdata("section_id",$section_id);
	}
	$acct->force_save();
	$acct_id = $acct->id;
    }
    $this->setdata($acctcol,$acct_id);
    $this->force_save;
    $this->add_contact(\%contact,$acct_id);
    return $acct_id;
}

sub add_contact {
    my ($this,$contact,$acct_id) = @_;
    delete $contact->{name};
    delete $contact->{first_name};
    delete $contact->{last_name};
    # now we have a clean contact record; add some meta data
    $contact->{category} = "registrants";
    my $fee = $this->fee;
    my $evt = $this->event;
    $contact->{notes} = "event:".$evt->id." fee:".$fee->id." ticket:".$this->id;
    $contact->{account_id} = $acct_id;
    $contact->{type} = &preference("EvtReg.guest_contact_type") || "main";
    my $c = new Modules::ID::Contact();
    return $c->save_contact_data($contact);
}

sub get_contact_info_from_response {
    my ($this) = @_;

    # copy response data to a virtual contact record
    my $response = $this->response;
    my $data = $response->get_response_data();
    my %contact = (
		   address => undef,
		   city => undef,
		   provstate => undef,
		   country => undef,
		   pcode => undef,
		   phone => undef,
		   cell => undef,
		   fax => undef,
		   email => undef,
		   website => undef,
		   );
    foreach my $key (keys %$data) {
	if (exists $contact{$key}) {
	    $contact{$key} = $data->{$key};
	}
    }
    # see if we have any contact info
    my $have_data = 0;
    foreach my $key (keys %contact) {
	if ($contact{$key}) {
	    $have_data = 1;
	    last;
	}
    }
    return undef if (! $have_data);
    # ditch phone/url fields
    if ($contact{url} && ! $contact{website}) {
	$contact{website} = $contact{url};
    }
    delete $contact{url};

    # add name fields
    $contact{name} = $data->{name};
    $contact{first_name} = $data->{first_name};
    $contact{last_name} = $data->{last_name};

    return wantarray ? %contact : \%contact;
}

# Sales Management API

# ticket added to cart - do nothing, make_claim() covers it
sub sale_select {
    my $this = shift;
    return;
}

# ticket removed from cart - release it back into the sales pool
sub sale_delete {
    my $this = shift;
    $this->release();
    # rebuild session ???
    return;
}

# ticket purchase confirmed - reserve it
sub sale_activate {
    my $this = shift;
    $this->set_claim_status("reserved");
    return;
}

# ticket purchase paid in full - confirm it
sub sale_complete {
    my $this = shift;
    $this->set_claim_status("confirmed");
    return;
}

1;
