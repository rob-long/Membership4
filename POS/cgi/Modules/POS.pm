package Modules::POS;

#----------------------------------------------------------------------------
#
#   Copyright (C) 2011 - Exware Solutions, Inc.  http://www.exware.com
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
#  POS (point-of-sale): Create ad-hoc invoices and accept payments on them.
#
#----------------------------------------------------------------------------

use strict;

# useful kernel libs; you can/should remove any of these that are not needed

use ExSite::Config;          # required
use ExSite::Input;           # optional input manager
use ExSite::Misc;            # optional utils
use ExSite::Util;            # optional utils
use ExSite::ML;              # optional markup-language generation
use ExSite::FormBuilder;     # optional form generation
use ExSite::ReportBuilder;   # optional report generation
use ExSite::Form;            # optional database manager
use ExSite::URI;
use ExSite::UI;
use Modules::Finance::Account;

# recommended base class for plug-in modules

use Modules::BaseDCD;

# declare package globals

use vars qw(@ISA $ml $ui);       # Perl inheritance global & markup language object

# define our class inheritance

@ISA = qw(Modules::BaseDCD); # inherit from this base class

sub read {
    my ($this,$opt) = @_;
    # fetch overlayed query and form input
    my $in = new ExSite::Input;
    $this->{input} = $in->combine;
    $this->{query} = $in->query;
    $this->{post} = $in->post;
    $this->{is_post} = (scalar keys %{$this->{post}}) > 0;
}

# write method (builds output for regular web pages)

sub write {
    my ($this,$options) = @_;
    $ml = new ExSite::ML;
    my $out;


    return $out;
}

# ioctl method (used by ExSite to query the module for its functionality)

sub ioctl {
    my $this = shift;
    $_ = shift;           # $_ is the ioctl request

    if (/isRestricted/) {
	return 0; ####################
    }
    elsif (/ModuleName/) {
	return "Point of Sale";
    }
    elsif (/ModuleInfo/) {
	return "Create ad-hoc invoices and accept payments on them.";
    }
    elsif (/Dependencies/) {
	return ["AddrBook","Finance"];
    }
    elsif (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/Category/) {
	my %cat = map { $_ => 1 } @{$config{webtop}{categories}};
	return exists $cat{Ecommerce} ? "Ecommerce" : "Applications";
    }
}

#----------------------------------------------------------------------------
# Everything after this point consists of private methods.

# ctrl_panel() generates the contents of the administrator control panel

sub ctrl_panel {
    my $this = shift;
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    my $out;

    my $section_id;
    if (! defined $config{POS}{scope} || $config{POS}{scope} eq "local") {
	$section_id = $this->get_section_id();
	if (! $section_id) { $out .= $this->set_section_id(); }
	return $out if (! $share{DB}->is_admin);
    }

    $out .= $this->show_path();

    if ($this->{account}) {
	$out .= $this->show_account();
    }
    else {
	$out .= $this->set_account();
    }

    if ($this->{account} || $this->{invoice}) {
	if (&ExSite::Module::exists("Pay")) {
	    my $payicon = &ExSite::Module::icon("Pay");
	    $out .= $ml->div($ml->a("&rarr; jump to Pay module".$ml->img(undef,{src=>$payicon}),{href=>"javascript:popup_large('$config{server}{CGIpath}/$config{prog}{ctrlpanel}/Pay?acct=$this->{query}{acct}&amp;inv=$this->{query}{inv}&amp;section_id=$this->{query}{section_id}')"}),{class=>"PayJumper"})
	}
    }

    return $out;
}

sub show_path {
    my $this = shift;
    my @path;
    push @path, $ml->a("Top",{href=>$this->link(inv=>undef,acct=>undef,item=>undef,section_id=>undef,cmd=>undef)});
    if ($this->{query}{section_id}) {
	my $s = new ExSite::Section(id=>$this->{input}{section_id});
	if ($s->owns()) {
	    $this->{section} = $s;
	    push @path, $ml->a($this->{section}->get_my("title"),{href=>$this->link(inv=>undef,acct=>undef,item=>undef,cmd=>undef)});
	}
	else {
	    return $this->error("Invalid section: permission denied.");
	}
    }
    if ($this->{query}{acct}) {
	my $a = new Modules::Finance::Account(id=>$this->{input}{acct});
	if ($a->allow()) {
	    $this->{account} = $a;
	    push @path, $ml->a($a->name(),{href=>$this->link(inv=>undef,item=>undef,cmd=>undef)});
	}
	else {
	    return $this->error("Invalid account: permission denied.");
	}
    }
    if ($this->{query}{inv}) {
	my $inv = new Modules::Finance::Receivable(id=>$this->{input}{inv});
	if ($inv->exists && $inv->account->id == $this->{account}->id) {
	    $this->{invoice} = $inv;
	    push @path, $ml->a($inv->name,{href=>$this->link(item=>undef,cmd=>undef)});
#	    push @path, $ml->a("Invoice $this->{input}{inv}",{href=>$this->link(item=>undef,cmd=>undef)});
	}
	else {
	    return $this->error("Invalid invoice: permission denied.");
	}
    }
    my $out = $ui->PathBar(links=>\@path);
    return $out;
}

sub set_account {
    my $this = shift;
    my $out;
    if ($this->{is_post}) {
	$out .= $this->new_account() if ($this->{post}{newacct});
	$out .= $this->find_account();
    }

    ###### SEARCH ACCOUNT CODE ??

    my $searchform = 
	$ml->h1("Search for account").
	$ml->form(
	    $ml->table(
		$ml->tr(
		    $ml->td("Account #").
		    $ml->td($ml->input(undef,{type=>"text",name=>"acct"})).
		    $ml->td("enter the exact account number",{class=>"POShelp"})
		).
		$ml->tr(
		    $ml->td("Invoice/Receipt #").
		    $ml->td($ml->input(undef,{type=>"text",name=>"inv"})).
		    $ml->td("enter an invoice or receipt number",{class=>"POShelp"})
		).
		$ml->tr(
		    $ml->td("Name").
		    $ml->td($ml->input(undef,{type=>"text",name=>"name"})).
		    $ml->td("enter a last name, company name, or last name, comma, first name",{class=>"POShelp"})
		).
		$ml->tr(
		    $ml->td("E-mail").
		    $ml->td($ml->input(undef,{type=>"text",name=>"email"})).
		    $ml->td("enter a complete email address",{class=>"POShelp"})
		).
		$ml->tr(
		    $ml->td("Phone").
		    $ml->td($ml->input(undef,{type=>"text",name=>"phone"})).
		    $ml->td("enter the last 4 digits of the phone number",{class=>"POShelp"})
		).
		$ml->tr(
		    $ml->td("Zip/Postal Code").
		    $ml->td($ml->input(undef,{type=>"text",name=>"pcode"})).
		    $ml->td("enter the complete postal code",{class=>"POShelp"})
		).
		$ml->tr(
		    $ml->td("").
		    $ml->td($ml->input(undef,{type=>"submit",value=>"Search"})).
		    $ml->td("")
		)
	    ),
	    {method=>"post"}
	),
    my $f = new ExSite::FormBuilder(method=>"post");
    $f->template("<table>",$ml->tr($ml->td("[[prompt]]").$ml->td("[[input]]")),"</table>");
    $f->input(name=>"newacct",value=>1,type=>"hidden",);
    $f->input(name=>"name",prompt=>"Name",placeholder=>"Last, First",required=>1,tail=>$ml->span(" Enter personal names as 'Lastname, Firstname'",{class=>"POShelp"}));
    $f->input(name=>"address",prompt=>"Address",size=>60);
    $f->input(name=>"city",prompt=>"City");
    $f->input(name=>"provstate",prompt=>"Province/State",type=>"select",options=>$share{DB}{map}->regexp("list:provstate"),nullvalue=>"== select ==");
    my $countries = $share{DB}{map}->regexp("list:country");
    if ($countries =~ /\|/) {
	$f->input(name=>"country",prompt=>"Country",type=>"select",options=>$share{DB}{map}->regexp("list:country"),nullvalue=>"== select ==");
    }
    else {
	$f->input(name=>"country",prompt=>"Country",type=>"text");
    }
    $f->input(name=>"pcode",prompt=>"Zip/Postal Code");
    $f->input(name=>"email",prompt=>"E-mail");
    $f->input(name=>"phone1",prompt=>"Phone");
    $f->input(name=>"phone2",prompt=>"Phone (alternate)");
    $f->input(name=>"fax",prompt=>"Fax");
    $f->input(name=>"web",prompt=>"URL");
    
    my $createform = $ml->h1("Create new account") . $f->make();

    $out .= $ui->DynTabBox(tabs=>["Search","New Account"],
			   panes=>[$searchform,$createform],
			   thistab=>0);

    return $out;
}

sub new_account {
    my $this = shift;
    my $out;

    my %acct = (
	section_id => $this->{input}{section_id},
	name => $this->{post}{name},
	);
    my %contact = (
	section_id => $this->{input}{section_id},
	type => $config{POS}{contact_type} || "billing",
	address => $this->{post}{address},
	city => $this->{post}{city},
	provstate => $this->{post}{provstate},
	country => $this->{post}{country},
	pcode => $this->{post}{pcode},
	email => $this->{post}{email},
	phone1 => $this->{post}{phone1},
	phone2 => $this->{post}{phone1},
	fax => $this->{post}{fax},
	web => $this->{post}{web},
	);

    my ($acct_id, $contact_id);
    $acct_id = $share{DB}->insert("account",\%acct);
    if ($acct_id) {
	$contact{account_id} = $acct_id;
	$contact_id = $share{DB}->insert("contact",\%contact);
    }
    if ($contact_id && $acct_id) {
	$out .= $ml->p("Account added successfully.");
    }
    else {
	$out .= $share{DB}->show_diagnostics("error","html");
    }
    return $out;
}

sub find_account {
    my $this = shift;
    my $post = $this->{post};
    if ($post->{inv}) {
	my $inv = new Modules::Finance::Receivable(id=>$post->{inv});
	my $acct = $inv->account();
	$ml->location($this->link(__plaintext=>1,acct=>$inv->getdata("account_id"),inv=>$inv->id));
	return undef;
    }
    my (@where,@param);
    if ($post->{acct}) { 
	push @where, "a.account_id=?";
	push @param, $post->{acct}; 
    }
    if ($post->{name}) { 
	push @where, "a.name like ?";
	push @param, "%".$post->{name}."%"; 
    }
    if ($post->{email}) { 
	push @where, "c.email like ?";
	push @param, $post->{email}; 
    }
    if ($post->{pcode}) { 
	push @where, "c.pcode like ?";
	push @param, $post->{pcode}; 
    }
    if ($post->{phone}) { 
	push @where, "(c.phone1 like ? or c.phone2 like ?)";
	push @param, "%".$post->{phone}, "%".$post->{phone};
    }
    my @result;
    if (scalar @where > 0) {
	my $query;
	$query = "select a.*,c.email,c.address,c.city,c.pcode,c.phone1,c.phone2,(select count(*) from receivable r where r.account_id=a.account_id) n_sale from account a left join contact c on c.account_id=a.account_id where ".
	    join(" and ",@where);
	if ($this->{input}{section_id} || $config{POS}{scope} eq "local") {
	    $query .= " and a.section_id=?";
	    push @param, $this->{input}{section_id};
	}
	$query .= " order by n_sale desc";
	@result = $share{DB}->custom_query($query,@param);
    }
    my $r = new ExSite::ReportBuilder(title=>"Accounts",dynamic=>1);
    $r->nodata("No matching accounts found.");
    $r->headers("#","Account","Email","Address","City","Phone");
    my %done;
    foreach my $a (@result) {
	my $key = "$a->{account_id} $a->{email} $a->{address} $a->{city} $a->{phone1}";
	next if $done{$key};
	$done{$key} = 1;
	$r->push(
	    $ml->a($a->{account_id},{href=>$this->link(acct=>$a->{account_id})}),
	    $ml->a($a->{name},{href=>$this->link(acct=>$a->{account_id})}),
	    $a->{email},
	    $a->{address},
	    $a->{city},
	    $a->{phone1} || $a->{phone2}
	    );
    }
    return $r->make;
}

sub show_account {
    my $this = shift;
    return undef if (! $this->{account});
    my $url = new ExSite::URI(); 
    my @tab;
    my @pane;

    if ($this->{invoice}) {
	push @tab, "Invoice";
	push @pane, $this->edit_invoice();
    }

    my $out = $this->{account}->show(receivable_uri=>$url,alltransactions=>1);
    $out .= $ml->p("To modify an existing invoice, click on its link.");
    push @tab, "Account";
    push @pane, $out;

    if (! $this->{invoice}) {
	push @tab, "New sale";
	push @pane, $this->new_invoice();
    }
    
    return $ui->DynTabBox( tabs=>\@tab, panes=>\@pane );
}

sub edit_invoice {
    my $this = shift;
    return undef if (! $this->{invoice});
    my $out;
    if ($this->{input}{item}) {
	return $this->invoice_item();
    }
    elsif ($this->{input}{cmd} eq "newitem") {
	return $this->new_invoice_item();
    }
    elsif ($this->{input}{cmd} eq "close") {
	$out .= $this->close_sale();
    }
    elsif ($this->{input}{cmd} eq "refund") {
	$out .= $this->refund_sale();
    }
    my $inv = $this->{invoice};
    if ($inv->is_valid && $this->{input}{cmd} eq "reopen") {
	$out .= $this->open_sale();
    }
    if ($inv->is_payable && ! $inv->is_valid) {
	$out .= $ui->ErrorBox(
	    title=>"You are editing a REFUND",
	    pane=>"Everything on this invoice will be refunded. More information is available under the help icon at top right."
	    );
    };
    $out .= $this->show_invoice();
    if ($inv->is_valid) {
	my $message = "This sale is closed, and cannot be modified.";
	my $warning = $ml->p("Altering completed sales can create imbalances or 
other auditing problems in your accounting system. It will also recalculate taxes
and surcharges from scratch, using the current rules. Please ensure that you know 
what you are doing before modifying completed sales.");
	$warning .= $ml->p($ui->Button(label=>"Continue",url=>$this->link(cmd=>"reopen")));
	$message .= $ml->br.
	    $ui->Popup(label=>"Re-open sale.",
		       closelabel=>"cancel",
		       pane=>$warning);
	$out .= $ml->p($message);
	if ($inv->is_receivable && $inv->is_active) {
	    $out .= $ml->p($ml->a("Refund all or part of this sale.",{href=>$this->link(cmd=>"refund")}));
	}
	if ($this->{input}{cmd} eq "close") {
	    $out .= $ui->BlindBox(
		title=>"Pay now",
		pane=>$this->payment(),
		open=>0);
	}
    }
    else {
	$out .= $ml->p($ui->Button(label=>"Finish Sale",url=>$this->link(cmd=>"close")));
	$out .= $ml->p("You must finish the sale to calculate taxes and surcharges, and add the invoice into the accounting system.");
    }
    return $out;
}

sub new_invoice {
    my $this = shift;
    return undef if (! $this->{account});
    my $out;
    if (scalar keys %{$this->{post}} > 0) {
	my %data = $share{DB}->parse_parts(%{$this->{post}});
	my $inv = new Modules::Finance::Receivable(data=>\%data);
	my $invid = $inv->save();
	if ($invid) {
	    $ml->location($this->link(__plaintext=>1,inv=>$invid));
	}
	else {
	    $out .= $inv->show_diagnostics("error","html");
	}
    }
    else {
	$out .= $ml->h1("New sale");
	$out .= $ml->p("In most cases, you do not need to set any advanced configuration options.".$ml->br."Just click Continue to start a new invoice.");

	$share{DB}->set_action("insert");
	my $form = $share{DB}->input_record({table=>"receivable",
					     data=>{account_id=>$this->{account}->id,
						    type=>"receivable",
						    status=>"inactive"},
					     hide=>["account_id"],
					     simplename=>1});

	$out .= $ml->form(
	    $ui->BlindBox(
		title=>"Advanced configuration options",
		pane=>$form,
		open=>0).
	    $ml->p($ml->input(undef,{type=>"submit",value=>"Continue &gt;"})),
	    {method=>"post"}
	    );
    }
    return $out;
}

sub show_invoice {
    my ($this,%opt) = @_;
    my $inv = $this->{invoice};
    return undef if (! $inv);
    my ($table,$total);
    my $table .= 
	$ml->colgroup(undef,{align=>"right"}).
	$ml->colgroup().
	$ml->colgroup(undef,{span=>3,align=>"right"}).
	$ml->colgroup();
    my $sizeunit = $opt{size} || "Size";
    my $thead = $ml->thead(
			   $ml->tr(
				   $ml->th("Quantity").
				   $ml->th("Description").
				   $ml->th($sizeunit).
				   $ml->th("Unit Price").
				   $ml->th("Subtotal").
				   $ml->th("Options")
				   )
			   );
    my $tbody;
    my $items = $inv->loaditems();
    my $delicon = "$config{server}{HTMLpath}/_Modules/POS/delete.png";
    my $editicon = "$config{server}{HTMLpath}/_Modules/POS/edit.png";
    my $addicon = "$config{server}{HTMLpath}/_Modules/POS/add.png";
    my $editable = ( ! $inv->is_valid );
    while (my $item = $items->next) {
	my @row = ($ml->div($item->quantity,{class=>"number"}), 
		   $ml->strong($item->name).$ml->br().$item->showdata("description"));
	push @row, $ml->div($item->size,{class=>"number"});
	push @row, $ml->div($item->unitprice,{class=>"number"});
	push @row, $ml->div($item->subtotal,{class=>"number"});
	push @row, $editable ?
	    $ml->a($ml->img(undef,{src=>$editicon,alt=>"edit",title=>"edit"}),{class=>"invoice_tool",href=>$this->link(item=>$item->id)}) . " " .
	    $ml->a($ml->img(undef,{src=>$delicon,alt=>"delete",title=>"delete"}),{class=>"invoice_tool",href=>$this->link(item=>$item->id,cmd=>"del")}) :
	    "";
	$tbody .= $ml->tr( \@row );
    }
    $tbody = $ml->tbody($tbody);
    my $tfoot;
    $tfoot .= $ml->tr( [ undef, 
			 "Total $sizeunit", 
			 $ml->div($inv->size(),{class=>"number"}), 
			 undef, 
			 undef, 
			 undef ] );
    my $total = $inv->is_payable ? $msg{"REFUND TOTAL"} : ($msg{$opt{total}} || $msg{"TOTAL DUE"});
    my $foot2 = [ undef, 
		  $total,
		  undef,
		  undef,
		  $ml->div('$'.$inv->total(),{class=>"number total"}),
		  undef ];
    push @$foot2, $tfoot .= $ml->tr( $foot2 );
    $tfoot = $ml->tfoot($tfoot);
    my $out = $ml->table( $table.$thead.$tfoot.$tbody, {class=>"Receivable",cellpadding=>5});
    if ($editable) {
	$out .= $ml->a($ml->img(undef,{src=>$addicon,alt=>"add",title=>"add"})." add item",{class=>"invoice_tool",href=>$this->link(cmd=>"newitem")});
    }
    return $out;
}

sub open_sale {
    my ($this) = @_;
    my $inv = $this->{invoice};
    return undef if (! $inv);
    my $out;
    if ($inv->is_valid) {
	$inv->setdata("status","inactive");
	if (! $inv->save) {
	    $out .= $inv->show_diagnostics("error","html");
	    return $out;
	}
	$out = $ml->p("resetting surcharges...");
	$inv->remove_surcharges();
    }
    return $out;
}

sub close_sale {
    my ($this) = @_;
    my $inv = $this->{invoice};
    return undef if (! $inv);
    my $out;
    if (! $inv->is_valid) {
	# calculate surcharges, unless user has added them manually
	my $has_surcharges = 0;
	my $items = $inv->loaditems();
	$items->reset();
	while (my $item = $items->next) {
	    if ($item->is_surcharge) {
		$has_surcharges = 1;
		last;
	    }
	}
	if ($has_surcharges) {
	    $out = $ui->ErrorBox(title=>"Warning",pane=>"Invoice already includes surcharges, skipping adjustments.");
	}
	else {
	    $out = $ml->p("calculating surcharges...");
	    $inv->remove_surcharges();
	    $inv->add_surcharges();
	}
	$inv->setdata("status","active");
	if (! $inv->save) {
	    $out .= $inv->show_diagnostics("error","html");
	    return $out;
	}
    }
    return $out;
}

sub refund_sale {
    my ($this) = @_;
    my $inv = $this->{invoice};
    return undef if (! $inv);
    my $newinv = $inv->copy(type=>"payable",status=>"inactive",date=>undef);
    if ($newinv) {
	# change line item descriptions
	my $refund = new Modules::Finance::Receivable(id=>$newinv);
	my $items = $refund->loaditems();
	while (my $item = $items->next) {
	    my $name = $item->getdata("item");
	    $item->setdata("item","REFUND: ".$name);
	    $item->save;
	}
	$ml->location($this->link(__plaintext=>1,inv=>$newinv,cmd=>undef));
    }
    return;
}

sub invoice_item {
    my $this = shift;
    my $item = new Modules::Finance::ReceivableItem(id=>$this->{input}{item});
    if ($item->exists) {
	if ($item->getdata("receivable_id") == $this->{invoice}->id) {
	    my $cmd = $this->{input}{cmd};
	    if ($cmd eq "del") {
		if ($item->delete()) {
		    $ml->location($this->link(__plaintext=>1,cmd=>undef,item=>undef));
		    return "Item deleted.";
		}
		else {
		    return $item->show_diagnostics("error","html");
		}
	    }
	    elsif ($cmd eq "doedit") {
		if ($item->do_edit()) {
		    $ml->location($this->link(__plaintext=>1,cmd=>undef,item=>undef));
		    return "Changes saved.";
		}
		else {
		    return $item->show_diagnostics("error","html");
		}
	    }
	    else {
		my $out = $this->{input}{item} ?
		    $ml->h1("Modify invoice item") :
		    $ml->h1("Add item to invoice");
		$out .= $item->edit(
		    action=>$this->link(cmd=>"doedit"),
		    hide=>["receivable_id","surcharge_id","fulfilled_by","fulfilled_on","fulfilled_qty"],
		    );
		return $out;
	    }
	}
	else {
	    return $this->error("Invoice mismatch: permission denied.");
	}

    }
    else {
	return $this->error("Invalid item: permission denied.");
    }
}

sub new_invoice_item {
    my $this = shift;
    my $item = new Modules::Finance::ReceivableItem();
    if (scalar keys %{$this->{post}} > 0) {
	if ($item->do_make()) {
	    if (&OnError()) {
		return $share{DB}->show_diagnostics("error","html").
		    $ml->p($ui->BackButton);
	    }
	    else {
		$ml->location($this->link(__plaintext=>1,cmd=>undef,item=>undef));
		return "Changes saved.";
	    }
	}
	else {
	    return $item->show_diagnostics("error","html");
	}
    }
    else {
	return $item->make(action=>$this->link(),
			   data=>{receivable_id=>$this->{invoice}->id,
				  member_id=>$share{DB}->my_uid},
			   hide=>["receivable_id","fulfilled_by","fulfilled_on","fulfilled_qty","member_id"]);
    }
}

sub payment {
    my ($this) = @_;
    my $inv = $this->{invoice};
    if (scalar keys %{$this->{post}} > 0) {
	my $total = $inv->total;
	my %payment = (receivable_id=>$inv->id,
		       account_id=>$inv->account->id,
		       amount=>$inv->total,
		       method=>$this->{post}{method},
		       note=>$this->{post}{note},
		       status=>"paid",
		       member_id=>$share{DB}->my_uid );
	if ($this->{invoice}->is_payable) {
	    # this payment is actually from us, not to us
	    $payment{amount} = - $payment{amount};
	}
	my $pid = $share{DB}->insert("payment",\%payment);
	if ($pid) {
	    $ml->location($this->link(__plaintext=>1,cmd=>undef,inv=>undef));
	    return "Payment recorded.";
	}
	else {
	    return $share{DB}->show_diagnostics("error","html");
	}
    }
    else {
	my $f = new ExSite::FormBuilder();
	$f->input(name=>"method",
		  prompt=>"Payment Method",
		  type=>"select",
		  options=>$share{DB}{map}->regexp("list:payment_method"));
	$f->input(name=>"note",
		  prompt=>"Notes",
		  type=>"textarea",
		  size=>100);
	$f->set("buttons",$ml->input(undef,{type=>"submit",value=>"Pay now"}));
	my $total = $inv->total();
	my $out = $ml->p("This will record a payment of $config{report}{currency_char}$total.");
	$out .= $f->make();
	return $out;
    }
}

1;
