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

package Modules::QA::Library;

use strict;
use ExSite::Config;
use ExSite::Base;
use ExSite::Form;
use ExSite::Misc;
use ExSite::Object;
use ExSite::ObjectList;
use Modules::QA::Form;

use vars qw(@ISA);
@ISA = qw(ExSite::Object);

sub my_type { return "qa_lib"; }

sub name {
    my $this = shift;
    $this->load() if (!defined $this->{data});
    return $this->showdata("title");
}

sub count_questions {
    my $this = shift;
    if ($this->loaded()) {
	return $this->{list}->count();
    }
    return undef;
}

sub questions {
    my $this = shift;
    if ($this->loaded()) {
	return $this->{list};
    }
    return undef;
}

#=== DISPLAY

sub show {
    my ($this,%opt) = @_;
    if ($this->ok) {
	if ($this->loaded()) {
	    my $name = ucfirst $this->name;
	    if (! $this->{data}) {
		return $this->error("$name does not exist.");
	    }
	    elsif (! $this->{list}) {
		return $this->error("$name has no questions.");
	    }
	    else {
		# library of questions; display as a simple report
		return $this->show_questions(%opt);
	    }
	}
    }
    return $this->error($this->{status});
}

sub show_questions {
    my ($this,%opt) = @_;
    my $out;
    my $table = $this->{type};

    my $r = new ExSite::ReportBuilder(title=>$this->name,
				      nodata=>"No questions found." );
    $r->headers(["ID","Question","Format","Input Responses"]);
    my $ml = &get_obj("ML");

    my $questions = $this->questions();
    if ($questions) {
	while (my $q = $questions->next()) {
	    $opt{url}->parameter(qb=>$q->id) if $opt{url};
	    $r->push(
		     $q->id,
		     $opt{url} ? 
		         $ml->a($q->showdata("label"),{href=>$opt{url}->write()}) :
		         $q->showdata("label"),
		     $q->showdata("format"),
		     $q->showdata("value"),
		     );
	}
    }
    return $r->make;
}

#=== DB

# load record : can pass an ID or a datahash

sub load {
    my ($this,$data) = @_;
    $this->{list} = undef;
    if ($this->SUPER::load($data)) {
	my $list =  new ExSite::ObjectList(type=>"qa_base");
	my @qb = $share{DB}->fetch_match("qa_base",{qa_lib_id=>$this->id});
	foreach my $q (@qb) {
	    if (! $q->{version}) { 
		$list->push($q);
	    }
	}
	$list->sort("label");
	$this->{list} = $list;
    }
    return $this->{data};
}

sub loaded {
    my $this = shift;
    return $this->load() if (! $this->{data} || ! $this->{list});
    return $this->{data};
}

sub copy {
    my $this = shift;
    return $this->warn("Copying of question libraries is not supported.");
}

1;
