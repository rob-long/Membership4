package Modules::Cron;
#-----------------------------------------------------------------------
#
#   Cron : create scheduled tasks
#
#   This plug-in helps with managing your scheduled tasks.  You must be 
#   running the ExSite cron tool to actually execute these tasks.
#   See cgi/cron.pl for details.
#
#-----------------------------------------------------------------------
#   Copyright 2001-2008 Exware Solutions, Inc.  http://www.exware.com
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
#-----------------------------------------------------------------------

use strict;
use ExSite::Config;
use ExSite::Object;
use ExSite::Util;
use ExSite::UI;
use Modules::BaseDCD;
use vars qw(@ISA $ui $ml);
@ISA = qw(Modules::BaseDCD ExSite::Object);

sub setup {
    my ($this,$id) = @_;
    # setup Object type
    &ExSite::Object::setup($this,type=>"crontask",id=>$id);
}

# Cron has no public-face functions

sub write {
    my ($this,$opt) = @_;
    return "";
}

sub ioctl {
    my $this = shift;
    $_ = shift;   # $_ is the ioctl request
    if (/ModuleName/) {
	return "Task Scheduler";
    }
    elsif (/ModuleInfo/) {
	return "The Task Scheduler (Cron) is used to set up regular, recurring, or scheduled tasks within the ExSite system.";
    }
    elsif (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/Category/) {
	return "System";
    }
    elsif (/Access/) {
	return 3;
    }
    return undef;
}

sub ctrl_panel {
    my $this = shift;
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    $this->setup($this->{input}{id});
    my $topurl = $this->link(cron=>undef,id=>undef);
    my $out; # = &Button(url=>$topurl,label=>"&lt; all tasks");
    if ($this->{input}{cron} eq "view") {
	$out .= $this->show();
    }
    elsif ($this->{input}{cron} eq "edit") {
	$this->id($this->{input}{id});
	$out .= $this->edit(extra=>{reply=>$this->link(__plaintext=>1,
						       cron=>"view")});
    }
    elsif ($this->{input}{cron} eq "new") {
	$out .= $this->make(data=>{method=>$this->{input}{method}},
			    extra=>{reply=>$this->link(__plaintext=>1,
						       cron=>undef)});
    }
    elsif ($this->{input}{cron} eq "del") {
	if ($this->ok) { 
	    $this->delete(); 
	    &redirect("$config{server}{server}$config{server}{CGIpath}/$config{prog}{ctrlpanel}/Cron");
	}
	else {
	    $out .= $this->error($this->{status});
	}
    }
    else {
	return $this->list;
    }
    return $out;
}

sub list {
    my $this = shift;
    my ($out,$url,@tab,$thistab,$pane,$ntask,$itab);
    $itab = 0;
    my @task = $share{DB}->fetch_all("crontask","crontask_id");

    my $r = new ExSite::ReportBuilder;
    $r->nodata("No tasks");
    $r->headers(["Task","Module","Status"]);

    foreach my $method ("hourly","daily","weekly") {
	my $ucmeth = ucfirst $method;
	my $title = $ucmeth." Tasks";
	$r->title($title);
	push @tab, { label=>$title, url=>$this->link(cron=>$method) };
	$ntask = 0;
	foreach my $t (@task) {
	    if ($t->{method} eq $method) {
		$url = $this->link(cron=>"view",id=>$t->{crontask_id});
		$r->push("<a href='$url'>$t->{description}</a>",
			 $t->{module},
			 $t->{status});
		$ntask++;
	    }
	}
	if (! $this->{input}{cron} && $method eq "hourly") {  # default view
	    $thistab = $itab;
	    $pane = $r->make();
	}
	elsif ($this->{input}{cron} eq $method) {
	    $thistab = $itab;
	    $pane = $r->make;
	}
	$r->clear;
	if ($ntask) {
	    $tab[-1]{label} .= $ml->span($ntask,{class=>"badge"});
	}
	$itab++;
    }

    push @tab, { label=>"Preset Tasks", url=>$this->link(cron=>"preset") };
    $r->headers(["Task","Module","When","Status"]);
    $r->title("Preset Tasks");
    $ntask = 0;
    foreach my $t (@task) {
	if ($t->{method} eq "preset") {
	    $url = $this->link(cron=>"view",id=>$t->{crontask_id});
	    $r->push("<a href='$url'>$t->{description}</a>",
		     $t->{module},
		     $t->{exectime},
		     $t->{status},
		);
	    $ntask++;
	}
    }
    if ($this->{input}{cron} eq "preset") {
	$thistab = $itab;
	$pane = $r->make;
    }
    $itab++;
    $r->clear;
    if ($ntask) {
	$tab[-1]{label} .= $ml->span($ntask,{class=>"badge"});
    }

    push @tab, { url=>$this->link(cron=>"new"),label=>"new task",faicon=>"plus" };

    return $ui->MenuBox(tabs=>\@tab,thistab=>$thistab,pane=>$pane);
}

sub list_old {
    my $this = shift;
    my ($out,$url);

    my @task = $share{DB}->fetch_all("crontask","crontask_id");

    my $r = new ExSite::ReportBuilder;
    $r->nodata("No tasks");
    $r->headers(["Task","Module","Status"]);

    foreach my $method ("hourly","daily","weekly") {
	my $ucmeth = ucfirst $method;
	$r->title("Recurring $ucmeth Tasks");
	foreach my $t (@task) {
	    if ($t->{method} eq $method) {
		$url = $this->link(cron=>"view",id=>$t->{crontask_id});
		$r->push("<a href='$url'>$t->{description}</a>",
			 $t->{module},
			 $t->{status});
	    }
	}
	$out .= $r->make;
	$r->clear;
    }

    $r->headers(["Task","Module","When"]);
    $r->title("Upcoming Preset Tasks");
    foreach my $t (@task) {
	if ($t->{method} eq "preset" && $t->{status} eq "active") {
	    $url = $this->link(cron=>"view",id=>$t->{crontask_id});
	    $r->push("<a href='$url'>$t->{description}</a>",
		     $t->{module},
		     $t->{exectime});
	}
    }
    $out .= $r->make;
    $r->clear;

    $r->headers(["Task","Module","When","Status"]);
    $r->title("Completed and Disabled Tasks");
    foreach my $t (@task) {
	if ($t->{method} eq "preset" && $t->{status} ne "active") {
	    $url = $this->link(cron=>"view",id=>$t->{crontask_id});
	    $r->push("<a href='$url'>$t->{description}</a>",
		     $t->{module},
		     $t->{exectime},
		     $t->{status});
	}
    }
    $out .= $r->make;
    $r->clear;

    $url = $this->link(cron=>"new");
    $out .= $ui->Button(url=>$url, label=>"+ new task");

    return $out;
}

sub show {
    my ($this) = @_;
    return $this->error("No such task") if (! $this->ok);
    my $t = $this->load();
#    return $this->error("Undefined task") if (! $t);
    my $out = $this->describe($t);
    $out .= $this->SUPER::show(title=>"Task '$t->{description}'");

    my $url = $this->link(cron=>"edit");
    $out .= $ui->Button(url=>$url, label=>"edit task");
    $url = "javascript:confirm_custom('Really delete this task?','".$this->link(cron=>"del")."')";
    $out .= $ui->Button(url=>$url, label=>"delete task");

    return $out;
}

sub describe {
    my ($this,$id) = @_;
    my ($out,$url);
    return undef if (! $id);
    my $t = ref $id ? $id : $share{DB}->fetch("crontask",$id);
    my $action = join(" ",("<em>$t->{command}</em>", $t->{type}, $t->{id}));
    $out = "<h1>$t->{description}</h1>
<p>This task tells the <strong>$t->{module}</strong> module to <em>$t->{command}</em> $t->{type} $t->{id}, ";
    my $time = $this->showdata("exectime");
    my %timetype = ( hourly => "hour", daily => "day", weekly => "week" );
    if ($t->{method} =~ /ly$/) {
	$out .= "once per ".$timetype{$t->{method}};
    }
    else {
	$out .= "at $time";
    }
    $out .= ".<br>\n";
    if ($t->{status} eq "active") {
	if ($t->{method} eq "preset") {
	    $out .= "This task is active and will execute after $time";
	}
	else {
	    $out .= "This task is active and will execute.<br>\nIt was last executed at $time.<br>\nNext execution will be approximately 1 $timetype{$t->{method}} thence.";
	}
    }
    elsif ($t->{status} eq "inactive") {
	$out .= "This task has been suspended, and will not execute.";
    }
    elsif ($t->{status} eq "completed") {
	$out .= "This task was completed at $time.";
    }
    $out .= "</p>\n";
    return $out;
}


1;
