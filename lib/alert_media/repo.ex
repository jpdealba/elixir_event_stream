defmodule AlertMedia.Repo do
  use Ecto.Repo,
    otp_app: :alert_media,
    adapter: Ecto.Adapters.Postgres
end
