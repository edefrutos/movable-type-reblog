use strict;
use warnings;

use lib 't/lib', 'lib', 'extlib', 'plugins/AdvancePermissions/t/lib';

BEGIN {
    $ENV{MT_APP} = 'MT::App::CMS';
}

use MT::Test qw( :app :db :data );
use MT;
use Test::More tests => 35;
use Test::Exception;
my $mt;

use MT::Author;
use MT::Blog;

my $john = MT::Author->load({ nickname => 'John Doe' });

my $blog = MT::Blog->load( 1 );

my $perms = MT::Permission->load({ blog_id => $blog->id,
                                   author_id => $john->id });
$perms->clear_full_permissions();
$perms->can_create_post(1);
$perms->can_edit_all_posts(1);

out_unlike ('MT::App::CMS', { __test_user => $john, blog_id => $blog->id }, qr|Reblog|, "Unprivileged user lacks manage reblog menu in the CMS");
out_like ('MT::App::CMS', { __test_user => $john, __mode => 'rb_blog_config', blog_id => $blog->id }, qr|You cannot configure|, "Unprivileged user has NO reblog config access in the CMS");
out_unlike ('MT::App::CMS', { __test_user => $john, blog_id => $blog->id }, qr|Sourcefeed|, "Unprivileged user lacks sourcefeeds menu in the CMS");
out_like ('MT::App::CMS', { __test_user => $john, __mode => 'rb_view_sourcefeeds', blog_id => $blog->id }, qr|You cannot configure|, "Unprivileged user has NO sourcefeed list access in the CMS");
out_like ('MT::App::CMS', { __test_user => $john, __mode => 'rb_validate_json', blog_id => $blog->id }, qr|You cannot configure|, "Unprivileged user has NO validate sourcefeed access in the CMS");
out_like ('MT::App::CMS', { __test_user => $john, __mode => 'edit_sourcefeed', blog_id => $blog->id }, qr|You cannot configure|, "Unprivileged user has NO edit sourcefeed access in the CMS");
out_like ('MT::App::CMS', { __test_user => $john, __mode => 'save_sourcefeed', blog_id => $blog->id }, qr|You cannot configure|, "Unprivileged user has NO save sourcefeed access in the CMS");

$perms->can_administer_blog(1);
$perms->save;

out_like ('MT::App::CMS', { __test_user => $john, blog_id => $blog->id }, qr|__mode=rb_blog_config|, "Blog administrator has manage reblog menu access");
out_like ('MT::App::CMS', { __test_user => $john, __mode => 'rb_blog_config', blog_id => $blog->id }, qr|<h2 id="page-title">Configure Reblog</h2>|, "Blog administrator has reblog config access in the CMS");
out_like ('MT::App::CMS', { __test_user => $john, blog_id => $blog->id }, qr|__mode=rb_view_sourcefeeds|, "Blog administrator has manage sourcefeeds menu access");
out_like ('MT::App::CMS', { __test_user => $john, __mode => 'rb_view_sourcefeeds', blog_id => $blog->id }, qr|No sourcefeeds could be found.|, "Blog administrator has sourcefeed list access in the CMS");
out_like ('MT::App::CMS', { __test_user => $john, __mode => 'rb_validate_json', blog_id => $blog->id }, qr|{"success":0,"errstr":"No sourcefeed given"}|, "Blog administrator has validate sourcefeed access in the CMS");
out_like ('MT::App::CMS', { __test_user => $john, __mode => 'edit_sourcefeed', blog_id => $blog->id }, qr|Validation check has not been run|, "Blog administrator has edit sourcefeed access in the CMS");
out_like ('MT::App::CMS', { __test_user => $john, __mode => 'save_sourcefeed', blog_id => $blog->id }, qr|Invalid request.|, "Blog administrator has save sourcefeed access in the CMS");

my $plugin = MT->component('reblog');
$plugin->set_config_value('restrict_reblog', '1', 'system');

out_unlike ('MT::App::CMS', { __test_user => $john, blog_id => $blog->id }, qr|Reblog|, "(restrict_reblog setting) Blog administrator lacks manage reblog menu access");
out_like ('MT::App::CMS', { __test_user => $john, __mode => 'rb_blog_config', blog_id => $blog->id }, qr|You cannot configure|, "(restrict_reblog setting) Blog administrator user has NO reblog config access in the CMS");
out_like ('MT::App::CMS', { __test_user => $john, blog_id => $blog->id }, qr|__mode=rb_view_sourcefeeds|, "(restrict_reblog setting) Blog administrator has manage sourcefeeds menu access");
out_like ('MT::App::CMS', { __test_user => $john, __mode => 'rb_view_sourcefeeds', blog_id => $blog->id }, qr|No sourcefeeds could be found.|, "(restrict_reblog setting) Blog administrator has sourcefeed list access in the CMS");
out_like ('MT::App::CMS', { __test_user => $john, __mode => 'rb_validate_json', blog_id => $blog->id }, qr|{"success":0,"errstr":"No sourcefeed given"}|, "(restrict_reblog setting) Blog administrator has validate sourcefeed access in the CMS");
out_like ('MT::App::CMS', { __test_user => $john, __mode => 'edit_sourcefeed', blog_id => $blog->id }, qr|Validation check has not been run|, "(restrict_reblog setting) Blog administrator has edit sourcefeed access in the CMS");
out_like ('MT::App::CMS', { __test_user => $john, __mode => 'save_sourcefeed', blog_id => $blog->id }, qr|Invalid request.|, "(restrict_reblog setting) Blog administrator has save sourcefeed access in the CMS");

$plugin->set_config_value('restrict_reblog', '0', 'system');
$plugin->set_config_value('restrict_sourcefeeds', '1', 'system');

out_like ('MT::App::CMS', { __test_user => $john, blog_id => $blog->id }, qr|__mode=rb_blog_config|, "(restrict_sourcefeeds setting) Blog administrator has manage reblog menu access");
out_like ('MT::App::CMS', { __test_user => $john, __mode => 'rb_blog_config', blog_id => $blog->id }, qr|<h2 id="page-title">Configure Reblog</h2>|, "(restrict_sourcefeeds setting) Blog administrator has reblog config access in the CMS");
out_unlike ('MT::App::CMS', { __test_user => $john, blog_id => $blog->id }, qr|Sourcefeed|, "(restrict_sourcefeeds setting) Blog administrator lacks sourcefeeds menu in the CMS");
out_like ('MT::App::CMS', { __test_user => $john, __mode => 'rb_view_sourcefeeds', blog_id => $blog->id }, qr|You cannot configure|, "(restrict_sourcefeeds setting) Blog administrator has NO sourcefeed list access in the CMS");
out_like ('MT::App::CMS', { __test_user => $john, __mode => 'rb_validate_json', blog_id => $blog->id }, qr|You cannot configure|, "(restrict_sourcefeeds setting) Blog administrator has NO validate sourcefeed access in the CMS");
out_like ('MT::App::CMS', { __test_user => $john, __mode => 'edit_sourcefeed', blog_id => $blog->id }, qr|You cannot configure|, "(restrict_sourcefeeds setting) Blog administrator has NO edit sourcefeed access in the CMS");
out_like ('MT::App::CMS', { __test_user => $john, __mode => 'save_sourcefeed', blog_id => $blog->id }, qr|You cannot configure|, "(restrict_sourcefeeds setting) Blog administrator has NO save sourcefeed access in the CMS");

$plugin->set_config_value('restrict_reblog', '1', 'system');
$plugin->set_config_value('restrict_sourcefeeds', '1', 'system');
$john->is_superuser(1);
$john->save;

out_like ('MT::App::CMS', { __test_user => $john, blog_id => $blog->id }, qr|__mode=rb_blog_config|, "(both restrictions) System administrator has manage reblog menu access");
out_like ('MT::App::CMS', { __test_user => $john, __mode => 'rb_blog_config', blog_id => $blog->id }, qr|<h2 id="page-title">Configure Reblog</h2>|, "(both restrictions) System administrator has reblog config access in the CMS");
out_like ('MT::App::CMS', { __test_user => $john, blog_id => $blog->id }, qr|__mode=rb_view_sourcefeeds|, "(both restrictions) System administrator has manage sourcefeeds menu access");
out_like ('MT::App::CMS', { __test_user => $john, __mode => 'rb_view_sourcefeeds', blog_id => $blog->id }, qr|No sourcefeeds could be found.|, "(both restrictions) System administrator has sourcefeed list access in the CMS");
out_like ('MT::App::CMS', { __test_user => $john, __mode => 'rb_validate_json', blog_id => $blog->id }, qr|{"success":0,"errstr":"No sourcefeed given"}|, "(both restrictions) System administrator has validate sourcefeed access in the CMS");
out_like ('MT::App::CMS', { __test_user => $john, __mode => 'edit_sourcefeed', blog_id => $blog->id }, qr|Validation check has not been run|, "(both restrictions) System administrator has edit sourcefeed access in the CMS");
out_like ('MT::App::CMS', { __test_user => $john, __mode => 'save_sourcefeed', blog_id => $blog->id }, qr|Invalid request.|s, "(both restrictions) System administrator has save sourcefeed access in the CMS");
