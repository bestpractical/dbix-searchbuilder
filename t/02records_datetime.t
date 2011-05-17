#!/usr/bin/perl -w


use strict;
use warnings;
use Test::More;
BEGIN { require "t/utils.pl" }
our (@AvailableDrivers);

use constant TESTS_PER_DRIVER => 42;

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
    isa_ok($ret,'DBI::st', "Inserted the schema. got a statement handle back");

    my $count_all = init_data( 'TestApp::User', $handle );
    ok( $count_all,  "init users data" );

    my $users_obj = TestApp::Users->new( $handle );
    isa_ok( $users_obj, 'DBIx::SearchBuilder' );
    is( $users_obj->_Handle, $handle, "same handle as we used in constructor");

# try to use $users_obj for all tests, after each call to CleanSlate it should look like new obj.
# and test $obj->new syntax
    my $clean_obj = $users_obj->new( $handle );
    isa_ok( $clean_obj, 'DBIx::SearchBuilder' );

    foreach my $type ('date time', 'DateTime', 'date_time', 'Date-Time') {
        $users_obj->CleanSlate;
        is_deeply( $users_obj, $clean_obj, 'after CleanSlate looks like new object');
        is_deeply(
            get_data( $users_obj, Type => $type ),
            {
                '' => undef,
                '2011-05-20 19:53:23' => '2011-05-20 19:53:23',
            },
        );
    }

    $users_obj->CleanSlate;
    is_deeply( $users_obj, $clean_obj, 'after CleanSlate looks like new object');
    is_deeply(
        get_data( $users_obj, Type => 'time' ),
        {
            '' => undef,
            '2011-05-20 19:53:23' => '19:53:23',
        },
    );

    $users_obj->CleanSlate;
    is_deeply( $users_obj, $clean_obj, 'after CleanSlate looks like new object');
    is_deeply(
        get_data( $users_obj, Type => 'hourly' ),
        {
            '' => undef,
            '2011-05-20 19:53:23' => '2011-05-20 19',
        },
    );

    $users_obj->CleanSlate;
    is_deeply( $users_obj, $clean_obj, 'after CleanSlate looks like new object');
    is_deeply(
        get_data( $users_obj, Type => 'hour' ),
        {
            '' => undef,
            '2011-05-20 19:53:23' => '19',
        },
    );

    foreach my $type ( 'date', 'daily' ) {
        $users_obj->CleanSlate;
        is_deeply( $users_obj, $clean_obj, 'after CleanSlate looks like new object');
        is_deeply(
            get_data( $users_obj, Type => $type ),
            {
                '' => undef,
                '2011-05-20 19:53:23' => '2011-05-20',
            },
        );
    }

    $users_obj->CleanSlate;
    is_deeply( $users_obj, $clean_obj, 'after CleanSlate looks like new object');
    is_deeply(
        get_data( $users_obj, Type => 'day of week' ),
        {
            '' => undef,
            '2011-05-20 19:53:23' => '5',
        },
    );

    foreach my $type ( 'day', 'DayOfMonth' ) {
        $users_obj->CleanSlate;
        is_deeply( $users_obj, $clean_obj, 'after CleanSlate looks like new object');
        is_deeply(
            get_data( $users_obj, Type => $type ),
            {
                '' => undef,
                '2011-05-20 19:53:23' => '20',
            },
        );
    }

    $users_obj->CleanSlate;
    is_deeply( $users_obj, $clean_obj, 'after CleanSlate looks like new object');
    is_deeply(
        get_data( $users_obj, Type => 'day of year' ),
        {
            '' => undef,
            '2011-05-20 19:53:23' => '140',
        },
    );

    $users_obj->CleanSlate;
    is_deeply( $users_obj, $clean_obj, 'after CleanSlate looks like new object');
    is_deeply(
        get_data( $users_obj, Type => 'month' ),
        {
            '' => undef,
            '2011-05-20 19:53:23' => '05',
        },
    );

    $users_obj->CleanSlate;
    is_deeply( $users_obj, $clean_obj, 'after CleanSlate looks like new object');
    is_deeply(
        get_data( $users_obj, Type => 'monthly' ),
        {
            '' => undef,
            '2011-05-20 19:53:23' => '2011-05',
        },
    );

    foreach my $type ( 'year', 'annually' ) {
        $users_obj->CleanSlate;
        is_deeply( $users_obj, $clean_obj, 'after CleanSlate looks like new object');
        is_deeply(
            get_data( $users_obj, Type => $type ),
            {
                '' => undef,
                '2011-05-20 19:53:23' => '2011',
            },
        );
    }

    $users_obj->CleanSlate;
    is_deeply( $users_obj, $clean_obj, 'after CleanSlate looks like new object');
    is_deeply(
        get_data( $users_obj, Type => 'week of year' ),
        {
            '' => undef,
            '2011-05-20 19:53:23' => '20',
        },
    );

    cleanup_schema( 'TestApp', $handle );
}} # SKIP, foreach blocks


sub get_data {
    my $users = shift;
    $users->UnLimit;
    $users->Column( FIELD => 'Expires' );
    my $column = $users->Column(
        ALIAS => 'main',
        FIELD => 'Expires',
        FUNCTION => $users->_Handle->DateTimeFunction( @_ ),
    );

    my %res;
    while ( my $user = $users->Next ) {
        $res{ $user->Expires || '' } = $user->__Value( $column );
    }
    return \%res;
}

1;

package TestApp;

sub schema_mysql {
<<EOF;
CREATE TEMPORARY TABLE Users (
    id integer AUTO_INCREMENT,
    Expires DATETIME NULL,
    PRIMARY KEY (id)
)
EOF

}

sub schema_pg {
<<EOF;
CREATE TEMPORARY TABLE Users (
    id serial PRIMARY KEY,
    Expires TIMESTAMP NULL
)
EOF

}

sub schema_sqlite {

<<EOF;
CREATE TABLE Users (
    id integer primary key,
    Expires TEXT NULL
)
EOF

}

#sub schema_oracle { [
#    "CREATE SEQUENCE Users_seq",
#    "CREATE TABLE Users (
#        id integer CONSTRAINT Users_Key PRIMARY KEY,
#        Login varchar(18) NOT NULL,
#    )",
#] }
#
#sub cleanup_schema_oracle { [
#    "DROP SEQUENCE Users_seq",
#    "DROP TABLE Users", 
#] }


1;

package TestApp::User;

use base $ENV{SB_TEST_CACHABLE}?
    qw/DBIx::SearchBuilder::Record::Cachable/:
    qw/DBIx::SearchBuilder::Record/;

sub _Init {
    my $self = shift;
    my $handle = shift;
    $self->Table('Users');
    $self->_Handle($handle);
}

sub _ClassAccessible {
    {   
        id =>
        {read => 1, type => 'int(11)' }, 
        Expires =>
        {read => 1, write => 1, type => 'datetime' },
    }
}

sub init_data {
    return (
    [ 'Expires' ],
    [ undef, ],
    [ '2011-05-20 19:53:23',     ],
    );
}

1;

package TestApp::Users;

# use TestApp::User;
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


