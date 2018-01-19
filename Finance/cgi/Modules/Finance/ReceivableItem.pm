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

package Modules::Finance::ReceivableItem;

use strict;
use ExSite::Config;
use ExSite::Object;
use ExSite::Misc;
use Modules::Finance::Acctcode;

use vars qw(@ISA);
@ISA = qw(ExSite::Object);

sub my_type { return "receivable_item"; }

sub is_active {
    my $this = shift;
    return ($this->getdata("status") ne "deleted");
}

sub is_visible {
    my $this = shift;
    return ($this->getdata("status") !~ /hidden|deleted/);
}

sub showdata {
    my ($this,$key,$auth) = @_;
    $this->load() if (!defined $this->{data});
    if ($key eq "quantity" && $this->{data}{quantity} == 0.00) {
	return "";
    }
    return $this->SUPER::showdata($key,$auth);
}

sub name {
    my $this = shift;
    $this->load() if (!defined $this->{data});
    return $this->{data}{item} || "(undefined receivable item)";
}

# glcode is a GL code for the item
# 1xx(.yyy.zzz) => sales
#    xx = acctcode (sales type)
#    yyy, zzz = sub-codes, eg. specific event, merchandise types 
# 3xx(.yyy.zzz) => refunds (same encoding)

sub glcode {
    my $this = shift;
    if (! $share{glcode}) {
	$share{glcode} = &keywise("icode",scalar $share{DB}->fetch_all("glcode"));
    }
    my @code = $this->iglcode();
    my $code = shift @code;
    my $glcode;
    if ($share{glcode}{$code}) { $glcode = $share{glcode}{$code}{xcode}; }
    my $acctcode2 = shift @code;
    if ($acctcode2) {
	$code .= ".$acctcode2";
	if ($share{glcode}{$code}) { $glcode = $share{glcode}{$code}{xcode}; }
	my $acctcode3 = shift @code;
	if ($acctcode3) {
	    $code .= ".$acctcode3";
	    if ($share{glcode}{$code}) { $glcode = $share{glcode}{$code}{xcode}; }
	}
    }
    # return most specific external glcode, or internal glcode if none
    return $glcode || $code;
}

# iglcode: returns the internal glcode, optionally as array

sub iglcode {
    my $this = shift;
    my $basecode = $this->receivable->getdata("type") =~ /payable/ ?
	"3%02d" : "1%02d";
    my $acctcode = $this->acctcode();
    my @code;
    push @code, sprintf $basecode, $acctcode->id();
    my $acctcode2 = $this->getdata("acctcode2");
    if ($acctcode2 =~ /\w/) {
	push @code, $acctcode2;
	my $acctcode3 = $this->getdata("acctcode3");
	if ($acctcode3 =~ /\w/) {
	    push @code, $acctcode3;
	}
    }
    return wantarray ? @code : join ".", @code;
}

sub quantity {
    my $this = shift;
    if ($this->loaded) {
	if ($this->is_active) {
	    my $q = $this->{data}{quantity};
	    if ($q > 0.00) {
		# report X.00 values as integer values X
		return ($q =~ /\.00$/) ? int($q) : $q;
	    }
	    return 1;
	}
    }
    return undef;
}

sub unitprice {
    my $this = shift;
    return ($this->is_active) ?
	sprintf "%.02f", $this->{data}{cost} : 
	undef;
}

sub subtotal {
    my $this = shift;
    return ($this->is_active) ?
	sprintf "%.02f",$this->quantity() * $this->{data}{cost} :
	undef;
}

sub size {
    my $this = shift;
    return ($this->is_active) ?
	$this->quantity() * $this->{data}{size} :
	undef;
}

sub set_uid {
    my ($this,$uid) = @_;
    $this->{data}{uid} = $uid || $this->DB->my_uid;
}

sub is_surcharge {
    my ($this) = @_;
    return $this->{data}{surcharge_id};
}

sub receivable {
    my $this = shift;
    return new Modules::Finance::Receivable(id=>$this->getdata("receivable_id"));
}

sub acctcode {
    my $this = shift;
    return new Modules::Finance::Acctcode(id=>$this->getdata("acctcode_id"));
}

sub fulfill {
    my ($this,$qty,$note) = @_;
    if ($this->is_active) {
	my $t = new ExSite::Time();
	$this->setdata("fulfilled_on",$t->write("sql_datetime"));
	$this->setdata("fulfilled_by",$share{DB}->my_uid() || 0);
	my $qty_ordered = $this->getdata("quantity");
	if ($qty_ordered) {
	    my $new_qty;
	    if ($qty) {
		# increment the qty shipped by the quantity passed
		my $qty_shipped = $this->getdata("fulfilled_qty");
		$new_qty = $qty_shipped > 0.00 ?
		    $qty_shipped + $qty :
		    $qty;
	    }
	    else {
		# no quantity specified; assume order is completely fulfilled
		$new_qty = $qty_ordered;
	    }
	    $this->setdata("fulfilled_qty",$new_qty);
	}
	if ($note) {
	    my $old_note = $this->getdata("note");
	    if ($old_note && $old_note !~ /\n$/) {
		$old_note .= "\n";
	    }
	    $this->setdata("note",$old_note.$note);
	}
	$this->save();
    }
}

sub is_fulfilled {
    my ($this) = @_;
    if ($this->is_active) {
	# order fulfillment supported
	return (($this->getdata("fulfilled_on") gt "0000-00-00 00:00:00") &&
		($this->getdata("fulfilled_qty") == $this->getdata("quantity")));
    }
    return undef;
}

sub purchased_object {
    my $this = shift;
    my $type = $this->getdata("objtype");
    my $id = $this->getdata("objid");
    return ($type && $id) ? &get_obj($type,$id) : undef;
}

#=== DISPLAY

sub showauth { 
    my ($this,$key) = @_;
    return $this->is_active ? 1 : $this->{auth};
    # set auth to allow unknown users to view this item
    # return $this->{auth};
}

sub show {
    my ($this,%opt) = @_;
    if ($this->ok) {
	if ($this->loaded) {
	    my $ml = new ExSite::ML;
	    my $foot = $ml->div("Subtotal: \$".$this->subtotal,
				{style=>"text-align:right"});
	    return $this->DB()->report({ 
		title=>$this->name,
		table=>$this->{type},
		data=>[$this->{data}], 
		foot=>$foot,
		columns=>"full|brief",
		type=>"full", 
		%opt });
	}
	else {
	    return $this->error("no receivable item to display");
	}
    }
    return $this->error($this->{status});
}

sub brief_description {
    my $this = shift;
    my $out;
    if ($this->is_active) {
	if ($this->{data}{quantity} > 0.00) {
	    $out = $this->quantity." &times; ";
	}
	$out .= $this->showdata("item");
	if ($this->{data}{description}) {
	    $out .= " (".$this->showdata("description").")";
	}
    }
    return $out;
}

# location() returns the location of the purchase, for the purposes of
# determining tax and/or shipping rules. It defaults to the account
# holder's location, but you can pass in another contact record, or 
# override with a handler.

sub location {
    my ($this,$contact) = @_;
    if ($this->is_active) {
	my $stat = $this->run_handler("ReceivableItem_location",$contact);
	if (ref $stat eq "ARRAY") {
	    return @$stat;
	}
	# check if the item defines its own location
	my $country = $this->getdata("country");
	my $prov = $this->getdata("provstate");
	return ($prov,$country) if ($country || $prov);
	# otherwise, use the purchaser's location
	if (ref $contact ne "Modules::ID::Contact") {
	    $contact = $this->receivable->account->get_contact();
	}
	$country = $contact->getdata("country");
	$prov = $contact->getdata("provstate");
	return ($prov,$country);
    }
}

sub validate {
    my $this = shift;
    my @err;
    if ($this->getdata("quantity") < 0) {
	push @err, "invalid quantity";
    }
    if ($this->getdata("size") < 0) {
	push @err, "invalid size";
    }
    push @err, $this->SUPER::validate();
    return @err;
}

# delete: set status to deleted; do not actually remove the record

sub delete {
    my ($this,$skip_check) = @_;
    if ($this->defined) {
	if ($this->is_surcharge) {
	    # surcharges can be deleted for real
	    $share{DB}->trash_r("receivable_item",$this->{id},$skip_check);
	    my $subitems = $this->get_child("receivable_item");
	    while (my $item = $subitems->next) {
		$item->delete($skip_check);
	    }
	}
	else {
	    # keep record of deletions of actual items
	    $this->setdata("status","deleted");
	    if ($this->force_save()) {
		# also remove sub-purchases
		my $subitems = $this->get_child("receivable_item");
		while (my $item = $subitems->next) {
		    $item->delete($skip_check);
		}
	    }
	}
    }
    return undef;
}

1;

