module Rack
  class RequestLang

    def initialize(app = nil, options = {})
      @app = app
    end

    def call(env)
      r = Rack::Request.new(env)
      lang = r.params["lang"] || r.params["language"]
      lang = lang.upcase.to_sym if lang
      RequestStore.store[:requested_lang] = lang
      @app.call(env)
    end
  end
end