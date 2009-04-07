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

use Test::More tests => 39;
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

require Reblog::Util;

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

my ( $atom, $rss091, $rss10, $rss20 ) = (
    MT->model('ReblogSourcefeed')->load(1),
    MT->model('ReblogSourcefeed')->load(2),
    MT->model('ReblogSourcefeed')->load(3),
    MT->model('ReblogSourcefeed')->load(4),
);

my $plugin = MT->component('reblog');
$plugin->set_config_value('import_categories', 1, 'blog:1');

my $import
    = Reblog::Util::do_import( $app, '', $blog, ( $atom, $rss091 ) );
my $count = Reblog::ReblogData->count();
my $entry_count = MT::Entry->count( { blog_id => 1 });
is ( $entry_count, 18, 'Import of two static feeds produces 18 new entries');
my $entry = MT::Entry->load( 1 );
is ( $entry->title, 'Facebook Connect for Movable Type', 'Entry title correctly parsed');
ok ( $entry->text =~ m|Today we are pleased to announce the beta release| && $entry->text =~ m|<a href="http://bugs.movabletype.org/">public bug tracking system</a>.|, 'Entry text correctly parsed');
is ( $entry->blog_id, 1, 'Entry blog id set correctly' );
is ( $entry->status, $blog->status_default, 'Entry status set correctly' );
is ( $entry->allow_comments, $blog->allow_comments_default, 'Entry allow_comments set correctly');
is ( $entry->allow_pings, $blog->allow_pings_default, 'Entry allow_pings set correctly');
is ( $entry->convert_breaks, 0, 'Entry convert_breaks set to 0');
is ( $entry->author_id, 0, 'Entry author_id set correctly');
is ( $entry->keywords, 'News, Plugins, beta, commenting, facebook, plugins', 'Entry keywords set correctly');
is ( $entry->authored_on, '20081204204722', 'Entry authored_on date set correctly');
is ( $entry->reblog_reblogged, 1, 'Entry reblog_reblogged set to 1');
is ( $entry->category->label, 'News', 'With import_categories set to 1, entry primary category set correctly');
my @cats = MT::Category->load({ label => 'facebook' });
my $cat = $cats[0];
ok ( $cat, "New category created thanks to feed load" );
ok ( $entry->is_in_category($cat), 'Entry category assigned correctly');
my $rb_data = Reblog::ReblogData->load( 1 );
is ( $rb_data->sourcefeed_id, 1, 'ReblogData sourcefeed_id set correctly ');
is ( $rb_data->blog_id, 1, 'ReblogData blog_id set correctly');
is ( $rb_data->link, 'http://www.movabletype.org/2008/12/facebook_connect_for_movable_type.html', 'ReblogData link set correctly');
is ( $rb_data->guid, 'tag:www.movabletype.org,2008://2.11641', 'ReblogData guid set correctly');
is ( $rb_data->via_link, $rb_data->link, 'ReblogData via_link defaults to link');
is ( $rb_data->orig_created_on, $entry->authored_on, 'ReblogData orig_created_on set correctly');
is ( $rb_data->source_author, 'Chris Ernest Hall', 'ReblogData source_author set correctly');
is ( $rb_data->source, 'MovableType.org - Home for the MT Community', 'ReblogData source set correctly');
is ( $rb_data->source_url, 'http://www.movabletype.org/', 'ReblogData source_url set correctly');
is ( $rb_data->source_feed_url, MT->model('ReblogSourcefeed')->load(1)->url, 'ReblogData source_feed_url set correctly');
is ( $rb_data->source_title, 'Facebook Connect for Movable Type', 'ReblogData source_title set correctly');
is ( $rb_data->enclosure_url, 'http://example.org/audio/podcast.mp3', 'ReblogData enclosure url set correctly' );
is ( $rb_data->enclosure_length, 1337, 'ReblogData enclosure length set correctly' );
is ( $rb_data->enclosure_type, 'audio/mpeg', 'ReblogData enclosure type set correctly' );

$plugin->set_config_value('import_categories', 0, 'blog:1');

my $blog2 = MT::Blog->new();
$blog2->set_values({
    name => 'naria2',
    site_url => 'http://narnia.na/nana/',
    archive_url => 'http://narnia.na/nana/archives/',
    site_path => 't/site/',
    archive_path => 't/site/archives/',
    archive_type=>'Individual,Monthly,Weekly,Daily,Category,Page',
    archive_type_preferred => 'Individual',
    description => "Narnia Test Blog",
    custom_dynamic_templates => 'custom',
    convert_paras => 1,
    allow_reg_comments => 1,
    allow_unreg_comments => 1,
    allow_pings => 1,
    sanitize_spec => 0,
    sort_order_posts => 'descend',
    sort_order_comments => 'ascend',
    remote_auth_token => 'token',
    convert_paras_comments => 1,
    google_api_key => 'r9Vj5K8PsjEu+OMsNZ/EEKjWmbCeQAv1',
    cc_license => 'by-nc-sa http://creativecommons.org/licenses/by-nc-sa/2.0/ http://creativecommons.org/images/public/somerights20.gif',
    server_offset => '-3.5',
    children_modified_on => '20000101000000',
    language => 'en_us',
    file_extension => 'html',
});
$blog->id(2);
$blog2->commenter_authenticators('enabled_TypeKey');
$blog2->save() or die "Couldn't save blog 2: ". $blog2->errstr;
$atom->blog_id(2);
$atom->save();
$rss091->blog_id(2);
$rss091->save();

$import = Reblog::Util::do_import( $app, '', $blog2, ( $atom, $rss091 ) );
my $count2 = Reblog::ReblogData->count() - $count;
my $entry_count2 = MT::Entry->count( { blog_id => 2 });
is ( $entry_count2, 18, 'Import of two static feeds with import_categories 0 produces 18 new entries');
is ( $count2, 18, '...and 18 ReblogData entities' );
my $cats2 = MT::Category->count({ blog_id => 2 });
is ( $cats2, 0, '...but no MT::Categories in the second blog' );
my $kw;
my $cats;
my @new_entries = MT::Entry->load({ blog_id => 2 });
foreach my $new_entry ( @new_entries ) {
	my $allcats = $new_entry->categories;
	if ( scalar @$allcats ) { $cats = 1; }
}
my $entry2 = MT::Entry->load(19);
my $prev_modified_on = MT::Entry->load(20)->modified_on;
is ( $entry2->keywords, 'News, Plugins, beta, commenting, facebook, plugins', 'Keywords are still picked up when import_categories set to 0' );
ok ( ! $cats, 'No entries pick up categories on import when import_categories 0' );
$entry2->modified_on(20010131120101);
$entry2->save();

$atom->url($feed_base . 'sample_good_updated.atom');
$atom->save;
$import = Reblog::Util::do_import( $app, '', $blog2, ( $atom ) );
$entry_count2 = MT::Entry->count( { blog_id => 2 });
is( $entry_count2, 18, 'Import of feed with updated item does not add a new entry' );
my $entry3 = MT::Entry->load(19);
is ( $entry3->title, 'Facebook Connect for Movable Type IS AWESOME', 'Updated entry picks up new title' );
ok ( $entry3->excerpt =~ m|AWESOME|, 'Updated entry picks up new excerpt' );
ok ( $entry3->modified_on > 20010131120101, 'Updated entry gets a new modified_on value' );
my $still_unchanged = MT::Entry->load(20);
is ( $still_unchanged->modified_on, $prev_modified_on, 'Reimporting does not increment modified_on value without a change');