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

package Modules::Registration::Fee;

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Util;
use ExSite::Time;
use ExSite::Content;
use ExSite::Metadata;
use ExSite::Module qw(&read_conf);
use Modules::Registration::Ticket;
#use Modules::Finance::Account;
use Modules::Finance::Cart;

use vars qw(@ISA);
@ISA = qw(ExSite::Content);

sub my_subtype { return "fee"; }

sub setup {
    my ($this,%opt) = @_;
    $this->SUPER::setup(%opt);
    my $db = $share{DB};

    # need some DB extensions
    $db->{map}->load_submaps("Finance");
    $db->{map}->load_submaps("Register");
    # also, some configurations
    &read_conf("Register");

    # setup some queries
    if (! exists $share{querylib}{"my tickets"}) {
	$db->set_query("my tickets",
		       sql => "select c.content_id,tc.* from content c, content_type type, ticket t, ticket_claim tc where c.type=type.content_type_id and type.name='fee' and c.content_id=t.content_id and tc.ticket_id=t.ticket_id and tc.status in ('confirmed','unconfirmed') and tc.account_id=? or tc.guest_account_id=?",
		       mode => "r",
		       nparam => 2,
		       keys => ["content","content_type","ticket","ticket_claim"],
	    );
	$db->set_query("all ticket claims",
		       ( sql=>"select a.account_id,a.name account,t.info ticket_info,c.*,r.form_id form from account a,ticket t,ticket_claim c left join response r on c.response_id=r.response_id where a.account_id=c.account_id and c.ticket_id=t.ticket_id and t.content_id=? order by c.ticket_claim_id",
			 nparam=>1,
			 mode=>"r",
			 keys=>["ticket_claim","ticket","account","response"],
		       ));
	$db->set_query("roster member data",
		       ( sql=>"select a.account_id,u.* from user u, account a, ticket_claim c, ticket t where u.uid=a.uid and c.account_id=a.account_id and t.ticket_id=c.ticket_id and t.content_id=?",
			 nparam=>1,
			 mode=>"r",
			 keys=>["user","account","ticket_claim","ticket"],
		       ));
	$db->set_query("roster contact info",
		       ( sql=>"select c.*,ci.* from contact c, contact_info ci, account a, ticket_claim tc, ticket t where c.account_id=a.account_id and ci.contact_id=c.contact_id and tc.account_id=a.account_id and t.ticket_id=tc.ticket_id and t.content_id=?",
			 nparam=>1,
			 mode=>"r",
			 keys=>["contact","contact_info","account","ticket_claim","ticket"],
		       ));
    }
    return;
}

# event, mainevt, event_group - fees are normally (but not necessarily) under 
# events; overload these methods, in case they're not.

sub event {
    my $this = shift;
    return $this->parent();
    #my $parent = $this->parent();
    #return $parent->subtype() eq "event" ? $parent->main_event : $parent;
}

sub main_event {
    my $this = shift;
    my $parent = $this->parent();
    return $parent->subtype() eq "event" ? $parent->main_event : $parent;
}

sub event_group {
    my $this = shift;
    my $mainevt = $this->main_event;
    return ($mainevt->subtype() eq "event") ? 
	$mainevt->event_group : 
	($mainevt);
}

sub is_main_fee {
    my $this = shift;
    return ($this->event->id == $this->main_event->id);
}

# status

sub sold_out {
    my $this = shift;
    my $ntix = $this->count_unsold_tickets();
    return (defined $ntix) ? ! $ntix : 0;          
}

sub is_ticketed {
    my $this = shift;
    my %meta = $this->get_metadata();
    return ($meta{type} =~ /ticket/);
}

sub has_waitlist {
    my $this = shift;
    my %meta = $this->get_metadata();
    return ($meta{type} =~ /waitlist/);
}

sub get_tickets {
    my $this = shift;
    $this->load_child("ticket");
    return $this->{children}{ticket};
}

sub count_tickets {
    my ($this,$status) = @_;
    if (! $this->{ticket_count}) {
	$this->{ticket_count} = {};
	my $tickets = $this->get_tickets;
	$tickets->reset;
	while (my $tic = $tickets->next) {
	    $this->{ticket_count}{all}++;
	    $this->{ticket_count}{$tic->status}++;
	}
    }
    return $status ? $this->{ticket_count}{$status} : $this->{ticket_count};
}

sub should_be_static {
    my $this = shift;
    return $this->event->should_be_static();
}

# available_to(fee_id)
# returns 1 if this is available to fee_id
# returns 0 if this is not available to fee_id
# returns undef if no special rule (use default logic)

sub available_to {
    my ($this,$fee_id) = @_;
    if (! exists $this->{available_to}) {
	my $avail = $this->meta->get("available_to");
	if ($avail) {
	    my @avail = split /,\s*/, $avail;
	    foreach my $id (@avail) {
		if ($id > 0) {
		    # available
		    $this->{available_to}{$id} = 1;
		}
		else {
		    # not availble
		    $this->{available_to}{-$id} = 0;
		}
	    }
	}
    }
    return $fee_id ? $this->{available_to}{$fee_id} : $this->{available_to};
}

sub fee_group {
    my $this = shift;
    # get event group
    my $parent = $this->parent();
    my $mainevt = $parent->subtype() eq "event" ? $parent->mainevt : $parent;
    my @fee = $mainevt->get_descendants("fee");
    my $feegrp = new ExSite::ObjectList(type=>"fee",list=>\@fee);
    return $feegrp;
}

# claim_ticket: find an available ticket, and put a claim on it

sub claim_ticket {
    my ($this,$claim) = @_;
    my $tix = $this->get_tickets();

    # release tickets
    $this->release_tickets($tix);

    my $tic;
    # see if any of the existing tickets are available
    $tix->reset;
    while ($tic = $tix->next) {
	if ($tic->is_available) {
	    my $lockid = "lock:ticket_".$tic->id;
	    if (exists $store{$lockid}) {
		# someone else is looking at this ticket right now
		if (time - $store{$lockid} > 60) {
		    # ticket was last looked at more than 60s ago, just take it
		    #### delete any receivable_items
		    $store{$lockid} = time;
		    last;
		}
	    }
	    else {
		# mark this ticket as in processing
		#### delete any receivable_items
		$store{$lockid} = time;
		last;
	    }
	}
    }
    if (! $tic && ! $this->is_ticketed) {
	# none of the existing tickets are available
	# but doesn't matter, we can just issue a new ticket
	$tic = new Modules::Registration::Ticket();
	$tic->setdata("content_id",$this->id);
	$tic->setdata("status","active");
	my $tic_id = $tic->force_save();
	$store{"lock:ticket_".$tic_id} = time;
    }
    if ($tic) {
	# we've got a ticket; make a claim on it
	my $status = $tic->make_claim($claim);
	delete $store{"lock:ticket_".$tic->id};
	return $tic;
    }
    else {
	$this->error("No tickets available at this time.");
	return undef;
    }
}

sub count_unsold_tickets {
    my $this = shift;
    if ($this->is_ticketed) {
	return 
	    $this->count_tickets("available") + 
	    $this->count_tickets("not available yet");
    }
    return undef;  # not applicable
}

sub release_tickets {
    my ($this,$tix) = @_;
    $tix or $tix = $this->get_tickets();
    $tix->reset;
    while (my $tic = $tix->next) {
	my $claim = $tic->get_claim();
	if ($claim->getdata("status") eq "held") {
	    my $t = new ExSite::Time(); #now
	    if ($t->diff($claim->getdata("ctime"),"sql_timestamp") < -3600) { # 1hr
		$tic->release();
	    }
	}
    }
}

sub show {
    my ($this,%opt) = @_;
    my $out = $this->run_handler("show_fee",%opt);
    return $out if (defined $out);
    if ($this->defined) {
	# don't show admin fees at all if not an admin
	return undef if ($this->getdata("access") > 4 && 
			 ! $share{DB}->is_executive);
	my $ml = &get_obj("ML");
	$out .= $ml->h1($this->title);
	$out .= $ml->div(
	    $this->show_price(),
	    {class=>"FeeAbout"}
	    );
	my $descr = $this->revision->get_html;
	$out .= $descr;

	if (! $this->allow_post) {
	    # permission denied - report failure message from allow_post
	    $out .= $ml->p($this->{disallow_post});
	    if ($this->has_role(undef,"administrator")) {
		my $ui = &get_obj("UI");
		$out .= $ui->ErrorMsg($msg{"As an administrator, you can force-register in this fee, regardless."});
	    }
	    else {
		return $ml->div($out,{class=>"Fee"});
	    }
	}

	$out .= $ml->h2($msg{Register}) if ($descr);
	my $input = new ExSite::Input;
	my $post = $input->post;
	my $indata  = $input->post_or_query();
	if (keys %$post > 0 ||   # post received
	    $indata->{ptic}) {   # subregistration - no post required
	    return $this->post();
	}
	if ($this->sold_out) {
	    $out .= $ml->p($msg{"Sorry, this registration fee is sold out."});
	}
	elsif (my $tic = $this->is_registered()) {
	    $out .= $ml->p($msg{"Looks like you have registered for this before. "}.$ml->a($msg{"Click here to resume your previous registration session."},{href=>$this->link(cmd=>"session")}));
	    $out .= $ml->h3($msg{"Or, Start Over:"});
	    $out .= $this->registration_form();
#		$out .= $ml->p($msg{"Looks like you have registered for this already..."});
#		$out .= $this->index(ticket=>$tic);
#		$out .= $ml->h3($msg{"Register again:"});
#		$out .= $this->registration_form();
	}
	else {
	    $out .= $this->registration_form();
	}
	return $ml->div($out,{class=>"Fee"});
    }
    return undef;
}

sub summary {
    my ($this,%opt) = @_;
    my $out = $this->run_handler("show_fee",%opt);
    return $out if (defined $out);
    if ($this->defined) {
	# don't show admin fees at all if not an admin
	return undef if ($this->getdata("access") > 4 && 
			 ! $share{DB}->is_executive);
	my $ml = &get_obj("ML");
	my $description = $this->has_revisions ? $this->revision->get_html : "";
	my $status = $this->wf_status();

	my $open = $this->is_open();
	my $link = $this->registration_link($opt{ticket});
	my @access;
	if ($this->getdata("code")) {
	    push @access, $msg{"Access code required."};
	}
	if ($this->getdata("access") && $this->getdata("access") ne "public") {
	    push @access, &substitute($msg{"This registration type is restricted to [[type]]."},{type=>$this->getdata("access")});
	}
	if (@access > 0) {
	    $description .= $ml->span(join(" ",@access),{class=>"feeAccess"});
	}
	if (! $this->is_open()) {
	    $description .= $ml->span($this->registration_status,{class=>"error"});
	}
	#my $cost = $this->show_cost($opt{date}); # date ??
	my $cost = $this->show_price();
	$out = $ml->span($this->title,{class=>"feeName"})."\n";

	# event info
	if ($this->event->is_activity) {
	    $out .= $ml->div(&ExSite::HTML::ResponsivePopup(label=>$msg{"Event Info"},type=>"inline",pane=>$this->event->summary()),{class=>"feeActivityInfo"});
	}
	$out .= $ml->span($cost.$link,{class=>"feeBuyInfo"})."\n";
#	if ($regdate) {
#	    $out .= $ml->span(&substitute($msg{"Registered [[date]]"},{date=>$regdate}),{class=>"feeRegdate"})."\n";
#	}
	if ($description) {
	    ### try translating fee descriptions
	    $out .= $ml->div($msg{$description},{class=>"feeDescr"});
	}
	my $class = $opt{class} ? "FeeSummary $opt{class}" : "FeeSummary";
	if (! $open) { $class .= " feeClosed"; }
	return $ml->div($out,{class=>$class,id=>"Fee".$this->id});
    }
    return undef;
}

sub preview {
    my ($this,%opt) = @_;
    #$this->{url} = new ExSite::URI;
    $this->{content_link_type} = "id";
    return $this->show();
}

sub registration_form {
    my $this = shift;

    my $ml = &get_obj("ML");
    my $out;
    # post() is now called indirectly through show() or preview()
    #my $posturl = "$config{server}{CGIpath}/$config{prog}{post}".$this->path();
    my $posturl = $share{Page} ? 
	$this->get_uri()->write() :
	$this->link();
    my $f = $this->my_content("form"); # by name, not type
    if ($f) {
	if (! $share{Page}) {
	    # admin view; add a price selector
	    my $fb = $f->get_form(action=>$posturl);
	    $this->admin_price_selector($fb);
	    
	}
	$out .= $f->show(action=>$posturl);
    }
    else {
	my $br = $ml->br;
	my $fb = new ExSite::FormBuilder(action=>$posturl);

	$fb->input(name=>"first_name",type=>"text",size=>20,prompt=>"First Name");
	$fb->input(name=>"last_name",type=>"text",size=>20,prompt=>"Last Name");
	if (! $share{Page}) {
	    $this->admin_price_selector($fb);
	}
	$fb->template("<table><tr>
<td>[[first_name:prompt]]${br}[[first_name:input]]</td>
<td>[[last_name:prompt]]${br}[[last_name:input]]</td>
</tr></table>");
	$out .= $fb->make();
    }
    return $ml->div($out,{class=>"FeeRegistrationForm"});
}

sub post {
    my ($this,%opt) = @_;
    my $out;
    my $ml = &get_obj("ML");
    if ($this->allow_post()) {

	# fix links
	my $from = $ENV{HTTP_REFERER};
	my $prog = $config{prog};
	my $uri = new ExSite::URI();
	if ($from =~ /$prog->{page}|$prog->{view}|$prog->{post}/) {
	    # posting from a regular content view
	    # convert url back to page URLs for links
	    $uri->path('ExSiteAction','page');
	}

	my $f = $this->my_content("form"); # by name, not type
	my ($response,%regdata);
	if ($f && $f->is_active) {
	    # submit post to form, instead
	    $out .= $f->post();
	    $response = $f->get("response");
	    if ($response) {
		%regdata = $response->get_response_data;
	    }
	}
	if (! scalar keys %regdata) {
	    # failed form, or no form
	    my $input = new ExSite::Input;
	    my $post = $input->post();
	    my $indata  = $input->post_or_query();
	    if (scalar keys %$post) {
		# generic form
		$regdata{first_name} = $post->{first_name};
		$regdata{last_name} = $post->{last_name};
	    }
	    elsif ($indata->{ptic}) {
		# subregistration - re-use values from main ticket
		## validate ptic?
		my $oldtic = new Modules::Registration::Ticket(id=>$indata->{ptic});
		if ($oldtic->is_mine) {
		    my ($first,$last) = $oldtic->claim_name();
		    $regdata{first_name} = $first;
		    $regdata{last_name} = $last;
		}
	    }
	    else {
		# no form
		if (exists $session{last_registration}) {
		    # use previous registration 
		    $regdata{first_name} = $session{last_registration}{first_name};
		    $regdata{last_name} = $session{last_registration}{last_name};
		}
		else {
		    # who knows!?
		    ####### FIXME: error? Will we process a registration on any
		    # post to a page that displays a fee?
		    $regdata{first_name} = "Unknown";
		    $regdata{last_name} = "Registrant";
		}
	    }
	}
	# if okay, proceed through registration
	my $tic = $this->register(uri=>$uri,response=>$response,response_data=>\%regdata);
	if ($tic) {
	    $out .= $ml->p($tic->name." held for ".$tic->claim_name);  ### translate
	}
	else {
	    $out .= $ml->h3($msg{"Registration Failed:"});
	    $out .= &ExSite::Config::show_diagnostics();
	}
	$out .= $this->index(uri=>$uri,ticket=>$tic,data=>\%regdata);
	$out .= $this->show_cart();
	return $out;
    }
    else {
	return $this->error("Permission denied.");
    }
}

sub show_cart {
    my $this = shift;
    if ($share{Page}) {
	return "<!--&Pay(cart=view)-->\n";
    }
    else {
	my $ui = new ExSite::UI;
	my $ml = &get_obj("ML");
	my $cart = new Modules::Finance::Cart();
	my $out = $ml->h3("Shopping Cart").$cart->show_readonly();
	$out .= $ui->Button(url=>"$config{server}{CGIpath}/$config{prog}{admin}/Pay?cart=view",target=>"_blank",label=>"Done - go to Pay module");
	return $out;
    }
}

sub registration_link {
    my ($this,$tic) = @_;
    my $url = ($tic && ! $this->is_main_fee) ?
	$this->link(ptic=>$tic->id,cmd=>undef) :
	$this->link(ptic=>undef,cmd=>undef);
    my $anchor;
    if ($this->sold_out) {
	$anchor = "Sold out";
	if ($this->has_waitlist) {
	    $anchor .= " - waitlist only";
	}
	elsif ($share{DB}->is_executive) {
	    $anchor .= " - force register";
	}
	else {
	    $url = "#";
	}
    }
    elsif ($this->is_closed) {
	$anchor = "Registration closed";
	if ($share{DB}->is_executive) {
	    $anchor .= " - force register";
	}
	else {
	    $url = "#";
	}
    }    
    else {
	$anchor = "Register now";
    }
    my $ml = &get_obj("ML");
    if ($tic) {
	if ($tic->fee->id == $this->id) {
	    my $status = $msg{Registered} . " - " . $msg{$tic->status_message()};
	    $anchor = $ml->span($status,{class=>"ticketStatus",title=>$msg{"You must checkout to complete your registration."}}).
		$ml->span($msg{"Get another ticket"},{class=>"ticketPurchase",title=>$msg{"Click here to register another."}});
	}
    }
    return $ml->a($anchor,{href=>$url,class=>"feeLink"});
}

sub can_index {
    my $this = shift;
    return undef; # do not index fees
}

sub hide_from_fees {
    my ($this,$fee_id) = @_;
    if (! $this->{hide_from_fees}) {
	my %hide = map { $_=>1 } split /,/, $this->meta->get("hide_from_fees");
	$this->{hide_from_fees} = scalar keys %hide ? \%hide : undef;
    }
    return $fee_id ? $this->{hide_from_fees}{$fee_id} : $this->{hide_from_fees};
}

sub count_current_registrations {
    my ($this,$tic) = @_;
    my $count = 0;
    if ($this->is_main_fee) {
	# count total number of registrants in this fee
	my $id = $this->id;
	foreach my $name (keys %{$session{registrants}}) {
	    $count++ if ($session{registrants}{$name}{registrations}[0]{content_id} == $id);
	}
    }
    else {
	# count total number of tickets for this registrant
	$tic or $tic = new Modules::Registration::Ticket(data=>$session{last_registration});
	my $tfee = $tic->getdata("content_id");
	my $name = $tic->unique_claim_name();
	foreach my $ticdata (@{$session{registrants}{$name}{registrations}}) {
	    $count++ if ($ticdata->{content_id} == $tfee);
	}
    }
    return $count;
}

# allow_post: is the user allowed to register in this fee?

sub allow_post {
    my $this = shift;
    my $level = $share{DB}->level;
    my $ml = &get_obj("ML");
    if ($this->is_active) { # do not allow registrations on disabled fees
	if ($this->url_is_me()) { # posts only accepted at the fee URL
	    if ($this->is_main_fee()) {
		# disallowed if a conditional fee that we do not qualify for
		my $hide = $this->hide_from_fees();
		if (ref $hide eq "HASH") {
		    # main fee, but hidden from certain fees - 
		    # do not show this fee if our existing registrations 
		    # are all in the hide_from fees
		    my $allow = 0;
		    foreach my $name (%{$session{registrants}}) {
			my $maintic = $session{registrants}{$name}{registrations}[0];
			if (! $hide->{$maintic->{content_id}}) {
			    # user is in a fee that this fee is NOT hidden from
			    $allow = 1;
			    last;
			}
		    }
		    if (! $allow) {
			# user's fees all block this fee
			$this->{disallow_post} = &substitute($msg{"You are not eligible for this fee."});
			return 0;
		    }
		}
	    }
	    else {
		# only allowed if already registered in main fee
		my $input = ExSite::Input->new()->combine();
		if ($input->{ptic}) {
		    ### should we check if preg's event is parent event?
		    my $ptic = new Modules::Registration::Ticket(id=>$input->{ptic});
		    if (! $ptic->is_mine) {
			$this->{disallow_post} = &substitute($msg{"Ticket [[tic]] is not yours."},{tic=>$ptic->id});
			return 0;
		    }
		    # check 
		    my $pfee = $ptic->fee();
		    if ($pfee && $this->hide_from_fees($pfee->id)) {
			# this fee is explicitly blocked in this case
			return 0;
		    }
		}
		else {
		    my $mainevt = $this->main_event();
		    if ($this->{content_link_type}) {
			$mainevt->set("content_link_type",$this->{content_link_type});
		    }
		    $this->{disallow_post} = &substitute($msg{"To register in ".$ml->em("[[activity]]")." you must first register in ".$ml->a($ml->em("[[event]]"),{href=>"[[link]]"})."."},{event=>$mainevt->title,activity=>$this->event->title,link=>$mainevt->link()});
		    return 0; # register at main fee, first
		}
	    }
	    # check permissions
	    if ($level >= $this->getdata("access")) {
		if ($level > 4) {
		    # execs always allowed to force-register
		    return 1;
		}
		elsif ($this->is_open) {
		    # no max
		    return 1;
		}
		elsif ($this->is_closed) {
		    $this->{disallow_post} = $msg{"Registration is now closed."};
		    return 0;
		}
		else {
		    $this->{disallow_post} = $msg{"This registration fee is not open at this time."};
		    $this->{disallow_post} .= $this->show_schedule();
		    return 0;
		}

	    }
	    else {
		$this->{disallow_post} = $msg{"This fee has restricted access. Please log in to access this registration fee."};
		return 0;
	    }
	}
	else {
	    $this->{disallow_post} = &substitute($msg{"Register ".$ml->a("here",{href=>"[[link]]"})."."},{link=>$this->link()});
	    return 0;
	}
    }
    $this->{disallow_post} = $msg{"This registration fee is not open at this time."};
    return 0;
}

# prices

# price - admin-only fees are only an option in the admin interface

sub price {
    my $this = shift;
    my $price;

    if ($share{DB}->is_executive ) {
	# executive price override
	my $input = new ExSite::Input;
	my $post = $input->post();
	if ($post->{"_price"}) {
	    $price = $share{DB}->fetch("price",$post->{"_price"});
	    if ($price && $price->{content_id} == $this->id) {
		return $price;
	    }
	    $price = undef;
	}
    }

    my @prices = $this->get_allowed_prices();
    foreach my $p (@prices) {
	next if ($p->{access} >= 5); # ignore admin fees when choosing best price
	if (! $price || $p->{cost} < $price->{cost}) {
	    $price = $p;
	}
    }
    return $price;
}

# show_price - hide free prices if there are activities

sub show_price {
    my ($this,$pricedata) = @_;
    my $cost = $this->SUPER::show_price($pricedata);
    my $ml = &get_obj("ML");
    if ($cost) {
	return $ml->span($cost,{class=>"feeCost"});
    }
    elsif ($this->event->has_activities()) {
	# do not display a cost, since the actual costs might be in the
	# activity fees
	return undef;
    }
    elsif ($this->has_prices()) {
	# has a price, but not available now
	return undef;
    }
    else {
	# no cost
	return $ml->span($msg{$config{Event}{Fee}{free}} || $msg{"FREE"}, {class=>"feeCostFree"});
    }
}

sub admin_price_selector {
    my ($this,$form) = @_; 
    my $ml = &get_obj("ML");
    my @price = $this->get_prices();
    my %price = &keywise("price_id",\@price);
    my $pref_price = $this->price();
    my @opt; 
    foreach my $p (@price) {
	next if ($p->{access} && $p->{access} > $share{DB}->level);
	my $descr = $p->{description} ? $p->{description} . ": \$" : "\$";
	$descr .= $p->{cost};
	push @opt, { text=>$descr, value=>$p->{price_id} };
    }
    if (scalar @opt > 1) {
	$form->input(type=>"select",prompt=>"Price",name=>"_price",options=>\@opt,value=>$pref_price->{price_id});
    }
}

# dates

# is_open - are we currently accepting registrations?

sub is_open {
    my ($this,$date) = @_;
    my @price = $this->get_allowed_prices;  #### FIXME: excludes open prices at different permission levels
    if (@price > 0) {
	# valid prices in effect
	return 1;
    }
    else {
	# no valid prices in effect
	@price = $this->get_prices();
	if (@price) {
	    # but there are prices, so nothing is valid 
	    # for this user at this time
	    return 0;
	}
	else {
	    # no prices; registration is open up until the start of the event
	    my $start = $this->event->get_date();
	    if ($start && $start->defined) {
		return $start->get_start()->in_future;
	    }
	    else {
		# undated event? always open?
		return 1;
	    }
	}
    }
}

# is_closed - are we after the end date?

sub is_closed {
    my ($this) = @_;
    my ($start,$end) = $this->event->get_date_range();
    if ($start) {
	my $date = new ExSite::Time($start,"sql_datetime");
	if ($date->in_future) {
	    # event hasn't started yet - check prices
	    my @price = $this->get_allowed_prices;
	    if (@price > 0) {
		# valid prices in effect - registration must be open
		return 0;
	    }
	    else {
		# no valid prices in effect - registration open until event start
		return 1;
	    }
	}
	else {
	    # event has started
	    return 1;
	}
    }
    else {
	# undated event? always open?
	return 0;
    }
}

sub registration_status {
    my $this = shift;
    my $status = $this->wf_status();
    my $message;
    if ($status eq "active") {

	### what about active but sold out?

	if ($this->is_open()) {
	    $message = $config{EvtReg}{message}{registration_open} || "Registration is open.";
	}
	elsif ($this->is_closed()) {
	    $message = $config{EvtReg}{message}{registration_closed} || "Registration is now closed.";
	}
	else {
	    $message = $config{EvtReg}{message}{registration_notopen} || "Registration is not open yet.";
	}
    }
    elsif ($status eq "inactive") {
	$message = $config{EvtReg}{message}{registration_inactive} || "Sorry, these registrations are not being accepted.";
    }
    elsif ($status eq "sold out") {
	$message = $config{EvtReg}{message}{registration_soldout} || "Sold out.";
    }
    elsif ($status eq "waitlist") {
	$message = $config{EvtReg}{message}{registration_waitlist} || "Sold out&mdash;waitlist only.";
    }
    return $message ? $msg{$message} : undef;
}

# report gives registration overview

sub report {
    my $this = shift;
    my $ml = &get_obj("ML");
    my $count = $this->count_tickets();
    $count->{available} = $count->{active} + $count->{canceled};
    $count->{reserved} = $count->{held} + $count->{reserved};
    my $r = new ExSite::ReportBuilder(
	title=>"Ticket Summary",
	class=>"feeOverview Report",
	);
    $r->headers("Ticket status","Count");
    my @status = ("confirmed","reserved","available","inactive","waitlist");
    my %statushdr = (
	confirmed => "Sold",
	available => "Available",
	reserved => "Reserved",
	inactive => "Unreleased",
	waitlist => "Waitlist",
	);
    my %statusdescr = (
	confirmed => "Completed ticket sales",
	reserved => "Reserved and on-hold tickets, not paid for yet",
	available => "Tickets currently available for purchase",
	inactive => "Tickets that have not been released for sale yet",
	waitlist => "Overflow tickets, may not be honored",
	);
    foreach my $stat (@status) {
	my $count = $count->{$stat} || 0;
	if ($stat eq "unreleased" && $count == 0) {
	    $count = "unlimited";
	}
	$r->push(
	    $ml->strong($statushdr{$stat}).$ml->br.$ml->em($statusdescr{$stat}),
	    $ml->div($count,{class=>"num"}),
	    );
    }
    my $total = $count->{all} || 0;
    $r->footdata(["TOTAL",$ml->div($total,{class=>"num"})]);
    return $r->make();
}

sub get_roster_data {
    my ($this,%opt) = @_;
    my $tix = $this->get_tickets();
    my @claims = $share{DB}->get_query("all ticket claims",$this->id);
    my %claims = &keywise("ticket_id",\@claims);
    my %response;
    my $f = $this->my_content("form");
    my $form_id = $f ? $f->id : 0;
    if ($opt{incl_response} && $form_id) {
	foreach my $answer ($f->get_all_answers()) {
	    $response{$answer->{response_id}}{$answer->{label}} = $answer->{answer};
	}
    }
    my %members;
    if ($opt{incl_membership}) {
	%members = &keywise("account_id",$share{DB}->get_query("roster member data",$this->id));

	### FIXME: status

    }
    my %contact;
    if ($opt{incl_contact}) {
	foreach my $cinfo ($share{DB}->get_query("roster contact info",$this->id)) {
	    $contact{$cinfo->{account_id}}{$cinfo->{type}}{$cinfo->{name}} = $cinfo->{value};
	}
    }

    my @data;
    $tix->reset;
    while (my $tic = $tix->next) {
	my $row = $tic->get();
	next if (! $opt{"incl_".$claims{$row->{ticket_id}}{status}});
	$row->{ticket_status} = $row->{status};
	foreach my $cfld ("ticket_claim_id","account_id","account","guest_account_id","status","parent","first_name","last_name","response_id","ctime") {
	    $row->{$cfld} = $claims{$row->{ticket_id}}{$cfld};
	}
	my $aid = $row->{guest_account_id} || $row->{account_id};
	if ($opt{incl_membership}) {
	    $row->{"member.uid"} = $members{$aid}{uid};

#### FIXME: next 4 rows don't produce the output you want

	    $row->{"member.type"} = $members{$aid}{type};
	    $row->{"member.organization"} = $members{$aid}{organization};
	    $row->{"member.status"} = $members{$aid}{status};
	}
	if ($opt{incl_contact}) {
	    foreach my $cfld ("address","city","provstate","country","pcode","phone","email") {
		if ($contact{$aid}{billing}{$cfld}) {
		    #$row->{"contact.$cfld"} = $contact{$aid}{billing}{$cfld};
		    $row->{$cfld} = $contact{$aid}{billing}{$cfld};
		}
	    }
	}
	if ($opt{incl_response}) {
	    my $rid = $row->{response_id};
	    if ($response{$rid}) {
		$row->{form} = $form_id;
		foreach my $q (keys %{$response{$rid}}) {
		    $row->{"form.$q"} = $response{$rid}{$q};
		}
	    }
	}
	else {
	    # still need the form ID
	    $row->{form} = $form_id;
	}
	push @data, $row;
    }

    ### incl_activities

    return @data;
}

#============================================================================
# REGISTRATION

# register : claim a ticket
# options:
# response : a response object, if there was a registration form
# response_data : info entered into the registration form
#
# returns the ticket

sub register {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    my %claim = (
	first_name => $opt{response_data}{first_name},
	last_name => $opt{response_data}{last_name},
	);

    # response
    if ($opt{response}) {
	$claim{response_id} = $opt{response}->id;
    }

    # account (purchaser)
    my $acct = new Modules::Finance::Account;
    $acct->setup_account("$claim{first_name} $claim{last_name}");
    if (! $acct->id) {
	$this->error("Registration failed: Unknown account");
	return undef;
    }
    $claim{account_id} = $acct->id;

    ##### guest account

    # parent ticket claim
    my $claimname = $claim{first_name} ?
	"$claim{first_name} $claim{last_name}" : $claim{last_name};
    my $evt = $this->event;
    my $mainevt = $this->main_event;
    if ($evt->id != $mainevt->id) {
	# we are in an activity
	if ($mainevt->has_registration) {
	    # this registration will have a parent registration
	    my $input = new ExSite::Input();
	    my $indata = $input->query();
	    if ($indata->{ptic}) {
		my $ptic = new Modules::Registration::Ticket(id=>$indata->{ptic});
		my $pclaim = $ptic->get_claim();
		$claim{parent} = $pclaim->id;
	    }
	    if (! $claim{parent}) {
		# lost track of our parent; pick something appropriate from
		# the registration session
		my $bestreg;
		if (exists $session{registrants}{$claimname}) {
		    $bestreg = $session{registrants}{$claimname};
		}
		my $dupekey = 2;
		while (exists $session{registrants}{$claimname." #".$dupekey}) {
		    $bestreg = $session{registrants}{$claimname." #".$dupekey};
		    $dupekey++;
		}
		if ($bestreg) {
		    if ($bestreg->{events}{$mainevt->id}) {
			$claim{parent} = $bestreg->{events}{$mainevt->id}{ticket_claim_id};
		    }
		    else {
			$this->error("$claimname is not being registered in ".$mainevt->title);
		    }
		}
		else {
		    $this->error("$claimname is not being registered in anything.");
		}
	    }
	}
    }
    else {
	# main event registration

	# dupekey
	if (exists $session{registrants}{$claimname}) {
	    # dupe! set a dupekey to distinguish this registrant from 
	    # others with the same name
	    my $dupekey = 2;
	    while (exists $session{registrants}{$claimname." #".$dupekey}) {
		$dupekey++;
	    }
	    $claim{dupekey} = $dupekey;
	}
    }

    my $tic = $this->claim_ticket(\%claim);
    if ($tic && $tic->defined) {
	$this->{registrant} = $tic;
	my $ticdata = $tic->get();

	# record purchase
	$this->add_ticket_to_cart($tic);

	# update session
	$session{last_registration} = $ticdata;
	if (! exists $session{main_registrant}) {
	    $session{main_registrant} = $ticdata;
	}
	if ($evt->id != $mainevt->id) {

	    ######## WRONG: this only sets registrant if evt is not main evt
	    # we should set registrant to be the top registration of last_registration

	    $session{registrant} = $ticdata; 
	}
	$session{last_registration} = $ticdata;
	if ($session{registrations}) {
	    push @{$session{registrations}}, $ticdata;
	}
	else {
	    $session{registrations} = [ $ticdata ];
	}
	### FIXME: will this hold onto data from previous attempts?
	my $registrant_name = $claim{dupekey} ? $claimname." #".$claim{dupekey} : $claimname;
	$session{registrants}{$registrant_name}{fees}{$this->id} = $ticdata;
	$session{registrants}{$registrant_name}{events}{$evt->id} = $ticdata;
	if (exists $session{registrants}{$registrant_name}{registrations}) {
	    push @{$session{registrants}{$registrant_name}{registrations}},$ticdata;
	}
	else {
	    $session{registrants}{$registrant_name}{registrations} = [$ticdata];
	}
	# force session update (because we are updating deep in session hashes)
	my $s = tied %session;
	$s->set("dirty",1) if $s;
	return $tic;
    }
    else {
	my $tic = new Modules::Registration::Ticket();
	return $tic; # undef ticket
    }
}

sub add_ticket_to_cart {
    my ($this,$tic) = @_;
    my $out;
    my $price = $this->price();
    my $devt = $this->event->label;
    my $dfee = $this->label;
    my $dprice = $price->{description};
    my $description = $devt;
    if ($devt ne $dfee) { $description .= " - $dfee"; }
    if ($dprice) { $description .= " - $dprice"; }

    my %item = (
	item => $msg{Registration}.": (".$tic->claim_name().")",
	description => $description,
	cost => $price->{cost},
	acctcode_id => $config{Register}{acctcode},
	acctcode2 => $this->event->id,
	acctcode3 => $this->id,
#	parent => , ############## parent ticket claim
	uid => $share{DB}->my_uid,
	objtype => "ticket",
	objid => $tic->id,
	);

    my $cart = new Modules::Finance::Cart();
    $cart->add(%item);
}
=pod
    if ($share{Page} && ! $this->{waitlist}) {
	# use regular shopping cart
	my $pay = &get_module("Pay");
	if ($pay) {
	    # get the regular cart to do all the work
	    $cartdata{cart} = "add";
	    $cartdata{silent} = 1; # suppress usual cart chatter
	    my $error_count = &AtError();
	    $out .= $pay->write(&EncodeHash(%cartdata));
	    if (&AtError($error_count)) {
		$out .= $pay->show_diagnostics("error","html");
	    }
	}
	else {
	    $out .= $this->error($@);
	}
	if ($session{invoice} && ! $this->{registrant}->getdata("account_id")) {
	    # looks like a new anonymous account - update the reg record
	    my $inv = new Modules::Finance::Receivable(id=>$session{invoice});
	    $this->{registrant}->setdata("account_id",$inv->getdata("account_id"));
	    $this->{registrant}->force_save();
	}

	# set back-to-shopping link to go to registration session
	my $spage = &service_page("EvtReg",$this->{section_id});
	if ($spage) {
	    $session{pay_redirect} = $spage->link(evt=>$this->{evt}->id,regcmd=>"session");
	}
    }
    else {
	# non-ecommerce invoice (waitlist or control panel)
	my $inv = $this->get_invoice(waitlist=>$this->{waitlist});
	if ($inv) { 
	    my $item = new Modules::Finance::ReceivableItem();
	    my $uid = $share{DB}->my_uid || 0;
	    $item->setdata("receivable_id",$inv->id);
	    foreach my $col (qw(item description cost acctcode_id member_id note objtype objid)) {
		if ($cartdata{$col}) {
		    $item->setdata($col,$cartdata{$col});
		}
	    }
	    my $uid = $share{DB}->my_uid || 0;
	    $item->setdata("receivable_id",$inv->id);
	    $item->setdata("member_id",$uid);
	    $item->setdata("note","autogenerated from control panel registration");
	    if (! $item->save()) {
		$out .= $item->show_diagnostics("error","html");
	    }
	}
	else {
	    $out .= &ExSite::Config::show_diagnostics();
	}
    }
    # free item warning is issued in payment, above
#    if ($cartdata{cost} < 0.01 && ! $this->{waitlist} && ! $this->{admin}) {
#	$out .= $ml->p($msg{"Although this registration has no cost, you must proceed through checkout in order to confirm. If you do not check out, your registration will be canceled."});
#    }
    return $out;
}
=cut

# is_registered: has current user EVER registered in this fee?
# is_registering: is current user CURRENTLY registering in this fee?

sub is_registered {
    my $this = shift;
    if (! exists $this->{is_registered}) {
	if (! $this->is_registering) {
	    # check older, completed registrations
	    my $acct = new Modules::Finance::Account;
	    $acct->setup_my_account;
	    my $acctid = $acct->id;
	    if ($acctid) {
		foreach my $tic ($share{DB}->get_query("my tickets",$acctid,$acctid)) {
		    if ($tic->{content_id} == $this->id) {
			$this->{is_registered} = new Modules::Registration::Ticket(data=>$tic);
		    }
		}
	    }
	}
    }
    return $this->{is_registered};
}

sub is_registering {
    my $this = shift;
    if (! exists $this->{is_registered}) {
	if (exists $session{registrations}) {
	    # check current list of tickets, in reverse order
	    foreach my $tic (reverse @{$session{registrations}}) {
		if ($tic->{content_id} == $this->id) {
		    $this->{is_registered} = new Modules::Registration::Ticket(data=>$tic);
		    last;
		}
	    }
	}
    }
    return $this->{is_registered};
}

# index: show the fee choices that the user is eligible for
# (same as old event::show_session_fees)

sub index {
    my ($this,%opt) = @_;
    #my $tic = $opt{ticket} || $this->is_registering();
    my $tic = $this->is_registering();
    return undef if (! $tic); # no indexes for non-registrants
    my $ml = &get_obj("ML");
    my $registrant_name = $tic->unique_claim_name();
    my $ui = new ExSite::UI;

    # list fees available to current registrant
    my $out = $ml->div(
	$this->index_registrant($tic),
	{class=>"CurrentRegistrant"}
	);

    # list other registrants 
    my $otherout;
    foreach my $name (sort keys %{$session{registrants}}) {
	next if ($name eq $registrant_name); # already done
	my $otic = new Modules::Registration::Ticket(data=>$session{registrants}{$name}{registrations}[0]);
	$otherout .= $ml->div(
	    $this->index_registrant($otic),
	    {class=>"OtherRegistrant"}
	    );
    }
    if ($otherout) {
	$out .= $ui->BlindBox(open=>0,
			      title=>$msg{"Other registrants (click to view)"},
			      pane=>$otherout);
    }


    #### TODO: merchandise


    $out .= $this->index_new_registrant();

    return $ml->div($ml->h2($msg{"Continue Registration"}).$out,
		    {class=>"FeeSession"}) if $out;
}

# index_registrant: show the fee choices for the registrant who holds a ticket

sub index_registrant {
    my ($this,$tic) = @_;
    my $out;
    my $ml = &get_obj("ML");
    my $name = $tic->claim_name();
    my $uname = $tic->unique_claim_name();
    foreach my $evt ($this->event_group()) {
	if (exists $session{registrants}{$uname}{events}{$evt->id}) {
	    # user is already registered in this event
	    ### FIXME: whatif this is the same as the passed tic?
	    my $tic = new Modules::Registration::Ticket(data=>$session{registrants}{$uname}{events}{$evt->id});
	    my $fee;
	    if ($this->id == $tic->getdata("content_id")) {
		$fee = $this;
	    }
	    else {
		#$fee = $tic->fee(url=>$this->{url});
		$fee = $tic->fee();
		$fee->set("content_link_type",$this->{content_link_type});
	    }
	    $out .= $fee->summary(ticket=>$tic);
	    $out .= $fee->index_merchandise();
	}
	else {
	    # not registered in this event, list available fees
	    # get parent ticket
	    my $tic = new Modules::Registration::Ticket(data=>$session{registrants}{$uname}{events}{$this->main_event->id});
	    foreach my $fee ($evt->get_contents("fee")) {
		next if ($fee->hide_from_fees($tic->getdata("content_id")));
#		my %hide = map { $_=>1 } split /,/, $fee->meta->get("hide_from_fees");
#		next if ($hide{$tic->getdata("content_id")});

		my $max = $fee->meta->get("maximum_registrations");
		next if ($max && $fee->count_current_registrations($tic) >= $max);

		$fee->set("content_link_type",$this->{content_link_type});
		$out .= $fee->summary(ticket=>$tic);
	    }
	}
    }
    return $ml->div(
	$ml->h3($name).
	$ml->div($out,{class=>"feeIndex"}),
	{class=>"EventRegistrant"}
	) if $out;
}

sub index_new_registrant {
    my ($this) = @_;
    my $out;
    my $ml = &get_obj("ML");
    my $evt = $this->main_event();
    foreach my $fee ($evt->get_contents("fee")) {
	my $max = $fee->meta->get("maximum_registrations");
	next if ($max && $fee->count_current_registrations() >= $max);
	$fee->set("content_link_type",$this->{content_link_type});
	if ($fee->hide_from("index")) {
	    # Do not display this fee in fresh indexes (no registrations yet).
	    # Display it if we have collected registrations and the fee is 
	    # not explicitly hidden from those fees.
	    foreach my $name (keys %{$session{registrants}}) {
		if ($session{registrants}{$name}{events}{$fee->event->id}) {
		    # we are already in this event, so we might be able to acces
		    # this conditional fee
		    my $tic = new Modules::Registration::Ticket(data=>$session{registrants}{$name}{events}{$fee->event->id});
		    if (! $fee->hide_from_fees($tic->fee->id)) {
			# no explicit instruction to hide it from this fee
			$out .= $fee->summary();
			last;
		    }
		}
	    }
	}
	else {
	    $out .= $fee->summary();
	}
    }
    return $ml->div(
	$ml->h3($msg{"New Registrant"}).
	$ml->div($out,{class=>"feeIndex"}),
	{class=>"NewRegistrant"}
	) if $out;
}

# index_merchandise: show merchandise that a registrant in this fee is 
# eligible to purchase

sub index_merchandise {
    my $this = shift;
    my $out;
    foreach my $product ($this->get_contents("product")) {
	if ($this->{content_link_type}) { 
	    $product->set("content_link_type","id");
	}
	$out .= $product->show();
    }
    if ($out) {
	my $ml = &get_obj("ML");
	return $ml->div($out,{class=>"feeMerchandise"});
    }
    return;
}

sub copy {
    my ($this,%data) = @_;
    my $diffdays = $data{_diffdays};
    delete $data{_diffdays};

    # don't use Content::copy because it won't change price dates
    # go one level deeper to ObjectMeta::copy, and then copy 
    # Content::copy logic here
    my $newid = &ExSite::ObjectMeta::copy($this,%data);
    if ($newid) {
	# copy current revision
	if ($this->has_revisions) {
	    my $newrevid = $this->revision->copy(content_id=>$newid);
	}
	# copy flags
	my %flag = $this->flags();
	if (keys %flag) {
	    my $c = $this->get_content_obj($newid);
	    foreach my $key (keys %flag) {
		$c->set_flag($key);
	    }
	}
	# copy prices, with date adjustments if necessary
	my @prices = $this->get_prices();
	if (@prices > 0) {
	    foreach my $price (@prices) {
		delete $price->{price_id};
		$price->{content_id} = $newid;
		# adjust price dates
		if ($diffdays) {
		    foreach my $time ("start","end") {
			if ($price->{$time} && $price->{$time} !~ /^0/) {
			    my $t = new ExSite::Time($price->{$time},"sql_datetime");
			    $t->add_approximate($diffdays,"days");
			    $price->{$time} = $t->write("sql_datetime");
			}
		    }
		}
		$share{DB}->insert("price",$price);
	    }
	}
    }
    return $newid;
}

1;
