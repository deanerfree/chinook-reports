defmodule ChinookReportsWeb.NavAssigns do
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 2]

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     attach_hook(socket, :nav_current_page, :handle_params, fn _params, url, socket ->
       uri = URI.parse(url)
       {:cont, assign(socket, current_page: uri.path)}
     end)}
  end
end
