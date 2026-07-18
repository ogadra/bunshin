#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use BunshinServer;

BunshinServer::run(
    handler_path => "$FindBin::Bin/handler.pm",
    listen_addr  => '0.0.0.0',
    listen_port  => 5000,
);
