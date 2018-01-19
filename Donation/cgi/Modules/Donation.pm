package Modules::Donation;

#----------------------------------------------------------------------------
#
#   Copyright (C) 2010 - Exware Solutions, Inc.  http://www.exware.com
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
#  Usage:
#
#  Add/process a form to solicit a donation:
#
#      <!--&Donation()-->
#
#  The donation is added to the shopping cart.
#
#  To include a description for the donation, put the description in the
#  parameters:
#
#      <!--&Donation(scholarship fund contribution)-->
#
#----------------------------------------------------------------------------

use strict;

# useful kernel libs; you can/should remove any of these that are not needed

use ExSite::Config;          # required
use ExSite::ML;              # optional markup-language generation
use ExSite::ReportBuilder;   # optional report generation
use ExSite::Time;
use ExSite::ObjectList;
use Modules::Finance::Receivable;

# recommended base class for plug-in modules

use Modules::BaseDCD;

# declare package globals

use vars qw(@ISA $ml); 

# define our class inheritance

@ISA = qw(Modules::BaseDCD); # inherit from this base class

sub write {
    my ($this,$options) = @_;
    my $out;
    $ml = &get_obj("ML");
    $this->setup_querylib();
    if ($options eq "gauge") {
        $out = $this->fundraising_gauge();
    }
    elsif ($this->{input}{donation}) {
        if ($this->{input}{donation} =~ /^\s*?\$?(\d+(.\d\d)?)$/) {
            my $amt = $1;
            if ($amt) {
                my $cartargs = "cart=add&item=Donation&cost=$amt";
                if ($config{Donation}{acctcode}) { 
                    $cartargs .= "&acctcode_id=$config{Donation}{acctcode}";
                }
                if ($options) { 
                    $cartargs .= "&description=$options";
                }
                $out .= "<!--&Pay($cartargs)-->";
            }
        }
        else {
            $out .= $this->error("Invalid donation amount: $this->{input}{donation}. Please enter a dollar amount, and do not include commas.");
            $out .= $this->donation_form();
        }
    }
    else {
        $out .= $this->donation_form();
    }
    return $out;
}

sub donation_form {
    my $this = shift;
    my $f = new ExSite::FormBuilder(action=>$this->link(),method=>"post");
    $f->template($ml->div("[[donation:prompt]]: [[donation:input]] [[buttons]]", {class=>"Donation"}));
    $f->input(name=>"donation",type=>"text",prompt=>$msg{"Donation Amount"},
              size=>10,required=>1,value=>$this->{input}{donation});
    $f->set("buttons",$ml->input(undef,{type=>"submit",value=>"Donate"}));
    return $f->make();
}

# ioctl method (used by ExSite to query the module for its functionality)

sub ioctl {
    my $this = shift;
    $_ = shift;           # $_ is the ioctl request

    if (/isRestricted/) {
        return 0;
    }
    elsif (/ModuleName/) {
        return "Donations";
    }
    elsif (/ControlPanel/) {
        return \&ctrl_panel;
    }
    elsif (/Summary/) {
        return \&summary;
    }
    elsif (/Dependencies/) {
        return "Finance";
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

    my $section_id = $this->get_section_id();
    if (! $section_id) {
        return $this->set_section_id();
    }
    $this->setup_querylib();
    
    # declare a markup generator
    $ml = &get_obj("ML");
    
    my @rcvblstat = split /\|/, $share{DB}{map}->regexp("list:receivable_status");
    my $out = $this->fundraising_gauge();
    $out .= $ml->p(
        $ml->form("Find donations from ".
            $ml->select([
                [ "option", "last 24 hours", { value=>1 } ],
                [ "option", "last 7 days", { value=>7 } ],
                [ "option", "last 30 days", { value=>30 } ],
                [ "option", "last 60 days", { value=>60 } ],
                [ "option", "last 90 days", { value=>90 } ],
            ],
                {name=>"age"}).
            $ml->input(undef,{name=>"section_id",type=>"hidden",value=>$section_id}).
            $ml->button("Submit",{type=>"submit"})
        )
    );
    my $time = new ExSite::Time;
    my $dateto = $this->{input}{dateto} || $time->write("sql_date");
    $time->add(-2,"weeks");
    my $datefrom = $this->{input}{datefrom} || $time->write("sql_date");
    $out .= $ml->p(
                   $ml->form("Find donations from ".
                             $ml->input(undef,{name=>"datefrom",type=>"text",size=>10,value=>$datefrom}).
                             " to ".
                             $ml->input(undef,{name=>"dateto",type=>"text",size=>10,value=>$dateto}).
                             $ml->input(undef,{name=>"section_id",type=>"hidden",value=>$section_id}).
                             $ml->button("Submit",{type=>"submit"})
                             )
                   );
    $out .= $ml->p(
                   $ml->form("Find donations from people named ".
                             $ml->input(undef,{name=>"name",type=>"text",size=>10,value=>$this->{input}{name}}).
                             $ml->input(undef,{name=>"section_id",type=>"hidden",value=>$section_id}).
                             $ml->button("Search",{type=>"submit"})
                             )
                   );
    $out .= $ml->p(
        $ml->form("Find receipt number ".
            $ml->input(undef,{type=>"text",size=>10,name=>"inv"}).
                  $ml->input(undef,{name=>"section_id",type=>"hidden",value=>$section_id}).
                  $ml->button("Lookup",{type=>"submit"})
        )
    );
    if ($this->{input}{inv}) {
        $out = $this->show_donation();
    }
    else {
        my $r = new ExSite::ReportBuilder(title=>"Donations");
        $r->nodata("No donations found.");
        $r->headers(["Receipt ID","Date","From","Donation Subtotal","Options"]);
        my @don;
        if ($this->{input}{age}) {
            my $time = new ExSite::Time();
            $time->add(-($this->{input}{age}),"days");
            my $sqldate = $time->write("sql_timestamp");
            @don = $share{DB}->get_query("recent donations",$section_id,$section_id,$config{Donation}{acctcode},$sqldate);
        }
        elsif ($this->{input}{datefrom} && $this->{input}{dateto}) {
            @don = $share{DB}->get_query("donations in period",$section_id,$section_id,$config{Donation}{acctcode},$this->{input}{datefrom},$this->{input}{dateto});
        }
        elsif ($this->{input}{name}) {
            @don = $share{DB}->get_query("donations from name",$section_id,$section_id,$config{Donation}{acctcode},"%".$this->{input}{name}."%");
        }
        my $dlist = new ExSite::ObjectList(type=>"receivable_item",list=>\@don);
        while (my $d = $dlist->next()) {
            my $subtotal = $d->subtotal();
            next if ($subtotal == 0.00);
            my $inv = $d->receivable();
            $r->push(
                     $inv->id(),
                     $inv->showdata("date"),
                     $inv->showdata("account_id")." (Account ".$inv->getdata("account_id").")",
                     $subtotal,
                     $ml->a("view",{href=>$this->link(inv=>$inv->id,age=>undef,datefrom=>undef,dateto=>undef)})
                     );
        }
        $out .= $r->make();
    }
    
    return $out;
}

sub show_donation {
    my $this = shift;
    my $inv = new Modules::Finance::Receivable(id=>$this->{input}{inv});
    my $out .= $ml->h1($inv->name);
    $out .= $inv->show();
    $out .= $ml->h1("Statement of Account");
    $out .= $inv->account()->show();
    return $out;
}

sub summary {
    my $this = shift;
    my $section_id = shift;
    $this->setup_querylib();
    my $r = new ExSite::ReportBuilder(title=>"Donations");
    $r->nodata("No donations found.");
    $r->headers(["In previous","Total"]);
    my $time = new ExSite::Time();
    $time->add(-90,"days");
    my $sqldate = $time->write("sql_timestamp");
    my @don = $share{DB}->get_query("recent donations",$section_id,$section_id,$config{Donation}{acctcode},$sqldate);
    my $dlist = new ExSite::ObjectList(type=>"receivable_item",list=>\@don);
    my %summary;
    $time->set(); # now
    while (my $d = $dlist->next()) {
        my $subtotal = $d->subtotal();
        my $inv = $d->receivable();
        my $age = $time->diff($inv->getdata("date","sql_timestamp"))/-86400;
        if ($age < 7) { $summary{7} += $subtotal; }
        if ($age < 14) { $summary{14} += $subtotal; }
        if ($age < 30) { $summary{30} += $subtotal; }
        if ($age < 60) { $summary{60} += $subtotal; }
        if ($age < 90) { $summary{90} += $subtotal; }
    }
    $r->push("week", $summary{7} ? sprintf("%f.02",$summary{7}) : 0);
    $r->push("2 weeks", $summary{14} ? sprintf("%f.02",$summary{14}) : 0);
    $r->push("month", $summary{30} ? sprintf("%f.02",$summary{30}) : 0);
    $r->push("2 months", $summary{60} ? sprintf("%f.02",$summary{60}) : 0);
    $r->push("3 months", $summary{90} ? sprintf("%f.02",$summary{90}) : 0);
    return $r->make();
}

# fundraising_gauge : show fundraising campaign progress meter

sub fundraising_gauge {
    my $this = shift;
    my $section_id = $this->get_section_id;
    return undef if (! $section_id);
    my $start = &preference("Donation.campaign_start");
    if (! $start) {
        my $t = new ExSite::Time();
        my $y = $t->write("raw_year");
        $start = "$y-01-01";
    }
    my $goal = &preference("Donation.campaign_goal");
    my @don = $share{DB}->get_query("recent donations",$section_id,$section_id,$config{Donation}{acctcode},$start);
    my $dlist = new ExSite::ObjectList(type=>"receivable_item",list=>\@don);
    my $total;
    while (my $d = $dlist->next()) {
        $total += $d->subtotal();
    }

    my $out;
    my $width = &preference("Donation.gauge_width") || 400;
    my $dwidth;
    if ($goal) {
        $dwidth = $total ? int(($total / $goal) * $width) : 0;
    }
    else {
        $dwidth = int($width / 2);
    }
    if ($dwidth > $width) { $dwidth = $width; }
    my $amt = sprintf("%.02f",$total);
    $out = $ml->div(
                    $ml->div(
                             $ml->div(
                                      $config{report}{currency_char}.$amt,
                                      {class=>"DonationFundsRaised",style=>"width:${dwidth}px"}
                                      ),
                             {class=>"DonationGoal",style=>"width:${width}px"}
                             ),
                    {class=>"DonationGauge"}
                    );
    if ($goal && $start) {
        $out .= $ml->table(
                           $ml->tr(
                                   $ml->th($msg{"Goal:"}).
                                   $ml->td($config{report}{currency_char}.$goal,{class=>"num"})
                                   ).
                           $ml->tr(
                                   $ml->th($msg{"Raised so far:"}).
                                   $ml->td($config{report}{currency_char}.$amt,{class=>"num"})
                                   ),
                           { class=>"DonationStats" }
                           );
    }
    return $out;
}

sub setup_querylib {
    my $this = shift;
    my $db = $share{DB};
    $db->set_query("recent donations",
                   sql=>"select ri.* from receivable r,receivable_item ri,account a left join member m on m.member_id=a.member_id where r.account_id=a.account_id and ri.receivable_id=r.receivable_id and r.status='active' and (m.section_id=? or a.section_id=?) and ri.acctcode_id=? and r.date >= ? order by ri.receivable_item_id desc",
                   nparam=>4,
                   mode=>"r",
                   keys=>["receivable","receivable_item","account","member"]);
    $db->set_query("donations during period",
                   sql=>"select ri.* from receivable r,receivable_item ri,account a left join member m on m.member_id=a.member_id where r.account_id=a.account_id and ri.receivable_id=r.receivable_id and r.status='active' and (m.section_id=? or a.section_id=?) and ri.acctcode_id=? and r.date >= ?  and r.date <= ? order by ri.receivable_item_id",
                   nparam=>5,
                   mode=>"r",
                   keys=>["receivable","receivable_item","account","member"]);
    $db->set_query("donations from name",
                   sql=>"select ri.* from receivable r,receivable_item ri,account a left join member m on m.member_id=a.member_id where r.account_id=a.account_id and ri.receivable_id=r.receivable_id and r.status='active' and (m.section_id=? or a.section_id=?) and ri.acctcode_id=? and a.name like ? order by r.date desc",
                   nparam=>4,
                   mode=>"r",
                   keys=>["receivable","receivable_item","account","member"]);
}

1;
