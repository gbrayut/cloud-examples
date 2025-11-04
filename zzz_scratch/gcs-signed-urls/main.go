package main

import (
	"context"
	"log"
	"os"
	"time"

	credentials "cloud.google.com/go/iam/credentials/apiv1"
	"cloud.google.com/go/storage"
	"golang.org/x/oauth2/google"
	"google.golang.org/api/impersonate"
	"google.golang.org/api/option"
	credentialspb "google.golang.org/genproto/googleapis/iam/credentials/v1"
)

func main() {
	// Initialize Environment
	bucket := os.Getenv("BUCKET")
	if bucket == "" {
		log.Fatalf("Must specify BUCKET environment variable")
	}
	gcpContext := context.Background()
	account := os.Getenv("ACCOUNT")
	if account == "" {
		log.Fatalf("Must specify ACCOUNT environment variable")
	}
	//filename := "test.csv"
	filename := "new/data-small.csv"
	creds, err := google.FindDefaultCredentials(gcpContext)
	if err != nil {
		// Try using https://developers.google.com/accounts/docs/application-default-credentials
		if os.Getenv("GOOGLE_APPLICATION_CREDENTIALS") == "" {
			// Detect if ADC token exists
			if _, err := os.Stat(os.Getenv("HOME") + "/.config/gcloud/application_default_credentials.json"); os.IsNotExist(err) {
				log.Fatalf("Missing GOOGLE_APPLICATION_CREDENTIALS environment variables and no Application Default Credentials\nPlease set GOOGLE_APPLICATION_CREDENTIALS or run: gcloud auth application-default login")
			}
			// Try ADC token
			os.Setenv("GOOGLE_APPLICATION_CREDENTIALS", os.Getenv("HOME")+"/.config/gcloud/application_default_credentials.json")
			creds, err = google.FindDefaultCredentials(gcpContext)
			if err != nil {
				log.Fatalf("google.FindDefaultCredentials with ADC failed: %s", err)
			}
		} else {
			log.Fatalf("google.FindDefaultCredentials failed: %s", err)
		}
	}
	ts := creds.TokenSource
	log.Printf("BUCKET=%s ACCOUNT=%s\n", bucket, account)
	if false {
		// When running locally impersonate the service account. See https://pkg.go.dev/google.golang.org/api/impersonate#example-CredentialsTokenSource-ServiceAccount
		ts, err = impersonate.CredentialsTokenSource(gcpContext, impersonate.CredentialsConfig{
			TargetPrincipal: account,
			Scopes:          []string{"https://www.googleapis.com/auth/cloud-platform"},
			Delegates:       []string{account},
		})
		if err != nil {
			log.Fatal(err)
		}
		log.Printf("BUCKET=%s and impersonating ACCOUNT=%s\n", bucket, account)
	}

	// Initialize storage client
	sc, err := storage.NewClient(gcpContext, option.WithTokenSource(ts))
	if err != nil {
		log.Fatal(err)
	}
	defer sc.Close()

	// Initialize Signed URL options
	iamClient, err := credentials.NewIamCredentialsClient(gcpContext)
	if err != nil {
		panic(err)
	}
	// see https://pkg.go.dev/cloud.google.com/go/storage#SignedURLOptions
	opts := &storage.SignedURLOptions{
		Method:         "PUT",
		GoogleAccessID: account,
		Expires:        time.Now().Add(12 * time.Hour),
		ContentType:    "text/csv",
		SignBytes: func(b []byte) ([]byte, error) {
			req := &credentialspb.SignBlobRequest{
				Payload: b,
				Name:    account,
			}
			resp, err := iamClient.SignBlob(gcpContext, req)
			if err != nil {
				panic(err)
			}
			return resp.SignedBlob, err
		},
	}
	log.Printf("storage.SignedURLOptions: %+v\n", opts)

	url, err := storage.SignedURL(bucket, filename, opts)
	if err != nil {
		log.Printf("SignedURL error: %s", err)
	}

	test := "curl -v $URL -X 'PUT' -H 'content-type: text/csv' -H 'origin: http://localhost:8080' --data-raw 'testing,1,2,3' --compressed"
	log.Printf("Test using:\nURL=\"%s\"\n%s", url, test)
}
