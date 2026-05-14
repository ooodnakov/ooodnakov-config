#!/usr/bin/env sh
set -eu

# Hermes v0.12.0 emits grouped zsh option specs like
# '(-h --help){-h,--help}[...]', which _arguments rejects because brace
# expansion is suppressed inside the quoted word. Split the grouping so zsh
# expands it into the two canonical option specs.
hermes completion zsh | sed \
  -e "s/'(-h --help){-h,--help}\\[Show help and exit\\]'/'(-h --help)'{-h,--help}'[Show help and exit]'/" \
  -e "s/'(-V --version){-V,--version}\\[Show version and exit\\]'/'(-V --version)'{-V,--version}'[Show version and exit]'/" \
  -e "s/'(-p --profile){-p,--profile}\\[Profile name\\]:profile:_hermes_profiles'/'(-p --profile)'{-p,--profile}'[Profile name]:profile:_hermes_profiles'/"
