require "net/http"

# Thin Net::HTTP wrapper so extractors (and their tests) never touch sockets
# directly. Returns an object with #status, #body and #headers, or raises one
# of the standard Net::HTTP timeouts / IO errors the extractor maps to its
# failure taxonomy.
class HttpFetcher
  Response = Struct.new(:status, :body, :headers, keyword_init: true)

  def get(url, timeout_seconds:, max_redirects: 3)
    uri = URI.parse(url)
    redirects = 0

    loop do
      response = perform_get(uri, timeout_seconds)

      if redirect?(response)
        redirects += 1
        raise Errors::ExtractionFailed.new(error_type: "network_error", message: "Too many redirects") if redirects > max_redirects

        location = response["location"]
        raise Errors::ExtractionFailed.new(error_type: "network_error", message: "Redirect without Location") if location.blank?

        uri = URI.join(uri, location)
        next
      end

      return Response.new(status: response.code.to_i, body: response.body.to_s, headers: response.to_hash)
    end
  end

  private

  def perform_get(uri, timeout_seconds)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = timeout_seconds
    http.read_timeout = timeout_seconds

    request = Net::HTTP::Get.new(uri.request_uri)
    request["User-Agent"] = "SearchProbe/0.1 (+https://github.com/yourname/searchprobe; local simulator)"
    request["Accept"] = "text/html"
    http.request(request)
  end

  def redirect?(response)
    response.is_a?(Net::HTTPRedirection)
  end
end
