defmodule AlertMedia.Repo.Migrations.CreateAlertProgress do
  use Ecto.Migration

  def change do
    create table(:alert_progress, primary_key: false) do
      add :alert_id,       :string,  primary_key: true
      add :total,          :integer, null: false
      add :done,           :integer, null: false, default: 0
      add :start_ms,       :bigint,  null: false
      add :enqueue_ms,     :bigint,  null: false, default: 0
      add :first_batch_ms, :bigint,  null: false, default: 0
      add :fake_send_us,   :bigint,  null: false, default: 0
      add :insert_us,      :bigint,  null: false, default: 0
      add :retry_us,       :bigint,  null: false, default: 0
    end
  end
end
