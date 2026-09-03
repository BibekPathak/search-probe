require "rails_helper"

RSpec.describe "Health endpoint", type: :request do
  it "reports ok when the database is reachable" do
    get "/health"

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["status"]).to eq("ok")
    expect(body["database"]).to eq("ok")
  end
end
