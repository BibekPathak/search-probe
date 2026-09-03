# Tiny JSON-lines emitter for machine-readable events. Every event is one JSON
# object per line, so `docker compose logs` can be tailed or piped to a log
# shipper. Timestamps are added here (formatters may vary by environment).
class StructuredLog
  def self.emit(event, payload = {})
    line = JSON.generate({ ts: Time.now.utc.iso8601(3), event: event, **payload })
    Rails.logger.info(line)
  end
end
