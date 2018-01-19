package Modules::Gallery;

#----------------------------------------------------------------------------
#
#   Copyright 2015 Exware Solutions, Inc.  http://www.exware.com
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
# Gallery : tool to browse an image library
#
# Options:
# id = library or other container object (defaults to page ID)
# css = include default gallery CSS (defaults to true)
# preview = view type (defaults to thumbnail)
# preview_size = size of preview images (defaults to 65% of preview viewdim)
# view = main view type (defaults to large)
#### view_size = max-size of main view images (defaults to 1024);
#-----------------------------------------------------------------------

use strict;
use ExSite::Config;
use ExSite::Input;
use ExSite::Misc;
use ExSite::Content;
use Modules::BaseDCD;

# inherit basic behaviours from BaseDCD

use vars qw(@ISA);
@ISA = qw(Modules::BaseDCD);

sub write {
    my ($this,$options) = @_;
    my %opt = &DecodeString($options);
    my $db = $share{DB};
    my $ml = &get_obj("ML");
    my $preview_type = $opt{preview} || "thumbnail";
    my $view_type = $opt{view} || "large";
    my $preview_size = $opt{preview_size} || 
	int($config{content}{viewdim}{$preview_type} * .65);
    my $view_size = $opt{view_size} || 1024; ####### not used

    # template for individual gallery photo
    my $item = 
	$ml->li(
	    $ml->a(
		$ml->img(undef,{src=>"[[url_$preview_type]]",alt=>"[[label]]",title=>"[[title]]",class=>"gallery_preview",style=>"[[style]]"}),
		{href=>"[[url_$view_type]]",class=>"gallery_link"}
	    ),
	    {style=>"[[li_style]]"}
	);

    # set preview height and width depending on preview type

    my $script = &insert_js("jquery");
    $script .= $ml->script(undef,{type=>"text/javascript", src=>"$config{server}{HTMLpath}/_Modules/Gallery/Gallery.js"});
    if (! defined $opt{css} || $opt{css}) {
	$script .= $ml->link(undef,{rel=>"stylesheet",type=>"text/css",href=>"$config{server}{HTMLpath}/_Modules/Gallery/Gallery.css"});
    }

    my $id = $opt{id};
    my $c = new ExSite::Content();
    my $lib;
    if (! $id && $share{Page}) {
	if ($opt{name}) {
	    my @lib = $share{Page}->my_section()->fetch_libraries();
	    my %lib = &keywise("name",\@lib);
	    if ($lib{$opt{name}}) {
		$lib = $c->get_content_obj($lib{$opt{name}});
		$id = $lib->id;
	    }
	}
	if (! $id) {
	    $id = $share{Page}->id;
	    $lib = $c->get_content_obj($id);
	}
    }
    if ($lib->defined) {
	my $index;
	my @img;
	my $stylesize = "${preview_size}px";
	my $contents = $lib->get_contents_as_list();
	while (my $img = $contents->next) {
	    my $style;
	    if ($img->revision->is_image && $img->is_indexable) {
		my @dim = $img->revision->view->dim;
		if ($dim[0] < $dim[1]) {
		    # portrait, crop top and bottom
		    $style = "width:$stylesize";
		}
		else {
		    # landscape, crop sides
		    $style = "height:$stylesize";
		}
		$index .= $img->show_formatted($item,
					       style=>$style,
					       li_style=>"height:$stylesize;width:$stylesize",
		    );
	    }
	}
	return $ml->div( $ml->ul($index), {id=>"gallery"} ) . 
	    $ml->div(undef,{id=>"gallery_overlay", style=>"display:none"}) .
	    $ml->div(undef,{id=>"gallery_viewer", style=>"display:none"}) .
	    $script;
    }
    else {
	return $this->error("Gallery: no library specified");
    }
}

sub ioctl {
    my $this = shift;
    $_ = shift;
    if (/ModuleName/) {
	return "Photo Gallery";
    }
    elsif (/ModuleInfo/) {
	return "The Photo Gallery tool allows your website users to browse
through thumbnails of an image library, and select particular images to 
few at full size.";
    }
    elsif (/PublishRule/) {
	return "static";
    }
}

1;
