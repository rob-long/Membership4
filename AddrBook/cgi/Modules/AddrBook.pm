package Modules::AddrBook;
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
#  The address book manages your database of people and places.
#
#----------------------------------------------------------------------------

=pod

TODO:
- alpha report contacts should link to different area
- saved contact lists should link to different area
- date ranges on registrant and customer reports
- purchase types on customer reports
- purchase objects on customer reports
- registrants - use account record, or registrant record
- BUG: members don't show up in alpha reports
- member_groups table/column names
- delete contacts
=cut

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
use ExSite::Wizard;

use Modules::ID::Contact;
use Modules::ID::ContactList;
use Modules::Location::Location;

# recommended base class for plug-in modules

use Modules::BaseDCD;

# declare package globals

use vars qw(@ISA $ml $ui $AddrBook @searchparam %contact_field);
@ISA = qw(Modules::BaseDCD);

@searchparam = qw(usertype status group evtfee type city provstate country dupe unsubscribe section_id type);

%contact_field = (
    address=>"Address",
    city=>"City",
    provstate=>"Province/State",
    country=>"Country",
    pcode=>"Postal/Zip Code",
    phone=>"Telephone",
    cell=>"Cell/Mobile",
    fax=>"Fax",
    email=>"E-mail",
    website=>"Website",
    );

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
	return "Address Book";
    }
    elsif (/ModuleInfo/) {
	return "The address book manages your database of people and places.";
    }
    elsif (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/Dependencies/) {
	return ["EvtCal","EvtReg","Finance"];
    }
    elsif (/Category/) {
	return ["Social", "Applications"];
    }
}

#----------------------------------------------------------------------------
# Everything after this point consists of private methods.

# ctrl_panel() generates the contents of the administrator control panel

sub ctrl_panel {
    my $this = shift;

    # declare a markup generator
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");

    # build a block of HTML to display the control panel

    my $out;  # our output buffer
    $this->{section_id} = $this->get_section_id();
    if (! $this->{section_id}) {
	$out .= $this->set_section_id();
	return $out;
    }

    $this->setup_querylib();
    my $tab = $this->{input}{tab} || "saved";
    my $imgbase = "$config{server}{HTMLpath}/_Modules/AddrBook";
    my $url = new ExSite::URI(uri=>"$config{server}{server}$config{server}{CGIpath}/$config{prog}{ctrlpanel}/AddrBook");
    $url->parameter("section_id",$this->{section_id});
    $out .= $ui->IconBar(
	links=>[{url=>$url->relink(query=>{tab=>"saved"}),label=>"Saved&nbsp;Lists",img=>"$imgbase/group.png"},
		{url=>$url->relink(query=>{tab=>"makelist"}),label=>"Advanced&nbsp;Search",img=>"$imgbase/group_add.png"},
		undef,
		{url=>$url->relink(query=>{tab=>"lookup"}),label=>"Find",img=>"$imgbase/lookup.png"},
		{url=>$url->relink(query=>{tab=>"browse"}),label=>"Browse",img=>"$imgbase/browse.png"},
		undef,
		{url=>$url->relink(query=>{tab=>"update"}),label=>"Add&nbsp;Contact",img=>"$imgbase/update.png"},
		{url=>$url->relink(query=>{tab=>"import"}),label=>"Import",img=>"$imgbase/import.png"},
]
	);
    if ($this->{input}{contact_id}) {
	$out .= $this->manage_contact($this->{input}{contact_id});
    }
    elsif ($tab eq "makelist") {
	$out .= $this->makelist();
    }
    elsif ($tab eq "lookup") {
	$out .= $this->lookup();
    }
    elsif ($tab eq "saved") {
	$out .= $this->saved_lists();
    }
    elsif ($tab eq "browse") {
	$out .= $this->browse();
    }
    elsif ($tab eq "update") {
	$out .= $this->new_contact();
    }
    elsif ($tab eq "import") {
	$out .= $this->import();
    }

    return $out;
}

sub browse {
    my $this = shift;
    my $out;
    foreach my $alpha ("A" .. "Z") {
	$out .= $ml->a($alpha,{href=>$this->link(alpha=>$alpha),class=>"alpha"});
    }
    $out .= $ml->a("?",{href=>$this->link(alpha=>0),class=>"alpha"});
    $out = $ml->div($out,{class=>"browse_index"});

    my $sid = $this->get_section_id;
    my $alpha = $this->{input}{alpha};
    if ($alpha) {
	#$out .= $ml->h1($alpha);

	# account contacts
	my @c = $share{DB}->get_query("lookup account contacts by name",$sid,$sid,"$alpha\%");
	push @c, $share{DB}->get_query("lookup location contacts by contact name","$alpha\%");
	foreach my $c ($share{DB}->get_query("lookup location contacts by location name","$alpha\%")) {
	    next if ($c->{name}); # skip ones that should be indexed elsewhere
	    push @c, $c;
	}
	#push @c, $share{DB}->get_query("lookup other contacts by name","$alpha\%");
	my $clist = new Modules::ID::ContactList;
	$clist->setlist(@c);
	$clist->sort("name");
	my $url = new ExSite::URI;
	$out .= $clist->show(url=>$url,title=>uc $alpha);
    }
    return $out;
}

sub makelist {
    my ($this) = @_;
    my $in = $this->{input};
    my $section_id = $this->{section_id};
    my $out;
    my $input = new ExSite::Input;
    my $q = $input->query;
    if ($q->{unsubscribe} || $q->{dupe}) {
	# search is completed
	if ($q->{save}) {
	    $out .= $this->save_search();
	}
	elsif ($q->{export}) {
	    $out .= $this->build_contact_list($q->{ctype},$q->{include},%$q);
	}
    }
    else {
	# search is incomplete
	$AddrBook = $this;
	my $wiz = new ExSite::Wizard(title=>"Contact List");
	$wiz->add_step("Start a new list",\&search_1,\&do_search_1);
	$wiz->add_step("Search parameters",\&search_2,\&do_search_2);
	$wiz->add_step("Report",\&search_3);
	$out .= $wiz->go();
    }
    return $out;
}

sub search_1 {
    my ($this,$in) = @_;
    my $db = $share{DB};
    my $out;
    my @opt = ( $ml->option("== NONE; start from scratch ==",{value=>""}) );
    foreach my $clist ($share{DB}->fetch_child("contact_list","section",$AddrBook->{section_id},"name")) {
	push @opt, $ml->option($clist->{name},{value=>$clist->{contact_list_id}});
    }
    $out .= $ml->p("Start with the contacts in:" . $ml->br .
		   $ml->select(join("",@opt),{name=>"include"}));
    $out .= $ml->p("Add contact records of the following type:" . $ml->br . 
	$ml->input(undef,{type=>"radio",name=>"contact_type",value=>"members"}).
	" users (people who can log in to your website)".$ml->br.
	$ml->input(undef,{type=>"radio",name=>"contact_type",value=>"membership"}).
	" members (people who have a membership with your organization)".$ml->br.
	$ml->input(undef,{type=>"radio",name=>"contact_type",value=>"group"}).
	" member groups (eg. committees, teams)".$ml->br.
	$ml->input(undef,{type=>"radio",name=>"contact_type",value=>"registrant"}).
	" registrants (people who have registered for events)".$ml->br.
	$ml->input(undef,{type=>"radio",name=>"contact_type",value=>"customer"}).
	" customers (people who have purchased something from your site)".$ml->br.
	$ml->input(undef,{type=>"radio",name=>"contact_type",value=>"location"}).
	" locations (places, not people)".$ml->br.
	$ml->input(undef,{type=>"radio",name=>"contact_type",value=>"other"}).
	" none of the above".$ml->br
#	$ml->input(undef,{type=>"radio",name=>"contact_type",value=>"all"}).
#	" search all"
	);
    $out .= $ml->p("Note: there are overlaps between these different types. For example, members and registrants may also be customers. Users and registrants can also be members.");
    return $ml->p($out);
}

sub do_search_1 {
    my ($this,$in) = @_;
    my @err;
    if (! $in->{contact_type}) {
	push @err, "Please select a contact type.";
    }
    return @err;
}

sub search_2 {
    my ($this,$in) = @_;
    my $db = $share{DB};
    my $type = $in->{contact_type};
    my $f = new ExSite::FormBuilder();
    $f->template("<table>","<tr><td>[[prompt]]</td><td>[[input]]</td></tr>","</table>");
    my $out;
    if ($type eq "membership") {
	my $membership = &ExSite::Module::get_module("Membership");
	if ($membership) {
	    $out .= $f->input(name=>"membership_heading",
			      type=>"preformatted",
			      input=>$ml->tr($ml->th("Membership Info",{colspan=>2})));
$ml->h2("Membership details");
	    $membership->setup_queries();
	    my @utype = sort $membership->known_membership_types($in->{section_id});
	    $out .= $f->input(prompt=>"User type",
			      name=>"usertype",
			      type=>"select",
			      options=>\@utype,
			      nullvalue=>"ANY",
			      templated=>1);
	    $out .= $f->input(prompt=>"Membership status",
			      name=>"status",
			      type=>"select",
			      options=>["active","pending","expired","archived"],
			      nullvalue=>"ANY",
			      templated=>1);
	}
    }
    if ($type eq "member_group") {
	if ($share{DB}{map}->is_mapped("member_group")) {
	    my @group = $share{DB}->fetch_child("member groups","section",$in->{section_id});
	    my @opt;
	    foreach my $gr (@group) {
		push @opt, [$gr->{member_group_id}, $gr->{name}];
	    }
	    if (scalar @group > 0) {
		$out .= $f->input(prompt=>"Group",
				  name=>"group",
				  type=>"select",
				  options=>\@opt,
				  nullvalue=>"ANY",
				  templated=>1);
	    }
	    else {
		$out .= $this->error("No member groups are defined.");
	    }
	}
	else {
	    $out .= $this->error("Member groups are not supported on this system.");
	}
    }	    
#    elsif ($type eq "customer") {
#	my @code;
#	foreach my $ac ($share{DB}->fetch_all("acctcode","code")) {
#	    push @code, [$ac->{acctcode_id},$ac->{code}];
#	}
#	$f->input(name=>"acctcode",prompt=>"Purchase Type",type=>"select",options=>\@code,nullvalue=>"ANY",value=>$in->{acctcode});
#	$f->input(name=>"startdate",prompt=>"From",type=>"text",placeholder=>"YYYY-MM-DD",value=>$in->{startdate},size=>12);
#	$f->input(name=>"enddate",prompt=>"To",type=>"text",placeholder=>"YYYY-MM-DD",value=>$in->{enddate},size=>12);
#    }
    elsif ($type eq "registrant") {
	$out .= $f->input(name=>"registrant_heading",
			  type=>"preformatted",
			  input=>$ml->tr($ml->th("Registration details",{colspan=>2})));
	my (@evt,%evt,$last_evt,$last_evt_id);
	my @evtfee = $share{DB}->get_query("events with registrant contacts",$this->{input}{section_id});
	foreach my $evt (@evtfee) { $evt{$evt->{evt_id}}++; }
	foreach my $evt (@evtfee) {
	    if ($evt->{evt_id} != $last_evt && $evt{$evt->{evt_id}} > 1) {
		push @evt, ["$evt->{evt_id}-0", $evt->{event}."/ALL FEES (".$evt->{date}.")" ];
	    }
	    push @evt, [ $evt->{evt_id}."-".$evt->{evt_fee_id}, $evt->{event}."/".$evt->{fee}." (".$evt->{date}.")" ];
	    $last_evt = $evt->{evt_id};
	    $last_evt_id = $evt->{evt_id};
	}
	$out .= $f->input(prompt=>"Event/Fee",
			  name=>"evtfee",
			  type=>"select",
			  options=>\@evt,
			  nullvalue=>"-- select one --",
			  templated=>1);
	$out .= $f->input(prompt=>"Registration status",
			  name=>"status",
			  type=>"select",
			  options=>$share{DB}{map}->regexp("list:evt_reg_status"),
			  nullvalue=>"ANY",
			  templated=>1);
    }
    elsif ($type eq "other") {
	my @group;
	foreach my $gr ($share{DB}->get_query("contact list categories",$AddrBook->{section_id})) {
	    my $cat = $gr->{category};
	    next if (! $cat || $cat =~ /NULL/);
	    push @group, $cat;
	}
	$out .= $f->input(prompt=>"Group",
			  name=>"group",
			  type=>"select",
			  options=>\@group,
			  nullvalue=>"ANY",
			  templated=>1);
    }
    $out .= $f->input(name=>"contact_heading",
		      type=>"preformatted",
		      input=>$ml->tr($ml->th("Location",{colspan=>2})));
    $out .= $f->input(name=>"city",prompt=>"City",type=>"text",placeholder=>"ANY",templated=>1);
    $out .= $f->input(name=>"provstate",prompt=>"Province/State",type=>"select",options=>$share{DB}{map}->regexp("list:provstate"),nullvalue=>"ANY",templated=>1);
    $out .= $f->input(name=>"country",prompt=>"Country",type=>"text",nullvalue=>"ANY",placeholder=>"ANY",templated=>1);

    $out .= $f->input(name=>"exclude_heading",
		      type=>"preformatted",
		      input=>$ml->tr($ml->th("Other",{colspan=>2})));
    $out .= $f->input(name=>"type",prompt=>"Contact Type",type=>"select",options=>$share{DB}{map}->regexp("list:contact_type"),nullvalue=>"ANY",templated=>1);
    $out .= $f->input(name=>"dupe",prompt=>"Contact records per person",type=>"select",options=>["all","best one"],templated=>1);
    $out .= $f->input(name=>"unsubscribe",prompt=>"Unsubscribed contact records",type=>"select",options=>["exclude","include"],templated=>1);
    $out .= $f->input(name=>"ctype",type=>"hidden",value=>$type);
#    $out .= $f->input(name=>"section_id",type=>"hidden",value=>$in->{section_id});
    return $ml->table($out,{class=>"AddrBookSearch"});
}

sub do_search_2 {
    my ($this,$in) = @_;
    my @err;
    if (! $in->{contact_type}) {
	push @err, "Please select a contact type.";
    }
    return @err;
}

sub search_3 {
    my ($this,$in) = @_;
    my %param;
    foreach my $p (@searchparam) {
	if ($in->{$p}) { $param{$p} = $in->{$p}; }
    }
    return $AddrBook->build_contact_list($in->{ctype},$in->{include},%param);
}

sub save_search {
    my $this = shift;
    my $out;
    if ($this->{input}{clist_name}) {
	my %clist = (
	    section_id=>$this->{input}{section_id},
	    name=>$this->{input}{clist_name},
	    type=>$this->{input}{ctype},
	    dupe=>$this->{input}{dupe},
	    unsubscribe=>$this->{input}{unsubscribe},
	    include=>$this->{input}{include} || 0,
	    );

	my %param;
	foreach my $p (@searchparam) {
	    if ($p eq "type" or ! exists $clist{$p}) {
		if ($this->{input}{$p}) { $param{$p} = $this->{input}{$p}; }
	    }
	}
	#delete $param{type};
	$clist{parameters} = &EncodeHash(%param);

	my $clid = $share{DB}->insert("contact_list",\%clist);
	if ($clid) {
	    $out .= $ml->p("Contact list saved.");
	}
	else {
	    $out .= $this->error("Failed to save contact list.").
		$share{DB}->show_diagnostics("error","html");
	}
    }
    else {
	$out = $ml->h1("Save Contact List");
	$out .= $ml->p("NOTE: This saves the parameters used to generate the contact list, 
not the actual contents of the list. That means the contact list may have 
different contents when viewed at different times.");
	$out .= $ml->p("To save the current contents of the contact list, you
should export the list to Excel or CSV.");
	my $f = new ExSite::FormBuilder();
	$f->input(name=>"clist_name",prompt=>"Save contact list as",type=>"text",required=>1);
	$out .= $f->make();
    }
    return $out;
}

# lookup : simple search by name

sub lookup {
    my $this = shift;
    my $out = $ml->h1("Find Specific Contacts");
    my $br = $ml->br;

    # search by name
    my $f = new ExSite::FormBuilder();
    $f->input(type=>"formatted",
	      prompt=>"Enter a first name or last name (not both), an organization name, or location name.${br}You can also search for partial names.",
	      name=>"tips");
    $f->input(type=>"text",
	      prompt=>"Name:",
	      name=>"name",
	      value=>$this->{input}{name},
	      required=>1);
    $f->set("buttons",$ml->input(undef,{type=>"submit",value=>"Submit"}));
    my $nameout .= $f->make();

    # search by email
    $f->init;
    my $f = new ExSite::FormBuilder();
    $f->input(type=>"formatted",
	      prompt=>"Enter all or part of an email address.",
	      name=>"tips");
    $f->input(type=>"text",
	      prompt=>"Email:",
	      name=>"email",
	      value=>$this->{input}{email},
	      required=>1);
    $f->set("buttons",$ml->input(undef,{type=>"submit",value=>"Submit"}));
    my $emailout .= $f->make();

    # search by phone
    $f->init;
    my $f = new ExSite::FormBuilder();
    $f->input(type=>"formatted",
	      prompt=>"Enter all or part of a telephone, cell phone, or fax number.",
	      name=>"tips");
    $f->input(type=>"text",
	      prompt=>"Phone:",
	      name=>"phone",
	      value=>$this->{input}{phone},
	      required=>1);
    $f->set("buttons",$ml->input(undef,{type=>"submit",value=>"Submit"}));
    my $phoneout .= $f->make();

    my ($itab,$searchout);
    if ($this->{input}{name}) {
	# search for name
	my $name = $this->{input}{name};
	my $sid = $this->{section_id};
	my @c = $share{DB}->get_query("lookup account contacts by name",$sid,$sid,"\%$name\%");
	push @c, $share{DB}->get_query("lookup location contacts by name","\%$name\%");
	push @c, $share{DB}->get_query("lookup other contacts by name","\%$name\%");
	my $clist = new Modules::ID::ContactList;
	$clist->setlist(@c);
	$clist->sort("name");
	my $url = new ExSite::URI;
	my $itab = 0;
	$searchout .= $clist->show(url=>$url,title=>$name);
    }
    elsif ($this->{input}{email}) {
	# search for email
	my $sid = $this->{section_id};
	my $wc_email = "%".$this->{input}{email}."%";
	my @c = $this->filter_content_contacts($sid,$share{DB}->get_query("lookup content contacts by email",$wc_email));
	push @c, $share{DB}->get_query("lookup account contacts by email",$sid,$wc_email);
	my $clist = new Modules::ID::ContactList;
	$clist->setlist(@c);
	$clist->sort("name");
	my $url = new ExSite::URI;
	$itab = 1;
	$searchout .= $clist->show(url=>$url,title=>"Email matching '$this->{input}{email}'");
    }
    elsif ($this->{input}{phone}) {
	# search for phone
	my $sid = $this->{section_id};
	my $tel = $this->{input}{phone};
	my $wctel = "%$tel%"; 
	my @c = $this->filter_content_contacts($sid,$share{DB}->get_query("lookup content contacts by phone",$wctel));
	push @c, $share{DB}->get_query("lookup account contacts by phone",$sid,$wctel);
	my $clist = new Modules::ID::ContactList;
	$clist->setlist(@c);
	$clist->sort("name");
	my $url = new ExSite::URI;
	$searchout .= $clist->show(url=>$url,title=>"Phone matching '$tel'");
    }
    $out .= $ui->DynTabBox(
	tabs=>["Name","E-mail","Phone"],
	thistab=>$itab,
	panes=>[$nameout,$emailout,$phoneout]
	);
    $out .= $searchout;
    return $out;
}

sub filter_content_contacts {
    my ($this,$section_id,@list) = @_;
    my $c = new ExSite::Content();
    my @myc;
    foreach my $contact (@list) {
	$c->setup(id=>$contact->{content_id});
	if ($c->ok) {
	    if ($c->my_section->id == $section_id) {
		push @myc, $contact;
	    }
	}
    }
    return @myc;
}

sub contact_name {
    my ($this, $c) = @_;

    my $name = $c->getdata("name");
    return $name if $name;

    my $first_name = $c->getdata("first_name");
    my $last_name = $c->getdata("last_name");
    if ($first_name || $last_name) {
	return ($last_name || "?") . ", " . $first_name;
    }

    return $c->contact_name;
}

sub saved_lists {
    my $this = shift;
    if ($this->{input}{clist}) {
	return $this->show_saved_list($this->{input}{clist});
    }
    my $out .= $ml->h1("Saved Contact Lists");
    my $r = new ExSite::ReportBuilder(title=>"Saved Contact Lists");
    $r->headers("Name","Type");
    $r->nodata("No saved contact lists.");
    my $section_id = $this->get_section_id;
    my @clist = $share{DB}->fetch_child("contact_list","section",$section_id,"name");
    foreach my $clist (@clist) {
	$r->push($ml->a($clist->{name},{href=>$this->link(clist=>$clist->{contact_list_id})}), $clist->{type});
    }
    $out .= $r->make();
}

sub show_saved_list {
    my ($this,$clistid) = @_;
    my $clist = new Modules::ID::ContactList;
    $clist->load_db($clistid);
    if ($this->{input}{cmd} =~ /dellist/) {
	if ($this->{input}{cmd} =~ /dellist_/) {
	    $share{DB}->trash_key("contact_list",$clistid);
	    if ($this->{input}{cmd} eq "dellist_all") {
		my @trash;
		$clist->reset;
		while (my $contact = $clist->next) {
		    push @trash, "contact", $clist->id;
		}
		$share{DB}->trash(@trash);
	    }
	    $ml->location($this->link(__plaintext=>1,clist=>undef,cmd=>undef));
	    return undef;
	}
	my $out .= $ml->h1("Delete Contact List");
	$out .= $ml->p("If you delete the contact list description only, it will be removed from the saved contact lists, but the actual contacts will remain in your address book. If you also delete the contract records, then the contacts will also be removed from your address book.");
	$out .= $ml->p($ml->a("Delete contact list description, only",{href=>$this->link(cmd=>"dellist_list"),class=>"button"}));
	$out .= $ml->p($ml->a("Delete contact list description AND ALL CONTACT RECORDS",{href=>$this->link(cmd=>"dellist_all"),class=>"button"}));
	$out .= $ml->p($ml->a("Cancel",{href=>$this->link(cmd=>undef),class=>"button"}));
	return $out;
    }
    else {
	$clist->sort("name","info");
	my $url = new ExSite::URI;
	my $tools = $ml->a("Delete contact list",{href=>$this->link(cmd=>"dellist"),class=>"button_sm"});
	return $clist->show(url=>$url,export=>$this->{input}{export},tools=>$tools);
    }
}

sub build_contact_list {
    my ($this,$ctype,$include,%param) = @_;
    my $clist = $this->get_contact_list($ctype,$include,%param);
    my $r = new ExSite::ReportBuilder(title=>ucfirst($ctype)." contacts");
    $r->nodata("No matching contact records.");
    $r->headers(["Name","Contact","Address","City","Prov/State","Country","Postal Code","Phone","Phone/Cell","Fax","E-mail","URL","Privacy","Notes","Type"]);
    while (my $c = $clist->next()) {
	my $editurl = $this->link(contact_id=>$c->id);
	my @data = (
	    $ml->a($this->contact_name($c),{href=>$editurl}),
	    $c->showdata("type"),
	    $c->showdata("address"),
	    $c->showdata("city"),
	    $c->showdata("provstate"),
	    $c->showdata("country"),
	    $c->showdata("pcode"),
	    $c->showdata("phone1"),
	    $c->showdata("phone2"),
	    $c->showdata("fax"),
	    $c->showdata("email"),
	    $c->showdata("website"),
	    $c->showdata("privacy"),
	    $c->showdata("notes"),
	    $c->showdata("type"),
	    );
	$r->push(@data);
    }
    if ($this->{input}{export} eq "xls") { 
	$ml->cancel;
	print "Content-type: application/vnd.ms-excel\ncontent-disposition: attachment; filename=query.xls\n\n";
	$r->export("excel");
	return undef;
    }
    elsif ($this->{input}{export} eq "csv") {
	$ml->cancel;
	print "Content-type: text/comma-separated-values\n\n";
	print $r->export("csv");
	return undef;
    }
    else {
	# HTML
	my $url = new ExSite::URI;
	$url->query(%param);
	$url->query(export=>"csv",ctype=>$ctype);
	my $csvlink = $url->write;
	$url->query(export=>"xls");
	my $xlslink = $url->write;
	$url->query(export=>undef,save=>1);
	my $savelink = $url->write;

	$r->paginate(1000);
	# would be nice to force a filename on CSV exports
	$r->foot(
	    $ml->a(undef,{name=>"foot"}).
	    $ml->a("CSV",{href=>$csvlink})."&nbsp;&bull;&nbsp;".
	    $ml->a("Excel",{href=>$xlslink})."&nbsp;&bull;&nbsp;".
	    $ml->a("Save",{href=>$savelink})
	    );
	return $r->make();
    }
}

sub get_contact_list {
    my ($this,$ctype,$include,%in) = @_;
    if ((keys %in) == 0) {
	%in = %{$this->{input}};
    }
    my $out;
    my %method = (
	member => "add_members",
	membership => "add_membership",
	group => "add_member_group",
	registrant => "add_registrants",
	customer => "add_customers",
	location => "add_locations",
	other => "add_other",
	);
    my $clist = new Modules::ID::ContactList();
    if ($include) {
	$clist->load_db($include);
    }
    my %match;
    if ($in{provstate} && $in{provstate} !~ /==/) {
	$match{provstate} = $in{provstate};
    }
    if ($in{city}) {
	$match{city} = $in{city};
    }
    if ($in{country}) {
	$match{country} = $in{country};
    }
    if ($in{type}) {
	$match{"c.type"} = $in{type};
    }
    if ($ctype =~ /member/) {
	if ($in{usertype} || $in{status}) {
	    if ($in{usertype}) {
		$match{'member_type'} = $in{usertype};
	    }
	    if ($in{status}) {
		$match{status} = $in{status};
	    }
	}
    }
    elsif ($ctype eq "registrant") {
	my ($evt,$fee) = split /-/,$in{evtfee};
	$match{evt_id} = $evt;
	if ($fee) { $match{evt_fee_id} = $fee; }
	if ($in{status}) {
	    $match{'r.status'} = $in{status};
	}
    }
    elsif ($ctype eq "other") {
	if ($in{group}) {
	    $match{category} = $in{group};
	}
    }
    my $method = $method{$ctype};
    eval { $clist->$method(\%match); };
    if ($@) {
	$this->error($@);
    }
    else {
	if ($in{unsubscribe} eq "exclude") {
	    $clist->remove_unsubscribed();
	}
	if ($in{dupe} =~ /best/) {
	    if ($ctype =~ /user|customer|registrant/) {
		$clist->best_of_account();
	    }
	    elsif ($ctype eq "location") {
		$clist->best_of_location();
	    }
	    else { #if ($ctype eq "other") {
		$clist->remove_dupe_emails();
		$clist->remove_dupe_addresses();
	    }
	}
    }
    return $clist;
}

sub manage_contact {
    my ($this,$contact) = @_;
    my $c = (ref $contact) =~ /Contact/ ? 
	$contact : new Modules::ID::Contact(id=>$contact);
    my $cid = $c->id;
    my $out = $ui->ToolBar(tools=>[
	$ml->a("&lt; Back",{href=>$this->link(ab=>undef,contact_id=>undef)}),
	$ml->a("Edit",{href=>$this->link(ab=>"edit",contact_id=>$cid)}).
	$ml->a("Permissions",{href=>$this->link(ab=>"perm",contact_id=>$cid)}),
	#$ml->a("Add",{href=>$this->link(ab=>"addcard",contact_id=>$cid)}).
	$ml->a("Delete",{href=>$this->link(ab=>"delete",contact_id=>$cid)})
	]);
    my $title = $this->contact_name($c);
    my $pane;
    if ($this->{input}{ab} eq "edit") {
	$pane .= $c->edit(action=>$this->link());
    }
    if ($this->{input}{ab} eq "perm") {
	$pane .= $this->permissions($c);
    }
    elsif ($this->{input}{ab} eq "delete") {
	$c->delete();
	$ml->location($this->link(ab=>undef,contact_id=>undef,__plaintext=>1));
	return;
    }
    else {
	my $uri = new ExSite::URI;
	$pane .= $c->show(notes=>1,vcard=>$uri);
    }
    $out .= $ui->BasicBox(title=>$title,pane=>$pane);
    return $out;
}

sub new_contact {
    my $this = shift;
    my $out;
    my $db = $share{DB};
    my $input = new ExSite::Input;
    my $post = $input->post;
    if (scalar keys %$post > 0) {
#	my %data = $db->parse_parts(%$post);
#	delete $data{action};
	my $contact = new Modules::ID::Contact();
	$out .= $contact->save_contact("insert");
	$out .= $this->manage_contact($contact);
    }
    else {
	$out = $ml->h1("Add Contact");
	my $contact = new Modules::ID::Contact();
	$out .= $contact->make(action=>$this->link(),hide=>["section_id"],data=>{section_id=>$this->{section_id},account_id=>$this->{input}{account_id}});
    }
    return $out;
}

sub permissions {
    my ($this,$c) = @_;
    my $out = $ml->h1("Access Permissions");
    my $cdata = $c->get_info();
    my %inforec = $c->meta()->get_record();
    my @permfield = qw(address city provstate country pcode phone cell fax email website);

    if (exists $this->{input}{access}) {
	# post data received
	my @changes;
	if ($this->{input}{access} != $c->getdata("privacy")) {
	    $c->setdata("privacy",$this->{input}{access});
	    $c->save();
	    push @changes, "contact";
	}
	foreach my $fld (@permfield) {
	    if ($this->{input}{$fld} ne $inforec{$fld}{privacy}) {
		if ($this->{input}{$fld} =~ /\d/) {
		    $inforec{$fld}{privacy} = $this->{input}{$fld};
		}
	        else {
		    $inforec{$fld}{privacy} = undef;
		}
		$share{DB}->update("contact_info",$inforec{$fld});
		push @changes, $contact_field{$fld};
	    }
	}
	if (@changes > 0) {
	    $out .= $ui->SuccessBox(title=>"Permissions Changed",pane=>"Changed permissions for ".join(", ",@changes));
	}
    }
    
    my @perms = ({text=>"n/a",value=>""},{text=>"public",value=>0},{text=>"users",value=>1},{text=>"members",value=>2},{text=>"executives",value=>5},{text=>"managers",value=>7},{text=>"system administrators",value=>8});

    my $f = new ExSite::FormBuilder();
    my $template;
    foreach my $fld (@permfield) {
	if ($cdata->{$fld}) {
	    $template .= $ml->tr(
		$ml->td("[[$fld:prompt]]").
		$ml->td($cdata->{$fld}).
		$ml->td("[[$fld:input]]")
		);
	}
    }
    $f->template(
	$ml->table(
	    $ml->tr(
		$ml->td("[[access:prompt]]",{colspan=>2}).$ml->td("[[access:input]]")
	    ).
	    $ml->tr(
		$ml->td("You can optionally specify more specific permissions for each field:",{colspan=>3})
	    ).
	    $ml->tr(
		$ml->th("Field").$ml->th("Currently").$ml->th("Access")
	    ).
	    $template,
	    {class=>"ContactAccess"}
	)
	);

    $f->input(name=>"access",prompt=>"This address card can be viewed by:",type=>"select",options=>\@perms,value=>$c->getdata("privacy"));
    foreach my $fld (@permfield) {
	if ($cdata->{$fld}) {
	    $f->input(name=>$fld,type=>"select",prompt=>$contact_field{$fld},options=>\@perms,value=>$inforec{$fld}{privacy});
	}
    }
    $out .= $f->make();
    return $out;
}

sub import {
    my $this = shift;
    my $out;
    if (eval 'require Text::CSV::Slurp') {
	my $db = $share{DB};
	my $input = new ExSite::Input;
	my $post = $input->post;
	if (scalar keys %$post > 0) {
	    return $this->do_import($post);
	}
	else {
	    $out .= $ml->h1("Import Contacts");
	    my @cat = map { $_->{category} } $share{DB}->get_query("contact list categories",$this->{section_id});

	    my $f = new ExSite::FormBuilder(highlight_rows=>1);

	    my $br = $ml->br;
	    $f->template("<table class='importForm'>",
			 "<tr class='[[rowclass]]'><td width='50%'>[[prompt]]</td><td>[[input]]</td></tr>\n",
			 "</table>");

#	    $f->template($ml->p("[[import:prompt]]${br}[[import:input]]").
#			 $ml->p("[[type:prompt]]${br}[[type:input]]").
#			 $ml->p("[[name:prompt]]${br}[[name:input]]").
#			 $ml->p("[[group_old:prompt]]${br}[[group_old:input]] Other: [[group_new:input]]${br}
#(If you do not specify a group code, they will automatically be tagged with the filename and date.)").
#			 $ml->p("[[privacy:prompt]]${br}[[privacy:input]]"));

	    $f->input(type=>"file",name=>"import",prompt=>"Upload CSV file",tail=>$ui->HelpPopup(label=>"?",message=>"See below for instructions on how to format this file."),required=>1);
	    $f->input(type=>"radio",name=>"type",prompt=>"Import as:",tail=>$ui->HelpPopup(label=>"?",message=>"To create login identities, import as members/users. To create e-commerce accounts, import as accounts. Otherwise, import as simple contacts."),options=>["accounts","members/users","simple contacts"],value=>"simple contacts");
	    $f->input(type=>"text",name=>"name",prompt=>"To save this import as its own contact list, provide a contact list name:",tail=>$ui->HelpPopup(label=>"?",message=>"This will add an entry in the 'Saved Lists' area, containing these contacts."),placeholder=>"list name");
	    $f->input(type=>"select",name=>"group_old",prompt=>"Add these contacts to this group:",tail=>$ui->HelpPopup(label=>"?",message=>"Contacts can be 'tagged' with a group name to make them easier to distinguish from other uploaded contacts. Select an existing group name here to add these contacts to that group."),options=>\@cat,nullvalue=>"== select ==");
	    $f->input(type=>"text",name=>"group_new",prompt=>"OR, start a new group based on these contacts:",tail=>$ui->HelpPopup(label=>"?",message=>"Enter a new group name if you want to tag these contacts with a group name that doesn't exist yet."),placeholder=>"group code");
	    $f->input(type=>"select",name=>"privacy",options=>$share{DB}{map}->regexp("list:contact_privacy"),nullvalue=>"== select ==",prompt=>"Privacy setting for these imported contacts:",tail=>$ui->HelpPopup(label=>"?",message=>"Select who is allowed to view this contact information."));
	    $out .= $f->make();
	    $out .= $ml->br;
	    $out .= $ui->AccordionBox(
		states=>[0,0],
		titles=>["Instructions","Example CSV format"],
		panes=>[
		    $ml->p("Contact information must be uploaded in CSV format. (Spreadsheet programs such as Excel can export/save to CSV format.) The first row should be the column headers, and each subsequent row is one contact record. Column headers like the following will be recognized (case is not important):").
		    $ml->ul(
			$ml->li("name, first name, last name, first_name, last_name, firstname, lastname, first, last").
			$ml->li("address, addr").
			$ml->li("city, town").
			$ml->li("province, state, prov, prov/state, state/province, state/prov").
			$ml->li("country").
			$ml->li("postal code, zip code, zip, pcode").
			$ml->li("telephone, phone, phone1, phone2, mobile, fax").
			$ml->li("email, e-mail").
			$ml->li("login, pass, passwd, password (for members only)")
		    ).
		    $ml->p("Unrecognized column headers will be ignored."),
		    $ml->pre('"First Name","Last Name","Email"
"John","Doe","johndoe@example.com"
"Jane","","janedoe@example.com"')
		]);
	}
    }
    else {
	return $this->error("Import not supported on this server: ".$@);
    }
    return $out;
}

sub do_import {
    my $this = shift;
    my $out;
    if (eval 'require Text::CSV::Slurp') {
	my $db = $share{DB};
	my $input = new ExSite::Input;
	my $post = $input->post;
	if (scalar keys %$post > 0) {
	    if ($post->{import}) {
		# we have been provided with a file
		#my $importdata = $input->fetch_file("import","raw");
		# next line fails on CGI data
		#my $data = Text::CSV::Slurp->load(string => $importdata);
		# so instead we write to a tmp file
		my $tmpfile = "/$config{server}{temppath}/AddrBook$$.csv";
		open TMP,">$tmpfile";
		print TMP $input->fetch_file("import","raw");
		close TMP;
		my $data = Text::CSV::Slurp->load(file => $tmpfile);
		unlink $tmpfile;
		if (ref $data eq "ARRAY") {
		    my $filename = $post->{import};
		    my $t = new ExSite::Time;
		    my $date = $t->write("sql_datetime");
		    my $group = 
			$post->{group_new} || 
			$post->{group_old} || 
			"$filename - $date";
		    my (%col);
		    my @unknown;
		    my ($login,$password);
		    my $headrow = $data->[0];
		    foreach (keys %$headrow) {
			if (/first/i) { $col{$_} = "info"; }
			elsif (/last/i) { $col{$_} = "info_last"; }
			elsif (/name/i) { $col{$_} = "info"; }
			elsif (/addr/i) { $col{$_} = "address"; }
			elsif (/city|town/i) { $col{$_} = "city"; }
			elsif (/prov|state/i) { $col{$_} = "provstate"; }
			elsif (/country/i) { $col{$_} = "country"; }
			elsif (/code/i) { $col{$_} = "pcode"; }
			elsif (/cell|mobile|phone2/i) { $col{$_} = "phone2"; }
			elsif (/phone/i) { $col{$_} = "phone"; }
			elsif (/fax/i) { $col{$_} = "fax"; }
			elsif (/e-?mail/i) { $col{$_} = "email"; }
			elsif (/web|url/i) { $col{$_} = "web"; }
			elsif (/login/i) { $col{$_} = "login"; }
			elsif (/pass/i) { $col{$_} = "password"; }
			else { push @unknown, $_; }
		    }
		    if (scalar @unknown > 0) {
			$out .= $ml->warn("Unknown columns: ".join(", ",@unknown));
		    }
		    my $sid = $this->get_section_id;
		    my $r = new ExSite::ReportBuilder(title=>"Contact Import");
		    $r->headers(["Name","Address","City","Phone","Email"]);
		    my $nrow = 1;
		    my @bad;
		    foreach my $row (@$data) {
			$nrow++;
			my %contact = ( section_id => $sid );
			my (@name,$first_name,$last_name,%account,%member);
			foreach (keys %$row) {
			    next if (! $row->{$_});
			    if ($col{$_} eq "info") {
				push @name, $row->{$_};
				$first_name or $first_name = $row->{$_};
			    }
			    elsif ($col{$_} eq "info_last") {
				unshift @name, $row->{$_}.", ";
				$last_name = $row->{$_};
			    }
			    elsif ($col{$_} eq "login") {
				$member{$config{auth}{user_login_column}} = $row->{$_};
			    }
			    elsif ($col{$_} eq "password") {
				$member{$config{auth}{user_pwd_column}} = $row->{$_};
			    }
			    elsif (! exists $col{$_}) {
				# ignore
			    }
			    else {
				$contact{$col{$_}} = $row->{$_};
			    }
			}
			$contact{category} = $group;
			$contact{notes} = "imported from $filename on $date";
			$contact{privacy} = $post->{privacy};
			my $name = scalar @name ? join " ",@name : "(NO NAME)";
			if ($post->{type} =~ /account|member/) {
			    $account{name} = $name;
			}
			else {
			    $contact{info} = join " ", @name;
			}
			if ($post->{type} =~ /member/) {
			    if (ref $config{auth}{user_name_column} eq "ARRAY") {
				$member{$config{auth}{user_name_column}[0]} = $first_name;
				$member{$config{auth}{user_name_column}[-1]} = $last_name;
			    }
			    else {
				$member{$config{auth}{user_name_column}} = $name;
			    }
			    $member{$config{auth}{user_email_column}} = $contact{email};
			}

			my ($member_id,$account_id,$section_id);
			$section_id = $this->get_section_id;
			if (scalar keys %member > 0) {
			    $member{section_id} = $section_id;
			    $member{access} = 1;
			    $member_id = $share{DB}->insert("member",\%member);
			}
			if (scalar keys %account > 0) {
			    $account{section_id} = $section_id;
			    $account{member_id} = $member_id;
			    $account_id = $share{DB}->insert("account",\%account);
			    $contact{account_id} = $account_id;
			}
			my $c = new Modules::ID::Contact(data=>\%contact);
			my $cid = $c->save();
			my $name = $contact{info} || "(NO NAME)";
			if ($cid) {
			    # add to report
			    $r->push($ml->a($contact{info},{href=>$this->link(tab=>undef,contact_id=>$cid)}),
				     $contact{address},
				     $contact{city},
				     $contact{phone},
				     $contact{email});
			}
			else {
			    push @bad, $this->error("Import failed: row $nrow: $name $contact{address} $contact{city} $contact{phone} $contact{email}");
			}
		    }
		    $out .= $ml->h1("Import completed");
		    $out .= $r->make();
		    if (scalar @bad > 0) {
			$out .= $ml->h2("Import failed:");
			$out .= join("",@bad);
		    }
		    if ($post->{name}) {
			my %clist = (
			    section_id=>$this->{section_id},
			    name=>$post->{name},
			    type=>"other",
			    dupe=>"all",
			    unsubscribe=>"exclude",
			    parameters=>"group=$group"
			    );
			my $clist_id = $share{DB}->insert("contact_list",\%clist);
			if ($clist_id) {
			    $out .= $ml->p($ml->a("Added new contact list.",{href=>$this->link(clist=>$clist_id,tab=>"saved")}));
			}
			else {
			    push @bad, $this->error("Failed to create contact list.");
			}
		    }
		}
		else {
		    # problem?
		    $out .= $this->error("Unknown data format in $post->{import}.");
		}
	    }
	}
    }
    return $out;
}

# doform - process forms
# $data = post data
# $goto = redirect URL when done (plaintext format)

sub doform {
    my ($this,$data,$goto) = @_;
    if ($data->{submit_action} eq "Cancel") {
	$ml->location($goto);
	return undef;
    }
    my $db = $share{DB};
    my $out;
    $db->get_data();
    $db->{action} = $db->get_action();
    
    my $errcnt = &AtError();
    $db->do_db($db->{action});

    # report results
    if (! &AtError($errcnt)) {
	# no errors
	$ml->location($goto);
	$out .= "Done!";
    }
    else {
	# uh-oh!
	$out = $ml->h3("Problem:");
	$out .= $this->show_diagnostics("error","html");
	$out .= $ml->p($ml->a("Go back to form.",{href=>"javascript:history.back()"}));
    }
    return $out;
}

# content-based contacts (like locations, events) need to use the 
# content tree to determine section affiliations

sub content_contacts {
    my ($this,@data) = @_;
    my $c = new ExSite::Content();
    my $tree = $c->get_content_tree();
    my @mydata;
    foreach my $dat (@data) {
	if ($tree->has_ancestor($dat->{content_id},$this->{section_id})) {
	    push @mydata, $dat;
	}
    }
    return wantarray ? @mydata : \@mydata;
}

sub my_locations {
    my $this = shift;
    return $this->content_contacts($share{DB}->get_query("all locations"));
}

sub setup_querylib {
    my $this = shift;
    my $db = $share{DB};

    # contacts are associated with content or accounts

    my $ml = new ExSite::ML;

    $db->set_query(
		   "content contacts",
		   ( sql=>"select * from contact where content_id=?",
		     nparam=>1,
		     mode=>"r",
		     keys=>["contact"],
		     )
		   );

    $db->set_query(
		   "user contacts",
		   ( sql=>"select a.name,c.* from contact c,account a,user u where c.account_id=a.account_id and u.uid=a.uid and u.section_id=?",
		     nparam=>1,
		     mode=>"r",
		     keys=>["contact","account"],
		     )
		   );

################
    $db->set_query(
		   "user groups",
		   ( sql=>"select * from usergroup where section_id=? order by name",
		     nparam=>1,
		     mode=>"r",
		     keys=>["usergroup"],
		     )
		   );

    $db->set_query(
		   "customer contacts",
		   ( sql=>"select a.name,c.* from contact c,account a where c.account_id=a.account_id and a.uid=0 and a.section_id=?",
		     nparam=>1,
		     mode=>"r",
		     keys=>["contact","account"],
		     )
		   );

    $db->set_query(
		   "location contacts",
		   ( sql=>"select l.content_id,l.title name,c.* from contact c,content l,content_type t where t.type=l.type and t.name='location' and c.content_id=l.content_id and l.content_id=?",
		     nparam=>1,
		     mode=>"r",
		     keys=>["contact","content","content_type"],
		     )
		   );

    $db->set_query(
		   "all content contacts",
		   ( 
		     sql=>"select l.*,l.title,c.address,c.city,c.provstate,c.phone1,c.email,c.web from content l, contact c where c.content_id=l.content_id order by l.sortkey,l.name,c.contact_id",
		     nparam=>0,
		     mode=>"r",
		     keys=>["contact","content"],
		     )
		   );
    $db->set_query(
		   "all locations",
		   ( 
		     sql=>"select l.*,l.title,c.address,c.city,c.provstate,c.phone1,c.email,c.web from content_type t,content l left join contact c on c.content_id=l.content_id where t.content_type_id=l.type and t.name='location' order by l.name,c.contact_id",
		     nparam=>0,
		     mode=>"r",
		     keys=>["contact","content","content_type"],
		     )
		   );
###
    $db->set_query("events with registrant contacts",
		   ( 
		     sql => "select e.evt_id,e.name event,fee.evt_fee_id,fee.name fee,ed.date from evt e,evt_date ed,evt_fee fee where ed.evt_id=e.evt_id and fee.evt_id=e.evt_id and fee.treat_as=0 and e.section_id=? order by ed.date desc,ed.time desc",
		     nparam => 1,
		     mode => "r",
		     keys => ["evt","evt_date","evt_fee"],
		     )
		   );
    $db->set_query(
		   "lookup account contacts by name",
		   ( sql=>"select a.name,c.* from contact c,account a left join user u on u.uid=a.uid where c.account_id=a.account_id and (a.section_id=? or u.section_id=?) and a.name like ?",
		     nparam=>3,
		     mode=>"r",
		     keys=>["contact","account","user"],
		     )
		   );
    $db->set_query(
		   "lookup location contacts by location name",
		   ( sql=>"select content.title name,c.* from content,contact c where c.content_id=content.content_id and content.title like ?",
		     nparam=>1,
		     mode=>"r",
		     keys=>["contact","content"],
		     )
		   );
    $db->set_query(
		   "lookup location contacts by contact name",
		   ( sql=>"select content.title name,c.* from content,contact c where c.content_id=content.content_id and c.name like ?",
		     nparam=>1,
		     mode=>"r",
		     keys=>["contact","content"],
		     )
		   );
    $db->set_query(
		   "lookup other contacts by name",
		   ( sql=>"select * from contact where account_id=0 and name like ?",
		     nparam=>1,
		     mode=>"r",
		     keys=>["contact"],
		     )
		   );
    $db->set_query(
		   "lookup content contacts by name",
		   ( sql=>sql=>"select c.* from content,contact c where content.content_id=c.content_id and content.title like ?",
#"select * from contact where content_id>0 and name like ?",
		     nparam=>1,
		     mode=>"r",
		     keys=>["content","contact"],
		     )
		   );
    $db->set_query(
		   "lookup account contacts by name",
		   ( sql=>"select c.* from account a,contact c where a.section_id=? and c.account_id=a.account_id and a.name like ?",
		     nparam=>2,
		     mode=>"r",
		     keys=>["account","contact"],
		     )
		   );
    $db->set_query(
		   "lookup content contacts by email",
		   ( sql=>"select c.* from contact c,contact_info i where c.contact_id=i.contact_id and i.name='email' and i.value like ?",
		     nparam=>1,
		     mode=>"r",
		     keys=>["contact","contact_info"],
		     )
		   );
    $db->set_query(
		   "lookup account contacts by email",
		   ( sql=>"select c.* from account a,contact c,contact_info i where a.section_id=? and c.account_id=a.account_id and c.contact_id=i.contact_id and i.name='email' and i.value like ?",
		     nparam=>2,
		     mode=>"r",
		     keys=>["account","contact","contact_info"],
		     )
		   );
    $db->set_query(
		   "lookup content contacts by phone",
		   ( sql=>"select c.* from contact c,contact_info i where c.contact_id=i.contact_id and i.name='phone' and i.value like ?",
		     nparam=>1,
		     mode=>"r",
		     keys=>["contact","contact_info"],
		     )
		   );
    $db->set_query(
		   "lookup account contacts by phone",
		   ( sql=>"select c.* from account a,contact c,contact_info i where a.section_id=? and c.account_id=a.account_id and c.contact_id=i.contact_id and i.name='phone' and i.value like ?",
		     nparam=>2,
		     mode=>"r",
		     keys=>["account","contact","contact_info"],
		     )
		   );
    $db->set_query(
		   "contact list categories",
		   ( sql=>"select distinct category from contact where category is not null and contact_id=?",
		     nparam=>1,
		     mode=>"r",
		     keys=>["contact"],
		     )
		   );
}

1;
