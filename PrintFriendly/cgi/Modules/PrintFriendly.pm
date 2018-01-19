package Modules::PrintFriendly;
#-----------------------------------------------------------------------
#
#   PrintFriendly : re-render the page in a printer-friendly format.
#
#   This module hacks the context for the page to change its template
#   to a bare-bones template that only includes a body object.
#
#   The following optional CMS object references are also added:
#
#   PrintFriendlyHead - inserts html into the head section of the document
#   PrintFriendlyTop - inserts content above the body content
#   PrintFriendlyFoot - inserts content below the body content
#
#-----------------------------------------------------------------------
#   Copyright 2012 Exware Solutions, Inc.  http://www.exware.com
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
#   The included Javascript source files are Copyright (C) 2010 of
#   Arc90 Inc (http://lab.arc90.com/experiments/readability)
#-----------------------------------------------------------------------

use strict;
use ExSite::Config;
use ExSite::Page;
use ExSite::Content;
use ExSite::Input;
use ExSite::Misc;
use ExSite::ML;
use ExSite::URI;
use Modules::BaseDCD;
use vars qw(@ISA);
@ISA = qw(Modules::BaseDCD);

sub write {
    my ($this,$opt) = @_;
    my %opt = &DecodeString($opt);
    $this->{opt} = \%opt;
    my $ml = new ExSite::ML;
    my $p = $share{Page};
#    my $title = $p->title();
    my $out;

    # must provide identifier and identifer name in the oyster to use readability
    $this->{opt}{identifier} or  $this->{opt}{identifier} = "class";
    $this->{opt}{identifier_name} or  $this->{opt}{identifier_name} = "body";
    my $url = "javascript:readability()";
    my $target = "_self";
    $out = $this->setup_readability();
    return $out . $ml->div(
	$ml->a($msg{"Printer-friendly version"},{href=>$url}),
	{class=>"PrintFriendly"}
	);
}

sub setup_readability {
    my $this = shift;
    my $ml = $share{ML};

    my $file_path = $config{server}{HTMLpath} . "/_Modules/PrintFriendly";
    my $content_container;

    if ($this->{opt}{identifier} eq "class") {
	$content_container = "document.getElementsByClassName(\"" . $this->{opt}{identifier_name} . "\")[0].innerHTML";
    }
    elsif ($this->{opt}{identifier} eq "id") {
	$content_container = "document.getElementById(\"" . $this->{opt}{identifier_name} . "\").innerHTML";
    }
    elsif ($this->{opt}{identifier} eq "name") {
	$content_container = "document.getElementsByName(\"" . $this->{opt}{identifier_name} . "\")[0].innerHTML";
    }

    my $section_id = $this->get_section_id();

    # if using config option for logo, you must supply the logo in the form of an img tag (ex: <img src="http://www.yoursite.ca/logo.jpg"/>)
    my $logo = $config{PrintFriendly}{$section_id}{logo} || $config{site}{logo} unless ($config{PrintFriendly}{hide_logo});
    my $copyright = "&#169; " . $config{site}{name};
    my $hidetitle = $config{PrintFriendly}{hide_title};
    my $hideurl = $config{PrintFriendly}{hide_url};
    my $hidecopyright = $config{PrintFriendly}{hide_copyright};
    my $hidedate = $config{PrintFriendly}{hide_date};
    my $headertext = $config{PrintFriendly}{header_text};
    
    my $out = <<END;
<script type="text/javascript">
onload = function () {
    if (document.getElementsByClassName == undefined) {
	document.getElementsByClassName = function(className)
	    {
		var hasClassName = new RegExp("(?:^|\\s)" + className + "(?:$|\\s)");
		var allElements = document.getElementsByTagName("*");
		var results = [];

		var element;
		for (var i = 0; (element = allElements[i]) != null; i++) {
		    var elementClass = element.className;
		    if (elementClass && elementClass == className)
			results.push(element);
		    }
		
		return results;
	    }
    }
}

function readability() {
    hideCopyright = '$hidecopyright';
    hideDate = '$hidedate';
    hideUrl = '$hideurl';
    hideTitle = '$hidetitle';
    copyright = '$copyright';
    siteLogo = '$logo';
    headerText = '$headertext';
    passedBodyContent = $content_container;
    readConvertLinksToFootnotes = false;
    readStyle = 'style-newspaper';
    readSize = 'size-medium';
    readMargin = 'margin-wide';
    _readability_script = document.createElement('script');
    _readability_script.type = 'text/javascript';
    _readability_script.src = '$file_path/readability.js?x=' + (Math.random());
    document.documentElement.appendChild(_readability_script);
    _readability_css = document.createElement('link');
    _readability_css.rel = 'stylesheet';
    _readability_css.href = '$file_path/readability.css';
    _readability_css.type = 'text/css';
    _readability_css.media = 'all';
    document.documentElement.appendChild(_readability_css);
    _readability_print_css = document.createElement('link');
    _readability_print_css.rel = 'stylesheet';
    _readability_print_css.href = '$file_path/readability-print.css';
    _readability_print_css.media = 'print';
    _readability_print_css.type='text/css';
    document.getElementsByTagName('head')[0].appendChild(_readability_print_css);
}
</script>
END

    return $out;
}

sub ioctl {
    my $this = shift;
    $_ = shift;   # $_ is the ioctl request
    if (/ModuleInfo/) {
	return "PrintFriendly regenerates the current page, but in a printer-friendly format with no graphics and minimal colors.";
    }
    elsif (/PublishRule/) {
	return "static";
    }
    return undef;
}

1;
