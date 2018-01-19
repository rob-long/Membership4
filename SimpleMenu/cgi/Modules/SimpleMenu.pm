package Modules::SimpleMenu;

#----------------------------------------------------------------------------
#
#   Copyright 2001-2014 Exware Solutions, Inc.  http://www.exware.com
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

=head1 Modules::SimpleMenu - generic menu-builder for ExSite

SimpleMenu is a multi-purpose menu-builder for ExSite websites.  It
will create context-specific menus on any web page in a site.
Context-specific means that the site navigation links will reflect the
current location in the site.

SimpleMenu can also serve as a code template for a customized menu
builder, since it contains a general purpose menu-construnction
algorithm based on the ExSite page placement parameters.

SimpleMenu can build four types of menus:

=over 4

=item vertical

navigation links are stacked in a vertical list, with submenus
exploded within this list.  This is the default menu type.

=item horizontal

navigation links are listed left-to-right, menubar style.  Only the
top-level links in the site are shown, and no submenus are displayed.

=item path

the path from the site home page to the current page
is displayed in the "cookie crumb" format, ie. page1 > page2 > page3

=item sitemap

the full site structure is shown, with child
pages indented beneath their parents.

=back

When inserting a web application tag into a block of HTML, any of the
above types may be provided as a parameter.

When manually coding a SimpleMenu dynamic content tag, the format is:

C<E<lt>!--&SimpleMenu(format)--E<gt>>

where "format" is one of the above menu types.

=head3 Sub-menus

SimpleMenu builds global menus for the whole website by default.  That
is, the "top" level pages displayed in the menu are those that have no
parent page defined.  Sub-menus show pages that have a common parent page.

SimpleMenu automatically inserts sub-menus into vertically-formatted menus
if the viewer is viewing a top-level parent page that has child pages, or
is viewing any of those child pages.  It does not descend any further
into the menu hierarchy than this.

If you want to build a menu starting from one of the submenus, instead
of from the top-level, then add a "submenu" keyword to the parameters:

C<E<lt>!--&SimpleMenu(vertical,submenu)--E<gt>>

C<E<lt>!--&SimpleMenu(horizontal,submenu)--E<gt>>

In these cases, the menu shows the pages that are children of the
currently-viewed page.  If the currently-viewed page has no children,
then it shows the submenu to which the current page belongs.  This is
the same as the top-level menu if the viewer is currently on a top-level
page.  If you never want to show ONLY submenu pages, and never top-level
pages, then change <tt>submenu</tt> to <tt>submenu-only</tt> in the above
parameters.

=head2 Customizing Menu Appearance

=head3 CSS

The following CSS classes are used, and may be customized in any
given site's stylesheets:

=over 4

=item div.vmenu

All vertically-formatted menus are wrapped in a div of the "vmenu" class.

=item span.hmenu

All horizontally-formatted menus are wrapped in a span of the "hmenu" class.

=item span.pmenu

All path menus are wrapped in a span of the "pmenu" class.

=item ul.sitemap

All sitemaps are contained in an unnumbered list of the "sitemap" class.

=item a.menu

All menu links in vertical, horizontal, and path menus are of the "menu" class.

=item a.submenu

All submenu links in vertically-formatted menus are of the "submenu" class.

=item a#toppage

If a submenu is open in a vertically-formatted menu, the parent page has the
id "toppage".

=item a#thispage

The page currently being viewed has the id of "thispage" (unless it has
already been tagged as "toppage", above.

=back

=head3 Menu Templates

Vertically-formatted menus will attempt to inline special content objects
to spice up the menu presentation:

=over 4

=item SimpleMenuTop

This content will be placed before all menu links.

=item SimpleMenuMid

This content will be placed between all menu links.

=item SimpleMenuBot

This content will be placed after all menu links.

=back

Using these content objects, a template can incorporate custom table layouts,
border graphics, and other visual tricks to lay out the menu.

You can do the same thing with horizontally-formatted menus, using
content objects named B<SimpleMenuTopH>, B<SimpleMenuMidH>, and
B<SimpleMenuBotH>.

=head3 Menu Spacer Strings

If the content objects noted above do not exist, then SimpleMenu will
used some simple spacer strings in their place.  These are defined
in the SimpleMenu configuration file, which should be located in
C<cgi/conf/SimpleMenu.conf>:

=over 4

=item hmenu_spacer

inserted between menu links in a horizontal menu.  Default: C<&nbsp;|&nbsp;>

=item pmenu_spacer

inserted between menu links in a path menu.  Default: C<&nbsp;&gt;&nbsp;>

=item vmenu_spacer

inserted between menu links in a vertical menu.  Default:
C<E<lt>br<gt>> Note that if you use display:block in your CSS for
menu links, the vmenu_spacer should be left blank to prevent extra
blank lines from being added to your menu layout.

=item submenu_prefix

inserted in front of submenu links.  Default: C<&nbsp;&nbsp;&nbsp;&middot;&nbsp;>

=back

=head2 Sections

By default, SimpleMenu displays a menu for the current section.

To generate a menu for the parent section instead of the current
section, add the "parent" parameter:

    <!--&SimpleMenu(horizontal,parent)-->

To generate a menu for a child section instead of the current section,
specify the child's section ID:

    <!--&SimpleMenu(horizontal,section=NNN)-->

=head3 Subsections in Menus

By default, SimpleMenu displays only the pages within a section.  If
you add the following configuration setting in its config file:

    show_subsections = 1

Then it will also include subsections under the current section.
Subsections are listed after all pages, and in the order the
subsections were created.  These cannot be reordered.

=head1 Configuring Menus

Page order and nesting in menus is determined by the following page
attributes:

=over 4

=item parent_id

Sets the page that this pages nests under.  Set to 0 (or unselect the
page) to make the page a top-level page.

=item rank

This is a number (typically 1-9, but you can use any numbers) used to
sort pages at a particular level in the menus.  Rank 1 pages are
placed before rank 2 pages, etc.  Pages of the same rank have no
particular order with respect to each other.

=back

You can set these values manually in the page configuration forms of most
of the CMS tools.

The easiest way to reorganize your menus, however, is to use the
SimpleMenu control panel which allows you to configure these settings
using a simple drag-and-drop interface.  Click and drag any page to
any other position in the site map.  The new position will be shown
with a dashed line so that you can tell what level of the menus you
are dropping it into.  Once you have your sitemap organized the way
you want, you must click the "Save" button to have SimpleMenu rewrite
the above menu configuration parameters for all of the affected pages.

Note that you can only reorder pages in the menu;  subsections always
appear at the end of the menu in a fixed order.

=cut

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Util;
use ExSite::Page;
use ExSite::Input;
use ExSite::Tree;
use ExSite::UI;
# inherit from BaseDCD class
use Modules::BaseDCD;
use vars qw(@ISA $ml $ui);
@ISA = qw(Modules::BaseDCD);

sub read {
    my ($this,$options) = @_;
    my $in = new ExSite::Input;
    $this->{input} = $in->query;
    $this->{post} = $in->post;
    $this->{is_post} = scalar keys %{$this->{post}};
    if ($this->{is_post}) {
	$this->{keys} = $in->fetch("post","keys");
    }
}

sub write {
    my ($this, $opt) = @_;

    # setup
    my $Page = $share{Page};
    return if (!$Page);
    $ml = &get_obj("ML");
    my $version = $Page->getdata("version");
    my $section = $Page->my_section;
    my $sid = $section->id;
    if ($opt =~ /parent/) {
	my $parent_id = $section->getdata("parent");
	if ($parent_id) {
	    $sid = $parent_id;
	}
	else {
	    return "";
	}
    }
    if ($opt =~ /section=(\d+)/) {
	# show menu for a subsection
	my $sid2 = $1;
	my $s2 = new ExSite::Section(id=>$sid2);
	if ($s2->getdata("parent") == $sid) {
	    $this->{map} = $s2->get_mapped_pages(0,{version=>$version});

	    if ($config{SimpleMenu}{show_subsections}) {
		my @site = $share{DB}->fetch_match("content",{type=>"section",parent=>$sid2});
		foreach my $s (@site) {
		    $s->{index} = "section ".$s->{content_id};
		    $s->{pindex} = "section ".$s->{parent};
		    $this->{map}->addtopnode($s,"index","pindex");
		}
	    }
	}
	else {
	    # you cannot view a menu of an unrelated section
	    return $this->error("Section $sid: permission denied");
	}
    }
    elsif ($Page->is_page()) {
	# show menu for current section
	my $s = new ExSite::Section(id=>$sid);
	$this->{map} = $s->get_mapped_pages(0,{version=>$version});

	if ($config{SimpleMenu}{show_subsections}) {
	    my @site = $share{DB}->fetch_match("content",{type=>"section",parent=>$sid});
	    foreach my $s (@site) {
		$s->{index} = "section ".$s->{content_id};
		$s->{pindex} = "section ".$s->{parent};
		$this->{map}->addtopnode($s,"index","pindex");
	    }
	}
    }
    else {
	# probably a template; make a fake map

	##### FIXME: nest 2,3,4 under 1 to match cnode structures

	$this->{map} = new ExSite::Tree("content_id","parent",
	      ({content_id=>1,parent=>$sid,label=>"Home",access=>0,url=>"#"},
	       {content_id=>2,parent=>$sid,label=>"About",access=>0,url=>"#"},
	       {content_id=>3,parent=>$sid,label=>"Contact",access=>0,url=>"#"},
	       {content_id=>4,parent=>$sid,label=>"Links",access=>0,url=>"#"},
	       ));
    }

    # generate a menu

    $this->{menu_mode} = $this->menu_mode();
    if ($opt =~ /horizontal/) { return $this->hmenu($opt); }
    elsif ($opt =~ /path/) { return $this->pmenu($opt); }
    elsif ($opt =~ /sitemap/) { return $this->sitemap($opt); }
    elsif ($opt =~ /next/) { return $this->nextpage($opt); }
    else { return $this->vmenu($opt); }
}

sub ioctl {
    my $this = shift;
    $_ = shift;
    if (/ModuleName/) {
	return "Menus";
    }
    elsif (/ModuleInfo/) {
	return "SimpleMenu is a multi-purpose menu-building system.
It automatically assembles site menus and site maps by inspecting the
relationships between your webpages.  It can build vertically-formatted
menus with exploded sub-menus, horizontally-formatted menus, and
path menus (also known as \"cookie-crumb\" menus) that show you where
you are in the site.  It has options for customizing the formatting and
layout of menus so that they can be incorporated into most graphic designs.
SimpleMenu does not do dynamic pop-up menus, or menus with graphical
buttons.  These options will require specialized menu plug-ins.";
    }
    elsif (/DynContentParameter/) {
	return "<p><b>Menu Type:</b>
<select name=\"param\">
<option value=\"\">(default)</option>
<option value=\"vertical\">Vertical (top-level pages)</option>
<option value=\"vertical,submenu\">Vertical (submenu or main menu pages)</option>
<option value=\"vertical,submenu-only\">Vertical (only submenu pages)</option>
<option value=\"vertical,all\">Vertical (all submenus shown)</option>
<option value=\"horizontal\">Horizontal (top-level pages)</option>
<option value=\"horizontal,submenu\">Horizontal (submenu or main menu pages)</option>
<option value=\"horizontal,submenu-only\">Horizontal (only submenu pages)</option>
<option value=\"path\">Path to current page</option>
<option value=\"next\">Link to next page</option>
<option value=\"sitemap\">Site Map</option>
</select></p>\n";
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

# hmenu - return a horizontal menu (global or child pages)

sub hmenu {
    my $this = shift;
    my $opt = shift;

    my $db = $share{DB};
    my $Page = $share{Page};
    my $this_page = $Page->id;
    my $version = $Page->getdata("version");
    my $wraptag = $config{SimpleMenu}{wrap} || "span";

    my ($menutop, $menumid, $menubot);
    $menutop = $Page->find("SimpleMenuTopH")->get_html() ||
	"<!-- begin menu -->\n<$wraptag class=\"hmenu\">\n";
    $menumid = $Page->find("SimpleMenuMidH")->get_html() ||
	$config{SimpleMenu}{hmenu_spacer};
    $menubot = $Page->find("SimpleMenuBotH")->get_html() ||
	"</$wraptag>\n<!-- end menu -->\n";

    # fetch all menu-able pages from this section
    my $pages = $opt =~ /submenu/ ? $this->get_menu(id=>$this_page) : $this->get_menu(top=>1);
    my $access = $db->authorize;
    my @menu;
    while (my $p = $pages->next) {
	next if (! $p->is_viewable);
	next if ($p->getdata("hide") =~ /menu/);
	next if ($config{SimpleMenu}{no_default_version} &&
		 $version ne $p->getdata("version"));
	my $url = $p->getdata("url") || $this->get_url($p);
	my $id;
	if ($Page->id() == $p->id) {
	    $id = " id=\"thispage\"";
	}
	elsif ($Page->getdata("parent") == $p->id) {
	    $id = " id=\"toppage\"";
	}
	my $label = $p->label();
	if ($config{SimpleMenu}{nobreak}) {
	    $label =~ s/\s+/&nbsp;/g;
	}
	push @menu, $ml->a($label,{href=>$url, class=>"menu"});
    }

    # optional links for members only
    if (! $config{SimpleMenu}{nologout}   # include logout links
	&& $access                        # if user is logged in
	&& $opt !~ /child|submenu|parent/ # on the main menu only
	&& ! $Page->is_publishing) {         # if this is a dynamic page view
#	&& ! $Page->is_template) {        # of a real page
	push @menu, $ml->a($msg{Logout},{href=>"$config{server}{CGIpath}/$config{prog}{logout}", class=>"menu"});
    }

    return $menutop.join($menumid, @menu).$menubot;
}

# pmenu - return a path menu
#
# Note that for pmenu we do not put the content into the menu class,
# because most commonly a pmenu is placed into the page body, not the
# menu bar.

sub pmenu {
    my $this = shift;
    my $opt = shift;
    my $Page = $share{Page};
    my $out = $Page->navpath();
    if ($config{SimpleMenu}{nobreak}) {
	$out =~ s/\s+/&nbsp;/g;
    }
    my $wraptag = $config{SimpleMenu}{wrap} || "div";
    return 
	$ml->Comment("begin menu").
	$ml->$wraptag($out,{class=>"pmenu"}).
	$ml->Comment("end menu");
}

sub vmenu {
    my $this = shift;
    my $opt = shift;

    my $CGIpath = $config{server}{CGIpath};
    my $HTMLpath = $config{server}{HTMLpath};
    my $db = $share{DB};
    my $Page = $share{Page};
    my $this_page = $Page->id;
    my $pdata = $Page->get;
    my $wraptag = $config{SimpleMenu}{wrap} || "div";
    my $version = $Page->getdata("version");
    my $out;

    # get menu template HTML
    my ($menutop, $menumid, $menubot);
    $menutop = $Page->find("SimpleMenuTop")->get_html();
    if ($menutop) {
	$menumid = $Page->find("SimpleMenuMid")->get_html();
	$menubot = $Page->find("SimpleMenuBot")->get_html();
    }
    else {
	$menutop = "<!-- begin menu -->\n<$wraptag class=\"vmenu\">\n";
	$menumid = $config{SimpleMenu}{vmenu_spacer};
	$menubot = "</$wraptag>\n<!-- end menu -->\n";
    }

    my @item;

    my $access = $db->level;
    my $parent = $Page->parent;
    my $ppid = $parent->id();

    my $separate_submenu;

    # get starting pages of the menu
    #my @map = $this->get_top_pages($opt);
    my $map = $opt =~ /submenu/ ? $this->get_menu(id=>$this_page) : $this->get_menu(top=>1);
    while (my $p = $map->next) {
	next if (! $p->is_viewable);

	# skip hidden pages
	next if ($p->getdata("hide") =~ /menu/);
	# skip pages if they are not the same version
	next if ($config{SimpleMenu}{no_default_version} &&
		 $version ne $p->getdata("version"));

	my $submenu;
	my %aopt = ( 
	    href=>$this->get_url($p),
	    class=>"menu" 
	    );
	if ($p->subtype ne "section") {
	    if ($p->id == $this_page || $Page->is_descendant_of($p)) {
		$aopt{id} = "toppage";
		$submenu = $this->make_submenu($p,show_parent=>0);
	    }
	}
	if ($p->id == $this_page) {
	    $aopt{id} = "thispage";
	}
	push @item, $ml->a($this->menu_label($p),\%aopt).$submenu;
    }

    # optional links for members only
    if ($opt !~ /submenu-only|child|parent/) {   # only show on main menus
	if ($db && $Page) {
	    if (! $Page->{publish}) {
		my $level = $db->authorize;
		if ($level) {
		    push @item, $ml->a($msg{Logout},{href=>"$CGIpath/$config{prog}{logout}",class=>"menu"});
		}
	    }
	}
    }

    if (@item > 0) { 
	return $ml->div(
	    $menutop . join($menumid,@item) . $menubot,
	    { class=>"menu" } 
	    );
    }
    return undef;
}

sub nextpage {
    my $this = shift;
    my $Page = $share{Page};
    my $next_page = $this->{map}->get_next_data($Page->id);
    if ($next_page) {
	my $url = $this->get_url($next_page);
	return "<div class=\"nextPage\"><a class=\"menu\" href=\"$url\">$next_page->{label}</a></div>\n";
    }
    return undef;
}

sub menu_mode {
    my $this = shift;
    # always do static menus when publishing
    return 1 if ($share{Page}->is_publishing());
    # otherwise, use static menus only when not in CMS mode
    return 0;
    #return &get_cookie("ExSiteCMS") ? 0 : 1;
}

sub get_url {
    my ($this,$p) = @_;

    if ((ref $p) eq "HASH") {
	if (exists $p->{index}) {
	    # subsection hash
	    my $s = new ExSite::Section(id=>$p->{content_id});
	    return $s->get_url();
	}
	elsif ($p->{url}) {
	    # dummy page hash
	    return $p->{url}
	}
	else {
	    # page hash
	    my $content = new ExSite::Content(id=>$p->{content_id});
	    my $page = $content->get_content_obj();
	    if ($this->{menu_mode}) {
		# link to public view
		return $page->permalink();
	    }
	    else {
		# link to preview if page is not yet published
		return $page->get_url();
	    }
	}
    }
    elsif (ref $p) {
	# $p is an object
	if ($p->is_page()) {
	    if ($this->{menu_mode}) {
		# link to public view
		return $p->permalink();
	    }
	    else {
		# link to preview if page is not yet published
		# ex.cgi/page/... links here
		return $p->get_url();
	    }
	}
    }
}

sub sitemap {
    my $this = shift;
    my $out;
    my $pages = $this->get_menu(top=>1);
    my $wraptag = $config{SimpleMenu}{wrap} || "div";

    # section link
    my $toppage = $pages->first;
    if (! $toppage->hide_from("sitemap") && $toppage->is_active) {
	my $url = $toppage->link();
	my $label = $toppage->label;
	$out .= $ml->li($ml->a($label,{href=>$url}));
    }

    # remaining pages
    while (my $p = $pages->next) {
	$out .= $this->sitemap_r($p);
    }
    return $ml->$wraptag($ml->ul($out,{class=>"sitemap"}),{class=>"sitemap"});
}

sub sitemap_r {
    # recursive mapping routine
    my ($this,$page) = @_;
    my $p = (ref $page) eq "HASH" ? $share{Page}->get_content_obj($page) : $page;
    return undef if ($p->hide_from("sitemap"));
    return undef if (! $p->is_active);

    my $db = $share{DB};
    my $out;

    # NB: will also work if $page is actually a subsection
    my $pid = $p->id;
    my $url = $this->get_url($p);
    my $label = $p->label;
    my $access = $p->getdata("access");
    my $link = $ml->a($label,{href=>$url});
    if ($access) {
	my $message = exists $config{SimpleMenu}{restricted_message} ?
	    $config{SimpleMenu}{restricted_message} :
	    "restricted access";
	if (length $message > 0) {
	    $link .= " (".$msg{$message}.")";
	}
    }
    $out .= $ml->li($link);
    return $out if ($access && $db->level() < $access);

    my @submap = $this->{map}->get_child_data($pid);
    my $submenu;
    foreach my $page (@submap) {
	$submenu .= $this->sitemap_r($page);
    }
    if ($submenu) {
	$out .= $ml->ul($submenu,{class=>"sitemap"});
    }
    return $out;
}

# get_menu : return list of pages to include in a menu
# NOTE: returns all pages, not just the visible ones
# options:
# id - starting node (defaults to current page id, but you can choose another)
# show_parent - whether to include the parent node as 1st menu link
# top - if true, show top menu for this section; otherwise submenu of page

sub get_menu {
    my ($this,%opt) = @_;
    my $id = $opt{id};
    if (! $id) {
	my $Page = $share{Page};
	if ($Page) {
	    if ($opt{top}) {
		$id = $Page->my_section()->id;
		$opt{show_parent} = 1;
	    }
	    else {
		$id = $Page->id;
	    }
	}
    }
    my $show_parent = defined $opt{show_parent} ? $opt{show_parent} : $config{SimpleMenu}{show_parent};
    my $loc = $share{Page}->get_content_obj($id);
    return $show_parent ? $loc->my_menu_items() : $loc->my_submenu_items();
}

# old version returns datahashes instead of objects
sub get_menu_old {
    my ($this,%opt) = @_;
    my $id = $opt{id};
    if (! $id) {
	my $Page = $share{Page};
	if ($Page) {
	    $id = $opt{top} ? $Page->my_section->id : $Page->id;
	}
    }
    my @page;
    my $show_parent = defined $opt{show_parent} ? $opt{show_parent} : $config{SimpleMenu}{show_parent};
    if ($show_parent) {
	push @page, $this->{map}->getnode_data($id);
    }
    push @page, $this->{map}->get_child($id);
    return @page;
}

sub make_submenu {
    my ($this,$page,%opt) = @_;
    my @item;
    $opt{id} = $page->id;
    my $menu = $this->get_menu(%opt); # objlist
    my $p = $share{Page};
    my $this_page = $p->id;
#    foreach my $item (@menu) {
    while (my $item = $menu->next) {
	next if ($item->getdata("hide") =~ /menu/);
	my %aopt = ( 
	    href=>$this->get_url($item),
	    class=>"submenu" 
	    );
	my $submenu;
	if ($p->is_descendant_of($item->id)) {
	    $submenu = $this->make_submenu($item,%opt);
	}
	if ($item->id == $this_page) {
	    $aopt{id} = "thispage";
	}
	push @item, $ml->a($this->menu_label($item),\%aopt).$submenu;
    }
    if (@item > 0) {
	return $ml->div(
	    $config{SimpleMenu}{submenu_prefix}.
	    join($config{SimpleMenu}{submenu_prefix},@item),
	    { class=>"submenu" } );
    }
    return undef;
}

sub menu_label {
    my ($this,$page) = @_;
    my $label = $page->label;
    if ($config{SimpleMenu}{nobreak}) {
	$label =~ s/\s+/&nbsp;/g;
    }
    return $label;
}

#------------------------ admin tools --------------------------

sub ctrl_panel {
    my ($this,$opt) = @_;
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    my $section_id = $this->get_section_id();
    return $this->set_section_id if (! $section_id);
    if ($this->{is_post}) {
	return $this->save_menu($section_id);
    }
    my $url = $this->link(__plaintext=>1,_bare=>2);
    my $section = new ExSite::Section(id=>$section_id);
    my $out = &insert_js("httprequest");
    $out .= &insert_js("$config{server}{HTMLpath}/_Modules/SimpleMenu/jquery.mjs.nestedSortable.js");
    $out .= $ml->script("
\$(document).ready(function(){
    \$('.sortable').nestedSortable({
        listType: 'ul',
        handle: 'div',
        items: 'li',
        placeholder: 'placeholder',
        toleranceElement: '> div'
    });
    \$('#saveMenu').click(function(){
        var serialized = \$('ul.sortable').nestedSortable('serialize');
        var post = postMenu(serialized);
        \$('#saveMenuStatus').html(post);
        window.scrollTo(0,0);
    })
});
function postMenu(postdata) {
    var url = '$url';
    var xmlObj = createRequestObj();
    xmlObj.open('POST',url,false);
    xmlObj.setRequestHeader('Content-type', 'application/x-www-form-urlencoded');
    xmlObj.send(postdata);
    if (xmlObj.status == 200) {
        result = xmlObj.responseText;
    }
    else {
	result = '<p class=error>Problem: ' + url + ' - ' + xmlObj.statusText + '</p>\\n';
    }
    return result;
}
");
    $out .= $ml->h1($section->title);
    $out .= $ml->div(
	$ui->HelpBox(title=>"Instructions",
		     pane=>"Drag pages to their correct locations in the site map, and then click \"Save\" at the bottom."),
	{id=>"saveMenuStatus"});
    my $map = $section->get_mapped_pages();
    my $pout;
    foreach my $p ($map->get_child_data($section_id)) {
	$pout .= $this->map_page($p,$map);
    }
    $out .= $ml->ul($pout,{class=>"sortable"});
    $out .= $ml->button("Save",{id=>"saveMenu"});
    return $out;
}

sub map_page { 
    my ($this,$p,$map) = @_;
    my $c = new ExSite::Content();
    my $page = $c->get_content_obj($p->{content_id});
    my $class = "type".ucfirst($page->subtype);
    my $hide = $page->getdata("hide");
    if ($hide =~ /menu|sitemap/) {
	$class .= " vis_hidden";
    }
    else {
	$class .= " vis_visible";
    }
    if ($page->getdata("access")) {
	$class .= " restricted";
    }
    my $info; # = $ml->span("&#9632;",{class=>"status".ucfirst($page->showdata("status"))});
    $info .= " ".$ml->span($page->name,{class=>$class});
    if ($page->subtype ne "page") {
	$info .= " (".$page->subtype.")";
    }
    if ($hide) {
	$info .= $ml->em(" hidden from $hide",{class=>"vis_hidden"});
    }
    my $status = $page->showdata("status");
    $info .= $ml->span($status,{class=>"status status".ucfirst($page->showdata("status"))});

    my $out = $ml->div($info);
    my $subout;
    foreach my $child ($map->get_child_data($p->{content_id})) {
	$subout .= $this->map_page($child,$map);
    }
    if ($subout) { $out .= $ml->ul($subout); }
    return $ml->li($out,{id=>"page_".$page->id});
}

#%%%%%% does not fix sortkey

sub save_menu {
    my ($this,$section_id) = @_;
    my $s = new ExSite::Section(id=>$section_id);
    my $map = $s->get_mapped_pages();
    my %post = %{$this->{post}};
    my $c = new ExSite::Content();
    my $out;

    # 1) get the page order

    my (%nchild,%orignchild,%sortkey,%origsortkey,%update);

    # get the new page order
    foreach my $key (@{$this->{keys}}) {
	$key =~ /^page\[(\d+)\]$/;
	my $page_id = $1;
	if ($page_id) {
	    my $val = $this->{post}{$key};
	    my $parent_id = ($val =~ /^\d+$/) ? $val : $section_id;
	    $nchild{$parent_id}++;
	    $sortkey{$page_id} = $nchild{$parent_id};
	}
    }

    # get the original page order
    my @page = $map->get_child_data($section_id);
    while (my $page = shift @page) {
	$orignchild{$page->{parent}}++;
	$origsortkey{$page->{content_id}} = $orignchild{$page->{parent}};
	push @page, $map->get_child_data($page->{content_id});
    }

    # find changes, flag affected pages for updates
    while (my ($key,$val) = each %post) {
	$key =~ /^page\[(\d+)\]$/;
	my $page_id = $1;
	if ($page_id) {
	    my $parent_id = ($val =~ /^\d+$/) ? $val : $section_id;
	    my $pdata = $map->getnode_data($page_id);
	    next if ($pdata->{parent} == $parent_id &&
		     $sortkey{$page_id} == $origsortkey{$page_id});
	    # might have to update everything under this parent
	    if (! exists $update{$parent_id}) { $update{$parent_id} = []; }
	    push @{$update{$parent_id}}, $page_id;
	}
    }

    # do the updates

    foreach my $parent_id (keys %update) {
	my $parent = $map->getnode_data($parent_id);
	foreach my $page_id (@{$update{$parent_id}}) {
	    my $pdata = $map->getnode_data($page_id);
	    $pdata->{parent} = $parent_id;
	    $pdata->{sortkey} = sprintf("%04d",$sortkey{$page_id});
	    $share{DB}->update("content",$pdata);
	}
	my $pname = $parent->{name} || "[top]";
	$out .= "pages under $pname reorganized".$ml->br;
    }

    return $out ? 
	$ui->SuccessBox(title=>"Sitemap Changed",pane=>$out) :
	$ui->ErrorBox(title=>"Sitemap Not Changed",pane=>"No pages changed position.");
}

1;
