package Modules::Forum;

use strict;
use ExSite::Config;
use ExSite::Forum;
use ExSite::Comment;
use ExSite::Misc;
use ExSite::Mail;
use ExSite::Util;
use ExSite::UI;
use ExSite::ReportBuilder;
use Modules::Content;

use vars qw(@ISA $ml $ui);
@ISA = qw(Modules::Content);

sub read {
    my ($this,$options) = @_;
    my $in = new ExSite::Input;
    $this->{input} = $in->combine;
    $this->{post} = $in->post;
    $this->{query} = $in->query;
}

sub write {
    my ($this,$options) = @_;
    my $out;
    my %opt = &DecodeString($options);
    $ml = &get_obj("ML");

    if ($opt{cmd} eq "recent") {
	return $this->recent_posts();
    }

    my $p = $share{Page};
    my $s = $p->my_section();
    #my @forums = $s->get_contents("forum");
    my @forums = $s->get_descendants("forum");
    my @throw;
    if (scalar @forums == 1) {
	my $f = new ExSite::Forum(data=>$forums[0]);
	return $f->show();
    }
    elsif (scalar @forums > 1) {
	foreach my $fdata (@forums) {
	    my $f = new ExSite::Forum(data=>$fdata);
	    push @throw, $ml->tr($ml->th($ml->a($f->title,{href=>$f->get_url}),{colspan=>4}));
	    my @thread = $f->fetch_current_threads();
	    foreach my $c (@thread) {
		push @throw, $ml->tr(
		    $ml->td($ml->a($c->title,{href=>$c->get_url})).
		    $ml->td($c->author).
		    $ml->td($c->posting_date).
		    $ml->td($c->thread_count())
		    );
	    }
	}
    }

    $out .= $ml->table(
	$ml->caption($msg{Forums}).
	$ml->thead(
	    $ml->th($msg{Topic}).$ml->th($msg{"Posted by"}).$ml->th($msg{"Started on"}).$ml->th($msg{Responses})
	).
	$ml->tbody(\@throw),
	{class=>"Forum"}
	);
    return $out;
}

sub ioctl {
    my ($this) = shift;
    $_ = shift;
    if (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/ModuleName/) {
	return "Forums";
    }
#    elsif (/Category/) {
#	return "CMS";
#    }
}

sub ctrl_panel {
    my $this = shift;
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    my $cmd = $this->{input}{cmd};
    my $id = $this->{input}{id};
    my $c = new ExSite::Content();
    $this->{content} = $c->get_content_obj($id);
    my $out = $ui->ToolBar(tools=>[
			       {label=>"All Forums",url=>$this->link(cmd=>undef,id=>undef)},
			       {label=>"Moderate",url=>$this->link(cmd=>"moderate")},
			       {label=>"Start a New Forum",url=>$this->link(id=>undef,cmd=>"newforum")}
			   ]);
    
    if ($cmd) {
	$out .= $this->pathbar($this->{content},linktypes=>"forum|comment");
	if ($cmd eq "conf") {
	    $out .= $this->configure($this->{content});
	}
	elsif ($cmd eq "edit") {
	    $out .= $this->update($this->{content}); #edit;
	}
	elsif ($cmd eq "moderate") {
	    $out .= $this->moderate;
	}
	elsif ($cmd eq "del") {
	    $out .= $this->delete;
	}
	elsif ($cmd =~ /^(publish|unpublish|reject|archive|approve)$/) {
	    $this->$1;
	    $out .= $this->show();
	}
	else {
	    $out .= $this->error("Unrecognized command: $cmd");
	}
    }
    elsif ($id) {
	$out .= $this->pathbar($this->{content},linktypes=>"forum|comment");
	$out .= $this->show;
    }
    else {
	$out .= $this->list_forums;
    }
    return $out;
}

sub recent_posts {
    my ($this,%opt) = @_;
    my $s = new ExSite::Section(data=>$share{DB}->this_site());
    if ($s->defined) {
	my $list;
	my @cdata;
	my $nforum == 0;
	my $format = $ml->p($ml->a("[[title]]",{href=>"[[url]]"}).
			    ", posted in ".$ml->em("[[forum]]").
			    " on [[date]], by [[author]]");
	foreach my $fdata ($s->get_descendants("forum")) {
	    $nforum++;
	    my $f = new ExSite::Forum(data=>$fdata);
	    push @cdata, $f->recent_comments();
	}
	if (scalar @cdata > 0) {
	    if ($nforum > 1) {
		@cdata = sort {$b->{ctime} cmp $a->{ctime}} @cdata;
	    }
	    my $ncom;
	    my $limit = $opt{limit} || $config{Forum}{recent_posts} || 3;
	    foreach my $cdata (@cdata) {
		$ncom++;
		my $c = new ExSite::Comment(data=>$cdata);
		$list .= $c->show_formatted($format,forum=>$c->thread_parent->title);
		last if ($limit && $ncom == $limit);
	    }
	}
	if ($list) {
	    return $ml->h1("Recent Posts").$ml->div($list,{class=>"Forum"});
	}
    }
    return undef;
}
	
sub list_forums {
    my $this = shift;
    my $c = new ExSite::Content();
    my $tree = $c->get_content_tree();
    my @forums = $tree->find({type=>$c->isubtype("forum")});
    my $r = new ExSite::ReportBuilder(title=>"Forums");
    $r->headers("Title","Location","Last Post","Posts","Published","Archived","Pending","Junk/Rejects");
    $r->nodata("No posts.");
    foreach my $forumdata (@forums) {
	my $forum = new ExSite::Forum(data=>$forumdata);
	next if (! $forum->allow("update"));
	my $section = $forum->my_section();
	my @data = ( 
	    $ml->a($forum->title,{href=>$this->link(id=>$forum->id)}),
	    );
	my $url = $forum->get_url;
	push @data, $ml->a($section->title,{href=>$url,target=>'_blank'});
	my %stat;
	my @com = $tree->find({type=>$c->isubtype("comment")},$forum->id);
	my $comment = new ExSite::Comment(data=>$com[-1]);
	push @data, $ml->a($comment->title,{href=>$this->link(id=>$comment->id)})." ".$comment->info();
	foreach my $cdata (@com) {
	    my $stat = $comment->wf_status($cdata->{status});
	    $stat{$stat}++;
	}
	my $drafts;
	if ($stat{draft}) {
	    $drafts = $ml->a($stat{draft},{href=>$this->link(id=>$forum->id,cmd=>"moderate")});
	}
	push @data, ( $ml->div(scalar @com,{class=>"num"}),
		      $ml->div($stat{published},{class=>"num"}),
		      $ml->div($stat{archived},{class=>"num"}),
		      $ml->div($drafts,{class=>"num"}),
		      $ml->div($stat{rejected},{class=>"num"})
	);
	$r->push(@data);
    }
    #$r->tools($ml->a("Start a new forum",{href=>$this->link(cmd=>"newforum")}));
    return $r->make();
}

sub show {
    my ($this) = @_;
    my $c = $this->{content};
    my $out;
    
    if ($c->subtype eq "forum") {
	$out .= $this->show_forum($c);
    }
    elsif ($c->subtype eq "comment") {
	$out .= $this->show_comment($c);
    }
    elsif (! $c->defined) {
	$out .= $this->warn("Nothing to show!");
    }
    else {
	$out .= $this->warn($ml->em(ucfirst $c->name)." is a ".$c->subtype()."; the Forum module can only be used to manage forums and their comments. Click on 'Top' to see a list of Forums.");
    }
    return $out;
}

sub show_forum {
    my ($this,$forum) = @_;
    return $this->error("Permission denied.") if (! $forum->allow("update"));
    my $out = $ui->ToolBar(
	tools=>[
	    {label=>"Start a new discussion",url=>$this->link(cmd=>"new")},
	    {label=>"Configure Forum",url=>$this->link(cmd=>"conf")},
	    undef,
	    {label=>"Delete",url=>$this->link(cmd=>"del"),confirm=>'Really unpublish and delete all discussions?',tone=>"bad"}
	]
	);
    my $tree = $forum->get_content_tree();
					 
    my $r = new ExSite::ReportBuilder(title=>$forum->title);
    $r->headers("Topic","Preview","Started on","Replies","Status");
    $r->nodata("No posts.");
    $r->set("dynamic",1);
    my @comment = $tree->get_child_data($forum->id);
    foreach my $cdata (reverse @comment) {
	my $comment = new ExSite::Comment(data=>$cdata);
	my $cid = $comment->id;
	my $ncomment = $tree->count({type=>$forum->isubtype("comment")},$cid)-1;
	my $errata;
	if ($ncomment > 1) {
	    $errata = "$ncomment replies";
	}
	elsif ($ncomment == 1) {
	    $errata = "1 reply";
	}
	my $status = $comment->showdata("status");
	my $url = $comment->link(_cms=>1,__uri=>$comment->get_uri());
	$r->push($ml->a($comment->title,{href=>$this->link(id=>$comment->id)})." by ".$comment->author,
		 $ml->a("preview",{href=>$url,target=>"_blank"}),
		 $comment->posting_date(),
		 $errata,
		 $ml->span($status,{class=>"status".ucfirst($status)})
	    );
    }
    $out .= $r->make();
    return $out;
}

sub show_comment {
    my ($this,$c) = @_;
    return $this->error("Permission denied.") if (! $c->allow("update"));
    $c->load_revision("newest");

    # show just this article
    my $pubtools;
    my $status = $c->wf_status();
    my $type = $c->subtype();
    my $out = $ui->ToolBar(
	tools=>[
	    {label=>"Edit",url=>$this->link(cmd=>"edit"),faicon=>"edit"},
	    {label=>"Configure",url=>$this->link(cmd=>"conf"),faicon=>"conf"},
	    {label=>"Preview",url=>$c->get_url_dynamic(),target=>"_blank",faicon=>"view"},
	    undef,
	    {label=>"Publish",url=>$this->link(cmd=>"publish"),faicon=>"publish"},
	    undef,
	    {label=>"Delete",confirm=>'Really unpublish and delete this $type?',url=>$this->link(cmd=>"del"),tone=>"bad",faicon=>"delete"}
	]
	);
    $out .= $ui->BasicBox(
	title=>$c->title." (".$status.")",
	pane=>$c->preview()
	);
    return $out;
}

# notify_post : inform moderator/administrator that a post was received

sub notify_post {
    my ($this,$comment) = @_;
    # find moderator
    my %role = $comment->all_roles();
    my $keys = $role{moderator} || $role{administrator};
    if ($keys) {

	# build notification message

	my $ml = &get_obj("ML");
	my $f = $comment->thread_parent();
	my $title = $f->title;
	my $s = $comment->my_section();
	my $time = new ExSite::Time();
	my $intro = $ml->p("Comment posted to ".
			   $ml->em("[[title]]")." forum, at [[time]]:");
	my $message = &substitute($intro,{title=>$title,time=>$time->write("datetime2")});
	$message .= $ml->div($comment->show_comment(tools=>0),
			     {style=>"border:1px dashed red; padding:20px;"});

	# mod link should go to regular forum view if message is published
	if ($comment->is_active()) {
	    # post-moderation
	    $message .= $ml->p($ml->a("Click here to review comments.",
				      {href=>$s->get_server."$config{server}{CGIpath}/$config{prog}{admin}/Forum?id=".$f->id}));
	}
	else {
	    # pre-moderation
	    $message .= $ml->p($ml->a("Click here to moderate comments.",
				      {href=>$s->get_server."$config{server}{CGIpath}/$config{prog}{admin}/Forum?id=".$f->id."&cmd=moderate"}));
	}

	foreach my $uid (keys %$keys) {
	    my $user = $share{DB}->fetch($config{auth}{user_table},$uid);
	    if ($user) {
		my $modemail = $user->{$config{auth}{user_email_column}};
		if ($modemail) {
		    &ExSite::Mail::send(
			 to=>$modemail,
			 from=>$modemail,
			 subject=>"Comment posted to $title",
			 body=>$message,
			);
		}
	    }
	}
    }
}

sub moderate {
    my $this = shift;
    my $out;
    if (scalar keys %{$this->{post}} > 0) {
	#return "nothing done!";
	my @id;
	foreach my $key (keys %{$this->{post}}) {
	    $key =~ /comment_(\d+)/;
	    push @id, $1 if ($1);
	}
	if (scalar @id > 0) {
	    my $napprove = 0;
	    my $modfunc = $this->{post}{moderate};
	    foreach my $id (@id) {
		my $comment = new ExSite::Comment(id=>$id);
		if ($comment->subtype eq "comment") {
		    if ($comment->allow("moderate")) {
			if ($modfunc =~ /delete/) {
			    $comment->delete();
			}
			elsif ($modfunc =~ /reject/) {
			    $comment->wf_reject();
			}
			elsif ($modfunc =~ /approve/) {
			    $comment->wf_publish();
			    $napprove++;
			}
		    }
		}
	    }
#	    if ($napprove > 0) {
#		# republish forum
#		$this->{content}->publish();
#	    }
	}
    }
    my $c = $this->{content};
    my $tree = $c->get_content_tree();
    my @new_comments = $tree->find({type=>$c->isubtype("comment"),status=>$c->wf_istatus("draft")},$c->id);
    my $tout;
    my $top_buttons = $ml->div(
	$ml->a(undef,{name=>"top"}).
	$ml->input(undef,{type=>"button",value=>"select all",id=>"modSelectAll"}).
	$ml->input(undef,{type=>"button",value=>"un-select all",id=>"modUnselectAll"}).
	$ml->a("Goto bottom",{class=>"button bottombutton",href=>"#bottom"}),
	{class=>"forumModerateButtons"}
	);
    my $bot_buttons = $ml->div(
	$ml->a(undef,{name=>"bottom"}).
	$ml->input(undef,{type=>"submit",class=>"approve",name=>"moderate",value=>"approve &amp; publish"}).
	$ml->input(undef,{type=>"submit",class=>"reject",name=>"moderate",value=>"reject"}).
	$ml->input(undef,{type=>"submit",class=>"reject",name=>"moderate",value=>"delete"}).
	$ml->a("Back to top",{class=>"button topbutton",href=>"#top",}),
	{class=>"forumModerateButtons"}
	);

    foreach my $c (@new_comments) {
	my $comment = new ExSite::Comment(data=>$c);
	$tout .= $ml->tr(
	    $ml->td($ml->input(undef,{name=>"comment_".$comment->id,type=>"checkbox",class=>"forumModerateCheck"})).
	    $ml->td($comment->show_comment())
	    );
    }
    $out .= $ui->BasicBox(
	title=>scalar @new_comments . " comments awaiting moderation.",
	pane=>$ml->form(
	    $ml->div(
		$top_buttons.
		$ml->table($tout,{class=>"forumModerate"}).
		$ml->a(undef,{name=>"bottom"}).$bot_buttons,
		{id=>"forumModeration"}
	    ),
	    {method=>"post",action=>$this->link()}
	)
	);
    return $out;
}

sub delete {
    my ($this) = @_;
    my $p = $this->{content}->parent();
    my $c = $this->{content}->delete();
    $ml->redirect($this->link(__plaintext=>1,cmd=>undef,id=>$p->id));
    return;
}

# status changes

sub publish {
    my $this = shift;
    #$this->{content}->wf_publish();
    $this->{content}->publish();
    return;
}

sub unpublish {
    my $this = shift;
    #$this->{content}->wf_draft();
    $this->{content}->unpublish();
    return;
}

1;
