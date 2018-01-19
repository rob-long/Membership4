package Modules::SocialMedia;

=pod 

noscript version:


=cut

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Content;
use Modules::BaseDCD;
use base qw(Modules::BaseDCD);

use vars qw($ml $ui);

sub ioctl {
    my $this = shift;
    $_ = shift;
    if (/ModuleName/) {
	return "Social Media";
    }
    elsif (/ModuleInfo/) {
	return "Cross-post content to your social media feeds.";
    }
    elsif (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/Category/) {
	return "Social";
    }
    elsif (/DynContentParameter/) {
	return "<p><select name=\"param\">
<option value=\"cmd=toolbar\">Toolbar Display</option>
<option value=\"cmd=\">Single Button Display</option>
</select></p>\n";
    }
}

sub write{
    # Parameters:
    # id => id of content to share
    # url => URL to share
    # title => text to share
    # Shares current URL is nothing is provided
    my ($this,$options) = @_;
    my %param = &DecodeString($options);

    my %data = (
	protocol=>$config{server}{protocol},
	title=>$param{title},
	url=>$param{url},
	);
    # Get url from parameter
    if ($param{id}) {
	my $c = new ExSite::Content();
	$c = $c->get_content_obj($param{id});
	$data{title} = $c->title();
	$data{url} = $c->get_url_canonical();
    }
    my $cmd = $param{cmd};
    if ($cmd eq "toolbar") {
	return $this->toolbar(%data);
    }
    elsif ($cmd eq "basic") {
	return $this->basic_links(%data);
    }
    else {
	# generic share button
	my $content;
	if ($data{url}){
	    $content = <<END;
<script type="text/javascript">
var a2a_config = a2a_config || {};
a2a_config.linkname = "[[title]]";
a2a_config.linkurl = "[[url]]";
</script>
END
	}
	$data{linkname} = &html_escape($data{linkname});
	my $template = <<END;
<div id="AddToAny">
<a class="a2a_dd" href="[[protocol]]://www.addtoany.com/share_save?linkurl=[[url]];linkname=[[title]]"><img src="[[protocol]]://static.addtoany.com/buttons/share_save_120_16.gif" width="120" height="16" border="0" alt="Share/Bookmark"/></a>
$content
<script type="text/javascript" src="[[protocol]]://static.addtoany.com/menu/page.js"></script>
</div>
END
        return &substitute($template,\%data);
    }
}

sub toolbar {
    my ($this,%opt) = @_;
    my $out;
    my $ml = $share{ML};

    my $tools = $opt{tools} || &preference("AddToAny.tools") || "facebook,twitter,google_plus,linkedin,email";
    my @tools = split(",", $tools);

    foreach my $tool (@tools) {
	$out .= $ml->a(undef, { class => "a2a_button_$tool" });
    }
    
    my $a2aconf = { class => "a2a_kit a2a_default_style" };
    $a2aconf->{"data-a2a-url"} = $opt{url} if ($opt{url});
    $a2aconf->{"data-a2a-title"} = $opt{title} if ($opt{title});
    $out = $ml->script(undef, { type => "text/javascript", src => "//static.addtoany.com/menu/page.js" }) . 
	$ml->div(
	    $ml->a(undef, { href => "https://www.addtoany.com/share_save", class => "a2a_dd" }) .
	    $ml->span(undef, { class => "a2a_divider" }) .
	    $out,
	    $a2aconf
	);
    
    return $out;
}

sub basic_links {
    my ($this,%opt) = @_;
    my $out;
    my $ml = $share{ML};

    my $tools = $opt{tools} || &preference("AddToAny.tools") || "facebook,twitter,google_plus,linkedin,email";
    my @tools = split(",", $tools);

    $out .= $ml->a($ml->img(undef,{src=>"https://static.addtoany.com/buttons/a2a.svg",width=>16,height=>16}),{href=>"https://www.addtoany.com/share?linkurl=$opt{url}&amp;linkname=$opt{title}",target=>"_blank"});

    foreach my $tool (@tools) {
	$out .= $ml->a($ml->img(undef,{src=>"https://static.addtoany.com/buttons/${tool}.svg",width=>16,height=>16}),{href=>"https://www.addtoany.com/add_to/${tool}?linkurl=$opt{url}&amp;linkname=$opt{title}",target=>"_blank"});
    }
    return $ml->div($out,{class=>"SocialMedia"});
}

sub ctrl_panel {
    my $this = shift;
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    my $in = $this->{input};
    if (! $in->{id}) {
	return $this->show_content();
    }
    else {
	return $this->share_content($in->{id});
    }
}

sub show_content {
    my $this = shift;
    if (! $share{querylib}{"recent content"}) {
	$share{DB}->set_query("recent content",
			      sql=>"select * from content c, content_type t where c.status=0 and c.type=t.content_type_id and t.name in ('page','article','event','product','album') order by c.ptime desc limit 50",
			      nparam=>0,
			      keys=>["content","content_type"],
			      mode=>"r");
    }
    my $out = $ml->h1("Share a recent post:");
    my $c = new ExSite::Content();
    my $r = new ExSite::ReportBuilder(title=>"Recent posts");
    $r->set("dynamic",1);
    $r->headers("Post","Type","Site","Posted","Public Link");
    my @c = $share{DB}->get_query("recent content");
    foreach my $cdata (@c) {
	my $p = $c->get_content_obj($cdata);
	next if (! $p->is_published);
	$r->push(
	    $ml->a($p->title,{href=>$this->link(id=>$p->id)}),
	    $p->subtype(),
	    $p->my_section->title(),
	    $p->posting_date(),
	    $ui->fatool("link",url=>$p->get_url_canonical()),
	    );
    }
    $out .= $r->make();
    return $out;
}

sub share_content {
    my ($this,$id) = @_;
    my $c = new ExSite::Content();
    $c = $c->get_content_obj($id);
    my $url = $c->get_url_canonical();
    $url =~ /^(\w+)"\/\//;
    my $protocol = $1 || "http";
    my %data = (
	protocol=>$protocol,
	title=>&html_escape($c->title()),
	url=>$url,
	);
    
    my $out = $ml->h1("Share ".$ml->em($c->title)." on social media");

    my @tools = $config{SocialMedia}{tools} ?
	@{$config{SocialMedia}{tools}} :
	qw(facebook twitter google_plus linkedin email);
    my $sharelinks;
    foreach my $tool (@tools) {
	$sharelinks .= $ml->a(undef, { class => "a2a_button_$tool" });
    }
    
    my $template = <<END;
<!-- AddToAny BEGIN -->
<div class="a2a_kit a2a_kit_size_32 a2a_default_style">
<a class="a2a_dd" href="https://www.addtoany.com/share"></a>
$sharelinks
</div>
<script>
var a2a_config = a2a_config || {};
a2a_config.linkname = "[[title]]";
a2a_config.linkurl = "[[url]]";
</script>
<script async src="https://static.addtoany.com/menu/page.js"></script>
<!-- AddToAny END -->
END
    $out .= &substitute($template,\%data);
    if ($c->access > 0) {
	$out .= $ui->ErrorMsg("This ".$c->subtype()." has access controls, and cannot be viewed by the public. It may not make sense to share it on public social media feeds.");
    }
    if (! $c->is_published) {
	$out .= $ui->ErrorMsg("This ".$c->subtype()." has not been published yet. You should not share it before there is a published URL to visit.");
    }
    $out .= $ml->p("This is the link that will be shared:");
    $out .= $ml->iframe(undef,{src=>$url,height=>500,width=>"100%"});
    $out .= $ml->p($ui->Button(label=>"Recent posts",url=>$this->link(id=>undef),faicon=>"back"));
    return $out;
}

1;
