package Modules::Pay::Moneris;

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


# MONERIS E-SELECT
# README:
# How To Guide for setting up Moneris
# Test Prodedure:
# login to https://esqa.moneris.com/mpg/index.php
# edit the hosted paypage options to change the approved and declined urls
# the urls should point to the receipt page (pay service page)
# the method should be POST
# configure response fields to return txn_number
# configure response fields to "Automatically prompt cardholder for new card number on decline."
# configure security to enable transaction verification (use XML option)
# configure appearance for cancel button url
# - must use path based url because query paramaters are not allowed

use strict;

use ExSite::Base;
use ExSite::Config;
use ExSite::FormBuilder;
use ExSite::Input;
use ExSite::Misc;
use ExSite::Util;
use ExSite::Time;
use LWP::UserAgent;
use XML::Twig;

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
	return exists $this->{input}{$this->result_paramname()} || 
		$this->{input}{cancelTXN};
}

sub Success {
	my $this = shift;
	my $crypt = new ExSite::Crypt();
	my $key = $crypt->decrypt($this->{input}{$this->key_paramname()});
	if ($key =~ /^[\d\.]+;\d+;\d+$/) {
	my ($amt,$id,$time) = split /;/, $key;
	$this->{transaction_details} = {
		amount => $amt,
		purchase_id => $id,
		time => $time,
	};
	if (time - $time < 36000) {
		# execute moneris transaction verfication process
		my $transactionKey = $this->{input}{transactionKey};
		$this->{status} = $this->{input}{message};
		my $result = $this->{input}{$this->result_paramname()};
		
		# moneris hpp enhanced cancel - see documentation
		if ($this->{input}{response_code} == 914) {
			return 0;
		}

		# do a verification request for the following statuses
		# Valid-Approved: The transaction was approved and successfully validated
		# Valid-Declined: The transaction was declined and successfully validated
		# Invalid: No reference to this transactionKey
		# Invalid-ReConfirmed: An attempt has already been made with this transactionKey
		# Invalid-Bad_Source: The referring URL is not correct
		my $ua = LWP::UserAgent->new;
		my $post_url = $this->gateway_setting("verify_url");
		my $response = $ua->post($post_url,$this->verification_params());

		if ($response->is_success) {
			# parse XML response ( choose XML on moneris hosted payment settings )
			my $t = new XML::Twig();
			$t->parse($response->content());
			my $root = $t->root;
			my $verified_status = $root->first_child_text('status');
			my $verified_amount = $root->first_child_text('amount');
			$this->{status} .=  " Verification: $verified_status";
			
			# if verification is invalid - mark as suspicious			
			# if verification is valid and statuses do not match or amounts do not match
			# mark as suspicious
			if ($verified_status =~ /^Invalid/) {
				$this->{status} .= " [SUSPICIOUS]";
			} elsif ($verified_status =~ /^Valid/) {
				if ($verified_amount != $amt || 
					($result == 1 && $verified_status !~ /Approved/i) || 
					($result == 0 && $verified_status !~ /Declined/i)) {
					$this->{transaction_details}{amount} = $verified_amount - 1;
					$this->{status} .= " [SUSPICIOUS]";
				}

				my $verified_result = $this->get_verified_result($verified_status);
				if ($verified_result && $config{Pay}{interac}{enable}) {
					my $interac_info;
					$interac_info .= $msg{"Issuer Name: "} . $this->{input}{ISSNAME} . $ml->br() if ($this->{input}{ISSNAME});
					$interac_info .= $msg{"Issuer Confirmation: "} . $this->{input}{ISSCONF} . $ml->br() if ($this->{input}{ISSCONF});
					$share{annotate_receipt} .= $ml->p($interac_info) if ($interac_info);
				}

				return $verified_result;
			}
		} else {
			$this->{status} = "Could not verify transaction -- manual check required";
			return 0;
		}
	}
	else {
		$this->{status} = "Transaction expired";
		return 0;
	}
	}
	else {
	$this->{status} = "Invalid transaction key";
	return 0;
	}
}

sub Cancel {
	my $this = shift;
	if ($this->{input}{cancelTXN} || $this->{input}{response_code} == 914) {
	return 1;
	}
}

sub Pass {
	my $this = shift;
	if (&preference("Pay.Moneris.capture_payment_metadata") && $this->{input}{card} && $this->{input}{f4l4}){
		my %card_info = (
			M=>"Mastercard",
			V=>"Visa",
			AX=>"American Express",
			DC=>"Diners Card",
			NO=>"Novus/Discover",
			SE=>"Sears",
		);
		return "Transaction approved: ".$card_info{$this->{input}{card}}." ".$this->{input}{f4l4};
	}
	return "Transaction approved: " . $this->Status();
}

sub Fail {
	my $this = shift;
	return "Transaction declined: " . $this->Status();
}

sub GetPurchaseId {
	my $this = shift;
	return $this->{transaction_details}{purchase_id};
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
	if ($opt{primary_contact}) {
	$this->{transaction}{email} = $opt{primary_contact}->getdata("email");
	$this->{transaction}{contact} = $opt{primary_contact};	
	}
	
	my $reply;
	if ($ENV{SCRIPT_NAME} =~ /^$config{server}{CGIpath}\/$config{prog}{page}$/) {
	my $uri = new ExSite::URI;
	$uri->setup();
	$uri->plaintext;
	$uri->service_page("Pay");
	$reply = $uri->write_full();
	}
	else {
	# not on a page;  may not work
	$reply = &relink;
	}
	# moneris uses fixed reply url currently
	$this->{transaction}{reply} = $reply;
	# set receipt page based on version
	my $version = $share{Page}->get_my("version");
    my $spage = &ExSite::Module::service_page("Pay");	
	$this->{transaction}{receipt_page} = $spage->id;
	
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
	if (defined &preference("Pay.$gateway.$key")) {
		return &preference("Pay.$gateway.$key");
	}
	$this->error("Missing $key configuration for $gateway gateway.");
	return undef;
}

sub post_params {
	my $this = shift;
	
	my %required_params = (
		ps_store_id=>$this->gateway_setting("ps_store_id"),
		hpp_key=>$this->gateway_setting("hpp_key"),
		charge_total=>$this->{transaction}{amount},
		$this->key_paramname() => $this->{transaction}{key},
	);

	# timestamp the order_id so we can submit retry requests
	my $t = new ExSite::Time;
	my $tstamp = $t->write("datetime");
	# hosted paypage language = en-ca|fr-ca
	my $lang = "en-ca";
	my $version = $share{Page}->get_my("version") || $config{default_version};
	# french version loose regexp
	if ($version =~ /fr/i) {
		$lang = "fr-ca";
	}
	my $cust_id;
	$cust_id = $this->{transaction}{contact}->id() if ($this->{transaction}{contact});
	my %optional_params = (
		# id used to identify the client
		cust_id=>$cust_id,
		# UNIQUE order identifier
		order_id=>$this->{transaction}{purchase_id},
		lang=>$lang,
		rvar_page=>$this->{transaction}{receipt_page},
		# email address for Moneris receipts
		email=>$this->{transaction}{email},
	);
	return (%required_params,%optional_params);
}

# params required by Moneris to perform a transaction verification
sub verification_params {
	my ($this) = @_;
	return {
		ps_store_id=>$this->gateway_setting("ps_store_id"),
		hpp_key=>$this->gateway_setting("hpp_key"),
		transactionKey=>$this->{input}{transactionKey}
	};
}

# returns the variable name of the parameter which indicates the success or failure of a transaction
sub result_paramname {
	my $this = shift;
	return $this->gateway_setting("result_param");
}

sub key_paramname {
	my $this = shift;
	return "rvar_key";
}

sub get_verified_result {
	my ($this,$status) = @_;
	return 1 if ($status =~ /Approved/i);
	return 0 if ($status =~ /Declined/i);
	return undef;
}


1;
