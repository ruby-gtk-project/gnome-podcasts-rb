# frozen_string_literal: true

require "strscan"

# EpisodeDescriptionParser turns a feed's HTML description into Pango markup.
#
# Ported from podcasts-gtk/src/episode_description_parser.rs. Upstream parses
# the description with html5ever into an rcdom and walks it, keeping the subset
# of tags Pango understands (b, i, s, u, tt, sub, sup and a), turning `<p>` and
# `<br>` into newlines, `<ol>`/`<ul>`/`<li>` into indented bullets or numbers,
# `<img>` into its alt text in brackets, and wrapping bare URLs, e-mail
# addresses and `HH:MM:SS` timestamps in links — the timestamps as
# `jump:seconds`, which lib/player.rb seeks on.
#
# The port has no HTML parser, so the walk runs over a token stream rather than
# a tree: `Tokenizer` emits start, end and text tokens, void elements never
# open a frame, an unmatched end tag closes everything it has to, and anything
# still open at the end of the document is closed. That produces the same
# events in the same order as a walk of html5ever's tree for the descriptions
# feeds actually carry.
#
# Two oddities of upstream are kept deliberately, because the output is the
# spec and quietly diverging from it would be worse than matching it:
#
#   * `push_text_with_links` escapes text that `handle_child` has already
#     escaped. Upstream's `escape_text` undoes the second pass for `&` but not
#     for `<` and `>`, so a literal angle bracket in a description reaches
#     Pango as `&amp;lt;`. The second pass is kept here.
#   * a link with no scheme is given one by prefixing `https:` to it, without
#     the `//`, exactly as upstream writes it.
module EpisodeDescriptionParser
  # Used by li tags, as upstream's INDENT.
  INDENT = 4

  # Elements that never have children, so they never open a frame. Upstream
  # only acts on br and img; the rest are here because html5ever closes them
  # too and a feed that leaves an `<hr>` open should not swallow the rest of
  # the description.
  VOID_ELEMENTS = %w[
    area base br col embed hr img input link meta param source track wbr
  ].freeze

  # Elements whose content is raw text rather than markup. html5ever hands
  # their body through as a text node, and so does this.
  RAW_TEXT_ELEMENTS = %w[script style].freeze

  # The tags Pango markup supports, mapped from the HTML that means them.
  # See https://docs.gtk.org/Pango/pango_markup.html.
  WRAPPER_TAGS = {
    "b"    => "b",
    "i"    => "i",
    "s"    => "s",
    "u"    => "u",
    "tt"   => "tt",
    "pre"  => "tt",
    "code" => "tt",
    "sub"  => "sub",
    "sup"  => "sup",
  }.freeze

  # Elements that cannot nest: a start tag for the key implicitly closes any
  # open element the value names, which is html5ever's tree builder putting a
  # feed's unclosed `<p>` and `<li>` where a browser would.
  IMPLIED_END = {
    "li"         => %w[li],
    "dt"         => %w[dt dd],
    "dd"         => %w[dt dd],
    "tr"         => %w[tr td th],
    "td"         => %w[td th],
    "th"         => %w[td th],
    "option"     => %w[option],
    "p"          => %w[p],
    "ol"         => %w[p],
    "ul"         => %w[p],
    "dl"         => %w[p],
    "div"        => %w[p],
    "hr"         => %w[p],
    "pre"        => %w[p],
    "address"    => %w[p],
    "blockquote" => %w[p],
    "fieldset"   => %w[p],
    "form"       => %w[p],
    "table"      => %w[p],
    "h1"         => %w[p],
    "h2"         => %w[p],
    "h3"         => %w[p],
    "h4"         => %w[p],
    "h5"         => %w[p],
    "h6"         => %w[p],
  }.freeze

  # The elements an end tag stops looking past for its own start tag — the
  # HTML list item scope, which is why a `</li>` in a nested list closes
  # nothing in the list that contains it.
  SCOPE_BREAKERS = {
    "li" => %w[ol ul],
    "dd" => %w[ol ul dl],
    "dt" => %w[ol ul dl],
  }.freeze

  TIMESTAMP = /([0-9]+):([0-9]+)(?::([0-9]+))?/

  # Stands in for linkify's top level domain table, which is what lets
  # upstream's LinkFinder match a URL that carries no scheme. A host with no
  # scheme and no path is only a link when it ends in one of these.
  TOP_LEVEL_DOMAINS = %w[
    com org net int edu gov mil info biz name pro xyz app dev io co me tv fm
    gg to cc ly sh st am audio radio show live life news blog media press
    site online store shop cloud space world today club one wiki link email
    de fr it es nl be at ch se no dk fi pl cz hu ro gr pt ie uk eu ru ua by
    us ca mx br ar cl au nz jp kr cn tw hk sg in il za tr is lt lv ee si sk
  ].freeze

  LINK = /
    (?<email>[\w.%+-]+@(?:[\w-]+\.)+[A-Za-z]{2,24})
    |
    (?<url>
      https?:\/\/[^\s<>"'`]+
      |
      (?:[\w-]+\.)+#{Regexp.union(TOP_LEVEL_DOMAINS.sort_by { |tld| -tld.length })}\b(?:\/[^\s<>"'`]*)?
    )
  /xi

  # Trailing characters a sentence ends with rather than a link, which is what
  # linkify stops a match before.
  TRAILING_PUNCTUATION = [".", ",", ";", ":", "!", "?", "'", '"', ")", "]", "}", ">", "*"].freeze

  # One element that is still open: the Pango tag it wrote, if any, and the
  # work its close has to do.
  Frame = Struct.new(
    :name,
    :tag,
    :link,
    :paragraph,
    :list,
    keyword_init: true,
  )

  # The walk's state, upstream's ParserState plus the frame stack the token
  # stream needs in place of the tree's recursion.
  class State
    def initialize(newline_style)
      @buffer = +""
      @newline_style = newline_style
      @skip_leading_spaces = true
      @indent = 0
      @list_style = []
      @inside_link = 0
      @frames = []
    end

    attr_reader :buffer, :newline_style, :list_style, :frames
    attr_accessor :skip_leading_spaces, :indent, :inside_link
  end

  # A tolerant HTML tokenizer: elements, attributes, text, comments,
  # doctypes, processing instructions and raw-text elements.
  module Tokenizer
    class << self
      def tokenize(source)
        [].tap do |tokens|
          StringScanner.new(source).then do |scanner|
            until scanner.eos?
              scan_text(scanner, tokens)
              unless scanner.eos?
                scan_markup(scanner, tokens)
              end
            end
          end
        end
      end

      private

        def scan_text(scanner, tokens)
          scanner.scan(/[^<]+/).then do |chunk|
            if chunk
              tokens << [:text, Entities.decode(chunk)]
            end
          end
        end

        def scan_markup(scanner, tokens)
          if scanner.scan(/<!--/)
            scanner.skip_until(/-->/) || scanner.terminate
          elsif scanner.scan(/<[?!]/)
            scanner.skip_until(/>/) || scanner.terminate
          elsif scanner.scan(%r{</})
            scan_end_tag(scanner, tokens)
          elsif scanner.scan(/<(?=[A-Za-z])/)
            scan_start_tag(scanner, tokens)
          else
            tokens << [:text, scanner.getch.to_s]
          end
        end

        def scan_end_tag(scanner, tokens)
          scanner.scan(%r{[^\s/>]+}).to_s.downcase.then do |name|
            scanner.skip_until(/>/) || scanner.terminate
            tokens << [:end, name]
          end
        end

        def scan_start_tag(scanner, tokens)
          scanner.scan(%r{[^\s/>]+}).to_s.downcase.then do |name|
            scan_attributes(scanner).then do |attributes|
              scanner.scan(%r{\s*/>}).then do |closed|
                unless closed
                  scanner.skip(/\s*>/)
                end
                tokens << [:start, name, attributes]
                if closed.nil? && RAW_TEXT_ELEMENTS.include?(name)
                  scan_raw_text(scanner, tokens, name)
                end
                if closed || VOID_ELEMENTS.include?(name)
                  tokens << [:end, name]
                end
              end
            end
          end
        end

        # A raw-text element's body reaches Pango as text, which is what
        # html5ever's tree gives upstream's walk.
        def scan_raw_text(scanner, tokens, name)
          scanner.scan_until(%r{</#{name}\s*>}i).to_s.sub(%r{</#{name}\s*>\z}i, "").then do |body|
            tokens << [:text, body]
            tokens << [:end, name]
          end
        end

        def scan_attributes(scanner)
          {}.tap do |attributes|
            loop do
              scanner.skip(/\s+/)
              if scanner.eos? || scanner.check(%r{/?>})
                break
              end

              scanner.scan(%r{[^\s=/>]+}).then do |key|
                if key.nil?
                  break
                end

                attributes[key.downcase] = scan_attribute_value(scanner)
              end
            end
          end
        end

        def scan_attribute_value(scanner)
          if scanner.skip(/\s*=\s*/).nil?
            +""
          elsif scanner.scan(/"/)
            Entities.decode(scanner.scan_until(/"/).to_s.chomp('"'))
          elsif scanner.scan(/'/)
            Entities.decode(scanner.scan_until(/'/).to_s.chomp("'"))
          else
            Entities.decode(scanner.scan(%r{[^\s/>]+}).to_s)
          end
        end
    end
  end

  # The character references html5ever decodes before upstream's walk sees a
  # text node. The five predefined ones plus the named references podcast
  # descriptions actually use, and numeric references in both bases.
  module Entities
    NAMED = {
      "amp"    => "&",
      "lt"     => "<",
      "gt"     => ">",
      "quot"   => '"',
      "apos"   => "'",
      "nbsp"   => " ",
      "copy"   => "©",
      "reg"    => "®",
      "trade"  => "™",
      "deg"    => "°",
      "plusmn" => "±",
      "middot" => "·",
      "laquo"  => "«",
      "raquo"  => "»",
      "lsquo"  => "‘",
      "rsquo"  => "’",
      "ldquo"  => "“",
      "rdquo"  => "”",
      "sbquo"  => "‚",
      "bdquo"  => "„",
      "ndash"  => "–",
      "mdash"  => "—",
      "hellip" => "…",
      "bull"   => "•",
      "dagger" => "†",
      "euro"   => "€",
      "pound"  => "£",
      "yen"    => "¥",
      "cent"   => "¢",
      "sect"   => "§",
      "para"   => "¶",
      "times"  => "×",
      "divide" => "÷",
      "frac12" => "½",
      "frac14" => "¼",
      "frac34" => "¾",
      "sup2"   => "²",
      "sup3"   => "³",
      "shy"    => "­",
      "ensp"   => " ",
      "emsp"   => " ",
      "thinsp" => " ",
    }.freeze

    class << self
      def decode(text)
        text.to_s.gsub(/&(#[xX][0-9A-Fa-f]+|#[0-9]+|[A-Za-z][A-Za-z0-9]*);/) do
          value(Regexp.last_match(1))
        end
      end

      private

        def value(body)
          if body.start_with?("#x", "#X")
            codepoint(body[2..].to_i(16), body)
          elsif body.start_with?("#")
            codepoint(body[1..].to_i, body)
          else
            NAMED.fetch(body, "&#{body};")
          end
        end

        def codepoint(number, body)
          if number.positive? && number < 0x110000
            [number].pack("U")
          else
            "&#{body};"
          end
        end
    end
  end

  class << self
    # Upstream's html2pango_markup.
    def html_to_pango_markup(text)
      Tokenizer.tokenize(text.to_s).then do |tokens|
        State.new(newline_style(tokens)).tap { |state| walk(state, tokens) }.buffer
      end
    end

    # Upstream's escape_text, including the two guards that keep an already
    # escaped sequence from growing a second time.
    def escape_text(text, newline_handling)
      text.to_s
        .gsub("&", "&amp;")
        .gsub("<", "&lt;")
        .gsub(">", "&gt;")
        .gsub("&amp;amp;", "&amp;")
        .gsub("&lt;lt;", "&lt;")
        .gsub("&gt;gt;", "&gt;")
        .then { |escaped| newlines(escaped, newline_handling) }
        .then { |newlined| collapse_whitespaces(newlined) }
    end

    private

      # Upstream's find_newline_style: a description that carries `<p>` or
      # `<br>` means its newlines with tags, and its text newlines become
      # spaces.
      def newline_style(tokens)
        tokens.any? { |token| token.first == :start && %w[p br].include?(token[1]) }.then do |tags|
          if tags
            :tag
          else
            :text
          end
        end
      end

      def walk(state, tokens)
        tokens.each { |token| handle(state, token) }
        until state.frames.empty?
          close(state, state.frames.pop)
        end
      end

      def handle(state, token)
        case token.first
        when :text then text(state, token[1])
        when :start then open(state, token[1], token[2])
        when :end then close_to(state, token[1])
        end
      end

      def open(state, name, attributes)
        IMPLIED_END.fetch(name, []).each { |implied| close_to(state, implied) }
        start(state, name, attributes).then do |frame|
          if frame
            state.frames.push(frame)
          end
        end
      end

      # Upstream's Element arm of handle_child, up to the point where it
      # recurses: the tag that gets written, and what the close has to undo.
      def start(state, name, attributes)
        case name
        when "br" then line_break(state)
        when "img" then image(state, attributes)
        when "p" then plain_frame(name, paragraph: true)
        when "ol" then open_list(state, name, [:ordered, 1])
        when "ul" then open_list(state, name, :unordered)
        when "li" then bullet(state, name)
        when "a" then anchor(state, name, attributes)
        else wrapper(state, name)
        end
      end

      def wrapper(state, name)
        WRAPPER_TAGS[name].then do |tag|
          if tag
            open_tag(
              state,
              name,
              tag,
              nil,
            )
          else
            plain_frame(name)
          end
        end
      end

      # Pango has no `a` without an href, and a link into the page or a
      # `jump:` the player cannot use leads nowhere, so both lose the tag and
      # keep their text.
      def anchor(state, name, attributes)
        attributes["href"].then do |href|
          if href.nil? || dead_href?(href)
            plain_frame(name)
          else
            open_tag(
              state,
              name,
              "a",
              href,
            )
          end
        end
      end

      def dead_href?(href)
        href.lstrip.start_with?("#") ||
          href.strip.empty? ||
          href.lstrip.start_with?("jump:")
      end

      def open_tag(state, name, tag, href)
        state.buffer << "<" << tag
        if href
          state.buffer << %( href="#{escape_text(href, :remove)}")
          state.inside_link += 1
        end
        state.buffer << ">"
        Frame.new(name: name, tag: tag, link: !href.nil?, paragraph: false, list: false)
      end

      def plain_frame(name, paragraph: false, list: false)
        Frame.new(name: name, tag: nil, link: false, paragraph: paragraph, list: list)
      end

      def open_list(state, name, style)
        state.list_style.push(style)
        state.indent += INDENT
        plain_frame(name, paragraph: true, list: true)
      end

      def line_break(state)
        state.buffer << "\n"
        state.skip_leading_spaces = true
        nil
      end

      def image(state, attributes)
        attributes["alt"].then do |alt|
          if alt
            state.buffer << "[" << escape_text(alt, :to_space) << "]\n"
            state.skip_leading_spaces = true
          end
        end
        nil
      end

      def bullet(state, name)
        state.buffer << "\n" << (" " * state.indent)
        state.list_style.last.then do |style|
          if style == :unordered
            state.buffer << "• "
          elsif style
            state.buffer << "#{style[1]}. "
            style[1] += 1
          end
        end
        state.skip_leading_spaces = true
        plain_frame(name)
      end

      # An end tag closes every frame up to and including the one it names,
      # and a tag that was never opened closes nothing.
      def close_to(state, name)
        if in_scope?(state, name)
          unwind(state, name)
        end
      end

      def in_scope?(state, name)
        SCOPE_BREAKERS.fetch(name, []).then do |breakers|
          state.frames
            .reverse_each
            .take_while { |frame| !breakers.include?(frame.name) }
            .any? { |frame| frame.name == name }
        end
      end

      def unwind(state, name)
        state.frames.pop.then do |frame|
          close(state, frame)
          unless frame.name == name
            unwind(state, name)
          end
        end
      end

      def close(state, frame)
        if frame.tag
          state.buffer << "</" << frame.tag << ">"
          if frame.link
            state.inside_link -= 1
          end
        else
          if frame.paragraph
            state.buffer << "\n\n"
            state.skip_leading_spaces = true
          end
          if frame.list
            state.indent -= INDENT
            state.list_style.pop
          end
        end
      end

      # Upstream's Text arm of handle_child.
      def text(state, contents)
        newline_handling(state).then do |handling|
          if state.skip_leading_spaces
            escape_text(contents.sub(/\A[[:space:]]+/, ""), handling).then do |escaped|
              unless escaped.empty?
                state.skip_leading_spaces = false
              end
              push(state, escaped, handling)
            end
          else
            push(state, escape_text(contents, handling), handling)
          end
        end
      end

      def newline_handling(state)
        if state.newline_style == :tag
          :to_space
        else
          :keep
        end
      end

      # Inside a link the text goes in as it is, because Pango has no nested
      # links to put a found one in.
      def push(state, text, handling)
        if state.inside_link.positive?
          state.buffer << text
        else
          push_timestamped_text(state, text, handling)
        end
      end

      # Upstream's push_timestamped_text: every `MM:SS` or `HH:MM:SS` becomes
      # a `jump:` link the player seeks on, and what is between them is
      # scanned for ordinary links.
      def push_timestamped_text(state, text, handling)
        [0].tap do |position|
          text.scan(TIMESTAMP) do
            position[0] = timestamp(
              state,
              text,
              Regexp.last_match,
              handling,
              position[0],
            )
          end
          push_text_with_links(state, text[position[0]..].to_s, handling)
        end
      end

      def timestamp(state, text, match, handling, position)
        jump_and_title(match).then do |jump, title|
          push_text_with_links(state, text[position...match.begin(0)].to_s, handling)
          state.buffer << %(<a href="jump:#{jump}" title="#{title}">) << match[0] << "</a>"
          match.end(0)
        end
      end

      def jump_and_title(match)
        [match[1].to_i, match[2].to_i, match[3]&.to_i].then do |first, second, third|
          if third
            [
              (first * 60 * 60) + (second * 60) + third,
              # Translators: Jump to Hours:Minutes:Seconds
              format(
                "Jump to %02d:%02d:%02d",
                first,
                second,
                third,
              ),
            ]
          else
            [
              (first * 60) + second,
              # Translators: Jump to Minutes:Seconds
              format("Jump to %02d:%02d", first, second),
            ]
          end
        end
      end

      # Upstream's push_text_with_links, standing in for linkify's LinkFinder
      # with `url_must_have_scheme(false)`.
      def push_text_with_links(state, text, handling)
        [0].tap do |position|
          text.scan(LINK) do
            position[0] = link(
              state,
              text,
              Regexp.last_match,
              handling,
              position[0],
            )
          end
          state.buffer << escape_text(text[position[0]..].to_s, handling)
        end
      end

      def link(state, text, match, handling, position)
        trimmed(match[0]).then do |body|
          state.buffer << escape_text(text[position...match.begin(0)].to_s, handling)
          state.buffer << %(<a href="#{href_for(match, body)}">) << body << "</a>"
          match.begin(0) + body.length
        end
      end

      def href_for(match, body)
        if match[:email]
          "mailto:#{body}"
        elsif body.start_with?("http://", "https://")
          body
        else
          "https:#{body}"
        end
      end

      # linkify stops a match before the punctuation that ends the sentence
      # rather than the link, and before a closing bracket the link never
      # opened.
      def trimmed(body)
        body.dup.tap do |text|
          while text.length > 1 && TRAILING_PUNCTUATION.include?(text[-1])
            text.chop!
          end
        end
      end

      def newlines(text, handling)
        case handling
        when :to_space then text.tr("\n", " ")
        when :remove then text.delete("\n")
        else text
        end
      end

      # Upstream's collapse_whitespaces: a space that follows a space or a
      # newline goes away.
      def collapse_whitespaces(text)
        [false].then do |was_space|
          text.each_char.select { |char| keep_char?(char, was_space) }.join
        end
      end

      def keep_char?(char, was_space)
        (char == " ").then do |is_space|
          if is_space && was_space[0]
            false
          else
            was_space[0] = is_space || char == "\n"
            true
          end
        end
      end
  end
end
