# frozen_string_literal: true

# Errors the data layer raises.
#
# Ported from podcasts-data/src/errors.rs. Upstream's enum variants become
# exception classes, keeping the distinctions the callers act on: a feed that
# has not changed is not a failure, a redirect is retried against the new url,
# and an HTTP status carries the url and code into the log.
module Errors
  # Base class, upstream's DataError.
  class DataError < StandardError; end

  # Upstream's DataError::FeedNotModified: a conditional GET answered 304, so
  # there is nothing to index.
  class FeedNotModified < DataError
    def initialize(source)
      @source = source
      super("#{source.uri} is up to date")
    end

    attr_reader :source
  end

  # Upstream's DataError::FeedRedirect: the source moved and the fetch should
  # be retried against the url it now carries.
  class FeedRedirect < DataError
    def initialize(source)
      @source = source
      super("#{source.uri} was redirected")
    end

    attr_reader :source
  end

  # Upstream's DataError::HttpStatusGeneral.
  class HttpStatusError < DataError
    def initialize(url, code, context)
      @url = url
      @code = code
      super("#{context} (#{code}) for #{url}")
    end

    attr_reader :url, :code
  end

  # Upstream's DataError::ParseEpisodeError / ParseShowError.
  class ParseError < DataError; end

  # Upstream's DownloadError.
  class DownloadError < DataError; end
end
