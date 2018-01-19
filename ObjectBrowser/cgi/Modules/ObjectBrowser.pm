package Modules::ObjectBrowser;
#-----------------------------------------------------------------------
#   Copyright 2001-2009 Exware Solutions, Inc.  http://www.exware.com
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
use ExSite::Util;
use ExSite::Object;
use ExSite::ObjectList;
use Modules::BaseDCD;
use vars qw(@ISA $ml $ui $OB $maxrec);
@ISA = qw(Modules::BaseDCD);

# ObjectBrowser has no public-face functions

sub write {
    my ($this,$opt) = @_;
    return "";
}

sub read {
    my ($this,$opt) = @_;
    # fetch overlayed query and form input
    my $in = new ExSite::Input;
    $this->{input} = $in->combine;
    $this->{post} = $in->post;
    $this->{is_post} = scalar keys %{$this->{post}};
    # preload entire DBmap 
    # (Dependency preloading hasn't happened yet, so we can't load our path)
    $share{DB}{map}->load_submaps();
    # evaluate path
    my @path = $in->path();
    if ($share{DB}->{map}->is_mapped($path[0])) {
	$this->{input}{type} = $path[0];
	if ($path[1]) {
	    $this->{input}{id} = $path[1];
	    $in->path("Object",$path[0],$path[1]);
	}
	else {
	    $in->path("Object",$path[0]);
	}
    }
}

sub ioctl {
    my $this = shift;
    $_ = shift;   # $_ is the ioctl request
    if (/ModuleName/) {
	return "Object Browser";
    }
    elsif (/ModuleInfo/) {
	return "This is an object-oriented database browser.";
    }
    elsif (/ControlPanel/) {
	return \&ctrl_panel;
    }
    elsif (/Category/) {
	return "Database";
    }
    elsif (/Access/) {
	return 3;
    }
    elsif (/Dependencies/) {
	return "*";
    }
    return undef;
}

sub ctrl_panel {
    my $this = shift;

    my $type = $this->{input}{type};
    my $id = $this->{input}{id};

    my $obj = $this->make_obj($type,$id);
    if (! $obj) {
	return "Invalid object: $@";
    }
    $ml = &get_obj("ML");
    $ui = &get_obj("UI");
    my $url = new ExSite::URI;
    $share{DB}->handler("show_data",\&OB_show_data);
    $share{DB}->handler("input_exsite",\&OB_input_fkey);
    $OB = $this;

    # NB: this is a global visible to ExSite::Form in the handler at end
    $maxrec = $config{ObjectBrowser}{max_records} || 100;

    my $out;
    if ($this->{input}{type}) {
	my @path = (
	    $ml->a("Top",{href=>"$config{server}{CGIpath}/ex.cgi/admin/ObjectBrowser"}),
	    $ml->a($share{DB}->title($this->{input}{type}),{href=>"$config{server}{CGIpath}/ex.cgi/admin/ObjectBrowser/$this->{input}{type}"})
	    );
	if ($this->{input}{id}) {
	    push @path, $ml->a($share{DB}->title($this->{input}{type},$this->{input}{id}),{href=>"$config{server}{CGIpath}/ex.cgi/admin/ObjectBrowser/$this->{input}{type}/$this->{input}{id}"});
	}
	$out .= $ui->PathBar(links=>\@path);
    }
    
    $_ = $this->{input}{ob};
    if (/new/) {
	my $title = $share{DB}{map}->get_table_attr($type,"title");
	$out .= $ml->h1("New $title");
	my $data = {};
	my $ref = $ENV{HTTP_REFERER};
	$ref =~ /ObjectBrowser(\/(\w+)(\/(\d+))?)?/;
	my $reftype = $2;
	my $refid = $4;
	if ($reftype && $refid) {
	    my $refcol = $share{DB}{map}->get_reference_column($type,$reftype);
	    if ($refcol) {
		$data->{$refcol} = $refid;
	    }
	}
	$out .= $obj->make(data=>$data,extra=>{reply=>$ref});
    }
    elsif (/edit/) {
	$out .= $obj->edit(extra=>{reply=>$this->link()});
    }
    elsif (/delete/) {
	my $name = $obj->name;
	if ($obj->delete) {
	    my $link = $this->link(__path=>{"Object"=>[$type]},ob=>undef);
	    &redirect($link);
	}
    }
    elsif (/searchf/) {
	$out .= $this->select_fkey($obj);
    }
    elsif (/search/) {
	$out .= $this->search($obj);
    }
    else { #if (/show/) {
	if ($id) {
	    # do edit first, in case it changes the view
	    my $objedit = $this->edit_object($obj);
	    my $objview = $this->view_object($obj) || $this->warn("No view of this object.");
	    my $objreport = $this->view_data($obj) . 
		$ml->p($this->list_children($obj));
	    $out .= $ml->h1($obj->name);
	    $out .= $ui->DynTabBox(
		tabs=>["View","Data","Edit"],
		panes=>[$objview,$objreport,$objedit],
		width=>"100%"
		);
	}
	elsif ($type) {
	    $out .= $this->list($type);
	}
	else {
	    $out .= $this->browse();
	}
    }
# control panels do this automatically if debug is on
#    $out .= $obj->show_diagnostics("error","html");
#    $out .= $this->show_diagnostics("error","html");
    return $out;
}

sub make_obj {
    my ($this,$type,$id) = @_;
    my $obj;
    my $class = $share{DB}->{map}->get_table_attr($type,"class");
    if ($class) {
	# object has a specialized class
	if (eval "require $class") {
	    $obj = eval "new $class";
	    if ($obj) {
		if ($class eq "ExSite::Content") {
		    $obj = $obj->get_content_obj($id);
		}
		else {
		    $obj->setup(id=>$id); 
		}
	    }
	    else {
		$this->error("$class: $@");
	    }
	}
	else {
	    $this->error("$class: $@");
	}
    }
    if (! $obj) {
	# setup as a generic object
	if (eval "require ExSite::Object") {
	    $obj = eval "new ExSite::Object";
	    if ($obj) {
		$obj->setup(type=>$type,id=>$id); 
	    }
	    else {
		$this->error("Cannot make object: $@");
	    }
	}
    }
    return $obj;
}

sub view_object {
    my ($this,$obj) = @_;
    return $obj->show();
}

sub view_data {
    my ($this,$obj) = @_;
    my $out;
    my $type = $obj->type;
    my $id = $obj->id;
    my $foot;
    if ($share{DB}->approve("delete",$type,$id)) {
	my $delurl = $this->link(ob=>"delete");
	my $name = $obj->name;
	if (length $name > 25) {
	    $name = substr($name,0,25)."...";
	}
	my $jsname = $name;
	$jsname =~ s/\"/&quot;/g;
	$foot = $ui->FATool("delete",label=>"delete $name",url=>$delurl,confirm=>"Move $jsname and its associated data to the trash bin?",tone=>"bad");
    }
    $out .= $obj->report(tools=>$foot);
    return $out;
}

sub edit_object {
    my ($this,$obj) = @_;
    return $this->{is_post} ?
	$obj->do_edit(extra=>{reply=>$this->link()}) :
	$obj->edit(extra=>{reply=>$this->link()});
}

sub browse {
    my $this = shift;
    my $title;
    my $db = $share{DB};
    my $map = $db->{map};
    my @table = $map->get_mapped_tables;
    my %report = ( 
		   title=>"Database Index - All Tables",
		   headers=>[], 
		   data=>[] 
		   );
    
    if ($config{report}->{link_position} eq "before") {
	push @{$report{headers}}, "Operations";
    }
    push @{$report{headers}},( "Table", "Record Count" );
    if ($config{report}->{link_position} ne "before") {
	push @{$report{headers}}, "Operations";
    }
    foreach my $tab (sort @table) {
	my @data;
	my $table_par = $map->get_table($tab);
	$title = $map->table_title($tab,1);
	my $name = $table_par->{alias};
	my $tablename = $name ne $tab ? "$tab [$name]" : $tab;

	my $op = 
	    $ui->FATool("list",label=>"list",url=>$this->link(__path=>{Object=>[$tab]},ob=>undef)).
	    $ui->FATool("search",label=>"search",url=>$this->link(__path=>{Object=>[$tab]},ob=>"search"));

	push @data, $ml->strong($tablename).": ".$title;
	push @data, $db->count($tab);
	push @data, $op;
	push @{$report{data}}, \@data;
    }
    my $r = new ExSite::ReportBuilder(%report);
    return $r->make;
}

sub list {
    my ($this,$type,$data) = @_;
    my $pkey = $share{DB}{map}->get_table_attr($type,"key");
    my $total = ref $data eq "ARRAY" ?
	scalar @$data :
	$share{DB}->count($type);
    my @data = ref $data eq "ARRAY" ?
	@$data : 
	reverse $share{DB}->fetch_all($type,{$pkey=>"desc"},$maxrec);
    my $count = scalar @data;
    my $list = new ExSite::ObjectList(type=>$type,list=>\@data);
    my $foot;
#    if ($count == $total) {
#	$foot = "Showing all $count records.";
#    }
#    else {
#	$foot = "Showing newest $count of $total records. ";
#	$foot .= $ml->a(
#			$ml->img(undef,{src=>"$config{server}{HTMLpath}/_Modules/ObjectBrowser/zoom.png",height=>16,width=>16,border=>0,alt=>"search",title=>"search"})." Search for more.",
#			{href=>$this->link(__path=>{Object=>[$type]},ob=>"search")}
#			);
#    }
#    my $out = $list->show(foot=>$foot);
    my $out = $list->show();
    return $out;
}

sub list_children {
    my ($this,$obj) = @_;
    my $out;
    my %child = $obj->get_children();
    foreach my $ch (sort keys %child) {
	my $list = $child{$ch};
	$list->reset;
	$out .= $list->show();
    }
    return $out;
}

#------ Search

# search : query to find objects that match a pattern

sub search {
    my $this = shift;
    my $obj = shift;
    my $table = $obj->type();
    my $input = new ExSite::Input;
    my $in = $input->post;
    my @data;
    my $db = $share{DB};
    my $title = $db->{map}->get_table_title($table,1);
    my $out;

    my $have_searchterms = (scalar keys %$in > 0);
    if ($have_searchterms) {
	@data = $this->get_search_results();
	if (@data > 0) {
	    $out .= $ml->h1("Search Results");
	    $out .= $this->list($table,\@data);
	    
	}
	else {
	    $out .= $this->warn("Nothing related was found.");
	}
    }
    
    $out .= $ml->h1("Search for $title");
    $out .= $ml->p("Enter values to match to in the following fields:");
    my $url = $this->link(ob=>"search");
    $db->set("action","search");
    $out .= $ml->form(
		      $db->input_record({table=>$table,data=>$this->{searchterms}}).
		      $ml->input(undef,{type=>"submit", name=>"submit_action", value=>"Search"}),
		      { name=>"select_fkey", method=>"post" }
		      );

    return $out;
}

sub get_search_results {
    my $this = shift;
    my $db = $share{DB};
    my @data;
    $db->get_data();
    $this->{searchterms} = {};
    foreach my $tab (keys %{$db->{form}}) {
	foreach my $record (values %{$db->{form}{$tab}}) {
	    foreach my $col (keys %$record) {
		# delete null-valued keys; add wildcards to the remainder
		if ($record->{$col}) {
		    $this->{searchterms}{$col} = $record->{$col};
		    my $datatype = $db->{map}->get_column_attr($tab,$col,"datatype");
		    # escape literals
		    $record->{$col} =~ s/%/\\%/g;
		    $record->{$col} =~ s/_/\\_/g;
		    if ($datatype !~ /^(key|list)/) {
			$record->{$col} ="%".$record->{$col}."%";
		    }
		}
		else {
		    delete $record->{$col};
		}
	    }
	    push @data, $db->fetch_match($tab,$record);
	}
    }
    return wantarray ? @data : \@data;
}

#====== handlers

# OB_show_data : show foreign keys as links, clip raw file data

sub OB_show_data {
    my ($this,$table,$column,$data,$id,$datatype) = @_;
    ### $this is a Report object
    $datatype or $datatype = $this->{map}->get($table,$column,"datatype");
    
    my $sc = $config{form}{sepchar};

    # get datatype
    if ($datatype =~ /^key[:=]/) {
        # foreign key
	if ($data > 0) {
	    # dereference foreign keys
	    my (undef,$ftable) = split /[:=]/,$datatype;
	    # look up foreign row
	    my %fdata = $this->fetch($ftable,$data);
	    my $fkey = $this->get_key($ftable);
	    return $ui->FATool("link",label=>"goto $ftable $data",url=>$OB->link(__path=>{ Object => [ $ftable, $data ] }, ob=>undef)).
		$this->record_label($ftable,$fdata{$fkey},\%fdata);
	}
	else {
	    return "n/a";
	}
    }
    elsif ($table eq "revision" && $column eq "data" &&
	$data =~ /^[\w\.-]+$sc[A-Za-z0-9\/\+]+=*$/) {
	# data is an encoded file
	my ($file,$fdata) = split /$sc/, $data;
	my $mimetype = &MimeType($file);
	# estimate the size
	# (multiply by 6/8 to account for Mime base64 encoding overhead)
	my $size = int(length($fdata)*6/8/100)/10;
	return "$file ($mimetype, $size K)";
    }

    return undef;
}

# OB_input_fkey : special foreign key selector if more than 100 records

sub OB_input_fkey {
    my ($this,%opt) = @_;
    return undef if ($this->{in_handler});
    $this->{in_handler} = 1;
    my $out;
    $this->{selector_id} = 0 if (! exists $this->{selector_id});
    if ($opt{datatype} =~ /^key[:=]/) {
	my (undef,$ftable) = split /[:=]/, $opt{datatype};

	# see if there is a function to trim the data down to size
	my $rdata = $this->run_handler("select_foreign_key",$opt{table},$opt{record},$opt{column},$ftable);
	return undef if ($rdata && scalar @$rdata < $maxrec);

	# switch to search selector if number of options is large
	if ($share{DB}->count($ftable) > $maxrec) {
	    $this->{selector_id}++;
	    my (%data,%pdata);
	    my $obj = $OB->make_obj($ftable,$opt{value});
	    my $name = $obj->name || $ml->em($msg{"undefined"});
	    my $url = $OB->link(ob=>"searchf",fkid=>$this->{selector_id},_bare=>1,__path=>{Object=>[$ftable]});
	    my $choose_url = "javascript:popup_medium('$url')";
	    my $button = $ui->Button(label=>"<span id='FkeySelect_$this->{selector_id}'>$name</span>",url=>$choose_url);
	    $out = "$button ".
		$ml->input(undef,{type=>'text',name=>$opt{name},size=>8,value=>$opt{value},id=>"FkeySelect_ID_$this->{selector_id}"});
	    my $clear_url = "javascript:clear_fkey_selector($this->{selector_id})";
	    my $clear_button = $ui->Button(label=>"Clear",url=>$clear_url);
	    $out .= $clear_button;
	    if (! $this->{selector_js}) {
		$out .= $ml->script("
function clear_fkey_selector(id) {
    var e_in = document.getElementById('FkeySelect_ID_'+id);
    e_in.value = '';
    var b_label = document.getElementById('FkeySelect_'+id);
    b_label.innerHTML = '<em>$msg{undefined}</em>';
}
");
		$this->{selector_js} = 1;
	    }
	}
    }
    $this->{in_handler} = 0;
    return $out;
}

# select_fkey : foreign key selector form

sub select_fkey {
    my $this = shift;
    my $obj = shift;
    my $table = $obj->type();
    my $input = new ExSite::Input;
    my $in = $input->post;
    my $q = $input->query;
    my $fkid = $q->{fkid};
    my @data;
    my $db = $share{DB};
    my $title = $db->{map}->get_table_title($table,1);
    my $searchterms;

    my ($results,$searchform);

    my $have_searchterms = (scalar keys %$in > 0);
    if ($have_searchterms) {
	@data = $this->get_search_results();
	if (@data > 0) {
	    my $count = scalar @data;
	    $results .= $ml->p("Found $count $title:");
	    my $options;
	    foreach my $d (@data) {
		my $key = $db->{map}->get_table_attr($table,"key");
		my $label = $db->record_label($table,$d->{$key},$d);
		my $id = $d->{$key};
		$options .= $ml->option("$label [$id]",{value=>"$id:$label"});
	    }
	    $results .= $ml->select($options,{size=>10,name=>"objectselected"});
	    $results .= 
		$ml->br.
		$ml->input(undef,{type=>"button",value=>"select",onclick=>"choosefkey()"});
	}
	else {
	    $results .= $this->warn("Nothing related was found.");
	}
	$results .= $ml->p("Can't find the record you want?  Resume searching by clicking on Search, below.");
    }
    else {
	$results .= $ml->input(undef,{type=>"hidden",name=>"objectselected",value=>''});
    }
    
    my $form .= $ml->p("Search for $title by entering values to match to in the following fields:");
    
    my $url = $this->link(ob=>"searchf");
    $db->set("action","search");
    $form .= $db->input_record({table=>$table,data=>$this->{searchterms}});
    $form .= $ml->input(undef,{type=>"submit", name=>"submit_action", value=>"find", onclick=>"findfkey()"});

    my $out .= $ml->p($ml->strong("Record Finder"));
    $out .= $ml->form(
	$ui->AccordionBox(
	    titles=>["Results","Search"],
	    panes=>[$results,$form],
	    states=>[$have_searchterms, ! $have_searchterms],
	    width=>"100%",
	),
	{ name=>"select_fkey", method=>"post" }
	);
    $out .= $ml->script("
function findfkey() {
    var f = document.select_fkey;
    // ignore the selected value
    f.objectselected.value = '';
    //f.submit();
    return true;
}
function choosefkey() {
    var f = document.select_fkey;
    if (! f.objectselected.value) {
        alert('Nothing selected!');
    }
    else {
        var ourl = parent.document.URL;
        var o2 = document.select_fkey.objectselected.value.split(':');
        var o_in = window.opener.document.getElementById('FkeySelect_ID_'+'$fkid');
	o_in.value = o2[0];
        var o_name = window.opener.document.getElementById('FkeySelect_'+'$fkid');
        o_name.innerHTML = o2[1];
        window.close();
        //f.submit();
    }
    return true;
}
");

}

1;
