#!/usr/bin/perl -w

use strict;
use lib "../lib";
use Data::Dumper;
use File::Basename;
use File::Copy;
use File::Copy::Recursive qw(dircopy);
use File::Path qw(make_path);
use File::Spec::Functions qw(catdir catfile rel2abs);
use Getopt::Long;
use Cwd;
use Config::General qw(ParseConfig);
use Time::localtime;

my %opt;
$opt{ID} = 1;
GetOptions(\%opt, "fullnice", "ID=s","debug|d") or die;

$| = 1;

###############################################################################
# Configuration
###############################################################################
my $start_time = time;

my $hostname = "faas.bme.unc.edu";

my $webapp_dir = "../";

my %dir_locations = (
	upload => catdir($webapp_dir, "uploaded_experiments"),
	data_proc => "../../../data/",
	results => "../../../results/",
	public_output => catdir($webapp_dir,"public","results"),
);

foreach (keys %dir_locations) {
	$dir_locations{$_} = rel2abs($dir_locations{$_});
}

if (! -e $dir_locations{public_output}) {
	make_path($dir_locations{public_output});
}

my $run_file = "fa_webapp.$opt{ID}.run";
&process_run_file($run_file);

###############################################################################
# Main
###############################################################################

###########################################################
# Preliminary Setup
###########################################################

#check for files in the upload directory, if none, wait 30 seconds and try again
my @uploaded_folders = <$dir_locations{upload}/*>;
if (scalar(@uploaded_folders) == 0) {
	if ($opt{debug}) {
		print "No new experiments found\n";
	}
	sleep 30;
	@uploaded_folders = <$dir_locations{upload}/*>;
	if (scalar(@uploaded_folders) == 0) {
		unlink $run_file;
		exit;
	}
}

my %oldest_data;
for my $folder (@uploaded_folders) {
	#folders marked with temp haven't been completely setup yet, skip those
	if ($folder =~ /temp$/) {
		next;
	}
	
	if (not defined $oldest_data{upload_folder}) {
		$oldest_data{upload_folder} = $folder;
	} else {
		if (-C $folder > -C $oldest_data{upload_folder}) {
			$oldest_data{upload_folder} = $folder;
		}
	}
}

if ($opt{debug}) {
	print "Found oldest upload file: $oldest_data{upload_folder}\n";
}

if (basename($oldest_data{upload_folder}) =~ /FAAS_(.*)/) {
	$oldest_data{ID} = $1;
}

###########################################################
# Processing
###########################################################
$oldest_data{data_folder} = catdir($dir_locations{data_proc},basename($oldest_data{upload_folder}));

#This deals with the very low probability that there is a collision in the new
#exp name and an older exp name, which then removes the old folder
if (-d $oldest_data{data_folder}) {
	File::Path::rmtree($oldest_data{data_folder});
}

if (-e $oldest_data{data_folder}) {
	open TEMP, ">>trouble_exps.txt";
	print TEMP "$oldest_data{data_folder}\n";
	close TEMP;
	File::Path::rmtree($oldest_data{data_folder});
}

move($oldest_data{upload_folder}, $oldest_data{data_folder}) or die $!;
# dircopy($oldest_data{upload_folder}, $oldest_data{data_folder});
if ($opt{fullnice}) {
	system("renice -n 20 -p $$ > /dev/null");
	system("ionice -c 3 -p $$");
}

$oldest_data{cfg_file} = rel2abs(catfile($oldest_data{data_folder},"analysis.cfg"));

my %temp = ParseConfig(
	-ConfigFile => $oldest_data{cfg_file},
	-MergeDuplicateOptions => 1,
	-IncludeRelative       => 1,
);
$oldest_data{cfg} = \%temp;

$oldest_data{results_folder} = rel2abs(catdir($dir_locations{results},basename($oldest_data{upload_folder})));

&setup_exp(%oldest_data);
&run_processing_pipeline(%oldest_data);
if (not $oldest_data{cfg}{static}) {
	&build_vector_vis(%oldest_data);
}
&add_runtime_to_config(\%oldest_data,$start_time);
&copy_config_to_results($oldest_data{cfg_file},$oldest_data{results_folder});
$oldest_data{public_zip} = &zip_results_folder(%oldest_data);

File::Path::rmtree($oldest_data{results_folder});

###########################################################
# Notifications, Cleanup
###########################################################
if (defined $oldest_data{cfg}{email}) {
	&send_done_email(%oldest_data);
}

unlink $run_file;

###############################################################################
# Functions
###############################################################################

sub add_runtime_to_config {
	my %oldest_data = %{$_[0]};
	my $start_time = $_[1];
	
	my $end_time = time;
	my $total_time = $end_time - $start_time;

	open OUTPUT, ">>$oldest_data{cfg_file}" or die $!;
	print OUTPUT "runtime = $total_time\n";
	close OUTPUT;
}

sub copy_config_to_results {
	my $config_file_location = $_[0];
	my $results_folder = $_[1];
	
	copy($config_file_location, $results_folder);
}

###########################################################
# Run File Processing
###########################################################

sub process_run_file {
	my $run_file = shift @_;
	if (-e $run_file) {
		open INPUT, $run_file;
		my $process_ID = <INPUT>;
		chomp($process_ID);
		close INPUT;

		my $exists = kill 0, $process_ID;
		if ($exists) {
			if ($opt{debug}) {
				print "Found running process\n";
			}
			exit;
		} else {
			unlink $run_file;
		}
	}

	open OUTPUT, ">$run_file" or die "$!";
	print OUTPUT $$;
	close OUTPUT;
}

###########################################################
# Email
###########################################################

sub send_email {
	my %email_data = @_;
	
	if (defined $email_data{exp_note}) {
		$email_data{body} = "$email_data{body}\n" . 
			"Your note about this experiment:\n\n$email_data{exp_note}";
	}
	
	my $from_str = "\"noreply\@$hostname (FAAS Notification)\"";

	my $command = "echo \"$email_data{body}\" | mail -r $from_str -s \"$email_data{subject}\" $email_data{address}";
	system $command;
}

sub send_start_email {
	my %config = @_;

	my %start_email = (
		'address' => "$config{email}",
		'body' => "Your experiment ($config{name}) has started processing. You will receive an email later with a link to download your results.",
		'subject' => "Your experiment has started processing ($config{name})",
	);

	if (defined $config{cfg}{exp_note}) {
		$start_email{exp_note} = $config{exp_note};
	}

	&send_email(%start_email);
}

sub send_done_email {
	my %config = @_;
	
	my $full_id = basename($config{upload_folder});
	
	my $body = "Your experiment ($full_id) has finished processing and " . 
		"you can download your results here:\n\n" .
		"http://$hostname/results/$config{public_zip}\n\n" .
		"Please note that these results will be removed in a month. " .
		"You can find help with understanding the results here:\n\n" .
		"http://$hostname/results_understanding/\n\n";

	my %done_email = (
		'address' => "$config{cfg}{email}",
		'body' => $body,
		'subject' => "Your experiment has finished processing ($full_id)",
	);

	if (defined $config{cfg}{exp_note}) {
		$done_email{exp_note} = $config{cfg}{exp_note};
	}

	&send_email(%done_email);
}

# sub send_done_text {
# 	my %config = @_;
# 	
# 	my $provider_email;
# 	if (defined $config{provider}) {
# 		if ($config{provider} eq "AT&T") {
# 			$provider_email = 'txt.att.net';
# 		} elsif ($config{provider} eq "Verizon") {
# 			$provider_email = 'vtext.com';
# 		} elsif ($config{provider} eq "Sprint") {
# 			$provider_email = 'messaging.nextel.com';
# 		} else {
# 			print "Unrecognized provider code: $config{provider}\n" if $opt{debug};
# 			return;
# 		}
# 	}
# 
# 	if (defined $config{phone} && $config{phone} =~ /\d+/) {
# 		my %text_email = (
# 			'address' => $config{phone} . "\@$provider_email",
# 			'body' => "Your exp ($config{name}) has finished. Self note: $config{self_note}",
# 			'subject' => "",
# 			'self_note' => undef,
# 		);
# 		&send_email(%text_email);
# 	}
# }

###########################################################
# Experiment Processing
###########################################################
sub setup_exp {
	my %oldest_data = @_;
		
	my $starting_dir = getcwd;
	chdir "../../find_cell_features";
	my $command = "./setup_results_folder.pl -convert_to_png -cfg $oldest_data{cfg_file} > /dev/null 2>/dev/null";
	
	if ($opt{debug}) {
		print "Running: $command\n";
	}	
	system($command);
	chdir $starting_dir;
}

sub run_processing_pipeline {
	my %oldest_data = @_;

	my $starting_dir = getcwd;
	chdir "../../scripts";
	
	my $output_status = catfile($oldest_data{results_folder},'run_status.txt');
	my $output_error = catfile($oldest_data{results_folder},'run_error.txt');

	my $command = "./build_all_results.pl -cfg $oldest_data{cfg_file} -exp_filter $oldest_data{ID} > $output_status 2> $output_error";
	if ($opt{debug}) {
		print "Running: $command\n";
	}
	system($command);
	chdir $starting_dir;
}

sub zip_results_folder {
	my %oldest_data = @_;
	
	my $zip_filename = basename($oldest_data{upload_folder}).".zip";
	my $output_zip = catfile(rel2abs($dir_locations{public_output}),$zip_filename);
	
	my $starting_dir = getcwd;
	chdir $dir_locations{results};
	my $command = "zip -q -r $output_zip " . basename($oldest_data{upload_folder});
	if ($opt{debug}) {
		print "Running: $command\n";
	}
	system($command);
	chdir $starting_dir;

	return $zip_filename; 
}

sub build_vector_vis {
	my %oldest_data = @_;

	my $starting_dir = getcwd;
	chdir "../../visualize_cell_features";
	my $command = "./build_vector_vis.pl -cfg $oldest_data{cfg_file} -white_background";
	
	if ($opt{debug}) {
		print "Running: $command\n";
	}
	system($command);
	chdir $starting_dir;
}
