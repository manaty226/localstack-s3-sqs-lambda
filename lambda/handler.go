package main

import (
	"context"
	"fmt"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

func main() {
	lambda.Start(Handler)
}

func Handler(ctx context.Context, event events.SQSEvent) error {
	for _, record := range event.Records {
		fmt.Printf("The message %s for event source %s = %s \n", record.MessageId, record.EventSource, record.Body)
	}
	return nil
}
