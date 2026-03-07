ARG RUBY_VERSION=3.2
ARG DISTRO=bullseye
ARG TESTKIT_BASE_IMAGE=ontoportal/testkit-base:ruby${RUBY_VERSION}-${DISTRO}
FROM ${TESTKIT_BASE_IMAGE}

WORKDIR /app

COPY Gemfile* *.gemspec ./

# Respect the project's Bundler lock when present.
RUN if [ -f Gemfile.lock ]; then \
      BUNDLER_VERSION=$(grep -A 1 "BUNDLED WITH" Gemfile.lock | tail -n 1 | tr -d ' '); \
      gem install bundler -v "$BUNDLER_VERSION"; \
    fi

RUN bundle install --jobs 4 --retry 3

COPY . ./

CMD ["bundle", "exec", "rackup", "-p", "9393", "--host", "0.0.0.0"]
