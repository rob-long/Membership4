package Modules::SlideShow;

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
# SlideShow : tool to browse an image library
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
    my $out;

    # set preview height and width depending on preview type

    my $out = &insert_js("jquery","$config{server}{HTMLpath}/_Modules/SlideShow/jquery.bxslider.min.js");
    if (! exists $opt{css} || $opt{css}) {
	$out .= $ml->link(undef,{href=>"$config{server}{HTMLpath}/_Modules/SlideShow/SlideShow.css", rel=>"stylesheet"});
    }
    $out .= &insert_js("\$(document).ready(function(){
  \$('.bxslider').bxSlider({
    auto:true,
//    adaptiveHeight:true,
    captions:true,
  });
});\n");

    # find album
    
    my $id = $opt{id};
    my $c = new ExSite::Content();
    my $lib;
    if ($id) {
	$lib = $c->get_content_obj($id);
    }
    elsif ($opt{name}) {
	my @lib = $share{Page}->my_section()->fetch_libraries();
	my %lib = &keywise("name",\@lib);
	if ($lib{$opt{name}}) {
	    $lib = $c->get_content_obj($lib{$opt{name}});
	    $id = $lib->id;
	}
    }
    else {
	$id = $share{Page}->id;
	$lib = $c->get_content_obj($id);
    }

    # build list of slides

    if ($lib && $lib->defined) {
	my $list;
	my $contents = $lib->get_contents_as_list();
	while (my $img = $contents->next) {
	    my $style;
	    if ($img->revision->is_image && $img->is_indexable) {
		my $opt = { src=>$img->get_url() };
		my $caption = $img->caption();
		if ($caption) { $opt->{title} = $caption; }
		$list .= $ml->li($ml->img(undef,$opt));
	    }
	}
	$out .= $ml->div(
	    $ml->ul($list,{class=>"bxslider"}),
	    {class=>"SlideShow"} 
	    );
    }
    else {
	$out = $this->error("SlideShow: no library specified");
    }
    return $out;
}

sub ioctl {
    my $this = shift;
    $_ = shift;
    if (/ModuleName/) {
	return "SlideShow";
    }
    elsif (/ModuleInfo/) {
	return "The Slide Show tool displays a library of images one at a 
time, with controls to move forward and backward.";
    }
    elsif (/PublishRule/) {
	return "static";
    }
}

1;
