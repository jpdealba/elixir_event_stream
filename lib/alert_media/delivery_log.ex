defmodule AlertMedia.DeliveryLog do
  use Ecto.Schema
  import Ecto.Changeset

  schema "delivery_logs" do
    field :alert_id,     :string
    field :recipient_id, :string
    field :channel,      :string
    field :status,       :string

    timestamps(updated_at: false)
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, [:alert_id, :recipient_id, :channel, :status])
    |> validate_required([:alert_id, :recipient_id, :channel, :status])
    |> unique_constraint([:alert_id, :recipient_id, :channel])
  end
end
