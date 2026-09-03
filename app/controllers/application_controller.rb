class ApplicationController < ActionController::Base
  # SearchProbe authenticates with API keys (X-API-Key), never browser
  # sessions, so CSRF token verification is irrelevant. Null-session keeps
  # POST/PUT/DELETE JSON requests from being rejected.
  protect_from_forgery with: :null_session
end
