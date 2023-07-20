package main

import (
	"github.com/GoogleCloudPlatform/functions-framework-go/funcframework"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"log"
	"os"
	RedpandaLocatorCF "redpanda.com/locator"
)

func main() {
	// Use PORT environment variable, or default to 9090.
	port := "9090"
	if envPort := os.Getenv("PORT"); envPort != "" {
		port = envPort
	}
	functions.HTTP("hello", RedpandaLocatorCF.Hello)
	if err := funcframework.Start(port); err != nil {
		log.Fatalf("funcframework.Start: %v\n", err)
	}

}
