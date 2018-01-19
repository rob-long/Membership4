package Modules::Zine;

#----------------------------------------------------------------------------
#
#   Copyright (C) 2012 - Exware Solutions, Inc.  http://www.exware.com
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
#
#  Zine backwards-compatibility module for v4
#
#  This module handles cross-zine functions such as recent articles,
#  recent comments, feature articles, and user post history.
#
#----------------------------------------------------------------------------

use strict;

use ExSite::Config;
use ExSite::Input;
use ExSite::Misc;
use ExSite::ML;
use Modules::BaseDCD;

use vars qw(@ISA $ml);
@ISA = qw(Modules::BaseDCD);

sub write {
    my ($this,$options) = @_;
    $ml = &get_obj("ML");
    my %opt = &DecodeString($options);
    #my $cmd = $this->{input}{zine} || $opt{zine};
    my $cmd = $opt{zine};
    my $content;
    if ($opt{aid}) {
	$content = $share{Page}->get_content_obj($opt{aid});
    }
    # newarticles, newcomments, zinedex, feature, history
    if ($cmd =~ /^newarticles?$/) {
	return $this->index_latest_articles(%opt);
    }
    elsif ($cmd =~ /^newcomments?$/) {
	return $this->index_latest_comments(%opt);
    }
    elsif ($cmd =~ /zine?dex/) {
	$opt{zine_id} or $opt{zine_id} = $opt{aid};
	$opt{type} or $opt{type} = $this->{input}{type};
	return $this->zinedex(%opt);
    }
    elsif ($cmd eq "feature") {
	return $content->show(%opt);
    }
    elsif ($cmd eq "history") {
	return $this->index_user_history(%opt);
    }
    elsif ($content) {
	if ($cmd eq "index") {
	    return $content->index(%opt);
	}
	else {
	    return $content->show(%opt);
	}
    }
    return "Zine: nothing to show.";
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
    elsif (/ModuleName/) {
	return "e-Zines";
    }
    elsif (/ModuleInfo/) {
	return "Zine backwards-compatibility module for v4";
    }
    elsif (/PublishRule/) {
	return "daily"; # nightly republish is good enough
    }
}

#----------------------------------------------------------------------------
# Everything after this point consists of private methods.

sub index_user_history {
    my ($this,%opt) = @_;
    my $limit = $opt{limit} || $config{Zine}{history_limit};
    my $uid = $opt{uid} || $share{DB}->my_uid;
    my $section = $this->this_section();
    my $section_id = $section->{section_id};

    my $out;
    my $c = new ExSite::Content();

    # find all article where we have been tagged as the owner
    my @art = $share{DB}->custom_query("select c.*,k.role from content c, content_key k where k.content_id=c.content_id and k.member_id=? order by ctime desc",$uid);
    my @item;
    my $count;
    foreach my $art (@art) {
	if ($art->{role} =~ /owner/) {
	    delete $art->{role};
	    my $content = $c->get_content_obj($art);
	    if ($content->is_active) {
		if ($content->my_section->id == $section_id) {
		    my $title = $content->title;
		    my $date = $content->date;
		    my $url = $content->get_url;
		    $out .= $ml->p(
			$ml->a($title,{href=>$url}).", posted on $date"
			);
		    $count++;
		    last if ($limit && $count == $limit);
		}
	    }
	}
    }
    if ($out) {
	$out = $ml->h1(&substitute($msg{"Recent Postings from [[user]]"},{user=>$share{DB}->user_name($uid)})).$out;
    }
    $out .= $this->run_handler("ZineAboutUser",$uid);
    return $out;
}

# index_latest: summarize recently added articles
# type = article | comment
# id = blog or other parent to search within
# number = max number to index

sub index_latest {
    my ($this,$type,%opt) = @_;
    return undef if ($type !~ /^(article|comment)$/);
    my $out;
    my $id = $opt{aid} || $opt{id};
    my $limit = $opt{limit} || $opt{number} || 5;
    my $format = $opt{format} || "article_link";
    my $p = $share{Page};
    my $s = $p->my_section();
    my @all = $p->sort("ctime",$s->get_descendants($type));
    if (@all > 0) {
	my $n = 0;
	$out = $ml->h1($msg{"Recent ${type}s"});
	foreach my $a (reverse @all) {
	    my $c = $p->get_content_obj($a);
	    next if (! $c->is_viewable);
	    $out .= $c->show_formatted($format);
	    $n++;
	    last if ($n > $limit);
	}
	$out = $n > 0 ? $ml->div($out,{class=>"ZineIndexLatest"}) : undef;
    }
    return $out;
}

sub index_latest_articles {
    my ($this,%opt) = @_;
    # return a dummy string in case there are no articles
    return $this->index_latest("article",%opt) || " ";
}

sub index_latest_comments {
    my ($this,%opt) = @_;
    # return a dummy string in case there are no comments
    return $this->index_latest("comment",%opt) || " ";
}

sub fetch_latest {
    my ($this,$type,$id,$number,$zinetype) = @_;
    if (! $type) { $type = "article"; }
    # set $number if it was not passed in  
    $number or $number = $config{Zine}{"new_".$type."s"} || 4;

    # set the zines to check
    my @aid;
    if ($id) {
	@aid = ($id);
    }
    else {

	#### find all types that can contain articles (or comments)
	#### find all of those within this section

    }
    return undef if (scalar @aid == 0);

    ### TODO

}

# zinedex - tabular index of zines, with activity summaries

sub zinedex {
    my ($this,%opt) = @_;
    my $type = $opt{type};
    my $section_id = $opt{section_id};
    my $zine_id = $opt{zine_id},
    my $stat = $this->run_handler("ZineDex",%opt);
    return $stat if ($stat);
    $this->save;

    my $db = $share{DB};
    my ($sid,$see_general_zines);
    $this->{zinedex_count} = 0;
    if ($db->is_admin()) {
	$sid = $section_id || ($share{Page} ? $share{Page}->id("section") : 0); 
	$see_general_zines = 1;
    }
    else {
	$sid = $share{Page} ? 
	    $share{Page}->id("section") : 
	    $section_id || $db->my_user_record()->{section_id};
	# general zines available for browsing, but not admin
	$see_general_zines = (! $this->{admin});
    }
    my @allzine = $this->all_zines();
    my $tree = new ExSite::Tree("article_id","parent_id",@allzine);
    if ($opt{zine_id}) {
	# only show a zinedex of a particular branch
	$tree = $tree->subtree($opt{zine_id});
    }

    # walk our tree, and disable zines that we should not be seeing

    my @z = $tree->get_topnodes_data();
    while (my $z = shift @z) {
	if ($sid && $z->{section_id} && $z->{section_id} != $sid) {
	    # not ours; prune this branch
	    $tree->delnode($z->{article_id});
	    next;
	}
	elsif (! $z->{section_id} && ! $see_general_zines) {
	    # we cannot view global zines
	    $tree->delnode($z->{article_id});
	    next;
	}
	elsif ($type && ! $tree->count({type=>$type},$z->{article_id})) {
	    # none of the desired type in this branch
	    $tree->delnode($z->{article_id});
	    next;
	}
	elsif ($this->{admin} && $z->{owner} && 
	       ($db->level < $config{auth}{root_auth_level} - 1) &&
	       $z->{owner} != $db->my_uid()) {
	    # admin mode, this zine has an owner, and it's not us
	    $tree->delnode($z->{article_id});
	    next;
	}
	my @child = $tree->get_child_data($z->{article_id});
	foreach my $c (@child) {
	    if ($type && ! $tree->count({type=>$type},$c->{article_id})) {
		# none of the desired type in this sub-branch
		$tree->delnode($c->{article_id});
		next;
	    }
	}
    }
    
    # display the zines in a tabular format

    my $title = $opt{title};
    if (! $title) {
	if ($type) {
	    $title = $msg{$this->confrule("whatami",undef,$type)."s"};
	}
	else {
	    $title = $msg{"Zines"};
	}
    }
    my $atype = (! $type || $this->confrule("allow","article",$type)) ?
	$msg{"Articles"} : $msg{"Threads"};

    my $out = 
	$ml->caption($title).
	$ml->tr(
		$ml->th($msg{$this->{config}{article_type}{$type}}).
		$ml->th($msg{$atype}).
		($this->{config}{hide_comments_column}{$type} ? "" : $ml->th($msg{"Comments"})).
		$ml->th($msg{"Most Recent Post"})
		);

    $opt{tree} = $tree;
    my $zout;
    my @zine = sort {
	($a->{sortkey} || $a->{title}) cmp ($b->{sortkey} || $b->{title})
	} $tree->get_topnodes_data();
    $this->{zinedex_depth} = 0;
    foreach my $z (@zine) {
	next if ($z->{type} eq "book");
	$opt{article} = $z;
	$zout .= $this->zinedex_r(%opt);
    }
    foreach my $z (@zine) {
	next if ($z->{type} ne "book");
	$opt{article} = $z;
	$zout .= $this->zinedex_r(%opt);
    }
    $this->restore;
    if ($zout) {
	$out .= $zout;
    }
    elsif ($opt{hide_empty_zinedex}) {
	return undef;
    }
    else {
	$out .= $ml->tr($ml->td("No ".$this->module_name."s found.",{colspan=>4}));
    }
    return $ml->table($out,{ class=> "Report" } );
}

sub zinedex_r {
    my ($this,%opt) = @_;
    my $type = $opt{type};
    my $article = $opt{article};
    my $tree = $opt{tree};
    my ($out,$db,$article_count,$comment_count);
    $db = $share{DB};
    $this->set($article);

    # count methods create their own trees as needed
    $comment_count = $this->count($article->{article_id},"comment");
    if (! $type || $this->confrule("allow","article",$type)) {
	$article_count = $this->count($article->{article_id},"article");
    }
    else {
	# should be no articles; count threads instead
	my $tree = $this->fetch_tree($this->{article_id});
	my $match = {type=>"comment",thread=>0};
	if (! $this->admin_mode) { $match->{status} = "active"; }
	$article_count = $tree->count($match,$this->{article_id});
    }

    if ($type && $article->{type} ne $type) {
	# wrong type; assume it is an oganizational category
	$out .= $ml->tr($ml->th($article->{title},{ class=>"ReportTitle", colspan=>4 }));
    }
    elsif (! $opt{hide_top} || $this->{article_id} != $opt{zine_id}) {

	my $time;
	my @articles = $this->fetch_latest("article",$this->{article_id},1);
	my @comments = $this->fetch_latest("comment",$this->{article_id},1);

	if (@articles > 0) { $time = $articles[-1]{mtime}; }
	if (@comments > 0 && $comments[-1]{mtime} > $time) { $time = $comments[-1]{mtime}; }
	my $date = "n/a";
	if ($time) {
	    my $t = new ExSite::Time($time,"sql_timestamp");
	    $date = $t->write($this->{config}{zinedex_date_format});
	}
	my $title;
	if ($article->{section_id} && 
	    $this->{admin} && 
	    ! $opt{no_section_name}) {
	    my $s = $db->fetch("section",$article->{section_id});
	    $title = $s->{title}.": ";
	}

	# the zinedex link has a few features for styling "new" links
	# The "ZineNew" class is added if is_new() indicates that the zine
	# holds new content.  This is customizable with a handler.
	# We also add dummy ac and cc parameters to hold the article count
	# and comment count; these will cause links to the zine to appear
	# unvisited if these counts change since the last time you were there.

	my $linkclass = $this->is_new ? "ZineNew" : undef;
	if ($opt{nolink}) {
	    $title = $article->{title};
	}
	elsif ($this->{config}{zinedex_show_visited}) {
	    $title .= $this->show_link(
				       undef,
				       $linkclass,
				       ac=>$article_count,
				       cc=>$comment_count,
				       );
	}
	else {
	    $title .= $this->show_link(undef,$linkclass);
	}

	if (! $type && ! $opt{hide_type}) { 
	    $title .= " ".$ml->em("(".ucfirst($article->{type}).")"); 
	}
	my $description = $article->{summary} ? 
	    $ml->br.$ml->span($article->{summary},{class=>"ZineReportAsbstract"}) : "";
	$this->{zinedex_count} ++;
	
	my $comments_column = $ml->td($comment_count) unless ($this->{config}{hide_comments_column}{$type});
	
	my $class = ($this->{zinedex_count} % 2) ? "A" : "B";
	my $indent;
	if (! $opt{hide_top}) {
	    $indent = "&nbsp;" x ($this->{zinedex_depth} * 4);
	    if ($indent) {
		$indent .= "&#8627;";
	    }
	}
	$out .= $ml->tr(
			$ml->td(
			        $indent.
				$ml->span($title,{class=>"ZineReportTitle"}).
				$description
				).
			$ml->td($article_count).
			$comments_column.
			$ml->td($date),
			{ class=>$class }
			);
    }

    # recurse into child zines
    foreach my $z ($tree->get_child_data($article->{article_id})) {
	next if (! $z->{section_id} && ! $db->is_admin());  # global zine
	$this->{zinedex_depth}++;
	my %zopt = %opt;
	$zopt{type} = $type;
	$zopt{article} = $z;
	$zopt{tree} = $tree;
	$out .= $this->zinedex_r(%zopt);
	$this->{zinedex_depth}--;
    }
    return $out;
}

1;
