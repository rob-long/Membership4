#!/usr/bin/perl
#-----------------------------------------------------------------------
#
#   Copyright 2001-2009 Exware Solutions, Inc.  http://www.exware.com
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

package Modules::Finance::Surcharge;

use strict;
use ExSite::Config;
use ExSite::Object;
use ExSite::Misc;

use vars qw(@ISA);
@ISA = qw(ExSite::Object);

sub my_type { return "surcharge"; }

sub name {
    my $this = shift;
    $this->load() if (!defined $this->{data});
    return $this->{data}{name} || "(undefined surcharge)";
}

# description : used for receivable_item.description

sub description {
    my ($this,$item) = @_;
    my $data = $this->{data};
    if ($data->{percent} || $data->{percent} || $data->{persize} || $data->{perproduct}) {
	# surcharge pertains directly to this item
	return &substitute($msg{"for [[item]]"},{item=>$item->getdata("item")});
    }
    # surcharge is not item-specific, no description necessary
    return undef;
}

sub is_active {
    my $this = shift;
    if ($this->exists) {
	my $stat = $this->getdata("status");
	return 0 if ($stat eq "inactive");
	my $start = $this->getdata("valid_from");
	if ($start =~ /^0000/) { $start = undef; }
	my $end = $this->getdata("valid_to");
	if ($end =~ /^0000/) { $end = undef; }
	if ($start || $end) {
	    # time-limited surcharge
	    my $t = new ExSite::Time;  # now
	    if ($start && $t->diff($start,"sql_datetime") > 0) {
		# start time is in future
		return 0;
	    }
	    if ($end && $t->diff($end,"sql_datetime") < 0) {
		# end time is in past
		return 0;
	    }
	}
	return 1;
    }
    return undef;
}

# is_valid - test whether a surcharge can be used on this site

sub is_valid {
    my ($this,$section_id) = @_;

    # ignore disabled surcharges - also checks dates
    return 0 if (! $this->is_active);

    if (! $section_id) {
	my $s = $share{DB}->this_site;
	$section_id = $s ? $s->{content_id} : 0;
    }

    # check site
    if ($this->{data}{section_id}) {
	if ($section_id) {
	    if ($section_id != $this->{data}{section_id}) {
		# this surcharge is not for us
		return 0;
	    }
	}
	else {
	    return 0;
	}
    }
		
    # default is valid
    return 1;
}

sub allow {
    my ($this,$contact,$item,$code) = @_;
    my $stat = $this->run_handler("allow_surcharge",$contact,$item,$code);
    return $stat if (defined $stat);

    # check status, section, dates
    return 0 if (! $this->is_valid);
    # ignore deleted items
    return 0 if (! $item->is_active);

    # do not apply surcharges to themselves
    return 0 if ($item && $item->getdata("surcharge_id") == $this->id);

    # check coupon code
    my $coupon_code = $this->{data}{code};
    # RE allows for leading/trailing whitespace and case insensitivity
    return 0 if ($coupon_code && $code !~ /^\s*$coupon_code\s*$/i);
    ### FIXME: no warning if the code is invalid/has typo

    # tax-exempt status
    # tax_exempt_acctcodes is a hash of the tax account codes that are 
    # ignored for tax-exempt clients, eg. tax_exempt_acctcodes.TAX = 1
    if (defined $config{tax_exempt_acctcodes}) {
	if ($config{tax_exempt_acctcodes}{$this->showdata("treat_as")}) {
	    if ($item->receivable->account->getdata("taxcode")) {
		# this account is tax-exempt
		return 0;
	    }
	}
    }

    # geographic restrictions
    my $sc_c = $this->{data}{country};
    my $sc_p = $this->{data}{provstate};
    if ($sc_c || $sc_p) {
	# compare to contact
	my ($prov,$country) = $item->location();
	# valid if there are no regional rules
	if ($country || $prov) {
	    # check country validity
	    if ($sc_c) {
		# this surcharge is country-specific
		if ($sc_c =~ /^\!/) {
		    # applies to all BUT this country
		    $sc_c =~ s/^\!//;
		    return 0 if ($country =~ /^$sc_c$/);
		}
		else {
		    return 0 if ($country !~ /^$sc_c$/);
		}
	    }
	    
	    # check provstate validity
	    if ($sc_p) {
		# this surcharge is provstate-specific
		if ($sc_p =~ /^\!/) {
		    # applies to all BUT this provstate
		    $sc_p =~ s/^\!//;
		    return 0 if ($prov =~ /^$sc_p$/);
		}
		else {
		    return 0 if ($prov !~ /^$sc_p$/);
		}
	    }
	}
	else {
	    # purchaser has no known country or province
	    return 0 if ($sc_c !~ /^\!/ && $sc_p !~ /^\!/);
	}
    }

    # NB: if no item is passed, the surcharge is allowed (this means that
    # the surcharge is "active" within the context of this site, contact,
    # and date) but should not actually be applied to anything.

    if ((ref $item) =~ /ReceivableItem/) {
	# apply_to cases - we only apply the surcharge if the item matches one
	# of the apply_to cases
	my $apply_to = $this->{data}{apply_to};
	my $apply_to_gl = $this->{data}{apply_to_gl};
	my $apply_to_type = $this->{data}{apply_to_objtype};
	my $apply_to_id = $this->{data}{apply_to_objid};
	return 0 if ($apply_to && $apply_to != $item->getdata("acctcode_id"));
	return 0 if ($apply_to_gl && $apply_to_gl ne $item->glcode());
	if ($apply_to_type && $apply_to_id) {
	    return 1 if ($this->object_is_valid($apply_to_type,$apply_to_id,$item));
	}

	# minimums ?
	my $minq = $this->{data}{min_quantity};
	return 0 if ($minq && $minq > $item->quantity);
	my $minv = $this->{data}{min_value};
	return 0 if ($minv && $minv > $item->subtotal);
	my $mins = $this->{data}{min_size};
	return 0 if ($mins && $mins > $item->size);

	# lastly, we test the apply_if cases - these are true (ie. the
	# surcharge is valid) if the apply_if condition is true for any
	# items on this invoice
	my $apply_if = $this->{data}{apply_if};
	my $apply_if_gl = $this->{data}{apply_if_gl};
	my $apply_if_type = $this->{data}{apply_if_objtype};
	my $apply_if_id = $this->{data}{apply_if_objid};
	if ($apply_if || $apply_if_gl || $apply_if_type) {

	    # see if the condition matches the current item

	    return 1 if ($apply_if && $item->getdata("acctcode_id") == $apply_if);
	    return 1 if ($apply_if_gl && $item->glcode() eq $apply_if_gl);
	    if ($apply_if_type) {
		return 1 if ($this->object_is_valid($apply_if_type,$apply_if_id,$item));
	    }

	    # otherwise, see if it matches any other items

	    my $inv = $item->receivable;
	    my $items = $inv->loaditems();
	    while (my $otheritem = $items->next()) {
		next if (! $otheritem->is_active);
		next if ($otheritem->id == $item->id);
		return 1 if ($apply_if && $otheritem->getdata("acctcode_id") == $apply_if);
		return 1 if ($apply_if_gl && $otheritem->glcode() eq $apply_if_gl);
		if ($apply_if_type) {
		    my $item_type = $otheritem->getdata("objtype");
		    if ($item_type eq $apply_if_type) {
			return 1 if ($this->object_is_valid($apply_if_type,$apply_if_id,$otheritem));
		    }
		}
	    }

	    # found no matching items in invoice
	    return 0;
	}
    }
		
    # default is valid
    return 1;
}

# object_is_valid: tests the ojbtype and objid settings of a surcharge
# against the purchased item

sub object_is_valid {
    my ($this,$type,$id,$item) = @_;
    my $stat = $this->run_handler("Surcharge_object_is_valid",$type,$id,$item);
    return $stat if (defined $stat);
    my $objtype = $item->getdata("objtype");
    if (! $share{DB}{map}->is_mapped($objtype)) {
	# not a DB table, may be a content type
	my $c = new ExSite::Content;
	if ($c->isubtype($objtype)) { # yup, it's a content type
	    $objtype = "content";
	}
    }
    my $objid = $item->getdata("objid");

    # direct match?
    return 1 if ($objtype eq $type && $objid == $id);

    # also look for ancestor matches; for example an event could match
    # when purchasing a registration
    my $ancestor = $share{DB}->fetch_ancestor($type,$objtype,$objid);
    if ($ancestor) {
	my $pkey = $share{DB}{map}->get_table_attr($type,"key");
	if ($ancestor->{$pkey} == $id) {
	    return 1;
	}
	else {
	    # $ancestor is the FIRST ancestor, might be inadequate if these
	    # ancestors can nest
	    my %parent = map { $_=>1 } $share{DB}{map}->get_parents($type);
	    if ($parent{$type}) {
		# yup, we might be a subobject
		my $ref = $share{DB}{map}->get_reference_column($type,$type);
		return 1 if ($ref && $ancestor->{$ref} == $id);
		# sub-subobjects also possible; ignore that possibility
	    }
	}
    }
    return undef;
}

sub cost {
    my ($this,$quantity,$size,$cost,$receivable) = @_;
    my $surcharge = 0;
    $quantity or $quantity = 0;
    $size or $size = 0;
    $cost or $cost = 0;
    # peritem surcharge is per unit of quantity
    $surcharge += $quantity * $this->getdata("peritem");
    # persize surcharge is per unit of size
    $surcharge += $size * $this->getdata("persize");
    # percent surcharge is a percentage of cost
    $surcharge += $cost * ($this->getdata("percent") / 100.00);
    # per product surcharge is charged once per line item no matter how many are ordered
    $surcharge += $this->getdata("perproduct");
    # per order surcharge is charged once per invoice
    if ($receivable && $receivable->log_surcharge($this->id)) {
	$surcharge += $this->getdata("perorder");
    }
    return sprintf "%.02f", $surcharge;
}

sub validate {
    my $this = shift;
    if ($this->{data}{apply_to} == $this->{data}{treat_as}) {
	return ("Apply-to and Treat-as cannot be the same");
    }

    ### validate : check for circular surcharge references (eg. charging tax on tax)

    return $this->SUPER::validate();
}

1;

