#!/usr/bin/perl
#-----------------------------------------------------------------------
#
#   Copyright 2015 Exware Solutions, Inc.  http://www.exware.com
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
#
#   A cart is just a receivable that the current user is using to collect
#   their purchases. It has its own display and editing conventions, which
#   are different than the inherited Receivable class.
#
#----------------------------------------------------------------------------

package Modules::Finance::Cart;

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Module qw(&get_module);
use ExSite::Object;
use ExSite::ObjectList;
use Modules::Finance::Receivable;
use Modules::Finance::Surcharge;
use Modules::Finance::Account;

use vars qw(@ISA);
@ISA = qw(Modules::Finance::Receivable);

sub setup {
    my ($this,%opt) = @_;
    $this->{id} = $opt{id} || $session{invoice};
    $this->{type} = "receivable";
    my $acct;

    # this is a shopping cart API for 3rd party plugins; they may not have the
    # necessary frameworks loaded
    if (! $share{DB}{map}->is_mapped("account")) {
	# loads dbmaps, configs
	&get_module("Finance");
    }

    # setup claimed cart ID

    if ($this->{id}) {
	# validate
	if ($this->loaded) {
	    my $acct = $this->account();
	    my $account_section = $acct->getdata("section_id");
	    if ($config{Finance}{scope} eq "local" && 
		$account_section != $this->get_section_id) {
		$this->error("System configured for local payments but account's section does not match current site; clearing cart.");	
		$session{invoice} = 0;
		delete $this->{id};
		delete $this->{data};
	    }
	}
    }

    # if nothing setup, try recovering an abandoned cart

    if (! $this->ok && $config{Finance}{member_cart_expiry}) {
	my $uid = $share{DB}->my_uid;
	if ($uid) {
	    # user is logged in - see if they have an abandoned cart
	    $acct = new Modules::Finance::Account();
	    $acct->setup_my_account();
	    my @inv = $share{DB}->fetch_match("receivable",{account_id=>$acct->id});
	    if (@inv > 0) {
		if ($inv[-1]{status} eq "inactive") {
		    my $t = new ExSite::Time();
		    if (- $t->diff($inv[-1]{date},"sql_timestamp")/60 < $config{Finance}{member_cart_expiry}) {
			# inactive cart within the expired cart timeout
			$this->{data} = $inv[-1];
			$this->{id} = $inv[-1]{receivable_id};
		    }
		}
	    }
	}
    }

    # if still nothing setup, make a new cart
    ## FIXME: should we wait until something is actually added?

    if (! $this->ok) {
	if (! $acct) {
	    $acct = new Modules::Finance::Account();
	    $acct->setup_account();
	}
	my $date = new ExSite::Time;
	$this->setdata("type","receivable");
	$this->setdata("date",$date->write("sql_timestamp"));
	$this->setdata("account_id",$acct->id);
	$this->setdata("status","inactive");
	$this->setdata("invoice",$opt{invoice_number});
#	if ($share{DB}{map}->is_mapped("receivable","uid")) {
#	    # record the "seller"
#	    $this->setdata("uid",$session{receivable_uid}||$share{DB}->my_uid);
#	}
	$this->force_save();
    }
    $session{invoice} = $this->id;
}

sub name_old {
    my $this = shift;
    if ($this->getdata("status") eq "inactive") {
	return $msg{"Shopping Cart"}." #".$this->id;
    }
    else {
	return $this->SUPER::name();
    }
}

#=== DISPLAY

# show: display the shopping cart

sub show {
    my ($this,%opt) = @_;
    my $out = $this->run_handler("cart_view");
    return $out if (defined $out);
    if ($opt{show_as_invoice} || $this->getdata("status") ne "inactive") {
	# not really a shopping cart; display as an invoice
	return $this->SUPER::show(%opt);
    }

    # check for edits

    if (! $opt{noedit}) {
	my $post = ExSite::Input->new->post();
	if (scalar keys %$post) {
	    foreach my $key (keys %$post) {
		if ($key =~ /cartDelete|cartQuantity_/) {
		    $out .= $this->modify();
		    last;
		}
	    }
	}
    }

    # display the cart

    $out .= &insert_js("jquery");
    $out .= &insert_js("$config{server}{HTMLpath}/_Modules/Finance/cart.js");
    my $ml = &get_obj("ML");
    my $currency_char = $config{report}{currency_char};
    if ($this->defined()) {
	$this->clear_items();
	$out .= $this->validate_cart(0);
	my $cart_editable = $this->{admin} ? 1 : $this->is_editable;
	my $itemlist = $this->loaditems();
	if ($itemlist->count() > 0) {
	    my $edit = (!$this->{admin} && $config{Finance}{noneditable_cart}) ? 0 :
		$this->is_editable || 
		($this->getdata("status") eq "advisory");
	    $out .= $ml->h1($msg{$config{Finance}{heading}{cart}});
	    $out .= "<!--content(ShoppingCartHead)-->\n";
	    my $form;
	    my ($table,$total);
	    my $table .= 
		$ml->colgroup(undef,{align=>"right"}).
		$ml->colgroup().
		$ml->colgroup(undef,{span=>2,align=>"right"});
	    my $ch_del = $config{Finance}{message}{delete} || "Delete";
	    my $ch_quan = $config{Finance}{message}{quantity} || "Quantity";
	    my $ch_desc = $config{Finance}{message}{description} || "Description";
	    my $ch_per = $config{Finance}{message}{unitprice} || "Unit Price";
	    my $ch_sub = $config{Finance}{message}{subtotal} || "Subtotal";
	    my $thead = $ml->thead(
		$ml->tr(
		    $ml->th($msg{$ch_quan}).
		    $ml->th($msg{$ch_desc}).
		    $ml->th($msg{$ch_per}).
		    $ml->th($msg{$ch_sub}).
		    $ml->th($edit ? $msg{$ch_del} : "")
		)
		);
	    my $tbody;
	    my $show_descr = defined $config{Finance}{item_descriptions} ?
		$config{Finance}{item_descriptions} : 1;
	    while (my $item = $itemlist->next()) {
		next if (! $item->is_active);
		next if ($item->is_surcharge && $cart_editable);
		my $item_editable = $cart_editable && $item->getdata("status") ne "readonly";
		my $q = $item->quantity;
		$q =~ s/\.0+$//;
		my $descr = $ml->strong($item->showdata("item"));
		if ($show_descr && $item->getdata("description")) {	
		    $descr .= $ml->br.$item->showdata("description");
		}
		my $cost = $item->unitprice();
		if ($cost == 0.00) {
		    $cost = $config{Finance}{zero_cost};
		}
		else {
		    $cost = $currency_char.$cost;
		}
		my $subtotal = $item->subtotal();
		if ($subtotal == 0.00) {
		    $subtotal = $config{Finance}{zero_cost};
		}
		else {
		    $subtotal = $currency_char.$subtotal;
		}
		my $quantity;
		if ($item_editable) {
		    if ($item->is_surcharge() || $item->getdata("quantity") == 0) {
			# not a quantitative purchase
			$quantity = $ml->div("1",{class=>"number"});
		    }
		    else {
			# editable quantity
			$quantity = $ml->input(undef,{type=>"text",size=>4,name=>"cartQuantity_".$item->id(),value=>$q,class=>"CartQuantity"});
		    }
		}
		else {
		    # non-editable quanity
		    $quantity = $ml->div($q,{class=>"number"});
		}
		my $itemid = $item->id();
		my $delete = ($item_editable && ! $item->is_surcharge()) ? 
		    $ml->input(undef,{type=>"checkbox",name=>"cartDelete",value=>$item->id(),id=>"CartDelete_$itemid",class=>"CartDelete"}).$ml->span($msg{delete},{id=>"CartDeleteHelp_$itemid",class=>"CartDeleteHelp",style=>"display:none"}) : "";
		$tbody .= $ml->tr( [ $quantity, 
				     $descr, 
				     $ml->div($cost,{class=>"number"}), 
				     $ml->div($subtotal,{class=>"number"}),
				     $delete,
				   ] );
	    }
	    $tbody = $ml->tbody($tbody);
	    my $tlabel = $config{Finance}{label}{total} || "TOTAL DUE";
	    my $tfoot = $ml->tfoot(
		$ml->tr( [ undef, $msg{$tlabel}, undef, $ml->div('$'.$this->total(),{class=>"number total"}), undef ] )
		);
	    $form .= $ml->table( $table.$thead.$tfoot.$tbody, {class=>"Receivable",cellpadding=>5});
	    $form .= $this->cart_buttons();
	    my $formopt = {method=>"post"};
	    if (! $this->{uri}) {
		$this->{uri} = new ExSite::URI;
		$this->{uri}->service_page("Pay");
	    }
	    if ($this->{uri}) {
		$formopt->{action} = $this->{uri}->write();
	    }
	    $out .= $ml->form($form,$formopt);
	}
	else {
	    $out .= $ml->p($msg{$config{Finance}{message}{emptycart}});
	}
    }
    else {
	$out .= $ml->p($msg{$config{Finance}{message}{emptycart}});
    }
    if (! $this->defined() || ! $this->count_items()) {
	$out .= $this->cart_help("ShoppingCartHelpEmpty", "ShoppingCartHelp");
    }
    else {
	$out .= $this->cart_help("ShoppingCartHelp");
    }
    return $out;
}

sub show_readonly {
    my ($this,%opt) = @_;
    my $out;
    my $ml = &get_obj("ML");
    my $currency_char = $config{report}{currency_char};
    if ($this->defined()) {
	$this->clear_items();
	$out .= $this->validate_cart(0);
	my $itemlist = $this->loaditems();
	if ($itemlist->count() > 0) {
	    $out .= $ml->h1($msg{$config{Finance}{heading}{cart}});
	    $out .= "<!--content(ShoppingCartHead)-->\n";
	    my $form;
	    my ($table,$total);
	    my $table .= 
		$ml->colgroup(undef,{align=>"right"}).
		$ml->colgroup().
		$ml->colgroup(undef,{span=>2,align=>"right"});
	    my $ch_quan = $config{Finance}{message}{quantity} || "Quantity";
	    my $ch_desc = $config{Finance}{message}{description} || "Description";
	    my $ch_per = $config{Finance}{message}{unitprice} || "Unit Price";
	    my $ch_sub = $config{Finance}{message}{subtotal} || "Subtotal";
	    my $thead = $ml->thead(
		$ml->tr(
		    $ml->th($msg{$ch_quan}).
		    $ml->th($msg{$ch_desc}).
		    $ml->th($msg{$ch_per}).
		    $ml->th($msg{$ch_sub})
		)
		);
	    my $tbody;
	    my $show_descr = defined $config{Finance}{item_descriptions} ?
		$config{Finance}{item_descriptions} : 1;
	    while (my $item = $itemlist->next()) {
		next if (! $item->is_active);
		my $q = $item->quantity;
		$q =~ s/\.0+$//;
		my $descr = $ml->strong($item->showdata("item"));
		if ($show_descr && $item->getdata("description")) {	
		    $descr .= $ml->br.$item->showdata("description");
		}
		my $cost = $item->unitprice();
		if ($cost == 0.00) {
		    $cost = $config{Finance}{zero_cost};
		}
		else {
		    $cost = $currency_char.$cost;
		}
		my $subtotal = $item->subtotal();
		if ($subtotal == 0.00) {
		    $subtotal = $config{Finance}{zero_cost};
		}
		else {
		    $subtotal = $currency_char.$subtotal;
		}
		my $quantity;
		if ($item->is_surcharge() || $item->getdata("quantity") == 0) {
		    # not a quantitative purchase
		    $quantity = $ml->div("1",{class=>"number"});
		}
		else {
		    # non-editable quanity
		    $quantity = $ml->div($q,{class=>"number"});
		}
		$tbody .= $ml->tr( [ $quantity, 
				     $descr, 
				     $ml->div($cost,{class=>"number"}), 
				     $ml->div($subtotal,{class=>"number"})
				   ] );
	    }
	    $tbody = $ml->tbody($tbody);
	    my $tlabel = $config{Finance}{label}{total} || "TOTAL DUE";
	    my $tfoot = $ml->tfoot(
		$ml->tr( [ undef, $msg{$tlabel}, undef, $ml->div('$'.$this->total(),{class=>"number total"}) ] )
		);
	    $out .= $ml->table( $table.$thead.$tfoot.$tbody, {class=>"Receivable",cellpadding=>5});
	}
	else {
	    $out .= $ml->p($msg{$config{Finance}{message}{emptycart}});
	}
    }
    else {
	$out .= $ml->p($msg{$config{Finance}{message}{emptycart}});
    }
#    if (! $this->defined() || ! $this->count_items()) {
#	$out .= $this->cart_help("ShoppingCartHelpEmpty", "ShoppingCartHelp");
#    }
#    else {
#	$out .= $this->cart_help("ShoppingCartHelp");
#    }
    return $out;
}

sub cart_buttons {
    my $this = shift;
    my $stat = $this->run_handler("cart_buttons");
    return $stat if $stat;
    my $ml = &get_obj("ML");
    my $ui = &get_obj("UI");
    my $out;
    my $txt_update = $this->{config}{button}{update} || "Update cart";
    my $txt_clear = $this->{config}{button}{clear} || "Clear cart";
    my $txt_continue = $this->{config}{button}{'continue'} || "Continue shopping";    
    my $txt_checkout = $this->{config}{button}{checkout} || "Checkout";

    (tied %msg)->nohighlight();
    # regular form buttons
    my $edit = ! $this->{config}{noneditable_cart};
    my @buttons;
    if ($edit) {
	push @buttons, $ui->Button(type=>"submit",label=>$msg{"Update cart"},id=>"CartUpdateButton");
	if ($this->{config}{button}{include_clear}) {
	    push @buttons, $ui->Button(type=>"submit",name=>"submitaction",value=>$msg{$txt_clear},label=>$msg{$txt_clear},id=>"CartClearButton",tone=>"bad");
	}
    }
    if ($this->{config}{button}{include_continue}) {
	push @buttons, $ui->Button(type=>"submit",name=>"submitaction",value=>$msg{$txt_continue},label=>$msg{$txt_continue});
    }
    push @buttons, $ui->Button(type=>"submit",name=>"submitaction",value=>$msg{"Checkout"},label=>$msg{"Checkout"},id=>"CartCheckoutButton",tone=>"primary");
    $out .= $ml->p(join("&nbsp;",@buttons),{class=>"CartCheckoutButtons"});
    (tied %msg)->restore();
    return $out;
}

sub cart_buttons_old {
    my $this = shift;
    my $stat = $this->run_handler("cart_buttons");
    return $stat if $stat;
    my $ml = &get_obj("ML");
    my $out;
    my $txt_update = $this->{config}{button}{update} || "Update cart";
    my $txt_clear = $this->{config}{button}{clear} || "Clear cart";
    my $txt_continue = $this->{config}{button}{'continue'} || "Continue shopping";    
    my $txt_checkout = $this->{config}{button}{checkout} || "Checkout";

    (tied %msg)->nohighlight();
    # regular form buttons
    my $edit = ! $this->{config}{noneditable_cart};
    my @buttons;
    if ($edit) {
	push @buttons, $ml->input(undef,{type=>"submit",value=>$msg{"Update cart"},id=>"CartUpdateButton"});
	if ($this->{config}{button}{include_clear}) {
	    push @buttons, 
	    $ml->input(undef,{type=>"submit",name=>"submitaction",value=>$msg{$txt_clear},id=>"CartClearButton"});
	}
    }
    if ($this->{config}{button}{include_continue}) {
	push @buttons, 
	$ml->input(undef,{type=>"submit",name=>"submitaction",
			  value=>$msg{$txt_continue}});
    }
    push @buttons, $ml->input(undef,{type=>"submit",name=>"submitaction",value=>$msg{"Checkout"},id=>"CartCheckoutButton"});
    $out .= $ml->p(join("&nbsp;",@buttons),{class=>"CartCheckoutButtons"});
    (tied %msg)->restore();
    return $out;
}

sub cart_help {
    my ($this,@content) = @_;
    if ($share{Page}) {
	my $out;
	my $ml = &get_obj("ML");
	foreach my $c (@content) {
	    my $cobj = $share{Page}->find($c);
	    if ($cobj) {
		$out = $cobj->get_html();
		last if $out;
	    }
	}
	# add a return to shopping link
	my $back_url = 
	    $this->run_handler("Pay_continue_shopping") || # custom logic
	    $session{continue_shopping_url} ||             # plugin-specific override
	    $this->{config}{continue_shopping_url} ||      # look for fixed shopping url
	    $session{pay_redirect};                        # last added item
	if ($back_url =~ /^((https?:\/\/)?[\w\.\-]+)?\/\w+/) {
	    my $message = $this->{config}{message}{continue_shopping} || 
		"Continue shopping";
	    $out .= $ml->p($ml->a($msg{$message},{href=>$back_url,class=>"CartShoppingLink"}));
	}
	return $out;
    }
}

# add to cart

sub add {
    my ($this,%opt) = @_;
    my $stat = $this->run_handler("cart_add",%opt);
    return $stat if (defined $stat);
    my $ml = &get_obj("ML");
    my $out;

    # store redirect url for continue shopping button
    $session{pay_redirect} = $ENV{HTTP_REFERER};

    # create a new invoice if previous invoice is not editable
    if (! $this->is_editable) {
	delete $session{invoice};
	return $this->error("Shopping cart is not editable.");
    }
    elsif ($this->authorize()) {
	# remove surcharges when we add another item
	$this->remove_surcharges();
    }
    else {
	$this->error("Permission denied.");
	return $this->show_diagnostics("error","html");
    }

    # modify existing item if we already have one in the cart
    my $new_key = $this->unique_item_identifier(%opt);
    if ($this->defined()) {
	my $itemlist = $this->loaditems();
	my $item_key;
	$itemlist->reset;
	while (my $item = $itemlist->next()) {
	    next if (! $item->is_active);
	    $item_key = $this->unique_item_identifier(
		item => $item->getdata("item"),
		description => $item->getdata("description"),
		cost => $item->getdata("cost"),
		objtype => $item->getdata("objtype"),
		objid => $item->getdata("objid"),
		);
	    if ($new_key eq $item_key) {
		my $old_quantity = $item->getdata("quantity") || 1;
		my $new_quantity = $opt{quantity} || 1;
		$item->setdata("quantity",$old_quantity + $new_quantity);
### size is unit size, not total size
#		my $s = $item->getdata("size") + $opt{size};
#		$item->setdata("size",$s);
		if (! $item->force_save()) {
		    return $this->error($msg{"Failed to add item to cart."}).
			$item->show_diagnostics("error","html");
		}
#		$this->run_handler("Pay_PostAddHandler", $item, \%opt);
		return $ml->p(
		    &substitute(
			 $msg{"\"[[item]]\" was added to your cart."},
			 {item=>$opt{item}}
		    )
		    );
	    }
	}
    }

    # add new item to cart
    my %item = (
	item => &html_to_plaintext($opt{item}),
	cost => $opt{cost},
	description => &html_to_plaintext($opt{description}),
	note => $opt{note},
	quantity => $opt{quantity},
	size => $opt{size},
	acctcode_id => $opt{acctcode_id} || 0,
	acctcode2 => $opt{acctcode2},
	acctcode3 => $opt{acctcode3},
	parent => $opt{parent} || 0,
	surcharge_id => $opt{surcharge_id} || 0, ### ?
	uid => $opt{uid} || 0,
	objtype => $opt{objtype},
	objid => $opt{objid},
	country => $opt{country},
	provstate => $opt{provstate},
	);

    my $item = $this->add_item(%item);
    if (! $item->id) {
	$this->error($msg{"Failed to add item to cart."});
	return &ExSite::Config::show_diagnostics();
    }

    $this->run_handler("Cart_PostAddHandler", $item, \%opt);

    return $ml->p(
	&substitute(
	     $msg{"\"[[item]]\" was added to your cart."},
	     {item=>$opt{item}}
	),
	{class=>"CartAddMessage"}
	);
}

# add_item: direct add, no sanity checks

sub add_item {
    my ($this,%item) = @_;
    if ($this->loaded) {
	if ($this->authorize) {
	    $item{status} or $item{status} = "active";
	    defined $item{uid} or $item{uid} = $this->DB->my_uid || 0;
	    $item{receivable_id} = $this->id;
	    delete $item{receivable_item_id};
	    my $item = new Modules::Finance::ReceivableItem(data=>\%item);
	    my $item_id = $item->insert();
	    if ($item_id) {
		my $obj = $item->purchased_object();
		if ($obj->can("sale_select")) {
		    $obj->sale_select($item);
		}
		$this->clear_items();
		$this->set_cart_cookie();
	    }
	    else {
		$item->error("Failed to add item to cart.");
	    }
	    return $item;
	}
	else {
	    $this->error("Cart::add_item: permission denied");
	}
    }
    return undef;
}

sub unique_item_identifier {
    my ($this,%opt) = @_;
    my %key = ( 
	item => $opt{item},
	description => $opt{description},
	cost => sprintf("%.02f",$opt{cost}),
	objtype => $opt{objtype},
	objid => $opt{objid},
	);
    return &hash2text(%key);
}

# modify cart contents

sub modify {
    my ($this,%opt) = @_;
    my $stat = $this->run_handler("cart_modify",%opt);
    return $stat if (defined $stat);
    my $out;
    my %not_in_cart;

    if (! $this->authorize) {
	$this->error("Permission denied.");
	return $this->show_diagnostics("error","html");
    }

    my $input = new ExSite::Input();
    my $post = $input->post();

    $this->remove_surcharges();

    if ($this->is_editable) {
	# update quantities
	foreach my $edititem (keys %$post) {
	    if ($edititem =~ /^cartQuantity_(\d+)$/) {
		my $item_id = $1;
		my $item = new Modules::Finance::ReceivableItem(id=>$item_id);
		if ($item->getdata("receivable_id") eq $this->id()) {
		    my $q = $post->{$edititem};
		    my $old_q = $item->getdata("quantity");

		    # validate quantity
		    ### allow for fractional quantities

		    if ($q =~ /^\d+(\.\d+)?$/) {
			my $obj = $item->purchased_object();
			if ($q == 0) {
			    # this is equivalent to deletion
			    $out .= $this->delete_item($item,$obj);
			}
			elsif ($old_q != $q) {
			    if ($obj->can("sale_quantity")) {
				$obj->sale_quantity($item,$old_q,$q); # from, to
			    }
			    $item->setdata("quantity",$q);
			    $item->force_save();
			}
		    }
		    else {
			$not_in_cart{$item_id} = 1;
			$out .= $this->error(
			    &substitute(
				 $msg{"Item mismatch: item [[item]] is not in your cart."},
				 {item=>$item_id}
			    )
			    );
		    }
		}
	    }
	}

	# delete items
	if ($post->{cartDelete}) {
	    my @del = split /; /,$post->{cartDelete};
	    foreach my $del (@del) {
		if ($del =~ /^\d+$/) {
		    my $item = new Modules::Finance::ReceivableItem(id=>$del);
		    if ($item->getdata("receivable_id") eq $this->id) {
			$out .= $this->delete_item($item);
		    }
		    else {
			$out .= $this->error(
			    &substitute(
				 $msg{"Item mismatch: item [[item]] is not in your cart."},
				 {item=>$del}
			    )
			    ) if (!$not_in_cart{$del});
		    }
		}
	    }
	    delete $post->{delete};
	}
	$this->remove_surcharges();
	$this->clear_items();
	$this->set_cart_cookie();
    }
    else {
	delete $session{invoice};
	$out .= $this->error($msg{"This invoice cannot be modified."});
    }

    return $out;
}

sub delete_item {
    my ($this,$item,$obj) = @_;
    my $out .= $this->run_handler("cart_delete_item", $item);
    $obj or $obj = $item->purchased_object();
    if ($obj->can("sale_delete")) {
	$obj->sale_delete($item);
    }
    $item->delete();
    return $out;
}

sub clear {
    my $this = shift;
    my $stat = $this->run_handler("cart_clear");
    return $stat if (defined $stat);
    my $out;
    if ($this->authorize()) {
	# loop over items
	my $itemlist = $this->loaditems();
	while (my $item = $itemlist->next()) {
	    $out .= $this->delete_item($item);
	}
	$this->set_cart_cookie();
    }
    else {
	$out .= $this->error($msg{"Cannot clear an active invoice."});
    }
    return $out;
}

# set_cart_cookie : track how many items in cart

sub set_cart_cookie {
    my ($this,$quantity) = @_;
    my $count = $quantity || $this->count_items(0); # all non-surcharge items
    if ($cookie{cart_contents} != $count) {
	$cookie{cart_contents} = $count;
    }
}

# authorize : does the user have permission to modify the cart?

sub authorize {
    my ($this) = @_;
    if ($this->loaded) {
	my $acct = $this->account;
	if ($acct && $acct->id) {
	    my $asid = $acct->getdata("section_id");
	    if ($asid) {
		my $site = $share{DB}->this_site;
		if ($site && $asid != $site->{content_id}) {
		    $this->error("This account belongs to a different website.");
		    return 0;
		}
	    }
	    if ($acct->allow()) {
		# user can work on this account
		return $this->is_editable;
	    }
	}
    }
    $this->error("Non-existent account.");
    return undef;
}

sub delete {
    my $this = shift;
    # we don't delete the data, just kill the cart
    delete $session{invoice};
    return 1;
}

sub validate_cart {
    my ($this,$final) = @_;
    # $final is true when checking out, false when simply displaying the cart.
    # This allows you to display warnings on normal cart views, but then take
    # action (modify/delete) when checking out if the user does not clean it up
    # themselves.
    my $ml = &get_obj("ML");

    # custom validation checks
    my $out = $this->run_handler("validate_cart",$final);

    # validate item relationships
    my @del;
    my $items = $this->loaditems();
    my %item = $items->hash("receivable_item_id");
    while (my $item = $items->next) {
	my $parent = $item->getdata("parent_id");
	if ($parent && ! exists $item{parent}) {
	    $out .= $this->error("Removing ".$item->name," from your cart; it is part of another purchase that is missing.");
	    $item->delete();
	}
    }
    if ($out) {
	$this->set_cart_cookie();
	return $ml->div($out,{class=>"CartValidateMessage"});
    }
    return $out;
}

1;

