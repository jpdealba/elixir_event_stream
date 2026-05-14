defmodule AlertMedia.BroadwayPipeline do
  use Broadway
  require Logger

  @max_attempts 3
  @queue_url Application.compile_env(:alert_media, :sqs_queue_url)

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {BroadwaySQS.Producer, queue_url: @queue_url, receive_interval: 100},
        concurrency: 100
      ],
      processors: [default: [concurrency: 200]],
      batchers: [
        deliveries: [batch_size: 500, batch_timeout: 200, concurrency: 5]
      ]
    )
  end

  @impl Broadway
  def handle_message(_, message, _) do
    data = Jason.decode!(message.data, keys: :atoms)
    message = Broadway.Message.update_data(message, fn _ -> data end)
    Broadway.Message.put_batcher(message, :deliveries)
  end

  @impl Broadway
  def handle_batch(:deliveries, messages, _, _) do
    # Fan-out: cada mensaje SQS es un recipient → expandir a sus canales
    # Mensajes iniciales no tienen :channel → procesar los 3 canales
    # Mensajes de retry sí tienen :channel → procesar solo ese canal
    deliveries =
      Enum.flat_map(messages, fn msg ->
        channels =
          case Map.get(msg.data, :channel) do
            nil -> ~w[sms email push]
            ch -> [ch]
          end

        Enum.map(channels, fn ch ->
          {msg.data.alert_id, msg.data.recipient_id, ch, msg.data.attempt}
        end)
      end)

    {send_us, {ok, failed}} =
      :timer.tc(fn ->
        deliveries
        |> Enum.map(fn {aid, rid, ch, attempt} -> {{aid, rid, ch, attempt}, fake_send()} end)
        |> Enum.split_with(fn {_, r} -> r == :ok end)
      end)

    {failed_final, failed_retry} =
      Enum.split_with(failed, fn {{_, _, _, attempt}, _} -> attempt >= @max_attempts end)

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    {insert_us, _} =
      :timer.tc(fn ->
        bulk_insert(ok, "delivered", now)
        bulk_insert(failed_final, "failed", now)
      end)

    {retry_us, _} =
      :timer.tc(fn ->
        unless failed_retry == [] do
          failed_retry
          |> Enum.map(fn {{aid, rid, ch, attempt}, _} ->
            [
              id: "#{rid}-#{ch}",
              message_body:
                Jason.encode!(%{
                  alert_id: aid,
                  recipient_id: rid,
                  channel: ch,
                  attempt: attempt + 1
                })
            ]
          end)
          |> Enum.chunk_every(10)
          |> Task.async_stream(
            &(ExAws.SQS.send_message_batch(@queue_url, &1) |> ExAws.request!()),
            max_concurrency: 50,
            ordered: false
          )
          |> Stream.run()
        end
      end)

    alert_id = hd(messages).data.alert_id
    AlertMedia.Progress.add_timing(alert_id, send_us, insert_us, retry_us)

    messages
  end

  defp bulk_insert([], _status, _now), do: :ok

  defp bulk_insert(deliveries, status, now) do
    logs =
      Enum.map(deliveries, fn {{alert_id, recipient_id, channel, _}, _} ->
        %{
          alert_id: alert_id,
          recipient_id: recipient_id,
          channel: channel,
          status: status,
          inserted_at: now
        }
      end)

    AlertMedia.Repo.insert_all(AlertMedia.DeliveryLog, logs,
      on_conflict: :nothing,
      conflict_target: [:alert_id, :recipient_id, :channel]
    )

    logs
    |> Enum.group_by(& &1.alert_id)
    |> Enum.each(fn {alert_id, group} -> AlertMedia.Progress.track(alert_id, length(group)) end)
  end

  defp fake_send do
    if :rand.uniform(100) > 2, do: :ok, else: :failed
  end
end
