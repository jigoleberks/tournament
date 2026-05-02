LOGIN_LOGGER = ActiveSupport::Logger.new(Rails.root.join("log/login_attempts.log"))
LOGIN_LOGGER.formatter = Logger::Formatter.new
