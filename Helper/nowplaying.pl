#!/usr/bin/perl
# Lädt NowPlayingHelper.dylib in den (von Apple berechtigten) perl-Prozess.
# Aufruf: perl nowplaying.pl <dylib> stream|send
use strict;
use DynaLoader;
my ($lib, $mode) = @ARGV;
my $handle = DynaLoader::dl_load_file($lib, 0) or die "load failed\n";
my $sym = DynaLoader::dl_find_symbol($handle, $mode eq 'send' ? 'nodge_send' : 'nodge_stream') or die "symbol\n";
DynaLoader::dl_install_xsub('main::run', $sym);
run();
