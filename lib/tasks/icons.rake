namespace :icons do
  desc "Generate PWA + apple-touch icons in public/icons/ from public/icon.{png,jpg}"
  task generate: :environment do
    require "vips"
    require "fileutils"

    src = Rails.root.join("public/icon.png")
    src = Rails.root.join("public/icon.jpg") unless src.exist?

    unless src.exist?
      warn "[icons] No source icon at public/icon.png or public/icon.jpg. " \
           "Drop a square logo (512x512 recommended) there to enable home-screen install."
      next
    end

    out_dir = Rails.root.join("public/icons")
    FileUtils.mkdir_p(out_dir)

    # icon-180 is the apple-touch-icon; 192 and 512 are the manifest icons.
    { "icon-180.png" => 180, "icon-192.png" => 192, "icon-512.png" => 512 }.each do |name, size|
      out = out_dir.join(name)
      if out.exist? && out.mtime >= src.mtime
        puts "[icons] skip #{name} (up to date)"
        next
      end
      Vips::Image.thumbnail(src.to_s, size).write_to_file(out.to_s)
      puts "[icons] wrote #{name} (#{size}x#{size})"
    end

    # Maskable icon: copy of icon-512 for now. Android adaptive-icon shapes
    # (circles, squircles, teardrops) may crop logo edges; revisit with a
    # padded variant if it actually looks bad in production.
    base = out_dir.join("icon-512.png")
    maskable = out_dir.join("icon-maskable-512.png")
    if maskable.exist? && maskable.mtime >= base.mtime
      puts "[icons] skip icon-maskable-512.png (up to date)"
    else
      FileUtils.cp(base, maskable)
      puts "[icons] wrote icon-maskable-512.png (copy of icon-512.png)"
    end
  end
end
