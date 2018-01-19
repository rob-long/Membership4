package Modules::Finance;

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
#  Track receivables and revenues from the Finance subsystem.
#
#  FIXME: invert payments if made against a payable!
#         ignore advisory invoices
#
#----------------------------------------------------------------------------

use strict;

use ExSite::Config;
use ExSite::Input;
use ExSite::Misc;
use ExSite::Util;
use ExSite::ML;
use ExSite::Content;
use ExSite::FormBuilder;
use ExSite::ReportBuilder;
use ExSite::Form;
use ExSite::UI;

use Modules::Finance::Receivable;
use Modules::BaseDCD;

# declare package globals

use vars qw(@ISA $ml $ui);

# define our class inheritance

@ISA = qw(Modules::BaseDCD);

sub write {
    return undef;
}

# ioctl method (used by ExSite to query the module for its functionality)

sub ioctl {
    my $this = shift;
    $_ = shift;           # $_ is the ioctl request

    if (/isRestricted/) {
	return 0;
    }
    elsif (/isService/) {
	return 0;
    }
    elsif (/ModuleName/) {
	return "Financial Reports";
    }
    elsif (/ModuleInfo/) {
	return "Track receivables and revenues from the Finance subsystem.";
    }
    elsif (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/Category/) {
	return [ "Ecommerce", "Applications" ];
#	my %cat = map { $_ => 1 } @{$config{webtop}{categories}};
#	return exists $cat{Ecommerce} ? "Ecommerce" : "Applications";
    }
}

#----------------------------------------------------------------------------
# Everything after this point consists of private methods.

# ctrl_panel() generates the contents of the administrator control panel

sub ctrl_panel {
    my $this = shift;
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    my $out = $ml->script(undef,{type=>"text/javascript",src=>"$config{server}{HTMLpath}/_ExSite/js/date.js"});
    $out .= $ml->script(undef,{type=>"text/javascript",src=>"$config{server}{HTMLpath}/_ExSite/js/jquery.datePicker.js"});
    $out .= $ml->link(undef,{rel=>"stylesheet",type=>"text/css",media=>"screen",href=>"$config{server}{HTMLpath}/_ExSite/css/datePicker.css"});
    $out .= $ml->script("Date.firstDayOfWeek = 0;\nDate.format = 'yyyy-mm-dd';\n\$(function() {\n\$('.date-pick').datePicker({startDate:'$config{form}{date_picker_start_date}'});\n});\n",
			{type=>"text/javascript",charset=>"utf-8"});

    $this->{section_id} = $this->get_section_id();
    if (! $this->{section_id} && $config{Finance}{scope} eq "local") {
	$out .= $this->set_section_id();
	if ($share{DB}->is_admin()) {
	    $out .= $this->warn("No site selected&mdash;showing aggregate financial results from all sites combined.");
	}
	else {
	    return $out;
	}
    }
    elsif ($this->{section_id} && $config{Finance}{scope} eq "global" && $share{DB}->count("section") > 1) {
	my $s = new ExSite::Section(id=>$this->{section_id});
	$out .= $this->warn("Viewing reports for ".$ml->em($s->title)." only. Click the home icon to view all financial data aggregated together.");
    }
    $this->setup_queries;
#    $out .= $ml->h1("Financial Reports");
    $this->get_report_data($this->{input}{date_start},$this->{input}{date_end});
    my $nitem = 
	scalar @{$this->{receivables_by_date}} + 
	scalar @{$this->{payments_by_date}};
    if ($nitem == 0) {
	if ($this->{input}{date_start}) {
	    $out .= $ml->p("No financial activity found in this date range.");
	}
	$out .= $this->report_form();
    }
    else {
	my $report;
	my $pane;
	my $rtype = $this->{input}{type};
	if ($rtype =~ /^purchases/) {
	    $pane = $this->report_activity();
	}
	elsif ($rtype =~ /^itemized/) {
	    $pane = $this->report_items($rtype);
	}
	elsif ($rtype =~ /^journal/) {
	    $pane = $this->report_journal();
	}
	elsif ($rtype =~ /^GL code/) {
	    $pane = $this->report_glcode();
	}
	elsif ($rtype =~ /^sales/) {
	    $pane = $this->report_sales();
	}
	elsif ($rtype =~ /^revenue/) {
	    $pane = $this->report_revenues();
	}
	elsif ($rtype =~ /^account/) {
	    $pane = $this->report_accounts();
	}
	elsif ($rtype =~ /daily/) {
	    $pane = $this->report_daily();
	}
	elsif ($rtype =~ /monthly/) {
	    $pane = $this->report_monthly();
	}

	$out .= $ui->TabBox(
	    tabs=>["Parameters","Report"],
	    panes=>[$this->report_form(),$pane],
	    thistab=>1,
	    );
    }
    return $out;
}

sub report_form {
    my $this = shift;
    my $hidden = shift;
    my $in = $this->{input};
    my $f = new ExSite::FormBuilder(action=>$this->link(date_start=>undef,date_end=>undef,type=>undef));
    my ($date_start,$date_end);
    if ($in->{date_start} && $in->{date_end}) {
	$date_start = $in->{date_start};
	$date_end = $in->{date_end};
    }
    else {
	my $t = new ExSite::Time;
	$date_end = $t->write("sql_date");
	$t->add(-30,"days");
	$date_start = $t->write("sql_date");
    }
    if ($hidden) {
	$f->input(name=>"date_start",type=>"hidden",value=>$date_start);
	$f->input(name=>"date_end",type=>"hidden",value=>$date_end);
	$f->input(name=>"type",type=>"hidden",value=>$in->{type});
	$f->input(name=>"confirm",type=>"hidden",value=>1);
	$f->set("buttons",$ml->input(undef,{type=>"submit",value=>"Confirm"}));
    }
    else {
	my $type = $in->{type};
	$type =~ s/ & / &amp; /;
	$f->input(name=>"date_start",prompt=>"Start Date",value=>$date_start,size=>12,class=>"date-pick");
	$f->input(name=>"date_end",prompt=>"End Date",value=>$date_end,size=>12,class=>"date-pick");
	$f->input(name=>"type",prompt=>"Report Type",value=>$type,required=>1,
		  type=>"radio",options=>[
					  "purchases &amp; payments",
					  "sales (purchases only)",
					  "itemized sales",
					  "revenues (payments only)",
					  "itemized revenues",
					  "journal (itemized sales + payments)",
					  "GL code summaries",
					  "account summaries",
					  "daily summaries",
					  "monthly summaries",
					  ]);
    }
    return $f->make() . $ml->p("Report types are defined in the help link, above.");
}

sub get_report_data {
    my ($this,$start,$end) = @_;
    my $db = $share{DB};
    my $sid = $this->{section_id};

    # add 1 day to end date, because we want to include everything to the 
    # end of the end date, not just take everything *before* the end date

    my $enddate = new ExSite::Time($end,'sql_date');
    $enddate->add(1,"day");
    $end = $enddate->write("sql_date");

    if ($sid && $config{Finance}{scope} eq "local") {
	$this->{receivables_by_date} = 
	    $db->get_query("receivables by date and section",$sid,$start,$end);
	$this->{payments_by_date} = 
	    $db->get_query("payments by date and section",$sid,$start,$end);
    }
    else {
	$this->{receivables_by_date} = 
	    $db->get_query("receivables by date",$start,$end);
	$this->{payments_by_date} = 
	    $db->get_query("payments by date",$start,$end);
    }
}

sub report_accounts {
    my $this = shift;
    my $db = $share{DB};
    my $in = $this->{input};
    my $out;
    my $start = $in->{date_start};
    my $t = new ExSite::Time($in->{date_end},"sql_date");
    $t->add(1,"day");
    my $end = $t->write("sql_date");

    # get account codes to report
    my @acctcode = $share{DB}->fetch_all("acctcode");
    my %acctcode_id = keywise("acctcode_id",\@acctcode);
    my %acctcode_name = keywise("code",\@acctcode);

    my @show_acctcode;
    @show_acctcode = map { $_->{acctcode_id} } @acctcode;

    # get reportable data
    my @data = sort { $a->{date} cmp $b->{date} } (@{$this->{receivables_by_date}},@{$this->{payments_by_date}});
    
    # merge into single account row
    my %acct;
    my %total;
    foreach my $data (@data) {
	my $aid = $data->{account_id};
	if (! exists $acct{$aid}) {
	    $acct{$aid} = { 
		account => $data->{account_id},
		name => $data->{name},
	    };
	}
	my @rdata;
	if ($data->{payment_id}) {
	    # payment
	    next if ($data->{status} !~ /paid|received/);
	    $acct{$aid}{credit} += $data->{amount};
	    $total{credit} += $data->{amount};
	}
	elsif ($data->{type} eq "receivable") {
	    # receivable
	    next if ($data->{status} ne "active");
	    my $r = new Modules::Finance::Receivable(data=>$data);
	    my $total = $r->total;
	    $acct{$aid}{debit} += $total;
	    $total{debit} += $total;
	    foreach (@show_acctcode) { 
		$acct{$aid}{$acctcode_id{$_}{code}} += $r->subtotal($_);
		$total{$acctcode_id{$_}{code}} += $r->subtotal($_);
	    }
	}
	else {
	    # payable 
	    next if ($data->{status} ne "active");
	    my $r = new Modules::Finance::Receivable(data=>$data);
	    my $total = $r->total;
	    $acct{$aid}{credit} += $total;
	    $total{credit} += $total;
	    foreach (@show_acctcode) { 
		$acct{$aid}{$acctcode_id{$_}{code}} -= $r->subtotal($_);
		$total{$acctcode_id{$_}{code}} -= $r->subtotal($_);
	    }
	}
	if ($data->{date} cmp $acct{$aid}{date} > 0) { 
	    $acct{$aid}{date} = $data->{date};
	}
    }
    
    # report
    my $r = new ExSite::ReportBuilder();
    $r->title("Account Summary $start to $end");
    my @acctinfo = @{$this->report_account_info()};
    my @head = ("Last Transaction","Account",@acctinfo,"Credit","Debit","Balance");
    foreach my $icode (@show_acctcode) {
	push @head, $acctcode_id{$icode}{code}; 
    }
    $r->headers(\@head);
    my $ncol = 6 + scalar @show_acctcode;
    foreach my $acct (sort { $a->{date} cmp $b->{date} } values %acct) {
	next if (! $acct->{credit} && ! $acct->{debit});
	my $url = new ExSite::URI(uri=>"$config{server}{server}$config{server}{CGIpath}/$config{prog}{ctrlpanel}/Pay");
	my $balance = $acct->{credit} - $acct->{debit};
	my @rdata = (
	    $acct->{date},
	    $acct->{account},
	    @{$this->report_account_info($acct->{account},$url)},
#	    $ml->a($acct->{name},{href=>"javascript:popup_large('$config{server}{server}$config{server}{CGIpath}/$config{prog}{ctrlpanel}/Pay?section_id=$this->{section_id}&acct=$acct->{account}')"}),
	    $ml->div(sprintf("%.02f",$acct->{credit}),{class=>"num"}),
	    $ml->div(sprintf("%.02f",$acct->{debit}),{class=>"num"}),
	    $balance != 0 ? $ml->div(sprintf("%.02f",$balance),{class=>"num"}) : undef,
	    );
    foreach (@show_acctcode) { 
	    my $sub = $acct->{$acctcode_id{$_}{code}};
	    push @rdata, $sub > 0 ? $ml->div(sprintf("%.02f",$acct->{$acctcode_id{$_}{code}}),{class=>"num"}) : undef;
	}
	$r->push(@rdata);
    }
    # totals
    my @acctfoot = map { undef } @acctinfo;
    my @rdata = (
	"TOTALS",
	undef,
	@acctfoot,
	$ml->div(sprintf("%.02f",$total{credit}),{class=>"num"}),
	$ml->div(sprintf("%.02f",$total{debit}),{class=>"num"}),
	$ml->div(sprintf("%.02f",$total{credit}-$total{debit}),{class=>"num"}),
	);
    foreach (@show_acctcode) { 
	my $sub = $total{$acctcode_id{$_}{code}};
	push @rdata, $sub ? $ml->div(sprintf("%.02f",$total{$acctcode_id{$_}{code}}),{class=>"num"}) : undef;
    }
    $r->push(@rdata);
    $r->foot($this->footer);
    if ($this->{input}{fmt}) {
	$this->export($r,$this->{input}{fmt});
	return undef;
    }    
    return $r->make;
}

sub export {
    my ($this,$r,$fmt) = @_;
    $fmt or $fmt = $this->{input}{fmt};
    $ml->cancel;
    if ($fmt eq "excel") { 
	print "Content-type: application/vnd.ms-excel\ncontent-disposition: attachment; filename=query.xls\n\n";
	$r->export("excel");
    }
    elsif ($fmt eq "csv") {
	print "Content-type: text/comma-separated-values\n\n";
	print $r->export("csv");
    }
}

sub report_account_info {
    my ($this,$account_id,$url) = @_;

    # allow for site-by-site customization of relevant account holder info
    my $stat = $this->run_handler("Finance_report_account_info",$account_id,$url);
    return $stat if (defined $stat);

    # no customization - show basic account info

    $ml or $ml = &get_obj("ML");
    if ($account_id) {
	# return account holder info
	my $acct = new Modules::Finance::Account(id=>$account_id);
	$url->query(acct=>$account_id,section_id=>$this->{section_id});
	return [$ml->a($acct->name,{href=>"javascript:popup_large('".$url->write()."')"})];
    }
    else {
	# return headers
	return ["Account"];
    }
}

sub report_activity {
    my $this = shift;
    my $db = $share{DB};
    my $in = $this->{input};
    my $out;
    my $start = $in->{date_start};
    my $t = new ExSite::Time($in->{date_end},"sql_date");
    $t->add(1,"day");
    my $end = $t->write("sql_date");

    # get reportable data
    my @data = sort { $a->{date} cmp $b->{date} } (@{$this->{receivables_by_date}},@{$this->{payments_by_date}});
    
    # get account codes to report
    my @acctcode = $share{DB}->fetch_all("acctcode");
    my %acctcode_id = keywise("acctcode_id",\@acctcode);
    my %acctcode_name = keywise("code",\@acctcode);

    my @show_acctcode;
    @show_acctcode = map { $_->{acctcode_id} } @acctcode;

    # report
    my $r = new ExSite::ReportBuilder();
    $r->title("Financial Activity Statement $start to $in->{date_end}");
    my @acctinfo = @{$this->report_account_info()};
    my @head = ("Date","Type",@acctinfo,"Invoice","Credit","Debit");
    foreach my $icode (@show_acctcode) { 
	push @head, $acctcode_id{$icode}{code}; 
    }
    $r->headers(\@head);
    my $ncol = 6 + scalar @show_acctcode;
    my %total;
    foreach my $data (@data) {
	my @rdata;
	my $acct = new Modules::Finance::Account(id=>$data->{account_id});
	my $url = new ExSite::URI(uri=>"$config{server}{server}$config{server}{CGIpath}/$config{prog}{ctrlpanel}/Pay");
	my $date = $data->{date};
	if ($config{Finance}{date_format}) {
	    my $t = new ExSite::Time($date,"sql_datetime");
	    $date = $t->write($config{Finance}{date_format});
	}
	if ($data->{payment_id}) {
	    # payment
	    next if ($data->{status} !~ /paid|received/);
	    $url->query(section_id=>$this->{section_id},acct=>$data->{account_id},inv=>$data->{receivable_id});
	    my $invdata = $data->{receivable_id} ?
		$ml->a($data->{receivable_id},{href=>"javascript:popup_large('".$url->write()."')"}) :
		"n/a";
	    @rdata = (
		$date,
		"payment",
		@{$this->report_account_info($data->{account_id},$url)},
#		      $ml->a($acct->name,{href=>"javascript:popup_large('".$url->write()."')"}),
		$invdata,
		$ml->div($data->{amount},{class=>"num"}),
		undef,
		);
	    for (1 .. scalar @show_acctcode) { push @rdata, undef; }
	    $total{Credit} += $data->{amount};
	}
	elsif ($data->{type} eq "receivable") {
	    # receivable
	    next if ($data->{status} ne "active");
	    my $r = new Modules::Finance::Receivable(data=>$data);
	    my $total = $r->total();
	    $url->query(section_id=>$this->{section_id},acct=>$data->{account_id},inv=>$data->{receivable_id});
	    @rdata = (
		$date,
		"receivable",
		@{$this->report_account_info($data->{account_id},$url)},
		#      $ml->a($acct->name,{href=>"javascript:popup_large('".$url->write()."')"}),
		$ml->a($data->{receivable_id},{href=>"javascript:popup_large('".$url->write()."')"}),
		undef,
		$ml->div($total,{class=>"num"}),
		);
	    $total{Debit} += $total;
	    foreach (@show_acctcode) { 
		my $sub = $r->subtotal($_);
		push @rdata, ($sub > 0 ? $ml->div($sub,{class=>"num"}) : undef);
		$total{$acctcode_id{$_}{code}} += $sub;
	    }
	}
	else {
	    # payable 
	    next if ($data->{status} ne "active");
	    my $r = new Modules::Finance::Receivable(data=>$data);
	    my $total = $r->total();
	    @rdata = (
		$date,
		"payable",
		@{$this->report_account_info($data->{account_id},$url)},
		# $data->{account_id},
		$data->{receivable_id},
		$ml->div($total,{class=>"num"}),
		undef,
		);
	    $total{Credit} += $total;
	    foreach (@show_acctcode) { 
		my $sub = $r->subtotal($_);
		push @rdata, ($sub > 0 ? $ml->div(- $sub,{class=>"num"}) : undef);
		$total{$acctcode_id{$_}{code}} -= $sub;
	    }
	}
	$r->push(@rdata);
    }
    # totals
    my @acctfoot = map { undef } @acctinfo;  # blank cell for each acct item
    my @rdata = (
	"TOTALS",
	undef,
	@acctfoot,
	undef,
	$ml->div(sprintf("%.02f",$total{Credit}),{class=>"num"}),
	$ml->div(sprintf("%.02f",$total{Debit}),{class=>"num"}),
	);
    foreach (@show_acctcode) { 
	push @rdata, $ml->div(sprintf("%.02f",$total{$acctcode_id{$_}{code}}),{class=>"num"});
    }
    $r->push(@rdata);
    $r->foot($this->footer);
    if ($this->{input}{fmt}) {
	$this->export($r,$this->{input}{fmt});
	return undef;
    }
    return $r->make;
}

# itemized reports show every line item sold in the period

sub report_items {
    my ($this,$report_type) = @_;
    my $db = $share{DB};
    my $in = $this->{input};
    my $out;
    my $start = $in->{date_start};
    my $t = new ExSite::Time($in->{date_end},"sql_date");
    $t->add(1,"day");
    my $end = $t->write("sql_date");
    my @item;
    if ($report_type =~ /revenues/) {
	@item = $this->{input}{section_id} ?
	    $db->get_query("itemized payments by date and section",$start,$end,$this->{input}{section_id}) :
	    $db->get_query("itemized payments by date",$start,$end);
    }
    else {
	@item = $this->{section_id} ?
	    $db->get_query("itemized sales by date and section",$start,$end,$this->{section_id}) :
	    $db->get_query("itemized sales by date",$start,$end);
    }
    my $r = new ExSite::ReportBuilder(title => ucfirst $report_type . " - $start to $in->{date_end}");
    my @head = ("Date",@{$this->report_account_info()},"Invoice","Quantity","Item","Description","Type","GL Code","Amount");
    $r->headers(\@head);
    foreach my $data (@item) {
	next if ($this->{input}{acctcode} && $this->{input}{acctcode}!=$data->{acctcode_id});
	my $ritem = new Modules::Finance::ReceivableItem(data=>$data);
	my $subtotal = $ritem->subtotal();
	next if ($report_type =~ /revenues/ && $subtotal < 0.01);
	my @rdata = ( $data->{date} );
	my $url = new ExSite::URI(uri=>"$config{server}{server}$config{server}{CGIpath}/$config{prog}{ctrlpanel}/Pay");
	if ($this->{input}{section_id}) {
	    $url->parameter("section_id",$this->{input}{section_id});
	}
	push @rdata, @{$this->report_account_info($data->{account_id},$url)};
	$url->query(inv=>$data->{receivable_id});
	push @rdata, $ml->a($data->{receivable_id},{href=>$url->write()});
	push @rdata, $ml->div($ritem->quantity(),{class=>"num"});
	push @rdata, ($data->{item}, $data->{description}, $data->{code}, $ritem->glcode());
	push @rdata, $ml->div($subtotal,{class=>"num"});
	$r->push(@rdata);
    }
    $r->foot($this->footer);
    if ($this->{input}{fmt}) {
	$this->export($r,$this->{input}{fmt});
	return undef;
    }
    my $out = $r->make();
    $out .= $this->acctcode_selector();
    return $out;
}

# a journal report is a sequential listing of every item sold and every
# payment received

sub report_journal {
    my ($this) = @_;
    my $db = $share{DB};
    my $in = $this->{input};
    my $out;
    my $start = $in->{date_start};
    my $t = new ExSite::Time($in->{date_end},"sql_date");
    $t->add(1,"day");
    my $end = $t->write("sql_date");
    my @item = $this->{section_id} ?
	$db->get_query("itemized sales by date and section",$start,$end,$this->{section_id}) :
	$db->get_query("itemized sales by date",$start,$end);
    push @item, $this->{section_id} ?
	$db->get_query("payments by date and section",$this->{section_id},$start,$end) :
	$db->get_query("payments by date",$start,$end);
    my @sorted = sort { $a->{date} cmp $b->{date} } @item;
    my $r = new ExSite::ReportBuilder(title => "Journal - $start to $in->{date_end}");
    my $accthead = $this->report_account_info();
    my @head = ("Date",@{$accthead},"Invoice","Quantity","Item","Description","Identifier","Type","GL Code","Credit","Debit");
    $r->headers(\@head);
    my ($total_db, $total_cr);
    foreach my $data (@sorted) {
	if ($data->{payment_id}) {
	    # payment
	    my $payment = new Modules::Finance::Payment(data=>$data);
	    next if (! $payment->is_paid);
	    my $amt = $payment->amount;
	    my $db = $amt < 0.00 ? sprintf("%.02f",-$amt) : undef;
	    my $cr = $amt >= 0.00 ? sprintf("%.02f",$amt) : undef;
	    $total_db += $db;
	    $total_cr += $cr;
	    my @rdata = ( $data->{date} );
	    my $url = new ExSite::URI(uri=>"$config{server}{server}$config{server}{CGIpath}/$config{prog}{ctrlpanel}/Pay");
	    if ($this->{input}{section_id}) {
		$url->parameter("section_id",$this->{input}{section_id});
	    }
	    push @rdata, @{$this->report_account_info($data->{account_id},$url)};
	    $url->query(inv=>$data->{receivable_id});
	    push @rdata, $ml->a($data->{receivable_id},{href=>$url->write()});
	    push @rdata, undef;  # quantity
	    push @rdata, $amt < 0.00 ? "Refunded Payment" : "Payment";
	    push @rdata, $data->{note}, $data->{ident}, $data->{method};
	    push @rdata, $payment->glcode;
	    push @rdata, $ml->div($cr,{class=>"num"});
	    push @rdata, $ml->div($db,{class=>"num"});
	    $r->push(@rdata);
	}
	else {
	    # sale
	    my $ritem = new Modules::Finance::ReceivableItem(data=>$data);
	    next if (! $ritem->is_active);
	    my $amt = $ritem->subtotal();
	    my $cr = $amt < 0.00 ? sprintf("%.02f",-$amt) : undef;
	    my $db = $amt >= 0.00 ? sprintf("%.02f",$amt) : undef;
	    $total_db += $db;
	    $total_cr += $cr;
	    my @rdata = ( $data->{date} );
	    my $url = new ExSite::URI(uri=>"$config{server}{server}$config{server}{CGIpath}/$config{prog}{ctrlpanel}/Pay");
	    if ($this->{input}{section_id}) {
		$url->parameter("section_id",$this->{input}{section_id});
	    }
	    push @rdata, @{$this->report_account_info($data->{account_id},$url)};
	    $url->query(inv=>$data->{receivable_id});
	    push @rdata, $ml->a($data->{receivable_id},{href=>$url->write()});
	    push @rdata, $ml->div($ritem->quantity(),{class=>"num"});
	    push @rdata, ($data->{item}, $data->{description}, undef, $data->{code}, $ritem->glcode());
	    push @rdata, $ml->div($cr,{class=>"num"});
	    push @rdata, $ml->div($db,{class=>"num"});
	    $r->push(@rdata);
	}
    }
    my @acctcols = map { "" } @$accthead;
    $r->push( undef, @acctcols, undef, undef, "TOTALS", undef, undef, undef, undef, $ml->div(sprintf("%.02f",$total_cr),{class=>"num"}), $ml->div(sprintf("%.02f",$total_db),{class=>"num"}) );
    $r->foot($this->footer);
    if ($this->{input}{fmt}) {
	$this->export($r,$this->{input}{fmt});
	return undef;
    }
    my $out = $r->make();
    return $out;
}

# GL code summary summarizes each GLcode

sub report_glcode {
    my ($this) = @_;
    my $db = $share{DB};
    my $in = $this->{input};
    my $out;
    my $start = $in->{date_start};
    my $t = new ExSite::Time($in->{date_end},"sql_date");
    $t->add(1,"day");
    my $end = $t->write("sql_date");
    my (%glcode,%iglcode);

    # first, do sales

    my @item = $this->{section_id} ?
	$db->get_query("itemized sales by date and section",$start,$end,$this->{section_id}) :
	$db->get_query("itemized sales by date",$start,$end);
    foreach my $data (@item) {
	my $ritem = new Modules::Finance::ReceivableItem(data=>$data);
	my $amt = $ritem->subtotal();
	$iglcode{$ritem->iglcode} += $amt;
	$glcode{$ritem->glcode} += $amt;
    }

    # next, do payments

    @item = $this->{section_id} ?
	$db->get_query("payments by date and section",$this->{section_id},$start,$end) :
	$db->get_query("payments by date",$start,$end);
    foreach my $data (@item) {
	my $pay = new Modules::Finance::Payment(data=>$data);
	my $amt = $pay->amount();
	$iglcode{$pay->iglcode} += $amt;
	$glcode{$pay->glcode} += $amt;
    }

    my @gldef = $share{DB}->fetch_all("glcode");
    my %gldef = &keywise("xcode",\@gldef);

    my $r = new ExSite::ReportBuilder(title => "GL Code Summaries - $start to $in->{date_end}");
    my @head = ("GL Code","Total","Description");
    $r->headers(\@head);
    foreach my $code (sort keys %glcode) {
	$r->push(
	    $code,
	    $ml->div(sprintf("%.02f",$glcode{$code}),{class=>"num"}),
	    $this->gl_description($code),
	    );
    }
    $r->foot($this->footer);
    if ($this->{input}{fmt}) {
	$this->export($r,$this->{input}{fmt});
	return undef;
    }
    my $out = $r->make();
    return $out;
}

sub gl_description {
    my ($this,$code) = @_;
    if (! exists $this->{gldef}) {
	my @gldef = $share{DB}->fetch_all("glcode");
	$this->{gldef} = &keywise("xcode",\@gldef);
	my @acctcode = $share{DB}->fetch_all("acctcode");
	$this->{acdef} = &keywise("acctcode_id",\@acctcode);
	my %paytype = reverse %Modules::Finance::Payment::method;
	$this->{paytype} = \%paytype;
    }

    # local override
    my $stat = $this->run_handler("gl_description",$code);
    return $stat if (defined $stat);

    # check for external glcode
    if (exists $this->{gldef}{$code}) {
	# defined external glcode
	return $this->{gldef}{$code}{description};
    }

    # internal code; make up a description
    my @out;
    my @type = (undef, "Sale", "Payment", "Refund", "Refund Payment");
    my @code = split /\./, $code;
    $code[0] =~ /^(\d)(\d+)$/;
    my $gltype = $type[$1];
    my ($acctcode_id,$acctcode);
    if ($1) {
	push @out, $gltype;
	my $subtype = $2;
	if ($gltype =~ /payment/i) {
	    push @out, $this->{paytype}{$subtype} || "unknown method";
	    if ($code[1]) {
		push @out, "account $code[1]";
	    }
	    elsif ($code[2]) {
		push @out, "invoice $code[2]";
	    }
	}
	else {
	    $acctcode_id = int($2);
	    $acctcode = $this->{acdef}{$acctcode_id}{code};
	    push @out, $this->{acdef}{$acctcode_id}{description} || "unknown type";
	    my $c = new ExSite::Content();
	    if ($code[1]) {
		my $gl_use_obj_label = $config{Finance}{gl}{label} || "EVENT|SALES|MERCH|DUES|MEMBER";
		if ($acctcode =~ /$gl_use_obj_label/) {
		    my $item = $c->get_content_obj($code[1]);
		    push @out, $item->label();
		}
		else {
		    push @out, "category $code[1]";
		}
	    }
	    if ($code[2]) {
		my $gl_use_obj_sublabel = $config{Finance}{gl}{sublabel} || "EVENT|SALES|MERCH";
		if ($acctcode =~ /$gl_use_obj_sublabel/) {
		    my $item = $c->get_content_obj($code[2]);
		    push @out, $item->label();
		}
		else {
		    push @out, "subcategory $code[2]";
		}
	    }
	}
    }
    return join(" - ",@out);
}

# sales is just activity with only receivables shown

sub report_sales {
    my $this = shift;
    my $db = $share{DB};
    my $in = $this->{input};
    my $out;
    my $start = $in->{date_start};
    my $t = new ExSite::Time($in->{date_end},"sql_date");
    $t->add(1,"day");
    my $end = $t->write("sql_date");

    # get reportable data
    my @data = @{$this->{receivables_by_date}};
    
    # get account codes to report
    my @acctcode = $share{DB}->fetch_all("acctcode");
    my %acctcode_id = keywise("acctcode_id",\@acctcode);
    my %acctcode_name = keywise("code",\@acctcode);

    my @show_acctcode;
    @show_acctcode = map { $_->{acctcode_id} } @acctcode;

    # report
    my $r = new ExSite::ReportBuilder();
    $r->title("Sales - $start to $in->{date_end}");
    my @acctinfo = @{$this->report_account_info()};
    my @head = ("Date",@acctinfo,"Invoice","Description","Amount");
    foreach my $icode (@show_acctcode) { 
	push @head, $acctcode_id{$icode}{code}; 
    }
    $r->headers(\@head);
    my $ncol = 6 + scalar @show_acctcode;
    my %total;
    foreach my $data (@data) {
	my @rdata;
	my $acct = new Modules::Finance::Account(id=>$data->{account_id});
	my $url = new ExSite::URI(uri=>"$config{server}{server}$config{server}{CGIpath}/$config{prog}{ctrlpanel}/Pay");
	if ($data->{type} eq "receivable") {
	    # receivable
	    next if ($data->{status} ne "active");
	    my $inv = new Modules::Finance::Receivable(data=>$data);
	    my $total = $inv->total();
	    $url->query(section_id=>$this->{section_id},acct=>$data->{account_id},inv=>$data->{receivable_id});
	    @rdata = (
		$data->{date},
		@{$this->report_account_info($data->{account_id},$url)},
#		      $ml->a($acct->name,{href=>"javascript:popup_large('".$url->write()."')"}),
		$ml->a($data->{receivable_id},{href=>"javascript:popup_large('".$url->write()."')"}),
		$inv->description(),
		$ml->div($total,{class=>"num"}),
		);
	    $total{Debit} += $total;
	    foreach (@show_acctcode) { 
		my $sub = $inv->subtotal($_);
		push @rdata, ($sub > 0 ? $ml->div($sub,{class=>"num"}) : undef);
		$total{$acctcode_id{$_}{code}} += $sub;
	    }
	    $r->push(@rdata);
	}
    }
    # totals
    my @acctfoot = map { undef } @acctinfo;
    my @rdata = (
	"TOTALS",
	@acctfoot,
	undef,
	undef,
	$ml->div(sprintf("%.02f",$total{Debit}),{class=>"num"}),
	);
    foreach (@show_acctcode) { 
	push @rdata, $ml->div(sprintf("%.02f",$total{$acctcode_id{$_}{code}}),{class=>"num"});
    }
    $r->push(@rdata);
    $r->foot($this->footer);
    if ($this->{input}{fmt}) {
	$this->export($r,$this->{input}{fmt});
	return undef;
    }
    return $r->make;
}

# revenues - actual payments received

sub report_revenues {
    my $this = shift;
    my $db = $share{DB};
    my $in = $this->{input};
    my $out;
    my $start = $in->{date_start};
    my $t = new ExSite::Time($in->{date_end},"sql_date");
    $t->add(1,"day");
    my $end = $t->write("sql_date");

    # get reportable data
    my @data = sort { $a->{date} cmp $b->{date} } (@{$this->{receivables_by_date}},@{$this->{payments_by_date}});
    
    # report
    my $r = new ExSite::ReportBuilder();
    $r->title("Revenues - $start to $in->{date_end}");
    my @acctinfo = @{$this->report_account_info()};
    my @head = ("Date",@acctinfo,"Invoice","Amount Received","Paid by","Identifier","GL code");
    $r->headers(\@head);
    my %total;
    foreach my $data (@data) {
	my @rdata;
	my $acct = new Modules::Finance::Account(id=>$data->{account_id});
	my $url = new ExSite::URI(uri=>"$config{server}{server}$config{server}{CGIpath}/$config{prog}{ctrlpanel}/Pay");
	if ($data->{payment_id}) {
	    # payment
	    next if ($data->{status} !~ /paid|received/);
	    my $payment = new Modules::Finance::Payment(data=>$data);
	    $url->query(section_id=>$this->{section_id},acct=>$data->{account_id},inv=>$data->{receivable_id});
	    @rdata = (
		$data->{date},
		@{$this->report_account_info($data->{account_id},$url)},
#		      $ml->a($acct->name,{href=>"javascript:popup_large('".$url->write()."')"}),
		$ml->a($data->{receivable_id},{href=>"javascript:popup_large('".$url->write()."')"}),
		$ml->div($data->{amount},{class=>"num"}),
		$data->{method},
		$data->{ident},
		$payment->glcode(),
		);
	    $total{Credit} += $data->{amount};
	    $r->push(@rdata);
	}
    }
    # totals
    my @acctfoot = map { undef } @acctinfo;
    my @rdata = (
	"TOTALS",
	@acctfoot,
	undef,
	$ml->div(sprintf("%.02f",$total{Credit}),{class=>"num"}),
	undef,
	undef,
	undef,
	);
    $r->push(@rdata);
    $r->foot($this->footer);
    if ($this->{input}{fmt}) {
	$this->export($r,$this->{input}{fmt});
	return undef;
    }
    return $r->make;
}

sub report_daily {
    my $this = shift;
    my $db = $share{DB};
    my $in = $this->{input};
    my $out;
    my $start = new ExSite::Time($in->{date_start},"iso_date");
    my $end = new ExSite::Time($in->{date_end},"iso_date");
    $end->add(1,"day");
    if ($start > $end) {
	return $this->error("Invalid date range.");
    }

    # get account codes to report
    my @acctcode = $share{DB}->fetch_all("acctcode");
    my %acctcode_id = keywise("acctcode_id",\@acctcode);
    my %acctcode_name = keywise("code",\@acctcode);

    my @show_acctcode;
    @show_acctcode = map { $_->{acctcode_id} } @acctcode;

    # get reportable data
    my @data = sort { $a->{date} cmp $b->{date} } (@{$this->{receivables_by_date}},@{$this->{payments_by_date}});
    
    # merge into single day row
    my %date;
    my %total;
    foreach my $data (@data) {
	$data->{date} =~ /^(\d\d\d\d-\d\d-\d\d) /;
	my $day = $1;
	if (! exists $date{$day}) {
	    $date{$day} = {};
	}
	my @rdata;
	if ($data->{payment_id}) {
	    # payment
	    next if ($data->{status} !~ /paid|received/);
	    $date{$day}{revenue} += $data->{amount};
	    $total{revenue} += $data->{amount};
	}
	elsif ($data->{type} eq "receivable") {
	    # receivable
	    next if ($data->{status} ne "active");
	    my $r = new Modules::Finance::Receivable(data=>$data);
	    my $total = $r->total;
	    $date{$day}{sale} += $total;
	    $total{sale} += $total;
	    foreach my $acode (sort keys %acctcode_id) { 
		my $sub = $r->subtotal($acode);
		$date{$day}{$acctcode_id{$acode}{code}} += $sub;
		$total{$acctcode_id{$acode}{code}} += $sub;
	    }
	}
	else {
	    # payable 
	    next if ($data->{status} ne "active");
	    my $r = new Modules::Finance::Receivable(data=>$data);
	    my $total = $r->total;
	    $date{$day}{sale} += $total;
	    $total{sale} -= $total;
	    foreach my $acode (sort keys %acctcode_id) {
		my $sub = $r->subtotal($acode);
		$date{$day}{$acctcode_id{$acode}{code}} -= $sub;
		$total{$acctcode_id{$acode}{code}} -= $sub;
	    }
	}
    }

    # report
    my (@chdata,@chlabel,@sales,@revenues); # charts
    my $r = new ExSite::ReportBuilder();
    $r->title("Daily Summary Statement $in->{date_start} to $in->{date_end}");
    my @head = ("Date");
    foreach my $icode (sort @show_acctcode) { 
	push @head, $acctcode_id{$icode}{code}; 
    }
    push @head, "Total Sales", "Revenues";
    $r->headers(\@head);
    my $ncol = 6 + scalar @show_acctcode;
    while ($start->diff($end->write("iso_date"),"iso_date") > 86400) {
	my $day = $start->write("iso_date");
	my @rdata = ($day);
	foreach my $acode (sort keys %acctcode_id) {
	    push @rdata, $this->num($date{$day}{$acctcode_id{$acode}{code}});
	}
	push @rdata, $this->num($date{$day}{sale});
	push @rdata, $this->num($date{$day}{revenue});
	push @sales,$date{$day}{sale};
	push @revenues,$date{$day}{revenue};
	$r->push(\@rdata);
	$start->add(1,"day");
    }
    # totals
    my @rdata = ("TOTALS");
    foreach my $acode (sort keys %acctcode_id) {
	my $code = $acctcode_id{$acode}{code};
	push @rdata, $this->num($total{$code});
	push @chdata, $total{$code};
	push @chlabel, $code;
    }
    push @rdata, $this->num($total{sale});
    push @rdata, $this->num($total{revenue});
    $r->push(\@rdata);

    # footer 
    $r->foot($this->footer);
    if ($this->{input}{fmt}) {
	$this->export($r,$this->{input}{fmt});
	return undef;
    }
    $out .= $r->make;
    $out .= $ml->div(
	$this->piechart(\@chdata,\@chlabel,"Sales by category").
	$this->barchart(\@sales,"Sales by day").
	$out .= $this->barchart(\@revenues,"Revenues by day"),
	{class=>"clearfix"}
	);
    return $out;
}

sub report_monthly {
    my $this = shift;
    my $db = $share{DB};
    my $in = $this->{input};
    my $out;
    my $start = new ExSite::Time($in->{date_start},"iso_date");
    my $end = new ExSite::Time($in->{date_end},"iso_date");
    $end->add(1,"day");
    if ($start > $end) {
	return $this->error("Invalid date range.");
    }

    # get account codes to report
    my @acctcode = $share{DB}->fetch_all("acctcode");
    my %acctcode_id = keywise("acctcode_id",\@acctcode);
    my %acctcode_name = keywise("code",\@acctcode);

    my @show_acctcode;
    @show_acctcode = map { $_->{acctcode_id} } @acctcode;

    # get reportable data
    my @data = sort { $a->{date} cmp $b->{date} } (@{$this->{receivables_by_date}},@{$this->{payments_by_date}});
    
    # merge into single month row
    my %date;
    my %total;
    foreach my $data (@data) {
	$data->{date} =~ /^(\d\d\d\d-\d\d)-/;
	my $month = $1;
	if (! exists $date{$month}) {
	    $date{$month} = {};
	}
	my @rdata;
	if ($data->{payment_id}) {
	    # payment
	    next if ($data->{status} !~ /paid|received/);
	    $date{$month}{revenue} += $data->{amount};
	    $total{revenue} += $data->{amount};
	}
	elsif ($data->{type} eq "receivable") {
	    # receivable
	    next if ($data->{status} ne "active");
	    my $r = new Modules::Finance::Receivable(data=>$data);
	    my $total = $r->total;
	    $date{$month}{sale} += $total;
	    $total{sale} += $total;
	    foreach my $acode (sort keys %acctcode_id) { 
		my $sub = $r->subtotal($acode);
		$date{$month}{$acctcode_id{$acode}{code}} += $sub;
		$total{$acctcode_id{$acode}{code}} += $sub;
	    }
	}
	else {
	    # payable 
	    next if ($data->{status} ne "active");
	    my $r = new Modules::Finance::Receivable(data=>$data);
	    my $total = $r->total;
	    $date{$month}{sale} += $total;
	    $total{sale} -= $total;
	    foreach my $acode (sort keys %acctcode_id) {
		my $sub = $r->subtotal($acode);
		$date{$month}{$acctcode_id{$acode}{code}} -= $sub;
		$total{$acctcode_id{$acode}{code}} -= $sub;
	    }
	}
    }

    # report
    my (@chdata,@chlabel,@sales,@revenues); # charts
    my $r = new ExSite::ReportBuilder();
    $r->title("Monthly Summary Statement $in->{date_start} to $in->{date_end}");
    my @head = ("Date");
    foreach my $icode (sort @show_acctcode) { 
	push @head, $acctcode_id{$icode}{code}; 
    }
    push @head, "Total Sales", "Revenues";
    $r->headers(\@head);
    my $ncol = 6 + scalar @show_acctcode;
    my $stm = $start->write("raw_year") * 12 + $start->write("raw_month");
    my $endm = $end->write("raw_year") * 12 + $end->write("raw_month");
    foreach my $imonth ($stm .. $endm) {
	my $m = $imonth % 12;
	my $y = int($imonth / 12);
	if ($m == 0) { $m = 12; $y--; }
	my $month = "$y-".sprintf("%02d",$m);
	my $t = new ExSite::Time($month."-01","iso_date");
	my $date = $t->write("month_long").", $y";
	my @rdata = ($date);
	foreach my $acode (sort keys %acctcode_id) {
	    push @rdata, $this->num($date{$month}{$acctcode_id{$acode}{code}});
	}
	push @rdata, $this->num($date{$month}{sale});
	push @rdata, $this->num($date{$month}{revenue});
	push @sales,$date{$month}{sale};
	push @revenues,$date{$month}{revenue};
	$r->push(\@rdata);
    }
    # totals
    my @rdata = ("TOTALS");
    foreach my $acode (sort keys %acctcode_id) {
	my $code = $acctcode_id{$acode}{code};
	push @rdata, $this->num($total{$code});
	push @chdata, $total{$code};
	push @chlabel, $code;
    }
    push @rdata, $this->num($total{sale});
    push @rdata, $this->num($total{revenue});
    $r->push(\@rdata);

    # footer 
    $r->foot($this->footer);
    if ($this->{input}{fmt}) {
	$this->export($r,$this->{input}{fmt});
	return undef;
    }
    $out .= $r->make;
    $out .= $ml->div(
	$this->piechart(\@chdata,\@chlabel,"Sales by category").
	$this->barchart(\@sales,"Sales by month").
	$this->barchart(\@revenues,"Revenues by month"),
	{class=>"clearfix"}
	);
### FIXME: combine 2 charts into 1
    return $out;
}

sub num {
    my ($this,$n) = @_;
    return $n > 0 ?
	$ml->div(sprintf("%.02f",$n),{class=>"num"}) : 
	undef;
}

sub footer {
    my $this = shift;
    my $out = "Report generated ".localtime;
    $out .= " &bull; ";
    $out .= $ml->a("Excel",{href=>$this->link(fmt=>"excel",date_start=>$this->{input}{date_start},date_end=>$this->{input}{date_end},type=>$this->{input}{type})});
    $out .= " &bull; ";
    $out .= $ml->a("CSV",{href=>$this->link(fmt=>"csv",date_start=>$this->{input}{date_start},date_end=>$this->{input}{date_end},type=>$this->{input}{type})});
    $out .= " &bull; ";
    $out .= $ml->a("Print",{href=>"javascript:print()"});
    return $out;
}

sub acctcode_selector {
    my $this = shift;
    my $opt = $ml->option("All purchase types",{value=>""});
    foreach my $acctcode ($share{DB}->fetch_all("acctcode")) {
	my $optopt = {value=>$acctcode->{acctcode_id}};
	if ($this->{input}{acctcode} == $acctcode->{acctcode_id}) {
	    $optopt->{selected} = undef;
	}
	$opt .= $ml->option($acctcode->{code}." - ".$acctcode->{description},$optopt);
    }
    return $ml->form(
	"Show ".$ml->select($opt,{name=>"acctcode",onchange=>"submit()"}).
	$ml->input(undef,{type=>"hidden",name=>"date_start",value=>$this->{input}{date_start}}).
	$ml->input(undef,{type=>"hidden",name=>"date_end",value=>$this->{input}{date_end}}).
	$ml->input(undef,{type=>"hidden",name=>"type",value=>$this->{input}{type}}),
	{method=>"get",action=>$this->link()}
	);
}

sub piechart {
    my ($this,$data,$label,$title) = @_;
    # scale data
    my $max = 0;
    foreach my $d (@$data) {
	$max = $d if ($d > $max);
    }
    my @scaled_data;
    if ($max > 0) {
	foreach my $d (@$data) {
	    push @scaled_data, int(($d / $max) * 1000)/10;
	}
    }
    else {
	# just zeroes?
	@scaled_data = @$data;
    }
    my $chdata = join(",",@scaled_data);
    my $chlabel = join("|",@$label);
#    return $ml->p(
#                  ($title ? $title.$ml->br : "").
#                  $ml->img(undef,{src=>"http://chart.apis.google.com/chart?cht=p3&chd=t:${chdata}&chs=250x100&chl=$chlabel"}),
#                  {class=>"chart"}
#                  );
    return $ui->Figure(
	img=>"http://chart.apis.google.com/chart?cht=p3&chd=t:${chdata}&chs=250x100&chl=$chlabel",
	alt=>"sales breakdown",
	title=>$title,
	float=>"left",
	);
}

sub barchart {
    my ($this,$data,$title) = @_;
    return scalar @$data > 12 ? 
	$this->chart("lc",$data,$title) :  # too many data points for bars
	$this->chart("bvs",$data,$title);
}

sub linechart {
    my ($this,$data,$title) = @_;
    return $this->chart("lc",$data,$title);
}

sub chart {
    my ($this,$type,$data,$title) = @_;
    return undef if (@$data < 2);
    # scale data
    my $max = 0;
    foreach my $d (@$data) {
	$max = $d if ($d > $max);
    }
    my @scaled_data;
    if ($max > 0) {
	foreach my $d (@$data) {
	    push @scaled_data, int(($d / $max) * 1000)/10;
	}
    }
    else {
	# just zeroes?
	@scaled_data = @$data;
    }
    my $chdata = join(",",@scaled_data);
#    return $ml->p(
#                  ($title ? $title.$ml->br : "").
#                  $ml->img(undef,{src=>"http://chart.apis.google.com/chart?cht=$type&chd=t:$chdata&chs=400x200"}),
#                  {class=>"chart"}
#                  );
    return $ui->Figure(
	img=>"http://chart.apis.google.com/chart?cht=$type&chd=t:$chdata&chs=400x200",
	alt=>"sales chart",
	title=>$title,
	caption=>$title,
	float=>"left",
	);
}

sub setup_queries {
    my $this = shift;
    my $db = $share{DB};
    $db->set_query(
		   "receivables by date",
		   sql => "select r.*,a.name from receivable r, account a where r.account_id=a.account_id and r.date > ? and r.date < ?",
		   param=>2,
		   mode=>"r",
		   keys=>["receivable","account"],
		   );
    $db->set_query(
		   "receivables by date and section",
		   sql => "select r.*,a.name from receivable r, account a left join user m on m.uid=a.uid where r.account_id=a.account_id and (a.section_id=?) and r.date > ? and r.date < ?",
		   param=>4,
		   mode=>"r",
		   keys=>["receivable","account"],
		   );
    $db->set_query(
		   "payments by date",
		   sql => "select p.*,a.name from payment p, account a where p.account_id=a.account_id and p.date > ? and p.date < ?",
		   param=>2,
		   mode=>"r",
		   keys=>["payment","account"],
		   );
    $db->set_query(
		   "payments by date and section",
		   sql => "select p.*,a.name from payment p, account a left join user m on m.uid=a.uid where p.account_id=a.account_id and (a.section_id=?) and p.date > ? and p.date < ?",
		   param=>3,
		   mode=>"r",
		   keys=>["payment","account"],
		   );
    $db->set_query(
		   "itemized payments by date",
		   sql => "select a.account_id,a.name,r.date,ri.*,ac.code,p.amount payment from account a,receivable r,payment p,receivable_item ri left join acctcode ac on ri.acctcode_id=ac.acctcode_id where r.account_id=a.account_id and ri.receivable_id=r.receivable_id and p.receivable_id=r.receivable_id and p.status='paid' and r.status='active' and ri.status != 'deleted' and r.date > ? and r.date < ? group by ri.receivable_item_id order by r.receivable_id",
		   param=>2,
		   mode=>"r",
		   keys=>["payment","account","receivable","receivable_item","acctcode"],
		   );
    $db->set_query(
		   "itemized payments by date and section",
		   sql => "select a.account_id,a.name,r.date,ri.*,ac.code,p.amount payment from account a,receivable r,payment p,receivable_item ri left join acctcode ac on ri.acctcode_id=ac.acctcode_id where r.account_id=a.account_id and ri.receivable_id=r.receivable_id and p.receivable_id=r.receivable_id and p.status='paid' and r.status='active' and ri.status != 'deleted' and r.date > ? and r.date < ? and a.section_id=? group by ri.receivable_item_id order by r.receivable_id",
		   param=>3,
		   mode=>"r",
		   keys=>["payment","account","receivable","receivable_item","acctcode"],
		   );
    $db->set_query(
		   "itemized sales by date",
		   sql => "select a.account_id,a.name,r.date,ri.*,ac.code from account a,receivable r,receivable_item ri left join acctcode ac on ri.acctcode_id=ac.acctcode_id where r.account_id=a.account_id and ri.receivable_id=r.receivable_id and r.status='active' and ri.status != 'deleted' and r.date > ? and r.date < ? order by r.receivable_id",
		   param=>2,
		   mode=>"r",
		   keys=>["account","receivable","receivable_item","acctcode"],
		   );
    $db->set_query(
		   "itemized sales by date and section",
		   sql => "select a.account_id,a.name,r.date,ri.*,ac.code from account a,receivable r,receivable_item ri left join acctcode ac on ri.acctcode_id=ac.acctcode_id where r.account_id=a.account_id and ri.receivable_id=r.receivable_id and r.status='active' and ri.status != 'deleted' and r.date > ? and r.date < ? and a.section_id=? order by r.receivable_id",
		   param=>3,
		   mode=>"r",
		   keys=>["account","receivable","receivable_item","acctcode"],
		   );
}

1;
