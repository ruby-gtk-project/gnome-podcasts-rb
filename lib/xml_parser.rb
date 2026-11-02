# frozen_string_literal: true

require "strscan"

# XmlParser is the port's XML reader and writer.
#
# It stands in for the Rust crates the data layer parses XML with — `rss` for
# feeds and `xml-rs` for OPML (podcasts-data/src/feed.rs,
# podcasts-data/src/opml.rs). Those are dependencies rather than upstream
# source files, and the port's runtime closure has no XML library at all:
# nix/Gemfile pins gtk4 and adwaita, and this Ruby ships without rexml. So the
# reader lives here, in one place, and `Feed` and `Opml` parse against it.
#
# It is a tree reader, not a validator: elements, attributes, text, CDATA,
# comments, processing instructions and the five predefined entities plus
# numeric character references. Namespace prefixes are kept as part of `name`
# and also exposed stripped as `local_name`, because a feed means different
# things by `<image>` and `<itunes:image>`.
module XmlParser
  # One element of the parsed tree.
  class Element
    def initialize(name, attributes)
      @name = name
      @attributes = attributes
      @children = []
      @text = +""
    end

    attr_reader :name, :attributes, :children
    attr_accessor :text

    def local_name = name.split(":").last.to_s

    # Every direct child element whose name — prefixed or not — matches.
    def elements(wanted)
      children.select { |child| child.name == wanted || child.local_name == wanted }
    end

    def element(wanted) = elements(wanted).first

    # The trimmed text of the first matching child, or nil when there is none.
    def text_of(wanted)
      element(wanted).then do |child|
        if child
          child.text.strip
        end
      end
    end

    def attribute(key) = attributes[key]

    # Depth-first walk, self included.
    def each_element(&block)
      block.call(self)
      children.each { |child| child.each_element(&block) }
    end
  end

  ENTITIES = {
    "amp"  => "&",
    "lt"   => "<",
    "gt"   => ">",
    "quot" => '"',
    "apos" => "'",
  }.freeze

  class << self
    # Parses a document and answers its root element, or nil for a document
    # with no elements in it.
    def parse(source)
      stack = []
      root = nil
      scanner = StringScanner.new(source.to_s)

      until scanner.eos?
        scan_text(scanner, stack)
        if scanner.eos?
          break
        end

        scan_markup(scanner, stack).then do |element|
          if element && root.nil?
            root = element
          end
        end
      end

      root
    end

    # Unescapes the predefined entities and numeric character references.
    def unescape(text)
      text.to_s.gsub(/&(#x?[0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]*);/) do
        entity_value(Regexp.last_match(1))
      end
    end

    # Escapes text for an attribute value or element body.
    def escape(text)
      text.to_s
        .gsub("&", "&amp;")
        .gsub("<", "&lt;")
        .gsub(">", "&gt;")
        .gsub('"', "&quot;")
    end

    private

      def entity_value(body)
        if body.start_with?("#x", "#X")
          [body[2..].to_i(16)].pack("U")
        elsif body.start_with?("#")
          [body[1..].to_i].pack("U")
        else
          ENTITIES.fetch(body, "&#{body};")
        end
      end

      # Appends everything up to the next `<` as text of the open element.
      def scan_text(scanner, stack)
        scanner.scan(/[^<]+/).then do |chunk|
          if chunk && stack.last
            stack.last.text << unescape(chunk)
          end
        end
      end

      # Consumes one markup construct and answers the element it opened, if
      # any.
      def scan_markup(scanner, stack)
        if scanner.scan(/<!--/)
          scanner.skip_until(/-->/) || scanner.terminate
          nil
        elsif scanner.scan(/<!\[CDATA\[/)
          scan_cdata(scanner, stack)
          nil
        elsif scanner.scan(/<[?!]/)
          scanner.skip_until(/>/) || scanner.terminate
          nil
        elsif scanner.scan(%r{</})
          scanner.skip_until(/>/) || scanner.terminate
          stack.pop
          nil
        elsif scanner.scan(/</)
          scan_start_tag(scanner, stack)
        else
          scanner.getch
          nil
        end
      end

      def scan_cdata(scanner, stack)
        scanner.scan_until(/\]\]>/).to_s.sub(/\]\]>\z/, "").then do |body|
          if stack.last
            stack.last.text << body
          end
        end
      end

      def scan_start_tag(scanner, stack)
        scanner.scan(%r{[^\s/>]+}).to_s.then do |name|
          Element.new(name, scan_attributes(scanner)).tap do |element|
            if stack.last
              stack.last.children << element
            end
            stack.push(element)
            if scanner.scan(%r{\s*/>})
              stack.pop
            end
            unless scanner.eos?
              scanner.skip(/\s*>/)
            end
          end
        end
      end

      def scan_attributes(scanner)
        {}.tap do |attributes|
          loop do
            scanner.skip(/\s+/)
            if scanner.eos? || scanner.check(%r{/?>})
              break
            end

            key = scanner.scan(%r{[^\s=/>]+})
            if key.nil?
              break
            end

            attributes[key] = scan_attribute_value(scanner)
          end
        end
      end

      def scan_attribute_value(scanner)
        scanner.skip(/\s*=\s*/)
        if scanner.scan(/"/)
          unescape(scanner.scan_until(/"/).to_s.chomp('"'))
        elsif scanner.scan(/'/)
          unescape(scanner.scan_until(/'/).to_s.chomp("'"))
        else
          unescape(scanner.scan(%r{[^\s/>]+}).to_s)
        end
      end
  end
end
