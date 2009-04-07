
use strict;
use warnings;

use lib 't/lib', 'lib', 'extlib';

use MT;
use MT::Test qw( :db );

use Test::More tests => 18;

ok (MT->model ('ReblogData'), "Model for ReblogData");

my $rd = MT->model ('ReblogData')->new;
ok ($rd, "ReblogData created");

$rd->entry_id(1);
$rd->link('http://narnia.na/reblog_link');
$rd->guid('guid:unique_id,1');
$rd->source_author('mkania');
$rd->via_link('http://narnia.na/via_link');
$rd->orig_created_on('2008-12-04 15:30:00');
$rd->source('Narnia Blog');
$rd->source_url('http://narnia.na');
$rd->source_feed_url('http://narnia.na/source.xml');
$rd->source_title('Narnia Blog');
$rd->thumbnail_url('http://narnia.na/thumbnail.jpg');
$rd->thumbnail_link('http://narnia.na/thumbnail_link');
$rd->enclosure_url('http://narnia.na/full.jpg');
$rd->enclosure_length(10000);
$rd->enclosure_type('image/jpeg');
$rd->annotation('annotation');
$rd->save;

is($rd->entry_id, 1, "Entry ID");
is($rd->link, 'http://narnia.na/reblog_link', "Reblog Link");
is($rd->guid, 'guid:unique_id,1', "Reblog GUID");
is($rd->source_author, 'mkania', "Reblog Source Author");
is($rd->via_link, 'http://narnia.na/via_link', "Reblog Via Link");
is($rd->orig_created_on, '2008-12-04 15:30:00', "Reblog Original Created On");
is($rd->source, 'Narnia Blog', "Reblog Source");
is($rd->source_url, 'http://narnia.na', "Reblog Source URL");
is($rd->source_feed_url, 'http://narnia.na/source.xml', "Reblog Source Feed URL");
is($rd->source_title, 'Narnia Blog', "Reblog Source Title");
is($rd->thumbnail_url, 'http://narnia.na/thumbnail.jpg', "Reblog Thumbnail URL");
is($rd->thumbnail_link, 'http://narnia.na/thumbnail_link', "Reblog Thumbnail Link");
is($rd->enclosure_url, 'http://narnia.na/full.jpg', "Reblog Enclosure URL");
is($rd->enclosure_length, 10000, "Reblog Enclosure Length");
is($rd->enclosure_type, 'image/jpeg', "Reblog Enclosure Type");
is($rd->annotation, 'annotation', "Reblog Annotation");