package Modules::Pay::AuthorizeNet;

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
#  This is a gateway for Moneris e-Select e-commerce payments.  It supports the 
#  ExSite Payment API, namely:
#
#  Setup(%) - prepare an e-commerce gateway connection
#  SetupTransaction(%) - create a transaction
#  PostTransaction() - send the transaction to the gateway
#  IsReceipt() - determine whether this is a reply from the gateway
#  Success() - determine whether the transaction succeeded
#  Pass() - process a transaction approval*
#  Fail() - process a declined transaction*
#  GetPurchaseId() - get the purchase ID
#  GetInvoicer() - get the name of the invoicing component
#  Status() - return a status/error message, if any
#
#  * only perform the processing that is needed for the e-commerce Gateway 
#  connection.  Account and invoice post-processing is handled by the Pay
#  module.
#----------------------------------------------------------------------------

# README:
# How To Guide for setting up AuthorizeNet
#
# this system posts payment information to authorize.net 

use strict;

use ExSite::Base;
use ExSite::Config;
use ExSite::FormBuilder;
use ExSite::Input;
use ExSite::Misc;
use ExSite::Util;
use ExSite::Time;

use POSIX qw(strftime);
use Digest::HMAC_MD5 qw(hmac_md5 hmac_md5_hex);

use vars qw(@ISA $ml);
@ISA = qw(ExSite::Base);

$ml = &get_obj("ML");

sub Setup {
	my ($this,%opt) = @_;
	return 1;
}

#--- receipt processing

sub IsReceipt {
	my $this = shift;
	my $input = new ExSite::Input;
	$this->{post} = $input->post();
	$this->{query} = $input->query();
	$this->{input} = $input->combine();
	my $key;
	if (!$this->gateway_setting("disable_key_encryption")) {	
	my $crypt = new ExSite::Crypt();
	$key = $crypt->decrypt($this->{input}{key});
	} else {
	$key = $this->{input}{key};
	}
	if ($key =~ /^[\d\.]+\-\d+\-\d+$/) {
	my ($amt,$id,$time) = split /\-/, $key;
	$this->{transaction_details} = {
		amount => $amt,
		purchase_id => $id,
		time => $time,
	};
	# we validate the transaction key and do a temp login for authorizenet's web service call
	my $r = new Modules::Finance::Receivable(id=>$id);
	if ($r->ok && $r->account()) {
	my $m = $r->account->get_member();
	$share{DB}->do_login_temp($m->get()) if ($m && $m->defined());
	# FIXME: authorize.net may still not have enough permissions - workaround by changing foreign_link_level
	$config{auth}{foreign_link_level} = 0;
	}
	}
	else {
	$this->{status} = "Invalid transaction key";
	return 0;
	}	
	return exists $this->{post}{"x_response_code"};
}

sub Success {
	my $this = shift;
	$this->{status} = $this->{post}{x_response_reason_text};
	return 1 if ($this->{post}{$this->result_paramname()} == 1);
	return 0;
}

sub Cancel {
	my $this = shift;
	return $this->{input}{cancelTXN};
}

sub Pass {
	my $this = shift;
	return "Transaction approved: " . $this->Status();
}

sub Fail {
	my $this = shift;
	return "Transaction declined: " . $this->Status();
}

sub GetPurchaseId {
	my $this = shift;
	if (!$this->{post}{x_invoice_num}) {
	my $input = new ExSite::Input;
	$this->{post} = $input->post();	
	}
	$this->{post}{x_invoice_num} =~ s/TEST-//;
	return $this->{post}{x_invoice_num};
}

sub GetAmount {
	my $this = shift;
	return $this->{post}{x_amount};
}

sub GetReceiptPageId {
	my $this = shift;
	return undef;
}

sub SetupTransaction {
	my ($this,%opt) = @_;
	$this->{transaction} = \%opt;
	my $amt = $opt{amount};
	my $id = $opt{purchase_id};
	my $time = time;
	if (!$this->gateway_setting("disable_key_encryption")) {	
	my $crypt = new ExSite::Crypt;	
	$this->{transaction}{key} = $crypt->encrypt("$amt-$id-$time");
	} else {
	$this->{transaction}{key} = "$amt-$id-$time";	
	}
	if ($opt{account}) {
	$this->{transaction}{account} = $opt{account};

	my @billing_contact_fallback_order = $config{Pay}{billing_contact_fallback_order} ? 
	    (ref $config{Pay}{billing_contact_fallback_order} eq "ARRAY" ? @{$config{Pay}{billing_contact_fallback_order}} : ($config{Pay}{billing_contact_fallback_order})) : ("billing");
	my @shipping_contact_fallback_order = $config{Pay}{shipping_contact_fallback_order} ? 
	    (ref $config{Pay}{shipping_contact_fallback_order} eq "ARRAY" ? @{$config{Pay}{shipping_contact_fallback_order}} : ($config{Pay}{shipping_contact_fallback_order})) : ("shipping");

	$this->{transaction}{billing_contact} = $opt{account}->get_contact(@billing_contact_fallback_order);
	$this->{transaction}{shipping_contact} = $opt{account}->get_contact(@shipping_contact_fallback_order);

	my $billing_stat = $this->run_handler("Pay_ValidateBillingContact", $this->{transaction}{billing_contact});
	$this->{transaction}{billing_contact} = $billing_stat if (defined $billing_stat);

	my $shipping_stat = $this->run_handler("Pay_ValidateShippingContact", $this->{transaction}{shipping_contact});
	$this->{transaction}{shipping_contact} = $shipping_stat if (defined $shipping_stat);
	}
	
	my $reply;
	if ($ENV{SCRIPT_NAME} =~ /^$config{server}{CGIpath}\/$config{prog}{page}$/) {
	my $uri = new ExSite::URI;
	$uri->setup();

	$uri->plaintext;

	# get pay receipt page 
	my $page = $share{Page};
	my @page = $share{DB}->fetch_match("page",{
		filename=>"receipt.html",
		section_id=>$page->get_my("section_id")});
	if (scalar @page) {
		$uri->query(_id=>$page[0]->{page_id},invoice_id=>$id);
	} else {
		$uri->query(invoice_id=>$id);
		$uri->service_page("Pay");
	}
	$uri->query(key=>$this->{transaction}{key});
	$reply = $uri->write_full();
	}
	else {
	# not on a page;  may not work
	$reply = &relink;
	}
	$this->{transaction}{reply} = $reply;
	return 1;
}

sub PostTransaction {
	my $this = shift;
	my $url = new ExSite::URI;
	my $post_url = $this->gateway_setting("post_url");
	my %post_params = $this->post_params();

	my $f = new ExSite::FormBuilder(method=>"post",action=>$post_url);
	$f->name("send_gateway");
	$f->buttons(submit=>0,cancel=>0,reset=>0);

	while ( my ($key, $value) = each(%post_params) ) {
		$f->input(type=>"hidden",
			name=>$key,
			value=>$value);
	}
	my $ml = &get_obj("ML");
	# alternative submit for clients with javascript disabled
	my $submit = $ml->noscript(
		$f->inputtag(type=>"submit",name=>"submit_action",value=>$msg{"Proceed to Pay"}));
	$f->input(type=>"preformatted",name=>"noscript",input=>$submit);

	# javascript to autosubmit the form
	my $autosubmit = $ml->script("document.send_gateway.submit()",{type=>"text/javascript"});
	return $f->make() . $autosubmit;
}

sub Status {
	my $this = shift;
	return $this->{status};
}

#----------------------------------------------------------------------------

# Helper (Private) Methods

# returns a gateway specific setting for the current gateway
sub gateway_setting {
	my ($this,$key) = @_;
	my $gateway = &preference("Pay.gateway");
	if (defined &preference("Pay.$gateway.$key")) {
		return &preference("Pay.$gateway.$key");
	}
	$this->warn("Missing $key configuration for $gateway gateway.");
	return undef;
}

sub post_params {
	my $this = shift;
	
	# a sequence number is randomly generated
	my $sequence	= int(rand(1000));
	# a timestamp is generated
	my $timeStamp	= time();
	
	# generate the SIM fingerprint 
	# use the HMAC_MD5 Digest to create the fingerprint
	my $transactionKey 	= $this->gateway_setting("transaction_key");
	my $loginID = $this->gateway_setting("x_login");
	my $amount = $this->{transaction}{amount};
	my $fingerprint = hmac_md5_hex($loginID . "^" . $sequence . "^" . $timeStamp . "^" . $amount . "^", $transactionKey);
	my $is_test = $this->gateway_setting("test_mode") || 0;
	my %required_params = (
		method=>'CC',
		x_login=>$loginID,
		x_amount=>$amount,
		x_description=>$this->{transaction}{description},
		x_invoice_num=>$is_test ? "TEST-".$this->{transaction}{purchase_id} : $this->{transaction}{purchase_id},
		x_fp_sequence=>$sequence,
		x_fp_timestamp=>$timeStamp,
		x_fp_hash=>$fingerprint,
		x_test_request=>$is_test,
		x_show_form=>'PAYMENT_FORM',
		x_relay_response=>"TRUE",
		x_relay_url=>$this->{transaction}{reply},
		x_email_customer=>"TRUE",
	);
	my $name = $this->{transaction}{account}->name;
	my ($first_name,$last_name);
	if (scalar split(" ",$name) == 2) {
		if ($name =~ /, /) {
			($last_name,$first_name) = split(", ",$name);
		} else {
			($first_name,$last_name) = split(" ",$name);
		}
	}
	my %optional_params = (
		x_cust_id=>$this->{transaction}{account}->id(),
		x_first_name=>$first_name,
		x_last_name=>$last_name,
		x_address=>$this->{transaction}{billing_contact}->getdata("address"),
		x_city=>$this->{transaction}{billing_contact}->getdata("city"),
		x_state=>$this->{transaction}{billing_contact}->getdata("provstate"),
		x_zip=>$this->{transaction}{billing_contact}->getdata("pcode"),
		x_country=>$this->{transaction}{billing_contact}->getdata("country") || "USA",
		x_phone=>$this->{transaction}{billing_contact}->getdata("phone1"),		
		# email address for receipts
		x_email=>$this->{transaction}{billing_contact}->getdata("email"),
		
		x_ship_to_first_name=>$first_name,
		x_ship_to_last_name=>$last_name,
		x_ship_to_address=>$this->{transaction}{shipping_contact}->getdata("address"),
		x_ship_to_city=>$this->{transaction}{shipping_contact}->getdata("city"),
		x_ship_to_state=>$this->{transaction}{shipping_contact}->getdata("provstate"),
		x_ship_to_zip=>$this->{transaction}{shipping_contact}->getdata("pcode"),
		x_ship_to_country=>$this->{transaction}{shipping_contact}->getdata("country") || "USA",
	);
	return (%required_params,%optional_params);
}

# returns the variable name of the parameter which indicates the success or failure of a transaction	
sub result_paramname {
	my $this = shift;
	return $this->gateway_setting("result_param");
}

1;
