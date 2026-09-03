module Api
  module V1
    # Asynchronous search lifecycle:
    #   POST /api/v1/searches  -> 202 { id, status: "queued" }
    #   GET  /api/v1/searches/:id -> queued/running/completed/failed + results
    class SearchesController < BaseController
      def create
        search = Search.create!(query: normalized_query, engine: normalized_engine, status: "queued")
        SearchJob.perform_later(search.id.to_s)

        render json: { id: search.id.to_s, query: search.query, engine: search.engine, status: "queued" },
               status: :accepted
      rescue Errors::ValidationError => e
        render json: { error: { code: "validation_error", type: e.code, message: e.message } },
               status: :bad_request
      rescue Errors::UnsupportedEngine => e
        render json: { error: { code: "unsupported_engine", type: "unsupported_engine", message: e.message } },
               status: :not_found
      rescue Mongoid::Errors::Validations => e
        render json: { error: { code: "validation_error", type: "invalid_request", message: e.message } },
               status: :bad_request
      end

      def show
        search = Search.where(id: params[:id]).first
        return render json: { error: { code: "not_found", type: "not_found", message: "Search not found." } },
                      status: :not_found if search.nil?

        render json: search_payload(search)
      end

      def diff
        search = Search.where(id: params[:id]).first
        return render json: { error: { code: "not_found", type: "not_found", message: "Search not found." } },
                      status: :not_found if search.nil?

        previous = Search.previous_for(query: search.query, engine: search.engine, not_id: search.id)
        return render json: { search_id: search.id.to_s, compared_to: nil,
                              added: [], removed: [], position_changes: [] } unless previous

        diff = SerpDiff.between(current: search, previous: previous)

        render json: {
          search_id: search.id.to_s,
          compared_to: previous.id.to_s,
          added: diff.added,
          removed: diff.removed,
          position_changes: diff.position_changes
        }
      end

      private

      def normalized_query
        query = params[:query].to_s.strip
        raise Errors::ValidationError.new("missing_query", "Parameter query is required.") if query.empty?
        raise Errors::ValidationError.new("query_too_long", "Parameter query must be 500 characters or fewer.") if query.length > 500

        query
      end

      def normalized_engine
        engine = params[:engine].to_s.strip.presence || SearchService::DEFAULT_ENGINE
        raise Errors::UnsupportedEngine.new(engine) unless Search::ENGINES.include?(engine)

        engine
      end

      def search_payload(search)
        {
          id: search.id.to_s,
          query: search.query,
          engine: search.engine,
          status: search.status,
          cache_hit: search.cache_hit,
          strategy: search.strategy,
          latency_ms: search.latency_ms,
          error_type: search.error_type,
          created_at: search.created_at&.iso8601,
          results: search.search_results.order_by(position: :asc).map(&:to_api_hash)
        }
      end
    end
  end
end
