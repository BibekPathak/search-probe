require "rails_helper"

RSpec.describe StructuredLog, type: :service do
  it "emits a single JSON line prefixed with timestamp and event to the logger" do
    line = a_string_matching(/"event":"extraction_attempt"/)
                      .and(a_string_matching(/"engine":"google"/))
                      .and(a_string_matching(/"success":true/))

    expect(Rails.logger).to receive(:info).with(line)

    described_class.emit("extraction_attempt", engine: "google", strategy: "http", success: true)
  end
end
