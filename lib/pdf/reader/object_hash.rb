# coding: utf-8

class PDF::Reader
  # Provides low level access to the objects in a PDF file via a hash-like
  # object.
  #
  # A PDF file can be viewed as a large hash map. It is a series of objects
  # stored at precise byte offsets, and a table that maps object IDs to byte
  # offsets. Given an object ID, looking up an object is an O(1) operation.
  #
  # Each PDF object can be mapped to a ruby object, so by passing an object
  # ID to the [] method, a ruby representation of that object will be
  # retrieved.
  #
  # The class behaves much like a standard Ruby hash, including the use of
  # the Enumerable mixin. The key difference is no []= method - the hash
  # is read only.
  #
  # == Basic Usage
  #
  #     h = PDF::Reader::ObjectHash.new("somefile.pdf")
  #     h[1]
  #     => 3469
  #
  #     h[PDF::Reader::Reference.new(1,0)]
  #     => 3469
  #
  class ObjectHash
    include Enumerable

    attr_accessor :default
    attr_reader :trailer, :pdf_version

    # Creates a new ObjectHash object. input can be a string with a valid filename,
    # a string containing a PDF file, or an IO object.
    #
    def initialize(input = nil)
      if input.nil?
        @io = StringIO.new
      elsif input.respond_to?(:seek) && input.respond_to?(:read)
        @io = input
      elsif File.file?(input.to_s)
        if File.respond_to?(:binread)
          input = File.binread(input.to_s)
        else
          input = File.read(input.to_s)
        end
        @io = StringIO.new(input)
      else
        raise ArgumentError, "input must be an IO-like object or a filename"
      end

      @cache       = PDF::Reader::ObjectCache.new
      @mem_objects = {}

      if input
        @xref        = PDF::Reader::XRef.new(@io)
        @pdf_version = read_version
        @trailer     = @xref.trailer
      else
        @xref        = {}
        @pdf_version = 1.3
        pages        = ref({:Type => :Pages, :Kids => [], :Count => 0})
        root         = ref({:Type => :Catalog, :Pages => pages})
        @trailer     = {:Root => root}
      end

      if trailer[:Encrypt]
        raise ::PDF::Reader::EncryptedPDFError, 'PDF::Reader cannot read encrypted PDF files'
      end
    end

    # returns the type of object a ref points to
    def obj_type(ref)
      self[ref].class.to_s.to_sym
    rescue
      nil
    end

    # returns true if the supplied references points to an object with a stream
    def stream?(ref)
      self[ref].class == PDF::Reader::Stream
    rescue
      false
    end

    # Access an object from the PDF. key can be an int or a PDF::Reader::Reference
    # object.
    #
    # If an int is used, the object with that ID and a generation number of 0 will
    # be returned.
    #
    # If a PDF::Reader::Reference object is used the exact ID and generation number
    # can be specified.
    #
    def [](key)
      return default if key.to_i <= 0
      begin
        unless key.kind_of?(PDF::Reader::Reference)
          key = PDF::Reader::Reference.new(key.to_i, 0)
        end
        if @mem_objects.has_key?(key)
          @mem_objects[key]
        elsif @cache.has_key?(key)
          @cache[key]
        elsif xref[key].is_a?(Fixnum)
          buf = new_buffer(xref[key])
          @cache[key] = Parser.new(buf, self).object(key.id, key.gen)
        elsif xref[key].is_a?(PDF::Reader::Reference)
          container_key = xref[key]
          object_streams[container_key] ||= PDF::Reader::ObjectStream.new(object(container_key))
          @cache[key] = object_streams[container_key][key.id]
        end
      rescue InvalidObjectError
        return default
      end
    end

    def []=(key, val)
      key = PDF::Reader::Reference.new(key, 0) if key.is_a?(Fixnum)

      if !key.is_a?(PDF::Reader::Reference)
        raise ArgumentError, "key must be an int or PDF::Reader::Reference"
      elsif xref[key]
        @mem_objects[key] = val
      else
        raise ArgumentError, "only existing objects can be replaced"
      end
    end

    def ref(obj)
      if @xref.respond_to?(:last_ref)
        max_ref = [@xref.last_ref, @mem_objects.keys.sort.last].compact.max
      else
        max_ref = @mem_objects.keys.sort.last
      end
      if max_ref
        new_ref = PDF::Reader::Reference.new(max_ref.id + 1, 0)
      else
        new_ref = PDF::Reader::Reference.new(1, 0)
      end
      @mem_objects[new_ref] = obj
      new_ref
    end

    # If key is a PDF::Reader::Reference object, lookup the corresponding
    # object in the PDF and return it. Otherwise return key untouched.
    #
    def object(key)
      key.is_a?(PDF::Reader::Reference) ? self[key] : key
    end
    alias :deref :object

    # Access an object from the PDF. key can be an int or a PDF::Reader::Reference
    # object.
    #
    # If an int is used, the object with that ID and a generation number of 0 will
    # be returned.
    #
    # If a PDF::Reader::Reference object is used the exact ID and generation number
    # can be specified.
    #
    # local_default is the object that will be returned if the requested key doesn't
    # exist.
    #
    def fetch(key, local_default = nil)
      obj = self[key]
      if obj
        return obj
      elsif local_default
        return local_default
      else
        raise IndexError, "#{key} is invalid" if key.to_i <= 0
      end
    end

    # iterate over each key, value. Just like a ruby hash.
    #
    def each(&block)
      keys.each do |ref|
        yield ref, self[ref]
      end
    end
    alias :each_pair :each

    # iterate over each key. Just like a ruby hash.
    #
    def each_key(&block)
      keys.each do |id, obj|
        yield id
      end
    end

    # iterate over each value. Just like a ruby hash.
    #
    def each_value(&block)
      each do |id, obj|
        yield obj
      end
    end

    # return the number of objects in the file. An object with multiple generations
    # is counted once.
    def size
      keys.size
    end
    alias :length :size

    # return true if there are no objects in this file
    #
    def empty?
      size == 0
    end

    # return true if the specified key exists in the file. key
    # can be an int or a PDF::Reader::Reference
    #
    def has_key?(check_key)
      if check_key.is_a?(PDF::Reader::Reference)
        keys.include?(check_key)
      else
        keys.any? { |k| k.id == check_key.to_i }
      end
    end
    alias :include? :has_key?
    alias :key? :has_key?
    alias :member? :has_key?

    # return true if the specifiedvalue exists in the file
    #
    def has_value?(value)
      # TODO update from O(n) to O(1)
      each_value do |obj|
        return true if obj == value
      end
      return false
    end
    alias :value? :has_key?

    def to_s
      "<PDF::Reader::ObjectHash size: #{self.size}>"
    end

    # return an array of all keys in the file
    #
    def keys
      ret = []
      @xref.each do |ref|
        ret << ref
      end
      @mem_objects.keys.each do |ref|
        ret << ref
      end
      ret.uniq.sort
    end

    # return an array of all values in the file
    #
    def values
      ret = []
      each_value { |v| ret << v }
      ret
    end

    # return an array of all values from the specified keys
    #
    def values_at(*ids)
      ids.map { |id| self[id] }
    end

    # return an array of arrays. Each sub array contains a key/value pair.
    #
    def to_a
      ret = []
      each do |id, obj|
        ret << [id, obj]
      end
      ret
    end

    # returns an array of PDF::Reader::References. Each reference in the
    # array points a Page object, one for each page in the PDF. The first
    # reference is page 1, second reference is page 2, etc.
    #
    # Useful for apps that want to extract data from specific pages.
    #
    def page_references
      root  = fetch(trailer[:Root])
      @page_references ||= get_page_objects(root[:Pages]).flatten
    end

    # render the current set of objects into a fresh PDF
    #
    def to_s
      FileWriter.new(self).to_s
    end

    # save the current set of objects into a fresh PDF and write it to disk
    #
    def save(filename)
      Kernel.const_defined?("Encoding") ? mode = "wb:ASCII-8BIT" : mode = "wb"
      File.open(filename, mode) { |f| f << self.to_s }
    end

    private

    def new_buffer(offset = 0)
      PDF::Reader::Buffer.new(@io, :seek => offset)
    end

    def xref
      @xref
    end

    def object_streams
      @object_stream ||= {}
    end

    # returns a nested array of object references for all pages in this object store.
    #
    def get_page_objects(ref)
      obj = fetch(ref)

      if obj[:Type] == :Page
        ref
      elsif obj[:Type] == :Pages
        obj[:Kids].map { |kid| get_page_objects(kid) }
      end
    end

    def read_version
      @io.seek(0)
      m, version = *@io.read(10).match(/PDF-(\d.\d)/)
      @io.seek(0)
      version.to_f
    end

  end
end
