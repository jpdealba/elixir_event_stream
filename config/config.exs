import Config

config :alert_media, ecto_repos: [AlertMedia.Repo]

config :alert_media, AlertMedia.Repo,
  database: "alert_media_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5432,
  # Fórmula por nodo: batcher_concurrency + headroom API (10 + 10 = 20).
  # Cada batcher usa 1 conexión Postgres (insert_all delivery_logs).
  # Nodos soportados por instancia RDS = max_connections / pool_size:
  #   db.t3.small  (~34)  → 1 nodo | db.t3.medium (~170) → 8 | db.t3.large (~340) → 17
  pool_size: 20

config :alert_media, :sqs_queue_url, "http://localhost:4566/000000000000/alerts"

config :ex_aws,
  access_key_id: "test",
  secret_access_key: "test",
  region: "us-east-1"

import_config "#{config_env()}.exs"
