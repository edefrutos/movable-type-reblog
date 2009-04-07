use strict;
use warnings;

use lib 't/lib', 'lib', 'extlib';

use MT;
use MT::App::CMS;
use MT::Template;
use MT::Template::Context;
use MT::Test qw( :cms :db ::data );

use Test::More tests => 22;
use Test::Exception;
use Cwd;
use File::Spec;

# Attempt to find our local files
my $path = File::Spec->catfile(Cwd::cwd(), $0);
my ($volume,$directories,$file) = File::Spec->splitpath( $path, 1 );
my @directories = File::Spec->splitdir( $directories );
if ( $directories[ scalar @directories - 1 ] =~ /\.t$/ ) {
	pop @directories;
}
my $feed_base = "file://";
foreach my $dir ( @directories ) {
	$feed_base .= $dir . "/";
}
my $null_feed;
my ( $good_atom, $good_rss091, $good_rss10, $good_rss20, $live_feed ) = ( $feed_base . 'sample_good.atom', $feed_base . 'sample_good-0.91.rss', $feed_base . 'sample_good-1.0.rss', $feed_base . 'sample_good-2.0.rss', 'http://googleblog.blogspot.com/feeds/posts/default' );
	my ( $bad_feed, $non_feed, $bad_url, $invalid_xml_feed ) = ( $feed_base . 'sample_bad.rss',  $feed_base . 'sample.html', 'http://bad.feed/url', $feed_base . 'sample_invalid.atom' );

my $blog = MT::Blog->load(1);
my $app = MT::App::CMS->instance;
require_ok('Reblog::Util');


is(Reblog::Util::validate_feed($app, $null_feed), 0, 'Null feed fails validation');
is($app->errstr, 'No sourcefeed selected for validation', 'Null feed reports error');
$app->{_errstr} = ''; # Reset error
is(Reblog::Util::validate_feed($app, $good_atom), 1, 'Good Atom feed validates');
is($app->errstr, '', 'Good feed reports no errors');
is(Reblog::Util::validate_feed($app, $good_rss091), 1, 'Good RSS 0.91 feed validates');
is($app->errstr, '', 'Good feed reports no errors');
is(Reblog::Util::validate_feed($app, $good_rss10), 1, 'Good RSS 1.0 feed validates');
is($app->errstr, '', 'Good feed reports no errors');
is(Reblog::Util::validate_feed($app, $good_rss20), 1, 'Good RSS 2.0 feed validates');
is($app->errstr, '', 'Good feed reports no errors');
my $uses_liberal = 1;
eval {
	require XML::LibXML;
	require XML::Liberal;
};
if ( $@ ) {
	$uses_liberal = 0;
}
SKIP: {
	skip 'Missing modules to use XML::Liberal for feed normalization', 2 unless ( $uses_liberal );
	is(Reblog::Util::validate_feed($app, $invalid_xml_feed), 1, 'Invalid Atom (high-bit ascii and &nbsp; character) feed validates');
	is($app->errstr, '', 'Invalid but parseable feed reports no errors');
}
SKIP: {
	skip 'XML::Liberal is present, skipping tests for non-Liberal parsing', 2 if ( $uses_liberal );
	is(Reblog::Util::validate_feed($app, $invalid_xml_feed), 0, 'Invalid Atom (high-bit ascii and &nbsp; character) feed does not validate');
	ok($app->errstr =~ m|undefined entity|s, 'Invalid but parseable feed reports "undefined entity" error');
}
is(Reblog::Util::validate_feed($app, $bad_feed), 0, 'Bad feed fails to validate');
SKIP: {
	skip 'Not testing for XML::Liberal error message', 1 unless ( $uses_liberal );
	is($app->errstr =~ m/parser error/, 1, 'Bad feed reports parser error');
}
SKIP: {
	skip 'Not testing detailed non-Liberal error message', 1 if ( $uses_liberal );
	is($app->errstr =~ m/unclosed token/, 1, 'Bad feed reports more detailed "unclosed token" error message');
}
$app->{_errstr} = ''; # Reset error
is(Reblog::Util::validate_feed($app, $non_feed), 0, 'Link to non-feed fails to validate');
is($app->errstr, 'Feed was neither RDF (RSS 1.0) nor RSS (2.0) nor Atom', 'Non-feed reports itself as such');
is(Reblog::Util::validate_feed($app, $bad_url), 0, 'Link to non-extant URL fails to validate');
is($app->errstr =~ m/^Error fetching feed/, 1, 'Bad URL feed reports error fetching feed');
$app->{_errstr} = ''; # Reset error
# is(Reblog::Util::validate_feed($app, $live_feed), 1, 'Live feed (GoogleBlog) validates');
# is($app->errstr, '', 'GoogleBlog feed reports no errors');
# $app->{_errstr} = ''; # Reset error
