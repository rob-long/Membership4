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

package Modules::Finance::Account;

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Object;
use Modules::ID::Contact;
use Modules::Finance::Receivable;
use Modules::Finance::Payment;

use vars qw(@ISA);
@ISA = qw(ExSite::Object);

sub setup {
    my ($this,%opt) = @_;
    $this->SUPER::setup(%opt);
    if ($opt{my_account}) {
	$this->setup_my_account;
    }
    if ($opt{uid}) {
	$this->setup_user_account($opt{uid});
    }
}

sub my_type { return "account"; }

sub name {
    my $this = shift;
    my $code = $this->getdata("code");
    return $code ? 
	$this->getdata("name")." [$code]" :
	$this->getdata("name");
}

sub get_children {
    my ($this,@child) = @_;
    if (! exists $this->{children}) {
	$this->{children} = $this->SUPER::get_children(@child);
    }
    return wantarray ? %{$this->{children}} : $this->{children};
}

sub section_id {
    my $this = shift;
    if ($this->loaded()) {
	my $data = $this->get();
	return $data->{section_id} if $data->{section_id};
	if ($data->{uid}) {
	    my $user = new ExSite::User(id=>$data->{uid});
	    return $user->getdata("section_id");
	}
    }
    return undef;
}

# setup_my_account : find account of current user

sub setup_my_account {
    my $this = shift;

    my $inv_id = $session{invoice} || $session{invoice_nocart};
    if ($inv_id) {
	# user has a shopping cart or other invoice going - use that
	my $r = new Modules::Finance::Receivable(id=>$inv_id);
	$this->setup(id=>$r->getdata("account_id"));
	return $this;
    }

    my $acct_id = $session{account};
    if ($acct_id) {
	# an account was setup for the user without an invoice on it
	$this->setup(id=>$acct_id);
	return $this;
    }

    if ($this->setup_user_account()) {
	# user has an account attached to their UID - use that
	return $this;
    }

    return undef;
}

# setup_user_account : find account of a user

sub setup_user_account {
    my ($this,$uid) = @_;

    $uid or $uid = $share{DB}->my_uid;
    if ($uid) {
	my $section = $share{DB}->this_site();
	my @acct = $share{DB}->fetch_match("account",{uid=>$uid,section_id=>$section->{content_id}},"account_id");
	if (!scalar @acct) {
	    @acct = $share{DB}->fetch_child("account","user",$uid,"account_id");
	}
	if (@acct > 0) {
	    # user has an account on the system
	    $this->setup(data=>$acct[-1]);
	    return $this;
	}
    }
    return undef;
}

# setup_account : find or make an account for the current visitor

sub setup_account {
    my ($this,$name) = @_;
    if ($share{Page}) {
	# public-site registration - look for existing account
	if ($this->setup_my_account()) {
	    # user has an account, return it
	    ### admin override on public pages???
	    return $this;
	}
	else {
	    my $uid = $share{DB}->my_uid;
	    return $uid ?
		$this->setup_new_account($uid,$name) :
		$this->setup_anonymous_account($name);
	}
    }
    else {
	# admin-side registration
	if ($session{account}) {
	    # already a recommended account
	    if ($this->{id} != $session{account}) {
		delete $this->{data};
		$this->{id} = $session{account};
	    }
	    return $this;
	}
	else {
	    return $this->setup_anonymous_account($name);
	}
    }
    return undef;
}

# create new accounts

sub setup_new_account {
    my ($this,$uid,$name) = @_;
    $uid or $uid = $share{DB}->my_uid;
    my $site = $share{DB}->this_site;
    $this->setdata("section_id",$site ? $site->{content_id} : 0);
    $this->setdata("name",$name || $share{DB}->user_name($uid));
    $this->setdata("uid",$uid);
    if ($this->force_save) {
	$session{account} = $this->id;
	return $this;
    }
    return undef;
}

sub setup_anonymous_account {
    my ($this,$name) = @_;
    $name or $name = 
	$config{Finance}{anonymous_account_name} || 
	"Internet Shopper";
    my $site = $share{DB}->this_site;
    $this->setdata("section_id",$site ? $site->{content_id} : 0);
    $this->setdata("name",$name);
    if ($this->force_save) {
	$session{account} = $this->id;
	return $this;
    }
    return undef;
}

# access control

sub allow {
    my $this = shift;
    my $level = $share{DB}->level();

    # admins get special privs
    if ($level > 2) {
	# system administrators can see all
	return 1;
    }
    elsif ($level == 2) {
	# site managers can only see accounts on their own sections
	my $section = $share{DB}->this_site();
	my $acct_section = $this->getdata("section_id");
	return 1 if ($acct_section == $section->{content_id});
    }

    # regular users can manage their own accounts only
    return $this->is_my_account();
}

sub is_my_account {
    my $this = shift;
    if ($this->defined) {
	my $uid = $share{DB}->my_uid;
	if ($uid) {
	    return ($this->getdata("uid") == $uid);
	}
	elsif ($session{account}) {
	    return ($session{account} == $this->id);
	}
	elsif ($session{invoice}) {
	    my $inv = new Modules::Finance::Receivable(id=>$session{invoice});
	    return ($inv->getdata("account_id") == $this->id);
	}
	elsif ($session{last_invoice}) {
	    my $inv = new Modules::Finance::Receivable(id=>$session{last_invoice});
	    return ($inv->getdata("account_id") == $this->id);
	}
    }
    return undef;
}

# get contact returns the "best" contact record we have for the account
# If there are more than 1 contact, we prefer the types that are passed,
# in the order they were passed.

sub get_contact {
    my ($this,@type) = @_;
    if (@type == 0) {
	if (! exists $config{Pay}) { &ExSite::Module::read_conf("Pay"); }
	my $main_contact_type = $config{Account}{main_contact_type} || 
		&preference("Pay.primary_contact");
	@type = split /,\s*/,$main_contact_type;
    }
    if ($this->loaded()) {
	$this->get_children();
	if ($this->{children}{contact}) {
	    my $clist = $this->{children}{contact};
		# newest record is preferred
		$clist->reverse;
	    my $count = $clist->count;
	    if ($count > 1) {
		foreach my $type (@type) {
		    while ($clist->next()) {
			if ($clist->getdata("type") eq $type) {
			    return $clist->newobj();
			}
		    }
		}
	    }
	    if ($count > 0) {
		# nothing found under the preferred types; 
		# just take the first one
		$clist->select(0);
		return $clist->newobj();
	    }
	}
    }
    # nothing found
    return undef;
}

# get user object attached to the account

sub get_user {
    my ($this) = @_;
    if (my $id = $this->getdata("uid")) {
	return &get_obj("user",$id);
    }
    return undef;
}

# show only the main (billing) address - other types can be passed if you prefer
sub billing_address {
    my ($this,@type) = @_;
    if (@type == 0) { @type = ("billing"); }
    my $contact = $this->get_contact(@type);
    my $out;
    my $ml = &get_obj("ML");
    if ($contact) {
	#$out = $this->name().$ml->br();
	$out .= $contact->show_address();
    }
    else {
	$out = "No contact information.";
    }
    return $ml->div($out,{class=>"account_address"});
}

sub show {
    my ($this,%opt) = @_;
    if ($this->ok) {
	if (! $this->{data}) { $this->load(); }
	if (! $this->{data}) {
	    my $name = ucfirst $this->name;
	    return $this->error("$name does not exist.");
	}

	if ($this->allow()) {
	    my $ml = &get_obj("ML");
	    my $out = $ml->h3($this->name);
	    my $code = $this->{data}{code};
	    if ($code) { 
		$out .= $ml->p($code);
	    }
	    $out .= $this->billing_address();
	    $out .= $this->show_statement(%opt);
	    return $out;
	}
	return $this->error("Permission denied");
    }
    return $this->error($this->{status});
}

# show all contacts
sub get_contacts {
    my $this = shift;
    my %children = $this->get_children();
    return $children{contact};
}

sub show_contacts {
    my ($this,%opt) = @_;
    if ($opt{plaintext}) {
	return $this->show_contacts_plaintext(%opt);
    }
    my $ml = &get_obj("ML");
    my $contacts = $this->get_children()->{contact};
    if (ref $contacts && $contacts->count > 0) {
	my $layout = $opt{contact_layout};
	if ($layout eq "table") {
	    my $contact_info;
	    while (my $c = $contacts->next) {
		my $type = $c->getdata("type");
		my $typehdr = $type ? $ml->strong(ucfirst $type." address:").$ml->br : "";
		$contact_info .= $ml->td($typehdr . $c->show, {valign=>"top"});
	    }
	    return $ml->table(
			      $ml->tr($contact_info),
			      );
	}
	elsif ($layout eq "tabbox") {
	    my (@type,@contact);
	    while (my $c = $contacts->next) {
		push @type, ucfirst $c->getdata("type");
		push @contact, $c->show();
	    }
	    return &ExSite::HTML::DynTabBox(
					    tabs=>\@type,
					    panes=>\@contact,
					    );
	}
	else {
	    my $out;
	    my $nc = $contacts->count;
	    while (my $c = $contacts->next) { 
		# include type only if more than one
		my $name = $nc > 1 ?
		    ucfirst $c->getdata("type") . ":" :
		    undef;
		$out .= $c->show(title=>$name); 
	    }
	    return $out;
	}
    }
    else {
	return $ml->p("No contact info available.");
    }
}

sub show_contacts_plaintext {
    my $this = shift;
    my %children = $this->get_children();
    my @contact = $children{contact} ? $children{contact}->getlist() : ();
    my $out;
    if (@contact == 1) {
	my $cont = new Modules::ID::Contact(data=>$contact[0]);
	$out .= $cont->show(plaintext=>1);
    }
    elsif (@contact > 0) {
	# more than 1 contact; include type info
	foreach my $c (@contact) {
	    my $cont = new Modules::ID::Contact(data=>$c);
	    $out .= ucfirst $cont->getdata("type")."\n";
	    $out .= $cont->show(plaintext=>1);
	}
	$out .= "\n";
    }
    else {
	$out = "No contact info available.";
    }
    return $out;
}

sub show_receivables {
    my $this = shift;
    my $ml = &get_obj("ML");
    my %children = $this->get_children();
    my @recv = $children{receivable} ? $children{receivable}->getlist() : ();
    if (@recv > 0) {
	my $rept = new ExSite::ReportBuilder(title=>"Receivables",
					     headers=>["ID","Date","Amount","Status"]);
	my $total = 0;
	foreach my $r (@recv) {
	    my $receivable = new Modules::Finance::Receivable(data=>$r);
	    my $rtot = $receivable->total();
	    $total += $receivable->getdata("type") eq "payable" ? -$rtot : $rtot;
	    $rept->push(
			$receivable->name(),
			$receivable->showdata("date"),
			$receivable->show_total(),
			$receivable->status(),
			);
	}
	$this->{total}{receivable} = $total;
	$rept->tools("Total: \$$total");
	return $rept->make();
    }
    else {
	return $ml->p("No receivables on this account.");
    }

}

sub show_payments {
    my $this = shift;
    my $ml = &get_obj("ML");
    my %children = $this->get_children();
    my @pay = $children{payment} ? $children{payment}->getlist() : ();
    if (@pay > 0) {
	my $rept = new ExSite::ReportBuilder(title=>"Payments",
					     headers=>["Date","Method","Amount","Note"]);
	my $total = 0;
	foreach my $p (@pay) {
	    my $pmt = new Modules::Finance::Payment(data=>$p);
	    my $amt = $pmt->amount,
	    my $status = $pmt->getdata("status");
	    my $note = $pmt->showdata("note");
	    if ($status ne "paid") {
		$note = uc($status)." (amount: ".$pmt->getdata("amount").") $note";
	    }
	    $total += $amt;
	    $rept->push(
			$pmt->showdata("date"),
			$pmt->showdata("method"),
			$amt,
			$note,
			);
	}
	$rept->tools("Total: \$$total");
	$this->{total}{payment} = $total;
	return $rept->make();
    }
    else {
	return $ml->p("No receivables on this account.");
    }
}

sub balance {
    my $this = shift;
    my $total;
    my %children = $this->get_children();
    my $recv = $children{receivable};
    if ($recv) {
	$recv->reset();
	while (my $r = $recv->next()) {
	    if ($r->is_active()) {
		my $rtot = $r->total();
		$total += $r->is_receivable ? $rtot : -$rtot;
	    }
	}
    }
    my $pay = $children{payment};
    if ($pay) {
	$pay->reset();
	while (my $p = $pay->next()) {
	    if ($p->is_paid) {
		$total -= $p->amount();
	    }
	}
    }
    return sprintf("%.02f",$total);
}

sub balance_on_date {
    my ($this,$date) = @_;
    return undef if (ref $date !~ /Time/); # date must be a Time object
    my $total;
    my %children = $this->get_children();
    my $recv = $children{receivable};
    if ($recv) {
	$recv->reset();
	while (my $r = $recv->next()) {
	    if ($r->is_active()) {
		my $rdate = new ExSite::Time($r->getdata("date"),"sql_timestamp");
		if ($date->compare($rdate) <= 0) {
		    my $rtot = $r->total();
		    $total += $r->is_receivable ? $rtot : -$rtot;
		}
	    }
	}
    }
    my $pay = $children{payment};
    if ($pay) {
	$pay->reset();
	while (my $p = $pay->next()) {
	    if ($p->is_paid) {
		my $pdate = new ExSite::Time($p->getdata("date"),"sql_timestamp");
		if ($date->compare($pdate) <= 0) {
		    $total -= $p->amount();
		}
	    }
	}
    }
    return sprintf("%.02f",$total);
}

sub show_balance {
    my $this = shift;
    if (! $this->allow()) {
	return $this->error("Permission denied.");
    }
    my $balance = $this->balance();
    my $due = $balance > 0 ? "\$$balance" : "<span class='error'>(\$$balance)</span>";
    return &ExSite::HTML::BasicBox(title=>$msg{"Balance Due"},
				   pane=>"<h1 style='text-align:center'>$due</h1>",
				   width=>"150px");
}

# from, to - statement for that time window only
# year - statement for that year only
# month - statement for that month only
# days - statement since that many days ago

sub show_statement {
    my ($this,%opt) = @_;
    if (! $this->allow()) {
	return $this->error("Permission denied.");
    }
    my $ml = &get_obj("ML");
    my %children = $this->get_children();

    # get time window of statement
    my ($from,$to,$statement_dates);
    if ($opt{year}) {
	$from = $opt{year}."-01-01";
	$to = ($opt{year}+1)."-01-01";
	$statement_dates = $opt{year};
    }
    elsif ($opt{month}) {
	$from = $opt{month}."-01";
	my $t = new ExSite::Time($from,"sql_date");
	$statement_dates = $t->write("%MMMM, %YYYY");
	$t->add_approximate(1,"month");
	$to = $t->write("sql_date");
    }
    elsif ($opt{days}) {
	my $t = new ExSite::Time();
	$t->add(- $opt{days},"days");
	$from = $t->write("sql_date");
	$statement_dates = "last $opt{days} days";
    }
    elsif ($opt{from} || $opt{to}) {
	$from = $opt{from};
	$to = $opt{to};
	$statement_dates = "$from - $to";
    }

    # get all items on the statement

    my @item;
    my @recv = $children{receivable} ? $children{receivable}->getlist() : ();
    foreach my $r (@recv) {
	$r->{class} = "Modules::Finance::Receivable";
	$r->{Time} = new ExSite::Time($r->{date},"sql_timestamp");
	push @item, $r;
    }
    my @pay = $children{payment} ? $children{payment}->getlist() : ();
    foreach my $p (@pay) {
	$p->{class} = "Modules::Finance::Payment";
	$p->{Time} = new ExSite::Time($p->{date},"sql_timestamp");
	push @item, $p;
    }

    if (@item > 0) {

	# order the items

	my @sorted_item = sort { $a->{Time} - $b->{Time} } @item;
	my $title = $statement_dates ? 
	    &substitute($msg{"Statement of Account: [[date]]"},{date=>$statement_dates}) :
	    $msg{"Statement of Account"};
	my $rept = new ExSite::ReportBuilder(title=>$title,
					     headers=>[$msg{"Date"},$msg{"Description"},$msg{"Credit"},$msg{"Debit"}],
					     show_data_if_nodata=>0);
	my $total_cr = 0;
	my $total_db = 0;
	my $first = 1;
	my $start_balance;
	foreach my $item (@sorted_item) {
	    my $t = $item->{Time};
	    my $class = $item->{class};
	    delete $item->{Time};
	    delete $item->{class};
	    my $obj = eval "new $class(data=>\$item)";
	    my ($date,$descr,$debit,$credit);
	    $date = $t->write("date");
	    my $iso_date = $t->write("iso_date");
	    if ($class =~ /Payment/) {
		my $method = $msg{$obj->getdata("method")};
		$descr = $method ? "$msg{Payment} ($method)" : $msg{"Payment"};
		my $note = $obj->getdata("note");
		$descr .= "; $note" if ($note);
		if ($opt{payment_uri}) {
		    $opt{payment_uri}->query(payment=>$obj->id,inv=>undef);
		    $descr = $ml->a($descr,{href=>$opt{payment_uri}->write()});
		}
		#$descr .= "; ".$obj->getdata("status");
		#my $amount = $obj->amount(); # only shows actual money received
		my $amount = $obj->getdata("amount");

                my $pay_status = $obj->is_paid();
                if ($pay_status) {
                    # good or possibly good payment
                    if ($pay_status < 0) {
                        # unconfirmed payment
                        $descr .= 
                            "; ". uc($obj->showdata("status")).
                            "; amount: $amount";
                        $amount = undef;
                    }
                }
                else {
                    # bad payment
                    next if (! $opt{alltransactions});
                    $descr .= 
                        "; ". uc $obj->showdata("status").
                        "; amount: $amount";
                    $amount = undef;
                }

		if ($amount >= 0) {
		    $credit = $amount;
		}
		else {
		    # refund?
		    $debit = -$amount;
		}
	    }
	    else {
		# receivable
		$descr = $obj->description();
		if ($opt{receivable_uri}) {
		    $opt{receivable_uri}->query(inv=>$obj->id,payment=>undef);
		    $descr = $ml->a($descr,{href=>$opt{receivable_uri}->write()});
		}
		#$descr .= "; ".$obj->getdata("status");
		my $amount = $obj->total();

		# skip invalid line items
		next if (! $amount);
		next if ($amount == 0.00);

		if ($opt{alltransactions}) {
		    if (! $obj->is_active()) {
			# show inactive receivables
			$descr .= 
			    "; ". uc($obj->showdata("status")).
			    "; amount: $amount";
			$amount = undef;
		    }
		}
		else {
		    next if (! $obj->is_active());
		}

		# adjust amount
		if ($obj->getdata("type") eq "payable") {
		    # this is owed, not owning
		    $amount = -$amount;
		}
		if ($amount >= 0) {
		    $debit = $amount;
		}
		else {
		    # payable
		    $credit = -$amount;
		}
	    }
	    $start_balance = $total_db - $total_cr;
	    last if ($to && $iso_date gt $to);
	    $total_cr += $credit;
	    $total_db += $debit;
	    next if ($from && $iso_date lt $from);
	    my $cr_money = sprintf("%.02f",$credit);
	    my $db_money = sprintf("%.02f",$debit);
	    if ($first) {
		if ($start_balance) {
		    my $bal_money = sprintf("%.02f",abs($start_balance));
		    $rept->push(undef,"Starting balance", ($start_balance < 0) ? $bal_money : "", ($start_balance > 0) ? $bal_money : "");
		}
		$first = 0;
	    }
	    $rept->push($date,$descr,$cr_money != 0.00 ? $cr_money : "",$db_money != 0.00 ? $db_money : "");
	}
	if ($first) {
	    if ($start_balance) {
		my $bal_money = sprintf("%.02f",abs($start_balance));
		$rept->push(undef,"Starting balance", ($start_balance < 0) ? $bal_money : "", ($start_balance > 0) ? $bal_money : "");
	    }
	    $first = 0;
	}
	my $balance = $total_db - $total_cr;
	my $cr_money = sprintf("%.02f",$total_cr);
	my $db_money = sprintf("%.02f",$total_db);
	my $bal_money = sprintf("%.02f",$balance);
	my $br = $ml->br;
	$rept->footpush(undef,$msg{"Total Credits"},$cr_money,undef);
	$rept->footpush(undef,$msg{"Total Debits"},undef,$db_money);
	$rept->footpush(undef,$msg{"BALANCE"},undef,$bal_money);
	$rept->set("width","100%");
	$rept->set("cclass",[undef,undef,"num","num"]);
	if ($opt{tools}) {
	    return $rept->make() . $ml->div($opt{tools},{class=>"AccountStatementTools"});
	}
	else {
	    return $rept->make();
	}
    }
    else {
	return $ml->p($msg{"No receivables or payments found on this account."});
    }
}

# stats: summary info about account and history

sub stats {
    my ($this,%opt) = @_;
    my %stat;
    if (! $this->allow()) {
	return undef;
    }
    $stat{id} = $this->id;
    $stat{name} = $this->name;
    $stat{code} = $this->getdata("code");
    my %children = $this->get_children();

    # get all items on the statement

    my @item;
    my @recv = $children{receivable} ? $children{receivable}->getlist() : ();
    foreach my $r (@recv) {
	$r->{class} = "Modules::Finance::Receivable";
	$r->{Time} = new ExSite::Time($r->{date},"sql_timestamp");
	push @item, $r;
    }
    my @pay = $children{payment} ? $children{payment}->getlist() : ();
    foreach my $p (@pay) {
	$p->{class} = "Modules::Finance::Payment";
	$p->{Time} = new ExSite::Time($p->{date},"sql_timestamp");
	push @item, $p;
    }

    if (@item > 0) {
	# order the items
	my @sorted_item = sort { $a->{Time} - $b->{Time} } @item;
	$stat{first} = $sorted_item[0]{Time}->write("iso_date");
	$stat{last} = $sorted_item[-1]{Time}->write("iso_date");
	foreach my $item (@sorted_item) {
	    my $t = $item->{Time};
	    my $class = $item->{class};
	    delete $item->{Time};
	    delete $item->{class};
	    my $obj = eval "new $class(data=>\$item)";
	    my ($date,$descr,$debit,$credit);
	    $date = $t->write("date");
	    my $iso_date = $t->write("iso_date");
	    if ($class =~ /Payment/) {
		my $method = $msg{$obj->getdata("method")};
		my $amount = $obj->getdata("amount");
                my $pay_status = $obj->is_paid();
                if ($pay_status) {
                    # good or possibly good payment
                    if ($pay_status < 0) {
                        # unconfirmed payment
			$stat{unconfirmed_payments}++;
                    }
		    else {
			$stat{payments}++;
		    }
                }
                else {
		    $stat{bad_payments}++;
                }
		if ($obj->getdata("receivable_id")) {
		    $stat{invoice_payments}++;
		}
		else {
		    $stat{account_payments}++;
		}

		if ($amount >= 0) {
		    $stat{credits} += $amount;
		    $stat{last_payment} = $amount;
		}
		else {
		    # refund?
		    $stat{debits} += -$amount;
		}
	    }
	    else {
		# receivable
		my $amount = $obj->total();

		# skip invalid line items
		next if (! $amount);
		next if ($amount == 0.00);

		if (! $obj->is_active()) {
		    $stat{inactive_receivables}++;
		    next;
		}
		$stat{receivables}++;
		$stat{last_invoice_total} = $amount;

		# adjust amount
		if ($obj->getdata("type") eq "payable") {
		    # this is owed, not owning
		    $amount = -$amount;
		}
		if ($amount >= 0) {
		    $stat{debits} += $amount;
		}
		else {
		    # payable
		    $stat{credits} += $amount;
		}
	    }
	}
	$stat{balance} = $stat{credits} - $stat{debits};
    }
    return wantarray ? %stat : \%stat;
}

# get email address for account
sub email {
    my ($this,$ctype) = @_;
    my %children = $this->get_children();
    my @contact = $children{contact} ? $children{contact}->getlist() : ();
    if (@contact > 0) {
	my %c = &keywise("type",\@contact);
	my $preferred_contact = $c{$ctype} || $c{billing} || $c{mailing} || $c{shipping} || $contact[0];
	if (ref $preferred_contact eq "HASH" && $preferred_contact->{email}) {
	    return $preferred_contact->{email};
	}
    }
    # no email in contacts!  See if there is any info under the member record
    my $uid = $this->getdata("uid");
    if ($uid) {
	my $user = new ExSite::User(id=>$uid);
	return $user->getdata($config{auth}{user_email_column});
    }
    return undef;
}

sub add_payment {
    my ($this,$pay) = @_;
    if ($this->exists()) {
	if (! $pay->{date}) {
	    # force payment timestamp to be auto-set by mysql
	    delete $pay->{date};
	}
	if (! $pay->{status}) {
	    $pay->{status} = "paid";
	}
	$pay->{account_id} = $this->id();
	my $p = new Modules::Finance::Payment(data=>$pay);
	### force_save!!! be sure to validate your own inputs
	return $p->force_save;
    }
    return undef;
}

sub validate {
    my $this = shift;
    if (! $this->{data}{uid}) {
	# anonymous buyers are allowed to edit their account name
	if ($session{invoice}) {
	    # check that they are currently in this account
	    # look in the session invoice
	    my $r = new Modules::Finance::Receivable(id=>$session{invoice});
	    # okay if the session invoice belongs to this account
	    if ($r->account->id() == $this->id) {
		if (! $this->{data}{name}) {
		    return ("Please provide a name.");
		}
		return ();
	    }
	}
    }
    # default rules
    return $this->SUPER::validate(@_);
}

#--- one-step receivable creation

sub add_receivable {
    my ($this,$receivable,@item) = @_;
    (ref $receivable) eq "HASH" or $receivable = {};
    $receivable->{account_id} = $this->id;
    $receivable->{type} or $receivable->{type} = "receivable";
    if (! $receivable->{date}) {
	my $date = new ExSite::Time;
	$receivable->{date} = $date->write("sql_datetime");
    }
    $receivable->{status} or $receivable->{status} = "inactive";
    delete $receivable->{receivable_id};

    my $errcnt = &AtError();
    my $r = new Modules::Finance::Receivable(data=>$receivable);
    $r->set("dirty",1);
    if ($r->save()) {
	foreach my $item (@item) {
	    if ((ref $item) eq "HASH") {
		$item->{receivable_id} = $r->id;
		delete $item->{receivable_item_id};
		my $ri = new Modules::Finance::ReceivableItem(data=>$item);
		if (! $ri->save()) {
		    $this->error("failed to add item '$item->{description}' to receivable");
		}
	    }
	    else {
		$this->error("invalid receivable item");
	    }
	}
	if (! &AtError($errcnt)) {
	    if ($receivable->{status} eq "inactive") {
		$r->activate();
	    }
	}
    }
    return $r->id;
}

1;

