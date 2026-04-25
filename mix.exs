defmodule ChinookReports.MixProject do
  use Mix.Project

  def project do
    [
      app: :chinook_reports,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {ChinookReports.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      # ── Core Phoenix (generated, keep these) ──────────────────────────────

      {:phoenix, "~> 1.8.5"},
      {:phoenix_html, "~> 4.2"},
      {:phoenix_live_view, "~> 1.1"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:phoenix_live_dashboard, "~> 0.8"},

      # ── Database ──────────────────────────────────────────────────────────

      {:phoenix_ecto, "~> 4.6"},
      {:ecto_sql, "~> 3.12"},
      {:postgrex, ">= 0.0.0"},
      {:flop, "~> 0.26.3"},
      {:flop_phoenix, "~> 0.26.0"},

      # ── LiveSvelte (Svelte inside LiveView) ───────────────────────────────
      #
      # 0.17+ uses Vite via phoenix_vite. Requires Node 19+.
      # Replaces the default esbuild setup — remove {:esbuild, ...} from deps
      # and the esbuild config from config.exs after installing.

      {:live_svelte, "~> 0.17"},
      # Vite integration for Phoenix (pulled by live_svelte)
      {:phoenix_vite, "~> 0.3"},

      # ── HTTP server ───────────────────────────────────────────────────────
      #
      # Phoenix 1.8 defaults to Bandit. If you prefer Cowboy, swap these.

      {:bandit, "~> 1.6"},
      # {:plug_cowboy, "~> 2.7"},      # alternative to Bandit

      # ── Reverse proxy / remote IP ─────────────────────────────────────────
      #
      # Behind Nginx, conn.remote_ip is 127.0.0.1 by default.
      # This plug reads X-Forwarded-For and sets the real client IP.

      {:remote_ip, "~> 1.2"},

      # ── JSON ──────────────────────────────────────────────────────────────

      {:jason, "~> 1.4"},

      # ── Telemetry & monitoring ────────────────────────────────────────────

      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.1"},

      # ── File uploads ──────────────────────────────────────────────────────
      #
      # LiveView has built-in upload support, but if you need to process
      # .xlsx files server-side before storing, you may want these:
      # (for now the Python script handles extraction outside the app)

      # ── Email (optional, add when needed) ─────────────────────────────────
      #
      # {:swoosh, "~> 1.17"},
      # {:finch, "~> 0.18"},           # HTTP client for Swoosh adapters

      # ── Auth (optional, add when needed) ──────────────────────────────────
      #
      # {:bcrypt_elixir, "~> 3.0"},    # password hashing
      # {:guardian, "~> 2.3"},         # JWT auth
      #   or
      # {:phx_gen_auth, "~> 0.7", only: :dev},  # mix phx.gen.auth generator

      # ── Background jobs (optional, add when needed) ───────────────────────
      #
      # For async well report parsing, email notifications, etc.
      # {:oban, "~> 2.18"},

      # ── Dev & test tools ──────────────────────────────────────────────────

      # HTML parsing for tests
      {:floki, ">= 0.36.0", only: :test},
      # Tailwind CLI wrapper
      {:tailwind, "~> 0.2", only: [:dev, :test]},
      {:heroicons, "~> 0.5",
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:gettext, "~> 0.26"},
      {:dns_cluster, "~> 0.1.1"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind chinook_reports", "esbuild chinook_reports"],
      "assets.deploy": [
        "tailwind chinook_reports --minify",
        "esbuild chinook_reports --minify",
        "phx.digest"
      ]
    ]
  end
end
