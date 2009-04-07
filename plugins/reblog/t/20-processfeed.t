use strict;
use warnings;

use lib 't/lib', 'lib', 'extlib';

use MT;
use MT::Log;
use MT::Entry;
use MT::Test qw( :cms :db ::data );

# use MT::Cache::Session;
use MT::TheSchwartz::Job;

use Test::More tests => 26;
use Test::Exception;

use POSIX;
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

require_ok('Reblog::Util');    # require reblog::util
require_ok('Reblog::Import');    # require reblog::import

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

my ( $deactivate_me, $remove_me ) = (
    MT->model('ReblogSourcefeed')->load(1),
    MT->model('ReblogSourcefeed')->load(2)
);

my $import
    = Reblog::Util::do_import( $app, '', $blog, ( $deactivate_me, $remove_me ) );
ok( $import =~ m/^2 feeds read/,
    'Parsed two good feeds' );
my $count = Reblog::ReblogData->count();
cmp_ok( $count, '>', 0,
    'ReblogData is nonzero (has imported some feed items)' );

# we should have imported the same number of entries as reblogdata items
my $entries_count = MT::Entry->count( { blog_id => 1 } );
cmp_ok( $count, '==', $entries_count,
    'Same number of entries as new ReblogData items' );

my @jobs = MT::TheSchwartz::Job->load( { uniqkey => 'reblog_1' } );
is( scalar @jobs, 1, 'New active feed generates a queued worker' );
$remove_me->remove;

# We're allowing up to a minute of error
cmp_ok(
    POSIX::abs( $jobs[0]->run_after - ( $time_snapshot + 60 * 60 * 12 ) ),
    '<',
    '60',
    'Default blog setting for feed reading frequency is 12 hours'
);
@jobs = MT::TheSchwartz::Job->load( { uniqkey => 'reblog_2' } );
is( scalar @jobs, 0, 'Removing a feed deletes queued worker' );

$deactivate_me->is_active(0);
$deactivate_me->save();
@jobs = MT::TheSchwartz::Job->load( { uniqkey => 'reblog_1' } );
is( scalar @jobs, 0, 'Marking sourcefeed inactive deletes queued worker' );

my $entry = MT::Entry->load(1);
is( $entry->author_id, 0,
    'Default author is anonymous; sets entry->author_id to 0' );
is( $entry->reblog_lbl, 'Atom',
    'Entry import sets entry meta label field' );
is( $entry->reblog_reblogged, '1',
    'Entry import sets entry meta reblogged field' );
is( $entry->reblog_anonymous, '1',
    'Entry import sets entry meta anonymous field' );

# Let's fail
my $failed_import = Reblog::Util::do_import( $app, '', $blog, ( $sources[3] ) );
ok( $failed_import =~ /^0 feeds read/, 'Bad feed URL fails to import' );
my $bad_feed = Reblog::ReblogSourcefeed->load(4);
is( $bad_feed->consecutive_failures,
    1, 'Incremented bad feed fail count correctly' );
is( $bad_feed->total_failures, 1,
    'Incremented bad feed total fail count correctly' );
my @logs = MT::Log->load( {},
    { sort => 'id', direction => 'descend', limit => 1 } );
my $log = $logs[0];
is( $log->message,
    'Reblog failed to import http://bad.feed/url',
    'Bad feed adds item to log'
);
my $max_fails
    = MT->component('reblog')->get_config_value( 'max_failures', 'blog:1' );

while ( $bad_feed->consecutive_failures < $max_fails ) {
    $bad_feed->increment_error('Dummy error');
}
is( $bad_feed->has_error, 1,
    'Bad feed has hit maximum fail count & been marked with an error' );
is( $bad_feed->is_active, 0,
    'Failure has caused bad feed to be deactivated' );

# set bad feed to a presumptively good feed
$bad_feed->url('http://rss.msnbc.msn.com/id/3032091/device/rss/rss.xml');
# reactivate it
$bad_feed->is_active(1);
$bad_feed->save;

# Update our blog settings
my $plugin = MT->component('reblog');
$plugin->set_config_value(
    'frequency',
    60 * 60,    # Hourly
    'blog:' . $blog->id
);
$plugin->set_config_value( 'default_author', 1, 'blog:' . $blog->id );
my $entry_count = MT::Entry->count({ blog_id => 1 });
# my $cache = MT::Cache::Session->new();
# $cache->flush_all;
my $new_import = Reblog::Util::do_import( $app, '', $blog, ($bad_feed) );
is( $bad_feed->has_error, 0, 'Successful feed import resets error' );
is( $bad_feed->consecutive_failures,
    0, 'Successful feed import resets consecutive_failures' );
cmp_ok( $bad_feed->total_failures, '>', 0,
    'Successful feed import does not reset total_failures' );
my $new_entry = MT::Entry->load( $entry_count + 1 );
is( $new_entry->reblog_anonymous, '0',
    'Entry meta anonymous field respects new default_user setting' );
is( $new_entry->author_id, '1',
    'Entry author_id field respects new default_user setting' );
$time_snapshot = time();
$bad_feed->save;
@jobs = MT::TheSchwartz::Job->load( { uniqkey => 'reblog_4' } );
# We're allowing up to a minute of error
cmp_ok(
    POSIX::abs( $jobs[0]->run_after - ( $time_snapshot + 60 * 60 ) ),
    '<',
    '60',
    'Previous feed workers respect per-blog feed scraping frequency after saving'
);
$time_snapshot = time();
my $feed = MT->model('ReblogSourcefeed')->new();
$feed->is_active(1);
$feed->blog_id( $blog->id );
$feed->url('http://example.com/feed.atom');
$feed->save();
@jobs = MT::TheSchwartz::Job->load( { uniqkey => 'reblog_5' } );
# We're allowing up to a minute of error
cmp_ok(
    POSIX::abs( $jobs[0]->run_after - ( $time_snapshot + 60 * 60 ) ),
    '<',
    '60',
    'New feed workers respect per-blog feed scraping frequency'
);
