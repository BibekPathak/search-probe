require "rails_helper"

RSpec.describe "Live extraction API (LIVE_ENGINES=bing)", type: :request do
  let(:bing_fixture) { File.read(Rails.root.join("spec/fixtures", "bing_html_results.html")) }

  before do
    allow(Rails.application.config.x).to receive(:live_engines).and_return(%w[bing])
    WebMock.stub_request(:get, %r{\Ahttps://www\.bing\.com/search\?})
           .to_return(status: 200, body: bing_fixture,
                      headers: { "Content-Type" => "text/html; charset=utf-8" })
  end

  def search(params = {}, headers = nil)
    get "/api/v1/search", params: params, headers: headers || auth_headers
  end

  it "returns real normalized results for the enabled engine" do
    search(q: "best rust web framework", engine: "bing")

    expect(response).to have_http_status(:ok)
    body = response.parsed_body

    expect(body["engine"]).to eq("bing")
    expect(body["results"]).not_to be_empty
    expect(body["results"].first["url"]).to match(%r{\Ahttps?://})
    expect(body["results"].first["url"]).not_to include("example.com")
    expect(body["metadata"]["strategy"]).to eq("http")
    expect(body["metadata"]["cached"]).to be(false)
  end

  it "serves a repeated live query from cache" do
    search(q: "best rust web framework", engine: "bing")
    expect(response).to have_http_status(:ok)

    search(q: "best rust web framework", engine: "bing")

    body = response.parsed_body
    expect(body["metadata"]["cached"]).to be(true)
    expect(body["metadata"]["strategy"]).to eq("cache")
  end

  it "does not leak simulator demo params onto the live engine" do
    search(q: "rust", engine: "bing", simulate: "429")

    expect(a_request(:get, %r{\Ahttps://www\.bing\.com/search\?})
      .with(query: hash_including("q" => "rust"))).to have_been_made
    expect(a_request(:get, /failure=/)).not_to have_been_made
  end
end
