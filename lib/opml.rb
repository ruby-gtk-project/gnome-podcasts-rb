# frozen_string_literal: true

require_relative "dbqueries"
require_relative "errors"
require_relative "source"
require_relative "xml_parser"

# Opml imports and exports subscription lists.
#
# Ported from podcasts-data/src/opml.rs: `extract_sources` reads the `outline`
# elements of an OPML document, `import_to_db` indexes each feed url it found
# as a `Source`, and the export writes the same `outline` attributes upstream
# writes — text, title, type, xmlUrl and htmlUrl — one per subscribed show.
module Opml
  # An `outline` element, as per the OPML spec; the sub-elements that are not
  # RSS related are left out, exactly as upstream leaves them out.
  Outline = Data.define(:title, :description, :url)

  class << self
    # Every distinct `outline` in the document.
    def extract_sources(source)
      XmlParser.parse(source).then do |root|
        unless root
          raise Errors::ParseError, "the file carried no xml"
        end

        outlines(root).uniq
      end
    end

    # Indexes the urls from an OPML document and answers the new sources. A url
    # that cannot be indexed is logged and skipped, as upstream does, so one
    # bad entry does not fail the whole import.
    def import_to_db(source)
      extract_sources(source).filter_map do |outline|
        begin
          Source.from_url(outline.url)
        rescue StandardError => e
          warn "Failed to import a Show: #{e.message}"
          nil
        end
      end
    end

    def import_from_file(path) = import_to_db(File.read(path))

    def export_from_db(path, export_title)
      File.write(path, export_to_string(export_title))
    end

    # The OPML document for everything subscribed, as a string.
    def export_to_string(export_title)
      (+"").tap do |out|
        out << %(<?xml version="1.0" encoding="UTF-8" standalone="no"?>\n)
        out << %(<opml version="2.0">\n)
        out << "  <head>\n    <title>#{XmlParser.escape(export_title)}</title>\n  </head>\n"
        out << "  <body>\n"
        exported_shows.each { |source, show| out << outline_element(source, show) }
        out << "  </body>\n</opml>\n"
      end
    end

    private

      def outlines(root)
        [].tap do |found|
          root.each_element do |element|
            if element.local_name == "outline" && element.attribute("xmlUrl")
              found << Outline.new(
                title:       element.attribute("title").to_s,
                description: element.attribute("description").to_s,
                url:         element.attribute("xmlUrl").to_s,
              )
            end
          end
        end
      end

      # Upstream joins shows to their source by hand; a show whose source row
      # went away is skipped rather than aborting the export.
      def exported_shows
        Dbqueries.podcasts.filter_map do |show|
          begin
            [Dbqueries.source_from_id(show.source_id), show]
          rescue KeyError
            nil
          end
        end
      end

      def outline_element(source, show)
        [
          %(    <outline text="#{XmlParser.escape(show.title)}"),
          %(title="#{XmlParser.escape(show.title)}"),
          %(type="rss"),
          %(xmlUrl="#{XmlParser.escape(source.uri)}"),
          %(htmlUrl="#{XmlParser.escape(show.link)}" />\n),
        ].join(" ")
      end
  end
end
