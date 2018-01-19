#!/usr/bin/perl
#----------------------------------------------------------------------------
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

package Modules::Location::Directory;

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Content;
use Modules::Location::Location;

use vars qw(@ISA $ml);
@ISA = qw(ExSite::Content);

sub my_subtype { return "location_directory"; }

sub show {
    my ($this,%opt) = @_;
    return $this->index(%opt);
}

sub preview {
    my ($this,%opt) = @_;
    $this->{preview} = 1;
    return $this->index(%opt);
}

# map : generate a map with pins for each location

sub map {
    my ($this,%opt) = @_;
    my $out;

    ### TODO

    return $out;
}

# index - display a directory of locations

sub index {
    my ($this,%opt) = @_;
    $this->setup_querylib();
    $ml = &get_obj("ML");
    my $out = $ml->h1($this->title);
    $opt{mode} = "index";
    if ($this->{preview}) {
	$opt{url} = new ExSite::URI();
    }
    if ($opt{sort} =~ /city/) {
	$out .= $this->index_by_city(%opt);
	return $out;
    }
    elsif ($opt{sort} =~ /prov|state/) {
	$out .= $this->index_by_provstate();
	return $out;
    }
    elsif ($opt{sort} =~ /country/) {
	$out .= $this->index_by_country();
	return $out;
    }

    # index by regular sort

    my %done;
    foreach my $loc ($share{DB}->get_query("locations",$this->id)) {
	my $l = new Modules::Location::Location(data=>$loc);
	next if (! $l->is_indexable && ! $this->{preview});
	next if ($done{$l->id});
	$out .= $l->show(%opt,data=>$loc);
	$done{$l->id} = 1;
    }
    return $ml->div($out,{class=>"LocationDirectory"});
}

sub index_by_country {
    my ($this,%opt) = @_;
    my $out;
    my @loc = $share{DB}->get_query("locations by country",$this->id);
    $out .= $this->map(%opt,locations=>\@loc) if ($opt{map});
    my (%country,%done);
    foreach my $loc (@loc) {
	my $l = new Modules::Location::Location(data=>$loc);
	next if (! $l->is_indexable);
	next if ($done{$l->id});
	if (! exists $country{$loc->{country}}) {
	    $out .= $ml->h2($loc->{country});
	    $country{$loc->{country}} = 1;
	}
	$out .= $l->show(%opt,data=>$loc);
	$done{$l->id} = 1;
    }
    return $ml->div($out,{class=>"LocationDirectory"});
}

sub index_by_provstate {
    my ($this,%opt) = @_;
    my $out;
    my @loc = $share{DB}->get_query("locations by provstate",$this->id);
    $out .= $this->map(%opt,locations=>\@loc) if ($opt{map});
    my (%country,%provstate,%done);
    my $show_country = ($loc[0]{country} != $loc[-1]{country});
    foreach my $loc (@loc) {
	my $l = new Modules::Location::Location(data=>$loc);
	next if (! $l->is_indexable);
	next if ($done{$l->id});
	if ($show_country && ! exists $country{$loc->{country}}) {
	    $out .= $ml->h2($loc->{country});
	    $country{$loc->{country}} = 1;
	}
	if (! exists $provstate{$loc->{provstate}}) {
	    $out .= $show_country ? 
		$ml->h3($loc->{provstate}) :
		$ml->h2($loc->{provstate});
	    $provstate{$loc->{provstate}} = 1;
	}
	$out .= $l->show(%opt,data=>$loc);
	$done{$l->id} = 1;
    }
    return $ml->div($out,{class=>"LocationDirectory"});
}

sub index_by_city {
    my ($this,%opt) = @_;
    my $out;
    my @loc = $share{DB}->get_query("locations by city",$this->id);
    $out .= $this->map(%opt,locations=>\@loc) if ($opt{map});
    my (%country,%provstate,%city,%done);
    my $show_country = ($loc[0]{country} != $loc[-1]{country});
    my $show_provstate = ($loc[0]{provstate} != $loc[-1]{provstate});
    foreach my $loc (@loc) {
	my $l = new Modules::Location::Location(data=>$loc);
	next if (! $l->is_indexable);
	next if ($done{$l->id});
	if ($show_country && ! exists $country{$loc->{country}}) {
	    $out .= $ml->h2($loc->{country});
	    $country{$loc->{country}} = 1;
	}
	if ($show_provstate && ! exists $provstate{$loc->{provstate}}) {
	    $out .= $show_country ? 
		$ml->h3($loc->{provstate}) :
		$ml->h2($loc->{provstate});
	    $provstate{$loc->{provstate}} = 1;
	}
	if (! exists $city{"$loc->{city} $loc->{provstate} $loc->{country}"}) {
	    $out .= $show_country ? 
		$ml->h4($loc->{city}) : 
		($show_provstate ? $ml->h3($loc->{city}) : $ml->h2($loc->{city}));
	    $city{"$loc->{city} $loc->{provstate} $loc->{country}"} = 1;
	}
	$out .= $l->show(%opt,data=>$loc);
	$done{$l->id} = 1;
    }
    return $ml->div($out,{class=>"LocationDirectory"});
}

### TODO: include latitude, longitude metadata for locations

sub setup_querylib {
    my $this = shift;

    $share{DB}->set_query("locations by city",
			  sql=>"select content.*,contact.* from content_type,content left join contact on content.content_id=contact.content_id where content_type.name='location' and content_type.content_type_id=content.type and content.parent=? order by contact.country,contact.provstate,contact.city,content.title",
			  nparam=>1,
			  mode=>"r",
			  keys=>["content_type","content","contact"]);
    $share{DB}->set_query("locations by provstate",
			  sql=>"select content.*,contact.* from content_type,content left join contact on content.content_id=contact.content_id where content_type.name='location' and content_type.content_type_id=content.type and content.parent=? order by contact.country,contact.provstate,content.title",
			  nparam=>1,
			  mode=>"r",
			  keys=>["content_type","content","contact"]);
    $share{DB}->set_query("locations by country",
			  sql=>"select content.*,contact.* from content_type,content left join contact on content.content_id=contact.content_id where content_type.name='location' and content_type.content_type_id=content.type and content.parent=? order by contact.country,contact.provstate,content.title",
			  nparam=>1,
			  mode=>"r",
			  keys=>["content_type","content","contact"]);
    $share{DB}->set_query("locations",
			  sql=>"select content.*,contact.* from content_type,content left join contact on content.content_id=contact.content_id where content_type.name='location' and content_type.content_type_id=content.type and content.parent=? order by coalesce(content.sortkey,content.title)",
			  nparam=>1,
			  mode=>"r",
			  keys=>["content_type","content","contact"]);

}

1;
