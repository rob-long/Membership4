#!/usr/bin/perl
#-----------------------------------------------------------------------
#
#   Copyright 2001-2007 Exware Solutions, Inc.  http://www.exware.com
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

package Modules::Finance::Acctcode;

use strict;
use ExSite::Config;
use ExSite::Object;
use ExSite::Misc;

use vars qw(@ISA);
@ISA = qw(ExSite::Object);

sub setup {
    my ($this,%opt) = @_;
    # preload all account codes for quicker lookups
    if (! $share{account_codes}) {
	my @code = $this->DB->fetch_all("acctcode");
	$share{account_codes}{by_id} = &keywise("acctcode_id",\@code);
	$share{account_codes}{by_code} = &keywise("code",\@code);
    }
    if ($opt{code} || $opt{id}) {
	my $code;
	if ($opt{code} && exists $share{account_codes}{by_code}{$opt{code}}) {
	    $code = $share{account_codes}{by_code}{$opt{code}};
	}
	elsif ($opt{id} && exists $share{account_codes}{by_id}{$opt{id}}) {
	    $code = $share{account_codes}{by_id}{$opt{id}};
	}
	if ($code) {
	    $this->{type} = "acctcode";
	    $this->{id} = $code->{acctcode_id};
	    $this->{data} = $code;
	    $this->{dirty} = 0;
	}
	return;
    }
    return $this->SUPER::setup(%opt);
}

sub my_type { return "acctcode"; }

sub name {
    my $this = shift;
    $this->load() if (!defined $this->{data});
    return $this->{data}{code} || "(undefined accounting code)";
}

sub validate {
    my $this = shift;
    # check for dupes
    my @dup = $this->DB->fetch_match("acctcode",{code=>$this->{data}{code}});
    if (@dup > 1 || $dup[0]->{acctcode_id} != $this->id()) {
	return ("duplicate accounting code found");
    }
    return $this->SUPER::validate();
}

sub delete {
    my $this = shift;
    if ($this->ok) {
	$this->DB()->trash_r($this->{type},$this->{id});
	return 1;
    }
    return undef;
}

sub copy {
    my $this = shift;
    $this->error("copy() not supported for accounting codes");
}

1;

