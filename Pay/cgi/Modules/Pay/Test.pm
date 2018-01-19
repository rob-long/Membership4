package Modules::Pay::Test;

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

sub Setup {
    my ($this,%opt) = @_;
    # test gateway has nothing to set up
}

#--- receipt processing

sub IsReceipt {
    my $this = shift;
    my $input = new ExSite::Input;
    $this->{input} = $input->query();
    my $crypt = new ExSite::Crypt();
    my $key = $crypt->decrypt($this->{input}{key});
    if ($key =~ /^[\d\.]+;\d+;\d+$/) {
	    my ($amt,$id,$time) = split /;/, $key;
	    $this->{transaction_details} = {
	        amount => $amt,
	        purchase_id => $id,
	        time => $time,
	    };    
    }    
    return exists $this->{input}{transaction_status};
}

sub Success {
    my $this = shift;
    if (my $time = $this->{transaction_details}{time}) {
	if (time - $time < 600) {
	    return $this->{input}{transaction_status};
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
    return $this->{input}{canceled};
}

sub Pass {
    my $this = shift;
    return "Transaction approved.";
}

sub Fail {
    my $this = shift;
    return "Transaction declined.";
}

sub GetAmount {
    my $this = shift;
    return $this->{transaction_details}{amount};
}

sub SetupTransaction {
    my ($this,%opt) = @_;
    $this->{transaction} = \%opt;
    my $amt = $opt{amount};
    my $id = $opt{purchase_id};
    my $time = time;
    my $crypt = new ExSite::Crypt;
    $this->{transaction}{key} = $crypt->encrypt("$amt;$id;$time");
    my $reply;
    if ($ENV{REQUEST_URI} =~ /^$config{server}{CGIpath}\/$config{prog}{page}/) {
	my $uri = new ExSite::URI;
	$uri->setup();
	$uri->plaintext;
	# EDIT - payment is not a module
	$uri->service_page("Pay");
	$reply = $uri->write_full();
    }
    else {
	# not on a page;  may not work
	$reply = &relink();
    }
    $this->{transaction}{reply} = $reply;
    return 1;
}

sub PostTransaction {
    my $this = shift;
    my $url = new ExSite::URI;
    $url->setup("$config{server}{server}$config{server}{CGIpath}/pay.cgi");
    $url->plaintext;
    $url->query(
		amount => $this->{transaction}{amount},
		purchase_id => $this->{transaction}{purchase_id},
		key => $this->{transaction}{key},
		reply=> $this->{transaction}{reply},
		);
    &redirect($url->write());
    return 1;
}

sub GetReceiptPageId {
    my $this = shift;
    return undef;
}

sub Status {
    my $this = shift;
    # test gateway always has a clean status
    return undef;
}

sub GetTransactionId {
	my $this = shift;
	$this->warn("GetTransactionId purchase_id" . $this->{transaction_details}{purchase_id});
	return $this->{transaction_details}{purchase_id};
}

sub GetPurchaseId {
    my $this = shift;
	$this->warn("GetPurchaseId purchase_id" . $this->{transaction_details}{purchase_id});    
    return $this->{transaction_details}{purchase_id};
}

1;
