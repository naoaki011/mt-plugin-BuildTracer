############################################################################
# Copyright © 2010 Six Apart Ltd.
# This program is free software: you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
# version 2 for more details. You should have received a copy of the GNU
# General Public License version 2 along with this program. If not, see
# <http://www.gnu.org/licenses/>.

package MT::Plugin::BuildTracer;

use strict;
use MT;
use MT::Plugin;
@MT::Plugin::BuildTracer::ISA = qw(MT::Plugin);

use vars qw($PLUGIN_NAME $VERSION);
$PLUGIN_NAME = 'BuildTracer';
$VERSION = '0.5';
my $plugin = new MT::Plugin::BuildTracer({
    name => $PLUGIN_NAME,
    version => $VERSION,
    description => "<MT_TRANS phrase='description of BuildTracer'>",
    author_name => 'Akira Sawada',
    author_link => 'http://blog.aklaswad.com/',
    l10n_class => 'BuildTracer::L10N',
});

MT->add_plugin($plugin);

sub instance { $plugin; }

sub doLog {
    my ($msg) = @_;
    return unless defined($msg);

    use MT::Log;
    my $log = MT::Log->new;
    $log->message($msg) ;
    $log->save or die $log->errstr;
}

sub init_registry {
    my $plugin = shift;

    my $menus = {
        'manage:fileinfo' => {
            label => 'FileInfo',
            mode  => 'list_fileinfo',
            order => 9000,
        },
    };

    my $methods = {
        'list_fileinfo' => 'BuildTracer::CMS::list_fileinfo',
        'build_tracer'  => 'BuildTracer::CMS::trace',
    };

    $plugin->registry({
        config_settings => {
            'BuildTracerDebugMode' => { default => 0, },
        },
        applications => {
            cms => {
                menus   => $menus,
                methods => $methods,
            },
        },
    });
}

1;
