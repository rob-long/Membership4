#!/usr/bin/perl
package Modules::Webtop;
#-----------------------------------------------------------------------
#
#   Copyright 2001-2014 Exware Solutions, Inc.  http://www.exware.com
#
#   This file is part of ExSite WebWare (ExSite, for short).
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

use strict;
use ExSite::Config;
use ExSite::Form;
use ExSite::Misc;
use ExSite::Input;
use ExSite::URI;
use ExSite::Module;
use ExSite::UI;
use Modules::BaseDCD;

# recommended base class for plug-in modules

use Modules::BaseDCD;

# declare package globals

use vars qw(@ISA $ml $ui);

# define our class inheritance

@ISA = qw(Modules::BaseDCD); # inherit from this base class

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
    elsif (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/Category/) {
	return "Overview";
    }
}

#----------------------------------------------------------------------------
# Everything after this point consists of private methods.

# ctrl_panel() generates the contents of the administrator control panel

sub ctrl_panel {
    my $this = shift;
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");

    my @modules = ($share{DB}->level < $config{auth}{level}{admin} && $config{webtop}{whitelist}) ? 
	@{$config{webtop}{whitelist}} :
	&ExSite::Module::module_list;
	
    my $errors;
    my %icongroup;
    my %category = map { $_=>1 } @{$config{webtop}{categories}};
    foreach my $modname (@modules) {
	next if ($modname eq "Webtop");
	my $mod = &ExSite::Module::get_module($modname);
	if ($mod) {
	    my $ctrlpanel = $mod->ioctl("ControlPanel");
	    if ($ctrlpanel) { 
		my $url = ((ref $ctrlpanel) =~ /CODE|ARRAY/) ?
		    "$config{server}{CGIpath}/$config{prog}{admin}/$modname" : 
		    $ctrlpanel;
		my $icon = $ui->Icon(
		    label=>$mod->ioctl('ModuleName')||$modname,
		    img=>&ExSite::Module::icon($modname,$config{iconset}),
		    img_size=>64,
		    url=>"javascript:launchApp('$modname')");
#		    url=>$url);
		my $category = $mod->ioctl('Category') || "Applications";
		if (ref $category eq "ARRAY") {
		    # multiple categories; use first one that already exists
		    foreach my $cat (@$category) {
			if (exists $category{$cat}) {
			    $category = $cat;
			    last;
			}
		    }
		    if (ref $category) {
			# no category selected, take first one
			$category = $category->[0];
		    }
		}
		$icongroup{$category} .= $icon;
	    }
	}
	elsif ($@) {
	    $errors .= $ml->div($@,{class=>"error"});
	}
    }

    # output our various application categories

    my $out = &insert_js("launcher.js");
    my $cat = $config{webtop}{categories};
    my @group = qw(A B);
    my $igroup = 0;
    foreach my $category (@$cat) {
	if (exists $icongroup{$category}) {
	    my $title = $config{webtop}{headings}{$category} || $category;
	    my $gr = $group[$igroup % 2];
	    $out .= $ml->div(
		$ml->h2($msg{$title}).$icongroup{$category},
		{ class=>"iconGroup$gr" }
		);
	    delete $icongroup{$category};
	    $igroup++;
	}
    }
    my $igrp = 0;
    foreach my $group (keys %icongroup) {
	$igrp++;
	$out .= $ml->div(
	    $ml->h1($msg{$group}).$icongroup{$group},
	    { class=> (($igrp % 2) ? "iconGroupA" : "iconGroupB") }
	    );
	delete $icongroup{group};
    }
    if ($errors && $config{debug}) {
	$out .= $ml->div($ui->BasicBox(title=>$msg{"Errors"},pane=>$errors),{style=>"padding:20px;" });
    }

    return $ml->div($out,{class=>"webtop"});
}

1;
