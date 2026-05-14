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
        concurrency: 25
      ],
      processors: [
        default: [concurrency: 50]
      ],
      batchers: [
        deliveries: [
          batch_size: 500,
          batch_timeout: 100,
          concurrency: 5
        ]
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

    {ok, failed} =
      deliveries
      |> Enum.map(fn delivery -> {delivery, fake_send()} end)
      |> Enum.split_with(fn {_, r} -> r == :ok end)

    {failed_final, failed_retry} =
      Enum.split_with(failed, fn {{_, _, _, attempt}, _} -> attempt >= @max_attempts end)

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    bulk_insert(ok, "delivered", now)
    bulk_insert(failed_final, "failed", now)

    Logger.info("[pipeline] #{length(deliveries)} deliveries — #{length(ok)} ok, #{length(failed_final)} failed, #{length(failed_retry)} retry")

    unless failed_retry == [] do
      failed_retry
      |> Enum.map(fn {{aid, rid, ch, attempt}, _} ->
        [
          id: "#{rid}-#{ch}",
          message_body: Jason.encode!(%{alert_id: aid, recipient_id: rid, channel: ch, attempt: attempt + 1})
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

    messages
  end

  defp bulk_insert([], _status, _now), do: :ok

  defp bulk_insert(deliveries, status, now) do
    logs =
      Enum.map(deliveries, fn {{alert_id, recipient_id, channel, _}, _} ->
        %{alert_id: alert_id, recipient_id: recipient_id, channel: channel, status: status, inserted_at: now}
      end)

    AlertMedia.Repo.insert_all(AlertMedia.DeliveryLog, logs,
      on_conflict: :nothing,
      conflict_target: [:alert_id, :recipient_id, :channel]
    )
  end

  defp fake_send do
    if :rand.uniform(100) > 2, do: :ok, else: :failed
  end
end
