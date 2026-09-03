# SearchProbe backend image.
# Multi-purpose: image bakes in gems for fast container start; development
# mounts the repo over /app (gems live in /usr/local/bundle, preserved).
FROM ruby:3.3.12-slim

ENV RUBY_YJIT_ENABLE=1 \
    BUNDLE_JOBS=4 \
    BUNDLE_PATH=/usr/local/bundle

RUN apt-get update -qq \
  && apt-get install -y --no-install-recommends \
     build-essential \
     curl \
     git \
     tzdata \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4

COPY . .

RUN chmod +x bin/* script/* 2>/dev/null || true

EXPOSE 3000

CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
