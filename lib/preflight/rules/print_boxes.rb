# coding: utf-8

module Preflight
  module Rules

    # For PDFX/1a, every page must have MediaBox, plus either ArtBox or
    # TrimBox
    #
    class PrintBoxes
      attr_reader :messages

      def initialize
        @messages = []
        @page_num = 0
        @parent   = {}
      end

      def begin_page_container(hash = {})
        @parent.merge!(hash)
      end

      def begin_page(hash = {})
        @page_num += 1
        hash = @parent.merge(hash)

        if hash[:MediaBox].nil?
          @messages << "every page must have a MediaBox (page #{@page_num})"
        elsif hash[:ArtBox].nil? && hash[:TrimBox].nil?
          @messages << "every page must have either an ArtBox or a TrimBox (page #{@page_num})"
        elsif hash[:ArtBox] && hash[:TrimBox]
          @messages << "no page can have both ArtBox and TrimBox - TrimBox is preferred (page #{@page_num})"
        end
      end
    end
  end
end
