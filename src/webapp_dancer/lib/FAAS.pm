package FAAS;
use Dancer ':syntax';
use strict;
use warnings;
use Cwd;
use Sys::Hostname;
use upload;
use exp_status;
use thresh_testing;
use results_understanding;
# use server_status;

our $VERSION = '0.1';

get '/' => sub {
    template 'index';
};

get '/deploy' => sub {
    template 'deployment_wizard', {
		directory => getcwd(),
		hostname  => hostname(),
		proxy_port=> 8000,
		cgi_type  => "fast",
		fast_static_files => 1,
	};
};

#The user clicked "updated", generate new Apache/lighttpd/nginx stubs
post '/deploy' => sub {
    my $project_dir = param('input_project_directory') || "";
    my $hostname = param('input_hostname') || "" ;
    my $proxy_port = param('input_proxy_port') || "";
    my $cgi_type = param('input_cgi_type') || "fast";
    my $fast_static_files = param('input_fast_static_files') || 0;

    template 'deployment_wizard', {
		directory => $project_dir,
		hostname  => $hostname,
		proxy_port=> $proxy_port,
		cgi_type  => $cgi_type,
		fast_static_files => $fast_static_files,
	};
};

true;
