package Modules::Tags;
#-----------------------------------------------------------------------
#
#   Tags : tag selected content with keywords for more efficient
#   browsing, indexing, and searching.
#
#-----------------------------------------------------------------------
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

use strict;
use ExSite::Config;
use ExSite::Object;
use ExSite::Misc;
use ExSite::UI;
use ExSite::ML;
use ExSite::Module qw(&service_page);
use ExSite::Time;
use ExSite::Content;
use ExSite::Index;
use ExSite::Keyword;
use Modules::Content;
use vars qw(@ISA $ml $ui);
@ISA = qw(Modules::Content);

sub write {
    my ($this,$opt) = @_;
    my $out;
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    my %opt = $opt ? &DecodeString($opt) : %{$this->{input}};
    $this->{section_id} = $this->get_section_id;
    if ($opt eq "list" || $opt{indextype} eq "list") {
	$out .= $this->index("list");
    }
    elsif ($opt eq "cloud" || $opt{indextype} eq "cloud") {
	$out .= $this->index("cloud");
    }
    elsif ($opt{content}) {
	# generate a linked list of tags under an item
	$out = $this->content_tags($opt{content});
    }
    elsif ($this->{keyword}) {
	# generate a list of resources under a keyword
	$out = $this->index_keyword($opt{keyword});
    }
    return $ml->div($out,{class=>"Tags"}) if $out;
    return undef;
}

sub ioctl {
    my $this = shift;
    $_ = shift;   # $_ is the ioctl request
    if (/ModuleName/) {
	return "Keyword Tags";
    }
    elsif (/ModuleInfo/) {
	return "Allows you to tag content with keywords for topic-based navigation and indexing.";
    }
    elsif (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/Category/) {
	return "CMS";
    }
    elsif (/PublishRule/) {
	return "static";
    }
    return undef;
}

sub index {
    my ($this,$style) = @_;
    my $c = $share{Page} || new ExSite::Content();
    my $tree = $c->get_content_tree;
    my @index = $tree->find({type=>$c->isubtype("index")},$this->{section_id});
    my $out;
    foreach my $indata (@index) {
	my $index = $c->get_content_obj($indata);
	$out .= $index->index(style=>$style);
    }
    return $out;
}

# display keyword tags for a particular item, linked back to the index

sub content_tags {
    my ($this,$id) = @_;
    my $c = new ExSite::Content(id=>$id);
    return $c->show_tags();
}

sub index_keyword {
    my ($this,$keyword) = @_;
    my $out;
    my $c = new ExSite::Content();
    my $tree = $c->get_content_tree();
    my $ktype = $c->isubtype("keyword");
    my @kw = $tree->find({type=>$ktype,label=>$keyword},$this->{section_id});
    foreach my $kw (@kw) {
	my $k = new ExSite::Keyword(data=>$kw);
	$out .= $k->show();
    }
    return $out;
}

sub ctrl_panel {
    my $this = shift;
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    my $out;
    my @path = ( $ml->a("Top", { href=>$this->link(section_id=>undef,kw=>undef,content=>undef,cmd=>undef)}) );

    $this->{section_id} = $this->get_section_id();
    if ($this->{section_id}) {
	my $s = new ExSite::Section(id=>$this->{section_id});
	push @path, $ml->a($s->title, { href=>$this->link(section_id=>$this->{section_id},content=>undef,kw=>undef,cmd=>undef)});
    }
    else {
	return $this->set_section_id();
    }
    
    if ($this->{input}{id}) {
	$this->{content} = new ExSite::Content(id=>$this->{input}{id});
	push @path, $ml->a($this->{content}->label, { href=>$this->link(section_id=>$this->{section_id},content=>$this->{input}{id},kw=>undef,cmd=>undef)});
    }
    elsif ($this->{input}{kw}) {
	$this->{keyword} = new ExSite::Keyword(id=>$this->{input}{kw});
	my $index = $this->{keyword}->parent();
	push @path, $ml->a($index->title . ": " . $this->{keyword}->label, { href=>$this->link(section_id=>$this->{section_id},content=>undef,kw=>$this->{input}{kw},cmd=>undef)});
    }

    my $c = new ExSite::Content;
    $c = $c->get_content_obj($this->{input}{id});
    $out .= $this->pathbar($c,section_id=>$this->{section_id});

    if ($this->{input}{cmd} eq "newindex") {
	$out .= $this->new_index();
	return $out;
    }
    elsif ($this->{input}{cmd} eq "newkw") {
	$out .= $this->new_keyword();
	return $out;
    }
    elsif ($this->{input}{cmd} eq "recent") {
	$out .= $this->recent_content();
	return $out;
    }
    else {
	if ($this->{input}{id}) {
	    $out .= $this->tags($c);
#	$out .= $this->show_content();
	}
	elsif ($this->{input}{kw}) {
	    $out .= $this->show_keyword();
	}
	else {
	    $out .= $this->show_section();
	}
    }

    return $out;
}
 
sub show_section {
    my $this = shift;
    my $out;
    $out .= $ui->ToolBar(
	tools=>[
	    {label=>"new index",url=>$this->link(cmd=>"newindex"),faicon=>"plus"},
	    {label=>"recent content",url=>$this->link(cmd=>"recent"),faicon=>"time"},
	    {label=>"all content",url=>$this->link(cmd=>"content"),faicon=>"list"}
	]);
    if ($this->{input}{cmd} eq "content") {
	$out .= $this->all_content();
    }
    else {
	$out .= $this->show_indexes();
    }
    return $out;
}

sub show_indexes {
    my $this = shift;
    my $out;
    my %index = $this->get_indexes();
    my $c = new ExSite::Content();
    my $tree = $c->get_content_tree;
    my @index = $tree->find({type=>$c->isubtype("index")},$this->{section_id});
    foreach my $indid (keys %index) { 
#ata (@index) {
	my $in = $index{$indid}{_}; #new ExSite::Index(data=>$indata);
	my $inreport = new ExSite::ReportBuilder(title=>$in->title);
	$inreport->headers("Keyword","# Tags","URL to public index");


#	my %kw;
#	my @keyword = $tree->find({type=>$c->isubtype("keyword")},$indid);
#	foreach my $kw (@keyword) {
#	    my $kwc = new ExSite::Keyword(data=>$kw);
#	    $kw{$kwc->label} = $kwc;
#	}

	foreach my $kw (sort keys %{$index{$indid}}) {
	    next if ($kw eq "_");
	    my $url = $index{$indid}{$kw}->get_url_canonical();
	    #my $url = $kw{$kw}->get_page_url_dynamic();
	    #my $url = $index{$indid}{$kw}->get_url();
	    $inreport->push(
		$ml->a($kw,{href=>$this->link(kw=>$index{$indid}{$kw}->id)}),
		$index{$indid}{$kw}->count_contents("alias"),
		$ml->a($url,{href=>$url}),
		);
	}
	$inreport->tools($ml->a("+ new keyword",{href=>$this->link(cmd=>"newkw",index=>$in->id),class=>"button_sm"}));
	$inreport->foot("Click on the keyword to manage it. Click on the URL to visit the public index for that keyword.");
	$out .= $inreport->make();
    }

    ### FIXME: show as a table, with counts, tools

    if (scalar @index == 0) {
	$out .= $ml->p("You have no keyword indexes set up on this section.");
    }

    return $out;
}

sub show_keyword {
    my $this = shift;
    my $out;
    my $ui = &get_obj("UI");
    my $kw = $this->{keyword};
    my $kwreport = new ExSite::ReportBuilder(title=>"Content tagged '".$ml->em($kw->title)."'");
    $kwreport->headers("Content","Type","Date","Public URL");
    $kwreport->nodata("No tagged content");
    my @content = $kw->get_contents();
    foreach my $tag (reverse @content) {
	#next if (! $tag->alias);
	my $url = $tag->get_url_canonical();
	#my $url = $tag->get_page_url_dynamic();
	$kwreport->push(
	    $ml->a($tag->label,{href=>$this->link(id=>$tag->id)}),
	    $tag->subtype,
	    $tag->posting_date(),
	    $ui->fatool("link",url=>"javascript:openOLFrame('$url')"),
	    );
    }
    #$kwreport->foot("Click on the content to manage it. Click on the URL link to visit the public URL for that content.");
    $out .= $kwreport->make();
    $out .= $ui->OverlayFrame();
    return $out;
}

sub all_content {
    my $this = shift;
    my $s = new ExSite::Section(data=>$share{DB}->this_site());
    my $tree = $s->get_content_tree();
    my (@topnode,@item);
    if ($this->{section_id}) {
	push @topnode, scalar $share{DB}->fetch("content",$this->{section_id});
    }
    else {
	@topnode = $tree->get_topnodes_data();
    }
    foreach my $top (@topnode) {
	push @item, $this->content_subtree($top,$tree,1);
    }
    return 
	$ui->TreeView(@item).
	$ui->OverlayFrame();
}

sub content_subtree {
    my ($this,$node,$tree,$open) = @_;
    my $c = new ExSite::Content();
    $c = $c->get_content_obj($node);
    my %item = (
	label=>$c->name() || $c->label(),
	text=>$c->subtype(),
	url=>"javascript:openOLFrame('".$this->link(id=>$c->id,cmd=>undef)."')",
	open=>$open,
	);
    my $details = $c->subtype();

    my %tag = $this->get_tags_by_keyword($c->id);
    if (keys %tag > 0) {
	$details .= "; ";
	$details .= $ml->span("Tagged as: ".$ml->em(join(", ",sort keys %tag)),{class=>"help"});
    }
    $item{text} = $details;
    
    my @subnode = $tree->get_child_data($node->{content_id});
    my $subout;
    my $ikw = $c->isubtype("keyword");
    my $iindex = $c->isubtype("index");
    my $ialias = $c->isubtype("alias");
    my $itemplate = $c->isubtype("template");
    my $icomment = $c->isubtype("comment");
    my $icontent = $c->isubtype("content");

    my @sublist;
    foreach my $sub (@subnode) {
	my $itype = $sub->{type};
	next if ($itype == $iindex ||
		 $itype == $ikw ||
		 $itype == $itemplate ||
		 $itype == $icomment ||
		 $itype == $ialias);
	if ($itype == $icontent) {
	    # only tag contents in libraries (eg. documents)
	    next if ($sub->{name} eq "body");
	    my $parent = $c->get_content_obj($sub->{parent});
	    next if ($parent->subtype() ne "library");
	}
	push @sublist, $this->content_subtree($sub,$tree,0);
    }
    if (scalar @sublist) {
	$item{sublist} = \@sublist;
    }
    return \%item;
}

sub get_indexes {
    my $this = shift;
    my %index;
    my $c = new ExSite::Content();
    my $tree = $c->get_content_tree;
    my @index = $tree->find({type=>$c->isubtype("index")},$this->{section_id});
    foreach my $indata (@index) {
	my $in = new ExSite::Index(data=>$indata);
	my $indid = $in->id;
	$index{$indid}{_} = $in;
	my @keyword = $tree->find({type=>$c->isubtype("keyword")},$indid);
	foreach my $kw (@keyword) {
	    my $k = new ExSite::Keyword(data=>$kw);
	    $index{$indid}{$k->label} = $k;
	}
    }
    return %index;
}

sub get_tags {
    my ($this,$content_id) = @_;
    my $c = new ExSite::Content();
    my $ktype = $c->isubtype("keyword");
    my $atype = $c->isubtype("alias");
    my $tree = $c->get_content_tree();
    # find all items in this section aliased to this content ID
    my @alias = $tree->find({type=>$atype,master=>$content_id},$this->{section_id});
    my %tag;
    foreach my $a (@alias) {
	# check if this alias belongs to a keyword
	my $parent = new ExSite::Keyword(data=>$tree->getnode_data($a->{parent}));
	if ($parent->isubtype() == $ktype) {
	    my $kw = $parent->label;
	    $tag{$parent->id} = {
		alias => $a,
		parent => $parent,
		keyword => $kw,
	    };
#	    $tag{$kw} = $tag{$a->{content_id}};
	}
    }
    return %tag;
}

sub get_tags_by_keyword {
    my ($this,$content_id) = @_;
    my %tag = $this->get_tags($content_id);
    return map { $_->{keyword} => $_ } values %tag;
}

sub new_index {
    my ($this) = @_;
    my $out = $ml->h1("New Index");
    if ($this->{post}{name}) {
	my $i = new ExSite::Index();
	my $index = $i->new_content_obj(type=>"index",title=>$this->{post}{name});
	if ($index->defined) {
	    # success
	    $out .= $ml->p("Created index $this->{post}{name}");
	    $ml->redirect($this->link(__plaintext=>1,cmd=>undef));
	}
	else {
	    $out .= $i->show_diagnostics();
	}
    }
    else {
	my $f = new ExSite::FormBuilder();
	$f->input(prompt=>"Index Name",
		  name=>"name",
		  type=>"text",
		  tail=>"Example: 'Keyword Index'",
		  required=>1);
	$out .= $f->make();
    }
    return $out;
}

sub new_keyword {
    my ($this) = @_;
    my $out = $ml->h1("New Keyword");
    if ($this->{post}{keyword}) {
	my $k = new ExSite::Keyword();
	my $kw = $k->new_content_obj(
	    type=>"keyword",
	    label=>$this->{post}{keyword},
	    parent=>$this->{input}{index},
	    );
	if ($kw->defined) {
	    # success
	    $out .= $ml->p("Created keyword $this->{post}{keyword}");
	    $ml->redirect($this->link(__plaintext=>1,cmd=>undef));
	}
	else {
	    $out .= $k->show_diagnostics();
	}
    }
    else {
	my $f = new ExSite::FormBuilder();
	$f->input(prompt=>"Keyword",
		  name=>"keyword",
		  type=>"text",
		  required=>1);
	$out .= $f->make();
    }
    return $out;
}

sub recent_content {
    my $this = shift;
    if (! $share{querylib}{"recent content"}) {
	# copied from SocialMedia
	$share{DB}->set_query("recent content",
			      sql=>"select * from content c, content_type t where c.status=0 and c.type=t.content_type_id and t.name in ('page','article','event','product','album') order by c.ptime desc limit 50",
			      nparam=>0,
			      keys=>["content","content_type"],
			      mode=>"r");
    }
    my $out = $ml->h1("Recently Posted Content");
    my $c = new ExSite::Content();
    my $r = new ExSite::ReportBuilder(title=>"Recent Posts");
    $r->set("dynamic",1);
    $r->headers("Post","Type","Posted","Public Link");
    my @c = $share{DB}->get_query("recent content");
    foreach my $cdata (@c) {
	my $p = $c->get_content_obj($cdata);
	next if (! $p->is_published);
	next if ($p->my_section->id != $this->{section_id});
	$r->push(
	    $ml->a($p->title,{href=>$this->link(cmd=>undef,id=>$p->id)}),
	    $p->subtype(),
	    $p->posting_date(),
	    $ui->fatool("link",url=>$p->get_url_canonical()),
	    );
    }
    $out .= $r->make();
    return $out;
}

1;
