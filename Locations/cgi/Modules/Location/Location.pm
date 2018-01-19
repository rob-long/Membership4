#!/usr/bin/perl
#-----------------------------------------------------------------------
#
#   Copyright 2014 Exware Solutions, Inc.  http://www.exware.com
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

package Modules::Location::Location;

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Content;
#use Modules::ID::Contact;

use vars qw(@ISA);
@ISA = qw(ExSite::Content);

# my_subtype - the subtype of this object/class

sub my_subtype { return "location"; }

sub filename {
    my $this = shift;
    if ($this->exists) {
	return $this->getdata("name").".html";
    }
    return undef;
}

sub show {
    my ($this,%opt) = @_;
    if (-e "$config{server}{CGIroot}/$share{DB}{map}{name}/AddrBook/contact") {
	$this->{show_contacts} = 1;
	require Modules::ID::Contact;
	&ExSite::Module::read_dbmap("AddrBook");
    }
    if ($opt{mode} eq "index") {
	return $this->show_item(%opt);
    }
    my $out;
    my $ml = &get_obj("ML");
    $out .= $ml->h1($this->title);

    # special writeup
    if ($this->has_revisions()) {
	$out .= $this->revision->show();
    }

    # contacts
    my $map;
    my $contacts = $this->contacts();
    if ($contacts) {
	while (my $c = $contacts->next) {
	    if ($c->allow) {
		$out .= $c->show();
	    }
	    if (! $map) {
		my %info = $c->get_info();
		if ($info{address}) {
		    $map = $this->map(contact=>$c);
		}
	    }
	}
    }

    if ($map) {
	$out .= $map;
    }

    return $ml->div($out,{class=>"Location"});
}

### Q: what is this used for??
sub show_item {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    my $url;
    if ($opt{url}) {
	$opt{url}->parameter("id",$this->id);
	$url = $opt{url}->write();
    }
    else {
	$url = $this->get_url();
    }
    my $out = $ml->div($ml->a($this->title,{href=>$url}),{class=>"locationTitle"});
    if ($this->{show_contacts}) {
	my $contact = new Modules::ID::Contact();
	if ($opt{data}{contact_id}) {
	    # contact info has been passed to us
	    $contact->setup(data=>$opt{data});
	}
	else {
	    # pick an appropriate contact record
	    my $cdata;
	    my @contact = $share{DB}->fetch_child("contact","content",$this->id);
	    if (scalar @contact == 1) {
		# only one to choose from
		$cdata = $contact[0];
	    }
	    else {
		my %contact = &keywise("type",\@contact);
		$cdata = $contact{main} || $contact{office} || $contact{billing};
		if (! $cdata) {
		    $cdata = (values %contact)[0];
		}
	    }
	    $contact->setup(data=>$cdata);
	}
	$out .= $contact->show() if $contact->defined();
    }
    return $ml->div($out,{class=>"LocationItem"});
}

sub summary {
    my $this = shift;
    my $ml = &get_obj("ML");
    my $out .= $ml->div($ml->a($this->title,{href=>$this->get_url()}),{class=>"locationTitle"});
    my $contacts = $this->contacts();
    if ($contacts && $contacts->count) {
	$out .= $ml->div($contacts->first->show_address(),{class=>"locationAddress"});
    }
    return $ml->div($out,{class=>"Location"});
}

sub preview {
    my ($this,%opt) = @_;
    $this->{preview} = 1;
    return $this->show(%opt);
}

sub map {
    my ($this,%opt) = @_;
    my $out;
    my $url = $this->map_url(%opt);
    if ($url) {
	my $ml = &get_obj("ML");
	return $ml->div($ml->img(undef,{src=>$url}),{class=>"locationMap"});
    }
    return $out;
}

sub map_url {
    my ($this,%opt) = @_;
    my $lat = $this->meta->get("latitude");
    my $lon = $this->meta->get("longitude");
    my $size = $opt{size} || "400x400";
    my $maptype = $opt{maptype} || "roadmap";
    my $zoom = $opt{zoom} || 15;
    # new sites need a key; old sites may be grandfathered
    my $key = $config{GoogleMapAPIkey} ? "&key=$config{GoogleMapAPIkey}" : "";
    if ($lat && $lon && abs($lat) > 0.0 && abs($lon) > 0.0) {
	# location is explicitly defined
	return "$config{server}{protocol}://maps.googleapis.com/maps/api/staticmap?center=$lat,$lon&size=$size&maptype=$maptype&sensor=false&zoom=$zoom&markers=color:blue%7Clabel:A%7C$lat,$lon$key";
    }
    else {
	# location is undefined, let Google guess based on address
	my $c = $opt{contact};
	if (! $c) {
	    my $contacts = $this->contacts();
	    if ($contacts && $contacts->count()) {
		while (my $c2 = $contacts->next) {
		    my %info = $c->get_info();
		    if ($info{address}) {
			# skip contact records with no street address
			$c = $c2; last;
		    }
		}
		$contacts->reset;
	    }
	}
	if ($c) {
	    my $addr = $c->show_address_abbr();
	    if ($addr) {
		my $urladdr = &url_escape($addr);
		return "$config{server}{protocol}://maps.googleapis.com/maps/api/staticmap?center=$urladdr&size=$size&maptype=$maptype&sensor=false&zoom=$zoom&markers=color:blue%7Clabel:A%7C$urladdr$key";
	    }
	}
    }
    return undef;
}

sub contacts {
    my ($this) = @_;
    if (! $share{DB}{map}->is_mapped("contact")) {
	require Modules::ID::Contact;
	&ExSite::Module::read_dbmap("AddrBook");
    }
    my @contactdata = $share{DB}->fetch_child("contact","content",$this->id);
    my $contacts = new ExSite::ObjectList(list=>\@contactdata,type=>"contact");
    return $contacts;
}

# contact_field - returns first defined contact field (eg. city, phone)

sub contact_field {
    my ($this,$field) = @_;
    my $contacts = $this->contacts();
    $contacts->reset;
    while (my $c = $contacts->next) {
	my $val = $c->meta_show($field);
	return $val if $val;
    }
    return undef;
}

### publish to geographical subdirs

# sub my_subdir {
# }

1;
