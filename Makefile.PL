# -*- mode: perl; c-basic-offset: 4; indent-tabs-mode: nil; -*-

use strict;
use File::Copy 'cp';
use File::Find;
use File::Basename;
use File::Path 'mkpath';
use ExtUtils::MakeMaker qw(WriteMakefile);
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

# I should maybe use something like Shipwright...
regen_README('lib/WWW/Mechanize/PhantomJS.pm');
regen_EXAMPLES();

my $source_dir= 'ghostdriver/src';
if( -d $source_dir ) {
    # Copy the latest files for distribution
    find({
        no_chdir => 1,
        wanted => sub {
            (my $target= $File::Find::name) =~ s!.*\bsrc\b!lib/WWW/Mechanize/PhantomJS/ghostdriver!;
            mkpath dirname $target;
            cp( $File::Find::name => $target );
        },
    }, $source_dir );
    
};

my @tests = map { glob $_ } 't/*.t', 't/*/*.t';

WriteMakefile1(
    MIN_PERL_VERSION => '5.006',
    META_MERGE => {
        resources => {
            repository => 'https://github.com/Corion/www-mechanize-phantomjs',
        },
    },
    BUILD_REQUIRES => {
        # Fairly long in core
        'File::Path' => 0,
        'File::Copy' => 0,
        'File::Find' => 0,
        'File::Basename' => 0,
    },
    'NAME'          => 'WWW::Mechanize::PhantomJS',
    'LICENSE'       => 'perl',
    'VERSION_FROM'  => 'lib/WWW/Mechanize/PhantomJS.pm', # finds $VERSION
    'PREREQ_PM'     => { 
                        'Carp' => 0,
                        'Scalar::Util' => 0, # for blessed()
                        'HTTP::Response' => 0,
                        'Selenium::Remote::Driver' => 0.18, # New structure, now uses Moo
                        'IO::Socket::INET' => 0, # For port probing
                        'HTML::Selector::XPath' => 0,
                        'Object::Import' => 0,
                        'WWW::Mechanize::Link' => 0,

                        'HTTP::Daemon' => 0, # just for testing
                        'LWP::Simple' => 0, # just for testing
                      }, # e.g., Module::Name => 1.1
    ABSTRACT_FROM   => 'lib/WWW/Mechanize/PhantomJS.pm', # retrieve abstract from module
    AUTHOR          => 'Max Maischein <corion@cpan.org>',
    test            => { TESTS => join( ' ', @tests ) },
);

1;

sub WriteMakefile1 {  #Written by Alexandr Ciornii, version 0.21. Added by eumm-upgrade.
    my %params=@_;
    my $eumm_version=$ExtUtils::MakeMaker::VERSION;
    $eumm_version=eval $eumm_version;
    die "EXTRA_META is deprecated" if exists $params{EXTRA_META};
    die "License not specified" if not exists $params{LICENSE};
    if ($params{BUILD_REQUIRES} and $eumm_version < 6.5503) {
        #EUMM 6.5502 has problems with BUILD_REQUIRES
        $params{PREREQ_PM}={ %{$params{PREREQ_PM} || {}} , %{$params{BUILD_REQUIRES}} };
        delete $params{BUILD_REQUIRES};
    }
    delete $params{CONFIGURE_REQUIRES} if $eumm_version < 6.52;
    delete $params{MIN_PERL_VERSION} if $eumm_version < 6.48;
    delete $params{META_MERGE} if $eumm_version < 6.46;
    delete $params{META_ADD} if $eumm_version < 6.46;
    delete $params{LICENSE} if $eumm_version < 6.31;
    delete $params{AUTHOR} if $] < 5.005;
    delete $params{ABSTRACT_FROM} if $] < 5.005;
    delete $params{BINARY_LOCATION} if $] < 5.005;
    
    WriteMakefile(%params);
}

sub regen_README {
    eval {
        require Pod::Readme;

        my $parser = Pod::Readme->new();

        # Read POD from Module.pm and write to README
        $parser->parse_from_file($_[0], 'README');
    };
    eval {
        require Pod::Markdown;

        my $parser = Pod::Markdown->new();

        # Read POD from Module.pm and write to README
        $parser->parse_from_file($_[0]);
        open my $fh, '>', 'README.mkdn'
            or die "Couldn't open 'README.mkdn': $!";
        print $fh $parser->as_markdown;
    };
}


sub regen_EXAMPLES {
    my $perl = $^X;
    warn "(Re)Creating lib/WWW/Mechanize/PhantomJS/Examples.pm\n";
    if ($perl =~/\s/) {
        $perl = qq{"$perl"};
    };
    my $examples = `$perl -w examples/gen_examples_pod.pl`;
    if ($examples) {
        $examples =~ s/\r\n/\n/g;
        if (open my $out, '>', 'lib/WWW/Mechanize/PhantomJS/Examples.pm') {
            binmode $out;
            print $out $examples;
        };
    };
};