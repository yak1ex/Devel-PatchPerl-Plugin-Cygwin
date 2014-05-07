package Devel::PatchPerl::Plugin::Cygwin;

use strict;
use warnings;

# ABSTRACT: Devel::PatchPerl plugin for Cygwin
# VERSION

use File::pushd qw[pushd];
use File::Spec;

my @patch = (
	{
		perl => [
# FIXME: Too tight specification
			qr/^5\.10\.1$/,
			qr/^5\.19\.8$/,
		],
		subs => [ [ \&_patch_cygwin_c_stdio ] ],
	},
	{
# FIXME: Too tight specification
		perl => [ qr/^5\.10\.1$/ ],
		subs => [ [ \&_patch_cygwin17 ] ],
	},
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
sub _patch_cygwin17
{
	Devel::PatchPerl::_patch(<<'END');
--- cygwin/cygwin.c.orig	2009-05-04 01:54:56.000000000 +0900
+++ cygwin/cygwin.c	2014-05-03 19:39:53.093468100 +0900
@@ -10,9 +10,13 @@
 #include <unistd.h>
 #include <process.h>
 #include <sys/cygwin.h>
+#include <cygwin/version.h>
 #include <mntent.h>
 #include <alloca.h>
 #include <dlfcn.h>
+#if (CYGWIN_VERSION_API_MINOR >= 181)
+#include <wchar.h>
+#endif
 
 /*
  * pp_system() implemented via spawn()
@@ -140,6 +144,44 @@
     return do_spawnvp(PL_Argv[0],(const char * const *)PL_Argv);
 }
 
+#if (CYGWIN_VERSION_API_MINOR >= 181)
+char*
+wide_to_utf8(const wchar_t *wbuf)
+{
+    char *buf;
+    int wlen = 0;
+    char *oldlocale = setlocale(LC_CTYPE, NULL);
+    setlocale(LC_CTYPE, "utf-8");
+
+    /* uvuni_to_utf8(buf, chr) or Encoding::_bytes_to_utf8(sv, "UCS-2BE"); */
+    wlen = wcsrtombs(NULL, (const wchar_t **)&wbuf, wlen, NULL);
+    buf = (char *) safemalloc(wlen+1);
+    wcsrtombs(buf, (const wchar_t **)&wbuf, wlen, NULL);
+
+    if (oldlocale) setlocale(LC_CTYPE, oldlocale);
+    else setlocale(LC_CTYPE, "C");
+    return buf;
+}
+
+wchar_t*
+utf8_to_wide(const char *buf)
+{
+    wchar_t *wbuf;
+    mbstate_t mbs;
+    char *oldlocale = setlocale(LC_CTYPE, NULL);
+    int wlen = sizeof(wchar_t)*strlen(buf);
+
+    setlocale(LC_CTYPE, "utf-8");
+    wbuf = (wchar_t *) safemalloc(wlen);
+    /* utf8_to_uvuni_buf(pathname, pathname + wlen, wpath) or Encoding::_utf8_to_bytes(sv, "UCS-2BE"); */
+    wlen = mbsrtowcs(wbuf, (const char**)&buf, wlen, &mbs);
+
+    if (oldlocale) setlocale(LC_CTYPE, oldlocale);
+    else setlocale(LC_CTYPE, "C");
+    return wbuf;
+}
+#endif /* cygwin 1.7 */
+
 /* see also Cwd.pm */
 XS(Cygwin_cwd)
 {
@@ -191,7 +233,12 @@
 
     pid = (pid_t)SvIV(ST(0));
 
-    if ((RETVAL = cygwin32_winpid_to_pid(pid)) > 0) {
+#if (CYGWIN_VERSION_API_MINOR >= 181)
+    RETVAL = cygwin_winpid_to_pid(pid);
+#else
+    RETVAL = cygwin32_winpid_to_pid(pid);
+#endif
+    if (RETVAL > 0) {
         XSprePUSH; PUSHi((IV)RETVAL);
         XSRETURN(1);
     }
@@ -204,29 +251,85 @@
     int absolute_flag = 0;
     STRLEN len;
     int err;
-    char *pathname, *buf;
+    char *src_path;
+    char *posix_path;
+    int isutf8 = 0;
 
     if (items < 1 || items > 2)
         Perl_croak(aTHX_ "Usage: Cygwin::win_to_posix_path(pathname, [absolute])");
 
-    pathname = SvPV(ST(0), len);
+    src_path = SvPV(ST(0), len);
     if (items == 2)
 	absolute_flag = SvTRUE(ST(1));
 
     if (!len)
 	Perl_croak(aTHX_ "can't convert empty path");
-    buf = (char *) safemalloc (len + 260 + 1001);
+    isutf8 = SvUTF8(ST(0));
 
+#if (CYGWIN_VERSION_API_MINOR >= 181)
+    /* Check utf8 flag and use wide api then.
+       Size calculation: On overflow let cygwin_conv_path calculate the final size.
+     */
+    if (isutf8) {
+	int what = absolute_flag ? CCP_WIN_W_TO_POSIX : CCP_WIN_W_TO_POSIX | CCP_RELATIVE;
+	int wlen = sizeof(wchar_t)*(len + 260 + 1001);
+	wchar_t *wpath = (wchar_t *) safemalloc(sizeof(wchar_t)*len);
+	wchar_t *wbuf = (wchar_t *) safemalloc(wlen);
+	if (!IN_BYTES) {
+	    mbstate_t mbs;
+            char *oldlocale = setlocale(LC_CTYPE, NULL);
+            setlocale(LC_CTYPE, "utf-8");
+	    /* utf8_to_uvuni_buf(src_path, src_path + wlen, wpath) or Encoding::_utf8_to_bytes(sv, "UCS-2BE"); */
+	    wlen = mbsrtowcs(wpath, (const char**)&src_path, wlen, &mbs);
+	    if (wlen > 0)
+		err = cygwin_conv_path(what, wpath, wbuf, wlen);
+            if (oldlocale) setlocale(LC_CTYPE, oldlocale);
+            else setlocale(LC_CTYPE, "C");
+	} else { /* use bytes; assume already ucs-2 encoded bytestream */
+	    err = cygwin_conv_path(what, src_path, wbuf, wlen);
+	}
+	if (err == ENOSPC) { /* our space assumption was wrong, not enough space */
+	    int newlen = cygwin_conv_path(what, wpath, wbuf, 0);
+	    wbuf = (wchar_t *) realloc(&wbuf, newlen);
+	    err = cygwin_conv_path(what, wpath, wbuf, newlen);
+	    wlen = newlen;
+	}
+	/* utf16_to_utf8(*p, *d, bytlen, *newlen) */
+	posix_path = (char *) safemalloc(wlen*3);
+	Perl_utf16_to_utf8(aTHX_ (U8*)&wpath, (U8*)posix_path, (I32)wlen*2, (I32*)&len);
+	/*
+	wlen = wcsrtombs(NULL, (const wchar_t **)&wbuf, wlen, NULL);
+	posix_path = (char *) safemalloc(wlen+1);
+	wcsrtombs(posix_path, (const wchar_t **)&wbuf, wlen, NULL);
+	*/
+    } else {
+	int what = absolute_flag ? CCP_WIN_A_TO_POSIX : CCP_WIN_A_TO_POSIX | CCP_RELATIVE;
+	posix_path = (char *) safemalloc (len + 260 + 1001);
+	err = cygwin_conv_path(what, src_path, posix_path, len + 260 + 1001);
+	if (err == ENOSPC) { /* our space assumption was wrong, not enough space */
+	    int newlen = cygwin_conv_path(what, src_path, posix_path, 0);
+	    posix_path = (char *) realloc(&posix_path, newlen);
+	    err = cygwin_conv_path(what, src_path, posix_path, newlen);
+	}
+    }
+#else
+    posix_path = (char *) safemalloc (len + 260 + 1001);
     if (absolute_flag)
-	err = cygwin_conv_to_full_posix_path(pathname, buf);
+	err = cygwin_conv_to_full_posix_path(src_path, posix_path);
     else
-	err = cygwin_conv_to_posix_path(pathname, buf);
+	err = cygwin_conv_to_posix_path(src_path, posix_path);
+#endif
     if (!err) {
-	ST(0) = sv_2mortal(newSVpv(buf, 0));
-	safefree(buf);
-       XSRETURN(1);
+	EXTEND(SP, 1);
+	ST(0) = sv_2mortal(newSVpv(posix_path, 0));
+	if (isutf8) { /* src was utf-8, so result should also */
+	    /* TODO: convert ANSI (local windows encoding) to utf-8 on cygwin-1.5 */
+	    SvUTF8_on(ST(0));
+	}
+	safefree(posix_path);
+        XSRETURN(1);
     } else {
-	safefree(buf);
+	safefree(posix_path);
 	XSRETURN_UNDEF;
     }
 }
@@ -237,29 +340,80 @@
     int absolute_flag = 0;
     STRLEN len;
     int err;
-    char *pathname, *buf;
+    char *src_path, *win_path;
+    int isutf8 = 0;
 
     if (items < 1 || items > 2)
         Perl_croak(aTHX_ "Usage: Cygwin::posix_to_win_path(pathname, [absolute])");
 
-    pathname = SvPV(ST(0), len);
+    src_path = SvPVx(ST(0), len);
     if (items == 2)
 	absolute_flag = SvTRUE(ST(1));
 
     if (!len)
 	Perl_croak(aTHX_ "can't convert empty path");
-    buf = (char *) safemalloc(len + 260 + 1001);
-
+    isutf8 = SvUTF8(ST(0));
+#if (CYGWIN_VERSION_API_MINOR >= 181)
+    /* Check utf8 flag and use wide api then.
+       Size calculation: On overflow let cygwin_conv_path calculate the final size.
+     */
+    if (isutf8) {
+	int what = absolute_flag ? CCP_POSIX_TO_WIN_W : CCP_POSIX_TO_WIN_W | CCP_RELATIVE;
+	int wlen = sizeof(wchar_t)*(len + 260 + 1001);
+	wchar_t *wpath = (wchar_t *) safemalloc(sizeof(wchar_t)*len);
+	wchar_t *wbuf = (wchar_t *) safemalloc(wlen);
+	char *oldlocale = setlocale(LC_CTYPE, NULL);
+	setlocale(LC_CTYPE, "utf-8");
+	if (!IN_BYTES) {
+	    mbstate_t mbs;
+	    /* utf8_to_uvuni_buf(src_path, src_path + wlen, wpath) or Encoding::_utf8_to_bytes(sv, "UCS-2BE"); */
+	    wlen = mbsrtowcs(wpath, (const char**)&src_path, wlen, &mbs);
+	    if (wlen > 0)
+		err = cygwin_conv_path(what, wpath, wbuf, wlen);
+	} else { /* use bytes; assume already ucs-2 encoded bytestream */
+	    err = cygwin_conv_path(what, src_path, wbuf, wlen);
+	}
+	if (err == ENOSPC) { /* our space assumption was wrong, not enough space */
+	    int newlen = cygwin_conv_path(what, wpath, wbuf, 0);
+	    wbuf = (wchar_t *) realloc(&wbuf, newlen);
+	    err = cygwin_conv_path(what, wpath, wbuf, newlen);
+	    wlen = newlen;
+	}
+	/* also see utf8.c: Perl_utf16_to_utf8() or Encoding::_bytes_to_utf8(sv, "UCS-2BE"); */
+	wlen = wcsrtombs(NULL, (const wchar_t **)&wbuf, wlen, NULL);
+	win_path = (char *) safemalloc(wlen+1);
+	wcsrtombs(win_path, (const wchar_t **)&wbuf, wlen, NULL);
+	if (oldlocale) setlocale(LC_CTYPE, oldlocale);
+	else setlocale(LC_CTYPE, "C");
+    } else {
+	int what = absolute_flag ? CCP_POSIX_TO_WIN_A : CCP_POSIX_TO_WIN_A | CCP_RELATIVE;
+	win_path = (char *) safemalloc(len + 260 + 1001);
+	err = cygwin_conv_path(what, src_path, win_path, len + 260 + 1001);
+	if (err == ENOSPC) { /* our space assumption was wrong, not enough space */
+	    int newlen = cygwin_conv_path(what, src_path, win_path, 0);
+	    win_path = (char *) realloc(&win_path, newlen);
+	    err = cygwin_conv_path(what, src_path, win_path, newlen);
+	}
+    }
+#else
+    if (isutf8)
+	Perl_warn(aTHX_ "can't convert utf8 path");
+    win_path = (char *) safemalloc(len + 260 + 1001);
     if (absolute_flag)
-	err = cygwin_conv_to_full_win32_path(pathname, buf);
+	err = cygwin_conv_to_full_win32_path(src_path, win_path);
     else
-	err = cygwin_conv_to_win32_path(pathname, buf);
+	err = cygwin_conv_to_win32_path(src_path, win_path);
+#endif
     if (!err) {
-	ST(0) = sv_2mortal(newSVpv(buf, 0));
-	safefree(buf);
-       XSRETURN(1);
+	EXTEND(SP, 1);
+	ST(0) = sv_2mortal(newSVpv(win_path, 0));
+	if (isutf8) {
+	    SvUTF8_on(ST(0));
+	}
+	safefree(win_path);
+	XSRETURN(1);
     } else {
-	safefree(buf);
+	safefree(win_path);
 	XSRETURN_UNDEF;
     }
 }
@@ -290,24 +444,22 @@
 {
     dXSARGS;
     char *pathname;
-    char flags[260];
+    char flags[PATH_MAX];
+    flags[0] = '\0';
 
     if (items != 1)
-        Perl_croak(aTHX_ "Usage: Cygwin::mount_flags(mnt_dir|'/cygwin')");
+        Perl_croak(aTHX_ "Usage: Cygwin::mount_flags( mnt_dir | '/cygdrive' )");
 
     pathname = SvPV_nolen(ST(0));
 
-    /* TODO: Check for cygdrive registry setting,
-     *       and then use CW_GET_CYGDRIVE_INFO
-     */
     if (!strcmp(pathname, "/cygdrive")) {
-	char user[260];
-	char system[260];
-	char user_flags[260];
-	char system_flags[260];
+	char user[PATH_MAX];
+	char system[PATH_MAX];
+	char user_flags[PATH_MAX];
+	char system_flags[PATH_MAX];
 
-	cygwin_internal (CW_GET_CYGDRIVE_INFO, user, system, user_flags,
-			 system_flags);
+	cygwin_internal (CW_GET_CYGDRIVE_INFO, user, system,
+			 user_flags, system_flags);
 
         if (strlen(user) > 0) {
             sprintf(flags, "%s,cygdrive,%s", user_flags, user);
@@ -320,6 +472,7 @@
 
     } else {
 	struct mntent *mnt;
+	int found = 0;
 	setmntent (0, 0);
 	while ((mnt = getmntent (0))) {
 	    if (!strcmp(pathname, mnt->mnt_dir)) {
@@ -328,12 +481,42 @@
 		    strcat(flags, ",");
 		    strcat(flags, mnt->mnt_opts);
 		}
+		found++;
 		break;
 	    }
 	}
 	endmntent (0);
-	ST(0) = sv_2mortal(newSVpv(flags, 0));
-	XSRETURN(1);
+
+	/* Check if arg is the current volume moint point if not default,
+	 * and then use CW_GET_CYGDRIVE_INFO also.
+	 */
+	if (!found) {
+	    char user[PATH_MAX];
+	    char system[PATH_MAX];
+	    char user_flags[PATH_MAX];
+	    char system_flags[PATH_MAX];
+
+	    cygwin_internal (CW_GET_CYGDRIVE_INFO, user, system,
+			     user_flags, system_flags);
+
+	    if (strlen(user) > 0) {
+		if (strcmp(user,pathname)) {
+		    sprintf(flags, "%s,cygdrive,%s", user_flags, user);
+		    found++;
+		}
+	    } else {
+		if (strcmp(user,pathname)) {
+		    sprintf(flags, "%s,cygdrive,%s", system_flags, system);
+		    found++;
+		}
+	    }
+	}
+	if (found) {
+	    ST(0) = sv_2mortal(newSVpv(flags, 0));
+	    XSRETURN(1);
+	} else {
+	    XSRETURN_UNDEF;
+	}
     }
 }
 
@@ -351,6 +534,8 @@
     XSRETURN(1);
 }
 
+XS(XS_Cygwin_sync_winenv){ cygwin_internal(CW_SYNC_WINENV); }
+
 void
 init_os_extras(void)
 {
@@ -366,6 +551,7 @@
     newXSproto("Cygwin::mount_table", XS_Cygwin_mount_table, file, "");
     newXSproto("Cygwin::mount_flags", XS_Cygwin_mount_flags, file, "$");
     newXSproto("Cygwin::is_binmount", XS_Cygwin_is_binmount, file, "$");
+    newXS("Cygwin::sync_winenv", XS_Cygwin_sync_winenv, file);
 
     /* Initialize Win32CORE if it has been statically linked. */
     handle = dlopen(NULL, RTLD_LAZY);
END
}

1;
__END__

=head1 SYNOPSIS

  # for bash etc.
  $ export PERL5_PATCHPERL_PLUGIN=Cygwin
  # for tcsh etc.
  % setenv PERL5_PATCHPERL_PLUGIN=Cygwin

  # After that, use patchperl, for example, via perlbrew
  $ perlbrew install perl-5.10.1

=head1 DESCRIPTION

This module is a plugin module for L<Devel::PatchPerl> for the Cygwin environment.
It might be better to be included in original because it is not for variant but for environment.
The Cygwin environment is, however, relatively minor and tricky environment.
So, this module is provided as a plugin in order to try patches unofficially and experimentally.

B<NOTE: This module is NOT yet checked for sufficient versions of perls.>

=head1 SEE ALSO

=for :list
* L<Devel::PatchPerl::Plugin>
* L<App::perlbrew>

=cut
