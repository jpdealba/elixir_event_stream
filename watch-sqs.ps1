while ($true) {
    Clear-Host
    aws --endpoint-url http://localhost:9324 sqs get-queue-attributes --queue-url "http://localhost:9324/000000000000/alerts" --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible
    Start-Sleep 1
}
