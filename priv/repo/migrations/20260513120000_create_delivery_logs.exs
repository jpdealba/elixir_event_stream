defmodule AlertMedia.Repo.Migrations.CreateDeliveryLogs do
  use Ecto.Migration

  def change do
    create table(:delivery_logs) do
      add :alert_id,     :string, null: false
      add :recipient_id, :string, null: false
      add :channel,      :string, null: false
      add :status,       :string, null: false

      timestamps(updated_at: false)
    end

    create unique_index(:delivery_logs, [:alert_id, :recipient_id, :channel])
  end
end
