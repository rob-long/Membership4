package Modules::SMenu;

#----------------------------------------------------------------------------
#
#   Copyright 2001-2016 Exware Solutions, Inc.  http://www.exware.com
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

=head1 Modules::SMenu - cascading DHTML menu-builder for ExSite

=cut

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Page;
use ExSite::Section;
use ExSite::Tree;

# inherit from BaseDCD class
use Modules::BaseDCD;
use base qw(Modules::BaseDCD);

sub write {
    my ($this, $opt) = @_;
    $this->config_setup($opt);
    # setup
    my $Page = $this->get_page();
    return "" if !$Page;
    my $sid = $this->section_id || $Page->my_section->id;

    if ($opt =~ /parent/) {
	my $parent_id = $Page->my_section->getdata("parent");
	if ($parent_id) {
	    $sid = $parent_id;
	}
	else {
	    return "";
	}
    }

    my $language = $share{Page}->getdata("language");
    if ($this->section_id){
	my $s = new ExSite::Section(id=>$this->section_id);
	$this->{map} = $s->get_mapped_pages(0,{language=>$language});
    }
    elsif ($Page->is_page()) {
	my $s = new ExSite::Section(id=>$sid);
	$this->{map} = $s->get_mapped_pages(0,{language=>$language});
    }
    else {
	# probably a template; make a fake map
	$this->{map} = new ExSite::Tree("content_id","parent",
	      ({content_id=>1,parent=>$sid,label=>"Home",access=>0,url=>"#"},
	       {content_id=>2,parent=>$sid,label=>"About",access=>0,url=>"#"},
	       {content_id=>3,parent=>$sid,label=>"Contact",access=>0,url=>"#"},
	       {content_id=>4,parent=>$sid,label=>"Links",access=>0,url=>"#"},
	      ));
    }
    # generate a menu
    return "\n<!--SMenu-->\n".$this->include_files.$this->menu($this->{config})."\n<!--SMenu-->\n";
}

sub get_page {
    my $this = shift;
    my $page;
    if ($this->{config}{page_id}) {
	$page = $share{Page}->get_content_obj($this->{config}{page_id});
    }
    return $page || $share{Page};
}

sub ioctl {
    my $this = shift;
    $_ = shift;
    if (/ModuleInfo/) {
	return "SMenu builds multi-level cascading menus.  It automatically
assembles site menus and site maps by inspecting the relationships/config
between your webpages.  It displays the top-level pages
in a horizontal \"menu bar\".  Secondary pages are displayed in drop-down
menus that appear when you mouse over the menu bar.  Tertiary pages appear
in drop-down menus that spring off the secondary menus.";
    }
    elsif (/PublishRule/) {
	return "static";
    }
    return undef;
}

# Gather module configuration
sub config_setup{
    my ($this,$opt) = @_;
    my %opt = ExSite::Misc::DecodeString($opt);
    my %default = ref($config{SMenu}) =~ /hash/i ? %{$config{SMenu}} : ();
    $this->{config} = \%default;
    foreach my $k (keys(%opt)){
	next if (!defined $opt{$k});
	$this->{config}{$k} = $opt{$k};
    }
    if ($opt =~ /vertical/i){
	$this->vertical(1);
    }
    # copy preferences
    my $site = $share{DB}->this_site();
    if ($site) {
	my $section_id = $site->{content_id};
	my @attr = $share{DB}->fetch_match("attribute",{tablename=>"content",id=>$section_id});
	foreach my $attr (@attr) {
	    my @param = split /\./,$attr->{name};
	    next if shift @param ne "SMenu";
	    my $conf = $this->{config};
	    while (my $p = shift @param) {
		if (@param == 0) {
		    $conf->{$p} = $attr->{value};
		} 
		elsif (! exists $conf->{$p}) {
		    $conf->{$p} = {};
		    $conf = $conf->{$p};
		} 
		else {
		    $conf = $conf->{$p};
		}
	    }
	}
    }
    return;
}

sub section_id{
    my ($this) = @_;
    return $this->{config}{section_id} || 0;
}

# Vertical Menu
sub vertical{
    my ($this,$value) = @_;
    if (defined $value){
	$this->{config}{vertical} = $value ? 1  : 0;
    }
    return $this->{config}{vertical} || 0;
}

sub include_files{
    my $this = shift;
    my $ml = &get_obj("ML");
    my $out;
    if ($this->{config}{include_mobile_menu}){
	$out .= $ml->link(undef,{rel=>"stylesheet",type=>"text/css",href=>"$config{server}{HTMLpath}/_Modules/SMenu/style_mobile.css"});
	$out .= $ml->link(undef,{rel=>"stylesheet",type=>"text/css",href=>"$config{server}{HTMLpath}/_Modules/SMenu/slicknav.css"});
	$out .= $ml->script(undef,{src=>"$config{server}{HTMLpath}/_Modules/SMenu/slicknav/jquery.slicknav.min.js"});
	if ($this->{config}{mobile_menu_only}){
	    $this->{config}{SlickNav}{option}{duplicate} = 0;
	}
	require JSON;
	my $slicknav_options;
	if (ref($this->{config}{SlickNav}{option}) =~ /hash/i){
	    $slicknav_options = JSON::to_json($this->{config}{SlickNav}{option});
	}
	$out .= $ml->script("jQuery(document).ready(function(){jQuery('#SMenu').slicknav(".$slicknav_options.");});");
    }else{
	$out .= $ml->link(undef,{rel=>"stylesheet",type=>"text/css",href=>"$config{server}{HTMLpath}/_Modules/SMenu/style_desktop.css"});
    }
    return $out;
}

# Show this page on the menu?
sub page_visible{
    my ($this,$pdata) = @_;
    my $p;
    if ((ref $pdata) =~ /ExSite|Modules/) {
	if ($pdata->is_page) { $p = $pdata; }
	else { $p = $pdata->my_page(); }
    }
    else { $p = $share{Page}->get_content_obj($pdata); }
    return 0 if (! $p->is_active);
    return 0 if ($p->hide_from("menu") || $p->hide_from("sitemap"));
    return 0 if ($this->{config}{no_default_version} && 
		 $p->getdata("language") ne $share{Page}->getdata("language"));
    return 1;
}

sub custom_link{
    # $where: before|after
    my ($this,$where) = @_;
    return undef if !$this->{config}{item}{$where};
    my @menu_items = ref $this->{config}{item}{$where} eq "ARRAY" ? @{$this->{config}{item}{$where}} : ($this->{config}{item}{$where});
    my @menu;
    foreach my $menu_item (@menu_items) {
	my ($label, $url, $id) = split(/\|/, $menu_item);
	push(@menu, {label => $label, url => $url, id => $id || undef});
    }
    return \@menu;
}

sub html_menu{
    my $this = shift;
    my $mdata = shift;
    my $ul_attr = shift || undef;
    return "" if (!$mdata || ref($mdata) !~ /array/i);
    my $ml = &get_obj("ML");
    my $out;
    foreach my $mdat(@$mdata){
	my $link = $ml->a($mdat->{a_label},$mdat->{a_attr});
	$out .= $ml->li($link.$this->html_menu($mdat->{submenu}),$mdat->{li_attr});
    }
    return $out ? $ml->ul($out,$ul_attr) : "";
}

sub get_child_link{
    my ($this,$pid) = @_;
    my @items = $this->{map}->get_child_data($pid);
    my @itemlist;
    foreach my $itm (@items){
	next if !$this->page_visible($itm);
	push @itemlist,$itm;
    }
    return \@itemlist;
}

sub generate_menu{
    my $this = shift;
    my $opt = shift;
    # get the menubar links
    my @map = $this->{map}->get_topnodes_data();
    push @map, $this->{map}->get_child_data($map[0]{content_id}); #pages
    my $this_page_id = $this->get_page() ? $this->get_page()->id() : 0;
    if ($this->{config}{page_id}) {
	foreach my $map_item (@map) {
	    next if !$this->page_visible($map_item);
	    if ($this->{config}{page_id} == $map_item->{content_id}) {
		@map = ($map_item);
		$this_page_id = $map_item->{content_id};
		last;
	    }
	}
    }
    my @menu_data;
    my %submenu_data = (current=>$this_page_id);
    foreach my $p (@map){
	next if !$this->page_visible($p);
	my $menuPage = $share{Page}->get_content_obj($p);
	my $pid = $menuPage->id;
	if ($submenu_data{current} == $pid){
	    $submenu_data{page}{$pid} = 1;
	}
	my %mlink = (
	    pid=>$pid,
	    li_attr=>{id=>$this->elm_id($pid),class=>"mLabel page_$pid"},
	    a_attr=>{href=>$this->page_url($menuPage),class=>"menu"},
	    a_label=>$menuPage->label,
	    submenu=>($opt->{no_sub_page} ? [] : $this->generate_menu_r($pid,$pid,\%submenu_data)),
	    link_type=>"link"
	    );
	if ($this->{config}{replace_top_level_link_with_child_link} && $this->{config}{replace_top_level_link_with_child_link} =~ /^\d+$/){
	    my $items = $this->get_child_link($pid);
	    if (scalar(@$items) > 0){
		my $my_itm = $items->[$this->{config}{replace_top_level_link_with_child_link} - 1];
		if ($my_itm){
		    my $mPage = $share{Page}->get_content_obj($my_itm);
		    $mlink{a_attr}{href} = $this->page_url($mPage);
		}
	    }
	}
	push(@menu_data,\%mlink);
    }
    if (!$this->{config}{disable_thispage_id}){
	foreach my $m(@menu_data){
	    if ($submenu_data{page}{$m->{pid}}){
		$m->{li_attr}{id} = "thispage";
	    }
	}
    }
    foreach my $where (("before","after")){
	my $custom = $this->custom_link($where);
	next if !$custom;
	foreach my $menu_item (@$custom) {
	    next if (!$menu_item);
	    my %cLink = (li_attr=>{id=>($menu_item->{id} ? $menu_item->{id} : "link_${where}"),class=>"mLabel"},a_attr=>{href=>$menu_item->{url},class=>"menu"},a_label=>$menu_item->{label});
	    if ($where eq "before"){
		unshift @menu_data, \%cLink;
	    } 
	    elsif ($where eq "after") {
		push  @menu_data, \%cLink;
	    }
	}
    }
    return \@menu_data;
}

sub generate_menu_r {
    my $this = shift;
    my $id = shift;
    my $pageid = shift;
    my $submenu_data = shift;
    return [] if !$id;
    if ($submenu_data->{current} == $id){
	$submenu_data->{page}{$pageid} = 1;
    }
    my @items = $this->{map}->get_child_data($id);
    return [] if scalar(@items) <= 0;
    my @menu;
    foreach my $p (@items) {
	my $menuPage = $share{Page}->get_content_obj($p);
	my $mpid = $menuPage->id;
	next if !$this->page_visible($menuPage);
	my @s_items = map {$this->page_visible($_) ? $_ : ()} $this->{map}->get_child_data($mpid);
	my %mlink = (
	    li_attr=>{id=>$this->elm_id($mpid),class=>"mItem page_$mpid"},
	    a_attr=>{href=>$this->page_url($menuPage),class=>"menu".(scalar(@s_items) > 0 ? " hassubmenu" : "")},
	    a_label=>$menuPage->label(),
	    submenu=>$this->generate_menu_r($mpid,$pageid,$submenu_data)
	    );
	push(@menu,\%mlink);
    }
    if (scalar(@menu) > 0){
	return \@menu;
    }
    return [];
}

sub page_url{
    my ($this,$page) = @_;
    return $page->get_url_canonical;
}

sub menu {
    my $this = shift;
    my $opt = shift || {};
    my $ml = &get_obj("ML");
    my %nav_attr = (class=>"main-navigation");
    if ($this->vertical){
	$nav_attr{class} .= " vertical-menu";
    }else{
	$nav_attr{class} .= " horizontal-menu";
    }
    return $ml->Element("nav",$this->html_menu($this->generate_menu($opt),{id=>"SMenu"}),\%nav_attr);
}

sub elm_id{
    my ($this,$id) = @_;
    return sprintf("page_%d",$id);
}

1;
