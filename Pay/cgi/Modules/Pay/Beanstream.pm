package Modules::Pay::Beanstream;

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
#  This is a gateway for Beanstream e-commerce payments.  It supports the 
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

#Test credit card
#VISA - 4030000010001234
#CVD 123

=pod

SETUP:

Beanstream configurations are done in the order settings page.
make sure invoice amount or invoice id is NOT editable
set hash_key configuration to validate responses
only check off "Include hash validation in Transaction Response Page redirection.." for hosted solution
=cut

use strict;

use ExSite::Base;
use ExSite::Config;
use ExSite::FormBuilder;
use ExSite::Input;
use ExSite::Misc;
use ExSite::ObjectMeta;
use ExSite::Util;
use ExSite::Time;
use LWP::UserAgent;
use XML::Twig;
use Digest::MD5 qw(md5_hex);

use vars qw(@ISA $ml);
@ISA = qw(ExSite::Base);

sub Setup {
	my ($this,%opt) = @_;
	return 1;
}

#--- receipt processing

sub IsReceipt {
	my $this = shift;
	my $input = new ExSite::Input;
	$this->{input} = $input->combine();
	my $crypt = new ExSite::Crypt();
	my $key = $crypt->decrypt($this->{input}{$this->key_paramname()});
	if ($key =~ /^[\d\.]+;\d+;\d+$/) {
	my ($amt,$id,$time) = split /;/, $key;
	$this->{transaction_details} = {
		amount => $amt,
		purchase_id => $id,
		time => $time,
	};
	}
	else {
	$this->{status} = "Invalid transaction key";
	return 0;
	}
	return exists $this->{input}{$this->result_paramname()};
}

sub Success {
	my $this = shift;
	my $time = $this->{transaction_details}{time};
	if (time - $time >= 3600) {
		$this->{status} = "Transaction start: $time.";
	}
	
	# validate hashValue from query string if hash_key is set
	my $hash_key = $this->gateway_setting("hash_key");
	if ($hash_key && $this->{input}{hashValue}) {
		my $query_string = $share{input}{get}{raw};
		$query_string =~ s/&hashValue=.+//g;
		my $validate_string = $query_string.$hash_key;
		my $hash_value = md5_hex($validate_string);
		if ($this->{input}{hashValue} ne $hash_value) {
			$this->{status} .= " [suspicious] ";
			return 0;
		}
	}
	my $transactionKey = $this->{input}{transactionKey};
	my $result = $this->{input}{$this->result_paramname()};
	# add canceled to status to cancel invoice ( we cannot allow retries due to beanstream api )
	if (!$result) {
		$this->{status} .= "[CANCELED] " . $this->{input}{messageText};
	} else {
		my $cardType = $this->card_type($this->{input}{cardType});
		$this->{status} .= $cardType." " if ($cardType);
		$this->{status} .= $this->{input}{messageText}."; AuthCode ".$this->{input}{authCode};
		if (my $b_account = $this->{input}{rbAccountId} || $this->{input}{billingId}) {
		$this->{status} .= " Account: ".$b_account;
		}
	}
	return $result;
}

sub Pass {
	my $this = shift;
	return $this->Status();
}

sub Fail {
	my $this = shift;
	return $this->Status();
}

sub GetPurchaseId {
	my $this = shift;
	return $this->{transaction_details}{purchase_id};
}

sub GetAmount {
	my $this = shift;
	# recurring transaction response
	if ($this->{input}{billingId}) {
		return $this->{input}{billingAmount};
	}
	# immediate redirect
	return $this->{transaction_details}{amount};
}

sub SetupTransaction {
	my ($this,%opt) = @_;
	$this->{transaction} = \%opt;
	$this->set_key($opt{amount},$opt{purchase_id});
	$this->{transaction}{primary_contact} = $opt{primary_contact};
	
	my $reply;
	if ($ENV{REQUEST_URI} =~ /^$config{server}{CGIpath}\/$config{prog}{page}/) {
	# service_page will find match service page version with current page version
	my $p = &ExSite::Module::service_page("Pay");
	# return a fully qualified dynamic url to the pay service page using path notation
	$reply = $config{server}{server} . $p->get_url_dynamic();
	}
	else {
	# not on a page;  may not work
	$reply = &relink();
	}
	$this->{transaction}{reply} = $reply;
	return 1;
}

sub set_key {
	my ($this,$amt,$id) = @_;
	my $time = time;
	my $crypt = new ExSite::Crypt;
	$this->{transaction}{key} = $crypt->encrypt("$amt;$id;$time");
}

sub PostTransaction {
	my $this = shift;
	my $url = new ExSite::URI;
	my $post_url = $this->gateway_setting("post_url");
	my %post_params = $this->post_params();

	my $f = new ExSite::FormBuilder(method=>"post",action=>$post_url,"accept-charset"=>"ISO-8859-1");
    $f->name("send_gateway");	
    $f->buttons(submit=>0,cancel=>0,reset=>0);

	$f->input(type=>"hidden",name=>"merchant_id",value=>$post_params{merchant_id});
	my $hash_key = $this->gateway_setting("hash_key");
	if ($hash_key) {
	my $validate_string = "merchant_id=".$post_params{merchant_id}."$hash_key";
	my $hash_value = md5_hex($validate_string);
	$this->warn("validate_string:".$validate_string);
	$this->warn("hash_value:".$hash_value); 
	$f->input(type=>"hidden",
			name=>"hashValue",
			value=>$hash_value);	
	}
	delete $post_params{merchant_id};
	
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
	return "Beanstream: ".$this->{status};
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

	# timestamp the order_id so we can submit retry requests
	my $t = new ExSite::Time;
	my $tstamp = $t->write("datetime");
	
	# hosted paypage language = ENG|FRE
	my $lang = "ENG";
	my $version = $share{Page}->get_my("version") || $config{default_version};
	# french version loose regexp
	if ($version =~ /fr/i) {
		$lang = "FRE";
	}
	
	# recurring payment plan parameters
	my %recurring_params;
	my $stat = $this->run_handler("Pay_custom_payment_beanstream_setup");
	%recurring_params = %$stat if ($stat);

    my $plan = &preference("Pay.payment_plan","receivable",$this->{transaction}{purchase_id});
	if ($plan && !$recurring_params{trnRecurring}) {
	if (&preference("Pay.payment_plan.$plan.num_payments") > 1) {
	my $num_payments = &preference("Pay.payment_plan.$plan.num_payments");
	my $increment = &preference("Pay.payment_plan.$plan.increment");
	my $period = &preference("Pay.payment_plan.$plan.period");
	my $expiry = new ExSite::Time;
	if (my $rolldate = &preference("Pay.rollover_date")) {
		my $year = $expiry->write("year");
		$expiry->set("$year-$rolldate","sql_date");
		my $today = new ExSite::Time;
		if ($today->diff($expiry) <= 0) {
			$expiry->add(1,"year");
		}
		if (!$increment || !$period) {
			my $diff = $today->diff($expiry);
			$increment = int(($diff / 86400) / $num_payments);
			$period = "days";
		}
	} else {
		$expiry->add($num_payments*$increment,$period);
	}
	my $abbr = { years=>"Y", months=>"M", weeks=>"W", days=>"D" };
	%recurring_params = (
		trnRecurring =>1,
		# e.g bill every 2 weeks, period is D/W/M/Y and increment is a number
		rbBillingIncrement=>$increment,
		rbBillingPeriod=>$abbr->{$period},
		rbExpiry=>$expiry->write_format("%MM%DD%YYYY"),
		rbNeverExpires=>0
	);
	$this->{transaction}{amount} = sprintf("%.2f",$this->{transaction}{amount}/$num_payments);
	# set encrypted key with new amount
	$this->set_key($this->{transaction}{amount},$this->{transaction}{purchase_id});
	}
	}
	my $prefix = $this->gateway_setting("order_prefix");
	my @p = $share{DB}->fetch_match("payment",{receivable_id=>$this->{transaction}{purchase_id}});
	my $postfix;
	$postfix = "-r".scalar @p if (scalar @p);
	my %required_params = (
		merchant_id=>$this->gateway_setting("merchant_id"),
		trnOrderNumber=>$prefix.$this->{transaction}{purchase_id}.$postfix,
		trnAmount=>$this->{transaction}{amount},
		errorPage=>"https://www.beanstream.com/scripts/payment/payment.asp",
		approvedPage=>$this->{transaction}{reply},
		declinedPage=>$this->{transaction}{reply},
		$this->key_paramname() => $this->{transaction}{key},
	);
	my $primary_contact = $this->{transaction}{primary_contact};
	my $invoice = new Modules::Finance::Receivable(id=>$this->{transaction}{purchase_id});
	$this->{account} = new Modules::Finance::Account(id=>$invoice->getdata("account_id"));
	my $address = $primary_contact->{address};
	$address =~ s/\r\n/ /g;
	my %optional_params = (
		# id used to identify the client
		ordName=>substr($this->{account}->name,0,64),
		ordAddress1=>substr($address,0,64),
		ordCity=>substr($primary_contact->{city},0,32),
		ordProvince=>substr($primary_contact->{provstate},0,2),
		ordPostalCode=>substr($primary_contact->{pcode},0,16),
		ordPhoneNumber=>substr($primary_contact->{phone1},0,32),
		ordCountry=>substr(&Modules::Pay::getCountryAbbreviation(
			$primary_contact->{country}),0,2),
		ordEmailAddress=>substr($primary_contact->{email},0,64),
		trnLanguage=>$lang,		
	);
	
	$optional_params{"ref2"} = $invoice->description();
	$this->warn(&ShowHash(%recurring_params));
	return (%required_params,%optional_params,%recurring_params);
}

# returns the variable name of the parameter which indicates the success or failure of a transaction	
sub result_paramname {
	my $this = shift;
	return $this->gateway_setting("result_param");
}

# returns the variable name of the encrypted transaction details which are passed unchanged to the gateway and then back
sub key_paramname {
	my $this = shift;
	return $this->gateway_setting("rvar_key") || "ref1";
}

sub GetReceiptPageId {
	my $this = shift;
	my $page = &ExSite::Module::service_page("Pay");
	return $page->id();
}

sub Cancel {
	my $this = shift;
	return ($this->{input}{messageText} =~ /Payment Canceled/i);
}

sub GetTransactionId {
	my $this = shift;
	return $this->{input}{trnId};
}
sub GetPaymentId{
	my $this = shift;
	return $this->card_type($this->{input}{cardType});
}
sub card_type{
	my ($this,$code) = @_;
	my %map = ( VI=>"Visa",MC=>"MasterCard",AM=>"American Express",NN=>"Discover",DI=>"Diners",JB=>"JCB",IO=>"INTERAC Online",ET=>"Direct Debit/Direct Payments/ACH" );
	return $map{$code};
}

1;
