FROM elixir:1.19-otp-28

RUN mix local.hex --force && mix local.rebar --force

RUN apt-get update && apt-get install -y \
  git \
  inotify-tools \
  build-essential \
  curl \
  gpg \
  poppler-utils \
  python3 \
  python3-pip \
  postgresql \
  postgresql-client \
  nginx \
  && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get install -y nodejs \
  && rm -rf /var/lib/apt/lists/*

COPY nginx/chinook.conf /etc/nginx/sites-enabled/chinook.conf
RUN rm -f /etc/nginx/sites-enabled/default

RUN pip3 install pydantic openpyxl pdfplumber --break-system-packages

WORKDIR /workspace