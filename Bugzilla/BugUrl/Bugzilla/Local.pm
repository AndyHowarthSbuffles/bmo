# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::BugUrl::Bugzilla::Local;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::BugUrl::Bugzilla);

use Bugzilla::Bug qw(bug_alias_to_id);
use Bugzilla::Error;
use Bugzilla::Util;

###############################
####    Initialization     ####
###############################

use constant VALIDATOR_DEPENDENCIES => {value => ['bug_id'],};

###############################
####        Methods        ####
###############################

sub ref_bug_url {
  my $self = shift;

  if (!exists $self->{ref_bug_url}) {
    my $ref_bug_id = new URI($self->name)->query_param('id');
    my $ref_bug    = Bugzilla::Bug->check($ref_bug_id);
    my $ref_value  = $self->local_uri($self->bug_id);
    $self->{ref_bug_url} = new Bugzilla::BugUrl::Bugzilla::Local(
      {bug_id => $ref_bug->id, value => $ref_value});
  }
  return $self->{ref_bug_url};
}

sub should_handle {
  my ($class, $uri) = @_;

  # Check if it is either a bug id number or an alias.
  return 1 if $uri->as_string =~ m/^\w+$/;

  # Check if it is a local Bugzilla uri and call
  # Bugzilla::BugUrl::Bugzilla to check if it's a valid Bugzilla
  # See Also URL.
  my $canonical_local = URI->new($class->local_uri)->canonical;
  if (  $canonical_local->authority eq $uri->canonical->authority
    and $canonical_local->path eq $uri->canonical->path)
  {
    return $class->SUPER::should_handle($uri);
  }

  return 0;
}

sub _check_value {
  my ($class, $uri, undef, $params) = @_;

  # At this point we are going to treat any word as a
  # bug id/alias to the local Bugzilla.
  my $value = $uri->as_string;
  if ($value =~ m/^\w+$/) {
    $uri = new URI($class->local_uri($value));
  }
  else {
    # It's not a word, then we have to check
    # if it's a valid Bugzilla URL.
    $uri = $class->SUPER::_check_value($uri);
  }

  # If bug ID is an alias, we want to store the value in the DB
  # as the actual ID instead of the alias for visibility checking
  # and other parts of the code.
  my $ref_bug_id = $uri->query_param('id');
  if ($ref_bug_id !~ /^\d+$/) {
    my $orig_ref_bug_id = $ref_bug_id;
    $ref_bug_id = bug_alias_to_id($ref_bug_id);
    $ref_bug_id
      || ThrowUserError('improper_bug_id_field_value',
      {bug_id => $orig_ref_bug_id});
    $uri->query_param('id', $ref_bug_id);
  }

  my $ref_bug     = Bugzilla::Bug->check($ref_bug_id);
  my $self_bug_id = $params->{bug_id};
  $params->{ref_bug} = $ref_bug;

  if ($ref_bug->id == $self_bug_id) {
    ThrowUserError('see_also_self_reference');
  }

  my $product = $ref_bug->product_obj;
  if (!Bugzilla->user->can_edit_product($product->id)) {
    ThrowUserError("product_edit_denied", {product => $product->name});
  }

  return $uri;
}

sub local_uri {
  my ($self, $bug_id) = @_;
  $bug_id ||= '';
  return Bugzilla->localconfig->urlbase . "show_bug.cgi?id=$bug_id";
}

sub bug {
  my ($self) = @_;
  return Bugzilla::Bug->new({id => $self->target_bug_id, cache => 1});
}

1;
