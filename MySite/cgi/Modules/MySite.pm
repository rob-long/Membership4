package Modules::MySite;
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
#----------------------------------------------------------------------------
#
#   MySite is a simplified content management system that is suitable for
#   newbies and ExSite-Lite users.  It can inline all CMS functions into the
#   website itself, rather than the administrator control panel.  That 
#   makes it a little harder to set up, since a website must preexist to 
#   embed the MySite tools into;  but much easier for casual users to use 
#   once the parent site is running.
#
#   Features of MySite:
#       - creates native websites only
#       - simplified library management ("My Image Library")
#       - simplified page creation assumes common defaults
#       - inline content editor appears right in page
#       - one-step content updates
#
#   For advanced CMS features like template building, version control, 
#   polymorphic content, dynamic page configuration, raw-HTML editing, etc. 
#   you must use the CMS module instead.
#----------------------------------------------------------------------------

use strict;
use MIME::Base64;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Util;
use ExSite::UI;
use ExSite::Mail;
use ExSite::Input;
use ExSite::Image;
use ExSite::Section;
use ExSite::Tree;
use ExSite::FormBuilder;
use Modules::Content;
use JSON;

use vars qw(@ISA $ml $ui $MySite);
@ISA = qw(Modules::Content);

my $rowcount;

# write : redirect to user control panel, or prompt for login

sub write {
    my ($this,$options) = @_;
    $ml = &get_obj("ML");
    if ($share{DB}->is_executive()) {
        return $this->ctrl_panel($options);
    }
    else {
	return $this->error("My Website: permission denied.");
    }
}

sub ioctl {
    my $this = shift;
    $_ = shift;   # $_ is the ioctl request
    if (/ModuleName/) {
        return "My Website";
    }
    elsif (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/Summary/) {
        return \&summary;
    }
    elsif (/Category/) {
        return "CMS";
    }
    elsif (/ModuleInfo/) {
        return "My Website is a simple, user-friendly website management
tool.  It allows for easy previewing and editing of pages, as well as providing 
shortcuts for document, photo album, and menu management.";
    }
    return undef;
}

#### FIXME
sub summary {
    my ($this,$section_id) = @_;
    $section_id = $section_id || $this->get_section_id();
    my $r = new ExSite::ReportBuilder();
    $r->title("My Website");
    my @head = ("Item","Count");
    $r->headers(\@head);

    my %page;
    my $s = new ExSite::Section(id=>$section_id);
    my @p = $s->get_all_pages();
    foreach my $page (@p) {
        if ($page->is_template) {
            $page{Templates}++;
        }
        elsif ($page->is_library) {
            $page{Libraries}++;
            $page{"Images &amp; Documents"} += scalar $page->fetch_all_content_objs();
        }
        else {
            if ($page->is_public()) {
                $page{"Pages (public)"}++;
            }
            else {
                $page{"Pages (restricted)"}++;
            }
        }
    }

    foreach my $key (sort keys %page) {
        $r->push($key,$page{$key});
    }
    return $r->make;
}

sub ctrl_panel {
    my ($this,$options) = @_;
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    $this->{section_id} = $this->get_section_id();
    if (! $this->{section_id}) {
	return $this->set_section_id();
    }
    my $c = new ExSite::Content();
    $this->{content} = $c->get_content_obj($this->{input}{id} || $this->{section_id});
    my $out = $this->pathbar($this->{content},section_id=>$this->{section_id});
    if ($this->{input}{id}) {
	# specific item selected
	if ($this->{input}{cmd} =~ /preview|update/) {
	    # special case - admin funcs are integrated with a page view
	    return $this->preview();
	}
	#$out .= $this->show_content();
	return $this->show_content();
    }
    else {
	my $cmd = $this->{input}{cmd};
	if ($cmd eq "conf") {
	    $out .= $this->configure($this->{content},hide=>[],show=>["title","url"]);
	    $out .= $ui->ErrorBox(title=>"Warning",pane=>"If you change the URL, you must ensure that your DNS and web server are also configured to serve this URL, or your links may break.");
					    
	}
	elsif ($cmd eq "newpage") {
	    $out .= $this->newpage();
	}
	else {
	    # nothing selected
	    $out .= $this->content_selector();
	}
    }
    return $out;
}

sub content_selector {
    my $this = shift;
    my $site = new ExSite::Section(id=>$this->{section_id});
    my $db = $share{DB};
    my $out; # .= $ml->h1($site->title);
    my $imgpath = "$config{server}{HTMLpath}/_ExSite/images/icons";
    $out .= $ui->MenuBar(
	links=>[
	    {url=>$this->link(cmd=>"conf"),label=>"configure site",faicon=>"conf"},
	    {url=>$this->link(cmd=>"newpage"),label=>"new&nbsp;page",faicon=>"add"},
	    {url=>"javascript:openOLFrame('$config{server}{CGIpath}/$config{prog}{ctrlpanel}/SimpleMenu?section_id=$this->{section_id}')",label=>"change menu order",faicon=>"list"},
	    {url=>"javascript:openOLFrame('$config{server}{CGIpath}/$config{prog}{ctrlpanel}/PhotoAlbum?section_id=$this->{section_id}')",label=>"photos",faicon=>"photo"},
	    {url=>"javascript:openOLFrame('$config{server}{CGIpath}/$config{prog}{ctrlpanel}/Document?section_id=$this->{section_id}')",label=>"documents",faicon=>"page"},
	    {url=>"javascript:openOLFrame('$config{server}{CGIpath}/$config{prog}{publish}?id=$this->{section_id}')",label=>"publish site",faicon=>"download"},
	]);
    $out .= $this->all_content();
    return $out;
}

sub all_content {
    my $this = shift;
    my $out;
    $out .= $ui->AlertBox(title=>"Reload?",pane=>"Some content has changed since this site map was last generated. ".$ui->Button(label=>"Reload now",url=>$this->link(cmd=>undef),tone=>"bad",size=>"s"),tone=>"bad",id=>"reloadAlert",state=>0);
#    $out .= &insert_js("jquery.magnific-popup.min.js");
#    $out .= &insert_css("magnific-popup.css");
#    $out .= $ml->script("var iconpath = '$config{server}{HTMLpath}/_ExSite/images/icons';\nvar modpath = '$config{server}{CGIpath}/$config{prog}{ctrlpanel}';\n");
    my $s = new ExSite::Section(id=>$this->{section_id});
    my $tree = $s->get_mapped_pages();
    my $top = $tree->getnode_data($this->{section_id});
    # the tree itself
    $out .= $ml->h1("Site Map");
    $out .=  $this->content_tree();
    return $out;

#    # the popups
#    $out .= $this->{popups};
#    $out .= $ml->script("var content_info = " . 
#			JSON::to_json( $this->{content_info} ) . ";\n" );
#    return $out;
}

sub content_tree {
    my ($this) = @_;
    my $out;
    my $s = new ExSite::Section(id=>$this->{section_id});
    my $tree = $s->get_mapped_pages();
    my @page;
    foreach my $p ($tree->get_topnodes_data()) {
	my $pg = $s->get_content_obj($p);
	push @page, {
	    label=>$pg->label,
	    text=>"website home page",
	    url=>"javascript:openOLFrame('".$this->link(id=>$pg->id)."')",
	    open=>1,
	    sublist=>$this->content_tree_r($pg,$tree),
	    class=>"contentSection",
	};
    }
    $out .= $ui->TreeView(@page);
    $out .= $ui->OverlayFrame();
    return $out;
}

sub content_tree_r {
    my ($this,$page,$tree) = @_;
    my @page;
    foreach my $p ($tree->get_child_data($page->id)) {
	my $pg = $page->get_content_obj($p);
	my @descr = ( $pg->is_active ? $pg->subtype() : $pg->wf_status()." ".$pg->subtype() );
	my @class = ("content".ucfirst($pg->subtype));
	if (! $pg->is_active) {
	    push @class, "contentInactive";
	}
	my $hide = $pg->hide_from();
	if ($hide) {
	    $hide =~ s/;/,/g;
	    push @descr, "hidden from: $hide";
	}
	push @page, {
	    label=>$pg->label,
	    text=>join("; ",@descr),
	    url=>"javascript:openOLFrame('".$this->link(id=>$pg->id)."')",
	    open=>$pg->is_active,
	    sublist=>$this->content_tree_r($pg,$tree),
	    class=>join(" ",@class),
	};
    }
    return scalar @page > 0 ? \@page : undef;
}

sub show_content {
    my $this = shift;
    my $iconpath = "$config{server}{HTMLpath}/_ExSite/images/icons";
    my $cid = $this->{content}->id;

    my $out = $ui->ToolBar(
	links=>[
	    {label=>"preview",url=>$this->link(cmd=>"preview",id=>$cid),faicon=>"view"},
	    {label=>"edit",url=>$this->link(cmd=>"update",id=>$cid),faicon=>"edit"},
	    {label=>"configure",url=>$this->link(cmd=>"conf",id=>$cid),faicon=>"configure"},
	    undef,
	    {label=>"publish",url=>"$config{server}{CGIpath}/$config{prog}{publish}?id=$cid",target=>"_blank",faicon=>"publish"},
	    undef,
	    {url=>$this->link(cmd=>"rollback",id=>$cid),label=>"rollback",faicon=>"back"},
	    {url=>$this->link(cmd=>"delete",id=>$cid),label=>"delete",faicon=>"delete"},
				     ]);

    my $cmd = $this->{input}{cmd};
    if ($cmd eq "conf") {
	$out .= $this->configure($this->{content});
    }
    elsif ($cmd eq "newpage2") {
	$out .= $this->newpage2();
    }
    elsif ($cmd eq "rollback") {
	$out .= $this->rollback();
    }
    elsif ($cmd eq "delete") {
	$out .= $this->delpage();
    }
    elsif ($cid) {
	my $p = $this->{content};
	my $r = new ExSite::ReportBuilder(title=>$p->title);
	$r->headers("Type","Status","Menu Label","Path","URL");
	my $status = $p->wf_status();
	my $url = $p->get_url();
	$r->data($p->subtype(),$ml->span($status,{class=>"status".ucfirst($status)}),$p->label(),scalar $p->path(),$ml->a($p->httppath,{href=>$p->get_url,target=>"_blank"}));
	$out .= $r->make();
	my $type = $p->subtype();
	if ($type ne "page") {
	    my $mod = $p->subtype_attr("plugin");
	    if ($mod) {
		$mod =~ s/Modules:://;
		$out .= $ui->HelpBox(
		    title=>"This is not a page!",
		    pane=>"It is a $type. To manage its contents, try using the ".$ml->a($mod,{href=>"$config{server}{CGIpath}/$config{prog}{ctrlpanel}/${mod}?id=".$p->id."&section_id=".$this->{section_id}})." module.");
	    }
	}
    }
    else {
	# unknown action - restart
	$ml->location($this->link(__plaintext=>1,cmd=>undef,id=>undef));
    }

    return $out;
}

sub newpage {
    my $this = shift;
    my $c = $this->{content};
    my $out;
    if (scalar keys %{$this->{post}} > 0) {
	my %post = $share{DB}->parse_parts(%{$this->{post}});
	if ($post{label}) {
	    my $p = $c->new_content_obj(label=>$post{label},
					type=>"page",
					parent=>$c->id);
	    my $body = $p->new_content_obj(
		title=>"body",
		parent=>$p->id,
		status=>0,
		type=>$c->isubtype("content"),
		);
	    if ($body->id) {
		$out .= $ml->h2("Page created");
		$ml->location($this->link(__plaintext=>1,cmd=>"newpage2",id=>$p->id));
	    }
	    else {
		$out .= $c->show_diagnostics("error","html");
	    }
	}
	else {
	    $out .= $this->error("Missing title or article body.");
	}
    }
    else {
	$out .= $ml->h1("New Page");
	my $db = $share{DB};
	my $f = $db->form();
	$f->input(name=>"label",prompt=>"Menu Label",type=>"text",size=>40,required=>1);
	$f->input(name=>"help",type=>"preformatted",input=>$ml->p($ml->strong("Tip:")." Menus generally do not have a lot of room for text. Keep your menu labels concise, to prevent formatting glitches."));
	$out .= $db->form->make();
    }
    return $out;
}

sub newpage2 {
    my $this = shift;
    my $c = $this->{content};
    my $out = $ml->h1("Page created");
    $out .= $ml->p("You should edit your new page to give it some content, then publish it to make it visible to your website visitors.");
    $out .= $ml->p("Click the configure icon to customize the page setup.");
    return $out;
}

sub configure {
    my ($this,$c,%opt) = @_;
    if (! $c->allow("edit")) {
	return $this->error("Sorry, you do not have permission to configure this ".$c->subtype().".");
    }
    if (scalar keys %{$this->{post}} > 0) {
	$cookie{lcc} = time; # flag sitemap change
	return $c->do_editmeta();
    }
    else {
	my $type = $c->subtype();
	my $ml = &get_obj("ML");
	my $out .= $ml->h1("Configure $type ".$ml->em($c->title));

	# simplify config form for casual editors
	my $hide = $opt{hide} || [qw(content_id type url master content_role mtime ptime)];
	$out .= $c->editmeta(
	    hide=>$hide,
	    show=>$opt{show},
	    extra=>{reply=>$this->link(__plaintext=>1,cmd=>undef)}
	    );
	return $out;
    }
}

sub preview {
    my $this = shift;
    my $page = $this->{content};
    # handler to inject MySite admin controls into page view
    $page->handler("get_content",\&MySite_get_content);
    $MySite = $this;
    # replace admin output with page view
    $share{Page} = $page;
    my $pagehtml = $page->expand();
    # we return a complete document; do not add any control panel HTML to this
    return $pagehtml;
}

# preview handler for page body

sub MySite_get_content {
    my ($this,$id,$option) = @_;
    return undef if ($id ne "body");
    $this->{htmlsub}++;
    my ($body,$newtext);
    $this->{expanded}{body} = 1;

    #$body = $this->find("body");  # this will find bodies all over the place
    $body = $this->my_content("body");
    if (! defined $body) {
	return 
	    $ml->p("No body content to update."); #.
#	    $ml->div(
#		$ml->a("close",{href=>"javascript:window.close()",class=>"MySiteUpdate"}),
#		{class=>"MySiteControls"}
#	    );
	### you get this message if trying to edit a non-page such as a blog,
	### or calendar; should we launch plugin here instead?
    }
    $body->load_revision("newest");
#    $newtext = $body->show();
    my $bodyhtml = $body->revision->get_html() || $ml->p();
    $newtext = $body->expand(html=>$bodyhtml,method=>"dummy-page,dummy-content,dummy-module");

    my $in = new ExSite::Input;
    my $p = $in->post;
    my $q = $in->query;
    if ($q->{cmd} eq "update") {
	my $purl = $MySite->link(cmd=>"preview");
	my $f = $share{DB}->form(method=>"post",action=>$purl);
	$f->template("[[prompt]][[input]]");
	$share{DB}->input_htmleditor(prompt=>"<!-- input body -->",value=>$newtext,name=>"body");
	my $buttons = $ml->input(undef,{type=>"submit",class=>"formButton",value=>"Save"});
	if (! $body->parent->wf_istatus()) {
	    # published; offer a save-as-draft option
	    $buttons .= $ml->input(undef,{type=>"submit",name=>"_save",class=>"formButton",value=>"Save as draft"});
	}
	$buttons .= $ml->button($msg{Cancel},{value=>"Cancel",class=>"formButton cancel",onclick=>"window.location.href='$purl'"}).
	    $ml->input(undef,{value=>$msg{Reset},class=>"formButton",type=>"reset"});

	$f->set("buttons",$ml->div($buttons,{class=>"formButtons"}));
	$newtext = $f->make();
    }
    else {
	if (scalar keys %$p) {
	    my %data = $share{DB}->parse_parts(%$p);
	    if ($data{body}) {
		# new body content has been posted
		# unescape stuff
		$newtext = &restore_cms_tags($data{body});
		my $t = new ExSite::Time;
		my $note = "edited using MySite by ".$share{DB}->my_name." on ".$t->write("datetime");
		my %rev = (data=>$newtext,format=>"text",note=>$note);
		if ($p->{_save} =~ /draft/i) {
		    $rev{status} = $ExSite::Workflow::status{draft};
		}
		$body->revise(%rev);
	    }
	    $this->warn("unexpected post data");
	}
	my $page = $body->parent();
	$newtext .= $ml->div(
	    $ml->a("edit page",{href=>$MySite->link(cmd=>"update"),class=>"MySiteUpdate"}).
	    $ml->a("done",{href=>"$config{server}{CGIpath}/$config{prog}{ctrlpanel}/MySite?id=".$page->id."&section_id=".$page->my_section->id(),class=>"MySiteUpdate"}),
	    {class=>"MySiteControls"});
    }
    $newtext .= $ml->link(undef,{rel=>"stylesheet",href=>"$config{server}{HTMLpath}/_Modules/MySite/controls.css",type=>"text/css"});
    return $ml->div($newtext,{style=>"border-width:1px; border-color:red; border-style:dashed; padding:0px;"});
}

sub rollback {
    my $this = shift;
    my $body = $this->{content}->my_content("body");
    if ($body && $body->has_revisions) {
	if ($body->rollback()) {
	    return $ui->SuccessBox(pane=>"Rollback completed.");
	}
	else {
	    return $ui->ErrorBox(pane=>"Rollback failed: ".&ExSite::Config::show_diagnostics());
	}
    }
    else {
	return $ui->ErrorBox(title=>"Warning",pane=>"Nothing to roll back.");
    }
}

sub delpage {
    my $this = shift;
    my $out;
    my $db = $share{DB};
    if ($this->{input}{id}) {
        # specific page id given in URL
	my $p = new ExSite::Page(id=>$this->{input}{id});
        if ($this->{input}{confirm}) {
            $out .= $msg{"deleting page"}." ".$p->id."...<br>";
            if ($p->allow("delete")) {
                $p->delete();
		$cookie{lcc} = time; # flag sitemap change
		$out .= $ui->SuccessMsg("Page deleted.");
            }
            else {
                $out .= $this->error($msg{"Delete page: permission denied."});
            }
        }
        else {
	    my $submenu = $p->my_submenu_items();
	    my $subout;
	    if ($submenu->count > 0) {
		my @link;
		while (my $subpage = $submenu->next) {
		    push @link, $ml->a($subpage->label,{href=>$this->link(id=>$subpage->id,cmd=>undef)});
		}
		$subout = "(".$msg{"along with the sub-pages"}." ".join(", ",@link).")";
	    }
	    if ($p->subtype() eq "section") {
		$out .= $ml->p($msg{"THIS ACTION WILL DELETE YOUR ENTIRE WEBSITE!"}).
		    $ml->p($msg{"If you choose to proceed, it may not be possible to recover it from the trash, if the quantity of deleted material is too large."});
	    }
	    else {
		$out .= $ml->p(&substitute($msg{"This action will remove this page [[others]] from your website. Your website should be republished after doing this, so that the menus on other pages will be updated appropriately."},{others=>$subout}));
		$out .= $ml->p($msg{"Deleted pages can be recovered from the Trash if you change your mind."});
	    }
            $out .= $ml->p(
                           $ml->form(
                                     $ml->input(undef,{type=>"hidden",name=>"id",value=>$this->{input}{id}}).
                                     $ml->input(undef,{type=>"hidden",name=>"section_id",value=>$this->{input}{section_id}}).
                                     $ml->input(undef,{type=>"hidden",name=>"cmd",value=>$this->{input}{cmd}}).
                                     $ml->input(undef,{type=>"hidden",name=>"confirm",value=>1}).
                                     $ml->input(undef,{type=>"submit",class=>"delete",value=>$msg{DELETE}}).
                                     $ml->input(undef,{type=>"button",value=>$msg{Cancel},OnClick=>"javascript:history.back()"})
                                     )
                           );
	    $out = $ui->ErrorBox(
		title=>&substitute($msg{"Delete page \"[[title]]\""},{title=>$p->title}),
		pane=>$out,
		size=>"m",
		);
        }
    }
    else {
        $out = $this->error($msg{"Error Deleting Page: no page was specified!"});
    }
    return $out;
}

1;
