# TODO:
# Test RSS flavors, Google Reader output
# Test enclosures
# Test via_link
use strict;
use warnings;

use lib 't/lib', 'lib', 'extlib';

use MT;
use MT::Category;
use MT::Entry;
use MT::Test qw( :cms :db ::data );

use Test::More tests => 15;
use Test::Exception;

use POSIX;
use Cwd;
use File::Spec;

use Reblog::Util;

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

my $feedurls = [
    {$feed_base . 'sample_good.atom' => 'Atom'},
    {$feed_base . 'sample_good-0.91.rss' => 'RSS 091'},
    {$feed_base . 'sample_good-2.0.rss' => 'RSS 2'},
    {'http://bad.feed/url' => 'Bad Feed'}
];

my $blog = MT::Blog->load(1);
my $app  = MT::App->instance;
$app->blog($blog);
$app->user( MT::Author->load(1) );

# add all our feeds
my @sources;
my $time_snapshot = time();
for my $feedhash (@$feedurls) {
	my @keys = keys %{$feedhash};
	my $feedurl = $keys[0];
	my $label = $feedhash->{$feedurl};
    my $feed = MT->model('ReblogSourcefeed')->new();
    $feed->is_active(1);
    $feed->blog_id( $blog->id );
    $feed->url($feedurl);
    $feed->label($label);
    $feed->save();
    push @sources, $feed;
}

my ( $atom, $rss091, $bad_feed ) = (
    MT->model('ReblogSourcefeed')->load(1),
    MT->model('ReblogSourcefeed')->load(2),
    MT->model('ReblogSourcefeed')->load(4)
);


use MT;
MT->add_callback('plugin_reblog_entry_parsed', 5, undef, \&parsed);
my $parsed = 0;
my ( $entry, $rb_data, $args );
sub parsed {
    my ( $cb, $e, $d, $a ) = @_;
    $parsed++;
    $entry = $e;
    $rb_data = $d;
    $args = $a;
}

my $import
    = Reblog::Util::do_import( $app, '', $blog, ( $atom, $rss091 ) );

ok( $parsed > 0, 'Entry parsing calls plugin_reblog_entry_parsed callback');
is( ref $entry, 'MT::Entry', 'plugin_reblog_entry_parsed passes in MT::Entry');
is( ref $rb_data, 'Reblog::ReblogData', 'plugin_reblog_entry_parsed passes in Reblog::ReblogData');
is( $rb_data->entry_id, $entry->id, 'ReblogData object passed corresponds to Entry object');
is( $args->{parser_type}, 'XML::XPath', 'plugin_reblog_entry_parsed arguments declares parser_type as "XML::XPath"');
is( ref $args->{parser}, 'XML::XPath', 'plugin_reblog_entry_parsed arguments passes XML::XPath parser');
is( ref $args->{node}, 'XML::XPath::Node::Element', 'plugin_reblog_entry_parsed arguments passes Element node');
is( $args->{parser}->findvalue('title', $args->{node}), MT::Entry->load( $parsed )->title, 'Node and parser passed may be used to extract data');

my $max_fails
    = MT->component('reblog')->get_config_value( 'max_failures', 'blog:1' );

MT->add_callback('plugin_reblog_import_failed', 5, undef, \&bad_import);
MT->add_callback('plugin_reblog_sourcefeed_failed', 5, undef, \&bad_sourcefeed);
my ( $feed, $error, $tripped, $source_feed, $source_error, $source_tripped, );
sub bad_import {
    my ( $cb, $f, $e ) = @_;
    $tripped = 1;
    $feed = $f;
    $error = $e;
}
sub bad_sourcefeed {
    my ( $cb, $f, $e ) = @_;
    $source_tripped = 1;
    $source_feed = $f;
    $source_error = $e;
}
while ( $bad_feed->consecutive_failures < $max_fails - 1 ) {
    my $import
        = Reblog::Util::do_import( $app, '', $blog, ( $bad_feed ) );
}
ok( $tripped, 'Import failure calls plugin_reblog_import_failed callback');
is( $feed, $bad_feed, "plugin_reblog_import_failed passes in bad feed");
is( $error, "Can't connect to bad.feed:80 (Bad hostname 'bad.feed')", "plugin_reblog_import_failed passes in error string");
ok( ! $source_tripped, "Import failure up to max_failures does not call plugin_report_sourcefeed_failed");
my $next_import
    = Reblog::Util::do_import( $app, '', $blog, ( $bad_feed ) );
is( $source_feed, $bad_feed, "plugin_reblog_sourcefeed_failed passes in bad feed");
is( $source_error, "Can't connect to bad.feed:80 (Bad hostname 'bad.feed')", "plugin_reblog_sourcefeed_failed passes in error string");
$bad_feed->is_active(1);
$bad_feed->save();
$source_tripped = 0;
$next_import
    = Reblog::Util::do_import( $app, '', $blog, ( $bad_feed ) );
ok( $source_tripped, "Import failure beyond max_failures calls plugin_report_sourcefeed_failed");
