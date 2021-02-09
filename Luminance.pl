#!/usr/bin/perl

# Script for simple and fast photo deflickering using imagemagick library
# Copyright Vangelis Tasoulas (cyberang3l@gmail.com)
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

#./timelapse-deflicker.pl -i "/var/www/vhosts/knaak.org/httpdocs/wsl_test/2019_11_12" -o "/data/temp/test" -d 1 -v 1 -V 1

# Needed packages
use Getopt::Std;
use strict "vars";
use feature "say";
use Image::Magick;
use Data::Dumper;
use File::Type;
use Term::ProgressBar;
use Image::ExifTool qw(:Public);
use version;
use File::Slurp; 

#use File::Spec;

# Set the version of the timelapse-deflicker script.
our $VERSION = version->declare("0.1.1");

# Read the version of the imagemagick library that is currently used.
my ( $_im_version ) = Image::Magick->new->Get('version') =~ /\s+(\d+\.\d+\.\d+-\d+)\s+/;
my $im_version = version->parse($_im_version =~ s/-/./r);

# Pixel Channel Constants as defined in PixelChannel enum in MagicCore/pixel.h
use constant {
    RedPixelChannel => 0,
    GreenPixelChannel => 1,
    BluePixelChannel => 2,
};

# PerlMagick statistics offset constants as defined in PerlMagick/Magick.xs
# (search for #define ChannelStatistics in the file Magick.xs)
use constant {
    statoffset_depth => 0,
    statoffset_minima => 1,
    statoffset_maxima => 2,
    statoffset_mean => 3,
    statoffset_sd => 4,
    statoffset_kurtosis => 5,
    statoffset_skewness => 6,
    statoffset_entropy => 7,
};

# On November 9th 2014 (with this http://git.imagemagick.org/repos/ImageMagick/commit/275bdd9d7
# and this http://git.imagemagick.org/repos/ImageMagick/commit/b44f27d0 git commits)
# one more value (the entropy) is returned when calling the #image->Statistics() function.
# Right after this change the first IM 6.9.0-0 version was released (7.0.0-0 hadn't been released
# yet at that moment). So for versions before 6.9.0-0 we should be using 7 stat fields per
# channel, while we should be using 8 after that.
my $imStatsChangedVer = version->parse("6.9.0.0");

my $im_version = version->parse($_im_version =~ s/-/./r);
my $statFieldsPerColChannel = $im_version >= $imStatsChangedVer ? 8 : 7;

# Global variables
my $VERBOSE       = 0;
my $DEBUG         = 0;
my $RollingWindow = 15;
my $Passes        = 1;
my $Input_Folder  = "";
my $Output_Folder = "";
my $Output_name   = "";

#Define namespace and tag for luminance, to be used in the XMP files.
%Image::ExifTool::UserDefined::luminance = (
    GROUPS => { 0 => 'XMP', 1 => 'XMP-luminance', 2 => 'Image' },
    NAMESPACE => { 'luminance' => 'https://github.com/cyberang3l/timelapse-deflicker' }, #Sort of semi stable reference?
    WRITABLE => 'string',
    luminance => {}
);

%Image::ExifTool::UserDefined = (
    # new XMP namespaces (ie. XMP-xxx) must be added to the Main XMP table:
    'Image::ExifTool::XMP::Main' => {
        luminance => {
            SubDirectory => {
                TagTable => 'Image::ExifTool::UserDefined::luminance'
            },
        },
    }
);

#####################
# handle flags and arguments
# h is "help" (no arguments)
# v is "verbose" (no arguments)
# d is "debug" (no arguments)
# w is "rolling window size" (single numeric argument)
# p is "passes" (single numeric argument)
# i is "inputfolder" (string)
# o is "outputfolder" (string)
# n is "outputname" (string)
my $opt_string = 'hvdw:p:V:i:o:n';
getopts( "$opt_string", \my %opt ) or usage() and exit 1;

# print help message if -h is invoked
if ( $opt{'h'} ) {
  usage();
  exit 0;
}

if ( $opt{'V'} ) {
  print_version();
  exit 0;
}

$VERBOSE       = 1         if $opt{'v'};
$DEBUG         = 1         if $opt{'d'};

$Input_Folder  = $opt{'i'} if defined( $opt{'i'} );

#This integer test fails on "+n", but that isn't serious here.

debug("IM Version $_im_version\n");
debug("Using $statFieldsPerColChannel channel stat fields.\n");

# Create hash to hold luminance values.
# Format will be: TODO: Add this here
my %luminance;

debug("Input_Folder $Input_Folder \n");


      my $ft   = File::Type->new();
      my $filename = $Input_Folder;
      debug("$filename \n");
      my $type = $ft->mime_type($filename);
     
      #Create ImageMagick object for the image
      my $image = Image::Magick->new;
      #Evaluate the image using ImageMagick.
      $image->Read($filename);
      my @statistics = $image->Statistics();
      # Use the command "identify -verbose <some image file>" in order to see why $R, $G and $B
      # are read from the following index in the statistics array
      # This is the average R, G and B for the whole image.
      my $R          = @statistics[ ( RedPixelChannel * $statFieldsPerColChannel ) + statoffset_mean ];
      my $G          = @statistics[ ( GreenPixelChannel * $statFieldsPerColChannel ) + statoffset_mean ];
      my $B          = @statistics[ ( BluePixelChannel * $statFieldsPerColChannel ) + statoffset_mean ];
      debug("$R \n");
      debug("$G \n");
      debug("$B \n");
      # We use the following formula to get the perceived luminance.
      # Set it as the original and target value to start out with.
      my $luminance = 0.299 * $R + 0.587 * $G + 0.114 * $B;

      my $exifTool = new Image::ExifTool;
      $exifTool->SetNewValue(luminance => $luminance);
      $exifTool->WriteInfo($filename);

      debug("$luminance \n");

      print "$R|$G|$B|$luminance";
  
#####################
# Helper routines



sub print_version {
  print "Timelapse-Deflicker v$VERSION\n";
  print "   used with ImageMagick v$_im_version\n";
}

sub verbose {
  print $_[0] if ($VERBOSE);
}

sub debug {
  print $_[0] if ($DEBUG);
}

#-i "/data/temp/2019_10_10" -o "/data/temp/test" -d 1 -v 1 -V 1

