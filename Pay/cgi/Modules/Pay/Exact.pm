package Modules::Pay::Exact;

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

=pod

Test credit card
Visa 4111111111111111 / expiration date: any future date

SETUP:
E-xact chase paymentech configurations are done at https://pos.e-xact.com/
set Automatic linking to the receipt page including result parameters using HTTP POST method (AUTO-POST)
set to use relay response and set url to be cart service page
check off allow redirect
=cut


use strict;

use ExSite::Base;
use ExSite::Config;
use ExSite::FormBuilder;
use ExSite::Input;
use ExSite::Misc;
use ExSite::Util;
use ExSite::Time;
use Digest::HMAC_MD5 qw(hmac_md5_hex);
use Digest::MD5 qw(md5_hex);

use vars qw(@ISA $ml);
@ISA = qw(ExSite::Base);

$ml = &get_obj("ML");

sub Setup {
	my ($this,%opt) = @_;
	my $input = new ExSite::Input;
	$this->{input} = $input->post();
	$this->{query} = $input->query();
	$this->{input} = $input->combine();
	return 1;
}

#--- receipt processing

sub IsReceipt {
	my $this = shift;
	return exists $this->{input}{"x_response_code"};
}

sub Success {
	my $this = shift;
	my $responseKey = $this->gateway_setting("response_key");
	my $loginID = $this->gateway_setting("x_login");
	my $transID = $this->{input}{x_trans_id};
	my $amount = $this->{input}{x_amount};
	my $fingerprint = md5_hex($responseKey.$loginID.$transID.$amount);
	my $their_md5 = $this->{input}{x_MD5_Hash};
	my $verified = $fingerprint eq $their_md5 ? 1 : 0;
	$this->{status} = $this->{input}{x_response_reason_text}." Authorization #".$this->{input}{x_auth_code};
	if ($this->{input}{$this->result_paramname()} == 1) {
		if (!$verified) {
			$this->{status} = "[SUSPICIOUS] " . $this->{status};
		}
		return 1;
	}
	return 0;
}

sub Cancel {
	my $this = shift;
	return undef;
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
	return $this->{input}{x_invoice_num};
}

sub GetAmount {
	my $this = shift;
	return $this->{input}{x_amount};
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
	my $crypt = new ExSite::Crypt;
	$this->{transaction}{key} = $crypt->encrypt("$amt;$id;$time");
	if ($opt{account}) {
	$this->{transaction}{account} = $opt{account};
	$this->{transaction}{contact} = $opt{primary_contact} || $opt{account}->get_contact();
	}
	
	my $id = $share{Page}->id;
	$this->{transaction}{reply} = "$config{server}{server}$config{server}{CGIpath}/$config{prog}{page}?_id=$id";
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
	my $version;
	if ($share{Page}) {
		$version = $share{Page}->get_my("version");
	}	
	if ($version && defined &preference("Pay.$gateway.${key}_${version}")) {
		return &preference("Pay.$gateway.${key}_${version}");
	}
	if (defined &preference("Pay.$gateway.$key")) {
		return &preference("Pay.$gateway.$key");
	}
	$this->error("Missing $key configuration for $gateway gateway.");
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
	my $test_mode = $this->gateway_setting("test_mode") ? "TRUE" : "FALSE";
	my %required_params = (
		x_login=>$loginID,
		x_amount=>$amount,
		x_description=>$this->{transaction}{description},
		x_invoice_num=>$this->{transaction}{purchase_id},
		x_fp_sequence=>$sequence,
		x_fp_timestamp=>$timeStamp,
		x_fp_hash=>$fingerprint,
		x_test_request=>$test_mode,
		x_show_form=>'PAYMENT_FORM',
		# unneeded feature since we can use auto-redirect
#		x_relay_response=>"TRUE",
#		x_relay_url=>$this->{transaction}{reply},
		x_email_customer=>"TRUE",
	);
	my $invoice = new Modules::Finance::Receivable(id=>$this->{transaction}{purchase_id});	
	my ($first_name,$last_name) = split(" ", $this->{transaction}{account}->name);
	my %optional_params = (
		x_po_num=>$this->{transaction}{account}->id(),
		x_first_name=>$first_name,
		x_last_name=>$last_name,
		x_address=>$this->{transaction}{contact}->getdata("address"),
		x_city=>$this->{transaction}{contact}->getdata("city"),
		x_state=>$this->{transaction}{contact}->getdata("provstate"),
		x_zip=>$this->{transaction}{contact}->getdata("pcode"),
		x_country=>$this->{transaction}{contact}->getdata("country"),
		x_phone=>$this->{transaction}{contact}->getdata("phone1"),
		# email address for receipts
		x_email=>$this->{transaction}{contact}->getdata("email"),
	);
	return (%required_params,%optional_params);
}

# returns the variable name of the parameter which indicates the success or failure of a transaction	
sub result_paramname {
	my $this = shift;
	return $this->gateway_setting("result_param") || "x_response_code";
}

1;
