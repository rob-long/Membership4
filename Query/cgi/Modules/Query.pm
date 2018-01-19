package Modules::Query;

#-----------------------------------------------------------------------
#
#   Copyright 2001-2007 Exware Solutions, Inc.  http://www.exware.com
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
# Custom Query Tool - execute, report, save, and export arbitrary 
# SQL queries.

use strict;
use ExSite::Config;
use ExSite::Util;
use ExSite::Misc;
use ExSite::UI;
use Modules::BaseDCD;

use vars qw(@ISA $ml $ui);
@ISA = qw(Modules::BaseDCD);

sub read {
    my ($this,$opt) = @_;
    # fetch overlayed query and form input
    my $in = new ExSite::Input;
    $this->{input} = $in->combine;
    if ($this->{input}{query} =~ /^\!/) {
	# query is encoded for html safety - decode to get original text
	$this->{input}{query} =~ s/^\!//;
	$this->{input}{query} = &unsafetext($this->{input}{query});
    }
}

sub write {
    my ($this,$options) = @_;
    return "";
}

sub ioctl {
    my $this = shift;
    $_ = shift;
    if (/ModuleName/) {
	return "Database Query Tool";
    }
    elsif (/ModuleInfo/) {
	return "The Query Tool allows you to run, view, and export save reports and live queries.";
    }
    elsif (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/Category/) {
	return "Database";
    }
    elsif (/isRestricted/) {
	return 0;
#	return 1;
    }
}

sub ctrl_panel {
    my $this = shift;
    my $out;
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    my $db = $share{DB};
    if ($db->authorize < $config{auth}{root_auth_level} - 1) {
	return $this->error("Permission denied");
    }

    if ($this->{input}{query} && $this->{input}{action} ne "save") {
	# execute a query
	$out = $this->query();
    }

    #$out .= &ShowHash($this->{input});

    if ($this->{input}{action} eq "new") {
	$out .= $this->prompt_for_query;
    }
    elsif ($this->{input}{action} eq "delete") {
	$out .= $this->delete_query;
    }
    elsif ($this->{input}{action} eq "save") {
	$out .= $this->save_query;
	$out .= $this->show_saved_queries;
    }
    elsif ($this->{input}{id}) {
	my $q = $db->fetch("query",$this->{input}{id});
	$this->{input}{query} = $q->{query};
	delete $this->{input}{id};
	$this->{saved_query} = $q;
	$out .= $this->query;
    }
    elsif ($this->{input}{r}) {
	my $r = new ExSite::ReportBuilder();
	$r->load($this->{input}{r});
	if ($this->{input}{fmt}) {
	    $out .= $r->export($this->{input}{fmt});
	}
	else {
	    $out .= $ui->ToolBar(links=>[
				     {label=>"Back",faicon=>"left",url=>$this->link(id=>undef,r=>undef,fmt=>undef)},
				     {label=>"Excel",faicon=>"download",url=>$this->link(fmt=>"xls")},
				     {label=>"CSV",faicon=>"download",url=>$this->link(fmt=>"csv")},
				 ]);
	    $out .= $r->make();
	}
    }
    elsif ($db->{map}->is_mapped("query") || $config{Query}{saved_reports}) {
	# we appear to support saving queries
	$out .= $this->show_saved_queries;
    }
    else {
	$out .= $this->prompt_for_query;
    }

    return $out;
}

sub qtitle {
    my ($this,$title) = @_;
    $title =~ s/</\&lt;/g;
    $title =~ s/>/\&gt;/g;
    $title =~ s/\&/\&amp;/g;
    return $title;
}

sub show_saved_queries {
    my $this = shift;
    my $out;
    my $db = $share{DB};
    my $rpt = new ExSite::ReportBuilder;
    if ($db->{map}->is_mapped("query")) {
	my @queries = $db->fetch_all("query","query_id");
	my @data;
	foreach my $q (@queries) {
	    my $title = $this->qtitle($q->{title});
	    my $qlink = $this->link(action=>undef,id=>$q->{query_id});
	    my $dlink = $this->link(id=>$q->{query_id},action=>"delete");
	    push @data, [ $ml->a($title,{href=>$qlink}),
			  substr($db->show_data("query","query",$q->{query}),0,40)."...", 
			  $ml->a("delete",{href=>$dlink}),
	    ];
	}
	my $newlink = $this->link(id=>undef,action=>"new");
	$rpt->init(
	    title=>"Live Reports - click to run report",
	    data=>\@data,
	    headers=>["Report","Query","Options"],
	    tools=>$ml->a("new query",{href=>$newlink}),
	    );
	$out .= $rpt->make;
    }

    # add saved reports
    
    if ($config{Query}{saved_reports}) {
	$rpt->init(title=>"Saved Reports - click to view",
		   headers=>["Report","Date"]);
	my @reports = ref $config{Query}{saved_reports} eq "ARRAY" ?
	    @{$config{Query}{saved_reports}} : ( $config{Query}{saved_reports} );
	foreach my $q (@reports) {
	    my $t = (tied %token)->fetch($q);
	    my $date = exists $t->{ctime} ? "run on ".$t->{ctime} : "expires ".$t->{expiry};
	    $rpt->push($ml->a($q,{href=>$this->link(r=>$q)}),$date);
	}
	$out .= $rpt->make();
    }

    return $out;
}

sub prompt_for_query {
    my $this = shift;
    my $url = $this->link(action=>undef,id=>undef);
    my $query = $this->{input}{query} || $config{Query}{default};
    my $allow = $config{Query}{allow} || "select";
    my $out = $ml->h1("Enter your query:");
    $out .= $ui->ErrorBox(title=>"Warning",
			  pane=>"This tool is for experts only.  Careless use could damage the database.");
    $out .= $ml->form(
	$ml->p("Query:".$ml->br.
	       $ml->textarea($query,{rows=>4, cols=>60, name=>"query"}).$ml->br.
	       "(Only $allow statements will be accepted.)").
	$ml->input(undef,{type=>"submit"}).
	$ml->input(undef,{type=>"reset"}),
	{method=>"POST", action=>$url}
	);
    return $out;
}

sub delete_query {
    my $this = shift;
    if ($this->{input}{id}) {
	my $db = $share{DB};
	$db->trash_key("query",$this->{input}{id});
	&redirect($this->link(action=>undef,id=>undef));
	return undef;
    }
    else {
	return $this->error("Invalid delete request - no ID");
    }
}

sub query {
    my $this = shift;
    my $db = $share{DB};
    #my $sql = &url_unescape($this->{input}{query});
    my $sql = $this->{input}{query};
    my $out;
    
    my $allow = $config{Query}{allow} || "select";
    my $allow_re = $allow;
    $allow_re =~ s/,\s*/|/g;

    if ($sql =~ /^$allow_re/) {
	my $sth = $db->dbh()->prepare($sql);
	if (! $sth) {
	    $out = $this->error("$DBI::errstr; $!");
	}
	elsif (! $sth->execute) {
	    $out = $this->error("$DBI::errstr; $!");
	}
	else {
	    my $names = $sth->{NAME} || [];
	    my $data = $sth->fetchall_arrayref;
	    if (@$data > 0) {
		if ($this->{input}{action} eq "export") {
		    $share{PageBuf}->cancel if ($share{PageBuf});
			print "Content-type: application/vnd.ms-excel\ncontent-disposition: attachment; filename=query.xls\n\n";
		    $this->export($names,$data);
		}
		else {
		    $out .= $this->report($names,$data);
		}
	    }
	    else {
		$out = $ml->p("Query executed successfully; no data returned.");
	    }
	}
	$sth->finish;
    }
    else {
	$out = $this->error("Illegal query.  Only $allow statements are permitted.");
    }
    return $out;
}

sub export {
    my ($this,$names,$data) = @_;
    my $ncol = scalar @{$data->[0]};
    if (@$names == 0) {
	for (1..$ncol) { push @$names, $_; }
    }
    # export the data

    use Spreadsheet::WriteExcel;
    my ($workbook,$worksheet,$format,$col,$row);

    # Create a new Excel workbook
    $workbook = Spreadsheet::WriteExcel->new("-");

    # Add a worksheet
    $worksheet = $workbook->addworksheet();
    $worksheet->keep_leading_zeros();

    #  Add and define a format
    $format = $workbook->addformat(); # Add a format
    $format->set_bold();

    # Write headings
    $col = $row = 0;
    foreach my $h (@$names) {
	$worksheet->write($row, $col, $h, $format);
	$col++;
    }
    $row++;
    
    # write data
    foreach my $d (@$data) {
	for (0..$ncol-1) {
	    $worksheet->write($row, $_, $d->[$_]);
	}
	$row++;
    }

    # done
    $workbook->close();
}

sub report {
    my ($this,$names,$data) = @_;
    my $out;
    if (@$names == 0) {
	my $ncol = scalar @{$data->[0]};
	for (1..$ncol) { push @$names, $_; }
    }
    if (@$names > $config{Query}{max_cols}) {
	my $ncol = scalar @$names;
	$out .= $ui->ErrorBox(
	    title=>"Warning",
	    pane=>"Query exceeded maximum number of displayable
columns.  This HTML report will only show the first $config{Query}{max_cols}
of $ncol columns.  If exported to Excel, all columns will be 
included."
	    );
	my @dat = @$names;
	my @subdat = @dat[0..($config{Query}{max_cols}-1)];
	$names = \@subdat;
	foreach my $d (@$data) {
	    my @dat = @$d;
	    my @subdat = @dat[0..($config{Query}{max_cols}-1)];
	    $d = \@subdat;
	}
    }
    if (@$data > $config{Query}{max_rows}) {
	my $nrow = scalar @$data;
	$out .= $ui->ErrorBox(
	    title=>"Warning",
	    pane=>"Query exceeded maximum number of displayable
rows.  This HTML report will only show the first $config{Query}{max_rows}
of $nrow rows.  If exported to Excel, all rows will be included."
	    );
	my @dat = @$data;
	my @subdat = @dat[0..($config{Query}{max_rows}-1)];
	$data = \@subdat;
    }
    # sanitize data for HTML display
    foreach my $d (@$data) {
	foreach my $v (@$d) {
	    $v =~ s/</&lt;/g;
	    $v =~ s/>/&gt;/g;
	    if ($config{Query}{max_length}) {
		if (length $v > $config{Query}{max_length}) {
		    $v = substr $v,0,$config{Query}{max_length};
		    $v .= "...";
		}
	    }
	    $v =~ s/:cntrl:/?/g;
	}
    }
    my $exporturl = $this->link(action=>undef,id=>undef);
    # mask quotes and other sensitive chars
    my $savebtn = $this->{saved_query} ? "" : $ml->input(undef,{type=>"submit", name=>"action", value=>"save"});
    my $queryinfo;
    my $in = new ExSite::Input;
    my $q = $in->query();
    my $qtext;
    if ($q->{id}) {
	$qtext =  &safehtml($this->{saved_query}{query});
	$queryinfo = $ml->input(undef,{type=>"hidden", value=>$q->{id}, name=>"id"});
    }
    else {
	#my $qdata = $this->{input}{query};
	$qtext =  &safehtml($this->{input}{query});
	my $qdata = &safetext($this->{input}{query});
	$queryinfo = $ml->input(undef,{type=>"hidden", value=>"!$qdata", name=>"query"});
    }
    my $exportform = $ml->form("$queryinfo$savebtn".$ml->input(undef,{type=>"submit", name=>"action", value=>"export"}),{method=>"post", action=>$exporturl});
    my $title = $this->{saved_query} ?
	$this->{saved_query}{title} :
	substr($this->qtitle($this->{input}{query}),0,40)."...";

    my $report = new ExSite::ReportBuilder(
					   data=>$data,
					   headers=>$names,
					   title=>$title,
					   tools=>$exportform,
					   );
    $out .= $report->make;
    $out .= $ui->BasicBox(title=>"Query",pane=>$qtext);
    return $out;
}

sub save_query {
    my $this = shift;
    if ($this->{input}{query}) {
	my $qdata = &safetext($this->{input}{query});
	if ($this->{input}{title}) {
	    # unmask quotes etc
	    $share{DB}->insert("query",{title=>$this->{input}{title},
					query=>$this->{input}{query}});
	}
	else {
	    my $url = $this->link();
	    return $ml->form(
		$ml->p("Enter Query Title: ".$ml->input(undef,{name=>"title", size=>40})).
		$ml->input(undef,{name=>"query", value=>"!$qdata", type=>"hidden"}).
		$ml->input(undef,{type=>"submit", name=>"action", value=>"save"}),
		{method=>"POST", action=>$url});
	}
    }
    else {
	return $this->error("Invalid delete request - no ID");
    }
    return "";
}

1;
