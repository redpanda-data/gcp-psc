package RedpandaLocatorCF

import (
	b64 "encoding/base64"
	"encoding/json"
	"fmt"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"log"
	"net/http"
	"os"
	"redpanda.com/locator/brokers"
	"redpanda.com/locator/cloud_dns"
	"redpanda.com/locator/logger"
	"regexp"
	"strconv"
)

func init() {
	functions.HTTP("update", UpdateDNS)
}

type UpdateRequest struct {
	Project     string
	Zone        string
	Prefix      string
	Credentials string

	User     string
	Password string
	Seed     string
}

func extractID(host string) (int, error) {
	pattern := "[a-z]+-([\\d]+)\\..+"
	r, err := regexp.Compile(pattern)
	if err != nil {
		return -1, err
	}
	matches := r.FindStringSubmatch(host)
	id, err := strconv.Atoi(matches[1])
	if err != nil {
		return -1, err
	}
	return id, nil
}

func transformEndpoints(m map[string]string) (map[int]string, error) {
	r := make(map[int]string)
	for hostname, ip := range m {
		id, err := extractID(hostname)
		if err != nil {
			return nil, err
		}
		r[id] = ip
	}
	return r, nil
}

func extractCredentials(s string) ([]byte, error) {
	decoded, err := b64.StdEncoding.DecodeString(s)
	if err != nil {
		return nil, err
	}
	return decoded, nil
}

func values[K comparable, V any](m map[K]V) []V {
	result := make([]V, 0, len(m))
	for _, value := range m {
		result = append(result, value)
	}
	return result
}

// Make betterer: See https://www.alexedwards.net/blog/how-to-properly-parse-a-json-request-body
func UpdateDNS(w http.ResponseWriter, r *http.Request) {

	logger.Logger = log.Default()
	logger.Logger.SetOutput(w)

	var ur UpdateRequest

	err := json.NewDecoder(r.Body).Decode(&ur)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	ur.Project = os.Getenv("PROJECT")
	ur.Zone = os.Getenv("ZONE")

	log.Println(fmt.Sprintf("Received a request to update DNS for seed: %s", ur.Seed))

	brokerNames, err := brokers.Brokers(ur.Seed, ur.User, ur.Password)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	log.Println(fmt.Sprintf("Discovered the broker names: %s", values(brokerNames)))

	credentials, err := extractCredentials(ur.Credentials)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	log.Println(fmt.Sprintf("Connecting to DNS zone %s in project %s", ur.Zone, ur.Project))

	handler, err := cloud_dns.New(ur.Project, ur.Zone, credentials)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	endpoints, err := handler.LookupAllARecords(ur.Prefix)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	targetIPAddresses, err := transformEndpoints(endpoints)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	log.Println(fmt.Sprintf("Discovered the required IP addresses: %s", values(targetIPAddresses)))

	// Join names in brokerNames to IPs in targetIPAddresses based on common node ID key

	correctAddresses := make(map[string]string)

	for id, hostname := range brokerNames {
		correctAddresses[hostname] = targetIPAddresses[id]
	}

	for hostname, ip := range correctAddresses {
		err = handler.CreateARecord(hostname, ip)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
	}

}
