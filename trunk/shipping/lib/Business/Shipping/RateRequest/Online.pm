# Business::Shipping::RateRequest::Online - Abstract class for shipping cost rating.
# 
# $Id: Online.pm,v 1.4 2003/08/20 12:58:48 db-ship Exp $
# 
# Copyright (c) 2003 Kavod Technologies, Dan Browning. All rights reserved. 
# 
# Licensed under the GNU Public Licnese (GPL).  See COPYING for more info.
# 

package Business::Shipping::RateRequest::Online;

use strict;
use warnings;

use vars qw( $VERSION );
$VERSION = do { my @r=(q$Revision: 1.4 $=~/\d+/g); sprintf "%d."."%03d"x$#r,@r };
use base ( 'Business::Shipping::RateRequest' );

use Business::Shipping::Debug;
use XML::Simple;
use LWP::UserAgent;
use Cache::FileCache;
use Business::Shipping::CustomMethodMaker
	new_hash_init => 'new',
	boolean => [ 'test_mode' ],
	get_set => [ 'user_id', 'password' ],
	grouped_fields_inherit => [
		required => [ 'user_id', 'password' ],
		optional => [ 'prod_url', 'test_url' ],
	],
	object => [
		'LWP::UserAgent' => {
			slot => 'user_agent',
		},
		'HTTP::Response' => {
			slot => 'response',
		}
	];



sub perform_action
{
	my $self = shift;	
	my $request = $self->_gen_request();
	trace( 'Please wait while we get a response from the server...' );
	$self->response( $self->_get_response( $request ) );
	#debug3( "response content = " . $self->response()->content() );
	
	if ( ! $self->response()->is_success() ) { 
		$self->error( 	
						"HTTP Error. Status line: " . $self->response->status_line .
						"Content: " . $self->response->content() 
					); 
	}
	
	return ( undef );
}

sub _gen_url
{
	trace( '()' );
	my ( $self ) = shift;
	
	return( $self->test_mode() ? $self->test_url() : $self->prod_url() );
}

sub _gen_request
{
	trace( '()' );
	my ( $self ) = shift;
	
	my $request_xml = $self->_gen_request_xml();
	#debug3( $request_xml );
	my $request = HTTP::Request->new( 'POST', $self->_gen_url() );
	$request->header( 'content-type' => 'application/x-www-form-urlencoded' );
	$request->header( 'content-length' => length( $request_xml ) );
	$request->content( $request_xml );
	
	return ( $request );
}

sub _get_response
{
	trace( '()' );
	return $_[0]->user_agent->request( $_[1] );
}


1;