package Modules::Template;

#----------------------------------------------------------------------------
#
#   Copyright (C) 2014 - Exware Solutions, Inc.  http://www.exware.com
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
#  Create and assign page layouts
#
#----------------------------------------------------------------------------
# +list all templates
# +template overview
# all pages using a template
# - change template for a page
# all pages in a section
# - change template for a page
# delete template
# publish template
# edit/update template?
# add content to template
# import template wizard

use strict;

use ExSite::Config;
use ExSite::Input;
use ExSite::Misc;
use ExSite::Util;
use ExSite::ML;
use ExSite::UI;
use ExSite::FormBuilder;
use ExSite::ReportBuilder;
use ExSite::Form;
use ExSite::Wizard;
use Modules::Content;
use MIME::Base64;

use Modules::BaseDCD;

use vars qw(@ISA $ml $ui $Template);
@ISA = qw(Modules::Content);

# read method (sets up input data)

sub read {
    my ($this,$options) = @_;
    my $in = new ExSite::Input;
    $this->{input} = $in->combine;
    $this->{post} = $in->post;
    $this->{is_post} = scalar keys %{$this->{post}};
}

# write method (builds output for regular web pages)

sub write {
    my ($this,$options) = @_;
    return undef;
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
	return "Template Manager";
    }
    elsif (/ModuleInfo/) {
	return "Create and assign page layouts";
    }
    elsif (/Category/) {
	return "CMS";
    }
    elsif (/ControlPanel/) {
	return \&ctrl_panel;
    }
}

# ctrl_panel() generates the contents of the administrator control panel

sub ctrl_panel {
    my $this = shift;
    $Template = $this;
    $this->{section_id} = $this->get_section_id();
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    $this->setup_queries();
    my $cmd = $this->{input}{cmd};
    if ($cmd eq "pages") {
	return $this->list_pages();
    }
    if ($cmd eq "import") {
	return $this->import_template();
    }
    elsif ($cmd eq "conf") {
	my $t = new ExSite::Template(id=>$this->{input}{id});
	my $out = $this->show_template_header($t);
	$out .= $this->configure($t,hide=>[qw(content_id type url access hide publish parent master sortkey content_role mtime ptime)]);
	return $out;
    }
    elsif ($cmd eq "del") {
	return $this->delete_template($this->{input}{id});
    }
    elsif ($this->{input}{id}) {
	return $this->show_template($this->{input}{id});
    }
    elsif ($this->{section_id}) {
	return $this->list_templates();
    }
    else {
	return $this->set_section_id();
    }
}

sub list_pages {
    my $this = shift;
    my $out;
    my $iconpath = "$config{server}{HTMLpath}/_ExSite/images/icons";
    $out .= $ui->IconBar(
	links=>[
	    {label=>"import",url=>$this->link(cmd=>"import"),img=>"$iconpath/add.png"},
	    {label=>"templates",url=>$this->link(cmd=>undef),img=>"$iconpath/template.png"},
	    {label=>"pages",url=>$this->link(cmd=>"pages"),img=>"$iconpath/pages.png"},
	    ]);
    if ($this->{is_post}) {
	$out .= $this->set_page_templates();
    }
    my $db = $share{DB};
    my $s = new ExSite::Section(id=>$this->{section_id});
    my $map = $s->get_mapped_pages();
    my $r = new ExSite::ReportBuilder(title=>"Pages");
    $r->headers("Page","Type","Hide From","Status","Template");
    $r->push($s->label,
	     $s->subtype(),	
	     $s->showdata("hide"),
	     $s->showdata("status"),
	     $this->template_dropdown($s));
    foreach my $data ($map->get_child_data($this->{section_id})) {
	my $p = $s->get_content_obj($data);
	$this->list_pages_row($r,$p,0,$map);
    }
    $out .= $r->make();
    return $ml->form($out . $ml->input(undef,{type=>"submit",value=>"Change templates"}),{method=>"post"});
}

sub list_pages_row {
    my ($this,$r,$page,$level,$map) = @_;
    $r->push($page->label,
	     $page->subtype(),
	     $page->showdata("hide"),
	     $page->showdata("status"),
	     #$page->showdata("template"), # drop-down
	     $this->template_dropdown($page));
    foreach my $data ($map->get_child_data($page->id)) {
	my $p2 = $page->get_content_obj($data);
	$this->list_pages_row($r,$p2,$level+1,$map);
    }
}

sub template_dropdown {
    my ($this,$p) = @_;
    if (! exists $this->{templates}) {
	my @tdata = $share{DB}->get_query("all templates");
	foreach my $tdata (@tdata) {
	    my $t = new ExSite::Template(data=>$tdata);
	    my $sid = $t->my_section->id;
	    $this->{templates}{$sid} or $this->{templates}{$sid} = [];
	    push @{$this->{templates}{$sid}}, $t;
	}
    }
    my $section_id = $p->my_section->id;
    my $opts = $ml->option("n/a",{value=>0});
    foreach my $template (@{$this->{templates}{$section_id}}) {
	my $optopt = {value=>$template->id};
	if ($p->getdata("template") == $template->id) {
	    $optopt->{selected} = undef;
	}
	$opts .= $ml->option($template->label,$optopt);
    }
    return $ml->select($opts,{name=>"template_".$p->id});
}

sub list_templates {
    my $this = shift;
    my $out;
    my $iconpath = "$config{server}{HTMLpath}/_ExSite/images/icons";
    $out .= $ui->IconBar(
	links=>[
	    {label=>"import",url=>$this->link(cmd=>"import"),img=>"$iconpath/add.png"},
	    {label=>"templates",url=>$this->link(cmd=>undef),img=>"$iconpath/template.png"},
	    {label=>"pages",url=>$this->link(cmd=>"pages"),img=>"$iconpath/pages.png"},
	    ]);
    my $db = $share{DB};
    my @tdata = $db->get_query("all templates");
    my $r = new ExSite::ReportBuilder(title=>"Templates");
    $r->headers("Template","Pages","Contents","Section");
    foreach my $data (@tdata) {
	if ($data->{template} == 0) {
	    my $t = new ExSite::Template(data=>$data);
	    next if ($this->{section_id} && 
		     $t->my_section->id != $this->{section_id});
	    $this->list_templates_row($r,$t,0,\@tdata);
	}
    }
    $out .= $r->make();
    return $out;
}

sub list_templates_row {
    my ($this,$r,$t,$level,$tdata) = @_;
    my $npage = $share{DB}->count("content",{template=>$t->id});
    my $ncontent = $share{DB}->count("content",{parent=>$t->id});
    $r->push("&nbsp;&nbsp;&nbsp;&nbsp;"x$level . $ml->a($t->title,{href=>$this->link(id=>$t->id,cmd=>undef)}),
	     $ml->div($npage,{class=>"num"}),
	     $ml->div($ncontent,{class=>"num"}),
	     $t->my_section->label);
    foreach my $data (@$tdata) {
	if ($data->{template} == $t->id) {
	    my $t2 = new ExSite::Template(data=>$data);
	    $this->list_templates_row($r,$t2,$level+1,$tdata);
	}
    }
}

sub show_template_header {
    my ($this,$template) = @_;
    my $out = $this->pathbar($template,linktypes=>"template",section_id=>$this->{section_id});
    $out .= $ui->ToolBar(
	tools=>[
	    $ml->a("overview",{href=>$this->link(cmd=>undef)}).
	    $ml->a("preview",{href=>$template->get_url(),target=>"_blank"}).
	    $ml->a("configure",{href=>$this->link(cmd=>"conf")}),
	    $ml->a("content management",{href=>"$config{server}{CGIpath}/$config{prog}{ctrlpanel}/CMS?cmd=contents&id=".$template->id}),
	    $ml->a("delete",{href=>$this->link(cmd=>"del")})
	]);
    $out .= $ml->h1("Template '".$ml->em($template->title)."'");
    return $out;
}

sub show_template {
    my ($this,$id) = @_;
    my $template = new ExSite::Template(id=>$id);
    return $this->error($template->title . " is not a template") if $template->subtype() ne "template";
    my $out = $this->show_template_header($template);
    if ($this->{is_post}) {
	$out .= $this->set_page_templates();
    }

    # list of pages using this template
    my @cdata = $share{DB}->fetch_match("content",{template=>$id},"sortkey");
    my $r = new ExSite::ReportBuilder();
    $r->nodata("Nothing appears to be using this template.");
    $r->title("Content using this template");
    $r->headers("Label","Type","Status","Change");
    foreach my $cdata (@cdata) {
	my $c = $template->get_content_obj($cdata);
	$r->push($ml->a($c->label,{href=>$c->get_url,target=>"_blank"}),
		 $c->subtype(),
		 $c->showdata("status"),
		 $this->template_dropdown($c));
    }
    $out .= $ml->form($r->make() . $ml->input(undef,{type=>"submit",value=>"Change templates"}),{method=>"post"});

    # summary report of template
    $out .= $ml->h2("Additional Info about '".$ml->em($template->title)."'");
    $out .= $template->report();

    return $out;
}

sub set_page_templates {
    my $this = shift;
    # template_PID = TID
    my $nupdate = 0;
    foreach my $key (keys %{$this->{post}}) {
	if ($key =~ /^template_(\d+)$/) {
	    my $p = new ExSite::Content(id=>$1); # don't really need subtype
	    $p->setdata("template",$this->{post}{$key});
	    $nupdate++ if $p->dirty();
	    $p->save();
	}
    }
    return $nupdate ?
	$ui->SuccessBox(title=>"Templates updated",pane=>"Changed template setting for $nupdate pages.") :
	$this->warn("No templates updated.");
}

sub delete_template {
    my ($this,$id) = @_;
    my $template = new ExSite::Template(id=>$id);
    my $out = $this->show_template_header($template);
    return $this->error("No template selected.") if (!$id);
    if ($this->{input}{confirm}) {
	$template->unpublish();
	$template->delete();
	$ml->location($this->link(__plaintext=>1,id=>undef,cmd=>undef));
	return;
    }
    # list of pages using this template
    my @cdata = $share{DB}->fetch_match("content",{template=>$id},"sortkey");
    if (@cdata > 0) {
	$out .= $this->error("There are pages currently using this template. Please change them to use a different template, first.");
    }
    else {
	$out .= $ui->SuccessBox(title=>"Deletion Permitted",
				pane=>"No pages are currently using this template");
	$out .= $ml->form(
	    $ml->input(undef,{type=>"hidden",name=>"id",value=>$id}).
	    $ml->input(undef,{type=>"hidden",name=>"cmd",value=>"del"}).
	    $ml->input(undef,{type=>"hidden",name=>"confirm",value=>1}).
	    $ml->input(undef,{type=>"submit",value=>"Unpublish &amp; delete"}),
	    {method=>"post"});
    }
    return $out;
}

sub import_template {
    my $this = shift;
    my $out = $this->set_section_id();
    return $out if (! $this->{section_id});
    my $action = $this->link();
    my $wiz = new ExSite::Wizard(action=>$action, reply=>$this->link(__plaintext=>1,cmd=>undef));
    $wiz->add_step("Upload layout",\&wiz_import_template_page1,\&do_wiz_import_template_page1);
    $wiz->add_step("HTML assets",\&wiz_import_template_page2,\&do_wiz_import_template_page2);
    $wiz->add_step("CSS assets",\&wiz_import_template_page3,\&do_wiz_import_template_page3);
    $wiz->add_step("Further Instructions",\&wiz_import_template_page4);
    return $wiz->go();
}

sub wiz_import_template_page1 {
    my $this = shift;
    my $in = shift;
    my $out;
    my $db = $share{DB};

    # switch form to multipart encoding
    $db->{enctype} = "multipart/form-data";

    $out .= $ui->HelpBox(title=>"Instructions",
			 size=>"m",
			 pane=>"Your mock-up template should consist of an HTML file plus numerous assets such as images and stylesheets. First you should upload the HTML file on this screen. On the next screens, you can upload the other assets.");

    $out .= $db->input_html(type=>"hidden",name=>"reply",value=>$this->{reply});
    $out .= $ml->p("Name:".$ml->br.
		   $db->input_html(name=>"name",type=>"text",required=>1));
    $out .= $ml->p("Upload Template HTML file:".$ml->br.
		   $db->input_html(name=>"file",type=>"file",required=>1));
    return $out;
}

sub do_wiz_import_template_page1 {
    my $this = shift;
    my $in = shift;
    my $db = $share{DB};
    my @err;
    if (! $in->{"name"}) {
	push @err, "Please specify a template name.";
    }
    if (! $in->{"file"}) {
	push @err, "No template file uploaded!";
    }
    else {
	my $input = new ExSite::Input;
	$in->{"file"} = $input->fetch_file("file","raw");
    }
    return @err;
}

sub wiz_import_template_page2 {
    my $this = shift;
    my $in = shift;
    my $db = $share{DB};
    $db->{enctype} = "multipart/form-data";
    my %files;
    my $nfile = 0;
    my $out = $ml->p("A scan of the uploaded HTML file shows that it uses 
the following assets.  Please indicate and upload the ones that are required:");

    # get file content
    my $html = $in->{"file"};
    $html =~ s/&#34;/\"/g;
    $html =~ s/&#60;/\</g;
    $html =~ s/&#62;/\>/g;
    my ($origfile,$file);

    if ($html =~ /\[\[\w+?\]\]/ || $html =~ /\{\{\w+?\}\}/ || $html =~ /<!--\$\w+?-->/) {
	return $this->warn("This template appears to already be prepared.");
    }

    my $ipass = 0;
    my $tabout;
    while ($html =~ /src=([^>\s]+)/i) {
	$origfile = $file = $1;
	#$out .= "$origfile<br>\n";
	$file =~ s/[\"\']//g;
	my @file = split /\//,$file;
	# mask attribute so we don't try to do it twice
	# add CMS notation
	$html =~ s/src=$origfile/__src__="\[\[$file[-1]\]\]"/i;
	if (! exists $files{$file[-1]}) {
	    $files{$file[-1]} = 1;
	    $tabout .= $ml->tr(
		$ml->td($ml->input(undef,{type=>"checkbox",name=>"select$nfile",checked=>undef})).
		$ml->td($file[-1]).
		$ml->td($ml->input(undef,{type=>"file",name=>"file$nfile"}))
		);
	    $nfile++;
	}
	$ipass++;
	if ($ipass > 1000) {
	    $tabout .= $ml->tr(
		$ml->td($ml->span("WARNING: bad file reference",{class=>"warning"})).
		$ml->td($file)
		);
	    last;
	}
    }
    $ipass = 0;
    while ($html =~ /<link [^>]*href=([^>\s]+)/i) {
	$file = $1;
	$origfile = &safe_regex($file);
	#$out .= "$origfile<br>\n";
	$file =~ s/[\"\']//g;
	my @file = split /\//,$file;	
	# mask attribute so we don't try to do it twice
	# add CMS notation
	$html =~ s/href=$origfile/__href__="\[\[$file[-1]\]\]"/i;
	if (! exists $files{$file[-1]}) {
	    $files{$file[-1]} = 1;
	    $tabout .= $ml->tr(
		$ml->td($ml->input(undef,{type=>"checkbox",name=>"select$nfile",checked=>undef})).
		$ml->td($file[-1]).
		$ml->td($ml->input(undef,{type=>"file",name=>"file$nfile"}))
		);
	    $nfile++;
	}
	$ipass++;
	if ($ipass > 1000) {
	    $tabout .= $ml->tr(
		$ml->td($ml->span("WARNING: bad file reference",{class=>"warning"})).
		$ml->td($file)
		);
	    last;
	}
    }
    $out .= $ml->table(
	$ml->tr($ml->th("Import").$ml->th("File").$ml->th("Upload")).
	$tabout,
	{class=>"Report"}
	);

    # undo attribute masking
    $html =~ s/__(src|href)__/$1/g;

    # save templated file content
    $in->{"file"} = $html;

    if ($nfile == 0) {
	# no files - clear the page
	$out = $ml->p("No auxiliary files were found in this page.").
	    $ml->p("Click on Finish to complete the import.");
    }

    return $out;
}

sub do_wiz_import_template_page2 {
    my $this = shift;
    #print "content-type: text/html\n\n";
    my $in = shift;
    my $id = $in->{page_id};
    my $db = $share{DB};
    $db->{enctype} = "multipart/form-data";
    $this->unescape_input($in);

    my @err;
    my $input = new ExSite::Input;
    foreach my $key (keys %$in) {
	if ($key =~ /^file(\d+)/) {
	    if ($in->{"select$1"}) {
		if (! $in->{$key}) {
		    push @err, "Missing file - please upload all checked files.";
		    last;
		}
		# replace filehandle with encoded file data
		my $fdata = $input->fetch_file($key);
		$in->{$key} = $fdata;
	    }
	}
    }
    return @err;
}

sub wiz_import_template_page3 {
    my $this = shift;
    my $in = shift;
    my $db = $share{DB};
    $db->{enctype} = "multipart/form-data";
    my %files;
    my $nfile = 0;
    my $out = $ml->p("A scan of the uploaded CSS files show that 
the following additional assets are needed:");
    my $tabout;
    my $ipass = 0;
    my $input = new ExSite::Input();

    # track already-loaded assets
    my (%in2file,%file2in);
    foreach my $infile (keys %$in) {
	if ($infile =~ /^file\d/ && $in->{$infile}) {
	    my ($filename,$mimedata) = split /$config{form}{sepchar}/,$in->{$infile},2;
	    $in2file{$infile} = $filename;
	    $file2in{$filename} = $infile;
	}
    }

    # get new assets
    foreach my $infile (keys %$in) {
	#$out .= "found $in->{$infile}<br>";
	if ($infile =~ /^file\d/) {
	    #$out .= "scanning $in->{$infile}<br>";
	    my ($filename,$mimedata) = split /$config{form}{sepchar}/,$in->{$infile},2;
	    # scan obvious CSS files, and uncertain (no suffix) files
	    if ($filename =~ /\.css$/ || $filename !~ /\./) {
		# can't be certain this is really a CSS file
		#my $css = $input->get_file($infile);
		my $css = &decode_base64($mimedata);
		if ($css =~ /\/\*|[\w-]+:\s*[\w\#]+\;|^\w*\.\w+\s*\{/) {
		    # okay, looks like CSS
		    #$out .= "$in->{$infile} looks like CSS<br>";
		    while ($css =~ /url\((.+?)\)/) {
			my $file = $1;
			my @file = split /\//,$file;
			# remove attribute so we don't try to do it twice
			#$css =~ s/url=\($file\)/__url__=($file)/;
			$css =~ s/url\($file\)//g;
			if (! exists $files{$file[-1]}) {
			    my $input = exists $file2in{$file[-1]} ?
				"already loaded" :
				$ml->input(undef,{type=>"file",name=>"cssfile$nfile"});
			    $files{$file[-1]} = 1;
			    $tabout .= $ml->tr(
				$ml->td($file[-1],{class=>"label"}).
				$ml->td($input)
				);
			    $nfile++;
			}
			$ipass++;
			if ($ipass > 1000) {
			    $tabout .= $ml->tr(
				$ml->td("WARNING: bad file reference",{class=>"label"}).
				$ml->td($file)
				);
			    $out .= $ml->pre($css);
			    last;
			}
		    }
		}
	    }
	}
    }

    $out .= $ml->table(
	$ml->tr($ml->th("File").$ml->th("Upload")).
	$tabout,
	{class=>"Report"}
	);

    if ($nfile == 0) {
	# no files - clear the page
	$out = $ml->p("No additional assets were detected in the CSS files.").
	    $ml->p("Click on Finish to complete the import.");
    }

    return $out;
}

sub do_wiz_import_template_page3 {
    my $this = shift;
    #print "content-type: text/html\n\n";
    my $in = shift;
    my $id = $in->{page_id};
    my $db = $share{DB};
    $db->{enctype} = "multipart/form-data";
    $this->unescape_input($in);
    my @err;

    if (! $in->{"name"} || ! $in->{"file"}) {
	push @err, "Cannot import - missing template!";
    }

=pod
    push @err, "importing template $in->{name} (".(length $in->{file})." bytes)";
    foreach my $key (keys %$in) {
	if ($key =~ /file(\d+)/) {
	    if ($in->{$key}) {
		my ($filename,$mimedata) = split /$config{form}{sepchar}/,$in->{$key},2;
		my $data = &decode_base64($mimedata);
		push @err, "importing asset $filename (".(length $data)." bytes)";
	    }
	}
    }
    return @err;
=cut

    # validation good - create the template

    my $section = new ExSite::Section(id=>$in->{section_id});
    my $template = $section->new_content_obj(type=>"template",
					     label=>$in->{name},
					     parent=>$in->{section_id},
					     content_role=>"design");
    if (! $template->id) {
	push @err, "Failed to create template.";
	push @err, $share{DB}->fetch_diagnostics("error");
	return @err;
    }

    # save the id for next screen
    $this->{new_template_id} = $template->id;

    # layout
    $template->revise(format=>"text",
		      data=>$in->{file},
		      mime_type=>"text/html",
		      note=>"imported using Modules::Template");

    my $input = new ExSite::Input;
    foreach my $key (keys %$in) {
	if ($key =~ /^(css)?file\d+$/ && $in->{$key}) {
	    # insert content object
	    my ($filename,$fdata) = split /$config{form}{sepchar}/,$in->{$key},2;
	    my $content = $template->new_content_obj(type=>"content",
						     label=>$filename,
						     parent=>$template->id,
						     content_role=>"design");
	    if ($content->id) {
		my $mimetype;
		if ($filename =~ /\./) {
		    $mimetype = &MimeType($filename);
		}
		elsif ($fdata =~ /^[[:print:]]+$/) {
		    my $view = new ExSite::View;
		    my $mimetype = $view->guess_mime_type($fdata,"text");
		}
		if ($mimetype =~ /^text\//) {
		    $content->revise(data=>&decode_base64($fdata),
				     format=>"text",
				     mime_type=>$mimetype,
				     note=>"imported using Modules::Template");
		}
		else {
		    $content->revise(data=>$in->{$key},
				     format=>"file",
				     mime_type=>$mimetype,
				     note=>"imported using Modules::Template");
		}
		my @cerr = $content->fetch_diagnostics("error");
		push @err, @cerr if (@cerr > 0);
	    }
	    else {
		push @err, "failed to install $filename";
	    }
	}
    }
    return @err;
}

sub wiz_import_template_page4 {
    my $this = shift;
    my $in = shift;
    my $page_url = $Template->link(id=>$this->{new_template_id},cmd=>undef);
    my $update_url = "$config{server}{CGIpath}/$config{prog}{ctrlpanel}/CMS?id=$this->{new_template_id}";
    my $out = $ml->p("Your template was successfully configured and installed.");
    $out .= $ml->p($ml->strong("Note:").
		   " Most imported templates require some extra configuration, 
which cannot be done automatically.  If your imported template includes 
sample text content, then you need to remove the sample content, and
replace it with a pointer to the content object that will contain the
actual content that goes in its place.");
    $out .= $ml->p("For example, a typical page includes a block of text (HTML) that comprises
the body of the page.  This text should be removed from your template, and
replaced with a tag like this:");
    $out .= $ml->pre("&lt;!--content(body)--&gt;");
    $out .= $ml->p("It may be easiest to do this in the plain-text editor update mode.
You can make similar replacements for other content regions that are 
handled independently of the body.");
    $out .= $ml->p("&rarr; ".$ml->a("Go to the new template.",{href=>$page_url}));
    $out .= $ml->p("&rarr; ".$ml->a("Update the template using the CMS application.",{href=>$update_url}));
    return $out;
}

sub setup_queries {
    my $this = shift;
    my $db = $share{DB};
    $db->set_query("all templates",
		   #sql => "select c.* from content c, content_type t where c.type=t.content_type_id and t.name='template'",  #### order by????
		   sql => "select c.*,count(p.template) npage from content_type t, content c left join content p on p.template=c.content_id where c.type=t.content_type_id and t.name='template' group by p.template order by npage desc",
		   nparam => 0,
		   mode => "r",
		   keys => ["content","content_type"],
	);


}

sub set_section_id {
    my $this = shift;
    my $out;
    if (! $share{Page}) {
	my $ml = &get_obj("ML");
	# only output a site selector on control panels
	my $sid = $this->{input}{section_id} ? $this->{input}{section_id} : 0;
	my @sites = $share{DB}->my_real_sites;
	my $opt;
	foreach my $s (@sites) {
	    my $attr = { value=>$s->{content_id} };
	    if ($s->{content_id} == $sid) { $attr->{selected} = undef; }
	    $opt .= $ml->option($s->{title},$attr);
	}
	$out = 
	    $ml->div(
		$ml->form("Select website: ".
		    $ml->input(undef,{type=>"hidden",name=>"cmd",value=>$this->{input}{cmd}}).
		    $ml->select(
			$ml->option($msg{"== choose a site =="},{value=>"0"}).
			$opt,
			{name=>"section_id", onchange=>"document.forms[0].submit()"}
		    ),
		    {method=>"GET"}
		),
		{class=>"section_selector"}
	    );
    }
    return $out;
}

1;
