// From https://github.com/guillaumeblaquiere/cloudrun-hello-go
package main

import (
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

func main() {

	// Get project ID from metadata server
	project := "???"
	projectFound := false
	client := &http.Client{}
	req, _ := http.NewRequest("GET", "http://metadata.google.internal/computeMetadata/v1/project/project-id", nil)
	req.Header.Set("Metadata-Flavor", "Google")
	res, err := client.Do(req)
	if err == nil {
		defer res.Body.Close()
		responseBody, err := ioutil.ReadAll(res.Body)
		if err != nil {
			log.Fatal(err)
		}
		project = string(responseBody)
		projectFound = true
	}

	service := os.Getenv("K_SERVICE")
	if service == "" {
		service = "???"
	}

	revision := os.Getenv("K_REVISION")
	if revision == "" {
		revision = "???"
	}

	path := "/secrets/"
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprint(w, "This created the revision "+revision+" of the Cloud Run service "+service)
		if projectFound {
			fmt.Fprint(w, " in the GCP project "+project)
		}

		// Option 1: env vars
		fmt.Fprint(w, "\n\nEnvironment:\n")
		fmt.Fprint(w, strings.Join(os.Environ(), "\n"))

		// Option 2: Mounted Volume
		fmt.Fprint(w, "\n\nSecrets:\n")
		files, err := ioutil.ReadDir(path)
		if err != nil {
			fmt.Fprintf(w, "Error: %s\n", err)
		}
		for _, file := range files {
			filename := filepath.Join(path, file.Name())
			val, err := ioutil.ReadFile(filename)
			if err != nil {
				fmt.Fprintf(w, "Error reading %s: %s\n", filename, err)
			} else {
				fmt.Fprintf(w, "%s=%s\n", file.Name(), val)
			}
		}

		// Option 3: Direct API access
		// TODO: Add API example based on https://github.com/GoogleCloudPlatform/golang-samples/blob/6c46053696035e0b5d210806f005c43da9bcb6ee/secretmanager/quickstart/quickstart.go#L81
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Print("Hello from Cloud Run! The container started successfully and is listening for HTTP requests on $PORT.")
	log.Fatal(http.ListenAndServe(fmt.Sprintf(":%s", port), nil))

}
