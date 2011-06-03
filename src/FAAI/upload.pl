#!/usr/bin/perl -wT

###############################################################################
# Setup
###############################################################################

use strict;
use File::Path;
use File::Basename;
use File::Spec::Functions;
use File::Copy;
use File::Temp;
use POSIX;
use CGI;
use CGI::Carp;
use IO::Handle;
use Config::General;
use Cwd;

$| = 1;

my $upload_dir = catdir(getcwd,'..','..','upload');
$upload_dir =~ /(.*)/;
$upload_dir = $1;
if (not -e $upload_dir) {
    mkdir($upload_dir) or die $!;
}

###############################################################################
# Main
###############################################################################

my $q = CGI->new();

print $q->header,
	  $q->start_html(-title=>'Focal Adhesion Alignment Index Server'), 
	  $q->h1('Focal Adhesion Alignment Index Server');

my $lightweight_fh = $q->upload('uploaded_file');
# undef may be returned if it's not a valid file handle
if (defined $lightweight_fh) {
    # Upgrade the handle to one compatible with IO::Handle:

    my $io_handle = $lightweight_fh->handle();
    $q->param('uploaded_file') =~ /(.*)/;
    
    my ($output_handle, $output_file) = File::Temp::tempfile(DIR=>$upload_dir) or die "$!";
    
    my %new_cfg;
    $new_cfg{email} = $q->param('email_address');
    $new_cfg{self_note} = $q->param('self_note');
    $new_cfg{exp_id} = basename($output_file);
    if ($q->param('color_blind')) {
        $new_cfg{color_blind} = 1;
    } else {
        $new_cfg{color_blind} = 0;
    }
    $new_cfg{stdev_thresh} = $q->param('stdev_thresh');
    $new_cfg{min_adhesion_size} = $q->param('min_adhesion_size');
    $new_cfg{min_axial_ratio} = $q->param('min_axial_ratio');
    my $conf = new Config::General(\%new_cfg);
    $conf->save_file("$output_file.cfg");
    chmod 0666, "$output_file.cfg" or die "$!";
    
    #print $q->h2('Data Loaded So Far');
    my $data_read = 0;
    my $buffer;
    while (my $bytesread = $io_handle->read($buffer,1024)) {
        print $output_handle $buffer or die;
        $data_read++;
    }
    close $output_handle;
    chmod 0666, "$output_file" or die "$!";
    
    print $q->p, 'Thanks for the file, you can expect two emails: one when your ' .
    'images start processing and another when they finish.';
} else {
    print $q->start_form(-method=>"POST",
                     -action=>basename($0),
                     -enctype=>"multipart/form-data");
    print $q->h2('Required Options');
    print $q->h3('Adhesion Image File'), 
          $q->filefield('uploaded_file','',50,80);
    print $q->h3('Your Email Address'),
          $q->textfield('email_address','',50,80);
    print $q->h3('Note to Self About Experiment'),
          $q->textfield('self_note','',50,80);
    
    print $q->h2('Adhesion Segmentation Options');
    print $q->h3('Identifcation Threshold (generally between 2-4)'),
          $q->textfield('stdev_thresh',2,10,10);
    print $q->h3('Minimum Adhesion Size (in pixels, generally either 2 or 3)'),
          $q->textfield('min_adhesion_size',3,10,10);
    print $q->h3('Minimum Major/Minor Axis Ratio (generally 3 or greater)'),
          $q->textfield('min_axial_ratio',3,10,10);

    print $q->h2('Miscelleous Options');

    print $q->checkbox(-name=>'color_blind',
                       -checked=>0,
                       -label=>'Are You Color Blind?');;
    
    print $q->p,
          $q->submit(-name=>"Submit Data");

    print $q->end_form;

    print $q->hr;

    print "Thank you for helping to test the Focal Adhesion Alignment Index
    server, please email me with any questions that come up as you interact with
    the website and files produced. I can be reached at mbergins (AT) unc.edu.";
    
    print $q->h1('Instructions');
 
    print $q->h2('Required Options');
    
    print $q->h3('Adhesion Image Zip File');

    print "The program expects that you will submit a set of images in either a
    zip file or a tiff stack. If submitted as a zip file, the programs expect to
    find a single folder when unzipped that contains all the images from the
    experiment.";    
    
    print $q->h3('Email Address');

    print "After you submit your files, notification of where to download the
    results will be sent through email. If you don't know email is, how did you
    manage to get to this website?";

    print $q->h3('Note to Self About Experiment');

    print "Whatever you put in this box will be send back to you in any email
    the system sends concerning your experiment. It is limited to 80
    characters.";
    
    print $q->h2('Segmentation Options');
    
    print $q->h3('Identification Threshold');
    
    print "This threshold determines how strigent the segmentation algorithm is
    when selecting which pixels are adhesions and which are not.";
    
    print $q->h3('Minimum Adhesion Size');
    
    print "The segmentation algorithms can automatically discard identified
    adhesions objects that are below the specified size. Since the alignment
    index is only calculated based on adhesions that have a major to minor axis
    ratio of at least three and objects below three pixels can't have a ratio
    past this threshold, a size threshold of two or three is advisable.";
    
    print $q->h3('Minimum Major/Minor Axis Ratio');
    
    print "In order to determine a single adhesion's angle an oval is fit to
    each adhesion. We use the ratio of the major/minor axes as filter to select
    which adhesions to include in the index calculations, with adhesions below
    the specified ratio being excluded. We include this filter because adhesions
    that are round, or nearly round, show no particular alignment, so their
    alignments can not be determined.";
    
    print $q->h2('Miscelleous Options');

    print $q->h3('Are You Color Blind?');
    
    print "One of the visualizations produced by the software uses green-red
    differences. If this box is checked, the visualization will be produced with
    blue-yellow differences.";
}

print $q->end_html;
