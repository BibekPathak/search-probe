module Errors
  class Error < StandardError; end

  # Client error: query/engine parameter problems. Maps to HTTP 400.
  class ValidationError < Error
    attr_reader :code

    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  # Engine name not supported. Maps to HTTP 404 (kept in sync with routes).
  class UnsupportedEngine < Error
    attr_reader :engine

    def initialize(engine)
      @engine = engine
      super("Unsupported engine: #{engine}")
    end
  end

  # Extraction stack exhausted every attempt without a result.
  class ExtractionFailed < Error
    attr_reader :error_type, :error_message, :http_status

    def initialize(error_type:, message:, http_status: nil)
      @error_type = error_type
      @error_message = message
      @http_status = http_status
      super(message)
    end
  end
end
