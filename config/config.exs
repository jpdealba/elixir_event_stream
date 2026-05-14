import Config

config :alert_media, ecto_repos: [AlertMedia.Repo]

config :alert_media, AlertMedia.Repo,
  database: "alert_media_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5432,
  pool_size: 30

config :alert_media, :sqs_queue_url, "http://localhost:9324/000000000000/alerts"

config :ex_aws,
  access_key_id: "test",
  secret_access_key: "test",
  region: "us-east-1"

import_config "#{config_env()}.exs"
