# Copyright (c) 2003-2004 Kavod Technologies, Dan Browning. All rights reserved.
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. See LICENSE for more info.

package Business::Shipping::RateRequest;

=head1 NAME

Business::Shipping::RateRequest - Abstract class

=head1 VERSION

$Rev: 369 $

=head1 DESCRIPTION

Abstract Class: real implementations are done in subclasses.

Represents a request for shipping cost estimation.

=head1 METHODS

=cut

$VERSION = do { my $r = q$Rev: 369 $; $r =~ /\d+/; $&; };

use strict;
use warnings;
use base ( 'Business::Shipping' );
use Data::Dumper;
use Business::Shipping::Util;
use Business::Shipping::Logging;
use Business::Shipping::Config;

=head2 $rate_request->is_success()

Boolean.  1 = Rate Request was successful.

=head2 $rate_request->cache()

Boolean.  1 = Save results using Cache::FileCache, and reload them if an 
identical request is made later.  See submit() for implementation details.

=head2 $rate_request->invalid()

Boolean.  1 = Rate request was invalid, because user supplied invalid data. This
can be useful in determining whether or not to log incident reports (see 
UserTag/business-shipping.tag for an example implementation).

=head2 $rate_request->results()

Hashref.  Stores the results of a rate request, for example:

 {
   'UPS' => [ 
              { 
                id      => 1,
                charges => 10.50
              },
              { 
                id      => 2,
                charges => 23.00
              }
            ]
 }
                
See _handle_response() for implementation details. 

=head2 $rate_request->shipment()

Stores a Business::Shipping::Shipment object.  Many methods are forwarded to it.
At this time, each RateRequest only has one Shipment.

=head2 $rate_request->error_details()

Arrayref.  Stores the error results of a rate request. There can be multiple
errors for one request.  Each entry in the array represents an error.  Each
error is a hashref with the following keys:

 error_code	: The error code
 error_msg	: A description error message

Additional keys may be added by the shipper class.

=cut

use Class::MethodMaker 2.0
    [ new => [ qw/ -hash new / ],
      scalar        => [ 'is_success', 'cache', 'invalid' ],
      scalar	    => [ 'dont_split_packages' ],
      scalar        => [ 'shipper' ],
      scalar        => [ 'results' ],
      scalar        => [ '_total_charges' ],
      scalar        => [ 'price_components' ],
      scalar => [ { -type    => 'Business::Shipping::Shipment',
                    -forward => [ 
                                    'service', 
                                    'service_code', 'service_nick', 'service_name', 'service_nick2',
                                    'from_country',
                                    'from_country_abbrev',
                                    'to_country',
                                    'to_country_abbrev',
                                    'to_ak_or_hi',
                                    'from_zip',
                                    'to_zip',
                                    'packages',
                                    'weight',
                                    'shipper',
                                    'domestic',
                                    'intl',
                                    'domestic_or_ca',
                                    'from_canada',
                                    'to_canada',
                                    'from_ak_or_hi',
                                ],
                   },
                   'shipment'
                 ],
      array  => [ 'error_details' ],
    ];

sub Required { return ( $_[ 0 ]->SUPER::Required, qw/ shipper weight / ); } # weight can be required even though some use pounds.
sub Optional { return ( $_[ 0 ]->SUPER::Optional, qw/ to_residential from_country to_country to_zip from_city
                                                      to_city        / ); }
sub Unique   { return ( $_[ 0 ]->SUPER::Unique,   qw/ shipper service from_zip from_country to_zip from_city
                                                      to_city weight / ); }    
    
=head2 $rate_request->execute()

This method sets some values (optional), executes the request, then parses the
results.

=cut

sub execute
{
    my ( $self, %args ) = @_;
    #trace( "( " . uneval( %args ) . " )" );
    
    # Try to clear previous results, in case this object was reused.
    $self->_total_charges( 0 );
    
    $self->init( %args ) if %args;
    $self->_massage_values();
    $self->validate() or return;
    my $cache = Cache::FileCache->new() if $self->cache();
    if ( $self->cache() ) {
        trace( 'cache enabled' );    

        my $key = $self->gen_unique_key();
        debug "cache key = $key\n";
        
        my $results = $cache->get( $key );
        if ( $results ) {
            trace( "found cached response, using that." );
            $self->results( $results );
            return 1;
        }
        else {
            trace( 'Cannot find cached results, running request manually, then add to cache.' );
        }
    }
    else {
        trace( 'cache disabled' );
    }
    
    # Estimate shipping for overweight shipments by dividing them into 
    # multiple shipments and sending multiple requests.
    # Lets not assume that every module can do it, though.
    my $handle_response_success;
    my $max_weight_per_package;
    $max_weight_per_package = $self->shipment->max_weight if $self->shipment->can( 'max_weight' );
    $max_weight_per_package ||= 150;
    
    #debug3 "before we start, all packages = " . Dumper( $self->shipment->packages );
    foreach my $p_idx ( 0 .. @{ $self->shipment->packages } - 1 ) {
        my $package = $self->shipment->packages_index( $p_idx );
        
        if ( ! $package->weight ) {
            error "package weight not found for package idx: $p_idx"; #, object = " . Dumper( $package );
            next;
        }
        
        my $original_weight = $package->weight;
        
        next if $self->dont_split_packages();
        next unless ( $max_weight_per_package and ( $original_weight > $max_weight_per_package ) );
    
        debug 'calculating multiple shipments due to overweight...';
        debug "original weight: $original_weight, max_weight_per_package: $max_weight_per_package";
        
        my $MAX_NUM_PACKAGES = 100;
        
        my $number_of_packages = $original_weight / $max_weight_per_package;
        if ( $number_of_packages != int $number_of_packages ) {
            # 1 for the remainder, this will be the usual case
            $number_of_packages = int $number_of_packages + 1; 
        }
        
        debug 'number of packages = ' . $number_of_packages;
        
        if ( $number_of_packages > $MAX_NUM_PACKAGES ) {
            $self->user_error( "Too heavy." );
            return $self->is_success( 0 );
        }
        
        
        
        # Set the current violating package to the maximum amount, then add packages until the remaining
        # amount runs out.
        
        my $running_weight = $original_weight;
        my $running_total_cost;
        my $sum_rate = 0;
        my $last_charges = 0;
        
        
        $self->shipment->packages_index( $p_idx )->weight( $max_weight_per_package );
        $running_weight -= $max_weight_per_package;
        
        for ( my $c = 1; $c <= $number_of_packages; $c++ ) {
            debug "splitting out package #$c";
            
            my $current_weight = $running_weight > $max_weight_per_package ? 
                $max_weight_per_package # Common path
                :
                $running_weight; # Last shipment, unless it divided evenly.
                
            $running_weight -= $current_weight;
            debug "setting weight to $current_weight";
            last if $current_weight <= 0;
           
            $self->shipment->add_package( weight => $current_weight );
        }
        
        debug "done handling overweight.";
        #use Data::Dumper;
        #debug2 "shipment now: " . Dumper( $self->shipment );
    }
    
    $self->perform_action();
    $handle_response_success = $self->_handle_response();
    
    my $results = $self->results();
    #use Data::Dumper; debug2 'results = ' . Dumper( $results );
    
    # Only cache if there weren't any errors and we only have one package.  The Unique() subs are not
    # built (currently) to generate cache keys for multiple packages.  It's all done at the shipment level.
    if ( $handle_response_success and $self->cache() and @{ $self->shipment->packages } == 1 ) {    
        trace( 'cache enabled, saving results.' );
        #
        # TODO: Allow setting of cache properties (time limit, enable/disable, etc.)
        #
        my $key = $self->gen_unique_key();
        my $new_cache = Cache::FileCache->new();
        $new_cache->set( $key, $results, "2 days" );
    }
    else {
        trace( 'cache disabled, not saving results.' );
    }
    
    debug "returning " . ( $self->is_success || 'undef' );
    return $self->is_success();
}

# COMPAT: submit() go()

*submit = *execute;
*go     = *execute;

=head2 $rate_request->validate()

Does some validation common to all RateRequest objects, but most of the 
validation goes on in the subclass.

=cut

sub validate
{
    my ( $self ) = @_;
    trace '()';
    
    my $return_val = $self->SUPER::validate;
    
    my @invalid_rate_requests_ups = config_to_ary_of_hashes( 
        cfg()->{ invalid_rate_requests }->{ invalid_rate_requests_ups }
    );
    
    foreach my $invalid_rate_request ( @invalid_rate_requests_ups ) {
        #
        # Look for an exact match
        #
        my $matches = 0;
        foreach my $option ( keys %$invalid_rate_request ) {
            
            my $not_logic = 0;
            if ( $invalid_rate_request->{ $option } =~ s/^\!// ) {
                $not_logic = 1;
            }
            if ( $option eq 'reason' ) {
                $matches++;  # Just fudge it so the count will be correct.
            }        
            elsif ( $self->can( $option ) and $self->$option() ) {
                debug3( "checking $option... matches = $matches" );
                if ( $not_logic ) {
                    if ( $self->$option() ne $invalid_rate_request->{ $option } ) {
                        $matches++;
                        debug3( $self->$option() . " does not equal " . $invalid_rate_request->{ $option } );
                    }
                }
                else {
                    if ( $self->$option() eq $invalid_rate_request->{ $option } ) {
                        debug3( $self->$option() . " equals " . $invalid_rate_request->{ $option } );
                        $matches++;
                    }
                }
            }
        }
        #debug( "matches = $matches, keys = " . keys %$invalid_rate_request );
        
        #
        # If all keys matched (i.e. the number of matches == the number of keys )
        #
        if ( $matches == keys %$invalid_rate_request ) {
            my $reason = ( $invalid_rate_request->{ reason } ? '  ' . $invalid_rate_request->{ reason } : '' ); 
            $self->invalid( 1 );
            $self->user_error( "Rate request invalid.$reason  See the configuration file for more information." );
            $return_val = 0;
        }
    }
        
    return $return_val;
}

=head2 $rate_request->get_unique_hash()

Calls unique() on all subclasses to determine a list of unique elements.

Returns a hash of element_name => element_value.  Used by gen_unique_key().

=cut

sub get_unique_hash
{
    my $self = shift;
    
    my %unique;
    
    my @Unique = $self->get_grouped_attrs( 'Unique' );
    
    debug( "Unique attributes for this RateRequest are: " . join( ',', @Unique ) ); 
    for ( @Unique ) {
        if ( $self->can( $_ ) ) {
            $unique{ $_ } = $self->$_;
        }
    }
    
    foreach my $package ( $self->shipment->packages() ) {
        foreach my $package_unique_key ( $package->get_grouped_attrs( 'Unique', object => $package ) ) {
            $unique{ 'p1_' . $package_unique_key } = $package->$package_unique_key();
        }
    }
    return %unique;
}

=head2 $rate_request->hash_to_sorted_values()

Sorts hash alphabetically, then returns just the values.  (So that the key will
have the values sorted in the same order always).

=cut

sub hash_to_sorted_values
{
    my $self = shift;
    my ( %hash ) = @_;
    my @sorted_values;
    foreach my $key ( sort keys %hash ) {
        push @sorted_values, ( $hash{ $key } || '' );
    }
    return @sorted_values;
}

=head2 $rate_request->gen_unique_key( )

Calls get_unique_hash(), sorts them with hash_to_sorted_values(), then returns 
them in string format.

=cut

sub gen_unique_key
{
    my $self = shift;
    my %unique = $self->get_unique_hash();
    my @sorted_values = $self->hash_to_sorted_values( %unique ); 
    return join( '|', @sorted_values );
    return;
}

=head2 $rate_request->rate()

Iterates the $self->results hash and sums the charges from each 
package->charges.  Returns the total.

Example of what the results look like:

 [
     { 
         name => 'UPS_Online',
         rates   => [
                        {
                            code        => '03',
                            short_name  => 'GNDRES',
                            name        => 'Ground Residential',
                            est_deliv   => 4,
                            charges     => 5.32,
                            charges_formatted => '$5.32',
                        },
                    ]
     }
 ];

=cut

sub rate
{
    my ( $self ) = @_;
    
    if ( $self->service and lc $self->service eq 'shop' ) {
        # rate() does not work for 'shop' types, how would you know
        # which service to return?  Return data structure with all
        # that is needed.
        return $self->results;
    }
    
    if ( ref( $self->results ) ne 'ARRAY' ) {
        $self->user_error( "Could not determine rate." );
        return;
    }
    
    foreach my $shipper ( @{ $self->results } ) {
        # Just return the amount for the first one.
        #debug "Shipper: $shipper\n";
        return $shipper->{ rates }->[ 0 ]->{ split_shipment_sum_rate } 
            || $shipper->{ rates }->[ 0 ]->{ charges };
    }
    
    return;
}

=head2 $rate_request->get_unique_keys()

=cut

sub get_unique_keys
{
    my $self = shift;
    
    # None at the Business::Shipping level, so do not check parent.
    my @unique_keys = ();
    
    return( @unique_keys );
}

=head2 $rate_request->_gen_unique_values()

=cut

sub _gen_unique_values
{
    trace '()';
    my ( $self ) = @_;
        
    # Now I need to get unique values for all packages.
    
    my @unique_values;
    foreach my $package ( @{$self->packages()} ) {
        push @unique_values, $package->get_unique_values();
    }
    
    # We prefer 0 in the key to represent 'undef'
    # clean it all up...
    my @new_unique_values;
    foreach my $value ( @unique_values ) {
        if ( not defined $value ) {
            $value = 0;
        }
        push @new_unique_values, $value;
    }

    return( @new_unique_values );
}

=head2 $rate_request->calc_debug_string()

Arrange the values of some important variables in a pretty format.
Return a scalar string.

=cut

sub calc_debug_string
{
    my ( $self ) = @_;
    
    my $vars_out .= "\nActual values from the rate_request object\n";
    foreach ( qw/ from_country to_country from_zip to_zip weight service / ) {
        
        my $val = ( $self->can( $_ ) ? $self->$_ : '' ) || '';
        $vars_out .= "\t$_ => \t\t\'" . $val . "\',\n";
    }
    
    return $vars_out;
}

=head2 $rate_request->display_price_components()

Return formatted string of price component information

=cut

sub display_price_components
{
    my ( $self ) = @_;
    return Data::Dumper::Dumper( $self->price_components ) if $self->price_components;
    return;
}

# COMPAT: get_total_charges()
# COMPAT: get_total_price()
# COMPAT: total_charges()

*get_total_charges = *rate;
*get_total_price   = *rate;
*total_charges     = *rate;

1;

__END__

=head1 AUTHOR

Dan Browning E<lt>F<db@kavod.com>E<gt>, Kavod Technologies, L<http://www.kavod.com>.

=head1 COPYRIGHT AND LICENCE

Copyright (c) 2003-2004 Kavod Technologies, Dan Browning. All rights reserved.
This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. See LICENSE for more info.

=cut