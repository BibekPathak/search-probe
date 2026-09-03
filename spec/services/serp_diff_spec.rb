require "rails_helper"

RSpec.describe SerpDiff, type: :service do
  def result(position, title, url)
    { position: position, title: title, url: url, snippet: "s", result_type: "organic" }
  end

  def search_with(results)
    search = Search.create!(query: "rust", engine: "google")
    docs = results.map { |r| { search_id: search.id, **r } }
    SearchResult.collection.insert_many(docs)
    search
  end

  it "detects added results" do
    previous = search_with([ result(1, "Keep", "https://example.com/keep") ])
    current = search_with([ result(1, "Keep", "https://example.com/keep"),
                           result(2, "New", "https://example.com/new") ])

    diff = described_class.between(current: current, previous: previous)

    expect(diff.added.map { |r| r[:title] }).to eq([ "New" ])
    expect(diff.removed).to be_empty
    expect(diff.position_changes).to be_empty
  end

  it "detects removed results" do
    previous = search_with([ result(1, "Old", "https://example.com/old"),
                            result(2, "Keep", "https://example.com/keep") ])
    current = search_with([ result(1, "Keep", "https://example.com/keep") ])

    diff = described_class.between(current: current, previous: previous)

    expect(diff.removed.map { |r| r[:title] }).to eq([ "Old" ])
    expect(diff.added).to be_empty
  end

  it "detects position changes" do
    previous = search_with([ result(1, "A", "https://example.com/a"),
                            result(2, "B", "https://example.com/b") ])
    current = search_with([ result(1, "B", "https://example.com/b"),
                           result(2, "A", "https://example.com/a") ])

    diff = described_class.between(current: current, previous: previous)

    expect(diff.position_changes).to contain_exactly(
      { title: "A", url: "https://example.com/a", from: 1, to: 2 },
      { title: "B", url: "https://example.com/b", from: 2, to: 1 }
    )
    expect(diff.added).to be_empty
    expect(diff.removed).to be_empty
  end

  it "reports nothing for unchanged results" do
    previous = search_with([ result(1, "A", "https://example.com/a") ])
    current = search_with([ result(1, "A", "https://example.com/a") ])

    diff = described_class.between(current: current, previous: previous)

    expect(diff.added).to be_empty
    expect(diff.removed).to be_empty
    expect(diff.position_changes).to be_empty
  end
end
