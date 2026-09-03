require "net/http"

# Minimal JSON HTTP client for talking to the browser worker. Kept deliberately
# small and dependency-free; only one verb (POST /extract) is ever needed.
class WorkerClient
  Response = Struct.new(:status, :body, keyword_init: true)

  def self.post(base_url, path, body:, timeout_seconds:)
    new.post(base_url, path, body: body, timeout_seconds: timeout_seconds)
  end

  def post(base_url, path, body:, timeout_seconds:)
    uri = URI.join(base_url, path)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = timeout_seconds
    http.read_timeout = timeout_seconds

    request = Net::HTTP::Post.new(uri.path)
    request["Content-Type"] = "application/json"
    request["Accept"] = "application/json"
    request.body = JSON.generate(body)

    response = http.request(request)
    Response.new(status: response.code.to_i, body: response.body.to_s)
  end
end
