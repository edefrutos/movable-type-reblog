
use strict;
use warnings;

use lib 't/lib', 'lib', 'extlib';

use MT;
use MT::Test qw( :db );

use Test::More tests => 9;

ok (MT->model ('ReblogSourcefeed'), "Model for ReblogSourceFeed");

my $rsf = MT->model ('ReblogSourcefeed')->new;
ok ($rsf, "ReblogSourcefeed created");

$rsf->blog_id(1);
$rsf->url('http://narnia.na/atom.xml');
$rsf->label('Narnia Feed');
$rsf->is_active(1);
$rsf->is_excerpted(1);
$rsf->save;

is ($rsf->blog_id, 1, "SourceFeed blog ID");
is ($rsf->url, 'http://narnia.na/atom.xml', "SourceFeed URL");
ok (! $rsf->consecutive_failures, "SourceFeed has no failures");
is ($rsf->label, 'Narnia Feed', "SourceFeed Label");
is ($rsf->has_error, 0, "SourceFeed has no errors");
is ($rsf->is_active, 1, "SourceFeed is active");
is ($rsf->is_excerpted, 1, "SourceFeed is excerpted");
