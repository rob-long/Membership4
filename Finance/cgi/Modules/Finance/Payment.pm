#!/usr/bin/perl
#-----------------------------------------------------------------------
#
#   Copyright 2001-2007 Exware Solutions, Inc.  http://www.exware.com
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

package Modules::Finance::Payment;

use strict;
use ExSite::Config;
use ExSite::Object;
use ExSite::Misc;

use vars qw(@ISA %method);
@ISA = qw(ExSite::Object);

# GL codes
%method = (
    other => "00",
    cash => "01",
    'e-commerce' => "02",
    cheque => "03",
    check => "03",
    'check/cheque' => "03",
    'money order' => "04",
    'debit card' => "05",
    'credit card' => "10",
    'credit card/Visa' => "11",
    'credit card/MC' => "12",
    'credit card/Amex' => "13",
    );

sub my_type {
    return "payment";
}

sub amount {
    my $this = shift;
    if ($this->defined) {
	if ($this->{data}{status} eq "paid") {
	    return $this->{data}{amount};
	}
    }
    return undef;
}

# glcode is a GL code for the payment
# 2xx => payments
#    xx = payment method
# 4xx => refund payments (same encoding)

sub glcode {
    my $this = shift;
    if (! $share{glcode}) {
	$share{glcode} = &keywise("icode",scalar $share{DB}->fetch_all("glcode"));
    }
    my $code = $this->iglcode();
    my $glcode;
    if ($share{glcode}{$code}) { $glcode = $share{glcode}{$code}{xcode}; }
    return $glcode || $code;
}

sub iglcode {
    my $this = shift;
    my ($code,$glcode);
    my $receivable_id = id=>$this->getdata("receivable_id");
    if ($receivable_id) {
	my $receivable = new Modules::Finance::Receivable(id=>$receivable_id);
	$code = $this->receivable->is_payable ? "4" : "2";
    }
    else {
	# payment on account
	$code = "2";
    }
    $code .= $method{$this->getdata("method")} || "00";
    my $acctid = $this->getdata("account_id");
    $code .= ".".$acctid;
    my $invid = $this->getdata("receivable_id");
    if ($invid) {
	$code .= ".$invid";
    }
    return $code;
}

# status:
# paid: payment is complete
# received: payment received, but unconfirmed (eg. cheque received)
# processing: payment sent to payment gateway, no reply received
# canceled: received or processing payment was canceled, declined, NSF, etc.
# suspicious: payment received from gateway, but confirmation check crashed
#             (requires manual reconciliation)

sub set_status {
    my ($this,$status) = @_;
    if ($status =~ /^paid|received|processing|canceled|suspicious$/) {
	if ($this->defined) {
	    $this->setdata("status",$status);
	    return $this->save();
	}
    }
    return undef;
}
sub paid       { return &set_status(@_,"paid"); }
sub received   { return &set_status(@_,"received"); }
sub processing { return &set_status(@_,"processing"); }
sub canceled   { return &set_status(@_,"canceled"); }
sub suspicious { return &set_status(@_,"suspicious"); }

sub is_paid { 
    my $this = shift; 
    $_ = $this->getdata("status");
    if (/paid/) { 
	# confirmed payment
	return 1;
    }
    elsif (/canceled/) {
	# confirmed non-payment
	return 0;
    }
    else {
	# unconfirmed payment
	return -1;
    }
}

sub receivable {
    my $this = shift;
    my $inv = $this->getdata("receivable_id");
    if ($inv) {
	return new Modules::Finance::Receivable(id=>$inv);
    }
    return undef;
}

sub account {
    my $this = shift;
    return new Modules::Finance::Account(id=>$this->getdata("account_id"));
}

sub edit {
    my $this = shift;
    my $out = $this->warn("For auditing reasons, you cannot edit payment 
amounts that have already been logged.  Instead, enter new payment records to 
correct or offset incorrect payments.  You can however, correct other 
informaton on the payment.");
    $out .= $this->SUPER::edit();
    return $out;
}

sub show {
    my ($this,%opt) = @_;
    my $out;
    if ($this->ok) {
	if (! $this->{data}) { $this->load(); }
	if (! $this->{data}) {
	    my $name = ucfirst $this->name;
	    return $this->error("No such payment.");
	}
	my $amt = $this->showdata("amount");
	my $date = $this->showdata("date");
	my $method = $this->showdata("method");
	my $status = $this->showdata("status");
	if ($status eq "paid") {
	    if ($amt >= 0) {
		$out .= &substitute($msg{"[[amount]] paid by [[method]] at [[date]]"},{amount=>$amt,date=>$date,,method=>$method});
	    }
	    else {
		$out .= &substitute($msg{"Refunded [[amount]] at [[date]]"},{amount=>$amt,date=>$date,,method=>$method});
	    }
	}
	else {
	    $out .= &substitute($msg{"[[status]] PAYMENT in the amount of [[amount]] at [[date]]"},{status=>uc($status),amount=>$amt,date=>$date,,method=>$method});
	}
	my $note = $this->showdata("note");
	if ($note) { $out .= " (\"$note\")"; }
    }
    return $out;
}


=pod
sub name {
    my $this = shift;
    $this->load() if (!defined $this->{data});
    return "Payment ".$this->{data}{date}."-".$this->id;
}
=cut

=pod
sub validate {
    my $this = shift;
    return ($msg{"no data"}) if (ref $this->{data} ne "HASH");
    my $action = $this->action;
    if ($action eq "update") {
	return $this->DB->validate_record_update($this->{type},$this->{data});
    }
    else {
	return $this->DB->validate_record_insert($this->{type},$this->{data});
    }
}
=cut

1;
