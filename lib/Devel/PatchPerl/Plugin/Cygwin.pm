package Devel::PatchPerl::Plugin::Cygwin;

use strict;
use warnings;

# ABSTRACT: Devel::PatchPerl plugin for Cygwin
# VERSION

use File::pushd qw[pushd];
use File::Spec;

my @patch = (
	{
		perl => [ qr/^5\.19\.8$/ ],
		subs => [ [ \&_patch_cygwin_c_stdio ] ],
	}
);

sub patchperl
{
	return unless $^O eq 'cygwin';

	require Devel::PatchPerl;
# Devel::PatchPerl::_patch(),_is() are NOT a public interface, so the existence SHOULD NOT be relied
	if(! defined *Devel::PatchPerl::_patch{CODE} || ! defined *Devel::PatchPerl::_is{CODE}) {
		die 'Devel::PatchPerl::_patch() or Devel::PatchPerl::_is() not found, please contact with the author of '.__PACKAGE__;
	}

	shift if eval { $_[0]->isa(__PACKAGE__) };
	my (%args) = @_;
# Copy from Devel::PatchPerl::patch_source()
	my $source = File::Spec->rel2abs($args{source});
	{
		my $dir = pushd( $source );
		for my $p ( grep { Devel::PatchPerl::_is( $_->{perl}, $args{version} ) } @patch ) {
			for my $s (@{$p->{subs}}) {
				my($sub, @args) = @$s;
				push @args, $args{version} unless scalar @args;
				$sub->(@args);
			}
		}
	}
}

sub _patch_cygwin_c_stdio
{
	Devel::PatchPerl::_patch(<<'END');
--- cygwin/cygwin.c.orig        2014-01-13 09:20:07.000000000 +0900
+++ cygwin/cygwin.c     2014-05-02 19:16:25.950179100 +0900
@@ -2,6 +2,7 @@
  * Cygwin extras
  */

+#define PERLIO_NOT_STDIO 0
 #include "EXTERN.h"
 #include "perl.h"
 #undef USE_DYNAMIC_LOADING
END
}


1;
__END__

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
