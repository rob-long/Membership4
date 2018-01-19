package Modules::SysMsg;
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
use ExSite::Form;
use ExSite::Misc;
use ExSite::Util;
use ExSite::ML;
use ExSite::ReportBuilder;
use Encode;
use Spreadsheet::ParseExcel;

# inherit from BaseDCD class
use Modules::BaseDCD;
use vars qw(@ISA $ml);
@ISA = qw(Modules::BaseDCD $ml);

# write : dummy method;  this is an administrator tool only

$ml = &get_obj("ML");

sub write {
    my ($this,$options) = @_;
    return "";
}

# ioctl : this is a public tool

sub ioctl {
    my $this = shift;
    $_ = shift;   # $_ is the ioctl request
    if (/ModuleName/) {
	return "System Messages";
    }
    elsif (/ModuleInfo/) {
	return "System Messages are coded in English by default.  This plug-in 
allows you to manage the translations of your system messages into 
alternate languages.";
    }
    elsif (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/ToDo/) {
	return \&todo;
    }
    elsif (/Category/) {
	return "System";
    }
    return undef;
}

sub ctrl_panel {
    my $this = shift;
    $ml = &get_obj("ML");
    my $db = $share{DB};
    $this->setup_queries();
    my $version = $this->my_version;
    my $out;
    my $thistab;
    my $action = $this->{input}{action} || "todo";
    if (! $version || $version =~ /^English$/i) {
	$out .= $ml->p("Select a language to manage its translations.");
	$out .= $this->select_version();
	return $out;
    }
    if ($action eq "todo") {
	$out = $this->list_todo();
	$thistab = 0;
    }
    elsif ($action eq "list") {
	$out = $this->list_all();
	$thistab = 1;
    }
    elsif ($action eq "import") {
	$out = $this->import();    
	$thistab = 2;
    }
    elsif ($action eq "do_import") {
	$out = $this->do_import();    
	$thistab = 2;
    }
    elsif ($action eq "export") {
	$out = $this->export();    
	$thistab = 2;
    }

    return &ExSite::HTML::TabBox(
	tabs=>[
	    {label=>"to-do",url=>$this->link(id=>undef,tid=>undef,action=>"todo")},
	    {label=>"all messages",url=>$this->link(id=>undef,tid=>undef,action=>"list")},
	    {label=>"import",url=>$this->link(id=>undef,tid=>undef,action=>"import")},
	],
	pane=>$out,
	thistab=>$thistab,
	tabwidth=>"100px",
	);
}

sub list {
    my ($this,%opt) = @_;
    my $out;
    my $version = $this->my_version;
    if (! $version || $version =~ /^English$/i) {
	$out .= $ml->p("Select another language to manage its translations.");
    }
    $out = $this->select_version($version);
    return $out if (! $version || $version =~ /^English$/i);

    if ($this->{input}{del}) {
	$share{DB}->trash_r("sysmsg",$this->{input}{del});
	$ml->location($this->link(_plaintext=>1,del=>undef,tid=>undef,id=>undef));
	return undef;
    }
    elsif ($this->{input}{id}) {
	return $this->update_message($this->{input}{id},$this->{input}{tid});
    }

    my $db = $share{DB};
    my @msg = $db->get_query("all translations",$version);
    my $r = new ExSite::ReportBuilder();
    $r->title($opt{skipOK} ? 
	      "Missing Translations ($version)" : 
	      "All Translations ($version)");
    $r->headers("Message","Translation","Status","Options");
    $r->nodata("No messages");
    $r->set("dynamic",1);
    foreach my $msg (@msg) {
	my $status;
	if (! $msg->{message_alt}) {
	    $status = $ml->span("missing",{class=>"translationMissing"});
	}
	elsif ($msg->{ctime_alt} lt $msg->{ctime_msg}) {
	    $status = $ml->span("stale",{class=>"translationStale"});
	}
	else {
	    $status = $ml->span("OK",{class=>"translationOK"});
	}
	next if ($opt{skipOK} && $status =~ /OK/);
	$r->push(
	    $msg->{message},
	    $msg->{message_alt},
	    $status,
	    $ml->a("update",{href=>$this->link(id=>$msg->{sysmsg_id},tid=>$msg->{sysmsg_alt_id}),class=>"button_sm"}).
	    $ml->a("delete",{href=>"javascript:confirm_custom('Really delete this message and its translations?','".$this->link(del=>$msg->{sysmsg_id},id=>undef,tid=>undef)."')",class=>"button_sm"})
	    );
    }
    $out .= $r->make();
    return $out;
}

sub list_all {
    my $this = shift;
    my $out = $this->list();
    if (! $this->{input}{id}) {
	$out .= $ml->p(&ExSite::HTML::Button(label=>"Export",url=>$this->link(action=>"export")));
    }
    return $out;
}

sub list_todo {
    my $this = shift;
    my $out = $this->list(skipOK=>1);
    if (! $this->{input}{id}) {
	$out .= $ml->p(&ExSite::HTML::Button(label=>"Export",url=>$this->link(action=>"export",missing=>1)));
    }
    return $out;
}

sub todo {
    my $this = shift;
    my @task;
    my $db = $share{DB};
    my @msg = $db->custom_query("select * from sysmsg s,sysmsg_alt a where a.sysmsg_id=s.sysmsg_id and length(a.message_alt)=0");
    if (@msg > 0) {
	my $link = "$config{server}{server}$config{server}{CGIpath}/$config{prog}{ctrlpanel}/SysMsg";
	my $count = scalar @msg;
	push @task, {link=>$link,
		     title=>"System messages awaiting translation",
		     description=>"$count messages are missing their translations",
		     };
    }
    return @task;
}

sub update_message {
    my ($this,$mid,$tid) = @_;
    my $version = $this->my_version;
    my $omsg = $share{DB}->fetch("sysmsg",$mid);
    if (! $omsg) {
	return $this->error($msg{"no such message"});
    }
    my $amsg;
    if ($tid && $version) {
	$amsg = $share{DB}->fetch("sysmsg_alt",$tid);
	if ($amsg->{sysmsg_id} != $omsg->{sysmsg_id}) {
	    return $this->error($msg{"mismatched messages"});
	}
    }
    my $input = new ExSite::Input;
    my $pin = $input->post;
    my $ml = &get_obj("ML");
    if ($pin->{message}) {
	# ExSite::Message self-manages translation updates
	my %m;
	tie %m, "ExSite::Message", $version, 1, \%share, \%store;
	$m{$omsg->{message}} = $pin->{message};
	if ($share{DB}->errorcheck()) {
	    return $share{DB}->show_diagnostics("error","html");
	}
	&redirect($this->link(__plaintext=>1,id=>undef,tid=>undef));
    }
    else {
	my $f = new ExSite::FormBuilder(method=>"post");
	$f->input(name=>"message_orig",
		  type=>"textarea",
		  cols=>80,
		  rows=>4,
		  prompt=>$msg{English},
		  value=> $omsg->{message},
		  #disabled=>1,
		  readonly=>1,
		  );
	$f->input(name=>"message",
		  type=>"textarea",
		  cols=>80,
		  rows=>4,
		  prompt=>$version,
		  value=> $amsg ? $amsg->{message_alt} : "",
		  required=>1,
		  );
	return $f->make;
    }
}

sub select_version {
    my $this = shift;
    my $version = shift || $this->my_version;
    my $datatype = $share{DB}->{map}->get_datatype("list:version");
    return $this->error($msg{"no versions/languages found"}) if (! $datatype);

    my @opt = split /\|/,$datatype->{regexp};

    my $f = new ExSite::FormBuilder(method=>"get");
    $f->name("VersionSelector");
    $f->template("[[version:prompt]]: [[version:input]]");
    $this->version_selector($f,$version,1);
    $f->set("buttons"," ");
    return $f->make;
}

sub version_selector {
    my ($this,$f,$version,$autosubmit) = @_;
    return $this->error($msg{"version_selector: no form"}) if (! $f);
    $version or $version = $this->my_version;
    my $datatype = $share{DB}->{map}->get_datatype("list:version");
    return $this->error($msg{"version_selector: no versions/languages found"}) if (! $datatype);
    my @opt = split /\|/,$datatype->{regexp};
    my $onchange = $autosubmit ?
	"document.forms['VersionSelector'].submit()" : undef;
    $f->input(name=>"version",
	      type=>"select",
	      prompt=>$msg{"Select language"},
	      options=>\@opt,
	      value=>$version,#$this->my_version(),
	      nullvalue=>"== $msg{select} ==",
	      onchange=>$onchange,
	      required=>1,
	      );
}

sub my_version {
    my $this = shift;
    my $version = $this->{input}{version} || $config{default_version};
    if (! $version || $version =~ /^English$/i) {
	my $datatype = $share{DB}->{map}->get_datatype("list:version");
	my @version = split /\|/, $datatype->{regexp};
	if (@version == 1) {
	    # if there is only one version, select that by default
	    $version = $version[0];
	}
    }
    return $version;
}

sub export {
    my $this = shift;
    my $version = $this->my_version;
    my @msg = $share{DB}->fetch_all("sysmsg");
    my @altmsg = $share{DB}->fetch_match("sysmsg_alt",{version=>$version});
    my $show_okay = 1;
    $show_okay = 0 if ($this->{input}{missing});

    my %altmsg = &keywise("sysmsg_id",\@altmsg);
    my $r = new ExSite::ReportBuilder(title=>"$msg{Messages} ($version)");
    $r->headers("Message","Translation");
    foreach my $m (sort { lc $a->{message} cmp lc $b->{message} } @msg) { 
	my $am = $altmsg{$m->{sysmsg_id}};
	next if (! $show_okay && $am && $am->{message_alt} && (($am->{ctime} cmp $m->{ctime}) > 0));
	if (! $am) { $am = {}; }
#	# skip messages with newline or return chars which are not supported by csv
#	next if ($m->{message} =~ /\r/ || $am->{message_alt} =~ /\r/);
#	next if ($m->{message} =~ /\n/ || $am->{message_alt} =~ /\n/);
#	next if ($m->{message} =~ /\t/ || $am->{message_alt} =~ /\t/);
	$r->push($m->{message},$am->{message_alt});
    }
    $ml->cancel;
    print "Content-type: application/vnd.ms-excel\ncontent-disposition: attachment; filename=translations.xls\n\n";
    print $r->export("excel");
}

sub import {
    my ($this) = @_;
    my $fb = new ExSite::FormBuilder;
    my $version = 
    $fb->action($this->link(action=>"do_import"));
    $this->version_selector($fb,$this->my_version,0);
    $fb->input(
	type=>"file",
	name=>"spreadsheet",
	prompt=>"Select your excel spreadsheet",
	required=>1);
    $fb->set("buttons",$ml->p($ml->input(undef,{type=>"submit",value=>"Import"})));
    my $out = $ml->h3("Import translations");
    $out .= $fb->make();
    $out .= $ml->h3("Instructions:");
    $out .= 
	$ml->ul(
	    $ml->li("export your current list of translatable messages using the buttons under the first two tabs") .
	    $ml->li("the export format will be xls which you can open with Microsoft Excel") .
	    $ml->li("the first column of your spreadsheet will contain messages which can be translated") . 
	    $ml->li("the second column of your spreadsheet will the translations for the selected language version") .
	    $ml->li("fill in missing translations and correct existing translations if needed") .
	    $ml->li("*note that messages with line breaks will not be exported") .		
	    $ml->li("save the sheet as an .xls file (Microsoft Excel)") .
	    $ml->li("use the form above to upload your translations"));
    return $out;
}

sub do_import {
	my ($this) = @_;
	my $input = new ExSite::Input;	
	my $filename = $input->fetch_file("spreadsheet","name");
	my $raw = $input->fetch_file("spreadsheet","raw");
	open(my $fh, '<', \$raw);
	my $book = Spreadsheet::ParseExcel::Workbook->Parse($fh);
	my $sheet = $book->{Worksheet}[0];
	my $version = $this->my_version;
	for (my $row = $sheet->{MinRow}; defined $sheet->{MaxRow} && $row <= $sheet->{MaxRow}; $row++) {
		my $o = $sheet->{Cells}[$row][0]{Val};
		my $t = $sheet->{Cells}[$row][1]{Val};
		if ($o && $t) {
	    my @sysmsg = $share{DB}->fetch_match("sysmsg",{message=>$o});
	    if (scalar @sysmsg) {
			if ($t =~ /[^[:ascii:]]/) {
				# strange characters are present
				if ($config{charset} !~ /ISO-8859-1/i) {
				$t = Encode::encode($config{charset}, Encode::decode("ISO-8859-1", $t));
				}
			}
			my %m;
			tie %m, "ExSite::Message", $version, 1, \%share, \%store;
			$m{$sysmsg[0]->{message}} = $t;
			if ($share{DB}->errorcheck()) {
				return $share{DB}->show_diagnostics("error","html");
			}
		}
		}
	}
	my $uri = new ExSite::URI;
	$uri->query(action=>undef,mid=>undef,tid=>undef);
	$uri->plaintext;
	&redirect($uri->write_full);
}

sub setup_queries {
    my $this = shift;
    my $db = $share{DB};
    $db->set_query("todo translations",
		   sql => "select s.sysmsg_id,s.ctime ctime_msg,s.message,a.sysmsg_ald_id,a.ctime ctime_alt,a.sysmsg_alt,a.version from sysmsg s left join sysmsg_alt a on a.sysmsg_id=s.sysmsg_id and a.version=? where length(a.message_alt)=0",
		   nparam => 1,
		   mode => "r",
		   keys => ["sysmsg","sysmsg_alt"],
	);
    $db->set_query("all translations",
		   sql => "select s.sysmsg_id,s.ctime ctime_msg,s.message,a.sysmsg_alt_id,a.ctime ctime_alt,a.message_alt,a.version from sysmsg s left join sysmsg_alt a on a.sysmsg_id=s.sysmsg_id and version=? order by s.message",
		   nparam => 1,
		   mode => "r",
		   keys => ["sysmsg","sysmsg_alt"],
	);
}

1;

