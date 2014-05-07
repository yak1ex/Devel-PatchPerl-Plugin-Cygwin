# NAME

Devel::PatchPerl::Plugin::Cygwin - Devel::PatchPerl plugin for Cygwin

# VERSION

version v0.0.1

# SYNOPSIS

    # for bash etc.
    $ export PERL5_PATCHPERL_PLUGIN=Cygwin
    # for tcsh etc.
    % setenv PERL5_PATCHPERL_PLUGIN=Cygwin

    # After that, use patchperl, for example, via perlbrew
    $ perlbrew install perl-5.10.1

# DESCRIPTION

This module is a plugin module for [Devel::PatchPerl](https://metacpan.org/pod/Devel::PatchPerl) for the Cygwin environment.
It might be better to be included in original because it is not for variant but for environment.
The Cygwin environment is, however, relatively minor and tricky environment.
So, this module is provided as a plugin in order to try patches unofficially and experimentally.

**NOTE: This module is NOT yet checked for sufficient versions of perls.**

# SEE ALSO

- [Devel::PatchPerl::Plugin](https://metacpan.org/pod/Devel::PatchPerl::Plugin)
- [App::perlbrew](https://metacpan.org/pod/App::perlbrew)

# AUTHOR

Yasutaka ATARASHI <yakex@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Yasutaka ATARASHI.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
