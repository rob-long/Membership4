package Modules::Search;

#----------------------------------------------------------------------------
#
#   Copyright 2001-2012 Exware Solutions, Inc.  http://www.exware.com
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
#
#  The search tool builds a search index using 2 tables:
#  - searchurl: every URL that is searched is represented once here
#  - searchterm: every indexed word at each url is represented once here,
#                with a weight (based on location and number of ocurrences)
#
#  The search index is constructed by stripping out all extraneous tags and
#  text, and counting the incidence of each remaining word in the body of 
#  the html at each URL.  Words in filenames, titles, descriptions, and 
#  keywords are counted and weighted separately.
#
#  This version searches only the default representation of each page, 
#  and does not follow links to recursive instances of the same page.
#
#  The search logic is somewhat crude, and does not allow for searching
#  for partial words, quoted phrases, absense of words, etc.
#
#-----------------------------------------------------------------------

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Util qw(&redirect);
use ExSite::Auth;
use ExSite::Page;
use ExSite::Search;
use ExSite::Module qw(&site_license &service_page);
use Modules::BaseDCD;
use Digest::MD5;

use vars qw(@ISA $ml $ui);
@ISA = qw(Modules::BaseDCD ExSite::Search);

sub new {
    my $this = shift;
    my $obj = {};
    my $class = ref($this) || $this;
    bless $obj, $class;
    $obj->initialize_object;
    $obj->read_conf;
    $obj->read;
    $obj->{scope} = $config{search}{scope};
    $obj->reset;
    return $obj;
}

sub write {
    my ($this, $opt) = @_;
    $ml = &get_obj("ML");
    my $a = new ExSite::Auth;
    my %opt;
    if ($opt =~ /=/) {
	%opt = &DecodeString($opt);
    }
    else {
	$opt{search} = $opt;
    }
    if ($opt{scope} && $config{search}{scope} eq "global") {
	# if scope is global, can manually set it back to local
	$this->{scope} = $opt{scope};
    }
    my $out;
    my $in = new ExSite::Input;
    my $sdata = $in->post_or_query;
    my $term = $sdata->{searchterm} || $opt{search};
    if ($term) {
	$out = $this->do_search($term);
    }
    else {
	my ($size,$title);
	my $size = $config{Search}{size} || 20;
	if ($config{Search}{showtitle}) {
	    $title .= $msg{'Search <!--$site_title-->'};
	}
	$out = $this->search_form($term,$title,$size,&service_page("Search"));
    }
    return $ml->div($out,{class=>"Search"});
}

sub ioctl {
    my $this = shift;
    $_ = shift;   # $_ is the ioctl request
    if (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/isService/) {
	return 1;
    }
    elsif (/ModuleInfo/) {
	return "Search is a standard website search tool.  It allows you
to build search indexes for your website, and easily search for any set of
terms.  Search results are ranked and reported with the page title and
description.  Search indexes can be manually edited by experts, if you 
want to boost or lower the relevance of certain terms on certain pages.";
    }
    elsif (/Category/) {
	return "CMS";
    }
    elsif (/Access/) {
	return $config{Search}{access} || 7;
    }
    elsif (/PublishRule/) {
	return "static";
    }
    return;
}

sub ctrl_panel {
    my $this = shift;
    $this->setup_querylib;
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    my $in = $this->{input};
    my $out;
    if ($config{search}{scope} ne "global") {
	$this->{section_id} = $this->get_section_id();
	if (! $this->{section_id}) {
	    if ($in->{content}) {
		my $c = new ExSite::Content();
		$this->{content} = $c->get_content_obj($in->{content});
		$this->{section_id} = $this->{content}->my_section->id;
	    }
	    else {
		return $this->set_section_id();
	    }
	}
    }
    $this->{section} = new ExSite::Section(id=>$this->{section_id});
    if (! $this->{content}) {
	$this->{content} = $in->{content} ? $this->{section}->get_content_obj($in->{content}) : $this->{section};
    }

    if (! $this->{content}->allow("publish")) {
	return $this->error("Permission denied: you must have authorization to publish this content in order to rebuild the search index.");
    }

    my @path = ( $ml->a("Top",{href=>$this->link(section_id=>undef,content=>undef,action=>undef)}) );
    if ($this->{section_id}) {
	push @path, $ml->a($this->{section}->name,{href=>$this->link(section_id=>$this->{section_id},content=>undef,action=>undef)});
    }
    if ($this->{content}->id != $this->{section_id}) {
	push @path, $ml->a($this->{content}->name,{href=>$this->link(section_id=>$this->{section_id},content=>$this->{content}->id,action=>undef)});
    }
    $out .= $ui->PathBar(links=>\@path);
    
    $out .= $ui->ToolBar(tools=>[
			     $ml->a("Re-build index",{href=>$this->link(action=>"index",url=>undef)}).
			     $ml->a("Clear index",{href=>$this->link(action=>"clear",url=>undef)}),
			     $ml->a("Browse index",{href=>$this->link(action=>"view",url=>undef)})
			 ]);

    my $donewrite;

    if ($in->{action} eq "index") {
	#$out .= $ml->h1($this->{content}->title);
	my $ierr = &AtError();
	$out .= $this->{content}->search_index($this);
	$this->update($config{search}{threshold});
	if (&AtError($ierr)) {
	    $out .= $ui->ErrorBox(title=>"Warnings",pane=>&ExSite::Config::show_diagnostics());
	}
	else {
	    $out .= $this->summary();
	}
    }
    elsif ($in->{action} eq "clear") {
	#$out .= $ml->h1($this->{content}->title);
	if ($this->{section_id} == $this->{content}->id) {
	    $out .= $this->clear_site($this->{section_id});
	}
	elsif ($this->{section_id} == $this->{content}->id) {
	    $out .= $this->clear_url($this->{section_id});
	}
	$out .= $this->info("Index for ".$this->{content}->subtype." ".$ml->em($this->{content}->label)." cleared.");
	$out .= $this->summary();
    }
    elsif ($in->{action} =~ /view/) {
	$out .= $this->view();
    }
    else {
	#$out .= $ml->h1($this->{content}->title);
	$out .= $this->summary();
	$out .= $this->admin_search();
    }
    return $out;
}

sub summary {
    my $this = shift;
    my $out;
    if ($this->{content}->id == $this->{section_id}) {
	my @url = $share{DB}->get_query("indexed urls for site",$this->{section_id});
	my @term = $share{DB}->get_query("indexed terms for site",$this->{section_id});
	my $r = new ExSite::ReportBuilder(title=>"Search Overview");
	$r->headers("Indexed URLs","Indexed Terms");
	$r->push($ml->div(scalar @url,{class=>"num"}),$ml->div(scalar @term,{class=>"num"}));
	$out .= $r->make();
    }
    else {
	my $url = $this->{content}->get_url_canonical();
	my @term = $share{DB}->get_query("indexed terms for url",$url);
	my $r = new ExSite::ReportBuilder(title=>"Search Overview");
	$r->set("dynamic",1);
	$r->headers("URL","Indexed Terms");
	$r->push($ml->a(($url||"-"),{href=>$url}),$ml->div(scalar @term,{class=>"num"}));
	$out .= $r->make();
    }
    #$out .= $this->write;  #doesn't work in ctrlpanels
    return $out;
}

sub admin_search {
    my $this = shift;
    my $out = $ml->form(
	$ml->input(undef,{type=>"text",name=>"search",value=>$this->{input}{search}}).
	$ml->input(undef,{type=>"submit",value=>"Search"}),
	{action=>$this->link(),method=>"post",class=>"Search"}
	);

    if ($this->{input}{search}) {
	my %results = $this->search($this->{input}{search});
	my @url_id = sort { $results{$b} <=> $results{$a}; } keys %results;
	my $sout;
	my $nresult = 0;
	my $db = $share{DB};
	foreach my $url_id (@url_id) {
	    my $url = $db->fetch("searchurl",$url_id);
	    next if (! $url->{content_id});
	    $nresult++;
	    my $score = int($results{$url_id}*10)/10;
	    if ($url->{url} =~ /^$config{server}{CGIpath}/) {
		# show complete URLs
		$url->{url} = $config{server}{server}.$url->{url};
	    }
	    my $link = $this->link(url=>$url_id,action=>"view");
	    $sout .= $ml->dt( $ml->a($url->{title},{href=>$link}) );
	    my $descr = $url->{description} . 
		($url->{description} ? $ml->br : "") .
		$ml->span("[$url->{url}, $msg{score}: $score]",{class=>"searchdetails"});
	    $sout .= $ml->dd($descr);
	}
	if ($nresult == 0) {
	    $sout .= $ml->dt($config{search}{no_results});
	}
	$out .= $ml->dl($sout);
    }
    return $out;
}

sub setup_querylib {
    my $this = shift;
    my $db = $share{DB};
    $db->set_query("indexed urls for site",
		   #sql=>"select * from searchurl where section_id=?",
		   sql=>"select searchurl.*,count(searchterm.term) as count from searchurl,searchterm where section_id=? and searchurl.searchurl_id=searchterm.searchurl_id group by searchterm.searchurl_id",
		   nparam=>1,
		   mode=>"r",
		   keys=>"searchurl");
    $db->set_query("indexed terms for site",
		   sql=>"select distinct t.term from searchterm t,searchurl u where t.searchurl_id=u.searchurl_id and u.section_id=?",
		   nparam=>1,
		   mode=>"r",
		   keys=>["searchurl","searchterm"]);
    $db->set_query("indexed terms for url",
		   sql=>"select distinct t.term from searchterm t,searchurl u where t.searchurl_id=u.searchurl_id and u.url=?",
		   nparam=>1,
		   mode=>"r",
		   keys=>["searchurl","searchterm"]);
    

}

sub view {
    my $this = shift;
    my $out;
    my $urlid = $this->{input}{url};
    if ($urlid) {
	$out .= $this->view_url($urlid);
    }
    elsif ($config{search}{scope} eq "global" && ! $this->{section_id}) {
	$out .= $this->set_section_id;
    }
    else {
	#$out .= $ml->h1($this->{content}->title);
	my $section = new ExSite::Section(id=>$this->{section_id});
	my $surl = $section->get_url;
	my @url = $share{DB}->get_query("indexed urls for site",$this->{section_id});
	my $r = new ExSite::ReportBuilder(title=>"Indexed URLs");
	$r->headers("URL","Indexed terms");
	foreach my $url (@url) {
	    my $curl = $url->{url};
	    $curl =~ s/^$surl//;
	    $r->push(
#		$ml->a($url->{url},{href=>$this->link(url=>$url->{searchurl_id})}),
		$ml->a($curl,{href=>$this->link(url=>$url->{searchurl_id})}),
		$url->{count}
		);
	}
	$out .= $r->make();
    }
    return $out;
}

sub view_url {
    my ($this,$urlid) = @_;
    my $out;
    my $urldata = $share{DB}->fetch("searchurl",$urlid);
    if ($urldata) {
	my $shorturl = $urldata->{url};
	$shorturl =~ s/^https?:\/\/[\w\-\.]+//;
	$out .= $ml->h1($shorturl);
	$out .= $ml->p("Higher weighted terms will make this page show up higher in search results, and are also important for SEO.").$ml->p("Term weight is increased if the term is used in titles, descriptions, and other significant areas.");
	my @term = map { $_->{term}." ".$ml->span("(weight: ".$_->{weight}.")",{class=>"termWeight"}) } $share{DB}->fetch_child("searchterm","searchurl",$urlid,{"weight"=>"desc"});
	$out .= $ml->ol(\@term);
#	my $r = new ExSite::ReportBuilder(title=>"Search Terms");
#	$r->headers("Term","Weight");
#	$r->set("dynamic",1);
#	my @term = $share{DB}->fetch_child("searchterm","searchurl",$urlid,{"weight"=>"desc"});
#	foreach my $term (@term) {
#	    $r->push($term->{term},$term->{weight});
#	}
#	$out .= $r->make();
    }
    else {
	$out .= $this->error("No such URL");
    }
    $out .= $ml->p($ui->BackButton());
    return $out;
}

1;
