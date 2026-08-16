defmodule ChinookReportsWeb.NavAssigns do
  import Phoenix.LiveView
  import Phoenix.Component

  alias ChinookReports.Reports

  def on_mount(:default, _params, _session, socket) do
    socket =
      socket
      |> assign(:new_report_form, blank_new_report_form())
      |> attach_hook(:nav_current_page, :handle_params, fn _params, url, socket ->
        uri = URI.parse(url)
        {:cont, assign(socket, current_page: uri.path)}
      end)
      |> attach_hook(:new_report_events, :handle_event, fn
        "validate_new_report", %{"new_report" => params}, socket ->
          changeset = Reports.new_report_changeset(params) |> Map.put(:action, :validate)
          {:halt, assign(socket, :new_report_form, to_form(changeset, as: :new_report))}

        "create_new_report", %{"new_report" => params}, socket ->
          attrs =
            Map.merge(params, %{
              "created_by" => "john.doe@chinookpetroleum.com",
              "updated_by" => "john.doe@chinookpetroleum.com"
            })

          case Reports.create_report(attrs) do
            {:ok, report} ->
              {:halt,
               socket
               |> assign(:new_report_form, blank_new_report_form())
               |> push_navigate(to: "/reports/#{report.id}/edit")}

            {:error, changeset} ->
              {:halt,
               assign(
                 socket,
                 :new_report_form,
                 to_form(%{changeset | action: :validate}, as: :new_report)
               )}
          end

        _event, _params, socket ->
          {:cont, socket}
      end)

    {:cont, socket}
  end

  defp blank_new_report_form do
    to_form(Reports.new_report_changeset(), as: :new_report)
  end
end
