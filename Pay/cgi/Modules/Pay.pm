package Modules::Pay;

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
#  This is a tool for site users to manage accounts, invoices, and 
#  e-commerce payments.
#
#----------------------------------------------------------------------------

### is checkout1_admin used???


use strict;

# useful kernel libs; you can/should remove any of these that are not needed

use ExSite::Config;          # required
use ExSite::Input;           # optional input manager
use ExSite::Misc;            # optional utils
use ExSite::Mail;            # optional utils
use ExSite::ML;              # optional markup-language generation
use ExSite::FormBuilder;     # optional form generation
use ExSite::ReportBuilder;   # optional report generation
use ExSite::Form;            # optional database manager
use ExSite::Time;
use ExSite::Module qw(&get_module);
use ExSite::ObjectList;
use ExSite::ObjectMeta;
use ExSite::Util;
use ExSite::URI;
use ExSite::UI;

use Modules::ID::Contact;
use Modules::Finance::Cart;
use Modules::Finance::Payment;

# recommended base class for plug-in modules

use Modules::BaseDCD;

# declare package global

use vars qw(@ISA $ml $ui);

# define our class inheritance

@ISA = qw(Modules::BaseDCD); # inherit from this base class

sub read {
    my ($this,$opt) = @_;
    my $input = new ExSite::Input;
    $this->{input} = $input->combine;
    $this->{post} = $input->post;
    $this->{query} = $input->query;
    if (! $this->{input}{inv}) {
	my $query = $input->query;
	# regular combine logic doesn't work for us
	$this->{input}{inv} = $this->{post}{inv} || $query->{inv};
    }
}

# write method (user management of shopping cart)

sub write {
    my ($this,$options) = @_;
    $this->get_config();
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    if ($this->{config}{kill}) {
	return $this->kill();
    }

    my %opt = &DecodeString($options);
    my $in = $this->{input};
    $this->setup_queries();
    $this->run_handler("Pay_init");

    # button clicks (update is default)
    my $cmd = $in->{submitaction} || $in->{clearaction};
    if (! $cmd) {
	# IE doesn't give us the value of the button clicked, but it does
	# give us the coordinates
	if ($in->{"submitaction.x"}) {
	    $cmd = $msg{Checkout};
	}
	elsif ($in->{"updateaction.x"}) {
	    $cmd = "edit";
	}
	elsif ($in->{"clearaction.x"}) {
	    $cmd = $msg{'Clear cart'};
	}
	elsif ($in->{"continue.x"}) {
	    $cmd = $msg{'Continue shopping'};
	}	
    }
    $cmd or $cmd = $in->{cart} || $opt{cart};

    # non-cart actions
    if ($cmd =~ /^(my|pay)acct$/) {
	return $ml->div($this->my_account(),{class=>"Pay"});
    } 
    elsif ($cmd eq "my_balance") {
	return $ml->div($this->my_balance(),{class=>"Pay"});
    }

    # don't setup a cart if we're not actually doing anything with it
    if (!$this->pgIsReceipt()) {
	if (! $cmd || $cmd eq "view") {
	    if (! $session{invoice}) {
		# no invoice/cart
		if ($share{Page}) {
		    my $out = $ml->p($msg{$this->{config}{message}{emptycart}});
		    my $template_name = "ShoppingCartHelp";
		    my $ctemplate = $share{Page}->find("ShoppingCartHelpEmpty");
		    $template_name = "ShoppingCartHelpEmpty" if ($ctemplate->get_html());
		    $out .= "<!--content($template_name)-->\n";
		    return $ml->div($out,{class=>"Pay"});
		}
		else {
		    return $this->error("The shopping cart is empty.");
		}
	    }
	}
    }

    $this->get_invoice($opt{invoice},%opt);
    if (! $this->{invoice}) {
	return $this->error($msg{"Session management needs to be enabled to use the shopping cart.  Please <a href=\"mailto:$config{site}{administrator}\">contact the webmaster</a> for assistance."});
    }
    my $out;
    my $txt_checkout = $this->{config}{button}{checkout} || "Checkout";
    if ($this->pgIsReceipt()) {
	# looks like we just completed an e-commerce payment
	$out .= $this->receipt(%opt);
    }
    elsif ($cmd eq $msg{'Clear cart'}) {
	$out .= $this->clear_cart();
#	### FIXME: confirm
#	delete $this->{invoice};
#	$session{invoice} = 0;
#	$this->get_invoice();
	$out .= $this->view();
    }
    elsif ($cmd eq $msg{'Continue shopping'}) {
	my $s = new ExSite::Section(section=>$share{Page}->get_my("section_id"));
	my $url = $session{pay_redirect} || $s->get_url;    
	&redirect($url);
    }
    elsif ($cmd eq $msg{$txt_checkout} || $cmd eq $txt_checkout) {
	$out .= $this->checkout1();
    }
    elsif ($cmd eq "checkout2") {
	$out .= $this->checkout2();
    }
    elsif ($cmd eq "add") {
	$out .= $this->{invoice}->add(%opt);
	$out .= $this->{invoice}->show();
    }
    elsif ($cmd eq "edit") {
	$out .= $this->{invoice}->modify();
	$out .= $this->{invoice}->show();
    }
    elsif ($cmd eq "payment") {
	$out .= $this->payment();
    }
    elsif ($cmd eq "cancel") {
	$out .= $this->cancel();
	$out .= $this->view();
    }
    elsif ($cmd eq "chacct") {
	# reset account
	$this->change_acct();
	# resume checkout
	$out .= $this->checkout1();
    }
    elsif ($cmd eq "quickpay") {
	# quickpay = add + checkout
	$this->add(%opt);
	# force reload of invoice
	delete $this->{invoice};
	$this->get_invoice();
	$out .= $this->checkout1();
    }
    elsif ($cmd eq "print") {
	$out .= $this->print_friendly();
    }
    else { #view 
	$out .= $this->{invoice}->show();
    }
    return $opt{silent} ? undef : $ml->div($out,{class=>"Pay"});
}

# ioctl method (used by ExSite to query the module for its functionality)

sub ioctl {
    my $this = shift;
    $_ = shift;           # $_ is the ioctl request

    if (/isRestricted/) {
	return defined $config{Pay}{isRestricted} ? $config{Pay}{isRestricted} : 0;
    }
    elsif (/isService/) {
	return 1;
    }
    elsif (/ModuleName/) {
	return "Payments";
    }
    elsif (/ModuleInfo/) {
	return "This is a tool for managing business accounts, invoices, and e-commerce payments.";
    }
    elsif (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/Summary/) {
	return \&summary;
    }
    elsif (/Access/) {
	return defined $config{Pay}{Access} ? $config{Pay}{Access} : 7;
    }
    elsif (/Dependencies/) {
	# we need the Finance and ID frameworks to manage accounts and payments
	return ["Finance","AddrBook"];
    }
    elsif (/Category/) {
	return [ "Ecommerce", "Applications" ];
    }
    elsif (/Tips/) {
	return \&tips;
    }
    elsif (/ToDo/) {
	return \&todo;
    }    
    elsif (/PublishRule/) {
	return "dynamic";
    }
}

#----------------------------------------------------------------------------
# Everything after this point consists of private methods.

sub get_config {
    my $this = shift;
    $this->{config} = {};
    # copy system config
    foreach my $key (keys %{$config{Pay}}) {
	$this->{config}{$key} = $config{Pay}{$key};
    }
    # copy preferences
    my $site = $share{DB}->this_site();
    if ($site) {
    my $section_id = $site->{section_id};
	my @attr = $share{DB}->fetch_match("attribute",
					   {tablename=>"section",
					    id=>$section_id});
	foreach my $attr (@attr) {
	    my @param = split /\./,$attr->{name};
	    next if shift @param ne "Pay";
	    my $conf = $this->{config};
	    while (my $p = shift @param) {
		if (@param == 0) {
		    $conf->{$p} = $attr->{value};
		}
		elsif (! exists $conf->{$p}) {
		    $conf->{$p} = {};
		    $conf = $conf->{$p};
		}
		else {
		    $conf = $conf->{$p};
		}
	    }
	}
    }
    # unescape newlines in messages
    foreach my $msg (keys %{$this->{config}{message}}) {
	next if ($msg eq "acctcode");
	my $val = $this->{config}{message}{$msg};
	$val =~ s/\\n/\n/g;
	$this->{config}{message}{$msg} = $val;
    }
    foreach my $msg (keys %{$this->{config}{message}{acctcode}}) {
	my $val = $this->{config}{message}{acctcode}{$msg};
	$val =~ s/\\n/\n/g;
	$this->{config}{message}{acctcode}{$msg} = $val;
    }
}

# authorize : does the user have permission to modify the cart?

sub authorize {
    my ($this) = @_;

    if (! $this->{invoice} && ! $this->{account}) {
	# not enough information to decide
	return 0;
    }
    elsif ($this->{invoice}->account->id != $this->{account}->id) {
	# invoice/account mismatch
	return 0;
    }
    elsif ($this->{account}->is_my_account) {
	# user accessing their own account
	return $this->{invoice}->is_editable();
    }
    elsif ($share{DB}->level > 1) {
	my $section_id = $this->get_section_id;
	if (! $share{DB}->owns($section_id)) {
	    # admin is outside their section(s)
	    $this->error("You are not an administrator of this website.");
	    return 0;
	}
	elsif ($this->{config}{scope} eq "local" && 
	       $this->{account}->getdata("section_id") != $section_id) {
	    # account/section mismatch
	    $this->error("This account belongs to a different website.");
	    return 0;
	}
    }
    # no reason to deny
    return 1;
}

######### use Account::setup...

sub get_account {
    my $this = shift;
    my $uid = $this->{config}{always_anonymous} ? 0 : $share{DB}->my_uid();
    if ($uid && ! $this->{admin}) {
	# find account belonging to current user

	my @acct = $share{DB}->fetch_match("account",{uid=>$uid,section_id=>$this->get_section_id},"account_id");
	if (!scalar @acct && $this->{config}{scope} ne "local") {
	    @acct = $share{DB}->fetch_child("account","member",$uid,"account_id");
	}
	if (@acct > 0) {
	    $this->{account} = new Modules::Finance::Account(data=>$acct[-1]);
	}
	if (!$this->{account}) {
	    # create an account for this member
	    my $acct = new Modules::Finance::Account();
	    $acct->setdata("uid",$uid);
	    $acct->setdata("section_id",$this->get_section_id());
	    $acct->setdata("name",scalar $share{DB}->my_name());
	    $acct->save;
	    $this->{account} = $acct;
	}
    }
    elsif ($session{account}) {
	# account has been preset
	$this->{account} = new Modules::Finance::Account(id=>$session{account});
    }
    else {
	# create an anonymous account
	$this->make_anonymous_account();
    }
    return $this->{account};
}

######### use Account::setup_anonymous_account?

sub make_anonymous_account {
    my $this = shift;
    # create an anonymous account
    my $acct = new Modules::Finance::Account();
    $acct->setdata("name","Internet shopper");
    $acct->setdata("uid",0);
    $acct->setdata("section_id",$this->get_section_id());
    $acct->force_save;
    $this->{account} = $acct;
    return $this->{account};
}

########## use Cart::setup???

sub get_invoice {
    my ($this,$invoice_id,%opt) = @_;
    my $invoice;
    my $pg_invoice_id = $this->pgGetPurchaseId();
    $invoice_id or $invoice_id = $pg_invoice_id || $session{invoice};
    my $in = new ExSite::Input;
    if ($invoice_id) {
	$invoice = new Modules::Finance::Cart(id=>$invoice_id);
	if ($invoice->exists) {
	    $this->{account} = new Modules::Finance::Account(id=>$invoice->getdata("account_id"));
	    my $account_section = $this->{account}->getdata("section_id");
	    if ($this->{config}{scope} eq "local" && 
		$account_section != $this->get_section_id) {
		$this->error("System configured for local payments but account's section does not match current site; clearing cart.");	
		$session{invoice} = 0;
		delete $this->{account};
		$invoice = undef;
	    }

	    if ($invoice) {  
		my $member_id = $this->{account}->getdata("uid");
		my $uid = $share{DB}->my_uid || $session{prelim_identity}->{uid};
		if ($member_id && $uid && $member_id != $uid) {
		    if ($pg_invoice_id != $invoice_id && $this->{input}{cart} ne "print") {
			# we didn't get our invoice # from the tx; validate it
			# we are not passing invoice via encryption to print
			# account hijack - abort
			$this->error("Account hijack detected, clearing cart.");
			$session{invoice} = 0;
			delete $this->{account};
			$invoice = undef;
		    } else {
			my $member = $share{DB}->fetch("user",$member_id);
			$share{DB}->do_login_temp($member);
		    }
		}
	    }
	}
    }
	
    if ($this->{config}{member_cart_expiry} && !$invoice) {
	# we are allowed to try to recover an abandoned cart
	my $uid = $share{DB}->my_uid;
	if ($uid) {
	    # user is logged in - see if they have an abandoned cart
	    my $acct = $this->get_account();
	    my @inv = $share{DB}->fetch_match("receivable",{account_id=>$acct->id});
	    if (@inv > 0) {
		$invoice = new Modules::Finance::Cart(data=>$inv[-1]);
		if ($invoice->getdata("status") eq "inactive") {
		    my $t = new ExSite::Time();
		    if ($t->diff($invoice->getdata("date"),"sql_timestamp") > ($this->{config}{member_cart_expiry}/60)) {
			# cart expired
			$invoice = undef;
		    }
		}
	    }
	}
    }

    my $set_session = 1;
    if (! $invoice && 
	$this->{input}{cart} eq "print" &&
	$this->{input}{last_invoice}) {
	# we should actually setup the *previous* invoice
	my $crypt = new ExSite::Crypt;
	my $inv_id = $crypt->decrypt($this->{input}{last_invoice});
	$invoice = new Modules::Finance::Cart(id=>$inv_id);
	$set_session = 0;
    }

    if (! $invoice) {
	# still no invoice;  make one
	my $acct = $this->get_account();
	$invoice = new Modules::Finance::Cart();
	# could use acct->add_receivable, but need to force_save
	my $date = new ExSite::Time;
	$invoice->setdata("type","receivable");
	$invoice->setdata("date",$date->write("sql_timestamp"));
	$invoice->setdata("account_id",$acct->id);
	$invoice->setdata("status","inactive");
	$invoice->setdata("invoice",$opt{invoice_number});
	if ($share{DB}{map}->is_mapped("receivable","uid")) {
	    # record the "seller"
	    $invoice->setdata("uid",$session{receivable_uid}||$share{DB}->my_uid);
	}
	#$invoice->setdata("description") = "";
	$invoice->force_save();
    }
    $session{invoice} = $invoice->id if $set_session;
    $this->{invoice} = $invoice;
    return $this->{invoice};
}

# cancel : remove surcharges, and resume shopping

sub cancel {
    my $this = shift;
    if ($this->authorize()) {
	$this->{invoice}->remove_surcharges();
	return;
    }
    else {
	return $this->error($msg{"Cannot cancel an active invoice."});
    }
}

# checkout1 : step 1: get account info

sub checkout1 {
    my $this = shift;
    my $stat = $this->run_handler("cart_checkout1");
    return $stat if (defined $stat);
    my $out = $ml->div(undef,{class=>"PayCheckoutStep1"});
    my $cust_info = $session{customer_info};
    if ($this->{invoice}->count_items() == 0) {
	# nothing to pay for!  We have lost track of the invoice,
	# possibly because cookies are off.
	$out .= $ml->h1($msg{$this->{config}{heading}{missingcart}});
	$out .= $ml->p($msg{$this->{config}{message}{missingcart}});
	return $out;
    }
    $out .= $this->{invoice}->validate_cart(1); # final validation, could modify cart
    if ($this->{invoice}->count_items() == 0) {
	# validate wiped out our cart contents
	$out .= $ml->p($msg{$this->{config}{message}{emptycart}});
	return $out;
    }
    if ($this->{invoice}->total < 0.01) {
	# nothing owing! We can still check out, but no payment
	# is required.
	$out .= $ml->h2($msg{$this->{config}{heading}{zerototal}});
	$out .= $ml->p($msg{$this->{config}{message}{zerototal}});
    }
    if ($this->{invoice}->allow_payment || $this->{input}{cart} eq "payacct") {
	# skip to payment if we are not collecting contact information
	if (!keys %{$this->{config}{contact_forms}}) {
	    #return $this->payment();   # this fails to add surcharges
	    return $this->checkout2();
	}
   
	$out .= $ml->h2($msg{$this->{config}{heading}{review}});
	my %invopt = (
	    item_descriptions=>$this->{config}{item_descriptions},
	    total=> $msg{$this->{config}{label}{total}},
	    show_as_invoice=>1,
	    );
	$this->get_receivable_display_options(\%invopt);
	$out .= $this->{invoice}->show(%invopt);

	if ($this->{config}{heading}{contact}) {
	    $out .= $ml->h3($msg{$this->{config}{heading}{contact}});
	}

	#------------
=pod
	$out .= $ml->p( $this->{account}->billing_address($this->{config}{primary_contact}), { class=>"puchaserContact" } );

	$out .= $ml->p("Is this you?");

	$out .= $ml->p(
	    $ml->button($ml->span($msg{Yes}).$msg{"proceed with checkout using this information"},{id=>"checkoutConfirmButtonYes",class=>"checkoutConfirmButton"}).
	    $ml->button($ml->span($msg{Yes}).$msg{"but I'd like to make some corrections first"},{id=>"checkoutConfirmButtonMaybe",class=>"checkoutConfirmButton"}).
	    $ml->button($ml->span($msg{No}).$msg{"please checkout as a different person"},{id=>"checkoutConfirmButtonNo",class=>"checkoutConfirmButton"})
	    );
=cut
	#-----------

	my $acctinfo;
	$this->{form} = new ExSite::FormBuilder(action=>$this->link(cart=>"checkout2"),method=>"post");

	my $custom_payment_options = $this->run_handler("Pay_custom_payment_options");
	my $plan = $this->{config}{payment_plan};
	my $options;
	if (ref $plan eq "HASH" && !$custom_payment_options) {
		my $obj = new ExSite::ObjectMeta(type=>"receivable",id=>$this->{invoice}->id);
		$obj->meta_set("Pay.payment_plan",undef);	
		my $items = $this->{invoice}->loaditems();
		my %acctcode;
		while (my $item = $items->next()) {
		my $acctcode_id = $item->getdata("acctcode_id");
		$acctcode{$acctcode_id}++;
		}
		foreach my $name (keys %$plan) {
		next if (keys %acctcode && 
			$plan->{$name}{acctcode} && !$acctcode{$plan->{$name}{acctcode}});
		push @$options, { value => $name, text => $plan->{$name}{label} };
		}
		if (scalar @$options > 1) {
		if (&preference("Pay.payment_plan_instr")) {
		$this->{form}->input(
				 name=>"payment_plan_instr",
				 type=>"preformatted",
				 input=>$ml->p($msg{&preference("Pay.payment_plan_instr")}),
				 );
		}
		$this->{form}->input(type=>"radio",
			prompt=>$msg{"Select a payment plan"},
			options=>$options,
			name=>"plan",
			required=>1
			);
		}
	}
	
	# set form template if defined
	if ($share{Page}) {
	    my $ctemplate = $share{Page}->find("pay_checkout2");
	    if ($ctemplate->get_html()) {
		$this->{form}->template($ctemplate->get_html());
	    }
	}

	# custom questions
	# - you can define arbitrary custom questions to add to the checkout form
	# - the answers are recorded in the invoice description
	if ($this->{config}{checkout_question}) {
	    my $co_questions = $this->{config}{checkout_question};
	    foreach my $q (keys %{$co_questions}) {
		my %qopt = (
		    name=>$q,
		    prompt=>$msg{$co_questions->{$q}{prompt}},
		    type=>$co_questions->{$q}{type} || "text",
		    options=>$co_questions->{$q}{options},
		    size=>$co_questions->{$q}{size},
		    value=>$co_questions->{$q}{value},
		    required=>$co_questions->{$q}{required},
		    );
		$this->{form}->input(%qopt);
	    }
	}

	# account name
	my $acctname = $this->{account}->getdata("name");
	my $anon_acctname = $config{Finance}{anonymous_account_name} || "Internet Shopper";
	if ($acctname =~ /$anon_acctname/i) {
	    $acctname = "";
	    $this->{account}->setdata("name","");
	}
	if (! $acctname && (ref $cust_info) =~ /HASH/) {
	    $acctname = $cust_info->{name};
	}

	my %contact = &keywise("type",scalar $share{DB}->fetch_match("contact",{account_id=>$this->{account}->id},"contact_id"));
	$this->{form}->input(name=>"acctname",
			     prompt=>$msg{&preference("Pay.name_label") || "Name"},
			     type=>"text",
			     size=>40,
			     required=>1,
			     value=>$acctname);

	my $uid = $share{DB}->my_uid();
	if (! $session{disable_change_account}) {
	    if ($acctname && $uid && $this->{account}->getdata("uid")==$uid && !$share{use_prelim_identity}) {
		# defaulting to member's account - verify that this is okay
		$this->{form}->input(
		    name=>"wrong_acct_warning",
		    type=>"preformatted",
		    input=>$ml->p(&substitute($msg{"<strong>Is this the wrong account?</strong> You are logged in as <em>[[name]]</em>. If this purchase should be billed to a different person, <a href='[[url]]'>click here to setup a new account</a> for this purchase.  Otherwise, confirm/correct the contact information for [[name]] below:"},{name=>$acctname,url=>$this->link(cart=>"chacct")}),{class=>"PayAccountWarning"}),
		    );
	    }
	    elsif ($acctname && ! $uid && $this->{account}->get_contact()) {
		# we already have contact info, but this is not a member
		# defaulting to previous purchaser's account - verify that this is okay
		$this->{form}->input(
		    name=>"wrong_acct_warning",
		    type=>"preformatted",
		    input=>$ml->p(&substitute($msg{"<strong>Is this the wrong account?</strong> You recently made a purchase as <em>[[name]]</em>. If this new purchase should be billed to a different person, <a href='[[url]]'>click here to setup a new account</a> for this purchase.  Otherwise, confirm/correct the contact information for [[name]] below:"},{name=>$acctname,url=>$this->link(cart=>"chacct")}),{class=>"PayAccountWarning"}),
		    );
	    }
	}

	my %contact = &keywise("type",scalar $share{DB}->fetch_match("contact",{account_id=>$this->{account}->id},"contact_id"));
	# prepopulate base contact form with some contact info
	my $primary_contact = $this->{config}{primary_contact};
	my $default_contact;
	if ($contact{$primary_contact}) {
	    my $cp = new Modules::ID::Contact(data=>$contact{$primary_contact});
	    $default_contact = $cp->get_info();
	}
	elsif ($contact{home}) {
	    my $cp = new Modules::ID::Contact(data=>$contact{home});
	    $default_contact = $cp->get_info();
	}
	elsif (my @types = keys %contact) {
	    my $c = $contact{$types[0]};
	    my $cp = new Modules::ID::Contact(data=>$contact{$types[0]});
	    $default_contact = $cp->get_info();
	}	
	else {
	    $default_contact = $cust_info;
	}

	$this->contact_form(
			    $this->{config}{contact_forms}{$primary_contact},
			    $primary_contact,
			    $default_contact
			    );
	foreach my $ctype (keys %{$this->{config}{contact_forms}}) {
	    next if ($ctype eq $primary_contact);
	    $this->contact_form(
				$this->{config}{contact_forms}{$ctype},
				$ctype,
				$contact{$ctype}
				);
	}
	$this->{form}->input(type=>"preformatted",name=>"contact_message",input=>$ml->p($msg{$this->{config}{message}{contact}}));

	# are there any active coupon codes we should ask for?
	my $section = $share{DB}->this_site;
	my $section_id = $section ? $section->{section_id} : 0;
	my @sc = $share{DB}->get_query("get our surcharges",$section_id);
	if ($this->{config}{giftcard} || scalar @sc > 0) { 
	    my $cc_prompt = $this->{config}{message}{coupon_code_prompt} ||
		"If you have a promotional code or gift card, you can enter it here:";
	    $this->{form}->input(type=>"text",name=>"couponcode",prompt=>$msg{$cc_prompt});
	}

	my $txt_continue_checkout = $this->{config}{button}{continue_checkout} || "Continue";    
	my $txt_cancel_checkout = $this->{config}{button}{cancel_checkout} || "Cancel";    
	(tied %msg)->nohighlight();
	my $ui = &get_obj("UI");
	$this->{form}->set("buttons",
			   $ml->p(
			       $ui->Button(
				   type=>"submit",
				   label=>$msg{$txt_continue_checkout},
				   tone=>"good",
				   id=>"CartContinueButton",
			       )."&nbsp;".
			       $ui->Button(
				   label=>$msg{$txt_cancel_checkout},
				   id=>"CartCancelButton",
				   tone=>"bad",
				   url=>$this->link(cart=>"view"),
			       ),
			       {class=>"CartCheckoutButtons"})
			   );

#	$this->{form}->set("buttons",
#			   $ml->p(
#			       $ml->input(undef,{type=>"submit",value=>$msg{$txt_continue_checkout},id=>"CartContinueButton"})."&nbsp;".
#			       $ml->input(undef,{type=>"button",value=>$msg{$txt_cancel_checkout},id=>"CartCancelButton",class=>"btn",onclick=>"location.href='".$this->link(cart=>"view")."'"}),
#			       {class=>"CartCheckoutButtons"})
#			   );

	(tied %msg)->restore();	
	$this->run_handler("Pay_append_to_contact_form"); # eg. custom validators?
	$out .= $this->{form}->make();
	$out .= $ml->p($msg{$this->{config}{message}{final}},{class=>"Pay_final"});
    }
    else {
	$out .= $this->error($msg{"Invalid invoice: starting new invoice."});
	delete $this->{invoice};
	$session{invoice} = 0;
	# start over
	$this->get_invoice();
	$out .= $this->view();
    }
    return $out;
}

# checkout2 : step 2: add surcharges, and jump to payment screen

sub checkout2 {
    my $this = shift;
#    return &ShowHash($this->{input});
    my $stat = $this->run_handler("cart_checkout2");
    return $stat if (defined $stat);
    my $out = $ml->div(undef,{class=>"PayCheckoutStep2"});
    my $cust_info = $session{customer_info};
    if ($this->{invoice}->count_items == 0) {
	# nothing to pay for!  We have lost track of the invoice,
	# probably because cookies are off.
	$out = $ml->h1($msg{$this->{config}{heading}{missingcart}});
	$out .= $ml->p($msg{$this->{config}{message}{missingcart}});
    }
    elsif ($this->{invoice}->allow_payment) {

	# save contact info

	if ($this->{input}{acctname}) {
	    # form data exists
	    $out .= $this->save_contact_info();
	}

	my $acctname = $this->{account}->getdata("name");
	if (! $acctname || $acctname =~ /Internet shopper/i) {
	    # no purchaser information!
	    $out .= $this->error($msg{"Please enter your name and contact information"});
	    $out .= $ml->form(
			      $ml->input(undef,{type=>"hidden",name=>"submitaction",value=>$msg{Checkout}}).
			      $ml->input(undef,{type=>"submit",name=>"tmp",value=>$msg{Retry}}),
			      {method=>"post",action=>$this->link()}
			      );
	    return $out;
	}

	# custom questions
	if ($this->{config}{checkout_question}) {
	    my $co_questions = $this->{config}{checkout_question};
	    my @info;
	    foreach my $q (keys %{$co_questions}) {
		if ($this->{input}{$q}) {
		    push @info,  $co_questions->{$q}{prompt}.": ".
			$this->{input}{$q};
		}
	    }
	    $this->{invoice}->setdata("description",join("; ",@info));
	    $this->{invoice}->save;
	}

	if (&OnError()) {
	    # problems with saving contacts, better abort
	    $out .= $ml->h3("Please correct the the following:");
	    $out .= &ExSite::Config::show_diagnostics();
	    $out .= $ml->p($ml->a($msg{Back},{href=>"javascript:history.back()"}));
	    return $out;
	}

	# now settle the invoice
	
	if (my $plan = $this->{input}{plan}) {
	    # recurring payment plan selected
	    my $obj = new ExSite::ObjectMeta(type=>"receivable",id=>$this->{invoice}->id);
	    $obj->meta_set("Pay.payment_plan",$this->{input}{plan});
	    $obj->save();
	}
	if ($this->{config}{giftcard}) {
	    $out .= $this->process_giftcard();
	}
	my $sc_count = $this->{invoice}->finalize($this->{input}{couponcode});
	$sc_count += $this->run_handler("receivable_finalize",$this->{invoice});

	if (&OnError()) {
	    # problems with finalizing, better abort
	    $out .= $ml->h3("Please correct the the following:");
	    $out .= &ExSite::Config::show_diagnostics();
	    $out .= $ml->p($ml->a($msg{Back},{href=>"javascript:history.back()"}));
	    return $out;
	}

	if ($this->{config}{skip_confirm} && # confirmation screen is optional
	    $sc_count == 0 &&                # if no surcharges
	    !$this->{giftcard_discount}) {   # and no giftcard changes to total
	    # invoice hasn't changed since last screen;
	    # can skip the confirm step and go straight to payment
	    return $this->payment();
	}

	$out .= $ml->h1($msg{$this->{config}{heading}{confirm}});
	$out .= "<!--content(checkout2_header)-->";

	$out .= $ml->p($this->{account}->billing_address());
	$out .= $this->get_text_of_invoice(
	    item_descriptions=>$this->{config}{item_descriptions},
	    show_as_invoice=>1,
	    );

	$this->{form} = new ExSite::FormBuilder(action=>$this->link(cart=>"payment"),method=>"post");

	(tied %msg)->nohighlight();
	
	if (my $plan = $this->{input}{plan}) {
	    my $num_payments = &preference("Pay.payment_plan.$plan.num_payments");
	    my $tot = sprintf "%.02f", $this->{invoice}->total / $num_payments;
	    $this->{form}->input(type=>"preformatted",name=>"payment_plan_message",
				 input=>$ml->p(&substitute($msg{"Under your selected payment plan, your payment will be for [[currency]][[tot]]."},
							   {currency=>$config{report}{currency_char},tot=>$tot})));
	}

	my $txt_finish = $this->{config}{button}{finish} || "Finish order";
	my $txt_cancel_free = $this->{config}{button}{cancel_free} || "Cancel";
	my $txt_paynow = $this->{config}{button}{paynow} || "Pay now";    
	my $txt_cancel_payment = $this->{config}{button}{cancel_payment} || "Cancel payment";
	if ($this->{invoice}->total < 0.01) {
	    # $0 order - change button labels
	    $this->{form}->set("buttons",
			       $ml->p(
				   $ml->input(undef,{type=>"submit",name=>"paynow",value=>$msg{$txt_finish},id=>"CartPayButton"})."&nbsp;".
				   $ml->input(undef,{type=>"button",name=>"paynow",value=>$msg{$txt_cancel_free},id=>"CartCancelButton",onclick=>"location.href='".$this->link(cart=>"view")."'"}),
				   {class=>"CartCheckoutButtons"})
			       );
	}
	else {
	    $this->{form}->set("buttons",
			       $ml->p(
				   $ml->input(undef,{type=>"submit",name=>"paynow",value=>$msg{$txt_paynow},id=>"CartPayButton"})."&nbsp;".
				   $ml->input(undef,{type=>"button",name=>"paynow",value=>$msg{$txt_cancel_payment},id=>"CartCancelButton",onclick=>"location.href='".$this->link(cart=>"view")."'"}),
				   {class=>"CartCheckoutButtons"})
			       );
	}
	(tied %msg)->restore();			   
	$out .= $this->{form}->make();
         # optional help info on payment procedure	 
         $out .= "<!--content(ShoppingCartHelpPayment)-->\n";	 
    }
    else {
	$out .= $this->error($msg{"Invalid invoice: starting new invoice."});
	delete $this->{invoice};
	$session{invoice} = 0;	
	# start over
	$this->get_invoice();
	$out .= $this->view();
    }
    return $out;
}

sub process_giftcard {
    my $this = shift;
    my $out;
    my $db = $share{DB};
    my $mod = &get_module("Giftcard"); # dynamically load giftcard
    $this->{giftcard_discount} = 0;
    if ($mod) {
	my @giftcard;
	my $code = $this->{input}{couponcode};
	if ($code) {
	    push @giftcard, $db->fetch_match("giftcard",{code=>$code});
	    if (scalar @giftcard == 0) {
		# maybe they didn't type it in perfectly
		my $newcode = $code;
		$newcode =~ s/[^\d]//g;
		if ($newcode ne $code) {
		    my @code = split //,$code;
		    my $ipos = 1;
		    $code = undef;
		    while (scalar @code) {
			$code .= shift @code;
			$code .= "-" if ($ipos % 4 == 0 && scalar @code);
			$ipos++;
		    }
		    push @giftcard, $db->fetch_match("giftcard",{code=>$code});
		}
	    }
	}
	push @giftcard, $db->fetch_match("giftcard",{account_id=>$this->{account}->id},["expiry","giftcard_id"]);
	if (@giftcard > 0) {
	    my %itemval;
	    my $inv = $this->{invoice};
	    my $items = $inv->loaditems();
	    my @items;
	    while (my $item = $items->next) {
		my $val = $item->subtotal();
		push @items, $item if ($val > 0.00);
		$itemval{$item->id} = $val;
	    }
	    foreach my $gc (@giftcard) {
		my $section = $share{DB}->this_site();
		next if ($section && $gc->{section_id} != $section->{section_id});
		my $remainval = $gc->{value};
		next if ($remainval < 0.01);
		if ($gc->{expiry} && $gc->{expiry} !~ /^0/) {
		    my $t = new ExSite::Time($gc->{expiry},"sql_date");
		    next if ($t->in_past); # expired
		}
		$items->reset;
		foreach my $item (@items) {
		    next if ($gc->{acctcode_id} && $gc->{acctcode_id} != $item->getdata("acctcode_id"));
		    next if ($itemval{$item->id} < 0.01);
		    my $amt = ($itemval{$item->id} > $remainval) ? $remainval : $itemval{$item->id};
		    $itemval{$item->id} -= $amt; # don't dicount items twice
		    $remainval -= $amt;          # don't discount more than card
		    my $name = $gc->{description} || "Gift Card discount";
		    $inv->add_item({
			item=>$msg{$name},
			description=>&substitute($msg{"discounted [[item]]"},{item=>$item->getdata("item")}),
			cost=> -$amt,
			acctcode_id=>$item->getdata("acctcode_id"),
			note=>"giftcard ".$gc->{code},
				   });
		    $out .= $ml->p(&substitute($msg{"Applied discount of [[amount]] using gift card [[code]]."},{amount=>$amt,code=>$gc->{code}}));
		    $this->{giftcard_discount}++;
		    last if ($remainval < 0.01);
		}
		if ($remainval != $gc->{value}) {
		    # used this card - update the card
		    my $totalused = $gc->{value} - $remainval;
		    $gc->{notes} .= "\nUsed \$$totalused on invoice ".$inv->id;
		    $gc->{value} = $remainval;
		    $gc->{account_id} = $inv->getdata("account_id");
		    $db->update("giftcard",$gc);


    ### report card remainders


		}
	    }
	}
    }
    return $out;
}

sub save_contact_info {
    my $this = shift;
    my $out;
    # 1) update account info
    if ($this->{input}{acctname} ne $this->{account}->getdata("name")) {
	$this->{account}->setdata("name",$this->{input}{acctname});
	$this->{account}->force_save;
    }
    # 2) update/create account contact info
    my @contact_records = keys %{$this->{config}{contact_forms}};
    my $contact_records = join "|",@contact_records;
    my %contact = &keywise("type",scalar $share{DB}->fetch_match("contact",{account_id=>$this->{account}->id},"contact_id"));
    foreach my $dat (keys %{$this->{input}}) {
	if ($dat =~ /(\w+)_($contact_records)$/) {
	    my $cn = $1; 
	    # we use force_save, below, so don't allow user to set foreign keys
	    next if ($cn eq "contact_id");
	    my $ct = $2;
	    next if ($cn eq "type");
	    if ($1 !~ /^provstate$/ || $this->{input}{$dat} !~ /^==/) {
		# don't save select hints
		$this->{input}{$dat} =~ s/^\s*//;
		$this->{input}{$dat} =~ s/\s*$//;
		$contact{$ct}{_info}{$cn} = $this->{input}{$dat};
	    }
	}
    }
    # save primary contact info 
    my @cdata = $share{DB}->fetch_match("contact",{account_id=>$this->{account}->id,type=>$this->{config}{primary_contact}});
    my $primary_contact;
    if (scalar @cdata) {
	$primary_contact = new Modules::ID::Contact(data=>$cdata[0]);
    }
    else {
	$primary_contact = new Modules::ID::Contact();
	$primary_contact->setdata("account_id",$this->{account}->id);
	$primary_contact->setdata("type",$this->{config}{primary_contact});
	my $privacy = $this->{config}{contact_privacy}{$this->{config}{primary_contact}} || 5;
	$primary_contact->setdata("privacy",$privacy);
    }
    $primary_contact->set_contact_data($contact{$this->{config}{primary_contact}}{_info});

    # copy organization to contact info from member record if applicable
#    if (my $member = $this->{account}->get_user()) {
#        if (my $org = $member->getdata("organization")) {
#            my $name = $this->{account}->name();
#            # account name does not already contain organization
#            if (!$primary_contact->getdata("name") && $name !~ /$org/) {
#                $primary_contact->setdata("name",$org);
#            }
#        }
#    }

    if ($primary_contact->force_save()) {
	# now save secondary contact info
	foreach my $ctype (keys %{$this->{config}{contact_forms}}) {
	    my $c = new Modules::ID::Contact();
	    next if ($ctype eq $this->{config}{primary_contact});
	    if ($this->{input}{"copy_$ctype"}) {
		# use primary contact info
		# but is there a pre-existing record for this ctype?
		my @contact = $share{DB}->fetch_match("contact",{account_id=>$this->{account}->id,type=>$ctype});
		if (@contact > 0) {
		    # there are pre-existing contact records of this 
		    # type - delete them
		    foreach my $cont (@contact) {
			$c->setup(data=>$cont);
			$c->delete();
		    }
		}
	    }
	    else {
		my @cdata = $share{DB}->fetch_match("contact",{account_id=>$this->{account}->id,type=>$ctype});
		my $contact;
		if (scalar @cdata) {
		    $contact = new Modules::ID::Contact(data=>$cdata[0]);
		}
		else {
		    $contact = new Modules::ID::Contact();
		    $contact->setdata("account_id",$this->{account}->id);
		    $contact->setdata("type",$ctype);
		    my $privacy = $this->{config}{contact_privacy}{$ctype} || 5;
		    $contact->setdata("privacy",$privacy);
		}
		$contact->set_contact_data($contact{$ctype}{_info});
		if ($c->ok && ! $c->force_save()) {
		    $this->error(
			&substitute(
			     "Failed to save [[type]] information.",
			     {type=>$ctype}
			)
			);
		}
	    }		    
	}
    }
    else {
	$this->error(
	    &substitute(
		 "Failed to save [[type]] information.",
		 {type=>$this->{config}{primary_contact}}
	    )
	    );
    }
    return $out;
}

# checkout_admin : alternate checkout for control panels

sub checkout1_admin {
    my $this = shift;
    my $out;
    my $cust_info = $session{customer_info};
    my $inv = $this->get_invoice;

    if ($inv->count_items() == 0) {
	$out .= $this->error("No valid invoice/cart found.");
    }
    if ($inv->total < 0.01) {
	# nothing owing! We can still check out, but no payment
	# is required.
	$out = $ml->h2($msg{$this->{config}{heading}{zerototal}});
	$out .= $ml->p($msg{$this->{config}{message}{zerototal}});
    }
    if ($inv->allow_payment) {
	if ($this->{input}{account_id} || $this->{post}{acctname}) {
	    # proceed to next step if account details are present
	    return $this->checkout2_admin();
	}
   
	$out .= $ml->h1($msg{$this->{config}{heading}{review}});
	$out .= $this->get_text_of_invoice(
	    item_descriptions=>$this->{config}{item_descriptions},
	    show_as_invoice=>1, # not as a cart
	    );
	my $acctinfo;
	$this->{form} = new ExSite::FormBuilder(action=>$this->link(cart=>"checkout2"),method=>"post");
	
	my $acctname = $this->{account}->getdata("name");
	if ($acctname =~ /Internet shopper/i) {
	    $acctname = "";
	    $this->{account}->setdata("name","");
	}
	if (! $acctname && (ref $cust_info) =~ /HASH/) {
	    $acctname = $cust_info->{name};
	}

	# look for existing accounts that might match
	### FIXME: better account name matching
	my %match;
	if ($acctname) {
	    if ($acctname =~ /, /) {
		# last, first
		my @name = split /, /,$acctname;
		$match{name} = '%'.$name[0].'%';
	    }
	    elsif ($acctname =~ /\w \w/) {
		# first last
		my @name = split /\s+/,$acctname;
		pop @name if (! $name[-1]); # in case of trailing whitespace
		$match{name} = '%'.$name[-1].'%';
	    }
	    else {
		$match{name} = '%'.$acctname;
		$match{name} =~ s/,.+$/\%/;
	    }
	}
	$match{section_id} = $this->{section_id} if ($this->{section_id});
	my @acct;
	my $acctlist = $this->run_handler("Pay_find_matching_accounts",\%match);
	if (ref $acctlist eq "ARRAY") {
	    @acct = @$acctlist;
	}
	elsif ($acctname) {
	    @acct = $share{DB}->fetch_match("account",\%match);
	}
	my $list;
	if (scalar @acct > 1) {
	    $out .= $ml->h2("Select an existing account for ".$ml->em($acctname).":");
	    ### FIXME: order accounts by relevance?
	    foreach my $acct (@acct) {
		my $account = new Modules::Finance::Account(data=>$acct);
		my $aid = $account->id;
		# ignore current account
		next if ($aid eq $inv->getdata('account_id'));
		# ignore retired accounts
		next if ($account->getdata('code') =~ /^use account \d+$/i);
		my @class = ("accountMatch");
		my $acctname = $ml->a("$aid: ".$account->name,
				      {href=>$this->link(account_id=>$aid)});
		if ($account->getdata("uid")) {
		    $acctname .= " Member ID: ".$account->showdata("uid");
		    push @class, "isMember";
		}
		my $c = $account->get_contact();
		if ($c && $c->defined) {
		    my $city = $c->getdata("city");
		    my $prov = $c->getdata("provstate");
		    if ($city && $prov) {
			$acctname .= " ($city, $prov)";
		    }
		    elsif ($city || $prov) {
			$acctname .= " ($city$prov)";
		    }
		    push @class,"hasContact";
		}
		$list .= $ml->li($acctname, {class=>join(" ",@class)});
	    }
	}
	else {
	    $list .= $ml->li("No similar accounts found. You can select an account ID, or start a new account.");
	}
	$list .= $ml->li($ml->form("Other Account ID: ".
				   $ml->input(undef,{type=>"text",name=>"account_id"}).
				   $ml->input(undef,{type=>"hidden",name=>"section_id",value=>$this->{input}{section_id}}).
				   $ml->input(undef,{type=>"hidden",name=>"cart",value=>$this->{input}{cart}}).
				   $ml->input(undef,{type=>"submit",value=>"Submit"}),
				   {method=>"get"}));
	$out .= $ml->ul($list,{class=>"matchingAccounts"});
	$out .= $ml->h2("Or, start a new account:");
	my %contact = &keywise("type",scalar $share{DB}->fetch_match("contact",{account_id=>$this->{account}->id},"contact_id"));
	$this->{form}->input(name=>"acctname",
			     prompt=>$msg{&preference("Pay.name_label") || "Name"},
			     type=>"text",
			     size=>40,
			     required=>1,
			     value=>$acctname);

	my %contact = &keywise("type",scalar $share{DB}->fetch_match("contact",{account_id=>$this->{account}->id},"contact_id"));
	# prepopulate base contact form with some contact info
	my $primary_contact = $this->{config}{primary_contact};
	my $default_contact;
	if ($contact{$primary_contact}) {
	    $default_contact = $contact{$primary_contact};
	}
	elsif ($contact{home}) {
	    $default_contact = &clone($contact{home});
	    $default_contact->{contact_id} = undef;
	    $default_contact->{type} = $this->{config}{primary_contact};
	}
	elsif (my @types = keys %contact) {
	    my $c = $contact{$types[0]};
	    $default_contact = &clone($c);
	    $default_contact->{contact_id} = undef;
	    $default_contact->{type} = $this->{config}{primary_contact};
	}	
	else {
	    $default_contact = $cust_info;
	}

	$this->contact_form(
			    $this->{config}{contact_forms}{$primary_contact},
			    $primary_contact,
			    $default_contact
			    );
	foreach my $ctype (keys %{$this->{config}{contact_forms}}) {
	    next if ($ctype eq $primary_contact);
	    $this->contact_form(
				$this->{config}{contact_forms}{$ctype},
				$ctype,
				$contact{$ctype} || $cust_info
				);
	}
	$this->{form}->input(type=>"preformatted",name=>"contact_message",input=>$ml->p($msg{$this->{config}{message}{contact}}));

	# are there any active coupon codes we should ask for?
	my $section = $share{DB}->this_site;
	my $section_id = $section ? $section->{section_id} : 0;
	my @sc = $share{DB}->get_query("get our surcharges",$section_id);
	if (scalar @sc > 0) { 
	    $this->{form}->input(type=>"text",name=>"couponcode",prompt=>$msg{"If you have a promotional code, you can enter it here:"});
	}
	
	(tied %msg)->nohighlight();	
	$this->{form}->set("buttons",
			   $ml->input(undef,{type=>"submit",value=>$msg{"Continue"}})."&nbsp;".
			   $ml->input(undef,{type=>"button",value=>$msg{"Cancel"},onclick=>"location.href='".$this->link(cart=>"view")."'"})
			   );
	(tied %msg)->restore();			   
	$out .= $this->{form}->make();
	$out .= $ml->p($msg{$this->{config}{message}{final}},{class=>"Pay_final"});
    }
    else {
	$out .= $this->error($msg{"Permission denied: this invoice is not editable."});
	$out .= $ml->p($ml->a("View invoice.",{href=>$this->link(cart=>undef,inv=>$inv->id)}));
    }
    return $out;
}

sub checkout2_admin {
    my $this = shift;
    my $out;
    my $cust_info = $session{customer_info};
    if ($this->{invoice}->count_items == 0) {
	$out .= $this->error("No valid invoice/cart found.");
    }
    elsif ($this->{invoice}->allow_payment) {
	if ($this->{input}{account_id}) {
	    # assign this invoice to an existing account
	    $this->{input}{account_id} =~ /(\d+)/;
	    my $new_acct_id = $1;
	    if ($new_acct_id) {
		my $old_acct_id = $this->{invoice}->getdata("account_id");
		$this->{invoice}->setdata("account_id",$new_acct_id);
		if ($this->{invoice}->save) {
		    # fix account
		    my $oldacct = $this->{account};
		    if (! $oldacct || $oldacct->id != $old_acct_id) { 
			$oldacct = new Modules::Finance::Account(id=>$old_acct_id);
		    }
		    $this->{account} = new Modules::Finance::Account(id=>$new_acct_id);
		    # if old account is now an orphan, delete it
		    my $acctch = $oldacct->get_children();
		    my $delacct = 1;
		    foreach my $ch (%$acctch) {
			if ($acctch->{$ch} && $acctch->{$ch}->count()) { 
			    $delacct = 0; last; 
			}
		    }
		    if ($delacct) {
			# don't delete the account, just mark it as moved
			$oldacct->setdata("code","use Account $new_acct_id");
			$oldacct->save();
		    }
		}
		else {
		    $out .= $this->error("Invalid account ID - please enter an account number.");
		}
	    }
	    else {
		$out .= $this->error("failed to set account");
	    }
	}
	elsif (keys %{$this->{post}}) {
	    # new contact info
	    $out .= $this->save_contact_info();
	}

	if (&OnError()) {
	    # problems with saving contacts, better abort
	    $out .= $ml->h3("Please correct the the following:");
	    $out .= &ExSite::Config::show_diagnostics();
	    $out .= $ml->p($ml->a($msg{Back},{href=>"javascript:history.back()"}));
	    return $out;
	}

	# now settle the invoice

	my $sc_count = $this->{invoice}->finalize($this->{input}{couponcode});
	my $stat = $this->run_handler("receivable_finalize",$this->{invoice});

	if (&OnError()) {
	    # problems with finalizing, better abort
	    $out .= $ml->h3("Please correct the the following:");
	    $out .= &ExSite::Config::show_diagnostics();
	    $out .= $ml->p($ml->a($msg{Back},{href=>"javascript:history.back()"}));
	    return $out;
	}

	# no problems, activate the invoice, and go to payment
	if ($this->{invoice}->activate()) {
	    my $invid = $this->{invoice}->id();
	    $out .= $ml->p("Invoice $invid has been entered into the system.");
	    $out .= $ml->p(
		$this->{account}->name . $ml->br . 
		$this->{account}->billing_address()
		);
	    $out .= $this->get_text_of_invoice(
		item_descriptions=>$this->{config}{item_descriptions}
		);
	    if ($this->{invoice}->total < 0.01) {
	        my $stat = $this->{invoice}->complete_sale();
		$out .= $stat if ($stat);
	    }
	    else {
		$out .= $ml->p(
		    $ui->Button(label=>"Record Payment",url=>"$config{server}{CGIpath}/$config{prog}{ctrlpanel}/Pay?section_id=$this->{section_id}&inv=$invid")
		    );
	    }
	    $this->end_payment_session();
	}
    }
    else {
	$out .= $this->error($msg{"Invalid invoice: starting new invoice."});
	delete $this->{invoice};
	$session{invoice} = 0;	
	# start over
	$this->get_invoice();
	$out .= $this->view();
    }
    return $out;
}

sub cancel_checkout {
    my $this = shift;
	# set the invoice status to inactive
	# allows user to resume editing invoice
	$this->{invoice}->setdata("status","inactive");
	$this->{invoice}->remove_surcharges();	
	$this->{invoice}->save();
	return undef;
}

# recheckout: restart an admin checkout process on an inactive invoice

sub recheckout {
    my ($this,$invid) = @_;
    my $inv = $this->get_invoice($invid);
    if ($inv->getdata("status") eq "inactive") {
	$session{invoice} = $invid;
	return $this->checkout1_admin();
    }
    else {
	return $this->error("Cannot checkout invoice $invid; it is not inactive.");
    }
}

sub change_acct {
    my $this = shift;
    if ($this->{invoice}) {
	# disconnect the invoice from the user's current account, and
	# reattach it to a new account
	$this->make_anonymous_account();
	$this->{invoice}->setdata("account_id",$this->{account}->id);
	$this->{invoice}->save;
    }
}

# payment

sub payment {
    my $this = shift;
    my $out = $ml->div(undef,{class=>"PayCheckoutStep3"});
    my %contact;
    if ($this->{invoice}->allow_payment && $this->{invoice}->count_items() > 0) {
	if ($this->{invoice}->total < 0.01) {
	    # nothing owed!  Go straight to receipt.
	    return $this->receipt();
	}
	my $in = $this->{input};
	my $method = $this->run_handler("Pay_methods") ||
	    $session{payment_method} ||
	    $this->{config}{payment_method} || 
	    "ecommerce";
	if (ref $method eq "ARRAY") {
	    # multiple payment methods supported
	    if ($in->{method}) {
		# a payment method was selected
		my %allowed_methods = map { $_ => 1 } @$method;
		if ($allowed_methods{$in->{method}}) {
		    $method = $in->{method};
		}
		else {
		    # not valid
		    $method = "NOT ALLOWED";
		}
	    }
	    else {
		# make a menu of payment methods
		my @item;
		foreach my $m (@$method) {
		    push @item, $ml->li(
					$ml->a(
					    $msg{$this->{config}{message}{"method_$m"}},
					    {href=>$this->link(cart=>"payment",method=>$m)}
			                )
					);
		}
		$out .= $ml->p($msg{$this->{config}{message}{method}});
		$out .= $ml->ul(join("\n",@item),{class=>"Pay_method"});
		$out .= $this->{config}{payment_method_help};
		return $out;
	    }
	}
	if ($method eq "ecommerce") {
	    $out .= $this->payment_ecommerce();
	}
	elsif ($method eq "invoice") {
	    $out .= $this->payment_invoice();
	}
	else {
	    $out .= $ml->p($msg{"Invalid payment method selected."});
	}
    }
    else {
	$out .= $this->error($msg{"Invalid invoice or payment has already been processed. Please contact website support for more information."});    
    }
    return $out;
}

# payment

sub payment_ecommerce {
    my $this = shift;
    my $out;

    # set the invoice status to processing
    if ($this->{invoice}->getdata("status") eq "inactive") {
	$this->{invoice}->setdata("status","processing");
	$this->{invoice}->save();
    }

    # get billing contact
    my $account = $this->{invoice}->account();
    my $contact = $this->{config}{primary_contact};
    if ($this->{config}{contact_forms}{billing}) {
	$contact = "billing";	
    }
    
    my $acct_contact;
    # handler to retrieve contact to be passed to gateway
    if (my $stat = $this->run_handler("Pay_gateway_contact", $account)) {
	$acct_contact = $stat;
    } 
    else {
	my $c = $account->get_contact($contact);
	$acct_contact = $c? $c->get_info() : {};
    }
    
    my %pay = (
	       description => $this->{invoice}->description || "Online Purchase",
	       amount => $this->{invoice}->total(),
	       purchase_id => $this->{invoice}->id(),
	       primary_contact => $acct_contact,
	       account => $account,
	       );

    if ($this->pgSetup(%pay)) {
	if ($this->pgSetupTransaction(%pay)) {
	    $out .= $ml->p($msg{"Processing..."});
	    if ($out .= $this->pgPostTransaction()) {
		# we have posted the new transaction to the gateway
		# and now must wait for a reply
		
		# payment gateway module will probably redirect
		# to the payment screens...
		return $out;
		    
	    }
	    else {
		my $error = $this->pgStatus();
		$out .= $this->error($msg{"Failed to post transaction"}.": $error");
	    }
	}
	else {
	    my $error = $this->pgStatus();
	    $out .= $this->error($msg{"Failed to setup transaction"}.": $error");
	}
    }
    else {
	my $error = $this->pgStatus();
	$out .= $this->error($msg{"Failed to connect to payment gateway"}.": $error");
    }
    return $out;
}

# payment

sub payment_invoice {
    my $this = shift;
    my $out;

    # set the invoice status to active
    if (! $this->{invoice}->activate()) {
	$out .= &ExSite::Config::show_diagnostics();
	$out .= $ml->p("Failed to activate invoice.");
	return $out;
    }
    
    $out .= $this->run_handler("Pay_payment_by_invoice");
    my $invoice = $this->show_order_as_invoice();
    $out .= $invoice;
    $out .= $this->print_friendly_link();

    my $id = $this->{invoice}->id();
    my $name = $this->{account}->name();
    my $seller = &preference("Pay.seller_email") || $this->{config}{seller_email} || $share{DB}->owner_email();

    my $notify_purchaser = defined $this->{config}{notify_purchaser} ?
		$this->{config}{notify_purchaser} : 1;
    my $notify_seller = defined $this->{config}{notify_seller} ?
		$this->{config}{notify_seller} : 1;

    my $message;
    if ($notify_seller) {
	$message = $ml->p("An order has been placed by $name\nfor the following:").$ml->hr;
	$message .= $invoice;
	$message .= $ml->hr.$ml->p("The customer will pay off-line.");
	my $to = $this->{config}{notification_email} || $seller;
	my $subj = $this->{config}{subject}{notify_seller} || "Order received";
	&ExSite::Mail::send(to=>$to,from=>$seller,subject=>$subj,body=>$message);
    }

    if ($notify_purchaser) {
	my $payment_instr;
	if ($share{Page}) {
	    # look for customized content object containing payment instructions
	    $payment_instr = $this->find_receivable_template("payment_instructions");
	}
	$message = $ml->p($msg{"Thank you for your order."});
	$message .= $invoice;
	my $purchaser = $this->{account}->email($this->{config}{primary_contact});
	if ($purchaser) {
	    my $subj = $this->{config}{subject}{notify_purchaser} || "Thank you for your order";
	    &ExSite::Mail::send(to=>$purchaser,from=>$seller,subject=>$msg{$subj},body=>$message);
	}
    }
    (tied %msg)->restore();
    
    # stop working on this invoice
    $session{last_invoice} = $session{invoice};
    $this->end_payment_session();
    return $out;
}

# receipt

sub receipt {
    my ($this,%opt) = @_;
    my $out;

    my $receipt_page = $this->pgGetReceiptPageId();
    if ($receipt_page && $share{Page}->id() != $receipt_page) {
	# relay data posted from gateway to redirected receipt page
	my @postvars = keys %{$this->{post}};
	my %relay;
	foreach my $var (@postvars) {
	    $relay{$var} = $this->{input}{$var};
	}
	my $uri = new ExSite::URI;
	$uri->query(%relay,_id=>$receipt_page);
	$uri->plaintext();
	&redirect($uri->write_full());
	return;
    }

    # proceed only if invoice has items
    if ($this->{invoice}->count_items() == 0) {
	return $this->error($msg{"Invalid invoice or payment has already been processed. Please contact website support for more information."});
    }
    # show receipt if payments have already been processed
    my $payment_recorded;
    # check if we have a unique transaction id from the gateway
    if (my $trnid = $this->pgGetTransactionId()) {
	my $payments = $this->{invoice}->get_children("payment")->{payment};
	while (my $p = $payments->next()) {
		if (&preference("Pay.transaction_id","payment",$p->id) eq $trnid) {
			$payment_recorded = 1;
		}
	}
    }
    if ($this->{invoice}->is_paid) {
	my $payments = $this->{invoice}->get_children("payment")->{payment};
	if ($payments->count() > 0) {
	    $payment_recorded = 1;
	}
    }
    return $this->show_order_as_receipt() if ($payment_recorded);

    my ($pass,$invoice_status,$info,$amount,$payment,$ident,$order_id);
    if ($this->{invoice}->total > 0.00) {
	if (my $pg = $this->pgSuccess()) {
	    # the transaction succeeded
	    $info = $this->pgPass();
	    $out .= $ml->p($info,{class=>"PaymentStatusPass"});
	    $pass = 1;
	    if (! $this->{invoice}->is_valid) {
		$invoice_status = "active";
	    }
	    $amount = $this->pgGetAmount();
	    $order_id = $this->pgGetPurchaseId() || $session{invoice};
	    $ident = $this->pgGetPaymentId();
	    my $status = "paid";
		$status = $pg if ($pg eq "processing");
	    $payment = { 
		amount=>$amount, 
		method=>"e-commerce",
		note=>$info,
		ident=>$ident,
		status=>$status,
		receivable_id=>$order_id,
	    };
	}
	elsif ($this->pgCancel()) {
	    # the transaction was canceled by the user
	    $invoice_status = "inactive";
	    $out .= $ml->h1($msg{$this->{config}{heading}{cancel}});
	    $out .= $ml->p($msg{$this->{config}{message}{cancel}});
	    $pass = 0;
	}
	else {
	    # the transaction failed or was suspicious or is a duplicate
	    $info = $this->pgFail();
	    my $payment_status = "canceled";
	    if ($info =~ /SUSPICIOUS/) {
		$payment_status = "suspicious";
	    }
	    # the transaction should not be recorded because it is a duplicate (race-conditions)
	    if ($info !~ /DUPLICATE/) {
	    $out .= $ml->p($info,{class=>"PaymentStatusFail"});
	    $pass = 0;
	    if ($this->{invoice}->getdata("status") ne "advisory") {
	    $invoice_status = $payment_status eq "canceled" ?
		"inactive" :    # canceled payments reset invoice to shopping mode
		"canceled";     # suspicious payments cancel the sale
		}
		$amount = $this->pgGetAmount();
	    $order_id = $this->pgGetPurchaseId() || $session{invoice};
	    $payment = { 
		amount=>$amount,
		method=>"e-commerce",
		note=>"FAILED TRANSACTION: $info",
		status=>$payment_status,
		receivable_id=>$order_id,
	    };
	    }
	}
    }
    else {  
	# total == 0.00
	# no payment required
	$pass = 1;
	$invoice_status = "active";
	$order_id = $session{invoice};
    }

    # update the invoice
    if ($invoice_status) {
	my $stat;
	if ($invoice_status eq "active") {
	    $stat = $this->{invoice}->activate();
	}
	elsif ($this->{invoice}->getdata("status") eq "advisory") {
	    # do not change status of advisory invoices
	    $stat = 1;
	}
	else {
	    $this->{invoice}->setdata("status",$invoice_status);
	    $stat = $this->{invoice}->force_save;
	}
	if (! $stat) {
	    $share{DB}->warn("Closed invoice not updated: ".
			     $this->{invoice}->show_diagnostics("error"));
	}
    }

    # log the payment on the account
    my $pid;
    if ($payment) {
	$pid = $this->{account}->add_payment($payment);    
	if (! $pid) {
	    $out .= $this->error($msg{"Failed to record payment."});
	}
    }
    if ($pass) {
	# record unique transaction id from gateway
	if (my $trnid = $this->pgGetTransactionId()) {
	    my $meta = new ExSite::ObjectMeta(type=>"payment",id=>$pid);
	    $meta->meta_set("Pay.transaction_id",$trnid);
	    $meta->force_save();
	}    
	# display the receipt
	$out .= $ml->div(undef,{class=>"PayCheckoutDone"});
	$out .= $this->show_order_as_receipt();
	$out .= $this->receipt_success($order_id,$payment);
    
	# remember the invoice number in case we need to regenerate the receipt
	$session{last_invoice} = $session{invoice};
	# remove the invoice from the cart
	delete $this->{invoice};
	delete $cookie{cart_contents};
	$session{invoice} = 0;
    }
    else {
	# We cannot use link() to relink to the original cart, because
	# it is probably contaminated with unknown gateway dreck.
	# So we will use Page::link() instead.
	if ($share{Page} && $this->{invoice}->allow_payment()) {
	    my $retry = $ui->Button(url=>$share{Page}->link(cart=>"payment"),
				    label=>$msg{Retry});
	    my $cart = $ui->Button(url=>$share{Page}->link(cart=>"view"),
				   label=>$msg{"Back to Cart"});
	    my $cancel = $ui->Button(url=>$share{Page}->link(cart=>"cancel"),
				     label=>$msg{"Cancel Purchase"});
	    $out .= $ml->p("$retry $cart $cancel");
	}
	if ($invoice_status eq "canceled") {
	    # remove the invoice from the cart
	    delete $this->{invoice};
	    $session{invoice} = 0;		
	}
    }
    return $out;
}

sub end_payment_session {
    my $this = shift;
    delete $session{invoice};
    delete $session{invoice_nocart};
    delete $session{account};
    delete $session{payment_method};
}

# The completed sale can be displayed as either a receipt or an invoice.
# Receipt is preferred if full payment has been received, otherwise invoice
# is preferred.
#
# The following content objects may be used to dress up the statement:
# receipt_header - used on both receipts and invoices to show organization's
#     contact info, logo, etc.
# receipt_footer - used only on receipts to include information about 
#     refunds, policies, tax numbers, etc.
# payment_instructions - used only on invoices to include information on
#     how to make payment

sub show_order_as_receipt {
    my $this = shift;
    my $out;

    # look for a template
    
    my $template = $this->find_receivable_template("receipt_template","receivable_template");
    $this->{templated_invoice} = 1;
    $out .= $this->{invoice}->show_templated(
	template=>$template,
	date_format=>$this->{config}{date_format},
	notes=>$this->purchase_messages(),
	receivable_options=>$this->get_receivable_display_options(),
	);
    return $out;
}

sub show_order_as_invoice {
    my $this = shift;
    my $out;

    # look for a template
    
    my $template = $this->find_receivable_template("invoice_template","receivable_template");
    $this->{templated_invoice} = 1;
    $out .= $this->{invoice}->show_templated(
	template=>$template,
	date_format=>$this->{config}{date_format},
	notes=>$this->purchase_messages(),
	receivable_options=>$this->get_receivable_display_options(),
	);
    return $out;
}

# print-friendly : display receipt or invoice in printer-friendly form

sub print_friendly_link {
    my $this = shift;
    my $out .= $ml->script("function popup_medium(url) { window.open(url,\"\",\"width=640,height=480,resizable,scrollbars=1,menubar=0,status=0\")}",{type=>"text/javascript"});
    my $crypt = new ExSite::Crypt;
    my $crypt_last_invoice = $crypt->encrypt($this->{invoice}->id());
    $out .= $ml->p($ml->a($msg{"Printer-friendly version"},{href=>"javascript:popup_medium('".$share{Page}->link(cart=>"print",last_invoice=>$crypt_last_invoice)."')"}));
    return $out;
}

sub print_friendly {
    my $this = shift;
    my $out;
    # look for a paid invoice in the front-end user's session first
    my $inv = $share{Page} ? $session{last_invoice} : undef;
    # if none, look for an encrypted invid in the URL
    if (!$inv && $this->{input}{last_invoice}) {
	my $crypt = new ExSite::Crypt;
	$inv = $crypt->decrypt($this->{input}{last_invoice});
    }
    if ($inv) {
	my $r = new Modules::Finance::Receivable(id=>$inv);
	$this->{invoice} = $r;
	my $a = new Modules::Finance::Account(id=>$r->getdata("account_id"));
	$this->{account} = $a;
	if ($r->is_valid()) {
	    $out .= $r->is_paid() ?
		$this->show_order_as_receipt() :
		$this->show_order_as_invoice();
		if ($this->{input}{ajax}) {
			my $uri = new ExSite::URI;
			$uri->plaintext();
			my $link = $uri->write();
			$out .= &ExSite::HTML::js();
		    $out .= $ml->script(
			"\$(function () {
			\$('#print').click(function () {
			var url = \"$link\";
			var w = window.open(url);
			w.window.print();
			})
			});");
			$out .= $ml->p($ml->a($msg{Print},{id=>"print",href=>"#"}));
		} else {
		    $out .= $ml->p($ml->a($msg{Print},{href=>"javascript:print()",class=>"noprint"}));
	    }
	}
	else {
	    $out .= $this->warn(&substitute($msg{"Modules::Pay::print_friendly: Cannot display [[status]] receivable"},{status=>$r->getdata("status")}));
	}
    }
    elsif ($this->{input}{acct}) {
	if ($share{DB}->user_owns("account",$this->{input}{acct})) {
	    if (!$share{Page}) {
		my $header = $this->{config}{message}{"account_statement_header"} || $this->{config}{message}{"receipt_header"};
		$out .= $ml->div($header);
	    }

	    my $a = new Modules::Finance::Account(id=>$this->{input}{acct});
	    $out .= $a->show(
		contact_layout=>"table",
		#alltransactions=>$this->{input}{allx},
		year=>$this->{input}{year},
		month=>$this->{input}{month},
		from=>$this->{input}{from},
		to=>$this->{input}{to},
		days=>$this->{input}{days},
		);
	}
	else {
	    $out .= $this->error($msg{"Modules::Pay::print_friendly: Invalid account"});
	}	    
    }
    else {
	$out .= $this->error($msg{"Modules::Pay::print_friendly: Invalid receivable"});
    }
    
    $ml->Doc(
	     $ml->a("X&nbsp;&nbsp;close",{ href=>"javascript:window.close()", class=>"close noprint" } ).
	     $out
	     );
    $ml->__body();
    $ml->Prepend(
		 $ml->head(
			   $ml->title("Printer-Friendly Statement").
			   $ml->link(undef,{rel=>"stylesheet",href=>"$config{server}{HTMLpath}/_ExSite/css/ExSite.css",type=>"text/css"}).
			   $ml->link(undef,{rel=>"stylesheet",href=>"$config{server}{HTMLpath}/_Modules/Pay/Pay.css",type=>"text/css"})
			   )
		 );
    $ml->__html();
    if ($share{Page}) {
	$share{Page}->set("html", $ml->Write());
	$share{Page}->redo();   # rebuild the page
    } 
    else {
	$ml->PrintWithHeader();
	$ml->cancel;
    }
    return;
}

# receipt_success : perform any actions that follow successful payment

sub receipt_success {
    my ($this,$invoice,$payment) = @_;
    my $out;

    my $inv = new Modules::Finance::Cart(id=>$invoice);   
    if ($this->{config}{fulfill}) {
	# order fulfillment is enabled
	my $items = $inv->loaditems();
	while (my $item = $items->next()) {
	    if ($item->is_active) {
		my $acctcode_id = $item->getdata("acctcode_id");
		if ($acctcode_id) {
		    my $acctcode = new Modules::Finance::Acctcode(id=>$acctcode_id);
		    my $fulfillment_type = 
			$this->{config}{Pay}{fulfill}{$acctcode->name} ||
			$this->{config}{Pay}{fulfill}{$acctcode->id};
		    if ($fulfillment_type ne "manual") {
			# automatic fulfillment of this acctcode
			$item->fulfill();
		    }
		}
	    }
	}
    }
    else {
	# order fulfillment is disabled
	my $items = $inv->loaditems();
	if ($items) {
	    while (my $item = $items->next()) {
		if ($item->is_active) {
		    # automatic fulfillment
		    $item->fulfill();
		}
	    }
	}
    }

    # annotate receipt
    if ($share{annotate_receipt}) {
	my $descr = $inv->getdata("description");
	$descr .= "\n" if $descr;
	$descr .= $share{annotate_receipt};
	$inv->setdata("description",$descr);
	$inv->force_save();
    }

    $inv->complete_sale();

    # email notification
    if ($this->{config}{no_notify} != 1) {
	$this->notify($payment);
    }
    
    # finalize unpaid invoices if advisory receivable
    if ($inv->getdata("status") eq "advisory") {
	my $unpaid = $this->unpaid_invoices($payment);
	while (my $r = $unpaid->next()) {
	    # notification for advisory invoice already sent - no need for additional notifications
	    $this->{config}{no_notify} = 1;
	    my $stat = $this->receipt_success($r->id);
	    $out .= $stat if ($stat);
	}
    }
    return $out;
}

# contact_form : sub-form for shipping details

sub contact_form {
    my ($this,$title,$type,$data) = @_;

    my $stat = $this->run_handler("Pay_contact_form",$title,$type,$data);
    return $stat if (defined $stat);

    my $copy;
    my $reqd;
    if ($type eq $this->{config}{primary_contact}) {
	$reqd = 1;
    }
    else {
	$reqd = 0;
	my $attr = {type=>"checkbox",
				name=>"copy_$type",
				onclick=>"contact_form_$type(this)",
				};
	$attr->{checked} = undef if (!$data);
	$copy .= $ml->p($ml->input(undef,$attr).
		       " ".$msg{"same as"}." ".
			$this->{config}{contact_forms}{$this->{config}{primary_contact}}
		       );
	$copy .= $ml->script("
function contact_form_$type(check) {
  var el = document.getElementById('contact_form_$type');
  if (check.checked) {
    el.style.display = 'none';
  }
  else {
    el.style.display = 'block';
  }
}
");
    }

    my $f = $this->{form};
    my $map = $share{DB}{map};

    my $fields = $this->{config}{contact}{$type} || "address,city,provstate,country,pcode";
    my %field;
    map { $field{$_} = 1; } split /,/, $fields;
	my $required = $this->{config}{contact_form_required};
	my %req_f;
	map { $req_f{$_} = 1; } split /,/, $required;

    my $disp = ($type eq $this->{config}{primary_contact} || $data) ? "block" : "none";
    $f->input(type=>"preformatted",name=>"title$type",input=>$ml->h3($msg{$title}).$copy);
    $f->input(type=>"preformatted",name=>"div$type",input=>"<div id='contact_form_$type' style='display:$disp'>");
    $f->input(type=>"hidden",name=>"contact_id_$type",value=>$data->{contact_id});
    $f->input(type=>"hidden",name=>"type_$type",value=>$type);
    if ($field{info}) {
	$f->input(type=>"text",
		  prompt=>$this->contact_label("info"),
		  size=>40,
		  name=>"info_$type",
		  value=>$data->{info},
		  class=>"info",
		  required=>($reqd && $req_f{info}));
    }
    if ($field{address}) {
	$f->input(type=>"textarea",
		  prompt=>$this->contact_label("address"),
		  rows=>2,
		  cols=>60,
		  name=>"address_$type",
		  value=>$data->{address},
		  class=>"address",
		  required=>($reqd && $req_f{address}));
    }
    if ($field{city}) {
	$f->input(type=>"text",
		  prompt=>$this->contact_label("city"),
		  name=>"city_$type",
		  value=>$data->{city},
		  size=>40,
		  class=>"city",
		  required=>($reqd && $req_f{city}));
    }
    if ($field{provstate}) {
    my @provstate = split(/\|/,$share{DB}->{map}->regexp("list:provstate"));
	my $options = $this->select_options(\@provstate);
	$f->input(type=>"select",
		  prompt=>$this->contact_label("provstate"),
		  options=>$options,
		  name=>"provstate_$type",
		  value=>$data->{provstate} || $this->{config}{contact}{default}{provstate},
		  nullvalue=>"== select ==",
		  class=>"provstate",
		  required=>($reqd && $req_f{provstate}));
    }
    if ($field{country}) {
	# country field is a dropdown or a text input
	# countries in dropdown determined by preferences or datatype in dbmap
	my $options;
	if (&preference("Pay.contact_form.countries")) {
	    my $country = &preference("Pay.contact_form.countries");
	    if (ref $country ne "ARRAY") {
		$country = [$country];
	    }
	    $options = $this->select_options($country);
	}
	elsif ($map->get_column_attr("contact","country","datatype") =~ /^list:/) {
	    my @country = split(/\|/,$share{DB}->{map}->regexp("list:country"));
	    $options = $this->select_options(\@country);
	}
	if ($options) {
	    $f->input(type=>"select",
		      prompt=>$this->contact_label("country"),
		      options=>$options,
		      name=>"country_$type",
		      value=>$data->{country} || $this->{config}{contact}{default}{country},
		      nullvalue=>(scalar @$options > 1) ? "== select ==" : undef,
		      class=>"country",
		      required=>($reqd && $req_f{country}));
	}
	else {
	    $f->input(type=>"text",
		      prompt=>$this->contact_label("country"),
		      name=>"country_$type",
		      value=>$data->{country} || $this->{config}{contact}{default}{country},
		      class=>"country",
		      required=>($reqd && $req_f{country}));
	}
    }
    if ($field{pcode}) {
	$f->input(type=>"text",
		  prompt=>$this->contact_label("pcode"),
		  name=>"pcode_$type",
		  value=>$data->{pcode},
		  size=>12,
		  class=>"pcode",
		  required=>($reqd && $req_f{pcode}));
    }
    if ($field{phone}) {
	$f->input(type=>"text",
		  prompt=>$this->contact_label("phone"),
		  name=>"phone_$type",
		  value=>$data->{phone},
		  size=>12,
		  class=>"phone",
		  required=>($reqd && $req_f{phone}));
    }
    if ($field{cell}) {
	$f->input(type=>"text",
		  prompt=>$this->contact_label("cell"),
		  name=>"cell_$type",
		  value=>$data->{cell},
		  size=>12,
		  class=>"cell",
		  required=>($reqd && $req_f{cell}));
    }
    if ($field{fax}) {
	$f->input(type=>"text",
		  prompt=>$this->contact_label("fax"),
		  name=>"fax_$type",
		  value=>$data->{fax},
		  size=>12,
		  class=>"fax",
		  required=>($reqd && $req_f{fax}));
    }
    if ($field{email}) {
	$f->input(type=>"text",
		  prompt=>$this->contact_label("email"),
		  name=>"email_$type",
		  value=>$data->{email},
		  size=>40,
		  class=>"email",
		  required=>($reqd && $req_f{email}));
    }
    if ($field{website}) {
	$f->input(type=>"text",
		  prompt=>$this->contact_label("website"),
		  name=>"website_$type",
		  value=>$data->{website},
		  size=>40,
		  class=>"website",
		  required=>($reqd && $req_f{website}));
    }
    if ($field{subscribe} && ! $share{DB}->level) {
	# allow non-members to manage subscription preferences
	# (members have their own subscription management tools)
	$f->input(type=>"radio",	 
		  prompt=>$this->contact_label("subscribe"),	 
		  name=>"subscribe_$type",	 
		  value=>$data->{subscribe},	 
		  options=>["Y","N"],	 
		  class=>"subscribe",
		  required=>($reqd && $req_f{subscribe}));	 
    }
    $f->input(type=>"preformatted",name=>"div2$type",input=>"</div>");

}

sub contact_label {
    my ($this,$name) = @_;
    my $map = $share{DB}{map};	
    my $label = &preference("Pay.contact_label.$name") || $Modules::ID::Contact::field_prompt{$name} || ucfirst $name;
    return $msg{$label};
}

sub select_options {
    my $this = shift;
    my $list = shift;
    my @options;
    foreach my $item ( @$list ) {
	push @options, { value => $item, text => $item };
    }
    return \@options;
}

# notify : plaintext notifications - better for getting through spam filters
# notify_html : formatted notifications - better formatting, especially for
#               multilingual invoices

sub notify {
    my ($this,$payment) = @_;
    (tied %msg)->nohighlight();

    my $old_version;
    if ($this->{config}{bilingual_invoices}) {
	(tied %msg)->bilingual_mode();
    }
    elsif (! $share{Page} && $this->{config}{default_notification_language}) {
	$old_version = (tied %msg)->current_version;
	(tied %msg)->version($this->{config}{default_notification_language});
    }
    my $id = $this->{invoice}->id();
    my $include_payment_note;
    if (defined $this->{input}{include_payment_note}) {
		$include_payment_note = $this->{input}{include_payment_note};
    } elsif ($this->{config}{ecommerce_payment_note} && $payment->{method} eq "e-commerce") {
    	$include_payment_note = 1;
    }
    my $invoice = $this->get_text_of_invoice(
	include_payment_note=>$include_payment_note,
	item_descriptions=>$this->{config}{item_descriptions},
	description=>$this->{config}{email_description},
	);
    my $total = $this->{invoice}->total();
    # notifications can be turned off if the total is zero
    if ($total < 0.01 
	&& defined $this->{config}{notify_zerototal}
	&& ! $this->{config}{notify_zerototal}) {
	if ($this->{config}{bilingual_invoices}) {
	    (tied %msg)->unilingual_mode();
	}
	elsif (! $share{Page} && $this->{config}{default_notification_language}) {
	    (tied %msg)->version($old_version);
	}
	return;
    }

    my $amount = $payment ? $payment->{amount} : "0.00";
    my $seller = $this->{config}{seller_email} || $share{DB}->owner_email();
    my $message;
    my $what = $total - $amount > 0.00 ? "payment" : "purchase";

    my $notify_purchaser = defined $this->{config}{notify_purchaser} ?
		$this->{config}{notify_purchaser} : 1;
    my $notify_seller = defined $this->{config}{notify_seller} ?
		$this->{config}{notify_seller} : 1;

    my $pay_message = &clone($this->{config}{message});
    # convert linebreaks to HTML linebreaks
    my $br = $ml->br;
    foreach my $msg (keys %{$this->{config}{message}}) {
	$pay_message->{$msg} =~ s/\n/$br/g;
    }

    if ($notify_purchaser) {
	my $purchaser = $this->{account}->email($this->{config}{primary_contact});
	my $thanks = $what eq "purchase" ?
	    $msg{$pay_message->{thanksForPurchase}} :
	    $msg{$pay_message->{thanksForPayment}};
	$message = $invoice;

# should already be on invoice
#	$message .= $this->purchase_messages($pay_message);

	# attachment (eg. a printable PDF receipt)

	my $attachment = $this->run_handler("Pay_receipt_attachment");

	# notify purchaser

	if ($purchaser) {
	    # purchaser has an email address for notification
	    if (!$attachment) {
		&ExSite::Mail::send(to=>$purchaser,from=>$seller,subject=>$thanks,body=>$message);
	    } 
	    else {
		$message .= $ml->p($msg{$pay_message->{attachment}});
		&ExSite::Mail::send(to=>$purchaser,from=>$seller,
				    subject=>$thanks,body=>$message,
				    attach=>{ filename => $config{site}{name} . " ${id}.pdf", data => $attachment });
	    }
	}

	# no purchaser email!  Might still need to send notification...

	elsif ($attachment && $this->{config}{notify_no_email_attachment}) {
	    my $to = $this->run_handler("Pay_notify_no_email_attachment",$payment) || 
		$this->{config}{notify_no_email_attachment} ||
		$seller;
	    # purchaser has no email address, but we have an attachment that needs mailing
	    $message = $this->{account}->show_contacts() . $message;
	    if ($this->{config}{notify_no_email_subject}) {
		$thanks = $this->{config}{notify_no_email_subject};
	    }
	    $message .= $ml->p($msg{$pay_message->{attachment}});
	    &ExSite::Mail::send(to=>$to,from=>$seller,
				subject=>$thanks,body=>$message,
				attach=>{ filename => $config{site}{name} . " ${id}.pdf", data => $attachment });
	}
	elsif ($this->{config}{notify_no_email}) {
	    my $to = $this->run_handler("Pay_notify_no_email",$payment) || 
		$this->{config}{notify_no_email} ||
		$seller;
	    # purchaser has no email, but we must email the notification regardless
	    if ($this->{config}{notify_no_email_subject}) {
		$thanks = $this->{config}{notify_no_email_subject};
	    }
	    if (! $attachment) {
		&ExSite::Mail::send(to=>$this->{config}{notify_no_email},from=>$seller,subject=>$thanks,body=>$message);
	    } 
	    else {
		$message .= $ml->p($msg{$pay_message->{attachment}});
		&ExSite::Mail::send(to=>$to,from=>$seller,
				    subject=>$thanks,body=>$message,
				    attach=>{ filename => $config{site}{name} . " ${id}.pdf", data => $attachment });
	    }
	}
    }

    if ($notify_seller) {
	my $name = $this->{account}->name();
	if (defined $this->{config}{item_descriptions}) {
	    # admin view might be different, regenerate
	    $invoice = $this->get_text_of_invoice();
	}
	$message = $ml->p("A payment of \$$amount was made by $name\nagainst the following receivable:").$invoice;
	if ($what eq "purchase" || $this->{invoice}->is_paid()) {
	    $message .= $ml->p("This receivable has been paid in full.");
	}
	else {
	    $message .= $ml->p("This receivable still has money owing.");
	}
	my $to = $this->notification_email($payment);
	my $descr = $this->{invoice}->description;
	my $subj = uc($what) . " - $name - $descr - $config{report}{currency_char}$total";
	&ExSite::Mail::send(to=>$to,from=>$seller,subject=>$subj,body=>$message);
    }
    if ($this->{config}{bilingual_invoices}) {
	(tied %msg)->unilingual_mode();
    }
    elsif (! $share{Page} && $this->{config}{default_notification_language}) {
	(tied %msg)->version($old_version);
    }
    (tied %msg)->restore();
    return;
}

sub purchase_messages {
    my ($this,$message) = @_;
    my $out = $this->run_handler("Pay_purchase_messages",$message);
    $message or $message = $this->{config}{message};
    if (ref $message->{acctcode} eq "HASH") {
	my %acmsg;
	my $items = $this->{invoice}->loaditems();
	if ($items) {
	    while (my $item = $items->next) {
		my $ac = $item->acctcode();
		if ($ac->defined) {
		    my $code = $ac->name;
		    my $msg = $message->{acctcode}{$code};
		    if ($msg && ! $acmsg{$msg}) {
			$out .= $ml->p($msg{$msg});
		    }
		    $acmsg{$msg} = 1;  # don't repeat messages
		}
		my $obj = $item->purchased_object();
		if ($obj && $obj->can("sale_note")) {
		    my $msg = $obj->sale_note($item);
		    if ($msg) {
			$out .= $ml->p($msg{$msg});
		    }
		}
	    }
	}
    }
    return $out;
}

sub notification_email {
    my ($this,$payment) = @_;
    my $stat = $this->run_handler("Pay_notification_to",$payment);
    return $stat if ($stat);
    my %emails;
    # acctcode-specific notification emails
    my $config = &clone($this->{config}{notification});
    if (ref $config->{acctcode} eq "HASH") {
	my $items = $this->{invoice}->loaditems();
	if ($items) {
	    while (my $item = $items->next) {
		my $ac = $item->acctcode();
		my $code = $ac->name;
		my @emails = split(/,/,$config->{acctcode}{$code});
		map { $emails{$_} = 1 } @emails;
	    }
	}
    }
    my $seller = $this->{config}{notification_email} ||
	$this->{config}{seller_email} ||
	$share{DB}->owner_email();
    map { $emails{$_} = 1 } split(/,/,$seller);
    return join(',',keys %emails);
}

sub get_text_of_invoice {
    my ($this,%opt) = @_;
    my $temp = $this->{invoice}->is_paid ? "receipt_template" : "invoice_template";
    my $template = $this->find_receivable_template($temp,"receivable_template");
    $this->{templated_invoice} = 1;
    return $this->{invoice}->show_templated(
	template=>$template,
	date_format=>$this->{config}{date_format},
	notes=>$this->purchase_messages(),
	receivable_options=>$this->get_receivable_display_options(\%opt),
	);
}

# get_receivable_display_options
# sets defaults used by both $inv->show and $inv->show_templated
sub get_receivable_display_options {
    my ($this,$opt) = @_;
    exists $opt->{unitcost} or $opt->{unitcost} = $this->{config}{unitcost};
    exists $opt->{size} or $opt->{size} = $this->{config}{size};
    exists $opt->{bilingual} or $opt->{bilingual} = $this->{config}{bilingual};
    exists $opt->{summarize_surcharges} or $opt->{summarize_surcharges} = 1;
    exists $opt->{description} or $opt->{description} = $this->{config}{description};
    exists $opt->{zero_cost} or $opt->{zero_cost} = $this->{config}{zero_cost};
#    exists $opt->{total} or $opt->{total} = ($this->{config}{label}{total} || "TOTAL");
    # total label only applies to carts, not completed sales
    exists $opt->{total} or $opt->{total} = "TOTAL";
    $opt->{head_quantity} = $this->{config}{message}{quantity};
    $opt->{head_description} = $this->{config}{message}{description};
    $opt->{head_unitprice} = $this->{config}{message}{unitprice};
    $opt->{head_subtotal} = $this->{config}{message}{subtotal};
    my $crypt = new ExSite::Crypt;
    if ($crypt->decrypt($this->{input}{last_invoice}) == $this->{invoice}->id) {
	$opt->{allow} = 1;
    }
    return $opt;
}

sub find_receivable_template {
    my ($this,@template) = @_;
    my $out = $this->run_handler("Pay_find_receivable_template",@template);
    return $out if (defined $out);
    my $cobj = $share{Page};
    if (! $cobj) {
	my $section = $share{DB}->this_site();
	if ($section) {
	    $cobj = new ExSite::Section(section=>$section);
	}
	else {
	    # need a section to search for a template; look in the conf 
	    # for a hard-coded section ID
	    $cobj = new ExSite::Section(id=>$this->{config}{section_id});
	}
    }
    if ($cobj) {
	foreach my $t (@template) {
	    my $tobj = $cobj->find($t);
	    if ($tobj) {
		$tobj->set_context();
		if ($tobj->has_content) {
		    #return $tobj->expand(); # [[merge]] codes converted to urls
		    return $tobj->get_html();
		}
	    }
	}
    }
    return undef;
}

# unpaid_invoices : list of all receivables that are unpaid

sub unpaid_invoices {
	my ($this,$payment) = @_;
	my $receivables = $this->{account}->get_children("receivable")->{receivable};
	my $balance = $this->{account}->balance;
	# add payment amount onto current balance to get balance prior to this payment
	$balance += $payment->{amount} if ($payment);
	$receivables->reverse();
	my $running_total;
	my $unpaid = new ExSite::ObjectList(type=>"receivable");
	while (my $rcv = $receivables->next()) {
		if ($rcv->getdata("status") eq "inactive" && $rcv->name() =~ /-retry/) {
			$rcv->setdata("status","active");
		}
		# is_paid receivable method only checks payments on the invoice
		if ($rcv->is_active && !$rcv->is_paid(ignore_account_balance=>1)) {
			$running_total += $rcv->total();
			# running total of unpaid invoices must be less than or equal to account balance
			last if ($running_total > $balance);
			$unpaid->push($rcv->get());
		}
	}
	return $unpaid;
}

# sale statement : a full description of the sale for admins/accountants

sub sale_statement {
    my $this = shift;
    my $out;
    my $inv = $this->{input}{inv};
    if ($inv) {
	my $r = new Modules::Finance::Receivable(id=>$inv);
	$this->{invoice} = $r;
	my $a = new Modules::Finance::Account(id=>$r->getdata("account_id"));
	$this->{account} = $a;
	$out .= $ml->h1("Sale #".$r->id);
	my $status = $r->getdata("status");
	if ($status eq "active") {
	    $out .= $ml->p(
		$ui->ToolIcon(name=>"approve").
		" Sale status: OK. This sale will be included in reports."
		);
	}
	elsif ($status eq "inactive") {
	    $out .= $ui->ErrorBox(title=>"Inactive Sale",
				  pane=>"This sale was not completed. It will not be included in reports.");
	}
	elsif ($status eq "advisory") {
	    $out .= $ui->ErrorBox(title=>"Advisory Invoice",
				  pane=>"This sale is advisory only, and will not appear as a separate sale in reports. It was issued in order to collect amounts due for other sales already in the system. Please see the account statement to see what those other sales were.");
	}
	elsif ($status eq "canceled") {
	    $out .= $ui->ErrorBox(title=>"CANCELED",
				  pane=>"This sale was canceled after being made. Check the ".$ml->a("payment history",{href=>"#payments"})." to see if refunds were issued.");
	}
	elsif ($status eq "processing") {
	    $out .= $ui->ErrorBox(title=>"PROCESSING",
				  pane=>"Payment is currently being processed on this sale.");
	}
	$out .= $ml->h2("Details of Sale");
	$out .= $ml->div($r->show_templated(),{class=>"greybox"});
	$out .= $ml->a(undef,{name=>"payments"});
	$out .= $ml->h2("Payment Information");
	my $payments = $r->get_payments();
	my @plist;
	my $ptotal = 0;
	if ($payments->count() > 0) {
	    my ($ptype,$pdate);
	    while (my $pay = $payments->next()) {
		push @plist, $pay->show();
		$ptotal += $pay->amount();
	    }
	}
	$out .= (@plist > 0) ? $ml->ol(\@plist) : $ml->p("No payments recorded on this invoice.");
	my $owed = $r->total;
	if ($ptotal > 0.00) {
	    my $tot = sprintf "%.02f", $ptotal;
	    if ($ptotal > $owed) {
		$out .= $ui->ErrorBox(title=>"OVERPAYMENT",
				      pane=>"$config{report}{currency_char}$tot paid on $config{report}{currency_char}$owed owed.");
	    }
	    else {
		$out .= $ml->p("$config{report}{currency_char}$tot paid on $config{report}{currency_char}$owed owed.");
	    }
	}
	if ($r->is_paid) {
	    if (@plist == 0 && $owed > 0.00) {
		$out .= (@plist == 0 && $owed > 0.00) ?
		    $ml->p("This account is paid up.") :
		    $ml->p("No amount is owed on this sale.");
	    }
	}
	$out .= $ml->h2("Order Fulfillment");
	my @olist;
	my $items = $r->loaditems();
	while (my $item = $items->next()) {
	    next if ($item->is_surcharge());
	    if ($item->is_active) {
		my $descr = $item->is_fulfilled ? 
		    $ui->ToolIcon(name=>"approve") :
		    $ui->ToolIcon(name=>"reject");
		$descr .= $item->brief_description;
		push @olist, $descr;
	    }
	}
	$out .= $ml->ol(\@olist);
    }
    else {
	$out .= $this->error($msg{"Modules::Pay: Invalid receivable"});
    }
    return $out;
}

# refund : "undo" function for sales

sub refund {
    my $this = shift;
    if (keys %{$this->{post}} > 0) {
	return $this->do_refund();
    }
    my $r = $this->{invoice};
    my $out = $ui->AlertBox(title=>"Refunds can get complicated!",pane=>"Are you reversing payments, refunding whole purchases, inndividual line-items, or returning money as a post-purchase discount? You can find guidance in the ".$ml->a("help documentation",{href=>"javascript:popup_medium('$config{server}{CGIpath}/$config{prog}{help}/Pay#refunds')"}));

    my $br = $ml->br;
    $out .= $ml->h3($r->name);
    if (! $r->is_active) {
	$out .= $ui->ErrorBox(title=>"Warning",
			      pane=>"This sale is marked as ".$r->showdata("status").". It is already excluded from sales reports.");
    }
    if ($r->getdata("type") eq "payable") {
	$out .= $ui->ErrorBox(title=>"Error",
			      pane=>"This is not an invoice owing to you, so we cannot do normal refund processing. Please correct this item manually.");
	return $out;
    }
    $out .= $ml->p("Please indicate how the original sale should be treated:");
    my %items;
    my @items;
    my $items = $r->loaditems();
    while (my $item = $items->next()) {
	if ($item->is_active) {
	    push @items, $item->id;
	    $items{$item->id} = $item->name() . " (" . $item->getdata("description") .")";
	}
    }
    my $refundables;
    foreach my $item (@items) {
	$refundables .= $ml->input(undef,{type=>"checkbox",checked=>undef,value=>$item,name=>"cancel_item"})." Refund ".$items{$item}.$br;
    }
    $refundables .= $ml->p("If doing partial refunds, you should also refund any taxes/surcharges related to the refunded items.");

    my $options = $ml->dt($ml->input(undef,{type=>"radio",checked=>undef,value=>"cancel",name=>"cancel_invoice",onchange=>"show_refundables(this)"})." Cancel the sale").
	$ml->dd("The buyer is no longer buying the purchased items, and you do not want the sale to appear in reports.").
	$ml->dt($ml->input(undef,{type=>"radio",value=>"deactivate",name=>"cancel_invoice",onchange=>"show_refundables(this)"})." Void the sale").
	$ml->dd("This was an error, this purchase never happened, and should not appear in reports.").
	$ml->dt($ml->input(undef,{type=>"radio",value=>"refund",name=>"cancel_invoice",onchange=>"show_refundables(this)"})." Enter a refund").
	$ml->dd("Both the original sale and the refund will appear in reports as separate items.".
		$ml->div($refundables,{id=>"refundables",style=>"display:none"})).
	$ml->dt($ml->input(undef,{type=>"radio",value=>"null",name=>"cancel_invoice",onchange=>"show_refundables(this)"})." Leave the sale as-is").
	$ml->dd("The sale is good; you are only refunding/canceling payments.");
    $out .= $ml->p($options);
    $out .= $ml->script("
function show_refundables(r) {
    var loc = document.getElementById('refundables');
    if (r.value == 'refund') {
        loc.style.display='block';
    }
    else {
        loc.style.display='none';
    }
    loc = document.getElementById('payments');
    if (r.value == 'refund') {
        loc.style.display='none';
    }
    else {
        loc.style.display='block';
    }
}\n");    
    my $payments = $r->get_payments();
    my @payment_options = (
	[ "fully refunded", "refund" ],
	[ "canceled/not received/error", "cancel" ],
	[ "leave payment as-is", "null" ]
	);
    if ($payments->count() > 0) {
	my ($ptype,$pdate);
	my $payrpt = new ExSite::ReportBuilder(title=>"Payment Corrections",id=>"payments");
	$payrpt->headers("Payment #","Date","Amount","Status","Info","Action");
	while (my $pay = $payments->next()) {
	    my $pid = $pay->id;
	    my $aval = $pay->is_paid ? "refund" : "null";
	    my $popt;
	    foreach my $opt (@payment_options) {
		my $text = $opt->[0];
		my $val = $opt->[1];
		my $oopt = {value=>$val};
		if ($aval eq $val) { $oopt->{selected} = undef; }
		$popt .= $ml->option($text,$oopt);
	    }
	    my $action = $ml->select($popt,{name=>"cancel_payment_$pid"});
	    $payrpt->push(
		$pay->id,
		$pay->showdata("date"),
		$pay->showdata("amount"),
		$pay->showdata("status"),
		$pay->showdata("note"),
		$action
		);
	}
	my $payout = $ml->h3("Payments");
	$payout .= $ml->p("Payments were recorded on this invoice. Please indicate what to do with each of the payments:");
	$payout .= $payrpt->make();
	$out .= $ml->div($payout,{id=>"payments"});
    }
    $out .= $ml->input(undef,{type=>"submit",value=>"Submit"});
    $out .= $ml->input(undef,{type=>"reset",value=>"Reset"});
    $out = $ml->form($out,{method=>"post"});
    return $ui->BasicBox(title=>"Refund Invoice ".$r->id,
			 pane=>$out);
}

sub do_refund {
    my $this = shift;
    my $r = $this->{invoice};
    my $post = $this->{post};
    #return &ShowHash($post);
    my $out = $ml->h1("Refund Invoice #".$r->id);
    my @items = split /; /, $post->{cancel_item};
    $out;
    my $method = $post->{cancel_invoice};
    my $errcnt = &AtError();

    if ($method eq "refund") {
	if (! $r->is_paid) {
	    return $this->error("This invoice does not include any record of having been paid. Automatic refund cannot be recorded. Please make corrections manually.");
	}

	# execute partial refund
	# 1) create new invoice

	my $today = new ExSite::Time();
	my $refund_id = $r->copy(
	    type=>"payable",
	    date=>$today->write("sql_timestamp"),
	    description=>"Refund entered on ".$today->write("date"),
	    status=>"active",
	    invoice=>undef
	    );
	if ($refund_id) {
	    # 2) add refunded items to it
	    my $total;
	    foreach my $item_id (@items) {
		my $item = new Modules::Finance::ReceivableItem(id=>$item_id);
		$total += $item->subtotal;
		if ($item->getdata("receivable_id") == $r->id) {
		    $item->copy(
			receivable_id=>$refund_id,
			item=>"REFUND ".$item->getdata("item"),
			uid=>$share{DB}->my_uid,
			);
		}
	    }
	    # 3) add payment for total
	    my $paydata = {
		account_id => $r->getdata("account_id"),
		receivable_id => $refund_id,
		date => $today->write("sql_timestamp"),
		amount=>-$total,
		method=>"other",
		status=>"paid",
		note=>"Refund of invoice ".$r->id,
		uid=>$share{DB}->my_uid,
	    };
	    my $payment = new Modules::Finance::Payment(data=>$paydata);
	    $payment->save();
	    my $rinv = new Modules::Finance::Receivable(id=>$refund_id);
	    $out .= $rinv->show();
	    $out .= $ml->p("Refund bookkeeping completed. Don't forget to make the actual refund payment! Click on the account tab to see the updated account statement.");
	}
    }
    else {
	if ($method eq "deactivate") {
	    $this->{invoice}->setdata("status","inactive");
	    if ($this->{invoice}->save) {
		$out .= $ml->p("Invoice deactivated.");
	    }
	}
	elsif ($method eq "cancel") {
	    $this->{invoice}->setdata("status","canceled");
	    if ($this->{invoice}->save) {
		$out .= $ml->p("Invoice canceled.");
	    }
	}
	$out .= $this->do_refund_payment($post,$r);
    }
    if (&AtError($errcnt)) { 
	$out .= &ExSite::Config::show_diagnostics();
    }

    return $out;
}

sub do_refund_payment {
    my ($this,$post,$r) = @_;
    my $out;
    foreach my $in (keys %$post) {
	if ($in =~ /^cancel_payment_(\d+)$/) {
	    my $today = new ExSite::Time();
	    my $payment = new Modules::Finance::Payment(id=>$1);
	    if ($r && $payment->getdata("receivable_id") == $r->id) {
		if ($post->{$in} eq "refund") {
		    # insert opposite payment
		    my $amt = $payment->getdata("amount");
		    my $pid = $payment->copy(
			status=>"paid",
			date=>$today->write("sql_timestamp"),
			amount=> -$amt,
			method=>"other",
			note=>"Refunded payment ID $1",
			uid=>$share{DB}->my_uid,
			);
		    if ($pid) {
			$out .= $ml->p("Refunded $amt.");
		    }
		    else {
			$out .= $ml->p("Failed to add refund to system.");
		    }
		}
		elsif ($post->{$in} eq "cancel") {
		    # cancel the payment
		    my $amt = $payment->getdata("amount");
		    $payment->setdata("status","canceled");
		    my $note = $payment->getdata("note");
		    $note .= "\nCanceled payment ".$today->write("date"),
		    $payment->setdata("note",$note);
		    if ($payment->save) {
			$out .= $ml->p("Canceled payment ".$payment->id.".");
		    }
		    else {
			$out .= $ml->p("Failed to add refund to system.");
		    }
		}
	    }
	}
    }
    return $out;
}

# move invoice - move receivable to another account in the system

sub move_invoice {
    my ($this) = @_;
    my $out = $ml->h1("Move Receivable");
    if ($this->{input}{name} || $this->{input}{account_id}) {
	my $acctid = $this->{input}{account_id};
	if (! $acctid) {
	    my $find = "\%$this->{input}{name}\%";
	    my @acct = $this->{section_id} ?
		$share{DB}->fetch_match("account",{section_id=>$this->{section_id},name=>$find},"name") :
		$share{DB}->fetch_match("account",{name=>$find},"name");
	    my $list;
	    foreach my $acct (@acct) {
		next if ($acct->{account_id} == $this->{invoice}->getdata("account_id"));
		next if ($acct->{code} =~ /use Account \d+/);
		my $info = " Account #$acct->{account_id}";
		if ($acct->{code}) {
		    $info .= " [$acct->{code}]";
		}
		if ($acct->{uid}) {
		    $info .= ", Member #$acct->{uid}";
		}
		$list .= $ml->li($ml->a($acct->{name},{href=>$this->link(account_id=>$acct->{account_id})}).$info);
	    }
	    $out .= $list ?
		$ml->p("Move this receivable to account") . $ml->ul($list) :
		$ml->p("No matching accounts found.");
	    return $out;
	}
	if ($share{DB}->user_owns("account",$acctid)) {
	    $this->{invoice}->setdata("account_id",$acctid);
	    $this->{invoice}->save;
	    my $invid = $this->{invoice}->id;
	    $out .= $ml->p("Receivable $invid moved to account $acctid.");
	    my @pay = $share{DB}->fetch_match("payment",{receivable_id=>$this->{invoice}->id});
	    foreach my $pmt (@pay) {
		$pmt->{account_id} = $acctid;
		$share{DB}->update("payment",$pmt);
		$out .= $ml->p("Payment $pmt->{payment_id} moved to account $acctid.");
	    }
	    $ml->location($this->link(__plaintext=>1,account_id=>undef,cart=>undef,acct=>undef,payment=>undef,inv=>$this->{invoice}->id));
	    return $out;
	}
	else {
	    $out .= $this->error("Permission denied: you do not have permission to link to that account.");
	}
    }
    $out .= $ui->HelpMsg("If this receivable was recorded under the wrong account, you can switch it to a different account. Enter the account ID of the new account, if you know it, or search by account name, if not.");
    my $f = new ExSite::FormBuilder();
    $f->input(name=>"account_id",type=>"text",prompt=>"Move to account ID:");
    $f->input(name=>"name",type=>"text",prompt=>"OR, search for accounts under name:");
    $out .= $f->make();
}

sub pay_account {
	my $this = shift;
	my $out;
    my $balance = $this->{account}->balance();
    my $options;
    $options .= $ml->h1($msg{"Account Payment Options"});
    my $invoices = $this->unpaid_invoices();
    if ($invoices->count) {
    $options .= $ml->div($ml->input(undef,{type=>"radio",checked=>undef,value=>"invoice",name=>"pay_account",onchange=>"show_invoices(this)"}).$msg{" Pay an individual invoice"});
    }
    $options .= $ml->div($ml->input(undef,{type=>"radio",value=>"balance",name=>"pay_account",alt=>"$balance",onchange=>"show_invoices(this)"}).$msg{" Pay the full balance due on my account"});
    $out .= $ml->p($options);
    my $r = new ExSite::ReportBuilder(title=>$msg{"Invoices"});
    $r->headers(["",$msg{"Date"},$msg{"Description"},$msg{"Amount"},""]);
    my $f = new ExSite::FormBuilder(action=>$this->link());
	my $on_payment_plan;
    while (my $inv = $invoices->next()) {
    	if (!$on_payment_plan && !$inv->is_paid) {
		my $plan = &preference("Pay.payment_plan","receivable",$inv->id);
		if (&preference("Pay.payment_plan.$plan.num_payments") > 1) {
			$on_payment_plan = 1;
		}
		}
		my $crypt = new ExSite::Crypt;
		my $crypt_last_invoice = $crypt->encrypt($inv->id());
		my $uri = new ExSite::URI;
		$uri->query(last_invoice=>$crypt_last_invoice,cart=>"print");
   		my $url = $uri->write;
		my $t = new ExSite::Time($inv->getdata("date"),"sql_timestamp");
		my $payments = $inv->get_payments();
		if ($payments->count() > 0) {
			my $ptotal = 0;
			while (my $pay = $payments->next()) {
			$ptotal += $pay->amount();
			}
		}
   
	    $r->push(
	    $ml->input(undef,{
	    	name=>"recvid",
	    	alt=>$inv->total,
	    	type=>"radio",
	    	value=>$inv->id()}),
	    $t->write("date"),
	    $inv->description(),
	    "\$".$inv->total(),
	    $ml->a("view",{title=>$inv->description(),href=>"javascript:popup_custom(640,480,'$url')",class=>"invoice_link"}),
	    );
    }
    my $errors;
    if ($this->{input}{ctrl}) {
    $errors = $this->error($msg{"Please select an invoice to pay."});    
    }
    $out .= $ml->div($r->make . $errors,{id=>"invoices"});
	$out .= $ml->script(undef,{src=>"$config{server}{server}$config{server}{HTMLpath}/_ExSite/js/misc.js",type=>"text/javascript"});
	$out .= $ml->script("document.write('<scr' + 'ipt type=\"text/javascript\" src=\"$config{jquery}\"></scr' + 'ipt>');",{type=>"text/javascript"});
    $out .= $ml->script("
var balance = \$(\"input[name='payment']\").val();
\$(\"input[name='recvid']\").change( function() {
	\$(\"input[name='payment']\").val(\$(this).attr('alt'));
	\$(\"input[name='inv']\").val(\$(this).val());		
});
\$(\"input[name='pay_account']\").change( function() {
	if (\$(this).val() == 'balance') {
		\$(\"input[name='inv']\").val(0);
		\$(\"input[name='recvid']\").attr('checked',false);
		\$(\"input[name='payment']\").val(\$(this).attr('alt'));
		\$(\"div#amount\").show();	
		\$(\"div#balance\").show();				
	}
	if (\$(this).val() == 'invoice') {
		\$(\"input[name='payment']\").val('');
		\$(\"div#amount\").hide();
		\$(\"div#balance\").hide();					
	}
});         
function show_invoices(r) {
    var loc = document.getElementById('invoices');
    if (r.value == 'balance') {
        loc.style.display='none';
    }
    if (r.value == 'invoice') {
        loc.style.display='block';
    }
}\n");
	if ($this->{input}{inv} || $this->{input}{payment} =~ /^\d+(\.\d{2})?$/) {
	my $inv_id;
	$session{disable_change_account} = 1;
	if ($inv_id = $this->{input}{inv}) {
	my $r = new Modules::Finance::Receivable(id=>$inv_id);
	$r->setdata("status","inactive");
	$r->remove_surcharges();
	$r->setdata("invoice","retry");
	$r->save();
	}
    elsif ($this->{input}{payment} =~ /^\d+(\.\d{2})?$/) {
	if ($on_payment_plan) {
    return $this->error($msg{"You previously set up automated payments on your account.  As such you are unable to pay the balance on your account at this time.  If you have any questions please contact the website administrator."});
    }
	$inv_id = $this->{account}->add_receivable(
						      {status=>"advisory"},
						      {item=>"Account Payment",
						       cost=>($this->{input}{payment} || $balance),
						       });
	}
	if ($inv_id) {
	    $session{invoice} = $inv_id;
	    $this->get_invoice($inv_id);
	    if ($this->{invoice}->getdata("status") eq "advisory") {
	    	$this->{invoice}->setdata("invoice","advisory");
	    	$this->{invoice}->save();
	    }
	}
	return $this->checkout1();
    }
    $out .= $ml->div($this->{account}->show_balance(),{id=>"balance",style=>"display: none;"});
    $f->input(type=>"hidden",name=>"ctrl",value=>1);
    $f->input(
    	  name=>"inv",
	      type=>"hidden",
	      value=>0
	      );
	my $edit = $this->{config}{acct_statement}{edit_amount};
    $f->input(prompt=>$edit ? $msg{'Payment Amount'} : " ",
	      name=>"payment",
	      type=>$edit ? "text" : "hidden",
	      required=>$edit ? 1 : 0,
	      );
    $f->set("buttons",$ml->input(undef,{type=>"submit",value=>$msg{Pay}}));
    $f->template("<div id=\"amount\"><p>[[payment:prompt]]</p><p>[[payment:input]]</p></div>");
    $out .= $f->make();
}

sub my_account {
    my $this = shift;
    my $uid = $share{DB}->my_uid();
    my $out;
    if ($uid) {
    my $acct = $this->get_account();
	if ($acct) {
	    my $balance = $this->{account}->balance();
	    if ($balance > 0.00) {

		if ($this->{input}{cart} eq "payacct") {
			return $this->pay_account();
		}
		else {
		    $out .= $ml->h1($msg{$this->{config}{heading}{myaccount}});
		    $out .= $this->{account}->show();
		    $out .= $this->{account}->show_balance();
		    $out .= $ui->Button(type=>"button",label=>$msg{"Make a payment"},url=>$this->link(cart=>"payacct"));
		}
	    }
	    else {
		$out .= $ml->h1($msg{$this->{config}{heading}{myaccount}});
		$out .= $this->{account}->show();
		$out .= $ml->p($msg{$this->{config}{message}{zero_account_balance}});
	    }
	}
	else {
	    $out .= $ml->p($msg{$this->{config}{message}{no_account}});
	}
    }
    else {
	$out .= $ml->p($msg{$this->{config}{message}{not_logged_in}});
    }
    return $out;
}

sub my_balance {
    my $this = shift;
    my $uid = $share{DB}->my_uid();
    my $out;
    if ($uid) {
	my @acct = $share{DB}->fetch_match("account",{uid=>$uid},"account_id");
	if (@acct > 0) {
	    $this->{account} = new Modules::Finance::Account(data=>$acct[-1]);
	    my $balance = $this->{account}->balance();
	    if ($balance > 0.00) {
		my $text = $msg{"You currently have an account balance of \$[[balance]]. View your [[statement]]."};
		my $s = &ExSite::Module::service_page("Pay");
		my $link = $ml->a($msg{"account statement"}, {href=>$s->link(cart=>"myacct")});
		return &substitute($text,{balance=>$balance,statement=>$link});
	    }
	}
    }
    return undef;
}

#--------------------------------------------------------------------------
# ctrl_panel() generates the contents of the administrator control panel

sub ctrl_panel {
    my $this = shift;
    $this->{admin} = 1;
    $this->get_config();
    $this->{scope} = $this->{config}{scope} || "global";
    if ($this->{scope} eq "local") {
	$this->{section_id} = $this->get_section_id();
	$this->{section_id} or return $this->set_section_id();
    }

    $this->setup_queries();

    # set up invoice links
    $share{DB}->handler("show_foreign_key",\&invoice_link);

    # declare a markup generator
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    
    my @rcvblstat = split /\|/, $share{DB}{map}->regexp("list:receivable_status");

    my $inv = $this->{input}{inv};
    my (%out,@tabs,@panes,$thistab);

    if ($this->{input}{cart} eq "print") {
	return $this->print_friendly();
    }
    elsif ($this->{input}{cart} eq "recheckout") {
	return $this->recheckout($inv);
    }
    elsif ($this->{input}{cart} =~ /^checkout/i) {
	return $this->checkout1_admin();
    }
    elsif ($this->{input}{cart} =~ /view|edit/) {
	return $ml->h1("Shopping Cart").$this->write();
    }

    my $searchurl = $this->link(inv=>undef,acct=>undef,payment=>undef);
    my $advsearch;
    $advsearch = $ml->p(
	 $ml->form("Find ".
		   $ml->select(\@rcvblstat,{name=>"status"}).
		   " invoices from ".
		   $ml->select([
				[ "option", "last 24 hours", { value=>1 } ],
				[ "option", "last 7 days", { value=>7 } ],
				[ "option", "last 30 days", { value=>30 } ],
				[ "option", "last 60 days", { value=>60 } ],
				[ "option", "last 90 days", { value=>90 } ],
				],
			       {name=>"age"}).
		   $ml->input(undef,{value=>"Submit",type=>"submit"}),
		   {method=>"post",action=>$searchurl}
		   )
			     );
    my $time = new ExSite::Time;
    my $dateto = $this->{input}{dateto} || $time->write("sql_date");
    $time->add(-2,"weeks");
    my $datefrom = $this->{input}{datefrom} || $time->write("sql_date");
    $advsearch .= $ml->p(
	 $ml->form("Find ".
		   $ml->select(\@rcvblstat,{name=>"status"}).
		   " invoices from ".
		   $ml->input(undef,{name=>"datefrom",type=>"text",size=>10,value=>$datefrom,class=>"date-pick"}).
		   " to ".
		   $ml->input(undef,{name=>"dateto",type=>"text",size=>10,value=>$dateto,class=>"date-pick"}).
		   $ml->input(undef,{value=>"Submit",type=>"submit"}),
		   {method=>"post",action=>$searchurl}
		   )
			     );
    $advsearch .= $ml->p(
	$ml->form("Find invoice/receipt number ".
		  $ml->input(undef,{type=>"text",size=>10,name=>"inv",value=>$inv}).
		  $ml->input(undef,{type=>"hidden",name=>"section_id",value=>$this->{input}{section_id}}).
		  $ml->input(undef,{value=>"Lookup",type=>"submit"}),
		  {method=>"get",action=>$searchurl}
		  )
			   );
    $advsearch .= $ml->p(
	$ml->form("Find account name ".
		  $ml->input(undef,{type=>"text",size=>10,name=>"acctname",value=>$this->{input}{acctname}}).
		  $ml->input(undef,{value=>"Search",type=>"submit"}),
		  {method=>"post",action=>$searchurl}
		  )
			   );
    $advsearch .= $ml->p(
	$ml->form("Show last ".
		  $ml->input(undef,{type=>"text",size=>10,name=>"n_pay"}).
		  " payments received ".
		  $ml->input(undef,{value=>"Show",type=>"submit"}),
		  {method=>"post",action=>$searchurl}
		  )
			   );

    $out{search} = $ml->p(
	$ml->form("Recent sales: ".
		  $ml->input(undef,{type=>"hidden",value=>"active",name=>"status"}).
		  $ml->input(undef,{type=>"hidden",value=>"30",name=>"age"}).
		  $ml->input(undef,{value=>"Show",type=>"submit"}),
		  {method=>"post",action=>$searchurl}
	).
	$ml->form("Last 20 payments: ".
		  $ml->input(undef,{type=>"hidden",value=>20,name=>"n_pay"}).
		  $ml->input(undef,{value=>"Show",type=>"submit"}),
		  {method=>"post",action=>$searchurl}
	).
	$ml->form("Recent payments left in processing: ".
		  $ml->input(undef,{type=>"hidden",value=>"processing",name=>"status"}).
		  $ml->input(undef,{type=>"hidden",value=>"30",name=>"age"}).
		  $ml->input(undef,{value=>"Show",type=>"submit"}),
		  {method=>"post",action=>$searchurl}
	).
	"Show all accounts receivable and payable: ".
	$ui->Button(
	    label=>"Show",
	    url=>$this->link(inv=>undef,acct=>0,payment=>undef),
	    type=>"button",
	    tone=>"good",
	    size=>"l",
	)
	);

    $out{search} .= $ui->BlindBox(title=>"Advanced Search",
				  pane=>$advsearch,
				  open=>$config{Pay}{advanced_search},
				  size=>"l");

    # setup invoice and account

    if ($inv) {
	$this->{invoice} = new Modules::Finance::Receivable(id=>$inv);
	$this->{account} = new Modules::Finance::Account(id=>$this->{input}{acct} || $this->{invoice}->getdata("account_id"));
    }

    # make payment

    my $payout;
    if (defined $this->{input}{payment}) {
	my $payment = new Modules::Finance::Payment(id=>$this->{input}{payment});
	if (! $inv) {
	    $inv = $payment->getdata("receivable_id");
	    $this->{invoice} = new Modules::Finance::Receivable(id=>$inv);
	}
	$this->{account} = new Modules::Finance::Account(id=>$this->{invoice}->getdata("account_id"));
	$payout = $this->do_payment;
	$thistab = "payment";
    }

    # show invoice / payment

    if ($inv) {
	my $type = $this->{invoice}->is_paid ? "receipt" : "invoice";
	my $crypt = new ExSite::Crypt;
	my $crypt_last_invoice = $crypt->encrypt($this->{invoice}->id());
	
	$out{invoice} = $ui->ToolBar(cmd=>$this->{input}{cart},
				     tools=>[
					 {label=>"Manage Invoice",url=>$this->link(cart=>undef,payment=>undef),cmd=>undef},
					 {label=>"Cancellation/Refund",url=>$this->link(cart=>"refund",payment=>undef),cmd=>"refund"},
					 {label=>"Change Account",url=>$this->link(cart=>"move_invoice",payment=>undef),cmd=>"move_invoice"},
					 undef,
					 {label=>"Printer-friendly",url=>"javascript:popup_medium('".$this->link(_bare=>2,cart=>"print",last_invoice=>$crypt_last_invoice)."')"},
					 {label=>"E-mail $type",url=>$this->link(cart=>"email_invoice",payment=>undef),cmd=>"email_invoice"},
					 {label=>"Statement of Sale",url=>$this->link(cart=>"sale_stmt",payment=>undef),cmd=>"sale_stmt"}
				     ]);
	$this->{invoice} = new Modules::Finance::Receivable(id=>$inv);
	if (! $this->{invoice}->exists) {
	    # perhaps this is a custom invoice number
	    my @recv = $share{DB}->get_query("get custom invoice number",$this->{section_id},$inv);
	    if (scalar @recv > 0) {
		$ml->location($this->link(__plaintext=>1,inv=>$recv[0]{receivable_id}));
		return undef;
	    }
	}
	$this->{account} = new Modules::Finance::Account(id=>$this->{input}{acct} || $this->{invoice}->getdata("account_id"));
	$out{invoice} .= $this->show_invoice();
	$out{account} = $this->show_account();
	$out{payments} = $payout . $this->show_payments();
	$thistab or $thistab = "invoice";
    }
    elsif ($this->{input}{payment}) {
	my $payment = new Modules::Finance::Payment(id=>$this->{input}{payment});
	$this->{invoice} = $payment->receivable();
	$this->{account} = $payment->account();
	if ($this->{invoice}) {
	    $out{invoice} .= $this->show_invoice();
	}
	$out{account} = $this->show_account();
	$out{payments} = $payout . $this->show_payments();
	$thistab or $thistab = "invoice";
    }
    elsif ($this->{input}{acct}) {
	$this->{account} = new Modules::Finance::Account(id=>$this->{input}{acct});
	$out{account} = $this->show_account();
	$out{invoice} .= $this->show_invoices();
	$out{payments} = $payout . $this->show_payments();
	$thistab or $thistab = "account";
    }
    elsif (defined $this->{input}{acct}) {
	# show accounts receivable
	$out{account} = $this->accounts_receivable();
	$thistab = "account";
    }
    
    if (! $out{account} && $this->{input}{acctname}) {
	my @acct;
	my $matchname = "%$this->{input}{acctname}%";
	my @acct = $this->get_accounts($matchname);
	my $r = new ExSite::ReportBuilder(title=>"Accounts");
	$r->headers(["ID","Name","Balance Due"]);
	foreach my $acct (@acct) {
	    my $a = new Modules::Finance::Account(data=>$acct);
	    $r->push(
		     $a->id(),
		     $ml->a($a->name(),{href=>$this->link(acct=>$a->id,status=>undef,age=>undef)}),
		     $ml->div(sprintf("%.02f",$a->balance()),{class=>"num"}),
	    );
	}
	$out{account} .= $r->make();
	$thistab or $thistab = "account";
    }
    elsif ($this->{input}{status} && $this->{input}{age}) {
	my $time = new ExSite::Time();
	$time->add(-($this->{input}{age}),"days");
	my $sqldate = $time->write("sql_timestamp");
	my @invoice = $this->get_receivables($this->{input}{status},$sqldate);
	my $ilist = new ExSite::ObjectList(type=>"receivable",list=>\@invoice);
	my $r = new ExSite::ReportBuilder(title=>"Invoices");
	$r->headers(["ID","Date","Status","Account","Total","Options"]);
	while (my $inv = $ilist->next()) {
	    $r->push(
		$inv->id(),
		$inv->showdata("date"),
		$inv->showdata("status"),
		$inv->showdata("account_id"),
		$inv->total(),
		$ml->a($msg{"view"},{href=>$this->link(inv=>$inv->id,status=>undef,age=>undef)}),
	    );
	}
	if ($this->{input}{export}) {
	    # cancel html output
	    my $ctrl_panel_page = &get_obj("ML");
	    $ctrl_panel_page->cancel;
	    # output export instead
	    print "Content-type: application/vnd.ms-excel\n\n";
	    $r->export("excel");
	}
	else {
	    $r->tools($ml->a("export",{href=>$this->link(status=>$this->{input}{status},age=>$this->{input}{age},export=>1)}));
	    $out{invoice} .= $r->make();
	}
	$thistab or $thistab = "invoice";
    }
    elsif ($this->{input}{status} && $this->{input}{datefrom} && $this->{input}{dateto}) {
	my @invoice = $this->get_receivables($this->{input}{status},$this->{input}{datefrom},$this->{input}{dateto});
	my $ilist = new ExSite::ObjectList(type=>"receivable",list=>\@invoice);
	my $r = new ExSite::ReportBuilder(title=>"Invoices");
	$r->headers(["ID","Date","Status","Account","Total","Options"]);
	while (my $inv = $ilist->next()) {
	    $r->push(
		$inv->id(),
		$inv->showdata("date"),
		$inv->showdata("status"),
		$inv->showdata("account_id"),
		$inv->total(),
		$ml->a("view",{href=>$this->link(inv=>$inv->id,status=>undef,age=>undef)}),
	    );
	}
	if ($this->{input}{export}) {
	    # cancel html output
	    my $ctrl_panel_page = &get_obj("ML");
	    $ctrl_panel_page->cancel;
	    # output export instead
	    print "Content-type: application/vnd.ms-excel\n\n";
	    $r->export("excel");
	}
	else {
	    $r->tools($ml->a("export",{href=>$this->link(status=>$this->{input}{status},datefrom=>$this->{input}{datefrom},dateto=>$this->{input}{dateto},export=>1)}));
	    $out{invoice} .= $r->make();
	}
	$thistab or $thistab = "invoice";
    }
    elsif ($this->{input}{n_pay}) {
	my @pay = $this->get_payments();
	my $plist = new ExSite::ObjectList(type=>"payment",list=>\@pay);
	my $r = new ExSite::ReportBuilder(title=>"Payments");
	$r->headers(["ID","Date","Status","Method","Invoice","Account","Amount"]);
	my $npay = 0;
	while (my $p = $plist->next()) {
	    $npay++;
	    $r->push(
		$p->id(),
		$p->showdata("date"),
		$p->showdata("status"),
		$p->showdata("method"),
		$p->showdata("receivable_id"), ### FIXME: invoice name
		$p->showdata("account_id"),
		$p->showdata("amount")
	    );
	    last if ($npay == $this->{input}{n_pay});
	}
	if ($this->{input}{export}) {
	    # cancel html output
	    my $ctrl_panel_page = &get_obj("ML");
	    $ctrl_panel_page->cancel;
	    # output export instead
	    print "Content-type: application/vnd.ms-excel\n\n";
	    $r->export("excel");
	}
	else {
	    $r->tools($ml->a("export",{href=>$this->link(n_pay=>$this->{input}{n_pay},export=>1)}));
	    $out{payments} .= $r->make();
	}
	$thistab or $thistab = "payments";
    }

    my $ntab = 0;
    my $tabnum = 0;
    foreach my $tab (qw(search payments invoice account)) { 
	if ($out{$tab}) {
	    push @panes, $out{$tab};
	    push @tabs, ucfirst $tab;
	    if ($thistab eq $tab) { $tabnum = $ntab; }
	    $ntab++;
	}
    }
    if (! $tabnum && $ntab > 1) { $tabnum = 1; }
    
    my $out = $ml->script(undef,{type=>"text/javascript",src=>"$config{server}{HTMLpath}/_ExSite/js/date.js"});
    $out .= $ml->script(undef,{type=>"text/javascript",src=>"$config{server}{HTMLpath}/_ExSite/js/jquery.datePicker.js"});
    $out .= $ml->link(undef,{rel=>"stylesheet",type=>"text/css",media=>"screen",href=>"$config{server}{HTMLpath}/_ExSite/css/datePicker.css"});
    $out .= $ml->script("Date.firstDayOfWeek = 0;\nDate.format = 'yyyy-mm-dd';\n\$(function() {\n\$('.date-pick').datePicker({startDate:'$config{form}{date_picker_start_date}'});\n});\n",
			{type=>"text/javascript",charset=>"utf-8"});

    $out .= $ui->DynTabBox(
	tabs=>\@tabs,
	panes=>\@panes,
	thistab=>$tabnum,
	width=>"100%",
	);
    return $out;
}

sub this_account_id {
    my $this = shift;
    if ($this->{input}{acct}) {
	return $this->{input}{acct};
    }
    elsif ($this->{input}{inv}) {
	my $inv = new Modules::Finance::Receivable(id=>$this->{input}{inv});
	return $inv->getdata("account_id");
    }
    elsif ($this->{input}{payment}) {
	my $payment = new Modules::Finance::Payment(id=>$this->{input}{payment});
	return $payment->getdata("account_id");
    }
    return undef;
}

sub get_accounts {
    my ($this,$matchname) = @_;
    return $this->{scope} eq "global" ?
	$share{DB}->get_query("get global accounts by name",$matchname) :
	$share{DB}->get_query("get local accounts by name",$this->{section_id},$matchname);
}

sub get_receivables {
    my ($this,$status,$start,$end) = @_;
    if ($this->{scope} eq "global") {
	if ($end) {
	    # date range
	    $end .= " 23:59:59";
	    return $share{DB}->get_query("get global receivables in date range",$status,$start,$end);
	}
	elsif ($start) {
	    # since
	    return $share{DB}->get_query("get global receivables since date",$status,$start);
	}
	else {
	    return $share{DB}->get_query("get global receivables");
	}
    }
    else {
	my @r;
	if ($end) {
	    # date range
	    $end .= " 23:59:59";
	    @r = $share{DB}->get_query("get local receivables in date range",$this->{section_id},$status,$start,$end);
	}
	elsif ($start) {
	    # since
	    @r = $share{DB}->get_query("get local receivables since date",$this->{section_id},$status,$start);
	}
	else {
	    @r = $share{DB}->get_query("get local receivables",$this->{section_id});
	}
	# filter receivables attached to accounts for other sections if not an administrator
	# and manager does not have key for section
	if (!$share{DB}->is_admin) {
	my @filtered;
	foreach my $r (@r) {
		push(@filtered,$r) if ($r->{account_section} && $share{DB}->owns($r->{account_section}));
	}
	return @filtered;	
	}
	return @r;
    }
}

sub get_payments {
    my ($this) = @_;
    return $this->{scope} eq "global" ?
	$share{DB}->get_query("get global payments") :
	$share{DB}->get_query("get local payments",$this->{section_id});
}

sub show_invoice {
    my $this = shift;
    if ($this->{input}{cart} eq "email_invoice") {
	return $this->email_invoice();
    }
    elsif ($this->{input}{cart} eq "sale_stmt") {
	return $this->sale_statement();
    }
    elsif ($this->{input}{cart} eq "refund") {
	return $this->refund();
    }
    elsif ($this->{input}{cart} eq "move_invoice") {
	return $this->move_invoice();
    }
    my $out;
    my $inv = $this->{invoice};
    #$out .= $ml->h1($inv->name);
    my $opt;

    if ($this->{input}{invstat}) {
	if ($this->{input}{invstat} eq "active") {
	    # use activate() in case we have any special activation handlers
	    if ($inv->activate()) {
		$ml->p("Status updated.");
	    }
	}
	else {
	    $inv->setdata("status",$this->{input}{invstat});
	    $out .= $ml->p("Status updated.") if ($inv->save() > 0);
	}
    }

    my $istat = $inv->getdata("status");
    my @invstat = split(/\|/,$share{DB}{map}->regexp("list:receivable_status"));
    foreach my $stat (@invstat) {
	$opt .= $istat eq $stat ?
	    $ml->option($stat,{selected=>undef}) : $ml->option($stat);
    }
    my $statform = $ml->select($opt,{name=>"invstat"}).
	$ml->input(undef,{type=>"submit",value=>"Change status"});
    if ($istat eq "inactive") {
	$statform .= $ui->Overlay(
	    label=>"Go through checkout",
	    title=>"Go through checkout",
	    class=>"button",
	    pane=>$ml->p("This invoice is inactive, which means the sale was not completed. To complete this sale, go through checkout to confirm account details, add taxes, surcharges, and payments.").$ml->p($ui->Button(type=>"link-button",label=>"Checkout now",url=>$this->link(cart=>"recheckout"),tone=>"important")),
	    );
    }
    $out .= $ml->form($statform,{method=>"post",action=>$this->link()});

    # check for orphaned payments
    if ($istat !~ /^(active|advisory)$/) {
	my $pay = $inv->get_payments();
	if ($pay && $pay->count > 0) {
	    my $goodpayment = 0;
	    while (my $p = $pay->next) {
		$goodpayment++ if ($p->is_paid);
	    }
	    if ($goodpayment) {
		$out .= $ui->ErrorBox(title=>"Warning",
				      pane=>"This invoice is marked as ".$ml->strong($istat).", but has payments recorded on it. This mismatch will create accounting imbalances. The invoice should be set to active or advisory, or the payments should be canceled.");
	    }
	}
    }

    if ($istat =~ /advisory/) {
	$out .= $ui->ErrorBox(title=>"Advisory Invoice",
			      pane=>"This invoice is advisory only, and does not create a new debit in the account. It is simply a statement of an outstanding balance from previous purchases that needs to be paid. The details of those previous purchases can be found in other invoices under the account statement.");
    }

    if ($inv->is_payable) {
	$out .= $ui->ErrorBox(title=>"Payable",
			      pane=>"This is payable to the account holder, not the other way around. Usually this is due to a refund, in which case this statement describes the refunded items and the total to be refunded to the account holder.");
    }

    $out .= $inv->show(summarize_surcharges=>1,
		       date=>"datetime",
		       description=>1,
		       unitcost=>$this->{config}{unitcost},
		       size=>$this->{config}{size},
		       zero_cost=>$this->{config}{zero_cost},
		       deletions=>$this->{config}{show_deletions},
		       objects=>$this->{config}{show_objects});

#    my @buttons;
#    if ($this->{input}{cart} ne "print") {
#	my $crypt = new ExSite::Crypt;
#	my $crypt_last_invoice = $crypt->encrypt($this->{invoice}->id());
#	push @buttons, $ml->a($msg{"Printer-friendly version"},{href=>"javascript:popup_medium('".$this->link(_bare=>2,cart=>"print",last_invoice=>$crypt_last_invoice)."')",class=>"button"});
#    }
#    if ($inv->is_valid) {
#	my $type = $inv->is_paid ? "receipt" : "invoice";
#	push @buttons, $ml->a($msg{"E-mail $type"},{href=>$this->link(cart=>"email_invoice",payment=>undef),class=>"button"});
#    }
#    push @buttons, $ml->a($msg{"Sale Statement"},{href=>$this->link(cart=>"sale_stmt",payment=>undef),class=>"button"});
#    if (scalar @buttons) {
#	$out .= $ml->p(join("\n",@buttons));
#    }

    $out .= $this->show_payments($this->{input}{inv});
    return $ml->h1($inv->name) . $out;
}

sub email_invoice {
    my $this = shift;
    my $old_version;
    if (! $share{Page} && $this->{config}{default_notification_language}) {
	$old_version = (tied %msg)->current_version;
	(tied %msg)->version($this->{config}{default_notification_language});
	(tied %msg)->nohighlight;
    }
    my $out = $ml->h1("Email Invoice/Receipt");
    my $inv = $this->{invoice};
    if ($inv->is_valid) {
	my $input = new ExSite::Input();
	my $post = $input->post;
	my $type = $inv->is_paid ? "receipt" : "invoice";
        my $invoice_txt = $this->get_text_of_invoice(
	    item_descriptions=>$this->{config}{item_descriptions},
            );
	(tied %msg)->nohighlight();
	if (scalar keys %$post > 0) {
	    my $message = $post->{preamble};
	    my $br = $ml->br;
	    $message =~ s/\s+$//;
	    $message =~ s/\r?\n/$br/g;
	    $message = $ml->p($message);
	    $message .= $ml->div($invoice_txt,{style=>"border:1px dotted grey; padding:10px"});
	    my $sig = $post->{signature};
	    $sig =~ s/\r?\n/$br/g;

	    $message .= $ml->p($sig);
	    &ExSite::Mail::send(
		to=>$post->{to},
		from=>$post->{from},
		subject=>$post->{subject},
		body=>$message
		);
	    $out .= $ml->h2("Message sent.",{style=>"color:red"});
	    $out .= $ml->div("To: $post->{to}${br}From: $post->{from}$br".$ml->strong("Subject: $post->{subject}"),{style=>"background-color:#eee; padding:20px"});
	    $out .= $ml->div($message,{style=>"background-color:#ddd; padding:20px"});
	    $out .= $ml->p($ml->a("Back to invoice",{href=>$this->link(cart=>undef),class=>"button"}));
	}
	else {
	    my $to = $inv->account->email($this->{config}{primary_contact});
	    my $name = $inv->account->name();
	    my $from = $share{DB}->my_email;
	    my $f = new ExSite::FormBuilder();
	    my $subject = $msg{"Your $type"};
	    my $message;
	    $message .= &substitute($msg{"Dear [[account]],"}."\n\n", { account => $name });
	    $message .= $msg{$this->{config}{message}{thanksForPurchase}};
	    if ($type eq "receipt") {
		$message .= "\n\n".$msg{$this->{config}{message}{receipt}};
	    }
	    my $signature;
	    if ($signature) { $signature .= "\n\n"; }
	    $signature .= $msg{"Regards,"}."\n".$share{DB}->my_name."\n";
	    my $site = $share{DB}->this_site;
	    $signature .= $site ? $site->{title} : $config{site}{name};
	    $f->input(type=>"text",name=>"to",prompt=>"To",required=>1,value=>$to);
	    $f->input(type=>"text",name=>"from",prompt=>"From",required=>1,value=>$from);
	    $f->input(type=>"text",name=>"subject",prompt=>"Subject",required=>1,size=>60,value=>$subject);
	    $f->input(type=>"textarea",name=>"preamble",prompt=>"Message",rows=>4,cols=>80,value=>$message);
	    $f->input(type=>"preformatted",name=>"invoice",prompt=>"Invoice (read-only)",input=>$invoice_txt);
	    $f->input(type=>"textarea",name=>"signature",prompt=>"Signature",rows=>4,cols=>80,value=>$msg{$signature});
	    $f->set("buttons",$ml->input(undef,{type=>"submit",value=>"Send"}).$ml->input(undef,{type=>"button",value=>"Cancel",class=>"cancel",onclick=>"history.back()"}));
	    $out .= $f->make;
	}
    }
    else {
	$out .= $this->error("Cannot email - invoice is not active");
    }
    if ($old_version) {
	(tied %msg)->version($old_version);
	(tied %msg)->restore;
    }
    return $out;
}

sub show_invoices {
    my ($this) = @_;
    return undef if ($this->{input}{cart} eq "email_invoice");
    my $receivables = $this->{account}->get_children("receivable")->{receivable};
    my $title = ($this->{invoice} ? "Other invoices for " : "Invoices for ").
	$this->{account}->name;
    my $r = new ExSite::ReportBuilder(title=>$title);
    $r->headers(["Date","Invoice","Status","Amount"]);
    $r->nodata("No invoices recorded.");
#    $r->tools($ml->a("+ Add invoice",{href=>$this->link(invoice=>0)}));
    my $ninv = 0;
    while (my $rcv = $receivables->next()) {
	my $id = $rcv->id();
	next if ($id == $this->{input}{inv});
	$r->push(
		 $rcv->showdata("date"),
		 $ml->a($rcv->description(),{href=>$this->link(inv=>$id,payment=>undef)}),
		 $rcv->showdata("status"),
		 $rcv->total(),
		 );
	$ninv++;
    }
    return $ninv ? $r->make() : undef;
}

sub show_account {
    my $this = shift;
    return $this->edit_acctinfo() if ($this->{input}{cart} eq "acctinfo");
    return $this->email_account() if ($this->{input}{cart} eq "email");
    my (@tools,$tool);
    my $url = new ExSite::URI;
    $url->query(cart=>undef);
    my $date = new ExSite::Time();
    my $thisyear = $date->write("raw_year");
    my $thismonth = $date->write("%YYYY-%MM");
    $date->add_approximate(-1,"month");
    my $lastmonth = $date->write("%YYYY-%MM");
    $date->add_approximate(1,"month");
    $date->add_approximate(-1,"year");
    my $lastyear = $date->write("raw_year");
    my $acctid = $this->{account}->id;
    my @datemenu = (
	{label=>"this month",url=>$this->link(month=>$thismonth,days=>undef,year=>undef,acct=>$acctid,inv=>undef)},
	{label=>"last month",url=>$this->link(month=>$lastmonth,days=>undef,year=>undef,acct=>$acctid,inv=>undef)},
	{label=>"last 30 days",url=>$this->link(days=>30,month=>undef,year=>undef,acct=>$acctid,inv=>undef)},
	{label=>"last 90 days",url=>$this->link(days=>90,month=>undef,year=>undef,acct=>$acctid,inv=>undef)},
	{label=>"this year",url=>$this->link(year=>$thisyear,days=>undef,month=>undef,acct=>$acctid,inv=>undef)},
	{label=>"last year",url=>$this->link(year=>$lastyear,days=>undef,month=>undef,acct=>$acctid,inv=>undef)},
	{label=>"last 365 days",url=>$this->link(days=>365,month=>undef,year=>undef,acct=>$acctid,inv=>undef)},
	{label=>"all time",url=>$this->link(days=>undef,month=>undef,year=>undef,acct=>$acctid,inv=>undef)},
	);
    push @tools, { label=>"Date range", links=>\@datemenu };
    if ($this->{input}{allx}) {
	push @tools, { label=>"Valid transactions only", url=>$this->link(allx=>undef,cart=>undef,inv=>undef) };
    }
    else {
	push @tools, { label=>"All transactions", url=>$this->link(allx=>1,cart=>undef,inv=>undef,acct=>$acctid)};
    }

    my $acct_id = $this->{input}{acct} || $this->{account}->id;
    $tool = $ml->a("Change account name/ID",{href=>$this->link(cart=>"acctinfo",payment=>undef,inv=>undef,acct=>$acct_id)});
    my $contact = $this->{account}->get_contact($this->{config}{primary_contact});
    my $sid = $this->get_section_id;
    if ($contact) {
	$tool .= $ml->a("Update contact info",{href=>"javascript:popup_large('$config{server}{server}$config{server}{CGIpath}/$config{prog}{ctrlpanel}/AddrBook?section_id=$sid&tab=lookup&contact_id=".$contact->id."')"});
    }
    else {
	$tool .= $ml->a("Add contact info",{href=>"javascript:popup_large('$config{server}{server}$config{server}{CGIpath}/$config{prog}{ctrlpanel}/AddrBook?section_id=$sid&tab=update&account_id=".$this->{account}->id."')"});
    }
    push @tools, $tool;
    push @tools, $ml->a("E-mail",{href=>$this->link(cart=>"email")}).$ml->a("Print",{href=>$this->link(inv=>undef,cart=>"print")});

    my $out = $ui->ToolBar(tools=>\@tools);
    $out .= $ml->h1("Statement of Account");
    $out .= $this->{account}->show(
				   receivable_uri=>$url,
				   payment_uri=>$url,
				   contact_layout=>"table",
				   alltransactions=>$this->{input}{allx},
				   year=>$this->{input}{year},
				   month=>$this->{input}{month},
				   from=>$this->{input}{from},
				   to=>$this->{input}{to},
				   days=>$this->{input}{days},
#				   tools=>$tools,
				   );
    if ($this->{account}->balance > 0.00) {
	my $astat = $this->{account}->stats();
	if ($astat->{last_invoice_total} != -$astat->{balance}) {
	    # don't show the pay balance button if it looks like only
	    # a single invoice is owning - use pay invoice instead
	    $out .= $ml->p($ui->Button(label=>"Pay account balance",url=>$this->link(inv=>undef,payment=>0)),{style=>"text-align:right"});
	}
    }
    return $out;
}

sub email_account {
    my $this = shift;
    my $acct = $this->{account} || new Modules::Finance::Account(id=>$this->{input}{acct});
    my $out = $ml->h1("Email Account Statement");
    my $input = new ExSite::Input();
    my $post = $input->post;
    my $statement = $acct->show(
	contact_layout=>"table",
	year=>$this->{input}{year},
	month=>$this->{input}{month},
	from=>$this->{input}{datefrom},
	to=>$this->{input}{dateto},
	days=>$this->{input}{days},
	);
    if (scalar keys %$post > 0) {
	my $message = $post->{preamble};
	my $br = $ml->br;
	$message =~ s/\s+$//;
	$message =~ s/\r?\n/$br/g;
	$message = $ml->p($message);
	$message .= $ml->style(".num { text-align:right; }\n");
	$message .= $ml->div($statement,{style=>"border:1px dotted grey; padding:10px"});
	my $sig = $post->{signature};
	$sig =~ s/\r?\n/$br/g;
	$message .= $ml->p($sig);
	&ExSite::Mail::send(
	    to=>$post->{to},
	    from=>$post->{from},
	    subject=>$post->{subject},
	    body=>$message
	    );
	$out .= $ml->h2("Message sent.",{style=>"color:red"});
	$out .= $ml->div("To: $post->{to}${br}From: $post->{from}$br".$ml->strong("Subject: $post->{subject}"),{style=>"background-color:#eee; padding:20px"});
	$out .= $ml->div($message,{style=>"background-color:#ddd; padding:20px"});
	$out .= $ml->p($ml->a("Back to account statement",{href=>$this->link(cart=>undef),class=>"button"}));
    }
    else {
	my $to = $acct->email;
	my $from = $share{DB}->my_email;
	my $f = $share{DB}->form();
	my $subject = "Your Account Statement";
	my $message = "Here is a copy of your account statement:";
	my $site = $share{DB}->this_site;
	my $sitename = $site ? $site->{title} : $config{site}{name};
	my $signature = "\n\nRegards,\n".$share{DB}->my_name."\n$sitename";

	$f->input(type=>"text",name=>"to",prompt=>"To",required=>1,value=>$to);
	$f->input(type=>"text",name=>"from",prompt=>"From",required=>1,value=>$from);
	$f->input(type=>"text",name=>"subject",prompt=>"Subject",required=>1,size=>60,value=>$subject);
	$f->input(type=>"textarea",name=>"preamble",prompt=>"Message",rows=>4,cols=>80,value=>$message);
	$f->input(type=>"preformatted",name=>"statement",input=>$ui->ScrollBox(title=>"Account Statement",pane=>$statement));
	$f->input(type=>"textarea",name=>"signature",prompt=>"Signature",rows=>4,cols=>80,value=>$signature);
	$f->set("buttons",$ml->input(undef,{type=>"submit",value=>"Send"}).$ml->input(undef,{type=>"button",value=>"Cancel",class=>"cancel",onclick=>"history.back()"}));
	$out .= $f->make;
    }
	
    return $out;
}

sub edit_acctinfo {
    my $this = shift;
    if (scalar keys %{$this->{post}} > 0) {
	$this->{account}->do_edit();
	$ml->location($this->link(__plaintext=>1,cart=>undef));
    }
    else {
	return $ml->h1("Account Name/ID").
	    $this->{account}->edit(
		hide=>["section_id"],
		action=>$this->link(),
	    );
    }
}

sub accounts_receivable {
    my $this = shift;
    my $out;
    my $db = $share{DB};
    my $in = $this->{input};
    # get reportable data
    my @receivable = $this->get_receivables();
    my @payment = $this->get_payments();
    my @data = sort { $a->{date} cmp $b->{date} } (@receivable,@payment);
    
    # merge into single account row
    my %acct;
    foreach my $data (@data) {
	my $aid = $data->{account_id};
	if (! exists $acct{$aid}) {
	    $acct{$aid} = { 
		account => $data->{account_id},
		name => $data->{name},
	    };
	}
	my @rdata;
	if ($data->{payment_id}) {
	    # payment
	    next if ($data->{status} !~ /paid|received/);
	    $acct{$aid}{credit} += $data->{amount};
	}
	elsif ($data->{type} eq "receivable") {
	    # receivable
	    next if ($data->{status} ne "active");
	    my $r = new Modules::Finance::Receivable(data=>$data);
	    my $total = $r->total;
	    $acct{$aid}{debit} += $total;
	}
	else {
	    # payable 
	    next if ($data->{status} ne "active");
	    my $r = new Modules::Finance::Receivable(data=>$data);
	    my $total = $r->total;
	    $acct{$aid}{credit} += $total;
	}
	if ($data->{date} cmp $acct{$aid}{date} > 0) { 
	    $acct{$aid}{date} = $data->{date};
	}
    }
    
    # reports
    my $t = new ExSite::Time();
    my $r = new ExSite::ReportBuilder();
    my $url = new ExSite::URI(uri=>"$config{server}{server}$config{server}{CGIpath}/$config{prog}{ctrlpanel}/Pay");
    my @acctinfo = @{$this->report_account_info()};
    $r->title("Accounts Receivable");
    $r->nodata("No accounts receivable.");
    $r->headers(["Last Transaction",@acctinfo,"Credit","Debit","Balance"]);
    foreach my $acct (sort { $a->{date} cmp $b->{date} } values %acct) {
	next if (! $acct->{credit} && ! $acct->{debit});
	my $balance = $acct->{debit} - $acct->{credit};
	next if (sprintf("%.02f",$balance) <= 0.00);
	my $fbalance = $balance > 0 ?
	    $ml->div(sprintf("%.02f",$balance),{class=>"num"}) :
	    $ml->div(sprintf("%.02f",$balance),{class=>"num debit"});
	$url->query(section_id=>$this->{section_id},acct=>$acct->{account});
	my @rdata = (
	    $acct->{date},
	    @{$this->report_account_info($acct->{account},$url)},
	    $ml->div(sprintf("%.02f",$acct->{credit}),{class=>"num"}),
	    $ml->div(sprintf("%.02f",$acct->{debit}),{class=>"num"}),
	    $fbalance,
	    );
	$r->push(@rdata);
    }
    $r->tools($ml->a("export",{href=>$this->link(export=>"ar")}));
    $r->foot("Accounts receivable = insufficient payment by the account holder.");
    if ($this->{input}{export} eq "ar") {
	# cancel html output
	my $ctrl_panel_page = &get_obj("ML");
	$ctrl_panel_page->cancel;
	# output export instead
	print "Content-type: application/vnd.ms-excel\ncontent-disposition: attachment; filename=accounts_receivable.xls\n\n";
	$r->export("excel");
	return;
    }
    $out .= $r->make;

    $r->init;
    $r->title("Accounts Payable");
    $r->nodata("No accounts payable.");
    $r->headers(["Last Transaction",@acctinfo,"Credit","Debit","Balance"]);
    foreach my $acct (sort { $a->{date} cmp $b->{date} } values %acct) {
	next if (! $acct->{credit} && ! $acct->{debit});
	my $balance = $acct->{debit} - $acct->{credit};
	next if (sprintf("%.02f",$balance) >= 0.00);
	my $fbalance = $balance > 0 ?
	    $ml->div(sprintf("%.02f",$balance),{class=>"num"}) :
	    $ml->div(sprintf("%.02f",$balance),{class=>"num debit"});
    $url->query(section_id=>$this->{section_id},acct=>$acct->{account});	    
	my @rdata = (
		     $acct->{date},
		     @{$this->report_account_info($acct->{account},$url)},
		     $ml->div(sprintf("%.02f",$acct->{credit}),{class=>"num"}),
		     $ml->div(sprintf("%.02f",$acct->{debit}),{class=>"num"}),

		     $fbalance,
		     );
	$r->push(@rdata);
    }
    $r->tools($ml->a("export",{href=>$this->link(export=>"ap")}));
    $r->foot("Accounts payable = overpayment by the account holder.");
    if ($this->{input}{export} eq "ap") {
	# cancel html output
	my $ctrl_panel_page = &get_obj("ML");
	$ctrl_panel_page->cancel;
	# output export instead
	print "Content-type: application/vnd.ms-excel\ncontent-disposition: attachment; filename=accounts_payable.xls\n\n";
	$r->export("excel");
	return;
    }
    $out .= $r->make;
    return $out;
}

# reroute to Finance::report_account_info
sub report_account_info {
    my ($this,$account_id,$url) = @_;
    my $finance = &ExSite::Module::get_module("Finance");
    $finance->{section_id} = $this->{section_id};
    return $finance->report_account_info($account_id,$url);
}

sub show_payments {
    my ($this,$inv) = @_;
	return $this->error("Permission denied") if (!$this->{account}->allow);
    my $acct_id = $this->{account}->id();
    my $match = { account_id => $acct_id };
    if ($inv) { $match->{receivable_id} = $inv; }
    my @pay = $share{DB}->fetch_match("payment",$match);
    my $r = new ExSite::ReportBuilder(title=> $inv ? 
				      "Payments on Invoice $inv" : 
				      "Payments on Account $acct_id (".$this->{account}->name.")");
    $r->headers(["Date","Method","Note","Invoice","Status","Amount"]);
    $r->nodata("No payments recorded.");
    my $nopay = 0;
    if ($inv) {
	my $recv = new Modules::Finance::Receivable(id=>$inv);
	$nopay = ! $recv->is_active();
    }
    my $toollink = $nopay ? 
	"javascript:alert('You can only add payments to active invoices.')" :
	$this->link(payment=>0,cart=>undef);
    $r->tools($ml->a("+ Add payment",{href=>$toollink,class=>"button_sm"}));
    foreach my $p (@pay) {
	my $pmt = new Modules::Finance::Payment(data=>$p);
	$r->push(
		 $pmt->showdata("date"),
		 $pmt->showdata("method"),
		 $pmt->showdata("note"),
		 $pmt->showdata("receivable_id"),  ### FIXME: invoice name
		 $ml->a($pmt->showdata("status"),{href=>$this->link(payment=>$pmt->id,cart=>undef)}),
		 $pmt->showdata("amount")
		 );
    }
    return $r->make();
}

sub do_payment {
    my ($this) = @_;
    my $db = $share{DB};
    my $out;

    my $pid = $this->{input}{payment};
    my $inv = $this->{post}{inv} || $this->{query}{inv}; # post data overrides the invoice we are looking at
    if (! $inv) {
	my $payment = new Modules::Finance::Payment(id=>$this->{input}{payment});
	$inv = $payment->getdata("receivable_id");
    }

    if ($this->{input}{method}) {
	my $p = new Modules::Finance::Payment();
	if ($pid) {
	    $p->setup(id=>$pid);
	}
	else {
	    if ($this->{input}{amount} =~ /^-?\d+(.\d\d)?$/) {
		# can only set amounts on new payments
		$p->setdata("amount",$this->{input}{amount});
	    }
	    else {
		return $this->error("Invalid amount!  Please use only digits and a decimal point.");
	    }
	}
	$p->setdata("status",$this->{input}{status});
	$p->setdata("method",$this->{input}{method});
	$p->setdata("note",$this->{input}{note});
	$p->setdata("uid", $db->my_uid());
	if ($this->{input}{acct}) {
	    $p->setdata("account_id", $this->{input}{acct});
	}
	if ($inv) {
	    $this->{invoice} = new Modules::Finance::Receivable(id=>$inv);
	    $p->setdata("receivable_id", $inv);
	    if (! $this->{input}{acct}) {
		$p->setdata("account_id", $this->{invoice}->getdata("account_id"));
	    }
	}
	else {
	    # payment not tied to invoice, but still need to get account
	    $p->setdata("receivable_id", 0);
	    if ($this->{input}{acct}) {
		if ($this->{input}{inv}) {
		    # in case query inv is different from post inv
		    my $inv2 = new Modules::Finance::Receivable(id=>$this->{input}{inv});
		    $p->setdata("account_id", $inv2->getdata("account_id"));
		}
		else {
		    # just take it from the query
		    $p->setdata("account_id", $this->{input}{acct});
		}
	    }
	}
	if ($p->save()) {
	    $out .= $ui->SuccessBox(title=>"Payment recorded",pane=>"Payment information updated successfully.");
	    if ($this->{input}{post}) {
		if ($this->{input}{status} eq "paid") {
		    if ($this->{invoice} && $this->{invoice}->defined) {
			$this->{account} = $this->{invoice}->account();
			$out .= $this->receipt_success($inv,$p->get());
		    }
		    else {
			$out .= $this->warn("Payment post-processing skipped because this payment is not connected to a specific invoice.");
		    }
		}
		else {
		    $out .= $this->warn("Payment post-processing skipped because this is not a valid payment.");
		}
	    }
	}
	else {
	    $out .= $p->show_diagnostics("error","html");
	}
    }

    my ($payamt,$notes);
    if ($pid) {
	$out .= $ml->h2("Edit Payment Information");
    }
    else {
	$out .= $ml->h2("Enter Payment Information");
	if ($inv) {
	    my $invoice = new Modules::Finance::Receivable(id=>$inv);
	    if (! $invoice->is_paid && ! $invoice->has_payments) {
		$payamt = $invoice->total;
	    }
	}
	elsif ($this->{input}{acct}) {
	    if (! $this->{account} || ! $this->{account}->defined) {
		$this->{account} = new Modules::Finance::Account(id=>$this->{input}{acct});
	    }
	    $payamt = $this->{account}->balance();
	}
    }
    my $br = $ml->br;
    $out .= $ml->p(
	$ui->HelpPopup(
	    label=>"How to record a payment",
	    pane=>$ml->strong("Amount").": Enter a negative amount if entering a refund.$br".
	    $ml->strong("Identifier").": You can record check/cheque numbers, or credit card info here.$br".
	    $ml->strong("Status").": set to 'paid' for good payments, 'canceled' otherwise. Other payment statuses are used by automatic payment processing, and should be ignored for manual payments.$br".
	    $ml->strong("Invoice").": if paying a particular invoice, select it here.$br".
	    $ml->strong("Note").": additional notes about the payment, if there is anything important to remember. You can optionally include the notes on the receipt itself.$br".
	    $ml->strong("Perform final processing of sale").": Select this if you want a receipt to go out, and for the purchased items to be processed.",
	)
	);
    
    my $f = new ExSite::FormBuilder( method=>"post", action=>$this->link() );
    $f->template(
		 $ml->table(
			    $ml->tr(
				    $ml->td("[[amount:prompt]]".$ml->br."[[amount:input]]&nbsp;&nbsp;&nbsp;").
				    $ml->td("[[method:prompt]]".$ml->br."[[method:input]]&nbsp;&nbsp;&nbsp;").
				    $ml->td("[[ident:prompt]]".$ml->br."[[ident:input]]&nbsp;&nbsp;&nbsp;").
				    $ml->td("[[status:prompt]]".$ml->br."[[status:input]]&nbsp;&nbsp;&nbsp;").
				    $ml->td("[[inv:prompt]]".$ml->br."[[inv:input]]")
				    ),
			    { cellpadding=>0, cellspacing=>0 }
			    ).	
		 $ml->p("[[note:prompt]]".$ml->br."[[note:input]]").
		 $ml->p("[[include_payment_note:input]] [[include_payment_note:prompt]]").		 
		 $ml->p("[[post:input]] [[post:prompt]]").
		 $ml->p("[[hint:input]]")
		 );
    $f->validate("validate_invoice(this)",
		 "function validate_invoice(f) {
      if (f.status.value == 'paid' &&
          f.inv.value.length == 0 &&
          f.post.checked) {
          alert('Cannot perform final processing of sale unless you select an invoice!');
          return false;
      }
}");
    my $p = $pid ? $db->fetch("payment",$pid) : {};
    my $amount = $p->{amount} || $payamt;

#### FIXME: code, ident

    $f->input(name=>"amount",prompt=>"Amount",type=>"text",
	      size=>12,
	      required=> $pid ? 0 : 1,
	      disabled=> $pid ? 1 : 0,
	      value=>$amount,
	      );
    $f->input(name=>"ident",prompt=>"Identifier",type=>"text",
	      size=>12,value=>$p->{ident},
	      );
    my @opt = split(/\|/,$db->{map}->regexp("list:payment_method"));
    $f->input(name=>"method",prompt=>"Payment method",
	      type=>"select",required=>1,
	      value=>$p->{method},
	      options=>\@opt);
    @opt = split(/\|/,$db->{map}->regexp("list:payment_status"));
    $f->input(name=>"status",prompt=>"Payment status",
	      type=>"select",required=>1,
	      value=>($p->{status} || "paid"),
	      options=>\@opt);
    $f->input(name=>"include_payment_note",
	      prompt=>"Include payment note with receipt ",
	      tail=>" ".$ui->HelpPopup(
		  label=>"what is this?",
		  message=>"If a note has been entered above, checking this box will add 
the note to the receipt that is sent to to purchaser.",
	      ),
	      checked=>$this->{config}{include_payment_note},
	      type=>"checkbox");
    $f->input(name=>"post",
	      prompt=>"Perform final processing of sale ",
	      tail=>" ".$ui->HelpPopup(
		  label=>"what is this?",
		  message=>"Certain actions do not get performed until payment 
is confirmed. Examples include sending of receipts, activation of memberships 
or registrations, and so on. Check this box if you want to perform these final 
steps of the sale at this time. Leave the box unchecked if you
simply want to record a payment on the account.",
	      ),
	      checked=>$this->{config}{postprocess},
	      type=>"checkbox");
    @opt = map { $_->{receivable_id} } 
        $db->fetch_match("receivable",{account_id=>$this->this_account_id,status=>"active"});
    $f->input(name=>"inv",prompt=>"Invoice",
	      type=>"select",value=>$inv,
	      nullvalue=>"N/A",
	      options=>\@opt);
    $f->input(name=>"note",prompt=>"Notes",type=>"textarea",
	      size=>200,value=>$p->{note});
#    if ($pid) {
#	$f->input(name=>"payment_id",type=>"hidden",value=>$pid);
#    }

    $out .= $f->make();
    return $out;
}

sub invoice_link {
    my ($this,$table,$column,$data,$id,$datatype) = @_;
    my (undef,$ftable) = split /[:=]/,$datatype;
    if ($ftable eq "receivable") {
	return $ml->a($data,{href=>&relink(inv=>$data,cart=>undef)});
    }
    else {
	# look up foreign row
	my %fdata = $this->fetch($ftable,$data);
	my $fkey = $this->get_key($ftable);
	my $label = $this->record_label($ftable,$fdata{$fkey},\%fdata);
	# print primary column of foreign record
	if ($ftable eq "account") {
	    return $ml->a($label,{href=>&relink(acct=>$data,cart=>undef)});
	}
	return $label;
    }
}

sub summary {
    my ($this,$section_id) = @_;
    $this->setup_queries();
    $section_id or $section_id = $this->get_section_id();
    my $date = new ExSite::Time;
    my @inv = $share{DB}->get_query("get recent local purchases",$section_id,5);
    my $r = new ExSite::ReportBuilder(title=>$msg{"Recent Purchases"});
    $r->headers("Date","Name","Purchase","Amount");
    $r->nodata("No purchases yet.");
    foreach my $inv (@inv) {
	my $invoice = new Modules::Finance::Receivable(data=>$inv);
	my $acctname = $inv->{name};
	$acctname =~ s/</&lt;/g;
	$acctname =~ s/>/&gt;/g;
	$r->push(
		 $invoice->showdata("date"),
		 $acctname,
		 $invoice->description(),
		 $invoice->total()
		 );
    }
    return $r->make();
}

sub setup_queries {
    my $this = shift;
    my $db = $share{DB};
    $db->set_query("get global accounts by name",
		   (sql=>"select * from account where name like ? order by account_id desc",
		    nparam=>1, mode=>"r", keys=>"account")
		   );
    $db->set_query("get local accounts by name",
		    sql=>"select account.* from account left join member on member.uid=account.uid where (account.section_id=? or account.section_id=0) and name like ? order by account_id desc",
		    nparam=>2, mode=>"r", keys=>["account","member"],
		   );
    $db->set_query("get global receivables since date",
		   (sql=>"select * from receivable where status = ? and date > ? order by date desc",
		    nparam=>2, mode=>"r", keys=>["receivable"])
		   );
    $db->set_query("get local receivables since date",
		    sql=>"select receivable.*,account.name,account.section_id as account_section from receivable,account left join member on account.uid=member.uid where receivable.account_id=account.account_id and (account.section_id=? or account.section_id=0) and receivable.status = ? and receivable.date > ? order by date desc",
		    nparam=>3, mode=>"r", keys=>["receivable","account","member"],
		   );
    $db->set_query("get custom invoice number",
		    (sql=>"select receivable.*,account.name,account.section_id as account_section from receivable,account left join member on account.uid=member.uid where receivable.account_id=account.account_id and (account.section_id=? or account.section_id=0) and invoice=?",
		    nparam=>2, mode=>"r", keys=>["receivable","account","member"])
		   );
    $db->set_query("get global receivables in date range",
		   (sql=>"select * from receivable where status = ? and date > ? and date < ? order by date desc",
		    nparam=>3, mode=>"r", keys=>["receivable"])
		   );
    $db->set_query("get local receivables in date range",
		   (sql=>"select receivable.*,account.name,account.section_id as account_section from receivable,account left join member on account.uid=member.uid where receivable.account_id=account.account_id and (account.section_id=? or account.section_id=0) and status = ? and date > ? and date < ? order by date desc",
		    nparam=>4, mode=>"r", keys=>["receivable","account","member"])
		   );
    $db->set_query("get local receivables",
		   sql => "select r.*,a.name,a.section_id as account_section from receivable r, account a left join member m on m.uid=a.uid where r.account_id=a.account_id and (a.section_id=? or a.section_id=0)",
		   param=>1, mode=>"r", keys=>["receivable","account","member"],
		   );
    $db->set_query("get global receivables",
		   sql => "select r.*,a.name from receivable r, account a where r.account_id=a.account_id",
		   param=>0, mode=>"r", keys=>["receivable","account"],
		   );
    $db->set_query("get local payments",
		   sql => "select p.*,a.name,a.section_id as account_section from payment p, account a left join member m on m.uid=a.uid where p.account_id=a.account_id and (a.section_id=? or a.section_id=0) order by payment_id desc",
		   param=>1, mode=>"r",keys=>["payment","account","member"],
		   );
    $db->set_query("get global payments",
		   sql => "select p.*,a.name from payment p, account a where p.account_id=a.account_id order by payment_id desc",
		   param=>0, mode=>"r",keys=>["payment","account"],
		   );
    $db->set_query("get recent global purchases",
		   sql => "select r.*,a.name from receivable r, account a where r.account_id=a.account_id and r.status='active' order by r.receivable_id desc limit ?",
		   param=>1, mode=>"r", keys=>["receivable","account"],
		   );
    $db->set_query("get recent local purchases",
		   sql => "select r.*,a.name,a.section_id as account_section from receivable r, account a left join member m on a.uid=m.uid where r.account_id=a.account_id and r.status='active' and r.account_id=a.account_id and (a.section_id=? or a.section_id=0) order by r.receivable_id desc limit ?",
		   param=>2, mode=>"r", keys=>["receivable","account","member"],
		   );
    $db->set_query("get our surcharges",
		   sql => "select * from surcharge where code != '' and (section_id=0 or section_id=?)",
		   param=>1, mode=>"r", keys=>["surcharge"],
		   );
}

sub tips {
	my $this = shift;
    $this->get_config();
    $ml = &get_obj("ML");    
	my $out;
	my $methods = $this->{config}{payment_method};
	$methods = (ref $methods eq "ARRAY") ? join(", ",@$methods) : $methods;
	my %settings = ( 
		"Allowed payment methods" => $methods,
		"E-commerce Payment Gateway" => $this->{config}{gateway},
		"From email address of notifications" => $this->{config}{seller_email},
		"Where purchase notifications are sent" => $this->{config}{notification_email},
	);	
	$out .= $ml->h2("Payments and E-commerce");
	my $table;
	foreach my $s (keys %settings) {
	$table .= $ml->tr(
				    $ml->td($s).
				    $ml->td($settings{$s})
				    );
	}
	$out .= $ml->table($table, { class=>"Report" } );	
	$out .= $ml->h3("Reconciliation");
	$out .= &substitute("On a regular basis, you will want to click on the Payment Module and review all 'Processing' items. Sometimes, a 'timeout' can occur between the e-commerce gateway and the membership system. When this happens, some payments may have been processed successfully by [[gateway]] without them notifying the system. If you see a 'Processing' item that has been successfully processed by [[gateway]], you must record the payment to this account. This will automatically update all system records.",{gateway=>$this->{config}{gateway}});
	$out .= $ml->h3("Cancellation/Refund Function");
	$out .= $ml->p("Many cancellations and refunds can be dealt with using the Cancellation/Refund function. When viewing an invoice, click the \"Cancellation/Refund\" button to launch a tool that gives you various options for reversing a sale in one step. This includes convenient settings to cancel and void sales, as well as cancel or refund payments.");
	$out .= $ml->p("Note that the website will not automatically reverse e-commerce transactions on your gateway.  In order to refund a credit card payment you must go through your payment gateway.");
	return $out;
}

# returns abbreviated version of a passed country

sub getCountryAbbreviation {
	my ($country) = @_;

	my $country_abbreviation = {
		"Albania" => "AL",
		"Algeria" => "DZ",
		"American Samoa" => "AS",
		"Andorra" => "AD",
		"Angola" => "AO",
		"Anguilla" => "AI",
		"Antarctica" => "AQ",
		"Antigua and Barbuda" => "AG",
		"Argentina" => "AR",
		"Armenia" => "AM",
		"Aruba" => "AW",
		"Australia" => "AU",
		"Austria" => "AT",
		"Azerbaijan" => "AZ",
		"Bahamas" => "BS",
		"Bahrain" => "BH",
		"Bangladesh" => "BD",
		"Barbados" => "BB",
		"Belgium" => "BE",
		"Belize" => "BZ",
		"Benin" => "BJ",
		"Bermuda" => "BM",
		"Bhutan" => "BT",
		"Bolivia" => "BO",
		"Bosnia and Herzegovina" => "BA",
		"Botswana" => "BW",
		"Bouvet Island" => "BV",
		"Brazil" => "BR",
		"British Indian Ocean Territory" => "IO",
		"Brunei Darussalam" => "BN",
		"Bulgaria" => "BG",
		"Burkina Faso" => "BF",
		"Burundi" => "BI",
		"Belarus" => "BY",
		"Cambodia" => "KH",
		"Cameroon" => "CM",
		"Canada" => "CA",
		"Cape Verde" => "CV",
		"Cayman Islands" => "KY",
		"Central African Republic" => "CF",
		"Chad" => "TD",
		"Chile" => "CL",
		"China" => "CN",
		"Christmas Island" => "CX",
		"Cocos (Keeling) Islands" => "CC",
		"Colombia" => "CO",
		"Comoros" => "KM",
		"Congo" => "CG",
		"Cook Islands" => "CK",
		"Costa Rica" => "CR",
		"Côte D’ivoire" => "CI",
		"Croatia" => "HR",
		"Cuba" => "CU",
		"Cyprus" => "CY",
		"Czech Republic" => "CZ",
		"Denmark" => "DK",
		"Djibouti" => "DJ",
		"Dominica" => "DM",
		"Dominican Republic" => "DO",
		"Serbia and Montenegro" => "CS",
		"Ecuador" => "EC",
		"Egypt" => "EG",
		"El Salvador" => "SV",
		"Equatorial Guinea" => "GQ",
		"Estonia" => "EE",
		"Ethiopia" => "ET",
		"Falkland Islands (Malvinas)" => "FK",
		"Faroe Islands" => "FO",
		"Fiji" => "FJ",
		"Finland" => "FI",
		"France" => "FR",
		"French Guiana" => "GF",
		"French Polynesia" => "PF",
		"French Southern Territories" => "TF",
		"Gabon" => "GA",
		"Gambia" => "GM",
		"Georgia" => "GE",
		"Germany" => "DE",
		"Ghana" => "GH",
		"Gibraltar" => "GI",
		"Greece" => "GR",
		"Greenland" => "GL",
		"Grenada" => "GD",
		"Guadeloupe" => "GP",
		"Guam" => "GU",
		"Guatemala" => "GT",
		"Guinea" => "GN",
		"Guinea-Bissau" => "GW",
		"Guyana" => "GY",
		"Haiti" => "HT",
		"Heard Island and McDonald Islands" => "HM",
		"Honduras" => "HN",
		"Hong Kong" => "HK",
		"Hungary" => "HU",
		"Iceland" => "IS",
		"India" => "IN",
		"Indonesia" => "ID",
		"Iran, Islamic Republic of" => "IR",
		"Iraq" => "IQ",
		"Ireland" => "IE",
		"Israel" => "IL",
		"Italy" => "IT",
		"Jamaica" => "JM",
		"Japan" => "JP",
		"Jordan" => "JO",
		"Kazakhstan" => "KZ",
		"Kenya" => "KE",
		"Kiribati" => "KI",
		"Korea, Democratic People’s Republic Of" => "KP",
		"Korea, Republic of" => "KR",
		"Kuwait" => "KW",
		"Kyrgyzstan" => "KG",
		"Lao People's Democratic Republic" => "LA",
		"Latvia" => "LV",
		"Lebanon" => "LB",
		"Lesotho" => "LS",
		"Liberia" => "LR",
		"Libyan Arab Jamahiriya" => "LY",
		"Liechtenstein" => "LI",
		"Lithuania" => "LT",
		"Luxembourg" => "LU",
		"Macao" => "MO",
		"Madagascar" => "MG",
		"Malawi" => "MW",
		"Malaysia" => "MY",
		"Maldives" => "MV",
		"Mali" => "ML",
		"Malta" => "MT",
		"Marshall Islands" => "MH",
		"Martinique" => "MQ",
		"Mauritania" => "MR",
		"Mauritius" => "MU",
		"Mexico" => "MX",
		"Micronesia, Federated States of" => "FM",
		"Moldova, Republic of" => "MD",
		"Monaco" => "MC",
		"Mongolia" => "MN",
		"Montserrat" => "MS",
		"Morocco" => "MA",
		"Mozambique" => "MZ",
		"Myanmar" => "MM",
		"Namibia" => "NA",
		"Nauru" => "NR",
		"Nepal" => "NP",
		"Netherlands" => "NL",
		"New Caledonia" => "NC",
		"New Zealand" => "NZ",
		"Nicaragua" => "NI",
		"Niger" => "NE",
		"Nigeria" => "NG",
		"Niue" => "NU",
		"Norfolk Island" => "NF",
		"Northern Mariana Islands" => "MP",
		"Norway" => "NO",
		"Oman" => "OM",
		"Pakistan" => "PK",
		"Palau" => "PW",
		"Panama" => "PA",
		"Åland Islands" => "AX",
		"Timor-Leste" => "TL",
		"Papua New Guinea" => "PG",
		"Paraguay" => "PY",
		"Peru" => "PE",
		"Philippines" => "PH",
		"Pitcairn" => "PN",
		"Poland" => "PL",
		"Portugal" => "PT",
		"Puerto Rico" => "PR",
		"Qatar" => "QA",
		"Reunion" => "RE",
		"Romania" => "RO",
		"Russian Federation" => "RU",
		"Rwanda" => "RW",
		"Saint Helena" => "SH",
		"Saint Kitts and Nevis" => "KN",
		"Saint Lucia" => "LC",
		"Saint Pierre and Miquelon" => "PM",
		"Saint Vincent and the Grenadines" => "VC",
		"Samoa" => "WS",
		"San Marino" => "SM",
		"Sao Tome and Principe" => "ST",
		"Saudi Arabia" => "SA",
		"Senegal" => "SN",
		"Seychelles" => "SC",
		"Sierra Leone" => "SL",
		"Singapore" => "SG",
		"Slovakia" => "SK",
		"Slovenia" => "SI",
		"Solomon Islands" => "SB",
		"Somalia" => "SO",
		"South Africa" => "ZA",
		"Spain" => "ES",
		"Sri Lanka" => "LK",
		"Sudan" => "SD",
		"Suriname" => "SR",
		"Svalbard and Jan Mayen" => "SJ",
		"Swaziland" => "SZ",
		"Sweden" => "SE",
		"Switzerland" => "CH",
		"Syrian Arab Republic" => "SY",
		"Taiwan, Province of China" => "TW",
		"Tajikistan" => "TJ",
		"Tanzania, United Republic of" => "TZ",
		"Thailand" => "TH",
		"Togo" => "TG",
		"Tokelau" => "TK",
		"Tonga" => "TO",
		"Trinidad and Tobago" => "TT",
		"Tunisia" => "TN",
		"Turkey" => "TR",
		"Turkmenistan" => "TM",
		"Turks and Caicos Islands" => "TC",
		"Tuvalu" => "TV",
		"Uganda" => "UG",
		"Ukraine" => "UA",
		"United Arab Emirates" => "AE",
		"United Kingdom" => "GB",
		"United States" => "US",
		"United States Minor Outlying Islands" => "UM",
		"Uruguay" => "UY",
		"Uzbekistan" => "UZ",
		"Vanuatu" => "VU",
		"Holy See (Vatican City state)" => "VA",
		"Venezuela" => "VE",
		"Viet Nam" => "VN",
		"Virgin Islands, British" => "VG",
		"Virgin Islands, U.S." => "VI",
		"Wallis and Futuna" => "WF",
		"Western Sahara" => "EH",
		"Yemen" => "YE",
		"Guernsey" => "GG",
		"Zambia" => "ZM",
		"Zimbabwe" => "ZW",
		"Netherlands Antilles" => "AN",
		"South Georgia and the South Sandwich Islands" => "GS",
		"Congo, The Democratic Republic of the" => "CD",
		"Eritrea" => "ER",
		"Macedonia, The Former Yugoslav Republic of" => "MK",
		"Mayotte" => "YT",
		"Palestinian Territory, Occupied" => "PS",
		"Afghanistan" => "AF",
		"Isle Of Man" => "IM",
		"Jersey" => "JE",
		"Montenegro" => "ME",
		"Saint Barthélemy" => "BL",
		"Saint Martin" => "MF",
		"Serbia" => "RS"
	};

	return $country_abbreviation->{$country} || $country;
}

# e-commerce killswitch

sub kill {
    my $this = shift;
    return $ml->div(
	$msg{"E-commerce has been temporarily disabled while we perform website maintenance. Sorry for the inconvenience. Please retry your purchase soon."},
	{ style=>"border:1px dashed red; background-color:#ffc; padding:40px; color:#900;font-size:large; line-height:120%;" }
	);
}

#----------------------------------------------------------------------------
# Everything after this point is the interface to the Payment Gateway API

# Setup - perform whatever steps are needed to initialize use of the payment
#         gateway.  Returns 1/0 for success/failure.  Should be 
#         prepared to report a status message on failure (see pgStatus()).

sub pgSetup {
    my ($this,%opt) = @_;
    return $this->do("Setup",%opt);
}

# IsReceipt - test whether we are preparing a new transaction (in which case
#         we return false/0), or reporting on the outcome of an existing
#         transaction (in which case we return true/1).

sub pgIsReceipt {
    my $this = shift;
    return $this->do("IsReceipt");
}

# Success - return true if the transaction succeeded, and false
#         if it failed or did not execute for any reason.

sub pgSuccess {
    my $this = shift;
    return $this->do("Success");
}

# Cancel - return true if we canceled payment at the gateway.
#         This cancels payment only, not the purchase.
#         Ie. shopping can resume normally.
#         The control flow should be:
#         if (pgSuccess) {
#            ... payment was made
#         }
#         elsif (pgCancel) {
#            ... payment was canceled by user
#         }
#         else {
#            ... payment failed
#         }

sub pgCancel {
    my $this = shift;
    return $this->do("Cancel");
}

# Pass - generate a message for successful transactions.

sub pgPass {
    my $this = shift;
    $this->{TransactionStatus} = "pass";
    return $this->do("Pass");
}

# Fail - generate a message for failed transactions.

sub pgFail {
    my $this = shift;
    $this->{TransactionStatus} = "fail";
    return $this->do("Fail");
}

# SetupTransaction - perform whatever steps are needed to prepare a 
#         transaction with the gateway.  Return TRUE if the transaction
#         is successfully prepared, and FALSE otherwise.  Be prepared to
#         to report a status message on failure (see pgStatus()).

sub pgSetupTransaction {
    my ($this,%opt) = @_;
    return $this->do("SetupTransaction",%opt);
}

# PostTransaction - send the prepared transaction to the gateway.
#         Return TRUE if the transaction is posted, and FALSE if the
#         communication with the gateway failed for any reason.  
#         Be prepared to report a status message on failure (see pgStatus()).

sub pgPostTransaction {
    my $this = shift;
    return $this->do("PostTransaction");
}

# GetPurchaseId - return the purchase ID for a received transaction.

sub pgGetPurchaseId {
    my $this = shift;
    return $this->do("GetPurchaseId");
}

# GetTransactionId - return the unique gateway generated transaction ID for a received transaction.

sub pgGetTransactionId {
    my $this = shift;
    return $this->do("GetTransactionId");
}

# pgGetAmount - return the amount of a transaction

sub pgGetAmount {
    my $this = shift;
    return $this->do("GetAmount");
}

# pgGetPaymentId - return the payment identifier (eg. last 4 digits of CC)

sub pgGetPaymentId {
    my $this = shift;
    return $this->do("GetPaymentId");
}

# pgGetReceiptPageId - ask which page we should be using to display the receipt
#         (If not the current page, we should redirect to this page.)
#         This is useful if the gateway's receipting is not flexible enough
#         to handle different receipt logic, eg. multiple languages.
#         It returns undef if the default receipt page is fine.

sub pgGetReceiptPageId {
    my $this = shift;
    return $this->do("GetReceiptPageId");
}

# Status - return a status message for the most recent gateway action.

sub pgStatus {
    my $this = shift;
    if ($this->{gateway}) {
	return 
	    $this->{pgStatus} ||
	    $this->do("Status") ||
	    $@;
    }
    return undef;
}

sub do {
    my ($this,$method,%opt) = @_;

    # create gateway if needed
    if (! $this->{gateway}) {
	my $gateway = $opt{gateway} || $this->{config}{gateway};
	my $safe_gateway;
	{
	    $gateway =~ /^(\w+)$/;
	    $safe_gateway = $1;
	}
	if ($safe_gateway) {
	    my $mod = eval "require Modules::Pay::$safe_gateway";
	    if ($mod) {
		$this->{gateway} = eval "new Modules::Pay::$safe_gateway()";
	    }
	    else {
		$this->{pgStatus} = $msg{"Gateway failure: $gateway: "}.$@;
		return undef;
	    }
	}
	else {
	    $this->{pgStatus} = $msg{"Gateway failure: unsafe gateway: $gateway"};
	    return undef;
	}
    }
    return undef if (!$this->{gateway}->can($method));
    # execute gateway command
    if ($this->{gateway} && $this->{gateway}->Setup()) {
	if (my $stat = $this->{gateway}->$method(%opt)) {
	    return $stat;
	}
	elsif ($@) {
	    $this->{pgStatus} = $msg{"Gateway failure: "}.$@;
	}
    }
    else {
	$this->{pgStatus} = $msg{"No payment gateway defined. "}.$@;
    }
    return undef;
}

# todo() allows this plug-in to advise the administrator of work that needs
#        attention.

sub todo {
    my $this = shift;

    # the todo list is analogous to an RSS feed of tasks
    my @todo;

    # determine your list of tasks, and add them to the list, eg.
    #push @todo, { link=> $url, title=> $title, description=> $description },

    #### notify of pending memberships

    return @todo;
}

1;
