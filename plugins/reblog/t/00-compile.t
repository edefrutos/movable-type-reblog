
use strict;
use warnings;

use lib 't/lib', 'lib', 'extlib';
use Test::More tests => 1;
use MT::Test qw( :db );
use MT;

ok (MT->component ('reblog'), "Plugin loaded fine");