#!/usr/bin/perl -w

use strict;

=head1 VARIABLES

=head2 @SupportedDrivers

Array of all supported DBD drivers.

=cut

our @SupportedDrivers = qw(
	Informix
	mysql
	mysqlPP
	ODBC
	Oracle
	Pg
	SQLite
	Sybase
);

our @AvailableDrivers = grep { eval "require DBD::". $_ } @SupportedDrivers;

Array that lists only drivers from supported list
that user has installed.

=cut

our @AvailableDrivers = grep { eval "require DBD::". $_ } @SupportedDrivers;

=head1 FUNCTIONS

=head2 get_handle

Returns new DB specific handle. Takes one argument DB C<$type>.
Other arguments uses to construct handle.

=cut

sub get_handle
{
	my $type = shift;
	my $class = 'DBIx::SearchBuilder::Handle::'. $type;
	eval "require $class";
	die $@ if $@;
	my $handle;
	$handle = $class->new( @_ );
	return $handle;
}

sub connect_handle
{
	my $class = lc ref($_[0]);
	$class =~ s/^.*:://;
	my $call = "connect_$class";

	return unless defined &$call;
	goto &$call;
}

sub connect_sqlite
{
	my $handle = shift;
	return $handle->Connect( Driver => 'SQLite', Database => File::Spec->catfile(File::Spec->tmpdir(), "sb-test.$$"));
}


1;
