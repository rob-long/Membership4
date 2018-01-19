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

package Modules::ID::Contact;

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Object;

use vars qw(@ISA @field_order %field_pref %field_size %field_type %field_prompt %regex);
@ISA = qw(ExSite::ObjectMeta);

@field_order = ("address","city","provstate","country","pcode","phone","cell","fax","email","website");
%field_size = (
    address=>200,
    city=>40,
    provstate=>4,
    province=>4,
    state=>4,
    country=>20,
    pcode=>10,
    "postal code"=>10,
    "zip code"=>10,
    phone=>20,
    cell=>20,
    fax=>20,
    email=>40,
    website=>40);
%field_pref = (
    address=>"address",
    city=>"city",
    provstate=>"provstate",
    country=>"country",
    pcode=>"pcode",
    phone=>"phone",
    cell=>"cell",
    fax=>"fax",
    email=>"email",
    website=>"website");
%field_type = (
    address=>"textarea",
    city=>"text",
    provstate=>"select",
    province=>"select",
    state=>"select",
    country=>"select",
    pcode=>"text",
    "postal code"=>"text",
    "zip code"=>"text",
    phone=>"text",
    cell=>"text",
    fax=>"text",
    email=>"text",
    website=>"text");
%field_prompt = (
    pcode=>"Postal or Zip Code",
    provstate=>"Province/State",
    email=>"E-mail address",
    website=>"Web Site URL",
    );
%regex = (
    provstate => "==Canada==|AB|BC|MB|NB|NL|NS|NT|NU|ON|PE|QC|SK|YT|==USA==|AK|AL|AR|AS|AZ|CA|CO|CT|DC|DE|FL|GA|GU|HI|IA|ID|IL|IN|KS|KY|LA|MA|MD|ME|MI|MN|MO|MR|MS|MT|NC|ND|NE|NH|NJ|NM|NN|NV|NY|OH|OK|OR|PA|PL|PO|PR|RI|SC|SD|TN|TT|TX|UT|VA|VI|VT|WA|WI|WV|WY",
    province => "AB|BC|MB|NB|NL|NS|NT|NU|ON|PE|QC|SK|YT",
    state => "AK|AL|AR|AS|AZ|CA|CO|CT|DC|DE|FL|GA|GU|HI|IA|ID|IL|IN|KS|KY|LA|MA|MD|ME|MI|MN|MO|MR|MS|MT|NC|ND|NE|NH|NJ|NM|NN|NV|NY|OH|OK|OR|PA|PL|PO|PR|RI|SC|SD|TN|TT|TX|UT|VA|VI|VT|WA|WI|WV|WY",
    country => "Canada|United States|---|Afghanistan|Albania|Algeria|American Samoa|Andorra|Angola|Anguilla|Antarctica|Antigua and Barbuda|Argentina|Armenia|Aruba|Australia|Austria|Azerbaijan|Bahamas|Bahrain|Bangladesh|Barbados|Belarus|Belgium|Belize|Benin|Bermuda|Bhutan|Bolivia|Bosnia and Herzegowina|Botswana|Bouvet Island|Brazil|British Indian Ocean Territory|Brunei Darussalam|Bulgaria|Burkina Faso|Burundi|Cambodia|Cameroon|Cape Verde|Cayman Islands|Central African Republic|Chad|Chile|China|Christmas Island|Cocos (Keeling) Islands|Colombia|Comoros|Congo|Congo, the Democratic Republic of the|Cook Islands|Costa Rica|Cote d'Ivoire|Croatia (Hrvatska)|Cuba|Cyprus|Czech Republic|Denmark|Djibouti|Dominica|Dominican Republic|East Timor|Ecuador|Egypt|El Salvador|Equatorial Guinea|Eritrea|Estonia|Ethiopia|Falkland Islands (Malvinas)|Faroe Islands|Fiji|Finland|France|France, Metropolitan|French Guiana|French Polynesia|French Southern Territories|Gabon|Gambia|Georgia|Germany|Ghana|Gibraltar|Greece|Greenland|Grenada|Guadeloupe|Guam|Guatemala|Guinea|Guinea-Bissau|Guyana|Haiti|Heard and Mc Donald Islands|Holy See (Vatican City State)|Honduras|Hong Kong|Hungary|Iceland|India|Indonesia|Iran|Iraq|Ireland|Israel|Italy|Jamaica|Japan|Jordan|Kazakhstan|Kenya|Kiribati|Korea, Democratic People's Republic of|Korea, Republic of|Kuwait|Kyrgyzstan|Lao People's Democratic Republic|Latvia|Lebanon|Lesotho|Liberia|Libyan Arab Jamahiriya|Liechtenstein|Lithuania|Luxembourg|Macau|Macedonia, The Former Yugoslav Republic of|Madagascar|Malawi|Malaysia|Maldives|Mali|Malta|Marshall Islands|Martinique|Mauritania|Mauritius|Mayotte|Mexico|Micronesia, Federated States of|Moldova, Republic of|Monaco|Mongolia|Montserrat|Morocco|Mozambique|Myanmar|Namibia|Nauru|Nepal|Netherlands|Netherlands Antilles|New Caledonia|New Zealand|Nicaragua|Niger|Nigeria|Niue|Norfolk Island|Northern Mariana Islands|Norway|Oman|Pakistan|Palau|Panama|Papua New Guinea|Paraguay|Peru|Philippines|Pitcairn|Poland|Portugal|Puerto Rico|Qatar|Reunion|Romania|Russian Federation|Rwanda|Saint Kitts and Nevis|Saint Lucia|Saint Vincent and the Grenadines|Samoa|San Marino|Sao Tome and Principe|Saudi Arabia|Senegal|Seychelles|Sierra Leone|Singapore|Slovakia (Slovak Republic)|Slovenia|Solomon Islands|Somalia|South Africa|South Georgia and the South Sandwich Islands|Spain|Sri Lanka|St. Helena|St. Pierre and Miquelon|Sudan|Suriname|Svalbard and Jan Mayen Islands|Swaziland|Sweden|Switzerland|Syrian Arab Republic|Taiwan|Tajikistan|Tanzania, United Republic of|Thailand|Togo|Tokelau|Tonga|Trinidad and Tobago|Tunisia|Turkey|Turkmenistan|Turks and Caicos Islands|Tuvalu|Uganda|Ukraine|United Arab Emirates|United Kingdom|United States Minor Outlying Islands|Uruguay|Uzbekistan|Vanuatu|Venezuela|Viet Nam|Virgin Islands (British)|Virgin Islands (U.S.)|Wallis and Futuna Islands|Western Sahara|Yemen|Yugoslavia|Zambia|Zimbabwe",
    email => "[\w](\.?[\-\w\+]+)*@([\-\w]+\.)+[A-Za-z]",
    website => "(https?://)?.+\..+",
    );

sub my_type { "contact"; }

sub setup {
    my ($this,%opt) = @_;
    $this->{metaclass} = "Modules::ID::ContactInfo";
    my $provstate = $opt{provstate} || $config{Contact}{provstate};
    if ($provstate) { $field_pref{provstate} = $provstate; }
    my $pcode = $opt{pcode} || $config{Contact}{pcode};
    if ($pcode) { $field_pref{pcode} = $pcode; }
    $this->SUPER::setup(%opt);
    return;
}

sub name {
    my $this = shift;
    $this->load() if (!defined $this->{data});
    return $this->{data}{name} || $this->{data}{type};
}

sub contact_name {
    my $this = shift;
    if ($this->defined) {
	if ($this->{data}{account_id}) {
	    my $acct = $share{DB}->fetch("account",$this->{data}{account_id});
	    return $acct->{name};
	}
	elsif ($this->{data}{content_id}) {
	    my $loc = $share{DB}->fetch("content",$this->{data}{content_id});
	    return $loc->{title};
	}
	else {
	    return $this->name;
	}
    }
    return undef;
}

sub subscribed {
    my $this = shift;
    my $sub = $this->getdata("subscribe");
    return $sub if $sub;
    my $uid = $this->uid();
    if ($uid) {
	my $user = new ExSite::User(id=>$uid);
	return $user->getdata("subscribe");
    }
    return undef;
}

sub showauth { 
    my ($this,$key) = @_;
    return 1;
}

sub uid {
    my ($this,$account_id) = @_;
    $account_id or $account_id = $this->getdata("account_id");
    # no explicit match criteria; match against current user
    if ($account_id) {
	my $account = $share{DB}->fetch("account",$account_id);
	return (ref $account eq "HASH") ? $account->{uid} : undef;
    }
}

sub section_id {
    my $this = shift;
    if ($this->loaded()) {
	my $data = $this->get();
	if ($data->{content_id}) {
	    my $c = new ExSite::Content(id=>$data->{content_id});
	    return $c->my_section()->id();
	}
	elsif ($data->{account_id}) {
	    my $a = new Modules::Finance::Account(id=>$data->{account_id});
	    return $a->section_id();
	}
    }
    return undef;
}

sub is_my_contact { 
    my ($this,$account_id,$content_id) = @_;
    my $acct = $this->getdata("account_id");
    my $loc = $this->getdata("content_id");

    # explicit match criteria
    if ($account_id) {
	return 1 if ($acct == $account_id);
    }
    if ($content_id) {
	return 1 if ($loc == $content_id);
    }
    return 0 if ($account_id || $content_id);

    # no explicit match criteria; match against current user
    if ($acct) {
	return 1 if ($session{account} == $acct);
	my $invid = $session{last_invoice} || $session{invoice};
	if ($invid) {
	    my $inv = $share{DB}->fetch("receivable",$invid);
	    return 1 if ($inv && $inv->{account_id} == $acct);
	}
	my $uid = $share{DB}->my_uid();
	return 1 if ($uid && $uid == $this->uid($acct));
    }
    if ($loc) {
	my $content = new ExSite::Content(id=>$loc);
	$content = $content->get_content_obj();
	return 1 if ($content->has_role($share{DB}->my_uid,"owner"));
    }
    return 0;
}

sub allow {
    my $this = shift;
    my $privacy = $this->getdata("privacy");
    if (! $privacy) {
	return 1;
    }
    else {
	my $level = $share{DB}->level();
	if ($privacy > $level) {
	    # not allowed in any case
	    return 0;
	}
	else {
	    my $site = $share{DB}->this_site();
	    if (! $site) {
		return $share{DB}->user_owns($this->{type},$this->{data});
	    }
	    if ($this->getdata("content_id")) {
		my $c = new ExSite::Content(id=>$this->getdata("content_id"));
		if ($site && $site->{content_id} == $c->my_section()->id()) {
		    return ($privacy <= $level);
		}
		else {
		    # wrong section; deny snooping
		    return 0;
		}
	    }
	    elsif ($this->getdata("account_id")) {
		if ($this->is_my_contact) {
		    return 1;
		}
		elsif ($this->section_id == $site->{content_id}) {
		    # contact record belongs to this section
		    return ($privacy <= $level);
		}
		else {
		    # admin/owner override
		    return $share{DB}->user_owns($this->{type},$this->{data});
		}
	    }
	}
    }
    return 0;
}

# get_info: get all the raw contact info that the user is permitted to see

sub get_info {
    my $this = shift;
    my %info;
    foreach my $name ($this->meta()->get_allowed()) {
	my $value = $this->meta_get($name);
	if ($value) {
	    $info{$name} = $value;
	}
    }
    return wantarray ? %info : \%info;
}

# show_info: same, but format data for display

sub show_info {
    my $this = shift;
    my %info;
    foreach my $name ($this->meta()->get_allowed()) {
	my $value = $this->meta_show($name);
	if ($value) {
	    $info{$name} = $value;
	}
    }
    return wantarray ? %info : \%info;
}

sub show {
    my ($this,%opt) = @_;
    if ($this->loaded) {
	# privacy check
	if (! $this->allow()) {
	    $this->warn("Show contact info: permission denied.");
	    return undef;
	}

	my $input = new ExSite::Input;
	my $in = $input->combine();
	if ($in->{vcard} && $in->{vcard} == $this->id) {
	    my $p = $share{Page} || $share{ML};
	    $p->cancel;
	    print "Content-type: text/x-vcard\ncontent-disposition: attachment; filename=contact.vcf\n\n";
	    print $this->vcard;
	    return;
	}

	# addr card is in 5 parts:
	# 1) name/identity
	# 2) mailing/street address
	# 3) telephone info
	# 4) net info
	# 5) addenda/notes

	my (@identity,@address,@telephone,@internet,@addenda);

	my $ml = new ExSite::ML;
	#my $c = $this->meta()->get_all();
	my $c = $this->show_info();

	my $out;
	if ($opt{title}) {
	    my $name;
	    if ($opt{title} != 1) {
		$name = $opt{title};
	    }
	    else {
		$name = $opt{name} ? $opt{name} : $this->contact_name();
	    }
	    push @identity, $name;
	}
	push @address, $this->show_address(data=>$c);

	if ($c->{phone}) {
	    push @telephone, $msg{TEL}.": ".$c->{phone};
	}
	if ($c->{cell}) {
	    push @telephone, $msg{CELL}.": ".$c->{cell};
	}
	if ($c->{fax}) {
	    push @telephone, $msg{FAX}.": ".$c->{fax};
	}
	if ($c->{email}) {
	    push @internet, $msg{"E-mail"}.": ".$c->{email};
	}
	if ($c->{website}) {
	    push @internet, $msg{"Website"}.": ".$c->{website};
	}
	if ($c->{notes}) {
	    push @addenda, $msg{"Notes"}.": ".$c->{notes};
	}

	if (@identity > 0) {
	    $out .= $ml->p(join($ml->br,@identity),{class=>"ContactInfo"});
	}
	if (@address > 0) {
	    $out .= $ml->p(join($ml->br,@address),{class=>"ContactAddress"});
	}
	if (@telephone > 0) {
	    $out .= $ml->p(join($ml->br,@telephone),{class=>"ContactPhone"});
	}
	if (@internet > 0) {
	    $out .= $ml->p(join($ml->br,@internet),{class=>"ContactNet"});
	}
	if (@addenda > 0) {
	    $out .= $ml->p(join($ml->br,@addenda),{class=>"ContactNotes"});
	}
	if ($opt{plaintext}) {
	    $out = $ml->p($out);  #??
	    return &html_to_plaintext($out);
	}
	if ((ref $opt{vcard}) =~ /URI/) {
	    $opt{vcard}->parameter("vcard",$this->id);
	    my $url = $opt{vcard}->write();
	    $out .= $ml->p(
		$msg{"Vcard"}.": ".
		$ml->a($msg{"import to my address book"},{href=>$url,class=>"vcard"}),
		{class=>"ContactVcard"}
		);
	}
	return $ml->div($opt{head}.$out.$opt{foot},{class=>"Contact"});
    }
    return $this->error($this->{status});
}

# only show address fields, as if for a mailing label
sub show_address {
    my ($this,%opt) = @_;
    if ($this->defined) {
	my $ml = new ExSite::ML;
	my $c = $opt{data} || $this->show_info();
	my $addr;
	my $name = $this->contact_name();
	if ($name) {
	    $addr .= $ml->span($name,{class=>"ContactInfo"}).$ml->br;
	}
	if ($c->{address}) { 
	    my $br = $ml->br;
	    my $address = $c->{address};
	    $address =~ s/\s+$//;  # trim trailing whitespace
	    $address =~ s/\r?\n/$br/;  # preserve linebreaks
	    $addr .= $address.$br;
	}

	my @citystate;
	my $info = $c->{city};
	push @citystate, $info if $info;
	$info = $c->{provstate} || $c->{province} || $c->{state};
	if ($info) {
	    push @citystate, $info;
	}
	if (scalar @citystate > 0) {
	    $addr .= @citystate > 0 ? join(", ",@citystate).$ml->br : "";
	}

	my @countrycode;
	$info = $c->{country};
	push @countrycode, $info if $info;
	$info = $c->{pcode} || $c->{"postal code"} || $c->{"zip code"};
	if ($info) {
	    push @countrycode, $info;
	}
	if (scalar @countrycode > 0) {
	    $addr .= @countrycode > 0 ? join("  ",@countrycode).$ml->br : "";
	}

	return $opt{plaintext} ? &html_to_plaintext($addr) : $addr;
    }
    return $this->error($this->{status});
}

# show an abbreviated 1-line address for reports

sub show_address_abbr {
    my ($this,%opt) = @_;
    if ($this->defined) {
	#my $c = $this->meta()->get_all();
	my $c = $this->show_info();
	my @addr;
	if ($c->{address}) { push @addr, $c->{address}; }
	if ($c->{city}) { push @addr, $c->{city}; }
	my $provstate = $c->{provstate} || $c->{province} || $c->{state};
	if ($provstate) { push @addr, $provstate; }
	# country and postal code are optional
	if ($opt{country} && $c->{country}) { push @addr, $c->{country}; }
	if ($opt{pcode}) {
	    my $pcode = $c->{pcode} || $c->{"postal code"} || $c->{"zip code"};
	    if ($pcode) { push @addr, $pcode; }
	}
	return join ", ", @addr;
    }
    return undef;
}

# simple vcard implementation

sub vcard {
    my ($this,%opt) = @_;
    my $c = $this->get_info();
    return undef if (scalar keys %$c == 0); # no permission to view

    my $type = "X-" . uc $this->getdata("type");
    my @vcard;
    push @vcard, "VERSION:3.0";

    # full name
#    push @vcard, "N:".$this->contact_name();  # required for strict compliance with RFC
    push @vcard, "FN:".$this->contact_name();

    # email
    if ($c->{email}) {
	push @vcard, "EMAIL;TYPE=INTERNET;TYPE=$type;TYPE=PREF:$c->{email}";
    }

    #phone
    if ($c->{phone}) {
	push @vcard, "TEL;TYPE=$type;TYPE=PREF:$c->{phone}";
    }
    if ($c->{cell}) {
	push @vcard, "TEL;TYPE=CELL:$c->{cell}";
    }
    if ($c->{fax}) {
	push @vcard, "TEL;TYPE=FAX:$c->{fax}";
    }

    # address
    my $addr = $this->show_address(plaintext=>1);
    $addr =~ s/,\s/;/g;
    $addr =~ s/\n/;/g;
    push @vcard, "ADR;TYPE=PREF:$addr";

    # url
    if ($c->{website}) {
	push @vcard, "URL:$c->{website}";
    }

    # note
    if ($c->{notes}) {
	$c->{notes} =~ s/[\r\n]/ /g;
	push @vcard, "NOTE:$c->{notes}";
    }

    return "BEGIN:VCARD\n".
	join("\n",@vcard).
	"\nEND:VCARD\n";
}

# compare - compare two contact datahashes to determine how similar they
# are (0=totally different, 1=same). This can be used to determine whether
# we already have a similar contact record on file.

sub compare {
    my ($this,%contact) = @_;
    return &ExSite::Misc::compare($this->meta()->get_all(),\%contact);
}

# misc DB ops

sub validate {
    my $this = shift;
    return ($msg{"no data"}) if (ref $this->{data} ne "HASH");
    # validate the contact record itself
    my @err = $this->SUPER::validate();
    # also validate the contact info
    my %c = $this->meta()->get_all();
    if (scalar keys %c == 0) {
	# would we ever insert a bare contact record with no info?
	push @err, "No contact information provided";
    }
    else {
	foreach my $key (keys %c) {
	    if ($c{$key} && $regex{$key} && $c{$key} !~ /$regex{$key}/) {
		push @err, "Invalid ".($field_prompt{$key}||$key);
	    }
	}
    }
    # some metadata combinations are invalid
    my %c = $this->get_info();
    if ($c{country} && $c{country} ne "Canada" && $c{provstate} =~ /^$regex{province}$/) {
	push @err, "Country/province mismatch";
    }
    elsif ($c{country} && $c{country} !~ /^United States|USA$/ && $c{provstate} =~ /^$regex{state}$/) {
	push @err, "Country/state mismatch";
    }
    return @err;
}

sub make { 
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    my $out;
    if ($this->approve("insert")) {
	my $in = new ExSite::Input();
	my $post = $in->post();
	if (keys %$post > 0) {
	    # no action provided
	    $out .= $this->do_make();
	    $out .= $this->show();
	}
	else {
	    $out .= $this->contact_form(%opt);
	    if ($opt{help}) {
		$out .= $opt{help};
	    }
	}
    }
    return $out;
}

sub edit { 
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    my $out;
    if ($this->loaded) {
	if ($this->approve("update")) {
	    my $in = new ExSite::Input();
	    my $post = $in->post();
	    if (keys %$post > 0) {
		# no action provided
		$out .= $this->do_edit();
		$out .= $this->show();
	    }
	    else {
		$out .= $this->contact_form(%opt);
		if ($opt{help}) {
		    $out .= $opt{help};
		}
	    }
	}
    }
    return $out;
}

sub do_make { 
    my ($this,%opt) = @_;
    return $this->save_contact("insert");
}

sub do_edit { 
    my ($this,%opt) = @_;
    return $this->save_contact("update");
}

sub save_contact {
    my ($this,$action) = @_;
    if ($this->approve($action)) {
	my $input = new ExSite::Input;
	my %data = $this->parse_contact_form();
	foreach my $key (keys %{$data{contact}}) {
	    $this->setdata($key,$data{contact}{$key});
	}	
	foreach my $key (keys %{$data{info}}) {
	    $this->meta_set($key,$data{info}{$key});
	}
	if (! $this->getdata("account_id") && ! $this->getdata("content_id")) {
	    # orphan; attach this to our current section
	    my $section = $share{DB}->this_site();
	    if ($section) {
		$this->setdata("content_id",$section->{content_id});
	    }
	    else {
		return $this->error("Save contact: no content or account specified.");
	    }
	}
	if ($this->force_save()) {    ### use force_update ??
	    return &ExSite::HTML::SuccessBox(title=>$msg{"Success"},pane=>$msg{"Contact info saved."});
	}
	else {
	    return $share{DB}->show_diagnostics("error","html");
	}
    }
    return $this->error("Save contact: Permission denied.");
}

# save_contact_data tries to save a simple datahash as contact records

sub save_contact_data {
    my ($this,$data) = @_;
    if ($this->approve("insert")) {
	$this->set_contact_data($data);
	if (! $this->getdata("account_id") && ! $this->getdata("content_id")) {
	    # orphan; attach this to our current section
	    my $section = $share{DB}->this_site();
	    if ($section) {
		$this->setdata("content_id",$section->{content_id});
	    }
	    else {
		return $this->error("Save contact: no content or account specified.");
	    }
	}
	return $this->force_save();
    }
    else {
	$this->error("Save contact: Permission denied.");
	return undef;
    }
}

sub set_contact_data {
    my ($this,$data) = @_;
    my %infoflds = map { $_=>1 } @field_order;
    my %contactflds = map { $_=>1 } $share{DB}{map}->get_columns("contact");
    foreach my $key (keys %$data) {
	if (exists $contactflds{$key}) {
	    $this->setdata($key,$data->{$key});
	}
	elsif (exists $infoflds{$key}) {
	    $this->meta_set($key,$data->{$key});
	}
    }
}

# the contact form includes the contact form, plus numerous contact_info
# fields. parse_contact_form() breaks it up into the appropriate records

sub parse_contact_form {
    my $this = shift;
    my %data;
    my $input = new ExSite::Input;
    my $post = $input->post();
    my $formdata = $share{DB}->parse_parts(%$post);
    my %info = map { $_ => 1 } @field_order;
    my %contact = map { $_ => 1 } $share{DB}{map}->get_columns("contact");
    foreach my $key (keys %$formdata) {
	if (exists $contact{$key}) {
	    $data{contact}{$key} = $formdata->{$key};
	}
	elsif (exists $info{$key}) {
	    if ($field_type{$key} eq "select") {
		if ($formdata->{$key} =~ /--|==/) {
		    $data{info}{$key} = undef;
		}
		else {
		    $data{info}{$key} = $formdata->{$key};
		}
	    }
	    else {
		$data{info}{$key} = $formdata->{$key};
	    }
	}
	else {
	    $this->warn("Unknown contact field: $key");
	}
    }
    return wantarray ? %data : \%data;
}

# contact_form
# Note: passing a hide param only hides contact fields, not contact_info fields

sub contact_form { 
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    my $db = $share{DB};
    my $data = $opt{data} || $this->get();
    my $admin = ($share{DB}->level > 1);
    my $admin_separator = $admin ? 
	$ml->hr().$ml->h4($msg{"Administrator-only fields"}) : 
	"";
    my $f = $share{DB}->form();
    $f->template(
	$ml->div(
	    $ml->table(
		$ml->tr(
		    $ml->td("[[type:prompt]]".$ml->br."[[type:input]]").
		    $ml->td("[[privacy:prompt]] (determines who can view this information)".$ml->br."[[privacy:input]]")
		)
	    ).
	    $ml->table(
		($admin ? $ml->tr($ml->td("[[name:prompt]]".$ml->br."[[name:input]]",{colspan=>2})):"").
		$ml->tr(
		    $ml->td("[[address:prompt]]".$ml->br."[[address:input]]",{colspan=>2})
		).
		$ml->tr(
		    $ml->td("[[city:prompt]]".$ml->br."[[city:input]]").
		    $ml->td("[[provstate:prompt]]".$ml->br."[[provstate:input]]")
		).
		$ml->tr(
		    $ml->td("[[country:prompt]]".$ml->br."[[country:input]]").
		    $ml->td("[[pcode:prompt]]".$ml->br."[[pcode:input]]")
		)
	    ).
	    $ml->table(
		$ml->tr(
		    $ml->td("[[phone:prompt]]".$ml->br."[[phone:input]]",{width=>"33%"}).
		    $ml->td("[[cell:prompt]]".$ml->br."[[cell:input]]",{width=>"33%"}).
		    $ml->td("[[fax:prompt]]".$ml->br."[[fax:input]]",{width=>"33%"})
		).
		$ml->tr(
		    $ml->td("[[email:prompt]]".$ml->br."[[email:input]]",{colspan=>3})
		).
		$ml->tr(
		    $ml->td("[[website:prompt]]".$ml->br."[[website:input]]",{colspan=>3})
		)
	    ),
	    {class=>"ContactForm"}
	).
	$admin_separator
	);

    # contact record fields
    $share{DB}->set_action($this->id ? "update" : "insert");
    $share{DB}->input_record({table=>"contact",id=>$this->id,simplename=>1,data=>$data,hide=>$opt{hide}});
    # contact info fields
    foreach my $field (@field_order) {
	my $fld = $field_pref{$field};
	my %opt = (name=>$fld,type=>$field_type{$fld},size=>$field_size{$fld});
	$opt{prompt} = $field_prompt{$fld} || ucfirst $fld;
	if ($opt{type} eq "select") {
	    $opt{nullvalue} = $msg{"== select =="};
	    $opt{options} = $regex{$fld};
	}
	$opt{value} = $this->meta->get($fld);
	if (! $opt{value} && $fld eq "provstate") {
	    $opt{value} = $this->meta->get("province") || $this->meta->get("state");
	}
    	$f->input(%opt);
    }
    return $f->make();
}

1;

