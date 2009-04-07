use strict;
use warnings;

use lib 't/lib', 'lib', 'extlib';

use MT;
use MT::Test qw( :cms :db ::data );

use Test::More tests => 11;
use Test::Exception;


my $feedurls = [ 
	'http://googleblog.blogspot.com/feeds/posts/default',
	'http://rss.cnn.com/rss/cnn_topstories.rss',
	'http://rss.msnbc.msn.com/id/3032091/device/rss/rss.xml',
	'http://bad.feed/url',
	'https://bad.feed/url'
	
];

ok (MT->model ('ReblogSourcefeed'), "Model for ReblogSourceFeed");
ok (MT->model ('ReblogData'), "Model for ReblogData");

my $blog = MT::Blog->load(1);

require_ok( 'Reblog::Util' );
require_ok( 'Reblog::CMS' );

my $lastfeedurl;
for my $feedurl (@$feedurls) {
    my $feed = MT->model('ReblogSourcefeed')->new();
    $feed->is_active(1);
    $feed->blog_id( $blog->id );
    $feed->url($feedurl);
    $feed->save();
	my $rsf = MT->model('ReblogSourcefeed')->load({ url => $feedurl});
	ok($rsf, "Added source feed: " . $feedurl);
}

my $somefeed = MT->model('ReblogSourcefeed')->load(2);
is($somefeed->label, 'rss.cnn.com', 'Labels are set automatically unless specified (domain name for http:// url)');
$somefeed = MT->model('ReblogSourcefeed')->load(5);
is($somefeed->label, 'bad.feed', 'Labels are set automatically unless specified (domain name for https:// url)');
