package Modules::Pay::PaypalPFLS;

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
#  This is a gateway for Paypal e-commerce payments.  It supports the 
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

use strict;

use ExSite::Base;
use ExSite::Config;
use ExSite::FormBuilder;
use ExSite::Input;
use ExSite::Misc;
use ExSite::URI;
use ExSite::Util;
use ExSite::Time;
use LWP::UserAgent;

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
	$this->{input} = $input->combine();
	return 1 if ($this->{input}{cart} eq "ipn");
	return 1 if ($this->Cancel);
	return exists $this->{input}{$this->result_paramname()};
}

# IPN processing (instant payment notification)
# post from paypal notifies us when payments are made
# this can come before or after the user is directed back to the site
# if user is directed back before IPN is received then we can ignore it

sub Notification {
	my $this = shift;

	# get post back data
	my $input = new ExSite::Input;
	my $in = $input->combine;

	# ipn log files
	my $ipn_success_log="logs/ipn_success.txt"; 

	# paypal configuration
	$in->{cmd}= "_notify-validate"; 

	# verify with paypal by sending data back with _notify-validate
	my $ua = LWP::UserAgent->new;
	my $post_url = $this->gateway_setting("post_url");
	my $response = $ua->post($post_url,$in);

	open(LOGFILE, ">>$ipn_success_log");
	print LOGFILE &ShowHash($in);
	close(LOGFILE); 

	# parse response
	if($response->content eq "VERIFIED") { 
	my $crypt = new ExSite::Crypt();
	my $key = $crypt->decrypt($in->{custom});
	if ($key =~ /^[\d\.]+;\d+;\d+$/) {
	my ($amt,$id,$time) = split /;/, $key;
	$this->{transaction_details} = {
		amount => $amt,
		purchase_id => $id,
		time => $time,
	};
	# do a verification request using the tx parameter in query string
	$this->{status} = $response->content() . " - Transaction Code ".$in->{txn_id};
	if (abs($amt - $in->{mc_gross}) > 0.01) {
		my $admin = $config{site}{adminstrator};
		$this->{status} .= 
	" [SUSPICIOUS] Please contact the website administrator at $admin to follow up on your payment.";
	}
	# check for race condition
	# ipn notification may have come after pdt notification)
	# check payments for existing txn_id
	my @p = $share{DB}->fetch_match("payment",{receivable_id=>$this->GetPurchaseId,note=>'%'.$in->{txn_id}.'%'});
	if (scalar @p) {
	$this->{status} = "Transaction already added: " . $in->{txn_id};
	return 0;
	}
	return 1 if ($in->{payment_status} =~ /completed/i);
	return 0;
	}
	else {
	$this->{status} = "Invalid transaction key";
	return 0;
	}	
	}
	elsif($response->content eq "INVALID") { 
	$this->{status} = "Could not verify transaction with Paypal: " . $in->{txn_id};
	return 0;
	}
	return 0;
}

sub Success {
	my $this = shift;
	#return $this->Notification if ($this->{input}{cart} eq "ipn");

	my $crypt = new ExSite::Crypt();
	my $key = $crypt->decrypt($this->{input}{USER1});
	if ($key =~ /^[\d\.]+;\d+;\d+$/) {
	my ($amt,$id,$time) = split /;/, $key;
	$this->{transaction_details} = {
		amount => $amt,
		purchase_id => $id,
		time => $time,
	};
	if (time - $time >= 3600) {
	$this->{status} .= "Transaction expired.";
	}
	# Payflow link solution does not have transaction verification
	$this->{status} .= " Transaction Code ".$this->{input}{PNREF};

	my @p = $share{DB}->fetch_match("payment",{receivable_id=>$this->GetPurchaseId,note=>'%'.$this->{input}{PNREF}.'%'});
	if (scalar @p) {
		my $payment = $p[0];

		if ($payment->{status} eq "paid") {
			$this->{status} = "This transaction has already been processed via IPN: " . $this->{input}{PNREF};
		}
		else {
			$this->{status} = "Transaction not approved: " . $this->{input}{PNREF};
		}

		return 0;
	}

	return 1 if ($this->{input}{$this->result_paramname()} eq 0);
	return 0;
	}
	else {
	$this->{status} = "Invalid transaction key";
	return 0;
	}
}

sub Cancel {
	my $this = shift;
	return $this->{input}{cancel_return};
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
       if (!$this->{input}{INVNUM}) {
       my $input = new ExSite::Input;
       $this->{input} = $input->combine();
       }
       return $this->{input}{INVNUM} || $this->{transaction_details}{purchase_id};
}

sub GetAmount {
	my $this = shift;
	return $this->{transaction_details}{amount};
}

sub GetReceiptPageId {
	my $this = shift;
	return $this->{input}{rvar_page};
}

sub SetupTransaction {
	my ($this,%opt) = @_;
	$this->{transaction} = \%opt;
	my $amt = $opt{amount};
	my $id = $opt{purchase_id};
	my $time = time;
	my $crypt = new ExSite::Crypt;
	$this->{transaction}{key} = $crypt->encrypt("$amt;$id;$time");
	if ($opt{account}) {
	$this->{transaction}{account} = $opt{account};

	my @billing_contact_fallback_order = $config{Pay}{billing_contact_fallback_order} ? (ref $config{Pay}{billing_contact_fallback_order} eq "ARRAY" ? @{$config{Pay}{billing_contact_fallback_order}} : ($config{Pay}{billing_contact_fallback_order})) : ("billing");
	my @shipping_contact_fallback_order = $config{Pay}{shipping_contact_fallback_order} ? (ref $config{Pay}{shipping_contact_fallback_order} eq "ARRAY" ? @{$config{Pay}{shipping_contact_fallback_order}} : ($config{Pay}{shipping_contact_fallback_order})) : ("shipping");

	$this->{transaction}{billing_contact} = $opt{account}->get_contact(@billing_contact_fallback_order);
	$this->{transaction}{shipping_contact} = $opt{account}->get_contact(@shipping_contact_fallback_order);

	my $billing_stat = $this->run_handler("Pay_ValidateBillingContact", $this->{transaction}{billing_contact});
	$this->{transaction}{billing_contact} = $billing_stat if (defined $billing_stat);

	my $shipping_stat = $this->run_handler("Pay_ValidateShippingContact", $this->{transaction}{shipping_contact});
	$this->{transaction}{shipping_contact} = $shipping_stat if (defined $shipping_stat);
	}
	
	my ($reply,$cancel);
	if ($ENV{SCRIPT_NAME} =~ /^$config{server}{CGIpath}\/$config{prog}{page}$/) {
	my $uri = new ExSite::URI;
	$uri->setup();
	$uri->plaintext;
	$uri->service_page("Pay");
	$reply = $uri->write_full();
	$uri->query(cancel_return=>1);
	$uri->query(invoice=>$opt{purchase_id});	
	$cancel = $uri->write_full();
	}
	else {
	# not on a page;  may not work
	$reply = &relink;
	}
	$this->{transaction}{reply} = $reply;
	$this->{transaction}{cancel_return} = $cancel;
	
	return 1;
}

sub PostTransaction {
	my $this = shift;
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
	my $gateway = $config{Pay}{gateway};
	return $config{Pay}{$gateway}{$key};
}

# paypal variables
sub post_params {
	my $this = shift;
	
	my %required_params = (
		LOGIN=>$this->gateway_setting("login"),
		PARTNER=>$this->gateway_setting("partner"),
		DESCRIPTION=>$this->{transaction}{description},
		AMOUNT=>$this->{transaction}{amount},
		$this->key_paramname() => $this->{transaction}{key},
		TYPE=>"S" # sale
	);

	# timestamp the order_id so we can submit retry requests
	my $t = new ExSite::Time;
	my $tstamp = $t->write("datetime");
	# hosted paypage language
	my $lang = "EN";
	my $version = $share{Page}->get_my("version") || $config{default_version};
	# french version loose regexp
	if ($version =~ /fr/i) {
		$lang = "FR";
	}
	my $cust_id;
	$cust_id = $this->{transaction}{contact}->id() if ($this->{transaction}{contact});
	my %optional_params = (
		# UNIQUE order identifier
		invoice=>$this->{transaction}{purchase_id},
		lc=>$lang,
	);
	# paypal will reject entire prepop if any values are invalid
	my %prepop;
	if ($this->{transaction}{billing_contact}) {

	%prepop = (
		address_override=>1,
		address=>$this->{transaction}{billing_contact}->getdata("address"),
		city=>$this->{transaction}{billing_contact}->getdata("city"),
		# the country and state must be 2 character codes which may not be the case atm
		country=>&Modules::Pay::getCountryAbbreviation($this->{transaction}{billing_contact}->getdata("country")),
		state=>$this->{transaction}{billing_contact}->getdata("provstate"),
		zip=>$this->{transaction}{billing_contact}->getdata("pcode"),
		email=>$this->{transaction}{billing_contact}->getdata("email")
	);
	}
	return (%required_params,%optional_params,%prepop);
}

# params required by Paypal to perform a PDT transaction verification
sub verification_params {
	my ($this,%opt) = @_;
	return {
		cmd=>"_notify-synch",
		tx=>$opt{tx},
		# identity_token copied from website payment preferences
		at=>$this->gateway_setting("identity_token")
	};
}


# returns the variable name of the parameter which indicates the success or failure of a transaction	
sub result_paramname {
	my $this = shift;
	return $this->gateway_setting("result_param");
}

# variable passed through to paypal with encrypted transaction details
# to prevent tampering of forms submitted to paypal
sub key_paramname {
	my $this = shift;
	return "USER1";
}

1;
