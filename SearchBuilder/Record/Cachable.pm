# $Header: /raid/cvsroot/DBIx/DBIx-SearchBuilder/SearchBuilder/Record/Cachable.pm,v 1.6 2001/06/19 04:22:32 jesse Exp $
# by Matt Knopp <mhat@netlag.com>

package DBIx::SearchBuilder::Record::Cachable; 

use DBIx::SearchBuilder::Record; 
use DBIx::SearchBuilder::Handle;
@ISA = qw (DBIx::SearchBuilder::Record);

my %_RECORD_CACHE = (); 


# Function: new 
# Type    : class ctor
# Args    : see DBIx::SearchBuilder::Record::new
# Lvalue  : DBIx::SearchBuilder::Record::Cachable

sub new () { 
  my ($class, @args) = @_; 
  my $this = $class->SUPER::new (@args);
 
  if ($this->can(_CacheConfig)) { 
     $this->{'_CacheConfig'}=$this->_CacheConfig();
  }
  else {
     $this->{'_CacheConfig'}=__CachableDefaults::_CacheConfig();
  }

  return ($this);
}



# Function: _RecordCache
# Type    : private instance
# Args    : none
# Lvalue  : hash: RecordCache
# Desc    : Returns a reference to the record cache hash

sub _RecordCache {
    my $this = shift;
    return(\%_RECORD_CACHE);
}


# Function: LoadByCols
# Type    : (overloaded) public instance
# Args    : see DBIx::SearchBuilder::Record::LoadByCols
# Lvalue  : array(boolean, message)

sub LoadByCols { 
  my ($this, %attr) = @_; 

  ## Generate the cache key
  my $cache_key=$this->_gen_cache_key(%attr);

  if (exists $this->_RecordCache->{$cache_key}) { 
    $cache_time = $this->_RecordCache->{$cache_key}{'time'};

    ## Decide if the cache object is too old
    if ((time() - $cache_time) <= $this->{'_CacheConfig'}{'cache_for_sec'}) {
	$this->_fetch($cache_key); 
	return (1, "Fetched from cache");
    }
    else { 
      $this->_gc_expired();
    }
  } 

  ## Fetch from the DB!
  my ($rvalue, $msg) = $this->SUPER::LoadByCols(%attr);
 
  ## Check the return value, if its good, cache it! 
  if ($rvalue) {
    ## Only cache the object if its okay to do so. 
    $this->_store($cache_key) if ($this->{'_CacheConfig'}{'cache_p'});
    return ($rvalue, $msg);
  }
  else { 
    return ($rvalue, $msg);
  }

  return (0, "Unexpected something or other [never hapens].");
}




# Function: _Set
# Type    : (overloaded) public instance
# Args    : see DBIx::SearchBuilder::Record::_Set
# Lvalue  : ?

sub _Set () { 
  my ($this, %attr) = @_; 
  my $cache_key = $this->{'_CacheConfig'}{'cache_key'};

  if (exists $this->_RecordCache->{$cache_key}) {
    $this->_expire($cache_key);
  }
 
  return $this->SUPER::_Set(%attr);

}




# Function: _gc_expired
# Type    : private instance
# Args    : nil
# Lvalue  : 1
# Desc    : Looks at all cached objects and expires if needed. 

sub _gc_expired () { 
  my ($this) = @_; 
  
  foreach $cache_key (keys %{$this->_RecordCache}) {
    my $cache_time = $this->_RecordCache->{$cache_key}{'time'};  
    $this->_expire($cache_key) 
      if ((time() - $cache_time) > $this->{'_CacheConfig'}{'cache_for_sec'});
  }
}




# Function: _expire
# Type    : private instance
# Args    : string(cache_key)
# Lvalue  : 1
# Desc    : Removes this object from the cache. 

sub _expire (\$) {
  my ($this, $cache_key) = @_; 
  delete $this->_RecordCache->{$cache_key} if (exists $this->_RecordCache->{$cache_key});
  return (1);
}




# Function: _fetch
# Type    : private instance
# Args    : string(cache_key)
# Lvalue  : 1
# Desc    : Get an object from the cache, and make this object that. 

sub _fetch () { 
  my ($this, $cache_key) = @_;

  $this->{'values'}  = 
    $this->_RecordCache->{$cache_key}{'obj'}{'values'};
  return(1); 
}




# Function: _store
# Type    : private instance
# Args    : string(cache_key)
# Lvalue  : 1
# Desc    : Stores this object in the cache. 

sub _store (\$) { 
  my ($this, $cache_key) = @_; 
  $this->{'_CacheConfig'}{'cache_key'} = $cache_key;
  $this->_RecordCache->{$cache_key}{'obj'}=$this;
  $this->_RecordCache->{$cache_key}{'time'}=time();
  
  return(1);
}




# Function: _gen_cache_key
# Type    : private instance
# Args    : hash (attr)
# Lvalue  : 1
# Desc    : Takes a perl hash and generates a key from it. 

sub _gen_cache_key {
  my ($this, %attr) = @_;
  my $cache_key=$this->Table() . ':';
  while (my ($key, $value) = each %attr) {
    $cache_key .= $key . '=' . $value . ',';
  }
  chop ($cache_key);
  return ($cache_key);
}




package __CachableDefaults; 

sub _CacheConfig { 
  { 
     'cache_p'        => 1,
     'fast_update_p'  => 1,
     'cache_for_sec'  => 5,
  }
}

1;
