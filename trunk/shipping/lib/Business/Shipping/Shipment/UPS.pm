# Business::Shipping::Shipment::UPS
# 
# $Id: UPS.pm,v 1.3 2003/10/13 18:25:15 db-ship Exp $
# 
# Copyright (c) 2003 Kavod Technologies, Dan Browning. All rights reserved. 
# 
# Licensed under the GNU Public Licnese (GPL).  See COPYING for more info.
# 

package Business::Shipping::Shipment::UPS;

use strict;
use warnings;

use vars qw( @ISA $VERSION );
@ISA = ( 'Business::Shipping::Shipment' );
$VERSION = do { my @r=(q$Revision: 1.3 $=~/\d+/g); sprintf "%d."."%03d"x$#r,@r };

use Business::Shipping::Debug;
use Business::Shipping::Package;

use Business::Shipping::CustomMethodMaker
	new_with_init => 'new',
	new_hash_init => 'hash_init',
    grouped_fields_inherit => [
		optional => [ 'to_residential' ],
		unique => [ 'to_residential' ],
		required => [ 'from_zip' ],
	];

use constant INSTANCE_DEFAULTS => (
	shipper => 'UPS',
);
 
sub init
{
	my $self   = shift;
	my %values = ( INSTANCE_DEFAULTS, @_ );
	$self->hash_init( %values );
	return;
}

	
1;