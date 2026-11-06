# frozen_string_literal: true

require "stringio"
require "gstreamer_play"
require "gobject-introspection"

# ChapterParser probes a media file's metadata for chapter markers.
#
# Ported from podcasts-gtk/src/chapter_parser/{mod,extended_comment,id3}.rs.
# Upstream drives a GstPbutils::Discoverer over the episode's uri, walks every
# stream's generic tags, and turns two kinds of tag into Chapter structs: a
# Vorbis/Opus-style "extended-comment" ("CHAPTER002NAME=Prologue",
# "CHAPTER002=00:00:14.640", one comment per half-chapter) and an ID3v2
# "private-id3v2-frame" CHAP frame (a single binary blob per chapter, with
# nested TIT2/TIT3 frames for title and description).
#
# gstreamer_play's loader brings up GstPlay plus gst_init, but the app also
# needs GstPbutils (for Discoverer) and Gst (for the TagList/Sample/Buffer the
# discovered info hands back) as plain GI namespaces. Neither gem in this
# fork's dependency list loads those, so this file loads them itself, exactly
# the way GstPlay::Loader loads GstPlay: a GObjectIntrospection::Loader
# subclass given a bare module to fill in. `require "gstreamer_play"` first
# guarantees gst_init has already run.
module ChapterParser
  # Fills in the bare `Gst` and `GstPbutils` modules from gst-plugins-base's
  # typelibs, the same shape as gstreamer_play's own GstPlay::Loader. `Gst` is
  # needed so the TagList/Sample/Buffer that GstPbutils hands back have real
  # Ruby classes (ruby-gnome resolves a returned GObject's class by its GType,
  # registered at the Loader's `super(namespace)` call, regardless of which
  # Ruby module it is nested under); `GstPbutils` for Discoverer itself.
  # `require "gstreamer_play"` must run first so `gst_init` has already
  # happened — Discoverer construction aborts the process otherwise.
  class NamespaceLoader < GObjectIntrospection::Loader
    def initialize(namespace, mod)
      @namespace = namespace
      super(mod)
    end

    def load
      self.version = "1.0"
      super(@namespace)
    end
  end

  module Gst; end unless defined?(Gst)
  module GstPbutils; end unless defined?(GstPbutils)
  NamespaceLoader.new("Gst", Gst).load unless defined?(Gst::Buffer)
  NamespaceLoader.new("GstPbutils", GstPbutils).load unless defined?(GstPbutils::Discoverer)

  # One chapter marker. Upstream's Chapter struct; start/end are seconds
  # (floats), matching chrono::Duration's use as a plain offset here.
  Chapter = Struct.new(:id, :title, :description, :start, :end, keyword_init: true) do
    def initialize(**kwargs)
      super(**{id: "", title: "", description: "", start: 0.0, end: 0.0}.merge(kwargs))
    end
  end

  class << self
    # Upstream's load_chapters: probes `uri` and returns every Chapter found,
    # sorted by start time.
    def load_chapters(uri)
      info = discoverer.discover_uri(uri)
      results = []
      info.stream_list.each do |stream|
        tags = stream.tags
        next unless tags

        results.concat(tags_to_chapters(tags))
      end
      results.sort_by(&:start)
    end

    private

      # Upstream's tag_generic: walks every value of every generic tag on a
      # TagList. The Ruby TagList has no generic iterator, so each tag name is
      # read back by index instead (`get_tag_size` is how many values it has).
      def tags_to_chapters(tags)
        results = []
        extended_comment_chapters = {}

        tags.n_tags.times do |i|
          name = tags.nth_tag_name(i)
          next unless %w[extended-comment private-id3v2-frame].include?(name)

          tags.get_tag_size(name).times do |j|
            case name
            when "extended-comment"
              comment = tags.get_string_index(name, j)
              parse_extended_comment(extended_comment_chapters, comment) if comment
            when "private-id3v2-frame"
              sample = tags.get_sample_index(name, j)
              chapter = read_id3_chapter(sample) if sample
              results << chapter if chapter
            end
          end
        end

        results + extended_comment_chapters.values
      end

      # Ported from chapter_parser/extended_comment.rs's parse_extended_comment.
      # A chapter's name and its timestamp arrive as two separate comments, so
      # this writes into the same chapter across repeated calls.
      def parse_extended_comment(chapters, comment)
        if (m = /^CHAPTER([0-9]+)NAME=(.+)$/.match(comment))
          id = m[1]
          chapter = chapters[id] ||= Chapter.new(id: id)
          chapter.id = id
          chapter.title = m[2]
        elsif (m = /CHAPTER([0-9]+)=([0-9]+):([0-9]+):([0-9.]+)/.match(comment))
          id = m[1]
          chapter = chapters[id] ||= Chapter.new(id: id)
          chapter.id = id
          chapter.start = (m[2].to_i * 3600) + (m[3].to_i * 60) + m[4].to_f
        end
      end

      # Ported from chapter_parser/id3.rs's read_id3_chapter: a single ID3v2
      # CHAP frame, with optional nested TIT2 (title) and TIT3 (description)
      # frames. `sample` is the Gst::Sample the "private-id3v2-frame" tag
      # carries; its buffer holds the raw frame bytes.
      def read_id3_chapter(sample)
        buffer = sample.buffer
        return nil unless buffer

        io = StringIO.new(buffer.extract_dup(0, buffer.size))
        header = Id3FrameHeader.read_from(io)
        return nil unless header&.name == "CHAP"

        id = read_terminated_string_iso(io, header.size)
        start_ms, end_ms = io.read(8).unpack("l>l>")
        # Byte offsets into the file, often 0xffffffff ("unused"); upstream
        # reads and discards them too.
        io.read(8)

        title = read_id3_tit(io, "TIT2") || ""
        description = read_id3_tit(io, "TIT3") || ""

        Chapter.new(
          id:          id,
          title:       title,
          description: description,
          start:       start_ms / 1000.0,
          end:         end_ms / 1000.0,
        )
      rescue StandardError
        nil
      end

      def read_id3_tit(io, name)
        return nil if io.eof?

        frame = Id3FrameHeader.read_from(io)
        return nil unless frame&.name == name

        encoding = io.read(1).unpack1("C")
        case encoding
        when 0 then read_terminated_string_iso(io, frame.size - 1)
        when 1, 2 then read_terminated_string_u16(io, frame.size - 1)
        when 3 then read_terminated_string_u8(io, frame.size - 1)
        end
      end

      # ISO-8859-1, 0x00-terminated.
      def read_terminated_string_iso(io, max_size)
        bytes = read_until_zero(io, 1, max_size)
        bytes.pack("C*").force_encoding("ISO-8859-1").encode("UTF-8")
      end

      # UTF-8, 0x00-terminated.
      def read_terminated_string_u8(io, max_size)
        bytes = read_until_zero(io, 1, max_size)
        bytes.pack("C*").force_encoding("UTF-8")
      end

      # Covers both ID3v2 encodings 1 (UCS-2 with BOM) and 2 (UTF-16BE):
      # upstream reads each 2-byte unit byte-swapped before decoding, which
      # makes both effectively UTF-16LE on the wire, BOM character kept as
      # part of the string (its own fixture expects "\u{feff}Intro").
      # 0x0000-terminated.
      def read_terminated_string_u16(io, max_size)
        bytes = read_until_zero(io, 2, max_size)
        bytes.pack("C*").encode("UTF-8", "UTF-16LE")
      end

      # Reads `width`-byte characters until an all-zero character, a short
      # read, or `max_size` bytes have been consumed, matching upstream's
      # three read_0_terminated_string_* helpers.
      def read_until_zero(io, width, max_size)
        bytes = []
        count = 0
        loop do
          chunk = io.read(width)
          break if chunk.nil? || chunk.bytesize < width || count >= max_size

          char = chunk.bytes
          break if char.all?(&:zero?)

          bytes.concat(char)
          count += width
        end
        bytes
      end

      # Gst::ClockTime is a plain nanosecond count on the Ruby side; 30s,
      # matching upstream's `ClockTime::try_from_seconds_f32(30.0)`.
      DISCOVER_TIMEOUT_NS = 30_000_000_000

      def discoverer
        @discoverer ||= GstPbutils::Discoverer.new(DISCOVER_TIMEOUT_NS)
      end
  end

  # Ported from chapter_parser/id3.rs's Id3FrameHeader: a 4-byte frame id, a
  # big-endian 4-byte size, and 2 flag bytes upstream reads but never acts on.
  Id3FrameHeader = Struct.new(:name, :size) do
    def self.read_from(io)
      name = io.read(4)
      size_bytes = io.read(4)
      return nil if name.nil? || size_bytes.nil?

      size = size_bytes.unpack1("N")
      io.read(2)
      new(name, size)
    end
  end
end
