# Lightweight JSON logger formatter so `docker compose logs` shows one JSON
# object per line. Controlled per environment (development keeps pretty logs).

class JsonLogFormatter < Logger::Formatter
  def call(severity, _time, _progname, message)
    payload =
      case message
      when String
        # Already-JSON strings emitted by our structured logger pass through.
        begin
          JSON.parse(message)
        rescue JSON::ParserError
          { message: message }
        end
      when Hash
        message
      else
        { message: message.inspect }
      end

    JSON.generate({ ts: Time.now.utc.iso8601(3), level: severity, **payload }) + "\n"
  rescue StandardError
    super
  end
end

if ENV.fetch("LOG_JSON", "false") == "true" || Rails.env.production?
  logger = ActiveSupport::Logger.new($stdout)
  logger.formatter = JsonLogFormatter.new
  Rails.application.config.logger = logger
end
