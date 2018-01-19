package Modules::Pay::MonerisVault;

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
#  This is a test gateway for e-commerce payments.  It supports the 
#  ExSite Payment API, namely:
#
#  Setup(%) - prepare an e-commerce gateway connection
#  SetupTransaction(%) - create a transaction
#  PostTransaction() - send the transaction to the gateway
#  IsReceipt() - determine whether this is a reply from the gateway
#  Success() - determine whether the transaction succeeded
#  Cancel() - determine whether the transaction was canceled
#  Pass() - process a transaction approval*
#  Fail() - process a declined transaction*
#  GetPurchaseId() - get the purchase ID
#  GetInvoicer() - get the name of the invoicing component
#  GetReceiptPageId() - get the receipt page ID, if defined
#  Status() - return a status/error message, if any
#
#  * only perform the processing that is needed for the e-commerce Gateway 
#  connection.  Account and invoice post-processing is handled by the Pay
#  module.
#----------------------------------------------------------------------------

use strict;

use ExSite::Config;
use ExSite::Input;
use ExSite::Misc;
use ExSite::Util;
use ExSite::Base;

use vars qw(@ISA $ml);
@ISA = qw(ExSite::Base);

use Modules::MonerisAPI;
use JSON;

sub Setup {
    my ($this,%opt) = @_;
    $ml = &get_obj("ML");
    $share{DB}->{map}->load_submaps("Finance");    
    if (!$this->{setup}) {
    my $in = new ExSite::Input;
    $this->{input} = $in->combine;
    &ExSite::Module::read_conf("MonerisAPI");
    $this->{store_id} = $config{MonerisAPI}{store_id};
    $this->{api_token} = $config{MonerisAPI}{api_token};
    $this->{tokenization_profile_id} = $config{MonerisAPI}{tokenization_profile_id};
    $this->{setup} = 1;
    }
    return 1;
}

#--- receipt processing

sub IsReceipt {
    my $this = shift;

    my $crypt = new ExSite::Crypt();
    my $key = $crypt->decrypt($this->{input}{key});
    if ($key =~ /^[\d\.]+;\d+;\d+$/) {
	    my ($amt,$id,$time) = split /;/, $key;
	    $this->{transaction_details} = {
	        amount => $amt,
	        purchase_id => $id,
	        time => $time,
	    };
	    return 1;
    }    
    return 0;
}

sub Success {
    my $this = shift;
    my $amount = $this->{transaction_details}{amount};
    my $purchase_id = $this->{transaction_details}{purchase_id};
    if ($amount && $purchase_id) {
        my $m = &ExSite::Module::get_module("MonerisAPI");
        my $token = $m->get_token();
        if (!$token) {
            return 0;
        }
        $this->{token_id} = $token->id();     
        my $mpgResponse = $m->charge_token($amount,$purchase_id,$token);
   
        if (ref $mpgResponse eq "mpgResponse") {
            $this->{Status} = $mpgResponse->getMessage();            
            my $responseCode = $mpgResponse->getResponseCode();
            if ($mpgResponse->getComplete() eq "true" && $responseCode <= 49) {
                return 1;
            }
        }
    }
    return 0;
}

sub Cancel {
    my $this = shift;
    return $this->{input}{canceled};
}

sub Pass {
    my $this = shift;
    return "Transaction approved."
}

sub Fail {
    my $this = shift;
    return "Transaction declined: ".$this->{Status};
}

sub GetAmount {
    my $this = shift;
    return $this->{transaction_details}{amount};
}

sub SetupTransaction {
    my ($this,%opt) = @_;
    $this->{receivable} = \%opt;
    return 1;
}

sub PostTransaction {
    my $this = shift;
    my $out;
    my $amount = $this->{receivable}{amount};
    my $purchase_id = $this->{receivable}{purchase_id};    
    my $r = new Modules::Finance::Receivable(id=>$purchase_id);
    if (!$r->allow_payment || !$r->count_items()) {
        $session{invoice} = 0;    
	    return $this->error($msg{"Invalid invoice or payment has already been processed. Please contact website support for more information."});
    } elsif ($r->has_payments) {
        $session{invoice} = 0;
	    return $this->error($msg{"Payment has already been processed. Please contact website support for more information."});
    }
  
    $out .= $ml->h1("Payment Form");
    $out .= $ml->div("Invoice $purchase_id");
    $out .= $r->show();
    my $m = &ExSite::Module::get_module("MonerisAPI");
    if ($share{DB}->my_uid) {
        my $token = $m->get_token();
        if ($token) {
            my $sp = &ExSite::Module::service_page("MonerisAPI");
            $out .= $ml->h2("Pay using the credit card on your account");
            $out .= $m->get_token_description($token);
            my $pay_url = $m->get_return_url($amount,$purchase_id);
            $out .= $ml->p( &ExSite::HTML::Button(label=>"Update my card",url=>$sp->link(monerisAPI=>"add_card",cart=>"checkout") ));
            $out .= $ml->p( &ExSite::HTML::Button(label=>"Pay Now",url=>$pay_url ));
            return $out;            
        }
    }
    $out .= $m->hosted_form($purchase_id,$amount);
    return $out;
}

sub GetReceiptPageId {
    my $this = shift;
    return undef;
}

sub Status {
    my $this = shift;
    return undef;
}

sub GetTransactionId {
	my $this = shift;
	return $this->{transaction_details}{transaction_id};
}

sub GetPurchaseId {
    my $this = shift;
    return $this->{transaction_details}{purchase_id};
}

sub Type {
    my $this = shift;
    return "integrated";
}

1;
