package Modules::Register;

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Util;
use ExSite::UI;
use ExSite::Time;
use ExSite::ReportBuilder;
use ExSite::Event;
use Modules::Registration::Fee;
use Modules::Registration::Ticket;
use Modules::Content;

use vars qw(@ISA $ml $ui);
@ISA = qw(Modules::Content);

sub read {
    my ($this,$options) = @_;
    my $in = new ExSite::Input;
    $this->{input} = $in->combine;
    $this->{post} = $in->post;
    $this->{query} = $in->query;
    $this->{is_post} = $in->is_post();
}

sub write {
    my ($this,$options) = @_;
    my $out;
    $ml = &get_obj("ML");
    my %opt = &DecodeString($options);

    return $out;
}

sub ioctl {
    my ($this) = shift;
    $_ = shift;
    if (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/ModuleName/) {
	return "Registration";
    }
    elsif (/Dependencies/) {
	return ["Calendar","Finance","AddrBook"];
    }
    elsif (/Category/) {
	return ["Events", "Applications"];
    }
    elsif (/PublishRule/) {
	# nightly republish should be adequate in most cases,
	# but can be overridden
	return $config{Register}{PublishRule} || "daily";
    }
}

sub ctrl_panel {
    my $this = shift;
    $this->{admin} = 1;
    $this->setup_querylib();
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    my $cmd = $this->{input}{cmd};
    my $id = $this->{input}{id};
    my $c = new ExSite::Content();
    my $out = &insert_js("misc");
    $share{Content} = $this->{content} = $c->get_content_obj($id);
    if ($id && $this->{content}->subtype =~ /event|fee/) {
	$out .= $this->pathbar($this->{content});
	$out .= $this->tools();
    }
    if ($cmd) {
	if ($cmd eq "conf") {
	    $out .= $this->configure($this->{content});
	}
	elsif ($cmd eq "edit") {
	    #$out .= $this->edit;
	    $out .= $this->update($this->{content},format=>"html",prompt=>"Event Description",name=>"event_descr");
	}
	elsif ($cmd eq "newfee") {
	    $out .= $this->new_fee;
	}
	elsif ($cmd eq "del") {
	    my $p = $this->{content}->parent();
	    $this->{content}->delete();
	    $ml->redirect($this->link(__plaintext=>1,cmd=>undef,id=>$p->id));
	    return;
	}
	elsif ($cmd =~ /schedule/) {
	    $out .= $this->schedule;
	}
	elsif ($cmd eq "fee") {
	    $out .= $this->show_fee($this->{content});
	}
	elsif ($cmd =~ /session/) {
	    $out .= $this->session;
	}
	elsif ($cmd =~ /^price/) {
	    $out .= $this->pricing();
	}
	elsif ($cmd =~ /^comm/) {
	    $out .= $this->communications();
	}
	elsif ($cmd =~ /fees/) {
	    $out .= $this->list_fees();
	    $out .= $ml->p(ExSite::UI->new->Button(label=>"+ New Fee",url=>$this->link(cmd=>"newfee")));
	}
	elsif ($cmd =~ /roster/) {
	    $out .= $this->roster();
	}
	elsif ($cmd =~ /acct/) {
	    return $this->show_account();
	}
	elsif ($cmd =~ /ticket/) {
	    if ($this->{input}{tid}) {
		return $this->ticket();
	    }
	    else {
		$out .= $this->roster();
	    }
	}
	elsif ($cmd =~ /^(publish|cancel|approve)$/) {
	    $out .= $this->$1;
	    $out .= $this->show();
	}
	elsif ($cmd =~ /copy/) {
	    $out .= $this->copy($this->{content});
	}
	else {
	    $out .= $this->error("Unrecognized command: $cmd");
	}
    }
    elsif ($id) {
	my $type = $this->{content}->subtype;
	if ($type eq "event") {
	    $out .= $this->show_event($this->{content});
	}
	elsif ($type eq "fee") {
#	    $out .= $this->show_fee($this->{content});
	    $out .= $this->register();
	}
	else {
	    $out .= $this->warn($ml->em(ucfirst $this->{content}->name)." is a ".$type."; the Registration module can only be used to manage Events and Fees. Click on 'Top' to see a list of available events or to setup a new one.");
	}
    }
    else {
	$out .= $this->list_events();
    }
    return $out;
}

sub setup_querylib {
    my $this = shift;
    if (! exists $share{querylib}{"invoice for registration"}) {
	my $db = $share{DB};
	$db->set_query("invoice for registration",
		       (
			sql => "select receivable.* from receivable_item,receivable where receivable_item.receivable_id=receivable.receivable_id and receivable.account_id=? and receivable_item.status != 'deleted' and receivable_item.objtype='ticket' and receivable_item.objid=?",
			nparam => 2,
			mode => "r",
			keys => ["receivable_item","receivable"],
		       )
	    );
    }
}


sub list_events {
    my $this = shift;
    my @evt;
    my $c = new ExSite::Content();
    my $tree = $c->get_content_tree();
    my @allevt = $tree->find({type=>$c->isubtype("event")});
    foreach my $evdata (@allevt) {
	my $evt = new ExSite::Event(data=>$evdata);
	if ($evt->has_registration || $this->{input}{allevt}) {
	    if ($evt->parent->subtype ne "event") { # skip activities
		if ($evt->allow("edit")) {
		    my $date = $evt->get_date();
		    if ($date->defined) {
			$evt->set("sortdate",$date->get_start->write("iso_date"));
		    }
		    else {
			$evt->set("sortdate","0000-00-00");
		    }
		    push @evt, $evt;
		}
	    }
	}
    }
    my @evtsort = sort { $b->{sortdate} cmp $a->{sortdate} } @evt;

    my $r = new ExSite::ReportBuilder(title=>$this->{input}{allevt} ? "Events" : "Events with Registration");
    $r->set("dynamic",1);
    $r->headers("Date","Event","Calendar","Site");
    foreach my $evt (@evtsort) {
	$r->push($evt->show_date_range(),
		 $ml->a($evt->label,{href=>$this->link(id=>$evt->id)}),
		 $evt->parent->label,
		 $evt->my_section->title);
    }
    my @tool = ( $ml->a("+ new event",{href=>"javascript:confirm_custom('Switch to Calendar module for event setup?','$config{server}{CGIpath}/$config{prog}{admin}/Calendar')",class=>"button_sm"}) );
    if ($this->{input}{allevt}) {
	push @tool, $ml->a("registration events only",{href=>$this->link(allevt=>1,id=>undef),class=>"button_sm"});
    }
    else {
	push @tool, $ml->a("all events",{href=>$this->link(allevt=>1,id=>undef),class=>"button_sm"});
    }
    $r->tools(join("\n",@tool));
    return $r->make();
}

sub list_fees {
    my $this = shift;
    my @evt;
    my $c = new ExSite::Content();
    my $evt = $c->get_content_obj($this->{input}{id});
    my @fee = $evt->get_contents("fee");
    my $r = new ExSite::ReportBuilder(title=>"Registration Fees");
    $r->nodata("No fees have been set up, yet.");
    $r->headers("Fee","Price","Sold","Available");
    foreach my $fee (@fee) {
	my $count = $fee->count_tickets();
	my $unsold = $fee->count_unsold_tickets();
	my @price;
	foreach my $price ($fee->get_allowed_prices) {
	    push @price, $fee->show_price($price);
	}
	$r->push(
	    $ml->a($fee->label,{href=>$this->link(cmd=>"fee",id=>$fee->id)}),
	    join(", ",@price),
	    $ml->div($count->{sold},{class=>"num"}),
	    $ml->div(defined $unsold ? $unsold : "n/a",{class=>"num"}),
	    );
    }
    my $out = $r->make();
    my @activities = $evt->activities();
    if (@activities > 0) {
	my $r = new ExSite::ReportBuilder(title=>"Activity Registration Fees");
	$r->nodata("No fees have been set up, yet.");
	$r->headers("Fee","Price","Sold","Available");
	foreach my $evt (@activities) {
	    my @fee = $evt->get_contents("fee");
	    foreach my $fee (@fee) {
		my $count = $fee->count_tickets();
		my $unsold = $fee->count_unsold_tickets();
		my @price;
		foreach my $price ($fee->get_allowed_prices) {
		    push @price, $fee->show_price($price);
		}
		$r->push(
		    $ml->a($fee->label,{href=>$this->link(cmd=>undef,id=>$fee->id)}),
		    join(", ",@price),
		    $ml->div($count->{sold},{class=>"num"}),
		    $ml->div(defined $unsold ? $unsold : "n/a",{class=>"num"}),
		    );
	    }
	}
	$out .= $r->make();
    }
    return $out;
}

sub new_fee {
    my $this = shift;
    my $c = $this->{content};
    my $out;
    my $post = $this->{post};
    if (scalar keys %$post > 0) {
	$post->{title} or $post->{title} = "Registration Fee";
	my %fdata = (
	    title=>$post->{title},
	    parent=>$c->id,
	    status=>$post->{status},
	    type=>$c->isubtype("fee"),
	    );
	my $fid = $c->new_content(%fdata);
	if ($fid) {
	    $fdata{content_id} = $fid;
	    if ($post->{description}) {
		my $fee = new Modules::Registration::Fee(data=>\%fdata);
		$fee->revise(data=>$post->{description},format=>"text");
	    }
	    if ($post->{price}) {
		$share{DB}->insert("price",
				   {content_id=>$fid,
				    status=>"active",
				    cost=>$post->{price},
				    access=>$post->{access}});
	    }
	    $ml->location($this->link(__plaintext=>1,id=>$c->id,cmd=>"fees"));
	}
	else {
	    # insert error?
	    $out .= &ExSite::Config::show_diagnostics();
	}
    }
    else {
	my $f = new ExSite::FormBuilder();
	$f->input(name=>"title",prompt=>"Fee Name",type=>"text",size=>40,required=>1);
	$f->input(name=>"price",prompt=>"Cost",type=>"text",size=>10,required=>0);
	$f->input(name=>"access",prompt=>"Access",type=>"select",
		  options=>[
		      {text=>"public",value=>0},
		      {text=>"users",value=>1},
		      {text=>"members",value=>2},
		      {text=>"administrators",value=>5},
		  ]);
	$f->input(name=>"status",prompt=>"Status",type=>"select",
		  options=>[
		      {text=>"open",value=>0},
		      {text=>"closed/draft",value=>4},
		  ]);
	$out .= $ml->h1("New Registration Fee") . $f->make();
	$out .= $ui->HelpBox(
	    title=>"Multiple price points or levels of access?",
	    pane=>"If this fee has multiple price points or different access levels, setup the lowest-level access (eg. public) first. Then go to the prices tool and add the other price points.",
	    );
    }
    return $out;
}

sub show {
    my ($this) = @_;
    my $c = $this->{content};
    my $out;
    if ($c->subtype eq "event") {
	$out .= $this->show_event($c);
    }
    elsif ($c->subtype eq "fee") {
	$out .= $this->show_fee($c);
    }
    else {
	$out .= $this->warn($ml->em(ucfirst $c->name)." is a ".$c->subtype()."; the Registration module can only be used to manage Events and Fees. Click on 'Top' to see a list of available events or to setup a new one.");
    }
    return $out;
}

sub tools {
    my ($this) = @_;
    my $type = $this->{content} ? $this->{content}->subtype() : undef;
    my $id = $this->{content} ? $this->{content}->id : undef;
    return undef if ($type !~ /event|fee/);
    my $icondir = "$config{server}{HTMLpath}/_ExSite/images/icons";
    my %tools = (
	conf => {label=>"configure",url=>$this->link(cmd=>"conf",id=>$id,__clear=>1),img=>"$icondir/conf.png",cmd=>"conf"},
	edit => {label=>"description",url=>$this->link(cmd=>"edit",id=>$id,__clear=>1),img=>"$icondir/edit.png",cmd=>"edit"},
	fees => {label=>"fees",url=>$this->link(cmd=>"fees",id=>$id,__clear=>1),img=>"$icondir/key.png",cmd=>"fees"},
	roster => {label=>"roster",url=>$this->link(cmd=>"roster",id=>$id,__clear=>1),img=>"$icondir/users.png",cmd=>"roster"},
	ticket => {label=>"ticketing",url=>$this->link(cmd=>"ticket",id=>$id,__clear=>1),img=>"$icondir/tag.png",cmd=>"ticket"},
#	schedule => {label=>"schedule",url=>$this->link(cmd=>"schedule"),img=>"$icondir/time.png"},
	comm => {label=>"communications",url=>$this->link(cmd=>"comm",id=>$id,__clear=>1),img=>"$icondir/email.png",cmd=>"comm"},
	sales => {label=>"sales",img=>"$icondir/dollar.png",links=>[{label=>"pricing",url=>$this->link(cmd=>"price",id=>$id,__clear=>1),icon=>"$icondir/dollar.png"},{label=>"merchandise",url=>$this->link(cmd=>"merch",id=>$id,__clear=>1),icon=>"$icondir/cart.png"},{label=>"revenues",url=>$this->link(cmd=>"revenues",id=>$id,__clear=>1),icon=>"$icondir/money.png"}]},
	pricing => {label=>"pricing",url=>$this->link(cmd=>"price",id=>$id,__clear=>1),img=>"$icondir/dollar.png",cmd=>"price"},
	merch => {label=>"merchandise",url=>$this->link(cmd=>"merch",id=>$id,__clear=>1),img=>"$icondir/cart.png",cmd=>"merch"},
	revenues => {label=>"revenues",url=>$this->link(cmd=>"revenues",id=>$id,__clear=>1),img=>"$icondir/money.png",cmd=>"revenues"},
	register => {label=>"register",url=>$this->link(cmd=>undef,id=>$id,__clear=>1),img=>"$icondir/approve.png",cmd=>undef},
	preview => {label=>"preview",url=>"javascript:openOLFrame('".$this->{content}->get_url_dynamic()."')",img=>"$icondir/view.png"},
	copy => {label=>"copy",url=>$this->link(cmd=>"copy",id=>$id,__clear=>1),img=>"$icondir/copy.png",cmd=>"copy"},
	publish => {label=>"publish",url=>$this->link(cmd=>"publish",id=>$id,__clear=>1),img=>"$icondir/publish.png",cmd=>"publish"},
	delete => {label=>"DELETE",url=>$this->link(cmd=>"del",id=>$id,__clear=>1),img=>"$icondir/delete.png",confirm=>"Really delete this $type?",tone=>"bad",cmd=>"del"},
	);
    my @evttool = ("conf","schedule","preview","fees","roster","comm","register",undef,"revenues",undef,"copy","publish",undef,"delete");
    my @feetool = ("conf","edit","schedule","preview","roster","comm","register",undef,"sales",undef,"copy","publish",undef,"cancel","delete");
    my @links;
    my @tools = $type eq "fee" ? @feetool : @evttool;
    foreach my $tool (@tools) { push @links, $tools{$tool} if $tools{$tool}; }
    return 
	$ui->IconBar(cmd=>$this->{input}{cmd},links=>\@links).
	$ui->OverlayFrame();
}

sub show_event {
    my ($this,$evt) = @_;
    return $this->error("Permission denied.") if (! $evt->allow("update"));
    $evt->load_revision("newest");
    return $evt->show();
}

sub show_fee {
    my ($this,$fee) = @_;
    return $this->error("Permission denied.") if (! $fee->allow("update"));
    $fee->load_revision("newest");

    my $help = $fee->is_ticketed ?
	"This is a ticketed event. When all tickets are sold, the event will sell-out. ".$ml->a("You can issue more tickets here.",{href=>$this->link(cmd=>"newtix")}) :
	"This event has ad-hoc registration. New tickets are issued as they are purchased, and the event will not sell out.";
    my $out = 
	$ml->div(
	    $ml->h1($fee->title).
	    $ui->HelpBox(title=>"About Ticketing",pane=>$help,float=>"right").
	    $fee->report(),
	    {class=>"clearfix"}
	);

    return $out;
}

sub register {
    my $this = shift;
    my $c = $this->{content};
    my $type = $c->subtype();
    if ($type eq "fee") {
	return $c->preview();
    }
    elsif ($type eq "event") {
	my $out;
	if ($c->is_activity) {
	    my $mainevt = $c->main_event();
	    $out .= $this->warn(&substitute($msg{"You need to register in ".$ml->em($ml->a("[[event]]",{href=>"[[link]]"}))." before you can register in this activity."},{event=>$mainevt->title,link=>$mainevt->get_url()}));
	}
	my $feeout;
	#my $uri = new ExSite::URI;
	foreach my $fee ($c->get_contents("fee")) {
	    #$uri->parameter("id",$fee->id);
	    #$fee->set("url",$uri);
	    $feeout .= $fee->summary();
	}
	if ($feeout) {
	    $out .= $ml->div($feeout,{class=>"FeeIndex"});
	}
	else {
	    $out .= $this->error($msg{"No fees to register in!"});
	}
	return $out;
    }
    else {
	return $this->error($c->title." is not a registration fee.");
    }
}

sub session {
    my $this = shift;
    if (ref $session{registrations} eq "ARRAY") {
	my $tic = new Modules::Registration::Ticket(data=>$session{registrations}[-1]);
	my $uri = new ExSite::URI();
	my $fee = new Modules::Registration::Fee(id=>$tic->getdata("content_id"));
	if ($this->{admin}) {
	    $fee->set("content_link_type","id");
	}
	my $out .= $fee->index(url=>$uri,ticket=>$tic);
	$out .= $fee->show_cart();
	return $out;
    }
    return $this->warn("You have no registrations in progress.");
}

sub roster_old {
    my $this = shift;
    my ($event,$fee,$title);
    my $tix = new ExSite::ObjectList(type=>"ticket");
    my $out;  # = $ml->h1("Roster");
    my $ml = &get_obj("ML");
    my @data;
    if ($this->{content}->subtype eq "event") {
	$event = $this->{content};
	foreach my $fee ($event->get_contents("fee")) {
	    push @data, $fee->get_roster_data();
	}
	$title = $event->title;
    }
    else {
	$fee = $this->{content};
	$title = $fee->title;
	push @data, $fee->get_roster_data();
    }
    my $r = new ExSite::ReportBuilder(title=>"Tickets for $title");
    $r->nodata("No tickets found.");
    $r->headers("#","Surname","Given Name","Registration Date","Registration Type","Status","Account","Response");
    $tix->reset;
    foreach my $reg (@data) {
	my $tid = $reg->{ticket_id};
	my $tinfo = $reg->{ticket_info};
	my $ticketname = $tinfo ? "$tid - $tinfo" : $tid;
	my $fee = new Modules::Registration::Fee(id=>$reg->{content_id});
	my $status = ucfirst $reg->{status};
	$r->push(
	    $ml->a($ticketname,{href=>$this->link(cmd=>"ticket",tid=>$tid)}),
	    $ml->span($reg->{first_name},{class=>"TicketName$status"}),
	    $ml->span($reg->{last_name},{class=>"TicketName$status"}),
	    $reg->{ctime},
	    $fee->label,
	    $ml->span($status,{class=>"Ticket$status"}),
	    $reg->{account_id},
	    $reg->{response_id},
#	    $claim->showdata("account_id"),
#	    $claim->showdata("response_id"),
	    );
    }
    $r->foot($ml->span("Strikeout",{class=>"TicketNameCanceled"})." names indicate tickets that were selected, but never purchased. They have since been released for other purchasers.");
    $out .= $r->make();
    return $out;
}

sub roster {
    my ($this,%opt) = @_;
    my $out;
    my $db = $share{DB};
    my $input = new ExSite::Input;
    my $post = $input->post();
    my $is_post = scalar keys %$post;
    my %combine = (%opt, %{$this->{input}});
    my $in = \%combine;
    if (! exists $in->{incl_confirmed}) {
	# set defaults
	$in->{incl_confirmed} = 1;
	$in->{incl_reserved} = 1;
	$in->{incl_held} = 1;
	$in->{incl_waitlist} = 1;
	$in->{incl_canceled} = 1;
    }

    # report options
    my $f = new ExSite::FormBuilder();

    # status filters
    $f->input(name=>"incl_confirmed",type=>"checkbox",prompt=>"confirmed registrations",class=>"ticStatus",checked=>$in->{incl_confirmed});
    $f->input(name=>"incl_reserved",type=>"checkbox",prompt=>"reserved/unpaid registrations",class=>"ticStatus",checked=>$in->{incl_reserved});
    $f->input(name=>"incl_held",type=>"checkbox",prompt=>"on-hold registrations",class=>"ticStatus",checked=>$in->{incl_held});
    $f->input(name=>"incl_waitlist",type=>"checkbox",prompt=>"waitlist registrations",class=>"ticStatus",checked=>$in->{incl_waitlist});
    $f->input(name=>"incl_canceled",type=>"checkbox",prompt=>"canceled registrations",class=>"ticStatus",checked=>$in->{incl_canceled});

    # add information
    $f->input(name=>"incl_response",type=>"checkbox",prompt=>"registration form responses",checked=>$in->{incl_response});
    $f->input(name=>"incl_contact",type=>"checkbox",prompt=>"purchaser's contact information",checked=>$in->{incl_contact});
    $f->input(name=>"incl_activities",type=>"checkbox",prompt=>"activity registrations",checked=>$in->{incl_activities});
    my $m = &get_obj("user",$share{DB}->my_uid);
    if ($m->can("member_type") && $m->can("status")) {
	$f->input(name=>"incl_membership",type=>"checkbox",prompt=>"membership information",checked=>$in->{incl_membership});
    }
    $f->input(name=>"id",type=>"hidden",value=>$in->{id});
    $f->input(name=>"cmd",type=>"hidden",value=>"roster");

    $f->template("",$ml->div("[[input]] [[prompt]]"),"");
    my $br = $ml->br;
    $f->template($ml->div($ml->strong("Rows").$br.
			  "[[incl_confirmed:input]] [[incl_confirmed:prompt]]$br".
			  "[[incl_reserved:input]] [[incl_reserved:prompt]]$br".
			  "[[incl_held:input]] [[incl_held:prompt]]$br".
			  "[[incl_waitlist:input]] [[incl_waitlist:prompt]]$br".
			  "[[incl_canceled:input]] [[incl_canceled:prompt]]$br".
			  "[[incl_activities:input]] [[incl_activities:prompt]]$br",
			  {class=>"pull-left",style=>"width:300px"}).
#		 $feeout.
		 $ml->div($ml->strong("Columns").$br.
			  "[[incl_response:input]] [[incl_response:prompt]]$br".
			  "[[incl_contact:input]] [[incl_contact:prompt]]$br".
			  "[[incl_membership:input]] [[incl_membership:prompt]]"));
    my $dump_url = "javascript:confirm_custom('This will export ALL registration data, including failed and incomplete registrations, to a CSV file. Continue?','".$this->link(regcmd=>"dump")."')";
    $f->set("buttons",$br.$br.
	    $ml->input(undef,{type=>"submit",value=>"Generate Roster"}).
	    $ml->input(undef,{type=>"button",value=>"Export ALL data",onclick=>$dump_url})
	);
    
    $out .= $ui->Overlay(label=>"Roster Options (click to view)",
			 title=>"Roster Options",
			 pane=>$ml->div($f->make(),{class=>"clearfix"}),
			 width=>"600px",
			 class=>"btn-info btn-sm",
			 );

    my $r = $this->get_roster(%$in);

    my $foot;
    if ($in->{fmt} eq "xls") {
	# export to excel
	$ml->cancel;
	print "Content-type: application/vnd.ms-excel\ncontent-disposition: attachment; filename=registrations.xls\n\n";
	$r->export("excel");
    }
    elsif ($in->{fmt} eq "csv") {
	# export to csv
	$ml->cancel;
	print "Content-type: text/comma-separated-values\n\n";
	print $r->export("csv");
    }
    else {
	# HTML; include export links
	my $url = new ExSite::URI();
	$url->query(
	    incl_confirmed => $in->{incl_confirmed},
	    incl_reserved => $in->{incl_reserved},
	    incl_held => $in->{incl_held},
	    incl_waitlist => $in->{incl_waitlist},
	    incl_canceled => $in->{incl_canceled},
	    incl_response => $in->{incl_response},
	    incl_contact => $in->{incl_contact},
	    incl_activities => $in->{incl_activities},
	    incl_membership => $in->{incl_membership},
	    fmt=>"xls",
	    );

	my $excel_url = $url->write;
	$url->query(fmt=>"csv");
	my $csv_url = $url->write;
	$foot .= $ml->p("Roster generated ".localtime().
			" &bull; ".
			$ui->Button(type=>"link-button",label=>"Excel",url=>$excel_url,faicon=>"download",size=>"s").
			" &bull; ".
			$ui->Button(type=>"link-button",label=>"CSV",url=>$csv_url,faicon=>"download",size=>"s"));

    }

    $out .= $r->make;
    $out .= $foot;
    $out .= $ui->OverlayFrame();
    return $out;
}

sub get_roster {
    my ($this,%opt) = @_;
    my ($event,$fee,$title,$section_id);
    my $ml = &get_obj("ML");
    $this->{is_admin} = $share{DB}->is_admin();
    my @data;
    if ($this->{content}->subtype eq "event") {
	$event = $this->{content};
	foreach my $fee ($event->get_contents("fee")) {
	    push @data, $fee->get_roster_data(%opt);
	}
	$title = $event->title;
	$section_id = $event->section->id;
    }
    else {
	$fee = $this->{content};
	$title = $fee->title;
	$section_id = $fee->section->id;
	push @data, $fee->get_roster_data(%opt);
    }

    # headers
    my @header = ("#","Surname","Given Name","Registration Date","Registration Type","Status","Account");
    if ($opt{incl_contact}) {
	push @header,"Address","City","Prov/State","Postal/Zip Code","Phone","Email";
    }
    push @header, "Response";

    my $r = new ExSite::ReportBuilder(title=>"Tickets for $title",dynamic=>1);
    $r->nodata("No tickets found.");
    $r->headers(@header);
    foreach my $reg (reverse @data) {
	my $tid = $reg->{ticket_id};
	my $fee = new Modules::Registration::Fee(id=>$reg->{content_id});
	my $status = ucfirst $reg->{status};
	my @row = (
#	    $ml->a($tid,{href=>$this->link(cmd=>"ticket",tid=>$tid)}),
	    $ml->a($tid,{href=>"javascript:openOLFrame('".$this->link(cmd=>"ticket",tid=>$tid)."')"}),
	    $ml->span($reg->{last_name},{class=>"TicketName$status"}),
	    $ml->span($reg->{first_name},{class=>"TicketName$status"}),
	    $reg->{ctime},
	    $ml->a($fee->label,{href=>$this->link(id=>$fee->id)}),
	    $ml->span($status,{class=>"Ticket$status"}),
	    $this->showdata_link($reg->{account},$this->link(cmd=>"acct","tid"=>$reg->{ticket_id},acct=>$reg->{account_id}),"medium"),
	    );
	if ($opt{incl_contact}) {
	    push @row,
	    $reg->{address},
	    $reg->{city},
	    $reg->{provstate},
	    $reg->{pcode},
	    $reg->{phone},
	    $reg->{email};
	}
	if ($reg->{response_id}) {
	    push @row, $this->showdata_link($reg->{response_id},"$config{server}{server}$config{server}{CGIpath}/$config{prog}{ctrlpanel}/Forms?cmd=responses&response=$reg->{response_id}&id=$reg->{form}","large");
	}
	else {
	    push @row, "n/a";
	}

	$r->push(@row);
    }
    return $r;
}

sub showdata_link {
    my ($this,$anchor,$url,$popup) = @_;
    if ($this->{is_admin}) {
#	my $link = $popup ? "javascript:popup_$popup('$url')" : $url;
	my $link = "javascript:openOLFrame('$url')";
	return $ml->a($anchor,{href=>$link});
    }
    else {
	return $anchor;
    }
}

sub ticket {
    my $this = shift;
    my $ticket = new Modules::Registration::Ticket(id=>$this->{input}{tid});
    my $out = $ticket->show();


    # also show related tickets
    return $out;
}

sub show_account {
    my ($this,$ticket_id) = @_;
    my $out;
    $ml or $ml = &get_obj("ML");
    $ticket_id or $ticket_id = $this->{input}{tid};
    my $tic = new Modules::Registration::Ticket(id=>$ticket_id);
    my $claim = $tic->get_claim;
    my $acct_id = $claim->getdata("account_id");
    my $acct = new Modules::Finance::Account(id=>$acct_id);
    if ($tic->exists && $acct->exists) {

	### FIXME: sanity check / access control?

	# find the invoice that references this registration
	my @inv = $share{DB}->get_query("invoice for registration",$acct->id,$ticket_id);
	if (@inv > 0) {
	    my $inv = new Modules::Finance::Receivable(data=>$inv[-1]);
	    $out .= $inv->show(date=>1,payment=>1,name=>1,summarize_sucharges=>1,account_info=>1,allow=>1,status=>1);
	    my @button = (
		$ml->a("close",{href=>"javascript:window.close()",class=>"button"})
		);
	    if ($share{DB}->is_admin) {
		my $sid = $acct->getdata("section_id");
		push @button, $ml->a("jump to Payments module",{href=>"$config{server}{server}$config{server}{CGIpath}/$config{prog}{ctrlpanel}/Pay?section_id=$sid&acct=$acct_id&inv=".$inv->id,class=>"button"});
	    }
	    $out .= $ml->p(join(" ",@button));
	}
	else {
	    $out = $this->warn("No matching invoice found.");
	}
    }
    else {
	$out = $this->warn("Account and/or registration not found.");
    }
    return $out;
}

sub copy {
    my ($this,$c) = @_;
    my $newid;
    if ($c->subtype eq "event") {
	return $this->copy_evt($c);
    }
    elsif ($c->subtype eq "fee") {
	return $this->copy_fee($c);
    }
    else {
	return $this->SUPER::copy($c);
    }
    if ($newid) {
	# done, now let them reconfigure it
	my $ml = &get_obj("ML");
	$ml->location($this->link(__plaintext=>1,cmd=>"conf",id=>$newid));
	return;
    }
    else {
	return $this->error("Failed to copy ".$c->subtype()." ".$c->id.".");
    }

}

sub copy_evt {
    my ($this,$evt) = @_;
    if ($evt->subtype() ne "event") {
	$this->error("not an event!");
	return undef;
    }
    if ($this->{is_post}) {
	my $newid = $evt->copy_r(
	    title=>$this->{post}{title},
	    _date=>$this->{post}{newdate}
	    );
	if ($newid) {
	    $ml->location($this->link(__plaintext=>1,cmd=>"conf",id=>$newid));
	    return;
	}
	else {
	    return $this->error("Failed to copy event ".$evt->id.".");
	}
    }
    my $out;
    my $date = $evt->get_date;
    my $dateval = $date ? $date->get_start()->write("sql_date") : "";
    $out .= $ml->h1("Copy Event");
    $out .= $ml->p("This will set up a new event with identical configuration to ".
		   $ml->strong($ml->em($evt->name)).", except for the dates.");
    $out .= $ml->p("This event date: ".$evt->show_date());
    $out .= $ml->form(
	$ml->p("New event start date: ".$ml->input(undef,{class=>"date-pick",size=>12,value=>$dateval,type=>"text",name=>"newdate"})).
	$ml->p("New event name: ".$ml->input(undef,{size=>60,value=>$evt->title,type=>"text",name=>"title"})).
	$ml->p($ml->input(undef,{type=>"submit",value=>"Copy"})),
	{method=>"post"}
	);
    return $out;
}

sub copy_fee {
    my ($this,$fee) = @_;
    if ($fee->subtype() ne "fee") {
	$this->error("not a registration fee!");
	return undef;
    }
    my $newid = $fee->copy_r(label=>$fee->label." - COPY");
    if ($newid) {
	$ml->location($this->link(__plaintext=>1,cmd=>"conf",id=>$newid));
	return;
    }
    else {
	return $this->error("Failed to copy fee ".$fee->id.".");
    }
}

# communications
# settings
# messages
# - confirm
# - confirm_guest
# - reminder
# - followup

sub communications {
    my $this = shift;
    my $c = $this->{content};
    


}

#--------------------------- E-COMMERCE -----------------------------

sub payment {
    my ($this,%opt) = @_;
    my $ticket = $opt{ticket};
    my $regname = $this->{registrant}->name;
    my $fee = $ticket->fee;
    my $evt = $this->event;
    my $price = $fee->price();
    my $cost = $price ? $price->{cost} : 0.00;
    my $feename = $fee->name();
    my $evtname = $evt->name();
    my $acctcode = $this->meta_get("acctcode") || $config{Fee}{acctcode};
    my %item = (
	item=>$msg{Registration}." ($regname)",
	description=> ($feename eq $evtname) ? $msg{$feename} : "$evtname - $msg{$feename}",
	cost=>$cost,
	objtype=>"evt_reg",
	objid=>$this->{registrant}->id,
	objtype=>"ticket",
	objid=>$ticket ? $ticket->id : 0,
	parent=>$ticket ? $ticket->getdata("parent") : 0,
	acctcode_id=>$acctcode,
	acctcode2=>$evt->mainevt->id,
	acctcode3=>$fee->id,
	);
    if (! $share{DB}->level) {
	$item{uid} = $share{DB}->my_uid;
	if (! exists $session{customer_info}) {
	    # remember purchaser info for checkout
	    my %info = ( name=>$regname );
	    if ($this->{response_data}) {
		# we have some info about the registrant already; try to 
		# re-use anything that looks like contact info
		foreach my $cf (qw(address city provstate country pcode email phone cell fax website)) {
		    if (exists $this->{response_data}{$cf}) {
			$info{$cf} = $this->{response_data}{$cf};
		    }
		}
	    }
	    $session{customer_info} = \%info;
	}
    }

### continue shopping link must be setup by the Register module
#    # continue shopping link (don't use link())
#    my $uri = new ExSite::URI(uri=>$this->link(__plaintext=>1,regcmd=>"session"));
#    $uri->query(first_name=>undef,last_name=>undef);
#    if ($this->{evt}->is_activity) {
#	# continue at main event, not the activity
#	$uri->query(evt=>$this->{evt}->is_activity,fee=>undef,preg=>undef);
#    }
#    else {
#	$uri->query(evt=>$this->{evt}->id);
#    }
#    $session{continue_shopping_url} = $uri->write_full();

    my $out .= $this->add_to_cart(%item);

    # check for a restricted payment method
    my $pay_method = $this->meta_get("payment_method");
    if ($pay_method) {
	$session{payment_method} = $pay_method;
    }

    if ($cost < 0.01 && ! $this->{waitlist} && ! $this->{admin}) {
	# you still have to checkout to confirm your registration,
	# even if it is free.
	if ($this->event->activities->count == 0) {
	    # do not show this message if this is a free main fee with
	    # paid activities
	    my $message = $config{Fee}{message}{checkout_nocost} || "Although this registration has no cost, you must proceed through checkout in order to confirm. If you do not check out, your registration will be canceled.";
	    $out .= $ml->p($msg{$message},{class=>"EvtRegNoCost"});
	}
    }
    return $out;
}

sub add_to_cart {
    my ($this,%cartdata) = @_;
    my $out = $this->run_handler("EvtReg_add_to_cart",%cartdata);
    return $out if (defined $out);

    if (! $cartdata{acctcode_id} && $config{EvtReg}{acctcode}) {
	$cartdata{acctcode_id} = $config{EvtReg}{acctcode};
    }

    if ($share{Page} && ! $this->{waitlist}) {
	# use regular shopping cart
	my $pay = &get_module("Pay");
	if ($pay) {
	    # get the regular cart to do all the work
	    $cartdata{cart} = "add";
	    $cartdata{silent} = 1; # suppress usual cart chatter
	    my $error_count = &AtError();
	    $out .= $pay->write(&EncodeHash(%cartdata));
	    if (&AtError($error_count)) {
		$out .= $pay->show_diagnostics("error","html");
	    }
	}
	else {
	    $out .= $this->error($@);
	}
	if ($session{invoice} && ! $this->{registrant}->getdata("account_id")) {
	    # looks like a new anonymous account - update the reg record
	    my $inv = new Modules::Finance::Receivable(id=>$session{invoice});
	    $this->{registrant}->setdata("account_id",$inv->getdata("account_id"));
	    $this->{registrant}->force_save();
	}

	# set back-to-shopping link to go to registration session
	my $spage = &service_page("EvtReg",$this->{section_id});
	if ($spage) {
	    $session{pay_redirect} = $spage->link(evt=>$this->{evt}->id,regcmd=>"session");
	}
    }
    else {
	# non-ecommerce invoice (waitlist or control panel)
	my $inv = $this->get_invoice(waitlist=>$this->{waitlist});
	if ($inv) { 
	    my $item = new Modules::Finance::ReceivableItem();
	    my $uid = $share{DB}->my_uid || 0;
	    $item->setdata("receivable_id",$inv->id);
	    foreach my $col (qw(item description cost acctcode_id uid note objtype objid)) {
		if ($cartdata{$col}) {
		    $item->setdata($col,$cartdata{$col});
		}
	    }
	    my $uid = $share{DB}->my_uid || 0;
	    $item->setdata("receivable_id",$inv->id);
	    $item->setdata("uid",$uid);
	    $item->setdata("note","autogenerated from control panel registration");
	    if (! $item->save()) {
		$out .= $item->show_diagnostics("error","html");
	    }
	}
	else {
	    $out .= &ExSite::Config::show_diagnostics();
	}
    }
    # free item warning is issued in payment, above
#    if ($cartdata{cost} < 0.01 && ! $this->{waitlist} && ! $this->{admin}) {
#	$out .= $ml->p($msg{"Although this registration has no cost, you must proceed through checkout in order to confirm. If you do not check out, your registration will be canceled."});
#    }
    return $out;
}

sub view_cart {
    my ($this) = @_;
    my $out = $this->run_handler("EvtReg_view_cart");
    return $out if (defined $out);
    if ($this->{waitlist}) {
	my $message = $config{EvtReg}{message}{waitlist_done} || "If space becomes available, an administrator will contact you to arrange payment. NO PAYMENT IS REQUIRED AT THIS TIME. These charges are shown for informational purposes only.";
	$out .= $ml->p($msg{$message});
	my $inv = $this->get_invoice();
	if ($inv) { 
	    $out .= $inv->show();
	    
	}
	else {
	    $out .= $this->show_diagnostics("error","html");
	}

	#### FIXME: prompt for contact info??

    }
    elsif ($share{Page}) {
	my $message = $config{EvtReg}{message}{checkout} || "Check out to complete your purchase.";
	$out .= $ml->p($msg{$message});
	$out .= "<!--&Pay(cart=view)-->";
    }
    else {
	my $inv = $this->get_invoice();
	if ($inv) { 
	    $out .= $inv->show();
	    $out .= $ml->p($ml->a("Done - Finish Registration",{href=>$this->link(regcmd=>"done_admin_reg",preg=>undef),class=>"button"}).
			   $ml->a("Cancel - Start Over",{href=>$this->link(regcmd=>"cancel_admin_reg",preg=>undef),class=>"button"}));
	}
	else {
	    $out .= $this->show_diagnostics("error","html"); 
	}
    }
    return $out;
}

sub get_invoice {
    my ($this,%opt) = @_;

    if (! $this->{invoice}) {
	if ($session{invoice_nocart} && $opt{waitlist}) {
	    # already have a waitlist invoice going
	    $this->{invoice} = new Modules::Finance::Receivable(id=>$session{invoice_nocart});
	}
	elsif ($session{invoice} && ! $opt{waitlist}) {
	    # already have a regular invoice going
	    $this->{invoice} = new Modules::Finance::Receivable(id=>$session{invoice});
	}
	else {
	    # start a new invoice
	    my $acct = $this->get_account();
	    if ($acct) {
		my $inv = $acct->make_receivable(); # will be blank
		$this->{invoice} = $inv;
		if ($opt{waitlist}) {
		    $session{invoice_nocart} = $inv->id();
		}
		else {
		    $session{invoice} = $inv->id();
		}
	    }
	    else {
		$this->error("Failed to setup account.");
	    }
	}
    }
    return $this->{invoice};
}

sub get_invoice_id {
    my ($this,%opt) = @_;

    if ($this->{invoice}) {
	return $this->{invoice}->id;
    }
    elsif ($session{invoice_nocart} && $opt{waitlist}) {
	return $session{invoice_nocart};
    }
    elsif ($session{invoice} && ! $opt{waitlist}) {
	return $session{invoice};
    }
    return undef;
}

sub get_account {
    my $this = shift;
    if (! $this->{account}) {
	my $acct = new Modules::Finance::Account();
	if ($this->{admin}) {
	    if ($session{account}) {
		# already have a registration going
		$acct->setup(id=>$session{account});
	    }
	    else {
		# put admin-side registrations into new accounts
		$acct->setdata("name",$this->{registrant_name});
		$acct->setdata("section_id",$this->{section_id});
		if ($acct->force_save) {
		    $session{account} = $acct->id;
		}
	    }
	}
	elsif (! $acct->setup_my_account) {
	    my $uid = $share{DB}->my_uid;
		my $site = $share{DB}->this_site;
		$acct->setdata("section_id",$site ? $site->{content_id} : 0);
	    if ($uid) {
		# user does not have an account yet
		$acct->setdata("name",$share{DB}->my_name);
		$acct->setdata("uid",$uid);
	    }
	    else {
		# member of public
		$acct->setdata("name",$this->{registrant_name});
	    }
	    if ($acct->force_save) {
		$session{account} = $acct->id;
	    }
	}
	$this->{account} = $acct;
    }
    return $this->{account};
}

# activate_invoice : mark any registration on an invoice as unconfirmed
# THIS IS USED AS A HANDLER when $inv->activate() is called 

sub activate_invoice {
    my ($this,$inv,$notify) = @_;
    my $db = $share{DB};
    if ((ref $inv) =~ /Receivable/) {
	my $acct = $inv->account();
	my $items = $inv->loaditems();
	my @regid;
	while (my $item = $items->next) {
	    my $type = $item->getdata("objtype");
	    my $id = $item->getdata("objid");
	    if ($type && $id) {
		if ($type eq "evt_reg") {
		    # mark registration as unconfirmed
		    my $r = new Modules::Registration::Registration(id=>$id);
		    $r->setdata("status","unconfirmed");
		    $r->setdata("account_id",$acct->id);
		    $r->force_save; # in case user is public
		    push @regid, $id;

		    if (! $this->{evt}) {
			# we've been called from a a Pay handler, so our
			# EvtReg object hasn't been properly set up
			my $evt = $r->event();
			$this->{evt} = $evt->main_event;
		    }

		    # add guest account contact info
		    my $fee = $r->fee;
		    if ($fee && $fee->getdata("options") =~ /create address cards for guests/) {
			if (! $r->getdata("guest_account_id")) {
			    my $site = $share{DB}->this_site();
			    if ($site) {
				$r->make_guest_account($site->{content_id});
			    }
			}
		    }
		}
	    }
	}

	if ($notify && scalar @regid > 0) {
	    # send notification of registration
	    #$this->notify(inv=>$inv->id,regid=>\@regid);
	    $this->notify(inv=>$inv->id);
	}

	$this->clear_registrant_history();
    }
}

### WARNING: You should install a Pay_delete_item handler to
### also remove the registration record that it points to.

sub delete_cart_registration {
    my $pay = shift;  # we are in a Pay object!
    my $item = shift;
    my $out;
    if ($item->getdata("objtype") eq "evt_reg") {
	my $regid = $item->getdata("objid");
	my $reg = new Modules::Registration::Registration(id=>$regid);
	if ($session{registrant}) {
	    if ($session{registrant}{evt_reg_id} == $regid) {
		delete $session{registrant};
	    }
	}
	if ($session{main_registrant}) {
	    if ($session{main_registrant}{evt_reg_id} == $regid) {
		delete $session{main_registrant};
	    }
	}
	if ($session{last_registration}) {
	    if ($session{last_registration}{evt_reg_id} == $regid) {
		delete $session{last_registration};
	    }
	}
	$reg->delete;
#	if (! $EvtReg) {
#	    # might come from a call to Pay, not EvtReg
#	    $EvtReg = &get_module("EvtReg");
#	}
#	$EvtReg->rebuild_session();
	#$reg->cancel;  # keeps better history, but still shows up in the session
    }
    return $out;
}

# rebuild_session: fix registrants in session if we start deleting things

sub rebuild_session {
    my $this = shift;

    # find all the registrations on the invoice
    my $inv = $this->get_invoice();
    $inv->clear_items();
    my $items = $inv->loaditems();
    my %ritem;
    while (my $item = $items->next) {
	if ($item->getdata("objtype") eq "evt_reg") {
	    $ritem{$item->getdata("objid")} = $item;
	}
    }

    # remember any registrations in the current session
    my %reg;
    $reg{$session{registrant}{evt_reg_id}} = $session{registrant};
    $reg{$session{main_registrant}{evt_reg_id}} = $session{main_registrant};
    $reg{$session{last_registration}{evt_reg_id}} = $session{last_registration};

    # clear the session to start over
    delete $session{registrant};
    delete $session{main_registrant};
    delete $session{last_registration};

    # rebuild the session
    foreach my $rid (sort keys %ritem) {
	my $data = $reg{$rid};
	if (! $session{main_registrant}) {
	    if (! $data) {
		my $r = new Modules::Registration::Registration(id=>$rid);
		$data = $r->get();
	    } 
	    $session{main_registrant} = $session{registrant} = $session{last_registration} = $data;
	    next;
	}
	my $r = new Modules::Registration::Registration();
	if ($data) {
	    $r->setup(data=>$data);
	}
	else {
	    $r->setup(id=>$rid);
	    $data = $r->get();
	}
	$session{last_registration} = $data;
	if (! $r->getdata("parent")) {
	    $session{registrant} = $data;
	}
    }
}

sub validate_cart {
    my ($this,$final) = @_; # $this may actually be a Pay object!
    # skip validation for admins
    return undef if (! $share{Page});
    # because we come from a Pay object, we may not have loaded EvtReg prereqs
#    $EvtReg or $EvtReg = &ExSite::Module::get_module("EvtReg");
    my $out;
    my $db = $share{DB};
    my $inv = $this->get_invoice();
    my $acct = $inv->account();
    my $ndel = 0;
    my $items = $inv->loaditems();
    my %ritem;
    while (my $item = $items->next) {
	if ($item->getdata("objtype") eq "evt_reg") {
	    $ritem{$item->getdata("objid")} = $item;
	}
    }
    if (scalar keys %ritem > 0) {
	# cart contains registrations - make reg objects for each one
	my $ml = &ExSite::Config::get_obj("ML");
	my (%reg,%fee,%evt,%parent);
	foreach my $r (keys %ritem) {
	    $reg{$r} = new Modules::Registration::Registration(id=>$r);
	    $fee{$r} = $reg{$r}->fee();
	    $evt{$r} = $fee{$r} ? $fee{$r}->event() : undef;
	    $parent{$r} = $reg{$r}->getdata("parent");
	}
	foreach my $r (keys %ritem) {
	    # check for valid registration
	    if (! $reg{$r}->exists) {
		$out .= &validate_delete_item($this,$ritem{$r},"Registration not found - [[item]] removed from cart.");
		$ndel++;
		next;
	    }
	    # check for activity prerequisites
	    my $p = $parent{$r};
	    if ($p && ! exists $reg{$p}) {
		# this is an activity, but the user does not have
		# the prerequisite parent event in their cart.
		my $in_parent = 0;

		# perhaps they purchased it on another invoice
		if ($evt{$r}) {
		    my $mainevt = $evt{$r}->main_registration_event();
		    if ($mainevt) {
			my $regs = $mainevt->registrations();
			while (my $rmain = $regs->next) {
			    if ($rmain->is_valid) {
				$in_parent = 1;
				last;
			    }
			}
		    }
		}
		if (! $in_parent) {
		    # They probably deleted the parent. 
		    $out .= &validate_delete_item($this,$ritem{$r},"Main event registration not found (did you delete it?) - [[item]] removed from cart.");
		    $ndel++;
		    next;
		}
	    }
	    # check for main registrant prerequisites
	    my $fee = $fee{$r};
	    if ($fee) {
		if ($fee->sold_out()) {
		    $out .= &validate_delete_item($this,$ritem{$r},"Sorry, fee is now sold out - [[item]] removed from cart.");
		    $ndel++;
		    next;
		}
		else {
		    my $pfee = $fee->getdata("parent_id");
		    if ($pfee) {
			my $pass = 0;
			foreach my $fr (keys %fee) {
			    if ($fee{$fr}->id == $pfee) {
				$pass = 1;
				last;
			    }
			}
			if (! $pass) {
			    # Could not find available_to fee in cart.
			    # perhaps they purchased it on another invoice
			    my $in_prereq = 0;
			    my @preg = $share{DB}->fetch_match("evt_reg",{evt_fee_id=>$pfee,account_id=>$acct->id});
			    foreach my $pdata (@preg) {
				my $preg = new Modules::Registration::Registration(data=>$pdata);
				if ($preg->is_valid) {
				    $in_prereq = 1;
				    last;
				}
			    }
			    if (! $in_prereq) {
				# Nothing found, they probably deleted it.
				$out .= &validate_delete_item($this,$ritem{$r},"Prerequisite registration not found (did you delete it?) - [[item]] removed from cart.");
				$ndel++;
				next;
			    }
			}
		    }
		}
	    }
	    else {
		$out .= &validate_delete_item($this,$ritem{$r},"Fee not found - [[item]] removed from cart.");
		$ndel++;
		next;
	    }
	}
    }
    if ($ndel) {
	$inv->clear_items();         # reload
	#$EvtReg->rebuild_session();  # fix session
    }
    return $out;
}

sub validate_delete_item {
    my ($this,$item,$message) = @_; # $this is a Pay object
    &delete_cart_registration($this,$item);  # deletes the registration
    $item->delete();  # deletes the receivable item
    return $this->error(&ExSite::Misc::substitute($msg{$message},{item=>$item->name}));
}




1;
