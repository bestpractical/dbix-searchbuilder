#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More;

use constant TESTS_PER_DRIVER => 4;

our @AvailableDrivers;
BEGIN { require "t/utils.pl" }

use DBIx::SearchBuilder::Handle;

my $total = scalar(@AvailableDrivers) * TESTS_PER_DRIVER;
plan tests => $total;

foreach my $d ( @AvailableDrivers ) {
SKIP: {
    unless ($d eq 'Pg') {
        skip "first goal is to work on Pg", TESTS_PER_DRIVER;
    }
	unless( should_test( $d ) ) {
		skip "ENV is not defined for driver '$d'", TESTS_PER_DRIVER;
	}

    my $handle = get_handle( $d );
    connect_handle( $handle );
    init_schema( 'TestApp::Address', $handle );

    is_deeply(
        [$handle->Fields('Address')],
        [qw(id name phone employeeid)],
        "listed all columns in the table for $d"
    );
    is_deeply(
        [$handle->Fields('Other')],
        ['id'],
        "'Other' is not seen when a schema is specified"
    );

    $handle->dbh(undef);
    connect_handle( $handle );
    local $DBIx::SearchBuilder::Handle::DBSchema = 'public';

    is_deeply(
        [$handle->Fields('Address')],
        [qw(id name phone employeeid)],
        "listed all columns in the table for $d"
    );
    is_deeply(
        [$handle->Fields('Other')],
        [],
        "'Other' is not seen when a schema is specified"
    );

	cleanup_schema( 'TestApp::Address', $handle );
}} # SKIP, foreach blocks

1;



package TestApp::Address;

use base $ENV{SB_TEST_CACHABLE}?
    qw/DBIx::SearchBuilder::Record::Cachable/:
    qw/DBIx::SearchBuilder::Record/;

sub _Init {
    my $self = shift;
    my $handle = shift;
    $self->Table('Address');
    $self->_Handle($handle);
}

sub ValidateName
{
	my ($self, $value) = @_;
	return 0 if $value =~ /invalid/i;
	return 1;
}

sub _ClassAccessible {

    {
        id =>
        {read => 1, type => 'int(11)', default => ''},
        Name =>
        {read => 1, write => 1, type => 'varchar(14)', default => ''},
        Phone =>
        {read => 1, write => 1, type => 'varchar(18)', length => 18, default => ''},
        EmployeeId =>
        {read => 1, write => 1, type => 'int(8)', default => ''},
    }

}

sub schema_pg {
<<EOF;
CREATE SCHEMA otherapp CREATE TABLE Other (id serial PRIMARY KEY);
CREATE TABLE public.Address (
        id serial PRIMARY KEY,
        Name varchar,
        Phone varchar,
        EmployeeId integer
);
EOF
}

# Can't create temporary tables in a schema
sub cleanup_schema_pg {
<<EOF;
DROP SCHEMA otherapp CASCADE;
DROP TABLE public.Address;
EOF
}

1;
