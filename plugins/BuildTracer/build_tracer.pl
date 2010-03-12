# $Id$

package MT::Plugin::BuildTracer;

use strict;
use MT;
use MT::Template::Context;
use MT::Plugin;
use MT::Util qw( is_valid_url decode_url );
@MT::Plugin::BuildTracer::ISA = qw(MT::Plugin);

use vars qw($PLUGIN_NAME $VERSION);
$PLUGIN_NAME = 'BuildTracer';
$VERSION = '0.1';
my $plugin = new MT::Plugin::BuildTracer({
    name => $PLUGIN_NAME,
    version => $VERSION,
    description => "<MT_TRANS phrase='description of BuildTracer'>",
    author_name => 'Akira Sawada',
    author_link => 'http://blog.aklaswad.com/',
    l10n_class => 'Test::L10N',
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
        'list_fileinfo'     => \&list_fileinfo,
        'build_tracer'    => \&trace,
    };

    $plugin->registry({
        applications => {
            cms => {
                menus   => $menus,
                methods => $methods,
            },
        },
    });
}

sub list_fileinfo {
    my $app = shift;
    if ( !$app->user->is_superuser ) {
        return $app->errtrans("Permission denied.");
    }
    my %param;
    my $blog_id = $app->param('blog_id');
    my $filter  = $app->param('filter');
    (my $limit  = $app->param('limit')  ) ||= 20;
    (my $offset = $app->param('offset') ) ||= 0;

    require MT::FileInfo;
    require MT::Template;

    #At first, build indexes.
    my $iter = MT::FileInfo->load_iter({
        'blog_id'      => $blog_id,
        'archive_type' => 'index',
    });
    my @indexes;
    while(my $fi = $iter->()) {
        my $tmpl = MT::Template->load({ 'id' => $fi->template_id});
        push @indexes, {
            'tmpl_name' => $tmpl->name,
            'url' => $fi->url,
        };
    }
    
    my @data;
    my $total;
    my $key_tmpl_name;
    if ( $filter =~ /^\d+$/ ) {
        my $tmpl_id = $filter;
        my $terms = { 'template_id' => $tmpl_id, };
        $total = MT::FileInfo->count( $terms );
        my $args  = { 'limit'  => $limit + 1,
                      'offset' => $offset,
                      'sort'   => 'url',
                    };
        if ( $total && $offset > $total - 1 ) {
            $args->{offset} = $offset = $total - $limit;
        }
        elsif ( ( $offset < 0 ) || ( $total - $offset < $limit ) ) {
            $args->{offset} = $offset = 0;
        }
        else {
            $args->{offset} = $offset if $offset;
        }

        @data = MT::FileInfo->load( $terms, $args );

        ## We tried to load $limit + 1 entries above; if we actually got
        ## $limit + 1 back, we know we have another page of fileinfos.
        my $have_next_fi = @data > $limit;
        pop @data while @data > $limit;
        if ($offset) {
            $param{prev_offset}     = 1;
            $param{prev_offset_val} = $offset - $limit;
            $param{prev_offset_val} = 0 if $param{prev_offset_val} < 0;
        }
        if ($have_next_fi) {
            $param{next_offset}     = 1;
            $param{next_offset_val} = $offset + $limit;
        }
        my $key_tmpl = MT::Template->load({ id => $tmpl_id });
        $key_tmpl_name = $key_tmpl->name;
    }
    else {
        $total = scalar @indexes;
        @data = @indexes;
        $key_tmpl_name = 'index templates';
    }

    my @individuals = MT::Template->load({
        blog_id => $blog_id,
        type    => 'individual', 
    });
    my @pages = MT::Template->load({
        blog_id => $blog_id,
        type    => 'page', 
    });
    my @archives = MT::Template->load({
        blog_id => $blog_id,
        type    => 'archive', 
    });

    my $page_tmpl = $plugin->load_tmpl('list_fileinfo.tmpl');
    $param{limit}               = $limit;
    $param{offset}              = $offset;
    $param{list_start}  = $offset + 1;
    $param{list_end}    = $offset + scalar @data;
    $param{list_total}  = $total;
    $param{next_max}    = $param{list_total} - $limit;
    $param{next_max}    = 0 if ( $param{next_max} || 0 ) < $offset + 1;
    $param{show_actions} = 1;
    $param{bar}    = 'Both';
    $param{object_label}            = 'FileInfo';
    $param{object_label_plural}     = 'FileInfos';
    $param{object_type}             = 'fileinfo';
    $param{screen_class} = "list-fileinfo";
    $param{screen_id} = "list-fileinfo";
    $param{listing_screen} = 1;
    $param{position_actions_top} = 1;
    $param{position_actions_bottom} = 1;
    $param{filter_label} = $key_tmpl_name;
    $param{list} = \@data;
    $param{archives} = \@archives;
    $param{individuals} = \@individuals;
    $param{pages} = \@pages;
    $param{indexes}  = \@indexes;
    $param{blog_id} = $blog_id;
    $param{object_loop} = \@data;
    $page_tmpl->param( \%param );
    return $app->build_page($page_tmpl);
}

our @BUILD_LOG;
our $DEPTH;
our $IGNORE_ERROR;
our %VAR_STOCK;
our %LAST_VAR;
our @TRACE_VARS;
our %STASH_STOCK;
our %LAST_STASH;
our @TRACE_STASH;
our ($TIMING, $START_TIME, $TOTAL_TIME);

sub build_log {
    my ($ctx, $log) = @_;
    if ('HASH' ne ref $log) {
        $log = { 'type' => $log };
    }
    diff_vars($ctx);
    my $vars = $ctx->{__stash}{vars};
    foreach my $v (keys %$vars){
        $VAR_STOCK{$v} = { 'var_name' => $v };
    }

    diff_stash($ctx);
    my $stash = $ctx->{__stash};
    foreach my $s (keys %$stash) {
        $STASH_STOCK{$s} = { 'stash_name' => $s };
    }
    $log->{id} = scalar @BUILD_LOG;
    push @BUILD_LOG, $log;
}

sub diff_vars {
    my $ctx = shift;
    my (@new_vars, @changed_vars, @gone_vars);
    my $vars = $ctx->{__stash}{vars};
    foreach my $v (@TRACE_VARS) {
        if( exists $LAST_VAR{$v} ) {
            my $old = $LAST_VAR{$v};
            if ( exists $vars->{$v} ) {
                my $new = $vars->{$v};
                if ($old ne $new) {
                    push @changed_vars, {
                        varname => $v,
                        old     => $old,
                        new     => $new,
                    };
                    $LAST_VAR{$v} = $new;
                }
            }
            else {
                push @gone_vars, {
                    varname => $v,
                    old     => $old,
                };
                delete $LAST_VAR{$v};
            }
        }
        else {
            if ( exists $vars->{$v} ) {
                my $new = $vars->{$v};
                push @new_vars, {
                    varname => $v,
                    new     => $new,
                };
                $LAST_VAR{$v} = $new;
            }
        } 
    }

    if ( scalar @new_vars || scalar @changed_vars || scalar @gone_vars ) {
        push @BUILD_LOG, { 
            'type'         => 'diff_vars',
            'new_vars'     => \@new_vars,
            'changed_vars' => \@changed_vars,
            'gone_vars'    => \@gone_vars,
        };
    }
}

sub diff_stash {
    my $ctx = shift;
    my (@new_stash, @changed_stash, @gone_stash);
    my $stash = $ctx->{__stash};
    foreach my $s (@TRACE_STASH) {
        if( exists $LAST_STASH{$s} ) {
            my $old = $LAST_STASH{$s};
            if ( exists $stash->{$s} ) {
                my $new = $stash->{$s};
                if ($old ne $new) {
                    push @changed_stash, {
                        stashname => $s,
                        old       => $old,
                        new       => $new,
                    };
                    $LAST_STASH{$s} = $new;
                }
            }
            else {
                push @gone_stash, {
                    stashname => $s,
                    old       => $old,
                };
                delete $LAST_STASH{$s};
            }
        }
        else {
            if ( exists $stash->{$s} ) {
                my $new = $stash->{$s};
                push @new_stash, {
                    stashname => $s,
                    new       => $new,
                };
                $LAST_STASH{$s} = $new;
            }
        } 
    }

    if ( scalar @new_stash || scalar @changed_stash || scalar @gone_stash ) {
        push @BUILD_LOG, { 
            'type'         => 'diff_stash',
            'new_stash'     => \@new_stash,
            'changed_stash' => \@changed_stash,
            'gone_stash'    => \@gone_stash,
        };
    }
}

#base on MT::Builder::build. taken from MTOS4.1 stable. 
sub psuedo_builder {
    my $build = shift;
    my($ctx, $tokens, $cond) = @_;
    
    if ((!defined $START_TIME) && $TIMING) {
        $START_TIME = [ Time::HiRes::gettimeofday() ];
    }

    build_log($ctx, { 'type' => 'enter_build', 'depth' => $DEPTH } );
    $DEPTH++;
    #print STDERR syntree2str($tokens,0) unless $count++ == 1;

    if ($cond) {
        my %lcond;
        # lowercase condtional keys since we're storing tags in lowercase now
        %lcond = map { lc $_ => $cond->{$_} } keys %$cond;
        $cond = \%lcond;
    } else {
        $cond = {};
    }
    $ctx->stash('builder', $build);
    my $res = '';
    my $ph = $ctx->post_process_handler;

    for my $t (@$tokens) {
        my $is_block = $t->[2] ? 1 : 0;
        my ($pre_handle_log, $post_handle_log);
        $pre_handle_log = { 'depth' => $DEPTH, 'type' => 'pre', 'block' => $is_block};
        $post_handle_log = { 'depth' => $DEPTH, 'type' => 'post', 'block' => $is_block};

        if ($t->[0] eq 'TEXT') {
            my $out = $t->[1];
            $out =~ s!^\s*?\n!!m;
            $out =~ s!^\n\s*?$!!m;
            $out =~ s!^\s*$!!m;
            build_log($ctx, { type => 'text', out => $out }) if $out;
            $res .= $t->[1];
        }
        elsif ($t->[0] eq 'START_TOKENS') {
            build_log($ctx, 'start_tokens');
        }
        elsif ($t->[0] eq 'START_TOKENS_ELSE') {
            build_log($ctx, 'start_tokens_else');
        }
        elsif ($t->[0] eq 'END_TOKENS') {
            build_log($ctx, 'end_tokens');
        }
        else {
            my($tokens, $tokens_else, $uncompiled);
            my $tag = lc $t->[0];
            $pre_handle_log->{tag} = $t->[0];
            $post_handle_log->{tag} = $t->[0];
            $post_handle_log->{include} = 1 if ($tag eq 'include');
            if ($cond && (exists $cond->{ $tag } && !$cond->{ $tag })) {
                # if there's a cond for this tag and it's false,
                # walk the children and look for an MTElse.
                # the children of the MTElse will become $tokens
                for my $tok (@{ $t->[2] }) {
                    if (lc $tok->[0] eq 'else' || lc $tok->[0] eq 'elseif') {
                        $tokens = $tok->[2];
                        unshift @$tokens, ['START_TOKENS_ELSE'];
                        push @$tokens, ['END_TOKENS'];
                        $uncompiled = $tok->[3];
                        $pre_handle_log->{cond} = "FALSE";
                        last;
                    }
                }
                next unless $tokens;
            } else {
                if ($t->[2] && ref($t->[2])) {
                    # either there is no cond for this tag, or it's true,
                    # so we want to partition the children into
                    # those which are inside an else and those which are not.
                    ($tokens, $tokens_else) = ([], []);
                    for my $sub (@{ $t->[2] }) {
                        if (lc $sub->[0] eq 'else' || lc $sub->[0] eq 'elseif') {
                            push @$tokens_else, $sub;
                        } else {
                            push @$tokens, $sub;
                        }
                    }
                    unshift @$tokens, ['START_TOKENS'];
                    push @$tokens, ['END_TOKENS'];
                    unshift @$tokens_else, ['START_TOKENS_ELSE'];
                    push @$tokens_else, ['END_TOKENS'];
                }
                $uncompiled = $t->[3];
            }
            my($h, $type) = $ctx->handler_for($t->[0]);
            if ($h) {
                my $start;
                if ($MT::DebugMode & 8) {
                    require Time::HiRes;
                    $start = [ Time::HiRes::gettimeofday() ];
                }
                my $tag_start_time;
                if ($TIMING) {
                    $tag_start_time = [ Time::HiRes::gettimeofday() ];
                }
                local($ctx->{__stash}{tag}) = $t->[0];
                local($ctx->{__stash}{tokens}) = ref($tokens) ? bless $tokens, 'MT::Template::Tokens' : undef;
                local($ctx->{__stash}{tokens_else}) = ref($tokens_else) ? bless $tokens_else, 'MT::Template::Tokens' : undef;
                local($ctx->{__stash}{uncompiled}) = $uncompiled;
                my %args = %{$t->[1]} if defined $t->[1];
                my @args = @{$t->[4]} if defined $t->[4];

                # process variables
                my $arg_str;
                foreach my $v (keys %args) {
                    if (ref $args{$v} eq 'ARRAY') {
                        $arg_str .= ' ' . $v . '="ARRAY"';
                        foreach (@{$args{$v}}) {
                            if (m/^\$([A-Za-z_](\w|\.)*)$/) {
                                $_ = $ctx->var($1);
                            }
                        }
                    } else {
                        $arg_str .= ' ' . $v . '="' . $args{$v} . '"';
                        if ($args{$v} =~ m/^\$([A-Za-z_](\w|\.)*)$/) {
                            $args{$v} = $ctx->var($1);
                        }
                    }
                }
                $pre_handle_log->{args} = $arg_str;
                foreach (@args) {
                    $_ = [ $_->[0], $_->[1] ];
                    my $arg = $_;
                    if (ref $arg->[1] eq 'ARRAY') {
                        $arg->[1] = [ @{$arg->[1]} ];
                        foreach (@{$arg->[1]}) {
                            if (m/^\$([A-Za-z_](\w|\.)*)$/) {
                                $_ = $ctx->var($1);
                            }
                        }
                    } else {
                        if ($arg->[1] =~ m/^\$([A-Za-z_](\w|\.)*)$/) {
                            $arg->[1] = $ctx->var($1);
                        }
                    }
                }

                build_log($ctx, $pre_handle_log);
                # Stores a reference to the ordered list of arguments,
                # just in case the handler wants them
                local $args{'@'} = \@args;
                my $out = $h->($ctx, \%args, $cond);
                my $err;
                unless (defined $out) {
                    $err = $ctx->errstr;
                    if (defined $err) {
                        if ($IGNORE_ERROR){
                            $pre_handle_log->{error} = 1;
                            $out = '';
                        }
                        else {
                            return $build->error(MT->translate("Error in <mt:[_1]> tag: [_2]", $t->[0], $ctx->errstr));
                        }
                    }
                    else {
                        # no error was given, so undef will mean '' in
                        # such a scenario
                        $out = '';
                    }
                }

                if ((defined $type) && ($type == 2)) {
                    # conditional; process result
                    $out = $out ? $ctx->slurp(\%args, $cond) : $ctx->else(\%args, $cond);
                    delete $ctx->{__stash}{vars}->{__value__};
                    delete $ctx->{__stash}{vars}->{__name__};
                }

                $out = $ph->($ctx, \%args, $out, \@args)
                    if %args && $ph;
                $post_handle_log->{out} = $pre_handle_log->{error} ? $err : $out;
                build_log($ctx, $post_handle_log);
                $res .= $out
                    if defined $out;
                if ($MT::DebugMode & 8) {
                    my $elapsed = Time::HiRes::tv_interval($start);
                    print STDERR "Builder: Tag [" . $t->[0] . "] - $elapsed seconds\n" if $elapsed > 0.25;
                }
                if ($TIMING) {
                    $post_handle_log->{ 'elapsed' } = sprintf("%f", Time::HiRes::tv_interval($tag_start_time));
                    $post_handle_log->{ 'elapsed_total' } = sprintf("%f", Time::HiRes::tv_interval($START_TIME));
                }
            } else {
                if ($t->[0] !~ m/^_/) { # placeholder tag. just ignore
                    if ($IGNORE_ERROR){
                        build_log($ctx, {
                            type => 'error',
                            out  => MT->translate("Unknown tag found: [_1]", $t->[0]),
                        });
                    }
                    else {
                        return $build->error(MT->translate("Unknown tag found: [_1]", $t->[0]));
                    }
                }
            }
        }
    }
    $DEPTH--;
    build_log($ctx, 'exit_build');
    $TOTAL_TIME = sprintf("%f", Time::HiRes::tv_interval($START_TIME))
        if $TIMING;
    
    return $res;
}

sub trace {
    my $app = shift;
    if ( !$app->user->is_superuser ) {
        return $app->errtrans("Permission denied.");
    }
    my $tmpl = $plugin->load_tmpl('build_tracer.tmpl');
    my $fi_id = $app->param('id');
    my $blog_id = $app->param('blog_id');
    my $url = decode_url( $app->param('url') );
    if ( $url =~ /[ \'\"]/ ) {
        die "invalid url";
    }
    $url =~ s!^https?://[^/]*!!;
    if ( $url =~ /\/$/ ) {
        #TBD: get from blog info... can we do that?
        $url .= 'index.html';
    }

    eval {require Time::HiRes; };
    my $can_timing = $@ ? 0 : 1;
    $TIMING = $app->param('timing') && $can_timing;
    @TRACE_VARS = $app->param('trace_vars');
    @TRACE_STASH = $app->param('trace_stash');

    require MT::FileInfo;
    my $fi = MT::FileInfo->load({'url' => $url});
    die "unknown url $url"
        unless $fi;
    $blog_id = $fi->blog_id;

    my $error;
    $IGNORE_ERROR = 1;
    {
        require MT::Builder;
        require MT::FileMgr::Local;
        require MT::WeblogPublisher;
        local *MT::Builder::build = \&psuedo_builder;
        local *MT::FileMgr::Local::content_is_updated = sub { 0 };
        my $pub = MT::WeblogPublisher->new;
        $pub->rebuild_from_fileinfo($fi)
            or $error = $pub->errstr;
    }
    require MT::Template;
    my $ft = MT::Template->load({ 'id' => $fi->template_id });
    $tmpl->param('build_log' => \@BUILD_LOG);
    $tmpl->param('lines' => @BUILD_LOG);
    foreach my $v (@TRACE_VARS) {
        $VAR_STOCK{$v}->{stocked} = 1;
    }
    foreach my $s (@TRACE_STASH) {
        $STASH_STOCK{$s}->{stocked} = 1;
    }
    $tmpl->param('varstock' => [ sort { $a->{var_name} cmp $b->{var_name} } values %VAR_STOCK ]);
    $tmpl->param('stashstock' => [ sort { $a->{stash_name} cmp $b->{stash_name} } values %STASH_STOCK ]);
    $tmpl->param('template_text' => $ft->text );
    $tmpl->param('tmpl_name' => $ft->name );
    $tmpl->param('tmpl_id' => $ft->id );
    $tmpl->param('tmpl_type' => $ft->type );
    $tmpl->param('fi_at' => $fi->archive_type );
    $tmpl->param('fi_url' => $fi->url );
    $tmpl->param('can_timing' => $can_timing);
    $tmpl->param('timing' => $TIMING);
    $tmpl->param('total_time' => $TOTAL_TIME);
    $tmpl->param('id' => $fi_id );
    $tmpl->param('blog_id' => $blog_id);
    $tmpl->param('error' => $error);
    return $app->build_page($tmpl);
}

1;
