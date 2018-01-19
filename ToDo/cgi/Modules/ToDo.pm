package Modules::ToDo;

#----------------------------------------------------------------------------
#
#   Copyright (C) 2015 - Exware Solutions, Inc.  http://www.exware.com
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

use strict;

use ExSite::Config;
use ExSite::Input;
use ExSite::Misc;
use ExSite::Util;
use ExSite::ML;
use ExSite::UI;
use ExSite::Content;
use ExSite::Date;
use Modules::BaseDCD;

# declare package globals

use vars qw(@ISA $ml);

@ISA = qw(Modules::BaseDCD);

sub read {
    my ($this,$options) = @_;
    my $in = new ExSite::Input;
    $this->{input} = $in->combine;
    $this->{post} = $in->post;
    $this->{query} = $in->query;
    $this->{is_post} = scalar keys %{$this->{post}};
}

sub write {
    my ($this,$options) = @_;
    return undef;
}

sub ioctl {
    my $this = shift;
    $_ = shift;           # $_ is the ioctl request

    if (/isRestricted/) {
	return 0;
    }
    elsif (/isService/) {
	return 0;
    }
    elsif (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/Category/) {
	return "System";
    }
    elsif (/ModuleName/) {
	return "To-Do";
    }
    elsif (/ModuleInfo/) {
	return "Display a to-do list of tasks that need to be manually addressed.";
    }
}

sub ctrl_panel {
    my $this = shift;
    my $ml = &get_obj("ML");
    my $ui = &get_obj("UI");
    my $out = $ml->h1("To-Do List");
    $out .= &insert_js("misc");
    if ($this->{is_post}) {
	my $now = new ExSite::Time();
	my $time = $now->write("sql_datetime");
	foreach my $key (keys %{$this->{post}}) {
	    $key =~ /^todo_(\d+)$/;
	    my $date_id = $1;
	    if ($date_id) {
		my $date = new ExSite::Date(id=>$date_id);
		if ($date->owns()) {
		    $date->setdata("status","completed");
		    $date->setdata("end",$time);
		    $date->save();
		    $out .= $ui->SuccessMsg($date->showdata("description").": done");
		}
		else {
		    $out .= $ui->ErrorMsg($date->showdata("description").": permission denied");
		}
	    }
	}
    }
    my @tasks = $share{DB}->custom_query("select * from content_date where type='todo' order by start desc");
    if (@tasks > 0) {
	my $f = new ExSite::FormBuilder(action=>$this->link());
	$f->template("<p>","[[input]]<br>","</p>");
	$f->buttons(submit=>"Update");
	my $now = new ExSite::Time();
	my $cobj = new ExSite::Content();
	foreach my $task (@tasks) {
	    my $status = $task->{status};
	    next if ($status eq "inactive");
	    my $c = $cobj->get_content_obj($task->{content_id});
	    my $link = $ml->a($c->subtype()." ".$c->id." (".$c->label.")",{href=>$c->admin_url()});
	    my %opt = (
		type=>"checkbox",
		name=>"todo_".$task->{content_date_id},
		label=>"$link: ".$task->{description},
		);
	    if ($task->{status} eq "completed") { 
		# show completed tasks for 14 days
		my $time = new ExSite::Time($task->{end},"sql_datetime");
		next if (! $this->{input}{all} && $time->diffdays($now) > 14);
		$opt{checked} = 1; 
		$opt{disabled} = 1; 
		$opt{label} .= " ".$ml->span("(completed ".$time->write("datetime").")",{class=>"TodoCompletion"});
	    }
	    elsif ($task->{status} eq "active") { 
		# only show incomplete todos and ones coming due in next day
		my $time = new ExSite::Time($task->{start},"sql_datetime");
		next if (! $this->{input}{all} && $now->diffdays($time) > 1);
		$opt{label} .= " ".$ml->span("(due on ".$time->write("date").")",{class=>"TodoCompletion"});
	    }
	    $f->input(%opt);
	}
	$out .= $f->make();
	$out .= $this->{input}{all} ?
	    $ml->p($ml->a("Show current tasks",{href=>$this->link(all=>undef)})):
	    $ml->p($ml->a("Show all tasks",{href=>$this->link(all=>1)}));
    }
    else {
	$out .= $ml->p("There is nothing to do! Take a coffee break.")
    }
    return $out;
}

1;
