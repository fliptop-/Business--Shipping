# Business::Shipping::Package - Abstract class
# 
# $Id: Package.pm,v 1.9 2004/06/24 03:09:23 danb Exp $
# 
# Copyright (c) 2003-2004 Kavod Technologies, Dan Browning. All rights reserved.
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. See LICENSE for more info.
# 

package Business::Shipping::Package;

=head1 NAME

Business::Shipping::Package - Abstract class

=head1 VERSION

$Revision: 1.9 $      $Date: 2004/06/24 03:09:23 $

=head1 DESCRIPTION

Represents package-level information (e.g. weight).  Subclasses provide real 
implementation.

=head1 METHODS

=over 4

=cut

$VERSION = do { my @r=(q$Revision: 1.9 $=~/\d+/g); sprintf "%d."."%03d"x$#r,@r };

use strict;
use warnings;
use base ( 'Business::Shipping' );

=item * $self->weight()

Accessor for weight.

=item * $self->id()

Package ID (for unique identification in a list of packages).

=cut

use Class::MethodMaker 2.0
    [ 
      new    => [ qw/ -hash new / ],
      scalar => [ 'weight', 'id', 'charges' ],
      scalar => [ { -static => 1, -default => ''            }, 'Required' ],
      scalar => [ { -static => 1, -default => 'id, charges' }, 'Optional' ],
      scalar => [ { -static => 1, -default => 'weight'      }, 'Unique'   ]
    ];

#
# TODO: How do charges() and set_price()/get_charges() interplay?
# If one is not needed, get rid of it.
# At least rename for consistency.
#
sub set_price
{
    my ( $self, $service, $price ) = @_;
    $self->{'price'}->{$service} = $price;
    return $self->{'price'}->{$service};    
}

sub get_charges
{
    my ( $self, $service ) = @_;    
    return $self->{ 'price' }->{ $service };    
}

1;

__END__

=back

=head1 AUTHOR

Dan Browning E<lt>F<db@kavod.com>E<gt>, Kavod Technologies, L<http://www.kavod.com>.

=head1 COPYRIGHT AND LICENCE

Copyright (c) 2003-2004 Kavod Technologies, Dan Browning. All rights reserved.
This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. See LICENSE for more info.

=cut
