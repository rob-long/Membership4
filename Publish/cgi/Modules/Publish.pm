package Modules::Publish;
#----------------------------------------------------------------------------
#   The Publish module is a user-friendly interface to publish.cgi;
#   it also is a shortcut to the publish functions in the content management
#   modules such as Website Manager and MySite.
#-----------------------------------------------------------------------
#
#   Copyright 2001-2006 Exware Solutions, Inc.  http://www.exware.com
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
use ExSite::Module;
use ExSite::Util;
use ExSite::UI;

# inherit from BaseDCD class
use Modules::BaseDCD;
use vars qw(@ISA $ml $ui);
@ISA = qw(Modules::BaseDCD);

# write : this is used to invoke the Publish plug-in from normal site 
# page views.  Typically, this is for the purpose of auto-publishing
# on a pseudo-scheduled basis.  The $options are:
#
# hourly - republish the current page if more than one hour has transpired
#          since the previous publish
# daily - republish the current page if more than one day has transpired
#          since the previous publish
# weekly - republish the current page if more than one week has transpired
#          since the previous publish
# [n] - republish the current page if more than [n] minutes have transpired
#       since the previous publish
#
# Note that publishing does not affect the current page view;  subsequent 
# views can see the newly published page (modulo caching).

sub write {
    my ($this,$options) = @_;
    return undef;
}

sub ioctl {
    my $this = shift;
    $_ = shift;   # $_ is the ioctl request
    if (/ModuleInfo/) {
	return "The Publish plug-in provides a simple interface to ExSite's publishing tools.";
    }
    elsif (/ControlPanel/) {
	return \&ControlPanel;
    }
    elsif (/Category/) {
	return "CMS";
    }
    elsif (/Access/) {
	return 7;
    }
}

sub ControlPanel {
    my $this = shift;
    my $db = $share{DB};
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");

    my $out = $ml->h1("Exsite Publisher");
    #$out .= $ml->p("Click on a website (folder) icon, or a web application icon to publish its files.");

    # sites

    my $nicon;
    my $sout;
    foreach my $site ($db->my_sites) {
	$nicon++;
	my $url = "$config{server}{CGIpath}/publish.cgi?id=$site->{content_id}";
	$sout .= $ml->div(
	    $ml->img(undef,{src=>"$config{server}{HTMLpath}/_ExSite/images/icons/folder.png"}).$ml->a($site->{title},{href=>$url,target=>"publish"}),
	    {class=>"publishSite"}
	    );
    }
    if ($sout) {
	$out .= $ui->BlindBox(
	    title=>"Web Sites",
	    pane=>$ml->p("Use these links to publish your web pages and regular website content.").$ml->div($sout,{class=>"publishSites"}),
	    open=>1,
	    );
    }

    # modules
    my $mout;
    my $section = $this->{input}{section_id} ? "&section_id=$this->{input}{section_id}" : undef;
    foreach my $mod (&ExSite::Module::my_module_list) {
	if (eval("require Modules::$mod")) {
	    my $m = eval("new Modules::$mod");
	    if ($m) {
		if (ref $m->ioctl("Publish") eq "CODE") {
		    $nicon++;
		    my $modname = $m->ioctl('ModuleName') || $mod;
		    my $icon = $m->icon;
		    my $url = "$config{server}{CGIpath}/publish.cgi?module=${mod}$section";
		    $mout .= $ml->div(
			$ml->img(undef,{src=>$icon,height=>16,width=>16}).$ml->a($modname,{href=>$url,target=>"publish"}),
			{class=>"publishModule"}
			);
		}
	    }
        }
    }
    if ($mout) {
	$out .= $ui->BlindBox(
	    title=>"Publish Modules",
	    pane=>$ml->p("Some modules have images or extra files that can be published for better performance. You can publish just those files with these links. These links do not publish webpages displaying these modules; use the top links for that.").$mout,
	    open=>0
	    );
    }
    return $out;
}

1;

