defmodule AlertMedia do
  require Logger

  @queue_url Application.compile_env(:alert_media, :sqs_queue_url)
  # AlertMedia.stress_test()

  def trigger_alert(alert) do
    Logger.info("[API] Alert #{alert.id} — #{length(alert.recipients)} recipients")

    messages = Enum.map(alert.recipients, fn r ->
      %{alert_id: alert.id, recipient_id: r, attempt: 0}
    end)

    # total = recipients × 3 channels (deliveries totales, no mensajes SQS)
    AlertMedia.Progress.init(alert.id, length(messages) * 3)

    {enqueue_us, _} =
      :timer.tc(fn ->
        messages
        |> Enum.with_index()
        |> Enum.chunk_every(10)
        |> Task.async_stream(
          fn batch ->
            sqs_batch = Enum.map(batch, fn {msg, i} ->
              [id: "msg-#{i}", message_body: Jason.encode!(msg)]
            end)
            ExAws.SQS.send_message_batch(@queue_url, sqs_batch) |> ExAws.request!()
          end,
          max_concurrency: 200,
          ordered: false
        )
        |> Stream.run()
      end)

    AlertMedia.Progress.set_enqueue_ms(alert.id, div(enqueue_us, 1_000))
    Logger.info("[API] 200 OK — #{length(messages)} messages queued")
    {:ok, alert.id}
  end

  def stress_test(recipient_count \\ 1_000) do
    id = "stress-#{System.unique_integer([:positive])}"
    recipients = Enum.map(1..recipient_count, fn i -> "user_#{i}" end)

    Logger.info("[Stress] #{recipient_count} recipients — #{recipient_count * 3} deliveries")
    {micros, result} = :timer.tc(fn -> trigger_alert(%{id: id, recipients: recipients}) end)
    Logger.info("[Stress] Queued in #{div(micros, 1000)}ms")
    result
  end
end
