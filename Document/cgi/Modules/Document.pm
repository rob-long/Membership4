package Modules::Document;

# Document : a simple library & document manager

### TODO: search for documents across all libraries?

# lib, doc => id

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Util;
use ExSite::UI;
use ExSite::ML;
use ExSite::Library;
use ExSite::Section;
use Modules::Content;
use MIME::Base64;

use vars qw(@ISA $ml $ui);
@ISA = qw(Modules::Content);

sub write {
    my ($this,$options) = @_;
    my %opt = &DecodeString($options);
    $this->get_content(%opt);
    return $this->error("No document library selected") if (! $this->{lib});

    my $in = $this->{input};
    $ml = &get_obj("ML");

    my $out = $ml->h1($this->{lib}->title);
    my @doc = $this->{lib}->get_contents();
    my $ndoc;
    my $format = $opt{format} || $config{Document}{format} || "summary";
    if ($opt{sort}) {
	my @sorted;
	if ($opt{sort} =~ /alpha/) {
	    @sorted = sort { $a->title cmp $b->title } @doc;
	}
	### other sort rules here
	@doc = @sorted;
    }
    foreach my $doc (@doc) {
	if ($doc->allow_view) {
	    $out .= $doc->summary(format=>$opt{format});
	    $ndoc++;
	}
    }
    return $ml->div($out,{class=>"Document"});
}

sub get_content {
    my ($this,%opt) = @_;
    my $id = $this->{input}{id} || $opt{id};
    my $c = new ExSite::Content;
    if ($id) {
	$c = $c->get_content_obj($id);
	if ($c->subtype() eq "library") {
	    $this->{content} = $this->{lib} = $c;
	}
	elsif ($c->subtype() eq "content") {
	    $this->{content} = $this->{doc} = $c;
	    $this->{lib} = $c->parent();
	}
	else {
	    $this->{content} = $c;
	}
    }
    elsif ($this->{input}{section_id}) {
	$this->{content} = $c->get_content_obj($this->{input}{section_id});
    }
}

# ioctl : all operations that don't qualify as reads or writes
#         invoked as <!--BaseDCD.ioctl(request)-->

sub ioctl {
    my $this = shift;
    $_ = shift;   # $_ is the ioctl request
    if (/ModuleName/) {
	return "Documents";
    }
    elsif (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/Category/) {
	return "CMS";
    }
    elsif (/DynContentParam/){
    	return $this->getDynContentParameter(shift);
    }
    elsif (/PublishRule/) {
	return "static";
    }
}

sub getDynContentParameter{
    my ($this,$sectionid) = @_;
    return undef if !$sectionid;
    my $s = new ExSite::Section(id=>$sectionid);
    my @libs = $s->fetch_libraries();
    my @libopt = map { "<option value=\"id=$_->{content_id}\">$_->{label}</option>" } @libs;

    $ml = &get_obj("ML");
    return $ml->table( [
			   [ 
			     $ml->strong("Select a library:"), 
			     $ml->select(join("\n",@libopt),{name=>"param"}) 
			   ],
		       ] );
}

sub ctrl_panel {
    my $this = shift;
    $this->get_content();
    my $db = $share{DB};
    my $in = $this->{input};
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    $this->{admin} = 1;
    $this->{section_id} or $this->{section_id} = $this->get_section_id;
    if (! $this->{section_id}) { return $this->set_section_id; }
    my $out = $this->pathbar($this->{content});
    my $cmd = $this->{input}{cmd};
    my $imgroot = "$config{server}{HTMLpath}/_ExSite/images/icons";

    if ($this->{lib}) {
	my $lib = $this->{lib};
	if ($this->{doc}) {
	    my $doc = $this->{doc};
	    $out .= $ui->IconBar(
		links=>[
		    {label=>"info",url=>$this->link(cmd=>undef),img=>"$imgroot/info.png"},
		    {label=>"configure",url=>$this->link(cmd=>"conf"),img=>"$imgroot/conf.png"},
		    {label=>"metadata",url=>$this->link(cmd=>"meta"),img=>"$imgroot/edit.png"},
		    {label=>"update",url=>$this->link(cmd=>"update"),img=>"$imgroot/copy.png"},
		    undef,
		    {label=>"publish",url=>"$config{server}{CGIpath}/$config{prog}{publish}?id=".$doc->id,img=>"$imgroot/publish.png"},
		    {label=>"unpublish",url=>"$config{server}{CGIpath}/$config{prog}{publish}?-id=".$doc->id,img=>"$imgroot/unpublish.png"},
		    undef,
		    {label=>"delete",url=>$this->link(cmd=>"del"),img=>"$imgroot/delete.png",confirm=>'Really delete this document?',tone=>"bad"},
		]
		);
	    if ($cmd eq "conf") {
		$out .= $this->configure($doc);
	    }
	    elsif ($cmd eq "del") {
		$this->delete($doc);
		$ml->location($this->link(id=>$this->{lib}->id,cmd=>undef,__plaintext=>1));
	    }
	    elsif ($cmd eq "rollback") {
		$out .= $this->rollback($doc);
		$out .= $this->show_document();
	    }
	    elsif ($cmd eq "update") {
		# upload new rev
		$out .= $this->update($doc);
	    }
	    elsif ($cmd eq "meta") {
		# optional metadata
		$out .= $this->metadata($doc);
	    }
	    else {
		$out .= $this->show_document();
	    }
	}
	else {
	    # library
	    $out .= $ui->IconBar(
		links=>[
		    {label=>"list",url=>$this->link(cmd=>undef),img=>"$imgroot/report.png"},
		    {label=>"configure",url=>$this->link(cmd=>"conf"),img=>"$imgroot/conf.png"},
		    {label=>"order",url=>$this->link(cmd=>"sort"),img=>"$imgroot/list.png"},
		    undef,
		    {label=>"upload",url=>$this->link(cmd=>"new_doc"),img=>"$imgroot/page.png"},
		    {label=>"bulk&nbsp;upload",url=>$this->link(cmd=>"new_docs"),img=>"$imgroot/pages.png"},
		    undef,
		    {label=>"publish",url=>"$config{server}{CGIpath}/$config{prog}{publish}?id=".$lib->id,img=>"$imgroot/publish.png"},
		    {label=>"unpublish",url=>"$config{server}{CGIpath}/$config{prog}{publish}?-id=".$lib->id,img=>"$imgroot/unpublish.png"},
		    undef,
		    {label=>"delete",url=>$this->link(cmd=>"del"),img=>"$imgroot/delete.png",confirm=>'Really delete this library and all of its documents?',tone=>"bad"},
		]
		);
	    if ($cmd eq "conf") {
		$out .= $this->configure($lib);
	    }
	    elsif ($cmd eq "del") {
		$this->delete($lib);
		$ml->location($this->link(id=>undef,cmd=>undef,__plaintext=>1));
	    }
	    elsif ($cmd eq "new_doc") {
		$out .= $this->new_doc();
	    }
	    elsif ($cmd eq "new_docs") {
		# bulk upload
		$this->info("in new_docs()");
		if ($this->{is_post}) {
		    $this->info("uploading...");
		    return $this->do_bulk_upload();
		}
		$out .= $this->new_docs();

	    }
	    elsif ($cmd eq "sort") {
		$out .= $this->order($lib);
	    }
	    else {
		$out .= $this->show_library();
	    }
	}
    }
    else {

	### FIXME: new library

	$out .= $this->list_libraries();
    }
    return $out;
}

sub list_libraries {
    my $this = shift;

    my $s = $this->get_section;
    my $r = new ExSite::ReportBuilder(title=>"Libraries in ".$s->title);
    $r->nodata("No libraries found.");
    $r->headers("Title","Contents");
    foreach my $ldata ($s->fetch_libraries()) {
	my $lib = new ExSite::Library(data=>$ldata);
	$r->push($ml->a($lib->title,{href=>$this->link(id=>$lib->id)}),
		 $ml->div($lib->count_contents,{class=>"num"}),
		 );
    }
    $r->tools($ml->a("+ new library",{href=>$this->link(cmd=>"lib_new"),class=>"button_sm"}));
    return $r->make();
}

sub show_library {
    my $this = shift;
    my $lib = $this->{lib};
    my $r = new ExSite::ReportBuilder(title=>"Documents in ".$lib->title);
    $r->nodata("No documents found.");
    $r->headers("Document","Type","Size","Uploaded");
    $r->set("dynamic",1);
    foreach my $doc ($lib->get_contents()) {
	my %info = $doc->revision->get_fileinfo;
	my $icon = $doc->show_icon();
	$r->push(
	    $ml->a($doc->title,{href=>$this->link(id=>$doc->id)}),
	    $icon ."&nbsp;". &MimeDescr($doc->revision->mime_type),
	    $info{size},
	    $doc->date,
	    );
    }
    return $r->make();
}

sub show_document {
    my $this = shift;
    my $doc = $this->{doc};
    return "No document selected." if (! $doc);
    my @row;
    my %info = $doc->revision->get_fileinfo();
    push @row, $ml->tr($ml->th("Title").$ml->td($doc->title));
    push @row, $ml->tr($ml->th("Type").$ml->td($doc->show_icon."&nbsp;".&MimeDescr($info{mimetype})));
    push @row, $ml->tr($ml->th("Size").$ml->td($info{size}));
    if ($doc->is_published) {
	my $url = $doc->get_url();
	push @row, $ml->tr($ml->th("published URL").$ml->td($ml->a($url,{href=>$url,target=>"_blank"})));
    }
    my $url = $doc->get_url_dynamic();
    push @row, $ml->tr($ml->th("preview URL").$ml->td($ml->a($url,{href=>$url,target=>"_blank"})));
    my $out = $ml->table({caption=>$doc->title,tbody=>join("",@row)},{class=>"Report"});
    my @rev = $doc->get_revisions();
    $out .= $ml->h3("Revisions");
    if ($session{Document_publish_warning}) {
	$out .= $ui->SuccessBox(title=>"Upload complete",
				pane=>"You can publish the document now, or when you are done with your updates, you can republish the library.");
	delete $session{Document_publish_warning};
    }
    my @revout;
    my @rev = reverse $doc->get_revisions();
    foreach my $revdata (@rev) {
	my $path = $doc->path;
	my $rev = new ExSite::Revision(data=>$revdata);
	my %info = $rev->get_fileinfo();
	my $time = new ExSite::Time($rev->timestamp,"sql_timestamp");
	my $revinfo = $ml->a($info{description},{href=>"$config{server}{CGIpath}/$config{prog}{view}$path?revision=".$rev->id,title=>$doc->name.".".&MimeToFile($info{mimetype})})." uploaded ".$time->write("datetime");
	if (@revout == 0 && scalar @rev > 1) {
	    $revinfo .= " ".$ml->a("rollback",{href=>"javascript:confirm_custom('Really delete this revision?','".$this->link(cmd=>"rollback")."')",class=>"button_sm"});
	}
	push @revout, $revinfo;
    }
    if (scalar @revout) {
	$out .= $ml->p("Most recent shown first. Click to download.");
	$out .= $ml->ol(\@revout);
    }
    else {
	$out .= $ui->ErrorBox(title=>"No Revisions",
			      pane=>"This document has no files or data associated with it; it should be updated or deleted.");
    }
    return $out;
}

# add a new document

sub new_doc {
    my $this = shift;
    my $out;
    if ($this->{is_post}) {
	my $input = new ExSite::Input();
	#$out .= &ShowHash($share{input});
	my $filename = $input->fetch_file("upload","name");
	if ($filename) {
	    my $title;
	    if ($this->{post}{title}) {
		$title = $this->{post}{title};
	    }
	    elsif ($filename =~ /(.+)\.(\w+)$/) {
		$title = $1;
	    }
	    else {
		$title = $filename;
	    }
	    my $doc = $this->{lib}->new_content_obj(
		title=>$title,
		parent=>$this->{lib}->id,
		);
	    $out .= $this->add_revision($doc);
	    if (&ExSite::Config::OnError()) {
		$out .= $ui->ErrorBox(
		    title=>"Error",
		    pane=>&ExSite::Config::show_diagnostics(),
		    );
	    }
	    else {
		if ($this->{input}{descr}) {
		    my $meta_descr = $config{Document}{meta_descr} || "caption";
		    $doc->meta->set($meta_descr,$this->{input}{descr});
		}
		$session{Document_publish_warning} = 1;
		$ml->location($this->link(__plaintext=>1,id=>$doc->id));
		return;
	    }
	}
    }

    $out .= $ml->h1("Upload new document");
    $out .= $this->large_file_warning();
    my $f = new ExSite::FormBuilder();
    $f->input(name=>"upload",prompt=>"Choose document",type=>"file",required=>1);
    $f->input(name=>"title",prompt=>"Title (optional)",type=>"text",tail=>"Filename will be used, if left blank.");
    $f->input(name=>"descr",prompt=>"Description (optional)",type=>"textarea");
    $out .= $f->make();

    return $out;
}

sub new_docs {
    my $this = shift;
    my $lib = $this->{input}{lib};
    my $out = $ml->h1($msg{"Upload multiple documents"});
    my $link = $this->link();
    $out .= <<END;
    <p>To upload files, click on the button below. You may select multiple files using ctrl-click on Windows or cmd-click on Mac OS X. Drag-and-drop is supported in Firefox and Chrome. Once you are finished uploading click on the list tool to view your files.</p>
	
    <div id="file-uploader">		
    <noscript>			
    <p>Please enable JavaScript to use file uploader.</p>
    <!-- or put a simple form for upload here -->
    </noscript>         
    </div>
    
    <script src="$config{server}{HTMLpath}/_ExSite/js/fileuploader.js" type="text/javascript"></script>
    <script>        
    function createUploader(){            
	var uploader = new qq.FileUploader({
	    element: document.getElementById('file-uploader'),
            action: '$config{server}{CGIpath}/$config{prog}{ctrlpanel}/Document?_bare=2&section_id=$this->{section_id}&cmd=new_docs',
            debug: true,
            sizeLimit: $config{max_upload_size},
            params: {
	      lib: $lib
	    }
        });           
        }
        
    // create uploader as soon as the DOM is ready
    window.onload = createUploader;     
    </script>
END
    return $out;
}

sub add_revision {
    my ($this,$doc) = @_;
    my $in = $this->{input};
    my $ml = new ExSite::ML;
    my $lib = $this->{lib} || $doc->parent();
    my %opt;
    $opt{note} = "uploaded using Document module on ".(scalar localtime);
    # prepare upload file for insertion into DB
    my $file = $in->{upload};
    my $fdata = undef;
    my $size = 0;
    my $mimedata = "";
    if ($ENV{CONTENT_TYPE} =~ /multipart\/form-data/) {
	# read file contents
	my $continue = 1;
	while ($continue) {
	    $continue = read($in->{upload},$fdata,1024,$size);
	    $size += $continue;
	}
	# MIME-encode the file contents
	$mimedata = encode_base64($fdata,"");
    }
    # check size
    if ($size > $config{form}{bigfile_maxsize}) {
	# meh...

    }

    # strip path from filename
    my @path = split /[:\\\/]/, $file;
    my $filename;
    if ($path[-1]) { $filename = &clean_filename($path[-1]); }
    $opt{format} = "file";
    $opt{data} = "$filename$config{form}{sepchar}$mimedata"; 
    if ($in->{upload}) {
	if ($doc->revise(%opt)) {
	    my $out = $ml->h1("$filename ".$msg{"uploaded successfully"});
	    $ml->location($this->link(__plaintext=>1,cmd=>undef,id=>$doc->id));
	    return $out;
	}
	else {
	    return $ml->p("Failed to upload file.").&ExSite::Config::show_diagnostics();
	}
    }
    else {
	return $this->error($msg{"Nothing to upload!"});
    }
}

sub do_bulk_upload {
    my $this = shift;
    my $lib = $this->{lib};
    if (! $lib) {
	return $this->error($msg{"No document library found."});
    }
    my $in = new ExSite::Input;
    my $input = $in->combine;
    my $file = $in->fetch("post","raw");
    my $filename = $input->{qqfile};
#    if (!$file) {
#	require CGI;
#	my $q = CGI->new();
#	my @uploaded_files = $q->upload();
#	my $fh = $q->upload('qqfile');
#	if (defined $fh) {
#	    my $io_handle = $fh->handle;
#	    $file = do { local $/; <$io_handle> };
#	}
#    }
    my $mimedata = encode_base64($file,"");
    $filename = &clean_filename($filename);
    my $c = new ExSite::Content();
    my $newdoc = $c->new_content_obj(
	type=>$c->isubtype("content"),
	label=>$filename,
	parent=>$lib->id,
	);
    $config{debug} = 0; # disable debug footers, which will mess up JSON reply
    if ($newdoc && $newdoc->ok) {
	if ($newdoc->revise(format=>"file",
			    note=>"uploaded to Documents app on ".(scalar localtime),
			    data=>"${filename}$config{form}{sepchar}${mimedata}")) {
	    # success
	    return qq|{ "success": true }|;
	    print STDERR "file has been successfully uploaded... thank you.\n";
	}
	else {
	    # bad revision
	    $newdoc->delete;
	    my $error = $newdoc->show_diagnostics("error");
	    print STDERR "$error.\n";
	    return qq|{ "success": false, "error": "$filename - $error" }|;
	}
    }
    else {
	# cannot make content obj
	my $error = $newdoc->show_diagnostics("error");
	print STDERR "$error.\n";
	return qq|{ "success": false, "error": "$filename - $error" }|;
    }
}

# update an existing document

sub update {
    my ($this,$doc) = @_;
    my $out;
    if ($this->{is_post}) {
	if ($this->add_revision($doc)) {
	    $session{Document_publish_warning} = 1;
	    $ml->location($this->link(__plaintext=>1,cmd=>undef,id=>$doc->id));
	    return;
	}
	else {
	    $out .= $ui->ErrorBox(
		title=>"Error",
		pane=>&ExSite::Config::show_diagnostics(),
		);
	}
    }
    else {
	my $title = $ml->em($doc->title);
	$out = $ml->h1($msg{"Upload new version of"}." ".$title);
	$out .= $this->large_file_warning();
	my $f = new ExSite::FormBuilder(action=>$this->link());
	$f->input(type=>"file",name=>"upload",prompt=>"Select new file:",required=>1);
	$f->buttons(submit=>"Upload");
	$out .= $f->make();
    }
}

sub metadata {
    my ($this,$doc) = @_;
    my @meta = $doc->meta->get_allowed();
    my $out = $ml->h1("Optional Metadata for ".$doc->name);

    my $input = new ExSite::Input;
    my $post = $input->post;
    if (scalar keys %$post > 0) {
	foreach my $meta (sort @meta) {
	    my $meta_new = $post->{$meta};
	    $doc->meta->set_nosave($meta,$meta_new);
	}
	$doc->meta->save;
	$out .= $ml->div("Metadata updated.",{class=>"notice"});
    }

    my %meta = $doc->get_metadata();
    my $form = new ExSite::FormBuilder(action=>$this->link());
    my ($template1, $template2);
    foreach my $meta (sort @meta) {
	next if ($meta =~ /^DC\./);
	my $input = $doc->meta->input($meta,$meta);
	$form->input(name=>$meta,prompt=>$doc->meta->label($meta),input=>$input,value=>$meta{$meta});
	$template1 .= $ml->tr($ml->td("[[$meta:prompt]]").$ml->td("[[$meta:input]]"));
    }
    # put DC metadata after custom metadata
    foreach my $meta (sort @meta) {
	next if ($meta !~ /^DC\./);
	my $input = $doc->meta->input($meta,$meta);
	$form->input(name=>$meta,prompt=>$doc->meta->label($meta),input=>$input);
	$template2 .= $ml->tr($ml->td("[[$meta:prompt]]").$ml->td("[[$meta:input]]"));
    }
    $form->template(
	$ml->table($template1).$ml->br.
	$ui->BlindBox(title=>"Dublin Core Metadata",
		      pane=>$ml->p($ml->img(undef,{src=>"$config{server}{HTMLpath}/_ExSite/images/icons/help.png"})." ".$ml->a("About the Dublin Core Schema",{href=>"http://en.wikipedia.org/wiki/Dublin_Core",target=>"_blank"})).
		      $ml->table($template2),
		      open=>!$template1)
	);
    $out .= $form->make();
    return $out;
}

sub large_file_warning {
    my $this = shift;
    return $ui->HelpBox(
	title=>"Web-friendly files",
	pane=>"Please make an effort to keep your file sizes down. Large files are slow to download, and can cost people on limited data plans. PDFs, Powerpoints, Word files, and other documents with embedded images and media can benefit by shrinking/optimizing before being uploaded.",
	size=>"m"
	);
}

1;

