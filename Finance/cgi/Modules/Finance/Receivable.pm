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

package Modules::Finance::Receivable;

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Object;
use ExSite::ObjectList;
use Modules::Finance::ReceivableItem;
use Modules::Finance::Surcharge;
use Modules::Finance::Account;

use vars qw(@ISA);
@ISA = qw(ExSite::Object);

sub my_type { return "receivable"; }

sub name {
    my $this = shift;
    my $stat = $this->run_handler("receivable_name");
    return $stat if (defined $stat);
    $this->load() if (!defined $this->{data});
    my $name = $this->getdata("receivable_id");
    my $inv = $this->getdata("invoice");
    my $type = $this->{data}{type} eq "receivable" ?
	"Invoice" : "Refund/Payable";
    return "$msg{$type} ".($inv ? "$name-$inv" : $name);
}

# description tries to add more information about the invoice such as
# number of purchased items, or the item name if there is only a single
# (non-surcharge) item on the invoice

sub description {
    my $this = shift;
    my $descr = $this->name;
    my $item;
    if (my $d = $this->getdata("description")) {
	$descr .= " ($d)";
    }
    elsif ($this->loaded) {
	my $nitems = $this->count_items(0);
	if ($nitems > 0) {
	    my $items = $this->loaditems();
	    $item = $items->next()->name();
	}
	if ($nitems > 1) {
	    my $nother = $nitems - 1;
	    $item .= ", ";
	    $item .= $nother > 1 ?
		&substitute($msg{"and [[other]] other items"},{other=>$nother}) :
		$msg{"and 1 other item"};
	}
	elsif ($nitems == 1) {
	    my $items = $this->loaditems();
	    $item = $items->next()->name();
	}
    }
    if ($item) {
	$descr .= " ($item)";
    }
    return $descr;
}

sub total {
    my $this = shift;
    if (my $items = $this->loaditems()) {
	my $total = 0;
	while (my $item = $items->next()) {
	    $total += $item->subtotal();
	}
	return sprintf("%.02f",$total);
    }
    return "0.00";
}

# subtotal of particular account codes
### FIXME: allow acctcode names in addition to IDs
sub subtotal {
    my ($this,@acctcode) = @_;
    if (my $items = $this->loaditems()) {
	my $total = 0;
	while (my $item = $items->next()) {
	    $total += $item->subtotal() if (grep { $_ eq $item->getdata("acctcode_id") } @acctcode);
	}
	return sprintf("%.02f",$total);
    }
    return "0.00";
}

sub show_total {
    my $this = shift;
    my $total = $this->total();
    return $this->getdata("type") eq "payable" ?
	"<span class='error'>(\$$total)</span>" : "\$$total";
}

sub size {
    my $this = shift;
    if (my $items = $this->loaditems()) {
	my $total = 0;
	while (my $item = $items->next()) {
	    $total += $item->size();
	}
	return $total;
    }
    return 0;
}

sub is_editable {
    my $this = shift;
    return ($this->getdata("status") eq "inactive");
    if ($this->defined()) {
	my $status = ($this->getdata("status") eq "inactive");
	if (! $status && $this->DB->is_admin()) {
	    # admins can override
	    $this->warn("You are modifying an active invoice.");
	    $status = 1;
	}
	return $status;
    }
    return undef;
}

sub allow_payment {
    my $this = shift;
    if ($this->defined()) {
	my $status = $this->getdata("status");
	if ($status =~ /processing/) {
	    # already sent to payment
	    return 0;
	}
	elsif ($this->DB->is_admin()) {
	    # admins can add payments at any time
	    return 1;
	}
	else {
	    # regular users can proceed to payment if their invoice is
	    # inactive or advisory
	    return ($status =~ /^(inactive|advisory)$/);
	}
    }
    return undef;
}

sub is_valid {
    my $this = shift;
    if ($this->defined()) {
	return ($this->getdata("status") =~ /^active|advisory$/);
    }
    return undef;
}

sub is_active {
    my $this = shift;
    if ($this->defined()) {
	return ($this->getdata("status") eq "active");
    }
    return undef;
}

sub is_receivable {
    my $this = shift;
    if ($this->defined()) {
	return ($this->getdata("type") eq "receivable");
    }
    return undef;
}

sub is_payable {
    my $this = shift;
    if ($this->defined()) {
	return ($this->getdata("type") eq "payable");
    }
    return undef;
}

sub account {
    my $this = shift;
    if (! $this->{Account}) {
	my $id = $this->getdata("account_id");
	$this->{Account} = new Modules::Finance::Account(id=>$id);
    }
    return $this->{Account};
}

sub activate {
    my $this = shift;
    if (! $this->is_valid) {
	my $stat = $this->run_handler("receivable_activate");
	return $stat if $stat;
	my $items = $this->loaditems();
	while (my $item = $items->next) {
	    if ($item->getdata("objtype") && $item->getdata("objid")) {
		my $obj = $item->purchased_object();
		if ($obj->can("sale_activate")) {
		    $obj->sale_activate($item);
		}
	    }
	}
	$this->setdata("status","active");
	# reset account object to force recalculation of balances
	$this->account->unload();
	return $this->force_save();
    }
    return undef;
}

# finalize : complete an invoice
# NB: does not activate the invoice, just produces a final total
# $code is an optional coupon code to access special surcharges/adjustments
# returns the number of added surcharges, or undef if we did nothing.

sub finalize {
    my ($this,$code) = @_;
    my $status = $this->getdata("status");
    if ($status =~ /^(inactive|advisory)$/) {
	# recalculate surcharges
	$this->remove_surcharges();
	return $this->add_surcharges($code);
    }
    else {
	$this->error("Cannot finalize $status receivable");
    }
    return undef;
}

# complete the purchase
# This is usually called once the receivable is paid in full.
# It does nothing to the invoice itself, but might do things to the 
# purchased items.

sub complete_sale {
    my $this = shift;
    if (! $this->getdata("status") eq "inactive") {
	$this->activate() or return undef;
    }
    if ($this->is_valid) {
	$share{DB}{map}->load_submaps(); # so we can instantiate purchased objects
	my $stat = $this->run_handler("receivable_finalize");
	return $stat if (defined $stat);
	my $items = $this->loaditems();
	while (my $item = $items->next) {
	    if ($item->getdata("objtype") && $item->getdata("objid")) {
		my $obj = $item->purchased_object();
		if ($obj->can("sale_complete")) {
		    $obj->sale_complete($item);
		}
	    }
	}
    }
    return undef;
}

sub get_payments {
    my $this = shift;
    return exists $this->{children}{payment} ?
	$this->{children}{payment} :
	$this->get_children("payment")->{payment};
}

sub has_payments {
    my $this = shift;
    my $payments = $this->get_payments();
    my $valid_payments = 0;
    if ($payments) {
	while (my $pay = $payments->next()) {
	    $valid_payments = 1 if ($pay->is_paid());
	}
    }
    return $valid_payments;
}

# has_item : return 1 if the item already exists
 
sub has_item {
    my ($this,$data) = @_;
    if (my $items = $this->loaditems()) {
      ITEM:
	while (my $item = $items->next()) {
	    foreach my $key ("item","description","objtype","objid") {
		if ($item->getdata($key) ne $data->{$key}) {
		    next ITEM;
		}
	    }
	    return 1;
	}
    }
    return 0;
}

# has this receivable been paid?

sub is_paid {
    my ($this,%opt) = @_;
    if (! $this->is_active()) {
	# not even an active receivable
	return 0;
    }
    else {
	# are there any payments on this invoice?
	my $payments = $this->get_payments();
	if ($payments->count() > 0) {
	    my $ptotal = 0;
	    while (my $pay = $payments->next()) {
		$ptotal += $pay->amount();
	    }
	    if ($ptotal >= $this->total()) {
		return 1;
	    }
	}
	if (!$opt{ignore_account_balance} && $this->account->balance() < 0.01) {
	    # nothing owing on account
	    return 1;
	}
	# unclear: no payments on the invoice, and balance owing on account
    }
    return 0;
}

sub is_paid {
    my ($this,%opt) = @_;
    if (! $this->is_active()) {
	# not even an active receivable
	return undef;
    }
    elsif ($this->total < 0.01) {
	# nothing to pay
	return 1;
    }
    else {
	# check payments on this invoice
	my $payments = $this->get_payments();
	if ($payments->count() > 0) {
	    my $ptotal = 0;
	    while (my $pay = $payments->next()) {
		if ($pay->is_paid) {
		    $ptotal += $pay->amount();
		}
	    }
	    if ($this->is_payable) { $ptotal = -$ptotal; } # payables go the other way
	    if ($this->total() - $ptotal < 0.01) {
		# less than 1 cent owing
		return 1;
	    }
	}
	# check payments on account
	if (!$opt{ignore_account_balance} && $this->account->balance() < 0.01) {
	    return 1;
	}
	# no payments on the invoice, and balance owing on account
	# check if account was ever paid off between then and now
	# NB: this does not account for refunds!
	my $rdate = new ExSite::Time($this->getdata("date"),"sql_timestamp");
	$payments->reset();
	while (my $pay = $payments->next()) {
	    if ($pay->is_paid) {
		my $pdate = new ExSite::Time($pay->getdata("date"),"sql_timestamp");
		if ($rdate->compare($pdate) > 0) {
		    # payment date is after the invoice date
		    # check account balance as of this payment
		    if ($this->account->balance_on_date($pdate) < 0.01) {
			return 1;
		    }
		}
	    }
	}
    }
    return 0;
}

# payment summary - returns a payment summary message

sub payment_summary {
    my $this = shift;
    my $stat = $this->run_handler("receivable_payment_sumamry");
    return $stat if defined $stat;
    my $payments = $this->get_payments();
    if ($payments->count() > 0) {
	my $ptotal = 0;
	my ($ptype,$pdate);
	while (my $pay = $payments->next()) {
	    my $amt = $pay->amount();
	    if ($amt) {
		$ptotal += $amt;
		$pdate = $pay->getdata("date");
		$ptype = $pay->getdata("method");
		# if there is more than 1 payment, we describe the last
	    }
	}
	my $total = $this->total();
	if ($ptotal >= $total) {
	    my $date = new ExSite::Time($pdate,"sql_timestamp");
	    return &substitute($msg{"Paid in full by [[method]] on [[date]]."},
			       { method => $ptype, date => $date->write("date") });
	}
	elsif ($this->is_paid) {
	    return $msg{"This invoice has been paid."};
	}
#	elsif ($ptotal < 0.01) {
#	    return $msg{"This invoice has not been paid yet."};
#	}
	elsif ($ptotal < $total) {
	    my $date = new ExSite::Time($pdate,"sql_timestamp");
	    my $paid = sprintf("%.02f",$ptotal);
	    return &substitute($msg{"Paid $config{report}{currency_char}\[[amount]] of $config{report}{currency_char}\[[total]] by [[method]] on [[date]]."},
			       { method => $ptype, date => $date->write("date"), amount=>$paid, total=>$total });
	}
	else {
	    return $msg{"No payments have been received."};
	}
    }
    return undef;
}

#=== DISPLAY

# show: display the receivable

# options:
# plaintext => if true, generate a plaintext view for email
# date => date format to use, or default date format if set true
# payment => if true, include payment summary
# name => if true, include invoice name (number)
# size => size unit (eg. lbs, kg)
# unitcost => if true, include unitcost column
# summarize_surcharges => if true, simplify invoice by aggregating surcharges
# bilingual => if true, show a bilingual receivable
# account_info => [contact types] (to include account info in the header)
# header => optional header text/html
# footer => optional footer text/html
# item_descriptions => if set false, do not display item descriptions
# allow => preauthorization to view this receivable
# deletions => show deleted items
# objects => show purchased objects

sub show {
    my ($this,%opt) = @_;
    my $stat = $this->run_handler("receivable_show");
    return $stat if defined $stat;
   
    return $this->error("Permission denied") if (!$opt{allow} && !$this->account->allow);
    return $this->error($this->{status}) if (! $this->ok);
    return $this->show_plaintext(%opt) if ($opt{plaintext});

    if (! $this->{data}) { $this->load(); }
    $this->loaditems();
    if (! $this->{data}) {
	my $name = ucfirst $this->name;
	return $this->error("$name does not exist.");
    }
    my $ml = &get_obj("ML");
    my $out = "<!--content(ReceivableHead)-->\n" . $opt{header};
    if ($opt{bilingual}) {
	(tied %msg)->bilingual_mode();
    }

    if ($opt{account_info}) {
	my $addrtype = ((ref $opt{account_info}) =~ /ARRAY/) ?
	    $opt{account_info} : ['shipping','billing'];
	$out .= $ml->table($ml->tr(
				   $ml->td($ml->span($msg{"To:"},{class=>"ReceivableTo"}),{valign=>"top"}).
				   $ml->td($this->account()->billing_address(@$addrtype))
				   ),
			   {class=>"ReceivableAccount"});
    }
    if ($opt{date}) {
	my $fmt = ($opt{date} =~ /[a-z]+/) ? $opt{date} : "date";
	my $t = new ExSite::Time($this->getdata("date"),"sql_timestamp");
	$out .= $ml->p($t->write($fmt),{class=>"ReceivableDate"});
    }
    if ($opt{name}) {
	$out .= $ml->p($this->name,{class=>"ReceivableName"});
    }
    if ($opt{description}) {
	my $descr = $this->showdata("description");
	if ($descr) {
	    $out .= $ml->p($descr,{class=>"ReceivableDescription"});
	}
    }
    if (! defined $opt{item_descriptions}) { $opt{item_descriptions} = 1; }

    my $showunit = 1;
	$showunit = 0 if (defined $opt{unitcost} && $opt{unitcost} == 0);
    my $showsize = $opt{size};
    if (my $items = $this->loaditems()) {
	if (! defined $opt{size}) {
	    # guess whether we need to show sizes on the receivable
	    while (my $item = $items->next()) {
		if ($item->size()) {
		    $showsize = 1;
		    $items->reset;
		    last;
		}
	    }
	}
    }
    else {
	return $this->warn("No items in this receivable.");
    }

    my @summary = $this->summarize_items(%opt);

    my ($table,$total);
    my $table .= 
	$ml->colgroup(undef,{align=>"right"}).
	$ml->colgroup().
	$ml->colgroup(undef,{span=>$showsize ? 3 : 2,align=>"right"});
    my $sizeunit = $opt{size} || "Size";
    my $thead = $ml->thead(
			   $ml->tr(
				   $ml->th($msg{Quantity}).
				   $ml->th($msg{Description}).
				   ($showsize ? $ml->th($msg{$sizeunit}) : "").
				   ($showunit ? $ml->th($msg{"Unit Price"}) : "").
				   $ml->th($msg{Subtotal})
				   )
			   );
    my $tbody;
    foreach my $item (@summary) {
	# item descriptions can optionally be hidden	
	my $itemdescr = $opt{item_descriptions} ?
	    $ml->strong($item->[1]).$ml->br().$item->[2] :
	    $item->[1];
	if ($opt{objects}) {
	    $itemdescr .= $ml->div($item->[6],{class=>"purchasedObject"});
	}
	my @row = ($ml->div($item->[0],{class=>"number"}), $itemdescr);
	if ($showsize) {
	    push @row, $ml->div($item->[4],{class=>"number"});
	}
	if ($showunit) {
	    push @row, $ml->div($item->[3],{class=>"number"});
	}
	push @row, $ml->div($item->[5],{class=>"number"});
	if ($item->[7] eq "deleted") {
	    next if (! $opt{deletions});
	    @row = map { $ml->del($_,{class=>"deleted"}) } @row;
	}
	elsif ($item->[7] eq "hidden") {
	    @row = map { $ml->span($_,{class=>"hidden"}) } @row;
	}
	$tbody .= $ml->tr( \@row );
    }
    $tbody = $ml->tbody($tbody);
    my $tfoot;
    if ($showsize) {
	$tfoot .= $ml->tr( [ undef, $msg{"Total $sizeunit"}, $ml->div($this->size(),{class=>"number"}), undef, undef ] );
    }
    my $foot2 = [ undef, $msg{$opt{total}} || $msg{"TOTAL"} ];
    push @$foot2, undef if ($showunit);
    push @$foot2, undef if ($showsize);
    push @$foot2, $ml->div('$'.$this->total(),{class=>"number total"});
    $tfoot .= $ml->tr( $foot2 );
    $tfoot = $ml->tfoot($tfoot);

# HTML 4.01
#    $out .= $ml->table( $table.$thead.$tfoot.$tbody, {class=>"Receivable",cellpadding=>5});
# HTML 5
    $out .= $ml->table( $table.$thead.$tbody.$tfoot, {class=>"Receivable",cellpadding=>5});
    if ($opt{payment}) {
	my $class = "ReceivablePaymentSummary";
	if (! $this->is_paid) {
	    $class = " ReceivableUnpaid";
	}
	$out .= $ml->p($this->payment_summary(),{class=>$class});
    }

    if ($opt{bilingual}) {
	(tied %msg)->unilingual_mode();
    }
    $out .= $opt{footer} . "<!--content(ReceivableFoot)-->\n";
    return $out;
}

sub show_items_with_size {
    my ($this,%opt) = @_;
    $opt{size} = "Size";
    return $this->show(%opt);
}

sub show_items_without_size {
    my ($this,%opt) = @_;
    $opt{size} = 0;
    return $this->show(%opt);
}

sub show_plaintext {
    my ($this,%opt) = @_;
    my $out;
    if ($opt{bilingual}) {
	(tied %msg)->bilingual_mode();
    }
    my @summary = $this->summarize_items(%opt);
    if (@summary > 0) {
	$out .=  $opt{header};
	if ($opt{date}) {
	    my $fmt = ($opt{date} =~ /\[a-z]+/) ? $opt{date} : "date";
	    my $t = new ExSite::Time($this->getdata("date"),"sql_timestamp");
	    $out .= "\n".$t->write($fmt)."\n";
	}
	if ($opt{name}) {
	    $out .= "\n".$this->name()."\n";
	}
	if (! defined $opt{item_descriptions}) { 
	    $opt{item_descriptions} = 1; 
	}
	my %heading = $opt{short_headings} || $opt{bilingual} ?
	    (qty=>"Qty",desc=>"Item",unitprice=>"Per",subtotal=>"Cost") :
	    (qty=>"Quantity",desc=>"Description",unitprice=>"Unit Price",subtotal=>"Subtotal");
	my %labels = (qty=>$msg{$heading{qty}},desc=>$msg{$heading{desc}},unitprice=>$msg{$heading{unitprice}},subt=>$msg{$heading{subtotal}}); 
	(tied %msg)->nohighlight();
	$out .= "
$labels{qty}    $labels{desc}                    $labels{unitprice}    $labels{subt}
-----------------------------------------------------------------
";
	my $fmt = "%8s    %-30s  %9s    %8.2f\n";
	foreach my $summitem (@summary) {
	    my ($q,$name,$descr,$cost,undef,$subtotal) = @$summitem;
	    $out .= sprintf $fmt, $q, substr($name,0,30), $cost, $subtotal;
	    if ($opt{item_descriptions}) {
		if ($descr) {
		    $descr = &html_to_plaintext($descr);
		    $descr = "            ".$descr;
		    $descr =~ s/\r?\n/            \n/g;
		    $out .= $descr;
		    if ($out !~ /\n$/) { $out .= "\n"; }
		}
	    }
	}
	$out .= "-----------------------------------------------------------------\n";
	$out .= sprintf "$msg{TOTAL}                                                   \$%8.2f\n",$this->total();
	if ($opt{payment}) {
	    $out .= "\n" . $this->payment_summary() . "\n";
	}
	(tied %msg)->restore();	
	$out .= $opt{footer};
    }
    if ($opt{bilingual}) {
	(tied %msg)->unilingual_mode();
    }
    return $out;
}

# show_templated: display the receivable in a template
# the following merge codes are supported:
# header = company masthead or logo
# name = name of the receivable, eg. "Invoice 1234"
# description = receivable description
# seller = seller name
# buyer = complete buyer info, including name and contact info
# buyer_name = just the buyer's account name
# buyer_contact = the buyer's contact info (mailing address)
# buyer_fullcontact = the buyer's contact info (address, phone, email, etc)
# receivable = the receivable details
# payment = payment info/notes
# notes = other notes about the purchase
# footer = general information about payments, refunds, policies, tax #s
# number = the receivable ID
# invoice_number = custom invoice #
# name = combination of number+invoice_number
# date = the purchase date
# uid = user # associated with the account
# acct_code = account.code
# taxno = account's tax exemption number

sub show_templated {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    my $template = $opt{template} || 
	$ml->div(
	    $ml->div("[[header]]",{class=>"ReceivableHeader"}).
	    $ml->h1("[[name]]",{class=>"ReceivableName"}).
	    $ml->div("[[description]]",{class=>"ReceivableDescription"}).
	    $ml->h2("[[seller]]",{class=>"ReceivableSeller"}).
	    $ml->div($ml->div("Sold to:")."[[buyer]]",{class=>"ReceivableBuyer"}).
	    $ml->div("[[date]]",{class=>"ReceivableDate"}).
	    $ml->div("[[receivable]]",{class=>"ReceivableData"}).
	    $ml->div("[[payment]]",{class=>"ReceivablePaymentInfo"}).
	    $ml->div("[[notes]]",{class=>"ReceivableNotes"}).
	    $ml->div("[[footer]]",{class=>"ReceivableFooter"}),
	    {class=>"Receivable"}
	);
    my $receivable_options = $opt{receivable_options};
    $receivable_options->{summarize_surcharges} or $receivable_options->{summarize_surcharges} = 1;
    $opt{receivable} = $opt{plaintext} ? $ml->pre($this->show_plaintext(%$receivable_options)) : $this->show(%$receivable_options); 
    $opt{name} or $opt{name} = $this->name;
    $opt{number} = $this->id;
    $opt{invoice_number} = $this->getdata("invoice");
    $opt{payment} = $this->payment_summary(include_note=>$opt{include_payment_note});
    if (! $opt{date}) {
	my $fmt = ($opt{date} =~ /[a-z]+/) ? $opt{date} : "date";
	my $t = new ExSite::Time($this->getdata("date"),"sql_timestamp");
	$opt{date} = $t->write($opt{date_format} || "date");
    }
    my $acct = $this->account();
    if (! $opt{buyer}) {
	$opt{buyer_name} = $acct->name;
	$opt{buyer_contact} = $acct->billing_address();
	my $contact = $acct->get_contact();
	$opt{buyer_fullcontact} = $contact ? $contact->show() : $opt{buyer_contact};
	$opt{buyer} = $opt{buyer_name} . $ml->br . $opt{buyer_contact};
    }
    if (! $opt{seller}) {
	if ($acct && $acct->getdata("section_id")) {
	    my $section = $share{DB}->fetch("section",$acct->getdata("section_id"));
	    $opt{seller} = $section->{title};
	}
	else {
	    $opt{seller} = $config{site}{name};
	}
    }
    $opt{uid} or $opt{uid} = $acct->getdata("uid");
    $opt{acct_code} or $opt{acct_code} = $acct->getdata("code");
    $opt{taxno} or $opt{taxno} = $acct->showdata("taxcode");
    return &substitute($template,\%opt);
}

# build a matrix of items
# returns:
# ( [ quantity, name, description, unitcost, size, subtotal, status ], ... )
#
# options:
# summarize_surcharges => summarize rather than itemize surcharges
# summarize_items => group items with similar visible descriptors
# unitcost => 1|0

sub summarize_items {
    my ($this,%opt) = @_;
    my $summarize_surcharges = &preference("Finance.always_summarize_surcharges") || 
    	$opt{summarize_surcharges};
    my $summarize_items = &preference("Finance.summarize_items") || 
    	$opt{summarize_items};
    my (@summary, @surcharge, @items);
    if (my $items = $this->loaditems()) {
	my $ml = &get_obj("ML");
	while (my $item = $items->next()) {
	    if ($summarize_surcharges && $item->is_surcharge()) {
		push @surcharge, $item;
		next;
	    }
	    if ($summarize_items && ! $item->is_surcharge()) {
		push @items, $item;
		next;
	    }
	    my $cost = $item->showdata("cost");
	    if ($cost =~ /^\$?0\.00$/ && $opt{zero_cost}) {
		$cost = $opt{zero_cost};
	    }
	    my $subtotal = $item->subtotal();
	    if ($subtotal == 0.00 && $opt{zero_cost}) {
		$subtotal = $opt{zero_cost};
	    }
	    my $obj = $item->purchased_object;
	    my $objname;
	    if ($obj) {
		$objname = $obj->name;
		my $objid = $obj->id;
		if ($objname !~ /$objid/) {
		    my $type = $obj->getdata("type");
		    if ($type eq "content") { 
			$type = $obj->subtype();
		    }
		    $objname .= " ($type $objid)";
		}
	    }
	    push @summary, [
			    $item->quantity,
			    $item->showdata("item"),
			    $item->showdata("description"),
			    $cost,
			    $item->size(),
			    $subtotal,
		            $objname,
		            $item->getdata("status"),
			    ];
	}
	if ($summarize_items) {
	    # group similar items
	    # items are similar if visible descriptors (item, description, 
	    # size, cost) are the same
	    my (%item_summary,@item_key);
	    foreach my $item (@items) {
		my $key = &array2text($item->name,$item->getdata("description"),$item->getdata("size"),$item->getdata("cost"));
		if (! exists $item_summary{$key}) { 
		    push @item_key, $key; 
		    $item_summary{$key}{name} = $item->name;
		    $item_summary{$key}{description} = $item->getdata("description");
		    $item_summary{$key}{cost} = $item->unitprice();
		}
		$item_summary{$key}{quantity} += $item->quantity();
		$item_summary{$key}{subtotal} += $item->subtotal();
		$item_summary{$key}{size} += $item->size();
	    }
	    foreach my $key (@item_key) {
		my $subtotal = sprintf "%.02f",$item_summary{$key}{subtotal};
		push @summary, [
		    $item_summary{$key}{quantity},
		    $item_summary{$key}{name},
		    $item_summary{$key}{description},
		    $item_summary{$key}{cost},
		    $item_summary{$key}{size},
		    $subtotal,
		];
	    }
	}
	if ($summarize_surcharges) {
	    # report surcharge subtotals, not each individual surcharge
	    my %surcharge_subtotal;
	    foreach my $scitem (@surcharge) {
		$surcharge_subtotal{$scitem->getdata("item")} += $scitem->subtotal();
	    }
	    # now replace the full list of surcharges with our summary list
	    foreach my $item (keys %surcharge_subtotal) {
		push @summary, [
				"",
				$item,
				"",
				"",
				"",
				sprintf("%.02f",$surcharge_subtotal{$item}),
				];
	    }
	}
    }
    return @summary;
}

#=== DB

# load record : can pass an ID or a datahash

sub loaditems {
    my $this = shift;
    if (! defined $this->{items} && $this->ok) {
	$this->{items} = new ExSite::ObjectList(type=>"receivable_item");
	$this->{items}->load({receivable_id => $this->id},"receivable_item_id");
    }
    elsif ($this->{items}) {
	# reset iterator
	$this->{items}->reset();
    }
    return $this->{items};
}

# clear_items : remove our item list to force it to be reloaded

sub clear_items {
    my ($this) = @_;
    delete $this->{items};
}

# count_items : count the items of a certain surcharge; if surcharge_id
#               in undef, count all items; if surcharge_id is defined but
#               0, count all non-surcharge items.
#               Counting includes hidden items, but excludes deleted items.

sub count_items {
    my ($this,$surcharge_id) = @_;
    my $count;
    my $items = $this->loaditems();
    $items->reset;
    if (defined $surcharge_id) {
	while (my $item = $items->next()) {
	    $count++ if ($item->is_active && $item->getdata("surcharge_id") == $surcharge_id);
	}
    }
    else {
	while (my $item = $items->next()) {
	    $count++ if ($item->is_active);
	}
    }
    return $count;
}

### allow deletes?

sub delete {
    my $this = shift;
    if ($this->getdata("status") eq "inactive") {
	return $this->SUPER::delete();
    }
    $this->error("Sorry, you cannot delete active invoices.");
    return 0;
}

#=== Amending the receivable
# $surcharge flag also adds the surcharges for this item

sub add_item {
    my ($this,$data,$surcharge) = @_;
    if ($this->loaded) {
	$data->{status} or $data->{status} = "active";
	$data->{uid} or $data->{uid} = $this->DB->my_uid;
	$data->{receivable_id} = $this->id;
	my $item = new Modules::Finance::ReceivableItem(data=>$data);
	if ($this->getdata("status") ne "inactive") {
	    #
	    # We are amending an active receivable, so we should note the
	    # amendements in our descriptions.  An inactive receivable is
	    # preliminary by nature, and can be amended freely.
	    #
	    my $descr = $item->getdata("description");
	    my $time = scalar localtime;
	    $descr = $descr ? $descr."\nAmended $time" : "Amended $time";
	    $item->setdata("description",$descr);
	}
	my $item_id = $item->insert();
	if ($item_id && $surcharge) { $this->add_surcharge($item); }
	$this->clear_items();
	return $item;
    }
    else {
	$this->error("cannot add items to an unsaved receivable");
	return undef;
    }
}

# add_surcharge : adds surcharges for a single item
# returns number of surcharges added
# $code is a 'coupon code' to access password-protected surcharges

sub add_surcharge {
    my ($this,$item,$code) = @_;
    my $stat = $this->run_handler("add_surcharge",$item);
    return $stat if (defined $stat);
    # find the surcharges that apply to this item
    my $surcharges = $this->get_surcharges();
    # get contact info
    my $contact = $this->account()->get_contact();
    my $n_sc = 0;
    while (my $sc = $surcharges->next()) {
	if ($sc->allow($contact,$item,$code)) {
	    # create a new receivable item, and populate with surcharge data
	    my $sccost = $sc->cost($item->quantity,
				   $item->size(),
				   $item->subtotal(),
				   $this);
	    next if (abs($sccost) < 0.01);  # no charge
	    my $scitem = new Modules::Finance::ReceivableItem();
	    $scitem->setdata("receivable_id",$this->id);
	    $scitem->setdata("parent",$item->id);
	    $scitem->setdata("uid",$this->DB->my_uid || 0);
	    $scitem->setdata("item",$sc->name());
	    $scitem->setdata("description",$sc->description($item));
	    $scitem->setdata("cost",$sccost);
	    $scitem->setdata("acctcode_id",$sc->getdata("treat_as"));
	    $scitem->setdata("acctcode2",$sc->getdata("surcharge_id"));
	    $scitem->setdata("surcharge_id",$sc->id);
	    # add the surcharge
	    $scitem->insert();
	    # apply surcharges on this surcharge (eg. tax on S&H)
	    # WARNING: recursion - make sure you have no surcharge loops
	    $this->add_surcharge($scitem);
	    $n_sc++;
	}
    }
    $this->clear_items();
    return $n_sc;
}

# add_surcharges : adds surcharges for all items
# returns number of surcharges added
# $code is a 'coupon code' to access password-protected surcharges

sub add_surcharges {
    my ($this,$code) = @_;
    my $stat = $this->run_handler("add_surcharges");
    return if (defined $stat);
    my $n_sc = 0;
    if (my $items = $this->loaditems()) {
	while (my $item = $items->next()) {
	    $n_sc += $this->add_surcharge($item,$code);
	}
    }
    $this->clear_items();
    return $n_sc;
}

# remove_surcharges : removes all surcharges to get back to a fresh state

sub remove_surcharges {
    my ($this) = @_;
    if (my $items = $this->loaditems()) {
	while (my $item = $items->next()) {
	    if ($item->is_surcharge()) {
		$item->force_delete();
	    }
	}
    }
    delete $this->{surcharges};
    $this->clear_items();
}

# has_surcharges : return 1 if there are surcharges are on the receivable

sub has_surcharges {
    my ($this) = @_;
    if (my $items = $this->loaditems()) {
	while (my $item = $items->next()) {
	    if ($item->is_surcharge()) {
		return 1;
	    }
	}
    }
    return undef;
}

# log_surcharge : record that a surcharge has been applied so that per-order
#                 surcharges are not double-counted

sub log_surcharge {
    my ($this,$sc) = @_;
    $this->{surcharges} or $this->{surcharges} = {};
    if ($this->{surcharges}{$sc}) {
	# already logged
	return 0;
    }
    else {
	$this->{surcharges}{$sc} = 1;
	return 1;
    }
}

# get a list of all surcharges that may be relevant to this invoice

sub get_surcharges {
    my $this = shift;
    my $db = $share{DB};
    my @all_sc = $db->fetch_all("surcharge");
    my @sc;
    my $section = $db->this_site;
    my $sid = $section ? $section->{section_id} : 0;
    foreach my $sc (@all_sc) {
	my $surcharge = new Modules::Finance::Surcharge(data=>$sc);
	if ($surcharge->is_valid($sid)) {
	    push @sc, $sc;
	}
    }
    my $surcharges = new ExSite::ObjectList(type=>"surcharge");
    $surcharges->setlist(@sc);
    return $surcharges;
}

# remove_items : removes all items, to empty out the receivable

sub remove_items {
    my ($this) = @_;
    if (my $items = $this->loaditems()) {
	while (my $item = $items->next()) {
	    $item->delete();
	}
    }
    $this->clear_items();
}

1;

