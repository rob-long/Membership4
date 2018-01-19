package Modules::PhotoAlbum;

# PhotoAlbum : a simple image library manager

### FIXME: query arg id should be used for both libraries & images

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Util;
use ExSite::HTML;
use ExSite::ML;
use ExSite::Section;
use ExSite::Album;
use Modules::Content;
use MIME::Base64;

use vars qw(@ISA $ml $ui);
@ISA = qw(Modules::Content);

sub write {
    my ($this,$options) = @_;
    my %opt = &DecodeString($options);
    my $lib = $this->{library} = new ExSite::Library(id=>$opt{id});
    return $this->error("No photo album selected") if (! $lib->exists);

    my $in = $this->{input};
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");

    my $out = $ml->h1($lib->title);
    my @img = $lib->get_contents();
    my $nimg;
    my $format = $opt{format} || $config{PhotoAlbum}{format} || "summary";
    if ($opt{sort}) {
	my @sorted;
	if ($opt{sort} =~ /alpha/) {
	    @sorted = sort { $a->title cmp $b->title } @img;
	}
	### other sort rules here
	@img = @sorted;
    }
    foreach my $img (@img) {
	if ($img->allow_view) {
	    $out .= $img->summary(format=>$opt{format});
	    $nimg++;
	}
    }
    return $ml->div($out,{class=>"PhotoAlbum"});
}

# ioctl : all operations that don't qualify as reads or writes
#         invoked as <!--BaseDCD.ioctl(request)-->

sub ioctl {
    my $this = shift;
    $_ = shift;   # $_ is the ioctl request
    if (/ModuleName/) {
	return "Photo Albums";
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
    my @libopt = map { "<option value=\"lib=$_->{content_id}\">$_->{label}</option>" } @libs;

    $ml = &get_obj("ML");
    return $ml->table( [
			   [ 
			     $ml->strong("Select an album:"), 
			     $ml->select(join("\n",@libopt),{name=>"param"}) 
			   ],
		       ] );
}

sub ctrl_panel {
    my $this = shift;
#    $this->info("in PhotoAlbum::ctrl_panel");
    my $db = $share{DB};
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    $this->{admin} = 1;
    $this->{section_id} or $this->{section_id} = $this->get_section_id;
    if (! $this->{section_id}) { return $this->set_section_id; }
    my $out = $this->show_path();
    my $cmd = $this->{input}{phocmd};
    my $imgroot = "$config{server}{HTMLpath}/_ExSite/images/icons";

    if ($this->{input}{id}) {
	my $lib = $this->get_library();
	if ($this->{input}{img}) {
	    my $img = $this->get_image();
	    $out .= $ui->IconBar(
		links=>[
		    {label=>"all&nbsp;images",url=>$this->link(img=>undef,phocmd=>undef,optimize=>undef,web_ready=>undef,scale=>undef,large=>undef,small=>undef,thumb=>undef),img=>"$imgroot/image.png"},
		    undef,
		    {label=>"info",url=>$this->link(phocmd=>undef,optimize=>undef,web_ready=>undef,scale=>undef,large=>undef,small=>undef,thumb=>undef),img=>"$imgroot/info.png"},
		    {label=>"configure",url=>$this->link(phocmd=>"conf",optimize=>undef,web_ready=>undef,scale=>undef,large=>undef,small=>undef,thumb=>undef),img=>"$imgroot/conf.png"},
		    {label=>"caption",url=>$this->link(phocmd=>"meta",optimize=>undef,web_ready=>undef,scale=>undef,large=>undef,small=>undef,thumb=>undef),img=>"$imgroot/edit.png"},
		    {label=>"update",url=>$this->link(phocmd=>"update",optimize=>undef,web_ready=>undef,scale=>undef,large=>undef,small=>undef,thumb=>undef),img=>"$imgroot/copy.png"},
		    undef,
		    {label=>"publish",url=>"$config{server}{CGIpath}/$config{prog}{publish}?back=1&id=".$img->id,img=>"$imgroot/publish.png"},
		    {label=>"unpublish",url=>"$config{server}{CGIpath}/$config{prog}{publish}?back=1&-id=".$img->id,img=>"$imgroot/unpublish.png"},
		    undef,
		    {label=>"delete",confirm=>'Really delete this image?',url=>$this->link(phocmd=>"del",optimize=>undef,web_ready=>undef,scale=>undef,large=>undef,small=>undef,thumb=>undef),img=>"$imgroot/delete.png"},
		]
		);
	    if ($cmd eq "conf") {
		$out .= $this->configure($img);
	    }
	    elsif ($cmd eq "del") {
		$this->delete($img);
		$ml->location($this->link(img=>undef,phocmd=>undef,optimize=>undef,web_ready=>undef,scale=>undef,large=>undef,small=>undef,thumb=>undef,__plaintext=>1));
	    }
	    elsif ($cmd eq "rollback") {
		$out .= $this->rollback($img);
		$out .= $this->show_image();
	    }
	    elsif ($cmd eq "update") {
		# upload new rev
		$out .= $this->update($img);
	    }
	    elsif ($cmd eq "meta") {
		# optional metadata
		$out .= $this->metadata($img);
	    }
	    else {
		$out .= $this->show_image();
	    }
	}
	else {
	    # library
	    $out .= $ui->IconBar(
		links=>[
		    {label=>"preview",url=>$lib->get_url_dynamic(),target=>"_blank",img=>"$imgroot/image.png"},
		    {label=>"configure",url=>$this->link(phocmd=>"conf",optimize=>undef,web_ready=>undef,scale=>undef,large=>undef,small=>undef,thumb=>undef),img=>"$imgroot/conf.png"},
		    {label=>"sort",url=>$this->link(phocmd=>"sort",optimize=>undef,web_ready=>undef,scale=>undef,large=>undef,small=>undef,thumb=>undef),img=>"$imgroot/list.png"},
		    undef,
		    {label=>"upload",url=>$this->link(phocmd=>"new_img",optimize=>undef,web_ready=>undef,scale=>undef,large=>undef,small=>undef,thumb=>undef),img=>"$imgroot/up.png"},
		    {label=>"bulk&nbsp;upload",url=>$this->link(phocmd=>"new_imgs",optimize=>undef,web_ready=>undef,scale=>undef,large=>undef,small=>undef,thumb=>undef),img=>"$imgroot/pages.png"},
		    undef,
		    {label=>"publish",url=>"$config{server}{CGIpath}/$config{prog}{publish}?back=1&id=".$lib->id,img=>"$imgroot/publish.png"},
		    {label=>"unpublish",url=>"$config{server}{CGIpath}/$config{prog}{publish}?back=1&-id=".$lib->id,img=>"$imgroot/unpublish.png"},
		    undef,
		    {label=>"delete",confirm=>'Really delete this album and all of its images?',url=>$this->link(phocmd=>"del",optimize=>undef,web_ready=>undef,scale=>undef,large=>undef,small=>undef,thumb=>undef),img=>"$imgroot/delete.png"},
		]
		);
	    if ($cmd eq "conf") {
		$out .= $this->configure($lib);
	    }
	    elsif ($cmd eq "sort") {
		$out .= $this->order($lib);
	    }
	    elsif ($cmd eq "del") {
		$this->delete($lib);
		$ml->location($this->link(id=>undef,img=>undef,phocmd=>undef,optimize=>undef,web_ready=>undef,scale=>undef,large=>undef,small=>undef,thumb=>undef,__plaintext=>1));
	    }
	    elsif ($cmd eq "new_img") {
		$out .= $this->new_img();
	    }
	    elsif ($cmd eq "new_imgs") {
		# bulk upload
		if ($this->{is_post}) {
		    return $this->do_bulk_upload();
		}
		$out .= $this->new_imgs();
	    }
	    else {
		$out .= $this->show_library();
	    }
	}
    }
    else {
	if ($cmd eq "lib_new") {
	    $out .= $this->new_library();
	}
	else {
	    $out .= $this->list_libraries();
	}
    }
    return $out;

}

sub get_section {
    my $this = shift;
    if (! $this->{section}) {
	if (! $this->{section_id}) {
	    $this->{section_id} = $this->get_section_id;
	}
	$this->{section} = new ExSite::Section(id=>$this->{section_id});
    }
    return $this->{section};
}

sub get_library {
    my ($this) = @_;
    if (! $this->{library}) {
	my $c = new ExSite::Content();
	$this->{library} = $c->get_content_obj($this->{input}{id});
	if ($this->{library} !~ /album|library/) {
	    $this->warn($this->{library}->title." is not a library or album");
	}
    }
    return $this->{library};
}

sub get_image {
    my $this = shift;
    if (! $this->{image}) {
	$this->{image} = new ExSite::Content(id=>$this->{input}{img});
    }
    return $this->{image};
}

sub show_path {
    my $this = shift;
    my @path = ( $ml->a("Top",{href=>$this->link(section_id=>undef,id=>undef,img=>undef,phocmd=>undef,optimize=>undef,web_ready=>undef,scale=>undef,large=>undef,small=>undef,thumb=>undef)}) );
    my $s = $this->get_section();
    if ($s->defined) {
	push @path, $ml->a($s->label,{href=>$this->link(id=>undef,img=>undef,phocmd=>undef,optimize=>undef,web_ready=>undef,scale=>undef,large=>undef,small=>undef,thumb=>undef)});
	my $lib = $this->get_library();
	if ($lib->defined) {
	    push @path, $ml->a($lib->label,{href=>$this->link(img=>undef,phocmd=>undef,optimize=>undef,web_ready=>undef,scale=>undef,large=>undef,small=>undef,thumb=>undef)});
	    my $img = $this->get_image();
	    if ($img->defined) {
		push @path, $ml->a($img->label,{href=>$this->link(phocmd=>undef,optimize=>undef,web_ready=>undef,scale=>undef,large=>undef,small=>undef,thumb=>undef)});
	    }
	}
    }
    return $ui->PathBar(links=>\@path);
}

sub list_libraries {
    my $this = shift;

    my $s = $this->get_section;
    my $r = new ExSite::ReportBuilder(title=>"Albums in ".$s->title);
    $r->nodata("No albums found.");
    $r->foot("Albums contain photos that will be displayed together in a gallery.");
    $r->headers("Title","Contents");
    foreach my $ldata ($s->fetch_content($s->isubtype("album"))) {
	my $album = new ExSite::Album(data=>$ldata);
	$r->push($ml->a($album->title,{href=>$this->link(id=>$album->id)}),
		 $ml->div($album->count_contents,{class=>"num"}),
		 );
    }
#    $r->tools($ml->a("+ new album",{href=>$this->link(phocmd=>"lib_new"),class=>"button_sm"}));
    my $out = $r->make();

    my $r = new ExSite::ReportBuilder(title=>"Libraries in ".$s->title);
    $r->nodata("No libraries found.");
    $r->foot("Libraries can contain photos that can be used individually throughout your site.");
    $r->headers("Title","Contents");
    foreach my $ldata ($s->fetch_libraries()) {
	my $lib = new ExSite::Library(data=>$ldata);
	$r->push($ml->a($lib->title,{href=>$this->link(id=>$lib->id)}),
		 $ml->div($lib->count_contents,{class=>"num"}),
		 );
    }
#    $r->tools($ml->a("+ new library",{href=>$this->link(phocmd=>"lib_new"),class=>"button_sm"}));
    $out .= $r->make();
    $out .= $ml->p($ui->Button(label=>"+ new photo album",url=>$this->link(phocmd=>"lib_new")));
    return $out;
}

sub new_library {
    my $this = shift;
    if ($this->{is_post}) {
	my $type = $this->{post}{type} =~ /^library/ ? "library" : "album";
	my $c = new ExSite::Content;
	my $lib = $c->new_content_obj(
	    title=>$this->{post}{title},
	    type=>$c->isubtype($type),
	    parent=>$this->get_section_id(),
	    );
	if ($lib->id) {
	    $ml->location($this->link(__plaintext=>1,id=>$lib->id,phocmd=>undef));
	}
	else {
	    return &ExSite::Config::show_diagnostics();
	}
    }
    else {
	my $f = new ExSite::FormBuilder();
	$f->input(name=>"title",prompt=>"Album Name",type=>"text",required=>1);
	$f->input(name=>"type",prompt=>"Type",type=>"select",options=>["album - photos that will be displayed together in a gallery","library - photos that will be used individually on various pages"],required=>1);
	$f->set("buttons",$ml->input(undef,{type=>"submit",value=>"make album"}));
	return $ml->h1("New Album") . $f->make();
    }
}

sub show_library {
    my $this = shift;
    my $lib = $this->get_library();
    my $out = $ml->h1($lib->title);
    my $nonimg = 0;
    foreach my $img ($lib->get_contents()) {
	my %info = $img->revision->get_fileinfo;
	if ($info{mimetype} =~ /^image/) {
	    my $thumb = $img->revision->get_thumb_url;
	    my $caption = $img->caption();
	    $out .= $ml->a(
		$ml->div(
		    $ml->div(
			$ml->img(undef,{src=>$thumb}),
			{class=>"ImageThumb"}
		    ).
		    $ml->div(
			($caption ? $ml->span($img->caption,{class=>"ImageCaption"})." " : "").
			$ml->span($img->content_info,{class=>"ImageInfo"}),
			{class=>"ImageDetails"}
		    ),
		    {class=>"ImageSlide"}
		),
		{href=>$this->link(img=>$img->id,optimize=>undef,web_ready=>undef,scale=>undef,large=>undef,small=>undef,thumb=>undef)}
	    );
	}
	else {
	    $nonimg++;
	}
    }
    if ($nonimg) {
	$out .= $ml->warn("$nonimg non-image file(s) found in this library. Use the Documents plug-in to manage these.");
    }
    return $ml->div($out,{class=>"AlbumPreview clearfix"});
}

sub show_image {
    my $this = shift;
    my $img = $this->get_image();
    my @row;
    my %info = $img->revision->get_fileinfo();
    push @row, $ml->tr($ml->th("Title").$ml->td($img->title));
    push @row, $ml->tr($ml->th("Caption").$ml->td($img->caption));
    push @row, $ml->tr($ml->th("Type").$ml->td($img->show_icon."&nbsp;".&MimeDescr($info{mimetype})));
    push @row, $ml->tr($ml->th("Size").$ml->td($info{size}));
    if ($img->is_published) {
	my $url = $img->get_url();
	push @row, $ml->tr($ml->th("Published URL").$ml->td($ml->a($url,{href=>$url,target=>"_blank"})));
    }
    my $url = $img->get_url_dynamic();
    push @row, $ml->tr($ml->th("Preview URL").$ml->td($ml->a($url,{href=>$url,target=>"_blank"})));
    $url =~ s/ex\.cgi\/view\//ex.cgi\/page\//;
    push @row, $ml->tr($ml->th("Pseudo-page URL").$ml->td($ml->a($url,{href=>$url,target=>"_blank"})));
    my $out = $ml->table({caption=>$img->title,tbody=>join("",@row)},{class=>"Report"});
    my @rev = $img->get_revisions();
    $out .= $ml->h3("Revisions");
    if ($session{Image_publish_warning}) {
	$out .= $ui->SuccessBox(title=>"Upload complete",
					  pane=>"You can publish the image now, or when you are done with your updates, you can republish the library.");
	delete $session{Image_publish_warning};
    }
    my @revout;
    my @revs = reverse $img->get_revisions();
    foreach my $revdata (@revs) {
	my $path = $img->path;
	my $rev = new ExSite::Revision(data=>$revdata);
	my %info = $rev->get_fileinfo();
	my $time = new ExSite::Time($rev->timestamp,"sql_timestamp");
	my $revinfo = $ml->a($info{description},{href=>"$config{server}{CGIpath}/$config{prog}{view}$path?revision=".$rev->id,title=>$img->name.".".&MimeToFile($info{mimetype})})." uploaded ".$time->write("datetime");
	if (@revout == 0 && scalar @revs > 1) {
	    $revinfo .= " ".$ui->Button(label=>"rollback",confirm=>'Really delete this revision?',url=>$this->link(phocmd=>"rollback",optimize=>undef,web_ready=>undef,scale=>undef,large=>undef,small=>undef,thumb=>undef),type=>"link-button",size=>"s",tone=>"bad",faicon=>"undo");
	}
	push @revout, $revinfo;
    }
    if (scalar @revout) {
	$out .= $ml->p("Most recent shown first. Click to download.");
	$out .= $ml->ol(\@revout);
	$out .= $ml->h3("Previews");
	$out .= $img->preview(view=>"all");
    }
    else {
	$out .= $ui->ErrorBox(title=>"No Revisions",
			      pane=>"This image has no files or data associated with it; it should be updated or deleted.");
    }
    return $out;
}

# add a new image

sub new_img {
    my $this = shift;
    my $out;
    return $this->setup_img if ($this->{is_post});
    $out .= $ml->h1("Upload new image");
    my $f = new ExSite::FormBuilder();
    $f->input(name=>"upload",prompt=>"Choose image",type=>"file",required=>1);
    $out .= $f->make();
    return $out;
}

sub setup_img {
    my $this = shift;
    my $out;
    my $input = new ExSite::Input();
    my $fdata = $this->{input}{file};
    if ($fdata) {
	my $lib = $this->get_library();
	my $img = new ExSite::Content();
	my $image = new ExSite::Image($fdata);
	my $name = $image->get("filename");
	my $mimetype = &MimeType($name);
	$name =~ s/\.\w+$//;
	if ($this->{input}{img}) {
	    $img->setup(id=>$this->{input}{img});
	}
	else {
	    $img = $img->new_content_obj(
		title=>$this->{input}{title}||$name,
		parent=>$lib->id,
		);
	}
	my $web_ready = 0;
	if ($this->{input}{caption}) {
	    $img->meta->set("caption",$this->{input}{caption});
	}
	my %view;
	if ((! $this->{input}{scale} && $this->{input}{optimize}) ||
	    $this->{input}{web_ready}) {
	    # no scaling that will perform web optimizations automatically,
	    # so perform them explicitly
	    $image->jpeg;
	    my $filename = $image->get("filename");
	    if ($filename !~ /\.jpe?g$/i) {
		# file type conversion; rename file for better mimetyping
		$filename =~ s/\.\w+$/\.jpg/;
		$image->set("filename",$filename);
	    }
	    $fdata = $image->encode;
	}
	    
	if (! $this->{input}{scale}) {
	    # force normal view
	    $view{normal} = {
		'format'=>"file",
		data=>$fdata,
	    }
	}
	else {
	    # autoscale
	    $view{normal} = 1;
	}
	$view{thumbnail} = 1 if ($this->{input}{thumb});
	$view{small} = 1 if ($this->{input}{small});
	$view{large} = 1 if ($this->{input}{large});
	if ($img->revise(data=>$fdata,
			 'format'=>"file",
			 note=>"uploaded from PhotoAlbum plugin",
			 view=>\%view)) {
	    # success - redirect to image view
	    $ml->location($this->link(__plaintext=>1,img=>$img->id));
	}
	else {
	    $out .= &ExSite::Config::show_diagnostics();
	}
    }
    else {
	$out .= $ml->h1("Setup new image");
	my $f = new ExSite::FormBuilder();
	$config{form}{stack_checkboxes} = 2;
	my $file = $input->fetch_file("upload");
	if ($file) {
	    $f->input(type=>"hidden",name=>"file",value=>$file);	    
	    $f->template("<p>","[[input]] [[prompt]]".$ml->br,"</p>");
	    my $img = new ExSite::Image($file);
	    my $name = $img->get("filename");
	    my $mimetype = &MimeType($name);
	    $name =~ s/\.\w+$//;
	    if ($mimetype =~ /^image/) {
		my ($x,$y) = $img->dim;
		my $size = (int($img->size / 100) / 10) . " kB";
		my $dim = ($x > $y) ? $x : $y;
		$out .= $ui->SuccessBox(title=>"Image received, but has not been saved yet",pane=>"You uploaded a $size $x &times; $y ".&MimeDescr($mimetype).".".$ml->br."Please configure it as follows:",size=>"m");
		$f->input(name=>"title",prompt=>"Titles are used for accessibility and alt-tags",type=>"text",size=>40,placeholder=>"image title (optional)");
		$f->input(name=>"caption",prompt=>"Captions will be used by some (but not all) photo galleries",type=>"text",size=>80,placeholder=>"caption (optional)");
		$this->new_image_setup_options($f);
		$out .= $f->make();
	    }
	    else {
		$out .= $this->error("Uploaded files must be JPG, PNG, or GIF format.");
	    }
	}
	else {
	    $out .= $this->error("No file was uploaded.");
	}
    }
    return $out;
}

sub new_image_setup_options {
    my ($this,$f) = @_;
    $f->input(name=>"optimize",type=>"checkbox",prompt=>"Optimize image file size where possible",value=>1,checked=>1);
    $f->input(name=>"web_ready",type=>"checkbox",prompt=>"Convert images to web-friendly JPG format",value=>1);
    $f->input(name=>"scale",type=>"checkbox",prompt=>"Downscale oversize images to standard ($config{content}{viewdim}{normal} pixel) size",value=>1,checked=>1);
    $f->input(name=>"large",type=>"checkbox",prompt=>"Keep a larger version on file, if possible",value=>1);
    $f->input(name=>"small",type=>"checkbox",prompt=>"Keep a smaller version on file, if possible",value=>1);
    $f->input(name=>"thumb",type=>"checkbox",prompt=>"Make a thumbnail",value=>1,checked=>1);
    return;
}

sub new_imgs {
    my $this = shift;
    my $lib = $this->{input}{id};
    my $out = $ml->h1($msg{"Upload multiple images"});
    if (! exists $this->{input}{scale}) {
	$out .= $ml->p("Pre-select your image processing options below. Captions and titles can be edited after files are uploaded.");
	my $f = new ExSite::FormBuilder(method=>"get",action=>$this->link());
	$f->template("<p>","[[input]] [[prompt]]".$ml->br,"</p>");
	$f->input(type=>"hidden",name=>"section_id",value=>$this->{input}{section_id});
	$f->input(type=>"hidden",name=>"phocmd",value=>"new_imgs");
	$f->input(type=>"hidden",name=>"id",value=>$this->{input}{id});
	$this->new_image_setup_options($f);
	$f->buttons(submit=>"next &gt;");
	$out .= $f->make();
    }
    else {
	my $link = $this->link(__plaintext=>1,_bare=>2);
	my @param;
	foreach my $par (%{$this->{input}}) {
	    next if (! $this->{input}{$par});
	    push @param, "$par: '$this->{input}{$par}'";
	}
	push @param, "'_bare': 2";
	my $param = join(", ",@param);
#/PhotoAlbum?_bare=2&section_id=$this->{section_id}&phocmd=new_imgs',
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
            action: '$config{server}{CGIpath}/$config{prog}{ctrlpanel}/PhotoAlbum',
            debug: true,
            sizeLimit: $config{max_upload_size},
            params: { $param }
        });           
        }
        
    // create uploader as soon as the DOM is ready
    window.onload = createUploader;     
    </script>
END
    }
    return $out;
}

### FIXME: install files, rather that save them to DB?

sub do_bulk_upload {
    my $this = shift;
    my $lib = $this->get_library();
    my $in = new ExSite::Input;
    my $input = $in->combine;
    my $file = $in->fetch("post","raw");
    my $filename = &clean_filename($input->{qqfile});
    my $image = new ExSite::Image($filename,$file);
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
    my $fdata = $filename.$config{form}{sepchar}.encode_base64($file,"");
    my $c = new ExSite::Content();
    my $newimg = $c->new_content_obj(
	type=>$c->isubtype("content"),
	label=>$filename,
	parent=>$lib->id,
	);
    $config{debug} = 0; # disable debug footers, which will mess up JSON reply
    $ml->cancel; # disable regular page output  ### doesn't do anything, since cntrl-panels do not use ML
    if (! $newimg->ok) {
	$this->error("Failed to create new content object");
	my $error = $newimg->show_diagnostics("error");
	print STDERR "$error.\n";
	print qq|{ "success": false, "error": "$filename - $error" }|;
    }
    my %view = (
	large=>$this->{input}{large},
	small=>$this->{input}{small},
	thumbnail=>$this->{input}{thumb},
	normal=>$this->{input}{scale} ? 1 : {'format'=>"file", data=>$fdata},
	);
    if ($newimg && $newimg->ok) {
	if ($newimg->revise('format'=>"file",
			    note=>"uploaded to Images app on ".(scalar localtime),
			    data=>$fdata,
			    view=>\%view )) {
	    # success
	    return qq|{ "success": true }|;
	    print STDERR "file has been successfully uploaded... thank you.\n";
	}
	else {
	    # bad revision
	    $newimg->delete;
	    my $error = $newimg->show_diagnostics("error");
	    print STDERR "$error.\n";
	    return qq|{ "success": false, "error": "$filename - $error" }|;
	}
    }
    else {
	# cannot make content obj
	my $error = $newimg->show_diagnostics("error");
	print STDERR "$error.\n";
	return qq|{ "success": false, "error": "$filename - $error" }|;
    }
}

# update an existing image

sub update {
    my ($this,$img) = @_;
    my $out;
    return $this->setup_img if ($this->{is_post});
	my $title = $ml->em($img->title);
	$out = $ml->h1($msg{"Upload new version of"}." ".$title);
	my $f = new ExSite::FormBuilder(action=>$this->link());
	$f->input(type=>"file",name=>"upload",prompt=>"Select new file:",required=>1);
	$f->buttons(submit=>"Upload");
	$out .= $f->make();
#    }
    return $out;
}

sub metadata {
    my ($this,$img) = @_;
    my @meta = $img->meta->get_allowed();
    my $out = $ml->h1("Optional Metadata for ".$img->name);

    my $input = new ExSite::Input;
    my $post = $input->post;
    if (scalar keys %$post > 0) {
	foreach my $meta (sort @meta) {
	    my $meta_new = $post->{$meta};
	    $img->meta->set_nosave($meta,$meta_new);
	}
	$img->meta->save;
	$out .= $ml->div("Metadata updated.",{class=>"notice"});
    }

    my %meta = $img->get_metadata();
    my $form = new ExSite::FormBuilder(action=>$this->link());
    my ($template1, $template2);
    foreach my $meta (sort @meta) {
	next if ($meta =~ /^DC\./);
	my $input = $img->meta->input($meta,$meta);
	$form->input(name=>$meta,prompt=>$img->meta->label($meta),input=>$input,value=>$meta{$meta});
	$template1 .= $ml->tr($ml->td("[[$meta:prompt]]").$ml->td("[[$meta:input]]"));
    }
    # put DC metadata after custom metadata
    foreach my $meta (sort @meta) {
	next if ($meta !~ /^DC\./);
	my $input = $img->meta->input($meta,$meta);
	$form->input(name=>$meta,prompt=>$img->meta->label($meta),input=>$input);
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

# order : manually re-sort sub-content

sub order {
    my ($this,$c) = @_;
    my $out;
    my $ml = &get_obj("ML");
    if (scalar keys %{$this->{post}} > 0) {
	# oid=144&oid=143&oid=142&oid=141
	my @sort = split /&?oid=/,$share{input}{post}{raw};
	shift @sort; # first one is a dummy
	my $order = 0;
	foreach my $cid (@sort) {
	    $order++;
	    my $c = $c->get_content_obj($cid);
	    my $sortkey = sprintf("%04d",$order);
	    $c->setdata("sortkey",$sortkey);
	    $c->save;
	}
	$out .= $this->info("Re-ordered $order items.");
    }
    my $tree = $c->get_content_tree;
    my @child = $tree->get_child_data($c->id);
    my @order;
    foreach my $ch (@child) {
	my $c = $c->get_content_obj($ch);
	push @order, $c->show_icon.$c->label." (".&MimeDescr($c->revision->mime_type).")".$ml->input(undef,{type=>"hidden",name=>"oid",value=>$c->id});
    }
    if (scalar @order > 1) {
	$out .= $ml->h1("Re-order Images");
	$out .= $ml->p("Drag images into their new order, then click the save button.");
	$out .= &ExSite::HTML::js();
	$out .= $ml->script('
$(function() {
  $( "#sortable" ).sortable();
  $( "#sortable" ).disableSelection();
});
');
	$out .= $ml->form(
	    $ml->ul(\@order,{id=>"sortable"}).
	    $ml->input(undef,{type=>"submit",value=>"Save order"}),
	    {action=>$this->link(),method=>"post",id=>"sortableContent"}
	    );
    }
    else {
	$out .= $this->warn("There are not enough images to order.");
    }
    return $out;
}

1;

