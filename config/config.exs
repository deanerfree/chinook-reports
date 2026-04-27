# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :chinook_reports,
  ecto_repos: [ChinookReports.Repo],
  generators: [timestamp_type: :utc_datetime]

config :mime, :types, %{
  "application/vnd.ms-excel.sheet.macroEnabled.12" => ["xlsm"]
}

# Configures the endpoint
config :chinook_reports, ChinookReportsWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ChinookReportsWeb.ErrorHTML, json: ChinookReportsWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ChinookReports.PubSub,
  live_view: [signing_salt: "kB28lKwu"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
# config :chinook_reports, ChinookReports.Mailer, adapter: Swoosh.Adapters.Local
# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.10",
  chinook_reports: [
    args: ~w(
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
