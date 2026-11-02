# frozen_string_literal: true

require "fileutils"
require "gdk_pixbuf2"

# ThumbnailGenerator makes the four cover thumbnails every cover gets.
#
# Ported from podcasts-gtk/src/thumbnail_generator.rs. Upstream decodes the
# downloaded cover once, resizes it to 64, 128, 256 and 512 pixels with a
# Lanczos filter, writes each one as a PNG beside the original and answers the
# textures it made. All four always generate, because the rest of the cover
# code takes a thumbnail's existence from the original's.
#
# Two differences, both forced by the port's toolkit rather than chosen:
#
#   * the resizing is GdkPixbuf's, with its best filter, because the port has
#     no `image` crate.
#   * the targets are passed in rather than computed from the show, so this
#     file does not have to require lib/download_covers.rb, which requires
#     this one. Upstream has the same cycle and Rust does not mind it.
#
# `generate` answers the paths it wrote; lib/download_covers.rb turns the one
# it asked for into a texture, on the main loop where GDK objects belong.
module ThumbnailGenerator
  # We only generate a fixed amount of thumbnails, and the cover code relies
  # on these being the sizes that exist.
  SIZES = [64, 128, 256, 512].freeze

  # Upstream's ThumbSize::hidpi: on a scaled display a widget that asks for a
  # size gets the next thumbnail up, and nil when there is none big enough.
  HIDPI = {
    5 => {64 => 512}.freeze,
    3 => {64 => 256, 128 => 512}.freeze,
    2 => {64 => 128, 128 => 256, 256 => 512}.freeze,
  }.freeze

  class << self
    def hidpi(size, scale)
      HIDPI.keys.sort.reverse.find { |threshold| scale >= threshold }.then do |threshold|
        if threshold
          HIDPI[threshold][size]
        else
          size
        end
      end
    end

    # `targets` maps a size to the path its thumbnail belongs at. Answers the
    # same map with the paths that were written.
    def generate(path, targets)
      GdkPixbuf::Pixbuf.new(file: path).then do |full|
        targets.to_h { |size, target| [size, write(full, size, target)] }
      end
    end

    private

      # The `.part` name and the rename are upstream's: a thumbnail only
      # appears under its real name once it is whole.
      def write(full, size, target)
        FileUtils.mkdir_p(File.dirname(target))
        "#{target}.part".then do |part|
          scaled(full, size).save(part, "png")
          FileUtils.mv(part, target)
          target
        end
      end

      def scaled(full, size)
        dimensions(full.width, full.height, size).then do |width, height|
          full.scale_simple(width, height, :hyper)
        end
      end

      # Upstream's image::resize: the biggest size that fits in a square of
      # `size` pixels, aspect ratio kept.
      def dimensions(width, height, size)
        (size.to_f / [width, height, 1].max).then do |ratio|
          [
            [(width * ratio).round, 1].max,
            [(height * ratio).round, 1].max,
          ]
        end
      end
  end
end
