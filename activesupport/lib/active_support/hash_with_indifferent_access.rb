require 'active_support/core_ext/hash/keys'

module ActiveSupport
  # Implements a hash where keys <tt>:foo</tt> and <tt>"foo"</tt> are considered
  # to be the same.
  #
  #   rgb = ActiveSupport::HashWithIndifferentAccess.new
  #
  #   rgb[:black] = '#000000'
  #   rgb[:black]  # => '#000000'
  #   rgb['black'] # => '#000000'
  #
  #   rgb['white'] = '#FFFFFF'
  #   rgb[:white]  # => '#FFFFFF'
  #   rgb['white'] # => '#FFFFFF'
  #
  # Internally symbols are mapped to strings when used as keys in the entire
  # writing interface (calling <tt>[]=</tt>, <tt>merge</tt>, etc). This
  # mapping belongs to the public interface. For example, given:
  #
  #   hash = ActiveSupport::HashWithIndifferentAccess.new(a: 1)
  #
  # You are guaranteed that the key is returned as a string:
  #
  #   hash.keys # => ["a"]
  #
  # Technically other types of keys are accepted:
  #
  #   hash = ActiveSupport::HashWithIndifferentAccess.new(a: 1)
  #   hash[0] = 0
  #   hash # => {"a"=>1, 0=>0}
  #
  # but this class is intended for use cases where strings or symbols are the
  # expected keys and it is convenient to understand both as the same. For
  # example the +params+ hash in Ruby on Rails.
  #
  # Note that core extensions define <tt>Hash#with_indifferent_access</tt>:
  #
  #   rgb = { black: '#000000', white: '#FFFFFF' }.with_indifferent_access
  #
  # which may be handy.
  class HashWithIndifferentAccess < Hash
    # Returns +true+ so that <tt>Array#extract_options!</tt> finds members of
    # this class.
    def extractable_options?
      true
    end

    def with_indifferent_access
      dup
    end

    def nested_under_indifferent_access
      self
    end

    def initialize(constructor = {})
      if constructor.is_a?(Hash)
        super()
        update(constructor)
      else
        super(constructor)
      end
    end

    def default(key = nil)
      if key.is_a?(Symbol) && include?(key = key.to_s)
        self[key]
      else
        super
      end
    end

    def self.new_from_hash_copying_default(hash)
      new(hash).tap do |new_hash|
        new_hash.default = hash.default
      end
    end

    def self.[](*args)
      new.merge!(Hash[*args])
    end

    alias_method :regular_writer, :[]= unless method_defined?(:regular_writer)
    alias_method :regular_update, :update unless method_defined?(:regular_update)

    # Assigns a new value to the hash:
    #
    #   hash = ActiveSupport::HashWithIndifferentAccess.new
    #   hash[:key] = 'value'
    #
    # This value can be later fetched using either +:key+ or +'key'+.
    def []=(key, value)
      regular_writer(convert_key(key), convert_value(value, for: :assignment))
    end

    alias_method :store, :[]=

    # Updates the receiver in-place, merging in the hash passed as argument:
    #
    #   hash_1 = ActiveSupport::HashWithIndifferentAccess.new
    #   hash_1[:key] = 'value'
    #
    #   hash_2 = ActiveSupport::HashWithIndifferentAccess.new
    #   hash_2[:key] = 'New Value!'
    #
    #   hash_1.update(hash_2) # => {"key"=>"New Value!"}
    #
    # The argument can be either an
    # <tt>ActiveSupport::HashWithIndifferentAccess</tt> or a regular +Hash+.
    # In either case the merge respects the semantics of indifferent access.
    #
    # If the argument is a regular hash with keys +:key+ and +"key"+ only one
    # of the values end up in the receiver, but which one is unspecified.
    #
    # When given a block, the value for duplicated keys will be determined
    # by the result of invoking the block with the duplicated key, the value
    # in the receiver, and the value in +other_hash+. The rules for duplicated
    # keys follow the semantics of indifferent access:
    #
    #   hash_1[:key] = 10
    #   hash_2['key'] = 12
    #   hash_1.update(hash_2) { |key, old, new| old + new } # => {"key"=>22}
    def update(other_hash)
      if other_hash.is_a? HashWithIndifferentAccess
        super(other_hash)
      else
        other_hash.each_pair do |key, value|
          if block_given? && key?(key)
            value = yield(convert_key(key), self[key], value)
          end
          regular_writer(convert_key(key), convert_value(value))
        end
        self
      end
    end

    alias_method :merge!, :update

    # Checks the hash for a key matching the argument passed in:
    #
    #   hash = ActiveSupport::HashWithIndifferentAccess.new
    #   hash['key'] = 'value'
    #   hash.key?(:key)  # => true
    #   hash.key?('key') # => true
    def key?(key)
      super(convert_key(key))
    end

    alias_method :include?, :key?
    alias_method :has_key?, :key?
    alias_method :member?, :key?

    # Same as <tt>Hash#fetch</tt> where the key passed as argument can be
    # either a string or a symbol:
    #
    #   counters = ActiveSupport::HashWithIndifferentAccess.new
    #   counters[:foo] = 1
    #
    #   counters.fetch('foo')          # => 1
    #   counters.fetch(:bar, 0)        # => 0
    #   counters.fetch(:bar) {|key| 0} # => 0
    #   counters.fetch(:zoo)           # => KeyError: key not found: "zoo"
    def fetch(key, *extras)
      super(convert_key(key), *extras)
    end

    # Returns an array of the values at the specified indices:
    #
    #   hash = ActiveSupport::HashWithIndifferentAccess.new
    #   hash[:a] = 'x'
    #   hash[:b] = 'y'
    #   hash.values_at('a', 'b') # => ["x", "y"]
    def values_at(*indices)
      indices.collect {|key| self[convert_key(key)]}
    end

    # Returns an exact copy of the hash.
    def dup
      self.class.new(self).tap do |new_hash|
        new_hash.default = default
      end
    end

    # This method has the same semantics of +update+, except it does not
    # modify the receiver but rather returns a new hash with indifferent
    # access with the result of the merge.
    def merge(hash, &block)
      self.dup.update(hash, &block)
    end

    # Like +merge+ but the other way around: Merges the receiver into the
    # argument and returns a new hash with indifferent access as result:
    #
    #   hash = ActiveSupport::HashWithIndifferentAccess.new
    #   hash['a'] = nil
    #   hash.reverse_merge(a: 0, b: 1) # => {"a"=>nil, "b"=>1}
    def reverse_merge(other_hash)
      super(self.class.new_from_hash_copying_default(other_hash))
    end

    # Same semantics as +reverse_merge+ but modifies the receiver in-place.
    def reverse_merge!(other_hash)
      replace(reverse_merge( other_hash ))
    end

    # Replaces the contents of this hash with other_hash.
    #
    #   h = { "a" => 100, "b" => 200 }
    #   h.replace({ "c" => 300, "d" => 400 }) #=> {"c"=>300, "d"=>400}
    def replace(other_hash)
      super(self.class.new_from_hash_copying_default(other_hash))
    end

    # Removes the specified key from the hash.
    def delete(key)
      super(convert_key(key))
    end

    def stringify_keys!; self end
    def deep_stringify_keys!; self end
    def stringify_keys; dup end
    def deep_stringify_keys; dup end
    undef :symbolize_keys!
    undef :deep_symbolize_keys!
    def symbolize_keys; to_hash.symbolize_keys! end
    def deep_symbolize_keys; to_hash.deep_symbolize_keys! end
    def to_options!; self end

    def select(*args, &block)
      dup.tap {|hash| hash.select!(*args, &block)}
    end

    # Convert to a regular hash with string keys.
    def to_hash
      _new_hash= {}
      each do |key, value|
        _new_hash[convert_key(key)] = convert_value(value, for: :to_hash)
      end
      Hash.new(default).merge!(_new_hash)
    end

    protected
      def convert_key(key)
        key.kind_of?(Symbol) ? key.to_s : key
      end

      def convert_value(value, options = {})
        if value.is_a? Hash
          if options[:for] == :to_hash
            value.to_hash
          else
            value.nested_under_indifferent_access
          end
        elsif value.is_a?(Array)
          unless options[:for] == :assignment
            value = value.dup
          end
          value.map! { |e| convert_value(e, options) }
        else
          value
        end
      end
  end
end

HashWithIndifferentAccess = ActiveSupport::HashWithIndifferentAccess
