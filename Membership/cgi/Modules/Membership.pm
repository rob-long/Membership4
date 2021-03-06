package Modules::Membership;

use strict;
use ExSite::Config;
use ExSite::Blog;
use ExSite::Misc;
use ExSite::Util;
use ExSite::HTML;
use ExSite::ReportBuilder;
use Modules::Content;
use Modules::Membership::Type;
use Modules::Membership::Profile;
use Modules::Membership::Directory;

use vars qw(@ISA $ml $ui @status);
@ISA = qw(Modules::Content);

sub my_subtype { return "membership"; }

sub read {
    my ($this,$options) = @_;
    my $in = new ExSite::Input;
    $this->{input} = $in->combine;
    $this->{query} = $in->query;
    $this->{post} = $in->post;
    $this->{is_post} = scalar %{$this->{post}};
    $this->setup_querylib();
    $ml = &get_obj("ML");
}

sub write {
    my ($this,$options) = @_;
    my $out;
    my $c = new ExSite::Content();
    my $content;
    my %opt = &DecodeString($options);
    if ($opt{id}) {
    $content = $c->get_content_obj($opt{id});
    delete $opt{id};
    }
    elsif ($opt{name}) {
    # context-dependent
    $content = $share{Page}->find($opt{name});
    delete $opt{name};
    }
    elsif ($opt{path}) {
    if ($opt{path} =~ /^\//) {
        # full path
        $content = $c->path_to_obj($opt{path});
    }
    else {
        # find under this page
        $content = $c->path_to_obj($opt{path},$share{Page}->id);
    }
    delete $opt{path};
    }

    if ($opt{pro} eq "advanced_search") {
        my $tree = $c->get_content_tree();
        my @types = $tree->find({type=>$c->isubtype("membership_type")});
        foreach my $typedata (@types) {
            my $type = new Modules::Membership::Type(data=>$typedata);
            my $tid = $type->id;        
            $content = $c->get_content_obj($tid);
            my $i;
            foreach my $p ($content->get_contents()) {
            $i++;
            $out .= $p->name();
            $this->load_meta();
            my $aid = $p->account ? $p->account->{account_id} : undef;
            my $contact;
            if ($aid) {
                my %cdata = $this->load_contacts();
                if ($cdata{contact}{contact_id}) {
                my $c = new Modules::ID::Contact(data=>$cdata{contact});
                my $info = $cdata{contact_info};
                $contact = $c->show(info=>$info);
                }
            }
            $out .= $p->summary(contact=>$contact);
            last if ($i>10);
            }
        }
        return $out;
    }

    if (! $content || ! $content->defined) {
    return $this->error("Membership($options): not found");
    }
    if ($opt{view}) {
    $content->set_view($opt{view});
    delete $opt{view};
    }
    # any remaining options are passed to the object
    if ($opt{method} =~ /index/) {
    $out = $content->index(%opt);
    }
    else {
    $out = $content->show(%opt);
    }
    return $out;
}

sub ioctl {
    my ($this) = shift;
    $_ = shift;
    if (/ControlPanel/) {
    return \&ctrl_panel;
    }
    elsif (/ModuleName/) {
    return "Memberships";
    }
    elsif (/Category/) {
    return "Social";
    }
    elsif (/Dependencies/) {
    return ["Finance"];
    }
    elsif (/Search/) {
    return \&search;
    }
}

sub ctrl_panel {
    my $this = shift;
    my $sid = $this->get_section_id();
    if (! $sid) { return $this->set_section_id("id"); }
    $this->{section} = new ExSite::Section(id=>$sid);

    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    my $out = &insert_js("misc","jquery.magnific-popup.min");
    $out .= $ml->link(undef,{rel=>"stylesheet",href=>"$config{server}{HTMLpath}/_ExSite/css/magnific-popup.css"});
    my $cmd = $this->{input}{cmd};
    my $id = $this->{input}{id} || $sid;
    #my $c = new ExSite::Content();
    my $c = new Modules::Membership::Profile;
    $this->{content} = $c->get_content_obj($id);
    if ($id) {
    $out .= $this->pathbar($this->{content},linktypes=>"section|membership_type|profile");
    $out .= $this->toolbar($this->{content});
    }

    if ($cmd) {

    if ($cmd =~ /^new/) {
        $out .= $this->newcontent($cmd,$this->{content});
        return $out;
    }
    elsif ($cmd eq "del") {
        $out .= $this->delete($this->{content});
    }
    elsif ($this->{content}->subtype eq "membership_type") {
        if ($cmd =~ /price/) {  
        $out .= $this->pricing($this->{content});
        }
        elsif ($cmd eq "edit") {
            #### add prompt, title, format
            ### different for 
            $out .= $this->update($this->{content});
        }       
        elsif ($cmd eq "conf") {
        # RL
        $share{DB}->handler("input_exsite",\&input_exsite);
        $out .= $this->configure($this->{content});
        if (keys %$this->{post}) {
            $out .= $this->show($this->{content});
        }
        }
    }
    elsif ($cmd =~ /^(publish|unpublish|queue|unqueue|archive|approve)$/) {
        $this->$1;
        $out .= $this->show($this->{content});
    }
    elsif ($this->{content}->subtype eq "profile") {
        if ($cmd eq "log") {
        $out .= $this->log($this->{content});
        }
        elsif ($cmd eq "status") {
        $out .= $this->membership_status($this->{content});
        }
        elsif ($cmd eq "renew") {
        $out .= $this->{content}->renew();
        }
        elsif ($cmd =~ /^image/) {
        $out .= $this->images($this->{content});
        }
        elsif ($cmd =~ /contact/) {
        $out .= $this->contacts($this->{content});
        }
        elsif ($cmd eq "conf") {
        $out .= $this->configure($this->{content});
        }
        elsif ($cmd eq "edit") {
        #### add prompt, title, format
        ### different for 
        $out .= $this->update($this->{content});
        }
        elsif ($cmd eq "login") {
        $out .= $this->{content}->login();
        }               
    }
    else {
        $out .= $this->error("Unrecognized command: $cmd");
    }
    }
    elsif ($id) {
    $out .= $this->show($this->{content});
    }
    else {
    $out .= $this->show_section($this->{section});
    }
    return $out;
}

# ExSite::Form::input_exsite handler

sub input_exsite {
    my ($db, %opt) = @_;
    if ($opt{name} eq "_meta_apply_fields") {
        my $in = new ExSite::Input;
        my $input = $in->combine;
        my $c = new ExSite::Content();    
        my $content = $c->get_content_obj($input->{id});
        my $meta = $content->metadefs;
        my $options;
        foreach my $fld (keys %$meta) {
            my $label = $fld || $meta->{$fld}{label} || $fld;
            $options .= $ml->option($label,{value=>$fld});
        }
        $opt{input} = $ml->select($options);
    }
}

sub my_memberships {
    my $this = shift;
    my $out = $ml->h1($msg{"Memberships"});
    my $uid = $share{DB}->my_uid;
    if ($uid) {
    my @profile = $share{DB}->get_query("my memberships",$uid);
    if (scalar @profile) {
        foreach my $pdata (@profile) {
        my $p = new Modules::Membership::Profile(data=>$pdata);
        my $pstat = $ExSite::Workflow::status[$p->getdata("status")];
        my ($status,$renewlink);
        if ($pstat =~ /published/) {
            $status = "This membership is in good standing.";
            ### FIXME: add a renew link if in the renewal period
        }
        elsif ($pstat eq "archived") {
            $status = "This membership has been archived.";
            $renewlink = $ml->a($msg{"renew now"},{href=>$p->link(cmd=>"renew",class=>"button")});
        }
        elsif ($pstat eq "expired") {
            $status = "This membership has expired.";
            $renewlink = $ml->a($msg{"renew now"},{href=>$p->link(cmd=>"renew",class=>"button")});
        }
        elsif ($pstat eq "draft") {
            $status = "This membership application has not been submitted yet.";
            $renewlink = $ml->a($msg{"submit now"},{href=>$p->link(cmd=>"renew",class=>"button")});
        }
        elsif ($pstat eq "canceled") {
            $status = "This membership was canceled.";
            $renewlink = $ml->a($msg{"Re-apply"},{href=>$p->link(cmd=>"renew",class=>"button")});
        }
        elsif ($pstat eq "rejected") {
            $status = "This membership application was not accepted.";
        }
        else {  # queued, approved, submitted
            $status = "This membership application is being processed.";
        }
        my $expdate = $p->expiry_date;
        my $memsince = $p->member_since;
        $out .= $ml->div(
            $p->summary().
#           $ml->div($p->title,{class=>"profileTitle"}).
            $ml->div($msg{"Membership type"}.": ".$p->membership_type->label).
            $ml->div($msg{"Member since"}.": ".
                 ($memsince && $memsince->has_date?$memsince->write("date"):"n/a")).
            $ml->div($msg{"Expiry date"}.": ".
                 ($expdate && $expdate->has_date?$expdate->write("date"):"n/a")).
            $ml->p($msg{$status}.$renewlink,{class=>"profileStatusMsg"}),
            {class=>"profileStatusSummary"}
            );
        }
    }
    else { 
        $out .= $ml->p($msg{"You do not have a membership."});
        ### add sign-up instructions
    }
    }
    else {
    $out .= $ml->p({"Please log in to view and manage your membership(s)."});
    }
    return $out;
}

sub toolbar {
    my ($this,$c) = @_;
    my $icondir = "$config{server}{HTMLpath}/_ExSite/images/icons";
    my $icondir2 = "$config{server}{HTMLpath}/_Modules/Membership";
    my $type = $c->subtype();
    if ($type eq "membership_type") {

    return $ui->ToolBar(
    tools=>[
        {label=>"overview", url=>$this->link(cmd=>undef,id=>$c->my_section->id), faicon=>"info", tone=>"good"},
        {label=>"configure", url=>$this->link(cmd=>"conf"), faicon=>"conf"},
        {label=>"description", url=>$this->link(cmd=>"edit"), faicon=>"edit"},      
        {label=>"pricing", url=>$this->link(cmd=>"price"), faicon=>"money"},
        {label=>"roster", url=>$this->link(cmd=>undef), faicon=>"users"},
        {label=>"delete", url=>$this->link(cmd=>"del"), faicon=>"delete", tone=>"bad", confirm=>'Really delete this membership type?'},
    ]
    );

    return $ui->IconBar(
        links=>[
        {label=>"overview",img=>"$icondir/star.png",url=>$this->link(cmd=>undef,id=>$c->my_section->id)},
        {label=>"configure",img=>"$icondir/conf.png",url=>$this->link(cmd=>"conf")},
        {label=>"description",img=>"$icondir/edit.png",url=>$this->link(cmd=>"edit")},
        {label=>"pricing",img=>"$icondir/money.png",url=>$this->link(cmd=>"price")},
        {label=>"roster",img=>"$icondir/users.png",url=>$this->link(cmd=>undef)},
        ]
        );
    }
    elsif ($type eq "profile") {
    return $ui->IconBar(
        links=>[
        {label=>"view&nbsp;profile",img=>"$icondir/user.png",url=>$this->link(cmd=>undef)},
        {label=>"edit&nbsp;profile",img=>"$icondir/edit.png",url=>$this->link(cmd=>"edit")},
        {label=>"settings",img=>"$icondir/conf.png",url=>$this->link(cmd=>"conf")},
        {label=>"photo/logo",img=>"$icondir/image.png",url=>$this->link(cmd=>"image")},
        {label=>"contacts",img=>"$icondir/home.png",url=>$this->link(cmd=>"contact")},
        {label=>"membership",img=>"$icondir2/membership.png",url=>$this->link(cmd=>"status")},
        {label=>"history",img=>"$icondir/time.png",url=>$this->link(cmd=>"log")},
        ]);
    }
}

sub show {
    my ($this,$c) = @_;
    my $out;
    if ($c->subtype eq "membership_type") {
    $out .= $this->show_type($c,$this->{input}{status});
    }
    elsif ($c->subtype eq "profile") {
    $out .= $this->show_profile($c);
    }
    elsif ($c->subtype eq "section") {
    $out .= $this->show_section($c);
    }
    else {
    $out .= $this->warn($ml->em(ucfirst $c->name)." is a ".$c->subtype()."; the Membership module can only be used to manage membership types, directories, and profiles. Click on 'Top' to get started.");
    }
    return $out;
}

sub show_section {
    my ($this,$c) = @_;
    my $out = $ml->h1($this->{section}->title);
    my $tree = $c->get_content_tree();
    my @types = $tree->find({type=>$c->isubtype("membership_type")});
    my $r = new ExSite::ReportBuilder(title=>"Membership Types");
    $r->headers("Type","Active","Pending","Expired","Canceled","Other");
    $r->nodata("No membership types have been set up.");
    foreach my $typedata (@types) {
    my $type = new Modules::Membership::Type(data=>$typedata);
    next if (! $type->allow("insert"));
    my @status = $this->summarize($type);
    my @data;
    my $url = $type->get_url_canonical;
    my $tid = $type->id;
    my $prefix;
    if ($type->parent->isubtype == $type->isubtype) {
        # sub-membership type
        $prefix = "&nbsp;&nbsp;&bull;&nbsp";
    }
    push @data, $prefix.$ml->a($type->title,{href=>$this->link(id=>$tid)});
    push @data, ( $this->type_status_link($tid,$status[0],0),
              $this->type_status_link($tid,$status[4],4),
              $this->type_status_link($tid,$status[6],6),
              $this->type_status_link($tid,$status[7],7),
              $this->type_status_link($tid,$status[1]+$status[2]+$status[3]+$status[5]+$status[8],"") );
    $r->push(@data);
    }
    $r->tools($ml->a("+new membership type",{href=>$this->link(cmd=>"newtype"),class=>"button_sm"}));
    $out .= $r->make();
    return $out;

### re-enable following once directory support is added
    my @dirs = $tree->find({type=>$c->isubtype("membership_directory")});
    my $r = new ExSite::ReportBuilder(title=>"Directories");
    $r->headers("Organization","Directory","Entries");
    $r->nodata("No additional directories have been set up.");
    foreach my $dirdata (@dirs) {
    my $dir = new Modules::Membership::Directory(data=>$dirdata);
    next if (! $dir->allow("insert"));
    my @data;
    my $url = $dir->get_url_canonical;
    push @data, $ml->a($this->{section}->title,{href=>$url,target=>'_blank'});
    push @data, $ml->a($dir->title,{href=>$this->link(id=>$dir->id)});
    my $count = $tree->count(undef,$dir->id);
    push @data, $ml->div($count,{class=>"num"});
    $r->push(@data);
    }
    $r->tools($ml->a("+new directory",{href=>$this->link(cmd=>"newdir"),class=>"button_sm"}));
    $out .= $r->make();
    return $out;
}

sub type_status_link {
    my ($this,$id,$anchor,$status) = @_;
    my $link = $anchor ?
    $ml->a($anchor,{href=>$this->link(id=>$id,status=>$status)}) :
    $anchor;
    return $ml->div($link,{class=>"num"});
}

sub show_type {
    my ($this,$c,$show_status) = @_;
    my $out; 
    my $icondir = "$config{server}{HTMLpath}/_ExSite/images/icons";
    my $title = $c->title;
    if (defined $show_status) {
    $title .= " (".$this->mstatus($show_status).")";
    }
    my $r = new ExSite::ReportBuilder(title=>$title);
    $r->set("dynamic",1);
    $r->headers("Name","Organization","Type","Status","Profile ID");
    $r->nodata("No $show_status members.");
    my @org = $share{DB}->fetch_match("metadata",{name=>"organization"});
    my %org = &keywise("id",\@org);

    ### FIXME: this is sorted by type, then by sortkey

    my $filter_status = defined $show_status;
    foreach my $profile_data ($c->get_descendants("profile")) {
    my $p = new Modules::Membership::Profile(data=>$profile_data);
    my $status = $p->getdata("status");
    if ($filter_status) {
        next if ($show_status =~ /\d/ && $show_status != $status);
        next if ($show_status eq "" && ($status==0 || $status==4 || $status==6 || $status==7 || $status==9));
    }
    my $statlabel = $this->mstatus($status);
    $r->push(
        $ml->a($p->label,{href=>$this->link(id=>$p->id)}),
        $org{$p->id}{value},
        $p->parent->label(),
        $ml->span($statlabel,{class=>"status".ucfirst($statlabel)}),
        $ml->div($p->id,{class=>"num"})
        );
    }
    $r->tools($ml->a("+ new ".$c->label,{href=>$this->link(cmd=>"newprofile"),class=>"button_sm"}));
    $out .= $r->make();
    return $out;
}

sub summarize {
    my ($this,$type) = @_;
    my $tree = $type->get_content_tree();
    my @status = ( 0,0,0,0,0,0,0,0 );
    foreach my $m ($tree->find({type=>$type->isubtype("profile")},$type->id)) {
    $status[$m->{status}]++;
    }
    return @status;
}

sub show_profile {
    my ($this,$c) = @_;
    my $out = $ui->BasicBox( title=>"Preview", pane=>$c->preview() );
    return $out;
}

sub update {
    my ($this,$c) = @_;
    my $type = $c->subtype();
    if ($type eq "membership_type") {
    return $this->SUPER::update($c,format=>"html",prompt=>"Describe the member benefits:",title=>"Membership benefits/details for ".$ml->em($c->title));
    }
    elsif ($type eq "profile") {
    return $this->SUPER::update($c,format=>"html",prompt=>"Member Bio",title=>"Bio for ".$c->title);
    }
    else {
    return $this->SUPER::update($c,format=>"html",prompt=>"Description");
    }
}

sub log {
    my ($this,$c) = @_;
    my $out;
    if (exists $this->{post}{log}) {
    if ($c->allow("edit")) {
        $c->log($this->{post}{log});
        $out .= $ui->SuccessMsg("Added note");
    }
    else {
        $out .= $this->error("Permission denied: you do not have authority to manage this profile");
    }
    }
    my $r = new ExSite::ReportBuilder(title=>"History of ".$ml->em($c->label));
    $r->nodata("This profile has no history.");
    $r->headers("Note","Date");
    foreach my $log ($share{DB}->fetch_match("content_date",{content_id=>$c->id},"start")) {
    my $note;
    if ($log->{type} ne "log") { $note .= uc $log->{type} . ": "; }
    $note .= $log->{description};
    my $t = new ExSite::Time($log->{start},"sql_datetime");
    $r->push($note,$t->write("date"));
    }
    $out .= $r->make();
    $out .= $ml->form($ml->input(undef,{type=>"text",name=>"log",size=>60}).$ml->input(undef,{type=>"submit",value=>"add note"}),{method=>"post",action=>$this->link()});
    return $out;
}

sub membership_status {
    my ($this,$c) = @_;
    my $out = $ml->h1($c->title);
    my $r = new ExSite::ReportBuilder(title=>"Membership Status");
    $r->headers("Membership Type","Status","Expiry Date","Member Since");
    my $expiry = $c->expiry_date(); # Time object
    my $since = $c->member_since(); # Time object
    my $status = $this->mstatus($c->getdata("status"));
    $r->set("data",[$ml->a($c->parent->label,{href=>$this->link(id=>$c->parent->id,cmd=>undef)}),
            $status,
            $expiry ? $expiry->write("date_long") : "n/a",
            $since ? $since->write("date_long") : "n/a"]);
    my $out .= $r->make();

    ### renewal, change status functions go here

    $out .= $ml->p(
    $ml->a("renew",{href=>$this->link(cmd=>"renew"),class=>"button"})
    );
    return $out;
}

sub newcontent {  # admin-side function
    my ($this,$cmd,$c) = @_;
    my $out;
    $cmd =~ /^new(.+)$/;
    my $type = $1;
    if ($c->allow("insert")) {
    my ($title,$prompt);
    if ($this->{is_post}) {
        my %cdata = (
        title => $this->{post}{title},
        parent => $this->{post}{parent},
        type => $this->{post}{type},
        status => $ExSite::Workflow::status{draft},
        );
        my $new = $c->new_content_obj(%cdata);
        if ($type eq "profile") {
        $new->log("profile created");
        }
        if ($new->id) {
        &ExSite::Util::redirect_html($this->link(__plaintext=>1,id=>$new->id,cmd=>"conf"));
        } else {
        return $this->error("Could not create ".$c->subtype());
        }
        #$ml->location($this->link(__plaintext=>1,id=>$new->id,cmd=>"conf"));
    }
    elsif ($type eq "profile") {
        $title = "New ".$c->title()." profile";
        $prompt = "Full name";
    }
    elsif ($type eq "type") {
        $type = "membership_type";
        $title = "New membership type";
        $prompt = "Membership type";
    }
    elsif ($type eq "dir") {
        $type = "membership_directory";
        $title = "New member directory";
        $prompt = "Directory title";
    }
    $out .= $ml->h1($title);
    my $parent = &preference("Membership.parent") || $c->id;
    my $f = new ExSite::FormBuilder();
    $f->input(name=>"title",prompt=>$prompt,type=>"text",required=>1);
    $f->input(name=>"type",type=>"hidden",value=>$c->isubtype($type));
    $out .= $f->make();
    return $out;
    }
    else {
    my $longtype = ($type eq "dir") ? "membership directory" : "membership type"; 
    return $this->error("You do not have permission to add a $longtype here.");
    }
}

sub mstatus {
    my ($this,$status) = @_;
    if ($status =~ /\d/) {
    return $status ? $ExSite::Workflow::status[$status] : "active";
    }
    else {
    return "other";
    }
}

#--------------------------------------------------------------------------
# Modules::Content

sub price_add {
    my ($this,$c) = @_;
    $c or $c = $this->{content};
    my $out;
    my $db = $share{DB};
    if (scalar keys %{$this->{post}} > 0) {
    my %post = $db->parse_parts(%{$this->{post}});
    delete $post{action};
    if ($post{cost}) {
        $post{content_id} = $c->id;
        $post{status} = "active";
        my $pid = $db->insert("price",\%post);
        if (! $pid) {
        $out .= $db->show_diagnostics("error","html");
        }
    }
    else {
        $out .= $this->error("You must specify a price.");
    }
    }
    else {
    $db->{map}->load_submaps("Finance");
    $ml = &get_obj("ML");
    $out .= $ml->h1("Add Price");
    $out .= $db->make(table=>"price",show=>["description","cost","access","start","end"],data=>{acctcode_id=>$config{Membership}{acctcode}},simplename=>1,action=>$this->link());
    }
    return $out;
}

#--------------------------------------------------------------------------
# Data

sub setup_querylib {
    my $this = shift;
    my $db = $share{DB};
    $db->set_query("my memberships",
           sql=>"select c.* from content c,content_key k,content_type t where c.content_id=k.content_id and k.uid=? and c.type=t.content_type_id and t.name='profile' and k.role like '%owner%'",
           nparam=>1,
           mode=>"r",
           keys=>["content","content_key","content_type"]);
    $db->set_query("my contact info",
           sql=>"select c.*,ci.* from contact c, contact_info ci, account a where c.account_id=a.account_id and ci.contact_id=c.contact_id",
           nparam=>0,
           mode=>"r",
           keys=>["contact","contact_info","account"]);
}

sub load_meta {
    my ($this) = @_;
    if (! defined $share{content}{metadata}) {
    my $allmeta = $share{DB}->fetch_all("metadata");
    foreach my $meta (@$allmeta) {
    if (! exists $share{content}{metadata}{$meta->{id}}) {
        $share{content}{metadata}{$meta->{id}} = [];
    }
    push @{$share{content}{metadata}{$meta->{id}}}, $meta;
    }
    }
}

sub load_contacts {
    my ($this,$account_id) = @_;
    if (! defined $share{contact}) {
    my $allcontact = $share{DB}->fetch_all("contact");
    foreach my $c (@$allcontact) {
    if (! exists $share{contact}{$c->{account_id}}) {
        $share{contact}{$c->{account_id}} = [];
    }
    push @{$share{contact}{$c->{account_id}}}, $c;
    }        

    my $allcontact = $share{DB}->get_query("my contact info");
    foreach my $c (@$allcontact) {
    if (! exists $share{contact_info}{$c->{contact_id}}) {
        $share{contact_info}{$c->{contact_id}}{info} = {};
    }
    $share{contact_info}{$c->{contact_id}}->{$c->{name}} = $c->{value};
    }
    }
    return $share{contact}{$account_id};
}

sub profile {
    my ($this,%opt) = @_;
    if (!exists $this->{Profile}) {
        $this->{Profile} = new Modules::Membership::Profile();
    }
    if (keys %opt) {
        $this->{Profile}->setup(%opt);
    }
    return $this->{Profile};
}

1;
