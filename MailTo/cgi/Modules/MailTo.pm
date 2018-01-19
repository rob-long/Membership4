package Modules::MailTo;

# MailTo : spambot-proof replacements for mailto: URIs.
#
# Usage:
#
# <!--&MailTo(mailto:foo@bar.com)-->    # makes an obfuscated mailto URI
# <!--&MailTo(foo@bar.com)-->           # ditto
# <!--&MailTo(mailform:foo@bar.com)-->  # makes a form to send an email
#
# can optionally add a name which behaves as the anchor text, eg.
# <!--&MailTo(foo@bar.com,Foo Bar)-->
#
# Note that even though the email address is plainly visible in the 
# oyster, it will not be visible in the public HTML.  The ExSite CMS
# will transform the oyster into something that spambots will not be
# able to parse easily.

use strict;
use ExSite::Config;
use ExSite::Mail;
use Modules::BaseDCD;

use vars qw(@ISA);
@ISA = qw(Modules::BaseDCD);

sub write {
    my ($this,$options) = @_;
    my $in = $this->{input};
    if ($in->{to_name}) {
	# we have some form input
	return $this->send;
    }
    else {
	my ($to,$name) = split(/,/,$options,2);
	my (undef,$addr) = split(/:/,$to,2);
	if ($options =~ /^mailform:/) {
	    return $this->mailform(to=>$addr);
	}
	elsif ($options =~ /^mailto:/) {
	    return $this->mailto($addr,$name);
	}
	return $this->mailto($to,$name);
    }
    return;
}

sub ioctl {
    my $this = shift;
    $_ = shift;   # $_ is the ioctl request
    if (/ModuleInfo/) {
	return "MailTo is a tool for securely placing email addresses into
webpages as clickable URLs, while not allowing automatic spambots to harvest 
them.  This reduces the incidence of junk mail that you receive as a result 
of posting email addresses on the web.";
    }
    if (/DynContentParam/) {
	return "E-mail address:<br><input type=\"text\" name=\"param\" value=\"\">";
    }
    elsif (/PublishRule/) {
	return "static";
    }
    return undef;
}

sub mailto {
    my ($this, $mailto, $name) = @_;
    my ($email, $params) = split(/\?/,$mailto,2);
    my ($user, $domain) = split(/\@/,$email,2);
    $name or $name = $email;
    my $out = "<SCRIPT LANGUAGE=\"JavaScript\">
<!-- //
user = \"$user\";
domain = \"$domain\";
params = \"$params\";
email = user + '\@' + domain;\n";
    $out .= $params ? 
	"addr = user + '\@' + domain + '?' + params;\n" :
	"addr = user + '\@' + domain\n";
    $out .= "document.write('<a href=\"mailto:' + addr + '\">' + ";
    $out .= $name eq $email ? "addr" : "'$name'";
    $out .= " + '</a>');// --></SCRIPT><NOSCRIPT>$user [AT] $domain</NOSCRIPT>";
    return $out;
}

sub mailform {
    my ($this, %data) = @_;
    if (! $data{to_name}) {
	($data{to_name}, $data{to_dom}) = split(/\@/,$data{to},2);
    }
    my $url = $this->link();
    return "<form action=\"$url\" method=\"POST\">
<input type=\"hidden\" name=\"to_name\" value=\"$data{to_name}\">
<input type=\"hidden\" name=\"to_dom\" value=\"$data{to_dom}\">
<table>
<tr><td>From:</td><td><input type=\"text\" name=\"from\" size=\"40\" value=\"$data{from}\"></td></tr>
<tr><td>Subject:</td><td><input type=\"text\" name=\"subject\" size=\"40\" value=\"$data{subject}\"></td></tr>
<tr><td>Message:</td><td><textarea name=\"message\" rows=\"6\" cols=\"60\">$data{message}</textarea></td></tr>
<tr><td></td><td><input type=\"submit\" value=\"Send\"></td></tr>
</table>
</form>\n";
}

sub send {
    my $this = shift;
    my $out;
    my $in = $this->{input};
    my $addr = $in->{to_name}."@".$in->{to_dom};
    my @err;
    if ($addr !~ /^[\w](\.?[\w\-]+)*@([\w\-]+\.)+[A-Za-z]{2,4}$/) {
	push @err, "no valid destination address";
    }
    if ($in->{from} !~ /^[\w](\.?[\w\-]+)*@([\w\-]+\.)+[A-Za-z]{2,4}$/) {
	push @err, "invalid from address";
    }
    if (! $in->{message}) {
	push @err, "no message to send";
    }
    if (! $in->{subject}) { $in->{subject} = "(no subject)"; }
    if (@err > 0) {
	$out = "<p class=\"error\">".join("<br>\n",@err)."</p>\n";
    }
    elsif (require ExSite::Mail) {
	my $stat = &SendMail($addr,$in->{from},$in->{subject},$in->{message});
	if ($stat) {
	    $out .= "<p class=\"error\">Problem sending message: error code $stat.</p>\n";
	}
	else {
	    $out .= "<p>Message sent successfully.</p>\n";
	    $in = {to=>$addr};
	}
    }
    $out .= $this->mailform(%$in);
    return $out;
}

1;

