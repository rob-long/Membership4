package Modules::Login;

#----------------------------------------------------------------------------
#
#   Copyright (C) 2015 - Exware Solutions, Inc.  http://www.exware.com
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
# Login : login tool
#
# This plug-in determines dynamically whether or not the user is logged in.
# If so, it displays the login identity; if not, it displays a login form 
# or link.  It works on both static and dynamic pages, but to get proper
# behaviour on static pages, you should configure your cookies to go
# to all URLs, not just dynamic ones.  (By default, cookies are only
# sent to CGI urls.)

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Util;
use ExSite::Content;
use Modules::BaseDCD;
use MIME::Base64;

use vars qw(@ISA $ml);
@ISA = qw(Modules::BaseDCD);

# options are:
# method = form | link
# goto = page ID
# goto_filename = page filename
# wrap = div | span
# name = login | name
# prefix = string

sub write {
    my ($this,$options) = @_;
    $ml = new ExSite::ML(nl=>0);
    my %opt = (%{$config{Login}}, &DecodeString($options));
    $this->{opt} = \%opt;
    return "Login: ".$msg{"no configuration info"} 
	if (ref $this->{opt} ne "HASH" || keys %{$this->{opt}} == 0);
    my $out;
    if ($opt{dropdown}) {
	$out = $this->drop_menu();
    }    
    elsif ($share{Page} && $share{Page}->is_publishing()) {
	$out = $this->write_static();
    }
    else {
	$out = $this->write_dynamic($options);
    }
    if ($opt{popup}) {
	$out .= $ml->a($msg{"close"},{href=>"#",onclick=>"hidelogin()",class=>"hideloginlink"});
	$out = $ml->div($out,{id=>"LoginBox",class=>"Login",style=>"display:none;"});
	$out = $ml->a($msg{$this->{opt}{login}},{href=>"#",onclick=>"showlogin()",class=>"showloginlink"}).$out;
	$out .= $ml->script("
function showlogin() {
    var loc = document.getElementById('LoginBox');
    loc.style.display='block';
}
function hidelogin() {
    var loc = document.getElementById('LoginBox');
    loc.style.display='none';
}\n");
    }
    else {
	my $wrap = $this->{opt}{wrap} || "div"; 
	return $ml->$wrap($out,{class=>"Login"});
    }
}

# write_static is for published pages - we cannot execute server-side calls,
# so instead we inspect our login cookie to see if it appears like we are 
# logged in.  This is not foolproof; a bad cookie could indicate that we
# are logged in, when in fact the cookie will be rejected/ignored when
# an actual server call occurs.  But it is useful for tidying up the UI
# (eg. show login forms only when you appear to be logged out; else show
# the login identity.)

sub write_static {
    my ($this) = @_;
    return $this->write_static_session() 
	if ($config{auth}{type} eq "session");
    my $cookiename = $config{site}{identity_cookie};
    my $loginhtml = $this->{opt}{method} eq "link" ? 
	$this->loginlink() : $this->loginform();
    $loginhtml =~ s/\n/\\n\\\n/g;

    my $logged_in_text = $this->{opt}{logged_in_text} ? 
	("'" . $this->{opt}{logged_in_text} . "'") : "id[0]";
    my $logouthtml = $this->logoutlink();
    my $js = $this->get_cookie_js();
    my $prefix = $msg{$this->{opt}{prefix}};

    my ($goto_link_open, $goto_link_close);
    if ($this->{opt}{goto}) {
	my $p = new ExSite::Page(id=>$this->{opt}{goto});
	my $lang = $share{Page} ? $share{Page}->getdata("language") : "";
	$p->set_language($lang);

	my $url = $p->get_url;
	$goto_link_open = "<a href=\"$url\" class=\"LoginUserLink\">";
	$goto_link_close = "</a>";
    }

    return $ml->script("var loginform = '$loginhtml';
var id_cookie = get_cookie('$cookiename');
if (id_cookie) {
    var id = id_cookie.split(':');
    document.write('$prefix$goto_link_open' + $logged_in_text + '$goto_link_close ($logouthtml)');
}
else {
    document.write(loginform);
}
$js",{type=>'text/javascript'});
}

sub write_static_session {
    my ($this) = @_;
    my $cookiename = $config{site}{id}."_sessionID";
    my $loginhtml = $this->{opt}{method} eq "link" ? 
	$this->loginlink() : $this->loginform();
    $loginhtml =~ s/\n/\\n\\\n/g;
    my $logouthtml = $this->logoutlink();
    my $js = $this->get_cookie_js();
    return $ml->script("var loginform = '$loginhtml';
var id_cookie = get_cookie('$cookiename');
if (id_cookie) {
    document.write('".$msg{'Logged in'}." ($logouthtml)');
}
else {
    document.write(loginform);
}
$js",{type=>'text/javascript'});
}

# write_dynamic is used on dynamically generated pages

sub write_dynamic {
    my ($this,$options) = @_;
    my $in = $this->{input};  # set by BaseDCD::read
    my $wrap = $this->{opt}{wrap} || "div";
    if ($share{DB}->level()) {
	# already logged in, don't clobber it
	return $this->userlink();
    }
    elsif ($in->{login} && $in->{login_action} ne "forgot") {
	# login info received
	if ($share{DB}->login($in->{login},$in->{password},$in->{goto})) {
	    return $this->userlink();
	}
	else {
	    return $msg{'Login failed - please try again.'};
	}
    }
    else {
	return $this->{opt}{method} eq "link" ? 
	    $this->loginlink() : $this->loginform();
    }
}

sub drop_menu {
    my ($this) = @_;
    my $loc = $share{Page} || $share{Section};
    my $template;
    my $ctemplate = $loc->find("Login_submenu");
    
    if ($ctemplate->get_html) {
	$template = $ctemplate->get_html;
    } else {
	my $submenu;
	my $goto = $this->goto();
	my $links = [$ml->a("Profile", {href=>$goto}), $ml->a("Sign Out", {href=>"$config{server}{CGIpath}/logout.cgi"})];
	$submenu = $ml->ul($links, {id=>"Login_submenu"});
	$template = $ml->div($ml->ul($ml->li("[[username]]".$submenu), {id=>"Login_name"}), {id=>"Login_menu"});
    }
    my $username;
    $username .= $ml->a($this->username . " " . $ml->div(undef, {class=>"arrow-down"}),{href=>"#"});
    my $out;
    if ($share{DB}->authorize) {
	$out .= &substitute($template, { username=>$username });
    } else {
	$out .= $ml->div($this->loginlink, {id=>"Login_link"});	
    }
    return $out;
}

sub userlink {
    my $this = shift;
    my $url = $this->goto_alt();
    my $logouthtml = $this->logoutlink();
    my $name = $this->{opt}{logged_in_text} || $this->username();
    return $msg{$this->{opt}{prefix}}.
	$ml->a($name, {href=>$url,class=>"LoginUserLink"}).
	" ($logouthtml)\n";
}

sub username {
    my $this = shift;
    return $this->{opt}{name} eq "name" ?
	$share{DB}->my_name() : $share{DB}->my_login();
}

sub loginform {
    my $this = shift;
    my $url = $this->goto();
    # list of login_form configurations
    my @keys = qw(login_heading login_form login_buttons forgot_login login_placeholder password_placeholder login_prompt password_prompt login_module);
    my @login_form = &preference("Login.login_form") || 
        map($ml->span("[[$_]]",{class=>$_}),qw(login_prompt login_input password_prompt password_input));
    my %prefs = (
    	# login_form handlers should use this
    	login_module => 1,
        login_heading => undef,
        login_form => \@login_form,
        login_buttons => &preference("Login.login_buttons") || 
            $ml->input(undef,{type=>"submit", value=>" ".$msg{"Log in"}." "}),
        forgot_login => undef,
        login_placeholder => &preference("Login.login_placeholder"),
        password_placeholder => &preference("Login.password_placeholder"));
    my %tmp;
    # temporarily override ExSite config settings
    foreach my $k (@keys) {
	$tmp{$k} = $config{auth}{$k};
	$config{auth}{$k} = $prefs{$k};
    }
    my $out = $share{DB}->login_form($url,$url);
    # suppress forgot login action in this module        
    if (!$this->{input}{login_action} && &preference("Login.forgot_login")) {
	my $forgoturl = $this->goto();
	my $uri = new ExSite::URI(uri=>$forgoturl);
	$uri->query(login_action=>"forgot");
	$out .= $ml->div(
	    $ml->a($msg{$config{auth}{forgot_prompt}}, {href=>$uri->write()}),
	    {class=>"forgot_login"}
	    );    
    }
    foreach my $k (@keys) {
	$config{auth}{$k} = $tmp{$k};
    }
    return $out;
}

sub loginlink {
    my $this = shift;
    my $url = $this->goto();
    my $login = $msg{$this->{opt}{login}};
    return $ml->a($login,{href=>$url});
}

sub logoutlink {
    my $this = shift;
    my $logout = $msg{$this->{opt}{logout}};
    return $ml->a($logout,{href=>"$config{server}{CGIpath}/$config{prog}{logout}", class=>"Logout"});
}

sub goto {
    my $this = shift;
    my $lang = $share{Page} ? $share{Page}->getdata("language") : "";
    if ($this->{opt}{goto}) {
	my $p = new ExSite::Page(id=>$this->{opt}{goto});
	$p->set_language($lang) if $lang;
	return $p->get_url_dynamic();
    }
    elsif ($this->{opt}{goto_filename}) {
	# goto based on which section we're in configured by filename
	my $s = new ExSite::Section(id=>$this->get_section_id());
	my $p = $s->get_page($this->{opt}{goto_filename});
	if ($p->defined()) {
	    $p->set_language($lang) if $lang;
	    return $p->get_url_dynamic();
	}
    }
    return $share{Page}->get_url();
}

sub goto_alt {
    my $this = shift;
    if ($this->{opt}{goto_alt}) {
	my $p = new ExSite::Page(id=>$this->{opt}{goto_alt});
	return $p->get_url_dynamic();
    }
    else {
	return $this->goto();
    }
}

sub get_cookie_js {
    return "function get_cookie(name) {
    var key = name + \"=\";
    var cookies = document.cookie.split(';');
    for(var i=0;i < cookies.length;i++) {
        var cookie = cookies[i];
        while (cookie.charAt(0)==' ') cookie = cookie.substring(1,cookie.length);
        if (cookie.indexOf(key) == 0) return cookie.substring(key.length,cookie.length);
    }
    return null;
}\n";
}

sub ioctl {
    my $this = shift;
    $_ = shift;   # $_ is the ioctl request
    if (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/Category/) {
	return "System";
    }
    return undef;
}

sub ctrl_panel {
    my $this = shift;
    $ml = &get_obj("ML");
    my $out = $ml->h1("Login switcher");
    $this->{section_id} = $this->get_section_id || 0;
    $out .= $this->set_section_id;
    return $out if (! $this->{section_id} && $config{Login}{scope} ne "global");
    if ($this->{input}{uid}) {
	return $this->login($this->{input}{uid});
    }
    elsif ($this->{input}{user}) {
	$out .= $this->find_users();
	my $u = $this->{input}{user};
	my @user = $share{DB}->fetch_match($config{auth}{user_table},{section_id=>$this->{section_id},$config{auth}{user_login_column}=>"%$u%"});
	if ($share{DB}{map}->is_mapped($config{auth}{user_table},"name")) {
	    my @namecol = ref $config{auth}{user_name_column} eq "ARRAY" ?
		@{$config{auth}{user_name_column}} :
		($config{auth}{user_name_column});
	    foreach my $col (@namecol) {
		push @user, $share{DB}->fetch_match($config{auth}{user_table},{section_id=>$this->{section_id},$col=>"%$u%"});
	    }
	    # remove dupes
	    my %user = &keywise("login",\@user);
	    @user = values %user;
	}
	if (scalar @user > 0) {
	    $out .= $this->list_users($share{DB}->sort_rows($config{auth}{user_table},\@user,"login"));
	}
	else {
	    $out .= $ml->p("No matching users found.");
	}
    }
    else {
	$out .= $this->find_users();
	if ($share{DB}->count($config{auth}{user_table},{$config{auth}{user_gid_column}=>$this->{section_id}}) < 200) {
	    $out .= $this->list_users();
	}
    }
    return $out;
}

sub find_users {
    my $this = shift;
    my $f = new ExSite::FormBuilder();
    $f->input(name=>"user",prompt=>"User name or login ID",value=>$this->{input}{user},required=>1);
    $f->buttons(submit=>"find");
    return $f->make();
}

sub list_users {
    my $this = shift;
    my @user = scalar @_ > 0 ? @_ : $share{DB}->fetch_match($config{auth}{user_table},{section_id=>$this->{section_id}},$config{auth}{user_sort_column});
    my $out = $ml->h3("Select a user to switch to:");
    my $permdenied;
    my @ulist;
    foreach my $u (@user) {
	my $uname = $share{DB}->user_name($u);
	if (! $u->{$config{auth}{user_access_column}}) {
	    push @ulist, $ml->li("$uname ($u->{$config{auth}{user_login_column}}) [NO ACCESS]");
	}
	elsif (! $u->{$config{auth}{user_login_column}}) {
	    push @ulist, $ml->li("$uname [NO LOGIN ID]");
	}
	elsif (! $u->{$config{auth}{user_pwd_column}}) {
	    push @ulist, $ml->li("$uname [NO PASSWORD]");
	}
	elsif ($u->{$config{auth}{user_access_column}} < $share{DB}->level()) {
	    my $url = $this->link(uid=>$u->{$config{auth}{user_uid_column}});
	    push @ulist, $ml->li(
				 $ml->a("$uname ($u->{$config{auth}{user_login_column}})",{href=>$url,target=>"_blank"})
				 );
	}
	else {
	    push @ulist, $ml->li("$uname ($u->{$config{auth}{user_login_column}}) [PERMISSION DENIED]");
	    $permdenied = 1;
	}
    }
    $out .= $ml->ol(join("",@ulist));
    return $out;
}

sub login {
    my ($this,$uid) = @_;
    my $user = $share{DB}->fetch($config{auth}{user_table},$uid);
    if ($user) {
	if ($user->{$config{auth}{user_access_column}} < $share{DB}->level()) {
	    $share{DB}->clear_login;
	    $share{DB}->do_login($user);
	    my $s = new ExSite::Section(id=>$this->{section_id});
	    &redirect($s->get_url());
	    return;
	}
    }
    return $this->error("Sorry, you cannot switch to that user ID.");
}

1;

