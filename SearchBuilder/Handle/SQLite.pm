
package DBIx::SearchBuilder::Handle::SQLite;
use DBIx::SearchBuilder::Handle;
@ISA = qw(DBIx::SearchBuilder::Handle);

use vars qw($VERSION @ISA $DBIHandle $DEBUG);
use strict;

=head1 NAME

  DBIx::SearchBuilder::Handle::SQLite -- A SQLite specific Handle object

=head1 SYNOPSIS


=head1 DESCRIPTION

This module provides a subclass of DBIx::SearchBuilder::Handle that 
compensates for some of the idiosyncrasies of SQLite.

=head1 METHODS

=head2 DatabaseVersion

Returns the version of the SQLite library which is used, e.g., "2.8.0".
SQLite can only return short variant.

=cut

sub DatabaseVersion {
    my $self = shift;
    return '' unless $self->dbh;
    return $self->dbh->{sqlite_version} || '';
}

=head2 Insert

Takes a table name as the first argument and assumes that the rest of the arguments
are an array of key-value pairs to be inserted.

If the insert succeeds, returns the id of the insert, otherwise, returns
a Class::ReturnValue object with the error reported.

=cut

sub Insert  {
    my $self = shift;
    my $table = shift;
    my %args = ( id => undef, @_);
    # We really don't want an empty id
    
    my $sth = $self->SUPER::Insert($table, %args);
    return unless $sth;

    # If we have set an id, then we want to use that, otherwise, we want to lookup the last _new_ rowid
    $self->{'id'}= $args{'id'} || $self->dbh->func('last_insert_rowid');

    warn "$self no row id returned on row creation" unless ($self->{'id'});
    return( $self->{'id'}); #Add Succeded. return the id
  }



=head2 CaseSensitive 

Returns undef, since SQLite's searches are not case sensitive by default 

=cut

sub CaseSensitive {
    my $self = shift;
    return(1);
}

sub BinarySafeBLOBs { 
    return undef;
}


=head2 DistinctCount STATEMENTREF

takes an incomplete SQL SELECT statement and massages it to return a DISTINCT result count


=cut

sub DistinctCount {
    my $self = shift;
    my $statementref = shift;

    # Wrapper select query in a subselect as Oracle doesn't allow
    # DISTINCT against CLOB/BLOB column types.
    $$statementref = "SELECT count(*) FROM (SELECT DISTINCT main.id FROM $$statementref )";

}



=head2 _BuildJoins

Adjusts syntax of join queries for SQLite.

=cut

#SQLite can't handle 
# SELECT DISTINCT main.*     FROM (Groups main          LEFT JOIN Principals Principals_2  ON ( main.id = Principals_2.id)) ,     GroupMembers GroupMembers_1      WHERE ((GroupMembers_1.MemberId = '70'))     AND ((Principals_2.Disabled = '0'))     AND ((main.Domain = 'UserDefined'))     AND ((main.id = GroupMembers_1.GroupId)) 
#     ORDER BY main.Name ASC
#     It needs
# SELECT DISTINCT main.*     FROM Groups main           LEFT JOIN Principals Principals_2  ON ( main.id = Principals_2.id) ,      GroupMembers GroupMembers_1      WHERE ((GroupMembers_1.MemberId = '70'))     AND ((Principals_2.Disabled = '0'))     AND ((main.Domain = 'UserDefined'))     AND ((main.id = GroupMembers_1.GroupId)) ORDER BY main.Name ASC

sub _BuildJoins {
    my $self = shift;
    my $sb   = shift;

    $self->OptimizeJoins( SearchBuilder => $sb );

    my $join_clause = join ", ", ($sb->Table ." main"), @{ $sb->{'aliases'} };
    my $joins = $sb->{'left_joins'};
    foreach my $join ( keys %{ $sb->{'left_joins'} } ) {
        my $meta = $sb->{'left_joins'}{ $join };
        my $aggregator = $meta->{'entry_aggregator'} || 'AND';

        $join_clause .= $meta->{'alias_string'} . " ON ";
        my @tmp = map {
                ref($_)?
                    $_->{'field'} .' '. $_->{'op'} .' '. $_->{'value'}:
                    $_
            }
            map { ('(', @$_, ')', $aggregator) } values %{ $meta->{'criteria'} };
        pop @tmp;
        $join_clause .= join ' ', @tmp;
    }

    return $join_clause;
}

1;

__END__

=head1 AUTHOR

Jesse Vincent, jesse@fsck.com

=head1 SEE ALSO

perl(1), DBIx::SearchBuilder

=cut
