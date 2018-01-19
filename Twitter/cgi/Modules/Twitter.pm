package Modules::Twitter;
#----------------------------------------------------------------------------
#   This plug-in uses HTML adapted from http://twitter.com/badges/html
#   That HTML code is Copyright Twitter.
#
#   If you want to post Twitter updates, then this plug-in requires 
#   the following Perl Modules:
#       Net::Twitter
#       JSON::Any
#       LWP::UserAgent
#   If you merely want to echo a Twitter log, then it requires no
#   special modules.
#-----------------------------------------------------------------------
#
#   Everything else is:
#   Copyright 2001-2007 Exware Solutions, Inc.  http://www.exware.com
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

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Section;
use ExSite::ML;

# inherit from BaseDCD class
use Modules::BaseDCD;
use vars qw(@ISA);
@ISA = qw(Modules::BaseDCD);

sub write {
    my ($this,$options) = @_;
    my ($out,$out_tweet);
    my %opt = &DecodeString($options);
    my $tw_title = $opt{title} || $config{Twitter}{title} || "Twitter Updates";
    my $tw_user = $opt{user} || $config{Twitter}{user};
    my $tw_count = $opt{count} || $config{Twitter}{count} || 5;
    my $rpp_count = $opt{rpp_count} || $config{Twitter}{rpp_count} || 5;
    my $tw_admin_level = $config{Twitter}{admin_level} || 3;
    
    my $ml = new ExSite::ML;

    # post tweets

    if ($config{Twitter}{allow_post}) {
	if ($config{Twitter}{password} && 
	    $share{DB}->level() >= $tw_admin_level) {
	    # we think we have twitter privs, and we do have local privs
	    if (eval "require Net::Twitter") {
		# the twitter API is available

		# display a twitter form
		my $url = $this->link();
		$out_tweet = "<form action=\"$url\" method=\"post\">
<input type=\"text\" name=\"tweet\" size=\"20\">
<input type=\"submit\" value=\"Tweet!\">
</form>\n";
		if ($this->{input}{tweet}) {
		    # we have form input; post it back to twitter
		    my $tw_pass = $config{Twitter}{password};
		    if ($tw_pass) {
			my $tw = new Net::Twitter(user=>$tw_user,
						  password=>$tw_pass);
			$tw->update($this->{input}{tweet});
		    }
		}
	    }
	}
	elsif ($share{Page} && $share{Page}->is_publishing()) {
	    # static page; hide the twitter form until we can authenticate the user
	    my $url = $this->link();
	    $out_tweet = "<p><a href=\"$url\">tweet!</a></p>\n";
	}
    }
    
    # display recent tweets

    $out .= "
<h2 class=\"twitter-title\">$msg{$tw_title}</h2>
<ul id=\"twitter_update_list\"></ul>
<script type=\"text/javascript\" src=\"http://twitter.com/javascripts/blogger.js\"></script>
<script text=\"text/javascript\" src=\"https://api.twitter.com/1/statuses/user_timeline.json?callback=twitterCallback2&screen_name=$tw_user&count=$tw_count\"></script>\n";

    my @search_tags = split(",",$config{Twitter}{search_tags});
    my @search_terms = split(",",$config{Twitter}{search_terms});
    my $search_tag_results;
    my $search_term_results;
    
    my $search_results_display = <<END;
<script type="text/javascript">
function relative_time2(time_value) {
	var values = time_value.split(" ");
	time_value = values[1] + " " + values[2] + ", " + values[4] + " " + values[3];
	var parsed_date = Date.parse(time_value);
	var relative_to = (arguments.length > 1) ? arguments[1] : new Date();
	var delta = parseInt((relative_to.getTime() - parsed_date) / 1000);
	delta = delta + (relative_to.getTimezoneOffset() * 60);

	if (delta < 60) {
		return 'less than a minute ago';
	} else if(delta < 120) {
		return 'about a minute ago';
	} else if(delta < (60*60)) {
		return (parseInt(delta / 60)).toString() + ' minutes ago';
	} else if(delta < (120*60)) {
		return 'about an hour ago';
	} else if(delta < (24*60*60)) {
		return 'about ' + (parseInt(delta / 3600)).toString() + ' hours ago';
	} else if(delta < (48*60*60)) {
		return '1 day ago';
	} else {
		return (parseInt(delta / 86400)).toString() + ' days ago';
	}
}

function twitterSearch(obj) {	
	var tDiv = document.getElementById("twitter_search_results");	
	var user, tweet, postedAt, userURL, out, reply_url, view_tweet_url;
	out = "";

	for (i=0;i<obj.results.length;i++) {	
	    user = obj.results[i].from_user;
	    userURL = "http://twitter.com/" + user;
	    tweet = obj.results[i].text;
	    postedAt = obj.results[i].created_at;
	    reply_url = "http://twitter.com/?status=@" + user + " &in_reply_to_status_id=" + obj.results[i].id_str + "&in_reply_to=" + user;
	    view_tweet_url = "http://twitter.com/" + user + "/statuses/" + obj.results[i].id_str;
	    
	    out += "<li><a href='" + userURL + "'>" + user + "</a>: " + tweet + " <a style='font-size:85%' href='" + view_tweet_url + "'>" + relative_time2(postedAt) + "</a></li>";
	    // out += " - <a href='" + reply_url + "'>Reply</a></li>";
	}	
	tDiv.innerHTML += "<ul id='twitter_update_list'>" + out + "</ul>";
}
</script>
END

    if (@search_tags > 0) {
    	foreach my $search_tag (@search_tags) {
    		$search_tag_results .= $ml->h2($search_tag, { class => "twitter-title" });
    		$search_tag_results .= "<script text=\"text/javascript\" src=\"http://search.twitter.com/search.json?callback=twitterSearch&tag=$search_tag&rpp=$rpp_count\"></script>\n";
    	}
    }
    if (@search_terms > 0) {
    	foreach my $search_term (@search_terms) {
    		$search_tag_results .= $ml->h2($search_term, { class => "twitter-title" });
    		$search_tag_results .= "<script text=\"text/javascript\" src=\"http://search.twitter.com/search.json?callback=twitterSearch&q=$search_term&rpp=$rpp_count\"></script>\n";
    	}
    }
 
    return "<!-- Begin Twitter -->
<div id=\"twitter_div\">
$out
$out_tweet
</div>
<div id=\"twitter_search_results\">
$search_results_display
$search_tag_results
$search_term_results
</div>
<!-- End Twitter -->\n";
}

sub ioctl {
    my $this = shift;
    $_ = shift;   # $_ is the ioctl request
    if (/ModuleInfo/) {
	return "The Twitter applet displays your recent \"tweets\" on a 
web page.  Among other things, this allows you to update your site from 
a cell phone.  It can also serve as a live update feature that lets you 
blast updates to your user's cell phones or IM programs.  Go to 
Twitter.com for more info.";
    }
    elsif (/ControlPanel/) {
	return \&write;
    }
    elsif (/Category/) {
	return ["Social", "Applications"];
    }
    elsif (/Size/) {
	return "small";
    }
    elsif (/PublishRule/) {
	return "static";
    }
    return;
}

1;

