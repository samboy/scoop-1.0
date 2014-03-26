package Bundle::Scoop;

# $Id: Scoop.pm,v 1.7 2003/10/05 08:56:31 panner Exp $

use strict;

$Bundle::Scoop::VERSION = '0.8';

1;

__END__

=head1 NAME

Bundle::Scoop - Bundle to install all the pre-requisites for Scoop

=head1 CONTENTS

Term::ReadKey
MD5
Digest::MD5 
MIME::Base64
Data::ShowTable
Storable
DBI
DBD::mysql
Apache::DBI
Apache::Request
Apache::Session
Apache::SIG
Class::Singleton
Crypt::UnixCrypt
Crypt::CBC
Crypt::Blowfish
Mail::Sendmail
String::Random
Time::Timezone 
Time::CTime
Image::Size
URI
HTML::Tagset
HTML::HeadParser
LWP::Simple
XML::Parser
XML::RSS

=head1 DESCRIPTION

Install all the modules needed for Scoop. 

=head1 MORE INFORMATION

Sourceforge Project Home:

 http://sourceforge.net/projects/scoop/

News, package repository and more information:

 http://scoop.kuro5hin.org/

=head1 AUTHOR

Rusty Foster <rusty@kuro5hin.org>, who shamelessly copied the work of Chris Winters <chris@cwinters.com>

=cut
