# Business::Shipping::Package::UPS
# 
# $Id: UPS.pm,v 1.3 2003/08/20 12:58:48 db-ship Exp $
# 
# Copyright (c) 2003 Kavod Technologies, Dan Browning. All rights reserved. 
# 
# Licensed under the GNU Public Licnese (GPL).  See COPYING for more info.
# 

package Business::Shipping::Package::UPS;

use strict;
use warnings;

use vars qw( @ISA $VERSION );
@ISA = ( 'Business::Shipping::Package' );
$VERSION = do { my @r=(q$Revision: 1.3 $=~/\d+/g); sprintf "%d."."%03d"x$#r,@r };

use Business::Shipping::Debug;
use Business::Shipping::CustomMethodMaker
	new_hash_init => 'new',
	grouped_fields_inherit => [
		optional => [ 'packaging' ],
		unique => [ 'packaging' ],
	];

1;