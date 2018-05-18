# NAME

Devel::PatchPerl::Plugin::Cygwin - Devel::PatchPerl plugin for Cygwin

# VERSION

version v0.1.0

# SYNOPSIS

    # for bash etc.
    $ export PERL5_PATCHPERL_PLUGIN=Cygwin
    # for tcsh etc.
    % setenv PERL5_PATCHPERL_PLUGIN Cygwin

    # After that, use patchperl, for example, via perlbrew
    $ perlbrew install perl-5.10.1

# DESCRIPTION

This module is a plugin module for [Devel::PatchPerl](https://metacpan.org/pod/Devel::PatchPerl) for the Cygwin environment.
It might be better to be included in original because it is not for variant but for environment.
The Cygwin environment is, however, relatively minor and tricky environment.
So, this module is provided as a plugin in order to try patches unofficially and experimentally.

As of this writing, it is confirmed that the following versions are compilable with Cygwin 2.10.0.

- 5.8.9
- 5.10.1
- 5.12.5
- 5.14.4
- 5.16.3
- 5.18.4
- 5.20.3
- 5.22.4
- 5.24.4
- 5.26.2

# METHODS

## patchperl

A class method of plugin interface for [Devel::PatchPerl](https://metacpan.org/pod/Devel::PatchPerl). See [Devel::PatchPerl::Plugin](https://metacpan.org/pod/Devel::PatchPerl::Plugin).

# TESTS

If you want to check if patches succeed for all stable releases on and after 5.8 series,
specify the environment variables `PERL5_DPPPC_PATCH_TESTING` and `AUTHOR_TESTING` when testing.

If you have dist tarballs in your perlbrew root, they are used.
Otherwise they are downloaded into a temporary directory for each invoking test.

# CAVEAT

[Devel::PatchPerl](https://metacpan.org/pod/Devel::PatchPerl) says as the following:

> [Devel::PatchPerl](https://metacpan.org/pod/Devel::PatchPerl) is intended only to facilitate the "building" of
> perls, not to facilitate the "testing" of perls. This means that it
> will not patch failing tests in the perl testsuite.

This statement is applicable also for this plugin.
For example, on some versions of perls, it is observed that tests such as op/taint.t and op/threads.t are blocked at the author's environment.

# SEE ALSO

- [Devel::PatchPerl::Plugin](https://metacpan.org/pod/Devel::PatchPerl::Plugin)
- [App::perlbrew](https://metacpan.org/pod/App::perlbrew)

# AUTHOR

Yasutaka ATARASHI <yakex@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2018 by Yasutaka ATARASHI.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
