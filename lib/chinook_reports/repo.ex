defmodule ChinookReports.Repo do
  use Ecto.Repo,
    otp_app: :chinook_reports,
    adapter: Ecto.Adapters.Postgres
end
