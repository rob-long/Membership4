package Modules::Adjustment;

#----------------------------------------------------------------------------
#
#   Copyright (C) 2011-2017 - Exware Solutions, Inc.  http://www.exware.com
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
#  Configure taxes, discounts, and other surcharges.
#
#----------------------------------------------------------------------------

### TODO:
### - minimum charge, eg. minimum S&H charge
### - minimum cost, eg. minimum item cost before you get discount

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
use ExSite::UI;
use Modules::Finance::Surcharge;

# recommended base class for plug-in modules
use Modules::BaseDCD;

use vars qw(@ISA $ml $ui $template);
@ISA = qw(Modules::BaseDCD);

sub write {
    my ($this,$options) = @_;
    return undef;
}

sub ioctl {
    my $this = shift;
    $_ = shift;           # $_ is the ioctl request

    if (/ModuleName/) {
	return "Billing Adjustments";
    }
    elsif (/ModuleInfo/) {
	return "Configure discounts, taxes, and other surcharges.";
    }
    elsif (/Category/) {
	my %cat = map { $_ => 1 } @{$config{webtop}{categories}};
	return exists $cat{Ecommerce} ? "Ecommerce" : "Applications";
    }
    elsif (/Dependencies/) {
	return ["Finance"];
    }
    elsif (/Access/) {
	return 3;
    }
    elsif (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/Tips/) {
	return \&tips;
    }    
}

#----------------------------------------------------------------------------
# Everything after this point consists of private methods.

# ctrl_panel() generates the contents of the administrator control panel

sub ctrl_panel {
    my $this = shift;
    my $out;
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    $this->{section_id} = $this->get_section_id;
    if (! $this->{section_id}) { 
	$out .= $this->set_section_id(); 
	return $out if (! $share{DB}->is_admin);
    }

    if ($this->{section_id} || $this->{input}{scid}) {
	my @path = ( {url=>$this->link(cmd=>undef,section_id=>undef,scid=>undef),
		      label=>"Top"} );
	if ($this->{section_id}) {
	    my $s = new ExSite::Section(id=>$this->{section_id});
	    push @path, {url=>$this->link(cmd=>undef,scid=>undef), label=>$s->get_my("title")};
	}
	if ($this->{input}{scid}) {
	    my $s = new Modules::Finance::Surcharge(id=>$this->{input}{scid});
	    push @path, {url=>$this->link(cmd=>undef), label=>$s->name};
	}
	$out = $ui->PathBar(links=>\@path);
    }

    my @tab = (
	{label=>"Adjustments",url=>$this->link(scid=>undef,cmd=>undef)},
	{label=>"+ Tax",url=>$this->link(scid=>undef,cmd=>"tax")},
	{label=>"+ Coupon Code",url=>$this->link(scid=>undef,cmd=>"coupon")},
	{label=>"+ Other",url=>$this->link(cmd=>undef,scid=>"0")},
	{label=>"Sales Codes",url=>$this->link(scid=>undef,cmd=>"acctcode")},
	);

    my ($pane,$thistab);
    if ($this->{input}{cmd} =~ /^acctcode/) {
	$pane = $this->acctcodes();
	$thistab = 4;
    }
    elsif ($this->{input}{cmd} eq "coupon") {
	$pane = $this->coupon_code();
	$thistab = 2;
    }
    elsif ($this->{input}{cmd} eq "tax") {
	$pane = $this->tax();
	$thistab = 1;
    }
    elsif (exists $this->{input}{scid}) {
	$pane = $this->do_surcharge($this->{input}{scid});
	$thistab = $this->{input}{scid} eq "0" ? 3 : 0;
    }
    else {
	$pane = $this->list_surcharges();
	$thistab = 0;
    }
    $out .= $ui->TabBox(tabs=>\@tab, thistab=>$thistab, pane=>$pane);
    return $out;
}


sub list_surcharges {
    my $this = shift;
    my %acctcode = &keywise("acctcode_id",scalar $share{DB}->fetch_all("acctcode"));
    my @sc = $share{DB}->fetch_all("surcharge","surcharge_id");
    my $r = new ExSite::ReportBuilder(title=>"Adjustments");
    $r->nodata("No surcharges have been defined.");
    $r->headers("Adjustment",
		"Type",
		"Apply to",
		"Apply if",
		"Buyer location",
		"Min. Quantity",
		"Coupon Code",
		"Cost");
    $r->foot("Click the surcharge name to manage it.");
    foreach my $sc (@sc) {
	next if ($this->{section_id} && $this->{section_id} != $sc->{section_id});
	my $surcharge = new Modules::Finance::Surcharge(data=>$sc);
	my $status = $surcharge->is_active ? "active" : "inactive";
	my $apply_to = $sc->{apply_to} ? $acctcode{$sc->{apply_to}}{code} :
	    $sc->{apply_to_objtype} . " " . $sc->{apply_to_objid};
	my $apply_if = $sc->{apply_if} ? $acctcode{$sc->{apply_if}}{code} :
	    $sc->{apply_if_objtype} . " " . $sc->{apply_if_objid};
	my $loc = $sc->{provstate} ? $sc->{provstate} . " " : "";
	$loc .= $sc->{country};
	my @cost;
	if ($sc->{percent}) { push @cost, $sc->{percent}."%"; }
	if ($sc->{peritem} != 0.00) { push @cost, $config{report}{currency_char}.$sc->{peritem}."/item"; }
	if ($sc->{perproduct} != 0.00) { push @cost, $config{report}{currency_char}.$sc->{perproduct}."/product"; }
	if ($sc->{perorder} != 0.00) { push @cost, $config{report}{currency_char}.$sc->{perorder}."/order"; }
	my $scclass = $sc->{status} eq "inactive" ? "inactive" : "active";
	$r->push($ml->a($sc->{name},{href=>$this->link(scid=>$sc->{surcharge_id}),class=>$scclass}),
		 $acctcode{$sc->{treat_as}}{code},
		 $apply_to,
		 $apply_if,
		 $loc,
		 $sc->{min_quantity},
		 $sc->{code},
		 join(", ",@cost),
		 );
    }
    return $r->make();
}

sub do_surcharge {
    my ($this,$scid) = @_;
    my $out;
    my $sc = new Modules::Finance::Surcharge(id=>$scid);
    if ($this->{input}{cmd} eq "del") {
	$sc->delete();
	$ml->location($this->link(scid=>undef,cmd=>undef,__plaintext=>1));
	return;
    }
    $sc->load();
    my $db = $share{DB};
    $db->set_action($scid ? "update" : "insert");
    my $in = new ExSite::Input;
    my $post = $in->post;
    if (scalar keys %$post > 0) {
	my %data = $db->parse_parts(%$post);
	if ($data{apply_to} == $data{apply_if}) {
	    $out .= $ui->ErrorBox(title=>"Warning",pane=>"You set ".$ml->em("Apply to")." and ".$ml->em("Apply if they bought")." to the same purchase type. This setting does not make sense, and will be ignored.");
	}
	if ($scid) {
	    my $stat = $db->update("surcharge",\%data);
	    if ($stat) {
		$out .= $ml->div($stat, {class=>"error"});
	    }
	    else {
		$out .= $ml->p("Updated surcharge.");
		$ml->location($this->link(__plaintext=>1,scid=>undef,cmd=>undef));
		return $out;
	    }
	    $sc->load; # reload so form populates correctly
	}
	else {
	    if ($data{discount}) {
		if ($data{discount} =~ /^(\d+)%$/) {
		    $data{percent} = - $1;
		}
		elsif ($data{discount} =~ /^(\d+)(\.\d\d)?$/) {
		    $data{perorder} = - $data{discount};
		}
		else {
		    return $this->error("Invalid discount.")
		}
		delete $data{discount};
		# set treat_as = apply_to
		$data{treat_as} = $data{apply_to};
	    }
	    my $newid = $db->insert("surcharge",\%data);
	    if ($newid) {
		$out .= $ml->p("Added new surcharge.");
		$ml->location($this->link(__plaintext=>1,scid=>undef,cmd=>undef));
		return $out;
	    }
	    else {
		$out .= $ml->div($db->show_diagnostics("error","html"), {class=>"error"});
	    }
	}
    }

    $db->set_action($scid ? "update" : "insert");
    my $form = $db->form;
    $config{form}{max_cols} = 30;
    $share{DB}->input_record({
	table=>"surcharge",
	record=>$scid,
	data=> $scid ? $sc->get() : { section_id=>$this->{section_id} },
	simplename=>1});
    $form->template($this->sc_template);
    $out .= $form->make();
    if ($scid) {
	$out .= $ml->p($ui->Button(label=>"Delete this surcharge",url=>$this->link(cmd=>"del"),confirm=>"Really delete this surcharge?"));
    }
    return $out;
}

sub sc_template {
    my $this = shift;
    my $br = $ml->br;
    my $out = $ml->table({
	caption => "Adjustment Info",
	tbody => [ 
	    [ "[[name:prompt]]${br}[[name:input]]", "[[status:prompt]]${br}[[status:input]]" ],
	    [ "[[treat_as#key:prompt]]${br}[[treat_as#key:input]]", "[[section_id#key:prompt]]${br}[[section_id#key:input]]" ],
	    [ "[[code:prompt]]${br}[[code:input]]" ]
	]
	},{class=>"SurchargeSetup"}).
	$ml->table({
	    caption => "Cost Adjustments",
	    tbody => [ 
		[ "[[percent:prompt]]${br}[[percent:input]]", 
		  "[[peritem:prompt]]${br}[[peritem:input]]",
		  "[[persize:prompt]]${br}[[persize:input]]",
		  "[[perproduct:prompt]]${br}[[perproduct:input]]",
		  "[[perorder:prompt]]${br}[[perorder:input]]"
		]
	    ]
	},{class=>"SurchargeSetup"}).
	$ml->table({
	    caption => "This adjustment applies to:",
	    tbody => [ 
		[ "[[apply_to#key:prompt]]${br}[[apply_to#key:input]]" ],
		[
		  "[[apply_to_objtype:prompt]]${br}[[apply_to_objtype:input]]",
		  "[[apply_to_objid:prompt]]${br}[[apply_to_objid:input]]"
		],
		[ "[[apply_to_gl:prompt]]${br}[[apply_to_gl:input]]" ]
	    ]
	},{class=>"SurchargeSetup"}).
	$ml->table({
	    caption => "This adjustment applies when certain other items are bought:",
	    tbody => [ 
		[ "[[apply_if#key:prompt]]${br}[[apply_if#key:input]]" ],
		[ "[[apply_if_objtype:prompt]]${br}[[apply_if_objtype:input]]",
		  "[[apply_if_objid:prompt]]${br}[[apply_if_objid:input]]"
		],
		[ "[[apply_if_gl:prompt]]${br}[[apply_if_gl:input]]" ]
	    ]
	},{class=>"SurchargeSetup"}).
	$ml->table({
	    caption => "This adjustment applies only in these regions:",
	    tbody => [ 
		[ 
		  "[[provstate:prompt]]${br}[[provstate:input]]",
		  "[[country:prompt]]${br}[[country:input]]"
		]
	    ]
	},{class=>"SurchargeSetup"}).
	$ml->table({
	    caption => "This adjustment only applies during this time period:",
	    tbody => [ 
		[ 
		  "[[valid_from:prompt]]${br}[[valid_from:input]]",
		  "[[valid_to:prompt]]${br}[[valid_to:input]]"
		]
	    ]
	},{class=>"SurchargeSetup"}).
	$ml->table({
	    caption => "Minimums for this adjustment to take effect",
	    tbody => [ 
		[ "[[min_quantity:prompt]]${br}[[min_quantity:input]]", 
		  "[[min_size:prompt]]${br}[[min_size:input]]", 
		  "[[min_value:prompt]]${br}[[min_value:input]]", 
		]
	    ]
	},{class=>"SurchargeSetup"});
    return $out;
}

sub tax { 
    my $this = shift;
    my @acctcode = map { { text=>$_->{description}, value=>$_->{acctcode_id} } } $share{DB}->fetch_all("acctcode");
    my $taxval;
    foreach my $ac (@acctcode) {
	if ($ac->{text} =~ /tax/i) { 
	    $taxval = $ac->{value};
	    last;
	}
    }
    my $out;
    $out .= $ui->HelpBox(
	title=>"Tips",
	pane=>"The tax region is a list of 2-letter province/state codes, separated 
by the bar character, '|'. For example: ".$ml->code("BC|AB|SK").". You can also 
specify the country. The purchaser must be from that region and country to be 
eligible for the tax.",
	float=>"right",
	width=>"300px",
	);
    $out .= $ml->h1("Setup new tax rule:");
    my $f = new ExSite::FormBuilder(action=>$this->link(cmd=>undef,scid=>"0"));
    $f->input(prompt=>"Tax name",type=>"text",name=>"name",required=>1);
    $f->input(prompt=>"Tax region",type=>"text",name=>"provstate");
    $f->input(prompt=>"Tax country",type=>"text",name=>"country");
    $f->input(prompt=>"Tax rate (%)",type=>"text",name=>"percent",required=>1);
    $f->input(prompt=>"Applies to",type=>"select",name=>"apply_to",options=>\@acctcode,nullvalue=>"-- select --",required=>1);
    $f->input(prompt=>"Treat as",type=>"select",name=>"treat_as",options=>\@acctcode,nullvalue=>"-- select --",value=>$taxval,required=>1);
    if ($this->{section_id}) {
	$f->input(type=>"hidden",name=>"section_id",value=>$this->{section_id});
    }
    $out .= $f->make();
    $out .= $ml->br;
    return $out;
}

sub coupon_code { 
    my $this = shift;
    my @acctcode = map { { text=>$_->{description}, value=>$_->{acctcode_id} } } $share{DB}->fetch_all("acctcode");
    my $out;
    $out .= $ui->HelpBox(
	title=>"Tips",
	pane=>"The discount can be a percentage (eg. ".$ml->code("50%")." meaning 50 percent off) or an absolute amount (eg. ".$ml->code("100")." meaning \$100.00 off).",
	float=>"right",
	width=>"300px",
	);
    $out .= $ml->h1("Setup new coupon code:");
    my $f = new ExSite::FormBuilder(action=>$this->link(cmd=>undef,scid=>"0"));
    $f->input(prompt=>"Name/description for receipt",type=>"text",name=>"name",required=>1);
    $f->input(prompt=>"Coupon code",type=>"text",name=>"code",size=>20,required=>1);
    $f->input(prompt=>"Discount",type=>"text",name=>"discount",required=>1);
    $f->input(prompt=>"Applies to",type=>"select",name=>"apply_to",options=>\@acctcode,nullvalue=>"-- select --",required=>1);
#    $f->input(prompt=>"Treat as",type=>"select",name=>"treat_as",options=>\@acctcode,nullvalue=>"-- select --",required=>1);
    if ($this->{section_id}) {
	$f->input(type=>"hidden",name=>"section_id",value=>$this->{section_id});
    }
    $out .= $f->make();
    $out .= $ml->br;
    return $out;
}

sub tips {
    my $this = shift;
    $this->{section_id} = $this->get_section_id;    
    $ml = &get_obj("ML");
    my %acctcode = &keywise("acctcode_id",scalar $share{DB}->fetch_all("acctcode"));
    my @sc = $share{DB}->fetch_all("surcharge","surcharge_id");
    my $r = new ExSite::ReportBuilder(title=>"Surcharges");
    $r->nodata("No surcharges have been defined.");
    $r->headers("Adjustment","Location","Cost","Apply To");
    
    # report taxes
    my $loc_index;
    foreach my $sc (@sc) {
	next if ($this->{section_id} && $this->{section_id} != $sc->{section_id});
	my $surcharge = new Modules::Finance::Surcharge(data=>$sc);
	my $status = $surcharge->is_active ? "active" : "inactive";
	next if ($status eq "inactive");
	my $apply_to = $sc->{apply_to} ? $acctcode{$sc->{apply_to}}{code} :
	    $sc->{apply_to_objtype} . " " . $sc->{apply_to_objid};
	my $apply_if = $sc->{apply_if} ? $acctcode{$sc->{apply_if}}{code} :
	    $sc->{apply_if_objtype} . " " . $sc->{apply_if_objid};
	my $loc = $sc->{provstate} ? $sc->{provstate} . " " : "";
	$loc .= $sc->{country};
	my @cost;
	if ($sc->{percent}) { push @cost, $sc->{percent}."%"; }
	if ($sc->{peritem} != 0.00) { push @cost, $config{report}{currency_char}.$sc->{peritem}."/item"; }
	if ($sc->{perproduct} != 0.00) { push @cost, $config{report}{currency_char}.$sc->{perproduct}."/product"; }
	if ($sc->{perorder} != 0.00) { push @cost, $config{report}{currency_char}.$sc->{perorder}."/order"; }
	my $cost = join(", ",@cost);
	if (my $apply_to_list = $loc_index->{$loc}{$sc->{name}}{$cost}) {
		push(@$apply_to_list,$apply_to);
		$loc_index->{$loc}{$sc->{name}}{$cost} = $apply_to_list;
	} else {
		$loc_index->{$loc}{$sc->{name}}{$cost} = [$apply_to];
	}
	}
	foreach my $loc (keys %$loc_index) {
		my @names = keys %{$loc_index->{$loc}};
		foreach my $name (@names) {
			# assume we only have 1 cost per location set+name
			my $cost = (keys %{$loc_index->{$loc}{$name}})[0];
			my $apply_to_list = $loc_index->{$loc}{$name}{$cost};
			my $location = $loc;
			$location  =~ s/\|/,/g;
			if ($apply_to_list) {
			$r->push($name,$location,$cost,join(", ",sort @$apply_to_list));
			}
		}
	}
	return $ml->h2("Discounts, taxes, and other surcharges") . $r->make();
}

sub acctcodes {
    my $this = shift;
    return $this->warn("You do not have sufficient permissions to setup accounting codes.") if (! $share{DB}->is_admin);
    my $out;
    my $input = new ExSite::Input;
    my $post = $input->post();
    my $cmd = $this->{input}{cmd};
    if ($cmd =~ /edit/) {
	if (keys %$post > 0) {
	    $out .= $share{DB}->do();
	}
	else {
	    $out .= $share{DB}->make(table=>"acctcode",record=>$this->{input}{aid},action=>$this->link());
	    return $out;
	}
    }
    elsif ($cmd =~ /add/) {
	if (keys %$post > 0) {
	    $out .= $share{DB}->do();
	}
	else {
	    $out .= $share{DB}->make(table=>"acctcode",record=>undef,action=>$this->link());
	    return $out;
	}
    }
    elsif ($cmd =~ /del/) {
	$share{DB}->trash_key("acctcode",$this->{input}{aid});
    }

    my $r = new ExSite::ReportBuilder(title=>"Sales Codes");
    $r->headers("ID","Code","Description","Options");
    $r->tools($ui->fatool("add",url=>$this->link(cmd=>"acctcode_add")));
    foreach my $acctcode ($share{DB}->fetch_all("acctcode","code")) {
	$r->push(
	    $acctcode->{acctcode_id},
	    $acctcode->{code},
	    $acctcode->{description},
	    $ui->fatool("edit",url=>$this->link(cmd=>"acctcode_edit",aid=>$acctcode->{acctcode_id})).
	    $ui->fatool("delete",confirm=>'DO NOT DELETE SALES CODES THAT ARE IN USE! It will destroy your sales history. Are you sure you want to ontinue?',url=>$this->link(cmd=>"acctcode_del",aid=>$acctcode->{acctcode_id}),tone=>"bad")
	    );
    }
    $out .= $r->make();
    return $out;
}

1;
