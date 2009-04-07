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

package Reblog::Worker::Import;

use strict;
use base qw( TheSchwartz::Worker );

use TheSchwartz::Job;
use MT;
use MT::Author;
use MT::Blog;
use MT::Plugin;
use Reblog::Util;
use Reblog::ReblogSourcefeed;

sub work {
    my $class = shift;
    my TheSchwartz::Job $job = shift;

    # Build this
    my $mt = MT->instance;

    my @jobs;
    push @jobs, $job;
    if ( my $key = $job->coalesce ) {
        while (
            my $job
            = MT::TheSchwartz->instance->find_job_with_coalescing_value(
                $class, $key
            )
            )
        {
            push @jobs, $job;
        }
    }

    foreach $job (@jobs) {
        my $hash          = $job->arg;
        my $sourcefeed_id = $job->uniqkey;
        $sourcefeed_id =~ s/^reblog_//;
        my $sourcefeed = Reblog::ReblogSourcefeed->load($sourcefeed_id);
        my $blog_id    = $sourcefeed->blog_id;
        my $blog       = MT::Blog->load($blog_id);
        my $plugin     = MT->component('reblog');
        my $author_id  = $plugin->get_config_value( 'default_author',
            'blog:' . $blog_id );
        my $author = MT::Author->load($author_id);
        $author ||= -1;
        MT::TheSchwartz->debug( "Importing sourcefeed $sourcefeed_id ("
                . $sourcefeed->url
                . ")..." );

        if ( $sourcefeed && $blog && $author ) {
            &Reblog::Util::do_import( '', $author, $blog, $sourcefeed );
            $job->completed();
            if ( $sourcefeed->is_active ) {
                $sourcefeed->inject_worker();
            }
        }
        else {
            my $url = $sourcefeed->url;
            $job->failed( "Error with job " . $job->id . " for url " . $url );
        }
    }
}

sub grab_for    {60}
sub max_retries {20}

sub retry_delay {
    my $self = shift;
    my ($failures) = @_;
    unless ( $failures && ( $failures + 0 ) ) {    # Non-zero digit
        return 600;
    }
    return 600  if $failures < 10;
    return 1800 if $failures < 15;
    return 60 * 60 * 12;
}

1;

