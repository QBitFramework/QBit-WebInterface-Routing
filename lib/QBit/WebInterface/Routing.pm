package QBit::WebInterface::Routing;

use POSIX qw(strftime setlocale LC_TIME);

use qbit;

use QBit::WebInterface::Routing::Routes;
use QBit::WebInterface::Response;

eval {require Exception::WebInterface::Controller::CSRF; require Exception::Request::UnknownMethod};

sub import {
    my ($package, %opts) = @_;

    die gettext('Use only with QBit::WebInterface or his descendant')
      unless $package->isa('QBit::WebInterface');

    $package->SUPER::import(%opts);

    {
        no strict 'refs';

        *{"${package}::build_response"} = \&build_response;
    }
}

sub new_routing {
    my ($self, %opts) = @_;

    return QBit::WebInterface::Routing::Routes->new(%opts);
}

sub routing {
    my ($self, $routing) = @_;

    return defined($routing) ? $self->{'__ROUTING__'} = $routing : $self->{'__ROUTING__'};
}

sub build_response {
    my ($self) = @_;

    $self->pre_run();

    throw gettext('No request object') unless $self->request;
    $self->response(QBit::WebInterface::Response->new());

    my $cmds = $self->get_cmds();

    my ($path, $cmd, %params);
    if ($self->routing()) {
        my $route = $self->routing()->get_current_route($self);

        if (exists($route->{'handler'})) {
            $path = '__HANDLER_PATH__';
            $cmd  = '__HANDLER_CMD__';

            my $package = $self->get_option('controller_class', 'QBit::WebInterface::Controller');

            $cmds->{$path}{$cmd} = {
                'package' => $package,
                'sub'     => $route->{'handler'},
                'type'    => 'CMD',
                'attrs'   => {map {$_ => TRUE} @{$route->{'attrs'} // []}}
            };

            {
                no strict 'refs';
                no warnings 'redefine';
                foreach my $method (qw(get_option request response)) {
                    *{"${package}::${method}"} = sub {shift->app->$method(@_)};
                }
            }
        } else {
            $path = $route->{'path'} // '';
            $cmd  = $route->{'cmd'}  // '';
        }

        %params = %{$route->{'args'} // {}};
    }
    
    if (!(length($path) || length($cmd)) && $self->get_option('use_base_routing')) {
        ($path, $cmd) = $self->get_cmd();

        $cmd = $cmds->{$path}{'__DEFAULT__'}{'name'} if $cmd eq '';
        $cmd = '' unless defined($cmd);
    }

    $self->set_option(cur_cmd     => $cmd);
    $self->set_option(cur_cmdpath => $path);

    if ($self->{'__EXCEPTION_IN_ROUTING__'}) {
        #nothing do...
    } elsif (exists($cmds->{$path}{$cmd})) {
        try {
            my $cmd = $cmds->{$path}{$cmd};

            my $controller = $cmd->{'package'}->new(
                app   => $self,
                path  => $path,
                attrs => $cmd->{'attrs'}
            );

            $self->{'__BREAK_PROCESS__'} = 0;
            $self->pre_cmd($controller);

            unless ($self->{'__BREAK_PROCESS__'}) {
                $controller->{'__BREAK_CMD__'} = FALSE;
                $controller->pre_cmd() if $controller->can('pre_cmd');

                unless ($controller->{'__BREAK_CMD__'}) {
                    if ($controller->attrs()->{'SAFE'}) {
                        throw Exception::WebInterface::Controller::CSRF gettext('CSRF has been detected')
                          unless $controller->check_anti_csrf_token(
                            $self->request->param(sign => $params{'sign'} // ''),
                            url => $self->get_option('cur_cmdpath') . '/' . $self->get_option('cur_cmd'));
                    }

                    my @data = $cmd->{'sub'}($controller, %params);
                    if (defined(my $method = $cmd->{'process_method'})) {
                        $controller->$method(@data);
                    }
                }
            }

            $self->post_cmd();
        }
        catch Exception::Denied with {
            $self->response->status(403);
            $self->response->data(undef);
        }
        catch Exception::Request::UnknownMethod with {
            $self->response->status(400);
            $self->response->data(undef);
        }
        catch {
            $self->exception_handling(shift);
        };
    } else {
        $self->response->status(404);
    }

    my $ua = $self->request->http_header('User-Agent');
    $self->response->headers->{'Pragma'} = ($ua =~ /MSIE/) ? 'public' : 'no-cache';

    $self->response->headers->{'Cache-Control'} =
      ($ua =~ /MSIE/)
      ? 'must-revalidate, post-check=0, pre-check=0'
      : 'no-cache, no-store, max-age=0, must-revalidate';

    my $tm   = time();
    my $zone = (strftime("%z", localtime($tm)) + 0) / 100;
    my $loc  = setlocale(LC_TIME);
    setlocale(LC_TIME, 'en_US.UTF-8');
    my $GMT = strftime("%a, %d %b %Y %H:%M:%S GMT", localtime($tm - $zone * 3600));
    setlocale(LC_TIME, $loc);

    $self->response->headers->{'Expires'} = $GMT;

    $self->post_run();

    $self->response->timelog($self->timelog);
}

sub exception_handling {
    my ($self, $exception) = @_;

    if (my $dir = $self->get_option('error_dump_dir')) {
        require File::Path;
        File::Path::make_path($dir);
        writefile("$dir/dump_" . format_date(curdate(), '%Y%m%d_%H%M%S') . "${$}.html",
            $self->_exception2html($exception));
        $self->response->status(500);
        $self->response->data(undef);
    } else {
        if (($self->request->http_header('Accept') || '') =~ /(application\/json|text\/javascript)/) {
            $self->response->content_type("$1; charset=UTF-8");
            $self->response->data(to_json({error => $exception->message()}));
        } else {
            $self->response->data($self->_exception2html($exception));
        }
    }
}

TRUE;
