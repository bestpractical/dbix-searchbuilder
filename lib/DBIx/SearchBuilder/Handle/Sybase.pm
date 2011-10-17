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
    $self->dbh->do( "set identity_insert $table on"  ) if $pairs{id};
    my $sth   = $self->SUPER::Insert( $table, %pairs );
    $self->dbh->do( "set identity_insert $table off" ) if $pairs{id};
    if ( !$sth ) {
        return ($sth);
    }
    
    # Can't select identity column if we're inserting the id by hand.
    unless ($pairs{'id'}) {
        my @row = $self->FetchResult('SELECT @@identity');

        # TODO: Propagate Class::ReturnValue up here.
        unless ( $row[0] ) {
            return (undef);
        }
        $self->{'id'} = $row[0];
    }
    return ( $self->{'id'} );
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


=head2 CaseSensitive 

Returns undef, since Sybase's searches are not case sensitive by default 

=cut

sub CaseSensitive {
    my $self = shift;
    return(1);
}

=head2 ApplyLimits

Uses cursors to implement something that works like the LIMIT statement of
MySQL. Needs the ProcessPostFetch hook to deallocate cursors.

=cut


sub ApplyLimits {
    my $self = shift;
    my $statementref = shift;
    my $per_page = shift;
    my $first = shift;

    if ( $per_page && $first ) {
        # Use a random number for the cursor name to avoid clashes.
        my $cursor_name = 'sb_cursor_' . int(rand(9_000_000) + 1_000_000);
        $first++; # Need to get the next one

        # Create the cursor directly in the database.
        $self->dbh->do( "declare $cursor_name scroll cursor for $$statementref" )
            or die $self->dbh->errstr;
        $self->dbh->do( "open $cursor_name" )
            or die $self->dbh->errstr;
        $self->dbh->do( "set cursor rows $per_page for $cursor_name" )
            or die $self->dbh->errstr;
        $$statementref = "fetch absolute $first $cursor_name";
    }
    elsif ( $per_page ) {
        $$statement_ref =~ s/^select/select top $per_page/i;
    }
}


=head2 DistinctQuery STATEMENTREFtakes an incomplete SQL SELECT statement and massages it to return a DISTINCT result set.


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


=head2 BinarySafeBLOBs

Return undef, as Oracle doesn't support binary-safe CLOBS


=cut

sub BinarySafeBLOBs {
    my $self = shift;
    return(undef);
}

=head2 ProcessPostFetch

Deallocate cursor if one was used.

=cut

sub ProcessPostFetch {
    my $self = shift;
    my $records = shift;
    my $query = shift;
    my ( $cursor_name ) = $query =~ /^fetch absolute \d+ (\w+)$/;
    if $cursor_name {
        $self->dbh->do( "close $cursor_name" );
        $self->dbh->do( "deallocate $cursor_name" );
    }
}

=head2 BuildDSN

This BuildDSN method will enable UTF-8 at output. It will also set the
output date format as ISO in DBD::Sybase. It allows to specify a database
server in the interfaces file using Server => "SERVERNAME".

=cut

sub BuildDSN {
    my $self = shift;
    my $args = ( Driver => 'Sybase',
                 Database => undef,
                 Host => undef,
                 Port => undef,
                 Server => undef,
                 Charset => undef,
                 @_ );

    my $dsn = "dbi:$args{Driver}(syb_enable_utf8=>1,syb_date_fmt=>ISO)";
    if ( $args{Server} ) {
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

=head2 Fields

DBD::Sybase needs a different Fields method since column_info behaves
differently.

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

=head2 _BuildJoins

Sybase does not like CROSS JOIN.

=cut

sub _BuildJoins {
    my $self = shift;
    my $join_clause = $self->SUPER::_BuildJoins(@_);
    $join_clause =~ s/CROSS JOIN /, /g;
    return $join_clause;
}

=head2 InsertQueryString

Sybase does not like dynamic PREPARE statements that refer to
TEXT, IMAGE or UNITEXT. So we avoid dynamic PREPARE statements
entirely.

=cut

sub InsertQueryString {
    my ( $self, $table, @pairs ) = @_;
    my ( @cols, @vals, @bind );

    while ( my $key = shift @pairs ) {
        my $val = shift @pairs;
        push @cols, $key;
		my $data_type = $self->FieldDataType( $table, $key );
		my $quotedval = $self->dbh->quote( $val, $data_type );
		push @vals, $quotedval;
    }

    my $QueryString = "INSERT INTO $table";
    $QueryString .= " (". join(", ", @cols) .")";
    $QueryString .= " VALUES (". join(",", @vals). ")";
    return ( $QueryString, @bind );
}

=head2 UpdateRecordValue

Sybase does not like dynamic PREPARE statements that refer to
TEXT, IMAGE or UNITEXT. So we avoid dynamic PREPARE statements
entirely.

=cut

sub UpdateRecordValue {
    my $self = shift;
    my %args = (
		Table			=> undef,
		Column			=> undef,
		IsSQLFunction	=> undef,
		PrimaryKeys		=> undef,
		@_
	);

    my @bind = ();
    my $query = 'UPDATE ' . $args{Table}  . ' SET ' . $args{Column} . ' = ';

	my $data_type = $self->FieldDataType( $args{Table}, $args{Column} );
	my $quotedval = $self->dbh->quote( $args{Value}, $data_type );
	$query .= $quotedval;
	
	## Constructs the where clause.
	my $where  = ' WHERE ';
	foreach my $key ( keys %{ $args{PrimaryKeys} } ) {
		my $data_type = $self->FieldDataType( $args{Table}, $key );
		$quotedval =
            $self->dbh->quote( $args{PrimaryKeys}{$key}, $data_type );
		$where .= "$key = $quotedval AND ";
	}
  
	$where =~ s/\s*AND\s*$//;

	my $query_str = $query . $where;
	$self->SimpleQuery( $query_str, @bind );
}

1;

__END__

=head1 AUTHOR

Jesse Vincent, jesse@fsck.com

=head1 SEE ALSO

DBIx::SearchBuilder, DBIx::SearchBuilder::Handle

=cut
