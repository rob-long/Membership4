package Modules::Comments;

use strict;
use ExSite::Config;
use ExSite::Forum;
use ExSite::Comment;
use ExSite::Misc;
use ExSite::Mail;
use ExSite::Util;
use ExSite::UI;
use ExSite::ReportBuilder;
use Modules::BaseDCD;

use vars qw(@ISA $ml $ui);
@ISA = qw(Modules::BaseDCD);

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
    return $this->recent_posts(%opt);
}

sub ioctl {
    my ($this) = shift;
    $_ = shift;
    if (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/ModuleName/) {
	return "Comments";
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
    my $out = $this->moderate();
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
	my @cdata = $share{DB}->sort_rows("content",scalar $s->get_descendants("comment"),"ctime","content_id");
	if (scalar @cdata > 0) {
	    my $ncom;
	    my $limit = $opt{limit} || $config{Comments}{limit} || 3;
	    foreach my $cdata (reverse @cdata) {
		my $c = new ExSite::Comment(data=>$cdata);
		next if (! $c->is_viewable);
		$ncom++;
		$list .= $c->show_formatted($format,forum=>$c->thread_parent->title);
		last if ($ncom >= $limit);
	    }
	}
	if ($list) {
	    return $ml->h1("Recent Posts").$ml->div($list,{class=>"Forum"});
	}
    }
    return undef;
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
	    {label=>"Delete",confirm=>'Really unpublish and delete this $type?',url=>$this->link(cmd=>"del"),tone=>"bad"}
	]
	);
    $out .= $ui->BasicBox(
	title=>$c->title." (".$status.")",
	pane=>$c->preview()); #$c->show_formatted($format));
	#pane=>$c->show()); #$c->show_formatted($format));

    return $out;
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
	}
	# uncache the tree
	delete $share{content}{tree};
    }
    my $c = $this->{content};
    my $tree = $c->get_content_tree();
    my @new_comments = $tree->find({type=>$c->isubtype("comment"),status=>$c->wf_istatus("submitted")},$c->id);
    if (scalar @new_comments == 0) {
	return $ml->p("No new comments requiring moderation.");
    }

    my $tout;
#	$ml->a(undef,{name=>"top"}).
    my $top_buttons = $ui->ToolBar(
	tools=>[
	    {label=>"select all",id=>"modSelectAll"},
#	$ml->input(undef,{type=>"button",value=>"select all",id=>"modSelectAll"}).
	    {label=>"un-select all",id=>"modUnselectAll"},
#	$ml->input(undef,{type=>"button",value=>"un-select all",id=>"modUnselectAll"}).
	    {label=>"goto bottom",type=>"link-button",class=>"bottombutton",url=>"#bottom"},
	]);
#	$ml->a("Goto bottom",{class=>"button bottombutton",href=>"#bottom"}),
#	{class=>"forumModerateButtons"}
#	);

#	$ml->a(undef,{name=>"bottom"}).
    my $bot_buttons = $ml->div(
	$ml->input(undef,{type=>"submit",class=>"approve",name=>"moderate",value=>"approve &amp; publish"}).
	$ml->input(undef,{type=>"submit",class=>"reject",name=>"moderate",value=>"reject"}).
	$ml->input(undef,{type=>"submit",class=>"reject",name=>"moderate",value=>"delete"}).
	$ml->a("Back to top",{class=>"button topbutton",href=>"#top"}),
	{class=>"forumModerateButtons"}
	);

    my $format = $ml->div(
	$ml->h3($ml->a(undef,{name=>"Comment[[id]]"})."[[title]]",{class=>"commentSubject",id=>"Comment[[id]]"}).
	$ml->div($msg{"Posted in [[ptype]] ".$ml->em("[[container]]")." on [[date]], by [[author]]"},{class=>"commentAbout"}).
	$ml->div("[[html]]",{class=>"commentBody"}).
	"[[attachments]]",
	{class=>"commentWrapper"});
    foreach my $c (@new_comments) {
	my $comment = new ExSite::Comment(data=>$c);
	my $container = $comment->thread_parent();
	$tout .= $ml->tr(
	    $ml->td($ml->input(undef,{name=>"comment_".$comment->id,type=>"checkbox",class=>"forumModerateCheck"})).
	    $ml->td($comment->show_formatted($format,ptype=>$container->subtype,container=>$container->title()))
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

1;
