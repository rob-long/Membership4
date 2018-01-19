package Modules::Blog;

### TODO:
# overview - hyperlink addenda if pending comments
# make link button work, or remove it

use strict;
use ExSite::Config;
use ExSite::Blog;
use ExSite::Misc;
use ExSite::Util;
use ExSite::UI;
use ExSite::ReportBuilder;
use Modules::Content;

use vars qw(@ISA $ui $ml %status);
@ISA = qw(Modules::Content);

%status = (
    active => "published",
    disabled => "draft",
    archived => "archived",
    pending => "awaiting approval",
    rejected => "rejected",
    queued => "queued"
    );

sub write {
    my ($this,$options) = @_;
    my $out;
    my $ml = &get_obj("ML");
    my $p = $share{Page};
    my $s = $p->my_section();
    my @blogs = $s->get_descendants("blog");
    my @throw;
    if (scalar @blogs == 1) {
	my $b = new ExSite::Blog(data=>$blogs[0]);
	return $b->show();
    }
    elsif (scalar @blogs > 1) {
	foreach my $bdata (@blogs) {
	    my $b = new ExSite::Blog(data=>$bdata);
	    next if ($b->wf_status ne "published");
	    push @throw, $ml->tr($ml->th($b->title,{colspan=>2,class=>"blogTitleTH"}));
	    my @art = $b->fetch_current_articles();
	    foreach my $a (@art) {
		push @throw, $ml->tr(
		    $ml->td($ml->a($a->title,{href=>$a->get_url})).
		    $ml->td($a->posting_date)
		    );
	    }
	}
    }
    else {
	# no blogs
	return $ml->("No blogs are available for viewing.");
    }

    $out .= $ml->table(
	$ml->caption($msg{Blogs}).
	$ml->thead(
	    $ml->th($msg{"Title"}).$ml->th($msg{"Posted on"})
	).
	$ml->tbody(\@throw),
	{class=>"Blog"}
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
	return "Blogs";
    }
    elsif (/Category/) {
	return "CMS";
    }
}

sub ctrl_panel {
    my $this = shift;
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    my $out = &insert_js("misc");
    my $cmd = $this->{input}{cmd};
    my $id = $this->{input}{id};
    my $c = new ExSite::Content();
    $this->{content} = $c->get_content_obj($id);
    
    if ($id) {
	$out .= $this->pathbar($this->{content},linktypes=>"blog|article|comment");

	$out .= $this->show;
    }
    elsif ($cmd) {
	$out .= $this->pathbar($this->{content},linktypes=>"blog|article|comment");
	if ($cmd eq "newblog") {
	    $out .= $this->newblog;
	}
	elsif ($cmd eq "search") {
	    $out .= $this->search($this->{content},type=>"article");
	}
	elsif ($cmd) {
	    $out .= $this->error("Unrecognized command: $cmd");
	}
    }
    else {
	$out .= $this->list_blogs;
    }
    return $out;
}

sub list_blogs {
    my $this = shift;
    my $c = new ExSite::Content();
    my $tree = $c->get_content_tree();
    my @blogs = $tree->find({type=>$c->isubtype("blog")});
    my $r = new ExSite::ReportBuilder(title=>"Blogs");
    $r->headers("Blog Title","Location","Posts","Last Post");
    $r->nodata("No posts.");
    foreach my $blogdata (@blogs) {
	my $blog = new ExSite::Blog(data=>$blogdata);
	next if (! $blog->allow("insert"));
	my $section = $blog->my_section();
	my @data = (
	    $ml->a($blog->title,{href=>$this->link(id=>$blog->id)}),
	    );
	my $url = $blog->get_url_canonical;
	#push @data, $ml->a($section->title,{href=>$url,target=>'_blank'});
	push @data, $section->label;
	my @art = $tree->find({type=>$c->isubtype("article")},$blog->id);
	push @data, $ml->div(scalar @art,{class=>"num"});
	if (scalar @art > 0) {
	    my $article = new ExSite::Article(data=>$art[-1]);
	    push @data, $ml->a($article->title,{href=>$this->link(id=>$article->id)})." ".$article->content_info();
	}
	else {
	    push @data, "";
	}
	$r->push(@data);
    }
    $r->tools($ml->a("Start a new blog",{href=>$this->link(cmd=>"newblog")}));
    return $r->make();
}

sub show {
    my ($this) = @_;
    my $c = $this->{content};
    my $out;
    if ($c->subtype eq "blog") {
	$out .= $this->show_blog($c);
    }
    elsif ($c->subtype eq "article") {
	$out .= $this->show_article($c);
    }
    elsif ($c->subtype eq "comment") {
	$out .= $this->show_comment($c);
    }
    else {
	$out .= $this->warn($ml->em(ucfirst $c->name)." is a ".$c->subtype()."; the Blog module can only be used to manage Blogs, Articles, and their Comments. Click on 'Top' to see a list of Blogs.");
    }
    return $out;
}

sub show_blog {
    my ($this,$blog) = @_;
    return $this->error("Permission denied.") if (! $blog->allow("insert"));
    my $cmd = $this->{input}{cmd};
    my $out = $ui->ToolBar(
	cmd=>$cmd,
	tools=>[
	    {label=>"Post a new article", url=>$this->link(cmd=>"new"), faicon=>"edit", tone=>"good", cmd=>"new"},
	    {label=>"Configure blog", url=>$this->link(cmd=>"conf"), faicon=>"conf", cmd=>"conf"},
	    {label=>"Search all posts", url=>$this->link(cmd=>"search"), faicon=>"search", cmd=>"search"},
	    {label=>"Publish", url=>$this->link(cmd=>"publish"), faicon=>"publish", cmd=>"publish"},
	    {label=>"Delete", url=>$this->link(cmd=>"del"), faicon=>"delete", tone=>"bad", confirm=>'Really unpublish and delete all articles?'},
	]
	);

    if ($cmd eq "new") {
	$out .= $this->newarticle();
    }
    elsif ($cmd eq "conf") {
	$out .= $this->configure($this->{content});
    }
    elsif ($cmd eq "del") {
	$out .= $this->delete();
    }
    elsif ($cmd eq "publish") {
	$this->publish($this->{content});
    }
    elsif ($cmd eq "search") {
	$out .= $this->search($this->{content},type=>"article");
    }
    elsif ($cmd) {
	$out .= $this->error("Unrecognized command: $cmd");
    }
    else {
	my $tree = $blog->get_content_tree();
	my $r = new ExSite::ReportBuilder(title=>$blog->title);
	$r->headers("Post Title","Preview","Posted on","Addenda","Status");
	$r->nodata("No posts.");
	$r->set("dynamic",1);
	my @article = $blog->fetch_articles();
	foreach my $adata (@article) {
	    my $article = new ExSite::Article(data=>$adata);
	    my $aid = $article->id;
	    my $ncomment = $tree->count({type=>$blog->isubtype("comment")},$aid);
	    my $ncontent = $tree->count({type=>$blog->isubtype("content")},$aid);
	    my $nother = $tree->count({type=>$blog->isubtype("content")},$aid)-$ncomment-$ncontent-1;
	    my @errata;
	    if ($ncontent > 0) {
		push @errata, "$ncontent attachment".($ncontent>1?"s":"");
	    }
	    if ($ncomment > 0) {
		push @errata, "$ncomment comment".($ncomment>1?"s":"");
	    }
	    if ($nother > 0) {
		push @errata, "$ncontent other item".($nother>1?"s":"");
	    }
	    my $errata = join "; ", @errata;
	    my $status = $article->showdata("status");
	    #my $url = $article->get_url;
	    my $url = $article->link(_cms=>1,__uri=>$article->get_uri());
	    my $title = $article->title;
	    if ($article->flag("sticky")) {
		$title = $ui->FAIcon("star").$title;
	    }
	    $r->push($ml->a($title,{href=>$this->link(id=>$article->id)}),
		     $ml->a("preview",{href=>$url,target=>"_blank"}),
		     $article->posting_date(),
		     $errata,
		     $status eq "published" ? $ml->span($status,{class=>"help"}) : $ml->span($status,{class=>"error"})
		);
	}
	$out .= $r->make();
    }
    return $out;
}

sub show_article {
    my ($this,$art) = @_;
    return $this->error("Permission denied.") if (! $art->allow("update"));
    my $out;
    $art->load_revision("newest");
    my @wftools = ($this->schedule_tool($art), $this->wf_tools($art) );
    if ($art->is_published && -e "$config{server}{CGIroot}/Modules/SocialMedia.pm") {
	unshift @wftools, {label=>"Share", faicon=>"social", url=>"javascript:openOLFrame('$config{server}{CGIpath}/$config{prog}{admin}/SocialMedia?id=".$art->id."')" };
	$out .= $ui->OverlayFrame();
    }

    # show just this article
    my $cmd = $this->{input}{cmd};
    $out = $ui->ToolBar(
	cmd=>$cmd,
	tools=>[
	    {label=>"Preview",url=>$this->link(cmd=>undef),faicon=>"view",cmd=>undef},
	    {label=>"Edit",url=>$this->link(cmd=>"edit"),faicon=>"edit",cmd=>"edit"},
	    {label=>"Configure",url=>$this->link(cmd=>"conf"),faicon=>"conf",cmd=>"conf"},
	    {label=>"Images",url=>$this->link(cmd=>"images"),faicon=>"image",cmd=>"images"},
	    {label=>"Tags",url=>$this->link(cmd=>"tags"),faicon=>"tag",cmd=>"tags"},
	    {label=>"Metadata",url=>$this->link(cmd=>"meta"),faicon=>"meta",cmd=>"meta"},
	    undef,
	    @wftools,
	    undef,
	    {label=>"Delete",tone=>"bad",confirm=>'Really unpublish and delete this article?',url=>$this->link(cmd=>"del"),faicon=>"delete"},
	]
	);

    my $cmd = $this->{input}{cmd};
    if ($cmd eq "conf") {
	$out .= $this->configure($art);
    }
    elsif ($cmd eq "edit") {
	$out .= $this->update;
    }
    elsif ($cmd eq "del") {
	$out .= $this->delete;
    }
    elsif ($cmd eq "tags") {
	$out .= $this->tags($art);
    }
    elsif ($cmd eq "meta") {
	$out .= $this->metadata($art,specific=>0);
    }
    elsif ($cmd =~ /^image/) {
	$out .= $this->images($art);
    }
    elsif ($cmd =~ /^schedule/) {
	$out .= $this->schedule($art);
    }
    elsif ($cmd =~ /^(publish|unpublish|queue|unqueue|draft|archive|submit|approve|reject|cancel)$/) {
	$out .= $this->$1($art);
	$ml->location($this->link(__plaintext=>1,cmd=>undef));
    }
    elsif ($cmd) {
	$out .= $this->error("Unrecognized command: $cmd");
    }
    else {
	#$out .= $this->preview_article($art);
	$out .= $this->preview($art);
    }

    return $out;
}

sub preview_article {
    my ($this,$art) = @_;
    my $preview_btn = $ui->Button(type=>"link-button",label=>"preview on website",url=>$ui->OLFrameLink($art->link("_cms"=>1,"__page"=>1)),faicon=>"view");
    return $ui->BasicBox(
	title=>$art->name.$ml->span($ui->FAIcon($ExSite::Workflow::wf_action[$art->wf_istatus()]).$art->wf_status(),{class=>"articleStatus"}),
	pane=>$art->preview().$ml->p($preview_btn)
	).
	$ui->OverlayFrame();
    # comments
}

sub show_comment {
    my ($this,$c) = @_;
    return $this->error("Permission denied.") if (! $c->allow("update"));
    $c->load_revision("newest");

    # show just this article
    my $pubtools;
    my $status = $c->wf_status;
    my $cmd = $this->{input}{cmd};
    my $out = $ui->ToolBar(
	cmd=>$cmd,
	tools=>[
	    { label=>"Edit", url=>$this->link(cmd=>"edit"), faicon=>"edit", cmd=>"edit"},
	    { label=>"Configure", url=>$this->link(cmd=>"conf"), faicon=>"conf", cmd=>"conf" },
	    { label=>"Delete", url=>$this->link(cmd=>"del"), faicon=>"delete", confirm=>"Really delete comment?", tone=>"bad", cmd=>"del" },
	]
	);
    if ($cmd eq "conf") {
	$out .= $this->configure($this->{content});
    }
    elsif ($cmd eq "edit") {
	$out .= $this->update($this->{content});
    }
    elsif ($cmd eq "del") {
	$out .= $this->delete();
    }
    $out .= $ui->BasicBox(
	title=>$c->name." ($status)",
	pane=>$c->preview());
    return $out;
}

sub update {
    my $this = shift;
    my $c = $this->{content};
    my $type = $c->subtype();
    if ($type !~ /article|comment/) {
	return $this->error("Cannot edit ${type}s");
    }
    return $this->SUPER::update($c,format=>$type eq "article" ? "html" : undef);
}

sub newarticle {
    my $this = shift;
    my $c = $this->{content};
    if (! $c->allow("insert")) {
	return $this->error("Sorry, you do not have permission to post here.");
    }
    my $out;
    if (scalar keys %{$this->{post}} > 0) {
	my %post = $share{DB}->parse_parts(%{$this->{post}});
	if ($post{title} && $post{article}) {
	    my $status;
	    if ($this->{post}{_save} =~ /draft/i) {
		$status = $c->wf_istatus("draft");
	    }
	    elsif ($this->{post}{_save} =~ /queue/i) {
		$status = $c->wf_istatus("queued");
	    }
	    else {
		$status = $c->wf_istatus("approved");
	    }
	    my %adata = $c->new_content(
		title=>$post{title},
		parent=>$c->id,
		status=>$status,
		type=>$c->isubtype("article"),
		);
	    if ($adata{content_id}) {
		my $art = new ExSite::Article(data=>\%adata);
		$art->revise(data=>$post{article},format=>"text");
		if ($this->{post}{_save} =~ /publish/i) {
		    if ($art->allow("publish")) {
			$art->wf_publish();
		    }
		    else {
			$out .= $art->error("Article saved, but you do not have the necessary permissions to publish.");
			return $out;
		    }
		}
		$ml->redirect($this->link(__plaintext=>1,id=>$art->id,cmd=>undef));
	    }
	    else {
		$out .= $c->show_diagnostics("error","html");
	    }
	}
	else {
	    $out .= $this->error("Missing title or article body.");
	}
    }
    else {
	$out .= $ml->h1("New Article");
	my $db = $share{DB};
	my $f = $db->form();
	$f->input(name=>"title",prompt=>"Title",type=>"text",size=>80,required=>1);
	$db->input_htmleditor(
	    prompt=>"Article",
	    name=>"article",
	    value=>"",
	    editor_height=>350,
	    editor_width=>550,
	    required=>1
	    );
	$f->set("buttons",
		$ml->input(undef,{type=>"submit",name=>"_save",value=>"Save and publish"}).
		$ml->input(undef,{type=>"submit",value=>"Save",title=>"allows you to preview/proofread before publishing"}).
		$ml->input(undef,{type=>"submit",name=>"_save",value=>"Save as draft",title=>"more editing needed, article will not be published"}).
#		$ml->input(undef,{type=>"submit",name=>"_save",value=>"Queue"}).
		$ml->input(undef,{type=>"button",value=>"Cancel",class=>"formButton cancel",onclick=>"javascript:history.back()"}).
		$ml->input(undef,{type=>"reset"}));
	$out .= $db->form->make();
#	$out .= $ml->br.$ui->HelpBox(
#	    title=>"Saving your work",
#	    pane=>$ml->div($ml->b("Publish:")." publishes the article immediately").
#	    $ml->div($ml->b("Save:")." allows you to preview/proofread before publishing").
#	    $ml->div($ml->b("Save as draft:")." more editing needed, the article will not be published").
#	    $ml->div($ml->b("Queue:")." the article will be published automatically at a later time by the queuing system"));
    }
    return $out;
}

sub newblog {
    my $this = shift;
    my $c = $this->{content};
    my $out;
    if (scalar keys %{$this->{post}} > 0) {
	my %post = $share{DB}->parse_parts(%{$this->{post}});
	if ($post{title}) {
	    my %adata = $c->new_content(
		title=>$post{title},
		parent=>$c->id,
		status=>$c->wf_istatus("draft"),
		type=>$c->isubtype("article"),
		);
	    if ($adata{content_id}) {
		my $art = new ExSite::Article(data=>\%adata);
		$art->revise(data=>$post{article},format=>"text");
		$ml->redirect($this->link(__plaintext=>1,id=>$art->id,cmd=>undef));
	    }
	    else {
		$out .= $c->show_diagnostics("error","html");
	    }
	}
	else {
	    $out .= $this->error("Missing title or article body.");
	}
    }
    else {
	$out .= $ml->h1("Start A New Blog");
	my $db = $share{DB};
	my $f = $db->form;
	$out .= $ui->HelpBox(title=>"Help",pane=>"A blog is a collection of articles or posts. The blog title is the overall name for all of your posts, for example 'News and Announcements'. It is not the title of an individual post. To make an individual post, go into the blog and click 'post a new article'.",size=>"m");
	$f->input(name=>"title",prompt=>"Blog Title",size=>40,required=>1);
	$out .= $f->make();
    }
    return $out;
}

sub delete {
    my ($this) = @_;
    my $c = $this->{content};
    my $p = $c->parent();
    $c->unpublish();
    $c->delete();
    $ml->redirect($this->link(__plaintext=>1,cmd=>undef,id=>$p->id));
    return;
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
	my $art = $comment->thread_parent();
	my $title = $art->title;
	my $blog = $art->parent;
	my $s = $comment->my_section();
	my $time = new ExSite::Time();
	my $intro = $ml->p("Comment posted to ".
			   $ml->em("[[title]]")." in [[blog]], at [[time]]:");
	my $message = &substitute($intro,{title=>$title,blog=>$blog->title,time=>$time->write("datetime2")});
	$message .= $ml->div($comment->show_comment(tools=>0),
			     {style=>"border:1px dashed red; padding:20px;"});

	# mod link should go to regular forum view if message is published
	$message .= $ml->p($ml->a("Click here to review comments.",
				  {href=>$s->get_server."$config{server}{CGIpath}/$config{prog}{admin}/Blog?id=".$art->id}));

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

1;
