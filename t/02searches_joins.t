#!/usr/bin/perl -w

use strict;
use File::Spec;
use Test::More;

BEGIN { require "t/utils.pl" }
our (@AvailableDrivers);

use constant TESTS_PER_DRIVER => 17;

my $total = scalar(@AvailableDrivers) * TESTS_PER_DRIVER;
plan tests => $total;

foreach my $d ( @AvailableDrivers ) {
SKIP: {
	unless( has_schema( 'TestApp', $d ) ) {
		skip "No schema for '$d' driver", TESTS_PER_DRIVER;
	}
	unless( should_test( $d ) ) {
		skip "ENV is not defined for driver '$d'", TESTS_PER_DRIVER;
	}

	my $handle = get_handle( $d );
	connect_handle( $handle );
	isa_ok($handle->dbh, 'DBI::db');

	my $ret = init_schema( 'TestApp', $handle );
	isa_ok($ret, 'DBI::st', "Inserted the schema. got a statement handle back");

	my $count_users = init_data( 'TestApp::User', $handle );
	ok( $count_users,  "init users data" );
	my $count_groups = init_data( 'TestApp::Group', $handle );
	ok( $count_groups,  "init groups data" );
	my $count_us2gs = init_data( 'TestApp::UsersToGroup', $handle );
	ok( $count_us2gs,  "init users&groups relations data" );

	# simple JOIN
	my $users_obj = TestApp::Users->new( $handle );
	ok( !$users_obj->_isJoined, "new object isn't joined");
	my $alias = $users_obj->Join( FIELD1 => 'id',
				      TABLE2 => 'UsersToGroups',
				      FIELD2 => 'UserId' );
	ok( $alias, "Join returns alias" );
        TODO: {
        	local $TODO = "is joined doesn't mean is limited, count returns 0";
		is( $users_obj->Count, 3, "three users are members of the groups" );
        }
	# fake limit to check if join actually joins
        $users_obj->Limit( FIELD => 'id', OPERATOR => 'IS NOT', VALUE => 'NULL' );
        is( $users_obj->Count, 3, "three users are members of the groups" );

	# LEFT JOIN
	$users_obj->CleanSlate;
	ok( !$users_obj->_isJoined, "new object isn't joined");
	$alias = $users_obj->Join( TYPE   => 'LEFT',
			           FIELD1 => 'id',
				   TABLE2 => 'UsersToGroups',
				   FIELD2 => 'UserId' );
	ok( $alias, "Join returns alias" );
        $users_obj->Limit( ALIAS => $alias, FIELD => 'id', OPERATOR => 'IS', VALUE => 'NULL' );
        is( $users_obj->Count, 1, "user is not member of any group" );
        is( $users_obj->First->id, 3, "correct user id" );

	# JOIN via existan alias
	$users_obj->CleanSlate;
	ok( !$users_obj->_isJoined, "new object isn't joined");
	$alias = $users_obj->NewAlias( 'UsersToGroups' );
	ok( $alias, "new alias" );
	ok($users_obj->Join( TYPE   => 'LEFT',
			     FIELD1 => 'id',
			     ALIAS2 => $alias,
			     FIELD2 => 'UserId' ),
		"joined table"
	);
        $users_obj->Limit( ALIAS => $alias, FIELD => 'id', OPERATOR => 'IS', VALUE => 'NULL' );
	TODO: {
		local $TODO = "JOIN with ALIAS2 is broken";
	        is( $users_obj->Count, 1, "user is not member of any group" );
	}


	cleanup_schema( 'TestApp', $handle );

}} # SKIP, foreach blocks

1;


package TestApp;
sub schema_sqlite {
[
q{
CREATE TABLE Users (
	id integer primary key,
	Login varchar(36)
) },
q{
CREATE TABLE UsersToGroups (
	id integer primary key,
	UserId  integer,
	GroupId integer
) },
q{
CREATE TABLE Groups (
	id integer primary key,
	Name varchar(36)
) },
]
}

sub schema_mysql {
[
q{
CREATE TEMPORARY TABLE Users (
	id integer primary key AUTO_INCREMENT,
	Login varchar(36)
) },
q{
CREATE TEMPORARY TABLE UsersToGroups (
	id integer primary key AUTO_INCREMENT,
	UserId  integer,
	GroupId integer
) },
q{
CREATE TEMPORARY TABLE Groups (
	id integer primary key AUTO_INCREMENT,
	Name varchar(36)
) },
]
}

sub schema_pg {
[
q{
CREATE TEMPORARY TABLE Users (
	id serial primary key,
	Login varchar(36)
) },
q{
CREATE TEMPORARY TABLE UsersToGroups (
	id serial primary key,
	UserId integer,
	GroupId integer
) },
q{
CREATE TEMPORARY TABLE Groups (
	id serial primary key,
	Name varchar(36)
) },
]
}

package TestApp::User;

use base qw/DBIx::SearchBuilder::Record/;

sub _Init {
    my $self = shift;
    my $handle = shift;
    $self->Table('Users');
    $self->_Handle($handle);
}

sub _ClassAccessible {
    {   
        
        id =>
        {read => 1, type => 'int(11)'}, 
        Login => 
        {read => 1, write => 1, type => 'varchar(36)'},

    }
}

sub init_data {
    return (
	[ 'Login' ],

	[ 'ivan' ],
	[ 'john' ],
	[ 'bob' ],
	[ 'aurelia' ],
    );
}

package TestApp::Users;

use base qw/DBIx::SearchBuilder/;

sub _Init {
    my $self = shift;
    $self->SUPER::_Init( Handle => shift );
    $self->Table('Users');
}

sub NewItem
{
	my $self = shift;
	return TestApp::User->new( $self->_Handle );
}

1;

package TestApp::Group;

use base qw/DBIx::SearchBuilder::Record/;

sub _Init {
    my $self = shift;
    my $handle = shift;
    $self->Table('Groups');
    $self->_Handle($handle);
}

sub _ClassAccessible {
    {   
        id =>
        {read => 1, type => 'int(11)'}, 
        Name => 
        {read => 1, write => 1, type => 'varchar(36)'},
    }
}

sub init_data {
    return (
	[ 'Name' ],

	[ 'Developers' ],
	[ 'Sales' ],
	[ 'Support' ],
    );
}

package TestApp::Groups;

use base qw/DBIx::SearchBuilder/;

sub _Init {
    my $self = shift;
    $self->SUPER::_Init( Handle => shift );
    $self->Table('Groups');
}

sub NewItem { return TestApp::Group->new( (shift)->_Handle ) }

1;

package TestApp::UsersToGroup;

use base qw/DBIx::SearchBuilder::Record/;

sub _Init {
    my $self = shift;
    my $handle = shift;
    $self->Table('UsersToGroups');
    $self->_Handle($handle);
}

sub _ClassAccessible {
    {   
        
        id =>
        {read => 1, type => 'int(11)'}, 
        UserId =>
        {read => 1, type => 'int(11)'}, 
        GroupId =>
        {read => 1, type => 'int(11)'}, 
    }
}

sub init_data {
    return (
	[ 'GroupId',	'UserId' ],
# dev group
	[ 1,		1 ],
	[ 1,		2 ],
	[ 1,		4 ],
# sales
#	[ 2,		0 ],
# support
	[ 3,		1 ],
    );
}

package TestApp::UsersToGroups;

use base qw/DBIx::SearchBuilder/;

sub _Init {
    my $self = shift;
    $self->Table('UsersToGroups');
    return $self->SUPER::_Init( Handle => shift );
}

sub NewItem { return TestApp::UsersToGroup->new( (shift)->_Handle ) }

1;
