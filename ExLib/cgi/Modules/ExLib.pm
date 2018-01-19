package Modules::ExLib;
#----------------------------------------------------------------------------
#
#   Copyright 2001-2016 Exware Solutions, Inc.  http://www.exware.com
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

=pod

ExLib : a library of general-purpose dynamic content tools

=cut

use strict;
use ExSite::Misc;
use ExSite::Input;
use ExSite::Config;

# inherit from Base class
use Modules::BaseDCD;
use vars qw(@ISA);
@ISA = qw(Modules::BaseDCD);

sub read {
    # do nothing
    return;
}

# write : accepts a string argument, which is one of the following:
#
# date
# datetime
# environment
# year
# server
# server_software
# address
# uptime
# url
# webmaster
# cgipath
# fulldomain
# my name
# jquery, jqueryui
# login_overlay
# member_content
# errors
# warnings
# diagnostics
# homesite
# lang, language

sub write {
    my $this = shift;
    $_ = shift;
    if (/^siteurl$/){
    	return $config{server}{server};
    }    
    if (/^site_name$/){
    	return $config{site}{name};
    }    
    elsif (/^cgipath$/) {
    	return "$config{server}{server}$config{server}{CGIpath}";
    }
    elsif (/^datetime$/) {
	return scalar localtime;
    }
    elsif (/^date$/) {
	my (undef,undef,undef,$mday,$mon,$year,undef,undef,undef) = localtime;
	return ("","Jan","Feb","Mar","Apr","Jun","Jul","Aug","Sep","Oct","Nov","Dec")[$mon]." $mday, ".($year + 1900);
    }
    elsif (/^time$/) {
	my (undef,$min,$hour,undef,undef,undef,undef,undef,undef) = localtime;
	return "$hour:$min";
    }
    elsif (/^year$/) {
	return (localtime)[5] + 1900;
    }
    elsif (/^server$/) {
	return $ENV{SERVER_SIGNATURE};
    }
    elsif (/^server_software$/) {
	return $ENV{SERVER_SOFTWARE};
    }
    elsif (/^address$/) {
	return $ENV{SERVER_ADDR};
    }
    elsif (/^environment$/) {
	return &ShowHash(%ENV);
    }
    elsif (/^session$/) {
	return &ShowHash(%session);
    }
#    elsif (/^uptime$/) {
#	return `uptime`;
#    }
    elsif (/^url$/) {
	return "$config{server}{server}$config{server}{HTMLpath}";
    }
    elsif (/^webmaster$/) {
	my ($user,$domain) = split /\@/,$config{site}{administrator};
	return "\n<SCRIPT LANGUAGE=\"JavaScript\">\n<!-- //\nuser = \"$user\";\ndomain = \"$domain\";\naddr = user + '\@' + domain;\ndocument.write('<a href=\"mailto:' + addr + '\">' + addr + '</a>');\n// -->\n</SCRIPT>\n";
    }
    elsif (/^my name$/) {
	return $share{DB}->my_name();
    }
    elsif (/^jquery$/) {
	return $config{jquery};
	$share{js}{query} = 1;
    }
    elsif (/^jqueryui$/) {
	return $config{jqueryui};
	$share{js}{queryui} = 1;
    }
    elsif (/^login_overlay$/) {
	my $loc = $share{Page};
	my %opt;
	my $name = "login_label";
	if ($loc) {
	my $ctemplate = $loc->find($name);
	$opt{label} = $ctemplate->get_html();
	}
	return &ExSite::HTML::LoginOverlay(%opt);	
    }
    elsif (/^member_content$/) {
	my $loc = $share{Page};	
	my $template;
	if (!$share{DB}->authorize) {
		my $ctemplate = $loc->find("default_content");
		$template = $ctemplate->get_html();
	} else {
		my $ctemplate = $loc->find("member_content");
		$template = $ctemplate->get_html();
	}
	my $p = new ExSite::Page(id=>$loc->id());
	return undef if (!$template);
	return $p->expand(html=>$template);
    }
    elsif (/^post$/) {
	my $in = new ExSite::Input;
	return &ShowHash($in->post);
    }
    elsif (/^errors?$/) {
	return &show_diagnostics("html",3);
    }
    elsif (/^warn((ing)?s)?$/) {
	return &show_diagnostics("html",2);
    }
    elsif (/^diagnostics?$/) {
	return &show_diagnostics("html",1);
    }
    elsif (/^homesite?$/) {
	if ($share{DB}) {
	    my $u = $share{DB}->my_user_record();
	    if (ref $u eq "HASH" && $u->{section_id}) {
		my $s = $share{DB}->fetch("section",$u->{section_id});
		return $s->{title} ? $s->{title} : $s->{section_id};
	    }
	}
	return "n/a";
    }
    elsif (/^lang/) {
	# "language" returns full version name
	my $lang = $share{Page}->language() || $config{default_language};
	return $lang if /^language$/;
	# "lang" returns 2-letter abbreviation
	return $config{language_extension}{$lang} if ($config{language_extension}{$lang});
	return lc substr($lang,0,2);
    }
    # default to date and time
    return scalar localtime;
}

sub ioctl{
    my $this = shift;
    $_ = shift;   # $_ is the ioctl request
    if (/ModuleInfo/) {
	return "Miscellaneous dynamic functions.";
    }
    elsif (/DynContentParam/) {
	return "<b>Parameter:</b>
<select name=\"param\">
<option>address</option>
<option>date</option>
<option>datetime</option>
<option>year</option>
<option>environment</option>
<option>session</option>
<option>homesite</option>
<option>jquery</option>
<option>jqueryui</option>
<option>lang</option>
<option>language</option>
<option>my name</option>
<option>post</option>
<option>server</option>
<option>server_software</option>
<option>uptime</option>
<option>url</option>
<option>webmaster</option>
<option>errors</option>
<option>warnings</option>
<option>diagnostics</option>
</select>\n";
    }
    elsif (/isDynamic/) {
	# most are static, actually, but some (eg. my_name, date/time) 
	# are dynamic
	return 1;
    }
}

1;

