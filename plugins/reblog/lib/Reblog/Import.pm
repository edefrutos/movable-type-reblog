#############################################################################
# Copyright © 2007-2009 Six Apart Ltd.
# This program is free software: you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# version 2 for more details.  You should have received a copy of the GNU
# General Public License version 2 along with this program. If not, see
# <http://www.gnu.org/licenses/>.
# $Id: Import.pm 17902 2009-04-07 02:16:15Z steve $

package Reblog::Import;

use base qw( Class::ErrorHandler );

use strict;
use warnings;

use POSIX;

use Date::Parse;

use MT::Author;
use MT::Blog;
use MT::Util qw( format_ts offset_time_list offset_time ts2epoch epoch2ts );

use URI::Fetch;
use XML::XPath;
use XML::XPath::XMLParser;

use Carp;
use Encode;

use constant SPLIT_TOKEN => chr(28);

sub iso2dt {

    # TAKEN FROM XML::Atom::Util
    my ($iso) = @_;
    return
        unless $iso
            =~ /^(\d{4})(?:-?(\d{2})(?:-?(\d\d?)(?:T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:Z|([+-]\d{2}:\d{2}))?)?)?)?/;
    my ( $y, $mo, $d, $h, $m, $s, $zone )
        = ( $1, $2 || 1, $3 || 1, $4 || 0, $5 || 0, $6 || 0, $7 );
    require DateTime;
    my $dt = DateTime->new(
        year      => $y,
        month     => $mo,
        day       => $d,
        hour      => $h,
        minute    => $m,
        second    => $s,
        time_zone => 'UTC',
    );
    if ( $zone && $zone ne 'Z' ) {
        my $seconds = DateTime::TimeZone::offset_as_seconds($zone);
        $dt->subtract( seconds => $seconds );
    }
    $dt;
}

sub assign_categories {
    my ( $entry, $blog, $author, $subjects ) = @_;
    my $res    = [];
    my $plugin = MT->component('reblog');
    my $import_categories;
    $import_categories = $plugin->get_config_value( 'import_categories',
        'blog:' . $blog->id );
    unless ($import_categories) {
        return $res;
    }

    my (@cats) = MT::Category->load( { blog_id => $blog->id } );
    my ( $cat, $place );

    my %cat_hash;
    foreach my $cat (@cats) {
        $cat_hash{ lc( $cat->label ) } = $cat;
    }

    # grab the placement entries from the database for this entry.
    my (@placements) = MT::Placement->load( { entry_id => $entry->id } );

    my %place_hash;

    foreach $place (@placements) {
        $place_hash{ $place->category_id } = $place;
    }
    my @subs;
    ($subjects) && ( @subs = split( SPLIT_TOKEN, $subjects ) );
    my $primary = 0;
    foreach my $sub (@subs) {

        (@cats) = split( /\:\:/, $sub );
        my $parent = 0;
        foreach $cat (@cats) {
            $cat =~ s/\+/ /igs;

            if ( exists( $cat_hash{ lc($cat) } ) ) {

                $cat = $cat_hash{ lc($cat) };
            }
            else {
                $cat = create_category( $cat, $blog, $author, $parent );
                $cat_hash{ lc( $cat->label ) } = $cat;
            }

            if ( exists( $place_hash{ $cat->id } ) ) {

                $place = $place_hash{ $cat->id };
            }
            else {
                $place = create_placement( $entry, $cat, 0 );
                $place_hash{ $cat->id } = $place;
            }

            if ( $place->is_primary ) {
                $primary = $place;
            }
            $parent = $cat;
            push( @$res, $cat );
        }
    }

    my %curr_cats;

    foreach $cat (@$res) {
        $curr_cats{ $cat->id } = $cat;
    }

    foreach $place ( values %place_hash ) {
        if ( !exists( $curr_cats{ $place->category_id } ) ) {
            $place->remove();
        }
    }

    if ( !$primary && scalar(@$res) > 0 ) {
        $primary = $place_hash{ $res->[0]->id };
        $primary->is_primary(1);
        $primary->save();
    }

    return $res;
}

sub create_category {
    my ( $label, $blog, $author, $parent ) = @_;
    my $author_id;
    if ( $author == -1 ) {
        $author_id = 0;
    }
    else {
        $author_id = $author->id;
    }
    my $cat = MT::Category->new();
    $cat->blog_id( $blog->id );
    $cat->allow_pings( $blog->allow_pings_default );
    $cat->label($label);
    $cat->author_id($author_id);
    $cat->parent( ( $parent ? $parent->id : 0 ) );

    $cat->save();
    return MT::Category->load( $cat->id );
}

sub create_placement {
    my ( $entry, $cat, $is_primary ) = @_;

    my $place = MT::Placement->new();
    $place->entry_id( $entry->id );
    $place->blog_id( $entry->blog_id );
    $place->category_id( $cat->id );
    $place->is_primary($is_primary);
    $place->save();

    return MT::Placement->load( $place->id );
}

sub import_entries {
    my $class = shift;
    my ( $sourcefeed, $args ) = @_;
    my ( $blog_id, $author, $suppress, $cache_ttl );
    $blog_id   = $args->{blog_id};
    $author    = $args->{author};
    $suppress  = $args->{suppress};
    $cache_ttl = $args->{cache_ttl};
    unless ( $cache_ttl && $cache_ttl =~ m|^\d+$| ) {
        $cache_ttl ||= 15 * 60;
    }
    my $author_id;
    my ( $blog, $cache, $source_rss );
    my $config = MT::ConfigMgr->instance;

    if ($suppress) {    # Indicating a validation test
        $source_rss = $sourcefeed;
        undef $sourcefeed;
        use MT::Cache::Null;
        $cache = MT::Cache::Null->new;
    }
    else {
        if ( $author == -1 ) {
            $author_id = 0;
        }
        else {
            if ( !ref($author) ) {
                $author = MT::Author->load($author);
            }
            $author_id = $author->id;
        }
        $source_rss = $sourcefeed->url;
        $blog       = MT::Blog->load($blog_id);

        # Someday perhaps we can have config directives
        # allowing us to choose between MT::Cache::Negotiate,
        # MT::Cache::Null, and a file-based caching system
        use MT::Cache::Negotiate;
        $cache = MT::Cache::Negotiate->new( ttl => $cache_ttl );
    }
    unless ($source_rss) {
        return $class->error("No sourcefeed selected for validation");
    }
    my $mt_vers = MT->version_number;
    my (@entries);
    my $plugin = MT->component('reblog');

    require LWP::UserAgent;
    my $ua = MT->new_ua( { timeout => 20 } );
    $ua->env_proxy;
    my $res;

    unless (
        $res = URI::Fetch->fetch(
            $source_rss,
            UserAgent => $ua,
            Cache     => $cache
        )
        )
    {

        if ($sourcefeed) {
            $sourcefeed->increment_error( URI::Fetch->errstr );
        }
        return $class->error(
            "Error fetching feed ($source_rss): " . URI::Fetch->errstr );
    }
    my $rss = $res->content;

    if ( MT->config('HTTPProxy') ) {    # For XML::XPath's DTD fetching
        $ENV{HTTP_PROXY} = MT->config('HTTPProxy');
    }

    if ( defined($rss) && $rss ) {
        my $xp = XML::XPath->new( xml => $rss );
        my $map = {
            'body'          => 'description',
            'title'         => 'title',
            'link'          => 'link',
            'guid'          => 'rb:guid',
            'via_link'      => 'rb:via_url',
            'orig_date'     => 'rb:source_published_date',
            'source_author' => 'rb:source_author',
            'source_name'   => 'rb:source',
            'source_url'    => 'rb:source_url',
            'summary'       => 'summary',
        };

        my $enclosure_url    = "";
        my $enclosure_length = "";
        my $enclosure_type   = "";
        my $gen;
        eval { $gen = $xp->findvalue('/feed/generator'); };
        my $flagged = 0;
        if ($@) {
            $flagged = 1;
        }
        if ($flagged) {
            my $unliberal_error = $@;
            eval "require XML::LibXML";
            eval "require XML::Liberal;";
            if ($@) {
                $@ = $unliberal_error;
            }
            else {
                $@ = $unliberal_error;
                XML::Liberal->globally_override('LibXML');
                my $parser = XML::LibXML->new;              # isa XML::Liberal
                my $doc    = $parser->parse_string($rss);
                $xp = XML::XPath->new( $doc->toString );
                eval { $gen = $xp->findvalue('/feed/generator'); };
            }
            if ($@) {

                if ($sourcefeed) {
                    $sourcefeed->increment_error($@);
                }
                return $class->error(
                    "Error parsing feed ($source_rss): " . $@ );
            }
        }
        my $type;
        if ( $xp->exists("/rss") ) {
            $type              = "rss";
            $map->{'date'}     = 'pubDate';
            $map->{'subjects'} = 'category';
        }
        elsif ( $xp->exists("/rdf:RDF") ) {
            $type              = "rdf";
            $map->{'date'}     = 'dc:date';
            $map->{'subjects'} = 'dc:subject';
        }
        elsif ( $gen eq 'Google Reader' ) {
            $type              = "atom";
            $map->{'date'}     = 'published';
            $map->{'subjects'} = 'category/@term';
            $map->{'body'}     = 'content';
            $map->{'summary'}  = 'summary';

            $map->{'link'} = 'link[@rel="alternate"]/@href';
            if ( !$map->{link} ) {
                $map->{'link'} = 'link/@href';
            }

            $map->{'guid'}          = 'id';
            $map->{'orig_date'}     = 'updated';
            $map->{'source_author'} = 'author/name';
            $map->{'source_name'}   = 'source/title';
            $map->{'source_url'}    = 'source/link/@href';
        }
        elsif ( $xp->exists("/feed") ) {
            $type               = "atom";
            $map->{'date'}      = 'updated';
            $map->{'orig_date'} = 'published';
            $map->{'body'}      = 'content';
            $map->{'summary'}   = 'summary';
            $map->{'subjects'}  = 'category/@term';

            $map->{'link'} = 'link[@rel="alternate"]/@href';
            if ( !$map->{link} ) {
                $map->{'link'} = 'link/@href';
            }
            $map->{'guid'}          = 'id';
            $map->{'source_author'} = 'author/name';
        }
        else {
            if ($sourcefeed) {
                $sourcefeed->increment_error(
                    "Feed was neither RDF (RSS 1.0) nor RSS (2.0) nor Atom");
            }
            return $class->error(
                "Feed was neither RDF (RSS 1.0) nor RSS (2.0) nor Atom");
        }

        my ( $channeltitle, $channellink );
        if ( $type eq 'rss' ) {
            $channeltitle = $xp->findvalue('/rss/channel/title');
            $channellink  = $xp->findvalue('/rss/channel/link');
        }
        elsif ( $type eq 'rdf' ) {
            $channeltitle = $xp->findvalue('/rdf:RDF/channel/title');
            $channellink  = $xp->findvalue('/rdf:RDF/channel/link');
        }
        elsif ( $type eq 'atom' ) {
            $channeltitle = $xp->findvalue('/feed/title');
            $channellink
                = $xp->findvalue('/feed/link[@rel="alternate"]/@href');
        }
        my $nodeset;
        if ( $type eq 'atom' ) {
            $nodeset = $xp->findnodes("//entry");
        }
        else {
            $nodeset = $xp->findnodes("//item");
        }

        while ( my $node = $nodeset->shift() ) {
            my $body;
            $body = &_clean_html( $xp->findvalue( $map->{'body'}, $node ) );
            unless ($body) {
                $body = &_clean_html(
                    $xp->findvalue( $map->{'summary'}, $node ) );
            }
            my $title
                = &_clean_html( $xp->findvalue( $map->{'title'}, $node ) );
            my $link = $xp->findvalue( $map->{'link'}, $node );
            my $date = $xp->findvalue( $map->{'date'}, $node );
            if ( !$date && $map->{'date'} eq 'pubDate' ) {

                # RSS 0.91 properly treats pubDate as a channel-level item
                $date = $xp->findvalue("/rss/channel/pubDate");
            }
            my $subjects
                = &_clean_html( $xp->findvalue( $map->{'subjects'}, $node ) );

            my $guid     = $xp->findvalue( $map->{'guid'},     $node );
            my $via_link = $xp->findvalue( $map->{'via_link'}, $node );
            my $orig_date;
            $orig_date = $xp->findvalue( $map->{'orig_date'}, $node );

            my $source_author = &_clean_html(
                $xp->findvalue( $map->{'source_author'}, $node ) );
            my $source_name = &_clean_html(
                $xp->findvalue( $map->{'source_name'}, $node ) );
            my $source_url = $xp->findvalue( $map->{'source_url'}, $node );
            my $source_title
                = &_clean_html( $xp->findvalue( $map->{'title'}, $node ) );
            my $summary
                = &_clean_html( $xp->findvalue( $map->{'summary'}, $node ) );

         # it may not be in the map hash, so if there's no value, that's okay.
            my $modifiedTime = $xp->findvalue( 'updated', $node );

            # Tricky to get the enclosures tag because it has no value,
            # so you can't call $xp->findvalue().  it only has attributes.
            # instead, call findnodes within this current node for enclosure,
            # grab the first one, and regard it as your winner.
            my $enclosures = $xp->findnodes( 'enclosure', $node );

            # $enclosures now is a nodelist.  just grab the first one.
            if ($enclosures) {
                $enclosures = $enclosures->shift();

                $enclosure_url  = $enclosures->getAttribute('url');
                $enclosure_type = $enclosures->getAttribute('type');
                if ( !$enclosure_type ) {
                    $enclosure_type = determine_file_type($enclosure_url);
                }
                $enclosure_length = $enclosures->getAttribute('length');
            }

            # Deal with the case of multiple categories in Atom and RSS
            if ( $type eq 'atom' || $type eq 'rss' ) {
                my @subjects;
                my @subjectnodes
                    = ( $xp->findnodes( $map->{'subjects'}, $node ) );
                foreach my $catnode (@subjectnodes) {
                    if ( $type eq 'atom' ) {
                        push @subjects,
                            &_clean_html( $catnode->getNodeValue );
                    }
                    elsif ( $type eq 'rss' ) {
                        push @subjects,
                            &_clean_html( $catnode->string_value );
                    }
                }
                if ( scalar @subjects > 1 ) {
                    $subjects = join SPLIT_TOKEN, @subjects;
                }
            }

            # Let's plug in some sensible values if these are missing
            # which will imply that we're not using a reblog feed but
            # rather just a standard RSS feed
            # We want to pick up: GUID, Source Author, Via Link, Source,
            #                     Source Title, Source Feed URL
            if ( !$guid ) {
                $guid = $xp->findvalue( 'guid', $node );
                if ( !$guid ) {
                    $guid = $link;

                    # This is questionable, as links are not assuredly GUIDs;
                    # this actually doesn't work for google reader feeds
                }
            }
            if ( !$via_link ) {
                $via_link = $link;
            }
            if ( !$source_author ) {
                $source_author
                    = $xp->findvalue( 'dc:creator', $node );    # dc:creator
            }
            if ( !$source_name ) {
                $source_name = $channeltitle;
            }
            if ( !$source_title ) {
                $source_title = $channeltitle;
            }
            if ( !$source_url ) {
                $source_url = $channellink;
            }

            my $ts = str2time($date);

            if ($modifiedTime) {
                $ts = str2time($modifiedTime);
            }

            $date = POSIX::strftime( "%Y%m%d%H%M%S",
                gmtime( offset_time( $ts, $blog ) ) );

            if ($orig_date) {
                my $orig_ts = str2time($orig_date);
                $orig_date = POSIX::strftime(
                    ( $mt_vers < 3.2 ? "%Y-%m-%d %H:%M:%S" : "%Y%m%d%H%M%S" ),
                    gmtime( offset_time( $orig_ts, $blog ) )
                );
            }
            else {
                $orig_date = $date;
            }

            if ($suppress) {
                return 1;
            }

            my $entry;

          # If we're updating an old reblogged row, we need this entry but
          # can't use MT::Object join for this circumstance, so do it manually
            my (@rb_data) = Reblog::ReblogData->load( { guid => $guid },
                { sort => 'created_on', direction => 'ascend' } );
            my $rb_data;
            foreach my $rbd (@rb_data) {
                $entry = MT::Entry->load(
                    { id => $rbd->entry_id, blog_id => $blog_id } );
                if ($entry) {

                    my $tempCatRef = $entry->category;
                    my @categories = keys(%$tempCatRef);
                    $rb_data = $rbd;
                }
            }

            if ( !$rb_data ) {
                $rb_data = Reblog::ReblogData->new;
                $rb_data->created_on($date);
            }

            $rb_data->sourcefeed_id( $sourcefeed->id );
            $rb_data->blog_id( $sourcefeed->blog_id );
            $rb_data->link($link);
            $rb_data->guid($guid);
            $rb_data->via_link($via_link);
            $rb_data->orig_created_on($orig_date);
            $rb_data->source_author($source_author);
            $rb_data->source($source_name);
            $rb_data->source_url($source_url);
            $rb_data->source_feed_url($source_rss);
            $rb_data->source_title($source_title);

            $rb_data->enclosure_url($enclosure_url);
            $rb_data->enclosure_length($enclosure_length);
            $rb_data->enclosure_type($enclosure_type);

          # If we're not updating an existing entry, we're creating an new one
          # if this is the case, we will be creating an reblog_data row

            if (!(  $rb_data->entry_id
                    && ($entry = MT::Entry->load(
                            { id => $rb_data->entry_id, blog_id => $blog_id }
                        )
                    )
                )
                )
            {
                $entry = MT::Entry->new();
                $entry->blog_id($blog_id);
                $entry->status( $blog->status_default );
                $entry->allow_comments( $blog->allow_comments_default );
                $entry->allow_pings( $blog->allow_pings_default );
                $entry->convert_breaks(0);
                $entry->author_id($author_id);
                my $kw    = $subjects;
                my $token = SPLIT_TOKEN;
                $kw && $kw =~ s/$token/, /g;
                $entry->keywords($kw);
                $entry->authored_on($orig_date);
                $entry->reblog_reblogged(1);

                if ( $author_id == 0 ) {
                    $entry->reblog_anonymous(1);
                }
                else {
                    $entry->reblog_anonymous(0);
                }
                $entry->reblog_lbl( $sourcefeed->label );
            }

            my $ts_modified = 0;
            if ( $entry->modified_on ) {
                $ts_modified = ts2epoch( $blog, $entry->modified_on );
            }
            unless ($ts) {
                $ts = 1;    # RSS 0.91, no pubDate found
            }

            my $status = 'old';

            my $categories = [];

            # No problem, now that ts_modified is correct.
            if (   ( !$entry->id )
                || ( POSIX::floor($ts) > POSIX::floor($ts_modified) ) )
            {
                $status = ( $entry->id ? 'update' : 'new' );
                if ( $entry->id ) {
                    use MT::Util;
                    $entry->modified_on( MT::Util::epoch2ts( undef, time ) );
                }
                if ($title) {
                    $entry->title($title);
                }
                else {
                    $entry->title('Untitled');
                }
                $entry->text($body);
                $entry->excerpt($summary);
                $entry->basename( MT::Util::make_unique_basename($entry) )
                    if ( $status eq 'new' );

# load SourceFeed by source_rss. If it's excerpted, then transform the $body and $created extended appropriately.
                my $so = Reblog::ReblogSourcefeed->load(
                    {   url       => $source_rss,
                        is_active => '1',
                        blog_id   => $blog_id
                    }
                );

                if ( $so->is_excerpted ) {

                    # chop body with regex
                    $body =~ m|(.*?</p>.*?</p>)(.*)|ms;

                    $entry->text($1);
                    $entry->text_more($2);
                }

                $entry->save || die "ENTRY SAVE FAILURE: " . $entry->errstr;

# NOTE: The new entry save creates an rbd row, per our post_save callback, so we need to sync the ID
# But sometimes, that doesn't happen, but it's overzealous to die.
                my $entry_rb_data;
                if ( $entry_rb_data
                    = Reblog::ReblogData->load( { entry_id => $entry->id } ) )
                {
                    $rb_data->id( $entry_rb_data->id );
                }

                $categories
                    = assign_categories( $entry, $blog, $author, $subjects );

                $rb_data->modified_on($date);
                $rb_data->entry_id( $entry->id );

                $rb_data->save
                    || return $class->error(
                    "RBDATA SAVE FAILURE: " . $rb_data->errstr );
            }

            MT->run_callbacks( 'plugin_reblog_entry_parsed', $entry, $rb_data,
                { parser_type => 'XML::XPath', parser => $xp, node => $node }
            );

            my $eRec = {
                entry       => $entry,
                status      => $status,
                reblog_data => $rb_data,
            };

            push( @entries, $eRec );

        }
    }
    elsif ( $res->http_status != 304 ) {
        if ($sourcefeed) {
            $sourcefeed->increment_error(
                "Failed to fetch RSS feed from $source_rss");
        }
        return $class->error("Failed to fetch RSS feed from $source_rss");
    }
    return (@entries);
}

sub determine_file_type {
    my $url = shift;
    use Switch;
    my $type = 'unknown';
    switch ($url) {
        case /^.*\.mp3$/i     { $type = 'audio/mpeg';               next; }
        case /^.*\.m4a$/i     { $type = 'audio/mp4';                next; }
        case /^.*\.wma$/i     { $type = 'audio/wma';                next; }
        case /^.*\.midi$/i    { $type = 'audio/midi';               next; }
        case /^.*\.aa$/i      { $type = 'audio/aa';                 next; }
        case /^.*\.wav$/i     { $type = 'audio/wav';                next; }
        case /^.*\.ogg$/i     { $type = 'application/ogg';          next; }
        case /^.*\.torrent$/i { $type = 'application/x-bittorrent'; next; }
        case /^.*\.exe$/i     { $type = 'application/octet-stream'; next; }
        case /^.*\.bmp$/i     { $type = 'image/bmp';                next; }
        case /^.*\.jpe?g$/i   { $type = 'image/jpeg';               next; }
        case /^.*\.gif$/i     { $type = 'image/gif';                next; }
        case /^.*\.tiff?$/i   { $type = 'image/tiff';               next; }
        case /^.*\.png$/i     { $type = 'image/png';                next; }
        case /^.*\.mp4/i      { $type = 'video/mp4';                next; }
        case /^.*\.mp4v/i     { $type = 'video/mp4';                next; }
        case /^.*\.mpeg$/i    { $type = 'video/mpeg';               next; }
        case /^.*\.avi$/i     { $type = 'video/msvideo';            next; }
        case /^.*\.mov$/i     { $type = 'video/quicktime';          next; }
        case /^.*\.wmv$/i     { $type = 'video/x-ms-wmv';           next; }
    }
    return $type;
}

sub _clean_html {
    my $text = shift;
    return unless ($text);
    $text =~ s/([^\x00-\x7f])/'&#' . ord($1) . ';'/ge;
    $text = decode_utf8($text);
    return $text;
}

1;
