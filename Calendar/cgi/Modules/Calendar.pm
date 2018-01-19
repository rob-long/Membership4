package Modules::Calendar;

### TODO:
# display event wf_status in show_event
# move month views in ExSite::Calendar to here
# small cal -> popups to daily event list
# large cal -> event list in date cell

use strict;
use ExSite::Config;
use ExSite::Calendar;
use ExSite::Misc;
use ExSite::Util;
use ExSite::UI;
use ExSite::Time;
use ExSite::ReportBuilder;
use Modules::Content;

use vars qw(@ISA $ui $ml);
@ISA = qw(Modules::Content);

use vars qw(@wd @wdy @weekday @mon @month @dayinmonth);

@wd = qw(Su Mo Tu We Th Fr Sa);
@wdy = qw(Sun Mon Tue Wed Thu Fri Sat);
@weekday = qw(Sunday Monday Tuesday Wednesday Thursday Friday Saturday);
@mon = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
@month = qw(January February March April May June July August September October November December);
@dayinmonth = qw(31 28 31 30 31 30 31 31 30 31 30 31);

sub read {
    my ($this,$options) = @_;
    my $in = new ExSite::Input;
    $this->{input} = $in->combine;
    $this->{post} = $in->post;
    $this->{query} = $in->query;
    my $path = $in->path();
    if ($path =~ /\/\d\d\d\d\/\d?\d/) {
	$in->new_path("Calendar",$path);
	$this->{path} = $path;
	my @date = split /\//,$path;
	shift @date;
	$this->{year} = shift @date;
	$this->{month} = shift @date;
	$this->{day} = shift @date;
	$this->{date} = $this->{year}."-".$this->{month}."-".$this->{day};
    }
    else {
	my $t = new ExSite::Time;
	$this->{date} = $t->write("iso_date");
	$this->{year} = $t->write("raw_year");
	$this->{month} = $t->write("raw_month");
	$this->{day} = $t->write("raw_day");
    }
}

sub write {
    my ($this,$options) = @_;
    my $out;
    $ml = &get_obj("ML");
    my %opt = &DecodeString($options);
    my $id = $this->{query}{id} || $opt{id};
    if ($id) {
	my $c = new ExSite::Content(id=>$id);
	if ($c->subtype eq "event") {
	    my $evt = $c->get_content_obj();
	    $this->{content} = $evt;
	    $out .= $evt->show();
	}
	elsif ($c->subtype eq "calendar") {
	    my $cal = $c->get_content_obj();
	    $this->{content} = $cal;
	    my @evt = $cal->fetch_events_by_month($this->{date});
	    $out .= $cal->show_month({popup=>0},@evt);
	}
	else {
	    $out .= $ml->Comment("Content node $id cannot be displayed by Calendar.");
	    #$out .= $this->warn(&substitute($msg{"Content node [[id]] cannot be displayed by Calendar."},{id=>$id}));
	}
    }
    elsif ($opt{cmd} =~ /next/) {
	$out .= $this->next_event();
    }
    else { #if ($opt{cmd} =~ /upcoming/) {
	# upcoming events
	$out .= $this->show_upcoming(%opt);
    }
    return $out;
}

sub ioctl {
    my ($this) = shift;
    $_ = shift;
    if (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/ModuleName/) {
	return "Calendar";
    }
    elsif (/Category/) {
	return ["Events", "Applications"];
    }
}

sub ctrl_panel {
    my $this = shift;
    $this->{admin} = 1;
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    my $cmd = $this->{input}{cmd};
    my $id = $this->{input}{id};
    my $c = new ExSite::Content();
    $this->{content} = $c->get_content_obj($id);
    my $out;
    if ($cmd) {
	$out .= $this->pathbar($this->{content});
	if ($cmd eq "conf") {
	    $out .= $this->configure($this->{content});
	}
	elsif ($cmd eq "edit") {
	    #$out .= $this->edit;
	    $out .= $this->update($this->{content},format=>"html",prompt=>"Event Description",name=>"event_descr");
	}
	elsif ($cmd eq "new") {
	    $out .= $this->newevent;
	}
	elsif ($cmd eq "newcal") {
	    $out .=  $this->newcalendar;
	}
	elsif ($cmd eq "cal") {
	    $out .=  $this->show();
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
	elsif ($cmd =~ /^(publish|cancel|approve)$/) {
	    $out .= $this->$1;
	    $out .= $this->show();
	}
	else {
	    $out .= $this->error("Unrecognized command: $cmd");
	}
    }
    elsif ($id) {
	my $type = $this->{content}->subtype;
	if ($type =~ /calendar|event/) {
	    $out .= $this->pathbar($this->{content});
	    $out .= $this->show;
	}
	elsif ($type =~ /fee/) {
	    $out .= $this->warn($ml->em("Calendar")." cannot manage registration fees. Use the ".$ml->em("Registration")." module instead.");
	    $out .= $ui->ToolBar(
		tools=>[
		    {label=>"never mind",faicon=>"left",url=>$this->link(id=>$this->{content}->parent->id)},
		    {label=>"go to Registration",faicon=>"calendar",url=>"$config{server}{CGIpath}/$config{prog}{ctrlpanel}/Register?id=".$this->{content}->id}
		]);
	}
	else {
	    $out .= $this->error("You cannot manage this content using the ".$ml->em("Calendar")." module.");
	}
    }
    else {
	$out .= $this->list_calendars;
    }
    return $out;
}

sub show_upcoming {
    my ($this,%opt) = @_;
    my ($out,$list);
    my $s = new ExSite::Section(data=>$share{DB}->this_site());
    if ($s->defined) {
	my @evtdata;
	my $ncal == 0;
	foreach my $caldata ($s->get_descendants("calendar")) {
	    $ncal++;
	    my $cal = new ExSite::Calendar(data=>$caldata);
	    push @evtdata, $cal->fetch_future_events()
	}
	if (scalar @evtdata > 0) {
	    if ($ncal > 1) {
		@evtdata = sort {$a->{start} cmp $b->{start}} @evtdata;
	    }
	    my ($nevt,%done);
	    my $limit = $opt{limit} || $config{Calendar}{limit} || 3;
	    foreach my $evtdata (reverse @evtdata) {
		next if $done{$evtdata->{content_id}};
		$done{$evtdata->{content_id}} = 1;
		$nevt++;
		my $evt = new ExSite::Event(data=>$evtdata);
		$list .= $evt->summary();
#		$list .= $ml->dt($evt->show_date_range());
#		$list .= $ml->dd($evt->show(view=>"small"));
		last if ($limit && $nevt == $limit);
	    }
	}
	$out = $ml->div(
	    $list ?
	    $ml->h2("Upcoming Events").$list :
	    $ml->p("No upcoming events."),
	    {class=>"Calendar"}
	    );

	### FIXME: more events link...

    }
    return $out;
}

sub next_event {
    my ($this,%opt) = @_;
    my $s = new ExSite::Section(data=>$share{DB}->this_site());
    if ($s->defined) {
	my @evtdata;
	my $ncal == 0;
	foreach my $caldata ($s->get_descendants("calendar")) {
	    $ncal++;
	    my $cal = new ExSite::Calendar(data=>$caldata);
	    push @evtdata, $cal->fetch_future_events()
	}
	if (scalar @evtdata > 0) {
	    if ($ncal > 1) {
		@evtdata = sort {$b->{start} cmp $a->{start}} @evtdata;
	    }
	    my $evtdata = pop @evtdata;
	    my $evt = new ExSite::Event(data=>$evtdata);
	    return $ml->div(
		$ml->a($evt->title,{href=>$evt->link()}).
		" (".$evt->show_date_range().")",
		{class=>"nextEvent"});
	}
    }
    return undef;
}
	
sub list_calendars {
    my $this = shift;
    my $c = new ExSite::Content();
    my $tree = $c->get_content_tree();
    my @cal = $tree->find({type=>$c->isubtype("calendar")});
    my $r = new ExSite::ReportBuilder(title=>"Calendars");
    $r->headers("Title","Location","Events");
    $r->nodata("No calendars.");
    foreach my $caldata (@cal) {
	my $cal = new ExSite::Calendar(data=>$caldata);
	next if (! $cal->allow("insert"));
	my $section = $cal->my_section();
	next if ($this->{input}{id} && $section->id != $this->{input}{id});
	my @data = ( 
	    $ml->a($cal->title,{href=>$this->link(id=>$cal->id)}),
	    );
	my $url = $cal->get_url;
	push @data, $ml->a($section->title,{href=>$url,target=>'_blank'});
	my @evt = $tree->find({type=>$c->isubtype("event")},$cal->id);
	push @data, $ml->div(scalar @evt,{class=>"num"});
	$r->push(@data);
    }
    $r->tools($ml->a("Start a new calendar",{class=>"button_sm",href=>$this->link(cmd=>"newcal")}));
    return $r->make();
}

sub show {
    my ($this) = @_;
    my $c = $this->{content};
    my $out;
    if ($c->subtype eq "calendar") {
	$out .= $this->show_calendar($c);
    }
    elsif ($c->subtype eq "event") {
	$out .= $this->show_event($c);
    }
    else {
	$out .= $this->warn($ml->em(ucfirst $c->name)." is a ".$c->subtype()."; the Calendar module can only be used to manage Calendars and Events. Click on 'Top' to see a list of available Calendars.");
    }
    return $out;
}

sub show_calendar {
    my ($this,$cal) = @_;
    return $this->error("Permission denied.") if (! $cal->allow("insert"));
#    my $viewswitcher = $this->{input}{cmd} eq "cal" ?
#	$ml->a("List View",{href=>$this->link(cmd=>undef)}) :
#	$ml->a("Monthly View",{href=>$this->link(cmd=>"cal")});

    my $icondir = "$config{server}{HTMLpath}/_ExSite/images/icons";
    my $out = $ui->IconBar(
	links=>[
	    {label=>"new&nbsp;event",url=>$this->link(cmd=>"new"),img=>"$icondir/add.png"},
	    {label=>"configure",url=>$this->link(cmd=>"conf"),img=>"$icondir/conf.png"},
	    $this->{input}{cmd} eq "cal" ?
	    {label=>"list&nbsp;view",url=>$this->link(cmd=>undef),img=>"$icondir/report.png"} :
	    {label=>"monthly&nbsp;view",url=>$this->link(cmd=>"cal"),img=>"$icondir/date.png"},
	    undef,
	    {label=>"publish",url=>$this->link(cmd=>"publish"),img=>"$icondir/publish.png"},
	    undef,
	    {label=>"DELETE",url=>$this->link(cmd=>"del"),confirm=>'Really unpublish and delete all events?',tone=>"bad",img=>"$icondir/delete.png"}
	]);

    if ($this->{input}{cmd} eq "cal") {
	$out .= $this->show_calendar_monthly($cal);
	return $out;
    }

    my $tree = $cal->get_content_tree();
    my $r = new ExSite::ReportBuilder(title=>$cal->title);
    $r->headers("Date","Event","Status","Preview");
    $r->nodata("No events.");
    $r->set("dynamic",1);
    my @evt = $cal->get_all_events();
    foreach my $edata (@evt) {
	my $date = new ExSite::Time($edata->{start},"sql_datetime");
	my $showdate = $edata->{end} ?
	    $date->show_date_range($edata->{end},"sql_datetime") : 
	    $date->write("date");
	my $evt = new ExSite::Event(data=>$edata);
	my $eid = $evt->id;
	my $url = $evt->link(_cms=>1,__uri=>$evt->get_uri());
	my $status = $evt->wf_status();
	$r->push($showdate,
		 $ml->a($evt->title,{href=>$this->link(id=>$evt->id)}),
		 $ml->span($status,{class=>"status".ucfirst($status)}),
		 $ml->a("preview",{href=>$url,target=>"_blank"}),
	    );
    }
    $out .= $r->make();
    return $out;
}

sub show_calendar_monthly {
    my ($this,$cal) = @_;
    my $date = $this->{input}{date};
    my $t = new ExSite::Time;
    if ($date) {
	$t->set($date,"iso_date");
    }
    else {
	$date = $t->write("iso_date");
    }
    my @evt = $cal->fetch_events_by_month($date);

    # navigation
    my $title = $t->write("%MMMM, %YYYY");
    $t->add_approximate(1,"month");
    my $nextmonth = $t->write("%YYYY-%MM");
    my $nextlink = $ml->span($ml->a($t->write("%MMMM, %YYYY"),{href=>$this->link(date=>$nextmonth)}).$ui->FAIcon("right"),{class=>"calendarNextMonth"});
    $t->add_approximate(-2,"month");
    my $prevmonth = $t->write("%YYYY-%MM");
    my $prevlink = $ml->span($ui->FAIcon("left").$ml->a($t->write("%MMMM, %YYYY"),{href=>$this->link(date=>$prevmonth)}),{class=>"calendarPrevMonth"});
    my $header = $nextlink . $prevlink . $ml->span(undef,{class=>"fa fa-calendar"}) . "&nbsp;" . $title;

    return $cal->show_month({popup=>0,date=>$date,header=>$header},@evt);
}

sub event_tools {
    my ($this,$evt) = @_;
    my $icondir = "$config{server}{HTMLpath}/_ExSite/images/icons";
    return $ui->IconBar(
	links=>[
	    {label=>"configure",url=>$this->link(cmd=>"conf"),img=>"$icondir/conf.png"},
	    {label=>"description",url=>$this->link(cmd=>"edit"),img=>"$icondir/edit.png"},
	    {label=>"schedule",url=>$this->link(cmd=>"schedule"),img=>"$icondir/time.png"},
	    {label=>"preview",url=>$evt->get_url_dynamic(),target=>"_blank",img=>"$icondir/view.png"},
	    {label=>"new&nbsp;activity",url=>$this->link(cmd=>"new"),img=>"$icondir/add.png"},
	    undef,
	    {label=>"publish",url=>$this->link(cmd=>"publish"),img=>"$icondir/publish.png"},
	    undef,
	    {label=>"cancel",url=>$this->link(cmd=>"cancel"),img=>"$icondir/cancel.png"},
	    {label=>"DELETE",url=>$this->link(cmd=>"del"),confirm=>'Really delete this event?',img=>"$icondir/delete.png",tone=>"bad"},
	]);

    # old toolbar
    return $ui->ToolBar(
	tools=>[
	$ml->a("Configure",{href=>$this->link(cmd=>"conf")}).
	$ml->a("Description",{href=>$this->link(cmd=>"edit")}).
	$ml->a("Schedule",{href=>$this->link(cmd=>"schedule")}).
	$ml->a("Preview",{href=>$evt->get_url_dynamic(),target=>"_blank"}),
	$ml->a("Publish",{href=>$this->link(cmd=>"publish")}).
	$ml->a("Cancel",{href=>$this->link(cmd=>"cancel")}),
	$ml->a("Delete",{href=>"javascript:confirm_custom('Really unpublish and delete this event?','".$this->link(cmd=>"del")."')",style=>"color:red"})
	]
	);
}

sub show_event {
    my ($this,$evt) = @_;
    return $this->error("Permission denied.") if (! $evt->allow("update"));
    $evt->load_revision("newest");
    my $out = $this->event_tools($evt);
    $out .= $this->{admin} ? $evt->preview() : $evt->show();
    return $out;

    # show just this event
    $out .= $ui->BasicBox(
	title=>"Event Details",
	pane=>$evt->preview()
	);
    return $out;
}

sub newcalendar {
    my $this = shift;
    my $c = new ExSite::Calendar;
    if (scalar keys %{$this->{post}} > 0) {
	return $c->do_make();
    }
    else {
	my $out;
	$share{DB}->handler("select_foreign_key",\&Calendar_select_section);
	$out .= $ml->h1("New Calendar");
	my @hide = qw(content_id type url template master sortkey content_role mtime ptime);
	$out .= $c->make(hide=>\@hide,data=>{type=>$c->isubtype("calendar"),access=>0,publish=>"static",status=>4},extra=>{reply=>$this->link(__plaintext=>1,cmd=>undef)});
	return $out;
    }
}

sub Calendar_select_section {
    my ($this, $table, $rec, $col, $ftable) = @_;
    if ($table eq "content" && $col eq "parent") {
	# choose a section
	return $share{DB}->my_sites();
    }
    return undef;
}

sub newevent {
    my $this = shift;
    my $c = $this->{content};
    my $out;
    if (scalar keys %{$this->{post}} > 0) {
	my %post = $share{DB}->parse_parts(%{$this->{post}});
	if ($post{title} && $post{start} && $post{start} !~ /^0/) {
	    my %edata = (
		title=>$post{title},
		parent=>$c->id,
		status=>$c->wf_istatus("draft"),
		type=>$c->isubtype("event"),
		);
	    $edata{name} = $this->unique_event_name(%edata);
	    %edata = $c->new_content(%edata);
	    if ($edata{content_id}) {
		if ($post{description}) {
		    my $evt = new ExSite::Event(data=>\%edata);
		    $evt->revise(data=>$post{description},format=>"text");
		}
		my %date = (
		    content_id=>$edata{content_id},
		    status=>"active",
		    type=>"calendar",
		    start=>$post{start},
		    end=>$post{end} ? $post{end} : undef,
		    );
		if ($share{DB}->insert("content_date",\%date)) {
		    $ml->redirect($this->link(__plaintext=>1,id=>$edata{content_id},cmd=>undef));
		}
		else {
		    $out .= $share{DB}->show_diagnostics("error","html");
		}
	    }
	    else {
		$out .= $c->show_diagnostics("error","html");
	    }
	}
	else {
	    $out .= $this->error("Missing title or start date.");
	}
    }
    else {
	my $type = $c->subtype eq "event" ? "Activity" : "Event";
	$out .= $ml->h1("New $type");
	my $db = $share{DB};
	my $f = $db->form();
	$f->input(name=>"title",prompt=>"$type Name",type=>"text",size=>80,required=>1);
	$db->input_htmleditor(
	    prompt=>"$type Description",
	    name=>"description",
	    editor_height=>350,
	    editor_width=>550,
	    required=>1
	    );

	### TODO: for activities, default dates to main event date

	$f->input(name=>"date_instructions",type=>"preformatted",prompt=>$ml->h3("Event Date(s)"),input=>"Times are optional; leave as 12:00 AM to ignore the time. The end date is also optional. After the event is created, you will have the option to add more dates to the schedule.");
	my $date = $type eq "Activity" ? $c->get_date->get_start->write("sql_datetime") : undef;
	$db->input_exsite(name=>"start",prompt=>"Start Date/Time",datatype=>"datetime:picker",value=>$date,required=>1);
	$db->input_exsite(name=>"end",prompt=>"End Date/Time (optional)",datatype=>"datetime:picker");
	
	$out .= $db->form->make();
    }
    return $out;
}

sub unique_event_name {
    my ($this,%data) = @_;
    my $db = $share{DB};
    my $name = $data{name} || &clean_filename($data{title});
    if ($db->count("content",{name=>$name,parent=>$data{parent}}) > 0) {
	# already an event of this name
	my $t = new ExSite::Time($data{start});
	$name .= "_".$t->write("raw_year");
	if ($db->count("content",{name=>$name,parent=>$data{parent}}) > 0) {
	    # already an event of this name + year
	    $name .= $t->write("MMDD");
	    if ($db->count("content",{name=>$name,parent=>$data{parent}}) > 0) {
		# already an event of this name + date
		$name .= "_".&randtext("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghjiklmnopqrstuvwxyz0123456789",5);
	    }
	}
    }
    return $name;
}

#### TODO: include activities in main schedule view

sub schedule {
    my ($this) = @_;
    my $evt = $this->{content};
    my $out .= $this->event_tools($evt);
    my $cmd = $this->{input}{cmd};

    if ($cmd eq "schedule_new") {
	$out .= $this->schedule_new($evt);
	return $out;
    }
    elsif ($cmd eq "schedule_edit") {
	$out .= $this->schedule_edit($evt);
	return $out;
    }
    elsif ($cmd eq "schedule_del") {
	my $dateid = $this->{input}{date};
	my $date = new ExSite::Object(type=>"content_date",id=>$dateid);
	if ($date->delete()) {
	    $ml->location($this->link(__plaintext=>1,key=>undef,cmd=>"schedule"));
	    return;
	}
	else {
	    $out .= &ExSite::Config::show_diagnostics();
	}
    }
    $out .= $this->schedule_show($evt);
    return $out;
}

sub schedule_show {
    my ($this,$evt) = @_;
    my $out;
    ###### why not use $evt->get_calendar_dates ?
    my $dates = $this->{content}->get_dates("calendar");
    $dates->sort("start");
    my $r = new ExSite::ReportBuilder(title=>"Event Schedule");
    $r->headers("Date(s)","Description","");
    $r->nodata("This event does not have a start date.".$ml->br."It may not appear correctly in the calendar.");
    while (my $d = $dates->next) {
	my $start = $d->getdata("start");
	my $t = new ExSite::Time($start,"sql_datetime");
	my $end = $d->getdata("end");
	my $range = (defined $end && $end !~ /^0/) ?
	    $t->show_date_range($end,"sql_timestamp") :
	    $t->write("date");
	$r->push(
	    $range,
	    $d->showdata("description"),
	    $ui->FATool("edit",url=>$this->link(cmd=>"schedule_edit",date=>$d->id)).
	    $ui->FATool("delete",url=>$this->link(cmd=>"schedule_del",date=>$d->id),confirm=>"Really delete this date?",tone=>"bad")
	    );
    }
    $r->tools($ui->FATool("add",label=>"new date",url=>$this->link(cmd=>"schedule_new")));
    $out .= $r->make();

    my @actout;
    foreach my $act ($evt->activities) {
	push @actout, $ml->a($act->label,{href=>$this->link(id=>$act->id)})." (".$act->show_date_range().")";
    }
    if (@actout > 0) {
	$out .= $ml->p("Activity schedules are managed separately. Click on the activity to manage its date(s) and time(s).").$ml->ul(\@actout);
    }
    my $mainevt = $evt->main_event;
    if ($mainevt->id != $evt->id) {
	$out .= $ml->p("This is an activity of ".$ml->a($ml->em($mainevt->title),{href=>$this->link(id=>$mainevt->id)}).". Main event and activity schedules can be managed there.");
	
    }

    $out .= $ui->HelpBox(
	title=>"About Event Schedules",
	size=>"m",
	pane=>$ml->ul([
	"Simple events will have only a single date entered into the event schedule.",
	"Events with multiple classes, sessions, or other recurrences will have one schedule entry for each date.",
	"Compound events can have multiple activities with their own schedules. Click into the activities to manage their schedules.",
	"You may optionally give special descriptions for each dates, if the event schedule needs to distinguish them.",
	"It is legal to have an event with no dates. Such events may not appear in normal calendar listings, however.",
		      ]));
    return $out;
}

sub schedule_new {
    my ($this,$evt) = @_;
    my $out;

    my $db = $share{DB};
    my %data = $db->parse_parts(%{$this->{post}});
    if (exists $data{start}) {
	my %evt = (
	    start=>$data{start},
	    end=>$data{end},
	    description=>$data{description},
	    content_id=>$evt->id,
	    type=>"calendar",
	    status=>"active",
	    );

	my $evtdate = new ExSite::Object(type=>"content_date",data=>\%evt);
	if ($evtdate->insert()) {
	    if ($data{repeat_interval}) {
		$out .= $this->add_repeated_dates($evt,\%data);
	    }
	    $out .= $this->schedule_show($evt);
	}
	else {
	    $out .= $db->show_diagnostics("error","html");
	}
    }
    else {
	$out .= $ml->h1("New Date for ".$ml->em($evt->label));
	$out .= $this->schedule_form($evt);
    }
    return $out;
}

sub add_repeated_dates {
    my ($this,$evt,$data) = @_;
    my $out;
    my $db = $share{DB};
    my $rpt_interval = $data->{repeat_interval};
    my $rpt_unit = $data->{repeat_unit};
    my $rpt_until = $data->{repeat_until};

    if ($rpt_interval && $rpt_unit && $rpt_until) {
	my $st = new ExSite::Time($data->{start},"sql_datetime");
	my ($end,$use_end);
	if ($data->{end}) {
	    $end = new ExSite::Time($data->{end},"sql_datetime");
	    $use_end = 1;
	}
	my $descr = $data->{"description"};
	my $until = new ExSite::Time($rpt_until,"iso_date"); # wrong time
	my $err = $until->validate();
	if ($err) {
	    $out .= $this->error("Until date: ".$err);
	}
	else {
	    if ($rpt_interval =~ /^\d+$/ && 
		$rpt_interval > 0 && 
		$rpt_unit =~ /day|week|month/) {
		$st->add_approximate($rpt_interval,$rpt_unit);
		while ($st->write("iso_date") lt $rpt_until) {
		    my $ed = new ExSite::Object(type=>"content_date");
		    $ed->setdata("content_id",$evt->id);
		    $ed->setdata("status","active");
		    $ed->setdata("type","calendar");
		    $ed->setdata("start",$st->write("sql_datetime"));
		    if ($use_end) {
			$end->add_approximate($rpt_interval,$rpt_unit);
			$ed->setdata("end",$end->write("sql_datetime"));
		    }
		    else {
			$ed->setdata("end",undef);
		    }
		    $ed->setdata("description",$descr);
		    $out .= $ml->p("adding ".$ed->showdata("start"));
		    $ed->save or 
			$out .= $this->error("Failed to save ".$st->write("date"));
		    $st->add_approximate($rpt_interval,$rpt_unit);
		}
	    }
	}
    }
#    if (! $db->errorcheck()) {
#	$ml->location($this->link(caladm=>"schedule",date=>undef,__plaintext=>1));
#    }
    return $out;
}

sub schedule_edit {
    my ($this,$evt) = @_;
    my $out;

    my $db = $share{DB};
    my %data = $db->parse_parts(%{$this->{post}});
    if (exists $data{start}) {
	my %evt = (
	    content_date_id=>$data{content_date_id},
	    start=>$data{start},
	    end=>$data{end},
	    #description=>$data{description},
	    content_id=>$evt->id,
	    status=>"active",
	    );
	my $evtdate = new ExSite::Object(type=>"content_date",data=>\%evt);
	$evtdate->set("dirty",1);
	if ($evtdate->update()) {
	    $out .= $this->schedule_show($evt);
	}
	else {
	    $out .= $db->show_diagnostics("error","html");
	}
    }
    else {
	my $date = $share{DB}->fetch("content_date",$this->{input}{date});
	$out .= $ml->h1("Edit Date for ".$ml->em($evt->label));
	$out .= $this->schedule_form($evt,%$date);
    }
    return $out;
}

sub schedule_form {
    my ($this,$evt,%data) = @_;
    my $br = $ml->br;
    my $f = $share{DB}->form();
    my $template = 
	$ml->p("[[start:prompt]]${br}[[start:input]]").
	$ml->p("[[end:prompt]]${br}[[end:input]]").
	$ml->p("[[description:prompt]]${br}[[description:input]]");
    $share{DB}->input_exsite(name=>"start",datatype=>"datetime:picker",prompt=>"Start Date",required=>1,value=>$data{start});
    $share{DB}->input_exsite(name=>"end",datatype=>"datetime:picker",prompt=>"End Date",value=>$data{end});
    $share{DB}->input_exsite(name=>"description",datatype=>"string",prompt=>"Description (optional)",value=>$data{description},size=>80);
    if ($data{content_date_id}) {
	# edit - include key
	$share{DB}->input_html(name=>"content_date_id",type=>"hidden",value=>$data{content_date_id});
    }
    else {
	# new date - include recurring event options
	$template .= $ui->FrameBox(
#	    bgcolor=>"#eee",
	    color=>"#999",
	    title=>"Recurring events only",
	    pane=>$ml->p("Repeat every [[repeat_interval:input]] [[repeat_unit:input]] until [[repeat_until:input]]")
	    );
	$share{DB}->input_exsite(name=>"repeat_until",datatype=>"date:picker",prompt=>"Repeat Until",placeholder=>"YYYY-MM-DD");
	$f->input(name=>"repeat_interval",type=>"text",size=>4,prompt=>"Repeat Interval");
	$f->input(name=>"repeat_unit",type=>"select",prompt=>"Repeat Unit",options=>["days","weeks","months"]);
    }
    $f->template($template);
    return $f->make();
}

# status changes

sub publish {
    my $this = shift;
    my $c = $this->{content};
    if ($c->wf_status eq "canceled") {
	# update status as well
	$c->wf_publish;
    }
    else {
	$c->publish();
    }
    return $ml->p("Published ".$ml->em($c->title));
}

sub cancel {
    my $this = shift;
    my $c = $this->{content};
    $c->wf_cancel();
    return $ml->p("Published ".$ml->em($c->title));
}

sub approve {
    my $this = shift;
    my $c = $this->{content};
    $c->wf_approve();
    return $ml->p("Approved ".$ml->em($c->title));
}

1;
