use strict;
use warnings;

use lib 't/lib', 'lib', 'extlib';

use MT;
use MT::Template;
use MT::Template::Context;
use MT::Test qw( :cms :db ::data );

use Test::More tests => 62;
use Test::Exception;

my $feedurls = [
    'http://googleblog.blogspot.com/feeds/posts/default',
    'http://bad.feed/url',
];

my $blog = MT::Blog->load(1);

require_ok('Reblog::Tags');    # require reblog::tags
require Reblog::Util;

my $ctx = new MT::Template::Context;
$ctx->stash( 'blog', $blog );
my $blog_text = '<mt:ifreblog>reblog</mt:ifreblog><mt:ifnotreblog>notreblog</mt:ifnotreblog>';
my $test_txt = $blog_text;
my $tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'notreblog', 'New blog matches mt:IfNotReblog');

for my $feedurl (@$feedurls) {
    my $feed = MT->model('ReblogSourcefeed')->new();
    $feed->is_active(1);
    $feed->blog_id( $blog->id );
    $feed->url($feedurl);
    $feed->save();
}

$tmpl->text($test_txt);
is ($tmpl->build($ctx), 'reblog', 'Adding two sourcefeeds matches mt:IfReblog');
my $feed;
$feed = MT->model('ReblogSourcefeed')->load(1);
$feed->is_active(0);
$feed->save();
is ($tmpl->build($ctx), 'reblog', 'One active, one inactive feed matches mt:IfReblog');
$feed->remove();
is ($tmpl->build($ctx), 'reblog', 'One active feed matches mt:IfReblog');
$feed = MT->model('ReblogSourcefeed')->load(2);
$feed->is_active(0);
$feed->save();
is ($tmpl->build($ctx), 'notreblog', 'Deactivating all feeds matches mt:IfNotReblog');
$feed->remove();
is ($tmpl->build($ctx), 'notreblog', 'Removing all feeds matches mt:IfNotReblog');

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
my $newfeed = MT->model('ReblogSourcefeed')->new();
$newfeed->is_active(1);
$newfeed->blog_id( $blog->id );
$newfeed->url($feed_base . 'sample_good-1.0.rss');
$newfeed->save;

my $mt = MT->instance;
my $import
    = Reblog::Util::do_import( $mt, '', $blog, ( $newfeed ) );

use MT::Entry;
my $entry = MT::Entry->load( 1 );

$ctx->stash( 'entry', $entry );
$ctx->stash( 'reblog_source', $newfeed );

my $rbdata = Reblog::ReblogData->load({ entry_id => 1 });
$rbdata->via_link('http://www.example.com');
$rbdata->guid('GUID');
$rbdata->thumbnail_link('http://example.com/landing/');
$rbdata->thumbnail_url('http://example.com/wombat.png');
$rbdata->annotation('Really good! --Steve');
$rbdata->enclosure_url('http://example.com/otter.png');
$rbdata->enclosure_length(123456);
$rbdata->enclosure_type('image/png');
$rbdata->save;

my $rbd2 = Reblog::ReblogData->load({ entry_id => 3 });
$rbd2->created_on('20090201120100');
$rbd2->enclosure_url('http://example.com/something/');
$rbd2->save;

my $nonrb = MT::Entry->new();
$nonrb->title('Hello');
$nonrb->text('There');
$nonrb->author_id(1);
$nonrb->blog_id(1);
$nonrb->status(MT::Entry::RELEASE());
$nonrb->save;


$test_txt = '<mt:entryreblogsource>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'XML.com', '<mt:entryreblogsource> yields "XML.com"');

$test_txt = '<mt:entryreblogsourcelink>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'http://www.xml.com/', '<mt:entryreblogsourcelink> yields "http://www.xml.com/"');

$test_txt = '<mt:entryreblogsourceurl>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'http://www.xml.com/', '<mt:entryreblogsourceurl> yields "http://www.xml.com/"');

$test_txt = '<mt:entryreblogsourcelinkxml>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
ok ($tmpl->build($ctx) =~ m|reblog/t/sample_good-1.0.rss|, '<mt:entryreblogsourcelinkxml> matches "reblog/t/sample_good-1.0.rss"');

$test_txt = '<mt:entryreblogsourcefeedurl>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
ok ($tmpl->build($ctx) =~ m|reblog/t/sample_good-1.0.rss|, '<mt:entryreblogsourcefeedurl> matches "reblog/t/sample_good-1.0.rss"');

$test_txt = '<mt:entryreblogsourcefeedid>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 1, '<mt:entryreblogsourcefeedid> is 1');

$test_txt = '<mt:entryrebloglink>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'http://www.xml.com/pub/a/2002/12/04/normalizing.html', '<mt:entryrebloglink> yields "http://www.xml.com/pub/a/2002/12/04/normalizing.html"');

$test_txt = '<mt:entryreblogvialink>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'http://www.example.com', '<mt:entryreblogvialink> yields "http://www.example.com"');

$test_txt = '<mt:entryreblogsourcepublisheddate>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'December  4, 2002  5:00 AM', '<mt:entryreblogsourcepublisheddate> yields "December  4, 2002  5:00 AM"');

$test_txt = '<mt:entryreblogsourceauthor>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'Will Provost', '<mt:entryreblogsourceauthor> yields "Will Provost"');

$test_txt = '<mt:entryreblogauthor>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'Will Provost', '<mt:entryreblogauthor> yields "Will Provost" (legacy syntax; duplicate tag to <mt:entryreblogsourceauthor>)');

$test_txt = '<mt:entryreblogidentifier>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'GUID', '<mt:entryreblogidentifier> yields "GUID"');

$test_txt = '<mt:entryreblogthumbnaillink>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'http://example.com/landing/', '<mt:entryreblogthumbnaillink> yields "http://example.com/landing/"');

$test_txt = '<mt:entryreblogthumbnailimg>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'http://example.com/wombat.png', '<mt:entryreblogthumbnailimg> yields "http://example.com/wombat.png"');

$test_txt = '<mt:entryreblogsourcetitle>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'Normalizing XML, Part 2', '<mt:entryreblogsourcetitle> yields "Normalizing XML, Part 2"');

$test_txt = '<mt:entryreblogannotation>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'Really good! --Steve', '<mt:entryreblogsourcetitle> yields "Really good! --Steve"');

$test_txt = '<mt:reblogsourcefeeds><mt:reblogsourceid></mt:reblogsourcefeeds>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), '1', '<mt:reblogsourceid> yields "1"');


$test_txt = '<mt:reblogsourcefeeds><mt:reblogsourcetitle></mt:reblogsourcefeeds>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'XML.com', '<mt:reblogsourcetitle> yields "XML.com"');

$test_txt = '<mt:reblogsourcefeeds><mt:reblogsourcexmllink></mt:reblogsourcefeeds>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
ok ($tmpl->build($ctx) =~ m|reblog/t/sample_good-1.0.rss|, '<mt:reblogsourcexmllink> matches "reblog/t/sample_good-1.0.rss"');

$test_txt = '<mt:reblogsourcefeeds><mt:reblogsourcefeedurl></mt:reblogsourcefeeds>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
ok ($tmpl->build($ctx) =~ m|reblog/t/sample_good-1.0.rss|, '<mt:reblogsourcefeedurl> matches "reblog/t/sample_good-1.0.rss"');

$test_txt = '<mt:reblogsourcefeeds><mt:reblogsourcelink></mt:reblogsourcefeeds>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'http://www.xml.com/', '<mt:reblogsourcelink> yields "http://www.xml.com/"');

$test_txt = '<mt:reblogsourcefeeds><mt:reblogsourceurl></mt:reblogsourcefeeds>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'http://www.xml.com/', '<mt:reblogsourceurl> yields "http://www.xml.com/"');

$test_txt = '<mt:entryreblogenclosure>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'http://example.com/otter.png', '<mt:entryreblogenclosure> yields "http://example.com/otter.png"');

$test_txt = '<mt:entryreblogenclosurelength>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), '123456', '<mt:entryreblogenclosure> yields "123456"');

$test_txt = '<mt:entryreblogenclosuremimetype>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'image/png', '<mt:entryreblogenclosuremimetype> yields "image/png"');

$test_txt = '<mt:reblogentries><mt:entrytitle></mt:reblogentries>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'Normalizing XML, Part 2The .NET Schema Object ModelSVG\'s Past and Promising Future', '<mt:reblogentries> loops through three entries');

$test_txt = '<mt:reblogentries><mt:if name="__first__">ENTRIES: </mt:if>
<mt:if name="__even__"><span class="even"><mt:else><mt:if name="__odd__"><span class="odd"></mt:if></mt:if><mt:var name="__counter__">. <mt:entrytitle></span>
<mt:if name="__last__">END</mt:if></mt:reblogentries>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
my $output = $tmpl->build($ctx);
ok($output =~ m|^ENTRIES: |s, "<mt:reblogentries> respects __first__");
ok($output =~ m|END$|s, "<mt:reblogentries> respects __last__");
ok($output =~ m|<span class="even">2\.|s, "<mt:reblogentries> respects __even__");
ok($output =~ m|<span class="odd">1\.|s && $output =~ m|<span class="odd">3\.|s, "<mt:reblogentries> respects __odd__");
ok($output =~ m|1\. .*2\. .*3\. |s, "<mt:reblogentries> respects __counter__");

$test_txt = '<mt:reblogentries limit="2"><mt:entrytitle></mt:reblogentries>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'Normalizing XML, Part 2The .NET Schema Object Model', '<mt:reblogentries> respects limit');

$test_txt = '<mt:reblogentries lastn="2"><mt:entrytitle></mt:reblogentries>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'Normalizing XML, Part 2The .NET Schema Object Model', '<mt:reblogentries> respects lastn as alias for limit');

$test_txt = '<mt:reblogentries offset="1"><mt:entrytitle></mt:reblogentries>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'The .NET Schema Object ModelSVG\'s Past and Promising Future', '<mt:reblogentries> respects offset');

$test_txt = '<mt:reblogentries limit="1" offset="1"><mt:entrytitle></mt:reblogentries>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'The .NET Schema Object Model', '<mt:reblogentries> respects offset and limit simultaneously');

$test_txt = '<mt:reblogenclosureentries><mt:entrytitle></mt:reblogenclosureentries>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'Normalizing XML, Part 2SVG\'s Past and Promising Future', '<mt:reblogenclosureentries> loops through two entries');

$ctx->stash( 'entry', $entry );
$test_txt = '<mt:EntryIfHasReblogAuthor><$mt:EntryTitle$><mt:else>No</mt:EntryIfHasReblogAuthor>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'Normalizing XML, Part 2', '<mt:EntryIfHasReblogAuthor> returns positive appropriately, passes MT::Entry');

$rbdata->source_author('');
$rbdata->save;
$test_txt = '<mt:EntryIfHasReblogAuthor><$mt:EntryTitle$><mt:else>No</mt:EntryIfHasReblogAuthor>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'No', '<mt:EntryIfHasReblogAuthor> returns negative when no reblog source author is present');

$ctx->stash( 'entry', $nonrb );
$test_txt = '<mt:EntryIfHasReblogAuthor><$mt:EntryTitle$><mt:else>No</mt:EntryIfHasReblogAuthor>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'No', '<mt:EntryIfHasReblogAuthor> returns negative when non-reblogged entry is in context');

$ctx->stash( 'entry', $entry );
$test_txt = '<mt:EntryIfReblog><$mt:EntryTitle$><mt:else>No</mt:EntryIfReblog>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'Normalizing XML, Part 2', '<mt:EntryIfReblog> returns positive appropriately, passes MT::Entry');

$ctx->stash( 'entry', $nonrb );
$test_txt = '<mt:EntryIfReblog><$mt:EntryTitle$><mt:else>No</mt:EntryIfReblog>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
is ($tmpl->build($ctx), 'No', '<mt:EntryIfReblog> returns negative when non-reblogged entry in context');

# ReblogSourcefeeds has existing stub coverage via the <mt:reblogsourceurl> tag et al, but let's check for first/last/etc
$newfeed = MT->model('ReblogSourcefeed')->new();
$newfeed->is_active(1);
$newfeed->blog_id( $blog->id );
$newfeed->url($feed_base . 'sample_good.atom');
$newfeed->save;
$import = Reblog::Util::do_import( $mt, '', $blog, ( $newfeed ) );
$newfeed = MT->model('ReblogSourcefeed')->new();
$newfeed->is_active(1);
$newfeed->blog_id( $blog->id );
$newfeed->url($feed_base . 'sample_nyt.atom');
$newfeed->save;
$import = Reblog::Util::do_import( $mt, '', $blog, ( $newfeed ) );

$test_txt = '<mt:reblogsourcefeeds>
<mt:if name="__first__">SOURCES: </mt:if>
<mt:if name="__even__"><span class="even"><mt:else><mt:if name="__odd__"><span class="odd"></mt:if></mt:if><mt:var name="__counter__">. <mt:reblogsourceurl></span><br />
<mt:if name="__last__">END</mt:if>
</mt:reblogsourcefeeds>';
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
$output = $tmpl->build($ctx);
ok($output =~ m|^SOURCES: |s, "<mt:reblogsourcefeeds> respects __first__");
ok($output =~ m|END$|s, "<mt:reblogsourcefeeds> respects __last__");
ok($output =~ m|<span class="even">2\.|s, "<mt:reblogsourcefeeds> respects __even__");
ok($output =~ m|<span class="odd">1\.|s && $output =~ m|<span class="odd">3\.|s, "<mt:reblogsourcefeeds> respects __odd__");
ok($output =~ m|1\. .*2\. .*3\. |s, "<mt:reblogsourcefeeds> respects __counter__");

$test_txt = q{<mt:reblogsourcefeeds limit="2">
<mt:reblogsourcetitle> <mt:reblogsourceurl><br />
</mt:reblogsourcefeeds>};
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
$output = $tmpl->build($ctx);
ok(($output =~ m|^XML.com|s and $output =~ m|MovableType.org| and $output !~ m|Open|s ), "<mt:reblogsourcefeeds> respects limit argument");
$test_txt = q{<mt:reblogsourcefeeds offset="1">
<mt:reblogsourcetitle> <mt:reblogsourceurl><br />
</mt:reblogsourcefeeds>};
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
$output = $tmpl->build($ctx);
ok(($output =~ m|^MovableType.org|s and $output =~ m|Open | and $output !~ m|XML.com|s ), "<mt:reblogsourcefeeds> respects offset argument");
$test_txt = q{<mt:reblogsourcefeeds limit="1" offset="1">
<mt:reblogsourcetitle> <mt:reblogsourceurl><br />
</mt:reblogsourcefeeds>};
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
$output = $tmpl->build($ctx);
ok(($output =~ m|^MovableType.org|s and $output !~ m|Open | and $output !~ m|XML.com|s ), "<mt:reblogsourcefeeds> respects offset and limit arguments simultaneously");
$test_txt = q{<mt:reblogsourcefeeds sort="title"><mt:reblogsourcetitle>,</mt:reblogsourcefeeds>};
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
$output = $tmpl->build($ctx);
ok( $output eq 'MovableType.org - Home for the MT Community,Open,XML.com,', 'reblogsourcefeeds allows sorting by sourcefeed title');
my $open = Reblog::ReblogSourcefeed->load(3);
$open->label('a');
$open->save;
my $xml = Reblog::ReblogSourcefeed->load(1);
$xml->label('b');
$xml->save;
my $mtorg = Reblog::ReblogSourcefeed->load(2);
$mtorg->label('c');
$mtorg->save;
$test_txt = q{<mt:reblogsourcefeeds sort="label"><mt:reblogsourcetitle>,</mt:reblogsourcefeeds>};
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
$output = $tmpl->build($ctx);
ok( $output eq 'Open,XML.com,MovableType.org - Home for the MT Community,', 'reblogsourcefeeds allows sorting by sourcefeed label');

my $badfeed = MT->model('ReblogSourcefeed')->new();
$badfeed->is_active(0);
$badfeed->blog_id( $blog->id );
$badfeed->url(q{http://bad.feed/url});
$badfeed->label(q{bad!});
$badfeed->save();

$test_txt = q{<mt:reblogsourcefeeds sort="title"><mt:reblogsourcetitle></mt:reblogsourcefeeds>};
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
$output = $tmpl->build($ctx);
ok( $output =~ m|bad\!$|, 'Sourcefeed label is used as title if no entry is available');

$test_txt = q{<mt:reblogsourcefeeds sort="title"><mt:reblogsourceurl></mt:reblogsourcefeeds>};
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
$output = $tmpl->build($ctx);
ok( $output =~ m|http://bad.feed/url$|, 'Sourcefeed feed url is used as source url if no entry is available');

$test_txt = q{<mt:reblogsourcefeeds sort="last_checked"><mt:reblogsourcetitle>,</mt:reblogsourcefeeds>};
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
$output = $tmpl->build($ctx);
ok($output =~ m|^XML\.com,| && $output =~ m|bad\!,$|, 'reblogsourcefeeds allows sorting by last_checked, with unchecked (new) feeds forced to the end' );

$test_txt = q{<mt:reblogsourcefeeds sort="last_checked" active_only="1"><mt:reblogsourcetitle>,</mt:reblogsourcefeeds>};
$tmpl = MT::Template->new();
$tmpl->text($test_txt);
$tmpl->blog_id( $blog->id );
$tmpl->save;
$output = $tmpl->build($ctx);
ok($output =~ m|^XML\.com,| && $output !~ m|bad\!|, 'reblogsourcefeeds accepts active_only argument' );
