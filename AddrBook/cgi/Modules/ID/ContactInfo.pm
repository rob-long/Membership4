package Modules::ID::ContactInfo;
#-----------------------------------------------------------------------
#
#   Copyright 2001-2014 Exware Solutions, Inc.  http://www.exware.com
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

# Modules::ID::ContactInfo - Member-specific meta-data
# based on ExSite::Attribute

use strict;
use ExSite::Config;
use ExSite::Attribute;
use ExSite::Misc;
use ExSite::Base;

use vars qw(@ISA %allowed);
@ISA = qw(ExSite::Attribute);

sub new {
    my ($this,$table,$id) = @_;
    # NB: $table is ignored, used only for compatibility with Attribute
    my $obj = {};
    my $class = ref($this) || $this;
    bless $obj, $class;
    $obj->setup("contact",$id);
    return $obj;
}

sub setup {
    my ($this,$table,$id) = @_;
    # NB: $table is ignored, used only for compatibility with Attribute
    
    # metadata for this record
    $this->{loaded} = undef;
    $this->{raw} = undef;      # copy of metadata records
    $this->{data} = undef;     # attribute values
    $this->{dirty} = undef;    # flag changed metadata

    # basic defs
    $this->{attr_table} = "contact_info";
    $this->{attr_id} = "contact_info_id";
    $this->{idcol} = "contact_id";
    $this->{table} = "contact";
    $this->{id} = $id;
    $this->{allow_table} = "contact";
    
    $this->load_allowed();
    return;
}

# load_allowed : we get the allowed fields from the dbmap

sub load_allowed {
    my ($this) = @_;
    if (! scalar keys %allowed) {
	my $irank = 0;
	foreach my $fld (split /\|/,$share{DB}{map}->regexp("list:contact_fields")) {
	    my ($datatype,$size);
	    if ($fld =~ /address/) {
		$datatype = "text";
		$size = 200;
	    }
	    else {
		if ($fld eq "email") {
		    $datatype = "email";
		}
		elsif ($fld eq "website") {
		    $datatype = "url";
		}
		else {
		    $datatype = "string";
		}
		$size = ($fld =~ /prov|state|code|phone|fax|cell/) ? 20 : 40;
	    }
	    $allowed{$fld} = { map => { rank=>$irank, datatype=>$datatype, size=>$size } };
	    $irank++;
	}
    }
    $this->{allowed} = \%allowed;
}

sub get_allowed {
    my ($this) = @_;
    return keys %{$this->{allowed}};
}

sub add_allowed {
    my ($this,$name,$options) = @_;
    $this->error("ContactInfo::add_allowed: not supported");
    return undef;
}

sub remove_allowed {
    my ($this,$name,$options) = @_;
    $this->error("ContactInfo::remove_allowed: not supported");
    return undef;
}

sub contact {
    my $this = shift;
    if (! $this->{contact}) {
	$this->{contact} = new Modules::ID::Contact(id=>$this->{id});
    }
    return $this->{contact};
}

# showdata : special privacy logic

sub showdata {
    my ($this,$name) = @_;
    my $out;
    my $val = $this->get($name);
    if ($val) {
	# access is max of contact privacy and contact_info privacy
	my $cpriv = $this->contact->getdata("privacy");
	my $cipriv = $this->{raw}{$name}{privacy};
	my $access = $cpriv > $cipriv ? $cpriv : $cipriv;
	if (! defined $access) { $access = $this->contact->getdata("privacy"); }
	$access = $this->contact->getdata("privacy") if (! defined $access);
	if ($access <= $share{DB}->level) {
	    my $datatype = $this->get_datatype($name);
	    if ($datatype =~ /text|string/) {
		# these fields can be entered by public; sanitize them
		$out = &html_escape($val);
	    }
	    else {
		$out = $share{DB}->show_data_noauth(
		    "contact_info",
		    "value",
		    $val,
		    $this->{raw}{$name}{$this->{attr_id}},
		    $datatype,
		    );
	    }
	}
	# no permission denied msg; act as if data does not exist
    }
    return $out;
}

# generate an input tag to accept attribute values
# NOTE: cannot do foreign key refs in attributes

# DB accessors, for easier overloading
# All low-level DB logic is defined here.

# make_record() - create a datahash suitable for inserting into the DB
# use insert() to actually insert it.

sub validate {
    my ($this,$name,$value) = @_;
    if ($name =~ /country|prov|state/) {
	# ignore help lines
	if ($value =~ /--|==/) {
	    return "please select a $name";
	}
    }
    return $this->SUPER::validate();
}

sub make_record {
    my ($this,$name,$value,$id,$privacy) = @_;
    return { 
	name=>$name, 
	value=>$value, 
	privacy=>$privacy,
	$this->{idcol}=>(defined $id ? $id : $this->{id}), 
	};
}

sub label {
    my ($this,$name) = @_;
    return $msg{ucfirst $name};
}

1;


