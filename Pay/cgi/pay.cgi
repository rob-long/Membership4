#!/usr/bin/perl
use strict;
use ExSite::Config;
use ExSite::ML;
use ExSite::URI;
use ExSite::Input;
use ExSite::Crypt;
&exsite_init;

my $input = new ExSite::Input;
my $q = $input->query();

my $uri = new ExSite::URI;
$uri->plaintext;
$uri->setup($q->{reply});

my $ml = new ExSite::ML;

$ml->_h1("Test Purchase");
$ml->_p("Amount: \$$q->{amount}");

my $c = new ExSite::Crypt;
my ($amt,$id,$time) = split /;/, $c->decrypt($q->{key});

if ($amt == $q->{amount} && $id eq $q->{purchase_id} && time - $time < 600) {
    $uri->parameter("key",$q->{key});
    $uri->parameter("transaction_status",1);
    my $approve_url = $uri->write_full();
    $uri->parameter("transaction_status",0);
    my $decline_url = $uri->write_full();
    $uri->parameter("transaction_status",0);
    $uri->parameter("canceled",1);
    my $cancel_url = $uri->write_full();
    $ml->_p($ml->a("Click here to approve this transaction",{href=>$approve_url}));
    $ml->_p($ml->a("Click here to decline this transaction",{href=>$decline_url}));
    $ml->_p($ml->a("Click here to cancel payment and return to shopping",{href=>$cancel_url}));
}
else {
    $ml->_p("Invalid transaction parameters!");
    $uri->parameter("transaction_status",0);
    $uri->parameter("canceled",1);
    my $cancel_url = $uri->write_full();
    $ml->_p($ml->a("Click here to cancel this transaction",{href=>$cancel_url}));
}

$ml->__body();
$ml->Prepend($ml->head($ml->title("Payment")));
$ml->__html();

$ml->PrintWithHeader();
