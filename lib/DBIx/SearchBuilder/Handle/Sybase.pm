# $Header: /home/jesse/DBIx-SearchBuilder/history/SearchBuilder/Handle/Sybase.pm,v 1.8 2001/10/12 05:27:05 jesse Exp $

package DBIx::SearchBuilder::Handle::Sybase;

use strict;
use warnings;

use base qw(DBIx::SearchBuilder::Handle);

our %FIELDS_IN_TABLE;

=head1 NAME

  DBIx::SearchBuilder::Handle::Sybase -- a Sybase specific Handle object

=head1 SYNOPSIS


=head1 DESCRIPTION

This module provides a subclass of DBIx::SearchBuilder::Handle that 
compensates for some of the idiosyncrasies of Sybase.

=head1 METHODS

=cut


=head2 Insert

Takes a table name as the first argument and assumes that the rest of the arguments
are an array of key-value pairs to be inserted.

If the insert succeeds, returns the id of the insert, otherwise, returns
a Class::ReturnValue object with the error reported.

=cut

sub Insert {
    my $self  = shift;

    my $table = shift;
    my %pairs = @_;
    my $sth   = $self->SUPER::Insert( $table, %pairs );
    if ( !$sth ) {
        return ($sth);
    }
    
    # Can't select identity column if we're inserting the id by hand.
    unless ($pairs{'id'}) {
        my @row = $self->FetchResult('SELECT @@identity');

        # TODO: Propagate Class::ReturnValue up here.
        unless ( $row[0] ) {
            @row = $self->FetchResult("SELECT MAX(id) FROM $table");
        }
        unless ( $row[0] ) {
            return (undef);
        }
        $self->{'id'} = $row[0];
    }
    return ( $self->{'id'} );
}


=head2 BuildDSN

In addition to the attributes supported by DBIx::SearchBuilder::Handle, this module
supports Server, Charset and attributes.

=cut

sub BuildDSN {
    my $self = shift;
    my %args = ( Driver => 'Sybase',
                 Database => undef,
                 Host => undef,
                 Port => undef,
                 Server => undef,
                 Charset => undef,
                 @_ );

    my $dsn = "dbi:$args{Driver}(syb_enable_utf8=>1)";
    if ($args{Server}) {
        $dsn .= ":server=$args{Server}";
    }
    else {
        $dsn .= ":host=$args{Host}";
        $dsn .= ";port=$args{Port}" if $args{Port};
    }
    $dsn .= ";database=$args{Database}" if $args{Database};
    $dsn .= ";charset=$args{Charset}"   if $args{Charset};
    $self->{dsn} = $dsn;
}



=head2 CaseSensitive 

Returns undef, since Sybase's searches are not case sensitive by default 

=cut

sub CaseSensitive {
    my $self = shift;
    return(1);
}


=head2 ApplyLimits

Sybase does not implement MySQL's LIMIT clause for SELECT statements. So ApplyLimits
uses a scrollable cursor to achieve the same results. The output of this method can
only be fed to this object's SimpleQuery() method to do something meaningful, since
it needs to perform multiple database queries. The corresponding DeallocateCursor()
method will clean up after ApplyLimits().

=cut


sub ApplyLimits {
    my $self = shift;
    my $statementref = shift;
    my $per_page = shift;
    my $first = shift;

    if ($per_page && $first) {
        # Use a random number for the cursor name to avoid clashes.
        my $cursor_name = 'sb_cursor_' . int(rand(9_000_000) + 1_000_000);

        $first++; # Need to get the next one
        # Construct the cursor query
        $$statementref = "declare $cursor_name scroll cursor for $$statementref\n"
                       . "go\n"
                       . "open $cursor_name\n"
                       . "set cursor rows $per_page for $cursor_name\n"
                       . "fetch absolute $first $cursor_name";
    } elsif ($per_page) {
        $$statementref =~ s/^select/select top $per_page/i;
    }
}

sub DeallocateCursor {
    my $self = shift;
    my $query = shift;
    
    my $cursor_name;
    if ($query =~ /(sb_cursor_\d+)/) {
        $cursor_name = $1;
        $self->dbh->do("close $cursor_name\ndeallocate $cursor_name")
            or die $self->dbh->errstr;
    }
}


=head2 SimpleQuery QUERY_STRING, [ BIND_VALUE, ... ]

Decouple the query if there's a cursor to declare. Run the cursor declaration first,
then run the rest of the query using our superclass' SimpleQuery() method.

=cut

sub SimpleQuery {
    my $self = shift;
    my $query = shift;

    my @queries = split /\ngo\n/, $query;
    while (@queries > 1) {
        $self->dbh->do(shift @queries) or die $self->dbh->errstr;
    }
    return $self->SUPER::SimpleQuery(shift @queries, @_);
}


=head2 DistinctQuery STATEMENTREF

Takes an incomplete SQL SELECT statement and massages it to return a DISTINCT result set.

=cut

sub DistinctQuery {
    my $self = shift;
    my $statementref = shift;
    my $sb = shift;
    my $table = $sb->Table;
    if ($sb->_OrderClause =~ /(?<!main)\./) {
        # Don't know how to do ORDER BY when the DISTINCT is in a subquery
        warn "Query will contain duplicate rows; don't how how to ORDER BY across DISTINCT";
        $$statementref = "SELECT main.* FROM $$statementref";
    } else {
        # Wrapper select query in a subselect as Sybase doesn't allow
        # DISTINCT against CLOB/BLOB column types.
        $$statementref = "SELECT main.* FROM ( SELECT DISTINCT main.id FROM $$statementref ) distinctquery, $table main WHERE (main.id = distinctquery.id) ";
    }
    $$statementref .= $sb->_GroupClause;
    $$statementref .= $sb->_OrderClause;
}


=head2 Fields

New Fields function because column_info is different in DBD::Sybase

=cut

sub Fields {
    my $self  = shift;
    my $table = shift;

    unless ( keys %FIELDS_IN_TABLE ) {
        my $sth = $self->dbh->column_info( undef, undef, $table, undef )
            or return ();
        my $info = $sth->fetchall_arrayref({});
        foreach my $e ( @$info ) {
            push @{ $FIELDS_IN_TABLE{ lc $e->{'TABLE_NAME'} } ||= [] },
                 lc $e->{'COLUMN_NAME'};
        }
    }

    return @{ $FIELDS_IN_TABLE{ lc $table } || [] };
}

=head2 DatabaseVersion [Short => 1]

Returns the database's version.

If argument C<Short> is true returns short variant, in other
case returns whatever database handle/driver returns. By default
returns short version, e.g. 15.0.2.

Returns empty string on error or if database couldn't return version.

=cut

sub DatabaseVersion {
    my $self = shift;
    my %args = ( Short => 1, @_ );

    unless ( defined $self->{'database_version'} ) {
        # turn off error handling, store old values to restore later
        my $re = $self->RaiseError;
        $self->RaiseError(0);
        my $pe = $self->PrintError;
        $self->PrintError(0);

        my $statement = 'select @@version';
        my $sth       = $self->SimpleQuery($statement);
        my $ver = $sth->fetchrow_arrayref->[0] || '' if $sth;
        my ($short_ver) = $ver =~ /((?:\d+\.)+\d+)/;
        $self->{database_version} = $ver;
        $self->{database_version_short} = $short_ver;

        $self->RaiseError($re);
        $self->PrintError($pe);
    }

    return $self->{'database_version_short'} if $args{'Short'};
    return $self->{'database_version'};
}


1;

=head2 SimpleDateTimeFunctions

See L</DateTimeFunction> for details on supported functions.
This method is for implementers of custom DB connectors.

Returns hash reference with (function name, sql template) pairs.

=cut

sub SimpleDateTimeFunctions {
    my $self = shift;
    return {
        datetime       => 'str_replace(convert(varchar(19), ?, 23), "T", " ")',
        time           => 'convert(varchar(8), ?, 8)',

        hourly         => 'str_replace(convert(varchar(13), ?, 23), "T", " ")',
        hour           => 'datepart(hour, ?)',

        date           => 'convert(varchar(10), ?, 23)',
        daily          => 'convert(varchar(10), ?, 23)',

        day            => 'day(?)',
        dayofmonth     => 'day(?)',

        monthly        => 'convert(varchar(7), ?, 23)',
        month          => 'month(?)',

        annually       => 'year(?)',
        year           => 'year(?)',
        
        dayofweek      => 'datepart(weekday, ?) - 1',
        dayofyear      => 'datepart(dayofyear, ?)',
        weekofyear     => 'datepart(calweekofyear, ?)',
    };
}

__END__

=head1 AUTHOR

Jesse Vincent, jesse@fsck.com

=head1 SEE ALSO

DBIx::SearchBuilder, DBIx::SearchBuilder::Handle

=cut
