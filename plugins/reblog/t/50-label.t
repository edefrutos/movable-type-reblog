
use strict;
use warnings;

use lib 't/lib', 'lib', 'extlib';

use MT;
use MT::Test qw( :db );

use Test::More tests => 6;
use Reblog::Util;
&Reblog::Util::sourcefeed_label_load;

ok (MT->model ('ReblogSourcefeed'), "Model for ReblogSourcefeed");

my $rsf = MT->model ('ReblogSourcefeed')->new;
ok ($rsf, "ReblogSourcefeed created");

$rsf->blog_id(1);
$rsf->url('http://narnia.na/atom.xml');
$rsf->label('Narnia Feed');
$rsf->is_active(1);
$rsf->is_excerpted(1);
$rsf->save;

is($rsf->label, 'Narnia Feed', 'label is set to initial value');
$rsf->label('');
$rsf->save;
is($rsf->label, 'narnia.na', 'label set to null string; transformed to narnia.na by callback');
monkeypatch();

sub monkeypatch {
    use Reblog::Util;
    local $SIG{__WARN__} = sub { };
    my $orig_sourcefeed_presave
        = \&Reblog::Util::sourcefeed_presave;
    *Reblog::Util::sourcefeed_presave = sub { 1; };
}    

monkeypatch();

$rsf->label('');
$rsf->save;
is($rsf->label, '', 'label set to null string (callback blocked by monkeypatch)');

&Reblog::Util::sourcefeed_label_load;

is($rsf->label, 'narnia.na', 'Post upgrade, label is set to narnia.na (domain of feed)');