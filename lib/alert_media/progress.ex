defmodule AlertMedia.Progress do
  use Ecto.Schema
  import Ecto.Query
  require Logger

  @primary_key {:alert_id, :string, []}
  schema "alert_progress" do
    field :total,          :integer
    field :done,           :integer
    field :start_ms,       :integer
    field :enqueue_ms,     :integer
    field :first_batch_ms, :integer
    field :fake_send_us,   :integer
    field :insert_us,      :integer
    field :retry_us,       :integer
  end

  def init(alert_id, total) do
    AlertMedia.Repo.insert_all(__MODULE__, [
      %{
        alert_id: alert_id,
        total: total,
        done: 0,
        start_ms: System.system_time(:millisecond),
        enqueue_ms: 0,
        first_batch_ms: 0,
        fake_send_us: 0,
        insert_us: 0,
        retry_us: 0
      }
    ])
  end

  def set_enqueue_ms(alert_id, ms) do
    from(p in __MODULE__, where: p.alert_id == ^alert_id)
    |> AlertMedia.Repo.update_all(set: [enqueue_ms: ms])
  end

  # Acumula tiempos de procesamiento de un batch y registra cuándo llegó el primer batch.
  # Cada nodo llama esto con sus propios micros — se suman atómicamente en Postgres.
  def add_timing(alert_id, send_us, insert_us, retry_us) do
    from(p in __MODULE__, where: p.alert_id == ^alert_id)
    |> AlertMedia.Repo.update_all(inc: [fake_send_us: send_us, insert_us: insert_us, retry_us: retry_us])

    # Solo el primer nodo que llegue aquí setea first_batch_ms (WHERE first_batch_ms = 0 es el guard)
    row = AlertMedia.Repo.get(__MODULE__, alert_id)

    if row && row.first_batch_ms == 0 do
      elapsed = System.system_time(:millisecond) - row.start_ms

      from(p in __MODULE__, where: p.alert_id == ^alert_id and p.first_batch_ms == 0)
      |> AlertMedia.Repo.update_all(set: [first_batch_ms: elapsed])
    end
  end

  # Incrementa el contador de deliveries completados. Si este nodo cruzó el total, loguea el summary.
  def track(alert_id, count) do
    {updated, _} =
      from(p in __MODULE__, where: p.alert_id == ^alert_id)
      |> AlertMedia.Repo.update_all(inc: [done: count])

    if updated > 0 do
      row = AlertMedia.Repo.get(__MODULE__, alert_id)

      if row do
        if div(row.done, 10_000) > div(row.done - count, 10_000) do
          elapsed = System.system_time(:millisecond) - row.start_ms
          Logger.info("[#{alert_id}] #{row.done}/#{row.total} (#{elapsed}ms)")
        end

        if row.done >= row.total do
          # delete_all retorna {1, _} al primer nodo que llegue, {0, _} a los demás — evita double-log
          case AlertMedia.Repo.delete_all(from p in __MODULE__, where: p.alert_id == ^alert_id) do
            {1, _} ->
              elapsed = System.system_time(:millisecond) - row.start_ms
              log_summary(alert_id, elapsed, row)
            _ ->
              :ok
          end
        end
      end
    end
  end

  defp log_summary(alert_id, elapsed, row) do
    Logger.info("""
    [#{alert_id}] ───────── Summary ─────────
      Total:           #{elapsed}ms
      SQS enqueue:     #{row.enqueue_ms}ms
      SQS poll delay:  #{row.first_batch_ms}ms
      fake_send:       #{div(row.fake_send_us, 1_000)}ms
      db_insert:       #{div(row.insert_us, 1_000)}ms
      retries to SQS:  #{div(row.retry_us, 1_000)}ms
    ──────────────────────────────────────────
    """)
  end
end
