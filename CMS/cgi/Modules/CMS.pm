package Modules::CMS;

#----------------------------------------------------------------------------
#
#   Copyright (C) 2011 - Exware Solutions, Inc.  http://www.exware.com
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
#  Utility for managing the content tree
#
#----------------------------------------------------------------------------

use strict;

# useful kernel libs; you can/should remove any of these that are not needed

use ExSite::Config;
use ExSite::Input;
use ExSite::Misc;
use ExSite::Util;
use ExSite::ML;
use ExSite::FormBuilder;
use ExSite::ReportBuilder;
use ExSite::Form;
use ExSite::UI;
use ExSite::Tree;
use ExSite::Content;
use ExSite::Module qw(icon launcher_link);

# base class
use Modules::Content;

# declare package globals

use vars qw(@ISA $ml $ui %icon $CMS @statusclass);

%icon = (
    section=>"section.png",
    page=>"page.png",
    template=>"template.png",
    library=>"library.png",
    content=>"content.png",
    );

@statusclass = (
    "good",
    "good",
    "fair",
    "fair",
    "fair",
    "bad",
    "bad",
    "bad",
    "bad",
    "bad",
    );

# define our class inheritance

@ISA = qw(Modules::Content);

# read method (sets up input data)

sub read {
    my ($this,$options) = @_;
    my $in = new ExSite::Input;
    $this->{input} = $in->combine;
    $this->{post} = $in->post;
    $this->{query} = $in->query;
    $this->{path} = $in->path();
    if ($this->{path}) {
	# take the whole path for ourselves
	$in->path("CMS",$this->{path});
    }
}

# write method (builds output for regular web pages)

sub write {
    my ($this,$options) = @_;
    $ml = new ExSite::ML;
    my $out = $this->error("CMS: permission denied");
    return $out;
}

# ioctl method (used by ExSite to query the module for its functionality)

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
	return "Content Management";
    }
    elsif (/ModuleInfo/) {
	return "Utility for browsing the content tree";
    }
    elsif (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/Size/) {
	return "xlarge";
    }
    elsif (/Category/) {
	return "CMS";
    }
}

sub select_content_key_label {
    my ($db,$ftable,$dat,$key,@show) = @_;
    if ($ftable eq "content") {
	my $c = $CMS->{cnode}->get_content_obj($dat);
	return $c->name." (".$c->subtype().") [".$c->id."]";
    }
}

#----------------------------------------------------------------------------
# Everything after this point consists of private methods.

# ctrl_panel() generates the contents of the administrator control panel

sub ctrl_panel {
    my $this = shift;
    $ml = &get_obj("ML");
    $ui = new ExSite::UI;
    #if (! $this->{input}{_bare}) {
    if (! $this->{input}{id}) {
	return $this->browser();
    }

    my $out;
    my $cnode = $this->get_content();
    $this->{cnode} = $cnode; # for wizards
    if ($cnode->defined) {

	# PathBar
	my @path = ( { label=>"Top", url=>$this->link(id=>undef,cmd=>undef) } );
	my $cpath = $cnode->content_path;
	$cpath->reset;
	while (my $pathnode = $cpath->next) {
	    push @path, { label=>$pathnode->name, url=>$this->link(id=>$pathnode->id,method=>undef) };
	}
	$out .= $ui->PathBar(links=>\@path);
	
	# IconBar
	$out .= $this->toolbar($cnode);

	my $obj;
	my $nodeout;
	# redefine cnode using more specific subclass
	$cnode = $this->{cnode}->get_content_obj($this->{cnode}->get());
	$cnode->load_revision("newest");
	$_ = $this->{input}{cmd};
	my $fout; # function output
	if (/^update/) {
	    $fout .= $this->update_wizard($cnode);
	}
	elsif (/^conf/) {
	    # CMS configure allows reconfiguration of any fields
	    $fout .= $this->configure($cnode,show=>["title","label","name","publish","access","hide","language","status", "type", "url", "parent", "template", "master", "sortkey", "content_role", "mtime", "ptime"],hide=>[]);
	}
	elsif (/^rev/) {
	    $fout .= $this->revisions($cnode);
	}
	elsif (/^key/) {
	    $fout .= $this->keys($cnode);
	}
	elsif (/^new/) {
	    $fout .= $this->new_content($cnode);
	}
	elsif (/^rollback/) {
	    if ($cnode->revision->delete) {
		$ml->redirect($this->link(__plaintext=>1,cmd=>undef));
	    }
	    else {
		$fout .= $ml->p("Deletion failed:");
		$fout .= &show_diagnostics();
	    }

	}
	elsif (/^del/) {
	    $fout .= $this->delete($cnode);
	}
	elsif (/^info/) {
	    $fout .= $this->content_info($cnode);
	}
	elsif (/^meta/) {
	    $fout .= $this->metadata($cnode);
	}
	elsif (/^copy/) {
	    $fout .= $this->copy($cnode);
	}
	elsif (/^search/) {
	    $fout .= $this->search($cnode);
	}
	elsif (/^schedule/) {
	    $fout .= $this->schedule($cnode);
	}
	elsif (/^todo/) {
	    $fout .= $this->todo($cnode);
	}
	elsif (/^translate/) {
	    $fout .= $this->translations($cnode);
	}
	elsif (/^workflow/) {
	    $fout .= $this->workflow($cnode);
	}
	elsif (/^preview/) {
	    $fout .= $ui->BasicBox(title=>$cnode->name,pane=>$cnode->preview(view=>"all"));
	}
	elsif (/^order$/) {
	    $fout .= $this->order($cnode);
	}
	elsif (/^price/) {
	    $fout .= $this->pricing($cnode);
	}
	elsif (/^publish$/) {
	    $fout .= $this->publish($cnode);
	}
	else { #if (/^contents/) {
	    $fout .= $this->contents($cnode);
	}
	$out .= $ml->div($fout,{id=>"CMSdisplay"});
    }
    else {
	# at top
	my @path = ( { label=>"Top", url=>$this->link(id=>undef) } );
	$out .= $ui->PathBar(links=>\@path);
	$out .= $this->toolbar($cnode);
	$_ = $this->{input}{cmd};
	if (/^new/) {
	    $out .= $this->new_content($cnode);
	}
	elsif (/^search/) {
	    $out .= $this->search($cnode);
	}
    }
    return $ml->div($out,{class=>"CMS"});
}

sub browser {
    my $this = shift;
    my $content_tree = $this->show_content_tree();
    if (! $content_tree) {
	return $this->init_cms();
    }
    $ml->Doctype('<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">');
    # javascript
    $ml->Doc($this->setup_js());
    $ml->_div( #$ui->TitleBar(title=>"Content Management",icon=>"$config{server}{HTMLpath}/_Modules/CMS/icon.gif").
	       # content tree
	       $ml->div($content_tree,{id=>"CP_content"}),
	       {id=>"CP_wrapper"});
    $ml->Append($share{page_footer}); # workarea, OverlayFrame
    $ml->__body();
    $ml->Prepend(
	$ml->head(
	    $ml->title("Content Management - ExSite4").
	    $ml->meta(undef,{'http-equiv'=>"Content-Type",content=>"text/html; charset=UTF-8"}).
	    $ml->link(undef,{rel=>"shortcut icon",href=>"$config{server}{HTMLpath}/_ExSite/images/exsite.ico"}).
	    $ml->link(undef,{rel=>"stylesheet",href=>"$config{server}{HTMLpath}/_ExSite/css/ExSite.css",type=>"text/css"}).
	    $ml->script(undef,{src=>"$config{server}{HTMLpath}/_ExSite/js/misc.js",type=>"text/javascript"}).
	    $ml->script(undef,{src=>$config{jquery},type=>"text/javascript"}).
	    $ml->script(undef,{src=>$config{jqueryui},type=>"text/javascript"}).
#	    $ml->link(undef,{rel=>"stylesheet",href=>"https://ajax.googleapis.com/ajax/libs/jqueryui/1.8/themes/base/jquery-ui.css",type=>"text/css"}).
	    $ml->link(undef,{rel=>"stylesheet",href=>"$config{server}{HTMLpath}/_Modules/CMS/CMS.css",type=>"text/css"})
	)
	);
    $ml->__html();
    return $ml->Write(); # returns a complete HTML document
}

sub setup_js {
    my $this = shift;
    my $out = $ml->script('$(document).ready(function(){
  $(".cnodeCtrl").click(function(){
     $(this).toggleClass("up");
     var cont = $(this).parent().siblings(".cnodeContents");
     if ($(this).hasClass("up")) {
	 cont.show("blind", { direction: "vertical" }, 250);
     }
     else {
         cont.hide("blind", { direction: "vertical" }, 250);
     }
     //$(this).parent().siblings(".cnodeContents").toggle();
  });
  //$("#workarea").resizable({handles:"n",helper:"resize_highlight",animate:true,maxHeight:400});
});',{type=>"text/javascript"});
#    $out .= $ml->script("
#function openContent(id) {
#//    url = \"$config{server}{HTMLpath}/_Modules/CMS/loading.html\";
#//    \$(\"#viewport\").attr(\"src\",url);
#    \$(\"#workoverlay\").fadeIn(\"fast\");
#    \$(\"#workwrapper\").fadeIn(\"slow\");
#    url = \"$config{server}{CGIpath}/ex.cgi/admin/CMS?_bare=3&id=\"+id;
#//    alert(url);
#    \$(\"#viewport\").attr(\"src\",url);
#}
#function closeContent() {
#    \$(\"#workwrapper\").hide();
#    \$(\"#workoverlay\").fadeOut(\"fast\");
#}",{type=>"text/javascript"});
    return $out;
}

# link() - special handling of content IDs

sub show_content_tree {
    my $this = shift;
    my $out;
    my $tree = $this->get_content_tree;
    my $cnode = $this->get_content;
    my $cpath;
    if ($cnode->defined) {
	$cpath = $cnode->content_path;
    }
    my $treeout;
    my @topnode = $tree->get_topnodes_data();
    foreach my $top (@topnode) {
	$treeout .= $this->content_subtree($top,$tree,$cpath);
    }
    return undef if (! $treeout);
    $out .= $ml->div(
	$ml->div(
	    "Content Type/Name".
	    $ml->div(
		$ml->span("Posted",{class=>"cnodeDate"}).
		$ml->span("Contents",{class=>"cnodeCount"}).
		$ml->span("Access",{class=>"cnodeAccess"}).
		$ml->span("Role",{class=>"cnodeRole"}).
		$ml->span("Hide from",{class=>"cnodeHide"}).
		$ml->span("Language",{class=>"cnodeLang"}).
		$ml->span("Status",{class=>"cnodeStatus"})
		,{class=>"cnodeData"}),
	    {class=>"cnodeHeaders"}).
	$treeout,
	{class=>"contentTree"});
    $out .= $ui->OverlayFrame();
    return $out;
}

# init_cms: setup a starting section

sub init_cms {
    my $this = shift;
    if ($this->{input}{confirm}) {
	my $c = new ExSite::Content();
	my %cdata = (
	    type=>$c->isubtype("section"),
	    title=>$config{site}{name},
	    label=>$config{site}{name},
	    access=>0,
	    content_role=>"editorial",
	    publish=>"static",
	    status=>0,
	    ctime=>undef
	);
	$c->setup(data=>\%cdata);
	my $id = $c->insert;
	$ml->location($this->link(__plaintext=>1,confirm=>undef,id=>$id));
    }
    else {
	return $ui->ErrorBox(
	    title=>"No Content!",
	    pane=>"This system has no content. Click the button to setup a base section to get started.".$ml->p($ui->Button(label=>"setup section",url=>$this->link(confirm=>1)))
	    );
    }
    return $this->new_content();
}

sub content_subtree {
    my ($this,$node,$tree,$cpath) = @_;
    my @subnode = $tree->get_child_data($node->{content_id});
    my $subout;
    my $cont = new ExSite::Content();
    my $plugin = $cont->subtype_attr("plugin",$node->{type});
    my $id = $node->{content_id};
    my $nchild = scalar @subnode;
    my $ichild = 0;
    if ($nchild > 10 && $plugin) {
	# too many items for CMS treeview, use plugin for deep admin
	### FiXME: should we also do this if the grandparent has a plugin?
	foreach my $sub (reverse @subnode) {
	    $ichild++;
	    if ($ichild <= 10) {
		$subout .= $this->content_subtree($sub,$tree,$cpath);
	    }
	    else {
		$plugin =~ /(\w+)$/;
		my $modname = $1;
		my $clink .= $ml->a((scalar @subnode - $ichild + 1)." more items &rarr;",
				    {href=>"javascript:openOLFrame('$config{server}{CGIpath}/$config{prog}{ctrlpanel}/$modname\&id=$id')"});
#				    {href=>&launcher_link($modname,"id=$id")});
		$subout .= 
		    $ml->div(
			$ml->div(
			    $ml->span(undef,{class=>"cnodeNoContents"}).
			    $ml->span(undef,{class=>"cnodeTypeNoIcon"}).
			    $clink,
			    {class=>"cnode"}),
			{class=>"cnodeGroup"});
		last;
	    }
	}
    }
    else {
	my $icontent = $cont->isubtype("content");
	foreach my $sub (@subnode) {
	    # show simple content at top
	    next if ($sub->{type} != $icontent);
	    $subout .= $this->content_subtree($sub,$tree,$cpath);
	}
	foreach my $sub (@subnode) {
	    # show non-simple content next
	    next if ($sub->{type} == $icontent);
	    $subout .= $this->content_subtree($sub,$tree,$cpath);
	}
    }

    # open this branch of the treeview if it is in our node path
    my $open;
    if ($cpath) {
	$cpath->reset;
	while (my $cnode = $cpath->next) {
	    if ($cnode->id == $node->{content_id}) {
		$open = 1;
		last;
	    }
	}
    }

    my $ctype= ExSite::Content->new->subtype($node->{type});
    my $ctype_class = "cnodeType".ucfirst($ctype);
    my $cnode = new ExSite::Content(id=>$id);
    my $count = $tree->count(undef,$id) - 1;
    my $ctrl_class = $subout ? "cnodeCtrl" : "cnodeNoContents";
    my $access = $cnode->getdata("access") ? $cnode->getdata("access") : "-";
    my $lang = $cnode->getdata("language") ?
	$ml->span($cnode->showdata("language"),{class=>"fair"}) :
	$config{default_language};
    my $statusclass = $statusclass[$cnode->getdata("status")];
    my $status = $ml->span($cnode->showdata("status"),{class=>$statusclass}); 
#    my $clink = $ml->span($ml->a($cnode->name,{onclick=>"openContent($id)"}),{class=>"cnodeName"});
    my $clink = $ml->span($ml->a($cnode->name,{onclick=>"openOLFrame('".$this->link(_bare=>3,id=>$cnode->id)."')"}),{class=>"cnodeName"});
    my $plugin = $share{content}{isubtype}{$cnode->getdata("type")}{plugin};
    if ($plugin) {
	$plugin =~ /(\w+)$/;
	my $modname = $1;
	my $icon = &icon($modname);
	$clink .= $ml->a(
	    $ml->img(undef,{src=>$icon,height=>16,width=>16}),
	    {href=>"javascript:openOLFrame('$config{server}{CGIpath}/$config{prog}{ctrlpanel}/${modname}?id=$id')",class=>"cnodePluginIcon"}
#	    {href=>&launcher_link($modname,"id=$id"),class=>"cnodePluginIcon"}
	    );
    }
    my $out = $ml->div(
	$ml->span(undef,{class=>$ctrl_class,id=>"cnodeCtrl$id"}).
	$ml->span(undef,{class=>"cnodeTypeIcon $ctype_class"}).
	$ml->span("$ctype $id",{class=>"cnodeType"}).
	$clink.
	$ml->div(
	    $ml->span($cnode->posting_date(),{class=>"cnodeDate"}).
	    $ml->span($count ? $count : "",{class=>"cnodeCount"}).
	    $ml->span($access,{class=>"cnodeAccess"}).
	    $ml->span($cnode->showdata("content_role"),{class=>"cnodeRole"}).
	    $ml->span($cnode->showdata("hide"),{class=>"cnodeHide"}).
	    $ml->span($lang,{class=>"cnodeLang"}).
	    $ml->span($status,{class=>"cnodeStatus"})
	    ,{class=>"cnodeData"}),
	{class=>"cnode"});
    if ($subout) {
	my $class = "cnodeContents";
	$class .= " open" if $open;
	$out .= $ml->div($subout,{class=>$class});
    }
    return $ml->div($out,{class=>"cnodeGroup"});
}

# custom content tree

sub get_content_tree {
    my ($this) = @_;
    if (! $share{content}{tree}) {
	my $query;
	if (! exists $share{querylib}{"CMS content tree"}) {
	    $query = "select content_id,parent,template,master,type,name,language,access,hide,content_role,status,ctime from content order by $config{content}{tree_order}";
	    $share{DB}->set_query("CMS content tree",
				  sql=>$query,
				  nparam=>0,
				  mode=>"r",
				  keys=>"content");
	}
	my @content = $share{DB}->get_query("CMS content tree");
	$share{content}{tree} = new ExSite::Tree("content_id","parent",@content);
	$share{content}{tree}->set("name_key","name"); # for paths
    }
    return $share{content}{tree};
}

sub get_content {
    my ($this,$id) = @_;
    $id or $id = $this->{input}{id};
    if ($this->{cnode} && $this->{cnode}->id == $id) {
	return $this->{cnode};
    }
    my $path = $id ? undef : $this->{path};
    my $cnode = new ExSite::Content(id=>$id,path=>$path);
    return $cnode->get_content_obj();
}

sub toolbar {
    my ($this,$c,%opt) = @_;
#    my $path1 = "$config{server}{HTMLpath}/_ExSite/images/icons";
#    my $path2 = "$config{server}{HTMLpath}/_Modules/CMS";
    my $newurl = $c->get_allowed_types() > 0 ?
	$this->link(cmd=>"new",id=>$c->id,method=>undef) :
	$this->link(cmd=>"new",id=>$c->parent->id,method=>undef);
    my %link = (
	configure => {faicon=>"conf", url=>$this->link(cmd=>"conf",method=>undef)},
	contents => {faicon=>"archive", url=>$this->link(cmd=>"contents",method=>undef)},
	copy => {faicon=>"copy", url=>$this->link(cmd=>"copy",method=>undef) },
	delete => {faicon=>"delete", url=>$this->link(cmd=>"del",method=>undef), tone=>"bad" },
	info => {faicon=>"info", url=>$this->link(cmd=>"info",method=>undef)},
	keys => {faicon=>"key", url=>$this->link(cmd=>"keys",method=>undef)},
	metadata => {faicon=>"meta", url=>$this->link(cmd=>"meta",method=>undef)},
	"new&nbsp;content" => {faicon=>"new", url=>$newurl},
	order => {faicon=>"sort", url=>$this->link(cmd=>"order",method=>undef) },
	preview => {faicon=>"view", url=>$this->link(cmd=>"preview",method=>undef)},
	price => {faicon=>"money", url=>$this->link(cmd=>"price",method=>undef)},
	publish => {faicon=>"download", url=>$this->link(cmd=>"publish",method=>undef)},
	revisions => {faicon=>"list", url=>$this->link(cmd=>"rev",method=>undef)},
	rollback => {faicon=>"back", url=>$this->link(cmd=>"rollback",method=>undef), tone=>"bad"},
	schedule => {faicon=>"time", url=>$this->link(cmd=>"schedule",method=>undef)},
	search => {faicon=>"search", url=>$this->link(cmd=>"search",method=>undef)},
	share => {faicon=>"social", url=>"$config{server}{CGIpath}/$config{prog}{admin}/SocialMedia?id=".$c->id },
	tags => {faicon=>"tag", url=>"$config{server}{CGIpath}/$config{prog}{admin}/Tags?_bare=3&id=".$c->id },
	todo => {faicon=>"check", url=>$this->link(cmd=>"todo",method=>undef)},
	translations => {faicon=>"flag", url=>$this->link(cmd=>"translate",method=>undef)},
	unpublish => {faicon=>"upload", url=>"$config{server}{CGIpath}/$config{prog}{publish}?-id=".$this->{cnode}->id."&back=1", tone=>"bad"},
	update => {faicon=>"edit", url=>$this->link(cmd=>"update",method=>undef)},
	workflow => {faicon=>"arrows", url=>$this->link(cmd=>"workflow",method=>undef)},
	);
    my %menu = (
	view => [ "contents", "preview", "info" ],
	create => [ "new&nbsp;content", "copy" ],
	edit => [ "configure", "update", "metadata", "order", "price", "schedule", "tags", "translations" ],
        publish => [ "publish", "unpublish" ],
        revisions => [ "revisions", "rollback" ],
	workflow => [ "workflow", "todo", "keys" ],
	'more...' => [ "search", "share", "delete" ],
	);
    my %menufaicon = (view=>"view",create=>"add",edit=>"edit",publish=>"download",revisions=>"list",workflow=>"arrows");
    my @menuorder = ( "view","edit","revisions","workflow","create","publish","more..." );

    my @tool;
    if (! $c || ! $c->defined) {
	# abbreviated toolbar
	return $ui->ToolBar(links=>[$link{search}]);
    }
    foreach my $menu (@menuorder) {
	my @links;
	if (ref $menu{$menu}) {
	    foreach my $menuitem (@{$menu{$menu}}) {
		$link{$menuitem}{label} = $menuitem;
		push @links, $link{$menuitem};
	    }
	    push @tool, { label=>$menu, faicon=>$menufaicon{$menu}, links=>\@links };
	}
	else {
	    $link{$menu}{label} = $menu;
	    push @tool, $link{$menu};
	}
    }
    return $ui->MenuBar(links=>\@tool);
}

sub toolbar_old {
    my ($this,$c,%opt) = @_;
    my $path1 = "$config{server}{HTMLpath}/_ExSite/images/icons";
    my $path2 = "$config{server}{HTMLpath}/_Modules/CMS";
    my $newurl = $c->get_allowed_types() > 0 ?
	$this->link(cmd=>"new",id=>$c->id,method=>undef) :
	$this->link(cmd=>"new",id=>$c->parent->id,method=>undef);
    my %link = (
	configure => {img=>"$path1/conf.png", url=>$this->link(cmd=>"conf",method=>undef)},
	contents => {img=>"$path1/folder.png", url=>$this->link(cmd=>"contents",method=>undef)},
	copy => {img=>"$path1/copy.png", url=>$this->link(cmd=>"copy",method=>undef) },
	delete => {img=>"$path1/delete.png", url=>$this->link(cmd=>"del",method=>undef)},
	info => {img=>"$path1/info.png", url=>$this->link(cmd=>"info",method=>undef)},
	keys => {img=>"$path1/key.png", url=>$this->link(cmd=>"keys",method=>undef)},
	metadata => {img=>"$path2/metadata.png", url=>$this->link(cmd=>"meta",method=>undef)},
	"new&nbsp;content" => {img=>"$path1/add.png", url=>$newurl},
	order => {img=>"$path2/order.png", url=>$this->link(cmd=>"order",method=>undef) },
	preview => {img=>"$path1/view.png", url=>$this->link(cmd=>"preview",method=>undef)},
	price => {img=>"$path1/money.png", url=>$this->link(cmd=>"price",method=>undef)},
	publish => {img=>"$path1/publish.png", url=>$this->link(cmd=>"publish",method=>undef)},
	revisions => {img=>"$path2/revision.png", url=>$this->link(cmd=>"rev",method=>undef)},
	rollback => {img=>"$path2/rollback.png", url=>$this->link(cmd=>"rollback",method=>undef)},
	schedule => {img=>"$path1/date.png", url=>$this->link(cmd=>"schedule",method=>undef)},
	search => {img=>"$path1/search.png", url=>$this->link(cmd=>"search",method=>undef)},
	tags => {img=>"$path1/tag.png", url=>"$config{server}{CGIpath}/$config{prog}{admin}/Tags?_bare=3&id=".$c->id },
	todo => {img=>"$path1/approve.png", url=>$this->link(cmd=>"todo",method=>undef)},
	translations => {img=>"$path2/translate.png", url=>$this->link(cmd=>"translate",method=>undef)},
	unpublish => {img=>"$path2/unpublish.png", url=>"$config{server}{CGIpath}/$config{prog}{publish}?-id=".$this->{cnode}->id."&back=1"},
	update => {img=>"$path1/edit.png", url=>$this->link(cmd=>"update",method=>undef)},
	workflow => {img=>"$path1/approve.png", url=>$this->link(cmd=>"workflow",method=>undef)},
	);

    my @tool;
    if (! $c || ! $c->defined) {
	# abbreviated toolbar
	@tool = qw(search);
    }
    elsif ($config{CMS}{tools}) {
	@tool = split(/,/,$config{CMS}{tools});
    }
    else {
	@tool = $opt{tools} ? @{$opt{tools}} : qw(contents preview info | update configure | copy new&nbsp;content | order workflow publish delete);
    }
    my $out = $ml->script(undef,{src=>"$config{server}{HTMLpath}/_ExSite/js/httprequest.js", type=>"text/javascript"});
    $out .= $ml->script("function CMSlink(url) {
	var loc = document.getElementById('CMSdisplay');
	loc.innerHTML = '<img src=\"$config{server}{HTMLpath}/_Modules/CMS/wait.gif\"';
	subRequestData('CMSdisplay',url);
}\n");
    my $type = $c->getdata("type");
    my @links;
    foreach my $tool (@tool) {
	if ($tool && $tool ne "|") {
	    my $opt = $link{$tool};
	    $opt->{label} = $tool;
	    push @links, $opt;
	    delete $link{$tool};
	}
	else {
	    push @links, undef;
	}
    }
    # add remaining tools into dropdown
    my $opt;
    my @menu;
    foreach my $tool (sort keys %link) {
	my $opt = $link{$tool};
	$opt->{label} = $tool;
	push @menu, $opt;
    }
    push @links, undef;
    push @links, { label=>"more", url=>\@menu };
    $out .= $ui->IconBar(links=>\@links);
    return $out;
}

sub content_info {
    my ($this,$cnode) = @_;
#    my $out = $cnode->report();
    my $out = $this->about($cnode);
    return $out;
}

sub content_metadata_old {
    my ($this,$cnode) = @_;
    my @meta = $cnode->meta->get_allowed();
    my $out = $ml->h1("Metadata for ".$cnode->name);

    my $input = new ExSite::Input;
    my $post = $input->post;
    if (scalar keys %$post > 0) {
	foreach my $meta (sort @meta) {
	    my $meta_new = $post->{$meta};
	    $cnode->meta->set_nosave($meta,$meta_new);
	}
	$cnode->meta->save;
	$out .= $ml->div("Metadata updated.",{class=>"notice"});
    }

    my %meta = $cnode->get_metadata();
    my $form = new ExSite::FormBuilder(action=>$this->link());
    my ($template1, $template2);
    foreach my $meta (sort @meta) {
	next if (exists $config{content}{metadata}{_}{$meta}); # generic
	next if ($meta =~ /[\.:]/); # 3rd-party scheme
	my $input = $cnode->meta->input($meta,$meta,$meta{$meta},$cnode->magic_meta($meta));
	my %inopt = (name=>$meta,prompt=>$cnode->meta->label($meta),input=>$input);#,value=>$meta{$meta});
	$form->input(%inopt);
	$template1 .= $ml->tr($ml->td("[[$meta:prompt]]").$ml->td("[[$meta:input]]"));
    }
    # put generic metadata after custom metadata
    foreach my $meta (sort @meta) {
	if ($meta =~ /:/ || exists $config{content}{metadata}{_}{$meta}) {
	    my $input = $cnode->meta->input($meta,$meta,$meta{$meta},$cnode->magic_meta($meta));
	    my %inopt = (name=>$meta,prompt=>$cnode->meta->label($meta),input=>$input);
	    $form->input(%inopt);
	    $template2 .= $ml->tr($ml->td("[[$meta:prompt]]").$ml->td("[[$meta:input]]"));
	}
    }
    $form->template(
	$ml->table($template1).$ml->br.
	$ui->BlindBox(title=>"Generic Metadata",
		      pane=>$ml->p($ml->img(undef,{src=>"$config{server}{HTMLpath}/_ExSite/images/icons/help.png"}).
				   " Generic metadata schemes include ".
				   $ml->a("Dublin Core",{href=>"http://en.wikipedia.org/wiki/Dublin_Core",target=>"_blank"}).", ".
				   $ml->a("OpenGraph",{href=>"http://ogp.me/",target=>"_blank"}).", and ".
				   $ml->a("Twitter Cards",{href=>"https://developer.twitter.com/en/docs/tweets/optimize-with-cards",target=>"_blank"}).".").
		      $ml->table($template2),
		      size=>"l",
		      open=>!$template1)
	);
    $out .= $form->make();
    return $out;
}

sub contents {
    my ($this,$cnode) = @_;
    my $out;

    # revisions

    if ($cnode->revision->getdata("content_id") == $cnode->id) {
	my @rev = $cnode->get_revisions();
	my $nrev = scalar @rev;
	my $revlabel = $nrev == 1 ? "1 revision" : "$nrev revisions";
	$out .= $ui->Icon(img=>"$config{server}{HTMLpath}/_Modules/CMS/revisions.png",url=>$this->link(cmd=>"rev",__ajax=>1,height=>64,width=>64),label=>$revlabel);
    }

    # sub-nodes

    my $tree = $this->get_content_tree();
    my @node = $cnode && $cnode->defined ? 
	$tree->get_child_data($cnode->id) :
	$tree->get_topnodes_data();
    my $ml = &get_obj("ML");
    my $ialias = $cnode->isubtype("alias");
    foreach my $n (@node) {
	my $label = $n->{name};
	my $content = $cnode->get_content_obj($n);
	my $icon = $this->content_icon($content);
	if ($n->{type} == $ialias) {
	    ### FIXME: link to manage the alias itself???
	    $label .= $ui->faicon("arrow-circle-right"); # alias indicator
	}
	$out .= $ui->Icon(img=>$icon,label=>$label,title=>$content->label(),url=>$this->link(id=>$content->id));

#$ml->div(
#	    $ml->a(
#		$ml->div($icon,{class=>"iconimg"}).
#		$content->name,
#		{href=>$this->link(id=>$content->id),title=>$content->label}),
#	    {class=>"icon"});
    }

    # new content

    if ($cnode->my_subdir) {
	$out .= $ui->Icon(img=>"$config{server}{HTMLpath}/_Modules/CMS/bignew.png",url=>$this->link(cmd=>"new",__ajax=>1),label=>"new content",height=>64,width=>64);
    }
    my $iconbox = $ml->div($out,{class=>"IconBox"});
    return ($cnode && $cnode->defined) ?
	$ui->BasicBox(title=>"Contents of ".$cnode->name,pane=>$iconbox) :
	$ui->BasicBox(title=>"Start",pane=>$iconbox);
}

sub content_icon {
    my ($this,$c) = @_;
    my ($icon,$attr);
    my $mime = $c->revision->mime_type();
    if ($c->my_subdir) {
	my $type = $c->subtype();
	# container object
	if (-e "$config{server}{HTMLroot}$config{server}{HTMLpath}/_Modules/CMS/${type}_64.png") {
	    $icon = "$config{server}{HTMLpath}/_Modules/CMS/${type}_64.png";
	}
	elsif ($c->getdata("language")) {
	    $icon = "$config{server}{HTMLpath}/_Modules/CMS/language.png";
	}
	else {
	    $icon = "$config{server}{HTMLpath}/_Modules/CMS/page_64.png";
	}
	$attr = { height=>64, width=>64, alt=>$type, title=>$c->label, class=>'icon' };
    }
    elsif ($mime =~ /image/ && $c->revision->has_view("thumbnail")) {
	# use image itself
	my $view = $c->revision->select_view("thumbnail");
	$icon = $view->get_url();
	$attr = { height=>64, alt=>$c->name, title=>$c->name, class=>'icon' };
    }
    else {
	# use MIME-type icon
	my ($class,$type) = split /\//,$mime;
	if (-e "$config{server}{HTMLroot}$config{server}{HTMLpath}/_Modules/CMS/mime-$type.png") {
	    $icon = "$config{server}{HTMLpath}/_Modules/CMS/mime-$type.png";
	}
	elsif (-e "$config{server}{HTMLroot}$config{server}{HTMLpath}/_Modules/CMS/mime-$class.png") {
	    $icon = "$config{server}{HTMLpath}/_Modules/CMS/mime-$class.png";
	}
	else {
	    $icon = "$config{server}{HTMLpath}/_Modules/CMS/blank.png";
	}
	$attr = { height=>64, width=>64, alt=>$mime, title=>$mime, class=>'icon' };
    }
    return $ml->img(undef,{src=>$icon,%$attr});
}

sub new_content {
    my ($this,$cnode) = @_;
    my $out;
    my $input = new ExSite::Input;
    my $post = $input->post;
    if (scalar keys %$post > 0) {
	return $this->new_content_2($cnode,$post);
    }
    else {
	my $out = $ml->h1("New Content Node");
	my $form = new ExSite::FormBuilder();
	#my @type = $share{DB}->fetch_all("content_type");
	### FIXME: use content_rel
	my $subtype = $this->{cnode}->subtype;
	my @type = $this->{cnode}->get_allowed_types();
	if (scalar @type == 0) { 
	    return $this->warn("You cannot add new content under a $subtype.");
	}
	my @typename = map { $_->{name} } @type;
	$form->input(name=>"name",prompt=>"Name",type=>"text",required=>1);
	$form->input(name=>"type",prompt=>"Type",type=>"radio",required=>1,options=>\@typename);
	$form->set("buttons",
		   $ml->p(
		       $ml->input(undef,{type=>"submit",value=>"Continue &gt;"}).
		       $ml->input(undef,{type=>"button",value=>"Cancel",class=>"cancel",onclick=>"history.back()"}).
		       $ml->input(undef,{type=>"reset",value=>"Reset"})
		   )
	    );
	$out .= $form->make();
	return $out;
    }
    return $out;
}

sub new_content_2 {
    my ($this,$cnode,$in) = @_;
    my $out;
    if (scalar keys %$in > 4) {
	return $this->new_content_3($cnode,$in);
    }
    my $spacechar = $config{spacechar} || "_";
    my $name = $in->{name};
    $name =~ s/[^\w\.-]/$spacechar/g;
    $name =~ s/$spacechar{2,}/$spacechar/g;
    $name =~ s/$spacechar$//g;
    $name =~ s/^$spacechar//g;

    # reference

    $out .= $ml->h1("New " . ucfirst $in->{type});
    my $form = new ExSite::FormBuilder();
    $form->input(name=>"type",type=>"hidden",value=>$in->{type});	
    $form->input(name=>"name",prompt=>"Name/Location",type=>"text",value=>$name);
    $form->input(name=>"title",prompt=>"Full Title",type=>"text",value=>$in->{name});	
    $form->input(name=>"label",prompt=>"Link Label",type=>"text",value=>$in->{name});	
    $form->input(name=>"publish",prompt=>"Publish Rule",type=>"select",options=>$share{DB}{map}->regexp("list:publish"),nullvalue=>"== select ==");
    $form->input(name=>"content_role",prompt=>"Content Role",type=>"select",options=>$share{DB}{map}->regexp("list:content_role"));
    my @access;
    foreach my $acc (split /\|/,$share{DB}{map}->regexp("enum:access")) {
	my ($level,$name) = split /:/, $acc;
	push @access, { value=>$level,text=>$name };
    }
    $form->input(name=>"access",prompt=>"Access",type=>"select",options=>\@access);
    my @lang;
    push @lang, split /\|/, $share{DB}{map}->regexp("list:language");
    if (@lang > 0) {
	unshift @lang, $config{default_language};
	$form->input(name=>"language",prompt=>"Language/Version",type=>"select",options=>\@lang);
    }

    my $refvalue = $cnode->getdata("template");
    #my @ref = $cnode->find_subtypes($cnode->my_reference_subtype);
    my @ref = $this->find_templates($cnode);
    my @refopt = ( { value=>0, text=>"== select template ==" } );
    foreach my $r (@ref) {
	push @refopt, { value=>$r->{content_id}, text=>$r->{name} };
    }
    $form->input(name=>"template",prompt=>"Template",type=>"select",options=>\@refopt,value=>$refvalue);

    $form->input(name=>"status",prompt=>"Status",type=>"select",value=>$cnode->wf_istatus("draft"),options=>{0=>"published",1=>"archived",2=>"queued",3=>"approved",4=>"submitted",5=>"draft",6=>"expired",7=>"canceled",8=>"rejected"});
    $form->input(name=>"sortkey",prompt=>"Sortkey",type=>"text",size=>8);
    if ($in->{type} eq "page") {
	$form->input(name=>"body",prompt=>"Create a page body",type=>"checkbox",checked=>1);
	$form->input(name=>"page",prompt=>"Copy the template",type=>"checkbox");
    }
    elsif ($in->{type} eq "section") {
	$form->input(name=>"url",prompt=>"URL/domain name",type=>"text",tail=>"(for stand-alone sections only)");
    }
    my $url = $this->link(cmd=>undef);
    $form->set("buttons",
	       $ml->p(
		   $ml->input(undef,{type=>"submit",value=>"Continue &gt;"}).
		   $ml->input(undef,{type=>"button",value=>"Cancel",class=>"cancel",onclick=>"window.location.href='$url'"}).
		   $ml->input(undef,{type=>"reset",value=>"Reset"})
	       )
	);
    $form->template("<table>",
		    $ml->tr($ml->td("[[prompt]]").$ml->td("[[input]]")),
		    "</table>");
    $out .= $form->make();
    return $out;
}

sub new_content_3 {
    my ($this,$cnode,$in) = @_;
    my $aterror = &AtError();
    my $itype = $cnode->isubtype($in->{type});

    my $c = $cnode->new_content_obj(
	type => $itype,
	name => $in->{name},
	label => $in->{label},
	title => $in->{title},
	parent => $cnode->id || "0",
	template => $in->{template},
	language => $in->{language} eq $config{default_language} ? undef : $in->{language},
	sortkey => $in->{sortkey},
	access => $in->{access},
	hide => $in->{hide},
	content_role => $in->{content_role},
	publish => $in->{publish},
	status => $in->{status},
	url => $in->{url},
	ctime => undef,
	);
    my $cid = $c->id;
    my $body_id;
    if ($cid) {
	if ($in->{body}) {
	    # add a page body
	    my $body = $c->new_content_obj(
		type => $cnode->isubtype("content"),
		name => "body",
		status => $cnode->wf_istatus("published"),
		);
	    $body_id = $body->id;
	    if (! $body_id) {
		$this->error("failed to add body to page");
	    }
	}
	if ($in->{page}) {
	    # copy template to allow layout customization
	    my $template = $cnode->template;
	    if ($template->exists) {
		my $html = $template->get_html();
		if ($html) {
		    $c->revise(data=>$html,format=>"text",mime_type=>"text/html",
			       note=>"copied template from ".$template->name);
		}
	    }
	}

	my $go_id = $body_id || $cid;

	### FIXME: if adding non-subdir content, goto contents view of parent

	if (! &AtError($aterror)) {
	    my $url = $c->subtype_attr("publish_as") eq "file" ?
		$this->link(__plaintext=>1,id=>$c->getdata("parent"),cmd=>"contents") :
		$this->link(__plaintext=>1,id=>$go_id,cmd=>"update");
	    $ml->redirect($url);
	    return $ml->p("Added $in->{type} $cid.");
	}
    }
    return $share{DB}->show_diagnostics("error","html");
}

sub find_templates {
    my ($this,$cnode) = @_;
    my $tree = $cnode->get_content_tree();
    my $path = $cnode->content_path();
    $path->reset();
    my @template;
    my $itemplate = $cnode->isubtype("template");
    # look for template nodes under each node in our path
    # other templates are not meant for our branch of the tree
    while (my $pnode = $path->next) {
	my @child = $tree->get_child_data($pnode->id);
	foreach my $c (@child) {
	    push @template, $c if ($c->{type} == $itemplate);
	}
    }
    return @template;
}

sub update_method {
    my $this = shift;
    my $mimetype = $this->{cnode}->revision->mime_type;
    if ($mimetype =~ /html/) {
	return $this->{cnode}->is_page ? "text" : "html";
    }
    elsif ($mimetype =~ /^text/) {
	return "text";
    }
    else {
	return "file";
    }
}

sub update_wizard {
    my ($this,$cnode) = @_;
    if (exists $this->{input}{data} || exists $this->{input}{'data#html'}) {
	return $this->update_wizard_2($cnode);
    }
    $cnode or $cnode = $this->{cnode};
    my $db = $share{DB};
    my ($type,$title,$init) = @_;
    my %method = (html=>0, text=>1, file=>2, url=>3, path=>4);
    my $method = $this->{input}{method} || $this->update_method();
    my $thistab = $method{$method};
    my $out = $ui->TabBox(tabs=>[
			      {label=>"HTML",url=>$this->link(method=>"html")},
			      {label=>"Text",url=>$this->link(method=>"text")},
			      {label=>"File",url=>$this->link(method=>"file")},
			      {label=>"URL",url=>$this->link(method=>"url")},
			      {label=>"Path",url=>$this->link(method=>"path")},
			  ],
			  thistab=>$thistab,
			  tabwidth=>"75px",
	);


    my $mimetype = $cnode->revision->mime_type();
    if ($cnode->is_page) {
	# should we really be editing the body?
	my $hasrev = $cnode->has_revisions();
	my $br = $ml->br;
	my $body = $cnode->my_content("body");
	if ($body) {
	    if ($hasrev) {
		$out .= $ui->ErrorBox(
		    title=>"Wrong content?",
		    pane=>"You are editing a page object, which is the wrapper (template) HTML used to format the page.$br
If you meant to edit the page content, ".$ml->a("click here",{href=>$this->link(id=>$body->id)})."."
		    );
	    }
	    elsif ($this->{input}{method} ne "text") {
		return $ui->ErrorBox(
		    title=>"Wrong content?",
		    pane=>"You are editing the page layout, but this page does not have its own layout.$br
You probably meant to edit the page body. If so, ".$ml->a("click here",{href=>$this->link(id=>$body->id)}).".$br
Otherwise, ".$ml->a("click here",{href=>$this->link(method=>"text")})." to start a special layout for this page."
		    );

	    }
	}
    }

    if ($method eq "html") {
	$out .= $ml->p("Use the HTML editor to enter your HTML content in WYSIWYG format. You can use the HTML tool in the editor toolbar to manually edit the HTML code. Use the image, link, and plugin tools to insert special CMS tags.");
	if ($mimetype && $mimetype ne "text/html") {
	    my $warning = "WARNING: \"".$cnode->name."\" is not currently HTML. If you use the HTML editor to enter new content, you will completely replace the existing content.";
	    if ($mimetype =~ /^text/) {
		$warning .= " Use the Text tab to edit the existing content.";
	    }
	    $out .= $ml->div($warning,{class=>"notice"});
	}
    }
    elsif ($method eq "text") {
	$out .= $ml->p("Enter the raw content below. If the content is in HTML format, you can include CMS tags such as:").
	    $ml->ul([
		$ml->code("[[name]]")." - the URL of the named CNode",
		$ml->code("&lt;!--content(name)--&gt;")." - content from the named CNode",
		$ml->code("&lt;!--&Plugin(parameters)--&gt;")." - content from the given plugin module"
	    ]).
	    $ml->p("Consult system documentation for explanations of these CMS tag formats and their options.");
    }
    elsif ($method eq "file") {
	$out .= $ml->p("Upload the file using the form below. Note that the revision control system may not accept very large files. Those will be converted to the \"path\" update method automatically.");
    }
    elsif ($method eq "url") {
	$out .= $ml->p("Provide a complete URL to the content below. Note that this content is outside the control of the CMS, and can change or disappear without notice.");
    }
    elsif ($method eq "path") {
	$out .= $ml->p("Provide the disk path to the content file on the webserver. A full path (starting with '/') is from the website's base directory. A relative path (starting with a character other than '/') is from the website's HTdocs directory. Note that paths containing '..' will not be accepted.");
    }

    my $form = $db->form(action=>$this->link(),method=>"post");

    if ($method eq "html") {
	#my $value = $cnode->revision->get_html();
	my $value = $cnode->has_revisions ? $cnode->expand(html=>$cnode->revision->get_html(),method=>"dummy-page,dummy-content,dummy-module") : undef;
	my $input = $db->input_exsite(datatype=>"html",name=>"data",prompt=>"HTML content",value=>$value,editor_width=>500);
    }
    elsif ($method eq "text") {
	my $rawvalue = $cnode->revision->get_raw();
	$rawvalue =~ s/</&lt;/g;
	$rawvalue =~ s/>/&gt;/g;
	$form->input(type=>"textarea",name=>"data",value=>$rawvalue,prompt=>"Raw text content",rows=>20,cols=>80);
    }
    elsif ($method eq "file") {
	$form->input(type=>"file",name=>"data",required=>1,prompt=>"Upload file");
    }
    elsif ($method eq "url") {
	$form->input(type=>"text",name=>"data",size=>80,prompt=>"URL to file");
    }
    elsif ($method eq "path") {
	$form->input(type=>"text",name=>"data",size=>80,prompt=>"Diskpath to file");
    }
    $form->input(type=>"hidden",name=>"method",value=>$method);
    $form->set("buttons",
	       $ml->p(
		   $ml->input(undef,{type=>"submit",value=>"Continue &gt;"}).
		   $ml->input(undef,{type=>"button",value=>"Cancel",class=>"cancel",onclick=>"history.back()"}).
		   $ml->input(undef,{type=>"reset",value=>"Reset"})
		   )
	);
    $out .= $form->make();
    return $out;
}

sub update_wizard_2 {
    my ($this,$cnode) = @_;
    $cnode or $cnode = $this->{cnode};
    my $input = new ExSite::Input;
    my $in = $input->post;
    if ($in->{'data#html'}) {
	$in->{data} = $in->{'data#html'};
	delete $in->{'data#html'};
    }
    if ($in->{mimetype}) {
	return $this->do_update($in);
    }
    my $out;
    my $db = $share{DB};
    my $method = $in->{method};
    if (! $method) {
	return $this->error("No input method specified.");
    }
    my $oldvalue = $cnode->revision->get_html();
    my ($mimetype,$fdata,$fname,$fsize);

    my $form = new ExSite::FormBuilder(action=>$this->link(),method=>"post");
    $form->input(type=>"hidden",name=>"method",value=>$method);
    my %data = (type=>"hidden",name=>"data");
    if ($method eq "html") {
	$mimetype = "text/html";
	$data{value} = $in->{data};
#	$data{value} =~ s/</&lt;/g;
#	$data{value} =~ s/>/&gt;/g;
    }
    elsif ($method eq "text") {
	# could be html, plain text, or css
	if ($in->{data} =~ /<(!--|[\/a-zA-Z])/) {
	    $mimetype = "text/html";
	}
	elsif ($in->{data} =~ /\/\*|     # comment
	       [\w-]+\s*:\s*[\w\#]+\;|   # attribute setting
	       ^\w*\#\w+\s*\{|           # tag.id 
	       ^\w*\.\w+\s*\{/x) {       # tag.class
	    $mimetype = "text/css";
	}
	else {
	    $mimetype = "text/plain";
	}
	$data{value} = $in->{data};
#	$data{value} =~ s/</&lt;/g;
#	$data{value} =~ s/>/&gt;/g;
    }
    else {
	if ($method eq "file") {
	    $fdata = $input->fetch_file("data");
	    $data{value} = $fdata;
	    ($fname,undef) = split(/\#/, $data{value});
	}
	else {
	    $fname = $in->{"url"} || $in->{"path"};
	    $data{value} = $in->{data};
	    $fname =~ s/.*\///; # file name is everything after the last /
	}
	# guess based on file name
	$mimetype = &MimeType($fname);
    }
    $form->input(%data);

    # 1) mime-type

    my $mimetype;
    if ($method eq "html") {
	$mimetype = "text/html";
    }
    elsif ($method eq "text") {
	# could be html, plain text, or css
	if ($in->{"data"} =~ /<(!--|[\/a-zA-Z])/) {
	    $mimetype = "text/html";
	}
	elsif ($in->{"data"} =~ /\/\*|     # comment
	       [\w-]+\s*:\s*[\w\#]+\;|     # attribute setting
	       ^\w*\#\w+\s*\{|             # tag.id 
	       ^\w*\.\w+\s*\{/x) {         # tag.class
	    $mimetype = "text/css";
	}
	else {
	    $mimetype = "text/plain";
	}
    }
    else {
	my $file;
	if ($method eq "file") {
	    ($file,undef) = split(/\#/, $fdata);
	}
	else {
	    $file = $in->{"url"} || $in->{"path"};
	}
	# guess based on file name
	$mimetype = &MimeType($file);
    }

    # above mimetype is just our best guess.  Show options, so that it
    # can be over-ridden.
    
    my $br = $ml->br;
    $form->input(
	type=>"select",
	name=>"mimetype",
	value=>$mimetype,
	options=>$db->{map}->regexp("list:mime"),
	prompt=>"ExSite thinks this content is of type",
	tail=>$br.$ml->small("(If ExSite has guessed incorrectly, you can set the content type manually.)")
	);

    # 2) attributes

    if ($mimetype =~ /^image/) {
	my $img = new ExSite::Image($fdata);
	my $info = $img->info;
	my $size = $info->{width} > $info->{height} ? $info->{width} : $info->{height};

	# views
	my $viewout;
	if ($size > $config{cnode}{viewdim}{normal} * 1.2) {
	    $viewout .= $ml->input(undef,{name=>"view_large",type=>"checkbox"})."large$br";
	}
	else {
	    $viewout .=  $ml->span($ml->input(undef,{name=>"view_large",disabled=>1,type=>"checkbox"})."large",{class=>"disabled"}).$br;
	}
	$viewout .= $ml->input(undef,{name=>"view_normal",checked=>1,type=>"checkbox"})."normal";
	if ($size > $config{cnode}{viewdim}{normal}) {
	    # uploaded image is larger than normal size; we can either scale it
	    # to normal size, or accept the original image as the normal size
	    $viewout .= "&nbsp;&nbsp";
	    $viewout .= $ml->input(undef,{name=>"view_normal_scale",checked=>1,type=>"radio",value=>"y"})."scale to default normal size ";
	    $viewout .= $ml->input(undef,{name=>"view_normal_scale",type=>"radio",value=>"n"})."already scaled to correct size$br";
	}
	else {
	    $viewout .= $br;
	}
	if ($size > $config{cnode}{viewdim}{small}) {
	    $viewout .= $ml->input(undef,{name=>"view_small",type=>"checkbox"})."small$br";
	}
	else {
	    $viewout .=  $ml->span($ml->input(undef,{name=>"view_small",disabled=>1,type=>"checkbox"})."small",{class=>"disabled"}).$br;
	}
	if ($size > $config{cnode}{viewdim}{thumb}) {
	    $viewout .= $ml->input(undef,{name=>"view_thumb",type=>"checkbox"})."thumbnail$br";
	}
	else {
	    $viewout .=  $ml->span($ml->input(undef,{name=>"view_thumb",disabled=>1,type=>"checkbox"})."thumbnail",{class=>"disabled"}).$br;
	}
	if ($size > $config{cnode}{viewdim}{icon}) {
	    $viewout .= $ml->input(undef,{name=>"view_icon",type=>"checkbox"})."icon$br";
	}
	else {
	    $viewout .=  $ml->span($ml->input(undef,{name=>"view_icon",disabled=>1,type=>"checkbox"})."icon",{class=>"disabled"}).$br;
	}
	$form->input(name=>"views",type=>"checkbox",input=>$viewout,prompt=>"Automatically scale to the following sizes:");

	# attributes
	#$out .= &ShowHash($info);
	my $alt = $fname;
	$alt =~ s/\.\w+$//;
	my $attributes = "alt=\"$alt\" ";
	if (exists $info->{width}) {
	    $attributes .= "width=\"$info->{width}\" height=\"$info->{height}\" border=\"0\"";
	    my $type = uc $mimetype;
	    $type =~ s/IMAGE\///;
	    $out .= $ml->div("Not quite done! You uploaded a $info->{width}&times;$info->{height} $type image.",{class=>"notice"});
	}
	
	$form->input(name=>"attributes",type=>"text",value=>$attributes, size=>60, prompt=>"Specify any image attributes you would like applied to this image:");
	
    }
    else {
	$form->input(type=>"hidden",name=>"view_normal",value=>"on");
	if ($mimetype =~ /^application\/x-shockwave-flash$/) {
	    $form->input(name=>"attributes",type=>"text", size=>60, prompt=>"Specify any attributes you would like applied to this Flash movie (eg. height, width).");
	}
    }

    # 3) revision control comment

    $form->input(name=>"comment",type=>"textarea",size=>100,placeholder=>"revision control comment",prompt=>"For the purposes of auditing, please include a note describing the changes you made:");

    $form->set("buttons",
	       $ml->p(
		   $ml->input(undef,{type=>"submit",value=>"Done"}).
		   $ml->input(undef,{type=>"button",value=>"&lt; Back",onclick=>"history.back()"}).
		   $ml->input(undef,{type=>"reset",value=>"Reset"})
		   )
	);
    $out .= $form->make();

    return $out;

}

sub do_update {
    my ($this,$in) = @_;
    my $out;
    my $db = $share{DB};

    # sanity checks
    my @err;
    if (! $in->{method}) {
	push @err, "no update method specified";
    }
    if (! $in->{data}) {
	push @err, "no content provided";
    }
    if (! $in->{mimetype}) {
	push @err, "you need to specify a mime-type";
    }
#    if (! $in->{comment}) {
#	push @err, "you need to provide a revision control comment";
#    }
    if ($in->{mimetype} =~ /image/ && ! $in->{view_large} && ! $in->{view_normal} && ! $in->{view_small} && ! $in->{view_thumb} && ! $in->{view_icon} ) {
	push @err, "you must select at least one image size";
    }
    if (@err > 0) {
	$out .= $this->error(@err);
	$out .= $ml->p($ml->a("&lt; Back",{href=>"javascript:history.back()"}));
	return $out;
    }

    # do the update

    my %view;
    if ($in->{view_large}) {
	$view{large} = 1;
    }
    if ($in->{view_normal}) {
	if (exists $in->{view_normal_scale}) {
	    if ($in->{view_normal_scale} eq "y") {
		$view{normal} = 1;
	    }
	    else {
		$view{normal} = {
		    type=>"normal",
		    mime_type=>$in->{mimetype},
		    'format'=>$in->{method},
		    data=>$in->{data},
		    attributes=>$in->{attributes},
		};
	    }
	}
	else {
	    $view{normal} = 1;
	}
    }
    if ($in->{view_small}) {
	$view{small} = 1;
    }
    if ($in->{view_thumb}) {
	$view{thumbnail} = 1;
    }
    if ($in->{view_icon}) {
	$view{icon} = 1;
    }
    
    my %attributes = &DecodeAttributes($in->{attributes});
    my $data = &restore_cms_tags($in->{data});

    my $format = $in->{method} eq "html" ? "text" : $in->{method};
    my $revid = $this->{cnode}->revise(data => $data,
				       'format' => $format,
				       mime_type => $in->{mimetype},
				       note => $in->{comment},
				       attributes=> \%attributes,
				       view=> \%view);
    my $redir = 1;
    if ($this->{cnode}->errorcheck()) {
	$out .= $this->{cnode}->show_diagnostics("error","html");
	$redir = 0;
    }
    if ($revid) {
	$out .= $ml->p("Installed revision $revid.");
	$ml->redirect($this->link(__plaintext=>1,cmd=>"info",method=>undef)) if $redir;
    }
    return $out;
}

sub revisions {
    my ($this,$cnode) = @_;    
    my $out;
    my $cmd = $this->{input}{cmd};
    if ($cmd eq "rev_del") {
	$out .= $this->revision_delete($cnode);
    }
    elsif ($cmd eq "rev_changes") {
	$out .= $this->revision_changes($cnode);
    }
    elsif ($cmd eq "rev_restore") {
	$out .= $this->revision_restore($cnode);
    }

    my %rev;
    my @rev = $cnode->get_revisions();
    my $revreport = new ExSite::ReportBuilder(title=>"Revisions of ".$cnode->name);
    $revreport->nodata("This content contains no revisions yet.");
    $revreport->headers("Revision","Type","Views","Updated by","Date","Published","Note","");
    foreach my $rev (reverse @rev) {
	next if ($rev->{content_id} != $cnode->id);
	my @rdata;
	my $r = new ExSite::Revision(data=>$rev,content=>$cnode);
	my $id = $r->id;
	push @rdata,$id;
	push @rdata,$r->showdata("mime_type");
	push @rdata,join(", ",$r->has_views());
	push @rdata,$r->showdata("uid");
	push @rdata,$r->getdata("ctime");
	if ($r->wf_status eq "draft") {
	    push @rdata, "draft";
	}
	else {
	    push @rdata, $r->getdata("ptime") =~ /^0/ ? "" : $ui->FAIcon("check");
	}
	push @rdata,$r->showdata("note");

	# tools
	my @tool;
	# preview
	push @tool, $ui->FATool("view",label=>"preview",url=>$r->get_url_dynamic(),target=>"_blank");
	# copy (not on last rev)
	push @tool, $ui->ToolIcon(img=>"$config{server}{HTMLpath}/_Modules/CMS/changes.png",url=>$this->link(cmd=>"rev_changes",rev=>$id),label=>"changes") if ($rev->{revision_id} != $rev[0]{revision_id});
	# diff (not on first rev)
	push @tool, $ui->FATool("up",url=>$this->link(cmd=>"rev_restore",rev=>$id),label=>"restore") if ($rev->{revision_id} != $rev[-1]{revision_id});
	# delete
	push @tool, $ui->FATool("delete",url=>$this->link(cmd=>"rev_del",rev=>$id),confirm=>"Really delete revision $id?",tone=>"bad");
	push @rdata,join("",@tool);
	$revreport->push(@rdata);
    }
    $out .= $revreport->make();
    return $out;
}

sub revision_delete {
    my ($this,$cnode) = @_;
    my $out;
    if ($cnode->allow("delete")) {
	my $revid = $this->{input}{rev};
	my $rev = new ExSite::Revision(id=>$revid);
	if ($rev->delete()) {
	    $ml->location($this->link(__plaintext=>1,rev=>undef,cmd=>"rev"));
	    return;
	}
	else {
	    $out .= &ExSite::Config::show_diagnostics();
	}
    }
    else {
	$out .= $this->error("Sorry, your keys do not allow you to delete revisions.");
    }
    return $out;
}

sub revision_restore {
    my ($this,$cnode) = @_;
    my $out;
    my $rev = new ExSite::Revision(id=>$this->{input}{rev});
    $rev->restore() or $out .= &ExSite::Config::show_diagnostics();
    return $out;
}

sub revision_changes {
    my ($this,$cnode) = @_;
    require String::Diff or return $this->error("View Changes not supported - please install String::Diff to get this feature.");

    my ($revnew,$revold);
    my @rev = $cnode->get_revisions();
    while (my $rev = pop @rev) {
	if ($rev->{revision_id} == $this->{input}{rev}) {
	    $revnew = new ExSite::Revision(data=>$rev);
	    $revold = new ExSite::Revision(data=>pop @rev);
	    last;
	}
    }
    if (! $revnew && ! $revold) {
	return undef;
    }

    my $text1 = $revnew->mime_type() =~ /^text/ ? $revnew->get_raw() : $revnew->get_html();
    my $text2 = $revold->mime_type() =~ /^text/ ? $revold->get_raw() : $revold->get_html();
    my $br = $ml->br;
    $text1 =~ s/</\&lt\;/g;
    $text2 =~ s/</\&lt\;/g;
    $text1 =~ s/>/\&gt\;/g;
    $text2 =~ s/>/\&gt\;/g;
    $text1 =~ s/\n/$br/g;
    $text2 =~ s/\n/$br/g;

    my $out .= $ml->div(String::Diff::diff_merge($text2,$text1,
						 remove_open => '<del>',
						 remove_close => '</del>',
						 append_open => '<ins>',
						 append_close => '</ins>',
			),{class=>"revisionChanges"});

    $out .= $ui->HelpPopup(message=>$ml->del("deleted").$br.$ml->ins("added")."${br}no changes",label=>"help key");
    return $ui->BasicBox(pane=>$out,title=>"Changes from revision ".$revold->id." to revision ".$revnew->id);
}

#### should only do this for page objects?

sub translations {
    my ($this,$cnode) = @_;
    my $out;
    my @lang = &get_languages(1);
    if (scalar @lang < 2) {
	$out = $ml->h1("Multilingual content management not enabled");
	$out .= $ml->p("Your system only recognizes one language:");
	$out .= $ml->ul(\@lang);
	$out .= $ml->p("Consult the help documentation to define additional languages.");
	return $out;
    }
    $out .= $ml->h1("Translations");

    ### FIXME: is this the correct place to be translating this content?

    my $language = $cnode->getdata("language");
    my $master = $cnode->master();
    if ($language) {
	$out .= $ml->p($ml->strong($cnode->name) . " is the " . 
		       $ml->em($language) . " version of " . 
		       $cnode->subtype() . " " .
		       $ml->a($master->name,{href=>$this->link(id=>$master->id)}) . "."
	    );
    }
    if (! $master->defined) { $master = $cnode; }
    my @c = $share{DB}->fetch_match("content",{master=>$master->id});
    my %tr = &keywise("language",\@c);
    if ($this->{input}{v}) {
	if ($tr{$lang[$this->{input}{v}]}) {
	    $out .= $this->warn("$lang[$this->{input}{v}] already exists.");
	}
	else {
	    $out .= $this->make_translation($master,$lang[$this->{input}{v}]);
	}
    }
    my $r = new ExSite::ReportBuilder(title=>"Translations of ".$master->name);
    $r->headers("Language","Content","URL","Last Update*");
    $r->foot("* green translation dates are fresher than the master content; red indicates translations that may be stale");
    my $t = new ExSite::Time($master->timestamp,"sql_timestamp");
    my $url = $master->get_url;
    $r->push($lang[0],
	     $ml->a($master->name,{href=>$this->link(cmd=>"info",id=>$master->id)}),
	     $ml->a($url,{href=>$url}),
	     $t->write("datetime"));
    shift @lang;
    my $iv = 0;
    foreach my $v (@lang) {
	$iv++;
	my @data = ( $v );
	if ($tr{$v}) {
	    my $tr_content = $cnode->get_content_obj($tr{$v});
	    my $url = $tr_content->get_url;
	    my $ctime = $tr_content->timestamp();
	    my ($date,$tclass);
	    if ($ctime) {
		my $t2 = new ExSite::Time($tr_content->timestamp,"sql_timestamp");
		$date = $t2->write("datetime");
		$tclass = $t2->diff($t) > 0 ? "stale" : "fresh";
	    }
	    else {
		$date = "no update yet";
		$tclass = "stale";
	    }
	    push @data, $ml->a($tr_content->name(),{href=>$this->link(cmd=>"info",id=>$tr_content->id)});
	    push @data, $ml->a($url,{href=>$url});
	    push @data, $ml->span($date,{class=>$tclass});
	}
	else {
	    push @data, $ml->a("create $v version",{href=>$this->link(v=>$iv),class=>"button_sm"}), "", "";
	}
	$r->push(\@data);
    }
    $out .= $r->make();
    return $out;
}

sub make_translation {
    my ($this,$master,$language) = @_;
    if (! $this->{cnode}->allow("update")) {
	# translations are an editorial function
	return $this->error("Sorry, your keys do not allow you to update translations.");
    }
    my $suffix = $config{language_suffix}{$language} || substr($language,0,2);
    my $name = $master->getdata("name") . "_$suffix";
    my $title = $master->getdata("title") . " ($language)";
    my $label = $master->getdata("label") . " ($language)";
    my $new_id = $master->copy(language=>$language,
			       name=>$name,
			       title=>$title,
			       label=>$label,
			       master=>$master->id);
    if ($new_id) {
	$ml->location($this->link(v=>undef,__plaintext=>1));
	return $ml->p("Created $language translation ".
		      $ml->a($ml->em($name),{href=>$this->link(cmd=>"info",id=>$new_id,v=>undef)}).".");
    }
    else {
	return $this->error("Failed to create $language translation.");
    }
}

sub keys {
    my ($this,$cnode) = @_;
    if (! $cnode->allow("delete") && 
	! $share{DB}->is_admin) {    # lvl 8 override
	# key management is an admin function, same as delete
	return $this->error("Sorry, your keys do not permit key management.");
    }

    my $out;
    my $cmd = $this->{input}{cmd};

    if ($cmd eq "key_new") {
	$out .= $this->key_new($cnode);
    }
    elsif ($cmd eq "key_del") {
	my $keyid = $this->{input}{key};
	my $key = new ExSite::Object(type=>"content_key",id=>$keyid);
	if ($key->delete()) {
	    $ml->location($this->link(__plaintext=>1,key=>undef,cmd=>"keys"));
	    return;
	}
	else {
	    $out .= &ExSite::Config::show_diagnostics();
	}
    }

    my @keyring = $cnode->keyring;
    my $r = new ExSite::ReportBuilder(title=>"Keyring for ".$cnode->name);
    $r->headers("Content","User","Roles","");
    $r->nodata("You do not have any keys to this content.");
    foreach my $key (@keyring) {
	my $k = new ExSite::Object(type=>"content_key",data=>$key);
	$r->push(
	    $ml->a($k->showdata("content_id"),{href=>$this->link(id=>$k->getdata("content_id"))}),
	    $k->showdata("uid"),
	    $k->showdata("role"),
	    $ui->FATool("delete",url=>$this->link(cmd=>"key_del",key=>$k->id),confirm=>"Really delete this key?",tone=>"bad")
	    );
    }
    $r->tools($ui->FATool("new",label=>"new key",url=>$this->link(cmd=>"key_new")));
    $out .= $r->make();
    return $out;
}

sub key_new {
    my ($this,$cnode) = @_;
    if (keys %{$this->{post}} > 0) {
	my @role;
	foreach my $role (qw(editor designer reviewer administrator owner)) {
	    if ($this->{post}{"role_$role"}) {
		push @role, $role;
	    }
	}
	my %key = ( content_id => $cnode->id,
		    uid => $this->{post}{uid},
		    type => $this->{post}{type} || "grant",
		    role => join($config{form}{multi_sep},@role) );
	my $key_id = $share{DB}->insert("content_key",\%key);
	return $key_id ? $ml->p("Key added to keychain.") : $share{DB}->show_diagnostics("error","HTML");
    }
    my $out = $ml->h1("New Key");
    my @admins = $share{DB}->fetch_match($config{auth}{user_table},"access>1");
    my @opt = map { {text=>$share{DB}->user_name($_)." ($_->{$config{auth}{user_login_column}}; level $_->{$config{auth}{user_access_column}})",
			 value=>$_->{$config{auth}{user_uid_column}}} } @admins;
    my $f = new ExSite::FormBuilder();
    my @groups = $share{DB}->fetch_all("usergroup");
    if (@groups > 0) {
	$out .= $ml->p("Select the user or group and their role(s) for managing ".$cnode->subtype." ".$ml->em($cnode->name).".");
	my @gropt = map { {text=>$_->{name}, value=>$_->{gid}} } @groups;
	$f->input(prompt=>"User",name=>"uid",type=>"select",options=>\@opt,required=>0,nullvalue=>"== select user ==");
	$f->input(prompt=>"Group",name=>"gid",type=>"select",options=>\@gropt,required=>0,nullvalue=>"== select group ==");
    }
    else {
	# uid required if no groups
	$out .= $ml->p("Select the user and their role(s) for managing ".$cnode->subtype." ".$ml->em($cnode->name).".");
	$f->input(prompt=>"User",name=>"uid",type=>"select",options=>\@opt,required=>1);
    }

    my $br = $ml->br;
    my @role = split /\|/, $share{DB}{map}->regexp("set:role");
    my @in_role;
    foreach my $role (@role) {
	push @in_role, $ml->input(undef,{type=>"checkbox",name=>"role_$role"})." $role";
    }
    $f->input(prompt=>"Roles",name=>"role",input=>join($br,@in_role),required=>-1);

    $f->input(prompt=>"Key Type",name=>"type",type=>"radio",options=>["grant"],value=>"grant",tail=>"(allow the user to act in these roles)$br");
    $f->input(prompt=>"Key Type",name=>"type",type=>"radio",options=>["revoke"],tail=>"(prevent the user from acting in these roles)");

    $out .= $f->make();
    $out .= $ml->h2("Roles:");
    $out .= $ml->ul([
	$ml->strong("Editors")." can create new content items and update editorial content.",
	$ml->strong("Designers")." can create new content items and update design content.",
	$ml->strong("Reviewers")." can moderate and approve new content.",
	$ml->strong("Administrators")." can publish, configure, and delete content.",
	$ml->strong("Owners")." are users who contributed this content and have limited editorial control over it.",
		    ]);
    return $out;
}

sub schedule {
    my ($this,$cnode) = @_;
    my $out;
    my $cmd = $this->{input}{cmd};

    if ($cmd eq "schedule_new") {
	return $this->schedule_new($cnode);
    }
    elsif ($cmd eq "schedule_del") {
	my $dateid = $this->{input}{date};
	my $date = new ExSite::Object(type=>"content_date",id=>$dateid);
	if ($date->delete()) {
	    $ml->location($this->link(__plaintext=>1,key=>undef,cmd=>"schedule"));
	    return;
	}
	else {
	    $out .= &ExSite::Config::show_diagnostics();
	}
    }

    my @date = $share{DB}->fetch_child("content_date","content",$cnode->id);
    my $r = new ExSite::ReportBuilder(title=>"Schedule for ".$cnode->name);
    $r->headers("Date/Time","Type","Description","Status","");
    $r->nodata("Nothing scheduled.");
    foreach my $d (@date) {
	my $e = new ExSite::Object(type=>"content_date",data=>$d);
	my $start = $e->getdata("start");
	my $t = new ExSite::Time($start,"sql_datetime");
	my $date = $d->{type} eq "calendar" ? 
	    $t->show_date_range($e->getdata("end"),"sql_timestamp") :
	    $t->write("datetime");
	$r->push(
	    $date,
	    $e->showdata("type"),
	    $e->showdata("description"),
	    $e->showdata("status"),
	    $ui->ToolIcon(name=>"delete",url=>$this->link(cmd=>"schedule_del",date=>$e->id),confirm=>"Really delete this date?")
	    );
    }
    $r->tools($ml->a($ml->img(undef,{src=>"$config{server}{HTMLpath}/_ExSite/images/icons/add.png",alt=>"new date",title=>"new date"}),{href=>$this->link(cmd=>"schedule_new")}));
    $out .= $r->make();
    return $out;
}

sub schedule_new {
    my ($this,$cnode) = @_;
    my $out;
    my $db = $share{DB};
    if (keys %{$this->{post}} > 0) {
	$out = $db->do();
	if ($db->errorcheck()) {
	    $out .= $db->show_diagnostics("error","html");
	}
	else {
	    $ml->location($this->link(__plaintext=>1,cmd=>"schedule"));
	}
    }
    else {
	my $title = $ml->em($cnode->label);
	my (@tab, @pane);
	push @tab, "Task";
	### FIXME: show only allowed tasks
	push @pane, $ml->h1("New Task for $title"). 
	    $share{DB}->make(table=>"content_date",
			     data=>{content_id=>$cnode->id,type=>"task",status=>"active"},
			     hide=>["content_id","type"],
			     action=>$this->link());
	$pane[-1] .= $ui->HelpBox(
	    title=>"Instructions",
	    pane=>$ml->p("The following task descriptions are allowed:").
	    $ml->ul(scalar $cnode->allowed_tasks()).
	    $ml->p("Active tasks will be executed once, within 1 hour after the specified date and time. Hourly, daily, and weekly tasks will be executed repeatedly between the start and end dates/times.")
	    );
			     
	push @tab, "To-do";
	push @pane, $ml->h1("New To-do Reminder for $title"). 
	    $share{DB}->make(table=>"content_date",
			     data=>{content_id=>$cnode->id,type=>"todo",status=>"active"},
			     hide=>["content_id","type","status","end"],
			     action=>$this->link());
	$pane[-1] .= $ui->HelpBox(
	    title=>"Instructions",
	    pane=>$ml->p("To-do reminders will be emailed to an appropriate administrator on the date. To-do reminders can be removed from your to-do list using the ToDo plugin.")
	    );
	push @tab, "Log";
	push @pane, $ml->h1("Log a note on $title"). 
	    $share{DB}->make(table=>"content_date",
			     data=>{content_id=>$cnode->id,type=>"log",status=>"active"},
			     hide=>["content_id","type","status","end"],
			     action=>$this->link());
	push @tab, "Other";
	push @pane, $ml->h1("Add a date to $title"). 
	    $share{DB}->make(table=>"content_date",
			     data=>{content_id=>$cnode->id},
			     hide=>["content_id"],
			     action=>$this->link());
	$out .= $ui->DynTabBox(tabs=>\@tab,panes=>\@pane);
    }
    return $out;
}

# search 

sub search {
    my ($this,$cnode) = @_;
    my $out;
    my $term = $this->{input}{search};
    my $method = $this->{input}{method};
    if ($term && $method) {
	$out .= $ml->h1("Results");
	if ($method =~ /find/) {
	    $out .= $this->find($cnode,$term);
	}
	elsif ($method =~ /names/) {
	    $out .= $this->search_names($cnode,$term);
	}
	elsif ($method =~ /metadata/) {
	    $out .= $this->search_metadata($cnode,$term);
	}
	elsif ($method =~ /index/) {
	    $out .= $this->search_index($cnode,$term);
	}
	elsif ($method =~ /revisions/) {
	    $out .= $this->search_content($cnode,$term);
	}
    }
    my $c = $this->get_content();
    my $sid = $c->my_section->id;
    my $cid = $c->id;
# not needed with use search index method
#    $out .= $ml->div(
#	$ml->a("Search Index",{href=>"javascript:popup_medium('$config{server}{CGIpath}/$config{prog}{admin}/Search?section_id=$sid&content=$cid')",class=>"button"}),
#	{style=>"width:150px; float:right"}
#	);
    my $f = new ExSite::FormBuilder();
    $f->input(prompt=>"Search Term",name=>"search",value=>$term,required=>1);
    $f->input(type=>"radio",
	      prompt=>"Search Method",
	      name=>"method",
	      required=>1,
	      value=>$method,
	      options=>["search for content names/titles",
			"search metadata",
			"use search index",
			"search all revisions and views",
			"find/resolve content"]
	);
    $out .= $ml->h1("Search");
    $out .= $f->make();
    return $out;
}

sub search_names {
    my ($this,$cnode,$name) = @_;
    my @content;
    my %results;
    foreach my $col (qw(name label title)) {
	push @content, $share{DB}->fetch_match("content",{name=>"%$name%"});
	push @content, $share{DB}->fetch_match("content",{label=>"%$name%"});
	push @content, $share{DB}->fetch_match("content",{title=>"%$name%"});
    }
    my %results = &keywise("content_id",\@content);
    my @results;
    my $out;
    foreach my $cid (sort keys %results) {
	my $c = $cnode->get_content_obj($results{$cid});
	next if ($c->alias());
	if ($c->allow()) {
	    push @results, 
	    $ml->a($c->title,{href=>$this->link(cmd=>"contents",id=>$c->id)}) . 
		" (".join(" &gt; ",$c->path()).")";
	}
    }
    return @results > 0 ? $ml->ul(\@results) : "Nothing found.";
}

sub search_metadata {
    my ($this,$cnode,$name) = @_;
    my @meta = $share{DB}->fetch_match("metadata",{value=>"%$name%"});
    my %results = &keywise("id",\@meta);
    my @results;
    my $out;
    foreach my $cid (sort keys %results) {
	my $c = $cnode->get_content_obj($cid);
	if ($c->allow()) {
	    push @results, 
	    $ml->a($c->title,{href=>$this->link(cmd=>"contents",id=>$c->id)}) . 
		" (".join(" &gt; ",$c->path()).")";
	}
    }
    return @results > 0 ? $ml->ul(\@results) : "Nothing found.";
}

sub search_index {
    my ($this,$cnode,$name) = @_;
    my $section_id = $cnode->my_section->id || $cnode->id;
    require ExSite::Search;
    my $search = new ExSite::Search($section_id);
    my %results = $search->search($name);
    my @url_id = sort { $results{$b} <=> $results{$a}; } keys %results;
    my $out;
    my $db = $share{DB};
    my $nresult = 0;
    foreach my $url_id (@url_id) {
	my $url = $search->{search_results}{$url_id} || 
	    $db->fetch("searchurl",$url_id);
	next if (! $url->{content_id});
	$nresult++;
	my $score = int($results{$url_id}*10)/10;
	if ($url->{url} =~ /^$config{server}{CGIpath}/) {
	    # show complete URLs
	    $url->{url} = $config{server}{server}.$url->{url};
	}
	my $link = $this->link(id=>$url->{content_id},cmd=>"preview");
	$out .= $ml->dt( $ml->a($url->{title},{href=>$link}) );
# show subtype, public link?
#	$out .= $ml->dt( $ml->a($url->{title},{href=>$url->{url}}) );
	my $descr = $url->{description} . 
	    ($url->{description} ? $ml->br : "") .
	    $ml->span("[$url->{url}, $msg{score}: $score]",{class=>"searchdetails"});
	$out .= $ml->dd($descr);
    }
    if ($nresult == 0) {
	$out .= $ml->dt($config{search}{no_results});
    }
    return $ml->dl($out);
}

sub search_content {
    my ($this,$cnode,$name) = @_;
    my $section_id = $cnode->my_section->id;
    my @content = $share{DB}->custom_query("select content.*,revision.revision_id from content,revision,cview where cview.format='text' and cview.data like ? and cview.revision_id=revision.revision_id and content.content_id=revision.content_id order by revision.revision_id,cview.cview_id","%$name%");
    my %results = &keywise("content_id",\@content);
    my @results;
    my $out;
    foreach my $cid (sort keys %results) {
	my $c = $cnode->get_content_obj($results{$cid});
	if ($c->allow()) {
	    push @results, 
	    $ml->a($c->title,{href=>$this->link(cmd=>"contents",id=>$c->id)}).
		" revision #".$results{$cid}{revision_id}.
		" (".join(" &gt; ",$c->path()).")";
	}
    }
    return @results > 0 ? $ml->ul(\@results) : "Nothing found.";
}

sub find {
    my ($this,$cnode,$name) = @_;
    my $out;
    my $c = $cnode->find($name);
    if ($c->has_content()) {
	my $path = $c->content_path();
	my @node = ($ml->a("Top",{href=>$this->link(id=>undef,cmd=>undef)}));
	while (my $node = $path->next()) {
	    push @node, $ml->a($node->name,{href=>$this->link(id=>$node->id,cmd=>"contents")});
	}
	$out .= $ml->p("The preferred instance of ".$ml->em($name)." is at:");
	$out .= $ui->PathBar(links=>\@node);
    }
    else {
	$out .= $ml->p("No matching content was found in this content's search path.");
    }
    return $out;
}

sub workflow {
    my ($this,$cnode) = @_;
    if ($cnode->allow("moderate")) {
	my $out;
	my @content = $cnode->get_contents();
	if (scalar keys %{$this->{post}} > 0) {
	    if ($this->{post}{wf_all} =~ /^\d$/) {
		$cnode->setdata("status",$this->{post}{wf_all});
		if ($cnode->save()) {
		    $out .= $ml->div("Updated ".$cnode->title);
		}
		foreach my $c (@content) {
		    $c->setdata("status",$this->{post}{wf_all});
		    if ($c->save()) {
			$out .= $ml->div("Updated ".$c->title);
		    }
		}
	    }
	    else {
		my $in = "wf_".$cnode->id;
		if ($this->{post}{$in} =~ /^\d$/) {
		    #$cnode->setdata("status",$this->{post}{$in});
		    $cnode->set_status($this->{post}{$in});
		    if ($cnode->save()) {
			$out .= $ml->div("Updated ".$cnode->title);
		    }
		}
		foreach my $c (@content) {
		    my $in = "wf_".$c->id;
		    if ($this->{post}{$in} =~ /^\d$/) {
			#$c->setdata("status",$this->{post}{$in});
			$c->set_status($this->{post}{$in});
			if ($c->save) {
			    $out .= $ml->div("Updated ".$c->title);
			}
		    }
		}
	    }
	}
	my $ncontent = 1;
	my $f = $share{DB}->form(method=>"post");
	my $r = new ExSite::ReportBuilder(title=>"Workflows");
	$r->headers("Content","Type","MIME-type","Status");
	$r->push($cnode->title,$cnode->subtype,$cnode->revision->mime_type(),$share{DB}->input_exsite(name=>"wf_".$cnode->id,datatype=>"enum:content_status",value=>$cnode->getdata("status")));
	foreach my $c (@content) {
	    $ncontent++;
	    $r->push("&bull; ".$ml->a($c->title,{href=>$this->link(id=>$c->id)}),$c->subtype,$c->revision->mime_type(),$share{DB}->input_exsite(name=>"wf_".$c->id,datatype=>"enum:content_status",value=>$c->getdata("status")));
	}
	my $foot;
	if ($ncontent > 1) {
	    $foot .= $ml->div("Set workflow statuses individually, or set all to: ".$share{DB}->input_exsite(name=>"wf_all",datatype=>"enum:content_status"));
	}
	$foot .= $ml->input(undef,{type=>"submit",value=>"Update"});
	$r->foot($foot);
	$out .= $ml->form($r->make,{method=>"post",action=>$this->link()});
	$out .= $ui->BasicBox(title=>"Definitions:",
			      pane=>$ml->ul([
				  $ml->b("published").": live content, suitable for public viewing",
				  $ml->b("archived").": old content, still okay for public viewing, but can be excluded from regular indexes and menus",
				  $ml->b("approved").": approved to be published (use the publish button to take this content live)",
				  $ml->b("queued").": approved to be published, will be taken live automatically by the queuing system",
				  $ml->b("submitted").": pending approval/moderation",
				  $ml->b("draft").": still being worked on, should not be published",
				  $ml->b("expired").": content is temporarily invalid, should not be published",
				  $ml->b("canceled").": content is no longer valid, should not be published",
				  $ml->b("rejected").": content does not belong here, and can be removed/deleted"
					    ]));
	return $out;
    }
    else {
	return $this->warn("You need moderator permissions to manage workflows.");
    }
}

sub publish {
    my ($this,$cnode) = @_;
    my $out = $ml->h1("Publish ".$ml->em($cnode->title));
    $out .= $ml->table(
	$ml->tr(
	    $ml->td().
	    $ml->th("Fast publish").
	    $ml->th("Force publish")
	).
	$ml->tr(
	    $ml->th("This item only",{class=>"left"}).
	    $ml->td($ui->Button(type=>"link-button",label=>"publish",url=>"$config{server}{CGIpath}/$config{prog}{publish}?back=1&child=0&parent=0&id=".$cnode->id,tone=>"good",tooltip=>"Publishes only this item, if it appears to need publishing.")).
	    $ml->td($ui->Button(type=>"link-button",label=>"publish",url=>"$config{server}{CGIpath}/$config{prog}{publish}?force=1&back=1&child=0&parent=0&id=".$cnode->id,tooltip=>"Publishes only this item."))
	).
	$ml->tr(
	    $ml->th("Item, contents, and container",{class=>"left"}).
	    $ml->td($ui->Button(type=>"link-button",label=>"publish",url=>"$config{server}{CGIpath}/$config{prog}{publish}?back=1&id=".$cnode->id,tone=>"warning",tooltip=>"Publishes this item and everything within it that needs to be published. This may take some time.")).
	    $ml->td($ui->Button(type=>"link-button",label=>"publish",url=>"$config{server}{CGIpath}/$config{prog}{publish}?force=1&back=1&id=".$cnode->id,tone=>"bad",tooltip=>"Publishes this item and everything within it. This takes the longest time."))
	),
	{class=>"pubOptions"}
	);
    $out .= $ml->ul(
	[
	 $ml->strong("Fast publish")." skips things that already seem to be published.",
	 $ml->strong("Force publish")." publishes things even if they already seem to be published.",
	 $ml->strong("Item only")." publishes only the currently selected content object.",
	 $ml->strong("Item, contents, and container")." publishes the currently selected content object plus all objects that are touching it."
	]
	);
    return $out;
}

sub delete {
    my ($this,$c) = @_;
    if ($this->{post}{del} == $c->id) {
	my $type = $c->subtype();
	my $title = $c->title;
	if (! $c->allow("delete")) {
	    return $this->error("Sorry, you do not have permission to delete $type '$title'.");
	}
	my $pid = $c->parent->id;
	$c->unpublish();
	$c->delete();
	if ($pid) {
	    $ml->redirect($this->link(__plaintext=>1,__clear=>1,id=>$pid));
	}
	return $title . " deleted.";
    }
    else {
	my $out = $ml->h1("Delete ".$c->label."?");
	my $tree = $c->get_content_tree();
	my @warn;
	my $nsub = $tree->count(undef,$c->id)-1;
	push @warn, $nsub." content(s)" if $nsub;
	my $nrev = $c->count_revisions();
	push @warn, $nrev." revision(s)" if $nrev;
	if (scalar @warn) {
	    $out .= $ml->p("Deleting this ".$c->subtype()." will also delete:");
	    $out .= $ml->ul(\@warn);
	}
	if ($nsub + $nrev > 100) {
	    $out .= $this->warn("If you delete large numbers of items all at once, you can overflow the trash bin, preventing recovery of the deleted items.");
	}
	$out .= $ml->form(
	    $ml->input(undef,{type=>"hidden",name=>"del",value=>$c->id}).
	    $ml->input(undef,{type=>"submit",class=>"btn btn-danger",value=>"DELETE"}),
	    {method=>"POST"}
	    );
	return $out;
    }
}

1;
