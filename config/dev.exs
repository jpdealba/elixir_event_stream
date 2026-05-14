import Config

config :ex_aws, :sqs,
  host: "localhost",
  port: 4566,
  scheme: "http://"

config :alert_media, AlertMedia.Repo, log: false
