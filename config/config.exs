import Config

config :alert_media, ecto_repos: [AlertMedia.Repo]

config :alert_media, AlertMedia.Repo,
  database: "alert_media_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5432,
  # Fórmula por nodo: batcher_concurrency + headroom API (p. ej. 5 + 10 = 15).
  # Cada batcher usa 1 conexión Postgres (insert_all delivery_logs).
  # Nodos soportados por instancia RDS = max_connections / pool_size:
  #   db.t3.small  (~34)  → 2 nodos | db.t3.medium (~170) → 11 | db.t3.large (~340) → 22
  pool_size: 15

config :alert_media, :sqs_queue_url, "http://localhost:4566/000000000000/alerts"

config :ex_aws,
  access_key_id: "test",
  secret_access_key: "test",
  region: "us-east-1"

import_config "#{config_env()}.exs"
