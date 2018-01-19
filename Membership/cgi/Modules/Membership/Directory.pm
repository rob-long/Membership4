#!/usr/bin/perl
#-----------------------------------------------------------------------
#
#   Copyright 2011 Exware Solutions, Inc.  http://www.exware.com
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

package Modules::Membership::Directory;

use strict;
use ExSite::Config;
use ExSite::Content;

use vars qw(@ISA);
@ISA = qw(ExSite::Content);

sub my_subtype { return "member_directory"; }

sub tools {
    my ($this,%opt) = @_;

    ### TODO: search?

}

sub index {
    my ($this,%opt) = @_;
    my $out;
    my $ml = &get_obj("ML");
    foreach my $p ($this->get_contents("profile")) {
	$out .= $p->summary();
    }
    return $out;
}

sub post {
    my ($this,%opt) = @_;
    # post not accepted
    return undef;
}

sub allow_post {
    my ($this) = @_;
    return undef;
}

sub report {
    my ($this,%opt) = @_;
    if ($this->defined()) {

	### report membership stats???

    }
    return undef;
}

