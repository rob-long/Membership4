package Modules::Trash;
#----------------------------------------------------------------------------
#
#   Copyright 2001-2004 Exware Solutions, Inc.  http://www.exware.com
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

=pod

Trash : a trashbin tool

The trashbin is a core table that stores information on all trash
calls (ie. reversible deletes).  The trashbin allows the following 
operations:

For administrators:
    - empty trash (permanently remove all trashed items)
    - restore (undelete) any trash item

For non-administrators:
    - restore (undelete) any trash item owned by the current user

When the ExSite trash methods (DB::trash_key and DB::trash_r) are 
called, the selected records are deleted, but some reconstruction
information is left behind in the trash table, allowing those
records to be re-created if necessary.  The reconstruction information
consists of a perl representation of the deleted datahashes.  These
are used to build an insert command to restore the data, if the user
so chooses.  

This technique allows us to store any number of trashed 
record(s) from any table or group of tables in a single trash record.
By default, recursive deletes of families of records are stored in a
single trash record; this allows the whole family to be restored at one
stroke, like reversing a transaction.

This also means that trash functionality will automatically extend itself
to any new tables added to the database, without any reconfiguration
needed.

By default, Trash is a simple tool which can be visited whenever the
user wishes to restore deleted records, or empty the trash to free up
database space.

=cut

use strict;
use ExSite::Config;
use ExSite::Form;
use ExSite::Misc;
use ExSite::HTML;

# inherit from BaseDCD class
use Modules::BaseDCD;
use vars qw(@ISA $ml $ui);
@ISA = qw(Modules::BaseDCD);

# write : dummy method;  this is an administrator tool only

sub write {
    my ($this,$options) = @_;
    return "";
}

# ioctl : this is a public tool

sub ioctl {
    my $this = shift;
    $_ = shift;   # $_ is the ioctl request
    if (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/Category/) {
	return "Database";
    }
    elsif (/ModuleInfo/) {
	return "The Trash manager lets you restore data that you have
previously deleted using other administration tools.  Note that the trash may
be automatically emptied periodically, so it only serves as a short-term 
emergency recovery tool, not as a long-term backup facility.";
    }
    elsif (/Cron/) {
	return \&cron;
    }
}

sub ctrl_panel {
    my $this = shift;
    my $db = $share{DB};
    $this->setup_querylib;
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    my ($out,@trash);
    if ($this->{input}{undel}) {
	# restore a trash item
	my $trash = $db->fetch("trash",$this->{input}{undel});
	if ($trash && ($db->is_admin || $trash->{uid} == $db->my_uid)) {
	    $db->undelete("trash",$this->{input}{undel});
	    if ($this->{input}{inspect}) {
		return $ui->SuccessMsg("Records have been restored.");
	    }
	}
	else {
	    return $ml->h3("Permission denied", {class=>"error"});
	}
    }
    if ($this->{input}{inspect}) {
	return $this->inspect($this->{input}{inspect});
    }
    if ($this->{input}{empty}) {
	my $uid = $db->is_admin ? $this->{input}{uid} : $db->my_uid;
	my $age = $this->{input}{empty} > 1 ? $this->{input}{empty} : 0;
	$this->empty($uid,$age);
    }

    # fetch trash items

    my $url = $this->link(undel=>undef,empty=>1,uid=>$db->my_uid);
    my @tools = ( { label=>"my trash", url=>$url, confirm=>"After emptying trash, the deleted data will no longer be recoverable. Continue?", tone=>"warning" } );
    $url = $this->link(undel=>undef,empty=>($config{Trash}{max_age} || 90));
    push @tools, { label=>"old trash", url=>$url, confirm=>"After emptying trash, the deleted data will no longer be recoverable. Continue?", tone=>"warning" };
    if ($db->is_admin) {
	$url = $this->link(undel=>undef,empty=>1);
	push @tools, { label=>"ALL trash", url=>$url, confirm=>"After emptying trash, the deleted data will no longer be recoverable. Continue?", tone=>"bad" };
    }
#    $out .= &ExSite::HTML::ToolBar(tools=>[$ml->strong("Empty trash: ").$tools]);
    $out .= $ui->ToolBar(tools=>[$ml->strong("Empty trash: "),@tools]);
    my %report = ( 
		   title=>"Trash",
		   nodata=>"The trash bin is currently empty.",
		   headers=> ["Item","Deleted on","Deleted by","Options"],
		   data=>[],
		   );
    if ($db->is_admin) {
	@trash = $db->get_query("all trash");
    }
    else {
	@trash = $db->get_query("my trash",$db->my_uid);
    }

    # list trash items

    if (@trash > 0) {
	foreach my $tr (reverse @trash) {
	    my @data;
	    foreach my $col ("description", "ctime", "uid") {
		push @data, $db->show_data("trash",$col,$tr->{$col},$tr->{trash_id});
	    }
	    my $restore_url = $this->link(inspect=>undef,undel=>$tr->{trash_id});
	    my $inspect_url = $this->link(inspect=>$tr->{trash_id},undel=>undef);
	    my $tools = 
		$ui->Button(type=>"link-button",size=>"s",label=>"recover",url=>$restore_url).
		$ui->Button(type=>"link-button",size=>"s",label=>"inspect",url=>"javascript:openOLFrame('".$inspect_url."')");
            push @data, $tools;
            push @{$report{data}},\@data;
	}
    }
    my $r = new ExSite::ReportBuilder(%report);
    $r->set("dynamic",1);
    $out .= $r->make;
    $out .= $ui->OverlayFrame();
    return $out;
}

sub empty {
    my ($this,$uid,$age) = @_;
    my @param;
    my $db = $share{DB};
    my $today = new ExSite::Time();
    if ($uid) {
	push @param, $uid;
    }
    if ($age) {
	$today->add(- $age,"days");
    }
    push @param, $today->write("sql_timestamp");
    if ($uid) {
	return $db->get_query("delete my trash",@param);
    }
    else {
	return $db->get_query("delete trash",@param);
    }
}

sub inspect {
    my ($this,$trash_id) = @_;
    my $out;
    my $db = $share{DB};
    my $data = $db->fetch("trash",$trash_id);
    if (ref $data eq "HASH") {
	$out .= $ml->h1($data->{description});
	$out .= $ml->p($ui->faicon("delete")." Deleted by ".$db->show_data("trash","uid",$data->{uid})." on ".$db->show_data("trash","ctime",$data->{ctime}).".");

	$out .= $ml->p($ui->Button(label=>"recover these records",url=>$this->link(undel=>$trash_id),faicon=>"download"));
	foreach my $rec (split /\n/,$data->{data}) {
	    $rec =~ /"(\w+)",{(.*)}$/;
#	    my @data = split /,/,$1;
	    my $table = $1;
	    my $dout;
	    foreach my $col (split /,/,$2) {
		my ($key,$val) = split /=>/,$col;
		if ($key =~ /^\w+$/) {
		    $val =~ s/^"//;
		    $val =~ s/"$//;
		    $val =~ s/</&lt;/g;
		    $val =~ s/>/&gt;/g;
		    if (length $val > 80) {
			$val = substr($val,0,80)."...";
		    }
		    $dout .= $ml->tr($ml->th($key).$ml->td($val));
		}
		else {
		    # data garbled, cannot parse
		    $key = "more...";
		    $val = "remaining data cannot be parsed...";
		    $dout .= $ml->tr($ml->th($key).$ml->td($val));
		    last;
		}
	    }
	    $out .= $ml->table(
		$ml->caption($table).
		$dout,
		{class=>"Report Inspector"}
		);
	}
	return $ml->div($out,{class=>"TrashInspector"});
    }
    else {
	return "No such trash record.";
    }
}

# task manager can periodically empty trash

sub cron {
    my ($this,$action,$type,$id) = @_;
    my $db = $share{DB};
    if ($action eq "empty my trash") {
	$this->empty($db->my_uid);
	return "emptied trash for user ".$db->my_login;
    }
    elsif ($action eq "empty all trash") {
	if ($db->is_admin()) {
	    $this->empty();
	    return "emptied all trash";
	}
	else {
	    return "empty all trash - premission denied";
	}
    }
    elsif ($action eq "empty old trash") {
	my $max_age = $config{Trash}{max_age} || 90;
	my $uid = $db->is_admin ? undef : $db->my_uid;
	$this->empty($uid,$max_age);
	return "emptied trash older than $max_age days";
    }
}

sub setup_querylib {
    my $this = shift;
    my $db = $share{DB};
    $db->set_query("all trash",
		   (sql=>"select trash_id,ctime,description,uid from trash order by ctime",
		    nparam=>0,
		    mode=>"r",
		    keys=>["trash"]
		    ));
    $db->set_query("my trash",
		   (sql=>"select trash_id,ctime,description,uid from trash where uid = ? order by ctime",
		    nparam=>1,
		    mode=>"r",
		    keys=>["trash"]
		    ));
    $db->set_query("delete my trash",
		   (sql=>"delete from trash where uid = ? and ctime < ?",
		    nparam=>2,
		    mode=>"w",
		    keys=>["trash"]
		    ));
    $db->set_query("delete trash",
		   (sql=>"delete from trash where ctime < ?",
		    nparam=>1,
		    mode=>"w",
		    keys=>["trash"]
		    ));
}

1;

