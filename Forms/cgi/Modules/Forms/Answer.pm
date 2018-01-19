#!/usr/bin/perl
#-----------------------------------------------------------------------
#
#   Copyright 2001-2009 Exware Solutions, Inc.  http://www.exware.com
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

package Modules::Forms::Answer;

use strict;
use ExSite::Config;
use ExSite::Base;
use ExSite::Form;
use ExSite::Misc;
use ExSite::Util;
use ExSite::Object;
use Modules::Forms::Response;
use Modules::Forms::Question;

use vars qw(@ISA);
@ISA = qw(ExSite::Object);

sub my_type { return "answer"; }

sub name {
    my $this = shift;
    return $this->value() || "[n/a]";
}

sub value {
    my $this = shift;
    return $this->loaded() ? $this->getdata("value") : undef;
}

sub response {
    my $this = shift;
    return $this->loaded() ? new Modules::Forms::Response(id=>$this->getdata("reponse_id")) : undef;
}

sub question {
    my $this = shift;
    return $this->loaded() ? new Modules::Forms::Question(id=>$this->getdata("question_id")) : undef;
}

#=== DISPLAY

sub show {
    my ($this,%opt) = @_;
    if ($this->ok) {
	#if ($opt{version}) { $this->set("version",$opt{version}); } ###### ?
	if ($this->loaded()) {
	    my $value = $this->value();
	    if ($value && $this->question->format eq "file") {
		my $ml = &get_obj("ML");
		my $filepath = $value;
		my $size = -s $filepath;
		$filepath =~ s/^$config{server}{fileroot}//;
		my $anchor;
		my $mime = &MimeType($filepath);
		my $src = "$config{server}{CGIpath}/$config{prog}{file}$filepath";
		if ($mime =~ /^image/) {
		    $anchor = $ml->img(undef,{src=>$src,style=>"max-width:150px"});
		}
		else {
		    my @path = split /\//,$filepath;
		    $anchor = $path[-1];
		    my $size_kb => int($size/100)/10;
		    my $size_mb => int($size/100000)/10;
		    if ($size_mb > 1) { $size = "$size_mb MB"; }
		    elsif ($size_kb > 1) { $size = "$size_kb kB"; }
		    else { $size = "$size bytes"; }
		    $anchor .= " (".&MimeDescr($mime).", $size)";
		}
		return $ml->a($anchor,{href=>"$config{server}{CGIpath}/$config{prog}{file}$filepath",target=>"_blank"});
	    }
	    my $datatype = $this->question->datatype;
	    if ($datatype) {
		# use show_data for its security 
		# (eg. masking tags)
		return $this->DB()->show_data_noauth("answer",
						     "value",
						     $value,
						     $this->{id},
						     $datatype);
	    }
	    else {
		return $value;
	    }
	}
	else {
	    return $this->error("Answer does not exist.");
	}
    }
    # not ok means no ID, ie. no answer was recorded for this question
    #return "[no answer]";
    return exists $opt{na} ? $opt{na} : "[n/a]";
}

### FIXME: show answers in orginal language

sub copy {
    my $this = shift;
    # can't copy individual answers - try Response::copy() instead
    return undef;
}

# delete: should files be uninstalled?
# not for now; makes trash recovery impossible
# a files utility can clear out unused files, if necessary

sub uninstall_file {
    my $this = shift;
    if ($this->question->format eq "file") {
	my $fpath = $this->value();
	if ($fpath && -e $fpath) {
	    $fpath =~ s/^$config{server}{fileroot}//;
	    $this->audit("uninstalling $fpath");
	    &run_publisher(install=>$fpath,unpublish=>1)
	}
    }
}

sub delete_old {
    my $this = shift;
    $this->uninstall_file();
    return $this->SUPER::delete();
}

1;


