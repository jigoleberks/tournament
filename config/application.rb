require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module TournamentApp
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # Set APP_TIME_ZONE to a Rails time zone name (e.g. "Saskatchewan", "Eastern Time (US & Canada)").
    # Saskatchewan never observes DST — handy if your club is in one.
    config.time_zone = ENV.fetch("APP_TIME_ZONE", "UTC")
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
