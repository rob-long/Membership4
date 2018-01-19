package Modules::AddToAny;
use strict;
use ExSite::Config;
use ExSite::Misc;

use Modules::BaseDCD;
use  base qw(Modules::BaseDCD);

sub ioctl {
    my $this = shift;
    $_ = shift;
    if (/ModuleName/) {
	return "AddToAny";
    }
    elsif (/ModuleInfo/) {
	return "Link sharing tool";
    }
    elsif (/DynContentParameter/) {
	return "<p><select name=\"param\">
<option value=\"cmd=toolbar\">Toolbar Display</option>
<option value=\"cmd=\">Single Button Display</option>
</select></p>\n";
    }
}

sub write{
    # Parameter:
    #	linkname: link name 
    #	linkurl: url
    my ($this,$options) = @_;
    my %param = &DecodeString($options);
    
    my $cmd = $param{cmd};
    if ($cmd eq "toolbar") {
	return $this->toolbar(\%param);
    }

    my %data = (
	protocol=>$config{server}{protocol},
	linkname=>"",
	linkurl=>"",
	);
    # Get url from parameter
    if ($param{linkurl}){
	$data{linkname} = $param{linkname};
	$data{linkurl} = $param{linkurl};
    }
    my $content;
    if ($data{linkurl}){
	$content = <<END;
<script type="text/javascript">
var a2a_config = a2a_config || {};
a2a_config.linkname = "[[linkname]]";
a2a_config.linkurl = "[[linkurl]]";
</script>
END
    }
    $data{linkname} = &html_escape($data{linkname});
    my $template = <<END;
<div id="AddToAny">
<a class="a2a_dd" href="[[protocol]]://www.addtoany.com/share_save?linkurl=[[linkurl]];linkname=[[linkname]]"><img src="[[protocol]]://static.addtoany.com/buttons/share_save_120_16.gif" width="120" height="16" border="0" alt="Share/Bookmark"/></a>
$content
<script type="text/javascript" src="[[protocol]]://static.addtoany.com/menu/page.js"></script>
</div>
END
    return &substitute($template,\%data);
}

sub toolbar {
    my $this = shift;
    my $opt = shift;
    my $out;
    my $ml = $share{ML};

    my $tools = $opt->{tools} || &preference("AddToAny.tools") || "facebook,twitter,google_plus,linkedin,email";
    my @tools = split(",", $tools);

    foreach my $tool (@tools) {
	$out .= $ml->a(undef, { class => "a2a_button_$tool" });
    }

    my $share_config = { class => "a2a_kit a2a_default_style" };
    $share_config->{"data-a2a-url"} = $opt->{url} if ($opt->{url});
    $out = $ml->script(undef, { type => "text/javascript", src => "//static.addtoany.com/menu/page.js" }) . 
	$ml->div(
	    $ml->a(undef, { href => "https://www.addtoany.com/share_save", class => "a2a_dd" }) .
	    $ml->span(undef, { class => "a2a_divider" }) .
	    $out,
	    $share_config
	);
    
    return $out;
}

1;
