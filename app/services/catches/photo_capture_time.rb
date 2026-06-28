module Catches
  # Reads the absolute moment a catch photo was actually captured, from its
  # EXIF DateTimeOriginal + OffsetTimeOriginal. A live photo's capture time is
  # within seconds of when the catch was logged; an imported gallery photo
  # carries the (often much earlier) time it was originally shot.
  #
  # Returns a Time, or nil when there's no usable capture metadata:
  #   - old canvas-captured catches (the pre-native camera stripped all EXIF),
  #   - images with no timezone offset (we won't guess the zone and risk a
  #     false "imported" flag), or
  #   - anything that fails to parse.
  class PhotoCaptureTime
    def self.call(catch_record)
      return nil unless catch_record.photo.attached?

      image = ::Vips::Image.new_from_buffer(catch_record.photo.download, "")
      datetime = exif_value(image, "exif-ifd2-DateTimeOriginal")
      offset   = exif_value(image, "exif-ifd2-OffsetTimeOriginal")
      return nil if datetime.nil? || offset.nil?

      # EXIF datetime is camera-local; the offset makes it absolute. Strip the
      # colon so "-06:00" parses with %z.
      ::Time.strptime("#{datetime} #{offset.delete(':')}", "%Y:%m:%d %H:%M:%S %z")
    rescue ::StandardError
      nil
    end

    # libvips returns EXIF values with a trailing type annotation, e.g.
    # "2026:06:12 10:59:46 (2026:06:12 10:59:46, ASCII, 20 components, 20 bytes)".
    # Take just the value before that annotation. Absent fields type-find as 0.
    def self.exif_value(image, field)
      return nil if image.get_typeof(field) == 0
      image.get(field).to_s.split(" (").first&.strip.presence
    end
  end
end
