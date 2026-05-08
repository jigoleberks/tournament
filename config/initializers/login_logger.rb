log_target = Rails.env.test? ? File::NULL : Rails.root.join("log/login_attempts.log")
LOGIN_LOGGER = ActiveSupport::Logger.new(log_target)
LOGIN_LOGGER.formatter = Logger::Formatter.new
