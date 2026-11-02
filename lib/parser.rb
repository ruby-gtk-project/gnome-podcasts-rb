# frozen_string_literal: true

# Parser reads the parts of a feed item the RSS spec leaves loose.
#
# Ported from podcasts-data/src/parser.rs.
module Parser
  class << self
    # The iTunes extension's `duration` in seconds.
    #
    # The Apple spec allows either an integer number of seconds or a string in
    # HH:MM:SS, H:MM:SS, MM:SS or M:SS form, so both are accepted here, as
    # upstream does.
    def itunes_duration(duration)
      duration.to_s.strip.then do |text|
        if text.empty?
          nil
        elsif /\A\d+\z/.match?(text)
          text.to_i
        else
          colon_duration(text)
        end
      end
    end

    private

      def colon_duration(text)
        text.split(":").map(&:to_i).then do |parts|
          if parts.length == 3
            (parts[0] * 3600) + (parts[1] * 60) + parts[2]
          elsif parts.length == 2
            (parts[0] * 60) + parts[1]
          else
            0
          end
        end
      end
  end
end
