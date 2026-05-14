defmodule AlertMedia.Application do
  use Application

  @impl true
  def start(_type, _args) do
    ExAws.SQS.create_queue("alerts") |> ExAws.request()

    children = [
      AlertMedia.Repo,
      AlertMedia.BroadwayPipeline
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: AlertMedia.Supervisor)
  end
end
