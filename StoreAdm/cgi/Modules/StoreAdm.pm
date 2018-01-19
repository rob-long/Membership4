package Modules::StoreAdm;
#----------------------------------------------------------------------------
#
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
use ExSite::Misc;
use ExSite::ReportBuilder;
use ExSite::ML;
use ExSite::UI;
use Modules::BaseDCD;
use Devel::Size qw(size total_size);
use vars qw(@ISA $ml $ui);
@ISA = qw(Modules::BaseDCD);

sub write {
    return undef;
}

sub ioctl {
    my $this = shift;
    $_ = shift;
    if (/ModuleName/) {
	return "Persistent Data Store";
    }
    elsif (/ModuleInfo/) {
	return "This is a tool for inspecting and managing the 
ExSite Persistent Data Store.  This is used for saving user sessions, 
and caching frequently-used data.";
    }
    elsif (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/Category/) {
	return "Database";
    }
    elsif (/Cron/) {
	return \&cron;
    }
    elsif (/Access/) {
	return 8;
    }
    elsif (/Publish/) {
	return \&publish;
    }
    return undef;
}

sub ctrl_panel {
    my $this = shift;
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    if (! $share{DB}->is_admin) {
	return $this->error("Permission denied.");
    }
    if (! tied %store) {
	return $this->error("Persistent Data Store is not enabled.");
    }
    if (! (tied %store)->is_persistent) {
	# should never happen
	return $this->error("Wrong Persistent Data Store!");
    }

    if ($this->{input}{cmd} eq "inspect") {
	return $this->showitem($this->{input}{item});
    }
    elsif ($this->{input}{cmd} eq "clear") {
	delete $store{$this->{input}{item}};
    }
    elsif ($this->{input}{cmd} eq "reset") {
	(tied %store)->reset();
    }
    elsif ($this->{input}{cmd} eq "clearns") {
	my $ns = $this->{input}{item};
	(tied %store)->clear_prefix("$ns:");
    }

    my @data;
    my %namespace;
    foreach my $key (sort keys %store) {
	my $label = $key;
	if (length $label > 100) {
	    substr($label,100,((length $label) - 100)) = "...";
	}
	my $raw = (tied %store)->getraw($key);
	my $dat = $raw->{data};
	my $size = total_size $dat;
	my $i_url = $this->link(cmd=>"inspect",item=>$key);
	my $d_url = $this->link(cmd=>"clear",item=>$key);
	my $tools = 
	    $ui->fatool("view",label=>"inspect", url=>"javascript:openOLFrame('$i_url')").
	    $ui->fatool("cross",label=>"clear", url=>$d_url);
	if ($key =~ /^(\w+):/) {
	    if (exists $namespace{$1}) {
		$namespace{$1}++;
	    }
	    else {
		$namespace{$1} = 0;
	    }
	}

	push @data, [$label,$size,$tools];
    }

    my $summary = (tied %store)->summary(1);

    my $tool = $ml->a("Reset Store",{href=>$this->link(cmd=>"reset",item=>undef)});
    foreach my $ns (keys %namespace) {
	$tool .= $ml->a("Clear $ns",{href=>$this->link(cmd=>"clearns",item=>$ns)});
    }
    my @tools = ($tool);
    if ($this->{input}{cmd} eq "inspect") {
	push @tools, $ml->a("Inspector",{href=>"#Inspector"});
    }
    push @tools, $ml->a("Refresh",{href=>$this->link(cmd=>undef,item=>undef)});

    my $out = $ui->ToolBar(tools=>\@tools);

    my $r = new ExSite::ReportBuilder(
	title=>"Data Store Inventory",
	headers=>["Item","Size","Options"],
	data=>\@data,
	foot=>$ml->p($summary),
	);
    $out .= $r->make;
    $out .= $ui->OverlayFrame();

    return $out;
}

sub showitem {
    my ($this,$item) = @_;
    my $raw = (tied %store)->getraw($item);
    return "Item not found" if (! defined $raw);
    my $idata = $raw->{data};
    my $dat;
    my $expire_msg;
    if ($raw->{etime}) {
	my $left = $raw->{etime} - time;
	if ($left > 0) {
	    $expire_msg = "Expires in ".$this->mmss($left);
	}
	else {
	    $expire_msg = "EXPIRED";
	}
    }
    else {
	$expire_msg = "Does not expire";
    }
    my $out = $ml->h1($item).$ml->p($expire_msg,{class=>"error"});
    if (ref $idata eq "HASH") {
	$dat = [ $idata ];
    }
    elsif (ref $idata eq "ARRAY") {
	$dat = $idata;
    }
    else {
	return $ml->p($out) . $idata;
    }
    my $n = 0;
    foreach my $i (@$dat) {
	$out .= (scalar @$dat > 1) ? $ml->h3("$n:") : $ml->h3("Data:");
	if (ref $i eq "HASH") {
	    $out .= &ShowHash($i);
	}
	elsif (ref $i eq "ARRAY") {
	    $out .= &ShowArray($i);
	}
	else {
	    $out .= $i;
	}
	$n++;
    }
    return $out;
}

# convert seconds to MM:SS
sub mmss {
    my ($this,$s) = @_;
    my $mm = ($s > 0) ? int ($s / 60) : int ($s / 60) - 1;
    my $ss = $s % 60;
    return sprintf "%d:%02d",$mm,$ss;
}

# publish: rebuilds the store to recover unused disk space

sub publish {
    my $this = shift;
    $ml = &get_obj("ML");
    my $st = tied %store;
    return $this->warn("store not enabled") 
	if (! $st || ! $st->is_persistent);
    $st->purge;   # clear expired data before rebuilding
    $st->rebuild;
    return $ml->p("Rebuilt persistent data store.");
}

# task manager can periodically maintain the store

sub cron {
    my ($this,$action,$type,$id) = @_;
    my $st = tied %store;
    return "store not enabled" if (! $st || ! $st->is_persistent);
    if ($action eq "rebuild") {
	$st->purge;   # clear expired data before rebuilding
	$st->rebuild;
	return "rebuilt store";
    }
    elsif ($action eq "reset") {
	$st->reset;
	return "reset store";
    }
    elsif ($action eq "purge") {
	$st->purge;
	return "purged store";
    }
    elsif ($action eq "delete" && $id) {
	$st->delete($id);
	return "deleted $id";
    }
}
