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
# $Id: Tags.pm 18705 2009-04-19 16:54:22Z steve $

package Reblog::Tags;
use strict;
use warnings;
use Switch;

sub _hdlr_if_reblog {
    my ( $ctx, $args ) = @_;
    my ( $blog, $blog_id );
    $blog_id = $args->{blog_id};
    if ($blog_id) {
        use MT::Blog;
        $blog = MT::Blog->load($blog_id);
    }
    else {
        $blog = $ctx->stash('blog');
    }
    ($blog) or return $ctx->error('No blog in context');
    require Reblog::ReblogSourcefeed;
    my @sf = Reblog::ReblogSourcefeed->load(
        { blog_id => $blog->id, is_active => 1 } );
    return scalar @sf;
}

sub _hdlr_if_not_reblog {
    my ( $ctx, $args ) = @_;
    my ( $blog, $blog_id );
    $blog_id = $args->{blog_id};
    if ($blog_id) {
        use MT::Blog;
        $blog = MT::Blog->load($blog_id);
    }
    else {
        $blog = $ctx->stash('blog');
    }
    ($blog) or return $ctx->error('No blog in context');
    require Reblog::ReblogSourcefeed;
    my @sf = Reblog::ReblogSourcefeed->load(
        { blog_id => $blog->id, is_active => 1 } );
    return ( !scalar @sf );
}

sub _hdlr_entry_if_reblog {
    my ( $ctx, $args ) = @_;

    my $entry = $ctx->stash('entry')
        or return $ctx->_no_entry_error('EntryIfReblog');

    require Reblog::ReblogData;
    my $rbd = Reblog::ReblogData->load( { entry_id => $entry->id } )
        or return '';
    return defined($rbd) && $rbd->id;
}

sub _hdlr_entry_if_has_reblog_author {
    my ( $ctx, $args ) = @_;

    my $entry = $ctx->stash('entry')
        or return $ctx->_no_entry_error('EntryIfHasReblogAuthor');

    require Reblog::ReblogData;
    my $rbd = Reblog::ReblogData->load( { entry_id => $entry->id } )
        or return '';
    return defined($rbd) && $rbd && $rbd->source_author;
}

sub _hdlr_entry_reblog_source {
    my ( $ctx, $args ) = @_;

    my $entry = $ctx->stash('entry')
        or return $ctx->_no_entry_error('EntryReblogSource');

    require Reblog::ReblogData;
    my $rbd = Reblog::ReblogData->load( { entry_id => $entry->id } )
        or return '';
    defined($rbd) && $rbd && $rbd->source ? $rbd->source : '';
}

sub _hdlr_entry_reblog_source_url {
    my ( $ctx, $args ) = @_;

    my $entry = $ctx->stash('entry')
        or return $ctx->_no_entry_error('EntryReblogSourceURL');

    require Reblog::ReblogData;
    my $rbd = Reblog::ReblogData->load( { entry_id => $entry->id } )
        or return '';
    defined($rbd) && $rbd && $rbd->source_url ? $rbd->source_url : '';
}

sub _hdlr_entry_reblog_source_feed_url {
    my ( $ctx, $args ) = @_;

    my $entry = $ctx->stash('entry')
        or return $ctx->_no_entry_error('EntryReblogSourceFeedURL');

    require Reblog::ReblogData;
    my $rbd = Reblog::ReblogData->load( { entry_id => $entry->id } )
        or return '';
    defined($rbd)
        && $rbd
        && $rbd->source_feed_url ? $rbd->source_feed_url : '';
}

sub _hdlr_entry_reblog_link {
    my ( $ctx, $args ) = @_;

    my $entry = $ctx->stash('entry')
        or return $ctx->_no_entry_error('EntryReblogSourceLink');

    require Reblog::ReblogData;
    my $rbd = Reblog::ReblogData->load( { entry_id => $entry->id } )
        or return '';
    defined($rbd) && $rbd ? $rbd->link : '';
}

sub _hdlr_entry_reblog_sourcefeed_id {
    my ( $ctx, $args ) = @_;

    my $entry = $ctx->stash('entry')
        or return $ctx->_no_entry_error('EntryReblogSourcefeedId');

    require Reblog::ReblogData;
    my $rbd = Reblog::ReblogData->load( { entry_id => $entry->id } )
        or return '';
    defined($rbd) && $rbd ? $rbd->sourcefeed_id : '';
}

sub _hdlr_entry_reblog_via_link {
    my ( $ctx, $args ) = @_;

    my $entry = $ctx->stash('entry')
        or return $ctx->_no_entry_error('EntryReblogViaLink');

    require Reblog::ReblogData;
    my $rbd = Reblog::ReblogData->load( { entry_id => $entry->id } )
        or return '';
    defined($rbd) && $rbd ? $rbd->via_link ? $rbd->via_link : '' : '';
}

sub _hdlr_entry_reblog_orig_date {
    my ( $ctx, $args ) = @_;

    my $entry = $ctx->stash('entry')
        or return $ctx->_no_entry_error('MTEntryReblogSourcePublishedDate');

    require Reblog::ReblogData;
    my $rbd = Reblog::ReblogData->load( { entry_id => $entry->id } )
        or return '';

    my $att = $_[1];
    eval {
        $args->{ts}
            = (
            $rbd ? MT::Object->driver()->db2ts( $rbd->orig_created_on ) : 0 );
    };
    if ($@) {
        $args->{ts} = $rbd->orig_created_on;
    }

    defined($rbd) && $rbd
        ? MT::Template::Context::_hdlr_date( $_[0], $args )
        : '';
}

sub _hdlr_entry_reblog_source_author {
    my ( $ctx, $args ) = @_;

    my $entry = $ctx->stash('entry')
        or return $ctx->_no_entry_error('MTEntryReblogSourceAuthor');

    require Reblog::ReblogData;
    my $rbd = Reblog::ReblogData->load( { entry_id => $entry->id } )
        or return '';
    defined($rbd) && $rbd ? $rbd->source_author : '';
}

sub _hdlr_entry_reblog_identifier {
    my ( $ctx, $args ) = @_;

    my $entry = $ctx->stash('entry')
        or return $ctx->_no_entry_error('MTEntryReblogIdentifier');

    require Reblog::ReblogData;
    my $rbd = Reblog::ReblogData->load( { entry_id => $entry->id } )
        or return '';

    defined($rbd) && $rbd ? $rbd->guid : '';
}

sub _hdlr_entry_reblog_thumbnail_url {
    my $ctx    = shift;
    my $args   = shift;
    my $e      = $ctx->stash('entry') or return;
    my $reblog = Reblog::ReblogData->load( { entry_id => $e->id } );
    ( $reblog && $reblog->thumbnail_url )
        ? return $reblog->thumbnail_url
        : return '';
}

sub _hdlr_entry_reblog_thumbnail_link {
    my $ctx    = shift;
    my $args   = shift;
    my $e      = $ctx->stash('entry') or return;
    my $reblog = Reblog::ReblogData->load( { entry_id => $e->id } );
    ( $reblog && $reblog->thumbnail_link )
        ? return $reblog->thumbnail_link
        : return '#';
}

sub _hdlr_entry_reblog_orig_source_title {
    my $ctx    = shift;
    my $args   = shift;
    my $e      = $ctx->stash('entry') or return;
    my $reblog = Reblog::ReblogData->load( { entry_id => $e->id } );
    ( $reblog && $reblog->source_title )
        ? return $reblog->source_title
        : return '';
}

sub _hdlr_entry_reblog_annotation {
    my $ctx    = shift;
    my $args   = shift;
    my $e      = $ctx->stash('entry') or return;
    my $reblog = Reblog::ReblogData->load( { entry_id => $e->id } );
    ( $reblog && $reblog->annotation )
        ? return $reblog->annotation
        : return '';
}

sub _hdlr_entry_reblog_favicon {
    my $ctx    = shift;
    my $args   = shift;
    my $e      = $ctx->stash('entry') or return;
    my $reblog = Reblog::ReblogData->load( { entry_id => $e->id } );
    return unless $reblog;
    my $sf = Reblog::ReblogSourcefeed->load( $reblog->sourcefeed_id );
    ( $sf && $sf->favicon_url )
        ? return $sf->favicon_url
        : return '';
}

sub _hdlr_entry_reblog_enclosure {
    my $ctx    = shift;
    my $args   = shift;
    my $e      = $ctx->stash('entry') or return;
    my $reblog = Reblog::ReblogData->load( { entry_id => $e->id } );

    if ( $reblog && $reblog->enclosure_url ) {
        return $reblog->enclosure_url;
    }
    else {
        return '';
    }
}

sub _hdlr_entry_reblog_enclosure_mimetype {
    my $ctx    = shift;
    my $args   = shift;
    my $e      = $ctx->stash('entry') or return;
    my $reblog = Reblog::ReblogData->load( { entry_id => $e->id } );

    if ( $reblog && $reblog->enclosure_url ) {
        return $reblog->enclosure_type;
    }
    else {
        return '';
    }
}

sub _hdlr_entry_reblog_enclosure_length {
    my $ctx    = shift;
    my $args   = shift;
    my $e      = $ctx->stash('entry') or return;
    my $reblog = Reblog::ReblogData->load( { entry_id => $e->id } );

    if ( $reblog && $reblog->enclosure_length ) {
        return $reblog->enclosure_length;
    }
    elsif ($reblog) {
        require LWP::UserAgent;
        my $ua      = LWP::UserAgent->new();
        my $headers = $ua->head( $reblog->enclosure_url );
        if ( $headers && $headers->content_length ) {
            $reblog->enclosure_length( $headers->content_length );
        }
        else {
            $reblog->enclosure_length(-1)
                ;  # set it to a nonzero value so we don't try to get it again
        }
        $reblog->save;
        return $reblog->enclosure_length;
    }
    else {
        return '';
    }
}

sub _hdlr_reblog_enclosure_entries {
    my ( $ctx, $args, $cond ) = @_;

    my $blog_id = $ctx->stash('blog_id');

    require MT::Entry;
    require Reblog::ReblogData;
    my @entries = MT::Entry->load(
        { blog_id => $blog_id, status => MT::Entry::RELEASE },
        { join => Reblog::ReblogData->join_on('entry_id') }
    );

    @entries = grep {
        my $rdb = Reblog::ReblogData->load( { entry_id => $_->id } );
        $rdb->enclosure_url;
    } @entries;

    return '' if ( !scalar @entries );

    my $out     = "";
    my $builder = $ctx->stash('builder');
    my $tokens  = $ctx->stash('tokens');
    foreach my $entry (@entries) {
        $ctx->stash( "entry", $entry );
        $out .= $builder->build( $ctx, $tokens, $cond );
    }
    return $out;
}

sub _hdlr_reblog_entries {
    my ( $ctx, $args, $cond ) = @_;
    my ( $limit, $offset, $sourcefeed );
    my $res     = '';
    my $builder = $ctx->stash('builder');
    my $tokens  = $ctx->stash('tokens');
    my $blog_id = $ctx->stash('blog_id');

    if ( $args->{sourcefeed} ) {
        $sourcefeed = $args->{sourcefeed};
    }
    elsif ( $ctx->stash('reblog_source') ) {
        my $source = $ctx->stash('reblog_source');
        $sourcefeed = $source->{feed_url};
    }
    else {
        return;
    }
    my @entries;
    $offset = $args->{offset} ? $args->{offset} : 0;

    my %query_args;
    $query_args{'sort'}      = 'orig_created_on';
    $query_args{'direction'} = 'descend';
    $query_args{'offset'}    = $offset;

    if ( $args->{limit} ) {
        $query_args{'limit'} = $args->{limit};
    }
    elsif ( $args->{lastn} ) {
        $query_args{'limit'} = $args->{lastn};
    }
    @entries = MT::Entry->load(
        { blog_id => $blog_id },
        {   'join' => [
                'Reblog::ReblogData', 'entry_id',
                { source_feed_url => $sourcefeed }, \%query_args
            ]
        }
    );

    my $i = 0;
    foreach my $entry (@entries) {
        local $ctx->{__stash}{entry}         = $entry;
        local $ctx->{current_timestamp}      = $entry->authored_on;
        local $ctx->{modification_timestamp} = $entry->modified_on;

        my $vars = $ctx->{__stash}{vars} ||= {};
        local $vars->{__first__}   = !$i;
        local $vars->{__last__}    = !defined $entries[ $i + 1 ];
        local $vars->{__odd__}     = ( $i % 2 ) == 0;             # 0-based $i
        local $vars->{__even__}    = ( $i % 2 ) == 1;
        local $vars->{__counter__} = $i + 1;

        defined(
            my $out = $builder->build(
                $ctx, $tokens,
                {   EntryIfExtended => $entry->text_more ? 1 : 0,
                    EntryIfAllowComments => $entry->allow_comments,
                    EntryIfAllowPings    => $entry->allow_pings
                }
            )
        ) or return $ctx->error( $ctx->errstr );
        $res .= $out;
        $i++;
    }
    $res;
}

sub _hdlr_reblog_sourcefeeds {
    my ( $ctx, $args, $cond ) = @_;

    my $res     = '';
    my $builder = $ctx->stash('builder');
    my $tokens  = $ctx->stash('tokens');
    my $blog    = $ctx->stash('blog');

    my $blog_id;
    if ( $args->{blog_id} ) {
        $blog_id = $args->{blog_id};
    }
    else {
        ($blog) or return $ctx->error('No blog in context');
        $blog_id = $blog->id;
    }

    my $arguments;
    $arguments->{blog_id} = $blog_id;
    if ( $args->{active_only} ) {
        $arguments->{is_active} = 1;
    }
    my $sourcefeed_iter = Reblog::ReblogSourcefeed->load_iter( $arguments, );
    my @sources;
    while ( my $sourcefeed = $sourcefeed_iter->() ) {
        my ( $title, $url ) = ( $sourcefeed->label, $sourcefeed->url );
        my $last
            = Reblog::ReblogData->load( { sourcefeed_id => $sourcefeed->id },
            { limit => 1 } );
        if ($last) {
            $title = $last->source;
            $url   = $last->source_url;
        }
        push @sources,
            {
            id         => $sourcefeed->id,
            url        => $url,
            feed_url   => $sourcefeed->url,
            label      => $sourcefeed->label,
            title      => $title,
            sourcefeed => $sourcefeed,
            };
    }
    my ( $limit, $offset ) = ( 0, 0 );
    if ( $args->{offset} and $args->{offset} =~ m/^\d+$/ ) {
        $offset = $args->{offset};
    }
    if ( $args->{limit} and $args->{limit} =~ m/^\d+$/ ) {
        $limit = $args->{limit};
    }
    my @slice;
    if ($limit) {
        my $end = $offset + $limit - 1;
        @slice = @sources[ $offset .. $end ];
    }
    else {
        my $end = scalar @sources - 1;
        @slice = @sources[ $offset .. $end ];
    }
    if ( $args->{sort} ) {
        switch ( $args->{sort} ) {
            case q{title} {
                @slice = map { $_->[0] }
                    sort { $a->[1] cmp $b->[1] }
                    map { [ $_, $_->{title} ] } @slice;
            }
            case q{label} {
                @slice = map { $_->[0] }
                    sort { $a->[1] cmp $b->[1] }
                    map { [ $_, $_->{label} ] } @slice;
            }
            case q{last_checked} {
                @slice = map { $_->[0] }
                    sort {
                    return 1 if ( ! defined $a->[1] );
                    return -1  if ( ! defined $b->[1] );
                    $a->[1] <=> $b->[1]
                    }
                    map { [ $_, $_->{sourcefeed}->epoch_last_read ] } @slice;
            }
        }
    }
    my $i = 0;
    foreach my $source (@slice) {
        next if ( !defined $source );
        my $vars = $ctx->{__stash}{vars} ||= {};
        local $vars->{__first__}   = !$i;
        local $vars->{__last__}    = !defined $slice[ $i + 1 ];
        local $vars->{__odd__}     = ( $i % 2 ) == 0;             # 0-based $i
        local $vars->{__even__}    = ( $i % 2 ) == 1;
        local $vars->{__counter__} = $i + 1;
        $ctx->stash( 'reblog_source', $source );
        defined( my $out = $builder->build( $ctx, $tokens ) )
            or return $ctx->error( $ctx->errstr );
        $res .= $out;
        $i++;
    }
    return $res;
}

sub _hdlr_reblog_source_url {
    my $ctx = shift;
    my $f   = $ctx->stash('reblog_source');
    return $f->{url} ? $f->{url} : '';
}

sub _hdlr_reblog_source_favicon {
    my $ctx = shift;
    my $f   = $ctx->stash('reblog_source');
    return unless $f->{id};
    my $sf = Reblog::ReblogSourcefeed->load( $f->{id} );
    return unless $sf;
    return $sf->favicon_url;
}

sub _hdlr_reblog_source_feed_url {
    my $ctx = shift;
    my $f   = $ctx->stash('reblog_source');
    return $f->{feed_url} ? $f->{feed_url} : '';
}

sub _hdlr_reblog_source_id {
    my $ctx = shift;
    my $f   = $ctx->stash('reblog_source');
    return $f->{id} ? $f->{id} : '';
}

sub _hdlr_reblog_source {
    my $ctx = shift;
    my $f   = $ctx->stash('reblog_source');
    return $f->{title} ? $f->{title} : '';
}

sub _hdlr_reblog_favicon {
    my $ctx  = shift;
    my $args = shift;
    my $f    = $ctx->stash('reblog_source');
    if ($f) {
        my $sf = Reblog::ReblogSourcefeed->load( $f->{id} );
        return unless $sf;
        return $sf->favicon_url;
    }
    else {
        my $id = $args->{id};
        return unless $id;
        my $sf = Reblog::ReblogSourcefeed->load($id);
        return unless $sf;
        return $sf->favicon_url;
    }
}

1;
