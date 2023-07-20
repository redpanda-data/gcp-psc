package cloud_dns

import (
	"context"
	"fmt"
	"google.golang.org/api/dns/v1"
	"google.golang.org/api/googleapi"
	"google.golang.org/api/option"
	"strings"
)

type GCPDNSHandler struct {
	Service *dns.Service
	Project string
	Zone    string
}

func New(project string, zone string, credentials []byte) (GCPDNSHandler, error) {
	ctx := context.Background()

	service, err := dns.NewService(ctx, option.WithCredentialsJSON(credentials))
	if err != nil {
		return GCPDNSHandler{Service: nil}, err
	}

	return GCPDNSHandler{Project: project, Zone: zone, Service: service}, nil
}

type HandlerError struct {
	Message string
	Cause   error
}

func (m *HandlerError) Error() string {
	return m.Message
}

func (handler GCPDNSHandler) CreateARecord(host string, ip string) error {
	host = makeHostname(host)
	addition := createChange(host, ip, Addition)
	_, err := handler.Service.Changes.Create(handler.Project, handler.Zone, addition).Do()
	if err != nil {
		gerr, _ := err.(*googleapi.Error)
		if strings.Contains(gerr.Message, "already exists") {
			// let's check that the ip matches - if it doesn't, return an error
			currentIP, err := handler.LookupARecord(host)
			if err != nil {
				return err
			}
			if currentIP != ip {
				return &HandlerError{Message: "Unable to create - record exists with a different IP"}
			}
		} else {
			return &HandlerError{Message: fmt.Sprintf("Unable to create a record: %s", err), Cause: err}
		}
	}
	return nil
}

func makeHostname(host string) string {
	if host[len(host)-1] != '.' {
		return host + "."
	} else {
		return host
	}
}

func (handler GCPDNSHandler) LookupAllARecords(prefix string) (map[string]string, error) {
	response, err := handler.Service.ResourceRecordSets.List(handler.Project, handler.Zone).Do()
	if err != nil {
		return nil, err
	}

	endpoints := make(map[string]string)

	for i := range response.Rrsets {
		var rrset = response.Rrsets[i]
		if strings.HasPrefix(rrset.Name, prefix) {
			endpoints[rrset.Name] = rrset.Rrdatas[0]
		}
	}

	return endpoints, nil
}

func (handler GCPDNSHandler) LookupARecord(host string) (string, error) {
	host = makeHostname(host)
	rr, err := handler.Service.ResourceRecordSets.Get(handler.Project, handler.Zone, host, "A").Do()
	if err != nil {
		return "", &HandlerError{Message: "Unable to lookup a record", Cause: err}
	}
	return rr.Rrdatas[0], nil
}

func (handler GCPDNSHandler) DeleteARecord(host string, ip string) error {
	host = makeHostname(host)
	deletion := createChange(host, ip, Deletion)

	_, err := handler.Service.Changes.Create(handler.Project, handler.Zone, deletion).Do()
	if err != nil {
		return &HandlerError{Message: "Unable to delete a record", Cause: err}
	}
	return nil
}

type ChangeType = int

const (
	Addition ChangeType = iota
	Deletion ChangeType = iota
)

func createChange(host string, ip string, changeType ChangeType) *dns.Change {
	var address []string
	address = append(address, ip)

	record := &dns.ResourceRecordSet{
		Kind:             "dns#resourceRecordSet",
		Name:             host,
		RoutingPolicy:    nil,
		Rrdatas:          address,
		SignatureRrdatas: nil,
		Ttl:              300,
		Type:             "A",
		ServerResponse:   googleapi.ServerResponse{},
		ForceSendFields:  nil,
		NullFields:       nil,
	}

	var records []*dns.ResourceRecordSet
	records = append(records, record)

	if changeType == Addition {
		return &dns.Change{
			Additions:       records,
			Deletions:       nil,
			Id:              "",
			IsServing:       false,
			Kind:            "",
			StartTime:       "",
			Status:          "",
			ServerResponse:  googleapi.ServerResponse{},
			ForceSendFields: nil,
			NullFields:      nil,
		}
	} else {
		return &dns.Change{
			Additions:       nil,
			Deletions:       records,
			Id:              "",
			IsServing:       false,
			Kind:            "",
			StartTime:       "",
			Status:          "",
			ServerResponse:  googleapi.ServerResponse{},
			ForceSendFields: nil,
			NullFields:      nil,
		}
	}
}
