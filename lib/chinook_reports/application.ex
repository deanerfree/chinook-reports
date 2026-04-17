defmodule ChinookReports.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ChinookReportsWeb.Telemetry,
      ChinookReports.Repo,
      {DNSCluster, query: Application.get_env(:chinook_reports, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ChinookReports.PubSub},
      # Start the Finch HTTP client for sending emails
      # {Finch, name: ChinookReports.Finch},
      # Start a worker by calling: ChinookReports.Worker.start_link(arg)
      # {ChinookReports.Worker, arg},
      ChinookReports.GenServer,
      # Start to serve requests, typically the last entry
      ChinookReportsWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ChinookReports.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ChinookReportsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
