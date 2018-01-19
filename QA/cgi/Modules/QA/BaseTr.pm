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

package Modules::QA::BaseTr;

use strict;
use ExSite::Object;
use Modules::QA::Base;

use vars qw(@ISA);
@ISA = qw(ExSite::Object);

sub my_type { return "qa_translation"; }

#=== DISPLAY

sub show {
    my ($this,%opt) = @_;
    if ($this->ok) {
	if ($this->defined()) {
	    my $version = $this->getdata("version");
	    my $q = new Modules::QA::Base(id=>$this->getdata("qa_base_id"));
	    return $q->show(version=>$version);
	}
    }
    return $this->error($this->{status});
}

1;

