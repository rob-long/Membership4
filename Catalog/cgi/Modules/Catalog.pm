package Modules::Catalog;

use strict;
use ExSite::Config;
use ExSite::Catalog;
use ExSite::Product;
use ExSite::Misc;
use ExSite::Util;
use ExSite::UI;
use ExSite::Time;
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
    my $path = $in->path();
}

sub write {
    my ($this,$options) = @_;
    my $out;
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    my %opt = &DecodeString($options);
    my $cmd = $this->{query}{cmd} || $opt{cmd};
    if ($opt{cmd} =~ /addtocart/) {
	$out .= $this->add_to_cart();
    }
    else {
	my $id = $this->{query}{id} || $opt{id};
	if ($id) {
	    my $c = new ExSite::Content(id=>$id);
	    if ($c->subtype =~ /catalog|product/) {
		$c = $c->get_content_obj();
		$this->{content} = $c;
		$out .= $c->show();
	    }
	    else {
		$out .= $this->warn(&substitute($msg{"Content node [[id]] ('[[title]]') cannot be displayed by Catalog."},{id=>$id,title=>$c->title}));
	    }
	}

	# default to top-level catalog objects?
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
	return "Catalog";
    }
    elsif (/Dependencies/) {
	return ["Finance"];
    }
    elsif (/Category/) {
	return $config{Catalog}{Category} ?
	    $config{Catalog}{Category} :
	    ["Ecommerce","Applications"];
    }
}

sub ctrl_panel {
    my $this = shift;
    $this->{admin} = 1;
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    my $cmd = $this->{input}{cmd};
    my $id = $this->{input}{id};
    my $c = new ExSite::Content();
    $this->{content} = $c->get_content_obj($id);
    my $out;
    my $out = &insert_js("misc","jquery.magnific-popup.min");
    $out .= $ml->link(undef,{rel=>"stylesheet",href=>"$config{server}{HTMLpath}/_ExSite/css/magnific-popup.css"});
    if ($id) {
	if ($this->{content}->subtype !~ /catalog|product/) {
	    return $this->warn($ml->em($this->{content}->title)." is not a catalog or product!");
	}
	$out .= $this->pathbar($this->{content});
	$out .= $this->toolbar($this->{content});
	if ($cmd) {
	    if ($cmd eq "conf") {
		$out .= $this->configure($this->{content});
	    }
	    elsif ($cmd eq "edit") {
		$out .= $this->update($this->{content},format=>"html",prompt=>"Product Details",name=>"product_descr");
	    }
	    elsif ($cmd eq "new") {
		$out .= $this->new_product;
	    }
	    elsif ($cmd =~ /^price/) {
		$out .=  $this->pricing($this->{content});
	    }
	    elsif ($cmd =~ /^image/) {
		$out .=  $this->images($this->{content});
	    }
	    elsif ($cmd =~ /option/) {
		$out .=  $this->options();
	    }
	    elsif ($cmd eq "del") {
		my $p = $this->{content}->parent();
		$this->{content}->delete();
		$ml->redirect($this->link(__plaintext=>1,cmd=>undef,id=>$p->id));
		return;
	    }
	    elsif ($cmd =~ /^(publish|cancel|approve)$/) {
		$out .= $this->$1;
		$out .= $this->show();
	    }
	    elsif ($cmd eq "newcat") {
		$out .=  $this->new_catalog;
	    }
	    else {
		$out .= $this->warn("$cmd: unknown command");
		$out .= $this->show();
	    }
	}
	else {
	    $out .= $this->show();
	}
    }
    elsif ($cmd eq "newcat") {
	$out .=  $this->new_catalog;
    }
    else {
	$out .= $this->list_catalogs($cmd);
    }
    return $out;
}

sub toolbar {
    my ($this,$c) = @_;
    my $type = $c->subtype();
    my $icondir = "$config{server}{HTMLpath}/_ExSite/images/icons";
    if ($type eq "catalog") {
	my $out = $ui->IconBar(
	    links=>[
		{label=>"new&nbsp;category",url=>$this->link(cmd=>"newcat",id=>$c->id),img=>"$config{server}{HTMLpath}/_Modules/Catalog/add_category.png"},
		{label=>"new&nbsp;product",url=>$this->link(cmd=>"new",id=>$c->id),img=>"$icondir/add.png"},
		{label=>"edit&nbsp;description",url=>$this->link(cmd=>"edit",id=>$c->id),img=>"$icondir/edit.png"},
		{label=>"configure",url=>$this->link(cmd=>"conf",id=>$c->id),img=>"$icondir/conf.png"},
		undef,
		{label=>"publish",url=>$this->link(cmd=>"publish",id=>$c->id),img=>"$icondir/publish.png"},
		undef,
		{label=>"DELETE",url=>$this->link(cmd=>"del"),tone=>"bad",img=>"$icondir/delete.png",confirm=>"Really unpublish and delete all categories and products under ".&quote_escape($c->title)."?"},
	    ]);
    }
    elsif ($type eq "product") {
	return $ui->IconBar(
	    links=>[
		{label=>"configure",url=>$this->link(cmd=>"conf",id=>$c->id),img=>"$icondir/conf.png"},
		{label=>"description",url=>$this->link(cmd=>"edit",id=>$c->id),img=>"$icondir/edit.png"},
		{label=>"pricing",url=>$this->link(cmd=>"price",id=>$c->id),img=>"$icondir/money.png"},
		{label=>"photos",url=>$this->link(cmd=>"image",id=>$c->id),img=>"$icondir/image.png"},
		{label=>"options",url=>$this->link(cmd=>"option",id=>$c->id),img=>"$icondir/approve.png"},
		undef,
#		{label=>"preview",url=>$c->get_url_dynamic(),img=>"$icondir/view.png",target=>"_blank"},
		{label=>"preview",url=>"javascript:openOLFrame()",img=>"$icondir/view.png"},
		{label=>"publish",url=>$this->link(cmd=>"publish",id=>$c->id),img=>"$icondir/publish.png"},
		undef,
		{label=>"delete",url=>$this->link(cmd=>"del",id=>$c->id),img=>"$icondir/delete.png",confirm=>"Really delete this product?"},
	    ]).
	    $ui->OverlayFrame(url=>$c->get_url_dynamic());
    }
}

sub list_catalogs {
    my ($this,$cmd) = @_;
    my ($pane,$thistab);
    my $c = new ExSite::Content();
    my $tree = $c->get_content_tree();
    my @cat = $tree->find({type=>$c->isubtype("catalog")});
    if ($cmd eq "listtree") {
	$pane = $this->list_catalogs_tree($tree,\@cat);
	$thistab = 2;
    }
    elsif ($cmd eq "listall") {
	my $r = new ExSite::ReportBuilder(title=>"Catalogs");
	$r->headers("Category","Status","Products");
	$r->nodata("No catalogs.");
	my $productype = $c->isubtype("product");
	foreach my $cat (@cat) {
	    my $catalog = new ExSite::Catalog(data=>$cat);
	    my $status = $catalog->wf_status();
	    my @products = $catalog->get_contents("product");
	    $r->push(
		$ml->a(scalar $catalog->path(),{href=>$this->link(id=>$catalog->id,cmd=>undef)}),
		$ml->span($status,{class=>"status".ucfirst($status)}),
		$ml->div(scalar @products,{class=>"num"}),
	    );
	}
	$r->set("dynamic",1);
	$pane = $r->make().$ml->br();
	$thistab = 1;
    }
    else {
	# just jump straight to the top category
	my $top = shift @cat;
	my $catalog = new ExSite::Catalog(data=>$top);
	$pane .= $this->toolbar($catalog);
	$pane .= $this->show_catalog($catalog);
	$thistab = 0;
    }
    return $ui->TabBox(
	tabs=>[
	    {label=>"Top",url=>$this->link(cmd=>undef)},
	    {label=>"All",url=>$this->link(cmd=>"listall")},
	    {label=>"Browser",url=>$this->link(cmd=>"listtree")},
	],
	pane=>$pane,
	thistab=>$thistab,
	);
}

#### doesn't clear subcats
sub list_catalogs_tree {
    my ($this,$tree,$cats) = @_;
    my $r = new ExSite::ReportBuilder(title=>"Catalogs");
    $r->headers("Title","Location","Products");
    $r->nodata("No catalogs.");
    my %cat = map { $_->{content_id} => $_ } @$cats;
    my @list;
    while (scalar keys %cat) {
	my $top = shift @$cats;
	my $topcat = new ExSite::Catalog(data=>$top);
	delete $cat{$top->{content_id}};
	my $class = "catalog status".ucfirst($topcat->wf_status());
	push @list, {
	    label=>$ml->span($topcat->label,{class=>$class}),
	    url=>$this->link(id=>$topcat->id,cmd=>undef),
	    open=>1,
	    sublist=>$this->list_subcatalogs($topcat,$tree,\%cat),
	};
    }
    return $ui->DynList(@list);
}

sub list_subcatalogs {
    my ($this,$node,$tree,$cat) = @_;
    my @list;
    foreach my $ch ($tree->get_child_data($node->id)) {
	my $obj = $node->get_content_obj($ch);
	my $subtype = $obj->subtype();
	next if ($subtype !~ /catalog|product/);
	my $class = "$subtype status".ucfirst($obj->wf_status());
	push @list, {
	    label=>$ml->span($obj->label,{class=>$class}),
	    url=>$this->link(id=>$obj->id,cmd=>undef),
	    open=>0,
	    sublist=>$obj->subtype eq "catalog" ? $this->list_subcatalogs($obj,$tree,$cat) : undef,
	    };
	delete $cat->{$obj->id};
    }
    return \@list;
}

sub show {
    my ($this) = @_;
    my $c = $this->{content};
    my $out;
    if ($c->subtype eq "catalog") {
	$out .= $this->show_catalog($c);
    }
    elsif ($c->subtype eq "product") {
	$out .= $this->show_product($c);
    }
    else {
	$out .= $this->warn($ml->em(ucfirst $c->name)." is a ".$c->subtype()."; the Catalog module can only be used to manage Catalogs and Products. Click on 'Top' to see a list of available Catalogs.");
    }
    return $out;
}

sub show_catalog {
    my ($this,$cat) = @_;
    return $this->error("Permission denied.") if (! $cat->allow("insert"));
    my $out = $ml->h1($cat->title);
    $out .= $cat->get_html();
    my $tree = $cat->get_content_tree();
    my @catchild = $tree->get_child_data($cat->id);
    my $r = new ExSite::ReportBuilder(title=>"Subcategories");
    $r->headers("Category","Status","Products");
    $r->nodata("No subcategories.");
    my $icatalog = $cat->isubtype("catalog");
    my $iproduct = $cat->isubtype("product");
    foreach my $cdata (@catchild) {
	next if ($cdata->{type} != $icatalog);
	my $subcat = new ExSite::Catalog(data=>$cdata);
	my $status = $subcat->wf_status();
	my $pcount = $tree->count({type=>$iproduct},$subcat->id);
	$r->push($ml->a($subcat->title,{href=>$this->link(id=>$subcat->id)}),
		 $ml->span($status,{class=>"status".ucfirst($status)}),
		 $ml->div($pcount,{class=>"num"}),
	    );
    }
    $out .= $r->make();

    $r->init(title=>"Products");
    $r->headers("Product","Status","Price");
    $r->nodata("No products found.");
    $r->set("dynamic",1);
    foreach my $pdata (@catchild) {
	next if ($pdata->{type} != $iproduct);
	my $prod = new ExSite::Product(data=>$pdata);
	my $status = $prod->wf_status();
	my $price = new ExSite::Object(type=>"price",data=>$prod->price);
	$r->push($ml->a($prod->title,{href=>$this->link(id=>$prod->id)}),
		 $ml->span($status,{class=>"status".ucfirst($status)}),
		 $ml->div($price->showdata("cost"),{class=>"num"}),
	    );
    }
    $out .= $r->make();
    return $out;
}

sub show_product {
    my ($this,$prod) = @_;
    return $this->error("Permission denied.") if (! $prod->allow("update"));
    $prod->load_revision("newest");
    # show just this product
    return $ui->BasicBox(
	title=>"Product Details",
	pane=>$prod->preview(),
	);
}

sub new_catalog {
    my $this = shift;
    my $c = new ExSite::Catalog;
    if (scalar keys %{$this->{post}} > 0) {
	return $c->do_make();
    }
    else {
	my $out;
	$out .= $ml->h1("New Catalog");
	my $pid = $this->{input}{id} || $this->get_section_id();
	if ($pid) {
	    my @hide = qw(content_id type url parent template master sortkey content_role mtime ptime);
	    $out .= $c->make(hide=>\@hide,data=>{parent=>$pid,type=>$c->isubtype("catalog"),access=>0,publish=>"static",status=>4},extra=>{reply=>$this->link(__plaintext=>1,cmd=>undef)});
	}
	else {
	    $out .= $this->set_section_id();
	}
	return $out;
    }
}

sub new_product {
    my $this = shift;
    my $c = $this->{content};
    my $out;
    if (scalar keys %{$this->{post}} > 0) {
	my %post = $share{DB}->parse_parts(%{$this->{post}});
	if ($post{title} && $post{price}) {
	    my %pdata = (
		title=>$post{title},
		parent=>$c->id,
		status=>$c->wf_istatus("draft"),
		type=>$c->isubtype("product"),
		);
	    my $pid = $c->new_content(%pdata);
	    if ($pid) {
		$pdata{content_id} = $pid;
		my $prod = new ExSite::Product(data=>\%pdata);
		if ($post{description}) {
		    $prod->revise(data=>$post{description},format=>"text");
		}
		my %price = (
		    );
		if ($share{DB}->insert("price",{
		    content_id=>$prod->id,
		    status=>"active",
		    cost=>$post{price},
		    access=>0})) {
		    $ml->redirect($this->link(__plaintext=>1,id=>$prod->id,cmd=>undef));
		}
		else {
		    $out .= $share{DB}->show_diagnostics("error","html");
		}
	    }
	    else {
		$out .= $c->show_diagnostics("error","html");
	    }
	}
	else {
	    $out .= $this->error("You must specify both a title and a price.");
	}
    }
    else {
	$out .= $ml->h1("New Product");
	my $db = $share{DB};
	my $f = $db->form();
	$f->input(name=>"title",prompt=>"Product Name",type=>"text",size=>80,required=>1);
	$f->input(name=>"price",prompt=>"Price",type=>"text",size=>10,required=>1);
	$db->input_htmleditor(
	    prompt=>"Product Details",
	    name=>"description",
	    editor_height=>350,
	    editor_width=>550,
	    required=>1
	    );
	
	$out .= $db->form->make();
    }
    return $out;
}

sub images_old {
    my $this = shift;
    my $c = $this->{content};
    my $out;
    if ($this->{input}{cmd} eq "image_add") {
	return $this->image_add();
    }
    elsif ($this->{input}{cmd} eq "image_edit") {
	return $this->image_edit();
    }
    elsif ($this->{input}{cmd} eq "image_sort") {
	$out .= $this->image_sort();
    }
    elsif ($this->{input}{cmd} eq "image_del") {
	my $photo = new ExSite::Content(id=>$this->{input}{img});
	$photo->delete();
	$ml->location($this->link(cmd=>"image",__plaintext=>1));
	return undef;
    }
    $out .= $ml->h1("Photos for ".$ml->em($c->title));
    $out .= $ml->script('
$(function() {
  $( "#sortable" ).sortable();
  $( "#sortable" ).disableSelection();
});
$(document).ready(function(){
  $(".popupLink").magnificPopup({type:"inline"});
})
');
    my $lout;
    my $capout;
    my $nimg;
    my @photo = $c->get_contents();
    if (scalar @photo) {
	foreach my $p (@photo) {
	    next if (! $p->revision->is_image);
	    $p->set_view("thumbnail");
#	    $p->revision->view("thumbnail");
	    my $pout = $ml->div($p->show(),{class=>"imageThumb"});
	    my $caption = $p->caption();
	    my $popupid = "editCaption".$p->id;
	    $capout .= $ml->div(
		$ml->form("Caption: ".
		$ml->input(undef,{type=>"text",name=>"caption",size=>40,value=>$caption}).
		$ml->input(undef,{type=>"submit",value=>"update caption"}),
		{action=>$this->link(cmd=>"image_edit",img=>$p->id),method=>"post"}),
		{id=>$popupid,class=>"editCaption white-popup mfp-hide"}
		);
	    $pout .= $ml->div(
		$ml->p("Caption: ".$ml->em($caption).$ml->a("edit",{href=>"#$popupid",class=>"popupLink button_sm"})).
		$ml->p($ml->a("delete image",{href=>$this->link(cmd=>"image_del",img=>$p->id),class=>"imageDelete"})),
		{class=>"imageEditDetails"});
	    $pout .= $ml->input(undef,{type=>"hidden",name=>"order",value=>$p->id});
	    $lout .= $ml->li($pout, {class=>"catalogProductImage"});
	    $nimg++;
	}
	$out .= $ml->form(
	    $ml->ul($lout,{id=>"sortable"}).
	    ($nimg>1?$ml->input(undef,{type=>"submit",value=>"save order"}):""),
	    {action=>$this->link(cmd=>"image_sort"),method=>"post"}
	    );
	$out .= $capout;
    }
    else {
	$out .= $ml->p("No photos have been uploaded for this product.");
    }
    $out .= $ml->p(
	$ui->Button(label=>"upload new photo",url=>$this->link(cmd=>"image_add"))
	);
    return $ml->div($out,{class=>"catalogProductImageList"});
}

sub image_add_old {
    my $this = shift;
    my $c = $this->{content};
    my $out;
    my $db = $share{DB};
    if (scalar keys %{$this->{post}} > 0) {
	my $in = new ExSite::Input;
	my $fdata = $in->fetch_file("photo");
	if ($fdata) {
	    my $fname = $in->fetch_file("photo","name");
	    my $img = $c->new_content_obj(name=>$fname,type=>"content",parent=>$c->id);
	    if ($img->id) {
		$img->revise(data=>$fdata,format=>"file",view=>{normal=>1,small=>1,thumbnail=>1});
		if ($this->{post}{caption}) {
		    $img->set_metadata("caption",$this->{post}{caption});
		    $img->save();
		    $out .= $db->show_diagnostics("error","html");
		}
		#$ml->location($this->link(__plaintext=>1,cmd=>"image"));
	    }
	    else {
		$out .= $db->show_diagnostics("error","html");
	    }
	}
    }
    else {
	$out .= $ml->h1("Add Image");
	my $f = new ExSite::FormBuilder();
	$f->input(type=>"file",name=>"photo",prompt=>"Image",required=>1);
	$f->input(type=>"text",name=>"caption",prompt=>"Caption",size=>40);	
	$out .= $f->make();
    }
    return $out;
}

sub image_edit_old {
    my $this = shift;
    if (scalar keys %{$this->{post}} > 0) {
	if ($this->{post}{caption}) {
	    my $photo = $this->{content}->get_content_obj($this->{input}{img});
	    $photo->set_metadata("caption",$this->{post}{caption});
	    $photo->save();
	}
    }
    #return $db->show_diagnostics("error","html");
    $ml->location($this->link(__plaintext=>1,cmd=>"image",img=>undef));
}

sub image_sort_old {
    my $this = shift;
    if (scalar keys %{$this->{post}} > 0) {
	my @order = split /; /,$this->{post}{order};
	my $isort = 1;
	foreach my $photo_id (@order) {
	    my $p = new ExSite::Content(id=>$photo_id);
	    $p->setdata("sortkey",$isort);
	    $p->save;
	    $isort++;
	}
    }
    $ml->location($this->link(__plaintext=>1,cmd=>undef,img=>undef));
}

sub options {
    my ($this) = @_;
    my $c = $this->{content};
    my @meta = $c->meta->get_allowed();
    my $out = $ml->h1("Options for ".$ml->em($c->title));

    my $input = new ExSite::Input;
    my $post = $input->post;
    if (scalar keys %$post > 0) {
	foreach my $meta (sort @meta) {
	    my $meta_new = $post->{$meta};
	    $c->meta->set_nosave($meta,$meta_new);
	}
	$c->meta->save;
	$out .= $ui->SuccessBox(title=>"Success",pane=>"Options updated.");
    }

    my %meta = $c->get_metadata();
    my $form = new ExSite::FormBuilder(action=>$this->link());
    foreach my $meta (sort @meta) {
	next if ($meta =~ /^DC\./);  # skip Dublin Core stuff
	my $input = $c->meta->input($meta,$meta);
	my $label = $c->meta->label($meta);
	my $tip;
	if ($label =~ /^Option_/) {
	    $tip = "List available options, separated by the bar character, |.";
	    $label =~ s/^Option_//g;
	}
	elsif ($label eq "Shipping_size") {
	    $tip = "Shipping size is used to calculate shipping surcharges. It must be a number.";
	}
	$label =~ s/_/ /g;
	$form->input(name=>$meta,prompt=>$label,input=>$input,value=>$meta{$meta},tail=>$tip);
    }
    $out .= $form->make();
    return $out;
}

# status changes

sub publish {
    my $this = shift;
    my $c = $this->{content};
    if ($c->wf_status eq "canceled") {
	# update status as well
	$c->wf_publish;
    }
    else {
	$c->publish();
    }
    return $ml->p("Published ".$ml->em($c->title));
}

sub cancel {
    my $this = shift;
    my $c = $this->{content};
    $c->wf_cancel();
    return $ml->p("Published ".$ml->em($c->title));
}

sub approve {
    my $this = shift;
    my $c = $this->{content};
    $c->wf_approve();
    return $ml->p("Approved ".$ml->em($c->title));
}

1;
