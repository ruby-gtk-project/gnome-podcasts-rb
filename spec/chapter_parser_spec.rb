# frozen_string_literal: true

require "chapter_parser"

# Covers the two tag formats chapter_parser.rb decodes, with the exact
# fixtures podcasts-gtk/src/chapter_parser/{extended_comment,id3}.rs test
# against, so the Ruby parsing stays byte-for-byte compatible with upstream's.
RSpec.describe ChapterParser do
  describe "extended-comment tags" do
    it "pairs a CHAPTERnnnNAME with its CHAPTERnnn timestamp" do
      chapters = {}
      [
        "CHAPTER001=00:00:00.000", "CHAPTER001NAME=Intro",
        "CHAPTER002=00:00:14.640", "CHAPTER002NAME=Prologue",
        "CHAPTER003=00:03:47.967", "CHAPTER003NAME=US president",
      ].each { |comment| described_class.send(:parse_extended_comment, chapters, comment) }

      expect(chapters["001"].title).to eq("Intro")
      expect(chapters["001"].start).to eq(0.0)
      expect(chapters["002"].title).to eq("Prologue")
      expect(chapters["002"].start).to eq(14.64)
      expect(chapters["003"].title).to eq("US president")
      expect(chapters["003"].start).to be_within(0.001).of(227.967)
    end
  end

  describe "ID3v2 CHAP frames" do
    # Fake just enough of Gst::Sample/Gst::Buffer for read_id3_chapter: a
    # buffer that hands back raw bytes through extract_dup, which is all it
    # calls on the real GI-wrapped buffer.
    FakeBuffer = Struct.new(:bytes) do
      def size = bytes.length

      def extract_dup(offset, length) = bytes.pack("C*")[offset, length]
    end
    FakeSample = Struct.new(:buffer)

    def chapter_from(bytes)
      described_class.send(:read_id3_chapter, FakeSample.new(FakeBuffer.new(bytes)))
    end

    it "reads a CHAP frame with a TIT2 title" do
      # github.com/newrustacean's feed, chp0: 0s-22.99s, "Intro" (BOM kept,
      # matching upstream's own expectation).
      bytes = [
        67, 72, 65, 80, 0, 0, 0, 44, 0, 0, 99, 104, 112, 48, 0, 0, 0, 0, 0,
        0, 0, 89, 206, 255, 255, 255, 255, 255, 255, 255, 255, 84, 73, 84,
        50, 0, 0, 0, 13, 0, 0, 1, 255, 254, 73, 0, 110, 0, 116, 0, 114, 0,
        111, 0,
      ]

      chapter = chapter_from(bytes)
      expect(chapter.id).to eq("chp0")
      expect(chapter.title).to eq("﻿Intro")
      expect(chapter.start).to eq(0.0)
      expect(chapter.end).to eq(22.99)
    end

    it "answers nil for a non-CHAP frame (CTOC)" do
      bytes = [
        67, 84, 79, 67, 0, 0, 0, 41, 0, 0, 116, 111, 99, 0, 3, 7, 99, 104,
        112, 48, 0, 99, 104, 112, 49, 0, 99, 104, 112, 50, 0, 99, 104, 112,
        51, 0, 99, 104, 112, 52, 0, 99, 104, 112, 53, 0, 99, 104, 112, 54,
        0,
      ]

      expect(chapter_from(bytes)).to be_nil
    end
  end
end
