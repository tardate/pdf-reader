# coding: utf-8

class PDF::Reader

  # converts an ObjectHash to a PDF. The rendered file can be returned as
  # a String or written to disk.
  #
  class FileWriter
    def initialize(objects)
      @objects = objects
    end

    def to_s
      output = StringIO.new

      render_header(output)
      offsets = render_body(output)
      render_xref(output, offsets)
      render_trailer(output, offsets)
      str = output.string
      str.force_encoding("ASCII-8BIT") if str.respond_to?(:force_encoding)
      str
    end

    def save_to_disk(filename)
      Kernel.const_defined?("Encoding") ? mode = "wb:ASCII-8BIT" : mode = "wb"
      File.open(filename,mode) { |f| f << render }
    end

    private

    # Write out the PDF Header, as per spec 3.4.1
    #
    def render_header(output)
      # pdf version
      output << "%PDF-#{@objects.pdf_version}\n"

      # 4 binary chars, as recommended by the spec
      output << "%\xFF\xFF\xFF\xFF\n"
    end

    # Write out the PDF Body, as per spec 3.4.2
    #
    def render_body(output)
      offsets = {}
      @objects.each do |ref, obj|
        offsets[ref] = output.size
        output << ref_to_pdf(ref, obj)
      end
      offsets
    end

    # Write out the PDF Cross Reference Table, as per spec 3.4.3
    #
    def render_xref(output, offsets)
      @xref_offset = output.size
      output << "xref\n"
      output << "0 #{offsets.size + 1}\n"
      output << "0000000000 65535 f \n"
      @objects.each_key do |ref|
        output.printf("%010d", offsets[ref])
        output << " 00000 n \n"
      end
    end

    # Write out the PDF Trailer, as per spec 3.4.4
    #
    def render_trailer(output, offsets)
      trailer = {:Size => offsets.size}.merge(@objects.trailer)
      output << "trailer\n"
      output << obj_to_pdf(trailer) << "\n"
      output << "startxref\n"
      output << @xref_offset << "\n"
      output << "%%EOF" << "\n"
    end

    # TODO: move this to PDF::Reader:Reference#to_pdf ?
    #
    def ref_to_pdf(ref, obj)
      output = "#{ref.id} #{ref.gen} obj\n"
      if obj.is_a?(PDF::Reader::Stream)
        output << obj_to_pdf(obj) << "\n"
        output << "stream\n" << obj.data << "\nendstream\n"
      else
        output << obj_to_pdf(obj) << "\n"
      end
      output << "endobj\n"
    end

    # Serializes Ruby objects to their PDF equivalents.  Most primitive objects
    # will work as expected, but please note that Name objects are represented
    # by Ruby Symbol objects and Dictionary objects are represented by Ruby hashes
    # (keyed by symbols)
    #
    #  Examples:
    #
    #     obj_to_pdf(true)      #=> "true"
    #     obj_to_pdf(false)     #=> "false"
    #     obj_to_pdf(1.2124)    #=> "1.2124"
    #     obj_to_pdf("foo bar") #=> "(foo bar)"
    #     obj_to_pdf(:Symbol)   #=> "/Symbol"
    #     obj_to_pdf(["foo",:bar, [1,2]]) #=> "[foo /bar [1 2]]"
    #
    def obj_to_pdf(obj, in_content_stream = false)
      case(obj)
      when NilClass   then "null"
      when TrueClass  then "true"
      when FalseClass then "false"
      when Numeric    then String(obj)
      when Array
        "[" << obj.map { |e| obj_to_pdf(e, in_content_stream) }.join(' ') << "]"
      #when Prawn::Core::LiteralString
      #  obj = obj.gsub(/[\\\n\r\t\b\f\(\)]/n) { |m| "\\#{m}" }
      #  "(#{obj})"
      when Time
        obj = obj.strftime("D:%Y%m%d%H%M%S%z").chop.chop + "'00'"
        obj = obj.gsub(/[\\\n\r\t\b\f\(\)]/n) { |m| "\\#{m}" }
        "(#{obj})"
      #when Prawn::Core::ByteString
      #  "<" << obj.unpack("H*").first << ">"
      when String
        obj = utf8_to_utf16(obj) unless in_content_stream
        "<" << obj.unpack("H*").first << ">"
       when Symbol
         "/" + obj.to_s.unpack("C*").map { |n|
          if n < 33 || n > 126 || [35,40,41,47,60,62].include?(n)
            "#" + n.to_s(16).upcase
          else
            [n].pack("C*")
          end
         }.join
      when Hash
        output = "<< "
        obj.each do |k,v|
          unless String === k || Symbol === k
            raise "A PDF Dictionary must be keyed by names"
          end
          output << obj_to_pdf(k.to_sym, in_content_stream) << " " <<
                    obj_to_pdf(v, in_content_stream) << "\n"
        end
        output << ">>"
      when PDF::Reader::Reference
        "#{obj.id} #{obj.gen} R"
      #when Prawn::Core::NameTree::Node
      #  obj_to_pdf(obj.to_hash)
      #when Prawn::Core::NameTree::Value
      #  obj_to_pdf(obj.name) + " " + obj_to_pdf(obj.value)
      #when Prawn::OutlineRoot, Prawn::OutlineItem
      #  obj_to_pdf(obj.to_hash)
      else
        raise "This object cannot be serialized to PDF (#{obj.inspect})"
      end
    end

    if "".respond_to?(:encode)
      # Ruby 1.9+
      def utf8_to_utf16(str)
        "\xFE\xFF".force_encoding("UTF-16BE") + str.encode("UTF-16BE")
      end
    else
      # Ruby 1.8
      def utf8_to_utf16(str)
        utf16 = "\xFE\xFF"

        str.unpack("U*").each do |cp|
          if cp < 0x10000 # Basic Multilingual Plane
            utf16 << [cp].pack("n")
          else
            # pull out high/low 10 bits
            hi, lo = (cp - 0x10000).divmod(2**10)
            # encode a surrogate pair
            utf16 << [0xD800 + hi, 0xDC00 + lo].pack("n*")
          end
        end

        utf16
      end
    end

  end
end
