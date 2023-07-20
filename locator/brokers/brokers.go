package brokers

import (
	"context"
	"crypto/tls"
	"github.com/twmb/franz-go/pkg/kadm"
	"github.com/twmb/franz-go/pkg/kgo"
	"github.com/twmb/franz-go/pkg/sasl"
	"github.com/twmb/franz-go/pkg/sasl/scram"
	"github.com/twmb/tlscfg"
	"net"
	"redpanda.com/locator/logger"
	"time"
)

func Brokers(seed string, user string, password string) (map[int]string, error) {

	logger.Logger.Println("Attempting to get brokers with user " + user)

	brokers := make(map[int]string)

	var mechanism sasl.Mechanism
	scramAuth := scram.Auth{
		User: user,
		Pass: password,
	}
	mechanism = scramAuth.AsSha256Mechanism()

	tlsCfg, err := tlscfg.New()

	if err != nil {
		logger.Logger.Println("failed to create tls config: %w", err)
		return nil, err
	}

	tlsDialer := &tls.Dialer{
		NetDialer: &net.Dialer{Timeout: 10 * time.Second},
		Config:    tlsCfg,
	}

	var adm *kadm.Client
	{
		cl, err := kgo.NewClient(
			kgo.SeedBrokers(seed),
			kgo.SASL(sasl.Mechanism(mechanism)),
			kgo.Dialer(tlsDialer.DialContext),
		)

		if err != nil {
			logger.Logger.Println("unable to create admin client: %w", err)
			return nil, err
		}
		adm = kadm.NewClient(cl)
	}
	metadata, err := adm.BrokerMetadata(context.Background())
	if err != nil {
		logger.Logger.Println("unable to create admin client: %v", err)
		return nil, err
	}
	for i, broker := range metadata.Brokers {
		brokers[i] = broker.Host
	}
	defer adm.Close()
	return brokers, nil
}
