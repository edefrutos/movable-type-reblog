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
# $Id: CMS.pm 17902 2009-04-07 02:16:15Z steve $

package Reblog::CMS;
use strict;
use warnings;

sub config {
    my $app   = shift;
    my $perms = $app->permissions;
    unless ( check_perms( $perms, $app->user, 'reblog' ) ) {
        return $app->error('You cannot configure Reblog for this blog.');
    }
    my $plugin = MT->component('reblog');
    my $tmpl   = $plugin->load_tmpl('config.tmpl');
    my $param;
    use MT::Blog;
    my $blog = MT::Blog->load( $app->param('blog_id') );
    if ( $app->param('save') ) {
        my $frequency = $app->param('frequency');
        if ( !$frequency || $frequency < 15 * 60 ) {
            $frequency = 15 * 60;
        }
        $frequency = sprintf( '%u', $frequency );
        $plugin->set_config_value(
            'frequency',
            $app->param('frequency'),
            'blog:' . $blog->id
        );
        $plugin->set_config_value(
            'default_author',
            $app->param('reblog_author'),
            'blog:' . $blog->id
        );
        if (   $app->param('max_failures') =~ m/^\d+$/
            && $app->param('max_failures') )
        {
            my $max_failures = $app->param('max_failures');
            ( $max_failures < 1 ) && ( $max_failures = 1 );
            $plugin->set_config_value(
                'max_failures',
                $max_failures,
                'blog:' . $blog->id
            );
        }
        if ( $app->param('import_categories') ) {
            $plugin->set_config_value( 'import_categories', 1,
                'blog:' . $blog->id );
        }
        else {
            $plugin->set_config_value( 'import_categories', 0,
                'blog:' . $blog->id );
        }
        if ( $app->param('rebuild_individual') ) {
            $plugin->set_config_value( 'rebuild_individual', 1,
                'blog:' . $blog->id );
        }
        else {
            $plugin->set_config_value( 'rebuild_individual', 0,
                'blog:' . $blog->id );
        }
        if ( $app->param('display_entry_details') ) {
            $plugin->set_config_value( 'display_entry_details', 1,
                'blog:' . $blog->id );
        }
        else {
            $plugin->set_config_value( 'display_entry_details', 0,
                'blog:' . $blog->id );
        }
    }
    use MT::Author;
    my $author_iter = MT::Author->load_iter(
        {},
        {   sort => 'name',
            join => MT::Permission->join_on(
                'author_id',
                { blog_id => $blog->id },
                { unique  => 1 }
            )
        }
    );
    my @author_loop;
    while ( my $a = $author_iter->() ) {
        next unless ( $a->permissions($blog)->has('publish_post') );
        my $row;
		my $shown = $a->name;
		if ( $a->nickname ) { $shown .= ' (' . $a->nickname . ')'; }
        $row->{author_name} = $shown;
        $row->{author_id}   = $a->id;
        push @author_loop, $row;
    }
    $param->{author_loop}    = \@author_loop;
    $param->{frequency_loop} = [
        { frequency => 'Every 24 hours',   seconds => 24 * 60 * 60 },
        { frequency => 'Every 12 hours',   seconds => 12 * 60 * 60 },
        { frequency => 'Every 6 hours',    seconds => 6 * 60 * 60 },
        { frequency => 'Every 3 hours',    seconds => 3 * 60 * 60 },
        { frequency => 'Hourly',           seconds => 60 * 60 },
        { frequency => 'Every 30 minutes', seconds => 30 * 60 },
        { frequency => 'Every 15 minutes', seconds => 15 * 60 },
    ];
    unless ($blog) {
        return $app->error('Blog not found');
    }
    $param->{blog_name} = $blog->name;
    $param->{display_entry_details}
        = $plugin->get_config_value( 'display_entry_details',
        'blog:' . $blog->id );
    $param->{default_author_id}
        = $plugin->get_config_value( 'default_author', 'blog:' . $blog->id );
    $param->{default_frequency}
        = $plugin->get_config_value( 'frequency', 'blog:' . $blog->id );
    $param->{default_max_failures}
        = $plugin->get_config_value( 'max_failures', 'blog:' . $blog->id );
    $param->{rebuild_individual}
        = $plugin->get_config_value( 'rebuild_individual',
        'blog:' . $blog->id );
    $param->{import_categories}
        = $plugin->get_config_value( 'import_categories',
        'blog:' . $blog->id );

    $app->build_page( $tmpl, $param );
}

sub import_sourcefeeds {
    my $app = shift;
    $app->validate_magic() or return;
    my $perms = $app->permissions;
    unless ( check_perms( $perms, $app->user, 'sourcefeeds' ) ) {
        return $app->error('You cannot configure sourcefeeds for this blog.');
    }
    my @ids = $app->param('id');
    use Reblog::ReblogSourcefeed;
    my @feeds;
    foreach my $id (@ids) {
        my @load = Reblog::ReblogSourcefeed->load(
            { id => $id, blog_id => $app->blog->id } );
        my $feed = shift @load;
        ($feed) && push @feeds, $feed;
    }
    my $blog = $app->blog;
    my $res;
    if (@feeds) {
        use Reblog::Util;
        $res = Reblog::Util::do_import( $app, '', $blog, @feeds );
        if ( $app->errstr ) {
            return $app->error( $app->errstr );
        }
    }
    else {
        return $app->error('Blog mismatch or no feeds selected');
    }
    my $plugin = MT->component('reblog');
    my $tmpl   = $plugin->load_tmpl('manual_import.tmpl');
    my $param;
    my $mt = MT->instance;
    $param->{script_url}     = $mt->uri;
    $param->{blog_id}        = $blog->id;
    $param->{reblog_message} = $res;
    $app->build_page( $tmpl, $param );
}

sub save_sourcefeed {
    my $app   = shift;
    my $perms = $app->permissions;
    unless ( check_perms( $perms, $app->user, 'sourcefeeds' ) ) {
        return $app->error('You cannot configure sourcefeeds for this blog.');
    }
    $app->forward('save');
}

sub cms_entry_preview_callback {
    my ( $cb, $app, $entry, $data ) = @_;
    unless ( $app->param('reblog_manual_edit') ) {
        return;
    }
    my @editablevals
        = qw( annotation source_title source_link via_link thumbnail_url thumbnail_link enclosure_url );
    foreach my $val (@editablevals) {
        push @{$data}, { data_name => $val, data_value => $app->param($val) };
    }
    push @{$data}, { data_name => 'reblog_manual_edit', data_value => 1 };
}

sub cms_sourcefeed_presave_callback {
    my ( $cb, $app, $feed, $orig ) = @_;
    unless ( $app->{query}->{is_active} ) {
        $feed->is_active(0);
    }
    unless ( $app->{query}->{is_excerpted} ) {
        $feed->is_excerpted(0);
    }
    if ( $app->{query}->{clear_errors} ) {
        $feed->has_error(0);
        $feed->consecutive_failures(0);
    }
    return 1;
}

sub list_sourcefeeds {
    use Reblog::ReblogSourcefeed;
    my ($app) = @_;
    my $perms = $app->permissions;
    unless ( check_perms( $perms, $app->user, 'sourcefeeds' ) ) {
        return $app->error('You cannot configure sourcefeeds for this blog.');
    }
    my $blog    = $app->blog;
    my $plugin  = MT->component('reblog');
    my $blog_id = $blog->id;

    $app->listing(
        {   type  => 'ReblogSourcefeed',
            terms => { blog_id => $blog_id, },
            args  => {
                sort      => 'label',
                direction => 'ascend'
            },
            code => sub {
                my ( $obj, $row ) = @_;
            },
        }
    );
}

sub validate_json {
    use Reblog::Util;
    use JSON;
    my $app   = shift;
    my $perms = $app->permissions;
    unless ( check_perms( $perms, $app->user, 'sourcefeeds' ) ) {
        return $app->error('You cannot configure sourcefeeds for this blog.');
    }
    my $sourcefeed = $app->param('sourcefeed');
    my $valid;
    my $res;
    if ($sourcefeed) {
        $valid = 0;
        eval { $valid = Reblog::Util::validate_feed( $app, $sourcefeed ); };
        if ($@) {
            $valid = 0;
        }
    }
    else {
        $app->error('No sourcefeed given');
    }
    if ($valid) {
        $res->{success} = 1;
        my $err = $app->errstr;
        if ($err) {
            $err =~ s/^\n//;
            $err =~ s/\n$//;
            use MT::Util;
            $err = MT::Util::encode_html($err);
            $res->{errstr} = MT::Util::encode_html($err);
        }
    }
    else {
        $res->{success} = 0;
        my $err = $app->errstr;
        $err ||= 'Unknown error';
        $err =~ s/^\n//;
        $err =~ s/\n$//;
        use MT::Util;
        $err = MT::Util::encode_html($err);
        $res->{errstr} = MT::Util::encode_html($err);
    }
    $app->{no_print_body} = 1;
    $app->send_http_header('text/javascript');
    if ( $JSON::VERSION > 2 ) {
        $app->print( JSON::to_json($res) );
    }
    else {
        $app->print( JSON::objToJson($res) );
    }
    1;
}

sub edit_sourcefeed {
    my $app   = shift;
    my $perms = $app->permissions;
    unless ( check_perms( $perms, $app->user, 'sourcefeeds' ) ) {
        return $app->error('You cannot configure sourcefeeds for this blog.');
    }
    my $q      = $app->param;
    my $plugin = MT->component('reblog');
    my $tmpl   = $plugin->load_tmpl('edit_ReblogSourcefeed.tmpl');

    my $class = $app->model('ReblogSourcefeed');
    my %param = ();

    $param{object_type} = 'ReblogSourcefeed';
    my $id = $q->param('id');
    my $obj;
    if ($id) {
        $obj = $class->load($id);
    }
    else {
        $obj = $class->new;
    }

    my $cols = $class->column_names;

    # Populate the param hash with the object's own values
    for my $col (@$cols) {
        $param{$col}
            = defined $q->param($col) ? $q->param($col) : $obj->$col();
    }

    if ( $class->can('class_label') ) {
        $param{object_label} = $class->class_label;
    }
    if ( $class->can('class_label_plural') ) {
        $param{object_label_plural} = $class->class_label_plural;
    }

    $param{saved} = $app->param('saved');

    $app->build_page( $tmpl, \%param );
}

sub reblog_save {
    my ( $cb, $app, $obj ) = @_;
    my $plugin = MT->component('reblog');
    unless ( $app->blog && $obj->blog_id ) {
        return;
    }
    unless ( $app->param('reblog_manual_edit') ) {
        return;
    }
    my ($blogid,        $via_link,         $source_title,
        $source_link,   $thumbnail_link,   $thumbnail_url,
        $enclosure_url, $enclosure_length, $enclosure_type,
        $annotation
    );

    $blogid           = $obj->blog_id;
    $via_link         = $app->param('via_link');
    $source_title     = $app->param('source_title');
    $source_link      = $app->param('source_link');
    $thumbnail_link   = $app->param('thumbnail_link');
    $thumbnail_url    = $app->param('thumbnail_url');
    $enclosure_url    = $app->param('enclosure_url');
    $enclosure_length = $app->param('enclosure_length');
    $enclosure_type   = $app->param('enclosure_type');
    $annotation       = $app->param('annotation');
    my $reblog = Reblog::ReblogData->load( { entry_id => $obj->id } );

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

        # TODO - not obviously exposed in app
        $rbd->source_author( $user->nickname );
        $rbd->link($source_link);
        $rbd->guid( $entry->atom_id );
        $rbd->source($source_title);
        $rbd->source_feed_url('#');
        $rbd->sourcefeed_id(0);
        $rbd->blog_id($blogid);
        $rbd->save;
    }
}

sub save_config {    # Translate default author's author_name into author id
    my $plugin = shift;
    my ( $param, $scope ) = @_;
    my $found;
    if ( $param->{default_author} ) {
        my @authors
            = MT::Author->load( { name => $param->{default_author} } );
        unless (@authors) {
            @authors = MT::Author->load( { id => $param->{default_author} } );
        }
        for (@authors) {
            $param->{default_author} = $_->id;
            $found = 1;
            last;
        }
    }
    if ( !$found ) {
        $param->{default_author} = '';
    }
    return $plugin->SUPER::save_config( $param, $scope );
}

sub inline_edit_entry {
    my ( $callback, $app, $param, $tmpl ) = @_;
    my $entry_id = $param->{id};
    my $plugin   = MT->component('reblog');
    unless ( $app->blog ) {
        return;
    }
    unless (
        $plugin->get_config_value(
            'display_entry_details', 'blog:' . $app->blog->id
        )
        )
    {
        return;
    }
    my $reblog_data;
    $reblog_data = Reblog::ReblogData->load( { entry_id => $param->{id} } );
    $reblog_data ||= Reblog::ReblogData->new
        ;    # not going to save this, just need an object to avoid errors
    my $reblog_setting = $tmpl->createElement(
        'app:setting',
        {   id          => 'reblog_info',
            required    => 0,
            label       => 'Reblog Information',
            shown       => 1,
            label_class => 'top-label'
        }
    );
    my $panel_tmpl = $plugin->load_tmpl('editentry_reblog_panel.tmpl');
    my $inner      = $panel_tmpl->text;
    use HTML::Template;
    my $addition
        = HTML::Template->new_scalar_ref( \$inner, option => 'value' );

    if ( $app->param('reedit') ) {
        $addition->param( ANNOTATION     => $app->param('annotation') );
        $addition->param( SOURCE_TITLE   => $app->param('source_title') );
        $addition->param( SOURCE_LINK    => $app->param('source_link') );
        $addition->param( VIA_LINK       => $app->param('via_link') );
        $addition->param( THUMBNAIL_LINK => $app->param('thumbnail_link') );
        $addition->param( THUMBNAIL_URL  => $app->param('thumbnail_url') );
        $addition->param( ENCLOSURE_URL  => $app->param('enclosure_url') );
    }
    else {
        $addition->param( ANNOTATION     => $reblog_data->annotation );
        $addition->param( SOURCE_TITLE   => $reblog_data->source_title );
        $addition->param( SOURCE_LINK    => $reblog_data->source_url );
        $addition->param( VIA_LINK       => $reblog_data->via_link );
        $addition->param( THUMBNAIL_LINK => $reblog_data->thumbnail_link );
        $addition->param( THUMBNAIL_URL  => $reblog_data->thumbnail_url );
        $addition->param( ENCLOSURE_URL  => $reblog_data->enclosure_url );
    }
    $reblog_setting->innerHTML( $addition->output );
    my $keywords_field = $tmpl->getElementById('keywords');
    $tmpl->insertAfter( $reblog_setting, $keywords_field );
}

sub check_perms {
    my ( $perms, $author, $type ) = @_;
    my $plugin = MT->component('reblog');
    unless ( $perms && $author && $type ) {
        return;
    }
    my $restrict;
    if ( $type eq 'reblog' ) {
        $restrict = $plugin->get_config_value( 'restrict_reblog', 'system' );
    }
    else {
        $restrict
            = $plugin->get_config_value( 'restrict_sourcefeeds', 'system' );
    }
    if ($restrict) {
        return $author->is_superuser;
    }
    else {
        return $perms->can_administer_blog;
    }
}

sub menu_permission_reblog {
    my $app = MT->instance;
    unless ($app) {
        return 0;
    }
    my $blog   = $app->blog;
    my $author = $app->user;
    my $plugin = MT->component('reblog');
    my $perms  = $app->permissions;
    unless ( $blog && $app && $plugin && $perms ) {
        return 0;
    }
    my $restrict = $plugin->get_config_value( 'restrict_reblog', 'system' );
    if ($restrict) {
        return $author->is_superuser;
    }
    else {
        return $perms->can_administer_blog;
    }
}

sub menu_permission_sourcefeeds {
    my $app = MT->instance;
    unless ($app) {
        return 0;
    }
    my $blog   = $app->blog;
    my $author = $app->user;
    my $plugin = MT->component('reblog');
    my $perms  = $app->permissions;
    unless ( $blog && $app && $plugin && $perms ) {
        return 0;
    }
    my $restrict
        = $plugin->get_config_value( 'restrict_sourcefeeds', 'system' );
    if ($restrict) {
        return $author->is_superuser;
    }
    else {
        return $perms->can_administer_blog;
    }
}

1;
