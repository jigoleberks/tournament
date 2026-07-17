require "test_helper"

class CatchesHelperTest < ActionView::TestCase
  # next_range(day, current_start, current_end) → [target_start, target_end]
  # Encodes the tap-rule table from the spec.

  def call(day, current_start, current_end)
    next_range(day, current_start, current_end)
  end

  test "no current selection — tap selects single day" do
    assert_equal [Date.new(2026, 5, 5), Date.new(2026, 5, 5)],
                 call(Date.new(2026, 5, 5), nil, nil)
  end

  test "single day, tap same day — no change" do
    s = Date.new(2026, 5, 5)
    assert_equal [s, s], call(s, s, s)
  end

  test "single day, tap a later day — extends to range" do
    s = Date.new(2026, 5, 5)
    d = Date.new(2026, 5, 12)
    assert_equal [s, d], call(d, s, s)
  end

  test "single day, tap an earlier day — extends backward" do
    s = Date.new(2026, 5, 12)
    d = Date.new(2026, 5, 5)
    assert_equal [d, s], call(d, s, s)
  end

  test "existing range, tap any day — resets to single day on tapped" do
    s = Date.new(2026, 5, 5)
    e = Date.new(2026, 5, 12)
    d = Date.new(2026, 5, 20)
    assert_equal [d, d], call(d, s, e)
  end

  test "existing range, tap inside the range — also resets to single day" do
    s = Date.new(2026, 5, 5)
    e = Date.new(2026, 5, 12)
    d = Date.new(2026, 5, 8)
    assert_equal [d, d], call(d, s, e)
  end

  test "maps_url_for builds a Google Maps query URL from full-precision coords" do
    c = Struct.new(:latitude, :longitude).new(49.123456, -103.987654)
    assert_equal "https://maps.google.com/?q=49.123456,-103.987654", maps_url_for(c)
  end

  test "month_calendar_link_url — no current selection, returns URL with start=end=tapped" do
    url = month_calendar_link_url(Date.new(2026, 5, 5),
                                  current_start: nil, current_end: nil,
                                  params: {}, path_helper: :catches_path)
    assert_match %r{\?.*start=2026-05-05}, url
    assert_match %r{\?.*end=2026-05-05}, url
  end

  test "month_calendar_link_url — preserves species and sort params" do
    url = month_calendar_link_url(Date.new(2026, 5, 5),
                                  current_start: nil, current_end: nil,
                                  params: { species: "3", sort: "longest" },
                                  path_helper: :catches_path)
    assert_match "species=3", url
    assert_match "sort=longest", url
    assert_match "start=2026-05-05", url
  end

  test "month_calendar_link_url — single day + later tap encodes range" do
    s = Date.new(2026, 5, 5)
    d = Date.new(2026, 5, 12)
    url = month_calendar_link_url(d,
                                  current_start: s, current_end: s,
                                  params: {}, path_helper: :catches_path)
    assert_match "start=2026-05-05", url
    assert_match "end=2026-05-12", url
  end

  test "month_calendar_link_url — drops controller/action keys from params" do
    url = month_calendar_link_url(Date.new(2026, 5, 5),
                                  current_start: nil, current_end: nil,
                                  params: { controller: "catches", action: "index" },
                                  path_helper: :catches_path)
    refute_match "controller=", url
    refute_match "action=", url
  end

  test "flag_label renders out_of_province as 'outside Saskatchewan'" do
    assert_equal "outside Saskatchewan", flag_label("out_of_province")
  end

  test "flag_label renders screenshot_suspect as 'possible screenshot'" do
    assert_equal "possible screenshot", flag_label("screenshot_suspect")
  end

  test "visible_flags_for hides screenshot_suspect from a non-reviewing member" do
    catch_record = Catch.new(flags: %w[missing_gps screenshot_suspect])
    define_singleton_method(:can_review_catch?) { |_| false }
    assert_equal %w[missing_gps], visible_flags_for(catch_record)
  end

  test "visible_flags_for shows screenshot_suspect to staff" do
    catch_record = Catch.new(flags: %w[missing_gps screenshot_suspect])
    define_singleton_method(:can_review_catch?) { |_| true }
    assert_equal %w[missing_gps screenshot_suspect], visible_flags_for(catch_record)
  end

  # --- JPEG-variant photo display helpers (iOS HEIC support) ---

  def attached_photo(path: "test/fixtures/files/sample_walleye.jpg", content_type: "image/jpeg", filename: "sample_walleye.jpg")
    blob = ActiveStorage::Blob.create_and_upload!(
      io: File.open(Rails.root.join(path)),
      filename: filename,
      content_type: content_type
    )
    record = Catch.new
    record.photo.attach(blob)
    record.photo
  end

  # These exercise the helpers themselves (not a re-implementation of their
  # internals) so they fail if a helper is changed to serve the raw original.
  # A variant routes through /representations/; a raw original through /blobs/.

  test "thumb renders a lazy <img> pointing at a processed variant, not the raw original" do
    html = thumb(attached_photo)
    assert_match %r{<img }, html
    assert_match %r{loading="lazy"}, html
    assert_includes html, "/rails/active_storage/representations/"
    refute_includes html, "/rails/active_storage/blobs/"
  end

  test "photo_full renders a full-bleed <img> at a processed variant" do
    html = photo_full(attached_photo)
    assert_match %r{<img }, html
    assert_includes html, "/rails/active_storage/representations/"
    refute_includes html, "/rails/active_storage/blobs/"
  end

  test "photo_src_url returns a representation URL, not a raw blob URL" do
    url = photo_src_url(attached_photo)
    assert_includes url, "/rails/active_storage/representations/"
    refute_includes url, "/rails/active_storage/blobs/"
  end

  test "photo_download_url serves a JPEG original raw (full size, no resize variant)" do
    url = photo_download_url(attached_photo)
    assert_includes url, "/rails/active_storage/blobs/"
    refute_includes url, "/representations/"
  end

  test "photo_download_url transcodes a non-JPEG original to a full-resolution JPEG" do
    photo = attached_photo(path: "test/fixtures/files/sample_walleye.heic",
                           content_type: "image/heic", filename: "sample_walleye.heic")
    url = photo_download_url(photo)
    # Non-JPEG goes through a variant (representation), not the raw original.
    assert_includes url, "/rails/active_storage/representations/"
  end

  test "the JPEG variant transcodes a HEIC original (the iOS path)" do
    photo = attached_photo(path: "test/fixtures/files/sample_walleye.heic",
                           content_type: "image/heic", filename: "sample_walleye.heic")
    processed = photo.variant(resize_to_limit: [400, 400], format: :jpeg).processed
    assert_equal "image/jpeg", processed.image.blob.content_type
  end

  # --- EXIF (GPS) stripping from served variants (privacy: defeats saved-photo GPS leak) ---

  test "jpeg_variant strips metadata from served variants" do
    # Minitest::Mock isn't available in this environment (minitest 6.0.6 split
    # Mock/Stub into a separate gem that isn't a dependency here), so this
    # matches the file's existing define_singleton_method stubbing style
    # (see visible_flags_for tests above) rather than the brief's Mock example.
    captured = nil
    attachment = Object.new
    attachment.define_singleton_method(:variant) { |**opts| captured = opts; :a_variant }
    jpeg_variant(attachment, [400, 400])
    assert_equal({ strip: true }, captured[:saver])
    assert_equal :jpeg, captured[:format]
    assert_equal [400, 400], captured[:resize_to_limit]
  end

  test "vips variant pipeline with strip removes EXIF GPS end-to-end" do
    require "image_processing/vips"
    src = Vips::Image.new_from_file(file_fixture("sample_walleye.jpg").to_s)
    tagged = src.mutate do |m|
      m.set_type!(GObject::GSTR_TYPE, "exif-ifd3-GPSLatitude", "49/1 24/1 30/1")
    end
    Dir.mktmpdir do |dir|
      tagged_path = File.join(dir, "gps.jpg")
      tagged.write_to_file(tagged_path)
      assert Vips::Image.new_from_file(tagged_path).get_fields.any? { |f| f.include?("GPS") },
             "precondition: tagged source must carry GPS EXIF"
      out = ImageProcessing::Vips.source(tagged_path)
        .resize_to_limit(400, 400).convert("jpg").saver(strip: true).call
      fields = Vips::Image.new_from_file(out.path).get_fields
      assert fields.none? { |f| f.include?("GPS") }, "GPS EXIF survived: #{fields.grep(/GPS/)}"
    end
  end
end
