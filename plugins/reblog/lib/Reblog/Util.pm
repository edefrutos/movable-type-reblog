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
# $Id: Util.pm 17902 2009-04-07 02:16:15Z steve $

package Reblog::Util;
use strict;
use warnings;

use constant DEFAULT_FREQUENCY => 12 * 60 * 60;    # Every twelve hours

sub sourcefeed_postsave {
    my ( $cb, $feed, $original ) = @_;
    use MT::TheSchwartz::Job;
    my $key = 'reblog_' . $feed->id;
    my @jobs = MT::TheSchwartz::Job->load( { uniqkey => $key } );
    foreach my $job (@jobs) {
        $job->remove;
    }
    if ( $feed->is_active ) {
        $feed->inject_worker();
    }
}

sub sourcefeed_presave {
    my ( $cb, $feed, $orig ) = @_;
    if ( !$feed->label ) {
        my $label = $feed->url;
        $label =~ s/^http(s?):\/\///;
        $label =~ s/\/.*//;
        $feed->label($label);
        $orig->label($label);
    }
}

sub sourcefeed_preremove {
    my ( $cb, $feed ) = @_;
    use MT::TheSchwartz::Job;
    my $key = 'reblog_' . $feed->id;
    my @jobs = MT::TheSchwartz::Job->load( { uniqkey => $key } );
    foreach my $job (@jobs) {
        $job->remove;
    }
}

sub entry_preremove {
    my ( $cb, $entry ) = @_;
    use Reblog::ReblogData;
    my @rds = Reblog::ReblogData->load( { entry_id => $entry->id } );
    foreach my $rd (@rds) {
        $rd->remove;
    }
}

sub validate_feed {
    my ( $app, $sourcefeed ) = @_;
    $sourcefeed ||= $app->param('newfeed');
    my $res;
    use Reblog::Import;
    eval {
        $res
            = Reblog::Import->import_entries( $sourcefeed,
            { suppress => 1 } );
    };
    if ($@) {
        $app->{_errstr} = $@;
        return 0;
    }
    if ($res) {
        return 1;
    }
    if ( Reblog::Import->errstr ) {
        $app->{_errstr} = Reblog::Import->errstr;
        return 0;
    }
    else {
        $app->{_errstr} = 'Parses but does not return results (warning only)';
        return 1;
    }
    return 0;
}

sub data_sourcefeedid_load {
    print "Inserting reblog sourcefeed and blog ID data...\n";
    my @rbds = Reblog::ReblogData->load( {} );
    foreach my $rbd (@rbds) {
        my $entry = MT::Entry->load( $rbd->entry_id );
        if ( !$entry ) {
            $rbd->blog_id(0);
            $rbd->sourcefeed_id(0);
            $rbd->save;
            next;
        }
        my @sourcefeeds
            = Reblog::ReblogSourcefeed->load(
            { blog_id => $entry->blog_id, url => $rbd->source_feed_url },
            { limit   => 1 } );
        my $sourcefeed = pop @sourcefeeds;
        if ($sourcefeed) {
            $rbd->sourcefeed_id( $sourcefeed->id );
            $rbd->blog_id( $entry->blog_id );
            $rbd->save;
        }
        else {
            $rbd->blog_id( $entry->blog_id );
            $rbd->sourcefeed_id(0);
            $rbd->save;
        }
    }
    return 1;
}

sub sourcefeed_label_load {
    print "Inserting reblog labels...\n";
    use Reblog::ReblogSourcefeed;
    my @feeds = Reblog::ReblogSourcefeed->load();
    foreach my $feed (@feeds) {
        if ( !$feed->label ) {
            my $label = $feed->url;
            $label =~ s/^http(s?):\/\///;
            $label =~ s/\/.*//;
            unless ($label) {
                $label = "Feed No. " . $feed->id;
                print "Feed with bad label: feed id " . $feed->id;
            }
            $feed->label($label);
            $feed->save;
        }
    }
    return 1;
}

sub initial_sourcefeed_load {

    # -When updating the database-, for each blog in the system,
    # we want to see if we can find a sourceg to insert into
    # mt_reblog_sourcefeed
    my @blogs = MT::Blog->load( {} );
    foreach my $blog (@blogs) {
        my $pref = $blog->id() . "-";
        my $data = MT::PluginData->load(
            { plugin => 'reblog', key => $pref . "source_rss" } );
        if ( defined($data) && $data ) {
            print "Inserting initial feed for blog#"
                . $blog->id() . ": "
                . ${ $data->data() } . "\n";
            my $sourcefeed = new Reblog::ReblogSourcefeed;
            $sourcefeed->blog_id( $blog->id() );
            $sourcefeed->is_active(1);
            $sourcefeed->url( ${ $data->data() } );
            $sourcefeed->save();
        }
    }
    return 1;
}

sub loadreblogparams {
    my ( $cb, $app, $param ) = @_;

    my $id = $param->{'id'};

    my $reblog = Reblog::ReblogData->load( { entry_id => $id } ) or return;

    $param->{'via-link'}   = $app->param('via-link')   || $reblog->via_link;
    $param->{'annotation'} = $app->param('annotation') || $reblog->annotation;
    $param->{'source-title'} = $app->param('source-title')
        || $reblog->source_title;
    $param->{'source-link'} = $app->param('source-link')
        || $reblog->source_url;
    $param->{'thumbnail-url'} = $app->param('thumbnail-url')
        || $reblog->thumbnail_url;
    $param->{'thumbnail-link'} = $app->param('thumbnail-link')
        || $reblog->thumbnail_link;
    $param->{'enclosure_url'} = $app->param('enclosure_url')
        || $reblog->enclosure_url;
    $param->{'enclosure_length'} = $app->param('enclosure_length')
        || $reblog->enclosure_length;
    $param->{'enclosure_type'} = $app->param('enclosure_type')
        || $reblog->enclosure_type;

}

sub param_preview_entry {
    my ( $cb, $app, $param ) = @_;

    $param->{entry_loop} = [
        @{ $param->{entry_loop} },
        map { { data_name => $_, data_value => $app->param($_) } }
            qw(via-link source-title source-link thumbnail-url thumbnail-link enclosure_url),
    ];
}

sub reblog_save {
    my ( $reblog, $cb, $app, $obj, $original ) = @_;

    my ( $bi, $vl, $st, $sl, $tl, $tu, $eu, $el, $et, $an );
    my ($blogid,        $via_link,         $source_title,
        $source_link,   $thumbnail_link,   $thumbnail_url,
        $enclosure_url, $enclosure_length, $enclosure_type,
        $annotation
    );

    my $q = $app->{'query'};
    eval {
        $bi               = $q->{blog_id};
        $blogid           = @$bi[0];
        $vl               = $q->{via_link};
        $via_link         = @$vl[0];
        $st               = $q->{source_title};
        $source_title     = @$st[0];
        $sl               = $q->{source_link};
        $source_link      = @$sl[0];
        $tl               = $q->{thumbnail_link};
        $thumbnail_link   = @$tl[0];
        $tu               = $q->{thumbnail_url};
        $thumbnail_url    = @$tu[0];
        $eu               = $q->{enclosure_url};
        $enclosure_url    = @$eu[0];
        $el               = $q->{enclosure_length};
        $enclosure_length = @$el[0];
        $et               = $q->{enclosure_type};
        $enclosure_type   = @$et[0];
        $an               = $q->{annotation};
        $annotation       = @$an[0];
    };

    $reblog = Reblog::ReblogData->load( { entry_id => $obj->id } );

    if ($reblog) {
        $reblog->via_link($via_link);
        $reblog->source_url($source_link);
        $reblog->source_title($source_title);
        $reblog->thumbnail_link($thumbnail_link);
        $reblog->thumbnail_url($thumbnail_url);
        $reblog->enclosure_url($enclosure_url);
        $reblog->enclosure_type($enclosure_type);
        $reblog->enclosure_length($enclosure_length);
        $reblog->annotation($annotation);

        $reblog->save;
    }
    else {

        # create a new reblog row
        my $entry = MT::Entry->load( { id => $obj->id } );

        my $user = $app->user;

        my $rbd = Reblog::ReblogData->new;
        if ($via_link) {
            $rbd->via_link($via_link);
        }
        $rbd->source_url($source_link);
        if ($source_title) {
            $rbd->source_title($source_title);
        }
        else {
            $rbd->source_title( $entry->title );
        }
        $rbd->thumbnail_link($thumbnail_link);
        $rbd->thumbnail_url($thumbnail_url);
        $rbd->enclosure_url($enclosure_url);
        $rbd->enclosure_length($enclosure_length);
        $rbd->enclosure_type($enclosure_type);

        $rbd->entry_id( $obj->id );
        $rbd->orig_created_on( $entry->created_on );
        $rbd->created_on( $entry->created_on );

        $rbd->source_author( $user->nickname );
        $rbd->link($source_link);
        $rbd->guid( $entry->atom_id );
        $rbd->source($source_title);
        $rbd->source_feed_url('#');
        $rbd->sourcefeed_id(0);
        $rbd->blog_id( $obj->blog_id );
        $rbd->save;
    }
}

sub entry_panel {
    return <<HTML;
<div id="reblog-panel-off" style="padding: 10px 0 10px 15px; background-color: #FAFCFF; border: 1px solid #CDD4EB;">
    <p><a href="javascript:var off = document.getElementById('reblog-panel-off').style.display = 'none'; var on = document.getElementById('reblog-panel').style.display = '';">Alter Reblog Values</a>
</div>
<div id="reblog-panel" style="padding: 10px 0 10px 15px; background-color: #FAFCFF; border: 1px solid #C5D4EB; display: none;">
<h4>Reblog Fields:</h4>
<div class="field">
        <div class="field-header">
                <label for="annotation">Annotation</label>
        </div>
        <div class="field-wrapper">
                <input type="text" name="annotation" id="annotation" value="<TMPL_VAR NAME=ANNOTATION>" size="50" />
    </div>
</div>
<div class="field">
        <div class="field-header">
                <label for="source-title">Source Title</label>
        </div>
        <div class="field-wrapper">
                <input type="text" name="source_title" id="source-title" value="<TMPL_VAR NAME=SOURCE_TITLE>" size="50" />
        </div>
</div>
<div class="field">
        <div class="field-header">
                <label for="source-link">Source Link</label>
        </div>
        <div class="field-wrapper"><input type="text" name="source_link" id="source-link" value="<TMPL_VAR NAME=SOURCE_LINK>" size="50" /></div>
</div>
<div class="field">
        <div class="field-header">
                <label for="via">Via</label>
        </div>
        <div class="field-wrapper"><input type="text" name="via_link" id="via" value="<TMPL_VAR NAME=VIA_LINK>" size="50" /></div>
</div>
<div class="field">
        <div class="field-header">
                <label for="thumbnail-url">Thumbnail Img URL</label>
        </div>
        <div class="field-wrapper"><input type="text" name="thumbnail_url" id="thumbnail-url" value="<TMPL_VAR NAME=THUMBNAIL_URL>" size="50" /></div>
</div>
<div class="field">
                <div class="field-header">
                        <label for="thumbnail-link">Thumbnail Link</label>
                </div>
                <div class="field-wrapper"><input type="text" name="thumbnail_link" id="thumbnail-link" value="<TMPL_VAR NAME=THUMBNAIL_LINK>" size="50" /></div>
</div>
<div class="field">
        <div class="field-header">
                <label for="enclosure">Enclosure URL</label>
        </div>
        <div class="field-wrapper"><input type="text" name="enclosure_url" id="enclosure" value="<TMPL_VAR NAME=ENCLOSURE_URL ESCAPE=HTML>" size="50" /></div>
</div>
<p><a href="javascript:var off = document.getElementById('reblog-panel').style.display = 'none'; var on = document.getElementById('reblog-panel-off').style.display = '';">Hide Reblog Values</a>
</div>
HTML
}

sub patch_rebuild_deleted_entry {
    my ($cb) = @_;
    require MT::WeblogPublisher;
    local $SIG{__WARN__} = sub { };
    my $orig_rebuild_deleted_entry
        = \&MT::WeblogPublisher::rebuild_deleted_entry;
    *MT::WeblogPublisher::rebuild_deleted_entry = sub {
        my $mt    = shift;
        my $app   = MT->instance;
        my %param = @_;
        my $entry = $param{Entry}
            or return $mt->error(
            MT->translate( "Parameter '[_1]' is required", 'Entry' ) );
        require MT::Entry;
        $entry = MT::Entry->load($entry) unless ref $entry;
        return unless $entry;
        my $author_id;

        if ( $entry->author && ( $entry->author_id > 0 ) ) {
            $author_id = $entry->author->id;
        }

        my $blog;
        unless ( $blog = $param{Blog} ) {
            require MT::Blog;
            my $blog_id = $entry->blog_id;
            $blog = MT::Blog->load($blog_id)
                or return $mt->error(
                MT->translate(
                    "Load of blog '[_1]' failed: [_2]", $blog_id,
                    MT::Blog->errstr
                )
                );
        }

        my %rebuild_recip;
        my $at = $blog->archive_type;
        my @at;
        if ( $at && $at ne 'None' ) {
            my @at_orig = split( /,/, $at );
            @at = grep { $_ ne 'Individual' && $_ ne 'Page' } @at_orig;
        }

        # Remove Individual archive file.
        if ( $app->config('DeleteFilesAtRebuild') ) {
            $mt->remove_entry_archive_file( Entry => $entry, );
        }

        # Remove Individual fileinfo records.
        $mt->remove_fileinfo(
            ArchiveType => 'Individual',
            Blog        => $blog->id,
            Entry       => $entry->id
        );

        require MT::Util;
        for my $at (@at) {
            my $archiver = $mt->archiver($at);
            next unless $archiver;

            my ( $start, $end ) = $archiver->date_range( $entry->authored_on )
                if $archiver->date_based() && $archiver->can('date_range');

            # Remove archive file if archive file has no entries.
            if ( $archiver->category_based() ) {
                my $categories = $entry->categories();
                for my $cat (@$categories) {
                    if (( $archiver->can('archive_entries_count') )
                        && ($archiver->archive_entries_count( $blog, $at,
                                $entry, $cat ) == 1
                        )
                        )
                    {
                        $mt->remove_fileinfo(
                            ArchiveType => $at,
                            Blog        => $blog->id,
                            Category    => $cat->id,
                            (   $archiver->date_based()
                                ? ( startdate => $start )
                                : ()
                            ),
                        );
                        if ( $app->config('DeleteFilesAtRebuild') ) {
                            $mt->remove_entry_archive_file(
                                Entry       => $entry,
                                ArchiveType => $at,
                                Category    => $cat,
                            );
                        }
                    }
                    else {
                        if ( $app->config('RebuildAtDelete') ) {
                            if ( $archiver->date_based() ) {
                                $rebuild_recip{$at}{ $cat->id }
                                    { $start . $end }{'Start'} = $start;
                                $rebuild_recip{$at}{ $cat->id }
                                    { $start . $end }{'End'} = $end;
                                $rebuild_recip{$at}{ $cat->id }
                                    { $start . $end }{'File'}
                                    = MT::Util::archive_file_for(
                                    $entry, $blog, $at, $cat,
                                    undef,  undef, undef
                                    );
                            }
                            else {
                                $rebuild_recip{$at}{ $cat->id }{id}
                                    = $cat->id;
                                $rebuild_recip{$at}{ $cat->id }{'File'}
                                    = MT::Util::archive_file_for(
                                    $entry, $blog, $at, $cat,
                                    undef,  undef, undef
                                    );
                            }
                        }
                    }
                }
            }
            else {
                if (( $archiver->can('archive_entries_count') )
                    && ($archiver->archive_entries_count(
                            $blog, $at, $entry
                        ) == 1
                    )
                    )
                {

                    # Remove archives fileinfo records.
                    $mt->remove_fileinfo(
                        ArchiveType => $at,
                        Blog        => $blog->id,
                        (   $archiver->author_based()
                            ? ( author_id => $author_id )
                            : ()
                        ),
                        (   $archiver->date_based() ? ( startdate => $start )
                            : ()
                        ),
                    );
                    if ( $app->config('DeleteFilesAtRebuild') ) {
                        $mt->remove_entry_archive_file(
                            Entry       => $entry,
                            ArchiveType => $at
                        );
                    }
                }
                else {
                    if ( $app->config('RebuildAtDelete') ) {
                        if ( $archiver->author_based() && $author_id ) {
                            if ( $archiver->date_based() ) {
                                $rebuild_recip{$at}{ $entry->author->id }
                                    { $start . $end }{'Start'} = $start;
                                $rebuild_recip{$at}{ $entry->author->id }
                                    { $start . $end }{'End'} = $end;
                                $rebuild_recip{$at}{ $entry->author->id }
                                    { $start . $end }{'File'}
                                    = MT::Util::archive_file_for( $entry,
                                    $blog, $at, undef, undef, undef,
                                    $entry->author );
                            }
                            else {
                                $rebuild_recip{$at}{ $entry->author->id }{id}
                                    = $entry->author->id;
                                $rebuild_recip{$at}{ $entry->author->id }
                                    {'File'}
                                    = MT::Util::archive_file_for( $entry,
                                    $blog, $at, undef, undef, undef,
                                    $entry->author );
                            }
                        }
                        elsif ( $archiver->date_based() ) {
                            $rebuild_recip{$at}{ $start . $end }{'Start'}
                                = $start;
                            $rebuild_recip{$at}{ $start . $end }{'End'}
                                = $end;
                            $rebuild_recip{$at}{ $start . $end }{'File'}
                                = MT::Util::archive_file_for(
                                $entry, $blog, $at, undef,
                                undef,  undef, undef
                                );
                        }
                        if ( my $prev = $entry->previous(1) ) {
                            $rebuild_recip{Individual}{ $prev->id }{id}
                                = $prev->id;
                            $rebuild_recip{Individual}{ $prev->id }{'File'}
                                = MT::Util::archive_file_for( $prev, $blog,
                                'Individual', undef, undef, undef, undef );
                        }
                        if ( my $next = $entry->next(1) ) {
                            $rebuild_recip{Individual}{ $next->id }{id}
                                = $next->id;
                            $rebuild_recip{Individual}{ $next->id }{'File'}
                                = MT::Util::archive_file_for( $next, $blog,
                                'Individual', undef, undef, undef, undef );
                        }
                    }
                }
            }
        }

        return %rebuild_recip;
        }
}

sub do_import {
    use Reblog::ReblogData;
    use Reblog::ReblogSourcefeed;
    use Reblog::Import;
    use MT;
    use MT::Category;
    use MT::Template::Context;
    use MT::Object;
    use MT::Util qw( encode_html );
    use MT::WeblogPublisher;
    my ( $app, $auth, $blog, @sources ) = @_;
    my $scheduled = 0;
    my $pub       = MT::WeblogPublisher->new;
    my $blog_id   = $blog->id;
    my $plugin    = MT->component('reblog');

    if ( $auth && $blog ) {
        $scheduled = 1;
    }
    else {
        my $default_author = $plugin->get_config_value( 'default_author',
            'blog:' . $blog_id );
        unless ($default_author) {
            $default_author = 0;
        }
        else {
            unless ( $default_author =~ m|^\d+$| ) {
                $default_author = 0;
            }
        }
        if ( $default_author == 0 ) {
            $auth = -1;
        }
        else {
            $auth = MT::Author->load($default_author);
            unless ($auth) {
                return $app->error('Could not load default author for blog');
            }
        }
    }
    my $feedcount = 0;

    my @sourcefeeds;
    if (@sources) {
        @sourcefeeds = @sources;
    }
    else {
        return $app->error('No sourcefeeds selected');
    }
    our $nBuilt = 0;
    my $wants_rebuild = $plugin->get_config_value( 'rebuild_individual',
        'blog:' . $blog_id );
    my $ttl = MT->config('ReblogCacheTTL');
    foreach my $sourcefeed (@sourcefeeds) {
        my (@entries);

        # do we need to do more about catching/reporting errors here?
        eval {
            @entries = Reblog::Import->import_entries( $sourcefeed,
                { author => $auth, blog_id => $blog->id, cache_ttl => $ttl }
            );
        };
        if ( $@ or Reblog::Import->errstr ) {
            next;
        }
        $feedcount++;
        $sourcefeed->has_error(0);
        $sourcefeed->consecutive_failures(0);
        $sourcefeed->epoch_last_read( time() );
        $sourcefeed->save;
        foreach my $eRec (@entries) {
            if ( $eRec->{status} ne 'old' ) {
                $nBuilt++;
                if ($wants_rebuild) {
                    $pub->rebuild_entry(
                        Entry => $eRec->{entry},
                        Blog  => $blog
                    );
                }
            }
            elsif ( $eRec->{status} eq 'update' ) {
                my $existingEntry = new MT::Entry;
                $existingEntry->load( $eRec->{entry} );

                # Or if it's an existing entry that has been published
                if (   $existingEntry
                    && $existingEntry->status == MT::Entry::RELEASE() )
                {
                    if ($wants_rebuild) {
                        $pub->rebuild_entry(
                            Entry => $eRec->{entry},
                            Blog  => $blog
                        );
                    }
                    $nBuilt++;
                }    # /if blog->status_default == RELEASE
            }    # /if eRec->{status} ne 'old'
        }    # /foreach eRec
    }    # / foreach $sourcefeed
    if ( $nBuilt > 0 ) {
        $pub->rebuild_indexes( Blog => $blog );
        $pub->rebuild_categories( Blog => $blog );
    }
    if ($scheduled) {
        Reblog::Import->error(undef);
        undef $@;
        return $nBuilt;
    }
    else {
        my $str;
        my $entries = 'entries';
        if ( $nBuilt == 1 ) {
            $entries = 'entry';
        }
        if ( $feedcount == 1 ) {
            $str
                = "$feedcount feed read successfully; $nBuilt new or updated $entries found.";
        }
        else {
            $str
                = "$feedcount feeds read successfully; $nBuilt new or updated $entries found.";
        }
        Reblog::Import->error(undef);
        undef $@;
        return $str;
    }
}

1;
